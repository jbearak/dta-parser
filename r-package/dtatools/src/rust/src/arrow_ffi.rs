//! FFI adapters for the dtatools Arrow profile: `dtatools_save_arrow_rust`,
//! `dtatools_read_arrow_rust`, and `dtatools_arrow_metadata_rust`, mirroring
//! the DTA entry points. The C layer validates R types and passes direct data
//! pointers; character data crosses through the string region callback.

use std::ffi::CStr;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::sync::Arc;

use dta_tools::arrow::{
    read_arrow_file, save_arrow_file, summarize_arrow_file, ArrowCompression,
    ArrowFieldDocument, ArrowMissingEncoding, ArrowRSemantics, ArrowReadColumn,
    ArrowReadOptions, ArrowWriteColumn, ArrowWriteDataset, DatasetDocument, StataStorage,
    ARROW_ROWS_PER_BATCH,
};
use dta_tools::{
    classify_byte_missing_for_version, classify_double_missing_bits,
    classify_float_missing_bits_for_version, classify_int_missing_for_version,
    classify_long_missing_for_version, dta_write_numeric_value_is_representable, encode_numeric,
    DtaWriteNumericValue, DtaWriteRawNumericValue, FormatVersion, MissingTag,
    ValueLabelEntry, ValueLabelTable, VariableInfo,
};

use arrow_array::builder::{BooleanBuilder, Int32Builder, StringBuilder};
use arrow_array::{
    Array, ArrayRef, BooleanArray, Date32Array, DictionaryArray, DurationNanosecondArray,
    Float32Array, Float64Array, Int16Array, Int32Array, Int64Array, Int8Array, StringArray,
    TimestampMicrosecondArray, UInt16Array, UInt32Array, UInt64Array, UInt8Array,
};
use arrow_schema::{DataType, TimeUnit};

use crate::{
    attach_variable_attributes, boundary, check_interrupt, coarse_interrupt,
    direct_r_missing_code, fill_string_region, label_attribute, missing_from_code,
    numeric_altrep_storage, observed_value, poll_interrupt, r_char, r_missing, scalar_string,
    set_attr, set_class, set_symbol_attr, string_vector, temporal_kind, write_numeric_value,
    NumericKind, ProtectGuard, RLen, Sexp, TemporalKind, DAYS_1960_TO_1970, INTEGER, INTSXP,
    LGLSXP, LOGICAL, REAL, REALSXP, R_ClassSymbol, R_NaInt, R_NaReal, R_NaString,
    R_NamesSymbol, R_RowNamesSymbol, SECONDS_1960_TO_1970, SET_STRING_ELT, SET_VECTOR_ELT,
    STRSXP, VECSXP,
};

/// One column handed from C for `save_arrow()`. Field meanings depend on
/// `kind`; unused pointers are null and unused strings empty.
#[repr(C)]
pub struct RArrowColumnDescriptor {
    name: *const c_char,
    /// 0 logical, 1 integer, 2 double, 3 character, 4 raw, 5 factor, 6 date,
    /// 7 datetime, 8 difftime, 9 profiled Stata numeric.
    kind: c_int,
    label: *const c_char,
    format: *const c_char,
    /// -1 none; 0 byte, 1 int, 2 long, 3 float, 4 double (kind 9 only).
    storage: c_int,
    ordered: c_int,
    tz: *const c_char,
    units: *const c_char,
    /// Direct data: `int*` for logical/integer/factor codes, `double*` for
    /// double/date/datetime/difftime and eager profiled columns, `uint8_t*`
    /// for raw. Null for character columns and compact profiled columns.
    values: *const c_void,
    /// STRSXP holding character values or factor levels; null otherwise.
    strings: Sexp,
    string_count: usize,
    /// Compact ALTREP backing bytes, or null when the column is eager.
    compact_values: *const c_void,
    compact_kind: c_int,
    compact_format_version: c_int,
    compact_temporal: c_int,
    /// Value-label codes as R doubles (tagged NAs carry extended tags).
    label_values: *const f64,
    label_texts: Sexp,
    label_count: usize,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum RArrowKind {
    Logical,
    Integer,
    Double,
    Character,
    Raw,
    Factor,
    Date,
    Datetime,
    Difftime,
    StataNumeric,
}

impl TryFrom<c_int> for RArrowKind {
    type Error = String;

    fn try_from(value: c_int) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Self::Logical),
            1 => Ok(Self::Integer),
            2 => Ok(Self::Double),
            3 => Ok(Self::Character),
            4 => Ok(Self::Raw),
            5 => Ok(Self::Factor),
            6 => Ok(Self::Date),
            7 => Ok(Self::Datetime),
            8 => Ok(Self::Difftime),
            9 => Ok(Self::StataNumeric),
            _ => Err("invalid native Arrow column kind".into()),
        }
    }
}

unsafe fn optional_c_string(value: *const c_char, what: &str) -> Result<String, String> {
    if value.is_null() {
        return Ok(String::new());
    }
    CStr::from_ptr(value)
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{what} is not valid UTF-8"))
}

unsafe fn required_c_string(value: *const c_char, what: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{what} is null"));
    }
    optional_c_string(value, what)
}

/// Read a whole STRSXP into owned strings; `None` marks `NA_character_`.
unsafe fn read_strings(
    values: Sexp,
    count: usize,
    what: &str,
) -> Result<Vec<Option<String>>, String> {
    let mut result = Vec::new();
    result
        .try_reserve_exact(count)
        .map_err(|_| format!("could not allocate {what}"))?;
    let mut start = 0_usize;
    while start < count {
        check_interrupt()?;
        let length = (count - start).min(65_536);
        let region = fill_string_region(values, start, length, what)?;
        for value in region {
            result.push(value);
        }
        start += length;
    }
    Ok(result)
}

fn storage_from_code(code: c_int) -> Result<Option<StataStorage>, String> {
    match code {
        -1 => Ok(None),
        0 => Ok(Some(StataStorage::Byte)),
        1 => Ok(Some(StataStorage::Int)),
        2 => Ok(Some(StataStorage::Long)),
        3 => Ok(Some(StataStorage::Float)),
        4 => Ok(Some(StataStorage::Double)),
        _ => Err("invalid native Stata storage code".into()),
    }
}

fn field_missing_for_storage(storage: StataStorage) -> ArrowMissingEncoding {
    match storage {
        StataStorage::Byte | StataStorage::Int | StataStorage::Long => {
            ArrowMissingEncoding::Sentinel
        }
        StataStorage::Float | StataStorage::Double => ArrowMissingEncoding::Payload,
    }
}

struct ColumnPlan {
    name: String,
    field: Option<ArrowFieldDocument>,
    array: ArrayRef,
    replacements: u64,
    value_labels: Option<ValueLabelTable>,
}

unsafe fn double_slice<'a>(
    descriptor: &RArrowColumnDescriptor,
    row_count: usize,
) -> Result<&'a [f64], String> {
    if descriptor.values.is_null() {
        return Err("native Arrow column data pointer is null".to_owned());
    }
    Ok(std::slice::from_raw_parts(
        descriptor.values.cast::<f64>(),
        row_count,
    ))
}

unsafe fn int_slice<'a>(
    descriptor: &RArrowColumnDescriptor,
    row_count: usize,
) -> Result<&'a [c_int], String> {
    if descriptor.values.is_null() {
        return Err("native Arrow column data pointer is null".to_owned());
    }
    Ok(std::slice::from_raw_parts(
        descriptor.values.cast::<c_int>(),
        row_count,
    ))
}

/// Classify every value of an R double column, rejecting invalid NaNs.
fn classify_doubles(
    values: &[f64],
    name: &str,
) -> Result<(Vec<c_int>, bool), String> {
    let mut codes = Vec::new();
    codes
        .try_reserve_exact(values.len())
        .map_err(|_| "could not allocate native missing codes".to_owned())?;
    let mut has_tags = false;
    for (index, &value) in values.iter().enumerate() {
        poll_interrupt(index)?;
        let code = direct_r_missing_code(value);
        if code > c_int::from(b'z') {
            return Err(format!(
                "column `{name}` contains an unsupported NaN payload"
            ));
        }
        has_tags |= code >= c_int::from(b'a');
        codes.push(code);
    }
    Ok((codes, has_tags))
}

fn string_array(values: &[Option<String>]) -> ArrayRef {
    let mut builder = StringBuilder::new();
    for value in values {
        match value {
            Some(value) => builder.append_value(value),
            None => builder.append_null(),
        }
    }
    Arc::new(builder.finish())
}

fn r_semantics(class: &str) -> Option<ArrowRSemantics> {
    Some(ArrowRSemantics {
        class: class.to_owned(),
        ordered: None,
        tz: None,
        units: None,
    })
}

fn base_field_document(
    label: &str,
    format: &str,
) -> ArrowFieldDocument {
    ArrowFieldDocument {
        version: 0,
        label: label.to_owned(),
        format: format.to_owned(),
        ..ArrowFieldDocument::default()
    }
}

/// A Float64 array holding the R doubles verbatim, with the field document
/// marking NaN-payload missing storage. Used whenever tagged NAs must survive
/// bit-exactly.
fn payload_double_column(
    values: &[f64],
    mut field: ArrowFieldDocument,
    class: &str,
) -> (Option<ArrowFieldDocument>, ArrayRef) {
    field.missing = Some(ArrowMissingEncoding::Payload);
    field.r = r_semantics(class);
    (Some(field), Arc::new(Float64Array::from(values.to_vec())))
}

/// A nullable Float64 array: R `NA` (missing code 0) becomes an Arrow null,
/// every other value — plain NaN included — keeps its bits.
fn semantic_double_array(values: &[f64], codes: &[c_int]) -> ArrayRef {
    Arc::new(Float64Array::from_iter(
        values
            .iter()
            .zip(codes)
            .map(|(&value, &code)| (code != 0).then_some(value)),
    ))
}

fn temporal_shift_scale(temporal: TemporalKind) -> (f64, f64) {
    match temporal {
        TemporalKind::None => (0.0, 1.0),
        TemporalKind::Date => (DAYS_1960_TO_1970, 1.0),
        TemporalKind::Datetime => (SECONDS_1960_TO_1970, 1_000.0),
    }
}

/// Encode one eager profiled column into raw Stata missing storage.
fn encode_profiled_column(
    name: &str,
    storage: StataStorage,
    temporal: TemporalKind,
    values: &[f64],
    codes: &[c_int],
) -> Result<(ArrayRef, u64), String> {
    let dta_type = storage.dta_type();
    let (shift, scale) = temporal_shift_scale(temporal);
    let mut replacements = 0_u64;
    let mut encoded = Vec::new();
    encoded
        .try_reserve_exact(values.len())
        .map_err(|_| "could not allocate a profiled column".to_owned())?;
    for (index, (&value, &code)) in values.iter().zip(codes).enumerate() {
        poll_interrupt(index)?;
        let source = match missing_from_code(code)? {
            Some(tag) => DtaWriteNumericValue::Missing(tag),
            None => {
                let encoded_value = write_numeric_value(value, shift, scale);
                if dta_write_numeric_value_is_representable(&dta_type, encoded_value) {
                    DtaWriteNumericValue::Value(encoded_value)
                } else {
                    replacements += 1;
                    DtaWriteNumericValue::Missing(MissingTag::System)
                }
            }
        };
        encoded.push(encode_numeric(&dta_type, source));
    }
    let array: ArrayRef = match storage {
        StataStorage::Byte => Arc::new(Int8Array::from_iter_values(encoded.iter().map(
            |value| match value {
                DtaWriteRawNumericValue::Byte(value) => *value,
                _ => unreachable!("byte column encodes bytes"),
            },
        ))),
        StataStorage::Int => Arc::new(Int16Array::from_iter_values(encoded.iter().map(
            |value| match value {
                DtaWriteRawNumericValue::Int(value) => *value,
                _ => unreachable!("int column encodes ints"),
            },
        ))),
        StataStorage::Long => Arc::new(Int32Array::from_iter_values(encoded.iter().map(
            |value| match value {
                DtaWriteRawNumericValue::Long(value) => *value,
                _ => unreachable!("long column encodes longs"),
            },
        ))),
        StataStorage::Float => Arc::new(Float32Array::from_iter_values(encoded.iter().map(
            |value| match value {
                DtaWriteRawNumericValue::Float(value) => *value,
                _ => unreachable!("float column encodes floats"),
            },
        ))),
        StataStorage::Double => Arc::new(Float64Array::from_iter_values(encoded.iter().map(
            |value| match value {
                DtaWriteRawNumericValue::Double(value) => *value,
                _ => unreachable!("double column encodes doubles"),
            },
        ))),
    };
    let _ = name;
    Ok((array, replacements))
}

/// Copy a compact ALTREP backing into an Arrow array, normalizing legacy
/// missing encodings to the modern sentinels the profile stores.
unsafe fn compact_profiled_column(
    descriptor: &RArrowColumnDescriptor,
    row_count: usize,
) -> Result<(ArrayRef, StataStorage, TemporalKind), String> {
    let kind = NumericKind::try_from(descriptor.compact_kind)?;
    let temporal = TemporalKind::try_from(descriptor.compact_temporal)?;
    let version = u16::try_from(descriptor.compact_format_version)
        .ok()
        .and_then(|value| FormatVersion::try_from(value).ok())
        .ok_or_else(|| "invalid compact numeric format version".to_owned())?;
    if descriptor.compact_values.is_null() {
        return Err("compact numeric backing pointer is null".to_owned());
    }
    let base = descriptor.compact_values;
    let (array, storage): (ArrayRef, StataStorage) = match kind {
        NumericKind::Byte => {
            let values = std::slice::from_raw_parts(base.cast::<i8>(), row_count);
            let normalized = values.iter().enumerate().map(|(index, &value)| {
                let _ = poll_interrupt(index);
                match classify_byte_missing_for_version(value, version) {
                    Some(tag) => tag.byte_value(),
                    None => value,
                }
            });
            (
                Arc::new(Int8Array::from_iter_values(normalized)),
                StataStorage::Byte,
            )
        }
        NumericKind::Int => {
            let values = std::slice::from_raw_parts(base.cast::<i16>(), row_count);
            let normalized = values.iter().enumerate().map(|(index, &value)| {
                let _ = poll_interrupt(index);
                match classify_int_missing_for_version(value, version) {
                    Some(tag) => tag.int_value(),
                    None => value,
                }
            });
            (
                Arc::new(Int16Array::from_iter_values(normalized)),
                StataStorage::Int,
            )
        }
        NumericKind::Long => {
            let values = std::slice::from_raw_parts(base.cast::<i32>(), row_count);
            let normalized = values.iter().enumerate().map(|(index, &value)| {
                let _ = poll_interrupt(index);
                match classify_long_missing_for_version(value, version) {
                    Some(tag) => tag.long_value(),
                    None => value,
                }
            });
            (
                Arc::new(Int32Array::from_iter_values(normalized)),
                StataStorage::Long,
            )
        }
        NumericKind::Float => {
            let values = std::slice::from_raw_parts(base.cast::<f32>(), row_count);
            let normalized = values.iter().enumerate().map(|(index, &value)| {
                let _ = poll_interrupt(index);
                match classify_float_missing_bits_for_version(value.to_bits(), version) {
                    Some(tag) => f32::from_bits(tag.float_bits()),
                    None => value,
                }
            });
            (
                Arc::new(Float32Array::from_iter_values(normalized)),
                StataStorage::Float,
            )
        }
    };
    Ok((array, storage, temporal))
}

unsafe fn value_label_table(
    descriptor: &RArrowColumnDescriptor,
    name: &str,
) -> Result<Option<ValueLabelTable>, String> {
    if descriptor.label_count == 0 {
        return Ok(None);
    }
    if descriptor.label_values.is_null() {
        return Err("value-label codes pointer is null".to_owned());
    }
    let codes = std::slice::from_raw_parts(descriptor.label_values, descriptor.label_count);
    let texts = read_strings(
        descriptor.label_texts,
        descriptor.label_count,
        "value-label texts",
    )?;
    let mut entries = Vec::new();
    entries
        .try_reserve_exact(descriptor.label_count)
        .map_err(|_| "could not allocate value labels".to_owned())?;
    for (index, (&code, text)) in codes.iter().zip(&texts).enumerate() {
        poll_interrupt(index)?;
        let label = text
            .clone()
            .ok_or_else(|| format!("column `{name}` has a missing value-label text"))?;
        let entry = match missing_from_code(direct_r_missing_code(code))? {
            Some(tag) => ValueLabelEntry {
                value: 0,
                missing_tag: Some(tag),
                label,
            },
            None => {
                if code.fract() != 0.0 || code < f64::from(i32::MIN) || code > f64::from(i32::MAX)
                {
                    return Err(format!(
                        "column `{name}` has a non-integer value-label code"
                    ));
                }
                ValueLabelEntry {
                    value: code as i32,
                    missing_tag: None,
                    label,
                }
            }
        };
        entries.push(entry);
    }
    Ok(Some(ValueLabelTable {
        name: name.to_owned(),
        entries,
    }))
}

unsafe fn plan_column(
    descriptor: &RArrowColumnDescriptor,
    row_count: usize,
) -> Result<ColumnPlan, String> {
    let name = required_c_string(descriptor.name, "a column name")?;
    let kind = RArrowKind::try_from(descriptor.kind)?;
    let label = optional_c_string(descriptor.label, "a variable label")?;
    let format = optional_c_string(descriptor.format, "a display format")?;
    let tz = optional_c_string(descriptor.tz, "a time zone")?;
    let units = optional_c_string(descriptor.units, "difftime units")?;
    let value_labels = value_label_table(descriptor, &name)?;

    let base_document = base_field_document(&label, &format);
    let needs_document = |document: &ArrowFieldDocument| {
        *document != ArrowFieldDocument::default()
    };
    let with_labels = |mut document: ArrowFieldDocument| {
        if value_labels.is_some() {
            document.value_labels = Some(name.clone());
        }
        document
    };

    let (field, array, replacements): (Option<ArrowFieldDocument>, ArrayRef, u64) = match kind {
        RArrowKind::Logical => {
            let values = int_slice(descriptor, row_count)?;
            let mut builder = BooleanBuilder::with_capacity(row_count);
            for (index, &value) in values.iter().enumerate() {
                poll_interrupt(index)?;
                if value == R_NaInt {
                    builder.append_null();
                } else {
                    builder.append_value(value != 0);
                }
            }
            let document = with_labels(base_document);
            (
                needs_document(&document).then_some(document),
                Arc::new(builder.finish()),
                0,
            )
        }
        RArrowKind::Integer => {
            let values = int_slice(descriptor, row_count)?;
            let array = Int32Array::from_iter(
                values
                    .iter()
                    .map(|&value| (value != R_NaInt).then_some(value)),
            );
            let document = with_labels(base_document);
            (
                needs_document(&document).then_some(document),
                Arc::new(array),
                0,
            )
        }
        RArrowKind::Double | RArrowKind::Date | RArrowKind::Datetime | RArrowKind::Difftime => {
            let values = double_slice(descriptor, row_count)?;
            let (codes, has_tags) = classify_doubles(values, &name)?;
            let class = match kind {
                RArrowKind::Double if value_labels.is_some() => "haven_labelled",
                RArrowKind::Double => "double",
                RArrowKind::Date => "Date",
                RArrowKind::Datetime => "POSIXct",
                RArrowKind::Difftime => "difftime",
                _ => unreachable!("double kinds"),
            };
            let mut document = with_labels(base_document);
            if kind == RArrowKind::Datetime {
                document.r = r_semantics(class);
                if let Some(semantics) = document.r.as_mut() {
                    semantics.tz = Some(tz.clone());
                }
            } else if kind == RArrowKind::Difftime {
                document.r = r_semantics(class);
                if let Some(semantics) = document.r.as_mut() {
                    semantics.units = Some(units.clone());
                }
            }
            if has_tags || value_labels.is_some() {
                // Tagged NAs and haven labels need bit-exact NaN payloads.
                let (mut field, array) = payload_double_column(values, document, class);
                if let Some(semantics) =
                    field.as_mut().and_then(|document| document.r.as_mut())
                {
                    if kind == RArrowKind::Datetime {
                        semantics.tz = Some(tz.clone());
                    } else if kind == RArrowKind::Difftime {
                        semantics.units = Some(units.clone());
                    }
                }
                (field, array, 0)
            } else {
                match kind {
                    RArrowKind::Double => {
                        let array = semantic_double_array(values, &codes);
                        (
                            needs_document(&document).then_some(document),
                            array,
                            0,
                        )
                    }
                    RArrowKind::Date => date32_or_fallback(values, &codes, document),
                    RArrowKind::Datetime => {
                        timestamp_or_fallback(values, &codes, document, &tz)
                    }
                    RArrowKind::Difftime => {
                        duration_or_fallback(values, &codes, document, &units)
                    }
                    _ => unreachable!("double kinds"),
                }
            }
        }
        RArrowKind::Character => {
            let values = read_strings(descriptor.strings, row_count, "character values")?;
            let document = with_labels(base_document);
            (
                needs_document(&document).then_some(document),
                string_array(&values),
                0,
            )
        }
        RArrowKind::Raw => {
            if descriptor.values.is_null() {
                return Err("native Arrow column data pointer is null".to_owned());
            }
            let values =
                std::slice::from_raw_parts(descriptor.values.cast::<u8>(), row_count);
            let array = UInt8Array::from_iter_values(values.iter().copied());
            let mut document = with_labels(base_document);
            document.r = r_semantics("raw");
            (Some(document), Arc::new(array), 0)
        }
        RArrowKind::Factor => {
            let codes = int_slice(descriptor, row_count)?;
            let levels = read_strings(
                descriptor.strings,
                descriptor.string_count,
                "factor levels",
            )?;
            let mut builder = Int32Builder::with_capacity(row_count);
            for (index, &code) in codes.iter().enumerate() {
                poll_interrupt(index)?;
                if code == R_NaInt {
                    builder.append_null();
                } else if code >= 1 && (code as usize) <= levels.len() {
                    builder.append_value(code - 1);
                } else {
                    return Err(format!(
                        "column `{name}` has a factor code outside its levels"
                    ));
                }
            }
            let level_values: Vec<&str> = levels
                .iter()
                .map(|value| {
                    value
                        .as_deref()
                        .ok_or_else(|| format!("column `{name}` has a missing factor level"))
                })
                .collect::<Result<_, _>>()?;
            let values = StringArray::from(level_values);
            let array = DictionaryArray::try_new(builder.finish(), Arc::new(values))
                .map_err(|error| error.to_string())?;
            let mut document = with_labels(base_document);
            document.r = Some(ArrowRSemantics {
                class: "factor".to_owned(),
                ordered: Some(descriptor.ordered != 0),
                tz: None,
                units: None,
            });
            (Some(document), Arc::new(array), 0)
        }
        RArrowKind::StataNumeric => {
            let storage = storage_from_code(descriptor.storage)?;
            let (array, storage, temporal, replacements) =
                if descriptor.compact_values.is_null() {
                    let storage = storage.ok_or_else(|| {
                        format!("column `{name}` has no declared Stata storage")
                    })?;
                    let values = double_slice(descriptor, row_count)?;
                    let (codes, _) = classify_doubles(values, &name)?;
                    let temporal = temporal_kind(&format);
                    let (array, replacements) =
                        encode_profiled_column(&name, storage, temporal, values, &codes)?;
                    (array, storage, temporal, replacements)
                } else {
                    let (array, storage, temporal) =
                        compact_profiled_column(descriptor, row_count)?;
                    (array, storage, temporal, 0)
                };
            let _ = temporal;
            let mut document = with_labels(base_document);
            document.storage = Some(storage);
            document.missing = Some(field_missing_for_storage(storage));
            (Some(document), array, replacements)
        }
    };

    Ok(ColumnPlan {
        name,
        field,
        array,
        replacements,
        value_labels,
    })
}

/// Date32 when every value is a whole day in range; Float64 fallback with the
/// Date class recorded otherwise.
fn date32_or_fallback(
    values: &[f64],
    codes: &[c_int],
    mut document: ArrowFieldDocument,
) -> (Option<ArrowFieldDocument>, ArrayRef, u64) {
    let exact = values.iter().zip(codes).all(|(&value, &code)| {
        code == 0
            || (value.fract() == 0.0
                && value >= f64::from(i32::MIN)
                && value <= f64::from(i32::MAX))
    });
    if exact {
        let array: ArrayRef = Arc::new(Date32Array::from_iter(
            values
                .iter()
                .zip(codes)
                .map(|(&value, &code)| (code != 0).then_some(value as i32)),
        ));
        (needs_document_or_none(document), array, 0)
    } else {
        document.r = r_semantics("Date");
        let array: ArrayRef = Arc::new(Float64Array::from_iter(
            values
                .iter()
                .zip(codes)
                .map(|(&value, &code)| (code != 0).then_some(value)),
        ));
        (Some(document), array, 0)
    }
}

fn needs_document_or_none(document: ArrowFieldDocument) -> Option<ArrowFieldDocument> {
    (document != ArrowFieldDocument::default()).then_some(document)
}

/// Timestamp in microseconds when the conversion is exactly reversible;
/// Float64 seconds fallback otherwise.
fn timestamp_or_fallback(
    values: &[f64],
    codes: &[c_int],
    mut document: ArrowFieldDocument,
    tz: &str,
) -> (Option<ArrowFieldDocument>, ArrayRef, u64) {
    let to_micros = |value: f64| -> Option<i64> {
        let scaled = value * 1_000_000.0;
        if !scaled.is_finite() {
            return None;
        }
        let rounded = scaled.round();
        if rounded < -9.2e18 || rounded > 9.2e18 || rounded / 1_000_000.0 != value {
            return None;
        }
        Some(rounded as i64)
    };
    let exact = values
        .iter()
        .zip(codes)
        .all(|(&value, &code)| code == 0 || to_micros(value).is_some());
    if exact {
        let array = TimestampMicrosecondArray::from_iter(values.iter().zip(codes).map(
            |(&value, &code)| {
                (code != 0)
                    .then(|| to_micros(value).expect("checked above"))
            },
        ));
        let array = if tz.is_empty() {
            array.with_timezone_utc()
        } else {
            array.with_timezone(tz)
        };
        (needs_document_or_none(document), Arc::new(array), 0)
    } else {
        document.r = r_semantics("POSIXct");
        if let Some(semantics) = document.r.as_mut() {
            semantics.tz = Some(tz.to_owned());
        }
        let array: ArrayRef = Arc::new(Float64Array::from_iter(
            values
                .iter()
                .zip(codes)
                .map(|(&value, &code)| (code != 0).then_some(value)),
        ));
        (Some(document), array, 0)
    }
}

/// Duration in nanoseconds when exactly reversible; Float64 fallback with the
/// difftime units recorded otherwise.
fn duration_or_fallback(
    values: &[f64],
    codes: &[c_int],
    mut document: ArrowFieldDocument,
    units: &str,
) -> (Option<ArrowFieldDocument>, ArrayRef, u64) {
    document.r = r_semantics("difftime");
    if let Some(semantics) = document.r.as_mut() {
        semantics.units = Some(units.to_owned());
    }
    let to_nanos = |value: f64| -> Option<i64> {
        let scaled = value * 1_000_000_000.0;
        if !scaled.is_finite() {
            return None;
        }
        let rounded = scaled.round();
        if rounded < -9.2e18 || rounded > 9.2e18 || rounded / 1_000_000_000.0 != value {
            return None;
        }
        Some(rounded as i64)
    };
    let exact = values
        .iter()
        .zip(codes)
        .all(|(&value, &code)| code == 0 || to_nanos(value).is_some());
    let array: ArrayRef = if exact {
        Arc::new(DurationNanosecondArray::from_iter(
            values.iter().zip(codes).map(|(&value, &code)| {
                (code != 0).then(|| to_nanos(value).expect("checked above"))
            }),
        ))
    } else {
        Arc::new(Float64Array::from_iter(
            values
                .iter()
                .zip(codes)
                .map(|(&value, &code)| (code != 0).then_some(value)),
        ))
    };
    (Some(document), array, 0)
}

#[no_mangle]
/// Save an R dataset as a dtatools Arrow profile file.
///
/// # Safety
///
/// `path`, `compression`, and `dataset_label` must point to readable
/// NUL-terminated C byte strings for the duration of this call. `columns`
/// must address `column_count` readable descriptors whose pointers stay valid
/// (the R spec list must stay protected) for the duration of this call.
/// `notes` must be a protected STRSXP holding `notes_count` strings or null
/// when `notes_count` is zero. If non-null, `error` must point to writable
/// storage for one C string pointer. The caller must run on R's main thread
/// with an initialized R runtime.
pub unsafe extern "C" fn dtatools_save_arrow_rust(
    path: *const c_char,
    dataset_label: *const c_char,
    notes: Sexp,
    notes_count: usize,
    columns: *const RArrowColumnDescriptor,
    column_count: usize,
    row_count: usize,
    compression: *const c_char,
    error: *mut *mut c_char,
) -> Sexp {
    boundary(error, ptr::null_mut(), || {
        let path = required_c_string(path, "the output path")?;
        let compression_label = required_c_string(compression, "the compression label")?;
        let compression = ArrowCompression::from_label(&compression_label)
            .ok_or_else(|| format!("unknown compression `{compression_label}`"))?;
        if columns.is_null() && column_count > 0 {
            return Err("column descriptor pointer is null".to_owned());
        }
        let descriptors = if column_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(columns, column_count)
        };

        let mut dataset = DatasetDocument {
            version: 0,
            label: optional_c_string(dataset_label, "the dataset label")?,
            ..DatasetDocument::default()
        };
        if notes_count > 0 {
            let notes = read_strings(notes, notes_count, "dataset notes")?;
            dataset.notes = notes
                .into_iter()
                .map(|note| note.ok_or_else(|| "a dataset note is missing".to_owned()))
                .collect::<Result<_, _>>()?;
        }

        let mut write_columns = Vec::new();
        write_columns
            .try_reserve_exact(column_count)
            .map_err(|_| "could not allocate output columns".to_owned())?;
        let mut replacements = Vec::new();
        replacements
            .try_reserve_exact(column_count)
            .map_err(|_| "could not allocate replacement counts".to_owned())?;
        for descriptor in descriptors {
            check_interrupt()?;
            let plan = plan_column(descriptor, row_count)?;
            if let Some(table) = &plan.value_labels {
                dataset.insert_value_label_table(table);
            }
            replacements.push(plan.replacements);
            write_columns.push(ArrowWriteColumn {
                name: plan.name,
                field: plan.field,
                array: plan.array,
            });
        }

        let dataset = ArrowWriteDataset {
            dataset,
            columns: write_columns,
        };
        save_arrow_file(
            &path,
            &dataset,
            compression,
            ARROW_ROWS_PER_BATCH,
            &mut coarse_interrupt,
        )
        .map_err(|error| error.to_string())?;

        let mut guard = ProtectGuard::new();
        let result = guard.alloc(
            REALSXP,
            RLen::try_from(column_count).map_err(|_| "too many columns".to_owned())?,
        )?;
        for (index, &count) in replacements.iter().enumerate() {
            *REAL(result).add(index) = count as f64;
        }
        Ok(result)
    })
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

fn row_window(skip: f64, n_max: f64) -> (u64, Option<u64>) {
    let start = if skip.is_finite() && skip > 0.0 {
        skip as u64
    } else {
        0
    };
    let limit = if (0.0..=9_007_199_254_740_992.0).contains(&n_max) {
        Some(n_max as u64)
    } else {
        None
    };
    (start, limit)
}

struct ColumnAttributes<'a> {
    document: Option<&'a ArrowFieldDocument>,
    dataset: Option<&'a DatasetDocument>,
}

impl ColumnAttributes<'_> {
    fn label(&self) -> &str {
        self.document.map_or("", |document| document.label.as_str())
    }

    fn format(&self) -> &str {
        self.document
            .map_or("", |document| document.format.as_str())
    }

    fn value_label_table(&self) -> Option<ValueLabelTable> {
        let name = self.document?.value_labels.as_deref()?;
        self.dataset?.value_label_table(name)
    }

    fn semantics(&self) -> Option<&ArrowRSemantics> {
        self.document?.r.as_ref()
    }

    fn class(&self) -> Option<&str> {
        self.semantics().map(|semantics| semantics.class.as_str())
    }
}

unsafe fn attach_simple_attributes(
    vector: Sexp,
    attributes: &ColumnAttributes<'_>,
    guard: &mut ProtectGuard,
) -> Result<(), String> {
    if !attributes.label().is_empty() {
        let label = scalar_string(attributes.label(), guard)?;
        set_attr(vector, "label", label)?;
    }
    if !attributes.format().is_empty() {
        let format = scalar_string(attributes.format(), guard)?;
        set_attr(vector, "format.stata", format)?;
    }
    Ok(())
}

/// The synthesized VariableInfo used to reuse the DTA attribute logic for
/// profiled columns.
fn profiled_variable(name: &str, attributes: &ColumnAttributes<'_>, storage: StataStorage)
    -> VariableInfo
{
    VariableInfo {
        name: name.to_owned(),
        dta_type: storage.dta_type(),
        type_code: 0,
        format: attributes.format().to_owned(),
        label: attributes.label().to_owned(),
        value_label_name: attributes
            .document
            .and_then(|document| document.value_labels.clone())
            .unwrap_or_default(),
        byte_width: 0,
        byte_offset: 0,
    }
}

fn chunk_error(name: &str) -> String {
    format!("column `{name}` has chunks of an unexpected Arrow type")
}

/// Iterate every (chunk, local index) pair of a column in row order.
fn for_each_value<T: Array + 'static>(
    column: &ArrowReadColumn,
    mut visit: impl FnMut(usize, &T, usize) -> Result<(), String>,
) -> Result<(), String> {
    let mut row = 0_usize;
    for chunk in &column.chunks {
        let typed = chunk
            .as_any()
            .downcast_ref::<T>()
            .ok_or_else(|| chunk_error(&column.name))?;
        for index in 0..typed.len() {
            poll_interrupt(row)?;
            visit(row, typed, index)?;
            row += 1;
        }
    }
    Ok(())
}

unsafe fn profiled_column_vector(
    column: &ArrowReadColumn,
    attributes: &ColumnAttributes<'_>,
    storage: StataStorage,
    row_count: usize,
    numeric_altrep: bool,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let temporal = temporal_kind(attributes.format());
    if storage == StataStorage::Double {
        // Raw Stata missing storage for doubles: classify the stored bits.
        let vector = guard.alloc(REALSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
        let output = REAL(vector);
        for_each_value::<Float64Array>(column, |row, values, index| {
            let value = values.value(index);
            *output.add(row) = match classify_double_missing_bits(value.to_bits()) {
                Some(tag) => r_missing(tag),
                None => observed_value(value, temporal),
            };
            Ok(())
        })?;
        return Ok(vector);
    }

    if numeric_altrep {
        let mut data = numeric_altrep_storage(
            storage.dta_type(),
            row_count,
            temporal,
            FormatVersion::V118,
            guard,
        )
        .map_err(|error| error.to_string())?;
        let mut no_na = true;
        match storage {
            StataStorage::Byte => for_each_value::<Int8Array>(column, |row, values, index| {
                let value = values.value(index);
                no_na &= classify_byte_missing_for_version(value, FormatVersion::V118).is_none();
                data.values.add(row).cast::<i8>().write_unaligned(value);
                Ok(())
            })?,
            StataStorage::Int => for_each_value::<Int16Array>(column, |row, values, index| {
                let value = values.value(index);
                no_na &= classify_int_missing_for_version(value, FormatVersion::V118).is_none();
                data.values
                    .add(row * 2)
                    .cast::<i16>()
                    .write_unaligned(value);
                Ok(())
            })?,
            StataStorage::Long => for_each_value::<Int32Array>(column, |row, values, index| {
                let value = values.value(index);
                no_na &= classify_long_missing_for_version(value, FormatVersion::V118).is_none();
                data.values
                    .add(row * 4)
                    .cast::<i32>()
                    .write_unaligned(value);
                Ok(())
            })?,
            StataStorage::Float => for_each_value::<Float32Array>(column, |row, values, index| {
                let value = values.value(index);
                no_na &= !value.is_nan();
                data.values
                    .add(row * 4)
                    .cast::<f32>()
                    .write_unaligned(value);
                Ok(())
            })?,
            StataStorage::Double => unreachable!("handled above"),
        }
        data.no_na = no_na;
        return guard.numeric(data);
    }

    let vector = guard.alloc(REALSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
    let output = REAL(vector);
    match storage {
        StataStorage::Byte => for_each_value::<Int8Array>(column, |row, values, index| {
            let value = values.value(index);
            *output.add(row) = match classify_byte_missing_for_version(value, FormatVersion::V118)
            {
                Some(tag) => r_missing(tag),
                None => observed_value(f64::from(value), temporal),
            };
            Ok(())
        })?,
        StataStorage::Int => for_each_value::<Int16Array>(column, |row, values, index| {
            let value = values.value(index);
            *output.add(row) = match classify_int_missing_for_version(value, FormatVersion::V118)
            {
                Some(tag) => r_missing(tag),
                None => observed_value(f64::from(value), temporal),
            };
            Ok(())
        })?,
        StataStorage::Long => for_each_value::<Int32Array>(column, |row, values, index| {
            let value = values.value(index);
            *output.add(row) = match classify_long_missing_for_version(value, FormatVersion::V118)
            {
                Some(tag) => r_missing(tag),
                None => observed_value(f64::from(value), temporal),
            };
            Ok(())
        })?,
        StataStorage::Float => for_each_value::<Float32Array>(column, |row, values, index| {
            let value = values.value(index);
            *output.add(row) =
                match classify_float_missing_bits_for_version(value.to_bits(), FormatVersion::V118)
                {
                    Some(tag) => r_missing(tag),
                    None => observed_value(f64::from(value), temporal),
                };
            Ok(())
        })?,
        StataStorage::Double => unreachable!("handled above"),
    }
    Ok(vector)
}

unsafe fn double_vector_from<F>(
    column: &ArrowReadColumn,
    row_count: usize,
    guard: &mut ProtectGuard,
    convert: F,
) -> Result<Sexp, String>
where
    F: Fn(f64) -> f64,
{
    let vector = guard.alloc(REALSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
    let output = REAL(vector);
    match column.data_type {
        DataType::Float64 => for_each_value::<Float64Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                convert(values.value(index))
            };
            Ok(())
        })?,
        DataType::Float32 => for_each_value::<Float32Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                convert(f64::from(values.value(index)))
            };
            Ok(())
        })?,
        DataType::Int64 => for_each_value::<Int64Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                convert(values.value(index) as f64)
            };
            Ok(())
        })?,
        DataType::UInt16 => for_each_value::<UInt16Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                convert(f64::from(values.value(index)))
            };
            Ok(())
        })?,
        DataType::UInt32 => for_each_value::<UInt32Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                convert(f64::from(values.value(index)))
            };
            Ok(())
        })?,
        DataType::UInt64 => for_each_value::<UInt64Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                convert(values.value(index) as f64)
            };
            Ok(())
        })?,
        _ => return Err(chunk_error(&column.name)),
    }
    Ok(vector)
}

unsafe fn payload_double_vector(
    column: &ArrowReadColumn,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let vector = guard.alloc(REALSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
    let output = REAL(vector);
    for_each_value::<Float64Array>(column, |row, values, index| {
        // Bit-exact: tagged NAs and NaN payloads pass through unchanged.
        *output.add(row) = values.value(index);
        Ok(())
    })?;
    Ok(vector)
}

unsafe fn integer_vector(
    column: &ArrowReadColumn,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let vector = guard.alloc(INTSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
    let output = INTEGER(vector);
    match column.data_type {
        DataType::Int32 => for_each_value::<Int32Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaInt
            } else {
                values.value(index)
            };
            Ok(())
        })?,
        DataType::Int8 => for_each_value::<Int8Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaInt
            } else {
                c_int::from(values.value(index))
            };
            Ok(())
        })?,
        DataType::Int16 => for_each_value::<Int16Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaInt
            } else {
                c_int::from(values.value(index))
            };
            Ok(())
        })?,
        DataType::UInt8 => for_each_value::<UInt8Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaInt
            } else {
                c_int::from(values.value(index))
            };
            Ok(())
        })?,
        _ => return Err(chunk_error(&column.name)),
    }
    Ok(vector)
}

unsafe fn logical_vector(
    column: &ArrowReadColumn,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let vector = guard.alloc(LGLSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
    let output = LOGICAL(vector);
    for_each_value::<BooleanArray>(column, |row, values, index| {
        *output.add(row) = if values.is_null(index) {
            R_NaInt
        } else {
            c_int::from(values.value(index))
        };
        Ok(())
    })?;
    Ok(vector)
}

unsafe fn character_vector(
    column: &ArrowReadColumn,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let vector = guard.alloc(STRSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
    match column.data_type {
        DataType::Utf8 => for_each_value::<StringArray>(column, |row, values, index| {
            if values.is_null(index) {
                SET_STRING_ELT(vector, row as RLen, R_NaString);
            } else {
                SET_STRING_ELT(vector, row as RLen, r_char(values.value(index))?);
            }
            Ok(())
        })?,
        DataType::LargeUtf8 => {
            for_each_value::<arrow_array::LargeStringArray>(column, |row, values, index| {
                if values.is_null(index) {
                    SET_STRING_ELT(vector, row as RLen, R_NaString);
                } else {
                    SET_STRING_ELT(vector, row as RLen, r_char(values.value(index))?);
                }
                Ok(())
            })?
        }
        _ => return Err(chunk_error(&column.name)),
    }
    Ok(vector)
}

unsafe fn raw_vector(
    column: &ArrowReadColumn,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let vector = guard.alloc(
        crate::RAWSXP,
        RLen::try_from(row_count).map_err(|_| "too long")?,
    )?;
    let output = crate::RAW(vector);
    for_each_value::<UInt8Array>(column, |row, values, index| {
        if values.is_null(index) {
            return Err(format!(
                "column `{}` maps to an R raw vector but contains nulls",
                column.name
            ));
        }
        *output.add(row) = values.value(index);
        Ok(())
    })?;
    Ok(vector)
}

unsafe fn factor_vector(
    column: &ArrowReadColumn,
    attributes: &ColumnAttributes<'_>,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let vector = guard.alloc(INTSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
    let output = INTEGER(vector);
    let mut levels: Option<Vec<String>> = None;
    let mut row = 0_usize;
    for chunk in &column.chunks {
        let dictionary = chunk
            .as_any()
            .downcast_ref::<DictionaryArray<arrow_array::types::Int32Type>>()
            .ok_or_else(|| chunk_error(&column.name))?;
        let chunk_levels: Vec<String> = match dictionary.values().data_type() {
            DataType::Utf8 => {
                let values = dictionary
                    .values()
                    .as_any()
                    .downcast_ref::<StringArray>()
                    .ok_or_else(|| chunk_error(&column.name))?;
                (0..values.len())
                    .map(|index| {
                        if values.is_null(index) {
                            Err(format!(
                                "column `{}` has a null factor level",
                                column.name
                            ))
                        } else {
                            Ok(values.value(index).to_owned())
                        }
                    })
                    .collect::<Result<_, _>>()?
            }
            DataType::LargeUtf8 => {
                let values = dictionary
                    .values()
                    .as_any()
                    .downcast_ref::<arrow_array::LargeStringArray>()
                    .ok_or_else(|| chunk_error(&column.name))?;
                (0..values.len())
                    .map(|index| {
                        if values.is_null(index) {
                            Err(format!(
                                "column `{}` has a null factor level",
                                column.name
                            ))
                        } else {
                            Ok(values.value(index).to_owned())
                        }
                    })
                    .collect::<Result<_, _>>()?
            }
            _ => return Err(chunk_error(&column.name)),
        };
        match &levels {
            None => levels = Some(chunk_levels),
            Some(existing) if *existing == chunk_levels => {}
            Some(_) => {
                return Err(format!(
                    "column `{}` has chunks with different dictionaries",
                    column.name
                ))
            }
        }
        let keys = dictionary.keys();
        for index in 0..keys.len() {
            poll_interrupt(row)?;
            *output.add(row) = if keys.is_null(index) {
                R_NaInt
            } else {
                keys.value(index) + 1
            };
            row += 1;
        }
    }
    let levels = levels.unwrap_or_default();
    let level_vector = string_vector(&levels, guard)?;
    set_attr(vector, "levels", level_vector)?;
    let ordered = attributes
        .semantics()
        .and_then(|semantics| semantics.ordered)
        .unwrap_or(false);
    if ordered {
        set_class(vector, &["ordered", "factor"], guard)?;
    } else {
        set_class(vector, &["factor"], guard)?;
    }
    Ok(vector)
}

const MICROS_PER_SECOND: f64 = 1_000_000.0;

fn timestamp_scale(unit: &TimeUnit) -> f64 {
    match unit {
        TimeUnit::Second => 1.0,
        TimeUnit::Millisecond => 1_000.0,
        TimeUnit::Microsecond => MICROS_PER_SECOND,
        TimeUnit::Nanosecond => 1_000_000_000.0,
    }
}

unsafe fn timestamp_vector(
    column: &ArrowReadColumn,
    attributes: &ColumnAttributes<'_>,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let DataType::Timestamp(unit, type_tz) = &column.data_type else {
        return Err(chunk_error(&column.name));
    };
    let scale = timestamp_scale(unit);
    let vector = guard.alloc(REALSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
    let output = REAL(vector);
    macro_rules! fill {
        ($array:ty) => {
            for_each_value::<$array>(column, |row, values, index| {
                *output.add(row) = if values.is_null(index) {
                    R_NaReal
                } else {
                    values.value(index) as f64 / scale
                };
                Ok(())
            })?
        };
    }
    match unit {
        TimeUnit::Second => fill!(arrow_array::TimestampSecondArray),
        TimeUnit::Millisecond => fill!(arrow_array::TimestampMillisecondArray),
        TimeUnit::Microsecond => fill!(TimestampMicrosecondArray),
        TimeUnit::Nanosecond => fill!(arrow_array::TimestampNanosecondArray),
    }
    set_class(vector, &["POSIXct", "POSIXt"], guard)?;
    let tz = attributes
        .semantics()
        .and_then(|semantics| semantics.tz.as_deref())
        .filter(|tz| !tz.is_empty())
        .or(type_tz.as_deref())
        .unwrap_or("UTC");
    let timezone = scalar_string(tz, guard)?;
    set_attr(vector, "tzone", timezone)?;
    Ok(vector)
}

unsafe fn duration_vector(
    column: &ArrowReadColumn,
    attributes: &ColumnAttributes<'_>,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let DataType::Duration(unit) = &column.data_type else {
        return Err(chunk_error(&column.name));
    };
    let scale = timestamp_scale(unit);
    let vector = guard.alloc(REALSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
    let output = REAL(vector);
    macro_rules! fill {
        ($array:ty) => {
            for_each_value::<$array>(column, |row, values, index| {
                *output.add(row) = if values.is_null(index) {
                    R_NaReal
                } else {
                    values.value(index) as f64 / scale
                };
                Ok(())
            })?
        };
    }
    match unit {
        TimeUnit::Second => fill!(arrow_array::DurationSecondArray),
        TimeUnit::Millisecond => fill!(arrow_array::DurationMillisecondArray),
        TimeUnit::Microsecond => fill!(arrow_array::DurationMicrosecondArray),
        TimeUnit::Nanosecond => fill!(DurationNanosecondArray),
    }
    apply_difftime_attributes(vector, attributes, guard)
}

unsafe fn apply_difftime_attributes(
    vector: Sexp,
    attributes: &ColumnAttributes<'_>,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let units = attributes
        .semantics()
        .and_then(|semantics| semantics.units.as_deref())
        .filter(|units| !units.is_empty())
        .unwrap_or("secs");
    let units_value = scalar_string(units, guard)?;
    set_attr(vector, "units", units_value)?;
    set_class(vector, &["difftime"], guard)?;
    Ok(vector)
}

unsafe fn labelled_double_attributes(
    vector: Sexp,
    table: &ValueLabelTable,
    guard: &mut ProtectGuard,
) -> Result<(), String> {
    let labels = label_attribute(table, guard)?;
    set_attr(vector, "labels", labels)?;
    set_class(vector, &["haven_labelled", "vctrs_vctr", "double"], guard)?;
    Ok(())
}

unsafe fn build_read_column(
    column: &ArrowReadColumn,
    dataset: Option<&DatasetDocument>,
    profiled: bool,
    row_count: usize,
    numeric_altrep: bool,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let attributes = ColumnAttributes {
        document: if profiled { column.field.as_ref() } else { None },
        dataset: if profiled { dataset } else { None },
    };

    // Profiled columns with declared Stata storage reuse the DTA attribute
    // logic wholesale; raw Stata missing storage drives the value mapping.
    if let Some(storage) = attributes.document.and_then(|document| document.storage) {
        let vector = profiled_column_vector(
            column,
            &attributes,
            storage,
            row_count,
            numeric_altrep,
            guard,
        )?;
        let variable = profiled_variable(&column.name, &attributes, storage);
        let table = attributes.value_label_table();
        attach_variable_attributes(vector, &variable, table.as_ref(), guard)?;
        return Ok(vector);
    }

    let class = attributes.class();
    let payload = attributes
        .document
        .and_then(|document| document.missing)
        == Some(ArrowMissingEncoding::Payload);

    let vector = match &column.data_type {
        DataType::Boolean => logical_vector(column, row_count, guard)?,
        DataType::Int8 | DataType::Int16 | DataType::Int32 | DataType::UInt8
            if class != Some("raw") =>
        {
            integer_vector(column, row_count, guard)?
        }
        DataType::UInt8 => raw_vector(column, row_count, guard)?,
        DataType::Utf8 | DataType::LargeUtf8 => character_vector(column, row_count, guard)?,
        DataType::Dictionary(_, _) => {
            let vector = factor_vector(column, &attributes, row_count, guard)?;
            attach_simple_attributes(vector, &attributes, guard)?;
            return Ok(vector);
        }
        DataType::Date32 => {
            let vector =
                guard.alloc(REALSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
            let output = REAL(vector);
            for_each_value::<Date32Array>(column, |row, values, index| {
                *output.add(row) = if values.is_null(index) {
                    R_NaReal
                } else {
                    f64::from(values.value(index))
                };
                Ok(())
            })?;
            set_class(vector, &["Date"], guard)?;
            vector
        }
        DataType::Timestamp(_, _) => {
            let vector = timestamp_vector(column, &attributes, row_count, guard)?;
            attach_simple_attributes(vector, &attributes, guard)?;
            return Ok(vector);
        }
        DataType::Duration(_) => {
            let vector = duration_vector(column, &attributes, row_count, guard)?;
            attach_simple_attributes(vector, &attributes, guard)?;
            return Ok(vector);
        }
        DataType::Float64 if payload => {
            let vector = payload_double_vector(column, row_count, guard)?;
            match class {
                Some("Date") => set_class(vector, &["Date"], guard)?,
                Some("POSIXct") => {
                    set_class(vector, &["POSIXct", "POSIXt"], guard)?;
                    let tz = attributes
                        .semantics()
                        .and_then(|semantics| semantics.tz.as_deref())
                        .filter(|tz| !tz.is_empty())
                        .unwrap_or("UTC");
                    let timezone = scalar_string(tz, guard)?;
                    set_attr(vector, "tzone", timezone)?;
                }
                Some("difftime") => {
                    apply_difftime_attributes(vector, &attributes, guard)?;
                }
                _ => {}
            }
            if let Some(table) = attributes.value_label_table() {
                labelled_double_attributes(vector, &table, guard)?;
            }
            vector
        }
        DataType::Float32
        | DataType::Float64
        | DataType::Int64
        | DataType::UInt16
        | DataType::UInt32
        | DataType::UInt64 => {
            let vector = double_vector_from(column, row_count, guard, |value| value)?;
            match class {
                Some("Date") => set_class(vector, &["Date"], guard)?,
                Some("POSIXct") => {
                    set_class(vector, &["POSIXct", "POSIXt"], guard)?;
                    let tz = attributes
                        .semantics()
                        .and_then(|semantics| semantics.tz.as_deref())
                        .filter(|tz| !tz.is_empty())
                        .unwrap_or("UTC");
                    let timezone = scalar_string(tz, guard)?;
                    set_attr(vector, "tzone", timezone)?;
                }
                Some("difftime") => {
                    apply_difftime_attributes(vector, &attributes, guard)?;
                }
                _ => {}
            }
            if let Some(table) = attributes.value_label_table() {
                labelled_double_attributes(vector, &table, guard)?;
            }
            vector
        }
        other => {
            return Err(format!(
                "column `{}` has unsupported Arrow type {other}",
                column.name
            ))
        }
    };
    attach_simple_attributes(vector, &attributes, guard)?;
    Ok(vector)
}

#[no_mangle]
/// Read a dtatools Arrow profile file (or a plain Arrow IPC file) into an R
/// tibble.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C byte string for the
/// duration of this call. Unless `all_columns` is nonzero, `columns` must
/// address `column_count` readable integers. If non-null, `error` must point
/// to writable storage for one C string pointer. The caller must run on R's
/// main thread with an initialized R runtime.
pub unsafe extern "C" fn dtatools_read_arrow_rust(
    path: *const c_char,
    columns: *const c_int,
    column_count: usize,
    all_columns: c_int,
    skip: f64,
    n_max: f64,
    verify: c_int,
    profile: c_int,
    numeric_altrep: c_int,
    error: *mut *mut c_char,
) -> Sexp {
    boundary(error, ptr::null_mut(), || {
        let path = required_c_string(path, "the input path")?;
        let projection = if all_columns != 0 {
            None
        } else {
            if columns.is_null() && column_count != 0 {
                return Err("column pointer is null".to_owned());
            }
            let indices: &[c_int] = if column_count == 0 {
                &[]
            } else {
                std::slice::from_raw_parts(columns, column_count)
            };
            Some(
                indices
                    .iter()
                    .map(|index| {
                        u32::try_from(*index).map_err(|_| "invalid projected column".to_owned())
                    })
                    .collect::<Result<Vec<_>, _>>()?,
            )
        };
        let (row_start, row_count) = row_window(skip, n_max);
        let options = ArrowReadOptions {
            columns: projection,
            row_start,
            row_count,
            verify: verify != 0,
            profile: profile != 0,
        };
        let result = read_arrow_file(&path, &options, &mut coarse_interrupt)
            .map_err(|error| error.to_string())?;
        let profiled = result.profile_version.is_some();
        let row_count = usize::try_from(result.row_count)
            .map_err(|_| "the selection has too many rows".to_owned())?;
        if result.row_count > crate::R_DATA_FRAME_MAX_ROWS {
            return Err("R data frames cannot contain more than 2^31-1 rows".to_owned());
        }

        let mut result_guard = ProtectGuard::new();
        let column_total =
            RLen::try_from(result.columns.len()).map_err(|_| "too many columns".to_owned())?;
        let frame = result_guard.alloc(VECSXP, column_total)?;
        let names = result_guard.alloc(STRSXP, column_total)?;
        for (index, column) in result.columns.iter().enumerate() {
            check_interrupt()?;
            {
                let mut column_guard = ProtectGuard::new();
                let vector = build_read_column(
                    column,
                    result.dataset.as_ref(),
                    profiled,
                    row_count,
                    numeric_altrep != 0,
                    &mut column_guard,
                )?;
                SET_VECTOR_ELT(frame, index as RLen, vector);
                SET_STRING_ELT(names, index as RLen, r_char(&column.name)?);
            }
        }
        set_symbol_attr(frame, R_NamesSymbol, names)?;

        {
            let mut attribute_guard = ProtectGuard::new();
            let row_names = attribute_guard.alloc(INTSXP, 2)?;
            *INTEGER(row_names) = R_NaInt;
            *INTEGER(row_names).add(1) = -(row_count as c_int);
            set_symbol_attr(frame, R_RowNamesSymbol, row_names)?;
            set_class(frame, &["tbl_df", "tbl", "data.frame"], &mut attribute_guard)?;
        }
        let _ = R_ClassSymbol;

        if let Some(dataset) = &result.dataset {
            if !dataset.label.is_empty() {
                let mut guard = ProtectGuard::new();
                let label = scalar_string(&dataset.label, &mut guard)?;
                set_attr(frame, "label", label)?;
            }
            if !dataset.notes.is_empty() {
                let mut guard = ProtectGuard::new();
                let notes = string_vector(&dataset.notes, &mut guard)?;
                set_attr(frame, "notes", notes)?;
            }
        }
        Ok(frame)
    })
}

#[no_mangle]
/// Return the column names and R proxy types of an Arrow file as a two
/// element list, for tidyselect resolution.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C byte string for the
/// duration of this call. If non-null, `error` must point to writable storage
/// for one C string pointer. The caller must run on R's main thread with an
/// initialized R runtime.
pub unsafe extern "C" fn dtatools_arrow_metadata_rust(
    path: *const c_char,
    error: *mut *mut c_char,
) -> Sexp {
    boundary(error, ptr::null_mut(), || {
        let path = required_c_string(path, "the input path")?;
        let summary = summarize_arrow_file(&path).map_err(|error| error.to_string())?;
        let mut guard = ProtectGuard::new();
        let result = guard.alloc(VECSXP, 2)?;
        let names: Vec<String> = summary
            .columns
            .iter()
            .map(|column| column.name.clone())
            .collect();
        let types: Vec<String> = summary
            .columns
            .iter()
            .map(|column| column.r_type.to_owned())
            .collect();
        let name_vector = string_vector(&names, &mut guard)?;
        let type_vector = string_vector(&types, &mut guard)?;
        SET_VECTOR_ELT(result, 0, name_vector);
        SET_VECTOR_ELT(result, 1, type_vector);
        Ok(result)
    })
}
