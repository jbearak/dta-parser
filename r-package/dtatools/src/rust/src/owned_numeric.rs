//! Experimental immutable compact numeric owners.
//!
//! C owns independent NumericData descriptors. Each descriptor retains this
//! owner, whose buffers are never offered through a mutable pointer. R-backed
//! chunks borrow an immutable raw allocation rooted by every C handle; Arrow
//! chunks retain their Buffer. These are deliberately distinct ownership cases.

use std::collections::HashSet;
use std::ffi::{c_int, c_void};
use std::ptr;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use arrow_array::{Array, ArrayRef, Float32Array, Int16Array, Int32Array, Int8Array};
use arrow_buffer::{Buffer, ScalarBuffer};

use crate::{FormatVersion, NumericData, NumericKind, TemporalKind};

static LIVE_NATIVE_BYTES: AtomicUsize = AtomicUsize::new(0);
static LIVE_OWNERS: AtomicUsize = AtomicUsize::new(0);

enum Storage {
    Arrow(Buffer),
    /// The C external pointer's protected slot retains the immutable RAWSXP.
    RRaw(usize),
}

struct Chunk {
    storage: Storage,
    end: usize,
}

impl Chunk {
    fn pointer(&self) -> *const u8 {
        match &self.storage {
            Storage::Arrow(buffer) => buffer.as_ptr(),
            Storage::RRaw(address) => *address as *const u8,
        }
    }
}

pub(crate) struct Owner {
    chunks: Vec<Chunk>,
    width: usize,
    length: usize,
    native_bytes: usize,
}

impl Drop for Owner {
    fn drop(&mut self) {
        LIVE_NATIVE_BYTES.fetch_sub(self.native_bytes, Ordering::Relaxed);
        LIVE_OWNERS.fetch_sub(1, Ordering::Relaxed);
    }
}

/// Pins a native owner independently of any ALTREP descriptor. R-backed chunks
/// still require the caller's immutable raw allocation to remain rooted until
/// the last read finishes. `arrow_chunks` copies those R-backed chunks so its
/// returned arrays can outlive the R read root.
pub(crate) struct RetainedRead {
    owner: Arc<Owner>,
}

impl RetainedRead {
    /// `owner` must be a live Owner pointer retained by a protected C read root.
    pub(crate) unsafe fn from_owner(owner: *const c_void) -> Option<Self> {
        if owner.is_null() {
            return None;
        }
        Arc::increment_strong_count(owner.cast::<Owner>());
        Some(Self {
            owner: Arc::from_raw(owner.cast::<Owner>()),
        })
    }

    pub(crate) fn len(&self) -> usize {
        self.owner.length
    }

    pub(crate) fn region(&self, start: usize, requested: usize) -> Option<(*const u8, usize)> {
        self.owner.region(start, requested)
    }

    pub(crate) fn arrow_chunks(&self, kind: NumericKind) -> Result<Vec<ArrayRef>, String> {
        if width(kind) != self.owner.width {
            return Err("owned numeric kind disagrees with retained width".to_owned());
        }
        let mut arrays = Vec::new();
        arrays
            .try_reserve_exact(self.owner.chunks.len())
            .map_err(|_| "could not reserve retained Arrow chunks".to_owned())?;
        let mut start = 0;
        for chunk in &self.owner.chunks {
            let length = chunk.end - start;
            let buffer = match &chunk.storage {
                Storage::Arrow(buffer) => buffer.clone(),
                Storage::RRaw(address) => unsafe {
                    Buffer::from_slice_ref(std::slice::from_raw_parts(
                        *address as *const u8,
                        length * self.owner.width,
                    ))
                },
            };
            let array: ArrayRef = match kind {
                NumericKind::Byte => {
                    Arc::new(Int8Array::new(ScalarBuffer::new(buffer, 0, length), None))
                }
                NumericKind::Int => {
                    Arc::new(Int16Array::new(ScalarBuffer::new(buffer, 0, length), None))
                }
                NumericKind::Long => {
                    Arc::new(Int32Array::new(ScalarBuffer::new(buffer, 0, length), None))
                }
                NumericKind::Float => Arc::new(Float32Array::new(
                    ScalarBuffer::new(buffer, 0, length),
                    None,
                )),
            };
            arrays.push(array);
            start = chunk.end;
        }
        Ok(arrays)
    }
}

impl Owner {
    fn region(&self, start: usize, requested: usize) -> Option<(*const u8, usize)> {
        if start > self.length {
            return None;
        }
        if requested == 0 || start == self.length {
            return Some((ptr::null(), 0));
        }
        let index = self.chunks.partition_point(|chunk| chunk.end <= start);
        let chunk = self.chunks.get(index)?;
        let first = if index == 0 {
            0
        } else {
            self.chunks[index - 1].end
        };
        Some((
            unsafe { chunk.pointer().add((start - first) * self.width) },
            requested.min(chunk.end - start),
        ))
    }
}

/// Read-only adapter for a rooted R allocation or a retained chunked owner.
/// The contiguous case performs no allocation or reference-count operation.
pub(crate) struct CompactRead {
    values: *const u8,
    width: usize,
    length: usize,
    retained: Option<RetainedRead>,
}

impl CompactRead {
    pub(crate) unsafe fn new(
        values: *const c_void,
        owner: *const c_void,
        width: usize,
        length: usize,
    ) -> Option<Self> {
        let retained = RetainedRead::from_owner(owner);
        if width == 0
            || (retained.is_none() && values.is_null() && length != 0)
            || retained
                .as_ref()
                .is_some_and(|read| read.owner.width != width || read.len() < length)
        {
            return None;
        }
        Some(Self {
            values: values.cast(),
            width,
            length,
            retained,
        })
    }

    pub(crate) fn region(&self, start: usize, requested: usize) -> Option<(*const u8, usize)> {
        if start > self.length {
            return None;
        }
        let requested = requested.min(self.length - start);
        if let Some(read) = &self.retained {
            return read.region(start, requested);
        }
        if requested == 0 {
            return Some((ptr::null(), 0));
        }
        Some((unsafe { self.values.add(start * self.width) }, requested))
    }

    pub(crate) fn cursor(&self) -> ReadCursor<'_> {
        ReadCursor {
            source: self,
            start: 0,
            end: 0,
            values: ptr::null(),
        }
    }
}

pub(crate) struct ReadCursor<'a> {
    source: &'a CompactRead,
    start: usize,
    end: usize,
    values: *const u8,
}

impl ReadCursor<'_> {
    pub(crate) fn at(&mut self, index: usize) -> Option<*const u8> {
        if index < self.start || index >= self.end {
            let (values, count) = self.source.region(index, usize::MAX)?;
            if count == 0 {
                return None;
            }
            self.values = values;
            self.start = index;
            self.end = index + count;
        }
        Some(unsafe { self.values.add((index - self.start) * self.source.width) })
    }
}

fn width(kind: NumericKind) -> usize {
    match kind {
        NumericKind::Byte => 1,
        NumericKind::Int => 2,
        NumericKind::Long | NumericKind::Float => 4,
    }
}

fn descriptor(
    owner: Owner,
    kind: NumericKind,
    temporal: TemporalKind,
    version: FormatVersion,
    missing_count: usize,
) -> NumericData {
    PreparedOwnedNumeric::new(owner, kind, temporal, version, missing_count).into_descriptor()
}

/// Fully checked native state. Workers can create/drop this without calling R;
/// only the R thread turns it into an external-pointer descriptor.
pub(crate) struct PreparedOwnedNumeric {
    owner: Arc<Owner>,
    kind: NumericKind,
    temporal: TemporalKind,
    version: FormatVersion,
    missing_count: usize,
}

impl PreparedOwnedNumeric {
    fn new(
        owner: Owner,
        kind: NumericKind,
        temporal: TemporalKind,
        version: FormatVersion,
        missing_count: usize,
    ) -> Self {
        LIVE_NATIVE_BYTES.fetch_add(owner.native_bytes, Ordering::Relaxed);
        LIVE_OWNERS.fetch_add(1, Ordering::Relaxed);
        Self {
            owner: Arc::new(owner),
            kind,
            temporal,
            version,
            missing_count,
        }
    }

    pub(crate) fn into_descriptor(self) -> NumericData {
        NumericData {
            values: ptr::null_mut(),
            length: self.owner.length,
            kind: self.kind as c_int,
            temporal: self.temporal as c_int,
            format_version: c_int::from(self.version.as_u16()),
            missing_count: self.missing_count,
            native_owner: Arc::into_raw(self.owner).cast(),
        }
    }
}

const MISSING_SCAN_ROWS: usize = 65_536;

pub(crate) fn prepare_from_arrow(
    arrays: &[ArrayRef],
    kind: NumericKind,
    temporal: TemporalKind,
    version: FormatVersion,
    expected_rows: usize,
    mut cancelled: impl FnMut() -> bool,
) -> Result<PreparedOwnedNumeric, String> {
    if cancelled() {
        return Err("Arrow read interrupted".to_owned());
    }
    expected_rows
        .checked_mul(width(kind))
        .filter(|&bytes| bytes <= isize::MAX as usize)
        .ok_or_else(|| "owned compact column is too long".to_owned())?;
    let mut chunks = Vec::new();
    chunks
        .try_reserve_exact(arrays.len())
        .map_err(|_| "could not allocate owned compact chunk descriptors".to_owned())?;
    let mut seen = HashSet::new();
    seen.try_reserve(arrays.len())
        .map_err(|_| "could not track owned compact allocations".to_owned())?;
    let mut length = 0usize;
    let mut native_bytes = 0usize;
    let mut missing_count = 0usize;
    for array in arrays {
        length = length
            .checked_add(array.len())
            .filter(|&rows| rows <= expected_rows)
            .ok_or_else(|| "owned compact chunk lengths exceed output length".to_owned())?;
        if array.null_count() != 0 {
            return Err("owned compact Arrow chunks cannot contain nulls".to_owned());
        }
        macro_rules! buffer {
            ($array:ty, $missing:expr) => {{
                let typed = array
                    .as_any()
                    .downcast_ref::<$array>()
                    .ok_or_else(|| "owned compact Arrow chunk has the wrong type".to_owned())?;
                for values in typed.values().chunks(MISSING_SCAN_ROWS) {
                    if cancelled() {
                        return Err("Arrow read interrupted".to_owned());
                    }
                    // No callbacks or atomics in the typed reduction. Each
                    // block is bounded so workers respond to cancellation.
                    missing_count += values.iter().filter(|&&value| ($missing)(value)).count();
                }
                typed.values().inner().clone()
            }};
        }
        let buffer = match kind {
            NumericKind::Byte => {
                buffer!(Int8Array, |value| crate::classify_byte_missing_for_version(
                    value, version
                )
                .is_some())
            }
            NumericKind::Int => {
                buffer!(Int16Array, |value| crate::classify_int_missing_for_version(
                    value, version
                )
                .is_some())
            }
            NumericKind::Long => buffer!(Int32Array, |value| {
                crate::classify_long_missing_for_version(value, version).is_some()
            }),
            NumericKind::Float => buffer!(Float32Array, |value: f32| value.is_nan()
                || crate::classify_float_missing_bits_for_version(value.to_bits(), version)
                    .is_some()),
        };
        if array.is_empty() {
            continue;
        }
        if buffer.len() != array.len() * width(kind) {
            return Err("owned compact Arrow buffer has the wrong length".to_owned());
        }
        // Capacity measures the retained allocation, including sliced-away
        // bytes. Deduplicate shared slices within this column. Separate owners
        // may charge one shared allocation twice; diagnostics document this.
        if seen.insert(buffer.data_ptr().as_ptr() as usize) {
            native_bytes = native_bytes
                .checked_add(buffer.capacity())
                .ok_or_else(|| "owned compact byte accounting overflow".to_owned())?;
        }
        chunks.push(Chunk {
            storage: Storage::Arrow(buffer),
            end: length,
        });
    }
    if length != expected_rows {
        return Err("owned compact chunks do not match output length".to_owned());
    }
    if cancelled() {
        return Err("Arrow read interrupted".to_owned());
    }
    Ok(PreparedOwnedNumeric::new(
        Owner {
            chunks,
            width: width(kind),
            length,
            native_bytes,
        },
        kind,
        temporal,
        version,
        missing_count,
    ))
}

/// The R thread keeps `data` rooted and immutable for every retained handle.
#[no_mangle]
pub unsafe extern "C" fn dtatools_owned_numeric_from_raw(
    data: *const u8,
    length: usize,
    chunk_rows: usize,
    kind: c_int,
    temporal: c_int,
    release: c_int,
    missing_count: usize,
) -> *mut c_void {
    let result = std::panic::catch_unwind(|| {
        let kind = NumericKind::try_from(kind).ok()?;
        let temporal = TemporalKind::try_from(temporal).ok()?;
        let version = FormatVersion::try_from(u16::try_from(release).ok()?).ok()?;
        let bytes = length.checked_mul(width(kind))?;
        if bytes > isize::MAX as usize || (length > 0 && data.is_null()) || chunk_rows == 0 {
            return None;
        }
        let count = length.div_ceil(chunk_rows);
        let mut chunks = Vec::new();
        chunks.try_reserve_exact(count).ok()?;
        let mut start = 0;
        while start < length {
            let end = start.saturating_add(chunk_rows).min(length);
            chunks.push(Chunk {
                storage: Storage::RRaw(data.add(start * width(kind)) as usize),
                end,
            });
            start = end;
        }
        Some(
            Box::into_raw(Box::new(descriptor(
                Owner {
                    chunks,
                    width: width(kind),
                    length,
                    native_bytes: 0,
                },
                kind,
                temporal,
                version,
                missing_count,
            )))
            .cast(),
        )
    });
    result.ok().flatten().unwrap_or(ptr::null_mut())
}

pub(crate) unsafe fn release(owner: *const c_void) {
    if !owner.is_null() {
        drop(Arc::from_raw(owner.cast::<Owner>()));
    }
}

/// Create an independent descriptor; C copies the original R roots, if any.
#[no_mangle]
pub unsafe extern "C" fn dtatools_owned_numeric_clone(data: *const c_void) -> *mut c_void {
    if data.is_null() {
        return ptr::null_mut();
    }
    let source = &*data.cast::<NumericData>();
    if source.native_owner.is_null() {
        return ptr::null_mut();
    }
    let result = std::panic::catch_unwind(|| {
        let mut result = Box::new(NumericData {
            values: ptr::null_mut(),
            length: source.length,
            kind: source.kind,
            temporal: source.temporal,
            format_version: source.format_version,
            missing_count: source.missing_count,
            native_owner: ptr::null(),
        });
        Arc::increment_strong_count(source.native_owner.cast::<Owner>());
        result.native_owner = source.native_owner;
        Box::into_raw(result).cast()
    });
    result.unwrap_or(ptr::null_mut())
}

/// Read-only contiguous span, borrowed while the descriptor/owner is rooted.
/// This function does not allocate, invoke R, or mutate a buffer.
#[no_mangle]
pub unsafe extern "C" fn dtatools_owned_numeric_region(
    data: *const c_void,
    start: usize,
    requested: usize,
    values: *mut *const c_void,
    count: *mut usize,
) -> c_int {
    if data.is_null() || values.is_null() || count.is_null() {
        return 0;
    }
    *values = ptr::null();
    *count = 0;
    let source = &*data.cast::<NumericData>();
    if source.native_owner.is_null() {
        return 0;
    }
    let owner = &*source.native_owner.cast::<Owner>();
    if start > owner.length {
        return 0;
    }
    if requested == 0 || start == owner.length {
        return 1;
    }
    let index = owner.chunks.partition_point(|chunk| chunk.end <= start);
    let Some(chunk) = owner.chunks.get(index) else {
        return 0;
    };
    let first = if index == 0 {
        0
    } else {
        owner.chunks[index - 1].end
    };
    *values = chunk.pointer().add((start - first) * owner.width).cast();
    *count = requested.min(chunk.end - start);
    1
}

#[no_mangle]
pub extern "C" fn dtatools_owned_numeric_live_bytes() -> usize {
    LIVE_NATIVE_BYTES.load(Ordering::Relaxed)
}

#[no_mangle]
pub extern "C" fn dtatools_owned_numeric_live_owners() -> usize {
    LIVE_OWNERS.load(Ordering::Relaxed)
}

#[no_mangle]
pub unsafe extern "C" fn dtatools_owned_numeric_chunks(data: *const c_void) -> usize {
    let source = &*data.cast::<NumericData>();
    if source.native_owner.is_null() {
        return 0;
    }
    (&*source.native_owner.cast::<Owner>()).chunks.len()
}
