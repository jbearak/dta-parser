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
//! same handle. Panics are caught and reported as errors. `dta_error_kind`
//! says what sort of error the last one was, so JavaScript can give it a
//! code without reading the message.

use std::alloc::{GlobalAlloc, Layout, System};
use std::borrow::Cow;
use std::cell::RefCell;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicPtr, Ordering};

use dta::{Column, Encoding, ErrorKind, Options, Reader, Source, StorageType};

use crate::json;
use crate::strings::{self, Dict, Strings};

// Running out of module memory must be an error, not a trap (plan 0008
// M2): large allocations are fallible (`try_reserve`, room checks), and
// a 1 MiB reserve, freed the first time any allocation fails, leaves
// room for the small ones that report the failure. Each call takes the
// reserve back before it starts.

const RESERVE_BYTES: usize = 1 << 20;
static RESERVE: AtomicPtr<u8> = AtomicPtr::new(std::ptr::null_mut());

fn reserve_layout() -> Layout {
    Layout::from_size_align(RESERVE_BYTES, 16).unwrap_or(Layout::new::<u8>())
}

/// Free the reserve, if held; true if it was.
fn release_reserve() -> bool {
    let r = RESERVE.swap(std::ptr::null_mut(), Ordering::Relaxed);
    if r.is_null() {
        return false;
    }
    unsafe { System.dealloc(r, reserve_layout()) };
    true
}

/// Hold the reserve again; false if memory is too short for it.
fn take_reserve() -> bool {
    if !RESERVE.load(Ordering::Relaxed).is_null() {
        return true;
    }
    let p = unsafe { System.alloc(reserve_layout()) };
    RESERVE.store(p, Ordering::Relaxed);
    !p.is_null()
}

struct WithReserve;

unsafe impl GlobalAlloc for WithReserve {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let p = System.alloc(layout);
        if p.is_null() && release_reserve() {
            System.alloc(layout)
        } else {
            p
        }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let p = System.alloc_zeroed(layout);
        if p.is_null() && release_reserve() {
            System.alloc_zeroed(layout)
        } else {
            p
        }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let p = System.realloc(ptr, layout, new_size);
        if p.is_null() && release_reserve() {
            System.realloc(ptr, layout, new_size)
        } else {
            p
        }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        System.dealloc(ptr, layout)
    }
}

#[global_allocator]
static ALLOCATOR: WithReserve = WithReserve;

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
            _ => Err(dta::Error::at(offset, "the file could not be read").of(ErrorKind::Io)),
        }
    }
}

struct Handle {
    reader: Reader<HostFile>,
    columns: Vec<Column>,
    /// Per read column: its dictionary over the current read, and what
    /// the last call hands JavaScript for it (None for numbers).
    dicts: Vec<Dict>,
    strings: Vec<Option<Strings>>,
}

struct State {
    handles: Vec<Option<Handle>>,
    /// Static when there was no memory to make a message.
    error: Cow<'static, str>,
    error_kind: u32,
    /// Most decoded bytes a read call holds (`BUDGET`; tests lower it).
    budget: usize,
    /// Bytes per decoded chunk for readers opened from now (0: the
    /// core's default; tests lower it).
    chunk_bytes: usize,
    /// Longest string JavaScript can make, in UTF-16 units, for readers
    /// opened from now (tests lower it).
    string_limit: usize,
    result: Vec<u8>,
    result_len: usize,
}

impl Default for State {
    fn default() -> Self {
        State {
            handles: Vec::new(),
            error: Cow::Borrowed(""),
            error_kind: 0,
            budget: BUDGET,
            chunk_bytes: 0,
            string_limit: STRING_LIMIT,
            result: Vec::new(),
            result_len: 0,
        }
    }
}

thread_local! {
    static STATE: RefCell<State> = RefCell::new(State::default());
}

/// Test builds only (`--features test-hooks`): lower the read budget, and
/// the chunk size and string limit of readers opened from now, so small
/// files exercise what large ones do.
#[cfg(feature = "test-hooks")]
#[no_mangle]
pub extern "C" fn dta_test_set(budget: usize, chunk_bytes: usize, string_limit: usize) {
    STATE.with(|cell| {
        let mut state = cell.borrow_mut();
        state.budget = budget;
        state.chunk_bytes = chunk_bytes;
        state.string_limit = string_limit;
    })
}

/// An error for JavaScript: its kind (see `dta_error_kind`) and message.
struct Fail {
    kind: u32,
    message: String,
}

// The kinds `dta_error_kind` returns.
const CORRUPT: u32 = 1;
const TOO_LARGE: u32 = 2;
const IO: u32 = 3;
const INVALID: u32 = 4;
const OUT_OF_RANGE: u32 = 5;
const INTERNAL: u32 = 6;
const CLOSED: u32 = 7;

impl From<dta::Error> for Fail {
    fn from(e: dta::Error) -> Self {
        let kind = match e.kind {
            ErrorKind::Corrupt => CORRUPT,
            ErrorKind::TooLarge => TOO_LARGE,
            ErrorKind::Io => IO,
            ErrorKind::Invalid => INVALID,
            ErrorKind::OutOfRange => OUT_OF_RANGE,
            ErrorKind::Internal => INTERNAL,
        };
        Fail { kind, message: e.to_string() }
    }
}

/// A plain message is a mistake in what JavaScript passed.
impl From<String> for Fail {
    fn from(message: String) -> Self {
        Fail { kind: INVALID, message }
    }
}

impl From<&str> for Fail {
    fn from(message: &str) -> Self {
        message.to_string().into()
    }
}

/// Run `f` on the state, turning an error or a panic into `fail`.
fn call<T>(fail: T, f: impl FnOnce(&mut State) -> Result<T, Fail>) -> T {
    STATE.with(|cell| {
        let mut state = cell.borrow_mut();
        state.error = Cow::Borrowed("");
        state.error_kind = 0;
        if !take_reserve() {
            state.error = Cow::Borrowed("module memory is full; close readers or read less at once");
            state.error_kind = TOO_LARGE;
            return fail;
        }
        match catch_unwind(AssertUnwindSafe(|| f(&mut state))) {
            Ok(Ok(v)) => v,
            Ok(Err(e)) => {
                state.error = Cow::Owned(e.message);
                state.error_kind = e.kind;
                fail
            }
            Err(_) => {
                state.error = Cow::Borrowed("internal error in dta-parser");
                state.error_kind = INTERNAL;
                fail
            }
        }
    })
}

fn handle(state: &mut State, h: u32) -> Result<&mut Handle, Fail> {
    state
        .handles
        .get_mut(h.wrapping_sub(1) as usize)
        .and_then(Option::as_mut)
        .ok_or_else(|| Fail { kind: CLOSED, message: "the file is closed".into() })
}

/// Leave `bytes` as the result and return a pointer to it.
fn result(state: &mut State, bytes: Vec<u8>) -> *const u8 {
    state.result_len = bytes.len();
    state.result = bytes;
    state.result.as_ptr()
}

#[no_mangle]
pub extern "C" fn dta_alloc(len: usize) -> *mut u8 {
    // Null when memory is short; JavaScript checks.
    let mut v = Vec::<u8>::new();
    if v.try_reserve_exact(len.max(1)).is_err() {
        return std::ptr::null_mut();
    }
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
        // No copy: there may be no memory to make one.
        let mut state = cell.borrow_mut();
        state.result_len = state.error.len();
        state.error.as_ptr()
    })
}

/// The kind of the last error: 1 a damaged file, 2 too large to read
/// here, 3 the file or output failed, 4 a bad argument, 5 a variable
/// or rows outside the file, 6 a bug, 7 a closed file.
#[no_mangle]
pub extern "C" fn dta_error_kind() -> u32 {
    STATE.with(|cell| cell.borrow().error_kind)
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
        let defaults = Options::default();
        let chunk_bytes = if state.chunk_bytes > 0 { state.chunk_bytes } else { defaults.chunk_bytes };
        let max_text_units = Some(state.string_limit);
        let reader = Reader::open(source, Options { encoding, chunk_bytes, max_text_units, ..defaults })?;
        state.handles.push(Some(Handle { reader, columns: Vec::new(), dicts: Vec::new(), strings: Vec::new() }));
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
        let meta = handle(state, h)?.reader.metadata();
        // JSON escapes a byte into at most six.
        let texts = meta.label.len() + meta.timestamp.len()
            + meta.variables.iter().map(|v| v.name.len() + v.format.len() + v.label.len() + v.value_labels.len() + 24).sum::<usize>();
        ensure_room(texts.saturating_mul(6).saturating_add(256))?;
        let bytes = json::metadata(handle(state, h)?.reader.metadata()).into_bytes();
        Ok(result(state, bytes))
    })
}

/// Every value label set as JSON.
#[no_mangle]
pub extern "C" fn dta_value_labels(h: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let sets = handle(state, h)?.reader.value_labels()?;
        let texts: usize = sets.iter().map(|s| s.name.len() + s.labels.iter().map(|l| l.text.len() + 12).sum::<usize>() + 16).sum();
        ensure_room(texts.saturating_mul(6).saturating_add(256))?;
        Ok(result(state, json::value_labels(&sets).into_bytes()))
    })
}

/// Every characteristic as JSON.
#[no_mangle]
pub extern "C" fn dta_characteristics(h: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let chars = handle(state, h)?.reader.characteristics()?;
        let texts: usize = chars.iter().map(|c| c.variable.len() + c.name.len() + c.value.len() + 12).sum();
        ensure_room(texts.saturating_mul(6).saturating_add(256))?;
        Ok(result(state, json::characteristics(&chars).into_bytes()))
    })
}

/// Read up to `count` rows from `start` of the `ncols` variables listed
/// (u32 indices) at `cols`, stopping after the row at which the decoded
/// output reaches 64 MiB, so module memory stays bounded. The columns
/// stay in the handle for `dta_column_part` until the next read. Returns
/// the number of rows read, or -1 on failure.
///
/// `flags`: `NEW_READ` starts a read (dictionaries begin again);
/// `DICTIONARY` codes string columns while they repeat enough (see
/// `strings.rs`). See `dta_column_mode` for what each column holds.
///
/// # Safety
/// `cols` must point to `ncols` u32 values.
#[no_mangle]
pub unsafe extern "C" fn dta_read(h: u32, cols: *const u32, ncols: usize, start: f64, count: f64, flags: u32) -> f64 {
    let cols: Vec<usize> = std::slice::from_raw_parts(cols, ncols).iter().map(|&c| c as usize).collect();
    call(-1.0, |state| {
        let budget = state.budget;
        let handle = handle(state, h)?;
        let Handle { reader, columns, dicts, strings } = handle;
        // Room for this call's columns and what it hands JavaScript.
        let meta = reader.metadata();
        let per_row: usize = cols
            .iter()
            .map(|&c| match meta.variables.get(c).map(|v| v.storage) {
                Some(StorageType::Str(w)) => 3 * w as usize + 16,
                Some(StorageType::StrL) => 32,
                _ => 9,
            })
            .sum();
        let rows_bytes = (count as usize).saturating_mul(per_row).min(budget.saturating_add(per_row));
        ensure_room(rows_bytes.saturating_mul(2))?;
        strings.clear();
        if flags & NEW_READ != 0 || dicts.len() != cols.len() {
            dicts.clear();
            dicts.resize_with(cols.len(), Dict::default);
        }
        columns.clear();
        // Room for the rows this call can return (the budget allows about
        // BUDGET / 9 numbers), so appending chunks does not regrow the
        // columns and leave freed copies in module memory.
        let rows = (count as usize).min(budget / (9 * cols.len()).max(1) + 1);
        *columns = cols
            .iter()
            .map(|&c| match meta.variables.get(c).map(|v| v.storage.is_numeric()) {
                Some(false) => Column::Strings { bytes: Vec::new(), ends: Vec::with_capacity(rows), binary: Vec::new() },
                _ => Column::Numbers { values: Vec::with_capacity(rows), missing: Vec::with_capacity(rows) },
            })
            .collect();
        // Decoded straight into the call's columns, so a large strL is
        // not held twice.
        let n = reader.read_into(&cols, start as u64, count as u64, Some(budget), columns)?;
        for (column, dict) in columns.iter().zip(dicts.iter_mut()) {
            strings.push(match column {
                Column::Numbers { .. } => None,
                Column::Strings { bytes, ends, binary } => Some(
                    match (flags & DICTIONARY != 0).then(|| dict.code(bytes, ends, binary)).flatten() {
                        Some((codes, new_bytes, new_utf16)) => Strings::Coded { codes, new_bytes, new_utf16 },
                        None => strings::plain(bytes, ends, binary),
                    },
                ),
            });
        }
        Ok(n as f64)
    })
}

const NEW_READ: u32 = 1;
const DICTIONARY: u32 = 2;

/// Free the dictionaries of the read that just ended.
#[no_mangle]
pub extern "C" fn dta_read_end(h: u32) {
    call((), |state| {
        let handle = handle(state, h)?;
        handle.dicts = Vec::new();
        handle.strings = Vec::new();
        Ok(())
    })
}

/// What read column `k` holds after `dta_read`: 0 numbers, 1 plain
/// strings, 2 dictionary codes.
#[no_mangle]
pub extern "C" fn dta_column_mode(h: u32, k: usize) -> u32 {
    call(0, |state| {
        Ok(match handle(state, h)?.strings.get(k).ok_or("no such column")? {
            None => 0,
            Some(Strings::Plain { .. }) => 1,
            Some(Strings::Coded { .. }) => 2,
        })
    })
}

/// Decoded bytes one read may hold in module memory (plus one row).
const BUDGET: usize = 64 << 20;

/// V8's longest string, in UTF-16 units: 2^29 - 24.
const STRING_LIMIT: usize = (1 << 29) - 24;

/// A buffer of read column `k`. Numbers: `part` 0 the f64 values, 1
/// the missing codes (u8). Plain strings: 0 the text bytes, 1 the
/// cumulative UTF-16 ends (u32, one per row), 2 the binary flags (u8,
/// strLs only), 3 every row's bytes as decoded (for the binary rows), 4
/// their cumulative byte ends (u32, one per row). Dictionary codes: 0 the new values' bytes, 1 their
/// cumulative UTF-16 ends, 5 the codes (u32, one per row). Returns a
/// pointer; `dta_result_len` gives the element count.
#[no_mangle]
pub extern "C" fn dta_column_part(h: u32, k: usize, part: u32) -> *const u8 {
    call(std::ptr::null(), |state| {
        let handle = handle(state, h)?;
        let column = handle.columns.get(k).ok_or("no such column")?;
        let strings = handle.strings.get(k).and_then(Option::as_ref);
        let (ptr, len) = match (column, strings, part) {
            (Column::Numbers { values, .. }, _, 0) => (values.as_ptr() as *const u8, values.len()),
            (Column::Numbers { missing, .. }, _, 1) => (missing.as_ptr(), missing.len()),
            (Column::Strings { bytes, .. }, Some(Strings::Plain { text, .. }), 0) => {
                let text = text.as_ref().unwrap_or(bytes);
                (text.as_ptr(), text.len())
            }
            (_, Some(Strings::Plain { utf16, .. }), 1) => (utf16.as_ptr() as *const u8, utf16.len()),
            (Column::Strings { binary, .. }, Some(Strings::Plain { .. }), 2) => (binary.as_ptr() as *const u8, binary.len()),
            (Column::Strings { bytes, .. }, Some(Strings::Plain { .. }), 3) => (bytes.as_ptr(), bytes.len()),
            (Column::Strings { ends, .. }, Some(Strings::Plain { .. }), 4) => (ends.as_ptr() as *const u8, ends.len()),
            (_, Some(Strings::Coded { new_bytes, .. }), 0) => (new_bytes.as_ptr(), new_bytes.len()),
            (_, Some(Strings::Coded { new_utf16, .. }), 1) => (new_utf16.as_ptr() as *const u8, new_utf16.len()),
            (_, Some(Strings::Coded { codes, .. }), 5) => (codes.as_ptr() as *const u8, codes.len()),
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
unsafe fn copy<T: Copy>(ptr: *const T, len: usize) -> Result<Vec<T>, Fail> {
    let mut v = Vec::new();
    if len > 0 {
        v.try_reserve_exact(len).map_err(|_| too_large(len * std::mem::size_of::<T>()))?;
        v.extend_from_slice(std::slice::from_raw_parts(ptr, len));
    }
    Ok(v)
}

fn too_large(bytes: usize) -> Fail {
    Fail { kind: TOO_LARGE, message: format!("{bytes} bytes do not fit in module memory") }
}

/// Room for allocations of up to `bytes` that follow (see
/// `dta::Source`'s `ensure_room`; this one is for the module's own).
fn ensure_room(bytes: usize) -> Result<(), Fail> {
    let mut probe: Vec<u8> = Vec::new();
    probe.try_reserve_exact(bytes).map_err(|_| too_large(bytes))?;
    std::hint::black_box(&probe);
    Ok(())
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
        let f = fields(&copy(meta, meta_len)?)?;
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
            let column = column(&f, storage, WriteData::Numbers(copy(values, n)?, copy(missing, n)?))?;
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
        let f = fields(&copy(meta, meta_len)?)?;
        WRITE.with(|w| {
            let mut w = w.borrow_mut();
            let ends = copy(ends, w.nobs)?;
            if ends.iter().any(|&e| e as usize > bytes_len) || ends.windows(2).any(|p| p[0] > p[1]) {
                return Err("string offsets out of order".into());
            }
            let bytes = copy(bytes, bytes_len)?;
            let (storage, data) = if binary.is_null() {
                (dta::StorageType::Str(1), WriteData::Strings(bytes, ends))
            } else {
                (dta::StorageType::StrL, WriteData::StrLs(bytes, ends, copy(binary, w.nobs)?))
            };
            let column = column(&f, storage, data)?;
            w.columns.push(column);
            Ok(1)
        })
    })
}

fn column(f: &[String], storage: dta::StorageType, data: WriteData) -> Result<WriteColumn, Fail> {
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
        let name = String::from_utf8(copy(name, name_len)?).map_err(|_| "label set names must be UTF-8")?;
        let (values, codes, ends) = (copy(values, n)?, copy(missing, n)?, copy(ends, n)?);
        let texts = String::from_utf8(copy(texts, texts_len)?).map_err(|_| "labels must be UTF-8")?;
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
        let f = fields(&copy(text, len)?)?;
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
        let order = copy(indices, n)?.into_iter().map(|i| i as usize).collect();
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
        let info = fields(&copy(info, info_len)?)?;
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
                    WriteData::Numbers(v, m) => dta::Values::numbers_by_row(move |i| (v[i], m[i])),
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
        // The writer's own tables: a row number per strL row, and one
        // entry per distinct strL.
        let strls = data.variables.iter().filter(|v| v.storage == StorageType::StrL).count();
        ensure_room(data.nobs.saturating_mul(strls).saturating_mul(64).saturating_add(4 << 20))?;
        dta::write(&data, HostSink(file))?;
        Ok(1)
    })
}
