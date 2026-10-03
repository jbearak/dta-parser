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
static MEMORY_PRESSURE: crate::native_pressure::NativeMemoryPressure =
    crate::native_pressure::NativeMemoryPressure::new();

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
        MEMORY_PRESSURE.allocated(owner.native_bytes);
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
            scalar_values: ptr::null(),
            scalar_start: 0,
            scalar_end: 0,
            domain_flags: 0,
        }
    }
}

const MISSING_SCAN_ROWS: usize = 65_536;
const _: () = assert!(MISSING_SCAN_ROWS <= u32::MAX as usize);

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
                    // A span fits in u32, including wider storage kinds;
                    // widen its subtotal after the contiguous reduction.
                    missing_count += values
                        .iter()
                        .map(|&value| u32::from(($missing)(value)))
                        .sum::<u32>() as usize;
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
            scalar_values: ptr::null(),
            scalar_start: 0,
            scalar_end: 0,
            domain_flags: source.domain_flags,
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

/// Return the complete owning chunk containing a scalar index. The base
/// pointer and half-open row bounds stay valid while the owner is rooted.
/// This function does not allocate, invoke R, or mutate any owner or buffer.
///
/// # Safety
///
/// `data` must be null or a live NumericData descriptor. Non-null output
/// pointers must be valid writable slots disjoint from the descriptor.
#[no_mangle]
pub unsafe extern "C" fn dtatools_owned_numeric_scalar_span(
    data: *const c_void,
    index: usize,
    values: *mut *const c_void,
    start: *mut usize,
    end: *mut usize,
) -> c_int {
    if data.is_null() || values.is_null() || start.is_null() || end.is_null() {
        return 0;
    }
    *values = ptr::null();
    *start = 0;
    *end = 0;
    let source = &*data.cast::<NumericData>();
    if source.native_owner.is_null() || index >= source.length {
        return 0;
    }
    let owner = &*source.native_owner.cast::<Owner>();
    if index >= owner.length {
        return 0;
    }
    let chunk_index = owner.chunks.partition_point(|chunk| chunk.end <= index);
    let Some(chunk) = owner.chunks.get(chunk_index) else {
        return 0;
    };
    *values = chunk.pointer().cast();
    *start = if chunk_index == 0 {
        0
    } else {
        owner.chunks[chunk_index - 1].end
    };
    *end = chunk.end;
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

pub(crate) fn collect_native_pressure<E>(
    collect: impl FnOnce() -> Result<(), E>,
) -> Result<bool, E> {
    MEMORY_PRESSURE.collect_if_needed(dtatools_owned_numeric_live_bytes(), collect)
}

#[no_mangle]
pub extern "C" fn dtatools_owned_numeric_gc_attempts() -> usize {
    MEMORY_PRESSURE.attempts()
}

#[no_mangle]
pub extern "C" fn dtatools_owned_numeric_allocation_debt() -> usize {
    MEMORY_PRESSURE.debt()
}

#[no_mangle]
pub unsafe extern "C" fn dtatools_owned_numeric_chunks(data: *const c_void) -> usize {
    let source = &*data.cast::<NumericData>();
    if source.native_owner.is_null() {
        return 0;
    }
    (&*source.native_owner.cast::<Owner>()).chunks.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    const RELEASES: [u16; 10] = [105, 108, 110, 111, 113, 114, 115, 117, 118, 119];

    fn assert_sliced_values_and_missing_count(
        arrays: Vec<ArrayRef>,
        kind: NumericKind,
        release: u16,
        expected_missing: usize,
        expected_bytes: &[u8],
    ) {
        let row_count = expected_bytes.len() / width(kind);
        let prepared = prepare_from_arrow(
            &arrays,
            kind,
            TemporalKind::None,
            FormatVersion::try_from(release).unwrap(),
            row_count,
            || false,
        )
        .expect("sliced compact chunks retain values and release-specific missings");
        let descriptor = prepared.into_descriptor();
        assert_eq!(descriptor.missing_count, expected_missing);
        let read = unsafe { RetainedRead::from_owner(descriptor.native_owner).unwrap() };
        drop(descriptor);
        drop(arrays);
        let mut observed = Vec::new();
        let mut row = 0;
        while row < read.len() {
            let (values, count) = read.region(row, row_count).unwrap();
            observed.extend_from_slice(unsafe {
                std::slice::from_raw_parts(values, count * width(kind))
            });
            row += count;
        }
        assert_eq!(observed, expected_bytes);
    }

    unsafe fn scalar_span(data: &NumericData, index: usize) -> Option<(*const u8, usize, usize)> {
        let mut values = ptr::null();
        let mut start = usize::MAX;
        let mut end = usize::MAX;
        let status = dtatools_owned_numeric_scalar_span(
            (data as *const NumericData).cast(),
            index,
            &mut values,
            &mut start,
            &mut end,
        );
        if status == 0 {
            assert!(values.is_null());
            assert_eq!((start, end), (0, 0));
            None
        } else {
            assert_eq!(status, 1);
            Some((values.cast(), start, end))
        }
    }

    #[test]
    fn scalar_spans_return_whole_sliced_arrow_chunks_in_any_order() {
        let whole = Int16Array::from(vec![99_i16, 10, 11, 12, 20, 21, 99]);
        let arrays: Vec<ArrayRef> = vec![
            Arc::new(Int16Array::from(Vec::<i16>::new())),
            Arc::new(whole.slice(1, 3)),
            Arc::new(Int16Array::from(Vec::<i16>::new())),
            Arc::new(whole.slice(4, 2)),
            Arc::new(Int16Array::from(Vec::<i16>::new())),
        ];
        let first_pointer = whole.values().as_ptr().wrapping_add(1).cast::<u8>();
        let second_pointer = whole.values().as_ptr().wrapping_add(4).cast::<u8>();
        let data = prepare_from_arrow(
            &arrays,
            NumericKind::Int,
            TemporalKind::None,
            FormatVersion::V118,
            5,
            || false,
        )
        .unwrap()
        .into_descriptor();
        drop(arrays);
        drop(whole);
        for index in [4, 3, 2, 1, 0, 2, 4, 0, 3, 1] {
            let (values, start, end) = unsafe { scalar_span(&data, index).unwrap() };
            let (expected_pointer, expected_start, expected_end, expected_values) = if index < 3 {
                (first_pointer, 0, 3, &[10_i16, 11, 12][..])
            } else {
                (second_pointer, 3, 5, &[20_i16, 21][..])
            };
            assert_eq!(values, expected_pointer);
            assert_eq!((start, end), (expected_start, expected_end));
            assert_eq!(
                unsafe { std::slice::from_raw_parts(values.cast::<i16>(), end - start) },
                expected_values
            );
            assert!(start <= index && index < end);
            // The existing bulk API still starts at the requested row.
            let mut region_values = ptr::null();
            let mut count = 0;
            assert_eq!(
                unsafe {
                    dtatools_owned_numeric_region(
                        (&data as *const NumericData).cast(),
                        index,
                        usize::MAX,
                        &mut region_values,
                        &mut count,
                    )
                },
                1
            );
            assert_eq!(
                region_values.cast::<u8>(),
                values.wrapping_add((index - start) * 2)
            );
            assert_eq!(count, end - index);
        }
        for index in [5, 6, usize::MAX] {
            assert!(unsafe { scalar_span(&data, index) }.is_none());
        }
    }

    #[test]
    fn scalar_spans_cover_raw_chunk_edges_for_every_storage_width() {
        for kind in [
            NumericKind::Byte,
            NumericKind::Int,
            NumericKind::Long,
            NumericKind::Float,
        ] {
            let bytes: Vec<u8> = (0..7 * width(kind)).map(|index| index as u8).collect();
            let descriptor = unsafe {
                dtatools_owned_numeric_from_raw(
                    bytes.as_ptr(),
                    7,
                    3,
                    kind as c_int,
                    TemporalKind::None as c_int,
                    118,
                    0,
                )
            };
            assert!(!descriptor.is_null());
            let data = unsafe { Box::from_raw(descriptor.cast::<NumericData>()) };
            for index in [6, 5, 4, 3, 2, 1, 0, 4, 1, 6, 0] {
                let (values, start, end) = unsafe { scalar_span(&data, index).unwrap() };
                let expected_start = index / 3 * 3;
                let expected_end = (expected_start + 3).min(7);
                assert_eq!((start, end), (expected_start, expected_end));
                assert_eq!(values, bytes.as_ptr().wrapping_add(start * width(kind)));
                assert_eq!(
                    unsafe { std::slice::from_raw_parts(values, (end - start) * width(kind)) },
                    &bytes[start * width(kind)..end * width(kind)]
                );
            }
            assert!(unsafe { scalar_span(&data, 7) }.is_none());
        }
    }

    #[test]
    fn scalar_spans_reject_empty_plain_and_invalid_arguments() {
        let empty = prepare_from_arrow(
            &[],
            NumericKind::Byte,
            TemporalKind::None,
            FormatVersion::V118,
            0,
            || false,
        )
        .unwrap()
        .into_descriptor();
        for index in [0, 1, usize::MAX] {
            assert!(unsafe { scalar_span(&empty, index) }.is_none());
        }
        let plain = NumericData::new(crate::RNumericData {
            backing: ptr::null_mut(),
            values: ptr::null_mut(),
            length: 0,
            kind: NumericKind::Byte,
            temporal: TemporalKind::None,
            format_version: FormatVersion::V118,
            missing_count: 0,
        });
        assert!(unsafe { scalar_span(&plain, 0) }.is_none());
        let data = (&empty as *const NumericData).cast();
        let mut values = ptr::null();
        let mut start = 0;
        let mut end = 0;
        assert_eq!(
            unsafe {
                dtatools_owned_numeric_scalar_span(
                    ptr::null(),
                    0,
                    &mut values,
                    &mut start,
                    &mut end,
                )
            },
            0
        );
        assert_eq!(
            unsafe {
                dtatools_owned_numeric_scalar_span(data, 0, ptr::null_mut(), &mut start, &mut end)
            },
            0
        );
        assert_eq!(
            unsafe {
                dtatools_owned_numeric_scalar_span(data, 0, &mut values, ptr::null_mut(), &mut end)
            },
            0
        );
        assert_eq!(
            unsafe {
                dtatools_owned_numeric_scalar_span(
                    data,
                    0,
                    &mut values,
                    &mut start,
                    ptr::null_mut(),
                )
            },
            0
        );
    }

    #[test]
    fn owned_int_missing_counts_cover_every_value_and_release_in_sliced_chunks() {
        let expected: Vec<i16> = (i16::MIN..=i16::MAX).collect();
        let expected_bytes: Vec<u8> = expected
            .iter()
            .flat_map(|value| value.to_ne_bytes())
            .collect();
        for release in RELEASES {
            let mut padded = vec![i16::MAX; 2];
            padded.extend_from_slice(&expected);
            padded.extend_from_slice(&[i16::MAX; 3]);
            let whole = Int16Array::from(padded);
            let arrays: Vec<ArrayRef> = vec![
                Arc::new(Int16Array::from(Vec::<i16>::new())),
                Arc::new(whole.slice(2, 13)),
                Arc::new(whole.slice(15, 4096)),
                Arc::new(whole.slice(4111, expected.len() - 4109)),
            ];
            drop(whole);
            assert_sliced_values_and_missing_count(
                arrays,
                NumericKind::Int,
                release,
                if release <= 111 { 1 } else { 27 },
                &expected_bytes,
            );
        }
    }

    #[test]
    fn owned_long_missing_counts_cover_sentinels_and_signed_boundaries_for_every_release() {
        let mut expected = vec![i32::MIN, i32::MIN + 1, -1, 0, 1, 2_147_483_620];
        expected.extend(2_147_483_621..=i32::MAX);
        let expected_bytes: Vec<u8> = expected
            .iter()
            .flat_map(|value| value.to_ne_bytes())
            .collect();
        for release in RELEASES {
            let mut padded = vec![i32::MAX; 2];
            padded.extend_from_slice(&expected);
            padded.extend_from_slice(&[i32::MAX; 3]);
            let whole = Int32Array::from(padded);
            let arrays: Vec<ArrayRef> = vec![
                Arc::new(Int32Array::from(Vec::<i32>::new())),
                Arc::new(whole.slice(2, 7)),
                Arc::new(whole.slice(9, expected.len() - 7)),
            ];
            drop(whole);
            assert_sliced_values_and_missing_count(
                arrays,
                NumericKind::Long,
                release,
                if release <= 111 { 1 } else { 27 },
                &expected_bytes,
            );
        }
    }

    #[test]
    fn owned_float_missing_counts_preserve_nan_payloads_and_legacy_ranges() {
        // These finite values and negative infinity are observed in every
        // release. Positive infinity belongs to the legacy missing range.
        let mut bits = vec![
            0,
            0x8000_0000,
            0x3f80_0000,
            0xbf80_0000,
            0x7eff_ffff,
            0xfeff_ffff,
            0xff00_0000,
            0xff80_0000,
        ];
        bits.extend((0..=26).map(|tag| 0x7f00_0000 + tag * 0x800));
        bits.extend([
            0x7f00_0001,
            0x7f00_07ff,
            0x7f00_d001,
            0x7f7f_ffff,
            0x7f80_0000,
        ]);
        // Both signs, quiet/signalling encodings and payload extremes remain
        // bit-exact in retained backing and count as missing in every release.
        bits.extend([
            0x7f80_0001,
            0x7fc0_0000,
            0x7fff_ffff,
            0xff80_0001,
            0xffc0_0000,
            0xffff_ffff,
        ]);
        let expected: Vec<f32> = bits.iter().copied().map(f32::from_bits).collect();
        let expected_bytes: Vec<u8> = bits.iter().flat_map(|value| value.to_ne_bytes()).collect();
        for release in RELEASES {
            let mut padded = vec![f32::NAN; 2];
            padded.extend_from_slice(&expected);
            padded.extend_from_slice(&[f32::NAN; 3]);
            let whole = Float32Array::from(padded);
            let arrays: Vec<ArrayRef> = vec![
                Arc::new(Float32Array::from(Vec::<f32>::new())),
                Arc::new(whole.slice(2, 11)),
                Arc::new(whole.slice(13, expected.len() - 11)),
            ];
            drop(whole);
            assert_sliced_values_and_missing_count(
                arrays,
                NumericKind::Float,
                release,
                if release <= 111 { 38 } else { 33 },
                &expected_bytes,
            );
        }
    }

    #[test]
    fn wider_owned_missing_scans_accumulate_spans_and_keep_cancellation_bounds() {
        let rows = MISSING_SCAN_ROWS * 2 + 1;
        let cases: Vec<(NumericKind, ArrayRef)> = vec![
            (
                NumericKind::Int,
                Arc::new(Int16Array::from(vec![i16::MAX; rows])),
            ),
            (
                NumericKind::Long,
                Arc::new(Int32Array::from(vec![i32::MAX; rows])),
            ),
            (
                NumericKind::Float,
                Arc::new(Float32Array::from(vec![f32::NAN; rows])),
            ),
        ];
        for (kind, array) in cases {
            let arrays = [array];
            // Initial poll, three bounded scan spans, and the final poll.
            for stop_at in 1..=5 {
                let mut polls = 0;
                let result = prepare_from_arrow(
                    &arrays,
                    kind,
                    TemporalKind::None,
                    FormatVersion::V118,
                    rows,
                    || {
                        polls += 1;
                        polls == stop_at
                    },
                );
                assert_eq!(result.err().as_deref(), Some("Arrow read interrupted"));
                assert_eq!(polls, stop_at);
            }
            let prepared = prepare_from_arrow(
                &arrays,
                kind,
                TemporalKind::None,
                FormatVersion::V118,
                rows,
                || false,
            )
            .expect("complete wider-storage scan spanning full blocks and a tail");
            assert_eq!(prepared.into_descriptor().missing_count, rows);
        }
    }

    #[test]
    fn owned_byte_missing_counts_preserve_sliced_chunk_values_for_every_release() {
        for (format_release, expected_missing) in [
            (105, 1),
            (108, 1),
            (110, 1),
            (111, 1),
            (113, 27),
            (114, 27),
            (115, 27),
            (117, 27),
            (118, 27),
            (119, 27),
        ] {
            let expected: Vec<i8> = (0..256).map(|value| value as i8).collect();
            let mut padded = vec![127_i8; 3];
            padded.extend_from_slice(&expected);
            padded.extend_from_slice(&[127; 5]);
            let whole = Int8Array::from(padded);
            let arrays: Vec<ArrayRef> = vec![
                Arc::new(Int8Array::from(Vec::<i8>::new())),
                Arc::new(whole.slice(3, 15)),
                Arc::new(whole.slice(18, 17)),
                Arc::new(whole.slice(35, 223)),
                Arc::new(whole.slice(258, 1)),
            ];
            let prepared = prepare_from_arrow(
                &arrays,
                NumericKind::Byte,
                TemporalKind::None,
                FormatVersion::try_from(format_release).unwrap(),
                256,
                || false,
            )
            .expect("sliced byte chunks preserve their values and release-specific missings");
            let descriptor = prepared.into_descriptor();
            assert_eq!(descriptor.missing_count, expected_missing);
            let read = unsafe { RetainedRead::from_owner(descriptor.native_owner).unwrap() };
            drop(descriptor);
            drop(arrays);
            drop(whole);
            let mut observed = Vec::new();
            while observed.len() < read.len() {
                let (values, count) = read.region(observed.len(), 256).unwrap();
                observed.extend_from_slice(unsafe {
                    std::slice::from_raw_parts(values.cast::<i8>(), count)
                });
            }
            assert_eq!(observed, expected);
        }
    }

    #[test]
    fn owned_byte_missing_scan_remains_interruptible_between_bounded_spans() {
        let rows = MISSING_SCAN_ROWS + 1;
        let arrays: Vec<ArrayRef> = vec![Arc::new(Int8Array::from(vec![127; rows]))];
        for stop_at in 1..=4 {
            let mut polls = 0;
            let result = prepare_from_arrow(
                &arrays,
                NumericKind::Byte,
                TemporalKind::None,
                FormatVersion::V118,
                rows,
                || {
                    polls += 1;
                    polls == stop_at
                },
            );
            assert_eq!(result.err().as_deref(), Some("Arrow read interrupted"));
            assert_eq!(polls, stop_at);
        }
        let prepared = prepare_from_arrow(
            &arrays,
            NumericKind::Byte,
            TemporalKind::None,
            FormatVersion::V118,
            rows,
            || false,
        )
        .expect("complete bounded byte scan");
        let descriptor = prepared.into_descriptor();
        assert_eq!(descriptor.missing_count, rows);
    }

    #[test]
    fn owned_byte_missing_counts_accumulate_across_full_spans_and_chunk_tails() {
        let arrays: Vec<ArrayRef> = vec![
            Arc::new(Int8Array::from(vec![127; 65_535])),
            Arc::new(Int8Array::from(vec![101; 65_536])),
            Arc::new(Int8Array::from(vec![-1; 65_537])),
            Arc::new(Int8Array::from(vec![127; 131_073])),
        ];
        for (version, expected_missing) in [
            (FormatVersion::V111, 196_608),
            (FormatVersion::V118, 262_144),
        ] {
            let prepared = prepare_from_arrow(
                &arrays,
                NumericKind::Byte,
                TemporalKind::None,
                version,
                327_681,
                || false,
            )
            .expect("missing counts span complete scan blocks and chunk tails");
            assert_eq!(prepared.into_descriptor().missing_count, expected_missing);
        }
    }
}
