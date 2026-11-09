//! What the Arrow path (`arrow::read`, for datakit's `read_parquet` and
//! `read_parquet_info`, plan 0019) shares about Parquet: opening a path,
//! bytes or another source (the binding's file objects); which Arrow type
//! each Parquet column becomes; picking the columns asked for; and the
//! names and messages reported. dta_parser itself reads no Parquet since
//! 0.3; the binding for R (r/dtaparser/src/rust/parquet_r.rs) is this
//! module's model.

use std::collections::HashMap;

use dta::{Bytes, FileSource, Source};
use dta_parquet::format::{converted, FileMetaData, LogicalType, TimeUnit};
use dta_parquet::{
    ColumnInfo, ColumnProfile, ColumnType, LevelsFrom, Logical, Output, Profile, ReadOptions, Reader, Role, Storage, TextChunk,
};

use super::error::{fail, Error, Result};

// ---------------------------------------------------------------- sources

/// A file read in blocks of 1 MiB, one per thread: a wide file has a
/// column chunk of a few kilobytes per column, and a system call for
/// each, from several threads at once, cost more than decoding them.
/// Reads of a quarter block or more go to the file directly. (The same
/// as dtaparser's, in r/dtaparser/src/rust/parquet_r.rs.)
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

/// A source given as a trait object (the binding's file objects).
pub struct DynSource<'a>(pub Box<dyn Source + Send + 'a>);

impl Source for DynSource<'_> {
    fn len(&self) -> u64 {
        self.0.len()
    }

    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> dta::Result<()> {
        self.0.read_at(offset, buf)
    }

    fn shared(&self) -> Option<&dyn dta::SharedSource> {
        self.0.shared()
    }
}

/// What the bridge needs of a reader, whatever its source.
pub trait Access: Send {
    fn columns(&self) -> &[ColumnInfo];
    fn profile(&self) -> Option<&Profile>;
    fn warnings(&self) -> &[String];
    fn rows(&self) -> u64;
    fn window(&self, skip: u64, n: u64) -> std::ops::Range<u64>;
    fn metadata(&self) -> &FileMetaData;
    fn row_groups(&self) -> Vec<dta_parquet::RowGroupInfo>;
    fn codecs(&self) -> Vec<dta_parquet::format::Codec>;
    fn created_by(&self) -> Option<&str>;
    fn label_set_spans(&self) -> (&[u8], &[dta_parquet::LabelSpan]);
    /// A categorical holding `.a` to `.z`'s value-label set, and a
    /// warning to pass on ([`Reader::categorical_labels`]).
    fn categorical_labels(&self, column: usize) -> Option<(dta::ValueLabelSet, Option<String>)>;
    fn read(
        &mut self,
        columns: &[usize],
        skip: u64,
        n: u64,
        outputs: &mut [Output<'_>],
        text: &mut dyn FnMut(usize, &TextChunk) -> dta::Result<()>,
    ) -> dta::Result<dta_parquet::ReadReport>;
}

impl<S: Source + Send> Access for Reader<S> {
    fn columns(&self) -> &[ColumnInfo] {
        Reader::columns(self)
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
    fn window(&self, skip: u64, n: u64) -> std::ops::Range<u64> {
        Reader::window(self, skip, n)
    }
    fn metadata(&self) -> &FileMetaData {
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
    fn label_set_spans(&self) -> (&[u8], &[dta_parquet::LabelSpan]) {
        Reader::label_set_spans(self)
    }
    fn categorical_labels(&self, column: usize) -> Option<(dta::ValueLabelSet, Option<String>)> {
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

/// Where a file comes from: a path, the whole file in memory, or another
/// source (a binary file object, which the binding wraps).
pub enum Input<'a> {
    Path(String),
    Bytes(&'a [u8]),
    Source(Box<dyn Source + Send + 'a>),
}

/// Open `input` and run `f` on its reader, which reads only the profile
/// entries of the columns in `selected` (all when `None`). From a path,
/// a `Value` error starts with the path.
pub fn with_reader_for<T>(
    input: Input<'_>,
    options: ReadOptions,
    selected: Option<&[&str]>,
    f: &mut dyn FnMut(&mut dyn Access) -> Result<T>,
) -> Result<T> {
    match input {
        Input::Path(p) => {
            let src = ReadAhead::open(&p).map_err(|e| fail(format!("{p}: {e}")))?;
            let mut r = Reader::open_for(src, options, selected).map_err(|e| fail(format!("{p}: {e}")))?;
            f(&mut r).map_err(|e| e.prefixed(&p))
        }
        Input::Bytes(b) => {
            let mut r = Reader::open_for(Bytes(b), options, selected).map_err(fail)?;
            f(&mut r)
        }
        Input::Source(s) => {
            let mut r = Reader::open_for(DynSource(s), options, selected).map_err(fail)?;
            f(&mut r)
        }
    }
}

// ---------------------------------------------------------------- types

/// What kind of column a selected Parquet column is, which `arrow::read`
/// turns into an Arrow type for polars.
#[derive(Clone, Debug, PartialEq)]
pub enum Kind {
    /// INT32, INT(8) or INT(16), by width in bytes.
    Int { width: u8 },
    /// Unsigned 8 to 64 bits, by width in bytes.
    UInt { width: u8 },
    Int64,
    Bool,
    Float32,
    /// DOUBLE, with the storage type or date or timestamp the profile
    /// gives one written wider for `.a` to `.z`.
    Double { storage: Option<Storage>, logical: Option<Logical> },
    /// DECIMAL of at most 15 digits, which a double holds exactly.
    DecimalFloat,
    /// DECIMAL of more digits.
    DecimalText,
    Date,
    /// TIMESTAMP (and INT96) in the file's unit, with a zone when
    /// adjusted to UTC.
    Timestamp { unit: TimeUnit, tz: Option<String> },
    /// TIME in the file's unit.
    Time { unit: TimeUnit },
    /// Text with levels: the profile's, or (`rows`) those of the rows read.
    Category { levels: Vec<String>, ordered: bool, rows: bool },
    /// A categorical holding `.a` to `.z` (plan 0022): DOUBLE level
    /// numbers from 1, the levels from the profile.
    LetterCategory { levels: Vec<String>, ordered: bool },
    Text,
    Binary,
}

/// The zone a timestamp reads with, for one adjusted to UTC: the
/// profile's (`""`, an instant written without one, reads as UTC), else
/// the one `ARROW:schema` gives, else UTC.
pub fn zone_of(col: &ColumnInfo, entry: Option<&ColumnProfile>) -> String {
    match entry.and_then(|p| p.tz.as_deref()) {
        Some(z) if !z.is_empty() => z.to_string(),
        Some(_) => "UTC".into(),
        None => col.zone.as_deref().filter(|z| !z.is_empty()).unwrap_or("UTC").to_string(),
    }
}

/// Whether every row group's statistics show column `leaf` has no null.
pub fn no_nulls(meta: &FileMetaData, col: &ColumnInfo) -> bool {
    if col.required {
        return true;
    }
    let leaf = col.leaf();
    meta.row_groups.iter().all(|g| {
        g.columns
            .get(leaf)
            .and_then(|c| c.meta.as_ref())
            .and_then(|m| m.statistics.as_ref())
            .and_then(|s| s.null_count)
            .is_some_and(|n| n == 0)
    })
}

pub fn kind_of(col: &ColumnInfo, entry: Option<&ColumnProfile>) -> std::result::Result<Kind, String> {
    Ok(match &col.kind {
        ColumnType::Int8 => Kind::Int { width: 1 },
        ColumnType::Int16 => Kind::Int { width: 2 },
        ColumnType::Int32 => Kind::Int { width: 4 },
        ColumnType::UInt8 => Kind::UInt { width: 1 },
        ColumnType::UInt16 => Kind::UInt { width: 2 },
        ColumnType::UInt32 => Kind::UInt { width: 4 },
        ColumnType::UInt64 => Kind::UInt { width: 8 },
        ColumnType::Int64 => Kind::Int64,
        ColumnType::Boolean => Kind::Bool,
        ColumnType::Float => Kind::Float32,
        ColumnType::Double => match (col.profile_logical, entry.and_then(|p| p.categorical.as_ref())) {
            // The core keeps `logical` categorical only beside valid levels.
            (Some(Logical::Categorical), Some(cat)) => {
                Kind::LetterCategory { levels: cat.levels.clone(), ordered: cat.ordered }
            }
            (Some(Logical::Categorical), None) => Kind::Double { storage: col.storage, logical: None },
            _ => Kind::Double { storage: col.storage, logical: col.profile_logical },
        },
        ColumnType::Decimal { precision, .. } => {
            if *precision as usize <= dta_parquet::decimal::DOUBLE_DIGITS {
                Kind::DecimalFloat
            } else {
                Kind::DecimalText
            }
        }
        ColumnType::Date => Kind::Date,
        ColumnType::Timestamp { unit, utc } => Kind::Timestamp {
            unit: *unit,
            tz: utc.then(|| zone_of(col, entry)),
        },
        ColumnType::Time { unit, .. } => Kind::Time { unit: *unit },
        ColumnType::Text => match (entry.and_then(|p| p.categorical.as_ref()), col.levels) {
            (Some(cat), _) => Kind::Category { levels: cat.levels.clone(), ordered: cat.ordered, rows: false },
            (None, Some(LevelsFrom::Rows)) => Kind::Category { levels: Vec::new(), ordered: false, rows: true },
            (None, _) => Kind::Text,
        },
        ColumnType::Binary => Kind::Binary,
        ColumnType::Unsupported(why) => return Err(format!("column \"{}\" is {why}", col.name)),
    })
}

pub fn logical_name(col: &ColumnInfo) -> Option<String> {
    let unit_name = |u: TimeUnit| match u {
        TimeUnit::Millis => "MILLIS",
        TimeUnit::Micros => "MICROS",
        TimeUnit::Nanos => "NANOS",
    };
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
        converted::UTF8 => "UTF8",
        converted::MAP => "MAP",
        converted::MAP_KEY_VALUE => "MAP_KEY_VALUE",
        converted::LIST => "LIST",
        converted::ENUM => "ENUM",
        converted::DECIMAL => "DECIMAL",
        converted::DATE => "DATE",
        converted::TIME_MILLIS => "TIME_MILLIS",
        converted::TIME_MICROS => "TIME_MICROS",
        converted::TIMESTAMP_MILLIS => "TIMESTAMP_MILLIS",
        converted::TIMESTAMP_MICROS => "TIMESTAMP_MICROS",
        converted::UINT_8 => "UINT_8",
        converted::UINT_16 => "UINT_16",
        converted::UINT_32 => "UINT_32",
        converted::UINT_64 => "UINT_64",
        converted::INT_8 => "INT_8",
        converted::INT_16 => "INT_16",
        converted::INT_32 => "INT_32",
        converted::INT_64 => "INT_64",
        converted::JSON => "JSON",
        converted::BSON => "BSON",
        converted::INTERVAL => "INTERVAL",
        _ => return None,
    };
    Some(name.into())
}

pub fn codec_name(c: dta_parquet::format::Codec) -> String {
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

// ---------------------------------------------------------------- profile

pub fn entries(profile: Option<&Profile>) -> HashMap<&str, &ColumnProfile> {
    profile.map_or_else(HashMap::new, |p| p.columns.iter().map(|c| (c.name.as_str(), c)).collect())
}

// ---------------------------------------------------------------- read

/// A column asked for: by name, by 0-based position among the data
/// columns, or by something that is neither (an error once the file is
/// open, as before the binding was split off).
#[derive(Clone, Debug, PartialEq)]
pub enum Selector {
    Name(String),
    Position(i64),
    Other,
}

/// The names asked for when every selector is a name.
pub fn names_of(wanted: Option<&[Selector]>) -> Option<Vec<&str>> {
    wanted?
        .iter()
        .map(|w| match w {
            Selector::Name(n) => Some(n.as_str()),
            _ => None,
        })
        .collect()
}

/// The columns asked for, as indices into the reader's columns.
pub fn select(r: &dyn Access, wanted: Option<&[Selector]>, nested_skip: bool) -> Result<Vec<usize>> {
    let cols = r.columns();
    let data: Vec<usize> = (0..cols.len()).filter(|&k| cols[k].role == Role::Data).collect();
    let Some(wanted) = wanted else {
        let nested: Vec<String> =
            cols.iter().filter(|c| c.role == Role::Nested).map(|c| format!("\"{}\"", c.name)).collect();
        if !nested.is_empty() && !nested_skip {
            return Err(fail(format!(
                "the file has nested columns, which are not read: {}; select the columns wanted, or pass nested=\"skip\"",
                nested.join(", ")
            )));
        }
        return Ok(data);
    };
    let by_name: HashMap<&str, usize> = cols.iter().enumerate().rev().map(|(k, c)| (c.name.as_str(), k)).collect();
    let mut out = Vec::with_capacity(wanted.len());
    for w in wanted {
        let k = match w {
            Selector::Name(name) => *by_name.get(name.as_str()).ok_or_else(|| {
                let shown: Vec<String> = cols.iter().take(20).map(|c| format!("\"{}\"", c.name)).collect();
                let more = if cols.len() > 20 { format!(" and {} more", cols.len() - 20) } else { String::new() };
                Error::Key(format!("column \"{name}\" is not in the file; its columns are {}{more}", shown.join(", ")))
            })?,
            Selector::Position(i) => *usize::try_from(*i).ok().and_then(|i| data.get(i)).ok_or_else(|| {
                Error::Index(format!("there is no column {i}; the file has {} data columns", data.len()))
            })?,
            Selector::Other => return Err(Error::Type("columns are names or 0-based positions".into())),
        };
        if cols[k].role == Role::Nested {
            return Err(fail(format!("column \"{}\" is nested (a list, map or group), which is not read", cols[k].name)));
        }
        if !out.contains(&k) {
            out.push(k);
        }
    }
    Ok(out)
}

/// The message of a read's error, with what Python offers instead.
pub fn read_error(m: String, decimal_names: &[String]) -> String {
    const DECIMAL: &str = "read the column as text to keep every digit";
    if decimal_names.iter().any(|n| m.starts_with(n.as_str())) && m.contains(DECIMAL) {
        return m.replace(DECIMAL, "this should not happen for a DECIMAL of 15 digits or fewer");
    }
    m
}
