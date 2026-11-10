//! The Parquet half of the bridge (plan 0018): datakit's `read_parquet`,
//! `read_parquet_info` and `save_parquet` reach these through the C
//! callables in init.c.
//!
//! Reads decode straight into R vectors allocated before the read: the
//! core's workers fill integer and double columns through pointers taken
//! here, and call no R function. Text arrives one column chunk at a time
//! on this thread and becomes a packed column (ADR 0010), with a
//! dictionary merged across row groups (ADR 0011). The rules of what each
//! Parquet type becomes are plan 0018's "Exactness" table, R column.

use std::collections::HashMap;
use std::ffi::{c_char, c_int, CStr};

use dta::{missing, Bytes, Characteristic, FileSource, Source, ValueLabel, ValueLabelSet};
use dta_parquet::format::{LogicalType, TimeUnit};
use dta_parquet::{
    tagged_nan, ColumnInfo, ColumnType, Compression, LevelsFrom, Logical, Nested, Numbers, Output, Profile,
    ReadOptions, Reader, Role, Storage, Table, TextChunk, Values, WriteColumn, WriteOptions,
};

use super::{
    alloc_attr, alloc_elt, c_str, guard, named_list, packed_elt, r_code, set_strs, status, string_attr, strings_elt,
    DictLimits, Fail, Res, Sexp, Strings, INTEGER, INTSXP, LGLSXP, LOGICAL, NA_BITS, NA_INTEGER, RAW, REAL, REALSXP,
    Rf_xlength, R_CHAR, R_NaString, STRING_ELT, STRSXP, TYPEOF, VECSXP, VECTOR_ELT,
};

const RAWSXP: c_int = 24;

extern "C" {
    fn dtaparser_set_strings_na(
        x: Sexp,
        first: isize,
        bytes: *const u8,
        ends: *const usize,
        missing: *const u8,
        n: isize,
    ) -> c_int;
    fn dtaparser_set_raws(
        x: Sexp,
        first: isize,
        bytes: *const u8,
        ends: *const usize,
        missing: *const u8,
        n: isize,
    ) -> c_int;
    fn STRING_PTR_RO(x: Sexp) -> *const Sexp;
}

fn na_real() -> f64 {
    f64::from_bits(NA_BITS)
}

/// Fill `x[first..]` with strings, NA where `missing` is nonzero.
fn set_strings_na(x: Sexp, first: usize, bytes: &[u8], ends: &[usize], missing: &[u8]) -> Res<()> {
    status(unsafe {
        dtaparser_set_strings_na(x, first as isize, bytes.as_ptr(), ends.as_ptr(), missing.as_ptr(), ends.len() as isize)
    })
}

// ---------------------------------------------------------------- opening

/// Where a file comes from: a path, or a raw vector holding a whole file.
enum Input<'a> {
    Path(String),
    Raw(&'a [u8]),
}

/// # Safety
/// `raw` is NULL or points at `raw_len` bytes alive for the call.
unsafe fn input<'a>(path: *const c_char, raw: *const u8, raw_len: usize) -> Input<'a> {
    if raw.is_null() {
        Input::Path(c_str(path).unwrap_or_default())
    } else if raw_len == 0 {
        Input::Raw(&[])
    } else {
        Input::Raw(std::slice::from_raw_parts(raw, raw_len))
    }
}

/// Run `f` on the file opened as a Parquet reader.
fn with_reader<T>(
    input: &Input,
    options: ReadOptions,
    f: &mut dyn FnMut(&mut dyn Access) -> Res<T>,
) -> Res<T> {
    match input {
        Input::Path(p) => {
            let source = ReadAhead::open(p).map_err(|e| Fail::Message(format!("{p}: {e}")))?;
            let mut r = Reader::open(source, options).map_err(|e| Fail::Message(format!("{p}: {e}")))?;
            f(&mut r).map_err(|e| prefix(e, p))
        }
        Input::Raw(bytes) => {
            let mut r = Reader::open(Bytes(*bytes), options)?;
            f(&mut r)
        }
    }
}

/// A file read in blocks of 1 MiB, one per thread: a wide file has a
/// column chunk of a few kilobytes per column, and a system call for
/// each, from several threads at once, cost more than decoding them.
/// Reads of a quarter block or more go to the file directly.
struct ReadAhead {
    file: FileSource,
    /// Tells this file's blocks from another's in a thread's cache.
    id: u64,
}

const BLOCK_BYTES: usize = 1 << 20;

struct Block {
    id: u64,
    start: u64,
    bytes: Vec<u8>,
}

thread_local! {
    static BLOCK: std::cell::RefCell<Block> = const { std::cell::RefCell::new(Block { id: 0, start: 0, bytes: Vec::new() }) };
}

impl ReadAhead {
    fn open(path: &str) -> dta::Result<Self> {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        Ok(ReadAhead { file: FileSource::open(path)?, id: NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed) })
    }

    /// Read through this thread's block of the file `id` (of `len`
    /// bytes), filling it with `fill`. It takes no borrow of the reader,
    /// so `fill` may borrow the file mutably.
    fn read_with(
        id: u64,
        len: u64,
        offset: u64,
        buf: &mut [u8],
        fill: impl FnOnce(u64, &mut [u8]) -> dta::Result<()>,
    ) -> dta::Result<()> {
        if buf.len() >= BLOCK_BYTES / 4 || offset.checked_add(buf.len() as u64).is_none_or(|e| e > len) {
            return fill(offset, buf);
        }
        BLOCK.with(|b| {
            let mut b = b.borrow_mut();
            let end = offset + buf.len() as u64;
            if !(b.id == id && b.start <= offset && end <= b.start + b.bytes.len() as u64) {
                let n = (BLOCK_BYTES as u64).min(len - offset) as usize;
                b.bytes.resize(n, 0);
                fill(offset, &mut b.bytes)?;
                b.id = id;
                b.start = offset;
            }
            let at = (offset - b.start) as usize;
            buf.copy_from_slice(&b.bytes[at..at + buf.len()]);
            Ok(())
        })
    }
}

impl Drop for ReadAhead {
    fn drop(&mut self) {
        // Workers' blocks go with their threads; free this thread's.
        let _ = BLOCK.try_with(|b| {
            if let Ok(mut b) = b.try_borrow_mut() {
                if b.id == self.id {
                    *b = Block { id: 0, start: 0, bytes: Vec::new() };
                }
            }
        });
    }
}

impl Source for ReadAhead {
    fn len(&self) -> u64 {
        self.file.len()
    }

    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> dta::Result<()> {
        let (id, len) = (self.id, self.file.len());
        let file = &mut self.file;
        Self::read_with(id, len, offset, buf, |o, b| file.read_at(o, b))
    }

    fn shared(&self) -> Option<&dyn dta::SharedSource> {
        self.file.shared().map(|_| self as &dyn dta::SharedSource)
    }
}

impl dta::SharedSource for ReadAhead {
    fn read_at_shared(&self, offset: u64, buf: &mut [u8]) -> dta::Result<()> {
        let shared = self.file.shared().ok_or_else(|| dta::Error::new("internal: the file has no shared reads"))?;
        Self::read_with(self.id, self.file.len(), offset, buf, |o, b| shared.read_at_shared(o, b))
    }
}

fn prefix(e: Fail, path: &str) -> Fail {
    match e {
        Fail::Message(m) => Fail::Message(format!("{path}: {m}")),
        other => other,
    }
}

/// What the bridge needs of a reader, whatever its source.
trait Access {
    fn reader_columns(&self) -> &[ColumnInfo];
    fn profile(&self) -> Option<&Profile>;
    fn warnings(&self) -> &[String];
    fn rows(&self) -> u64;
    fn data_columns(&self) -> dta::Result<Vec<usize>>;
    fn window(&self, skip: u64, n: u64) -> std::ops::Range<u64>;
    fn metadata(&self) -> &dta_parquet::format::FileMetaData;
    fn row_groups(&self) -> Vec<dta_parquet::RowGroupInfo>;
    fn codecs(&self) -> Vec<dta_parquet::format::Codec>;
    fn created_by(&self) -> Option<&str>;
    fn categorical_labels(&self, column: usize) -> Option<(ValueLabelSet, Option<String>)>;
    fn read(
        &mut self,
        columns: &[usize],
        skip: u64,
        n: u64,
        outputs: &mut [Output<'_>],
        text: &mut dyn FnMut(usize, &TextChunk) -> dta::Result<()>,
    ) -> dta::Result<dta_parquet::ReadReport>;
}

impl<S: Source> Access for Reader<S> {
    fn reader_columns(&self) -> &[ColumnInfo] {
        self.columns()
    }
    fn profile(&self) -> Option<&Profile> {
        Reader::profile(self)
    }
    fn warnings(&self) -> &[String] {
        Reader::warnings(self)
    }
    fn rows(&self) -> u64 {
        Reader::rows(self)
    }
    fn data_columns(&self) -> dta::Result<Vec<usize>> {
        Reader::data_columns(self)
    }
    fn window(&self, skip: u64, n: u64) -> std::ops::Range<u64> {
        Reader::window(self, skip, n)
    }
    fn metadata(&self) -> &dta_parquet::format::FileMetaData {
        Reader::metadata(self)
    }
    fn row_groups(&self) -> Vec<dta_parquet::RowGroupInfo> {
        Reader::row_groups(self)
    }
    fn codecs(&self) -> Vec<dta_parquet::format::Codec> {
        Reader::codecs(self)
    }
    fn created_by(&self) -> Option<&str> {
        Reader::created_by(self)
    }
    fn categorical_labels(&self, column: usize) -> Option<(ValueLabelSet, Option<String>)> {
        Reader::categorical_labels(self, column)
    }
    fn read(
        &mut self,
        columns: &[usize],
        skip: u64,
        n: u64,
        outputs: &mut [Output<'_>],
        text: &mut dyn FnMut(usize, &TextChunk) -> dta::Result<()>,
    ) -> dta::Result<dta_parquet::ReadReport> {
        Reader::read(self, columns, skip, n, outputs, text)
    }
}

// ---------------------------------------------------------------- types

/// How `read_parquet` returns INT64 and unsigned 32- and 64-bit columns.
#[derive(Clone, Copy, PartialEq)]
enum Int64Mode {
    /// Doubles; a value a double does not hold exactly is an error.
    Double,
    /// bit64's `integer64`: the bits of each value in a double vector.
    Integer64,
    /// Character, every digit kept.
    Character,
}

/// How `read_parquet` returns DECIMAL columns.
#[derive(Clone, Copy, PartialEq)]
enum DecimalMode {
    /// The nearest double; a value with more than 15 significant digits
    /// is an error.
    Double,
    /// Character, every digit kept.
    Character,
}

/// The arguments of `read_parquet` that choose a column's R type.
#[derive(Clone, Copy)]
struct Modes {
    int64: Int64Mode,
    decimal: DecimalMode,
}

impl Modes {
    /// `read_parquet`'s defaults.
    const DEFAULT: Modes = Modes { int64: Int64Mode::Double, decimal: DecimalMode::Double };
}

/// What a selected column becomes in R.
#[derive(Clone, PartialEq)]
enum Kind {
    /// INT32 (any width, signed, or unsigned 8 or 16 bits) as an integer
    /// vector.
    Integer,
    Logical,
    /// FLOAT or DOUBLE; `integer` when the profile says it was a byte,
    /// int or long column written wider for `.a` to `.z`, so that it is
    /// an integer vector again where the rows read hold none.
    Double { integer: bool },
    /// Days since 1970, class `Date`: INT32 DATE, or a DOUBLE with
    /// `logical` date.
    Date,
    /// Seconds since 1970, class `POSIXct`: a TIMESTAMP in milliseconds
    /// or microseconds (read as counts, then divided), or a DOUBLE with
    /// `logical` timestamp (`per_second` 1).
    Seconds { per_second: f64, tz: Option<String> },
    /// A TIMESTAMP in nanoseconds (or INT96), read as 64-bit integers
    /// into the double vector's memory and converted after the read.
    Nanos { tz: Option<String> },
    /// A TIME: a count of units since midnight, read as doubles and
    /// divided into seconds, class `difftime`.
    Time { per_second: f64 },
    /// INT64, or an unsigned 32- or 64-bit integer.
    Int64(Int64Mode),
    /// A categorical: levels from the profile, or (`rows`) a dictionary of
    /// strings in `ARROW:schema`, whose levels are the distinct values of
    /// the rows read, filled in after the read.
    Factor { levels: Vec<String>, ordered: bool, rows: bool },
    /// A categorical holding `.a` to `.z` (plan 0022): DOUBLE level
    /// numbers 1 to `levels`, read as a labelled double, since a factor
    /// cannot hold the letters. A value that is not a level number is
    /// NA, with a warning.
    LetterLevels { levels: usize },
    Text,
    Binary,
}

/// The time zone a timestamp column reads with: the profile's (`""` for
/// an instant without one, which has no `tzone`), else the one
/// `ARROW:schema` gives, else UTC.
fn zone_of(col: &ColumnInfo, profile: Option<&dta_parquet::ColumnProfile>) -> Option<String> {
    match profile.and_then(|p| p.tz.as_deref()) {
        Some("") => None,
        Some(z) => Some(z.to_string()),
        None => Some(col.zone.as_deref().filter(|z| !z.is_empty()).unwrap_or("UTC").to_string()),
    }
}

fn per_second(unit: TimeUnit) -> f64 {
    match unit {
        TimeUnit::Millis => 1e3,
        TimeUnit::Micros => 1e6,
        TimeUnit::Nanos => 1e9,
    }
}

fn kind_of(col: &ColumnInfo, profile: Option<&dta_parquet::ColumnProfile>, modes: Modes) -> Res<Kind> {
    Ok(match &col.kind {
        ColumnType::Int8 | ColumnType::Int16 | ColumnType::Int32 | ColumnType::UInt8 | ColumnType::UInt16 => {
            Kind::Integer
        }
        ColumnType::Boolean => Kind::Logical,
        ColumnType::Float => Kind::Double { integer: false },
        ColumnType::Double => match (col.profile_logical, col.storage) {
            (Some(Logical::Date), _) => Kind::Date,
            (Some(Logical::Timestamp), _) => Kind::Seconds { per_second: 1.0, tz: zone_of(col, profile) },
            (Some(Logical::Categorical), _) => Kind::LetterLevels {
                levels: profile.and_then(|p| p.categorical.as_ref()).map_or(0, |c| c.levels.len()),
            },
            (None, Some(Storage::Byte | Storage::Int | Storage::Long)) => Kind::Double { integer: true },
            _ => Kind::Double { integer: false },
        },
        ColumnType::Int64 | ColumnType::UInt32 | ColumnType::UInt64 => Kind::Int64(modes.int64),
        ColumnType::Date => Kind::Date,
        ColumnType::Timestamp { unit, .. } => match unit {
            TimeUnit::Millis | TimeUnit::Micros => {
                Kind::Seconds { per_second: per_second(*unit), tz: zone_of(col, profile) }
            }
            TimeUnit::Nanos => Kind::Nanos { tz: zone_of(col, profile) },
        },
        ColumnType::Time { unit, .. } => Kind::Time { per_second: per_second(*unit) },
        ColumnType::Decimal { .. } => match modes.decimal {
            DecimalMode::Double => Kind::Double { integer: false },
            DecimalMode::Character => Kind::Text,
        },
        ColumnType::Text => match (profile.and_then(|p| p.categorical.as_ref()), col.levels) {
            (Some(cat), _) => Kind::Factor { levels: cat.levels.clone(), ordered: cat.ordered, rows: false },
            (None, Some(LevelsFrom::Rows)) => Kind::Factor { levels: Vec::new(), ordered: false, rows: true },
            (None, _) => Kind::Text,
        },
        ColumnType::Binary => Kind::Binary,
        ColumnType::Unsupported(why) => {
            return Err(Fail::Message(format!("column \"{}\" is {why}", col.name)));
        }
    })
}

/// The R type `read_parquet()` gives a column by default, for the info
/// call; `None` for one it does not read.
fn r_type(col: &ColumnInfo, profile: Option<&dta_parquet::ColumnProfile>, labelled: bool) -> Option<&'static str> {
    if col.role == Role::Nested {
        return None;
    }
    let kind = kind_of(col, profile, Modes::DEFAULT).ok()?;
    Some(match kind {
        Kind::Integer | Kind::Double { .. } | Kind::Int64(_) if labelled => "dtaparser_labelled",
        // Always labelled: its set is recorded or made from the levels.
        Kind::LetterLevels { .. } => "dtaparser_labelled",
        Kind::Integer => "integer",
        Kind::Logical => "logical",
        Kind::Double { .. } | Kind::Int64(_) => "double",
        Kind::Date => "Date",
        Kind::Seconds { .. } | Kind::Nanos { .. } => "POSIXct",
        Kind::Time { .. } => "difftime",
        Kind::Factor { ordered: true, .. } => "ordered",
        Kind::Factor { .. } => "factor",
        Kind::Text => "character",
        Kind::Binary => "list",
    })
}

fn unit_name(u: TimeUnit) -> &'static str {
    match u {
        TimeUnit::Millis => "MILLIS",
        TimeUnit::Micros => "MICROS",
        TimeUnit::Nanos => "NANOS",
    }
}

/// Parquet's logical type (or else its converted type) as text.
fn logical_name(col: &ColumnInfo) -> Option<String> {
    use dta_parquet::format::converted as cv;
    if let Some(l) = &col.logical {
        return Some(match l {
            LogicalType::String => "STRING".into(),
            LogicalType::Map => "MAP".into(),
            LogicalType::List => "LIST".into(),
            LogicalType::Enum => "ENUM".into(),
            LogicalType::Decimal { scale, precision } => format!("DECIMAL({precision}, {scale})"),
            LogicalType::Date => "DATE".into(),
            LogicalType::Time { utc, unit } => {
                format!("TIME({}, {})", unit.map_or("?", unit_name), if *utc { "UTC" } else { "local" })
            }
            LogicalType::Timestamp { utc, unit } => {
                format!("TIMESTAMP({}, {})", unit.map_or("?", unit_name), if *utc { "UTC" } else { "local" })
            }
            LogicalType::Integer { bits, signed } => {
                format!("INT({bits}, {})", if *signed { "signed" } else { "unsigned" })
            }
            LogicalType::Null => "NULL".into(),
            LogicalType::Json => "JSON".into(),
            LogicalType::Bson => "BSON".into(),
            LogicalType::Uuid => "UUID".into(),
            LogicalType::Float16 => "FLOAT16".into(),
            LogicalType::Other(id) => format!("logical type {id}"),
        });
    }
    let name = match col.converted? {
        cv::UTF8 => "UTF8",
        cv::MAP => "MAP",
        cv::MAP_KEY_VALUE => "MAP_KEY_VALUE",
        cv::LIST => "LIST",
        cv::ENUM => "ENUM",
        cv::DECIMAL => "DECIMAL",
        cv::DATE => "DATE",
        cv::TIME_MILLIS => "TIME_MILLIS",
        cv::TIME_MICROS => "TIME_MICROS",
        cv::TIMESTAMP_MILLIS => "TIMESTAMP_MILLIS",
        cv::TIMESTAMP_MICROS => "TIMESTAMP_MICROS",
        cv::UINT_8 => "UINT_8",
        cv::UINT_16 => "UINT_16",
        cv::UINT_32 => "UINT_32",
        cv::UINT_64 => "UINT_64",
        cv::INT_8 => "INT_8",
        cv::INT_16 => "INT_16",
        cv::INT_32 => "INT_32",
        cv::INT_64 => "INT_64",
        cv::JSON => "JSON",
        cv::BSON => "BSON",
        cv::INTERVAL => "INTERVAL",
        _ => return None,
    };
    Some(name.into())
}

/// The profile's entries by column name, built once.
fn entries(profile: Option<&Profile>) -> HashMap<&str, &dta_parquet::ColumnProfile> {
    profile.map_or_else(HashMap::new, |p| p.columns.iter().map(|c| (c.name.as_str(), c)).collect())
}

fn nonempty(s: &Option<String>) -> Option<&str> {
    s.as_deref().filter(|s| !s.is_empty())
}

/// The profile's value label sets by name, built once: a file may have
/// thousands of columns, each naming one.
fn sets_by_name(profile: Option<&Profile>) -> HashMap<&str, usize> {
    profile.map_or_else(HashMap::new, |p| {
        p.value_labels.iter().enumerate().map(|(k, s)| (s.name.as_str(), k)).collect()
    })
}

/// The index of the value label set a column's profile entry names, if
/// the profile has it.
fn label_set(sets: &HashMap<&str, usize>, entry: Option<&dta_parquet::ColumnProfile>) -> Option<usize> {
    let name = entry?.value_labels.as_deref()?;
    sets.get(name).copied()
}

// ---------------------------------------------------------------- info

/// The footer of a Parquet file as element 0 of `holder`: a list of
/// rows, row_groups (a list of rows, compressed and uncompressed bytes),
/// created_by, compression, label, notes, columns (a list of character
/// vectors: name, role, r_type, physical_type, logical_type, label,
/// value_labels, storage, logical), warnings and key_value (a list of
/// character vectors: key, value; the value as text, bytes that are not
/// UTF-8 replaced, NA when the entry has none).
///
/// # Safety
/// The pointers come from init.c.
#[no_mangle]
pub unsafe extern "C" fn dtaparser_parquet_info_rs(
    path: *const c_char,
    raw: *const u8,
    raw_len: usize,
    holder: Sexp,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let input = input(path, raw, raw_len);
    guard(err, err_len, || {
        let options = ReadOptions { threads: 1, nested: Nested::Skip, ..ReadOptions::default() };
        with_reader(&input, options, &mut |r| {
            let names = [
                "rows", "row_groups", "created_by", "compression", "label", "notes", "columns", "warnings",
                "key_value",
            ];
            let out = named_list(holder, 0, &names)?;
            super::doubles_elt(out, 0, &[r.rows() as f64])?;
            let groups = r.row_groups();
            let g = named_list(out, 1, &["rows", "compressed_bytes", "uncompressed_bytes"])?;
            super::doubles_elt(g, 0, &groups.iter().map(|x| x.rows as f64).collect::<Vec<_>>())?;
            super::doubles_elt(g, 1, &groups.iter().map(|x| x.compressed_bytes as f64).collect::<Vec<_>>())?;
            super::doubles_elt(g, 2, &groups.iter().map(|x| x.uncompressed_bytes as f64).collect::<Vec<_>>())?;
            optional_string_elt(out, 2, r.created_by())?;
            let codecs: Vec<String> = r.codecs().iter().map(|c| codec_name(*c)).collect();
            strings_elt(out, 3, &codecs)?;
            let profile = r.profile();
            optional_string_elt(out, 4, profile.and_then(|p| nonempty(&p.label)))?;
            strings_elt(out, 5, profile.map_or(&[][..], |p| &p.notes[..]))?;
            let by_name = entries(profile);
            let sets = sets_by_name(profile);
            let cols = r.reader_columns();
            let fields = [
                "name", "role", "r_type", "physical_type", "logical_type", "label", "value_labels", "storage",
                "logical",
            ];
            let list = named_list(out, 6, &fields)?;
            let mut text: Vec<Vec<Option<String>>> = vec![Vec::with_capacity(cols.len()); fields.len()];
            let mut warnings = r.warnings().to_vec();
            for (k, c) in cols.iter().enumerate() {
                let entry = by_name.get(c.name.as_str()).copied();
                let set = label_set(&sets, entry)
                    .filter(|_| c.role == Role::Data && labels_apply(c, entry))
                    .and_then(|k| profile.map(|p| &p.value_labels[k]))
                    .map(|s| s.name.clone());
                // A categorical holding .a to .z: its set, recorded or made.
                let set = match r.categorical_labels(k) {
                    Some((s, w)) => {
                        warnings.extend(w);
                        Some(s.name)
                    }
                    None => set,
                };
                text[0].push(Some(c.name.clone()));
                text[1].push(Some(if c.role == Role::Data { "data" } else { "nested" }.into()));
                text[2].push(r_type(c, entry, set.is_some()).map(String::from));
                text[3].push(c.physical.map(|p| p.name()));
                text[4].push(logical_name(c));
                text[5].push(entry.and_then(|e| nonempty(&e.label)).map(String::from));
                text[6].push(set);
                text[7].push(c.storage.map(|s| s.name().to_string()));
                // Both forms of a categorical say so: text with levels in
                // the profile, and DOUBLE level numbers (plan 0022).
                let text_categorical = c.kind == ColumnType::Text && entry.is_some_and(|e| e.categorical.is_some());
                text[8].push(
                    c.profile_logical
                        .map(|l| l.name().to_string())
                        .or_else(|| text_categorical.then(|| Logical::Categorical.name().to_string())),
                );
            }
            for (k, v) in text.iter().enumerate() {
                optional_strings_elt(list, k, v)?;
            }
            strings_elt(out, 7, &warnings)?;
            let kv = &r.metadata().key_value;
            let pairs = named_list(out, 8, &["key", "value"])?;
            let keys: Vec<Option<String>> = kv.iter().map(|e| Some(e.key.clone())).collect();
            let values: Vec<Option<String>> =
                kv.iter().map(|e| e.value.as_deref().map(|v| String::from_utf8_lossy(v).into_owned())).collect();
            optional_strings_elt(pairs, 0, &keys)?;
            optional_strings_elt(pairs, 1, &values)?;
            Ok(())
        })
    })
}

fn codec_name(c: dta_parquet::format::Codec) -> String {
    use dta_parquet::format::Codec::*;
    match c {
        Uncompressed => "none".into(),
        Snappy => "snappy".into(),
        Gzip => "gzip".into(),
        Lzo => "lzo".into(),
        Brotli => "brotli".into(),
        Lz4 => "lz4".into(),
        Zstd => "zstd".into(),
        Lz4Raw => "lz4_raw".into(),
        Other(v) => format!("codec {v}"),
    }
}

/// A character vector with NA for each `None`, as element `i` of `parent`.
pub(crate) fn optional_strings_elt<S: AsRef<str>>(parent: Sexp, i: usize, v: &[Option<S>]) -> Res<()> {
    let x = alloc_elt(parent, i, STRSXP, v.len())?;
    let mut bytes = Vec::new();
    let mut ends = Vec::with_capacity(v.len());
    let mut missing = Vec::with_capacity(v.len());
    for s in v {
        if let Some(s) = s {
            bytes.extend_from_slice(s.as_ref().as_bytes());
        }
        ends.push(bytes.len());
        missing.push(s.is_none() as u8);
    }
    set_strings_na(x, 0, &bytes, &ends, &missing)
}

/// A string, or NULL, as element `i` of `parent`.
pub(crate) fn optional_string_elt(parent: Sexp, i: usize, v: Option<&str>) -> Res<()> {
    match v {
        Some(s) => strings_elt(parent, i, &[s]),
        None => Ok(()),
    }
}

/// Whether value labels apply to a column: numbers that are not dates,
/// times or factors, as `read_dta` keeps them.
fn labels_apply(col: &ColumnInfo, entry: Option<&dta_parquet::ColumnProfile>) -> bool {
    matches!(
        kind_of(col, entry, Modes::DEFAULT),
        Ok(Kind::Integer | Kind::Double { .. } | Kind::Int64(Int64Mode::Double))
    )
}

// ---------------------------------------------------------------- read

/// One selected column as it is read.
struct Col {
    /// Index into the reader's columns.
    index: usize,
    kind: Kind,
    /// The R vector filled (null for text and int64-as-character, made
    /// after the read).
    x: Sexp,
    /// A missing code per row, when one is needed after the read.
    codes: Vec<u8>,
    /// int64 as character: the values, converted after the read (the
    /// bits of `u64`s for an unsigned 64-bit column).
    int64s: Vec<i64>,
    /// An unsigned 64-bit column, read as `u64`.
    unsigned: bool,
    /// INT32: whether a value may be -2^31, which R's integers cannot
    /// hold (it is their NA), so the codes are needed to tell it apart.
    check_min: bool,
}

/// What text columns gather during the read.
enum Sink {
    None,
    Text(Strings),
    /// A list of raw vectors, filled chunk by chunk.
    Binary(Sexp),
}

/// Whether every row group's statistics show column `leaf`'s minimum
/// above the type's least value, so no value is R's integer NA.
fn min_ruled_out(meta: &dta_parquet::format::FileMetaData, leaf: usize, width: usize) -> bool {
    meta.row_groups.iter().all(|g| {
        let Some(m) = g.columns.get(leaf).and_then(|c| c.meta.as_ref()) else { return false };
        let Some(s) = &m.statistics else { return false };
        let min = s.min_value.as_ref().or(s.min.as_ref());
        match (min, width) {
            (Some(b), 4) if b.len() == 4 => i32::from_le_bytes(b[..4].try_into().unwrap_or_default()) > i32::MIN,
            (Some(b), 8) if b.len() == 8 => i64::from_le_bytes(b[..8].try_into().unwrap_or_default()) > i64::MIN,
            // A chunk of only nulls has no minimum and no value.
            (None, _) => s.null_count.is_some_and(|n| n >= 0 && n == m.num_values),
            _ => false,
        }
    })
}

/// Read columns of a Parquet file into R vectors, as element 0 of
/// `holder`: list(columns, names, label, notes, warnings, integer, rows,
/// letter_levels), `letter_levels` TRUE for each categorical holding `.a`
/// to `.z` (plan 0022), which `factors = TRUE` leaves a labelled double.
/// `names` selects columns by name (NULL for every data column); `int64`
/// is 0 for doubles, 1 for integer64, 2 for character; `timestamps` 0
/// to make nanoseconds that are not whole microseconds an error, 1 to
/// drop them; `nested` 0 to make nested columns an error, 1 to skip them;
/// `decimal` 0 for doubles, 1 for character.
///
/// # Safety
/// The pointers come from init.c; `names` is R_NilValue or a character
/// vector.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn dtaparser_parquet_read_rs(
    path: *const c_char,
    raw: *const u8,
    raw_len: usize,
    names: Sexp,
    prefer: *const c_char,
    skip: f64,
    n_max: f64,
    int64: c_int,
    timestamps: c_int,
    nested: c_int,
    decimal: c_int,
    threads: c_int,
    holder: Sexp,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let input = input(path, raw, raw_len);
    let wanted: Option<Vec<String>> = (TYPEOF(names) == STRSXP)
        .then(|| super::r_strings(names).into_iter().map(String::from).collect());
    let prefer = c_str(prefer);
    guard(err, err_len, || {
        let int64 = match int64 {
            0 => Int64Mode::Double,
            1 => Int64Mode::Integer64,
            _ => Int64Mode::Character,
        };
        let decimal = if decimal == 1 { DecimalMode::Character } else { DecimalMode::Double };
        let modes = Modes { int64, decimal };
        let options = ReadOptions {
            threads: threads.max(0) as usize,
            nested: if nested == 1 { Nested::Skip } else { Nested::Error },
            ..ReadOptions::default()
        };
        with_reader(&input, options, &mut |r| {
            read_into(r, wanted.as_deref(), prefer.as_deref(), skip, n_max, modes, timestamps == 1, holder)
        })
    })
}

fn select(r: &dyn Access, wanted: Option<&[String]>, prefer: Option<&str>) -> Res<Vec<usize>> {
    let cols = r.reader_columns();
    let Some(wanted) = wanted else {
        return r.data_columns().map_err(|e| {
            Fail::Message(e.message.replace("or skip nested columns", "or pass nested = \"skip\""))
        });
    };
    let by_name: HashMap<&str, usize> = cols.iter().enumerate().rev().map(|(k, c)| (c.name.as_str(), k)).collect();
    if let Some(&k) = prefer.and_then(|p| by_name.get(p)) {
        return Ok(vec![k]);
    }
    wanted
        .iter()
        .map(|name| {
            by_name.get(name.as_str()).copied().ok_or_else(|| {
                let shown: Vec<String> = cols.iter().take(20).map(|c| format!("\"{}\"", c.name)).collect();
                let more = if cols.len() > 20 { format!(" and {} more", cols.len() - 20) } else { String::new() };
                Fail::Message(format!(
                    "column \"{name}\" is not in the file; its columns are {}{more}",
                    shown.join(", ")
                ))
            })
        })
        .collect()
}

#[allow(clippy::too_many_arguments)]
fn read_into(
    r: &mut dyn Access,
    wanted: Option<&[String]>,
    prefer: Option<&str>,
    skip: f64,
    n_max: f64,
    modes: Modes,
    truncate: bool,
    holder: Sexp,
) -> Res<()> {
    let selected = select(r, wanted, prefer)?;
    let skip = skip as u64;
    let n = if n_max.is_finite() { n_max as u64 } else { u64::MAX };
    let window = r.window(skip, n);
    let rows = usize::try_from(window.end - window.start).map_err(|_| Fail::Message("too many rows".into()))?;
    let profile = r.profile();
    let by_name: HashMap<&str, usize> =
        profile.map_or_else(HashMap::new, |p| p.columns.iter().enumerate().map(|(k, c)| (c.name.as_str(), k)).collect());
    let set_names = sets_by_name(profile);
    let entry_of = |name: &str| by_name.get(name).and_then(|&k| profile.map(|p| &p.columns[k]));
    let fields = ["columns", "names", "label", "notes", "warnings", "integer", "rows", "letter_levels"];
    let out_list = named_list(holder, 0, &fields)?;
    let out = alloc_elt(out_list, 0, VECSXP, selected.len())?;
    let reader_cols = r.reader_columns();
    let meta = r.metadata();
    let limits = DictLimits::from_env();

    let mut kinds = Vec::with_capacity(selected.len());
    for &c in &selected {
        let info = &reader_cols[c];
        if info.role == Role::Nested {
            return Err(Fail::Message(format!(
                "column \"{}\" is nested (a list, map or group), which is not read",
                info.name
            )));
        }
        kinds.push(kind_of(info, entry_of(info.name.as_str()), modes)?);
    }
    // The R vectors the read makes: 4 or 8 bytes a row, and for text at
    // least the 8-byte end of each value.
    let width = |kind: &Kind| match kind {
        Kind::Integer | Kind::Logical | Kind::Factor { .. } => 4,
        _ => 8,
    };
    super::reserve(kinds.iter().map(width).sum::<usize>().saturating_mul(rows))?;

    let mut cols = Vec::with_capacity(selected.len());
    let mut sinks = Vec::with_capacity(selected.len());
    for ((k, &c), kind) in selected.iter().enumerate().zip(kinds) {
        let info = &reader_cols[c];
        let mut col = Col {
            index: c,
            kind: kind.clone(),
            x: std::ptr::null_mut(),
            codes: Vec::new(),
            int64s: Vec::new(),
            unsigned: info.kind == ColumnType::UInt64,
            check_min: false,
        };
        let mut sink = Sink::None;
        match &kind {
            Kind::Integer => {
                col.x = alloc_elt(out, k, INTSXP, rows)?;
                col.check_min = info.kind == ColumnType::Int32 && !min_ruled_out(meta, info.leaf(), 4);
                if col.check_min {
                    col.codes = vec![0; rows];
                }
            }
            Kind::Logical => col.x = alloc_elt(out, k, LGLSXP, rows)?,
            Kind::Factor { .. } => col.x = alloc_elt(out, k, INTSXP, rows)?,
            Kind::Double { .. }
            | Kind::LetterLevels { .. }
            | Kind::Date
            | Kind::Seconds { .. }
            | Kind::Nanos { .. }
            | Kind::Time { .. } => col.x = alloc_elt(out, k, REALSXP, rows)?,
            Kind::Int64(Int64Mode::Double) => col.x = alloc_elt(out, k, REALSXP, rows)?,
            Kind::Int64(Int64Mode::Integer64) => {
                col.x = alloc_elt(out, k, REALSXP, rows)?;
                // Unsigned values are never -2^63, integer64's NA.
                col.check_min = info.kind == ColumnType::Int64 && !min_ruled_out(meta, info.leaf(), 8);
                if col.check_min {
                    col.codes = vec![0; rows];
                }
            }
            Kind::Int64(Int64Mode::Character) => {
                col.int64s = vec![0; rows];
                col.codes = vec![0; rows];
            }
            Kind::Text => sink = Sink::Text(Strings::new(limits, rows)),
            Kind::Binary => sink = Sink::Binary(alloc_elt(out, k, VECSXP, rows)?),
        }
        cols.push(col);
        sinks.push(sink);
    }

    // The outputs point into the R vectors and the buffers above, which
    // stay where they are until the read returns.
    let mut outputs: Vec<Output> = Vec::with_capacity(cols.len());
    for col in &mut cols {
        let codes = (!col.codes.is_empty()).then(|| unsafe { std::slice::from_raw_parts_mut(col.codes.as_mut_ptr(), rows) });
        let output = unsafe {
            match &col.kind {
                Kind::Integer | Kind::Logical => {
                    let p = if col.kind == Kind::Logical { LOGICAL(col.x) } else { INTEGER(col.x) };
                    let mut n = Numbers::new(slice_mut(p, rows), NA_INTEGER);
                    if let Some(c) = codes {
                        n = n.with_codes(c);
                    }
                    Output::Int32(n)
                }
                Kind::Factor { .. } => Output::Levels { codes: slice_mut(INTEGER(col.x), rows), base: 1, null: NA_INTEGER },
                Kind::Double { .. }
                | Kind::LetterLevels { .. }
                | Kind::Date
                | Kind::Seconds { .. }
                | Kind::Time { .. }
                | Kind::Int64(Int64Mode::Double) => {
                    Output::Float64(Numbers::new(slice_mut(REAL(col.x), rows), na_real()).with_missing(r_missing))
                }
                Kind::Nanos { .. } => {
                    Output::Int64(Numbers::new(slice_mut(REAL(col.x) as *mut i64, rows), i64::MIN))
                }
                Kind::Int64(Int64Mode::Integer64) => {
                    let mut n = Numbers::new(slice_mut(REAL(col.x) as *mut i64, rows), i64::MIN);
                    if let Some(c) = codes {
                        n = n.with_codes(c);
                    }
                    Output::Int64(n)
                }
                Kind::Int64(Int64Mode::Character) if col.unsigned => Output::UInt64(
                    Numbers::new(slice_mut(col.int64s.as_mut_ptr() as *mut u64, rows), 0)
                        .with_codes(codes.expect("codes")),
                ),
                Kind::Int64(Int64Mode::Character) => Output::Int64(
                    Numbers::new(slice_mut(col.int64s.as_mut_ptr(), rows), 0).with_codes(codes.expect("codes")),
                ),
                Kind::Text | Kind::Binary => Output::Text,
            }
        };
        outputs.push(output);
    }

    let names: Vec<&str> = cols.iter().map(|c| reader_cols[c.index].name.as_str()).collect();
    let names: Vec<String> = names.into_iter().map(String::from).collect();
    // Indices of what the steps after the read need, so that the reader
    // can be borrowed mutably for the read.
    let entry_ix: Vec<Option<usize>> = names.iter().map(|n| by_name.get(n.as_str()).copied()).collect();
    let set_ix: Vec<Option<usize>> = cols
        .iter()
        .zip(&names)
        .map(|(c, n)| {
            let info = &reader_cols[c.index];
            let e = entry_of(n.as_str());
            label_set(&set_names, e).filter(|_| labels_apply(info, e))
        })
        .collect();
    let integer: Vec<bool> = cols
        .iter()
        .map(|c| {
            let info = &reader_cols[c.index];
            matches!(
                info.kind,
                ColumnType::Int8 | ColumnType::Int16 | ColumnType::Int32 | ColumnType::UInt8 | ColumnType::UInt16
            ) || matches!(info.storage, Some(Storage::Byte | Storage::Int | Storage::Long))
        })
        .collect();
    let data_label = profile.and_then(|p| nonempty(&p.label)).map(String::from);
    let notes: Vec<String> = profile.map_or_else(Vec::new, |p| p.notes.clone());
    let mut warnings: Vec<String> = r.warnings().to_vec();
    // Each categorical holding .a to .z: its value label set, recorded or
    // made from the levels, and the warning about a recorded one that
    // does not fit.
    let letter_sets: Vec<Option<ValueLabelSet>> = cols
        .iter()
        .map(|c| match c.kind {
            Kind::LetterLevels { .. } => r.categorical_labels(c.index).map(|(set, w)| {
                warnings.extend(w);
                set
            }),
            _ => None,
        })
        .collect();
    let letter_levels: Vec<bool> = cols.iter().map(|c| matches!(c.kind, Kind::LetterLevels { .. })).collect();
    let int64_names: Vec<String> = cols
        .iter()
        .filter(|c| matches!(reader_cols[c.index].kind, ColumnType::Int64 | ColumnType::UInt32 | ColumnType::UInt64))
        .map(|c| format!("column \"{}\":", reader_cols[c.index].name))
        .collect();
    drop(by_name);
    drop(set_names);

    let mut failed: Option<Fail> = None;
    let selected_ix: Vec<usize> = cols.iter().map(|c| c.index).collect();
    let report = {
        let mut text = |k: usize, chunk: &TextChunk| -> dta::Result<()> {
            let step = match &mut sinks[k] {
                Sink::Text(s) => s.add_chunk(&names[k], chunk),
                Sink::Binary(list) => set_raws(*list, chunk),
                Sink::None => Err(Fail::Message("internal: text for a column that is not text".into())),
            };
            step.map_err(|f| {
                failed = Some(f);
                dta::Error::new("stopped")
            })
        };
        r.read(&selected_ix, skip, n, &mut outputs, &mut text)
    };
    drop(outputs);
    let mut report = match (report, failed) {
        (_, Some(f)) => return Err(f),
        (Err(e), None) => {
            return Err(Fail::Message(read_error(e.to_string(), &int64_names)));
        }
        (Ok(report), None) => report,
    };

    let profile = r.profile();
    let mut shared = SharedAttrs::default();
    for (k, (col, sink)) in cols.iter_mut().zip(sinks).enumerate() {
        let name = &names[k];
        let entry = entry_ix[k].and_then(|i| profile.map(|p| &p.columns[i]));
        let set = set_ix[k].and_then(|i| profile.map(|p| (i, &p.value_labels[i])));
        if let Kind::Factor { levels, rows: true, .. } = &mut col.kind {
            *levels = report.levels.get_mut(k).and_then(Option::take).unwrap_or_default();
        }
        let x = finish(out, k, col, sink, name, rows, report.letters[k], truncate)?;
        set_column_attributes(x, &col.kind, entry, set, &mut shared)?;
        if let Kind::LetterLevels { levels } = col.kind {
            if let Some((row, v)) = bad_levels(x, rows, levels) {
                warnings.push(format!(
                    "column \"{name}\": row {} holds {v}, which is not one of its {levels} level numbers; it is read as NA",
                    window.start + row as u64 + 1
                ));
            }
            if let Some(set) = &letter_sets[k] {
                set_labels(x, set)?;
                string_attr(x, c"label_set", &set.name)?;
                shared.text(x, c"class", &["dtaparser_labelled", "vctrs_vctr"])?;
            }
        }
    }
    strings_elt(out_list, 1, &names)?;
    optional_string_elt(out_list, 2, data_label.as_deref())?;
    strings_elt(out_list, 3, &notes)?;
    strings_elt(out_list, 4, &warnings)?;
    let flags = alloc_elt(out_list, 5, LGLSXP, integer.len())?;
    for (d, &b) in unsafe { slice_mut(LOGICAL(flags), integer.len()) }.iter_mut().zip(&integer) {
        *d = b as c_int;
    }
    super::doubles_elt(out_list, 6, &[rows as f64])?;
    let flags = alloc_elt(out_list, 7, LGLSXP, letter_levels.len())?;
    for (d, &b) in unsafe { slice_mut(LOGICAL(flags), letter_levels.len()) }.iter_mut().zip(&letter_levels) {
        *d = b as c_int;
    }
    Ok(())
}

/// A categorical holding `.a` to `.z` read as doubles: make each value
/// that is not a level number from 1 to `levels` (a fraction, a number
/// past the levels, a plain NaN) NA, `.`. Returns the first such row
/// (from 0) and its value; NA and the tagged NAs `.a` to `.z` stay as
/// they are.
fn bad_levels(x: Sexp, rows: usize, levels: usize) -> Option<(usize, f64)> {
    let v = unsafe { slice_mut(REAL(x), rows) };
    let mut first = None;
    for (i, d) in v.iter_mut().enumerate() {
        if r_code_parquet(*d) == 0 && dta_parquet::level_index(*d, levels).is_none() {
            first.get_or_insert((i, *d));
            *d = na_real();
        }
    }
    first
}

/// The message of a read's error, with the argument of `read_parquet`
/// that keeps the value added where the core names another way.
/// `int64_names` are the `column "name":` prefixes of the INT64 and
/// unsigned 32- and 64-bit columns read.
fn read_error(mut m: String, int64_names: &[String]) -> String {
    const DECIMAL: &str = "read the column as text to keep every digit";
    if m.contains(DECIMAL) {
        return m.replace(DECIMAL, "read with decimal = \"character\" to keep every digit");
    }
    if int64_names.iter().any(|n| m.starts_with(n.as_str())) {
        if m.contains("cannot be held exactly as a double") {
            m.push_str("; read with int64 = \"integer64\" or int64 = \"character\" to keep every digit");
        } else if m.contains("cannot be held exactly as a 64-bit integer") {
            m.push_str("; read with int64 = \"character\" to keep every digit");
        }
    }
    m
}

/// # Safety
/// `p` points at `n` elements alive and not otherwise borrowed while the
/// slice is used.
unsafe fn slice_mut<'a, T>(p: *mut T, n: usize) -> &'a mut [T] {
    if n == 0 {
        &mut []
    } else {
        std::slice::from_raw_parts_mut(p, n)
    }
}

/// R's double for missing code `c`: NA for `.`, a tagged NA for `.a` to
/// `.z`.
fn r_missing(c: u8) -> f64 {
    if c == missing::SYSTEM {
        na_real()
    } else {
        tagged_nan(c)
    }
}

/// Put one chunk of a binary column into its list of raw vectors.
fn set_raws(list: Sexp, chunk: &TextChunk) -> Res<()> {
    let mut bytes = Vec::new();
    let mut ends = Vec::with_capacity(chunk.rows);
    let mut missing = Vec::with_capacity(chunk.rows);
    for r in 0..chunk.rows {
        match chunk.row(r) {
            Some(v) => {
                bytes.extend_from_slice(v);
                missing.push(0);
            }
            None => missing.push(1),
        }
        ends.push(bytes.len());
    }
    status(unsafe {
        dtaparser_set_raws(list, chunk.first as isize, bytes.as_ptr(), ends.as_ptr(), missing.as_ptr(), chunk.rows as isize)
    })
}

/// After the read: convert what was read as counts or bits, check what
/// R cannot hold, and make text columns. Returns the column's vector.
#[allow(clippy::too_many_arguments)]
fn finish(out: Sexp, k: usize, col: &mut Col, sink: Sink, name: &str, rows: usize, letters: bool, truncate: bool) -> Res<Sexp> {
    let first_min = |codes: &[u8], values: &dyn Fn(usize) -> bool| -> Option<usize> {
        (0..rows).find(|&i| codes[i] == 0 && values(i))
    };
    match &col.kind {
        Kind::Integer if col.check_min => {
            let v = unsafe { slice_mut(INTEGER(col.x), rows) };
            if let Some(i) = first_min(&col.codes, &|i| v[i] == NA_INTEGER) {
                return Err(Fail::Message(format!(
                    "column \"{name}\": the value -2147483648 in row {} cannot be held as an R integer, whose NA it is",
                    i + 1
                )));
            }
            Ok(col.x)
        }
        Kind::Int64(Int64Mode::Integer64) if col.check_min => {
            let v = unsafe { slice_mut(REAL(col.x) as *mut i64, rows) };
            if let Some(i) = first_min(&col.codes, &|i| v[i] == i64::MIN) {
                return Err(Fail::Message(format!(
                    "column \"{name}\": the value -9223372036854775808 in row {} cannot be held as an integer64, whose NA it is; read with int64 = \"character\"",
                    i + 1
                )));
            }
            Ok(col.x)
        }
        Kind::Int64(Int64Mode::Character) => {
            let x = alloc_elt(out, k, STRSXP, rows)?;
            let mut bytes = Vec::with_capacity(rows * 8);
            let mut ends = Vec::with_capacity(rows);
            for (&v, &c) in col.int64s.iter().zip(&col.codes) {
                if c == 0 && col.unsigned {
                    bytes.extend_from_slice((v as u64).to_string().as_bytes());
                } else if c == 0 {
                    bytes.extend_from_slice(v.to_string().as_bytes());
                }
                ends.push(bytes.len());
            }
            set_strings_na(x, 0, &bytes, &ends, &col.codes)?;
            col.int64s = Vec::new();
            Ok(x)
        }
        Kind::Seconds { per_second, .. } | Kind::Time { per_second } if *per_second != 1.0 => {
            let v = unsafe { slice_mut(REAL(col.x), rows) };
            for d in v.iter_mut() {
                if !d.is_nan() {
                    *d /= per_second;
                }
            }
            Ok(col.x)
        }
        Kind::Nanos { .. } => {
            let v = unsafe { slice_mut(REAL(col.x), rows) };
            for (i, d) in v.iter_mut().enumerate() {
                let n = d.to_bits() as i64;
                *d = if n == i64::MIN {
                    na_real()
                } else {
                    if n % 1000 != 0 && !truncate {
                        return Err(Fail::Message(format!(
                            "column \"{name}\": row {} is {n} nanoseconds, which is not a whole number of microseconds; read with timestamps = \"truncate\" to drop what is below a microsecond",
                            i + 1
                        )));
                    }
                    n.div_euclid(1000) as f64 / 1e6
                };
            }
            Ok(col.x)
        }
        Kind::Double { integer: true } if !letters => {
            // A byte, int or long column written wider for `.a` to `.z`,
            // none of them in the rows read: an integer column again.
            let v = unsafe { std::slice::from_raw_parts(REAL(col.x) as *const f64, rows) };
            let whole = v.iter().all(|&d| (d.is_nan() && d.to_bits() == NA_BITS) || (d.fract() == 0.0 && d > i32::MIN as f64 && d <= i32::MAX as f64));
            if !whole {
                return Ok(col.x);
            }
            // `col.x` stays in `out` until this allocation replaces it, and
            // nothing allocates while it is copied.
            let y = alloc_elt(out, k, INTSXP, rows)?;
            for (d, &s) in unsafe { slice_mut(INTEGER(y), rows) }.iter_mut().zip(v) {
                *d = if s.is_nan() { NA_INTEGER } else { s as i32 };
            }
            col.x = y;
            col.kind = Kind::Integer;
            Ok(y)
        }
        Kind::Text => match sink {
            Sink::Text(mut s) => {
                if let Some(d) = &mut s.dict {
                    d.table = HashMap::default();
                    d.next = Vec::new();
                }
                let x = packed_elt(out, k, &s)?;
                Ok(x)
            }
            _ => Err(Fail::Message("internal: a text column without its text".into())),
        },
        Kind::Binary => match sink {
            Sink::Binary(x) => Ok(x),
            _ => Err(Fail::Message("internal: a binary column without its list".into())),
        },
        _ => Ok(col.x),
    }
}

/// The attributes `read_dta` gives the same column: `label` and `format`
/// from the profile; for labelled numbers `labels` in code order and the
/// class `dtaparser_labelled`; the classes of dates, date-times, factors
/// and integer64.
/// Attribute values made once and given to every column that has the
/// same one: classes, display formats, time zones and each value label
/// set's labels. A wide file then makes a few R objects for these, not
/// some per column, which R's collector would trace. R copies a shared
/// attribute before anything changes it.
#[derive(Default)]
struct SharedAttrs {
    texts: HashMap<(&'static str, String), Sexp>,
    labels: HashMap<usize, Sexp>,
}

impl SharedAttrs {
    /// Set attribute `name` of `x` to the character vector `value`,
    /// made the first time.
    fn text(&mut self, x: Sexp, name: &'static CStr, value: &[&str]) -> Res<()> {
        let key = (name.to_str().unwrap_or(""), value.join("\u{1}"));
        if let Some(&v) = self.texts.get(&key) {
            return set_attr(x, name, v);
        }
        let v = alloc_attr(x, name, STRSXP, value.len())?;
        set_strs(v, value)?;
        self.texts.insert(key, v);
        Ok(())
    }
}

extern "C" {
    fn dtaparser_set_attr(x: Sexp, name: *const c_char, value: Sexp) -> c_int;
}

/// Set attribute `name` of `x` to `value`, which is already reachable.
fn set_attr(x: Sexp, name: &CStr, value: Sexp) -> Res<()> {
    status(unsafe { dtaparser_set_attr(x, name.as_ptr(), value) })
}

fn set_column_attributes(
    x: Sexp,
    kind: &Kind,
    entry: Option<&dta_parquet::ColumnProfile>,
    set: Option<(usize, &ValueLabelSet)>,
    shared: &mut SharedAttrs,
) -> Res<()> {
    if let Some(label) = entry.and_then(|e| nonempty(&e.label)) {
        string_attr(x, c"label", label)?;
    }
    if let Some(format) = entry.and_then(|e| nonempty(&e.format)) {
        shared.text(x, c"format", &[format])?;
    }
    match kind {
        Kind::Date => shared.text(x, c"class", &["Date"])?,
        Kind::Seconds { tz, .. } | Kind::Nanos { tz } => {
            shared.text(x, c"class", &["POSIXct", "POSIXt"])?;
            if let Some(tz) = tz {
                shared.text(x, c"tzone", &[tz])?;
            }
        }
        Kind::Time { .. } => {
            shared.text(x, c"class", &["difftime"])?;
            shared.text(x, c"units", &["secs"])?;
        }
        Kind::Factor { levels, ordered, .. } => {
            let l = alloc_attr(x, c"levels", STRSXP, levels.len())?;
            set_strs(l, levels)?;
            if *ordered {
                shared.text(x, c"class", &["ordered", "factor"])?;
            } else {
                shared.text(x, c"class", &["factor"])?;
            }
        }
        Kind::Int64(Int64Mode::Integer64) => shared.text(x, c"class", &["integer64"])?,
        Kind::Integer | Kind::Double { .. } | Kind::Int64(Int64Mode::Double) => {
            if let Some((k, set)) = set {
                match shared.labels.get(&k) {
                    Some(&v) => set_attr(x, c"labels", v)?,
                    None => {
                        let v = set_labels(x, set)?;
                        shared.labels.insert(k, v);
                    }
                }
                shared.text(x, c"class", &["dtaparser_labelled", "vctrs_vctr"])?;
            }
        }
        _ => {}
    }
    Ok(())
}

/// The `labels` attribute: codes named by their text, in the order
/// dtaparser keeps them (numbers ascending, then `.`, then `.a` to `.z`).
/// Returns it.
fn set_labels(x: Sexp, set: &ValueLabelSet) -> Res<Sexp> {
    let mut labels: Vec<&ValueLabel> = set.labels.iter().collect();
    labels.sort_by(|a, b| {
        let key = |l: &ValueLabel| (l.missing != 0, l.missing);
        key(a).cmp(&key(b)).then(a.value.partial_cmp(&b.value).unwrap_or(std::cmp::Ordering::Equal))
    });
    // `.` (R's NA) sorts after the numbers and before `.a`, as order()
    // puts NA last among them.
    let codes = alloc_attr(x, c"labels", REALSXP, labels.len())?;
    let values: Vec<f64> = labels.iter().map(|l| super::r_double(l.value, l.missing)).collect();
    if !values.is_empty() {
        unsafe { slice_mut(REAL(codes), values.len()) }.copy_from_slice(&values);
    }
    let texts = alloc_attr(codes, c"names", STRSXP, labels.len())?;
    set_strs(texts, &labels.iter().map(|l| l.text.as_str()).collect::<Vec<_>>())?;
    Ok(codes)
}

// ---------------------------------------------------------------- write

/// Make the columns' fill functions callable from the writer's threads:
/// they read R vectors that stay alive and unchanged for the call (R
/// runs no code during it), through pointers taken on this thread.
#[derive(Clone, Copy)]
struct Shared<T>(T);
unsafe impl<T> Send for Shared<T> {}
unsafe impl<T> Sync for Shared<T> {}

impl<T: Copy> Shared<T> {
    /// The value; a closure calling this captures the whole wrapper, not
    /// the field inside it.
    #[inline]
    fn get(&self) -> T {
        self.0
    }
}

/// The missing code of an R double for the Parquet writer: 0 for a
/// number or NaN (a value), 1 for NA, 2 to 27 for a tagged `.a` to `.z`.
/// R calls a double NA when its low word is 1954, quieted or not.
#[inline]
fn r_code_parquet(x: f64) -> u8 {
    if !x.is_nan() {
        return 0;
    }
    let bits = x.to_bits();
    if bits as u32 != 1954 {
        return 0;
    }
    let tag = ((bits >> 32) & 0xff) as u8;
    if tag.is_ascii_lowercase() {
        tag - b'a' + 2
    } else {
        missing::SYSTEM
    }
}

/// The seconds a TIMESTAMP in microseconds gives back, as the reader
/// computes them.
#[inline]
fn seconds_of_micros(m: i64) -> f64 {
    m as f64 / 1e6
}

/// The microseconds of `s` seconds, if reading them back gives `s`
/// exactly.
#[inline]
fn exact_micros(s: f64) -> Option<i64> {
    let m = (s * 1e6).round();
    if !(m.abs() < 9.2e18) {
        return None;
    }
    let m = m as i64;
    (seconds_of_micros(m) == s).then_some(m)
}

/// # Safety
/// `x` is a vector alive for the call, of the type the accessor needs.
unsafe fn doubles<'a>(x: Sexp, n: usize) -> &'a [f64] {
    if n == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(REAL(x), n)
    }
}

unsafe fn ints<'a>(x: Sexp, n: usize) -> &'a [i32] {
    if n == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(if TYPEOF(x) == LGLSXP { LOGICAL(x) } else { INTEGER(x) }, n)
    }
}

/// An integer column's fill: NA is `.`.
fn int_fill<'a>(v: &'a [i32]) -> Box<dta_parquet::Fill<'a, i32>> {
    Box::new(move |first, values: &mut [i32], codes: &mut [u8]| {
        for (i, (d, c)) in values.iter_mut().zip(codes.iter_mut()).enumerate() {
            let x = v[first + i];
            if x == NA_INTEGER {
                *d = 0;
                *c = missing::SYSTEM;
            } else {
                *d = x;
                *c = 0;
            }
        }
    })
}

/// A double column's fill as type `T`, with `.a` to `.z` as codes.
fn double_fill<'a, T: Default + Copy + 'a>(v: &'a [f64], conv: impl Fn(f64) -> T + Sync + 'a) -> Box<dta_parquet::Fill<'a, T>> {
    Box::new(move |first, values: &mut [T], codes: &mut [u8]| {
        for (i, (d, c)) in values.iter_mut().zip(codes.iter_mut()).enumerate() {
            let x = v[first + i];
            let code = r_code_parquet(x);
            *c = code;
            *d = if code == 0 { conv(x) } else { T::default() };
        }
    })
}

/// The first row (0-based) of `v` that is a number but not one `ok`
/// accepts.
fn first_bad(v: &[f64], ok: impl Fn(f64) -> bool) -> Option<usize> {
    v.iter().position(|&x| r_code_parquet(x) == 0 && !ok(x))
}

/// Write the data frame `spec` describes (see datakit's save_parquet) to
/// `path` as Parquet.
///
/// # Safety
/// `spec` is the list save_parquet builds; the strings are NUL-terminated.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn dtaparser_parquet_write_rs(
    path: *const c_char,
    spec: Sexp,
    compression: *const c_char,
    level: c_int,
    has_level: c_int,
    row_group_size: f64,
    missing_letters: c_int,
    threads: c_int,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    let path = c_str(path).unwrap_or_default();
    let compression = CStr::from_ptr(compression).to_string_lossy().into_owned();
    guard(err, err_len, || {
        let compression = Compression::from_name(&compression)?;
        let options = WriteOptions {
            compression,
            compression_level: (has_level != 0).then_some(level),
            row_group_rows: (row_group_size.is_finite() && row_group_size >= 1.0).then_some(row_group_size as usize),
            missing_letters: missing_letters != 0,
            threads: threads.max(0) as usize,
            ..WriteOptions::default()
        };
        let table = table_of(spec)?;
        let file = std::fs::File::create(&path).map_err(|e| Fail::Message(format!("{path}: {e}")))?;
        let result = dta_parquet::write(&table, std::io::BufWriter::with_capacity(1 << 20, file), &options);
        if let Err(e) = result {
            let _ = std::fs::remove_file(&path);
            return Err(Fail::Message(e.to_string()));
        }
        Ok(())
    })
}

/// The table save_parquet's spec describes: list(columns, names, kinds,
/// labels, formats, label_sets, sets, tz, levels, ordered, label, notes,
/// characteristics, sort).
unsafe fn table_of<'a>(spec: Sexp) -> Res<Table<'a>> {
    let elt = |i: isize| VECTOR_ELT(spec, i);
    let columns = elt(0);
    let names = super::r_strings(elt(1));
    let kinds = super::r_strings(elt(2));
    let labels = super::r_strings(elt(3));
    let formats = super::r_strings(elt(4));
    let label_sets = super::r_strings(elt(5));
    let sets = elt(6);
    let tz = elt(7);
    let levels = elt(8);
    let ordered = elt(9);
    let rows = if names.is_empty() { 0 } else { Rf_xlength(VECTOR_ELT(columns, 0)).max(0) as usize };
    let mut profile = Profile::default();
    profile.label = super::r_strings(elt(10)).first().filter(|s| !s.is_empty()).map(|s| s.to_string());
    profile.notes = super::r_strings(elt(11)).iter().map(|s| s.to_string()).collect();
    let chars = elt(12);
    let (cv, cn, cx) = (
        super::r_strings(VECTOR_ELT(chars, 0)),
        super::r_strings(VECTOR_ELT(chars, 1)),
        super::r_strings(VECTOR_ELT(chars, 2)),
    );
    profile.characteristics = cv
        .iter()
        .zip(&cn)
        .zip(&cx)
        .map(|((v, n), x)| Characteristic { variable: v.to_string(), name: n.to_string(), value: x.to_string() })
        .collect();
    profile.sort = super::r_strings(elt(13)).iter().map(|s| s.to_string()).collect();
    for s in 0..Rf_xlength(sets).max(0) {
        let set = VECTOR_ELT(sets, s);
        let name = super::r_strings(VECTOR_ELT(set, 0)).first().copied().unwrap_or("").to_string();
        let codes = VECTOR_ELT(set, 1);
        let codes = doubles(codes, Rf_xlength(codes).max(0) as usize);
        let texts = super::r_strings(VECTOR_ELT(set, 2));
        let labels = codes
            .iter()
            .zip(texts)
            .map(|(&v, t)| {
                let m = r_code(v);
                ValueLabel { value: if m == 0 { v } else { f64::NAN }, missing: m, text: t.to_string() }
            })
            .collect();
        profile.value_labels.push(ValueLabelSet { name, labels });
    }

    let mut out = Vec::with_capacity(names.len());
    for (i, name) in names.iter().enumerate() {
        let x = VECTOR_ELT(columns, i as isize);
        if Rf_xlength(x).max(0) as usize != rows {
            return Err(Fail::Message("columns differ in length".into()));
        }
        // save_parquet checked the names are unique.
        profile.columns.push(dta_parquet::ColumnProfile::named(*name));
        let entry = profile.columns.last_mut().expect("just pushed");
        if !labels[i].is_empty() {
            entry.label = Some(labels[i].to_string());
        }
        if !formats[i].is_empty() {
            entry.format = Some(formats[i].to_string());
        }
        if !label_sets[i].is_empty() {
            entry.value_labels = Some(label_sets[i].to_string());
        }
        let zone = if TYPEOF(tz) == STRSXP && i < Rf_xlength(tz) as usize {
            let s = STRING_ELT(tz, i as isize);
            (s != R_NaString).then(|| super::r_string(tz, i)).map(|b| String::from_utf8_lossy(b).into_owned())
        } else {
            None
        };
        let bad = |what: &str, r: usize, v: f64| {
            Fail::Message(format!("column \"{name}\": row {} holds {v}, which {what}", r + 1))
        };
        let values: Values = match kinds[i] {
            "int8" | "int16" | "int32" if TYPEOF(x) == INTSXP || TYPEOF(x) == LGLSXP => {
                let f = int_fill(ints(x, rows));
                match kinds[i] {
                    "int8" => Values::Int8(f),
                    "int16" => Values::Int16(f),
                    _ => Values::Int32(f),
                }
            }
            "int8" | "int16" | "int32" => {
                let v = doubles(x, rows);
                let (lo, hi, what) = match kinds[i] {
                    "int8" => (-128.0, 127.0, "a byte column cannot hold"),
                    "int16" => (-32768.0, 32767.0, "an int column cannot hold"),
                    _ => (-2147483647.0, 2147483647.0, "a long column cannot hold"),
                };
                if let Some(r) = first_bad(v, |d| d.fract() == 0.0 && d >= lo && d <= hi) {
                    return Err(bad(what, r, v[r]));
                }
                let f = double_fill(v, |d| d as i32);
                match kinds[i] {
                    "int8" => Values::Int8(f),
                    "int16" => Values::Int16(f),
                    _ => Values::Int32(f),
                }
            }
            "float" => {
                let v = doubles(x, rows);
                if let Some(r) = first_bad(v, |d| (d as f32) as f64 == d || d.is_nan()) {
                    return Err(bad("a float column does not hold exactly", r, v[r]));
                }
                Values::Float(double_fill(v, |d| d as f32))
            }
            "double" => Values::Double(double_fill(doubles(x, rows), |d| d)),
            "int64" => {
                let v: &[i64] = if rows == 0 { &[] } else { std::slice::from_raw_parts(REAL(x) as *const i64, rows) };
                Values::Int64(Box::new(move |first, values: &mut [i64], codes: &mut [u8]| {
                    for (k, (d, c)) in values.iter_mut().zip(codes.iter_mut()).enumerate() {
                        let n = v[first + k];
                        (*d, *c) = if n == i64::MIN { (0, missing::SYSTEM) } else { (n, 0) };
                    }
                }))
            }
            "bool" => {
                let v = ints(x, rows);
                Values::Bool(Box::new(move |first, values: &mut [u8], codes: &mut [u8]| {
                    for (k, (d, c)) in values.iter_mut().zip(codes.iter_mut()).enumerate() {
                        let n = v[first + k];
                        (*d, *c) = if n == NA_INTEGER { (0, missing::SYSTEM) } else { ((n != 0) as u8, 0) };
                    }
                }))
            }
            "date" if TYPEOF(x) == INTSXP => Values::Date(int_fill(ints(x, rows))),
            "date" => {
                let v = doubles(x, rows);
                let whole = first_bad(v, |d| d.fract() == 0.0 && d.abs() <= i32::MAX as f64).is_none();
                if whole {
                    Values::Date(double_fill(v, |d| d as i32))
                } else {
                    // Fractions of a day, or what an INT32 cannot hold:
                    // days as doubles, a date again for our readers.
                    entry.logical = Some(Logical::Date);
                    Values::Double(double_fill(v, |d| d))
                }
            }
            "timestamp" => {
                let v = doubles(x, rows);
                let exact = first_bad(v, |d| exact_micros(d).is_some()).is_none();
                if exact {
                    Values::Timestamp {
                        unit: TimeUnit::Micros,
                        utc: true,
                        zone: zone.filter(|z| !z.is_empty()),
                        fill: double_fill(v, |d| exact_micros(d).unwrap_or(0)),
                    }
                } else {
                    // Seconds that whole microseconds do not give back
                    // exactly: kept as R holds them.
                    entry.logical = Some(Logical::Timestamp);
                    entry.tz = Some(zone.unwrap_or_default());
                    Values::Double(double_fill(v, |d| d))
                }
            }
            "text" => text_values(x, rows),
            "binary" => {
                let mut parts: Vec<Option<Shared<(*const u8, usize)>>> = Vec::with_capacity(rows);
                for r in 0..rows {
                    let e = VECTOR_ELT(x, r as isize);
                    parts.push(match TYPEOF(e) {
                        RAWSXP => {
                            let n = Rf_xlength(e).max(0) as usize;
                            Some(Shared((if n == 0 { std::ptr::NonNull::dangling().as_ptr() } else { RAW(e) as *const u8 }, n)))
                        }
                        0 => None,
                        _ => {
                            return Err(Fail::Message(format!(
                                "column \"{name}\": element {} is not a raw vector or NULL; a list column must hold only raw vectors",
                                r + 1
                            )))
                        }
                    });
                }
                Values::Binary(Box::new(move |r| parts[r].map(|Shared((p, n))| std::slice::from_raw_parts(p, n))))
            }
            "categorical" => {
                let v = ints(x, rows);
                let lv = VECTOR_ELT(levels, i as isize);
                let lv: Vec<String> = super::r_strings(lv).iter().map(|s| s.to_string()).collect();
                let ordered = LOGICAL(ordered).add(i).read() == 1;
                Values::Categorical {
                    levels: lv,
                    ordered,
                    codes: Box::new(move |first, codes: &mut [i32]| {
                        for (k, d) in codes.iter_mut().enumerate() {
                            let n = v[first + k];
                            *d = if n == NA_INTEGER { -1 } else { n - 1 };
                        }
                    }),
                }
            }
            other => return Err(Fail::Message(format!("internal: unknown column kind \"{other}\""))),
        };
        out.push(WriteColumn { name: name.to_string(), values });
    }
    Ok(Table { rows, columns: out, profile })
}

/// A character column for the writer. A packed column dtaparser read is
/// read from its bytes, so no R string is made; any other through the
/// CHARSXPs of its (materialised) data, whose bytes R_CHAR and the
/// length give without allocating, from the writer's threads too: they
/// only read memory that cannot change during the call.
unsafe fn text_values<'a>(x: Sexp, rows: usize) -> Values<'a> {
    let (mut bytes, mut ends, mut codes) = (std::ptr::null_mut(), std::ptr::null_mut(), std::ptr::null_mut());
    match super::dtaparser_packed_parts(x, &mut bytes, &mut ends, &mut codes) {
        1 => {
            let n = Rf_xlength(ends).max(0) as usize;
            let ends = Shared(if n == 0 { &[][..] } else { std::slice::from_raw_parts(REAL(ends) as *const f64, n) });
            let len = Rf_xlength(bytes).max(0) as usize;
            let text = Shared(if len == 0 { &[][..] } else { std::slice::from_raw_parts(RAW(bytes) as *const u8, len) });
            let codes = Shared((TYPEOF(codes) == INTSXP && rows > 0).then(|| std::slice::from_raw_parts(INTEGER(codes) as *const c_int, rows)));
            Values::Text(Box::new(move |r| {
                let (ends, text, codes) = (ends.get(), text.get(), codes.get());
                let j = match codes {
                    Some(c) if c[r] == NA_INTEGER => return None,
                    Some(c) => c[r] as usize,
                    None => r,
                };
                let from = if j == 0 { 0 } else { ends[j - 1] as usize };
                Some(&text[from..ends[j] as usize])
            }))
        }
        state => {
            let v = if state == 2 { bytes } else { x };
            let ptrs = Shared(if rows == 0 { &[][..] } else { std::slice::from_raw_parts(STRING_PTR_RO(v), rows) });
            let na = Shared(R_NaString);
            Values::Text(Box::new(move |r| {
                let s = ptrs.get()[r];
                if s == na.get() {
                    None
                } else {
                    Some(std::slice::from_raw_parts(R_CHAR(s) as *const u8, Rf_xlength(s).max(0) as usize))
                }
            }))
        }
    }
}
