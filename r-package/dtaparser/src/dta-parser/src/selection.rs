use std::collections::HashSet;

use crate::{DtaError, DtaMetadata, ReadOptions};

pub(crate) fn resolve_columns(
    metadata: &DtaMetadata,
    options: &ReadOptions,
) -> Result<Vec<u32>, DtaError> {
    let requested = options
        .column_indices
        .clone()
        .unwrap_or_else(|| (0..metadata.nvar).collect());
    let mut seen = HashSet::with_capacity(requested.len());
    let mut resolved = Vec::with_capacity(requested.len());
    for index in requested {
        if index >= metadata.nvar {
            return Err(DtaError::InvalidColumnIndex {
                index,
                nvar: metadata.nvar,
            });
        }
        if seen.insert(index) {
            resolved.push(index);
        }
    }
    Ok(resolved)
}

pub(crate) fn row_window(metadata: &DtaMetadata, options: &ReadOptions) -> (u64, u64) {
    let row_start = options.row_start.min(metadata.nobs);
    let available = metadata.nobs - row_start;
    let row_count = options.row_count.unwrap_or(available).min(available);
    (row_start, row_count)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ByteOrder, FormatVersion, SectionOffsets};

    fn metadata(nvar: u32, nobs: u64) -> DtaMetadata {
        DtaMetadata {
            format_version: FormatVersion::V118,
            byte_order: ByteOrder::Lsf,
            nvar,
            nobs,
            dataset_label: String::new(),
            notes: Vec::new(),
            variables: Vec::new(),
            section_offsets: SectionOffsets::from_array([0; 14]),
            obs_length: 0,
        }
    }

    #[test]
    fn columns_preserve_request_order_deduplicate_and_reject_invalid_indices() {
        let metadata = metadata(4, 0);
        let options = ReadOptions {
            row_start: 0,
            row_count: None,
            column_indices: Some(vec![3, 1, 3, 0, 1]),
        };
        assert_eq!(resolve_columns(&metadata, &options).unwrap(), vec![3, 1, 0]);

        let invalid = ReadOptions {
            column_indices: Some(vec![1, 4]),
            ..ReadOptions::default()
        };
        assert_eq!(
            resolve_columns(&metadata, &invalid),
            Err(DtaError::InvalidColumnIndex { index: 4, nvar: 4 })
        );
        assert_eq!(
            resolve_columns(&metadata, &ReadOptions::default()).unwrap(),
            vec![0, 1, 2, 3]
        );
    }

    #[test]
    fn row_windows_clamp_without_underflow() {
        let mut metadata = metadata(0, 10);
        assert_eq!(row_window(&metadata, &ReadOptions::default()), (0, 10));
        assert_eq!(
            row_window(
                &metadata,
                &ReadOptions {
                    row_start: 8,
                    row_count: Some(9),
                    column_indices: None,
                }
            ),
            (8, 2)
        );
        metadata.nobs = 0;
        assert_eq!(
            row_window(
                &metadata,
                &ReadOptions {
                    row_start: u64::MAX,
                    row_count: None,
                    column_indices: None,
                }
            ),
            (0, 0)
        );
    }
}
