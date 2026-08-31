use crate::endian::{checked_add, checked_mul, read_i16, read_i32, read_u16, slice_at};
use crate::stata_metadata::{
    validate_raw_value_bytes, validate_raw_value_length, CharacteristicCollector,
    CharacteristicPlan, CharacteristicValueUse, VariableTargetIndexes,
};
use crate::text::{field_bytes, TextEncoding};
use crate::{
    ByteOrder, DtaError, DtaMetadata, DtaType, FormatVersion, SectionOffsets, VariableInfo,
};

pub(crate) const SORTLIST_WIDTH: usize = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum LegacyValueLabelLayout {
    Fixed8,
    OffsetTable,
}

/// Release-specific widths for the sequential (pre-117) file layout.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct LegacyLayout {
    pub header_size: usize,
    pub dataset_label_width: usize,
    pub varname_width: usize,
    pub format_width: usize,
    pub value_label_name_width: usize,
    pub variable_label_width: usize,
    pub expansion_length_width: usize,
    pub value_label_table_name_width: usize,
    pub value_label_layout: LegacyValueLabelLayout,
    pub uses_old_type_codes: bool,
}

impl LegacyLayout {
    pub(crate) fn for_version(version: FormatVersion) -> Self {
        match version {
            FormatVersion::V105 => Self {
                header_size: 60,
                dataset_label_width: 32,
                varname_width: 9,
                format_width: 12,
                value_label_name_width: 9,
                variable_label_width: 32,
                expansion_length_width: 2,
                value_label_table_name_width: 9,
                value_label_layout: LegacyValueLabelLayout::Fixed8,
                uses_old_type_codes: true,
            },
            FormatVersion::V108 => Self {
                header_size: 109,
                dataset_label_width: 81,
                varname_width: 9,
                format_width: 12,
                value_label_name_width: 9,
                variable_label_width: 81,
                expansion_length_width: 2,
                value_label_table_name_width: 9,
                value_label_layout: LegacyValueLabelLayout::OffsetTable,
                uses_old_type_codes: true,
            },
            FormatVersion::V110 => Self {
                header_size: 109,
                dataset_label_width: 81,
                varname_width: 33,
                format_width: 12,
                value_label_name_width: 33,
                variable_label_width: 81,
                expansion_length_width: 4,
                value_label_table_name_width: 33,
                value_label_layout: LegacyValueLabelLayout::OffsetTable,
                uses_old_type_codes: true,
            },
            FormatVersion::V111 | FormatVersion::V113 => Self {
                header_size: 109,
                dataset_label_width: 81,
                varname_width: 33,
                format_width: 12,
                value_label_name_width: 33,
                variable_label_width: 81,
                expansion_length_width: 4,
                value_label_table_name_width: 33,
                value_label_layout: LegacyValueLabelLayout::OffsetTable,
                uses_old_type_codes: false,
            },
            FormatVersion::V114 | FormatVersion::V115 => Self {
                header_size: 109,
                dataset_label_width: 81,
                varname_width: 33,
                format_width: 49,
                value_label_name_width: 33,
                variable_label_width: 81,
                expansion_length_width: 4,
                value_label_table_name_width: 33,
                value_label_layout: LegacyValueLabelLayout::OffsetTable,
                uses_old_type_codes: false,
            },
            FormatVersion::V117 | FormatVersion::V118 | FormatVersion::V119 => {
                unreachable!("modern releases do not use a legacy layout")
            }
        }
    }

    pub(crate) const fn expansion_header_width(self) -> usize {
        1 + self.expansion_length_width
    }
}

fn decode_field(bytes: &[u8], encoding: TextEncoding) -> String {
    encoding.decode(field_bytes(bytes))
}

pub(crate) fn legacy_type(code: u8, version: FormatVersion) -> Result<(DtaType, u32), DtaError> {
    let layout = LegacyLayout::for_version(version);
    let value = if layout.uses_old_type_codes {
        match code {
            b'b' => (DtaType::Byte, 1),
            b'i' => (DtaType::Int, 2),
            b'l' => (DtaType::Long, 4),
            b'f' => (DtaType::Float, 4),
            b'd' => (DtaType::Double, 8),
            0x80..=0xff => {
                let width = u16::from(code - 0x7f);
                (DtaType::FixedString(width), u32::from(width))
            }
            _ => {
                return Err(DtaError::UnknownTypeCode {
                    code: u16::from(code),
                    version,
                })
            }
        }
    } else {
        match code {
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
    let layout = LegacyLayout::for_version(version);
    let variable_types = layout.header_size;
    let varnames = checked_add(variable_types, nvar, "legacy variable types")?;
    let sortlist = checked_add(
        varnames,
        checked_mul(nvar, layout.varname_width, "legacy varnames")?,
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
        checked_mul(nvar, layout.format_width, "legacy formats")?,
        "legacy formats",
    )?;
    let variable_labels = checked_add(
        value_label_names,
        checked_mul(
            nvar,
            layout.value_label_name_width,
            "legacy value-label names",
        )?,
        "legacy value-label names",
    )?;
    let end = checked_add(
        variable_labels,
        checked_mul(nvar, layout.variable_label_width, "legacy variable labels")?,
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
    layout: LegacyLayout,
    variables: &[VariableInfo],
) -> Result<(usize, Option<CharacteristicCollector>), DtaError> {
    // Frame the complete expansion section before validating metadata values.
    // A second bounded pass folds accepted records directly into the compact
    // characteristic plan instead of retaining one descriptor per record.
    let data_offset = walk_expansion_fields(bytes, start, byte_order, layout, |_, _, _| Ok(()))?;
    let mut plan = CharacteristicPlan::<(usize, usize)>::default();
    let mut variable_indexes = VariableTargetIndexes::new(variables);
    let mut ordinal = 0_usize;
    let folded_data_offset = walk_expansion_fields(
        bytes,
        start,
        byte_order,
        layout,
        |data_type, cursor, payload| {
            if data_type != 1 || payload.len() < 2 * layout.varname_width {
                return Ok(());
            }
            let (variable, remainder) = payload.split_at(layout.varname_width);
            let (characteristic, value) = remainder.split_at(layout.varname_width);
            let target = encoding.decode(field_bytes(variable));
            let name = encoding.decode(field_bytes(characteristic));
            let value_offset = cursor + 2 * layout.varname_width;
            plan.push_record(
                ordinal,
                &target,
                name,
                cursor + layout.varname_width,
                |target| variable_indexes.resolve(target),
                |value_use| match value_use {
                    CharacteristicValueUse::Skip => Ok(None),
                    CharacteristicValueUse::Retain => {
                        validate_raw_value_length(
                            value.len(),
                            value_offset,
                            "legacy characteristic value",
                        )?;
                        let value = validate_raw_value_bytes(
                            value,
                            value_offset,
                            "legacy characteristic value",
                        )?;
                        Ok(Some((value_offset, value.len())))
                    }
                    CharacteristicValueUse::Validate => {
                        validate_raw_value_length(
                            value.len(),
                            value_offset,
                            "legacy characteristic value",
                        )?;
                        validate_raw_value_bytes(
                            value,
                            value_offset,
                            "legacy characteristic value",
                        )?;
                        Ok(None)
                    }
                },
            )?;
            ordinal = ordinal.checked_add(1).ok_or(DtaError::ArithmeticOverflow(
                "legacy characteristic record count",
            ))?;
            Ok(())
        },
    )?;
    debug_assert_eq!(folded_data_offset, data_offset);
    drop(variable_indexes);
    Ok((
        data_offset,
        Some(plan.decode(|(offset, length)| {
            Ok(encoding.decode(slice_at(
                bytes,
                offset,
                length,
                "legacy characteristic value",
            )?))
        })?),
    ))
}

fn walk_expansion_fields<F>(
    bytes: &[u8],
    start: usize,
    byte_order: ByteOrder,
    layout: LegacyLayout,
    mut visit: F,
) -> Result<usize, DtaError>
where
    F: FnMut(u8, usize, &[u8]) -> Result<(), DtaError>,
{
    let mut cursor = start;
    loop {
        let data_type = slice_at(bytes, cursor, 1, "legacy expansion-field type")?[0];
        let length_offset = checked_add(cursor, 1, "legacy expansion-field length")?;
        let value = if layout.expansion_length_width == 2 {
            i32::from(read_i16(
                bytes,
                length_offset,
                byte_order,
                "legacy expansion-field length",
            )?)
        } else {
            read_i32(
                bytes,
                length_offset,
                byte_order,
                "legacy expansion-field length",
            )?
        };
        if data_type == 0 && value == 0 {
            return checked_add(
                cursor,
                layout.expansion_header_width(),
                "legacy expansion-field terminator",
            );
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
        cursor = checked_add(
            cursor,
            layout.expansion_header_width(),
            "legacy expansion-field header",
        )?;
        let payload = slice_at(bytes, cursor, length, "legacy expansion-field payload")?;
        visit(data_type, cursor, payload)?;
        cursor = checked_add(cursor, length, "legacy expansion-field payload")?;
    }
}

pub(crate) fn parse_legacy_metadata(
    bytes: &[u8],
    file_length: u64,
    encoding: TextEncoding,
) -> Result<DtaMetadata, DtaError> {
    let release = *slice_at(bytes, 0, 1, "legacy release")?
        .first()
        .expect("one-byte release slice");
    let version = FormatVersion::try_from(u16::from(release))
        .map_err(|_| DtaError::InvalidRelease(release.to_string()))?;
    if version.is_modern() {
        return Err(DtaError::InvalidSignature);
    }
    let layout = LegacyLayout::for_version(version);
    slice_at(bytes, 0, layout.header_size, "legacy header")?;
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
    let varname_bytes = slice_at(
        bytes,
        fixed.varnames,
        checked_mul(nvar_usize, layout.varname_width, "legacy varnames length")?,
        "legacy varnames",
    )?;
    let dataset_label = decode_field(
        slice_at(
            bytes,
            10,
            layout.dataset_label_width,
            "legacy dataset label",
        )?,
        resolved_encoding,
    );
    let type_codes = slice_at(
        bytes,
        fixed.variable_types,
        nvar_usize,
        "legacy variable types",
    )?;
    let mut variables = Vec::with_capacity(nvar_usize);
    let mut byte_offset = 0_u64;
    for ((index, &code), name) in type_codes
        .iter()
        .enumerate()
        .zip(varname_bytes.chunks_exact(layout.varname_width))
    {
        let format_at = checked_add(
            fixed.formats,
            checked_mul(index, layout.format_width, "legacy format offset")?,
            "legacy format offset",
        )?;
        let value_label_at = checked_add(
            fixed.value_label_names,
            checked_mul(
                index,
                layout.value_label_name_width,
                "legacy value-label name offset",
            )?,
            "legacy value-label name offset",
        )?;
        let label_at = checked_add(
            fixed.variable_labels,
            checked_mul(
                index,
                layout.variable_label_width,
                "legacy variable-label offset",
            )?,
            "legacy variable-label offset",
        )?;
        let (dta_type, byte_width) = legacy_type(code, version)?;
        variables.push(VariableInfo {
            name: resolved_encoding.decode(field_bytes(name)),
            dta_type,
            type_code: u16::from(code),
            format: decode_field(
                slice_at(
                    bytes,
                    format_at,
                    layout.format_width,
                    "legacy display format",
                )?,
                resolved_encoding,
            ),
            label: decode_field(
                slice_at(
                    bytes,
                    label_at,
                    layout.variable_label_width,
                    "legacy variable label",
                )?,
                resolved_encoding,
            ),
            value_label_name: decode_field(
                slice_at(
                    bytes,
                    value_label_at,
                    layout.value_label_name_width,
                    "legacy value-label name",
                )?,
                resolved_encoding,
            ),
            notes: Vec::new(),
            characteristics: Vec::new(),
            byte_width,
            byte_offset,
        });
        byte_offset = byte_offset
            .checked_add(u64::from(byte_width))
            .ok_or(DtaError::ArithmeticOverflow("legacy observation length"))?;
    }

    let (data_offset, collector) = scan_expansion_fields_ordered(
        bytes,
        expansion_start,
        byte_order,
        resolved_encoding,
        layout,
        &variables,
    )?;

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
    let mut notes = Vec::new();
    let mut characteristics = Vec::new();
    if let Some(collector) = collector {
        collector.finish(&mut notes, &mut characteristics, &mut variables);
    }

    Ok(DtaMetadata {
        format_version: version,
        byte_order,
        nvar,
        nobs,
        dataset_label,
        notes,
        characteristics,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unterminated_legacy_characteristics_are_framed_before_values_are_decoded() {
        let layout = LegacyLayout::for_version(FormatVersion::V115);
        let value_length = crate::stata_metadata::MAX_METADATA_VALUE_BYTES + 2;
        let payload_length = layout.varname_width * 2 + value_length;
        let mut bytes = vec![1];
        bytes.extend_from_slice(&(payload_length as i32).to_le_bytes());
        let mut target = vec![0; layout.varname_width];
        target[..4].copy_from_slice(b"_dta");
        bytes.extend_from_slice(&target);
        let mut name = vec![0; layout.varname_width];
        name[..6].copy_from_slice(b"source");
        bytes.extend_from_slice(&name);
        bytes.extend(std::iter::repeat_n(b'x', value_length));

        assert!(matches!(
            scan_expansion_fields_ordered(
                &bytes,
                0,
                ByteOrder::Lsf,
                TextEncoding::Utf8,
                layout,
                &[],
            ),
            Err(DtaError::Truncated {
                context: "legacy expansion-field type",
                ..
            })
        ));
    }

    #[test]
    fn pre111_string_codes_cover_widths_one_through_128() {
        assert_eq!(
            legacy_type(0x80, FormatVersion::V105).unwrap(),
            (DtaType::FixedString(1), 1)
        );
        assert_eq!(
            legacy_type(0xff, FormatVersion::V110).unwrap(),
            (DtaType::FixedString(128), 128)
        );
        assert!(matches!(
            legacy_type(0x7f, FormatVersion::V108),
            Err(DtaError::UnknownTypeCode { code: 0x7f, .. })
        ));
    }
}
