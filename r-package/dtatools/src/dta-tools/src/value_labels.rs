use std::collections::HashSet;

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
pub(crate) const MAX_VALUE_LABEL_ENTRIES: usize = 65_536;

#[derive(Clone, Copy)]
pub(crate) struct OffsetValueLabelFrame {
    pub entry_count: usize,
    pub text_length: usize,
}

pub(crate) fn frame_offset_value_label_payload(
    header: &[u8],
    byte_order: crate::ByteOrder,
    table_offset: usize,
    payload_offset: usize,
    declared: usize,
) -> Result<OffsetValueLabelFrame, DtaError> {
    let entry_count_i32 = read_i32(header, 0, byte_order, "value-label entry count")?;
    if entry_count_i32 < 0 {
        return Err(DtaError::NegativeValueLabelField {
            field: "entry count",
            value: entry_count_i32,
            offset: payload_offset,
        });
    }
    let text_length_i32 = read_i32(header, 4, byte_order, "value-label text length")?;
    if text_length_i32 < 0 {
        return Err(DtaError::NegativeValueLabelField {
            field: "text length",
            value: text_length_i32,
            offset: payload_offset.saturating_add(4),
        });
    }
    let entry_count = usize::try_from(entry_count_i32)
        .map_err(|_| DtaError::ArithmeticOverflow("value-label entry count"))?;
    if entry_count > MAX_VALUE_LABEL_ENTRIES {
        return Err(DtaError::ArithmeticOverflow(
            "value-label entry count exceeds 65,536",
        ));
    }
    let text_length = usize::try_from(text_length_i32)
        .map_err(|_| DtaError::ArithmeticOverflow("value-label text length"))?;
    let arrays_length = checked_mul(entry_count, 8, "value-label arrays length")?;
    let expected_length = checked_add(
        checked_add(8, arrays_length, "value-label payload length")?,
        text_length,
        "value-label payload length",
    )?;
    if declared != expected_length {
        return Err(DtaError::InvalidValueLabelLength {
            offset: table_offset,
            declared,
            expected: expected_length,
        });
    }
    Ok(OffsetValueLabelFrame {
        entry_count,
        text_length,
    })
}

pub(crate) fn has_legacy_offset_table_framing(
    bytes: &[u8],
    byte_order: crate::ByteOrder,
    section_length: usize,
    name_width: usize,
) -> bool {
    let Some(payload_start) = 4_usize
        .checked_add(name_width)
        .and_then(|value| value.checked_add(RESERVED_WIDTH))
    else {
        return false;
    };
    let Some(header_end) = payload_start.checked_add(8) else {
        return false;
    };
    if header_end > bytes.len() || header_end > section_length {
        return false;
    }
    let Ok(table_length) = read_i32(bytes, 0, byte_order, "value-label table length") else {
        return false;
    };
    let Ok(entry_count) = read_i32(bytes, payload_start, byte_order, "value-label entry count")
    else {
        return false;
    };
    let Ok(text_length) = read_i32(
        bytes,
        payload_start + 4,
        byte_order,
        "value-label text length",
    ) else {
        return false;
    };
    if table_length <= 0 || entry_count < 0 || text_length < 0 {
        return false;
    }
    let Ok(entry_count) = usize::try_from(entry_count) else {
        return false;
    };
    if entry_count > MAX_VALUE_LABEL_ENTRIES {
        return false;
    }
    let Ok(text_length) = usize::try_from(text_length) else {
        return false;
    };
    let Ok(table_length) = usize::try_from(table_length) else {
        return false;
    };
    let Some(payload_length) = entry_count
        .checked_mul(8)
        .and_then(|length| length.checked_add(8))
        .and_then(|length| length.checked_add(text_length))
    else {
        return false;
    };
    payload_length == table_length
        && payload_start
            .checked_add(payload_length)
            .is_some_and(|table_end| table_end <= section_length)
}

pub(crate) fn has_legacy_offset_section_framing(
    bytes: &[u8],
    byte_order: crate::ByteOrder,
    name_width: usize,
) -> bool {
    let Some(prefix_width) = 4_usize
        .checked_add(name_width)
        .and_then(|value| value.checked_add(RESERVED_WIDTH))
    else {
        return false;
    };
    let mut cursor = 0;
    let mut known_nonzero = None;
    while cursor < bytes.len() {
        let remaining = &bytes[cursor..];
        if !known_nonzero.is_some_and(|offset| offset >= cursor) {
            if let Some(relative) = remaining.iter().position(|byte| *byte != 0) {
                let Some(offset) = cursor.checked_add(relative) else {
                    return false;
                };
                known_nonzero = Some(offset);
            } else {
                return true;
            }
        }
        if !has_legacy_offset_table_framing(remaining, byte_order, remaining.len(), name_width) {
            return false;
        }
        let Ok(table_length) = read_i32(remaining, 0, byte_order, "value-label table length")
        else {
            return false;
        };
        let Ok(table_length) = usize::try_from(table_length) else {
            return false;
        };
        let Some(next) = cursor
            .checked_add(prefix_width)
            .and_then(|value| value.checked_add(table_length))
        else {
            return false;
        };
        if next <= cursor || next > bytes.len() {
            return false;
        }
        cursor = next;
    }
    true
}

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
    selected: Option<&HashSet<&str>>,
) -> Result<(Option<ValueLabelTable>, usize), DtaError> {
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
    let retain = selected.is_none_or(|selected| selected.contains(name.as_str()));
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
    if !retain {
        return Ok((None, table_end));
    }

    let mut entries = Vec::new();
    entries
        .try_reserve_exact(entry_count)
        .map_err(|_| DtaError::ArithmeticOverflow("value-label entry allocation"))?;
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
    Ok((Some(ValueLabelTable { name, entries }), table_end))
}

fn nul_positions(text: &[u8]) -> Result<Vec<usize>, DtaError> {
    let mut positions = Vec::new();
    for (position, byte) in text.iter().enumerate() {
        if *byte != 0 {
            continue;
        }
        if positions.len() == positions.capacity() {
            let additional = positions.capacity().max(4);
            positions
                .try_reserve_exact(additional)
                .map_err(|_| DtaError::ArithmeticOverflow("value-label terminator index"))?;
        }
        positions.push(position);
    }
    Ok(positions)
}

fn first_nul_at_or_after(positions: &[usize], offset: usize) -> Option<usize> {
    positions
        .get(positions.partition_point(|&position| position < offset))
        .copied()
}

fn parse_table(
    bytes: &[u8],
    metadata: &DtaMetadata,
    table_start: usize,
    name_width: usize,
    wrapped: bool,
    encoding: TextEncoding,
    selected: Option<&HashSet<&str>>,
) -> Result<(Option<ValueLabelTable>, usize), DtaError> {
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
    let retain = selected.is_none_or(|selected| selected.contains(name.as_str()));
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
    let frame = frame_offset_value_label_payload(
        payload_header,
        metadata.byte_order,
        table_start,
        payload_start,
        declared,
    )?;
    let entry_count = frame.entry_count;
    let text_length = frame.text_length;
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
    let text = &payload[text_start..text_end];
    let mut text_offsets = retain.then(Vec::new);
    if let Some(text_offsets) = text_offsets.as_mut() {
        text_offsets
            .try_reserve_exact(entry_count)
            .map_err(|_| DtaError::ArithmeticOverflow("value-label offset allocation"))?;
    }
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

        if let Some(text_offsets) = text_offsets.as_mut() {
            text_offsets.push(text_offset_usize);
        }
    }

    let entries = if retain {
        let text_offsets = text_offsets
            .as_ref()
            .expect("retained table has text offsets");
        let terminators = nul_positions(text)?;
        let mut entries = Vec::new();
        entries
            .try_reserve_exact(entry_count)
            .map_err(|_| DtaError::ArithmeticOverflow("value-label entry allocation"))?;
        for (entry_index, &text_offset) in text_offsets.iter().enumerate() {
            let Some(nul) = first_nul_at_or_after(&terminators, text_offset) else {
                return Err(DtaError::MissingNulTerminator {
                    context: "value-label text",
                    offset: checked_add(
                        payload_start,
                        checked_add(text_start, text_offset, "value-label text")?,
                        "value-label text",
                    )?,
                });
            };
            let element_offset = checked_mul(entry_index, 4, "value-label entry offset")?;
            let value_position =
                checked_add(values_start, element_offset, "value-label value position")?;
            let value = read_i32(
                payload,
                value_position,
                metadata.byte_order,
                "value-label value",
            )?;
            entries.push(ValueLabelEntry {
                value,
                missing_tag: classify_long_missing_for_version(value, metadata.format_version),
                label: encoding.decode(&text[text_offset..nul]),
            });
        }
        Some(entries)
    } else if text.last() != Some(&0) {
        let last_nul = text.iter().rposition(|byte| *byte == 0);
        for entry_index in 0..entry_count {
            let raw_offset_position = checked_add(
                offsets_start,
                checked_mul(entry_index, 4, "value-label entry offset")?,
                "value-label entry offset position",
            )?;
            let text_offset = usize::try_from(read_i32(
                payload,
                raw_offset_position,
                metadata.byte_order,
                "validated value-label text offset",
            )?)
            .map_err(|_| DtaError::ArithmeticOverflow("validated value-label text offset"))?;
            if last_nul.is_none_or(|last_nul| text_offset > last_nul) {
                return Err(DtaError::MissingNulTerminator {
                    context: "value-label text",
                    offset: checked_add(
                        payload_start,
                        checked_add(text_start, text_offset, "value-label text")?,
                        "value-label text",
                    )?,
                });
            }
        }
        None
    } else {
        None
    };

    cursor = checked_add(payload_start, declared, "value-label table payload")?;
    if wrapped {
        cursor = expect_at(bytes, cursor, LABEL_CLOSE, "</lbl>")?;
    }
    Ok((
        entries.map(|entries| ValueLabelTable { name, entries }),
        cursor,
    ))
}

fn parse_legacy_tables(
    bytes: &[u8],
    metadata: &DtaMetadata,
    start: usize,
    end: usize,
    encoding: TextEncoding,
    layout: (LegacyValueLabelLayout, usize),
    selected: Option<&HashSet<&str>>,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    let (layout, name_width) = layout;
    let mut cursor = start;
    let mut tables = Vec::new();
    let mut known_nonzero = None;
    while cursor < end {
        let suffix_is_zero = if known_nonzero.is_some_and(|offset| offset >= cursor) {
            false
        } else if let Some(relative) = bytes[cursor..end].iter().position(|byte| *byte != 0) {
            known_nonzero = Some(checked_add(cursor, relative, "value-label trailing bytes")?);
            false
        } else {
            true
        };
        if suffix_is_zero {
            cursor = end;
            break;
        }
        let (table, next) = match layout {
            LegacyValueLabelLayout::Fixed8 => {
                parse_fixed8_table(bytes, metadata, cursor, encoding, selected)?
            }
            LegacyValueLabelLayout::OffsetTable => parse_table(
                bytes, metadata, cursor, name_width, false, encoding, selected,
            )?,
        };
        if next <= cursor {
            return Err(DtaError::ArithmeticOverflow("legacy value-label cursor"));
        }
        if let Some(table) = table {
            tables.push(table);
        }
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
        None,
    )
}

pub(crate) fn parse_selected_value_labels_with_encoding(
    bytes: &[u8],
    metadata: &DtaMetadata,
    encoding: TextEncoding,
    selected: &HashSet<&str>,
) -> Result<Vec<ValueLabelTable>, DtaError> {
    parse_value_labels_section(
        bytes,
        metadata,
        0,
        encoding.resolve(metadata.format_version),
        Some(selected),
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
    selected: Option<&HashSet<&str>>,
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
        let section = bytes.get(start..end).ok_or(DtaError::Truncated {
            context: "value-label section",
            offset: start,
            needed: end.saturating_sub(start),
            available: bytes.len().saturating_sub(start),
        })?;
        let (value_label_layout, table_name_width) = match metadata.format_version {
            FormatVersion::V105
                if has_legacy_offset_section_framing(section, metadata.byte_order, 33) =>
            {
                (LegacyValueLabelLayout::OffsetTable, 33)
            }
            FormatVersion::V105 => (LegacyValueLabelLayout::Fixed8, 9),
            FormatVersion::V108
                if !has_legacy_offset_section_framing(section, metadata.byte_order, 9)
                    && has_legacy_offset_section_framing(section, metadata.byte_order, 33) =>
            {
                (LegacyValueLabelLayout::OffsetTable, 33)
            }
            _ => (
                layout.value_label_layout,
                layout.value_label_table_name_width,
            ),
        };
        return parse_legacy_tables(
            bytes,
            metadata,
            start,
            end,
            encoding,
            (value_label_layout, table_name_width),
            selected,
        );
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
        let (table, next) = parse_table(
            bytes, metadata, cursor, name_width, true, encoding, selected,
        )?;
        if let Some(table) = table {
            tables.push(table);
        }
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

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::{
        parse_fixed8_table, parse_selected_value_labels_with_encoding, parse_table,
        parse_value_labels_with_encoding,
    };
    use crate::{
        parse_metadata, ByteOrder, DtaMetadata, FormatVersion, SectionOffsets, TextEncoding,
    };

    #[test]
    fn unselected_fixed8_table_skips_entry_iteration_after_bounds_check() {
        const ENTRY_COUNT: u16 = u16::MAX;
        let metadata = parse_metadata(include_bytes!("../tests/data/synthetic-v105.dta")).unwrap();
        let mut bytes = Vec::with_capacity(12 + usize::from(ENTRY_COUNT) * 10);
        bytes.extend_from_slice(&match metadata.byte_order {
            ByteOrder::Lsf => ENTRY_COUNT.to_le_bytes(),
            ByteOrder::Msf => ENTRY_COUNT.to_be_bytes(),
        });
        bytes.extend_from_slice(b"labels\0\0\0");
        bytes.push(0);
        bytes.resize(12 + usize::from(ENTRY_COUNT) * 10, 0xff);

        let selected = HashSet::new();
        let (table, end) = parse_fixed8_table(
            &bytes,
            &metadata,
            0,
            TextEncoding::Windows1252,
            Some(&selected),
        )
        .unwrap();
        assert!(table.is_none());
        assert_eq!(end, bytes.len());
    }

    #[test]
    fn selected_value_labels_resolve_automatic_encoding() {
        let bytes = include_bytes!("../../../../../tests/fixtures/dta/value_labels_v115.dta");
        let metadata = parse_metadata(bytes).unwrap();
        let expected = parse_value_labels_with_encoding(bytes, &metadata, TextEncoding::Auto)
            .expect("the fixture value labels are valid");
        assert!(!expected.is_empty());
        let selected = expected
            .iter()
            .map(|table| table.name.as_str())
            .collect::<HashSet<_>>();

        let actual = parse_selected_value_labels_with_encoding(
            bytes,
            &metadata,
            TextEncoding::Auto,
            &selected,
        )
        .expect("automatic encoding resolves before selected parsing");

        assert_eq!(actual, expected);
    }

    #[test]
    fn oversized_offset_table_count_is_rejected_before_declared_payload_is_sliced() {
        let metadata = DtaMetadata {
            format_version: FormatVersion::V118,
            byte_order: ByteOrder::Lsf,
            nvar: 0,
            nobs: 0,
            dataset_label: String::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            variables: Vec::new(),
            section_offsets: SectionOffsets::default(),
            obs_length: 0,
        };
        let declared = 8_i32 + 65_537_i32 * 8;
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&declared.to_le_bytes());
        bytes.extend(std::iter::repeat_n(0, 129));
        bytes.extend_from_slice(&[0; 3]);
        bytes.extend_from_slice(&65_537_i32.to_le_bytes());
        bytes.extend_from_slice(&0_i32.to_le_bytes());

        assert!(matches!(
            parse_table(&bytes, &metadata, 0, 129, false, TextEncoding::Utf8, None,),
            Err(crate::DtaError::ArithmeticOverflow(
                "value-label entry count exceeds 65,536"
            ))
        ));
    }
}
