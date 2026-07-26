use std::collections::HashMap;

use crate::endian::{
    checked_add, checked_sub, expect_at, offset_to_usize, read_u16, read_u32, read_u64, slice_at,
};
use crate::text::TextEncoding;
use crate::{Column, ColumnValues, DtaError, DtaMetadata, DtaType, FormatVersion, VariableInfo};

const STRLS_OPEN: &[u8] = b"<strls>";
const STRLS_CLOSE: &[u8] = b"</strls>";
const GSO_MARKER: &[u8] = b"GSO";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct GsoKey {
    variable: u32,
    observation: u64,
}

#[derive(Debug, Clone, Copy)]
struct GsoEntry {
    content_offset: usize,
    content_length: usize,
    gso_type: u8,
}

fn checked_add_u64(left: u64, right: u64, context: &'static str) -> Result<u64, DtaError> {
    left.checked_add(right)
        .ok_or(DtaError::ArithmeticOverflow(context))
}

fn checked_mul_u64(left: u64, right: u64, context: &'static str) -> Result<u64, DtaError> {
    left.checked_mul(right)
        .ok_or(DtaError::ArithmeticOverflow(context))
}

fn read_u48(bytes: &[u8], offset: usize, metadata: &DtaMetadata) -> Result<u64, DtaError> {
    let field = slice_at(bytes, offset, 6, "strL observation pointer")?;
    let mut value = 0_u64;
    match metadata.byte_order {
        crate::ByteOrder::Lsf => {
            for (shift, byte) in field.iter().enumerate() {
                value |= u64::from(*byte) << (shift * 8);
            }
        }
        crate::ByteOrder::Msf => {
            for byte in field {
                value = (value << 8) | u64::from(*byte);
            }
        }
    }
    Ok(value)
}

fn read_pointer(
    bytes: &[u8],
    offset: usize,
    metadata: &DtaMetadata,
) -> Result<Option<GsoKey>, DtaError> {
    let (variable, observation) = if metadata.format_version == FormatVersion::V117 {
        (
            read_u32(bytes, offset, metadata.byte_order, "strL variable pointer")?,
            u64::from(read_u32(
                bytes,
                checked_add(offset, 4, "strL observation pointer")?,
                metadata.byte_order,
                "strL observation pointer",
            )?),
        )
    } else {
        (
            u32::from(read_u16(
                bytes,
                offset,
                metadata.byte_order,
                "strL variable pointer",
            )?),
            read_u48(
                bytes,
                checked_add(offset, 2, "strL observation pointer")?,
                metadata,
            )?,
        )
    };
    if variable == 0 && observation == 0 {
        return Ok(None);
    }
    let key = GsoKey {
        variable,
        observation,
    };
    validate_key(metadata, key, offset, true)?;
    Ok(Some(key))
}

fn validate_key(
    metadata: &DtaMetadata,
    key: GsoKey,
    offset: usize,
    pointer: bool,
) -> Result<(), DtaError> {
    let valid_variable = key
        .variable
        .checked_sub(1)
        .and_then(|index| usize::try_from(index).ok())
        .and_then(|index| metadata.variables.get(index))
        .is_some_and(|variable| variable.dta_type == DtaType::StrL);
    let valid_observation = key.observation >= 1 && key.observation <= metadata.nobs;
    if key.variable == 0 || key.observation == 0 || !valid_variable || !valid_observation {
        return if pointer {
            Err(DtaError::InvalidStrlPointer {
                variable: key.variable,
                observation: key.observation,
                offset,
            })
        } else {
            Err(DtaError::InvalidGsoKey {
                variable: key.variable,
                observation: key.observation,
                offset,
            })
        };
    }
    Ok(())
}

fn strls_bounds(bytes: &[u8], metadata: &DtaMetadata) -> Result<(usize, usize), DtaError> {
    let start = offset_to_usize(metadata.section_offsets.strls, "strls")?;
    let payload_start = expect_at(bytes, start, STRLS_OPEN, "<strls>")?;
    let value_labels = offset_to_usize(metadata.section_offsets.value_labels, "value_labels")?;
    let close = checked_sub(value_labels, STRLS_CLOSE.len(), "strls closing-tag offset")?;
    if close < payload_start {
        return Err(DtaError::SectionOrder {
            section: "value_labels",
            previous_offset: payload_start as u64,
            offset: metadata.section_offsets.value_labels,
        });
    }
    expect_at(bytes, close, STRLS_CLOSE, "</strls>")?;
    Ok((payload_start, close))
}

fn build_index(
    bytes: &[u8],
    metadata: &DtaMetadata,
) -> Result<HashMap<GsoKey, GsoEntry>, DtaError> {
    let (mut cursor, end) = strls_bounds(bytes, metadata)?;
    let mut index = HashMap::new();
    while cursor < end {
        if slice_at(bytes, cursor, GSO_MARKER.len(), "GSO marker")? != GSO_MARKER {
            return Err(DtaError::InvalidGsoMarker { offset: cursor });
        }
        let record_offset = cursor;
        cursor = checked_add(cursor, GSO_MARKER.len(), "GSO marker")?;
        let variable = read_u32(bytes, cursor, metadata.byte_order, "GSO variable")?;
        cursor = checked_add(cursor, 4, "GSO variable")?;
        let observation = if metadata.format_version == FormatVersion::V117 {
            let value = u64::from(read_u32(
                bytes,
                cursor,
                metadata.byte_order,
                "GSO observation",
            )?);
            cursor = checked_add(cursor, 4, "GSO observation")?;
            value
        } else {
            let value = read_u64(bytes, cursor, metadata.byte_order, "GSO observation")?;
            cursor = checked_add(cursor, 8, "GSO observation")?;
            value
        };
        let gso_type = slice_at(bytes, cursor, 1, "GSO type")?[0];
        if !matches!(gso_type, 129 | 130) {
            return Err(DtaError::InvalidGsoType {
                gso_type,
                offset: cursor,
            });
        }
        cursor = checked_add(cursor, 1, "GSO type")?;
        let content_length_u32 =
            read_u32(bytes, cursor, metadata.byte_order, "GSO content length")?;
        cursor = checked_add(cursor, 4, "GSO content length")?;
        let content_length = usize::try_from(content_length_u32)
            .map_err(|_| DtaError::ArithmeticOverflow("GSO content length"))?;
        let content_offset = cursor;
        let content = slice_at(bytes, content_offset, content_length, "GSO content")?;
        cursor = checked_add(cursor, content_length, "GSO content")?;
        if cursor > end {
            return Err(DtaError::Truncated {
                context: "GSO content",
                offset: content_offset,
                needed: content_length,
                available: end.saturating_sub(content_offset),
            });
        }
        if gso_type == 130 && (content.is_empty() || content.last() != Some(&0)) {
            return Err(DtaError::InvalidGsoText {
                offset: content_offset,
            });
        }
        let key = GsoKey {
            variable,
            observation,
        };
        validate_key(metadata, key, record_offset, false)?;
        let entry = GsoEntry {
            content_offset,
            content_length,
            gso_type,
        };
        if index.insert(key, entry).is_some() {
            return Err(DtaError::DuplicateGsoKey {
                variable,
                observation,
                offset: record_offset,
            });
        }
    }
    Ok(index)
}

fn collect_pointers(
    bytes: &[u8],
    metadata: &DtaMetadata,
    payload_start: usize,
    row_start: u64,
    row_count: u64,
    variable: &VariableInfo,
) -> Result<Vec<Option<GsoKey>>, DtaError> {
    let capacity = usize::try_from(row_count)
        .map_err(|_| DtaError::ArithmeticOverflow("projected row count"))?;
    let mut pointers = Vec::with_capacity(capacity);
    let payload = u64::try_from(payload_start)
        .map_err(|_| DtaError::ArithmeticOverflow("data payload offset"))?;
    let first_row = checked_mul_u64(row_start, metadata.obs_length, "row start offset")?;
    let first = checked_add_u64(
        checked_add_u64(payload, first_row, "row start offset")?,
        variable.byte_offset,
        "strL pointer offset",
    )?;
    for row in 0..row_count {
        let row_offset = checked_mul_u64(row, metadata.obs_length, "row offset")?;
        let offset = checked_add_u64(first, row_offset, "strL pointer offset")?;
        let offset = offset_to_usize(offset, "strL pointer")?;
        pointers.push(read_pointer(bytes, offset, metadata)?);
    }
    Ok(pointers)
}

pub(crate) fn decode_strl_columns(
    bytes: &[u8],
    metadata: &DtaMetadata,
    payload_start: usize,
    row_start: u64,
    row_count: u64,
    variable_indices: &[u32],
    encoding: TextEncoding,
) -> Result<Vec<Column>, DtaError> {
    if variable_indices.is_empty() {
        return Ok(Vec::new());
    }
    let mut pointer_columns = Vec::with_capacity(variable_indices.len());
    for &variable_index in variable_indices {
        let index = usize::try_from(variable_index)
            .map_err(|_| DtaError::ArithmeticOverflow("column index"))?;
        let variable = &metadata.variables[index];
        pointer_columns.push(collect_pointers(
            bytes,
            metadata,
            payload_start,
            row_start,
            row_count,
            variable,
        )?);
    }

    let index = build_index(bytes, metadata)?;
    let mut decoded = HashMap::<GsoKey, String>::new();
    let mut columns = Vec::with_capacity(variable_indices.len());
    for (&variable_index, pointers) in variable_indices.iter().zip(pointer_columns) {
        let mut values = Vec::with_capacity(pointers.len());
        for pointer in pointers {
            let Some(key) = pointer else {
                values.push(String::new());
                continue;
            };
            if let Some(value) = decoded.get(&key) {
                values.push(value.clone());
                continue;
            }
            let entry = index.get(&key).ok_or(DtaError::DanglingStrlPointer {
                variable: key.variable,
                observation: key.observation,
            })?;
            let content = slice_at(
                bytes,
                entry.content_offset,
                entry.content_length,
                "GSO content",
            )?;
            let string_bytes = if entry.gso_type == 130 {
                &content[..content.len() - 1]
            } else {
                content
            };
            let value = encoding.decode(string_bytes);
            decoded.insert(key, value.clone());
            values.push(value);
        }
        columns.push(Column {
            variable_index,
            values: ColumnValues::StrL { values },
        });
    }
    Ok(columns)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ByteOrder, SectionOffsets};

    fn metadata(version: FormatVersion, byte_order: ByteOrder, nobs: u64) -> DtaMetadata {
        DtaMetadata {
            format_version: version,
            byte_order,
            nvar: 1,
            nobs,
            dataset_label: String::new(),
            variables: vec![VariableInfo {
                name: "long".into(),
                dta_type: DtaType::StrL,
                type_code: 32768,
                format: "%9s".into(),
                label: String::new(),
                value_label_name: String::new(),
                byte_width: 8,
                byte_offset: 0,
            }],
            section_offsets: SectionOffsets {
                stata_data: 0,
                map: 1,
                variable_types: 2,
                varnames: 3,
                sortlist: 4,
                formats: 5,
                value_label_names: 6,
                variable_labels: 7,
                characteristics: 8,
                data: 9,
                strls: 0,
                value_labels: 0,
                stata_data_close: 0,
                end_of_file: 0,
            },
            obs_length: 8,
        }
    }

    #[test]
    fn reads_all_six_observation_bytes_in_both_orders() {
        let observation = 0x0102_0304_0506_u64;
        let mut little = [0_u8; 8];
        little[..2].copy_from_slice(&1_u16.to_le_bytes());
        little[2..].copy_from_slice(&[0x06, 0x05, 0x04, 0x03, 0x02, 0x01]);
        let little_metadata = metadata(FormatVersion::V118, ByteOrder::Lsf, observation);
        assert_eq!(
            read_pointer(&little, 0, &little_metadata).unwrap(),
            Some(GsoKey {
                variable: 1,
                observation
            })
        );

        let mut big = [0_u8; 8];
        big[..2].copy_from_slice(&1_u16.to_be_bytes());
        big[2..].copy_from_slice(&[0x01, 0x02, 0x03, 0x04, 0x05, 0x06]);
        let big_metadata = metadata(FormatVersion::V119, ByteOrder::Msf, observation);
        assert_eq!(
            read_pointer(&big, 0, &big_metadata).unwrap(),
            Some(GsoKey {
                variable: 1,
                observation
            })
        );
    }

    #[test]
    fn indexes_big_endian_v119_u64_gso_observations() {
        let observation = 0x0000_0001_0000_0001_u64;
        let mut bytes = Vec::from(STRLS_OPEN);
        bytes.extend_from_slice(GSO_MARKER);
        bytes.extend_from_slice(&1_u32.to_be_bytes());
        bytes.extend_from_slice(&observation.to_be_bytes());
        bytes.push(129);
        bytes.extend_from_slice(&0_u32.to_be_bytes());
        bytes.extend_from_slice(STRLS_CLOSE);
        let mut metadata = metadata(FormatVersion::V119, ByteOrder::Msf, observation);
        metadata.section_offsets.value_labels = bytes.len() as u64;
        let index = build_index(&bytes, &metadata).unwrap();
        assert!(index.contains_key(&GsoKey {
            variable: 1,
            observation
        }));
    }
}
