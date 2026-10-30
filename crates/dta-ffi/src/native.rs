//! The native C ABI, for Julia. `include/dta.h` documents every call.
//!
//! Every call that can fail takes an error buffer and writes the message
//! there; nothing is kept per thread, so a caller may move between
//! threads. A handle is used by one thread at a time; distinct handles
//! are independent. Panics are caught and reported as errors.

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::fs::File;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;

use dta::{Characteristic, Column, Encoding, FileSource, Options, Reader, StorageType, ValueLabel, ValueLabelSet};

use crate::json::{self, Value};

pub const ABI_VERSION: u32 = 1;

// Storage types, as `DtaColumn::storage`.
pub const BYTE: u32 = 1;
pub const INT: u32 = 2;
pub const LONG: u32 = 3;
pub const FLOAT: u32 = 4;
pub const DOUBLE: u32 = 5;
pub const STR: u32 = 6;
pub const STRL: u32 = 7;

// Element types of `DtaColumn::values`.
pub const I8: u32 = 1;
pub const I16: u32 = 2;
pub const I32: u32 = 3;
pub const I64: u32 = 4;
pub const F32: u32 = 5;
pub const F64: u32 = 6;
pub const U8: u32 = 7;

/// An open file.
pub struct DtaFile {
    reader: Reader<FileSource>,
}

/// One column of a chunk being read, or of a frame being written. See
/// `dta_column` in dta.h.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct DtaColumn {
    pub storage: u32,
    pub value_type: u32,
    pub values: *const c_void,
    pub codes: *const u8,
    pub bytes: *const u8,
    pub offsets: *const u64,
    pub binary: *const u8,
}

impl DtaColumn {
    fn empty(storage: u32, value_type: u32) -> Self {
        DtaColumn {
            storage,
            value_type,
            values: std::ptr::null(),
            codes: std::ptr::null(),
            bytes: std::ptr::null(),
            offsets: std::ptr::null(),
            binary: std::ptr::null(),
        }
    }
}

pub type ChunkFn = unsafe extern "C" fn(user: *mut c_void, first_row: u64, nrows: u64, columns: *const DtaColumn) -> c_int;

/// Copy `message` into the caller's buffer, truncated to whole UTF-8
/// characters and NUL-terminated.
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

/// Run `f`, turning an error or a panic into `fail` and a message.
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

#[no_mangle]
pub extern "C" fn dta_abi_version() -> u32 {
    ABI_VERSION
}

/// # Safety
/// See dta.h: `path` is a NUL-terminated path, `encoding` NULL or a
/// NUL-terminated name, `err` NULL or `err_len` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn dta_open(path_: *const c_char, encoding: *const c_char, err: *mut c_char, err_len: usize) -> *mut DtaFile {
    guard(err, err_len, std::ptr::null_mut(), || {
        let p = path(c_str(path_).ok_or("the path is NULL")?)?;
        let encoding = match c_str(encoding).filter(|e| !e.is_empty()) {
            None => Encoding::default(),
            Some(name) => {
                let name = String::from_utf8_lossy(name);
                Encoding::from_name(&name).ok_or_else(|| format!("unknown encoding \"{name}\""))?
            }
        };
        let source = FileSource::open(&p).map_err(|e| format!("{}: {e}", p.display()))?;
        let reader = Reader::open(source, Options { encoding }).map_err(|e| e.to_string())?;
        Ok(Box::into_raw(Box::new(DtaFile { reader })))
    })
}

/// # Safety
/// `file` is NULL or a handle from `dta_open` not yet closed.
#[no_mangle]
pub unsafe extern "C" fn dta_close(file: *mut DtaFile) {
    if !file.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(file))));
    }
}

/// # Safety
/// `file` is an open handle; `len` NULL or writable.
#[no_mangle]
pub unsafe extern "C" fn dta_meta_json(file: *mut DtaFile, len: *mut usize, err: *mut c_char, err_len: usize) -> *mut c_char {
    guard(err, err_len, std::ptr::null_mut(), || {
        let reader = &mut file.as_mut().ok_or("the file is NULL")?.reader;
        let sets = reader.value_labels().map_err(|e| e.to_string())?;
        let chars = reader.characteristics().map_err(|e| e.to_string())?;
        let notes = reader.notes().map_err(|e| e.to_string())?;
        let text = json::document(reader.metadata(), &sets, &chars, &notes);
        if !len.is_null() {
            *len = text.len();
        }
        // JSON escapes control characters, so there is no NUL inside.
        Ok(CString::new(text).map_err(|e| e.to_string())?.into_raw())
    })
}

/// # Safety
/// `s` is NULL or came from `dta_meta_json` and was not freed.
#[no_mangle]
pub unsafe extern "C" fn dta_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Values of one chunk column in its storage type, kept between chunks
/// so each chunk reuses the space.
enum Scratch {
    None,
    I8(Vec<i8>),
    I16(Vec<i16>),
    I32(Vec<i32>),
    F32(Vec<f32>),
}

fn storage_code(t: StorageType) -> (u32, u32) {
    match t {
        StorageType::Byte => (BYTE, I8),
        StorageType::Int => (INT, I16),
        StorageType::Long => (LONG, I32),
        StorageType::Float => (FLOAT, F32),
        StorageType::Double => (DOUBLE, F64),
        StorageType::Str(_) => (STR, 0),
        StorageType::StrL => (STRL, 0),
    }
}

/// # Safety
/// See dta.h: `cols` points to `ncols` indices; `callback` must not
/// unwind.
#[no_mangle]
pub unsafe extern "C" fn dta_read(
    file: *mut DtaFile,
    cols: *const u32,
    ncols: usize,
    start: u64,
    count: u64,
    callback: Option<ChunkFn>,
    user: *mut c_void,
    err: *mut c_char,
    err_len: usize,
) -> i64 {
    guard(err, err_len, -1, || {
        let reader = &mut file.as_mut().ok_or("the file is NULL")?.reader;
        let callback = callback.ok_or("the callback is NULL")?;
        let cols: Vec<usize> = slice(cols, ncols, "cols")?.iter().map(|&c| c as usize).collect();
        let nobs = reader.metadata().nobs;
        if start.checked_add(count).is_none_or(|end| end > nobs) {
            return Err(format!("rows {start} to {} are past the {nobs} rows in the file", start.saturating_add(count)));
        }
        let nvar = reader.metadata().variables.len();
        if let Some(&bad) = cols.iter().find(|&&c| c >= nvar) {
            return Err(format!("there is no variable {bad}; the file has {nvar}"));
        }
        if cols.is_empty() {
            return Ok(count as i64);
        }
        let types: Vec<StorageType> = cols.iter().map(|&c| reader.metadata().variables[c].storage).collect();
        let mut scratch: Vec<Scratch> = types
            .iter()
            .map(|t| match t {
                StorageType::Byte => Scratch::I8(Vec::new()),
                StorageType::Int => Scratch::I16(Vec::new()),
                StorageType::Long => Scratch::I32(Vec::new()),
                StorageType::Float => Scratch::F32(Vec::new()),
                _ => Scratch::None,
            })
            .collect();
        let mut offsets: Vec<Vec<u64>> = vec![Vec::new(); cols.len()];
        let mut views: Vec<DtaColumn> = types
            .iter()
            .map(|&t| {
                let (s, v) = storage_code(t);
                DtaColumn::empty(s, v)
            })
            .collect();
        let mut cancelled = false;
        let result = reader.read_chunks(&cols, start, count, None, |first, chunk| {
            let nrows = chunk[0].len();
            for (k, column) in chunk.iter().enumerate() {
                let view = &mut views[k];
                match column {
                    Column::Numbers { values, missing } => {
                        // A missing value's NaN becomes 0 in an integer type.
                        view.values = match &mut scratch[k] {
                            Scratch::I8(v) => fill(v, values, |x| x as i8),
                            Scratch::I16(v) => fill(v, values, |x| x as i16),
                            Scratch::I32(v) => fill(v, values, |x| x as i32),
                            Scratch::F32(v) => fill(v, values, |x| x as f32),
                            Scratch::None => values.as_ptr() as *const c_void,
                        };
                        view.codes = if missing.iter().any(|&m| m != 0) { missing.as_ptr() } else { std::ptr::null() };
                    }
                    Column::Strings { bytes, ends, binary } => {
                        let o = &mut offsets[k];
                        o.clear();
                        o.push(0);
                        o.extend(ends.iter().map(|&e| e as u64));
                        view.bytes = bytes.as_ptr();
                        view.offsets = o.as_ptr();
                        // bool is one byte, 0 or 1.
                        view.binary =
                            if binary.iter().any(|&b| b) { binary.as_ptr() as *const u8 } else { std::ptr::null() };
                    }
                }
            }
            if callback(user, first as u64, nrows as u64, views.as_ptr()) != 0 {
                cancelled = true;
                return Err(dta::Error::new("the read was cancelled"));
            }
            Ok(())
        });
        match result {
            Ok(n) => Ok(n as i64),
            Err(_) if cancelled => Ok(-2),
            Err(e) => Err(e.to_string()),
        }
    })
}

fn fill<T>(out: &mut Vec<T>, values: &[f64], f: impl Fn(f64) -> T) -> *const c_void {
    out.clear();
    out.extend(values.iter().map(|&x| f(x)));
    out.as_ptr() as *const c_void
}

/// A number from a host buffer, as f64.
trait Number: Copy + Sync {
    fn f64(self) -> f64;
}

macro_rules! number {
    ($($t:ty),*) => {$(impl Number for $t {
        #[inline]
        fn f64(self) -> f64 {
            self as f64
        }
    })*};
}
number!(i8, i16, i32, i64, f32, f64, u8);

fn numbers<'a, T: Number>(values: &'a [T], codes: Option<&'a [u8]>) -> dta::Values<'a> {
    // NaN with no code is `.`.
    let code = |x: f64, c: u8| if c == 0 && x.is_nan() { 1 } else { c };
    match codes {
        Some(codes) => dta::Values::numbers_by_row(move |i| {
            let x = values[i].f64();
            (x, code(x, codes[i]))
        }),
        None => dta::Values::numbers_by_row(move |i| {
            let x = values[i].f64();
            (x, code(x, 0))
        }),
    }
}

/// # Safety
/// `c` describes `nrows` rows as dta.h says.
unsafe fn values<'a>(c: &DtaColumn, nrows: usize, name: &str) -> Result<(StorageType, dta::Values<'a>), String> {
    let storage = match c.storage {
        BYTE => StorageType::Byte,
        INT => StorageType::Int,
        LONG => StorageType::Long,
        FLOAT => StorageType::Float,
        DOUBLE => StorageType::Double,
        STR => StorageType::Str(1),
        STRL => StorageType::StrL,
        other => return Err(format!("{name}: unknown storage type {other}")),
    };
    if storage.is_numeric() {
        let codes = if c.codes.is_null() { None } else { Some(slice(c.codes, nrows, "codes")?) };
        if codes.is_some_and(|codes| codes.iter().any(|&m| m > dta::missing::LAST)) {
            return Err(format!("{name}: a missing code is above 27 (.z)"));
        }
        let v = c.values;
        let what = "values";
        let values = match c.value_type {
            I8 => numbers(slice(v as *const i8, nrows, what)?, codes),
            I16 => numbers(slice(v as *const i16, nrows, what)?, codes),
            I32 => numbers(slice(v as *const i32, nrows, what)?, codes),
            I64 => numbers(slice(v as *const i64, nrows, what)?, codes),
            F32 => numbers(slice(v as *const f32, nrows, what)?, codes),
            F64 => numbers(slice(v as *const f64, nrows, what)?, codes),
            U8 => numbers(slice(v as *const u8, nrows, what)?, codes),
            other => return Err(format!("{name}: unknown value type {other}")),
        };
        return Ok((storage, values));
    }
    let offsets = slice(c.offsets, nrows + 1, "offsets")?;
    if offsets.first().is_some_and(|&o| o != 0) || offsets.windows(2).any(|w| w[0] > w[1]) {
        return Err(format!("{name}: string offsets must start at 0 and not decrease"));
    }
    let total = usize::try_from(*offsets.last().unwrap_or(&0)).map_err(|_| "strings too large")?;
    let bytes = slice(c.bytes, total, "bytes")?;
    let at = move |i: usize| &bytes[offsets[i] as usize..offsets[i + 1] as usize];
    if c.binary.is_null() {
        return Ok((storage, dta::Values::Strings(Box::new(at))));
    }
    if storage != StorageType::StrL {
        return Err(format!("{name}: only a strL column can hold binary values"));
    }
    let binary = slice(c.binary, nrows, "binary")?;
    Ok((storage, dta::Values::StrLs(Box::new(move |i| (at(i), binary[i] != 0)))))
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
            let (value, missing) = match value {
                Value::Number(x) => (*x, 0),
                Value::String(m) => {
                    (f64::NAN, dta::missing::from_name(m).ok_or_else(|| format!("\"{m}\" is not a missing value"))?)
                }
                _ => return Err("a labelled value must be a number or a missing value such as \".a\"".into()),
            };
            labels.push(ValueLabel { value, missing, text: text.clone() });
        }
        sets.push(ValueLabelSet { name: set.str("name")?.to_string(), labels });
    }
    Ok(sets)
}

fn characteristics(doc: &Value) -> Result<Vec<Characteristic>, String> {
    let mut out = Vec::new();
    for c in doc.array("characteristics")? {
        out.push(Characteristic {
            variable: c.str("variable")?.to_string(),
            name: c.str("name")?.to_string(),
            value: c.str("value")?.to_string(),
        });
    }
    out.retain(|c| !json::is_note(c));
    let notes = doc.array("notes")?;
    if !notes.is_empty() {
        let note = |n: usize, value: &str| Characteristic { variable: "_dta".into(), name: format!("note{n}"), value: value.into() };
        out.push(note(0, &notes.len().to_string()));
        for (i, n) in notes.iter().enumerate() {
            let Value::String(text) = n else { return Err("notes must be strings".into()) };
            out.push(note(i + 1, text));
        }
    }
    Ok(out)
}

/// # Safety
/// See dta.h: `columns` points to `ncols` columns whose buffers hold
/// `nrows` rows; `meta_json` is NUL-terminated.
#[no_mangle]
pub unsafe extern "C" fn dta_write(
    path_: *const c_char,
    nrows: u64,
    columns: *const DtaColumn,
    ncols: usize,
    meta_json: *const c_char,
    err: *mut c_char,
    err_len: usize,
) -> c_int {
    guard(err, err_len, -1, || {
        let target = path(c_str(path_).ok_or("the path is NULL")?)?;
        let text = c_str(meta_json).map(String::from_utf8_lossy).unwrap_or_default();
        let doc = if text.trim().is_empty() { Value::Object(Vec::new()) } else { json::parse(&text)? };
        let nrows = usize::try_from(nrows).map_err(|_| "too many rows")?;
        let columns = slice(columns, ncols, "columns")?;
        let described = doc.array("variables")?;
        if described.len() != ncols {
            return Err(format!("the metadata describes {} variables, but there are {ncols} columns", described.len()));
        }
        let mut variables = Vec::with_capacity(ncols);
        for (c, v) in columns.iter().zip(described) {
            let name = v.str("name")?.to_string();
            let (storage, values) = values(c, nrows, &name)?;
            variables.push(dta::WriteVariable {
                storage,
                format: v.str("format")?.to_string(),
                label: v.str("label")?.to_string(),
                value_labels: v.str("valueLabels")?.to_string(),
                values,
                name,
            });
        }
        let mut sort_order = Vec::new();
        for s in doc.array("sortedBy")? {
            match s {
                Value::Number(i) if *i >= 0.0 && i.fract() == 0.0 => sort_order.push(*i as usize),
                _ => return Err("sortedBy must list variable indices".into()),
            }
        }
        let data = dta::Dataset {
            nobs: nrows,
            label: doc.str("label")?.to_string(),
            timestamp: doc.str("timestamp")?.to_string(),
            variables,
            value_labels: label_sets(&doc)?,
            characteristics: characteristics(&doc)?,
            sort_order,
        };
        // Write beside the target and rename, so a failed write leaves
        // any file already there alone.
        let (tmp, file) = create_beside(&target)?;
        let written = dta::write(&data, file).map_err(|e| e.to_string());
        let renamed = written.and_then(|_| std::fs::rename(&tmp, &target).map_err(|e| format!("{}: {e}", target.display())));
        if renamed.is_err() {
            let _ = std::fs::remove_file(&tmp);
        }
        renamed.map(|_| 0)
    })
}

/// A new file beside `target` that no other call has: created exclusively,
/// so an existing file or symlink at a name is never opened or removed.
fn create_beside(target: &std::path::Path) -> Result<(std::path::PathBuf, File), String> {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_panic_becomes_an_error() {
        let mut err = [0u8; 64];
        let p = err.as_mut_ptr() as *mut c_char;
        let got: i32 = guard(p, 64, -1, || panic!("boom"));
        assert_eq!(got, -1);
        let text = CStr::from_bytes_until_nul(&err).unwrap().to_str().unwrap();
        assert_eq!(text, "internal error in dta-parser: boom");
        assert_eq!(guard(p, 64, -1, || Ok(7)), 7);
        assert_eq!(err[0], 0);
    }
}
