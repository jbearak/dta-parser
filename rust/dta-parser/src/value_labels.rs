use crate::endian::{checked_add, checked_mul, read_i32, slice_at};
use crate::{
    classify_long_missing, DtaError, DtaMetadata, FormatVersion, ValueLabelEntry, ValueLabelTable,
};

const VALUE_LABELS_OPEN: &[u8] = b"<value_labels>";
const VALUE_LABELS_CLOSE: &[u8] = b"</value_labels>";
const LABEL_OPEN: &[u8] = b"<lbl>";
const LABEL_CLOSE: &[u8] = b"</lbl>";
const STATA_DATA_CLOSE: &[u8] = b"</stata_dta>";
const RESERVED_WIDTH: usize = 3;

fn offset_to_usize(offset: u64, context: &'static str) -> Result<usize, DtaError> {
    usize::try_from(offset).map_err(|_| DtaError::OffsetOutOfRange { context, offset })
}

fn expect_at(
    bytes: &[u8],
    offset: usize,
    tag: &'static [u8],
    expected: &'static str,
) -> Result<usize, DtaError> {
    if slice_at(bytes, offset, tag.len(), expected)? != tag {
        return Err(DtaError::UnexpectedTag { expected, offset });
    }
    checked_add(offset, tag.len(), expected)
}

fn ensure_map_offset(section: &'static str, expected: usize, actual: u64) -> Result<(), DtaError> {
    let expected = u64::try_from(expected).map_err(|_| DtaError::OffsetOutOfRange {
        context: section,
        offset: u64::MAX,
    })?;
    if expected != actual {
        return Err(DtaError::MapOffsetMismatch {
            section,
            expected,
            actual,
        });
    }
    Ok(())
}

fn name_width(version: FormatVersion) -> Result<usize, DtaError> {
    match version {
        FormatVersion::V117 => Ok(33),
        FormatVersion::V118 | FormatVersion::V119 => Ok(129),
        legacy => Err(DtaError::UnsupportedRelease(legacy)),
    }
}

fn parse_table(
    bytes: &[u8],
    metadata: &DtaMetadata,
    table_start: usize,
    name_width: usize,
) -> Result<(ValueLabelTable, usize), DtaError> {
    let mut cursor = expect_at(bytes, table_start, LABEL_OPEN, "<lbl>")?;
    let length_offset = cursor;
    let declared_i32 = read_i32(
        bytes,
        cursor,
        metadata.byte_order,
        "value-label table length",
    )?;
    if declared_i32 < 0 {
        return Err(DtaError::NegativeValueLabelField {
            field: "table length",
            value: declared_i32,
            offset: length_offset,
        });
    }
    let declared = usize::try_from(declared_i32)
        .map_err(|_| DtaError::ArithmeticOverflow("value-label table length"))?;
    cursor = checked_add(cursor, 4, "value-label table length")?;

    let name_start = cursor;
    let name_field = slice_at(bytes, name_start, name_width, "value-label table name")?;
    let name_end =
        name_field
            .iter()
            .position(|byte| *byte == 0)
            .ok_or(DtaError::MissingNulTerminator {
                context: "value-label table name",
                offset: name_start,
            })?;
    let name = String::from_utf8_lossy(&name_field[..name_end]).into_owned();
    cursor = checked_add(cursor, name_width, "value-label table name")?;

    // The format reserves these bytes but does not assign them semantics.
    slice_at(bytes, cursor, RESERVED_WIDTH, "value-label reserved bytes")?;
    cursor = checked_add(cursor, RESERVED_WIDTH, "value-label reserved bytes")?;

    let payload_start = cursor;
    let payload = slice_at(bytes, payload_start, declared, "value-label table payload")?;
    if declared < 8 {
        return Err(DtaError::InvalidValueLabelLength {
            offset: table_start,
            declared,
            expected: 8,
        });
    }

    let entry_count_i32 = read_i32(payload, 0, metadata.byte_order, "value-label entry count")?;
    if entry_count_i32 < 0 {
        return Err(DtaError::NegativeValueLabelField {
            field: "entry count",
            value: entry_count_i32,
            offset: payload_start,
        });
    }
    let text_length_i32 = read_i32(payload, 4, metadata.byte_order, "value-label text length")?;
    if text_length_i32 < 0 {
        return Err(DtaError::NegativeValueLabelField {
            field: "text length",
            value: text_length_i32,
            offset: checked_add(payload_start, 4, "value-label text length")?,
        });
    }

    let entry_count = usize::try_from(entry_count_i32)
        .map_err(|_| DtaError::ArithmeticOverflow("value-label entry count"))?;
    let text_length = usize::try_from(text_length_i32)
        .map_err(|_| DtaError::ArithmeticOverflow("value-label text length"))?;
    let arrays_length = checked_mul(entry_count, 8, "value-label arrays length")?;
    let expected = checked_add(
        checked_add(8, arrays_length, "value-label payload length")?,
        text_length,
        "value-label payload length",
    )?;
    if declared != expected {
        return Err(DtaError::InvalidValueLabelLength {
            offset: table_start,
            declared,
            expected,
        });
    }

    let offsets_start = 8;
    let values_start = checked_add(
        offsets_start,
        checked_mul(entry_count, 4, "value-label offsets length")?,
        "value-label values offset",
    )?;
    let text_start = checked_add(
        values_start,
        checked_mul(entry_count, 4, "value-label values length")?,
        "value-label text offset",
    )?;
    let text_end = checked_add(text_start, text_length, "value-label text block")?;

    let mut entries = Vec::with_capacity(entry_count);
    let mut previous_value = None;
    for entry_index in 0..entry_count {
        let element_offset = checked_mul(entry_index, 4, "value-label entry offset")?;
        let raw_offset_position = checked_add(
            offsets_start,
            element_offset,
            "value-label entry offset position",
        )?;
        let text_offset = read_i32(
            payload,
            raw_offset_position,
            metadata.byte_order,
            "value-label text offset",
        )?;
        let valid_offset = usize::try_from(text_offset)
            .ok()
            .filter(|offset| *offset < text_length);
        let Some(text_offset_usize) = valid_offset else {
            return Err(DtaError::InvalidValueLabelTextOffset {
                entry_index,
                offset: checked_add(
                    payload_start,
                    raw_offset_position,
                    "value-label text offset position",
                )?,
                text_offset,
                text_length,
            });
        };

        let value_position =
            checked_add(values_start, element_offset, "value-label value position")?;
        let value = read_i32(
            payload,
            value_position,
            metadata.byte_order,
            "value-label value",
        )?;
        if let Some(previous) = previous_value {
            if value <= previous {
                return Err(DtaError::UnsortedValueLabelValues {
                    table_offset: table_start,
                    entry_index,
                    previous,
                    value,
                });
            }
        }
        previous_value = Some(value);

        let label_start = checked_add(text_start, text_offset_usize, "value-label text")?;
        let remaining = payload
            .get(label_start..text_end)
            .ok_or(DtaError::ArithmeticOverflow("value-label text bounds"))?;
        let nul =
            remaining
                .iter()
                .position(|byte| *byte == 0)
                .ok_or(DtaError::MissingNulTerminator {
                    context: "value-label text",
                    offset: checked_add(payload_start, label_start, "value-label text")?,
                })?;
        let label = String::from_utf8_lossy(&remaining[..nul]).into_owned();
        entries.push(ValueLabelEntry {
            value,
            missing_tag: classify_long_missing(value),
            label,
        });
    }

    cursor = checked_add(payload_start, declared, "value-label table payload")?;
    cursor = expect_at(bytes, cursor, LABEL_CLOSE, "</lbl>")?;
    Ok((ValueLabelTable { name, entries }, cursor))
}

/// Parse the modern Stata value-label section in on-disk table and entry order.
///
/// This validates every declared table boundary, text offset, NUL terminator,
/// section close, and final file-map offset before returning any tables.
pub fn parse_value_labels(
    bytes: &[u8],
    metadata: &DtaMetadata,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    let name_width = name_width(metadata.format_version)?;
    let start = offset_to_usize(metadata.section_offsets.value_labels, "value_labels")?;
    let mut cursor = expect_at(bytes, start, VALUE_LABELS_OPEN, "<value_labels>")?;
    let mut tables = Vec::new();

    loop {
        if bytes
            .get(cursor..)
            .is_some_and(|remaining| remaining.starts_with(VALUE_LABELS_CLOSE))
        {
            cursor = expect_at(bytes, cursor, VALUE_LABELS_CLOSE, "</value_labels>")?;
            break;
        }
        let (table, next) = parse_table(bytes, metadata, cursor, name_width)?;
        tables.push(table);
        cursor = next;
    }

    ensure_map_offset(
        "stata_data_close",
        cursor,
        metadata.section_offsets.stata_data_close,
    )?;
    cursor = expect_at(bytes, cursor, STATA_DATA_CLOSE, "</stata_dta>")?;
    ensure_map_offset("end_of_file", cursor, metadata.section_offsets.end_of_file)?;
    ensure_map_offset(
        "file length",
        bytes.len(),
        metadata.section_offsets.end_of_file,
    )?;
    Ok(tables)
}
