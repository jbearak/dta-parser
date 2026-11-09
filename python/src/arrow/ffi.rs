//! Memory shared with numpy (plan 0024, stage 4), by hand (ADR 0033's
//! reasons for not adding arrow-rs, and no numpy C API, which the abi3
//! build for Python 3.10 cannot use):
//!
//! - [`Buffer`]: a buffer we own, handed to numpy through
//!   `__array_interface__`; numpy keeps the object as the array's `base`,
//!   and the object keeps the read's memory alive through an `Arc`.
//! - [`Block`] and [`Plan`]: the one zeroed allocation a read lays its
//!   columns out in.
//! - The Arrow C data interface's array struct, which the writers read a
//!   frame through: [`Imported`] holds a table built over numpy arrays
//!   (`frame.rs`), and [`ArrayRef`] reads it. The layouts are Arrow's, so
//!   the writers' rules did not change when polars' export went.

use std::any::Any;
use std::ffi::c_void;
use std::sync::Arc;

use pyo3::exceptions::PyValueError;
use pyo3::prelude::*;
use pyo3::types::{PyDict, PyTuple};

// ------------------------------------------------------------ C struct

#[repr(C)]
pub(crate) struct ArrowArray {
    pub(crate) length: i64,
    pub(crate) null_count: i64,
    pub(crate) offset: i64,
    pub(crate) n_buffers: i64,
    pub(crate) n_children: i64,
    pub(crate) buffers: *mut *const c_void,
    pub(crate) children: *mut *mut ArrowArray,
    pub(crate) dictionary: *mut ArrowArray,
    pub(crate) release: Option<unsafe extern "C" fn(*mut ArrowArray)>,
    pub(crate) private_data: *mut c_void,
}

// ------------------------------------------------------------ buffers

/// What keeps a read's buffers alive.
pub(crate) type Owner = Arc<dyn Any + Send + Sync>;

/// One buffer handed to numpy: `len` elements of `typestr` at `addr`,
/// alive while `owner` is. numpy keeps this object as the array's
/// `base`, so the memory lives as long as any array or slice of it.
#[pyclass(frozen, module = "dta_parser._native")]
pub(crate) struct Buffer {
    owner: Owner,
    addr: usize,
    len: usize,
    typestr: String,
}

impl Buffer {
    pub(crate) fn new(owner: Owner, addr: usize, len: usize, typestr: impl Into<String>) -> Self {
        // numpy takes a NULL data pointer as "allocate"; an empty buffer
        // gets an aligned one it never reads.
        let addr = if len == 0 && addr == 0 { 64 } else { addr };
        Buffer { owner, addr, len, typestr: typestr.into() }
    }

    /// A buffer that owns its own vector.
    pub(crate) fn of<T: Send + Sync + 'static>(v: Vec<T>, typestr: &str) -> Self {
        let (addr, len) = (v.as_ptr() as usize, v.len());
        let owner: Owner = Arc::new(v);
        Buffer::new(owner, if len == 0 { 0 } else { addr }, len, typestr)
    }
}

#[pymethods]
impl Buffer {
    /// numpy's array interface, version 3: one dimension, C-contiguous,
    /// writable. The pointer is the buffer's own start.
    #[getter]
    fn __array_interface__<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let _ = &self.owner;
        let d = PyDict::new(py);
        d.set_item("shape", PyTuple::new(py, [self.len])?)?;
        d.set_item("typestr", &self.typestr)?;
        d.set_item("data", (self.addr, false))?;
        d.set_item("version", 3)?;
        Ok(d)
    }
}

/// The byte-order character numpy writes for multi-byte types here.
pub(crate) const ORDER: char = if cfg!(target_endian = "little") { '<' } else { '>' };

/// numpy's type string for `kind` (`i`, `u`, `f`, `b`, `M8[s]`, ...) of
/// `size` bytes.
pub(crate) fn typestr(kind: &str, size: usize) -> String {
    let order = if size == 1 { '|' } else { ORDER };
    if kind.starts_with('M') || kind.starts_with('m') {
        format!("{order}{kind}")
    } else {
        format!("{order}{kind}{size}")
    }
}

/// Zeroed bytes from one allocation, aligned to 16 (the widest element,
/// a string view), so the allocator's calloc gives them: for large
/// blocks, pages the kernel zeroes when first written. (Asking for more
/// alignment than the allocator's own makes Rust zero every byte at
/// once, which touched a gigabyte on the synthetic `long` before the
/// read began.)
pub(crate) struct Block {
    ptr: *mut u8,
    len: usize,
}

// SAFETY: a Block is plain memory, handed out as raw pointers that the
// read fills before anyone else sees them.
unsafe impl Send for Block {}
unsafe impl Sync for Block {}

/// Each buffer in a block starts at a multiple of this.
pub(crate) const ALIGN: usize = 64;
const BLOCK_ALIGN: usize = 16;

impl Block {
    pub(crate) fn zeroed(len: usize) -> PyResult<Self> {
        if len == 0 {
            return Ok(Block { ptr: BLOCK_ALIGN as *mut u8, len: 0 });
        }
        let layout = std::alloc::Layout::from_size_align(len, BLOCK_ALIGN).map_err(|_| PyValueError::new_err("too large"))?;
        // SAFETY: the layout has a non-zero size.
        let ptr = unsafe { std::alloc::alloc_zeroed(layout) };
        if ptr.is_null() {
            return Err(pyo3::exceptions::PyMemoryError::new_err(format!("{len} bytes do not fit in memory here")));
        }
        Ok(Block { ptr, len })
    }

    pub(crate) fn addr(&self) -> usize {
        self.ptr as usize
    }
}

impl Drop for Block {
    fn drop(&mut self) {
        if self.len > 0 {
            // SAFETY: allocated in `zeroed` with this layout.
            unsafe { std::alloc::dealloc(self.ptr, std::alloc::Layout::from_size_align_unchecked(self.len, BLOCK_ALIGN)) }
        }
    }
}

/// Lays out many buffers in one [`Block`], each at a multiple of
/// [`ALIGN`]: a wide file's thousands of columns then cost one
/// allocation, not two each.
#[derive(Default)]
pub(crate) struct Plan {
    size: usize,
}

impl Plan {
    /// Room for `len` bytes; returns its offset.
    pub(crate) fn add(&mut self, len: usize) -> usize {
        let at = self.size;
        self.size += len.div_ceil(ALIGN) * ALIGN;
        at
    }

    pub(crate) fn block(&self) -> PyResult<Block> {
        Block::zeroed(self.size)
    }
}

// ------------------------------------------------------------ tables

/// A field of a table the writers read: its name, Arrow format, metadata
/// and dictionary.
#[derive(Debug, Clone)]
pub(crate) struct InField {
    pub(crate) name: String,
    pub(crate) format: String,
    pub(crate) metadata: Vec<(String, Vec<u8>)>,
    pub(crate) children: Vec<InField>,
    pub(crate) dictionary: Option<Box<InField>>,
}

impl InField {
    pub(crate) fn meta(&self, key: &str) -> Option<&[u8]> {
        self.metadata.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_slice())
    }
}

/// The field metadata that says a categorical keeps every level, used or
/// not (a pandas `category`), so the writers write them all.
pub(crate) const EVERY_LEVEL: &str = "datakit:every_level";

/// A table's top array (a struct of columns). Its children, buffers and
/// dictionaries are owned by whoever built it, and outlive it.
pub(crate) struct InArray {
    pub(crate) raw: Box<ArrowArray>,
}

// SAFETY: the buffers are plain memory, read only while a write runs.
unsafe impl Send for InArray {}
unsafe impl Sync for InArray {}

/// A view of an array (the top one or a child).
#[derive(Clone, Copy)]
pub(crate) struct ArrayRef<'a> {
    raw: &'a ArrowArray,
}

impl<'a> ArrayRef<'a> {
    pub(crate) fn len(&self) -> usize {
        self.raw.length.max(0) as usize
    }
    pub(crate) fn offset(&self) -> usize {
        self.raw.offset.max(0) as usize
    }
    pub(crate) fn null_count(&self) -> i64 {
        self.raw.null_count
    }
    pub(crate) fn n_buffers(&self) -> usize {
        self.raw.n_buffers.max(0) as usize
    }
    /// Buffer `i`'s address, 0 when null or absent.
    pub(crate) fn buffer(&self, i: usize) -> usize {
        if i >= self.n_buffers() {
            return 0;
        }
        // SAFETY: the array has `n_buffers` buffer pointers.
        unsafe { *self.raw.buffers.add(i) as usize }
    }
    pub(crate) fn child(&self, i: usize) -> Option<ArrayRef<'a>> {
        if i >= self.raw.n_children.max(0) as usize {
            return None;
        }
        // SAFETY: the array has `n_children` child pointers.
        unsafe { (*self.raw.children.add(i)).as_ref().map(|raw| ArrayRef { raw }) }
    }
    pub(crate) fn dictionary(&self) -> Option<ArrayRef<'a>> {
        // SAFETY: a non-null dictionary pointer is a valid array.
        unsafe { self.raw.dictionary.as_ref().map(|raw| ArrayRef { raw }) }
    }
}

impl InArray {
    pub(crate) fn get(&self) -> ArrayRef<'_> {
        ArrayRef { raw: &self.raw }
    }
}

/// A table for the writers: its schema and its batches.
pub(crate) struct Imported {
    pub(crate) schema: InField,
    pub(crate) batches: Vec<InArray>,
}

// ------------------------------------------------------------ reading arrays

/// Whether row `i` (counting the array's offset) has a value.
#[inline]
pub(crate) fn valid(a: &ArrayRef, i: usize) -> bool {
    let v = a.buffer(0);
    v == 0 || a.null_count() == 0 || unsafe { (*(v as *const u8).add(i / 8) >> (i % 8)) & 1 == 1 }
}

/// The bytes of row `i` of a string array (`u`, `U`, `vu` and the binary
/// ones), counting its offset.
///
/// # Safety
/// The array's buffers are of the format given.
pub(crate) unsafe fn text_at<'a>(a: &ArrayRef<'a>, format: &str, i: usize) -> &'a [u8] {
    match format {
        "u" | "z" => {
            let o = a.buffer(1) as *const i32;
            let (s, e) = (*o.add(i) as usize, *o.add(i + 1) as usize);
            std::slice::from_raw_parts((a.buffer(2) as *const u8).add(s), e - s)
        }
        "U" | "Z" => {
            let o = a.buffer(1) as *const i64;
            let (s, e) = (*o.add(i) as usize, *o.add(i + 1) as usize);
            if e == s {
                return &[];
            }
            std::slice::from_raw_parts((a.buffer(2) as *const u8).add(s), e - s)
        }
        _ => view_at(a.buffer(1), |b| a.buffer(2 + b), i),
    }
}

/// Row `i` of a string-view buffer at `views`, whose long values are in
/// the data buffers `data(index)` gives.
///
/// # Safety
/// `views` holds row `i`, and its data buffers the bytes it points at.
pub(crate) unsafe fn view_at<'a>(views: usize, data: impl Fn(usize) -> usize, i: usize) -> &'a [u8] {
    // A view: 16 bytes, inline up to 12.
    let v = (views as *const u8).add(16 * i);
    let len = u32::from_le_bytes(std::ptr::read_unaligned(v as *const [u8; 4])) as usize;
    if len == 0 {
        &[]
    } else if len <= 12 {
        std::slice::from_raw_parts(v.add(4), len)
    } else {
        let buf = u32::from_le_bytes(std::ptr::read_unaligned(v.add(8) as *const [u8; 4])) as usize;
        let off = u32::from_le_bytes(std::ptr::read_unaligned(v.add(12) as *const [u8; 4])) as usize;
        std::slice::from_raw_parts((data(buf) as *const u8).add(off), len)
    }
}

/// A dictionary array's key at row `i`.
///
/// # Safety
/// The keys buffer holds row `i` in `format`.
pub(crate) unsafe fn key_at(a: &ArrayRef, format: &str, i: usize) -> Option<usize> {
    let p = a.buffer(1);
    Some(match format {
        "C" => *(p as *const u8).add(i) as usize,
        "c" => usize::try_from(*(p as *const i8).add(i)).ok()?,
        "S" => *(p as *const u16).add(i) as usize,
        "s" => usize::try_from(*(p as *const i16).add(i)).ok()?,
        "I" => *(p as *const u32).add(i) as usize,
        "i" => usize::try_from(*(p as *const i32).add(i)).ok()?,
        "L" => usize::try_from(*(p as *const u64).add(i)).ok()?,
        "l" => usize::try_from(*(p as *const i64).add(i)).ok()?,
        _ => return None,
    })
}
