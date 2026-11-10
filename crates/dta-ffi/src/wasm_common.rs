//! What the wasm module's exports stand on: the allocator that turns
//! running out of memory into an error, the error and result exports,
//! and the host's file callbacks. The `.dta` exports are in `wasm.rs`
//! (feature `wasm-dta`).
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

use dta::{ErrorKind, Source};

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
    pub(crate) fn host_read(file: u32, ptr: *mut u8, len: usize, offset: f64) -> i32;
}

/// A file JavaScript holds, known to us by number.
pub(crate) struct HostFile {
    pub(crate) id: u32,
    pub(crate) len: u64,
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

pub(crate) struct State {
    /// The `.dta` readers and the read settings (`wasm.rs`).
    #[cfg(feature = "wasm-dta")]
    pub(crate) dta: crate::wasm::DtaState,
    /// Static when there was no memory to make a message.
    error: Cow<'static, str>,
    error_kind: u32,
    result: Vec<u8>,
    pub(crate) result_len: usize,
}

impl Default for State {
    fn default() -> Self {
        State {
            #[cfg(feature = "wasm-dta")]
            dta: Default::default(),
            error: Cow::Borrowed(""),
            error_kind: 0,
            result: Vec::new(),
            result_len: 0,
        }
    }
}

thread_local! {
    pub(crate) static STATE: RefCell<State> = RefCell::new(State::default());
}

/// An error for JavaScript: its kind (see `dta_error_kind`) and message.
pub(crate) struct Fail {
    pub(crate) kind: u32,
    pub(crate) message: String,
}

// The kinds `dta_error_kind` returns.
pub(crate) const CORRUPT: u32 = 1;
pub(crate) const TOO_LARGE: u32 = 2;
pub(crate) const IO: u32 = 3;
pub(crate) const INVALID: u32 = 4;
pub(crate) const OUT_OF_RANGE: u32 = 5;
pub(crate) const INTERNAL: u32 = 6;
pub(crate) const CLOSED: u32 = 7;

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
pub(crate) fn call<T>(fail: T, f: impl FnOnce(&mut State) -> Result<T, Fail>) -> T {
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

/// Leave `bytes` as the result and return a pointer to it.
pub(crate) fn result(state: &mut State, bytes: Vec<u8>) -> *const u8 {
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

#[link(wasm_import_module = "env")]
extern "C" {
    /// Write `len` bytes at `ptr` to `file`; 0 on success.
    pub(crate) fn host_write(file: u32, ptr: *const u8, len: usize) -> i32;
}

pub(crate) struct HostSink(pub(crate) u32);

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

/// # Safety
/// `ptr` points to `len` readable elements of T.
pub(crate) unsafe fn copy<T: Copy>(ptr: *const T, len: usize) -> Result<Vec<T>, Fail> {
    let mut v = Vec::new();
    if len > 0 {
        v.try_reserve_exact(len).map_err(|_| too_large(len * std::mem::size_of::<T>()))?;
        v.extend_from_slice(std::slice::from_raw_parts(ptr, len));
    }
    Ok(v)
}

pub(crate) fn too_large(bytes: usize) -> Fail {
    Fail { kind: TOO_LARGE, message: format!("{bytes} bytes do not fit in module memory") }
}

/// Room for allocations of up to `bytes` that follow (see
/// `dta::Source`'s `ensure_room`; this one is for the module's own).
pub(crate) fn ensure_room(bytes: usize) -> Result<(), Fail> {
    let mut probe: Vec<u8> = Vec::new();
    probe.try_reserve_exact(bytes).map_err(|_| too_large(bytes))?;
    std::hint::black_box(&probe);
    Ok(())
}
