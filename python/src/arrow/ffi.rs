//! The Arrow C data interface, by hand (plan 0019; ADR 0033's reasons for
//! not adding arrow-rs): the C structures, export of buffers we own as an
//! `ArrowArrayStream` in a PyCapsule (`__arrow_c_stream__`), and import
//! of another library's stream (polars' `DataFrame.__arrow_c_stream__()`).
//!
//! Exported buffers stay alive through an `Arc` held by every array that
//! points into them, so polars may keep a column after our object and the
//! stream are gone; the release callbacks drop the `Arc`s.

use std::any::Any;
use std::collections::VecDeque;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::ptr::{null, null_mut};
use std::sync::Arc;

use pyo3::exceptions::{PyTypeError, PyValueError};
use pyo3::ffi;
use pyo3::prelude::*;

// ------------------------------------------------------------ C structs

#[repr(C)]
pub(crate) struct ArrowSchema {
    pub(crate) format: *const c_char,
    pub(crate) name: *const c_char,
    pub(crate) metadata: *const c_char,
    pub(crate) flags: i64,
    pub(crate) n_children: i64,
    pub(crate) children: *mut *mut ArrowSchema,
    pub(crate) dictionary: *mut ArrowSchema,
    pub(crate) release: Option<unsafe extern "C" fn(*mut ArrowSchema)>,
    pub(crate) private_data: *mut c_void,
}

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

#[repr(C)]
pub(crate) struct ArrowArrayStream {
    pub(crate) get_schema: Option<unsafe extern "C" fn(*mut ArrowArrayStream, *mut ArrowSchema) -> c_int>,
    pub(crate) get_next: Option<unsafe extern "C" fn(*mut ArrowArrayStream, *mut ArrowArray) -> c_int>,
    pub(crate) get_last_error: Option<unsafe extern "C" fn(*mut ArrowArrayStream) -> *const c_char>,
    pub(crate) release: Option<unsafe extern "C" fn(*mut ArrowArrayStream)>,
    pub(crate) private_data: *mut c_void,
}

pub(crate) const NULLABLE: i64 = 2;
pub(crate) const DICTIONARY_ORDERED: i64 = 1;

fn empty_array() -> ArrowArray {
    ArrowArray {
        length: 0,
        null_count: 0,
        offset: 0,
        n_buffers: 0,
        n_children: 0,
        buffers: null_mut(),
        children: null_mut(),
        dictionary: null_mut(),
        release: None,
        private_data: null_mut(),
    }
}

fn empty_schema() -> ArrowSchema {
    ArrowSchema {
        format: null(),
        name: null(),
        metadata: null(),
        flags: 0,
        n_children: 0,
        children: null_mut(),
        dictionary: null_mut(),
        release: None,
        private_data: null_mut(),
    }
}

// ------------------------------------------------------------ export

/// A field to export: its format string (the C interface's), name,
/// flags, metadata (already encoded) and children or dictionary.
#[derive(Clone)]
pub(crate) struct Field {
    pub(crate) name: String,
    pub(crate) format: String,
    pub(crate) flags: i64,
    pub(crate) metadata: Option<Vec<u8>>,
    pub(crate) children: Vec<Field>,
    pub(crate) dictionary: Option<Box<Field>>,
}

impl Field {
    pub(crate) fn new(name: &str, format: &str) -> Self {
        Field { name: name.into(), format: format.into(), flags: NULLABLE, metadata: None, children: Vec::new(), dictionary: None }
    }
}

/// Encode key-value metadata as the interface lays it out.
pub(crate) fn metadata(pairs: &[(&str, &[u8])]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(&(pairs.len() as i32).to_ne_bytes());
    for (k, v) in pairs {
        out.extend_from_slice(&(k.len() as i32).to_ne_bytes());
        out.extend_from_slice(k.as_bytes());
        out.extend_from_slice(&(v.len() as i32).to_ne_bytes());
        out.extend_from_slice(v);
    }
    out
}

struct SchemaPrivate {
    _format: CString,
    _name: CString,
    _metadata: Option<Vec<u8>>,
    children: Vec<*mut ArrowSchema>,
    dictionary: *mut ArrowSchema,
}

fn export_schema(f: &Field) -> ArrowSchema {
    let format = CString::new(f.format.as_str()).expect("formats have no NUL");
    let name = CString::new(f.name.replace('\0', "")).expect("NULs removed");
    let children: Vec<*mut ArrowSchema> = f.children.iter().map(|c| Box::into_raw(Box::new(export_schema(c)))).collect();
    let dictionary = f.dictionary.as_ref().map_or(null_mut(), |d| Box::into_raw(Box::new(export_schema(d))));
    let mut p = Box::new(SchemaPrivate { _format: format, _name: name, _metadata: f.metadata.clone(), children, dictionary });
    ArrowSchema {
        format: p._format.as_ptr(),
        name: p._name.as_ptr(),
        metadata: p._metadata.as_ref().map_or(null(), |m| m.as_ptr() as *const c_char),
        flags: f.flags,
        n_children: p.children.len() as i64,
        children: p.children.as_mut_ptr(),
        dictionary,
        release: Some(release_schema),
        private_data: Box::into_raw(p) as *mut c_void,
    }
}

unsafe extern "C" fn release_schema(s: *mut ArrowSchema) {
    if s.is_null() || (*s).release.is_none() {
        return;
    }
    let p = Box::from_raw((*s).private_data as *mut SchemaPrivate);
    for &c in &p.children {
        free_schema(c);
    }
    if !p.dictionary.is_null() {
        free_schema(p.dictionary);
    }
    (*s).release = None;
}

unsafe fn free_schema(c: *mut ArrowSchema) {
    if let Some(r) = (*c).release {
        r(c);
    }
    drop(Box::from_raw(c));
}

/// What keeps exported buffers alive.
pub(crate) type Owner = Arc<dyn Any + Send + Sync>;

/// An array to export: pointers into buffers that `owner` keeps alive.
#[derive(Clone)]
pub(crate) struct Array {
    pub(crate) length: usize,
    pub(crate) null_count: usize,
    pub(crate) offset: usize,
    pub(crate) buffers: Vec<usize>,
    pub(crate) children: Vec<Array>,
    pub(crate) dictionary: Option<Box<Array>>,
    pub(crate) owner: Option<Owner>,
}

struct ArrayPrivate {
    _owner: Option<Owner>,
    buffers: Vec<*const c_void>,
    children: Vec<*mut ArrowArray>,
    dictionary: *mut ArrowArray,
}

fn export_array(a: &Array) -> ArrowArray {
    let children: Vec<*mut ArrowArray> = a.children.iter().map(|c| Box::into_raw(Box::new(export_array(c)))).collect();
    let dictionary = a.dictionary.as_ref().map_or(null_mut(), |d| Box::into_raw(Box::new(export_array(d))));
    let mut p = Box::new(ArrayPrivate {
        _owner: a.owner.clone(),
        buffers: a.buffers.iter().map(|&b| b as *const c_void).collect(),
        children,
        dictionary,
    });
    ArrowArray {
        length: a.length as i64,
        null_count: a.null_count as i64,
        offset: a.offset as i64,
        n_buffers: p.buffers.len() as i64,
        n_children: p.children.len() as i64,
        buffers: p.buffers.as_mut_ptr(),
        children: p.children.as_mut_ptr(),
        dictionary,
        release: Some(release_array),
        private_data: Box::into_raw(p) as *mut c_void,
    }
}

unsafe extern "C" fn release_array(a: *mut ArrowArray) {
    if a.is_null() || (*a).release.is_none() {
        return;
    }
    let p = Box::from_raw((*a).private_data as *mut ArrayPrivate);
    for &c in &p.children {
        free_array(c);
    }
    if !p.dictionary.is_null() {
        free_array(p.dictionary);
    }
    (*a).release = None;
}

unsafe fn free_array(c: *mut ArrowArray) {
    if let Some(r) = (*c).release {
        r(c);
    }
    drop(Box::from_raw(c));
}

/// A table to export: fields and batches (struct arrays, one child per
/// field).
#[derive(Clone)]
pub(crate) struct Table {
    pub(crate) fields: Vec<Field>,
    pub(crate) batches: Vec<Array>,
}

struct StreamPrivate {
    table: Table,
    next: VecDeque<Array>,
}

unsafe extern "C" fn stream_get_schema(s: *mut ArrowArrayStream, out: *mut ArrowSchema) -> c_int {
    let p = &*((*s).private_data as *const StreamPrivate);
    let root = Field { name: String::new(), format: "+s".into(), flags: 0, metadata: None, children: p.table.fields.clone(), dictionary: None };
    out.write(export_schema(&root));
    0
}

unsafe extern "C" fn stream_get_next(s: *mut ArrowArrayStream, out: *mut ArrowArray) -> c_int {
    let p = &mut *((*s).private_data as *mut StreamPrivate);
    match p.next.pop_front() {
        None => out.write(empty_array()),
        Some(a) => out.write(export_array(&a)),
    }
    0
}

unsafe extern "C" fn stream_last_error(_: *mut ArrowArrayStream) -> *const c_char {
    null()
}

unsafe extern "C" fn stream_release(s: *mut ArrowArrayStream) {
    if s.is_null() || (*s).release.is_none() {
        return;
    }
    drop(Box::from_raw((*s).private_data as *mut StreamPrivate));
    (*s).release = None;
}

const STREAM: &CStr = c"arrow_array_stream";

unsafe extern "C" fn capsule_destructor(cap: *mut ffi::PyObject) {
    let p = ffi::PyCapsule_GetPointer(cap, STREAM.as_ptr()) as *mut ArrowArrayStream;
    if p.is_null() {
        ffi::PyErr_Clear();
        return;
    }
    // A consumer that took the stream set its release to null.
    if let Some(r) = (*p).release {
        r(p);
    }
    drop(Box::from_raw(p));
}

/// `table` as a PyCapsule holding an `ArrowArrayStream`.
pub(crate) fn stream_capsule<'py>(py: Python<'py>, table: &Table) -> PyResult<Bound<'py, PyAny>> {
    let private = Box::new(StreamPrivate { next: table.batches.iter().cloned().collect(), table: table.clone() });
    let stream = Box::into_raw(Box::new(ArrowArrayStream {
        get_schema: Some(stream_get_schema),
        get_next: Some(stream_get_next),
        get_last_error: Some(stream_last_error),
        release: Some(stream_release),
        private_data: Box::into_raw(private) as *mut c_void,
    }));
    // SAFETY: the capsule owns `stream` and releases it unless the
    // consumer moved it out.
    unsafe {
        let cap = ffi::PyCapsule_New(stream as *mut c_void, STREAM.as_ptr(), Some(capsule_destructor));
        if cap.is_null() {
            stream_release(stream);
            drop(Box::from_raw(stream));
            return Err(PyErr::fetch(py));
        }
        Ok(Bound::from_owned_ptr(py, cap))
    }
}

/// An object polars (or pyarrow) takes with `pl.DataFrame(obj)`: it
/// exports its table as often as asked, every export sharing the buffers.
#[pyclass(frozen, module = "dta_parser._native")]
pub(crate) struct ArrowTable {
    pub(crate) table: Table,
}

#[pymethods]
impl ArrowTable {
    #[pyo3(signature = (requested_schema = None))]
    fn __arrow_c_stream__<'py>(
        &self,
        py: Python<'py>,
        requested_schema: Option<Bound<'py, PyAny>>,
    ) -> PyResult<Bound<'py, PyAny>> {
        let _ = requested_schema;
        stream_capsule(py, &self.table)
    }

    /// The columns' names, in order.
    #[getter]
    fn names(&self) -> Vec<String> {
        self.table.fields.iter().map(|f| f.name.clone()).collect()
    }

    /// Rows, over every batch.
    #[getter]
    fn rows(&self) -> usize {
        self.table.batches.iter().map(|b| b.length).sum()
    }

    /// Per column, the address of its values buffer (keys for a
    /// dictionary, views for text), for tests that check polars took the
    /// buffers without a copy.
    #[getter]
    fn addresses(&self) -> Vec<usize> {
        self.table.batches.first().map_or_else(Vec::new, |b| {
            b.children.iter().map(|c| c.buffers.get(1).copied().unwrap_or(0)).collect()
        })
    }
}

// ------------------------------------------------------------ buffers

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

// ------------------------------------------------------------ import

/// A field of an imported schema.
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

unsafe fn cstr(p: *const c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        CStr::from_ptr(p).to_string_lossy().into_owned()
    }
}

unsafe fn read_metadata(p: *const c_char) -> Vec<(String, Vec<u8>)> {
    if p.is_null() {
        return Vec::new();
    }
    unsafe fn int(at: &mut *const u8) -> usize {
        let v = i32::from_ne_bytes(std::ptr::read_unaligned(*at as *const [u8; 4]));
        *at = at.add(4);
        v.max(0) as usize
    }
    let mut at = p as *const u8;
    let n = int(&mut at);
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        let kl = int(&mut at);
        let k = String::from_utf8_lossy(std::slice::from_raw_parts(at, kl)).into_owned();
        at = at.add(kl);
        let vl = int(&mut at);
        let v = std::slice::from_raw_parts(at, vl).to_vec();
        at = at.add(vl);
        out.push((k, v));
    }
    out
}

unsafe fn read_field(s: *const ArrowSchema) -> InField {
    let s = &*s;
    let children = (0..s.n_children.max(0) as usize).map(|i| read_field(*s.children.add(i))).collect();
    InField {
        name: cstr(s.name),
        format: cstr(s.format),
        metadata: read_metadata(s.metadata),
        children,
        dictionary: (!s.dictionary.is_null()).then(|| Box::new(read_field(s.dictionary))),
    }
}

/// An imported array: released when dropped. Its children and dictionary
/// belong to it.
pub(crate) struct InArray {
    raw: Box<ArrowArray>,
}

// SAFETY: the producer's buffers are plain memory, read only, and the
// array is released once, from whichever thread drops it.
unsafe impl Send for InArray {}
unsafe impl Sync for InArray {}

impl Drop for InArray {
    fn drop(&mut self) {
        if let Some(r) = self.raw.release {
            // SAFETY: the producer's release callback, called once.
            unsafe { r(&mut *self.raw) };
        }
    }
}

/// A view of an imported array (the top one or a child).
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

/// An imported stream: its schema and every batch.
pub(crate) struct Imported {
    pub(crate) schema: InField,
    pub(crate) batches: Vec<InArray>,
}

/// Take every batch of `obj.__arrow_c_stream__()`.
pub(crate) fn import_stream(obj: &Bound<'_, PyAny>) -> PyResult<Imported> {
    let cap = obj
        .call_method0("__arrow_c_stream__")
        .map_err(|_| PyTypeError::new_err("the object does not export an Arrow stream (__arrow_c_stream__)"))?;
    // SAFETY: a capsule named arrow_array_stream holds an ArrowArrayStream,
    // which we move out, leaving the capsule's released.
    unsafe {
        let p = ffi::PyCapsule_GetPointer(cap.as_ptr(), STREAM.as_ptr()) as *mut ArrowArrayStream;
        if p.is_null() {
            return Err(PyErr::fetch(obj.py()));
        }
        let mut stream = std::ptr::read(p);
        (*p).release = None;
        struct Release(*mut ArrowArrayStream);
        impl Drop for Release {
            fn drop(&mut self) {
                // SAFETY: the stream moved out above, released once.
                unsafe {
                    if let Some(r) = (*self.0).release {
                        r(self.0);
                    }
                }
            }
        }
        let _release = Release(&mut stream);
        let error = |s: *mut ArrowArrayStream, what: &str| {
            let msg = (*s).get_last_error.map(|f| cstr(f(s))).unwrap_or_default();
            PyValueError::new_err(format!("reading the Arrow stream ({what}): {msg}"))
        };
        let mut schema = empty_schema();
        let get_schema = stream.get_schema.ok_or_else(|| PyValueError::new_err("an Arrow stream without get_schema"))?;
        if get_schema(&mut stream, &mut schema) != 0 {
            return Err(error(&mut stream, "schema"));
        }
        let field = read_field(&schema);
        if let Some(r) = schema.release {
            r(&mut schema);
        }
        let get_next = stream.get_next.ok_or_else(|| PyValueError::new_err("an Arrow stream without get_next"))?;
        let mut batches = Vec::new();
        loop {
            let mut a = Box::new(empty_array());
            if get_next(&mut stream, &mut *a) != 0 {
                return Err(error(&mut stream, "a batch"));
            }
            if a.release.is_none() {
                break;
            }
            batches.push(InArray { raw: a });
        }
        Ok(Imported { schema: field, batches })
    }
}
