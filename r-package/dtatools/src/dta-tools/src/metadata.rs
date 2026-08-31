use crate::endian::{
    checked_add, checked_mul, ensure_map_offset, expect_at, offset_to_usize, read_u16, read_u32,
    read_u64, read_u8, slice_at,
};
use crate::legacy::parse_legacy_metadata;
use crate::stata_metadata::{
    validate_raw_value_bytes, validate_raw_value_length, CharacteristicCollector,
    CharacteristicPlan, CharacteristicValueUse, VariableTargetIndexes,
};
use crate::text::{field_bytes, TextEncoding};
use crate::{
    ByteOrder, DtaError, DtaMetadata, DtaType, FormatVersion, SectionOffsets, VariableInfo,
};

const RELEASE_OPEN: &[u8] = b"<stata_dta><header><release>";
const RELEASE_CLOSE: &[u8] = b"</release>";
const BYTE_ORDER_OPEN: &[u8] = b"<byteorder>";
const BYTE_ORDER_CLOSE: &[u8] = b"</byteorder>";
const K_OPEN: &[u8] = b"<K>";
const K_CLOSE: &[u8] = b"</K>";
const N_OPEN: &[u8] = b"<N>";
const N_CLOSE: &[u8] = b"</N>";
const LABEL_OPEN: &[u8] = b"<label>";
const LABEL_CLOSE: &[u8] = b"</label>";
const TIMESTAMP_OPEN: &[u8] = b"<timestamp>";
const TIMESTAMP_CLOSE: &[u8] = b"</timestamp>";
const HEADER_CLOSE: &[u8] = b"</header>";
const MAP_OPEN: &[u8] = b"<map>";
const MAP_CLOSE: &[u8] = b"</map>";
const VARIABLE_TYPES_OPEN: &[u8] = b"<variable_types>";
const VARIABLE_TYPES_CLOSE: &[u8] = b"</variable_types>";
const VARNAMES_OPEN: &[u8] = b"<varnames>";
const VARNAMES_CLOSE: &[u8] = b"</varnames>";
const SORTLIST_OPEN: &[u8] = b"<sortlist>";
const SORTLIST_CLOSE: &[u8] = b"</sortlist>";
const FORMATS_OPEN: &[u8] = b"<formats>";
const FORMATS_CLOSE: &[u8] = b"</formats>";
const VALUE_LABEL_NAMES_OPEN: &[u8] = b"<value_label_names>";
const VALUE_LABEL_NAMES_CLOSE: &[u8] = b"</value_label_names>";
const VARIABLE_LABELS_OPEN: &[u8] = b"<variable_labels>";
const VARIABLE_LABELS_CLOSE: &[u8] = b"</variable_labels>";
const CHARACTERISTICS_OPEN: &[u8] = b"<characteristics>";
const CHARACTERISTICS_CLOSE: &[u8] = b"</characteristics>";
const CHARACTERISTIC_OPEN: &[u8] = b"<ch>";
const CHARACTERISTIC_CLOSE: &[u8] = b"</ch>";

const SECTION_MAP_ENTRIES: usize = 14;

#[derive(Clone, Copy)]
pub(crate) struct FieldWidths {
    pub(crate) varname: usize,
    pub(crate) format: usize,
    pub(crate) value_label_name: usize,
    pub(crate) variable_label: usize,
}

pub(crate) const fn field_widths(version: FormatVersion) -> FieldWidths {
    match version {
        FormatVersion::V117 => FieldWidths {
            varname: 33,
            format: 49,
            value_label_name: 33,
            variable_label: 81,
        },
        FormatVersion::V118 | FormatVersion::V119 => FieldWidths {
            varname: 129,
            format: 57,
            value_label_name: 129,
            variable_label: 321,
        },
        FormatVersion::V105
        | FormatVersion::V108
        | FormatVersion::V110
        | FormatVersion::V111
        | FormatVersion::V113
        | FormatVersion::V114
        | FormatVersion::V115 => {
            panic!("legacy releases are rejected before widths are selected")
        }
    }
}

fn parse_release(bytes: &[u8]) -> Result<(FormatVersion, usize), DtaError> {
    if !bytes.starts_with(RELEASE_OPEN) {
        return Err(DtaError::InvalidSignature);
    }

    let release_start = RELEASE_OPEN.len();
    let release_bytes = slice_at(bytes, release_start, 3, "release number")?;
    let release_text = String::from_utf8_lossy(release_bytes).into_owned();
    let release_number = release_text
        .parse::<u16>()
        .map_err(|_| DtaError::InvalidRelease(release_text.clone()))?;
    let version = FormatVersion::try_from(release_number)
        .map_err(|_| DtaError::InvalidRelease(release_text))?;
    if !version.is_modern() {
        return Err(DtaError::UnsupportedRelease(version));
    }

    let after_release = checked_add(release_start, 3, "release number")?;
    let cursor = expect_at(bytes, after_release, RELEASE_CLOSE, "</release>")?;
    Ok((version, cursor))
}

fn parse_byte_order(bytes: &[u8], mut cursor: usize) -> Result<(ByteOrder, usize), DtaError> {
    cursor = expect_at(bytes, cursor, BYTE_ORDER_OPEN, "<byteorder>")?;
    let value = slice_at(bytes, cursor, 3, "byte order")?;
    let byte_order = match value {
        b"MSF" => ByteOrder::Msf,
        b"LSF" => ByteOrder::Lsf,
        invalid => {
            return Err(DtaError::InvalidByteOrder(
                String::from_utf8_lossy(invalid).into(),
            ))
        }
    };
    cursor = checked_add(cursor, 3, "byte order")?;
    cursor = expect_at(bytes, cursor, BYTE_ORDER_CLOSE, "</byteorder>")?;
    Ok((byte_order, cursor))
}

fn parse_counts(
    bytes: &[u8],
    version: FormatVersion,
    byte_order: ByteOrder,
    mut cursor: usize,
) -> Result<(u32, u64, usize), DtaError> {
    cursor = expect_at(bytes, cursor, K_OPEN, "<K>")?;
    let (nvar, k_width) = if version == FormatVersion::V119 {
        (read_u32(bytes, cursor, byte_order, "variable count")?, 4)
    } else {
        (
            u32::from(read_u16(bytes, cursor, byte_order, "variable count")?),
            2,
        )
    };
    cursor = checked_add(cursor, k_width, "variable count")?;
    cursor = expect_at(bytes, cursor, K_CLOSE, "</K>")?;

    cursor = expect_at(bytes, cursor, N_OPEN, "<N>")?;
    let (nobs, n_width) = if version == FormatVersion::V117 {
        (
            u64::from(read_u32(bytes, cursor, byte_order, "observation count")?),
            4,
        )
    } else {
        (read_u64(bytes, cursor, byte_order, "observation count")?, 8)
    };
    cursor = checked_add(cursor, n_width, "observation count")?;
    cursor = expect_at(bytes, cursor, N_CLOSE, "</N>")?;
    Ok((nvar, nobs, cursor))
}

fn parse_length_prefixed_text(
    bytes: &[u8],
    version: FormatVersion,
    byte_order: ByteOrder,
    mut cursor: usize,
    encoding: TextEncoding,
) -> Result<(String, usize), DtaError> {
    cursor = expect_at(bytes, cursor, LABEL_OPEN, "<label>")?;
    let (length, length_width) = if version == FormatVersion::V117 {
        (
            usize::from(read_u8(bytes, cursor, "dataset label length")?),
            1,
        )
    } else {
        (
            usize::from(read_u16(bytes, cursor, byte_order, "dataset label length")?),
            2,
        )
    };
    cursor = checked_add(cursor, length_width, "dataset label length")?;
    let label = encoding.decode(slice_at(bytes, cursor, length, "dataset label")?);
    cursor = checked_add(cursor, length, "dataset label")?;
    cursor = expect_at(bytes, cursor, LABEL_CLOSE, "</label>")?;

    cursor = expect_at(bytes, cursor, TIMESTAMP_OPEN, "<timestamp>")?;
    let timestamp_length = usize::from(read_u8(bytes, cursor, "timestamp length")?);
    cursor = checked_add(cursor, 1, "timestamp length")?;
    slice_at(bytes, cursor, timestamp_length, "timestamp")?;
    cursor = checked_add(cursor, timestamp_length, "timestamp")?;
    cursor = expect_at(bytes, cursor, TIMESTAMP_CLOSE, "</timestamp>")?;
    cursor = expect_at(bytes, cursor, HEADER_CLOSE, "</header>")?;
    Ok((label, cursor))
}

fn parse_section_map(
    bytes: &[u8],
    byte_order: ByteOrder,
    map_start: usize,
) -> Result<(SectionOffsets, usize), DtaError> {
    let mut cursor = expect_at(bytes, map_start, MAP_OPEN, "<map>")?;
    let mut values = [0_u64; SECTION_MAP_ENTRIES];
    for value in &mut values {
        *value = read_u64(bytes, cursor, byte_order, "section map")?;
        cursor = checked_add(cursor, 8, "section map")?;
    }
    cursor = expect_at(bytes, cursor, MAP_CLOSE, "</map>")?;

    let offsets = SectionOffsets::from_array(values);
    validate_map(&offsets, map_start, cursor)?;
    Ok((offsets, cursor))
}

fn validate_map(
    offsets: &SectionOffsets,
    map_start: usize,
    after_map: usize,
) -> Result<(), DtaError> {
    if offsets.stata_data != 0 {
        return Err(DtaError::MapOffsetMismatch {
            section: "stata_data",
            expected: 0,
            actual: offsets.stata_data,
        });
    }
    let expected_map = u64::try_from(map_start).map_err(|_| DtaError::OffsetOutOfRange {
        context: "map",
        offset: u64::MAX,
    })?;
    if offsets.map != expected_map {
        return Err(DtaError::MapOffsetMismatch {
            section: "map",
            expected: expected_map,
            actual: offsets.map,
        });
    }

    let values = offsets.as_array();
    for index in 1..values.len() {
        if values[index] <= values[index - 1] {
            return Err(DtaError::SectionOrder {
                section: SectionOffsets::NAMES[index],
                previous_offset: values[index - 1],
                offset: values[index],
            });
        }
    }

    ensure_map_offset("variable_types", after_map, offsets.variable_types)
}

fn parse_variable_types(
    bytes: &[u8],
    byte_order: ByteOrder,
    offsets: &SectionOffsets,
    nvar: usize,
) -> Result<Vec<u16>, DtaError> {
    let start = offset_to_usize(offsets.variable_types, "variable_types")?;
    let mut cursor = expect_at(bytes, start, VARIABLE_TYPES_OPEN, "<variable_types>")?;
    let payload_length = checked_mul(nvar, 2, "variable_types length")?;
    slice_at(bytes, cursor, payload_length, "variable_types")?;

    let mut types = Vec::with_capacity(nvar);
    for _ in 0..nvar {
        types.push(read_u16(bytes, cursor, byte_order, "variable type")?);
        cursor = checked_add(cursor, 2, "variable type")?;
    }
    cursor = expect_at(bytes, cursor, VARIABLE_TYPES_CLOSE, "</variable_types>")?;
    ensure_map_offset("varnames", cursor, offsets.varnames)?;
    Ok(types)
}

struct StringSection {
    offset: u64,
    next_offset: u64,
    next_name: &'static str,
    open: &'static [u8],
    open_name: &'static str,
    close: &'static [u8],
    close_name: &'static str,
    field_width: usize,
}

fn parse_fixed_string_section(
    bytes: &[u8],
    nvar: usize,
    section: StringSection,
    encoding: TextEncoding,
) -> Result<Vec<String>, DtaError> {
    let start = offset_to_usize(section.offset, section.open_name)?;
    let mut cursor = expect_at(bytes, start, section.open, section.open_name)?;
    let payload_length = checked_mul(nvar, section.field_width, "string section length")?;
    let payload = slice_at(bytes, cursor, payload_length, "string section")?;

    let mut strings = Vec::with_capacity(nvar);
    for field in payload.chunks_exact(section.field_width) {
        let nul = field
            .iter()
            .position(|byte| *byte == 0)
            .unwrap_or(field.len());
        strings.push(encoding.decode(&field[..nul]));
    }

    cursor = checked_add(cursor, payload_length, "string section length")?;
    cursor = expect_at(bytes, cursor, section.close, section.close_name)?;
    ensure_map_offset(section.next_name, cursor, section.next_offset)?;
    Ok(strings)
}

fn validate_sortlist(
    bytes: &[u8],
    version: FormatVersion,
    offsets: &SectionOffsets,
    nvar: usize,
) -> Result<(), DtaError> {
    let start = offset_to_usize(offsets.sortlist, "sortlist")?;
    let mut cursor = expect_at(bytes, start, SORTLIST_OPEN, "<sortlist>")?;
    let entries = checked_add(nvar, 1, "sortlist entries")?;
    let element_width = if version == FormatVersion::V119 { 4 } else { 2 };
    let payload_length = checked_mul(entries, element_width, "sortlist length")?;
    slice_at(bytes, cursor, payload_length, "sortlist")?;
    cursor = checked_add(cursor, payload_length, "sortlist length")?;
    cursor = expect_at(bytes, cursor, SORTLIST_CLOSE, "</sortlist>")?;
    ensure_map_offset("formats", cursor, offsets.formats)
}

#[derive(Clone, Copy)]
struct CharacteristicRecord {
    payload_start: usize,
    payload_length: usize,
}

fn walk_characteristic_records<F>(
    bytes: &[u8],
    start: usize,
    data: usize,
    byte_order: ByteOrder,
    names_length: usize,
    offsets: &SectionOffsets,
    mut visit: F,
) -> Result<(), DtaError>
where
    F: FnMut(usize, CharacteristicRecord) -> Result<(), DtaError>,
{
    let mut ordinal = 0_usize;
    let mut cursor = expect_at(bytes, start, CHARACTERISTICS_OPEN, "<characteristics>")?;
    loop {
        if bytes.get(cursor..cursor.saturating_add(CHARACTERISTICS_CLOSE.len()))
            == Some(CHARACTERISTICS_CLOSE)
        {
            cursor = expect_at(bytes, cursor, CHARACTERISTICS_CLOSE, "</characteristics>")?;
            ensure_map_offset("data", cursor, offsets.data)?;
            return Ok(());
        }

        cursor = expect_at(bytes, cursor, CHARACTERISTIC_OPEN, "<ch>")?;
        let payload_length = usize::try_from(read_u32(
            bytes,
            cursor,
            byte_order,
            "characteristic length",
        )?)
        .map_err(|_| DtaError::ArithmeticOverflow("characteristic length"))?;
        cursor = checked_add(cursor, 4, "characteristic length")?;
        if payload_length < names_length {
            return Err(DtaError::Truncated {
                context: "characteristic names",
                offset: cursor,
                needed: names_length,
                available: payload_length,
            });
        }
        let payload_end = checked_add(cursor, payload_length, "characteristic payload")?;
        let record_end = checked_add(
            payload_end,
            CHARACTERISTIC_CLOSE.len(),
            "characteristic closing tag",
        )?;
        if record_end > data {
            return Err(DtaError::Truncated {
                context: "characteristic payload",
                offset: cursor,
                needed: payload_length.saturating_add(CHARACTERISTIC_CLOSE.len()),
                available: data.saturating_sub(cursor),
            });
        }
        slice_at(bytes, cursor, payload_length, "characteristic payload")?;
        visit(
            ordinal,
            CharacteristicRecord {
                payload_start: cursor,
                payload_length,
            },
        )?;
        ordinal = ordinal
            .checked_add(1)
            .ok_or(DtaError::ArithmeticOverflow("characteristic record count"))?;
        cursor = expect_at(bytes, payload_end, CHARACTERISTIC_CLOSE, "</ch>")?;
    }
}

fn parse_characteristics(
    bytes: &[u8],
    version: FormatVersion,
    byte_order: ByteOrder,
    offsets: &SectionOffsets,
    encoding: TextEncoding,
    variables: &[VariableInfo],
) -> Result<Option<CharacteristicCollector>, DtaError> {
    let start = offset_to_usize(offsets.characteristics, "characteristics")?;
    if bytes.len() == start {
        return Ok(None);
    }
    let data = offset_to_usize(offsets.data, "data")?;
    let width = if version == FormatVersion::V117 {
        33
    } else {
        129
    };
    let names_length = checked_mul(width, 2, "characteristic names length")?;
    let close_start = data
        .checked_sub(CHARACTERISTICS_CLOSE.len())
        .ok_or(DtaError::ArithmeticOverflow("characteristics closing tag"))?;
    expect_at(
        bytes,
        close_start,
        CHARACTERISTICS_CLOSE,
        "</characteristics>",
    )?;
    // Validate every record boundary before decoding any values. The section
    // map alone cannot distinguish a real terminator from tag bytes forged in
    // the final record payload.
    walk_characteristic_records(
        bytes,
        start,
        data,
        byte_order,
        names_length,
        offsets,
        |_, _| Ok(()),
    )?;
    let mut plan = CharacteristicPlan::<&[u8]>::default();
    let mut variable_indexes = VariableTargetIndexes::new(variables);
    walk_characteristic_records(
        bytes,
        start,
        data,
        byte_order,
        names_length,
        offsets,
        |ordinal, record| {
            let cursor = record.payload_start;
            let payload = slice_at(
                bytes,
                cursor,
                record.payload_length,
                "characteristic payload",
            )?;
            let (variable, remainder) = payload.split_at(width);
            let (characteristic, value) = remainder.split_at(width);
            let target = encoding.decode(field_bytes(variable));
            let name = encoding.decode(field_bytes(characteristic));
            plan.push_record(
                ordinal,
                &target,
                name,
                cursor + width,
                |target| variable_indexes.resolve(target),
                |value_use| match value_use {
                    CharacteristicValueUse::Skip => Ok(None),
                    CharacteristicValueUse::Retain => {
                        validate_raw_value_length(
                            value.len(),
                            cursor + names_length,
                            "characteristic value",
                        )?;
                        Ok(Some(validate_raw_value_bytes(
                            value,
                            cursor + names_length,
                            "characteristic value",
                        )?))
                    }
                    CharacteristicValueUse::Validate => {
                        validate_raw_value_length(
                            value.len(),
                            cursor + names_length,
                            "characteristic value",
                        )?;
                        validate_raw_value_bytes(
                            value,
                            cursor + names_length,
                            "characteristic value",
                        )?;
                        Ok(None)
                    }
                },
            )
        },
    )?;
    drop(variable_indexes);
    Ok(Some(plan.decode(|value| Ok(encoding.decode(value)))?))
}

pub(crate) fn resolve_type(code: u16, version: FormatVersion) -> Result<(DtaType, u32), DtaError> {
    DtaType::from_modern_code(code)
        .map(|dta_type| {
            let width = dta_type.storage_width();
            (dta_type, width)
        })
        .ok_or(DtaError::UnknownTypeCode { code, version })
}

/// Parse metadata from a Stata 105, 108, 110–111, 113–115, or 117–119 byte slice.
///
/// Modern input may contain the full file or end immediately after the
/// `variable_labels` section; later section-map offsets are retained without
/// dereferencing them. Legacy input must contain the complete file because its
/// sequential layout requires scanning expansion fields and observation
/// geometry to establish the value-label and end-of-file offsets.
pub fn parse_metadata(bytes: &[u8]) -> Result<DtaMetadata, DtaError> {
    parse_metadata_with_encoding(bytes, TextEncoding::Auto)
}

/// Parse metadata while overriding the source encoding of every textual
/// field. [`TextEncoding::Auto`] preserves the release-specific default.
pub fn parse_metadata_with_encoding(
    bytes: &[u8],
    encoding: TextEncoding,
) -> Result<DtaMetadata, DtaError> {
    if matches!(bytes.first(), Some(105 | 108 | 110 | 111 | 113..=115)) {
        return parse_legacy_metadata(
            bytes,
            u64::try_from(bytes.len()).map_err(|_| DtaError::ArithmeticOverflow("file length"))?,
            encoding,
        );
    }
    let (format_version, cursor) = parse_release(bytes)?;
    let encoding = encoding.resolve(format_version);
    let (byte_order, cursor) = parse_byte_order(bytes, cursor)?;
    let (nvar, nobs, cursor) = parse_counts(bytes, format_version, byte_order, cursor)?;
    let (dataset_label, map_start) =
        parse_length_prefixed_text(bytes, format_version, byte_order, cursor, encoding)?;
    let (section_offsets, _) = parse_section_map(bytes, byte_order, map_start)?;

    let nvar_usize = usize::try_from(nvar).map_err(|_| DtaError::ArithmeticOverflow("nvar"))?;
    let widths = field_widths(format_version);
    let type_codes = parse_variable_types(bytes, byte_order, &section_offsets, nvar_usize)?;
    let varnames = parse_fixed_string_section(
        bytes,
        nvar_usize,
        StringSection {
            offset: section_offsets.varnames,
            next_offset: section_offsets.sortlist,
            next_name: "sortlist",
            open: VARNAMES_OPEN,
            open_name: "<varnames>",
            close: VARNAMES_CLOSE,
            close_name: "</varnames>",
            field_width: widths.varname,
        },
        encoding,
    )?;
    validate_sortlist(bytes, format_version, &section_offsets, nvar_usize)?;
    let formats = parse_fixed_string_section(
        bytes,
        nvar_usize,
        StringSection {
            offset: section_offsets.formats,
            next_offset: section_offsets.value_label_names,
            next_name: "value_label_names",
            open: FORMATS_OPEN,
            open_name: "<formats>",
            close: FORMATS_CLOSE,
            close_name: "</formats>",
            field_width: widths.format,
        },
        encoding,
    )?;
    let value_label_names = parse_fixed_string_section(
        bytes,
        nvar_usize,
        StringSection {
            offset: section_offsets.value_label_names,
            next_offset: section_offsets.variable_labels,
            next_name: "variable_labels",
            open: VALUE_LABEL_NAMES_OPEN,
            open_name: "<value_label_names>",
            close: VALUE_LABEL_NAMES_CLOSE,
            close_name: "</value_label_names>",
            field_width: widths.value_label_name,
        },
        encoding,
    )?;
    let variable_labels = parse_fixed_string_section(
        bytes,
        nvar_usize,
        StringSection {
            offset: section_offsets.variable_labels,
            next_offset: section_offsets.characteristics,
            next_name: "characteristics",
            open: VARIABLE_LABELS_OPEN,
            open_name: "<variable_labels>",
            close: VARIABLE_LABELS_CLOSE,
            close_name: "</variable_labels>",
            field_width: widths.variable_label,
        },
        encoding,
    )?;
    let mut byte_offset = 0_u64;
    let mut variables = Vec::with_capacity(nvar_usize);
    for index in 0..nvar_usize {
        let type_code = type_codes[index];
        let (dta_type, byte_width) = resolve_type(type_code, format_version)?;
        variables.push(VariableInfo {
            name: varnames[index].clone(),
            dta_type,
            type_code,
            format: formats[index].clone(),
            label: variable_labels[index].clone(),
            value_label_name: value_label_names[index].clone(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            byte_width,
            byte_offset,
        });
        byte_offset = byte_offset
            .checked_add(u64::from(byte_width))
            .ok_or(DtaError::ArithmeticOverflow("observation length"))?;
    }

    let mut notes = Vec::new();
    let mut characteristics = Vec::new();
    let collector = parse_characteristics(
        bytes,
        format_version,
        byte_order,
        &section_offsets,
        encoding,
        &variables,
    )?;
    if let Some(collector) = collector {
        collector.finish(&mut notes, &mut characteristics, &mut variables);
    }

    Ok(DtaMetadata {
        format_version,
        byte_order,
        nvar,
        nobs,
        dataset_label,
        notes,
        characteristics,
        variables,
        section_offsets,
        obs_length: byte_offset,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::StataCharacteristic;

    fn push_modern_characteristic(
        bytes: &mut Vec<u8>,
        width: usize,
        target: &[u8],
        name: &[u8],
        value: &[u8],
    ) {
        let payload_length = 2 * width + value.len() + 1;
        bytes.extend_from_slice(CHARACTERISTIC_OPEN);
        bytes.extend_from_slice(&(payload_length as u32).to_le_bytes());
        let mut names = vec![0; 2 * width];
        names[..target.len()].copy_from_slice(target);
        names[width..width + name.len()].copy_from_slice(name);
        bytes.extend_from_slice(&names);
        bytes.extend_from_slice(value);
        bytes.push(0);
        bytes.extend_from_slice(CHARACTERISTIC_CLOSE);
    }

    #[test]
    fn in_memory_modern_characteristics_compact_adversarial_duplicates() {
        const DUPLICATES: usize = 10_000;
        let width = 129;
        let mut bytes = CHARACTERISTICS_OPEN.to_vec();
        for ordinal in 0..DUPLICATES {
            push_modern_characteristic(
                &mut bytes,
                width,
                b"_dta",
                b"source",
                ordinal.to_string().as_bytes(),
            );
        }
        bytes.extend_from_slice(CHARACTERISTICS_CLOSE);
        let offsets = SectionOffsets {
            characteristics: 0,
            data: bytes.len() as u64,
            ..SectionOffsets::default()
        };

        let collector = parse_characteristics(
            &bytes,
            FormatVersion::V118,
            ByteOrder::Lsf,
            &offsets,
            TextEncoding::Utf8,
            &[],
        )
        .unwrap()
        .unwrap();
        let mut characteristics = Vec::new();
        collector.finish(&mut Vec::new(), &mut characteristics, &mut []);
        assert_eq!(
            characteristics,
            vec![StataCharacteristic {
                name: "source".into(),
                value: (DUPLICATES - 1).to_string(),
            }]
        );
    }

    #[test]
    fn unterminated_modern_characteristics_are_framed_before_values_are_decoded() {
        let width = 129;
        let value_length = crate::stata_metadata::MAX_METADATA_VALUE_BYTES + 2;
        let payload_length = width * 2 + value_length;
        let mut bytes = CHARACTERISTICS_OPEN.to_vec();
        bytes.extend_from_slice(CHARACTERISTIC_OPEN);
        bytes.extend_from_slice(&(payload_length as u32).to_le_bytes());
        let mut target = vec![0; width];
        target[..4].copy_from_slice(b"_dta");
        bytes.extend_from_slice(&target);
        let mut name = vec![0; width];
        name[..6].copy_from_slice(b"source");
        bytes.extend_from_slice(&name);
        bytes.extend(std::iter::repeat_n(b'x', value_length));
        bytes.extend_from_slice(CHARACTERISTIC_CLOSE);
        let offsets = SectionOffsets {
            characteristics: 0,
            data: bytes.len() as u64,
            ..SectionOffsets::default()
        };

        assert!(matches!(
            parse_characteristics(
                &bytes,
                FormatVersion::V118,
                ByteOrder::Lsf,
                &offsets,
                TextEncoding::Utf8,
                &[],
            ),
            Err(DtaError::UnexpectedTag {
                expected: "</characteristics>",
                ..
            })
        ));
    }

    #[test]
    fn forged_modern_terminator_is_framed_before_values_are_decoded() {
        let width = 129;
        let value_length = crate::stata_metadata::MAX_METADATA_VALUE_BYTES + 2;
        let payload_length = width * 2 + value_length;
        let mut bytes = CHARACTERISTICS_OPEN.to_vec();
        bytes.extend_from_slice(CHARACTERISTIC_OPEN);
        bytes.extend_from_slice(&(payload_length as u32).to_le_bytes());
        let mut names = vec![0; width * 2];
        names[..4].copy_from_slice(b"_dta");
        names[width..width + 6].copy_from_slice(b"source");
        bytes.extend_from_slice(&names);
        bytes.extend(std::iter::repeat_n(b'x', value_length));
        bytes.extend_from_slice(CHARACTERISTIC_CLOSE);

        let forged_length = width * 2 + CHARACTERISTICS_CLOSE.len();
        bytes.extend_from_slice(CHARACTERISTIC_OPEN);
        bytes.extend_from_slice(&(forged_length as u32).to_le_bytes());
        bytes.extend(std::iter::repeat_n(0, width * 2));
        bytes.extend_from_slice(CHARACTERISTICS_CLOSE);
        let offsets = SectionOffsets {
            characteristics: 0,
            data: bytes.len() as u64,
            ..SectionOffsets::default()
        };

        assert!(matches!(
            parse_characteristics(
                &bytes,
                FormatVersion::V118,
                ByteOrder::Lsf,
                &offsets,
                TextEncoding::Utf8,
                &[],
            ),
            Err(DtaError::Truncated {
                context: "characteristic payload",
                ..
            })
        ));
    }

    #[test]
    fn enforces_type_boundaries_by_release() {
        for width in [244, 245, 251, 2045] {
            assert_eq!(
                resolve_type(width, FormatVersion::V117).unwrap(),
                (DtaType::FixedString(width), u32::from(width))
            );
        }
        assert_eq!(
            resolve_type(2045, FormatVersion::V119).unwrap(),
            (DtaType::FixedString(2045), 2045)
        );
        assert!(resolve_type(2046, FormatVersion::V118).is_err());
        assert_eq!(
            resolve_type(251, FormatVersion::V118).unwrap(),
            (DtaType::FixedString(251), 251)
        );
        assert_eq!(
            resolve_type(65526, FormatVersion::V117).unwrap(),
            (DtaType::Double, 8)
        );
        assert_eq!(
            resolve_type(32768, FormatVersion::V119).unwrap(),
            (DtaType::StrL, 8)
        );
    }

    #[test]
    fn rejects_truncated_legacy_and_unknown_signatures_without_panicking() {
        assert!(matches!(
            parse_metadata(&[115]),
            Err(DtaError::Truncated {
                context: "legacy header",
                ..
            })
        ));
        assert_eq!(
            parse_metadata(b"xot a dta"),
            Err(DtaError::InvalidSignature)
        );
    }
}
