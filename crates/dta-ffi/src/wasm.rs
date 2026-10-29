//! The C ABI the npm package's wasm module exports.
//!
//! The module reads files through one import, `host_read(file, ptr, len,
//! offset)`, which JavaScript implements over `fs.readSync` or a
//! `Uint8Array`, so a file never has to fit in wasm memory. Offsets and
//! counts that may exceed 2^32 cross as `f64`.
//!
//! Calls return 0 (or a null pointer) on failure; `dta_error` then holds
//! the message. Results larger than a number (JSON, column buffers) are
//! left in module memory: the call returns a pointer, `dta_result_len`
//! gives the length, and the bytes stay valid until the next call on the
//! same handle. Panics are caught and reported as errors.

use std::cell::RefCell;
use std::panic::{catch_unwind, AssertUnwindSafe};

use dta::{Column, Encoding, Options, Reader, Source};

use crate::json;

#[link(wasm_import_module = "env")]
extern "C" {
    /// Fill `len` bytes at `ptr` from `file` at `offset`; 0 on success.
    fn host_read(file: u32, ptr: *mut u8, len: usize, offset: f64) -> i32;
}

/// A file JavaScript holds, known to us by number.
struct HostFile {
    id: u32,
    len: u64,
}

impl Source for HostFile {
    fn len(&self) -> u64 {
        self.len
    }

    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> dta::Result<()> {
        if offset.checked_add(buf.len() as u64).is_none_or(|end| end > self.len) {
            return Err(dta::Error::at(offset, "unexpected end of file"));
        }
        match unsafe { host_read(self.id, buf.as_mut_ptr(), buf.len(), offset as f64) } {
            0 => Ok(()),
            _ => Err(dta::Error::at(offset, "the file could not be read")),
        }
    }
}

struct Handle {
    reader: Reader<HostFile>,
    columns: Vec<Column>,
}

#[derive(Default)]
struct State {
    handles: Vec<Option<Handle>>,
    error: String,
    result: Vec<u8>,
    result_len: usize,
}

thread_local! {
    static STATE: RefCell<State> = RefCell::new(State::default());
}

/// Run `f` on the state, turning an error or a panic into `fail`.
fn call<T>(fail: T, f: impl FnOnce(&mut State) -> Result<T, String>) -> T {
    STATE.with(|cell| {
        let mut state = cell.borrow_mut();
        state.error.clear();
        match catch_unwind(AssertUnwindSafe(|| f(&mut state))) {
            Ok(Ok(v)) => v,
            Ok(Err(message)) => {
                state.error = message;
                fail
            }
            Err(_) => {
                state.error = "internal error in dta-parser".into();
                fail
            }
        }
    })
}

fn handle(state: &mut State, h: u32) -> Result<&mut Handle, String> {
    state
        .handles
        .get_mut(h.wrapping_sub(1) as usize)
        .and_then(Option::as_mut)
        .ok_or_else(|| "the file is closed".to_string())
}

/// Leave `bytes` as the result and return a pointer to it.
fn result(state: &mut State, bytes: Vec<u8>) -> *const u8 {
    state.result_len = bytes.len();
    state.result = bytes;
    state.result.as_ptr()
}

#[no_mangle]
pub extern "C" fn dta_alloc(len: usize) -> *mut u8 {
    let mut v = Vec::<u8>::with_capacity(len.max(1));
    let p = v.as_mut_ptr();
    std::mem::forget(v);
    p
}

/// # Safety
/// `ptr` and `len` must come from one `dta_alloc` call.
#[no_mangle]
pub unsafe extern "C" fn dta_free(ptr: *mut u8, len: usize) {
    drop(Vec::from_raw_parts(ptr, 0, len.max(1)));
}

#[no_mangle]
pub extern "C" fn dta_error() -> *const u8 {
    STATE.with(|cell| {
        let mut state = cell.borrow_mut();
        let message = state.error.clone().into_bytes();
        result(&mut state, message)
    })
}

#[no_mangle]
pub extern "C" fn dta_result_len() -> usize {
    STATE.with(|cell| cell.borrow().result_len)
}

/// Open host file `file` of `len` bytes. `encoding` is 0 for
/// Windows-1252, 1 for Latin-1, 2 for UTF-8 (files before 118 only).
/// Returns a handle, or 0.
#[no_mangle]
pub extern "C" fn dta_open(file: u32, len: f64, encoding: u32) -> u32 {
    call(0, |state| {
        let encoding = match encoding {
            0 => Encoding::Windows1252,
            1 => Encoding::Latin1,
            2 => Encoding::Utf8,
            _ => return Err("unknown encoding".into()),
        };
        let source = HostFile { id: file, len: len as u64 };
        let reader = Reader::open(source, Options { encoding }).map_err(|e| e.to_string())?;
        state.handles.push(Some(Handle { reader, columns: Vec::new() }));
        Ok(state.handles.len() as u32)
    })
}

#[no_mangle]
pub extern "C" fn dta_close(h: u32) {
    call((), |state| {
        if let Some(slot) = state.handles.get_mut(h.wrapping_sub(1) as usize) {
            *slot = None;
        }
        Ok(())
    })
}

/// The header and descriptors as JSON.
#[no_mangle]
pub extern "C" fn dta_metadata(h: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let bytes = json::metadata(handle(state, h)?.reader.metadata()).into_bytes();
        Ok(result(state, bytes))
    })
}

/// Every value label set as JSON.
#[no_mangle]
pub extern "C" fn dta_value_labels(h: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let sets = handle(state, h)?.reader.value_labels().map_err(|e| e.to_string())?;
        Ok(result(state, json::value_labels(&sets).into_bytes()))
    })
}

/// Every characteristic as JSON.
#[no_mangle]
pub extern "C" fn dta_characteristics(h: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let chars = handle(state, h)?.reader.characteristics().map_err(|e| e.to_string())?;
        Ok(result(state, json::characteristics(&chars).into_bytes()))
    })
}

/// Read up to `count` rows from `start` of the `ncols` variables listed
/// (u32 indices) at `cols`, stopping after the row at which the decoded
/// output reaches 64 MiB, so module memory stays bounded. The columns
/// stay in the handle for `dta_column_part` until the next read. Returns
/// the number of rows read, or -1 on failure.
///
/// # Safety
/// `cols` must point to `ncols` u32 values.
#[no_mangle]
pub unsafe extern "C" fn dta_read(h: u32, cols: *const u32, ncols: usize, start: f64, count: f64) -> f64 {
    let cols: Vec<usize> = std::slice::from_raw_parts(cols, ncols).iter().map(|&c| c as usize).collect();
    call(-1.0, |state| {
        let handle = handle(state, h)?;
        let Handle { reader, columns } = handle;
        columns.clear();
        let mut first = true;
        let n = reader
            .read_chunks(&cols, start as u64, count as u64, Some(BUDGET), |_, chunk| {
                if first {
                    *columns = chunk.to_vec();
                    first = false;
                } else {
                    for (all, part) in columns.iter_mut().zip(chunk) {
                        all.append(part);
                    }
                }
                Ok(())
            })
            .map_err(|e| e.to_string())?;
        Ok(n as f64)
    })
}

/// Decoded bytes one read may hold in module memory (plus one row).
const BUDGET: usize = 64 << 20;

/// A buffer of read column `k`: `part` 0 is the f64 values or the
/// string bytes, 1 the missing codes (u8) or the string ends (u32), 2
/// the binary flags (u8) of a strL column. Returns a pointer;
/// `dta_result_len` gives the element count.
#[no_mangle]
pub extern "C" fn dta_column_part(h: u32, k: usize, part: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let column = handle(state, h)?.columns.get(k).ok_or("no such column")?;
        let (ptr, len) = match (column, part) {
            (Column::Numbers { values, .. }, 0) => (values.as_ptr() as *const u8, values.len()),
            (Column::Numbers { missing, .. }, 1) => (missing.as_ptr(), missing.len()),
            (Column::Strings { bytes, .. }, 0) => (bytes.as_ptr(), bytes.len()),
            (Column::Strings { ends, .. }, 1) => (ends.as_ptr() as *const u8, ends.len()),
            (Column::Strings { binary, .. }, 2) => (binary.as_ptr() as *const u8, binary.len()),
            _ => return Err("no such column part".into()),
        };
        state.result_len = len;
        Ok(ptr)
    })
}

// Writing. JavaScript builds a dataset with the calls below, copying
// each column into module memory, then `dta_write_finish` streams the
// file out through `host_write`.

#[link(wasm_import_module = "env")]
extern "C" {
    /// Write `len` bytes at `ptr` to `file`; 0 on success.
    fn host_write(file: u32, ptr: *const u8, len: usize) -> i32;
}

struct HostSink(u32);

impl std::io::Write for HostSink {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        match unsafe { host_write(self.0, buf.as_ptr(), buf.len()) } {
            0 => Ok(buf.len()),
            _ => Err(std::io::Error::other("the file could not be written")),
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

enum WriteData {
    Numbers(Vec<f64>, Vec<u8>),
    Strings(Vec<u8>, Vec<u32>),
    /// strLs: bytes, ends, and per row 1 if binary.
    StrLs(Vec<u8>, Vec<u32>, Vec<u8>),
}

struct WriteColumn {
    name: String,
    storage: dta::StorageType,
    format: String,
    label: String,
    value_labels: String,
    data: WriteData,
}

#[derive(Default)]
struct WriteState {
    nobs: usize,
    columns: Vec<WriteColumn>,
    sets: Vec<dta::ValueLabelSet>,
    characteristics: Vec<dta::Characteristic>,
    sort_order: Vec<usize>,
}

thread_local! {
    static WRITE: RefCell<WriteState> = RefCell::new(WriteState::default());
}

/// # Safety
/// `ptr` points to `len` readable elements of T.
unsafe fn copy<T: Copy>(ptr: *const T, len: usize) -> Vec<T> {
    if len == 0 {
        Vec::new()
    } else {
        std::slice::from_raw_parts(ptr, len).to_vec()
    }
}

/// Fields separated by NUL: name, format, label, value label set name.
fn fields(bytes: &[u8]) -> Result<Vec<String>, String> {
    std::str::from_utf8(bytes)
        .map(|s| s.split('\0').map(str::to_string).collect())
        .map_err(|_| "names and labels must be UTF-8".to_string())
}

/// Start a new dataset of `nobs` rows, dropping any half-built one.
#[no_mangle]
pub extern "C" fn dta_write_begin(nobs: f64) {
    WRITE.with(|w| *w.borrow_mut() = WriteState { nobs: nobs as usize, ..Default::default() });
}

/// Add a numeric column: `meta` holds NUL-separated name, format,
/// label, value label set; `storage` 0 to 4 is byte, int, long, float,
/// double; `values` and `missing` hold `nobs` elements each.
///
/// # Safety
/// The pointers hold the stated lengths.
#[no_mangle]
pub unsafe extern "C" fn dta_write_numbers(
    meta: *const u8,
    meta_len: usize,
    storage: u32,
    values: *const f64,
    missing: *const u8,
) -> u32 {
    call(0, |_| {
        let f = fields(&copy(meta, meta_len))?;
        let storage = [
            dta::StorageType::Byte,
            dta::StorageType::Int,
            dta::StorageType::Long,
            dta::StorageType::Float,
            dta::StorageType::Double,
        ]
        .get(storage as usize)
        .copied()
        .ok_or("unknown storage type")?;
        WRITE.with(|w| {
            let mut w = w.borrow_mut();
            let n = w.nobs;
            let column = column(&f, storage, WriteData::Numbers(copy(values, n), copy(missing, n)))?;
            w.columns.push(column);
            Ok(1)
        })
    })
}

/// Add a string column: `bytes` and `nobs` end offsets. With `binary`
/// null, the values are UTF-8 text, written as strN or, beyond 2045
/// bytes, strL. Otherwise the column is strL and `binary` holds `nobs`
/// flags: 1 where the value is binary bytes, 0 where it is UTF-8 text.
///
/// # Safety
/// The pointers hold the stated lengths; `binary` is null or holds
/// `nobs` bytes.
#[no_mangle]
pub unsafe extern "C" fn dta_write_strings(
    meta: *const u8,
    meta_len: usize,
    bytes: *const u8,
    bytes_len: usize,
    ends: *const u32,
    binary: *const u8,
) -> u32 {
    call(0, |_| {
        let f = fields(&copy(meta, meta_len))?;
        WRITE.with(|w| {
            let mut w = w.borrow_mut();
            let ends = copy(ends, w.nobs);
            if ends.iter().any(|&e| e as usize > bytes_len) || ends.windows(2).any(|p| p[0] > p[1]) {
                return Err("string offsets out of order".into());
            }
            let bytes = copy(bytes, bytes_len);
            let (storage, data) = if binary.is_null() {
                (dta::StorageType::Str(1), WriteData::Strings(bytes, ends))
            } else {
                (dta::StorageType::StrL, WriteData::StrLs(bytes, ends, copy(binary, w.nobs)))
            };
            let column = column(&f, storage, data)?;
            w.columns.push(column);
            Ok(1)
        })
    })
}

fn column(f: &[String], storage: dta::StorageType, data: WriteData) -> Result<WriteColumn, String> {
    let [name, format, label, value_labels] = f else { return Err("expected four fields".into()) };
    Ok(WriteColumn {
        name: name.clone(),
        storage,
        format: format.clone(),
        label: label.clone(),
        value_labels: value_labels.clone(),
        data,
    })
}

/// Add a value label set: `n` values with missing codes, and texts as
/// UTF-8 bytes with `n` end offsets.
///
/// # Safety
/// The pointers hold the stated lengths.
#[no_mangle]
pub unsafe extern "C" fn dta_write_labels(
    name: *const u8,
    name_len: usize,
    n: usize,
    values: *const f64,
    missing: *const u8,
    texts: *const u8,
    texts_len: usize,
    ends: *const u32,
) -> u32 {
    call(0, |_| {
        let name = String::from_utf8(copy(name, name_len)).map_err(|_| "label set names must be UTF-8")?;
        let (values, codes, ends) = (copy(values, n), copy(missing, n), copy(ends, n));
        let texts = String::from_utf8(copy(texts, texts_len)).map_err(|_| "labels must be UTF-8")?;
        let mut labels = Vec::with_capacity(n);
        let mut from = 0;
        for i in 0..n {
            let to = ends[i] as usize;
            let text = texts.get(from..to).ok_or("label offsets out of order")?.to_string();
            labels.push(dta::ValueLabel { value: values[i], missing: codes[i], text });
            from = to;
        }
        WRITE.with(|w| w.borrow_mut().sets.push(dta::ValueLabelSet { name, labels }));
        Ok(1)
    })
}

/// Add characteristics: `text` holds NUL-separated variable, name and
/// value, three fields per characteristic.
///
/// # Safety
/// `text` holds `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn dta_write_characteristics(text: *const u8, len: usize) -> u32 {
    call(0, |_| {
        let f = fields(&copy(text, len))?;
        if f.len() % 3 != 0 {
            return Err("expected three fields per characteristic".into());
        }
        let chars = f.chunks_exact(3).map(|c| dta::Characteristic {
            variable: c[0].clone(),
            name: c[1].clone(),
            value: c[2].clone(),
        });
        WRITE.with(|w| w.borrow_mut().characteristics.extend(chars));
        Ok(1)
    })
}

/// Set the sort order: `n` 0-based variable indices.
///
/// # Safety
/// `indices` holds `n` u32 values.
#[no_mangle]
pub unsafe extern "C" fn dta_write_sort_order(indices: *const u32, n: usize) -> u32 {
    call(0, |_| {
        let order = copy(indices, n).into_iter().map(|i| i as usize).collect();
        WRITE.with(|w| w.borrow_mut().sort_order = order);
        Ok(1)
    })
}

/// Write the dataset to host file `file`. `info` holds NUL-separated
/// data label, timestamp, then the notes, which follow the
/// characteristics added. Returns 1, or 0 on failure.
///
/// # Safety
/// `info` holds `info_len` bytes.
#[no_mangle]
pub unsafe extern "C" fn dta_write_finish(file: u32, info: *const u8, info_len: usize) -> u32 {
    call(0, |_| {
        let info = fields(&copy(info, info_len))?;
        let state = WRITE.with(|w| std::mem::take(&mut *w.borrow_mut()));
        let notes: Vec<&String> = info.iter().skip(2).collect();
        let mut characteristics = state.characteristics;
        if !notes.is_empty() {
            let note = |n: usize, value: &str| dta::Characteristic {
                variable: "_dta".into(),
                name: format!("note{n}"),
                value: value.into(),
            };
            characteristics.push(note(0, &notes.len().to_string()));
            characteristics.extend(notes.iter().enumerate().map(|(i, v)| note(i + 1, v)));
        }
        let variables = state
            .columns
            .iter()
            .map(|c| dta::WriteVariable {
                name: c.name.clone(),
                storage: c.storage,
                format: c.format.clone(),
                label: c.label.clone(),
                value_labels: c.value_labels.clone(),
                values: match &c.data {
                    WriteData::Numbers(v, m) => dta::Values::Numbers(Box::new(move |i| (v[i], m[i]))),
                    WriteData::Strings(b, e) => dta::Values::Strings(Box::new(move |i| {
                        let start = if i == 0 { 0 } else { e[i - 1] as usize };
                        &b[start..e[i] as usize]
                    })),
                    WriteData::StrLs(b, e, binary) => dta::Values::StrLs(Box::new(move |i| {
                        let start = if i == 0 { 0 } else { e[i - 1] as usize };
                        (&b[start..e[i] as usize], binary[i] != 0)
                    })),
                },
            })
            .collect();
        let data = dta::Dataset {
            nobs: state.nobs,
            label: info.first().cloned().unwrap_or_default(),
            timestamp: info.get(1).cloned().unwrap_or_default(),
            variables,
            value_labels: state.sets.clone(),
            characteristics,
            sort_order: state.sort_order,
        };
        dta::write(&data, HostSink(file)).map_err(|e| e.to_string())?;
        Ok(1)
    })
}
