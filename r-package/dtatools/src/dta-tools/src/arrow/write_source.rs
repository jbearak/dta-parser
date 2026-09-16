//! Checked, immutable arrays presented as one logical writer column.
//!
//! The writer requests canonical row windows, never a contiguous whole column.
//! A window inside one chunk shares its value buffers. Crossing windows own only
//! that window's concatenation; unaligned bitmaps need at most a window's bitmap.

use std::sync::Arc;

use arrow_array::types::Int32Type;
use arrow_array::{Array, ArrayRef, BooleanArray, DictionaryArray, Int32Array};
use arrow_buffer::{BooleanBuffer, NullBuffer};
use arrow_schema::DataType;

use super::{ArrowProfileError, ARROW_ROWS_PER_BATCH};

/// An immutable column for the private R adapter writer interface.
///
/// Owns array handles, which keep all underlying buffers alive. `try_new`
/// validates chunks and requires one Arrow type and unchanged dictionary values.
/// At least one typed array is required, even for a zero-row column.
/// Batch hashing copies at most one canonical column window per task. Writing
/// can retain one window per column of the active record batch. Variable-width
/// data has no fixed byte bound per window; these are not total-memory limits.
pub struct ArrowWriteSource {
    chunks: Vec<ArrayRef>,
    ends: Vec<usize>,
    length: usize,
    null_count: usize,
    dictionary: Option<ArrayRef>,
}

impl ArrowWriteSource {
    /// Adapt one array under the same valid-Arrow-array precondition as
    /// `ArrowWriteColumn`. Safe Arrow builders already establish that invariant;
    /// this adds no redundant full string or dictionary validation pass.
    pub fn from_array(array: ArrayRef) -> Self {
        let length = array.len();
        let null_count = array.null_count();
        let dictionary = if matches!(array.data_type(), DataType::Dictionary(_, _)) {
            super::write::dictionary_values(&array)
        } else {
            None
        };
        Self {
            chunks: vec![array],
            ends: vec![length],
            length,
            null_count,
            dictionary,
        }
    }

    pub fn try_new(chunks: Vec<ArrayRef>) -> Result<Self, ArrowProfileError> {
        let first = chunks.first().ok_or_else(|| {
            ArrowProfileError::Invalid("Arrow write source requires a typed array".to_owned())
        })?;
        let data_type = first.data_type();
        let dictionary = if matches!(data_type, DataType::Dictionary(_, _)) {
            Some(super::write::dictionary_values(first).ok_or_else(|| {
                ArrowProfileError::Invalid("dictionary source has no values array".to_owned())
            })?)
        } else {
            None
        };
        let mut ends = Vec::with_capacity(chunks.len());
        let mut length = 0_usize;
        let mut null_count = 0_usize;
        for chunk in &chunks {
            if chunk.data_type() != data_type {
                return Err(ArrowProfileError::Invalid(
                    "Arrow write source chunks have different types".to_owned(),
                ));
            }
            chunk.to_data().validate_full().map_err(|error| {
                ArrowProfileError::Invalid(format!("invalid Arrow write source: {error}"))
            })?;
            if let Some(expected) = &dictionary {
                let values = super::write::dictionary_values(chunk).ok_or_else(|| {
                    ArrowProfileError::Invalid("dictionary source has no values array".to_owned())
                })?;
                if values.to_data() != expected.to_data() {
                    return Err(ArrowProfileError::Invalid(
                        "Arrow write source dictionary values change between chunks".to_owned(),
                    ));
                }
            }
            length = length.checked_add(chunk.len()).ok_or_else(|| {
                ArrowProfileError::Invalid("Arrow write source row count overflow".to_owned())
            })?;
            null_count = null_count.checked_add(chunk.null_count()).ok_or_else(|| {
                ArrowProfileError::Invalid("Arrow write source null count overflow".to_owned())
            })?;
            ends.push(length);
        }
        Ok(Self {
            chunks,
            ends,
            length,
            null_count,
            dictionary,
        })
    }

    pub fn len(&self) -> usize {
        self.length
    }

    pub fn is_empty(&self) -> bool {
        self.length == 0
    }

    pub fn data_type(&self) -> &DataType {
        self.chunks[0].data_type()
    }

    pub fn null_count(&self) -> usize {
        self.null_count
    }

    pub(super) fn dictionary_values(&self) -> Option<ArrayRef> {
        self.dictionary.clone()
    }

    fn check_range(&self, offset: usize, length: usize) -> Result<(), ArrowProfileError> {
        if length > ARROW_ROWS_PER_BATCH
            || offset
                .checked_add(length)
                .is_none_or(|end| end > self.length)
        {
            return Err(ArrowProfileError::Invalid(
                "Arrow write source range exceeds its canonical row window".to_owned(),
            ));
        }
        Ok(())
    }

    fn ranges(
        &self,
        offset: usize,
        length: usize,
    ) -> impl Iterator<Item = (usize, usize, usize)> + '_ {
        let first = self.ends.partition_point(|&end| end <= offset);
        let end = offset + length;
        (first..self.chunks.len())
            .map_while(move |index| {
                let start = if index == 0 { 0 } else { self.ends[index - 1] };
                if start >= end {
                    return None;
                }
                let selected_start = offset.max(start);
                Some((
                    index,
                    selected_start - start,
                    self.ends[index].min(end) - selected_start,
                ))
            })
            .filter(|&(_, _, length)| length != 0)
    }

    pub(super) fn has_nulls(
        &self,
        offset: usize,
        length: usize,
    ) -> Result<bool, ArrowProfileError> {
        self.check_range(offset, length)?;
        Ok(self.ranges(offset, length).any(|(index, start, length)| {
            self.chunks[index]
                .nulls()
                .is_some_and(|nulls| nulls.slice(start, length).null_count() != 0)
        }))
    }

    pub(super) fn slice(
        &self,
        offset: usize,
        length: usize,
    ) -> Result<ArrayRef, ArrowProfileError> {
        self.check_range(offset, length)?;
        if length == 0 {
            return align_bitmaps(self.chunks[0].slice(0, 0));
        }
        let mut ranges = self.ranges(offset, length);
        let (index, start, count) = ranges.next().expect("checked nonempty source range");
        if count == length {
            return align_bitmaps(self.chunks[index].slice(start, count));
        }
        let mut slices = vec![self.chunks[index].slice(start, count)];
        slices.extend(ranges.map(|(index, start, count)| self.chunks[index].slice(start, count)));
        if let Some(values) = &self.dictionary {
            // General dictionary concatenation may recode or discard levels.
            // Identical checked dictionaries let us concatenate keys verbatim.
            let keys: Vec<&dyn Array> = slices
                .iter()
                .map(|slice| {
                    slice
                        .as_any()
                        .downcast_ref::<DictionaryArray<Int32Type>>()
                        .map(|array| array.keys() as &dyn Array)
                        .ok_or_else(|| {
                            ArrowProfileError::Invalid(
                                "Arrow write source requires Int32 dictionary keys".to_owned(),
                            )
                        })
                })
                .collect::<Result<_, _>>()?;
            let keys = arrow_select::concat::concat(&keys)
                .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
            let keys = keys
                .as_any()
                .downcast_ref::<Int32Array>()
                .expect("Int32 key concatenation");
            let array = DictionaryArray::<Int32Type>::try_new(keys.clone(), values.clone())
                .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
            return Ok(Arc::new(array));
        }
        arrow_select::concat::concat(
            &slices
                .iter()
                .map(|slice| slice.as_ref())
                .collect::<Vec<_>>(),
        )
        .map_err(|error| ArrowProfileError::Invalid(error.to_string()))
    }
}

fn align_bitmaps(array: ArrayRef) -> Result<ArrayRef, ArrowProfileError> {
    let data = array.to_data();
    let nulls_unaligned = data
        .nulls()
        .is_some_and(|nulls| !nulls.offset().is_multiple_of(8));
    let values_unaligned =
        data.data_type() == &DataType::Boolean && !data.offset().is_multiple_of(8);
    if !nulls_unaligned && !values_unaligned {
        return Ok(array);
    }
    let nulls = data.nulls().map(|nulls| {
        if nulls_unaligned {
            NullBuffer::new(BooleanBuffer::new(nulls.inner().sliced(), 0, data.len()))
        } else {
            nulls.clone()
        }
    });
    if data.data_type() == &DataType::Boolean {
        let values = BooleanBuffer::new(
            data.buffers()[0].bit_slice(data.offset(), data.len()),
            0,
            data.len(),
        );
        return Ok(Arc::new(BooleanArray::new(values, nulls)));
    }
    let aligned = data
        .into_builder()
        .nulls(nulls)
        .build()
        .map_err(|error| ArrowProfileError::Invalid(error.to_string()))?;
    Ok(arrow_array::make_array(aligned))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn windows_share_values_and_only_crossing_windows_coalesce() {
        let original: ArrayRef = Arc::new(Int32Array::from_iter_values(0..200_000));
        let original_values = original.as_any().downcast_ref::<Int32Array>().unwrap();
        let source =
            ArrowWriteSource::try_new(vec![original.slice(0, 17), original.slice(17, 199_983)])
                .unwrap();
        let inside = source.slice(18, 20).unwrap();
        let inside = inside.as_any().downcast_ref::<Int32Array>().unwrap();
        assert_eq!(
            inside.values().as_ptr(),
            original_values.values()[18..].as_ptr()
        );
        let crossing = source.slice(0, ARROW_ROWS_PER_BATCH).unwrap();
        let crossing = crossing.as_any().downcast_ref::<Int32Array>().unwrap();
        assert_eq!(
            crossing.values().as_ref(),
            &original_values.values()[..ARROW_ROWS_PER_BATCH]
        );
        assert_ne!(
            crossing.values().as_ptr(),
            original_values.values().as_ptr()
        );
        assert!(crossing.to_data().get_buffer_memory_size() <= ARROW_ROWS_PER_BATCH * 4 + 64);
        assert!(source.slice(0, ARROW_ROWS_PER_BATCH + 1).is_err());
        assert!(source.slice(200_000, 1).is_err());
        assert!(source.slice(usize::MAX, 2).is_err());
        drop(source);
        drop(original);
        assert_eq!(inside.value(0), 18);
    }

    #[test]
    fn source_rejects_missing_types_mixed_types_and_dictionary_changes() {
        assert!(ArrowWriteSource::try_new(Vec::new()).is_err());
        assert!(ArrowWriteSource::try_new(vec![
            Arc::new(Int32Array::from(vec![1])),
            Arc::new(arrow_array::Int16Array::from(vec![1])),
        ])
        .is_err());
        let dictionary = |value: &str| -> ArrayRef {
            Arc::new(
                DictionaryArray::<Int32Type>::try_new(
                    Int32Array::from(vec![0]),
                    Arc::new(arrow_array::StringArray::from(vec![value])),
                )
                .unwrap(),
            )
        };
        assert!(ArrowWriteSource::try_new(vec![dictionary("a"), dictionary("b")]).is_err());
        let empty =
            ArrowWriteSource::try_new(vec![Arc::new(Int32Array::from(Vec::<i32>::new()))]).unwrap();
        assert!(empty.is_empty());
        assert_eq!(empty.data_type(), &DataType::Int32);
        assert_eq!(empty.slice(0, 0).unwrap().len(), 0);
    }
}
