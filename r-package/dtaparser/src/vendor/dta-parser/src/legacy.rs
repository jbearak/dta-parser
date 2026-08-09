use crate::endian::{checked_add, checked_mul, read_i32, read_u16, slice_at};
use crate::text::{field_bytes, is_dataset_note, TextEncoding};
use crate::{
    ByteOrder, DtaError, DtaMetadata, DtaType, FormatVersion, SectionOffsets, VariableInfo,
};

pub(crate) const HEADER_SIZE: usize = 109;
pub(crate) const VARNAME_WIDTH: usize = 33;
pub(crate) const SORTLIST_WIDTH: usize = 2;
pub(crate) const VALUE_LABEL_NAME_WIDTH: usize = 33;
pub(crate) const VARIABLE_LABEL_WIDTH: usize = 81;

pub(crate) fn format_width(version: FormatVersion) -> usize {
    if matches!(version, FormatVersion::V111 | FormatVersion::V113) {
        12
    } else {
        49
    }
}

fn decode_field(bytes: &[u8], encoding: TextEncoding) -> String {
    encoding.decode(field_bytes(bytes))
}

pub(crate) fn legacy_type(code: u8, version: FormatVersion) -> Result<(DtaType, u32), DtaError> {
    let value = match code {
        251 => (DtaType::Byte, 1),
        252 => (DtaType::Int, 2),
        253 => (DtaType::Long, 4),
        254 => (DtaType::Float, 4),
        255 => (DtaType::Double, 8),
        1..=244 => (DtaType::FixedString(u16::from(code)), u32::from(code)),
        _ => {
            return Err(DtaError::UnknownTypeCode {
                code: u16::from(code),
                version,
            })
        }
    };
    Ok(value)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct LegacyFixedOffsets {
    pub variable_types: usize,
    pub varnames: usize,
    pub sortlist: usize,
    pub formats: usize,
    pub value_label_names: usize,
    pub variable_labels: usize,
    pub end: usize,
}

pub(crate) fn legacy_fixed_offsets(
    nvar: usize,
    version: FormatVersion,
) -> Result<LegacyFixedOffsets, DtaError> {
    let variable_types = HEADER_SIZE;
    let varnames = checked_add(variable_types, nvar, "legacy variable types")?;
    let sortlist = checked_add(
        varnames,
        checked_mul(nvar, VARNAME_WIDTH, "legacy varnames")?,
        "legacy varnames",
    )?;
    let formats = checked_add(
        sortlist,
        checked_mul(
            checked_add(nvar, 1, "legacy sortlist entries")?,
            SORTLIST_WIDTH,
            "legacy sortlist",
        )?,
        "legacy sortlist",
    )?;
    let value_label_names = checked_add(
        formats,
        checked_mul(nvar, format_width(version), "legacy formats")?,
        "legacy formats",
    )?;
    let variable_labels = checked_add(
        value_label_names,
        checked_mul(nvar, VALUE_LABEL_NAME_WIDTH, "legacy value-label names")?,
        "legacy value-label names",
    )?;
    let end = checked_add(
        variable_labels,
        checked_mul(nvar, VARIABLE_LABEL_WIDTH, "legacy variable labels")?,
        "legacy variable labels",
    )?;
    Ok(LegacyFixedOffsets {
        variable_types,
        varnames,
        sortlist,
        formats,
        value_label_names,
        variable_labels,
        end,
    })
}

fn scan_expansion_fields_ordered(
    bytes: &[u8],
    start: usize,
    byte_order: ByteOrder,
    encoding: TextEncoding,
) -> Result<(usize, Vec<String>), DtaError> {
    let mut cursor = start;
    let mut notes = Vec::new();
    loop {
        let data_type = slice_at(bytes, cursor, 1, "legacy expansion-field type")?[0];
        let length_offset = checked_add(cursor, 1, "legacy expansion-field length")?;
        let value = read_i32(
            bytes,
            length_offset,
            byte_order,
            "legacy expansion-field length",
        )?;
        if data_type == 0 && value == 0 {
            return Ok((
                checked_add(cursor, 5, "legacy expansion-field terminator")?,
                notes,
            ));
        }
        if value < 0 {
            return Err(DtaError::NegativeExpansionLength {
                value,
                offset: length_offset,
            });
        }
        if data_type == 0 {
            return Err(DtaError::InvalidExpansionTerminator {
                value,
                offset: cursor,
            });
        }
        let length = usize::try_from(value)
            .map_err(|_| DtaError::ArithmeticOverflow("legacy expansion-field length"))?;
        cursor = checked_add(cursor, 5, "legacy expansion-field header")?;
        let payload = slice_at(bytes, cursor, length, "legacy expansion-field payload")?;
        if data_type == 1 && payload.len() >= 2 * VARNAME_WIDTH {
            let (variable, remainder) = payload.split_at(VARNAME_WIDTH);
            let (characteristic, value) = remainder.split_at(VARNAME_WIDTH);
            if is_dataset_note(variable, characteristic) {
                let note = encoding.decode(field_bytes(value));
                if !note.is_empty() {
                    notes.push(note);
                }
            }
        }
        cursor = checked_add(cursor, length, "legacy expansion-field payload")?;
    }
}

pub(crate) fn parse_legacy_metadata(
    bytes: &[u8],
    file_length: u64,
    encoding: TextEncoding,
) -> Result<DtaMetadata, DtaError> {
    slice_at(bytes, 0, HEADER_SIZE, "legacy header")?;
    let version = FormatVersion::try_from(u16::from(bytes[0]))
        .map_err(|_| DtaError::InvalidRelease(bytes[0].to_string()))?;
    if version.is_modern() {
        return Err(DtaError::InvalidSignature);
    }
    let byte_order = match bytes[1] {
        1 => ByteOrder::Msf,
        2 => ByteOrder::Lsf,
        other => return Err(DtaError::InvalidByteOrder(format!("0x{other:02x}"))),
    };
    if bytes[2] != 1 {
        return Err(DtaError::InvalidFileType(bytes[2]));
    }
    let nvar = u32::from(read_u16(bytes, 4, byte_order, "legacy variable count")?);
    let nobs_signed = read_i32(bytes, 6, byte_order, "legacy observation count")?;
    if nobs_signed < 0 {
        return Err(DtaError::NegativeObservationCount(nobs_signed));
    }
    let nobs = u64::try_from(nobs_signed)
        .map_err(|_| DtaError::ArithmeticOverflow("legacy observation count"))?;
    let nvar_usize =
        usize::try_from(nvar).map_err(|_| DtaError::ArithmeticOverflow("legacy variable count"))?;
    let fixed = legacy_fixed_offsets(nvar_usize, version)?;
    let expansion_start = fixed.end;
    slice_at(bytes, 0, expansion_start, "legacy fixed metadata sections")?;
    let resolved_encoding = encoding.resolve(version);
    let (data_offset, notes) =
        scan_expansion_fields_ordered(bytes, expansion_start, byte_order, resolved_encoding)?;
    parse_legacy_metadata_layout(
        bytes,
        file_length,
        data_offset,
        version,
        byte_order,
        nvar,
        nobs,
        resolved_encoding,
        notes,
    )
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn parse_legacy_metadata_layout(
    bytes: &[u8],
    file_length: u64,
    data_offset: usize,
    version: FormatVersion,
    byte_order: ByteOrder,
    nvar: u32,
    nobs: u64,
    encoding: TextEncoding,
    notes: Vec<String>,
) -> Result<DtaMetadata, DtaError> {
    let nvar_usize =
        usize::try_from(nvar).map_err(|_| DtaError::ArithmeticOverflow("legacy variable count"))?;
    let fixed = legacy_fixed_offsets(nvar_usize, version)?;
    let expansion_start = fixed.end;
    if data_offset < checked_add(expansion_start, 5, "legacy expansion terminator")? {
        return Err(DtaError::MissingExpansionTerminator);
    }
    slice_at(bytes, 0, expansion_start, "legacy fixed metadata sections")?;

    let dataset_label = decode_field(slice_at(bytes, 10, 81, "legacy dataset label")?, encoding);
    let type_codes = slice_at(
        bytes,
        fixed.variable_types,
        nvar_usize,
        "legacy variable types",
    )?;
    let mut variables = Vec::with_capacity(nvar_usize);
    let mut byte_offset = 0_u64;
    for (index, &code) in type_codes.iter().enumerate() {
        let name_at = checked_add(
            fixed.varnames,
            checked_mul(index, VARNAME_WIDTH, "legacy varname offset")?,
            "legacy varname offset",
        )?;
        let format_at = checked_add(
            fixed.formats,
            checked_mul(index, format_width(version), "legacy format offset")?,
            "legacy format offset",
        )?;
        let value_label_at = checked_add(
            fixed.value_label_names,
            checked_mul(
                index,
                VALUE_LABEL_NAME_WIDTH,
                "legacy value-label name offset",
            )?,
            "legacy value-label name offset",
        )?;
        let label_at = checked_add(
            fixed.variable_labels,
            checked_mul(index, VARIABLE_LABEL_WIDTH, "legacy variable-label offset")?,
            "legacy variable-label offset",
        )?;
        let (dta_type, byte_width) = legacy_type(code, version)?;
        variables.push(VariableInfo {
            name: decode_field(
                slice_at(bytes, name_at, VARNAME_WIDTH, "legacy varname")?,
                encoding,
            ),
            dta_type,
            type_code: u16::from(code),
            format: decode_field(
                slice_at(
                    bytes,
                    format_at,
                    format_width(version),
                    "legacy display format",
                )?,
                encoding,
            ),
            label: decode_field(
                slice_at(
                    bytes,
                    label_at,
                    VARIABLE_LABEL_WIDTH,
                    "legacy variable label",
                )?,
                encoding,
            ),
            value_label_name: decode_field(
                slice_at(
                    bytes,
                    value_label_at,
                    VALUE_LABEL_NAME_WIDTH,
                    "legacy value-label name",
                )?,
                encoding,
            ),
            byte_width,
            byte_offset,
        });
        byte_offset = byte_offset
            .checked_add(u64::from(byte_width))
            .ok_or(DtaError::ArithmeticOverflow("legacy observation length"))?;
    }

    let data = u64::try_from(data_offset)
        .map_err(|_| DtaError::ArithmeticOverflow("legacy data offset"))?;
    let observation_bytes = nobs
        .checked_mul(byte_offset)
        .ok_or(DtaError::ArithmeticOverflow(
            "legacy observation data length",
        ))?;
    let value_labels = data
        .checked_add(observation_bytes)
        .ok_or(DtaError::ArithmeticOverflow("legacy value-label offset"))?;
    if value_labels > file_length {
        let offset = data_offset;
        let needed = usize::try_from(observation_bytes).unwrap_or(usize::MAX);
        let available = usize::try_from(file_length.saturating_sub(data)).unwrap_or(usize::MAX);
        return Err(DtaError::Truncated {
            context: "legacy observation data",
            offset,
            needed,
            available,
        });
    }

    let to_u64 = |offset: usize, context: &'static str| {
        u64::try_from(offset).map_err(|_| DtaError::ArithmeticOverflow(context))
    };
    Ok(DtaMetadata {
        format_version: version,
        byte_order,
        nvar,
        nobs,
        dataset_label,
        notes,
        variables,
        section_offsets: SectionOffsets {
            stata_data: 0,
            map: 0,
            variable_types: to_u64(fixed.variable_types, "legacy variable_types offset")?,
            varnames: to_u64(fixed.varnames, "legacy varnames offset")?,
            sortlist: to_u64(fixed.sortlist, "legacy sortlist offset")?,
            formats: to_u64(fixed.formats, "legacy formats offset")?,
            value_label_names: to_u64(fixed.value_label_names, "legacy value_label_names offset")?,
            variable_labels: to_u64(fixed.variable_labels, "legacy variable_labels offset")?,
            characteristics: to_u64(expansion_start, "legacy characteristics offset")?,
            data,
            strls: value_labels,
            value_labels,
            stata_data_close: file_length,
            end_of_file: file_length,
        },
        obs_length: byte_offset,
    })
}
