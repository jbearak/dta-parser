use crate::endian::{checked_add, checked_mul, read_u16, read_u32, read_u64, read_u8, slice_at};
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

const SECTION_MAP_ENTRIES: usize = 14;

#[derive(Clone, Copy)]
struct FieldWidths {
    varname: usize,
    format: usize,
    value_label_name: usize,
    variable_label: usize,
}

fn field_widths(version: FormatVersion) -> FieldWidths {
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
        FormatVersion::V113 | FormatVersion::V114 | FormatVersion::V115 => {
            unreachable!("legacy releases are rejected before widths are selected")
        }
    }
}

fn expect_at(
    bytes: &[u8],
    offset: usize,
    tag: &'static [u8],
    expected: &'static str,
) -> Result<usize, DtaError> {
    let actual = slice_at(bytes, offset, tag.len(), expected)?;
    if actual != tag {
        return Err(DtaError::UnexpectedTag { expected, offset });
    }
    checked_add(offset, tag.len(), expected)
}

fn parse_release(bytes: &[u8]) -> Result<(FormatVersion, usize), DtaError> {
    if matches!(bytes.first(), Some(113..=115)) {
        let version = FormatVersion::try_from(u16::from(bytes[0]))
            .expect("the matched legacy release is represented");
        return Err(DtaError::UnsupportedRelease(version));
    }
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
    let label =
        String::from_utf8_lossy(slice_at(bytes, cursor, length, "dataset label")?).into_owned();
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

    ensure_next_offset("variable_types", after_map, offsets.variable_types)
}

fn offset_to_usize(offset: u64, context: &'static str) -> Result<usize, DtaError> {
    usize::try_from(offset).map_err(|_| DtaError::OffsetOutOfRange { context, offset })
}

fn ensure_next_offset(section: &'static str, expected: usize, actual: u64) -> Result<(), DtaError> {
    let expected = u64::try_from(expected).map_err(|_| DtaError::OffsetOutOfRange {
        context: section,
        offset: u64::MAX,
    })?;
    if actual != expected {
        return Err(DtaError::MapOffsetMismatch {
            section,
            expected,
            actual,
        });
    }
    Ok(())
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
    ensure_next_offset("varnames", cursor, offsets.varnames)?;
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
        strings.push(String::from_utf8_lossy(&field[..nul]).into_owned());
    }

    cursor = checked_add(cursor, payload_length, "string section length")?;
    cursor = expect_at(bytes, cursor, section.close, section.close_name)?;
    ensure_next_offset(section.next_name, cursor, section.next_offset)?;
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
    ensure_next_offset("formats", cursor, offsets.formats)
}

fn resolve_type(code: u16, version: FormatVersion) -> Result<(DtaType, u32), DtaError> {
    let numeric = match code {
        65530 => Some((DtaType::Byte, 1)),
        65529 => Some((DtaType::Int, 2)),
        65528 => Some((DtaType::Long, 4)),
        65527 => Some((DtaType::Float, 4)),
        65526 => Some((DtaType::Double, 8)),
        251 if version == FormatVersion::V117 => Some((DtaType::Byte, 1)),
        252 if version == FormatVersion::V117 => Some((DtaType::Int, 2)),
        253 if version == FormatVersion::V117 => Some((DtaType::Long, 4)),
        254 if version == FormatVersion::V117 => Some((DtaType::Float, 4)),
        255 if version == FormatVersion::V117 => Some((DtaType::Double, 8)),
        _ => None,
    };
    if let Some(resolved) = numeric {
        return Ok(resolved);
    }
    if code == 32768 {
        return Ok((DtaType::StrL, 8));
    }

    let maximum = if version == FormatVersion::V117 {
        244
    } else {
        2045
    };
    if (1..=maximum).contains(&code) {
        return Ok((DtaType::FixedString(code), u32::from(code)));
    }
    Err(DtaError::UnknownTypeCode { code, version })
}

/// Parse metadata from a Stata 117, 118, or 119 byte slice.
///
/// The slice may contain the full file or end immediately after the
/// `variable_labels` section. Section-map offsets for observation data and
/// later payloads are retained but are not dereferenced by this metadata-only
/// parser.
pub fn parse_metadata(bytes: &[u8]) -> Result<DtaMetadata, DtaError> {
    let (format_version, cursor) = parse_release(bytes)?;
    let (byte_order, cursor) = parse_byte_order(bytes, cursor)?;
    let (nvar, nobs, cursor) = parse_counts(bytes, format_version, byte_order, cursor)?;
    let (dataset_label, map_start) =
        parse_length_prefixed_text(bytes, format_version, byte_order, cursor)?;
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
            byte_width,
            byte_offset,
        });
        byte_offset = byte_offset
            .checked_add(u64::from(byte_width))
            .ok_or(DtaError::ArithmeticOverflow("observation length"))?;
    }

    Ok(DtaMetadata {
        format_version,
        byte_order,
        nvar,
        nobs,
        dataset_label,
        variables,
        section_offsets,
        obs_length: byte_offset,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enforces_type_boundaries_by_release() {
        assert_eq!(
            resolve_type(244, FormatVersion::V117).unwrap(),
            (DtaType::FixedString(244), 244)
        );
        assert!(matches!(
            resolve_type(245, FormatVersion::V117),
            Err(DtaError::UnknownTypeCode { code: 245, .. })
        ));
        assert_eq!(
            resolve_type(2045, FormatVersion::V119).unwrap(),
            (DtaType::FixedString(2045), 2045)
        );
        assert!(resolve_type(2046, FormatVersion::V118).is_err());
        assert_eq!(
            resolve_type(251, FormatVersion::V117).unwrap(),
            (DtaType::Byte, 1)
        );
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
    fn rejects_legacy_and_unknown_signatures_without_panicking() {
        assert_eq!(
            parse_metadata(&[115]),
            Err(DtaError::UnsupportedRelease(FormatVersion::V115))
        );
        assert_eq!(
            parse_metadata(b"not a dta"),
            Err(DtaError::InvalidSignature)
        );
    }
}
