use crate::endian::{checked_add, checked_mul, read_i32, read_u16, slice_at};
use crate::text::{decode_windows_1252, field_bytes};
use crate::{
    ByteOrder, DtaError, DtaMetadata, DtaType, FormatVersion, SectionOffsets, VariableInfo,
};

pub(crate) const HEADER_SIZE: usize = 109;
pub(crate) const VARNAME_WIDTH: usize = 33;
pub(crate) const SORTLIST_WIDTH: usize = 2;
pub(crate) const VALUE_LABEL_NAME_WIDTH: usize = 33;
pub(crate) const VARIABLE_LABEL_WIDTH: usize = 81;

pub(crate) fn format_width(version: FormatVersion) -> usize {
    if version == FormatVersion::V113 {
        12
    } else {
        49
    }
}

fn decode_field(bytes: &[u8]) -> String {
    decode_windows_1252(field_bytes(bytes))
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

pub(crate) fn legacy_fixed_metadata_end(
    nvar: usize,
    version: FormatVersion,
) -> Result<usize, DtaError> {
    let mut cursor = HEADER_SIZE;
    cursor = checked_add(cursor, nvar, "legacy variable types")?;
    cursor = checked_add(
        cursor,
        checked_mul(nvar, VARNAME_WIDTH, "legacy varnames")?,
        "legacy varnames",
    )?;
    cursor = checked_add(
        cursor,
        checked_mul(
            checked_add(nvar, 1, "legacy sortlist entries")?,
            SORTLIST_WIDTH,
            "legacy sortlist",
        )?,
        "legacy sortlist",
    )?;
    cursor = checked_add(
        cursor,
        checked_mul(nvar, format_width(version), "legacy formats")?,
        "legacy formats",
    )?;
    cursor = checked_add(
        cursor,
        checked_mul(nvar, VALUE_LABEL_NAME_WIDTH, "legacy value-label names")?,
        "legacy value-label names",
    )?;
    checked_add(
        cursor,
        checked_mul(nvar, VARIABLE_LABEL_WIDTH, "legacy variable labels")?,
        "legacy variable labels",
    )
}

fn scan_expansion_fields_ordered(
    bytes: &[u8],
    start: usize,
    byte_order: ByteOrder,
) -> Result<usize, DtaError> {
    let mut cursor = start;
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
            return checked_add(cursor, 5, "legacy expansion-field terminator");
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
        slice_at(bytes, cursor, length, "legacy expansion-field payload")?;
        cursor = checked_add(cursor, length, "legacy expansion-field payload")?;
    }
}

pub(crate) fn parse_legacy_metadata(
    bytes: &[u8],
    file_length: u64,
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
    let expansion_start = legacy_fixed_metadata_end(nvar_usize, version)?;
    slice_at(bytes, 0, expansion_start, "legacy fixed metadata sections")?;
    let data_offset = scan_expansion_fields_ordered(bytes, expansion_start, byte_order)?;
    parse_legacy_metadata_layout(
        bytes,
        file_length,
        data_offset,
        version,
        byte_order,
        nvar,
        nobs,
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
) -> Result<DtaMetadata, DtaError> {
    let nvar_usize =
        usize::try_from(nvar).map_err(|_| DtaError::ArithmeticOverflow("legacy variable count"))?;
    let expansion_start = legacy_fixed_metadata_end(nvar_usize, version)?;
    if data_offset < checked_add(expansion_start, 5, "legacy expansion terminator")? {
        return Err(DtaError::MissingExpansionTerminator);
    }
    slice_at(bytes, 0, expansion_start, "legacy fixed metadata sections")?;

    let dataset_label = decode_field(slice_at(bytes, 10, 81, "legacy dataset label")?);
    let variable_types_offset = HEADER_SIZE;
    let varnames_offset = checked_add(variable_types_offset, nvar_usize, "legacy varnames")?;
    let sortlist_offset = checked_add(
        varnames_offset,
        checked_mul(nvar_usize, VARNAME_WIDTH, "legacy varnames")?,
        "legacy sortlist",
    )?;
    let formats_offset = checked_add(
        sortlist_offset,
        checked_mul(
            checked_add(nvar_usize, 1, "legacy sortlist entries")?,
            SORTLIST_WIDTH,
            "legacy sortlist",
        )?,
        "legacy formats",
    )?;
    let value_label_names_offset = checked_add(
        formats_offset,
        checked_mul(nvar_usize, format_width(version), "legacy formats")?,
        "legacy value-label names",
    )?;
    let variable_labels_offset = checked_add(
        value_label_names_offset,
        checked_mul(
            nvar_usize,
            VALUE_LABEL_NAME_WIDTH,
            "legacy value-label names",
        )?,
        "legacy variable labels",
    )?;

    let type_codes = slice_at(
        bytes,
        variable_types_offset,
        nvar_usize,
        "legacy variable types",
    )?;
    let mut variables = Vec::with_capacity(nvar_usize);
    let mut byte_offset = 0_u64;
    for (index, &code) in type_codes.iter().enumerate() {
        let name_at = checked_add(
            varnames_offset,
            checked_mul(index, VARNAME_WIDTH, "legacy varname offset")?,
            "legacy varname offset",
        )?;
        let format_at = checked_add(
            formats_offset,
            checked_mul(index, format_width(version), "legacy format offset")?,
            "legacy format offset",
        )?;
        let value_label_at = checked_add(
            value_label_names_offset,
            checked_mul(
                index,
                VALUE_LABEL_NAME_WIDTH,
                "legacy value-label name offset",
            )?,
            "legacy value-label name offset",
        )?;
        let label_at = checked_add(
            variable_labels_offset,
            checked_mul(index, VARIABLE_LABEL_WIDTH, "legacy variable-label offset")?,
            "legacy variable-label offset",
        )?;
        let (dta_type, byte_width) = legacy_type(code, version)?;
        variables.push(VariableInfo {
            name: decode_field(slice_at(bytes, name_at, VARNAME_WIDTH, "legacy varname")?),
            dta_type,
            type_code: u16::from(code),
            format: decode_field(slice_at(
                bytes,
                format_at,
                format_width(version),
                "legacy display format",
            )?),
            label: decode_field(slice_at(
                bytes,
                label_at,
                VARIABLE_LABEL_WIDTH,
                "legacy variable label",
            )?),
            value_label_name: decode_field(slice_at(
                bytes,
                value_label_at,
                VALUE_LABEL_NAME_WIDTH,
                "legacy value-label name",
            )?),
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
        variables,
        section_offsets: SectionOffsets {
            stata_data: 0,
            map: 0,
            variable_types: to_u64(variable_types_offset, "legacy variable_types offset")?,
            varnames: to_u64(varnames_offset, "legacy varnames offset")?,
            sortlist: to_u64(sortlist_offset, "legacy sortlist offset")?,
            formats: to_u64(formats_offset, "legacy formats offset")?,
            value_label_names: to_u64(value_label_names_offset, "legacy value_label_names offset")?,
            variable_labels: to_u64(variable_labels_offset, "legacy variable_labels offset")?,
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
