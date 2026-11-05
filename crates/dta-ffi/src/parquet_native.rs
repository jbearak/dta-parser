//! The native C ABI for Parquet (plan 0018), for Julia's `read_parquet`,
//! `read_meta` and `write_parquet`. `include/dta.h` documents every call.
//!
//! Reads decode straight into memory the caller allocated: numbers into
//! its vectors, with a missing code per row where it asks for one, and
//! categorical columns as level codes. Text arrives one column chunk at a
//! time through a callback, on the calling thread, as the chunk's bytes
//! with a code per row when the chunk is dictionary-encoded, so the
//! caller makes one string per distinct value. What each Parquet type
//! becomes is decided by the caller from `dta_pq_info_json`.
//!
//! As in `native.rs`, every call that can fail writes its message to an
//! error buffer, and panics are caught.

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::fs::File;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;

use dta::{missing, Bytes, Characteristic, FileSource, Source, ValueLabel, ValueLabelSet};
use dta_parquet::format::{converted as cv, Codec, LogicalType, TimeUnit};
use dta_parquet::{
    ColumnInfo, ColumnProfile, ColumnType, Compression, LevelsFrom, Nested, Numbers, Output, Profile,
    ReadOptions, Reader, Role, Table, TextChunk, Values, WriteColumn, WriteOptions,
};

use crate::json::{self, Value};

// ---------------------------------------------------------------- errors

fn set_error(err: *mut c_char, err_len: usize, message: &str) {
    if err.is_null() || err_len == 0 {
        return;
    }
    let mut n = message.len().min(err_len - 1);
    while !message.is_char_boundary(n) {
        n -= 1;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(message.as_ptr(), err as *mut u8, n);
        *err.add(n) = 0;
    }
}

fn guard<T>(err: *mut c_char, err_len: usize, fail: T, f: impl FnOnce() -> Result<T, String>) -> T {
    set_error(err, err_len, "");
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(v)) => v,
        Ok(Err(message)) => {
            set_error(err, err_len, &message);
            fail
        }
        Err(payload) => {
            let what = payload
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| payload.downcast_ref::<String>().cloned())
                .unwrap_or_default();
            set_error(err, err_len, &format!("internal error in dta-parser: {what}"));
            fail
        }
    }
}

/// # Safety
/// `s` is NULL or a NUL-terminated string.
unsafe fn c_str<'a>(s: *const c_char) -> Option<&'a [u8]> {
    (!s.is_null()).then(|| CStr::from_ptr(s).to_bytes())
}

fn path(bytes: &[u8]) -> Result<PathBuf, String> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        Ok(PathBuf::from(std::ffi::OsStr::from_bytes(bytes)))
    }
    #[cfg(not(unix))]
    {
        std::str::from_utf8(bytes).map(PathBuf::from).map_err(|_| "the path is not UTF-8".to_string())
    }
}

/// # Safety
/// `ptr` is NULL only when `len` is 0, and otherwise points to `len`
/// readable values of T.
unsafe fn slice<'a, T>(ptr: *const T, len: usize, what: &str) -> Result<&'a [T], String> {
    if len == 0 {
        Ok(&[])
    } else if ptr.is_null() {
        Err(format!("{what} is NULL"))
    } else {
        Ok(std::slice::from_raw_parts(ptr, len))
    }
}

/// # Safety
/// As [`slice`], writable and not otherwise borrowed while the slice is
/// used.
unsafe fn slice_mut<'a, T>(ptr: *mut T, len: usize, what: &str) -> Result<&'a mut [T], String> {
    if len == 0 {
        Ok(&mut [])
    } else if ptr.is_null() {
        Err(format!("{what} is NULL"))
    } else {
        Ok(std::slice::from_raw_parts_mut(ptr, len))
    }
}

fn c_string(text: String, len: *mut usize) -> Result<*mut c_char, String> {
    if !len.is_null() {
        unsafe { *len = text.len() };
    }
    // JSON escapes control characters, so there is no NUL inside.
    Ok(CString::new(text).map_err(|e| e.to_string())?.into_raw())
}

// ---------------------------------------------------------------- JSON out

fn push_str(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

fn push_opt(out: &mut String, s: Option<&str>) {
    match s {
        Some(s) => push_str(out, s),
        None => out.push_str("null"),
    }
}

/// `,"key":` (without the comma for the first member).
fn key(out: &mut String, k: &str) {
    if !out.ends_with('{') {
        out.push(',');
    }
    push_str(out, k);
    out.push(':');
}

fn push_strs<S: AsRef<str>>(out: &mut String, v: &[S]) {
    out.push('[');
    for (i, s) in v.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        push_str(out, s.as_ref());
    }
    out.push(']');
}

// ---------------------------------------------------------------- opening

/// A file read in blocks of 1 MiB, one per thread: a wide file has a
/// column chunk of a few kilobytes per column, and a system call for
/// each, from several threads at once, costs more than decoding them.
/// Reads of a quarter block or more go to the file directly. (The same as
/// R's bridge, r/dtaparser/src/rust/parquet_r.rs.)
pub struct ReadAhead {
    file: FileSource,
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
    fn open(path: &std::path::Path) -> dta::Result<Self> {
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

/// An open Parquet file: on disk, or in the caller's memory, which must
/// stay where it is until the handle is closed.
pub enum PqFile {
    File(Reader<ReadAhead>),
    Memory(Reader<Bytes<&'static [u8]>>),
}

macro_rules! with_reader {
    ($file:expr, $r:ident => $body:expr) => {
        match $file {
            PqFile::File($r) => $body,
            PqFile::Memory($r) => $body,
        }
    };
}

/// # Safety
/// See dta.h: `path` is NULL or NUL-terminated; when it is NULL, `bytes`
/// points to `len` bytes that stay alive and unchanged until
/// `dta_pq_close`.
#[no_mangle]
pub unsafe extern "C" fn dta_pq_open(
    path_: *const c_char,
    bytes: *const u8,
    len: usize,
    nested_skip: c_int,
    err: *mut c_char,
    err_len: usize,
) -> *mut PqFile {
    guard(err, err_len, std::ptr::null_mut(), || {
        let options = ReadOptions { nested: if nested_skip != 0 { Nested::Skip } else { Nested::Error }, ..ReadOptions::default() };
        let file = match c_str(path_) {
            Some(p) => {
                let p = path(p)?;
                let source = ReadAhead::open(&p).map_err(|e| format!("{}: {e}", p.display()))?;
                PqFile::File(Reader::open(source, options).map_err(|e| format!("{}: {e}", p.display()))?)
            }
            None => {
                let data: &'static [u8] = slice(bytes, len, "bytes")?;
                PqFile::Memory(Reader::open(Bytes(data), options).map_err(|e| e.to_string())?)
            }
        };
        Ok(Box::into_raw(Box::new(file)))
    })
}

/// # Safety
/// `file` is NULL or a handle from `dta_pq_open` not yet closed.
#[no_mangle]
pub unsafe extern "C" fn dta_pq_close(file: *mut PqFile) {
    if !file.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(file))));
    }
}

// ---------------------------------------------------------------- info

fn unit_name(u: TimeUnit) -> &'static str {
    match u {
        TimeUnit::Millis => "ms",
        TimeUnit::Micros => "us",
        TimeUnit::Nanos => "ns",
    }
}

fn unit_upper(u: TimeUnit) -> &'static str {
    match u {
        TimeUnit::Millis => "MILLIS",
        TimeUnit::Micros => "MICROS",
        TimeUnit::Nanos => "NANOS",
    }
}

/// Parquet's logical type (or else its converted type) as text.
fn logical_name(col: &ColumnInfo) -> Option<String> {
    if let Some(l) = &col.logical {
        return Some(match l {
            LogicalType::String => "STRING".into(),
            LogicalType::Map => "MAP".into(),
            LogicalType::List => "LIST".into(),
            LogicalType::Enum => "ENUM".into(),
            LogicalType::Decimal { scale, precision } => format!("DECIMAL({precision}, {scale})"),
            LogicalType::Date => "DATE".into(),
            LogicalType::Time { utc, unit } => {
                format!("TIME({}, {})", unit.map_or("?", unit_upper), if *utc { "UTC" } else { "local" })
            }
            LogicalType::Timestamp { utc, unit } => {
                format!("TIMESTAMP({}, {})", unit.map_or("?", unit_upper), if *utc { "UTC" } else { "local" })
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

fn codec_name(c: Codec) -> String {
    match c {
        Codec::Uncompressed => "none".into(),
        Codec::Snappy => "snappy".into(),
        Codec::Gzip => "gzip".into(),
        Codec::Lzo => "lzo".into(),
        Codec::Brotli => "brotli".into(),
        Codec::Lz4 => "lz4".into(),
        Codec::Zstd => "zstd".into(),
        Codec::Lz4Raw => "lz4_raw".into(),
        Codec::Other(v) => format!("codec {v}"),
    }
}

/// Whether any row group's chunk of `col` may hold a null: its statistics
/// count some, or do not say.
fn may_have_nulls<S: Source>(r: &Reader<S>, col: &ColumnInfo) -> bool {
    if col.required {
        return false;
    }
    r.metadata().row_groups.iter().any(|g| {
        let Some(m) = g.columns.get(col.leaf()).and_then(|c| c.meta.as_ref()) else { return true };
        match m.statistics.as_ref().and_then(|s| s.null_count) {
            Some(n) => n != 0,
            None => true,
        }
    })
}

fn info_json<S: Source>(r: &Reader<S>) -> String {
    let mut o = String::from("{");
    key(&mut o, "rows");
    o.push_str(&r.rows().to_string());
    key(&mut o, "row_groups");
    o.push('[');
    for (i, g) in r.row_groups().iter().enumerate() {
        if i > 0 {
            o.push(',');
        }
        o.push_str(&format!(
            "{{\"rows\":{},\"compressed_bytes\":{},\"uncompressed_bytes\":{}}}",
            g.rows, g.compressed_bytes, g.uncompressed_bytes
        ));
    }
    o.push(']');
    key(&mut o, "created_by");
    push_opt(&mut o, r.created_by());
    key(&mut o, "compression");
    push_strs(&mut o, &r.codecs().into_iter().map(codec_name).collect::<Vec<_>>());
    key(&mut o, "warnings");
    push_strs(&mut o, r.warnings());
    let profile = r.profile();
    key(&mut o, "profile");
    o.push_str(if profile.is_some() { "true" } else { "false" });
    key(&mut o, "label");
    push_opt(&mut o, profile.and_then(|p| p.label.as_deref()));
    key(&mut o, "notes");
    push_strs(&mut o, profile.map_or(&[][..], |p| &p.notes[..]));
    key(&mut o, "timestamp");
    push_opt(&mut o, profile.and_then(|p| p.timestamp.as_deref()));
    key(&mut o, "sort");
    push_strs(&mut o, profile.map_or(&[][..], |p| &p.sort[..]));
    key(&mut o, "characteristics");
    o.push_str(&json::characteristics(profile.map_or(&[][..], |p| &p.characteristics[..])));
    key(&mut o, "valueLabels");
    o.push_str(&json::value_labels(profile.map_or(&[][..], |p| &p.value_labels[..])));
    let by_name: std::collections::HashMap<&str, &ColumnProfile> =
        profile.map_or_else(Default::default, |p| p.columns.iter().map(|c| (c.name.as_str(), c)).collect());
    key(&mut o, "columns");
    o.push('[');
    for (i, c) in r.columns().iter().enumerate() {
        if i > 0 {
            o.push(',');
        }
        let entry = by_name.get(c.name.as_str()).copied();
        o.push('{');
        key(&mut o, "name");
        push_str(&mut o, &c.name);
        key(&mut o, "role");
        push_str(&mut o, if c.role == Role::Data { "data" } else { "nested" });
        key(&mut o, "physical_type");
        push_opt(&mut o, c.physical.map(|p| p.name()).as_deref());
        key(&mut o, "logical_type");
        push_opt(&mut o, logical_name(c).as_deref());
        let (kind, extra): (&str, String) = match &c.kind {
            ColumnType::Int8 => ("int8", String::new()),
            ColumnType::Int16 => ("int16", String::new()),
            ColumnType::Int32 => ("int32", String::new()),
            ColumnType::Int64 => ("int64", String::new()),
            ColumnType::UInt8 => ("uint8", String::new()),
            ColumnType::UInt16 => ("uint16", String::new()),
            ColumnType::UInt32 => ("uint32", String::new()),
            ColumnType::UInt64 => ("uint64", String::new()),
            ColumnType::Float => ("float", String::new()),
            ColumnType::Double => ("double", String::new()),
            ColumnType::Boolean => ("bool", String::new()),
            ColumnType::Text => ("text", String::new()),
            ColumnType::Binary => ("binary", String::new()),
            ColumnType::Date => ("date", String::new()),
            ColumnType::Timestamp { unit, utc } => {
                ("timestamp", format!(",\"unit\":\"{}\",\"utc\":{utc}", unit_name(*unit)))
            }
            ColumnType::Time { unit, .. } => ("time", format!(",\"unit\":\"{}\"", unit_name(*unit))),
            ColumnType::Decimal { precision, scale } => {
                ("decimal", format!(",\"precision\":{precision},\"scale\":{scale}"))
            }
            ColumnType::Unsupported(why) => {
                let mut w = String::from(",\"why\":");
                push_str(&mut w, why);
                ("unsupported", w)
            }
        };
        key(&mut o, "kind");
        push_str(&mut o, if c.role == Role::Nested { "nested" } else { kind });
        o.push_str(&extra);
        // A timestamp's zone: the profile's ("" for an instant without
        // one), else the one ARROW:schema gives.
        let zone = match entry.and_then(|e| e.tz.as_deref()) {
            Some(z) => Some(z),
            None => c.zone.as_deref().filter(|z| !z.is_empty()),
        };
        key(&mut o, "zone");
        push_opt(&mut o, zone);
        key(&mut o, "levels");
        push_opt(
            &mut o,
            c.levels.map(|l| match l {
                LevelsFrom::Profile => "profile",
                LevelsFrom::Rows => "rows",
            }),
        );
        if let (Some(LevelsFrom::Profile), Some(cat)) = (c.levels, entry.and_then(|e| e.categorical.as_ref())) {
            key(&mut o, "categories");
            push_strs(&mut o, &cat.levels);
            key(&mut o, "ordered");
            o.push_str(if cat.ordered { "true" } else { "false" });
        }
        key(&mut o, "storage");
        push_opt(&mut o, c.storage.map(|s| s.name()));
        key(&mut o, "logical");
        push_opt(&mut o, c.profile_logical.map(|l| l.name()));
        key(&mut o, "label");
        push_opt(&mut o, entry.and_then(|e| e.label.as_deref()));
        key(&mut o, "format");
        push_opt(&mut o, entry.and_then(|e| e.format.as_deref()));
        key(&mut o, "value_labels");
        push_opt(&mut o, entry.and_then(|e| e.value_labels.as_deref()));
        key(&mut o, "unit_profile");
        push_opt(&mut o, entry.and_then(|e| e.unit.as_deref()));
        key(&mut o, "nulls");
        o.push_str(if c.role == Role::Data && may_have_nulls(r, c) { "true" } else { "false" });
        o.push('}');
    }
    o.push_str("]}");
    o
}

/// # Safety
/// `file` is an open handle; `len` NULL or writable. Free the result with
/// `dta_string_free`.
#[no_mangle]
pub unsafe extern "C" fn dta_pq_info_json(file: *mut PqFile, len: *mut usize, err: *mut c_char, err_len: usize) -> *mut c_char {
    guard(err, err_len, std::ptr::null_mut(), || {
        let file = file.as_mut().ok_or("the file is NULL")?;
        let text = with_reader!(file, r => info_json(r));
        c_string(text, len)
    })
}

// ---------------------------------------------------------------- read

// What an output receives (`dta_pq_output.kind`).
pub const OUT_I8: u32 = 1;
pub const OUT_I16: u32 = 2;
pub const OUT_I32: u32 = 3;
pub const OUT_I64: u32 = 4;
pub const OUT_F32: u32 = 5;
pub const OUT_F64: u32 = 6;
pub const OUT_U8: u32 = 7;
pub const OUT_U16: u32 = 8;
pub const OUT_U32: u32 = 9;
pub const OUT_U64: u32 = 10;
/// Level codes (`i32`), `base` for the first level and `null` for a
/// missing value.
pub const OUT_LEVELS: u32 = 11;
/// Text or bytes, through the callback.
pub const OUT_TEXT: u32 = 12;

/// Where one selected column goes. See `dta_pq_output` in dta.h.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct PqOutput {
    pub kind: u32,
    pub base: i32,
    pub null: i32,
    pub values: *mut c_void,
    pub codes: *mut u8,
}

/// Called with one column chunk of text: `k` is the column's place in the
/// selection, `first` the chunk's first row in the read, `rows` its rows.
/// Value `i` is `bytes[ends[i-1]..ends[i]]`. With a dictionary, `codes`
/// gives each row's value (`u32::MAX` for a missing row) and `missing` is
/// NULL; without one, row `r` is value `r`, missing where `missing[r]` is
/// not 0.
pub type TextFn = unsafe extern "C" fn(
    user: *mut c_void,
    k: usize,
    first: u64,
    rows: u64,
    bytes: *const u8,
    ends: *const usize,
    nvalues: usize,
    codes: *const u32,
    missing: *const u8,
) -> c_int;

fn numbers<'a, T: dta_parquet::Element>(o: &PqOutput, rows: usize, null: T) -> Result<Numbers<'a, T>, String> {
    let values = unsafe { slice_mut(o.values as *mut T, rows, "values")? };
    let mut n = Numbers::new(values, null);
    if !o.codes.is_null() {
        n = n.with_codes(unsafe { slice_mut(o.codes, rows, "codes")? });
    }
    Ok(n)
}

fn output<'a>(o: &PqOutput, rows: usize) -> Result<Output<'a>, String> {
    Ok(match o.kind {
        OUT_I8 => Output::Int8(numbers(o, rows, 0)?),
        OUT_I16 => Output::Int16(numbers(o, rows, 0)?),
        OUT_I32 => Output::Int32(numbers(o, rows, 0)?),
        OUT_I64 => Output::Int64(numbers(o, rows, 0)?),
        OUT_F32 => Output::Float32(numbers(o, rows, f32::NAN)?),
        OUT_F64 => Output::Float64(numbers(o, rows, f64::NAN)?),
        OUT_U8 => Output::UInt8(numbers(o, rows, 0)?),
        OUT_U16 => Output::UInt16(numbers(o, rows, 0)?),
        OUT_U32 => Output::UInt32(numbers(o, rows, 0)?),
        OUT_U64 => Output::UInt64(numbers(o, rows, 0)?),
        OUT_LEVELS => Output::Levels {
            codes: unsafe { slice_mut(o.values as *mut i32, rows, "values")? },
            base: o.base,
            null: o.null,
        },
        OUT_TEXT => Output::Text,
        other => return Err(format!("unknown output kind {other}")),
    })
}

fn read_with<S: Source>(
    r: &mut Reader<S>,
    cols: &[usize],
    skip: u64,
    n: u64,
    outputs: &[PqOutput],
    callback: Option<TextFn>,
    user: *mut c_void,
) -> Result<(u64, String), String> {
    if let Some(&bad) = cols.iter().find(|&&c| c >= r.columns().len()) {
        return Err(format!("there is no column {}; the file has {}", bad + 1, r.columns().len()));
    }
    let window = r.window(skip, n);
    let rows = usize::try_from(window.end - window.start).map_err(|_| "too many rows".to_string())?;
    let mut outs = outputs.iter().map(|o| output(o, rows)).collect::<Result<Vec<_>, String>>()?;
    let mut cancelled = false;
    let report = r.read(cols, skip, n, &mut outs, |k, chunk: &TextChunk| {
        let Some(cb) = callback else { return Err(dta::Error::new("a text column was read without a callback")) };
        let codes = chunk.codes.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
        let missing = if chunk.missing.is_empty() { std::ptr::null() } else { chunk.missing.as_ptr() };
        let rc = unsafe {
            cb(user, k, chunk.first, chunk.rows as u64, chunk.bytes.as_ptr(), chunk.ends.as_ptr(), chunk.ends.len(), codes, missing)
        };
        if rc != 0 {
            cancelled = true;
            return Err(dta::Error::new("the read was cancelled"));
        }
        Ok(())
    });
    let report = match report {
        Ok(rep) => rep,
        Err(_) if cancelled => return Ok((u64::MAX, String::new())),
        Err(e) => return Err(e.to_string()),
    };
    let mut o = String::from("{\"letters\":[");
    for (i, l) in report.letters.iter().enumerate() {
        if i > 0 {
            o.push(',');
        }
        o.push_str(if *l { "true" } else { "false" });
    }
    o.push_str("],\"levels\":[");
    for (i, l) in report.levels.iter().enumerate() {
        if i > 0 {
            o.push(',');
        }
        match l {
            Some(levels) => push_strs(&mut o, levels),
            None => o.push_str("null"),
        }
    }
    o.push_str("]}");
    Ok((report.rows, o))
}

/// Read rows `skip` to `skip + n` (clipped to the file) of the columns
/// `cols` (0-based) into `outputs`. Returns the rows read, -2 when the
/// callback stopped the read, -1 on error. `report` receives a JSON
/// object (free it with `dta_string_free`): `letters`, per column whether
/// any `.a` to `.z` was read, and `levels`, per column the levels found
/// in the rows read (null where the levels are not from the rows).
///
/// # Safety
/// See dta.h: each output's buffers hold the window's rows; `callback`
/// must not unwind.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn dta_pq_read(
    file: *mut PqFile,
    cols: *const u32,
    ncols: usize,
    skip: u64,
    n: u64,
    outputs: *const PqOutput,
    callback: Option<TextFn>,
    user: *mut c_void,
    report: *mut *mut c_char,
    report_len: *mut usize,
    err: *mut c_char,
    err_len: usize,
) -> i64 {
    guard(err, err_len, -1, || {
        let file = file.as_mut().ok_or("the file is NULL")?;
        let cols: Vec<usize> = slice(cols, ncols, "cols")?.iter().map(|&c| c as usize).collect();
        let outputs = slice(outputs, ncols, "outputs")?;
        let (rows, text) = with_reader!(file, r => read_with(r, &cols, skip, n, outputs, callback, user))?;
        if rows == u64::MAX {
            return Ok(-2);
        }
        if !report.is_null() {
            *report = c_string(text, report_len)?;
        }
        Ok(rows as i64)
    })
}

// ---------------------------------------------------------------- write

// What a column to write holds (`dta_pq_column.kind`).
pub const W_INT8: u32 = 1;
pub const W_INT16: u32 = 2;
pub const W_INT32: u32 = 3;
pub const W_INT64: u32 = 4;
pub const W_FLOAT: u32 = 5;
pub const W_DOUBLE: u32 = 6;
/// `u8`, 0 or 1.
pub const W_BOOL: u32 = 7;
/// `i64` days since 0000-12-31 (Julia's `Date`).
pub const W_DATE: u32 = 8;
/// `i64` milliseconds since 0000-12-31 00:00 (Julia's `DateTime`), a
/// clock time without zone.
pub const W_DATETIME: u32 = 9;
/// As `W_DATETIME`, in UTC, with the zone named in the metadata.
pub const W_ZONED: u32 = 10;
/// UTF-8 text: `bytes` and `offsets` (n + 1, from 0).
pub const W_TEXT: u32 = 11;
pub const W_BINARY: u32 = 12;
/// `u32` level numbers from 1, 0 for missing; the levels in the metadata.
pub const W_CATEGORICAL: u32 = 13;

/// Days from 0000-12-31 to 1970-01-01.
const RATA_DIE_1970: i64 = 719_163;
const MS_PER_DAY: i64 = 86_400_000;

/// One column to write. See `dta_pq_column` in dta.h.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct PqColumn {
    pub kind: u32,
    pub values: *const c_void,
    /// Per row: 0 a value, 1 missing (`.`), 2 to 27 `.a` to `.z`. NULL
    /// when every row is a value. For text, nonzero is missing.
    pub codes: *const u8,
    pub bytes: *const u8,
    pub offsets: *const u64,
}

/// The fill of a column of `S`s, each converted to `T`.
fn fill<'a, S: Copy + Sync + 'a, T: Default + Copy + 'a>(
    v: &'a [S],
    codes: Option<&'a [u8]>,
    conv: impl Fn(S) -> T + Sync + 'a,
) -> Box<dta_parquet::Fill<'a, T>> {
    Box::new(move |first, values: &mut [T], out: &mut [u8]| {
        let n = values.len();
        match codes {
            Some(c) => {
                for (i, (d, o)) in values.iter_mut().zip(out.iter_mut()).enumerate() {
                    let code = c[first + i];
                    *o = code;
                    *d = if code == 0 { conv(v[first + i]) } else { T::default() };
                }
            }
            None => {
                for (d, &s) in values.iter_mut().zip(&v[first..first + n]) {
                    *d = conv(s);
                }
                out[..n].fill(0);
            }
        }
    })
}

/// # Safety
/// `c` describes `rows` rows as dta.h says.
unsafe fn values_of<'a>(c: &PqColumn, rows: usize, name: &str, meta: &Value) -> Result<Values<'a>, String> {
    let codes = if c.codes.is_null() { None } else { Some(slice(c.codes, rows, "codes")?) };
    if c.kind != W_TEXT && c.kind != W_BINARY {
        if let Some(i) = codes.and_then(|cs| cs.iter().position(|&m| m > missing::LAST)) {
            return Err(format!("column \"{name}\": row {} has missing code {}, above 27 (.z)", i + 1, codes.unwrap()[i]));
        }
    }
    let v = c.values;
    Ok(match c.kind {
        W_INT8 => Values::Int8(fill(slice(v as *const i8, rows, "values")?, codes, i32::from)),
        W_INT16 => Values::Int16(fill(slice(v as *const i16, rows, "values")?, codes, i32::from)),
        W_INT32 => Values::Int32(fill(slice(v as *const i32, rows, "values")?, codes, |x| x)),
        W_INT64 => Values::Int64(fill(slice(v as *const i64, rows, "values")?, codes, |x| x)),
        W_FLOAT => Values::Float(fill(slice(v as *const f32, rows, "values")?, codes, |x| x)),
        W_DOUBLE => Values::Double(fill(slice(v as *const f64, rows, "values")?, codes, |x| x)),
        W_BOOL => Values::Bool(fill(slice(v as *const u8, rows, "values")?, codes, |x| (x != 0) as u8)),
        W_DATE => {
            let days = slice(v as *const i64, rows, "values")?;
            let bad = days.iter().enumerate().find(|&(i, &d)| {
                codes.is_none_or(|c| c[i] == 0) && i32::try_from(d - RATA_DIE_1970).is_err()
            });
            if let Some((i, _)) = bad {
                return Err(format!("column \"{name}\": row {} holds a date more than 5.8 million years from 1970, which a Parquet DATE cannot hold", i + 1));
            }
            Values::Date(fill(days, codes, |d| (d - RATA_DIE_1970) as i32))
        }
        W_DATETIME | W_ZONED => {
            let ms = slice(v as *const i64, rows, "values")?;
            let zone = meta.str("zone")?;
            Values::Timestamp {
                unit: TimeUnit::Millis,
                utc: c.kind == W_ZONED,
                zone: (c.kind == W_ZONED && !zone.is_empty()).then(|| zone.to_string()),
                fill: fill(ms, codes, |m| m - RATA_DIE_1970 * MS_PER_DAY),
            }
        }
        W_TEXT | W_BINARY => {
            let offsets = slice(c.offsets, rows + 1, "offsets")?;
            if offsets.first().is_some_and(|&o| o != 0) || offsets.windows(2).any(|w| w[0] > w[1]) {
                return Err(format!("column \"{name}\": offsets must start at 0 and not decrease"));
            }
            let total = usize::try_from(*offsets.last().unwrap_or(&0)).map_err(|_| "text too large")?;
            let bytes = slice(c.bytes, total, "bytes")?;
            let get = move |r: usize| -> Option<&'a [u8]> {
                if codes.is_some_and(|c| c[r] != 0) {
                    None
                } else {
                    Some(&bytes[offsets[r] as usize..offsets[r + 1] as usize])
                }
            };
            if c.kind == W_TEXT {
                Values::Text(Box::new(get))
            } else {
                Values::Binary(Box::new(get))
            }
        }
        W_CATEGORICAL => {
            let refs = slice(v as *const u32, rows, "values")?;
            let levels: Vec<String> = meta
                .array("levels")?
                .iter()
                .map(|l| match l {
                    Value::String(s) => Ok(s.clone()),
                    _ => Err(format!("column \"{name}\": levels must be text")),
                })
                .collect::<Result<_, _>>()?;
            if let Some(i) = refs.iter().position(|&r| r as usize > levels.len()) {
                return Err(format!("column \"{name}\": row {} has level {}, but there are {}", i + 1, refs[i], levels.len()));
            }
            let ordered = matches!(meta.get("ordered"), Value::Bool(true));
            Values::Categorical {
                levels,
                ordered,
                codes: Box::new(move |first, out: &mut [i32]| {
                    for (d, &r) in out.iter_mut().zip(&refs[first..]) {
                        *d = r as i32 - 1;
                    }
                }),
            }
        }
        other => return Err(format!("column \"{name}\": unknown column kind {other}")),
    })
}

fn label_sets(doc: &Value) -> Result<Vec<ValueLabelSet>, String> {
    let mut sets = Vec::new();
    for set in doc.array("valueLabels")? {
        let mut labels = Vec::new();
        for pair in set.array("labels")? {
            let Value::Array(pair) = pair else { return Err("a value label must be [value, text]".into()) };
            let [value, Value::String(text)] = pair.as_slice() else {
                return Err("a value label must be [value, text]".into());
            };
            let (value, m) = match value {
                Value::Number(x) => (*x, 0),
                Value::String(m) => (f64::NAN, missing::from_name(m).ok_or_else(|| format!("\"{m}\" is not a missing value"))?),
                _ => return Err("a labelled value must be a number or a missing value such as \".a\"".into()),
            };
            labels.push(ValueLabel { value, missing: m, text: text.clone() });
        }
        sets.push(ValueLabelSet { name: set.str("name")?.to_string(), labels });
    }
    Ok(sets)
}

fn some_text(s: &str) -> Option<String> {
    (!s.is_empty()).then(|| s.to_string())
}

/// The profile the metadata JSON describes, and each column's entry in
/// it.
fn profile_of(doc: &Value, names: &[String]) -> Result<Profile, String> {
    let mut p = Profile { label: some_text(doc.str("label")?), ..Profile::default() };
    for n in doc.array("notes")? {
        let Value::String(t) = n else { return Err("notes must be text".into()) };
        p.notes.push(t.clone());
    }
    let ts = doc.str("timestamp")?;
    p.timestamp = some_text(ts);
    for s in doc.array("sort")? {
        let Value::String(t) = s else { return Err("sort must list column names".into()) };
        p.sort.push(t.clone());
    }
    for c in doc.array("characteristics")? {
        p.characteristics.push(Characteristic {
            variable: c.str("variable")?.to_string(),
            name: c.str("name")?.to_string(),
            value: c.str("value")?.to_string(),
        });
    }
    p.value_labels = label_sets(doc)?;
    for (name, c) in names.iter().zip(doc.array("columns")?) {
        let mut e = ColumnProfile::named(name.as_str());
        e.label = some_text(c.str("label")?);
        e.format = some_text(c.str("format")?);
        e.value_labels = some_text(c.str("valueLabels")?);
        p.columns.push(e);
    }
    Ok(p)
}

/// A new file beside `target` that no other call has: created exclusively.
fn create_beside(target: &std::path::Path) -> Result<(PathBuf, File), String> {
    let base = target.file_name().ok_or("the path names no file")?.to_os_string();
    for n in 0..1000 {
        let mut name = base.clone();
        name.push(format!(".{}.{n}.tmp", std::process::id()));
        let tmp = target.with_file_name(name);
        match std::fs::OpenOptions::new().write(true).create_new(true).open(&tmp) {
            Ok(file) => return Ok((tmp, file)),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(format!("{}: {e}", tmp.display())),
        }
    }
    Err(format!("{}: no free name for a temporary file", target.display()))
}

/// Write a table as Parquet to `path`, or, when `path` is NULL, to memory
/// returned through `out` and `out_len` (free it with `dta_pq_bytes_free`).
/// `meta_json` holds `label`, `notes`, `timestamp`, `sort`,
/// `characteristics`, `valueLabels` and `columns` (one object per column:
/// `name`, `label`, `format`, `valueLabels`, and `levels` and `ordered`
/// for a categorical, `zone` for a zoned timestamp). Returns 0, or -1 on
/// error.
///
/// # Safety
/// See dta.h: `columns` points to `ncols` columns whose buffers hold
/// `nrows` rows; the strings are NUL-terminated.
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn dta_pq_write(
    path_: *const c_char,
    nrows: u64,
    columns: *const PqColumn,
    ncols: usize,
    meta_json: *const c_char,
    compression: *const c_char,
    level: c_int,
    has_level: c_int,
    row_group_rows: u64,
    missing_letters: c_int,
    out: *mut *mut u8,
    out_len: *mut usize,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    guard(err, err_len, -1, || {
        let text = c_str(meta_json).map(String::from_utf8_lossy).unwrap_or_default();
        let doc = if text.trim().is_empty() { Value::Object(Vec::new()) } else { json::parse(&text)? };
        let rows = usize::try_from(nrows).map_err(|_| "too many rows")?;
        let columns = slice(columns, ncols, "columns")?;
        let described = doc.array("columns")?;
        if described.len() != ncols {
            return Err(format!("the metadata describes {} columns, but there are {ncols}", described.len()));
        }
        let names: Vec<String> = described.iter().map(|c| c.str("name").map(String::from)).collect::<Result<_, _>>()?;
        let profile = profile_of(&doc, &names)?;
        let mut cols = Vec::with_capacity(ncols);
        for ((c, meta), name) in columns.iter().zip(described).zip(&names) {
            cols.push(WriteColumn { name: name.clone(), values: values_of(c, rows, name, meta)? });
        }
        let table = Table { rows, columns: cols, profile };
        let codec = String::from_utf8_lossy(c_str(compression).unwrap_or(b"snappy")).into_owned();
        let options = WriteOptions {
            compression: Compression::from_name(&codec).map_err(|e| e.to_string())?,
            compression_level: (has_level != 0).then_some(level),
            row_group_rows: (row_group_rows > 0).then_some(row_group_rows as usize),
            missing_letters: missing_letters != 0,
            ..WriteOptions::default()
        };
        match c_str(path_) {
            Some(p) => {
                let target = path(p)?;
                // Write beside the target and rename, so a failed write
                // leaves any file already there alone.
                let (tmp, file) = create_beside(&target)?;
                let written = dta_parquet::write(&table, std::io::BufWriter::with_capacity(1 << 20, file), &options)
                    .map_err(|e| e.to_string());
                let renamed =
                    written.and_then(|_| std::fs::rename(&tmp, &target).map_err(|e| format!("{}: {e}", target.display())));
                if renamed.is_err() {
                    let _ = std::fs::remove_file(&tmp);
                }
                renamed.map(|_| 0)
            }
            None => {
                let mut buf = Vec::new();
                dta_parquet::write(&table, &mut buf, &options).map_err(|e| e.to_string())?;
                let mut buf = buf.into_boxed_slice();
                if !out_len.is_null() {
                    *out_len = buf.len();
                }
                if out.is_null() {
                    return Err("out is NULL".into());
                }
                *out = buf.as_mut_ptr();
                std::mem::forget(buf);
                Ok(0)
            }
        }
    })
}

/// # Safety
/// `p` and `len` came from `dta_pq_write`, and `p` was not freed.
#[no_mangle]
pub unsafe extern "C" fn dta_pq_bytes_free(p: *mut u8, len: usize) {
    if !p.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_table_written_to_memory_reads_back() {
        let ints: Vec<i8> = vec![1, 0, 3];
        let codes: Vec<u8> = vec![0, 2, 1];
        let words = b"abcd";
        let offsets: Vec<u64> = vec![0, 1, 1, 4];
        let wcodes: Vec<u8> = vec![0, 1, 0];
        let cols = [
            PqColumn { kind: W_INT8, values: ints.as_ptr() as *const c_void, codes: codes.as_ptr(), bytes: std::ptr::null(), offsets: std::ptr::null() },
            PqColumn { kind: W_TEXT, values: std::ptr::null(), codes: wcodes.as_ptr(), bytes: words.as_ptr(), offsets: offsets.as_ptr() },
        ];
        let meta = CString::new(r#"{"label":"t","timestamp":"01 Jan 2024 10:00","columns":[{"name":"a","label":"A"},{"name":"w"}],"valueLabels":[{"name":"s","labels":[[1,"one"],[".a","no"]]}]}"#).unwrap();
        let mut err = [0 as c_char; 256];
        let (mut out, mut len) = (std::ptr::null_mut(), 0usize);
        let rc = unsafe {
            dta_pq_write(std::ptr::null(), 3, cols.as_ptr(), 2, meta.as_ptr(), c"snappy".as_ptr(), 0, 0, 0, 1, &mut out, &mut len, err.as_mut_ptr(), 256)
        };
        assert_eq!(rc, 0, "{:?}", unsafe { CStr::from_ptr(err.as_ptr()) });
        let file = unsafe { dta_pq_open(std::ptr::null(), out, len, 0, err.as_mut_ptr(), 256) };
        assert!(!file.is_null());
        let mut n = 0usize;
        let info = unsafe { dta_pq_info_json(file, &mut n, err.as_mut_ptr(), 256) };
        let text = unsafe { CStr::from_ptr(info) }.to_str().unwrap().to_string();
        unsafe { crate::native::dta_string_free(info) };
        let doc = json::parse(&text).unwrap();
        assert_eq!(doc.str("timestamp").unwrap(), "01 Jan 2024 10:00");
        let cols = doc.array("columns").unwrap();
        assert_eq!(cols[0].str("kind").unwrap(), "double");
        assert_eq!(cols[0].str("storage").unwrap(), "byte");
        assert_eq!(cols[0].str("label").unwrap(), "A");

        let mut values = [0i8; 3];
        let mut got_codes = [0u8; 3];
        let outputs = [
            PqOutput { kind: OUT_I8, base: 0, null: 0, values: values.as_mut_ptr() as *mut c_void, codes: got_codes.as_mut_ptr() },
            PqOutput { kind: OUT_TEXT, base: 0, null: 0, values: std::ptr::null_mut(), codes: std::ptr::null_mut() },
        ];
        unsafe extern "C" fn on_text(
            user: *mut c_void,
            _k: usize,
            _first: u64,
            rows: u64,
            bytes: *const u8,
            ends: *const usize,
            nvalues: usize,
            codes: *const u32,
            missing: *const u8,
        ) -> c_int {
            let seen = &mut *(user as *mut Vec<Option<String>>);
            let ends = std::slice::from_raw_parts(ends, nvalues);
            let value = |i: usize| {
                let start = if i == 0 { 0 } else { ends[i - 1] };
                String::from_utf8(std::slice::from_raw_parts(bytes.add(start), ends[i] - start).to_vec()).unwrap()
            };
            for r in 0..rows as usize {
                seen.push(if !codes.is_null() {
                    let c = *codes.add(r);
                    (c != u32::MAX).then(|| value(c as usize))
                } else if !missing.is_null() && *missing.add(r) != 0 {
                    None
                } else {
                    Some(value(r))
                });
            }
            0
        }
        let mut seen: Vec<Option<String>> = Vec::new();
        let (mut report, mut rlen) = (std::ptr::null_mut(), 0usize);
        let rows = unsafe {
            dta_pq_read(
                file,
                [0u32, 1].as_ptr(),
                2,
                0,
                u64::MAX,
                outputs.as_ptr(),
                Some(on_text),
                &mut seen as *mut _ as *mut c_void,
                &mut report,
                &mut rlen,
                err.as_mut_ptr(),
                256,
            )
        };
        assert_eq!(rows, 3, "{:?}", unsafe { CStr::from_ptr(err.as_ptr()) });
        assert_eq!(values, [1, 0, 0]);
        assert_eq!(got_codes, [0, 2, 1]);
        assert_eq!(seen, vec![Some("a".to_string()), None, Some("bcd".to_string())]);
        let rep = unsafe { CStr::from_ptr(report) }.to_str().unwrap().to_string();
        assert_eq!(rep, r#"{"letters":[true,false],"levels":[null,null]}"#);
        unsafe {
            crate::native::dta_string_free(report);
            dta_pq_close(file);
            dta_pq_bytes_free(out, len);
        }
    }

    #[test]
    fn a_bad_file_is_an_error() {
        let mut err = [0 as c_char; 256];
        let bytes = b"not parquet at all";
        let file = unsafe { dta_pq_open(std::ptr::null(), bytes.as_ptr(), bytes.len(), 0, err.as_mut_ptr(), 256) };
        assert!(file.is_null());
        let text = unsafe { CStr::from_ptr(err.as_ptr()) }.to_str().unwrap();
        assert!(text.contains("not a Parquet file"), "{text}");
    }
}
