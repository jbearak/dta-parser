//! What the Arrow path (`arrow::read`, for datakit's `read_parquet` and
//! `read_parquet_info`, plan 0019) shares about Parquet: opening a path,
//! a Python file or bytes; which Python type each Parquet column becomes;
//! picking the columns asked for; and the names and messages reported.
//! dta_parser itself reads no Parquet since 0.3; the binding for R
//! (r/dtaparser/src/rust/parquet_r.rs) is this module's model.

use std::collections::HashMap;

use pyo3::exceptions::{PyIndexError, PyKeyError, PyTypeError, PyValueError};
use pyo3::prelude::*;
use pyo3::types::{PyBytes, PyString};

use dta::{Bytes, FileSource, Source};
use dta_parquet::format::{converted, FileMetaData, LogicalType, TimeUnit};
use dta_parquet::{
    ColumnInfo, ColumnProfile, ColumnType, LevelsFrom, Logical, Output, Profile, ReadOptions, Reader, Role, Storage, TextChunk,
};

use super::fail;

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

/// A binary Python file object with `seek` and `read`, read on the
/// calling thread (it is not shared, so a read from one decodes on one
/// thread).
pub(crate) struct PyFile {
    file: Py<PyAny>,
    len: u64,
}

impl PyFile {
    pub(crate) fn new(file: &Bound<'_, PyAny>) -> PyResult<Self> {
        let len: u64 = file.call_method1("seek", (0, 2))?.extract()?;
        Ok(PyFile { file: file.clone().unbind(), len })
    }
}

impl Source for PyFile {
    fn len(&self) -> u64 {
        self.len
    }

    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> dta::Result<()> {
        Python::attach(|py| -> PyResult<()> {
            let f = self.file.bind(py);
            f.call_method1("seek", (offset,))?;
            let mut at = 0;
            while at < buf.len() {
                let got = f.call_method1("read", (buf.len() - at,))?;
                let got = got.cast::<PyBytes>().map_err(|_| PyTypeError::new_err("read() did not return bytes"))?;
                let b = got.as_bytes();
                if b.is_empty() {
                    return Err(PyValueError::new_err("the file ended early"));
                }
                buf[at..at + b.len()].copy_from_slice(b);
                at += b.len();
            }
            Ok(())
        })
        .map_err(|e| dta::Error::new(format!("reading the file object: {e}")))
    }
}

/// What the bridge needs of a reader, whatever its source.
pub(crate) trait Access: Send {
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

/// Where a file comes from: a path (`str`), the whole file (`bytes`), or
/// a binary file object.
enum Input<'a> {
    Path(String),
    Bytes(&'a [u8]),
    File(&'a Bound<'a, PyAny>),
}

fn input<'a>(source: &'a Bound<'a, PyAny>) -> PyResult<Input<'a>> {
    if let Ok(s) = source.cast::<PyString>() {
        return Ok(Input::Path(s.to_str()?.to_string()));
    }
    if let Ok(b) = source.cast::<PyBytes>() {
        return Ok(Input::Bytes(b.as_bytes()));
    }
    Ok(Input::File(source))
}

/// [`with_reader`], reading only the profile entries of the columns in
/// `selected` (all when `None`).
pub(crate) fn with_reader_for<T>(
    source: &Bound<'_, PyAny>,
    options: ReadOptions,
    selected: Option<&[&str]>,
    f: &mut dyn FnMut(&mut dyn Access) -> PyResult<T>,
) -> PyResult<T> {
    match input(source)? {
        Input::Path(p) => {
            let src = ReadAhead::open(&p).map_err(|e| fail(format!("{p}: {e}")))?;
            let mut r = Reader::open_for(src, options, selected).map_err(|e| fail(format!("{p}: {e}")))?;
            f(&mut r).map_err(|e| prefix(e, &p, source.py()))
        }
        Input::Bytes(b) => {
            let mut r = Reader::open_for(Bytes(b), options, selected).map_err(fail)?;
            f(&mut r)
        }
        Input::File(obj) => {
            let mut r = Reader::open_for(PyFile::new(obj)?, options, selected).map_err(fail)?;
            f(&mut r)
        }
    }
}

/// The error `e`, its message starting with the path when it is a
/// `ValueError` from the core.
fn prefix(e: PyErr, path: &str, py: Python<'_>) -> PyErr {
    if e.is_instance_of::<PyValueError>(py) {
        PyValueError::new_err(format!("{path}: {}", e.value(py)))
    } else {
        e
    }
}

// ---------------------------------------------------------------- types

/// What kind of column a selected Parquet column is, which `arrow::read`
/// turns into an Arrow type for polars.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Kind {
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

pub(crate) fn unit_code(u: TimeUnit) -> &'static str {
    match u {
        TimeUnit::Millis => "ms",
        TimeUnit::Micros => "us",
        TimeUnit::Nanos => "ns",
    }
}

/// The zone a timestamp reads with, for one adjusted to UTC: the
/// profile's (`""`, an instant written without one, reads as UTC), else
/// the one `ARROW:schema` gives, else UTC.
pub(crate) fn zone_of(col: &ColumnInfo, entry: Option<&ColumnProfile>) -> String {
    match entry.and_then(|p| p.tz.as_deref()) {
        Some(z) if !z.is_empty() => z.to_string(),
        Some(_) => "UTC".into(),
        None => col.zone.as_deref().filter(|z| !z.is_empty()).unwrap_or("UTC").to_string(),
    }
}

/// Whether every row group's statistics show column `leaf` has no null.
pub(crate) fn no_nulls(meta: &FileMetaData, col: &ColumnInfo) -> bool {
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

pub(crate) fn kind_of(col: &ColumnInfo, entry: Option<&ColumnProfile>) -> Result<Kind, String> {
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

pub(crate) fn logical_name(col: &ColumnInfo) -> Option<String> {
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

pub(crate) fn codec_name(c: dta_parquet::format::Codec) -> String {
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

pub(crate) fn entries(profile: Option<&Profile>) -> HashMap<&str, &ColumnProfile> {
    profile.map_or_else(HashMap::new, |p| p.columns.iter().map(|c| (c.name.as_str(), c)).collect())
}

// ---------------------------------------------------------------- read

/// The columns asked for, as indices into the reader's columns.
pub(crate) fn select(r: &dyn Access, wanted: Option<&[Bound<'_, PyAny>]>, nested_skip: bool) -> PyResult<Vec<usize>> {
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
        let k = if let Ok(name) = w.cast::<PyString>() {
            let name = name.to_str()?;
            *by_name.get(name).ok_or_else(|| {
                let shown: Vec<String> = cols.iter().take(20).map(|c| format!("\"{}\"", c.name)).collect();
                let more = if cols.len() > 20 { format!(" and {} more", cols.len() - 20) } else { String::new() };
                PyKeyError::new_err(format!(
                    "column \"{name}\" is not in the file; its columns are {}{more}",
                    shown.join(", ")
                ))
            })?
        } else {
            let i: i64 = w.extract().map_err(|_| PyTypeError::new_err("columns are names or 0-based positions"))?;
            *usize::try_from(i).ok().and_then(|i| data.get(i)).ok_or_else(|| {
                PyIndexError::new_err(format!("there is no column {i}; the file has {} data columns", data.len()))
            })?
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
pub(crate) fn read_error(m: String, decimal_names: &[String]) -> String {
    const DECIMAL: &str = "read the column as text to keep every digit";
    if decimal_names.iter().any(|n| m.starts_with(n.as_str())) && m.contains(DECIMAL) {
        return m.replace(DECIMAL, "this should not happen for a DECIMAL of 15 digits or fewer");
    }
    m
}
