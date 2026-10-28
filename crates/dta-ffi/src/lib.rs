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

mod json;

use std::cell::RefCell;
use std::panic::{catch_unwind, AssertUnwindSafe};

use dta::{Column, Encoding, Options, Reader, Source};

#[cfg(target_arch = "wasm32")]
#[link(wasm_import_module = "env")]
extern "C" {
    /// Fill `len` bytes at `ptr` from `file` at `offset`; 0 on success.
    fn host_read(file: u32, ptr: *mut u8, len: usize, offset: f64) -> i32;
}

#[cfg(not(target_arch = "wasm32"))]
unsafe fn host_read(_file: u32, _ptr: *mut u8, _len: usize, _offset: f64) -> i32 {
    1
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
