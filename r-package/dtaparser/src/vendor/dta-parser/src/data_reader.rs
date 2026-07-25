use std::collections::{HashMap, HashSet};

use crate::endian::{
    checked_add, checked_sub, ensure_map_offset, expect_at, offset_to_usize, read_i16, read_i32,
    read_i8, read_u32, read_u64, slice_at,
};
use crate::strl::decode_strl_columns;
use crate::text::{decode_utf8, decode_windows_1252, field_bytes};
use crate::{
    classify_byte_missing, classify_double_missing_bits, classify_float_missing_bits,
    classify_int_missing, classify_long_missing, parse_metadata, parse_value_labels, Column,
    ColumnValues, DtaData, DtaError, DtaMetadata, DtaType, ReadOptions, VariableInfo,
};

const DATA_OPEN: &[u8] = b"<data>";
const DATA_CLOSE: &[u8] = b"</data>";
const STRLS_OPEN: &[u8] = b"<strls>";
const STRLS_CLOSE: &[u8] = b"</strls>";

fn checked_add_u64(left: u64, right: u64, context: &'static str) -> Result<u64, DtaError> {
    left.checked_add(right)
        .ok_or(DtaError::ArithmeticOverflow(context))
}

fn checked_mul_u64(left: u64, right: u64, context: &'static str) -> Result<u64, DtaError> {
    left.checked_mul(right)
        .ok_or(DtaError::ArithmeticOverflow(context))
}

fn validate_data_section(bytes: &[u8], metadata: &DtaMetadata) -> Result<usize, DtaError> {
    let data_offset = offset_to_usize(metadata.section_offsets.data, "data")?;
    if !metadata.format_version.is_modern() {
        let payload_length = checked_mul_u64(
            metadata.nobs,
            metadata.obs_length,
            "legacy observation data length",
        )?;
        let payload_length = offset_to_usize(payload_length, "legacy observation data length")?;
        slice_at(
            bytes,
            data_offset,
            payload_length,
            "legacy observation data",
        )?;
        let after_data = checked_add(data_offset, payload_length, "legacy observation data")?;
        ensure_map_offset(
            "value_labels",
            after_data,
            metadata.section_offsets.value_labels,
        )?;
        return Ok(data_offset);
    }
    let payload_start = expect_at(bytes, data_offset, DATA_OPEN, "<data>")?;
    let payload_length = checked_mul_u64(
        metadata.nobs,
        metadata.obs_length,
        "observation data length",
    )?;
    let payload_length = offset_to_usize(payload_length, "observation data length")?;
    slice_at(bytes, payload_start, payload_length, "observation data")?;
    let close_offset = checked_add(payload_start, payload_length, "observation data end")?;
    let after_close = expect_at(bytes, close_offset, DATA_CLOSE, "</data>")?;
    ensure_map_offset("strls", after_close, metadata.section_offsets.strls)?;

    let after_strls_open = expect_at(bytes, after_close, STRLS_OPEN, "<strls>")?;
    let value_labels_offset =
        offset_to_usize(metadata.section_offsets.value_labels, "value_labels")?;
    let strls_close_offset = checked_sub(
        value_labels_offset,
        STRLS_CLOSE.len(),
        "strls closing-tag offset",
    )?;
    if strls_close_offset < after_strls_open {
        return Err(DtaError::SectionOrder {
            section: "value_labels",
            previous_offset: u64::try_from(after_strls_open)
                .map_err(|_| DtaError::ArithmeticOverflow("strls payload start"))?,
            offset: metadata.section_offsets.value_labels,
        });
    }
    let after_strls_close = expect_at(bytes, strls_close_offset, STRLS_CLOSE, "</strls>")?;
    ensure_map_offset(
        "value_labels",
        after_strls_close,
        metadata.section_offsets.value_labels,
    )?;
    Ok(payload_start)
}

fn resolve_columns(metadata: &DtaMetadata, options: &ReadOptions) -> Result<Vec<u32>, DtaError> {
    let requested = match &options.column_indices {
        Some(indices) => indices.clone(),
        None => (0..metadata.nvar).collect(),
    };
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

fn row_window(metadata: &DtaMetadata, options: &ReadOptions) -> (u64, u64) {
    let row_start = options.row_start.min(metadata.nobs);
    let available = metadata.nobs - row_start;
    let row_count = options.row_count.unwrap_or(available).min(available);
    (row_start, row_count)
}

fn first_cell_offset(
    payload_start: usize,
    metadata: &DtaMetadata,
    row_start: u64,
    variable: &VariableInfo,
) -> Result<u64, DtaError> {
    let payload_start = u64::try_from(payload_start)
        .map_err(|_| DtaError::ArithmeticOverflow("data payload offset"))?;
    let rows_offset = checked_mul_u64(row_start, metadata.obs_length, "row start offset")?;
    checked_add_u64(
        checked_add_u64(payload_start, rows_offset, "row start offset")?,
        variable.byte_offset,
        "column start offset",
    )
}

fn decode_column(
    bytes: &[u8],
    metadata: &DtaMetadata,
    payload_start: usize,
    row_start: u64,
    row_count: u64,
    variable_index: u32,
) -> Result<Column, DtaError> {
    let index = usize::try_from(variable_index)
        .map_err(|_| DtaError::ArithmeticOverflow("column index"))?;
    let variable = &metadata.variables[index];
    let capacity = usize::try_from(row_count)
        .map_err(|_| DtaError::ArithmeticOverflow("projected row count"))?;
    let first_offset = first_cell_offset(payload_start, metadata, row_start, variable)?;

    macro_rules! decode_numeric {
        ($variant:ident, $value_type:ty, $read:expr, $classify:expr) => {{
            let mut values: Vec<$value_type> = Vec::with_capacity(capacity);
            let mut missing_tags = Vec::with_capacity(capacity);
            for row in 0..row_count {
                let row_offset = checked_mul_u64(row, metadata.obs_length, "row offset")?;
                let cell_offset = checked_add_u64(first_offset, row_offset, "cell offset")?;
                let cell_offset = offset_to_usize(cell_offset, "cell")?;
                let value: $value_type = $read(cell_offset)?;
                missing_tags.push($classify(value));
                values.push(value);
            }
            ColumnValues::$variant {
                values,
                missing_tags,
            }
        }};
    }

    let values = match variable.dta_type {
        DtaType::Byte => decode_numeric!(
            Byte,
            i8,
            |offset| read_i8(bytes, offset, "byte observation"),
            classify_byte_missing
        ),
        DtaType::Int => decode_numeric!(
            Int,
            i16,
            |offset| read_i16(bytes, offset, metadata.byte_order, "int observation"),
            classify_int_missing
        ),
        DtaType::Long => decode_numeric!(
            Long,
            i32,
            |offset| read_i32(bytes, offset, metadata.byte_order, "long observation"),
            classify_long_missing
        ),
        DtaType::Float => {
            let mut values = Vec::with_capacity(capacity);
            let mut missing_tags = Vec::with_capacity(capacity);
            for row in 0..row_count {
                let row_offset = checked_mul_u64(row, metadata.obs_length, "row offset")?;
                let cell_offset = checked_add_u64(first_offset, row_offset, "cell offset")?;
                let cell_offset = offset_to_usize(cell_offset, "cell")?;
                let bits = read_u32(bytes, cell_offset, metadata.byte_order, "float observation")?;
                missing_tags.push(classify_float_missing_bits(bits));
                values.push(f32::from_bits(bits));
            }
            ColumnValues::Float {
                values,
                missing_tags,
            }
        }
        DtaType::Double => {
            let mut values = Vec::with_capacity(capacity);
            let mut missing_tags = Vec::with_capacity(capacity);
            for row in 0..row_count {
                let row_offset = checked_mul_u64(row, metadata.obs_length, "row offset")?;
                let cell_offset = checked_add_u64(first_offset, row_offset, "cell offset")?;
                let cell_offset = offset_to_usize(cell_offset, "cell")?;
                let bits = read_u64(
                    bytes,
                    cell_offset,
                    metadata.byte_order,
                    "double observation",
                )?;
                missing_tags.push(classify_double_missing_bits(bits));
                values.push(f64::from_bits(bits));
            }
            ColumnValues::Double {
                values,
                missing_tags,
            }
        }
        DtaType::FixedString(width) => {
            let width = usize::from(width);
            let mut values = Vec::with_capacity(capacity);
            for row in 0..row_count {
                let row_offset = checked_mul_u64(row, metadata.obs_length, "row offset")?;
                let cell_offset = checked_add_u64(first_offset, row_offset, "cell offset")?;
                let cell_offset = offset_to_usize(cell_offset, "cell")?;
                let field = slice_at(bytes, cell_offset, width, "fixed-string observation")?;
                let value = if metadata.format_version.is_modern() {
                    decode_utf8(field_bytes(field))
                } else {
                    decode_windows_1252(field_bytes(field))
                };
                values.push(value);
            }
            ColumnValues::FixedString { values }
        }
        DtaType::StrL => {
            return Err(DtaError::UnsupportedColumnType {
                index: variable_index,
                dta_type: DtaType::StrL,
            })
        }
    };
    Ok(Column {
        variable_index,
        values,
    })
}

/// Parse and decode all observations and variables in a supported Stata file.
pub fn read_dta(bytes: &[u8]) -> Result<DtaData, DtaError> {
    read_dta_with_options(bytes, &ReadOptions::default())
}

/// Parse a supported Stata file into a column-oriented, projected result.
pub fn read_dta_with_options(bytes: &[u8], options: &ReadOptions) -> Result<DtaData, DtaError> {
    let metadata = parse_metadata(bytes)?;
    let payload_start = validate_data_section(bytes, &metadata)?;
    let column_indices = resolve_columns(&metadata, options)?;
    let value_label_tables = parse_value_labels(bytes, &metadata)?;
    let (row_start, row_count) = row_window(&metadata, options);
    let mut strl_indices = Vec::new();
    for &index in &column_indices {
        let variable_index =
            usize::try_from(index).map_err(|_| DtaError::ArithmeticOverflow("column index"))?;
        if metadata.variables[variable_index].dta_type == DtaType::StrL {
            strl_indices.push(index);
        }
    }
    let mut strl_columns = decode_strl_columns(
        bytes,
        &metadata,
        payload_start,
        row_start,
        row_count,
        &strl_indices,
    )?
    .into_iter()
    .map(|column| (column.variable_index, column))
    .collect::<HashMap<_, _>>();

    let mut columns = Vec::with_capacity(column_indices.len());
    for variable_index in column_indices {
        if let Some(column) = strl_columns.remove(&variable_index) {
            columns.push(column);
        } else {
            columns.push(decode_column(
                bytes,
                &metadata,
                payload_start,
                row_start,
                row_count,
                variable_index,
            )?);
        }
    }
    Ok(DtaData {
        metadata,
        row_start,
        row_count,
        columns,
        value_label_tables,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn row_windows_are_clamped_without_underflow() {
        let mut metadata: DtaMetadata = serde_json::from_value(serde_json::json!({
            "format_version": 118,
            "byte_order": "LSF",
            "nvar": 0,
            "nobs": "10",
            "dataset_label": "",
            "variables": [],
            "section_offsets": {
                "stata_data": "0", "map": "1", "variable_types": "2", "varnames": "3",
                "sortlist": "4", "formats": "5", "value_label_names": "6",
                "variable_labels": "7", "characteristics": "8", "data": "9",
                "strls": "10", "value_labels": "11", "stata_data_close": "12",
                "end_of_file": "13"
            },
            "obs_length": "0"
        }))
        .unwrap();
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

    #[test]
    fn rejects_a_value_labels_offset_too_small_for_the_strls_close() {
        let metadata: DtaMetadata = serde_json::from_value(serde_json::json!({
            "format_version": 118,
            "byte_order": "LSF",
            "nvar": 0,
            "nobs": "0",
            "dataset_label": "",
            "variables": [],
            "section_offsets": {
                "stata_data": "0", "map": "1", "variable_types": "2", "varnames": "3",
                "sortlist": "4", "formats": "5", "value_label_names": "6",
                "variable_labels": "7", "characteristics": "8", "data": "0",
                "strls": "13", "value_labels": "3", "stata_data_close": "30",
                "end_of_file": "42"
            },
            "obs_length": "0"
        }))
        .unwrap();
        let bytes = b"<data></data><strls></strls>";
        assert_eq!(
            validate_data_section(bytes, &metadata),
            Err(DtaError::ArithmeticOverflow("strls closing-tag offset"))
        );
    }
}
