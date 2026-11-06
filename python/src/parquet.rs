//! The Parquet half of the bridge (plan 0018): `read_parquet`,
//! `read_meta` and `write_parquet` in `dta_parser._parquet` reach these.
//!
//! Reads decode straight into numpy arrays that Python allocates before
//! the read (through the `alloc` callable), on the core's worker threads,
//! with the GIL released. Text arrives one column chunk at a time on the
//! calling thread: into Arrow buffers that pandas' `str` dtype holds
//! without a copy, or, where pandas keeps text as Python objects, into a
//! `str` per distinct value of each chunk. The rules of what each Parquet
//! type becomes are plan 0018's "Exactness" table, Python column; the
//! binding for R (r/dtaparser/src/rust/parquet_r.rs) is its model.

use std::collections::HashMap;
use std::ffi::c_char;
use std::slice;

use pyo3::exceptions::{PyIndexError, PyKeyError, PyTypeError, PyValueError};
use pyo3::ffi;
use pyo3::prelude::*;
use pyo3::types::{PyBytes, PyDict, PyList, PyString};

use dta::{missing, Bytes, Characteristic, FileSource, Source, ValueLabel, ValueLabelSet};
use dta_parquet::format::{converted, FileMetaData, LogicalType, TimeUnit};
use dta_parquet::{
    tagged_code, tagged_nan, ColumnInfo, ColumnProfile, ColumnType, Compression, Fill, LevelsFrom, Logical, Nested,
    Numbers, Output, Profile, ReadOptions, Reader, Role, Storage, Table, TextChunk, Values, WriteColumn, WriteOptions,
};

use super::{create_beside, fail, string_row, Recent};

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

/// Run `f` on the file opened as a Parquet reader; errors from a path
/// name it.
fn with_reader<T>(
    source: &Bound<'_, PyAny>,
    options: ReadOptions,
    f: &mut dyn FnMut(&mut dyn Access) -> PyResult<T>,
) -> PyResult<T> {
    with_reader_for(source, options, None, f)
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

/// What a selected column becomes in pandas.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Kind {
    /// INT32, INT(8) or INT(16): int32, int8 or int16, as Stata's long,
    /// byte and int; float64 or float32 when the rows read hold a null.
    /// `codes`: the footer does not rule out nulls, so the values are
    /// read straight into the float type, NaN for null, and made integers
    /// again after the read if no null was read.
    Int { width: u8, codes: bool },
    /// Unsigned 8 to 64 bits; with nulls float32, float64 or `UInt64`
    /// (read as for `Int`, but for 64 bits, read with a code per row).
    UInt { width: u8, codes: bool },
    /// INT64: int64; with nulls `Int64`.
    Int64 { codes: bool },
    /// bool; with nulls `boolean`.
    Bool { codes: bool },
    Float32,
    /// DOUBLE, with the storage type or date or timestamp the profile
    /// gives one written wider for `.a` to `.z`.
    Double { storage: Option<Storage>, logical: Option<Logical> },
    /// DECIMAL of at most 15 digits: float64.
    DecimalFloat,
    /// DECIMAL of more: `decimal.Decimal` objects.
    DecimalText,
    /// DATE: datetime64[s].
    Date,
    /// TIMESTAMP (and INT96): datetime64 in the file's unit, tz-aware
    /// when adjusted to UTC; `seconds` when the profile records unit `s`.
    Timestamp { unit: TimeUnit, tz: Option<String>, seconds: bool, codes: bool },
    /// TIME: timedelta64 in the file's unit.
    Time { unit: TimeUnit, codes: bool },
    Category { levels: Vec<String>, ordered: bool, rows: bool },
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

/// Whether every row group's statistics show a chunk with a null.
fn some_nulls(meta: &FileMetaData, col: &ColumnInfo) -> bool {
    let leaf = col.leaf();
    meta.row_groups.iter().any(|g| {
        g.columns
            .get(leaf)
            .and_then(|c| c.meta.as_ref())
            .and_then(|m| m.statistics.as_ref())
            .and_then(|s| s.null_count)
            .is_some_and(|n| n > 0)
    })
}

/// Whether the statistics of a row group that `window` takes whole show
/// a null in column `col`.
fn nulls_in(
    meta: &FileMetaData,
    col: &ColumnInfo,
    groups: &[dta_parquet::RowGroupInfo],
    window: &std::ops::Range<u64>,
) -> bool {
    let leaf = col.leaf();
    meta.row_groups.iter().zip(groups).any(|(g, info)| {
        info.first_row >= window.start
            && info.first_row + info.rows <= window.end
            && info.rows > 0
            && g.columns
                .get(leaf)
                .and_then(|c| c.meta.as_ref())
                .and_then(|m| m.statistics.as_ref())
                .and_then(|s| s.null_count)
                .is_some_and(|n| n > 0)
    })
}

/// Whether every row group's statistics show column `leaf`'s minimum
/// above -2^63, numpy's NaT, so no value is taken for a missing one.
fn min_ruled_out(meta: &FileMetaData, col: &ColumnInfo) -> bool {
    let leaf = col.leaf();
    meta.row_groups.iter().all(|g| {
        let Some(m) = g.columns.get(leaf).and_then(|c| c.meta.as_ref()) else { return false };
        let Some(s) = &m.statistics else { return false };
        match s.min_value.as_ref().or(s.min.as_ref()) {
            Some(b) if b.len() == 8 => i64::from_le_bytes(b[..8].try_into().unwrap_or_default()) > i64::MIN,
            Some(b) if b.len() == 4 => true,
            None => s.null_count.is_some_and(|n| n >= 0 && n == m.num_values),
            _ => false,
        }
    })
}

pub(crate) fn kind_of(col: &ColumnInfo, entry: Option<&ColumnProfile>, meta: &FileMetaData) -> Result<Kind, String> {
    let codes = || !no_nulls(meta, col);
    Ok(match &col.kind {
        ColumnType::Int8 => Kind::Int { width: 1, codes: codes() },
        ColumnType::Int16 => Kind::Int { width: 2, codes: codes() },
        ColumnType::Int32 => Kind::Int { width: 4, codes: codes() },
        ColumnType::UInt8 => Kind::UInt { width: 1, codes: codes() },
        ColumnType::UInt16 => Kind::UInt { width: 2, codes: codes() },
        ColumnType::UInt32 => Kind::UInt { width: 4, codes: codes() },
        ColumnType::UInt64 => Kind::UInt { width: 8, codes: codes() },
        ColumnType::Int64 => Kind::Int64 { codes: codes() },
        ColumnType::Boolean => Kind::Bool { codes: codes() },
        ColumnType::Float => Kind::Float32,
        ColumnType::Double => Kind::Double { storage: col.storage, logical: col.profile_logical },
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
            seconds: *unit == TimeUnit::Millis && entry.and_then(|e| e.unit.as_deref()) == Some("s"),
            codes: !min_ruled_out(meta, col),
        },
        ColumnType::Time { unit, .. } => Kind::Time {
            unit: *unit,
            codes: *unit != TimeUnit::Millis && !min_ruled_out(meta, col),
        },
        ColumnType::Text => match (entry.and_then(|p| p.categorical.as_ref()), col.levels) {
            (Some(cat), _) => Kind::Category { levels: cat.levels.clone(), ordered: cat.ordered, rows: false },
            (None, Some(LevelsFrom::Rows)) => Kind::Category { levels: Vec::new(), ordered: false, rows: true },
            (None, _) => Kind::Text,
        },
        ColumnType::Binary => Kind::Binary,
        ColumnType::Unsupported(why) => return Err(format!("column \"{}\" is {why}", col.name)),
    })
}

/// The dtype of the 2D array a column is read into with others of its
/// dtype, for the kinds whose values go straight into numpy memory.
fn block_dtype(kind: &Kind) -> Option<&'static str> {
    Some(match kind {
        Kind::Int { width: 1 | 2, codes: true } | Kind::UInt { width: 1 | 2, codes: true } | Kind::Float32 => {
            "float32"
        }
        Kind::Int { codes: true, .. } | Kind::UInt { width: 4, codes: true } => "float64",
        Kind::Double { storage: None, logical: None } | Kind::DecimalFloat => "float64",
        Kind::Int { width: 1, .. } => "int8",
        Kind::Int { width: 2, .. } => "int16",
        Kind::Int { .. } => "int32",
        Kind::UInt { width: 1, codes: false } => "uint8",
        Kind::UInt { width: 2, codes: false } => "uint16",
        Kind::UInt { width: 4, codes: false } => "uint32",
        Kind::UInt { width: 8, codes: false } => "uint64",
        Kind::Int64 { codes: false } => "int64",
        Kind::Bool { codes: false } => "bool",
        Kind::Date => "datetime64[s]",
        _ => return None,
    })
}

fn itemsize(dtype: &str) -> usize {
    match dtype {
        "int8" | "uint8" | "bool" => 1,
        "int16" | "uint16" => 2,
        "int32" | "uint32" | "float32" => 4,
        _ => 8,
    }
}

/// The pandas dtype a whole-file read gives a column, from the footer's
/// null counts.
fn dtype_name(col: &ColumnInfo, kind: &Kind, meta: &FileMetaData) -> String {
    let nulls = some_nulls(meta, col);
    match kind {
        Kind::Int { width: 1, .. } if nulls => "float32".into(),
        Kind::Int { width: 2, .. } if nulls => "float32".into(),
        Kind::Int { width: 4, .. } if nulls => "float64".into(),
        Kind::Int { width, .. } => format!("int{}", 8 * width),
        Kind::UInt { width: 1 | 2, .. } if nulls => "float32".into(),
        Kind::UInt { width: 4, .. } if nulls => "float64".into(),
        Kind::UInt { width: 8, .. } if nulls => "UInt64".into(),
        Kind::UInt { width, .. } => format!("uint{}", 8 * width),
        Kind::Int64 { .. } if nulls => "Int64".into(),
        Kind::Int64 { .. } => "int64".into(),
        Kind::Bool { .. } if nulls => "boolean".into(),
        Kind::Bool { .. } => "bool".into(),
        Kind::Float32 => "float32".into(),
        Kind::Double { storage: Some(s), .. } => format!("stata[{}]", s.name()),
        Kind::Double { logical: Some(_), .. } => "stata[double]".into(),
        Kind::Double { .. } | Kind::DecimalFloat => "float64".into(),
        Kind::DecimalText | Kind::Binary => "object".into(),
        Kind::Date => "datetime64[s]".into(),
        Kind::Timestamp { seconds: true, tz, .. } => datetime_name("s", tz),
        Kind::Timestamp { unit, tz, .. } => datetime_name(unit_code(*unit), tz),
        Kind::Time { unit, .. } => format!("timedelta64[{}]", unit_code(*unit)),
        Kind::Category { .. } => "category".into(),
        Kind::Text => "str".into(),
    }
}

fn datetime_name(unit: &str, tz: &Option<String>) -> String {
    match tz {
        Some(z) => format!("datetime64[{unit}, {z}]"),
        None => format!("datetime64[{unit}]"),
    }
}

/// The Stata storage type a column has in `attrs["dta"]`, where it has
/// one: from Parquet's type, or the profile's for a column written wider.
pub(crate) fn storage_name(kind: &Kind) -> Option<&'static str> {
    Some(match kind {
        Kind::Int { width: 1, .. } => "byte",
        Kind::Int { width: 2, .. } => "int",
        Kind::Int { .. } | Kind::Date => "long",
        Kind::Float32 => "float",
        Kind::Double { storage: Some(s), .. } => s.name(),
        Kind::Double { .. } | Kind::Timestamp { .. } => "double",
        Kind::Text => "str",
        Kind::Binary => "strL",
        _ => return None,
    })
}

fn logical_name(col: &ColumnInfo) -> Option<String> {
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

// ---------------------------------------------------------------- profile

/// The profile as a dict of plain Python values: label, timestamp,
/// notes, characteristics (variable, name, text), sort, value_labels (as
/// `read_dta` gives them in attrs: set name to {code: text}, a code an
/// int where it is whole, else a float, `.a` to `.z` as
/// `dta_parser.missing` values and `.` as NaN) and columns (name to a
/// dict of label, format, value_labels), for the columns `names` (all
/// when None).
fn profile_dict<'py>(py: Python<'py>, p: Option<&Profile>, names: Option<&[String]>) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    let Some(p) = p else {
        out.set_item("present", false)?;
        return Ok(out);
    };
    out.set_item("present", true)?;
    out.set_item("label", p.label.as_deref())?;
    out.set_item("timestamp", p.timestamp.as_deref())?;
    out.set_item("notes", &p.notes)?;
    let chars: Vec<(&str, &str, &str)> =
        p.characteristics.iter().map(|c| (c.variable.as_str(), c.name.as_str(), c.value.as_str())).collect();
    out.set_item("characteristics", chars)?;
    out.set_item("sort", &p.sort)?;
    let from_code = py.import("dta_parser.missing")?.getattr("from_code")?;
    let sets = PyDict::new(py);
    for set in &p.value_labels {
        let table = PyDict::new(py);
        for l in &set.labels {
            if l.missing != 0 {
                table.set_item(from_code.call1((l.missing,))?, &l.text)?;
            } else if l.value.fract() == 0.0 && l.value.abs() < 9.0e15 {
                table.set_item(l.value as i64, &l.text)?;
            } else {
                table.set_item(l.value, &l.text)?;
            }
        }
        sets.set_item(&set.name, table)?;
    }
    out.set_item("value_labels", sets)?;
    let cols = PyDict::new(py);
    let wanted: Option<std::collections::HashSet<&str>> = names.map(|n| n.iter().map(String::as_str).collect());
    for c in p.columns.iter().filter(|c| wanted.as_ref().is_none_or(|w| w.contains(c.name.as_str()))) {
        let d = PyDict::new(py);
        d.set_item("label", c.label.as_deref())?;
        d.set_item("format", c.format.as_deref())?;
        d.set_item("value_labels", c.value_labels.as_deref())?;
        cols.set_item(&c.name, d)?;
    }
    out.set_item("columns", cols)?;
    Ok(out)
}

/// A value label set as Python gets and gives it: (name, [(value,
/// missing code, text)]).
type LabelSet<S> = (S, Vec<(f64, u8, S)>);

/// Allocates a numpy array of a dtype for the read's rows: the array and
/// its data address.
type Alloc<'f> = dyn FnMut(&str) -> PyResult<(Py<PyAny>, usize)> + 'f;

pub(crate) fn entries(profile: Option<&Profile>) -> HashMap<&str, &ColumnProfile> {
    profile.map_or_else(HashMap::new, |p| p.columns.iter().map(|c| (c.name.as_str(), c)).collect())
}

// ---------------------------------------------------------------- meta

/// The footer of a Parquet file: rows, row_groups [(rows, compressed,
/// uncompressed)], created_by, compression, profile (see `profile_dict`),
/// columns [(name, role, physical_type, logical_type, dtype, storage,
/// profile storage, profile logical)] and warnings.
#[pyfunction]
pub fn parquet_meta<'py>(py: Python<'py>, source: &Bound<'py, PyAny>) -> PyResult<Bound<'py, PyDict>> {
    let options = ReadOptions { threads: 1, nested: Nested::Skip, ..ReadOptions::default() };
    with_reader(source, options, &mut |r| {
        let out = PyDict::new(py);
        out.set_item("rows", r.rows())?;
        let groups: Vec<(u64, u64, u64)> =
            r.row_groups().iter().map(|g| (g.rows, g.compressed_bytes, g.uncompressed_bytes)).collect();
        out.set_item("row_groups", groups)?;
        out.set_item("created_by", r.created_by())?;
        let codecs: Vec<String> = r.codecs().into_iter().map(codec_name).collect();
        out.set_item("compression", codecs)?;
        out.set_item("profile", profile_dict(py, r.profile(), None)?)?;
        let by_name = entries(r.profile());
        let meta = r.metadata();
        let cols = PyList::empty(py);
        for c in r.columns() {
            let entry = by_name.get(c.name.as_str()).copied();
            let nested = c.role == Role::Nested;
            let kind = if nested { None } else { kind_of(c, entry, meta).ok() };
            cols.append((
                &c.name,
                if nested { "nested" } else { "data" },
                c.physical.map(|p| p.name()),
                logical_name(c),
                kind.as_ref().map(|k| dtype_name(c, k, meta)),
                kind.as_ref().and_then(storage_name),
                c.storage.map(|s| s.name()),
                c.profile_logical.map(|l| l.name()),
            ))?;
        }
        out.set_item("columns", cols)?;
        out.set_item("warnings", r.warnings())?;
        Ok(out)
    })
}

// ---------------------------------------------------------------- read

/// # Safety
/// `addr` points at `n` elements alive and not otherwise used while the
/// slice is.
unsafe fn slice_mut<'a, T>(addr: usize, n: usize) -> &'a mut [T] {
    if n == 0 {
        &mut []
    } else {
        slice::from_raw_parts_mut(addr as *mut T, n)
    }
}

/// A buffer of bytes made here, kept alive by the Python object that
/// pyarrow's `foreign_buffer` holds as its base.
#[pyclass(frozen, module = "dta_parser._native")]
pub struct Buffer {
    data: BufferData,
}

enum BufferData {
    Bytes(Vec<u8>),
    Offsets(Vec<i64>),
}

#[pymethods]
impl Buffer {
    /// The address of the first byte.
    #[getter]
    fn address(&self) -> usize {
        match &self.data {
            BufferData::Bytes(v) => v.as_ptr() as usize,
            BufferData::Offsets(v) => v.as_ptr() as usize,
        }
    }

    /// The size in bytes.
    #[getter]
    fn size(&self) -> usize {
        match &self.data {
            BufferData::Bytes(v) => v.len(),
            BufferData::Offsets(v) => v.len() * 8,
        }
    }
}

/// Text gathered as an Arrow `large_string` array: the values' bytes,
/// an offset per row and one more, and a validity bit per row once a
/// null is seen.
struct ArrowText {
    data: Vec<u8>,
    offsets: Vec<i64>,
    validity: Option<Vec<u8>>,
    nulls: usize,
    rows: usize,
}

impl ArrowText {
    fn new(rows: usize) -> Self {
        let mut offsets = Vec::with_capacity(rows + 1);
        offsets.push(0);
        ArrowText { data: Vec::new(), offsets, validity: None, nulls: 0, rows }
    }

    /// Mark row `r` (counted from the read's first) null.
    fn null(&mut self, r: usize) {
        let rows = self.rows;
        let v = self.validity.get_or_insert_with(|| vec![0xff; rows.div_ceil(8)]);
        v[r / 8] &= !(1u8 << (r % 8));
        self.nulls += 1;
    }

    fn add(&mut self, chunk: &TextChunk) {
        let first = chunk.first as usize;
        match &chunk.codes {
            Some(codes) => {
                // Each dictionary value's start and length, and the bytes
                // with room to copy 16 at a time past the last: most
                // survey text is short, and a copy call per row was most
                // of the time spent here.
                const WIDE: usize = 16;
                let n = chunk.ends.len();
                let spans: Vec<(usize, usize)> = (0..n)
                    .map(|i| {
                        let start = if i == 0 { 0 } else { chunk.ends[i - 1] };
                        (start, chunk.ends[i] - start)
                    })
                    .collect();
                let mut dict = Vec::with_capacity(chunk.bytes.len() + WIDE);
                dict.extend_from_slice(&chunk.bytes);
                dict.resize(chunk.bytes.len() + WIDE, 0);
                let total: usize =
                    codes.iter().map(|&c| if c == TextChunk::NULL { 0 } else { spans[c as usize].1 }).sum();
                let at = self.data.len();
                self.data.reserve(total + WIDE);
                self.offsets.reserve(codes.len());
                let mut end = at;
                let base = self.data.as_mut_ptr();
                for (i, &c) in codes.iter().enumerate() {
                    if c == TextChunk::NULL {
                        self.null(first + i);
                    } else {
                        let (start, len) = spans[c as usize];
                        // SAFETY: `data` has room for `total + WIDE` bytes
                        // past `at`, and `end + len <= at + total`; `dict`
                        // has WIDE bytes past every value's start.
                        unsafe {
                            let src = dict.as_ptr().add(start);
                            let dst = base.add(end);
                            if len <= WIDE {
                                std::ptr::copy_nonoverlapping(src, dst, WIDE);
                            } else {
                                std::ptr::copy_nonoverlapping(src, dst, len);
                            }
                        }
                        end += len;
                    }
                    self.offsets.push(end as i64);
                }
                // SAFETY: bytes `at..end` were written above.
                unsafe { self.data.set_len(end) };
            }
            None => {
                let base = self.data.len() as i64;
                self.data.extend_from_slice(&chunk.bytes);
                self.offsets.extend(chunk.ends.iter().map(|&e| base + e as i64));
                for (i, &m) in chunk.missing.iter().enumerate() {
                    if m != 0 {
                        self.null(first + i);
                    }
                }
            }
        }
    }
}

/// Text or bytes as Python objects in an object array, one object per
/// distinct value of a dictionary-encoded chunk.
struct Objects {
    /// The object array's data, as an address.
    out: usize,
    recent: Recent,
    /// Make `bytes`, not `str`.
    binary: bool,
}

impl Objects {
    /// # Safety
    /// The GIL is held; the array holds the read's rows.
    unsafe fn add(&mut self, py: Python<'_>, chunk: &TextChunk) -> PyResult<()> {
        let out = self.out as *mut *mut ffi::PyObject;
        let make = |recent: &mut Recent, b: &[u8], binary: bool| -> *mut ffi::PyObject {
            if binary {
                ffi::PyBytes_FromStringAndSize(b.as_ptr() as *const c_char, b.len() as ffi::Py_ssize_t)
            } else {
                recent.get(b)
            }
        };
        let put = |r: usize, obj: *mut ffi::PyObject| {
            let slot = out.add(chunk.first as usize + r);
            let old = *slot;
            *slot = obj;
            ffi::Py_XDECREF(old);
        };
        let binary = self.binary || !chunk.utf8;
        match &chunk.codes {
            Some(codes) => {
                let mut made: Vec<*mut ffi::PyObject> = vec![std::ptr::null_mut(); chunk.ends.len()];
                let mut result = Ok(());
                for (r, &c) in codes.iter().enumerate() {
                    if c == TextChunk::NULL {
                        continue;
                    }
                    let m = &mut made[c as usize];
                    if m.is_null() {
                        *m = if binary {
                            make(&mut self.recent, chunk.value(c as usize), true)
                        } else {
                            ffi::PyUnicode_FromStringAndSize(
                                chunk.value(c as usize).as_ptr() as *const c_char,
                                chunk.value(c as usize).len() as ffi::Py_ssize_t,
                            )
                        };
                        if m.is_null() {
                            result = Err(PyErr::fetch(py));
                            break;
                        }
                    }
                    ffi::Py_INCREF(*m);
                    put(r, *m);
                }
                for m in made {
                    if !m.is_null() {
                        ffi::Py_DECREF(m);
                    }
                }
                result
            }
            None => {
                for r in 0..chunk.rows {
                    if chunk.missing[r] != 0 {
                        continue;
                    }
                    let obj = make(&mut self.recent, chunk.value(r), binary);
                    if obj.is_null() {
                        return Err(PyErr::fetch(py));
                    }
                    put(r, obj);
                }
                Ok(())
            }
        }
    }
}

enum Sink {
    None,
    Arrow(ArrowText),
    Objects(Objects),
}

/// One selected column as it is read.
struct Col {
    index: usize,
    kind: Kind,
    /// The arrays allocated for it (values, then codes), and their
    /// addresses.
    arrays: Vec<Py<PyAny>>,
    addrs: Vec<usize>,
    /// The footer shows a null in a row group the read takes whole.
    nulls_known: bool,
}

impl Col {
    /// The values' address; 0 for text gathered outside numpy.
    fn values(&self) -> usize {
        self.addrs.first().copied().unwrap_or(0)
    }
    fn codes(&self) -> Option<usize> {
        self.addrs.get(1).copied()
    }
}

/// Read rows `skip..skip + n_max` of `columns` (names or positions of
/// data columns; every data column when None). `alloc(dtype, n)` returns
/// a new numpy array of `n` elements and its data address. `arrow_text`
/// gathers text into Arrow buffers; otherwise into `str` objects.
///
/// Returns a dict: rows, names, columns (one tuple per column; see
/// `finish`), profile (see `profile_dict`) and warnings.
#[pyfunction]
#[pyo3(signature = (source, columns, skip, n_max, nested_skip, alloc, arrow_text))]
#[allow(clippy::too_many_arguments)]
pub fn parquet_read<'py>(
    py: Python<'py>,
    source: &Bound<'py, PyAny>,
    columns: Option<Vec<Bound<'py, PyAny>>>,
    skip: u64,
    n_max: Option<u64>,
    nested_skip: bool,
    alloc: &Bound<'py, PyAny>,
    arrow_text: bool,
) -> PyResult<Bound<'py, PyDict>> {
    let options = ReadOptions {
        threads: 0,
        nested: if nested_skip { Nested::Skip } else { Nested::Error },
        ..ReadOptions::default()
    };
    // Columns chosen by name: read only their entries of the profile,
    // which for a survey file is mostly value labels of other columns.
    let names: Option<Vec<String>> =
        columns.as_ref().and_then(|c| c.iter().map(|w| w.extract::<String>().ok()).collect());
    let names: Option<Vec<&str>> = names.as_ref().map(|n| n.iter().map(String::as_str).collect());
    with_reader_for(source, options, names.as_deref(), &mut |r| {
        read_into(py, r, columns.as_deref(), skip, n_max, nested_skip, alloc, arrow_text)
    })
}

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

#[allow(clippy::too_many_arguments)]
fn read_into<'py>(
    py: Python<'py>,
    r: &mut dyn Access,
    wanted: Option<&[Bound<'py, PyAny>]>,
    skip: u64,
    n_max: Option<u64>,
    nested_skip: bool,
    alloc: &Bound<'py, PyAny>,
    arrow_text: bool,
) -> PyResult<Bound<'py, PyDict>> {
    let selected = select(r, wanted, nested_skip)?;
    let n = n_max.unwrap_or(u64::MAX);
    let window = r.window(skip, n);
    let rows = usize::try_from(window.end - window.start).map_err(|_| fail("too many rows to read at once"))?;
    let by_name = entries(r.profile());
    let meta = r.metadata();
    let infos = r.columns();

    let groups = r.row_groups();
    let mut cols: Vec<Col> = Vec::with_capacity(selected.len());
    let mut sinks: Vec<Sink> = Vec::with_capacity(selected.len());
    let mut make = |dtype: &str| -> PyResult<(Py<PyAny>, usize)> {
        let (a, addr): (Py<PyAny>, usize) = alloc.call1((dtype, rows, 0))?.extract()?;
        Ok((a, addr))
    };
    let kinds: Vec<Kind> = selected
        .iter()
        .map(|&c| kind_of(&infos[c], by_name.get(infos[c].name.as_str()).copied(), meta).map_err(fail))
        .collect::<PyResult<_>>()?;
    // Numbers of one dtype go into one 2D array, a column per row, as
    // pandas keeps them (its "blocks"); each block's columns, in order.
    let mut blocks: Vec<(&'static str, Vec<usize>)> = Vec::new();
    let block_of: Vec<Option<usize>> = kinds
        .iter()
        .enumerate()
        .map(|(k, kind)| {
            let dtype = block_dtype(kind)?;
            let b = match blocks.iter().position(|(d, _)| *d == dtype) {
                Some(b) => b,
                None => {
                    blocks.push((dtype, Vec::new()));
                    blocks.len() - 1
                }
            };
            blocks[b].1.push(k);
            Some(b)
        })
        .collect();
    let mut block_arrays: Vec<Py<PyAny>> = Vec::with_capacity(blocks.len());
    let mut block_views: Vec<(usize, Vec<Py<PyAny>>)> = Vec::with_capacity(blocks.len());
    for (dtype, members) in &blocks {
        let (a, addr, views): (Py<PyAny>, usize, Vec<Py<PyAny>>) =
            alloc.call1((*dtype, rows, members.len()))?.extract()?;
        block_arrays.push(a);
        block_views.push((addr, views));
    }
    for (k, (&c, kind)) in selected.iter().zip(kinds).enumerate() {
        let info = &infos[c];
        let mut col = Col {
            index: c,
            kind: kind.clone(),
            arrays: Vec::new(),
            addrs: Vec::new(),
            nulls_known: nulls_in(meta, info, &groups, &window),
        };
        let mut sink = Sink::None;
        let add = |col: &mut Col, dtype: &str| -> PyResult<()> {
            let (a, addr) = make(dtype)?;
            col.arrays.push(a);
            col.addrs.push(addr);
            Ok(())
        };
        if let Some(b) = block_of[k] {
            let j = blocks[b].1.iter().position(|&m| m == k).unwrap_or(0);
            let (addr, views) = &block_views[b];
            col.arrays.push(views[j].clone_ref(py));
            col.addrs.push(addr + j * rows * itemsize(blocks[b].0));
            cols.push(col);
            sinks.push(sink);
            continue;
        }
        match &kind {
            Kind::Int { width, codes: true } | Kind::UInt { width: width @ (1 | 2 | 4), codes: true } => {
                add(&mut col, if *width <= 2 { "float32" } else { "float64" })?
            }
            Kind::Int { width, .. } => add(&mut col, ["", "int8", "int16", "", "int32"][*width as usize])?,
            Kind::UInt { width, codes } => {
                add(&mut col, ["", "uint8", "uint16", "", "uint32", "", "", "", "uint64"][*width as usize])?;
                if *codes {
                    add(&mut col, "codes")?;
                }
            }
            Kind::Int64 { codes } => {
                add(&mut col, "int64")?;
                if *codes {
                    add(&mut col, "codes")?;
                }
            }
            Kind::Bool { codes } => {
                add(&mut col, "uint8")?;
                if *codes {
                    add(&mut col, "codes")?;
                }
            }
            Kind::Float32 => add(&mut col, "float32")?,
            Kind::Double { .. } | Kind::DecimalFloat => add(&mut col, "float64")?,
            Kind::Date | Kind::Timestamp { codes: false, .. } | Kind::Time { codes: false, .. } => {
                add(&mut col, "int64")?
            }
            Kind::Timestamp { codes: true, .. } | Kind::Time { codes: true, .. } => {
                add(&mut col, "int64")?;
                add(&mut col, "codes")?;
            }
            Kind::Category { .. } => add(&mut col, "int32")?,
            Kind::Text if arrow_text => sink = Sink::Arrow(ArrowText::new(rows)),
            Kind::Text | Kind::Binary | Kind::DecimalText => {
                add(&mut col, "object")?;
                sink = Sink::Objects(Objects {
                    out: col.addrs[0],
                    recent: Recent::new(),
                    binary: matches!(kind, Kind::Binary),
                });
            }
        }
        cols.push(col);
        sinks.push(sink);
    }

    // The outputs point into the arrays above, which Python holds (and
    // no other code sees) until the read returns.
    let mut outputs: Vec<Output> = Vec::with_capacity(cols.len());
    for col in &cols {
        let v = col.values();
        let codes = col.codes().map(|c| unsafe { slice_mut::<u8>(c, rows) });
        macro_rules! nums {
            ($t:ty, $null:expr) => {{
                let mut n = Numbers::new(unsafe { slice_mut::<$t>(v, rows) }, $null);
                if let Some(c) = codes {
                    n = n.with_codes(c);
                }
                n
            }};
        }
        outputs.push(match &col.kind {
            Kind::Int { width: 1 | 2, codes: true } | Kind::UInt { width: 1 | 2, codes: true } => {
                Output::Float32(nums!(f32, f32::NAN))
            }
            Kind::Int { codes: true, .. } | Kind::UInt { width: 4, codes: true } => Output::Float64(nums!(f64, f64::NAN)),
            Kind::Int { width: 1, .. } => Output::Int8(nums!(i8, 0)),
            Kind::Int { width: 2, .. } => Output::Int16(nums!(i16, 0)),
            Kind::Int { .. } => Output::Int32(nums!(i32, 0)),
            Kind::UInt { width: 1, .. } | Kind::Bool { .. } => Output::UInt8(nums!(u8, 0)),
            Kind::UInt { width: 2, .. } => Output::UInt16(nums!(u16, 0)),
            Kind::UInt { width: 4, .. } => Output::UInt32(nums!(u32, 0)),
            Kind::UInt { .. } => Output::UInt64(nums!(u64, 0)),
            Kind::Int64 { .. } => Output::Int64(nums!(i64, 0)),
            Kind::Float32 => Output::Float32(nums!(f32, f32::NAN)),
            Kind::Double { .. } | Kind::DecimalFloat => Output::Float64(
                Numbers::new(unsafe { slice_mut::<f64>(v, rows) }, f64::NAN)
                    .with_missing(|c| if c == missing::SYSTEM { f64::NAN } else { tagged_nan(c) }),
            ),
            Kind::Date | Kind::Timestamp { .. } | Kind::Time { .. } => Output::Int64(nums!(i64, i64::MIN)),
            Kind::Category { .. } => Output::Levels { codes: unsafe { slice_mut::<i32>(v, rows) }, base: 0, null: -1 },
            Kind::Text | Kind::Binary | Kind::DecimalText => Output::Text,
        });
    }

    let selected_ix: Vec<usize> = cols.iter().map(|c| c.index).collect();
    let names: Vec<String> = selected_ix.iter().map(|&c| infos[c].name.clone()).collect();
    let decimal_names: Vec<String> = cols
        .iter()
        .filter(|c| matches!(c.kind, Kind::DecimalFloat))
        .map(|c| format!("column \"{}\":", infos[c.index].name))
        .collect();
    drop(by_name);

    let mut failed: Option<PyErr> = None;
    let report = py.detach(|| {
        let mut text = |k: usize, chunk: &TextChunk| -> dta::Result<()> {
            match &mut sinks[k] {
                Sink::Arrow(a) => {
                    a.add(chunk);
                    Ok(())
                }
                Sink::Objects(o) => match Python::attach(|py| unsafe { o.add(py, chunk) }) {
                    Ok(()) => Ok(()),
                    Err(e) => {
                        failed = Some(e);
                        Err(dta::Error::new("stopped"))
                    }
                },
                Sink::None => Err(dta::Error::new("internal: text for a column that is not text")),
            }
        };
        r.read(&selected_ix, skip, n, &mut outputs, &mut text)
    });
    drop(outputs);
    if let Some(e) = failed {
        return Err(e);
    }
    let mut report = report.map_err(|e| fail(read_error(e.to_string(), &decimal_names)))?;

    let out = PyDict::new(py);
    let list = PyList::empty(py);
    for (k, (col, sink)) in cols.iter_mut().zip(sinks).enumerate() {
        if let Kind::Category { levels, rows: true, .. } = &mut col.kind {
            *levels = report.levels.get_mut(k).and_then(Option::take).unwrap_or_default();
        }
        list.append(finish(py, col, sink, &names[k], rows, report.letters[k], &mut make)?)?;
    }
    out.set_item("rows", rows)?;
    let block_list = PyList::empty(py);
    for (a, (_, members)) in block_arrays.into_iter().zip(&blocks) {
        block_list.append((a, members.clone()))?;
    }
    out.set_item("blocks", block_list)?;
    out.set_item("names", &names)?;
    out.set_item("columns", list)?;
    out.set_item("profile", profile_dict(py, r.profile(), Some(&names))?)?;
    out.set_item("warnings", r.warnings())?;
    let storage: Vec<Option<&str>> = cols.iter().map(|c| storage_name(&c.kind)).collect();
    out.set_item("storage", storage)?;
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

/// After the read: each column as a tuple for Python to make into a
/// pandas column:
///
/// - ("int", values, codes or None): an int8, int16 or int32 array, and
///   the codes of its nulls; Python widens to float where any is set.
/// - ("uint", values, codes or None), ("int64", values, codes or None),
///   ("bool", values as uint8, codes or None).
/// - ("float32", values).
/// - ("double", values, codes or None, storage or None, logical or None,
///   any NaN): codes only where the rows read hold `.a` to `.z`.
/// - ("datetime", int64 values, unit, zone or None), ("timedelta",
///   values, unit): NaT for nulls.
/// - ("category", int32 codes, levels, ordered).
/// - ("arrow_text", data, offsets, validity or None, null count): Buffers.
/// - ("objects", object array), ("decimal", object array of str).
#[allow(clippy::too_many_arguments)]
fn finish<'py>(
    py: Python<'py>,
    col: &mut Col,
    sink: Sink,
    name: &str,
    rows: usize,
    letters: bool,
    make: &mut Alloc<'_>,
) -> PyResult<Bound<'py, PyAny>> {
    let a0 = col.arrays.first().map(|a| a.bind(py).clone());
    let codes = col.arrays.get(1).map(|a| a.bind(py).clone());
    let check_nat = |col: &Col| -> PyResult<()> {
        if let Some(c) = col.codes() {
            let v = unsafe { slice_mut::<i64>(col.values(), rows) };
            let c = unsafe { slice_mut::<u8>(c, rows) };
            if let Some(i) = (0..rows).find(|&i| c[i] == 0 && v[i] == i64::MIN) {
                return Err(fail(format!(
                    "column \"{name}\": the value -9223372036854775808 in row {} cannot be held, since numpy uses it for NaT",
                    i + 1
                )));
            }
        }
        Ok(())
    };
    Ok(match &col.kind {
        Kind::Int { width, codes: true } | Kind::UInt { width: width @ (1 | 2 | 4), codes: true } => {
            let nulls = col.nulls_known
                || if *width <= 2 {
                    unsafe { slice_mut::<f32>(col.values(), rows) }.iter().any(|x| x.is_nan())
                } else {
                    unsafe { slice_mut::<f64>(col.values(), rows) }.iter().any(|x| x.is_nan())
                };
            let signed = matches!(col.kind, Kind::Int { .. });
            let int = format!("{}int{}", if signed { "" } else { "u" }, 8 * width);
            ("float_int", a0, nulls, int).into_pyobject(py)?.into_any()
        }
        Kind::Int { .. } => ("int", a0, codes).into_pyobject(py)?.into_any(),
        Kind::UInt { .. } => ("uint", a0, codes).into_pyobject(py)?.into_any(),
        Kind::Int64 { .. } => ("int64", a0, codes).into_pyobject(py)?.into_any(),
        Kind::Bool { .. } => ("bool", a0, codes).into_pyobject(py)?.into_any(),
        Kind::Float32 => ("float32", a0).into_pyobject(py)?.into_any(),
        Kind::DecimalFloat => ("double", a0, None::<Py<PyAny>>, None::<&str>, None::<&str>, true).into_pyobject(py)?.into_any(),
        Kind::Double { storage, logical } => {
            let v = unsafe { slice_mut::<f64>(col.values(), rows) };
            let mut codes_arr: Option<Py<PyAny>> = None;
            let mut nan = false;
            if letters {
                let (arr, addr) = make("codes")?;
                let c = unsafe { slice_mut::<u8>(addr, rows) };
                for (x, c) in v.iter_mut().zip(c.iter_mut()) {
                    if x.is_nan() {
                        let t = tagged_code(*x);
                        *c = if t >= 2 { t } else { missing::SYSTEM };
                        *x = f64::NAN;
                        nan = true;
                    }
                }
                codes_arr = Some(arr);
            } else if matches!(storage, Some(Storage::Byte | Storage::Int | Storage::Long))
                || logical.is_some()
            {
                // Only these need it (integers again, or dates); a scan
                // of every double on this thread was a third of a
                // threaded read of wide.dta.
                nan = v.iter().any(|x| x.is_nan());
            }
            (
                "double",
                a0,
                codes_arr,
                storage.map(|s| s.name()),
                logical.map(|l| l.name()),
                nan,
            )
                .into_pyobject(py)?
                .into_any()
        }
        Kind::Date => {
            for d in unsafe { slice_mut::<i64>(col.values(), rows) } {
                if *d != i64::MIN {
                    *d *= 86_400;
                }
            }
            ("datetime", a0, "s", None::<&str>).into_pyobject(py)?.into_any()
        }
        Kind::Timestamp { unit, tz, seconds, .. } => {
            check_nat(col)?;
            let v = unsafe { slice_mut::<i64>(col.values(), rows) };
            let whole = *seconds && v.iter().all(|&x| x == i64::MIN || x % 1000 == 0);
            let unit = if whole {
                for x in v.iter_mut() {
                    if *x != i64::MIN {
                        *x /= 1000;
                    }
                }
                "s"
            } else {
                unit_code(*unit)
            };
            ("datetime", a0, unit, tz.clone()).into_pyobject(py)?.into_any()
        }
        Kind::Time { unit, .. } => {
            check_nat(col)?;
            ("timedelta", a0, unit_code(*unit)).into_pyobject(py)?.into_any()
        }
        Kind::Category { levels, ordered, .. } => {
            ("category", a0, levels.clone(), *ordered).into_pyobject(py)?.into_any()
        }
        Kind::Text | Kind::Binary | Kind::DecimalText => match sink {
            Sink::Arrow(t) => {
                let validity = t.validity.map(|v| Buffer { data: BufferData::Bytes(v) });
                (
                    "arrow_text",
                    Buffer { data: BufferData::Bytes(t.data) },
                    Buffer { data: BufferData::Offsets(t.offsets) },
                    validity,
                    t.nulls,
                )
                    .into_pyobject(py)?
                    .into_any()
            }
            _ if matches!(col.kind, Kind::DecimalText) => ("decimal", a0).into_pyobject(py)?.into_any(),
            _ => ("objects", a0).into_pyobject(py)?.into_any(),
        },
    })
}

// ---------------------------------------------------------------- write

/// A number type of a source array, converted to the type written. The
/// Python side has checked each value fits.
trait FromSource: Copy + Default + Send + Sync + 'static {
    fn from_i64(v: i64) -> Self;
    fn from_u64(v: u64) -> Self;
    fn from_f64(v: f64) -> Self;
}

macro_rules! from_source {
    ($t:ty) => {
        impl FromSource for $t {
            #[inline]
            fn from_i64(v: i64) -> Self {
                v as $t
            }
            #[inline]
            fn from_u64(v: u64) -> Self {
                v as $t
            }
            #[inline]
            fn from_f64(v: f64) -> Self {
                v as $t
            }
        }
    };
}
from_source!(i32);
from_source!(i64);
from_source!(f32);
from_source!(f64);
from_source!(u8);

/// The fill of a numeric column from a numpy buffer of dtype `dtype`
/// (`i1` ... `u8`, `f4`, `f8`, `b1`) at `addr`, with a missing code per
/// row at `codes` (0 for none). In a float buffer without a code, NaN is
/// a null.
///
/// # Safety
/// The buffers hold `nobs` elements, alive and unchanged for the write.
unsafe fn numbers<'a, T: FromSource>(dtype: &str, addr: usize, codes: usize, nobs: usize) -> Result<Box<Fill<'a, T>>, String> {
    let codes: Option<&'a [u8]> = (codes != 0 && nobs > 0).then(|| slice::from_raw_parts(codes as *const u8, nobs));
    macro_rules! fill {
        ($s:ty, $conv:expr, $nan:expr) => {{
            let x: &'a [$s] = if nobs == 0 { &[] } else { slice::from_raw_parts(addr as *const $s, nobs) };
            let f: Box<Fill<'a, T>> = Box::new(move |first, values: &mut [T], out: &mut [u8]| {
                for (i, (v, o)) in values.iter_mut().zip(out.iter_mut()).enumerate() {
                    let r = first + i;
                    let c = match codes {
                        Some(c) => c[r],
                        None => 0,
                    };
                    if c != 0 {
                        *v = T::default();
                        *o = c;
                    } else if $nan(x[r]) {
                        *v = T::default();
                        *o = missing::SYSTEM;
                    } else {
                        *v = $conv(x[r]);
                        *o = 0;
                    }
                }
            });
            f
        }};
    }
    Ok(match dtype {
        "i1" => fill!(i8, |v: i8| T::from_i64(v as i64), |_| false),
        "i2" => fill!(i16, |v: i16| T::from_i64(v as i64), |_| false),
        "i4" => fill!(i32, |v: i32| T::from_i64(v as i64), |_| false),
        "i8" => fill!(i64, T::from_i64, |_| false),
        "u1" | "b1" => fill!(u8, |v: u8| T::from_u64(v as u64), |_| false),
        "u2" => fill!(u16, |v: u16| T::from_u64(v as u64), |_| false),
        "u4" => fill!(u32, |v: u32| T::from_u64(v as u64), |_| false),
        "u8" => fill!(u64, T::from_u64, |_| false),
        "f4" => fill!(f32, |v: f32| T::from_f64(v as f64), |v: f32| v.is_nan()),
        "f8" => fill!(f64, T::from_f64, |v: f64| v.is_nan()),
        other => return Err(format!("cannot write numbers of dtype {other}")),
    })
}

/// One chunk of an Arrow string array: validity bitmap (0 for none),
/// offsets, offsets' width (4 or 8), data, length and offset.
type ArrowChunk = (usize, usize, u8, usize, usize, usize);

/// Text from Arrow string arrays, read in place.
///
/// # Safety
/// The arrays' buffers stay alive and unchanged for the write.
unsafe fn arrow_text<'a>(chunks: Vec<ArrowChunk>) -> Box<dta_parquet::GetBytes<'a>> {
    // One chunk (pandas' usual case): no search for the row's chunk.
    if let [(validity, offsets, width, data, _, offset)] = chunks[..] {
        return Box::new(move |r: usize| arrow_value(validity, offsets, width, data, r + offset));
    }
    let mut starts = Vec::with_capacity(chunks.len());
    let mut at = 0usize;
    for c in &chunks {
        starts.push(at);
        at += c.4;
    }
    Box::new(move |r: usize| {
        let k = starts.partition_point(|&s| s <= r) - 1;
        let (validity, offsets, width, data, _, offset) = chunks[k];
        arrow_value(validity, offsets, width, data, r - starts[k] + offset)
    })
}

/// Value `i` of an Arrow string array's buffers.
///
/// # Safety
/// The buffers hold value `i`, alive for `'a`.
#[inline]
unsafe fn arrow_value<'a>(validity: usize, offsets: usize, width: u8, data: usize, i: usize) -> Option<&'a [u8]> {
    if validity != 0 {
        let byte = *(validity as *const u8).add(i / 8);
        if byte & (1 << (i % 8)) == 0 {
            return None;
        }
    }
    let (from, to) = if width == 8 {
        let o = offsets as *const i64;
        (*o.add(i) as usize, *o.add(i + 1) as usize)
    } else {
        let o = offsets as *const i32;
        (*o.add(i) as usize, *o.add(i + 1) as usize)
    };
    Some(if to == from { &[][..] } else { slice::from_raw_parts((data as *const u8).add(from), to - from) })
}

/// (name, kind, data address, dtype, codes address, extra): see
/// `_parquet.py`'s `_column`.
type WriteSpec<'py> = (String, String, usize, String, usize, Bound<'py, PyAny>);

/// Write the DataFrame `columns` describe as Parquet, to `path`, or
/// return it as `bytes` when `path` is None. `profile` gives label,
/// timestamp, notes, characteristics [(variable, name, text)], sort,
/// value_labels [(name, [(value, code, text)])] and columns [(name,
/// label, format, value_labels, unit)].
#[pyfunction]
#[pyo3(signature = (path, nobs, columns, profile, compression, compression_level, row_group_size, missing_letters))]
#[allow(clippy::too_many_arguments)]
pub fn parquet_write<'py>(
    py: Python<'py>,
    path: Option<String>,
    nobs: usize,
    columns: Vec<WriteSpec<'py>>,
    profile: &Bound<'py, PyDict>,
    compression: &str,
    compression_level: Option<i32>,
    row_group_size: Option<usize>,
    missing_letters: bool,
) -> PyResult<Option<Bound<'py, PyBytes>>> {
    let compression = Compression::from_name(compression).map_err(fail)?;
    let options = WriteOptions {
        compression,
        compression_level,
        row_group_rows: row_group_size,
        missing_letters,
        ..WriteOptions::default()
    };
    let get = |k: &str| -> PyResult<Bound<'py, PyAny>> {
        profile.get_item(k)?.ok_or_else(|| fail(format!("internal: no {k} in the profile")))
    };
    let mut p = Profile {
        label: get("label")?.extract()?,
        timestamp: get("timestamp")?.extract()?,
        notes: get("notes")?.extract()?,
        sort: get("sort")?.extract()?,
        ..Profile::default()
    };
    let chars: Vec<(String, String, String)> = get("characteristics")?.extract()?;
    p.characteristics = chars.into_iter().map(|(variable, name, value)| Characteristic { variable, name, value }).collect();
    let sets: Vec<LabelSet<String>> = get("value_labels")?.extract()?;
    p.value_labels = sets
        .into_iter()
        .map(|(name, labels)| ValueLabelSet {
            name,
            labels: labels.into_iter().map(|(value, missing, text)| ValueLabel { value, missing, text }).collect(),
        })
        .collect();
    type Entry = (String, Option<String>, Option<String>, Option<String>, Option<String>);
    let entries: Vec<Entry> = get("columns")?.extract()?;
    for (name, label, format, value_labels, unit) in entries {
        p.columns.push(ColumnProfile { name, label, format, value_labels, unit, ..ColumnProfile::default() });
    }

    let mut out = Vec::with_capacity(columns.len());
    for (name, kind, addr, dtype, codes, extra) in columns {
        let at = |e: PyErr| fail(format!("column \"{name}\": {e}"));
        let values = unsafe {
            match kind.as_str() {
                "int8" => Values::Int8(numbers(&dtype, addr, codes, nobs).map_err(fail)?),
                "int16" => Values::Int16(numbers(&dtype, addr, codes, nobs).map_err(fail)?),
                "int32" => Values::Int32(numbers(&dtype, addr, codes, nobs).map_err(fail)?),
                "int64" => Values::Int64(numbers(&dtype, addr, codes, nobs).map_err(fail)?),
                "float" => Values::Float(numbers(&dtype, addr, codes, nobs).map_err(fail)?),
                "double" => Values::Double(numbers(&dtype, addr, codes, nobs).map_err(fail)?),
                "bool" => Values::Bool(numbers(&dtype, addr, codes, nobs).map_err(fail)?),
                "date" => Values::Date(numbers(&dtype, addr, codes, nobs).map_err(fail)?),
                "timestamp" => {
                    let (unit, utc, zone, scale): (String, bool, Option<String>, i64) = extra.extract().map_err(at)?;
                    let unit = match unit.as_str() {
                        "ms" => TimeUnit::Millis,
                        "us" => TimeUnit::Micros,
                        _ => TimeUnit::Nanos,
                    };
                    let x: &[i64] = if nobs == 0 { &[] } else { slice::from_raw_parts(addr as *const i64, nobs) };
                    let fill: Box<Fill<i64>> = Box::new(move |first, values: &mut [i64], out: &mut [u8]| {
                        for (i, (v, o)) in values.iter_mut().zip(out.iter_mut()).enumerate() {
                            let t = x[first + i];
                            (*v, *o) = if t == i64::MIN { (0, missing::SYSTEM) } else { (t * scale, 0) };
                        }
                    });
                    Values::Timestamp { unit, utc, zone, fill }
                }
                "category" => {
                    let (levels, ordered): (Vec<String>, bool) = extra.extract().map_err(at)?;
                    let codes = numbers::<i32>(&dtype, addr, 0, nobs).map_err(fail)?;
                    Values::Categorical {
                        levels,
                        ordered,
                        codes: Box::new(move |first, out: &mut [i32]| {
                            let mut flags = vec![0u8; out.len()];
                            codes(first, out, &mut flags);
                        }),
                    }
                }
                "arrow_text" => {
                    let chunks: Vec<ArrowChunk> = extra.extract().map_err(at)?;
                    Values::Text(arrow_text(chunks))
                }
                "objects" => {
                    let rows = addr as *const *mut ffi::PyObject;
                    let binary = check_objects(py, &name, rows, nobs)?;
                    let rows = rows as usize;
                    let get = move |r: usize| -> Option<&[u8]> {
                        let obj = *(rows as *const *mut ffi::PyObject).add(r);
                        if obj == ffi::Py_None() {
                            None
                        } else {
                            Some(string_row(obj).0)
                        }
                    };
                    if binary {
                        Values::Binary(Box::new(get))
                    } else {
                        Values::Text(Box::new(get))
                    }
                }
                other => return Err(fail(format!("internal: unknown column kind \"{other}\""))),
            }
        };
        out.push(WriteColumn { name, values });
    }
    let table = Table { rows: nobs, columns: out, profile: p };
    match path {
        None => {
            let mut buf = Vec::new();
            dta_parquet::write(&table, &mut buf, &options).map_err(fail)?;
            Ok(Some(PyBytes::new(py, &buf)))
        }
        Some(path) => {
            // Write beside the target and rename, so a failed write leaves
            // any existing file as it was.
            let (tmp, file) = create_beside(&path).map_err(|e| fail(format!("{path}: {e}")))?;
            let result = dta_parquet::write(&table, std::io::BufWriter::with_capacity(1 << 20, file), &options);
            if let Err(e) = result {
                let _ = std::fs::remove_file(&tmp);
                return Err(fail(e.to_string()));
            }
            std::fs::rename(&tmp, &path).map_err(|e| {
                let _ = std::fs::remove_file(&tmp);
                fail(format!("{path}: {e}"))
            })?;
            Ok(None)
        }
    }
}

/// Check every row of an object column is a `str` (with a UTF-8 form),
/// a `bytes` or None (a null); returns whether any is a `bytes`.
///
/// # Safety
/// The GIL is held; `rows` holds `nobs` objects.
unsafe fn check_objects(py: Python<'_>, name: &str, rows: *const *mut ffi::PyObject, nobs: usize) -> PyResult<bool> {
    let mut any_binary = false;
    for r in 0..nobs {
        let obj = *rows.add(r);
        if obj == ffi::Py_None() {
            continue;
        }
        if ffi::PyBytes_Check(obj) != 0 {
            any_binary = true;
        } else if ffi::PyUnicode_Check(obj) != 0 {
            let mut n: ffi::Py_ssize_t = 0;
            if ffi::PyUnicode_AsUTF8AndSize(obj, &mut n).is_null() {
                let e = PyErr::fetch(py);
                return Err(fail(format!("column \"{name}\": row {}: {e}", r + 1)));
            }
        } else {
            let value = Bound::from_borrowed_ptr(py, obj);
            let kind = value.get_type().name()?;
            return Err(PyTypeError::new_err(format!(
                "column \"{name}\": row {} holds a {kind}; a text column holds str, bytes or missing values",
                r + 1
            )));
        }
    }
    Ok(any_binary)
}

/// Whether every value of each numeric column fits a Stata storage type,
/// as `write_dta` checks it (`_write._fits`): `checks` holds (data
/// address, dtype `f4` or `f8`, codes address or 0, storage). Values with
/// a missing code, and NaN, are not checked.
#[pyfunction]
pub fn parquet_fits(checks: Vec<(usize, String, usize, String)>, nobs: usize) -> PyResult<Vec<bool>> {
    checks
        .into_iter()
        .map(|(addr, dtype, codes, storage)| {
            if nobs == 0 {
                return Ok(true);
            }
            let codes: Option<&[u8]> = (codes != 0).then(|| unsafe { slice::from_raw_parts(codes as *const u8, nobs) });
            match dtype.as_str() {
                "f4" => {
                    let x = unsafe { slice::from_raw_parts(addr as *const f32, nobs) };
                    fits_storage(x, codes, &storage)
                }
                "f8" => {
                    let x = unsafe { slice::from_raw_parts(addr as *const f64, nobs) };
                    fits_storage(x, codes, &storage)
                }
                other => Err(fail(format!("internal: fits takes floats, not {other}"))),
            }
        })
        .collect()
}

/// A float type of a source array.
trait Float: Copy {
    fn f64(self) -> f64;
}
impl Float for f32 {
    #[inline]
    fn f64(self) -> f64 {
        f64::from(self)
    }
}
impl Float for f64 {
    #[inline]
    fn f64(self) -> f64 {
        self
    }
}

/// Whether every value of `x` without a code is NaN or `ok`. Without an
/// early exit, so the loop vectorises: values almost always fit.
fn all_ok<T: Float>(x: &[T], codes: Option<&[u8]>, ok: impl Fn(f64) -> bool) -> bool {
    let mut good = true;
    match codes {
        Some(c) => {
            for (v, &c) in x.iter().zip(c) {
                let v = v.f64();
                good &= (c != 0) | v.is_nan() | ok(v);
            }
        }
        None => {
            for v in x {
                let v = v.f64();
                good &= v.is_nan() | ok(v);
            }
        }
    }
    good
}

fn fits_storage<T: Float>(x: &[T], codes: Option<&[u8]>, storage: &str) -> PyResult<bool> {
    let whole_in = |lo: f64, hi: f64| move |v: f64| (v.trunc() == v) & (v >= lo) & (v <= hi);
    Ok(match storage {
        "byte" => all_ok(x, codes, whole_in(-127.0, 100.0)),
        "int" => all_ok(x, codes, whole_in(-32767.0, 32740.0)),
        "long" => all_ok(x, codes, whole_in(-2_147_483_647.0, 2_147_483_620.0)),
        "float" => {
            let max = f64::from(f32::from_bits(0x7EFF_FFFF));
            all_ok(x, codes, |v| (v.abs() <= max) & (f64::from(v as f32) == v))
        }
        "double" => {
            let max = f64::from_bits(0x7FDF_FFFF_FFFF_FFFF);
            all_ok(x, codes, |v| v.abs() <= max)
        }
        other => return Err(fail(format!("internal: unknown storage type {other}"))),
    })
}

/// The first four bytes of a source: `PAR1` for Parquet.
#[pyfunction]
pub fn magic<'py>(py: Python<'py>, source: &Bound<'py, PyAny>) -> PyResult<Bound<'py, PyBytes>> {
    let mut head = [0u8; 4];
    let n = match input(source)? {
        Input::Path(p) => {
            use std::io::Read;
            let mut f = std::fs::File::open(&p).map_err(|e| fail(format!("{p}: {e}")))?;
            f.read(&mut head).map_err(|e| fail(format!("{p}: {e}")))?
        }
        Input::Bytes(b) => {
            let n = b.len().min(4);
            head[..n].copy_from_slice(&b[..n]);
            n
        }
        Input::File(_) => return Err(PyTypeError::new_err("internal: magic takes a path or bytes")),
    };
    Ok(PyBytes::new(py, &head[..n]))
}
