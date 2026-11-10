//! The Arrow C data interface, by hand (plan 0019; ADR 0033's reasons for
//! not adding arrow-rs): the C structures, export of buffers we own as an
//! `ArrowArrayStream`, import of another library's stream (a polars
//! frame's Arrow export), and reading the buffers' layouts. The binding
//! moves an exported stream into a struct its language allocated (R's
//! does so with nanoarrow) and takes an imported one out of one.
//!
//! Exported buffers stay alive through an `Arc` held by every array that
//! points into them, so polars may keep a column after our object and the
//! stream are gone; the release callbacks drop the `Arc`s.

use std::any::Any;
use std::collections::VecDeque;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::ptr::{null, null_mut};
use std::sync::Arc;

use super::error::{fail, Error, Result};

// ------------------------------------------------------------ C structs

#[repr(C)]
pub struct ArrowSchema {
    pub format: *const c_char,
    pub name: *const c_char,
    pub metadata: *const c_char,
    pub flags: i64,
    pub n_children: i64,
    pub children: *mut *mut ArrowSchema,
    pub dictionary: *mut ArrowSchema,
    pub release: Option<unsafe extern "C" fn(*mut ArrowSchema)>,
    pub private_data: *mut c_void,
}

#[repr(C)]
pub struct ArrowArray {
    pub length: i64,
    pub null_count: i64,
    pub offset: i64,
    pub n_buffers: i64,
    pub n_children: i64,
    pub buffers: *mut *const c_void,
    pub children: *mut *mut ArrowArray,
    pub dictionary: *mut ArrowArray,
    pub release: Option<unsafe extern "C" fn(*mut ArrowArray)>,
    pub private_data: *mut c_void,
}

#[repr(C)]
pub struct ArrowArrayStream {
    pub get_schema: Option<unsafe extern "C" fn(*mut ArrowArrayStream, *mut ArrowSchema) -> c_int>,
    pub get_next: Option<unsafe extern "C" fn(*mut ArrowArrayStream, *mut ArrowArray) -> c_int>,
    pub get_last_error: Option<unsafe extern "C" fn(*mut ArrowArrayStream) -> *const c_char>,
    pub release: Option<unsafe extern "C" fn(*mut ArrowArrayStream)>,
    pub private_data: *mut c_void,
}

pub const NULLABLE: i64 = 2;
pub const DICTIONARY_ORDERED: i64 = 1;

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
pub struct Field {
    pub name: String,
    pub format: String,
    pub flags: i64,
    pub metadata: Option<Vec<u8>>,
    pub children: Vec<Field>,
    pub dictionary: Option<Box<Field>>,
}

impl Field {
    pub fn new(name: &str, format: &str) -> Self {
        Field { name: name.into(), format: format.into(), flags: NULLABLE, metadata: None, children: Vec::new(), dictionary: None }
    }
}

/// Encode key-value metadata as the interface lays it out.
pub fn metadata(pairs: &[(&str, &[u8])]) -> Vec<u8> {
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
pub type Owner = Arc<dyn Any + Send + Sync>;

/// An array to export: pointers into buffers that `owner` keeps alive.
#[derive(Clone)]
pub struct Array {
    pub length: usize,
    pub null_count: usize,
    pub offset: usize,
    pub buffers: Vec<usize>,
    pub children: Vec<Array>,
    pub dictionary: Option<Box<Array>>,
    pub owner: Option<Owner>,
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
pub struct Table {
    pub fields: Vec<Field>,
    pub batches: Vec<Array>,
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

/// `table` as an `ArrowArrayStream` that owns a copy of its batches (the
/// buffers shared through their owners); its `release` frees it.
pub fn export_stream(table: &Table) -> ArrowArrayStream {
    let private = Box::new(StreamPrivate { next: table.batches.iter().cloned().collect(), table: table.clone() });
    ArrowArrayStream {
        get_schema: Some(stream_get_schema),
        get_next: Some(stream_get_next),
        get_last_error: Some(stream_last_error),
        release: Some(stream_release),
        private_data: Box::into_raw(private) as *mut c_void,
    }
}

// ------------------------------------------------------------ buffers

/// Zeroed bytes from one allocation, aligned to 16 (the widest element,
/// a string view), so the allocator's calloc gives them: for large
/// blocks, pages the kernel zeroes when first written. (Asking for more
/// alignment than the allocator's own makes Rust zero every byte at
/// once, which touched a gigabyte on the synthetic `long` before the
/// read began.)
pub struct Block {
    ptr: *mut u8,
    len: usize,
}

// SAFETY: a Block is plain memory, handed out as raw pointers that the
// read fills before anyone else sees them.
unsafe impl Send for Block {}
unsafe impl Sync for Block {}

/// Each buffer in a block starts at a multiple of this.
pub const ALIGN: usize = 64;
const BLOCK_ALIGN: usize = 16;

impl Block {
    pub fn zeroed(len: usize) -> Result<Self> {
        if len == 0 {
            return Ok(Block { ptr: BLOCK_ALIGN as *mut u8, len: 0 });
        }
        let layout = std::alloc::Layout::from_size_align(len, BLOCK_ALIGN).map_err(|_| fail("too large"))?;
        // SAFETY: the layout has a non-zero size.
        let ptr = unsafe { std::alloc::alloc_zeroed(layout) };
        if ptr.is_null() {
            return Err(Error::Memory(format!("{len} bytes do not fit in memory here")));
        }
        Ok(Block { ptr, len })
    }

    pub fn addr(&self) -> usize {
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
pub struct Plan {
    size: usize,
}

impl Plan {
    /// Room for `len` bytes; returns its offset.
    pub fn add(&mut self, len: usize) -> usize {
        let at = self.size;
        self.size += len.div_ceil(ALIGN) * ALIGN;
        at
    }

    pub fn block(&self) -> Result<Block> {
        Block::zeroed(self.size)
    }
}

// ------------------------------------------------------------ import

/// A field of an imported schema.
#[derive(Debug, Clone)]
pub struct InField {
    pub name: String,
    pub format: String,
    pub metadata: Vec<(String, Vec<u8>)>,
    pub children: Vec<InField>,
    pub dictionary: Option<Box<InField>>,
}

impl InField {
    pub fn meta(&self, key: &str) -> Option<&[u8]> {
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
    let mut at = p.cast::<u8>();
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
pub struct InArray {
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
pub struct ArrayRef<'a> {
    raw: &'a ArrowArray,
}

// Public since the move to a crate of its own (plan 0025, stage 2b); no
// caller asks whether a view is empty.
#[allow(clippy::len_without_is_empty)]
impl<'a> ArrayRef<'a> {
    pub fn len(&self) -> usize {
        self.raw.length.max(0) as usize
    }
    pub fn offset(&self) -> usize {
        self.raw.offset.max(0) as usize
    }
    pub fn null_count(&self) -> i64 {
        self.raw.null_count
    }
    pub fn n_buffers(&self) -> usize {
        self.raw.n_buffers.max(0) as usize
    }
    /// Buffer `i`'s address, 0 when null or absent.
    pub fn buffer(&self, i: usize) -> usize {
        if i >= self.n_buffers() {
            return 0;
        }
        // SAFETY: the array has `n_buffers` buffer pointers.
        unsafe { *self.raw.buffers.add(i) as usize }
    }
    pub fn child(&self, i: usize) -> Option<ArrayRef<'a>> {
        if i >= self.raw.n_children.max(0) as usize {
            return None;
        }
        // SAFETY: the array has `n_children` child pointers.
        unsafe { (*self.raw.children.add(i)).as_ref().map(|raw| ArrayRef { raw }) }
    }
    pub fn dictionary(&self) -> Option<ArrayRef<'a>> {
        // SAFETY: a non-null dictionary pointer is a valid array.
        unsafe { self.raw.dictionary.as_ref().map(|raw| ArrayRef { raw }) }
    }
}

impl InArray {
    pub fn get(&self) -> ArrayRef<'_> {
        ArrayRef { raw: &self.raw }
    }
}

/// An imported stream: its schema and every batch.
pub struct Imported {
    pub schema: InField,
    pub batches: Vec<InArray>,
}

/// Take every batch of the stream at `p`, moving it out: its `release`
/// is set to null, and the stream is released here, once, whatever
/// happens.
///
/// # Safety
/// `p` points at a valid `ArrowArrayStream` that no one else is reading.
pub unsafe fn import_stream(p: *mut ArrowArrayStream) -> Result<Imported> {
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
        fail(format!("reading the Arrow stream ({what}): {msg}"))
    };
    let mut schema = empty_schema();
    let get_schema = stream.get_schema.ok_or_else(|| fail("an Arrow stream without get_schema"))?;
    if get_schema(&mut stream, &mut schema) != 0 {
        return Err(error(&mut stream, "schema"));
    }
    let field = read_field(&schema);
    if let Some(r) = schema.release {
        r(&mut schema);
    }
    let get_next = stream.get_next.ok_or_else(|| fail("an Arrow stream without get_next"))?;
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

// ------------------------------------------------------------ layouts

/// Whether row `i` (counting the array's offset) has a value. Panics if
/// `i` is past the array's end, where the bitmap may not reach.
#[inline]
pub fn valid(a: &ArrayRef, i: usize) -> bool {
    let v = a.buffer(0);
    if v == 0 || a.null_count() == 0 {
        return true;
    }
    assert!(i < a.offset() + a.len(), "row {i} is past the array's end");
    // SAFETY: the bitmap holds `offset + length` bits.
    unsafe { (*(v as *const u8).add(i / 8) >> (i % 8)) & 1 == 1 }
}

/// The bytes of row `i` of a string array (`u`, `U`, `vu` and the binary
/// ones), counting its offset.
///
/// # Safety
/// The array's buffers are of the format given.
pub unsafe fn text_at<'a>(a: &ArrayRef<'a>, format: &str, i: usize) -> &'a [u8] {
    match format {
        "u" | "z" => {
            let o = a.buffer(1) as *const i32;
            let (s, e) = (*o.add(i) as usize, *o.add(i + 1) as usize);
            std::slice::from_raw_parts((a.buffer(2) as *const u8).add(s), e - s)
        }
        "U" | "Z" => {
            let o = a.buffer(1) as *const i64;
            let (s, e) = (*o.add(i) as usize, *o.add(i + 1) as usize);
            std::slice::from_raw_parts((a.buffer(2) as *const u8).add(s), e - s)
        }
        _ => {
            // A view: 16 bytes, inline up to 12.
            let v = (a.buffer(1) as *const u8).add(16 * i);
            let len = u32::from_le_bytes(std::ptr::read_unaligned(v as *const [u8; 4])) as usize;
            if len <= 12 {
                std::slice::from_raw_parts(v.add(4), len)
            } else {
                let buf = u32::from_le_bytes(std::ptr::read_unaligned(v.add(8) as *const [u8; 4])) as usize;
                let off = u32::from_le_bytes(std::ptr::read_unaligned(v.add(12) as *const [u8; 4])) as usize;
                std::slice::from_raw_parts((a.buffer(2 + buf) as *const u8).add(off), len)
            }
        }
    }
}

/// A dictionary array's key at row `i`.
///
/// # Safety
/// The keys buffer holds row `i` in `format`.
pub unsafe fn key_at(a: &ArrayRef, format: &str, i: usize) -> Option<usize> {
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

/// Nanoseconds per unit of a `ts` or `tt` format's unit letter.
pub fn per_unit(c: u8) -> Option<i128> {
    Some(match c {
        b's' => 1_000_000_000,
        b'm' => 1_000_000,
        b'u' => 1_000,
        b'n' => 1,
        _ => return None,
    })
}
