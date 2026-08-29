//! Canonical per-buffer xxHash64 checksums.
//!
//! Both the writer and the reader hash the logical bytes of each Arrow buffer
//! in a canonical, offset-independent form: validity bitmaps and boolean
//! values sliced to `ceil(len / 8)` bytes with unused trailing bits masked,
//! string offsets rebased to start at zero, and value buffers sliced to their
//! exact logical length. The writer hashes the arrays it is about to write;
//! the reader hashes the arrays it reconstructed, so any bit flipped in a
//! stored buffer changes the recomputed hash.

use std::borrow::Cow;

use arrow_array::Array;
use arrow_buffer::ArrowNativeType;
use arrow_data::ArrayData;
use arrow_schema::DataType;

use super::ArrowProfileError;

const XXH64_SEED: u64 = 0;

pub(crate) fn xxh64(bytes: &[u8]) -> u64 {
    twox_hash::XxHash64::oneshot(XXH64_SEED, bytes)
}

fn unsupported(data_type: &DataType) -> ArrowProfileError {
    ArrowProfileError::Invalid(format!(
        "cannot checksum unsupported Arrow type {data_type}"
    ))
}

/// The exact bytes of a bitmap covering `len` bits starting at `bit_offset`,
/// with the unused bits of the final byte cleared. The offset must be
/// byte-aligned, which the bounded batch length guarantees.
fn canonical_bitmap(
    bytes: &[u8],
    bit_offset: usize,
    len: usize,
) -> Result<Cow<'_, [u8]>, ArrowProfileError> {
    if !bit_offset.is_multiple_of(8) {
        return Err(ArrowProfileError::Invalid(
            "bitmap checksum requires a byte-aligned offset".to_owned(),
        ));
    }
    let start = bit_offset / 8;
    let byte_length = len.div_ceil(8);
    let slice = bytes
        .get(start..start + byte_length)
        .ok_or_else(|| ArrowProfileError::Invalid("bitmap buffer is too short".to_owned()))?;
    let trailing_bits = len % 8;
    if trailing_bits == 0 {
        return Ok(Cow::Borrowed(slice));
    }
    let mut owned = slice.to_vec();
    let mask = (1_u8 << trailing_bits) - 1;
    *owned.last_mut().expect("len > 0 implies a final byte") &= mask;
    Ok(Cow::Owned(owned))
}

fn value_slice(
    data: &ArrayData,
    buffer_index: usize,
    width: usize,
) -> Result<&[u8], ArrowProfileError> {
    let buffer = data
        .buffers()
        .get(buffer_index)
        .ok_or_else(|| ArrowProfileError::Invalid("missing Arrow value buffer".to_owned()))?;
    let start = data.offset() * width;
    let end = start + data.len() * width;
    buffer
        .as_slice()
        .get(start..end)
        .ok_or_else(|| ArrowProfileError::Invalid("Arrow value buffer is too short".to_owned()))
}

fn offsets_hashes<O: ArrowNativeType + Into<i64>>(
    data: &ArrayData,
    hashes: &mut Vec<u64>,
) -> Result<(), ArrowProfileError> {
    let offsets: &[O] = data.buffer(0);
    let window = offsets
        .get(data.offset()..data.offset() + data.len() + 1)
        .ok_or_else(|| ArrowProfileError::Invalid("Arrow offset buffer is too short".to_owned()))?;
    let first: i64 = window[0].into();
    let last: i64 = window[window.len() - 1].into();
    if first == 0 {
        let start = data.offset() * size_of::<O>();
        let bytes = data.buffers()[0]
            .as_slice()
            .get(start..start + size_of_val(window))
            .ok_or_else(|| {
                ArrowProfileError::Invalid("Arrow offset buffer is too short".to_owned())
            })?;
        hashes.push(xxh64(bytes));
    } else {
        // A sliced batch: hash the rebased offsets the IPC writer stores.
        let mut rebased = Vec::with_capacity(size_of_val(window));
        for &offset in window {
            let offset: i64 = offset.into();
            let rebased_offset = offset - first;
            if size_of::<O>() == 4 {
                rebased.extend_from_slice(&(rebased_offset as i32).to_le_bytes());
            } else {
                rebased.extend_from_slice(&rebased_offset.to_le_bytes());
            }
        }
        hashes.push(xxh64(&rebased));
    }
    let values = data.buffers()[1]
        .as_slice()
        .get(usize::try_from(first).unwrap_or(usize::MAX)
            ..usize::try_from(last).unwrap_or(usize::MAX))
        .ok_or_else(|| ArrowProfileError::Invalid("Arrow string buffer is too short".to_owned()))?;
    hashes.push(xxh64(values));
    Ok(())
}

/// Hash every canonical buffer of one array: the validity bitmap when the
/// array has nulls, then the type's data buffers. Dictionary arrays hash only
/// their key buffer; their shared values array is hashed separately.
pub(crate) fn canonical_array_hashes(array: &dyn Array) -> Result<Vec<u64>, ArrowProfileError> {
    let data = array.to_data();
    let mut hashes = Vec::new();
    if let Some(nulls) = data.nulls() {
        let bitmap = canonical_bitmap(
            nulls.buffer().as_slice(),
            nulls.inner().offset(),
            nulls.len(),
        )?;
        hashes.push(xxh64(&bitmap));
    }
    match data.data_type() {
        DataType::Boolean => {
            let buffer = data.buffers().first().ok_or_else(|| {
                ArrowProfileError::Invalid("missing Arrow boolean buffer".to_owned())
            })?;
            let bitmap = canonical_bitmap(buffer.as_slice(), data.offset(), data.len())?;
            hashes.push(xxh64(&bitmap));
        }
        data_type @ (DataType::Int8
        | DataType::Int16
        | DataType::Int32
        | DataType::Int64
        | DataType::UInt8
        | DataType::UInt16
        | DataType::UInt32
        | DataType::UInt64
        | DataType::Float32
        | DataType::Float64
        | DataType::Date32
        | DataType::Date64
        | DataType::Timestamp(_, _)
        | DataType::Duration(_)) => {
            let width = data_type
                .primitive_width()
                .ok_or_else(|| unsupported(data_type))?;
            hashes.push(xxh64(value_slice(&data, 0, width)?));
        }
        DataType::Utf8 => offsets_hashes::<i32>(&data, &mut hashes)?,
        DataType::LargeUtf8 => offsets_hashes::<i64>(&data, &mut hashes)?,
        DataType::Dictionary(key_type, _) => {
            let width = key_type
                .primitive_width()
                .ok_or_else(|| unsupported(data.data_type()))?;
            hashes.push(xxh64(value_slice(&data, 0, width)?));
        }
        other => return Err(unsupported(other)),
    }
    Ok(hashes)
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use arrow_array::{ArrayRef, BooleanArray, Int32Array, StringArray};

    use super::*;

    #[test]
    fn sliced_and_rebuilt_arrays_hash_identically() {
        let strings: ArrayRef = Arc::new(StringArray::from(vec![
            Some("alpha"),
            None,
            Some("beta"),
            Some("gamma"),
        ]));
        let sliced = strings.slice(2, 2);
        let rebuilt: ArrayRef = Arc::new(StringArray::from(vec![Some("beta"), Some("gamma")]));
        assert_eq!(
            canonical_array_hashes(&sliced).unwrap(),
            canonical_array_hashes(&rebuilt).unwrap()
        );
    }

    #[test]
    fn boolean_trailing_bits_do_not_affect_the_hash() {
        let long = BooleanArray::from(vec![true, false, true, true, false, true, false, false]);
        let short = BooleanArray::from(vec![true, false, true]);
        let sliced = long.slice(0, 3);
        assert_eq!(
            canonical_array_hashes(&sliced).unwrap(),
            canonical_array_hashes(&short).unwrap()
        );
    }

    #[test]
    fn value_changes_change_the_hash() {
        let first = Int32Array::from(vec![1, 2, 3]);
        let second = Int32Array::from(vec![1, 2, 4]);
        assert_ne!(
            canonical_array_hashes(&first).unwrap(),
            canonical_array_hashes(&second).unwrap()
        );
    }
}
