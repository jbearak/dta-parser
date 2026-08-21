use crate::endian::{
    checked_add, checked_mul, expect_at, offset_to_usize, read_i16, read_i32, read_u16, slice_at,
};
use crate::legacy::{LegacyLayout, LegacyValueLabelLayout};
use crate::text::{field_bytes, is_utf8_boundary, TextEncoding};
use crate::{
    missing::classify_long_missing_for_version, DtaError, DtaMetadata, FormatVersion,
    ValueLabelEntry, ValueLabelTable,
};

const VALUE_LABELS_OPEN: &[u8] = b"<value_labels>";
const VALUE_LABELS_CLOSE: &[u8] = b"</value_labels>";
const LABEL_OPEN: &[u8] = b"<lbl>";
const LABEL_CLOSE: &[u8] = b"</lbl>";
const STATA_DATA_CLOSE: &[u8] = b"</stata_dta>";
const RESERVED_WIDTH: usize = 3;

fn name_width(version: FormatVersion) -> Result<usize, DtaError> {
    if version.is_modern() {
        return match version {
            FormatVersion::V117 => Ok(33),
            FormatVersion::V118 | FormatVersion::V119 => Ok(129),
            _ => unreachable!("modern release expected"),
        };
    }
    Ok(LegacyLayout::for_version(version).value_label_table_name_width)
}

fn parse_fixed8_table(
    bytes: &[u8],
    metadata: &DtaMetadata,
    table_start: usize,
    encoding: TextEncoding,
) -> Result<(ValueLabelTable, usize), DtaError> {
    const NAME_WIDTH: usize = 9;
    const PADDING_WIDTH: usize = 1;
    const LABEL_WIDTH: usize = 8;

    let entry_count = usize::from(read_u16(
        bytes,
        table_start,
        metadata.byte_order,
        "legacy value-label entry count",
    )?);
    let name_start = checked_add(table_start, 2, "legacy value-label table name")?;
    let name = encoding.decode(field_bytes(slice_at(
        bytes,
        name_start,
        NAME_WIDTH,
        "legacy value-label table name",
    )?));
    let values_start = checked_add(
        checked_add(name_start, NAME_WIDTH, "legacy value-label table name")?,
        PADDING_WIDTH,
        "legacy value-label padding",
    )?;
    slice_at(
        bytes,
        values_start - PADDING_WIDTH,
        PADDING_WIDTH,
        "legacy value-label padding",
    )?;
    let labels_start = checked_add(
        values_start,
        checked_mul(entry_count, 2, "legacy value-label values")?,
        "legacy value-label labels",
    )?;
    let table_end = checked_add(
        labels_start,
        checked_mul(entry_count, LABEL_WIDTH, "legacy value-label labels")?,
        "legacy value-label table",
    )?;
    slice_at(
        bytes,
        table_start,
        table_end - table_start,
        "legacy value-label table",
    )?;

    let mut entries = Vec::with_capacity(entry_count);
    for entry_index in 0..entry_count {
        let value_at = checked_add(
            values_start,
            checked_mul(entry_index, 2, "legacy value-label value")?,
            "legacy value-label value",
        )?;
        let label_at = checked_add(
            labels_start,
            checked_mul(entry_index, LABEL_WIDTH, "legacy value-label text")?,
            "legacy value-label text",
        )?;
        let value = i32::from(read_i16(
            bytes,
            value_at,
            metadata.byte_order,
            "legacy value-label value",
        )?);
        let label = encoding.decode(field_bytes(slice_at(
            bytes,
            label_at,
            LABEL_WIDTH,
            "legacy value-label text",
        )?));
        entries.push(ValueLabelEntry {
            value,
            missing_tag: classify_long_missing_for_version(value, metadata.format_version),
            label,
        });
    }
    Ok((ValueLabelTable { name, entries }, table_end))
}

fn parse_table(
    bytes: &[u8],
    metadata: &DtaMetadata,
    table_start: usize,
    name_width: usize,
    wrapped: bool,
    encoding: TextEncoding,
) -> Result<(ValueLabelTable, usize), DtaError> {
    let mut cursor = if wrapped {
        expect_at(bytes, table_start, LABEL_OPEN, "<lbl>")?
    } else {
        table_start
    };
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
    let name_bytes = if metadata.format_version.is_modern() {
        let name_end = name_field.iter().position(|byte| *byte == 0).ok_or(
            DtaError::MissingNulTerminator {
                context: "value-label table name",
                offset: name_start,
            },
        )?;
        &name_field[..name_end]
    } else {
        field_bytes(name_field)
    };
    let name = encoding.decode(name_bytes);
    cursor = checked_add(cursor, name_width, "value-label table name")?;

    // The format reserves these bytes but does not assign them semantics.
    slice_at(bytes, cursor, RESERVED_WIDTH, "value-label reserved bytes")?;
    cursor = checked_add(cursor, RESERVED_WIDTH, "value-label reserved bytes")?;

    let payload_start = cursor;
    if declared < 8 {
        return Err(DtaError::InvalidValueLabelLength {
            offset: table_start,
            declared,
            expected: 8,
        });
    }

    // Validate the self-describing payload header before requiring the entire
    // declared range. This matches the bounded file reader and reports a
    // corrupt declaration precisely without staging an attacker-sized slice.
    let payload_header = slice_at(bytes, payload_start, 8, "value-label payload header")?;
    let entry_count_i32 = read_i32(
        payload_header,
        0,
        metadata.byte_order,
        "value-label entry count",
    )?;
    if entry_count_i32 < 0 {
        return Err(DtaError::NegativeValueLabelField {
            field: "entry count",
            value: entry_count_i32,
            offset: payload_start,
        });
    }
    let text_length_i32 = read_i32(
        payload_header,
        4,
        metadata.byte_order,
        "value-label text length",
    )?;
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
    let payload = slice_at(bytes, payload_start, declared, "value-label table payload")?;

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
        if encoding.is_utf8()
            && !is_utf8_boundary(&payload[text_start..text_end], text_offset_usize)
        {
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
        }

        let value_position =
            checked_add(values_start, element_offset, "value-label value position")?;
        let value = read_i32(
            payload,
            value_position,
            metadata.byte_order,
            "value-label value",
        )?;

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
        let label = encoding.decode(&remaining[..nul]);
        entries.push(ValueLabelEntry {
            value,
            missing_tag: classify_long_missing_for_version(value, metadata.format_version),
            label,
        });
    }

    cursor = checked_add(payload_start, declared, "value-label table payload")?;
    if wrapped {
        cursor = expect_at(bytes, cursor, LABEL_CLOSE, "</lbl>")?;
    }
    Ok((ValueLabelTable { name, entries }, cursor))
}

fn parse_legacy_tables(
    bytes: &[u8],
    metadata: &DtaMetadata,
    start: usize,
    end: usize,
    encoding: TextEncoding,
    layout: LegacyValueLabelLayout,
    name_width: usize,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    let mut cursor = start;
    let mut tables = Vec::new();
    while cursor < end {
        if bytes[cursor..end].iter().all(|byte| *byte == 0) {
            cursor = end;
            break;
        }
        let (table, next) = match layout {
            LegacyValueLabelLayout::Fixed8 => {
                parse_fixed8_table(bytes, metadata, cursor, encoding)?
            }
            LegacyValueLabelLayout::OffsetTable => {
                parse_table(bytes, metadata, cursor, name_width, false, encoding)?
            }
        };
        if next <= cursor {
            return Err(DtaError::ArithmeticOverflow("legacy value-label cursor"));
        }
        tables.push(table);
        cursor = next;
    }
    if cursor != end {
        return Err(DtaError::MapOffsetMismatch {
            section: "end_of_file",
            expected: end as u64,
            actual: cursor as u64,
        });
    }
    Ok(tables)
}

/// Parse the modern Stata value-label section in on-disk table and entry order.
///
/// This validates every declared table boundary, text offset, NUL terminator,
/// section close, and final file-map offset before returning any tables.
pub fn parse_value_labels(
    bytes: &[u8],
    metadata: &DtaMetadata,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    parse_value_labels_with_encoding(bytes, metadata, TextEncoding::Auto)
}

/// Parse value-label tables with an explicit source-text encoding.
pub fn parse_value_labels_with_encoding(
    bytes: &[u8],
    metadata: &DtaMetadata,
    encoding: TextEncoding,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    parse_value_labels_section(
        bytes,
        metadata,
        0,
        encoding.resolve(metadata.format_version),
    )
}

fn local_offset(absolute: u64, base_offset: u64, context: &'static str) -> Result<usize, DtaError> {
    let relative = absolute
        .checked_sub(base_offset)
        .ok_or(DtaError::ArithmeticOverflow(context))?;
    offset_to_usize(relative, context)
}

fn ensure_absolute_offset(
    section: &'static str,
    local: usize,
    base_offset: u64,
    expected: u64,
) -> Result<(), DtaError> {
    let local = u64::try_from(local).map_err(|_| DtaError::OffsetOutOfRange {
        context: section,
        offset: u64::MAX,
    })?;
    let actual = base_offset
        .checked_add(local)
        .ok_or(DtaError::ArithmeticOverflow(section))?;
    if actual != expected {
        return Err(DtaError::MapOffsetMismatch {
            section,
            expected,
            actual,
        });
    }
    Ok(())
}

pub(crate) fn parse_value_labels_section(
    bytes: &[u8],
    metadata: &DtaMetadata,
    base_offset: u64,
    encoding: TextEncoding,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    let name_width = name_width(metadata.format_version)?;
    let start = local_offset(
        metadata.section_offsets.value_labels,
        base_offset,
        "value_labels",
    )?;
    if !metadata.format_version.is_modern() {
        let end = local_offset(
            metadata.section_offsets.end_of_file,
            base_offset,
            "end_of_file",
        )?;
        if bytes.len() != end {
            return Err(DtaError::MapOffsetMismatch {
                section: "file length",
                expected: end as u64,
                actual: bytes.len() as u64,
            });
        }
        let layout = LegacyLayout::for_version(metadata.format_version);
        if metadata.format_version == FormatVersion::V105 {
            return parse_legacy_tables(
                bytes,
                metadata,
                start,
                end,
                encoding,
                LegacyValueLabelLayout::OffsetTable,
                33,
            )
            .or_else(|_| {
                parse_legacy_tables(
                    bytes,
                    metadata,
                    start,
                    end,
                    encoding,
                    LegacyValueLabelLayout::Fixed8,
                    9,
                )
            });
        }
        let primary = parse_legacy_tables(
            bytes,
            metadata,
            start,
            end,
            encoding,
            layout.value_label_layout,
            layout.value_label_table_name_width,
        );
        return match metadata.format_version {
            FormatVersion::V108 => primary.or_else(|_| {
                parse_legacy_tables(
                    bytes,
                    metadata,
                    start,
                    end,
                    encoding,
                    LegacyValueLabelLayout::OffsetTable,
                    33,
                )
            }),
            _ => primary,
        };
    }
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
        let (table, next) = parse_table(bytes, metadata, cursor, name_width, true, encoding)?;
        tables.push(table);
        cursor = next;
    }

    ensure_absolute_offset(
        "stata_data_close",
        cursor,
        base_offset,
        metadata.section_offsets.stata_data_close,
    )?;
    cursor = expect_at(bytes, cursor, STATA_DATA_CLOSE, "</stata_dta>")?;
    ensure_absolute_offset(
        "end_of_file",
        cursor,
        base_offset,
        metadata.section_offsets.end_of_file,
    )?;
    ensure_absolute_offset(
        "file length",
        bytes.len(),
        base_offset,
        metadata.section_offsets.end_of_file,
    )?;
    Ok(tables)
}
