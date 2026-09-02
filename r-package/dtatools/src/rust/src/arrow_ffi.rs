//! FFI adapters for the dtatools Arrow profile: `dtatools_save_arrow_rust`,
//! `dtatools_read_arrow_rust`, and `dtatools_arrow_metadata_rust`, mirroring
//! the DTA entry points. The C layer validates R types and passes direct data
//! pointers; character data crosses through the string region callback.

use std::collections::{HashMap, HashSet};
use std::ffi::CStr;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;

use dta_tools::arrow::{
    arrow_stored_signature, dataset_signature, preflight_arrow_metadata,
    save_arrow_file_with_preflight, ArrowCompression, ArrowFieldDocument, ArrowFileSnapshot,
    ArrowMetadataPreflight, ArrowMissingEncoding, ArrowRSemantics, ArrowReadColumn,
    ArrowReadOptions, ArrowWriteColumn, ArrowWriteDataset, DatasetDocument, StataStorage,
};
use dta_tools::{
    classify_byte_missing_for_version, classify_double_missing_bits,
    classify_float_missing_bits_for_version, classify_int_missing_for_version,
    classify_long_missing_for_version, dta_write_numeric_value_is_representable, encode_numeric,
    DtaWriteNumericValue, DtaWriteRawNumericValue, FormatVersion, MissingTag, StataCharacteristic,
    StataNote, ValueLabelEntry, ValueLabelTable,
};

use arrow_array::builder::{BooleanBuilder, Int32Builder, LargeStringBuilder, StringBuilder};
use arrow_array::types::{
    ArrowDictionaryKeyType, ArrowPrimitiveType, Float32Type, Float64Type, Int16Type, Int32Type,
    Int64Type, Int8Type, UInt8Type,
};
use arrow_array::{
    Array, ArrayRef, BooleanArray, Date32Array, DictionaryArray, DurationNanosecondArray,
    Float32Array, Float64Array, Int16Array, Int32Array, Int64Array, Int8Array, PrimitiveArray,
    StringArray, TimestampMicrosecondArray, UInt16Array, UInt32Array, UInt64Array, UInt8Array,
};
use arrow_buffer::{ArrowNativeType, Buffer, ScalarBuffer};
use arrow_schema::{DataType, TimeUnit};

use crate::{
    attach_source_rows, attach_stata_metadata, attach_variable_attribute_view, boundary,
    check_interrupt,
    coarse_interrupt, direct_r_missing_code, fill_string_region, label_attribute_from_entries,
    missing_from_code, numeric_altrep_storage, observed_value, parse_stata_metadata_sexp,
    poll_interrupt, r_char, r_missing, scalar_string, set_attr, set_class, set_symbol_attr,
    should_preserve_value_label_name, string_vector, temporal_kind, write_numeric_value,
    NumericKind, ProtectGuard, RLen, RNumericData, RStringData, R_ClassSymbol, R_NaInt, R_NaReal,
    R_NaString, R_NamesSymbol, R_RowNamesSymbol, Sexp, TemporalKind, DAYS_1960_TO_1970, INTEGER,
    INTSXP, LGLSXP, LOGICAL, REAL, REALSXP, SECONDS_1960_TO_1970, SET_STRING_ELT, SET_VECTOR_ELT,
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
    /// -1 none; 0 strL; 1..=2045 fixed-string byte width.
    string_storage: c_int,
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
    value_label_index: c_int,
    stata_metadata: Sexp,
    haven_labelled: c_int,
    /// Unmaterialized dictionary-string payload (`DictStringData`), or null
    /// for eager character columns.
    dictstring: *const c_void,
}

#[cfg(target_pointer_width = "64")]
const _: () = {
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, name) == 0);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, kind) == 8);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, label) == 16);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, format) == 24);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, storage) == 32);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, string_storage) == 36);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, ordered) == 40);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, tz) == 48);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, units) == 56);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, values) == 64);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, strings) == 72);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, string_count) == 80);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, compact_values) == 88);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, compact_kind) == 96);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, compact_format_version) == 100);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, compact_temporal) == 104);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, value_label_index) == 108);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, stata_metadata) == 112);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, haven_labelled) == 120);
    assert!(std::mem::offset_of!(RArrowColumnDescriptor, dictstring) == 128);
    assert!(std::mem::size_of::<RArrowColumnDescriptor>() == 136);
};

#[repr(C)]
pub struct RArrowValueLabelTableDescriptor {
    name: *const c_char,
    /// Value-label codes as R doubles (tagged NAs carry extended tags).
    label_values: *const f64,
    label_texts: Sexp,
    label_count: usize,
}

#[cfg(target_pointer_width = "64")]
const _: () = {
    assert!(std::mem::offset_of!(RArrowValueLabelTableDescriptor, name) == 0);
    assert!(std::mem::offset_of!(RArrowValueLabelTableDescriptor, label_values) == 8);
    assert!(std::mem::offset_of!(RArrowValueLabelTableDescriptor, label_texts) == 16);
    assert!(std::mem::offset_of!(RArrowValueLabelTableDescriptor, label_count) == 24);
    assert!(std::mem::size_of::<RArrowValueLabelTableDescriptor>() == 32);
};

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
    LabelledInteger,
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
            10 => Ok(Self::LabelledInteger),
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

fn native_arrow_interrupted(message: &str) -> bool {
    matches!(
        message,
        "interrupted"
            | "DTA read interrupted"
            | "Arrow read interrupted"
            | "Arrow write interrupted"
    )
}

unsafe fn arrow_boundary<T, F>(
    interrupted: *mut c_int,
    error: *mut *mut c_char,
    failure: T,
    call: F,
) -> T
where
    T: Copy,
    F: FnOnce() -> Result<T, String>,
{
    boundary(error, failure, || {
        if interrupted.is_null() {
            return Err("native Arrow interrupt status pointer is null".to_owned());
        }
        *interrupted = 0;
        match call() {
            Err(message) if native_arrow_interrupted(&message) => {
                *interrupted = 1;
                Ok(failure)
            }
            result => result,
        }
    })
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

/// Classify every value of an R double column. Ordinary and noncanonical NaN
/// payloads remain observed floating-point values; R NA and canonical tagged
/// NAs receive their missing codes. Pure: callable from any thread.
fn classify_doubles(values: &[f64], _name: &str) -> Result<(Vec<c_int>, bool), String> {
    let mut codes = Vec::new();
    codes
        .try_reserve_exact(values.len())
        .map_err(|_| "could not allocate native missing codes".to_owned())?;
    let mut has_tags = false;
    for &value in values {
        let code = direct_r_missing_code(value);
        has_tags |= (c_int::from(b'a')..=c_int::from(b'z')).contains(&code);
        codes.push(code);
    }
    Ok((codes, has_tags))
}

fn uses_large_string_offsets(total_bytes: usize) -> bool {
    total_bytes > i32::MAX as usize
}

fn string_array(values: &[Option<String>], name: &str) -> Result<ArrayRef, String> {
    let total_bytes = values.iter().try_fold(0_usize, |total, value| {
        total
            .checked_add(value.as_ref().map_or(0, String::len))
            .ok_or_else(|| format!("column `{name}` overflows the Arrow string buffer"))
    })?;
    if uses_large_string_offsets(total_bytes) {
        let mut builder = LargeStringBuilder::with_capacity(values.len(), total_bytes);
        for value in values {
            match value {
                Some(value) => builder.append_value(value),
                None => builder.append_null(),
            }
        }
        Ok(Arc::new(builder.finish()))
    } else {
        let mut builder = StringBuilder::with_capacity(values.len(), total_bytes);
        for value in values {
            match value {
                Some(value) => builder.append_value(value),
                None => builder.append_null(),
            }
        }
        Ok(Arc::new(builder.finish()))
    }
}

/// Build the Arrow string array straight from an unmaterialized
/// dictionary-string payload, creating no CHARSXPs. Dictionary payloads hold
/// UTF-8 and cannot represent `NA_character_`, so the array has no nulls and
/// is byte-identical to the eager path's output.
///
/// # Safety
///
/// `data` must stay live for the duration of the call; the ALTREP vector that
/// owns it is protected by the caller's column specification.
unsafe fn dictstring_array(
    data: &crate::DictStringData,
    row_count: usize,
    name: &str,
) -> Result<ArrayRef, String> {
    if data.length != row_count {
        return Err(format!(
            "column `{name}` has {} dictionary rows; expected {row_count}",
            data.length
        ));
    }
    let ids = std::slice::from_raw_parts(data.value_ids, data.length);
    let mut total_bytes = 0_usize;
    for &id in ids {
        let (_, length) = data
            .value_views
            .get(id as usize)
            .ok_or_else(|| format!("column `{name}` has an invalid dictionary index"))?;
        total_bytes = total_bytes
            .checked_add(*length)
            .ok_or_else(|| format!("column `{name}` overflows the Arrow string buffer"))?;
    }
    if uses_large_string_offsets(total_bytes) {
        let mut builder = LargeStringBuilder::with_capacity(row_count, total_bytes);
        for &id in ids {
            let &(bytes, length) = &data.value_views[id as usize];
            let view = std::slice::from_raw_parts(bytes, length);
            let value = std::str::from_utf8(view)
                .map_err(|_| format!("column `{name}` holds invalid UTF-8"))?;
            builder.append_value(value);
        }
        Ok(Arc::new(builder.finish()))
    } else {
        let mut builder = StringBuilder::with_capacity(row_count, total_bytes);
        for &id in ids {
            let &(bytes, length) = &data.value_views[id as usize];
            let view = std::slice::from_raw_parts(bytes, length);
            let value = std::str::from_utf8(view)
                .map_err(|_| format!("column `{name}` holds invalid UTF-8"))?;
            builder.append_value(value);
        }
        Ok(Arc::new(builder.finish()))
    }
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
    label: String,
    format: String,
    notes: Vec<StataNote>,
    characteristics: Vec<StataCharacteristic>,
) -> ArrowFieldDocument {
    ArrowFieldDocument {
        version: 0,
        label,
        format,
        notes,
        characteristics,
        ..ArrowFieldDocument::default()
    }
}

/// A non-nullable primitive array over R-owned memory, without copying.
///
/// # Safety
///
/// `values` must address `row_count` readable elements that stay valid and
/// unchanged for the array's whole lifetime. The save driver satisfies this:
/// the R spec list stays protected for the duration of the `.Call`, and every
/// array is dropped before it returns.
unsafe fn zero_copy_array<T: ArrowPrimitiveType>(
    values: *const T::Native,
    row_count: usize,
) -> ArrayRef {
    if row_count == 0 {
        return Arc::new(PrimitiveArray::<T>::from_iter_values(std::iter::empty()));
    }
    let Some(bytes) = std::ptr::NonNull::new(values.cast_mut().cast::<u8>()) else {
        return Arc::new(PrimitiveArray::<T>::from_iter_values(std::iter::empty()));
    };
    let buffer = Buffer::from_custom_allocation(
        bytes,
        row_count * std::mem::size_of::<T::Native>(),
        Arc::new(()),
    );
    let values = ScalarBuffer::<T::Native>::new(buffer, 0, row_count);
    Arc::new(PrimitiveArray::<T>::new(values, None))
}

/// A Float64 array holding the R doubles verbatim, with the field document
/// marking NaN-payload missing storage. Used whenever tagged NAs must survive
/// bit-exactly. The values buffer aliases the R vector; see
/// [`zero_copy_array`] for the lifetime contract.
unsafe fn payload_double_column(
    values: &[f64],
    mut field: ArrowFieldDocument,
    class: &str,
) -> (Option<ArrowFieldDocument>, ArrayRef) {
    field.missing = Some(ArrowMissingEncoding::Payload);
    field.r = r_semantics(class);
    (
        Some(field),
        zero_copy_array::<Float64Type>(values.as_ptr(), values.len()),
    )
}

/// A nullable Float64 array: R `NA` (missing code 0) becomes an Arrow null,
/// every other value — plain NaN included — keeps its bits. Columns without
/// `NA` alias the R vector; see [`zero_copy_array`] for the lifetime
/// contract.
unsafe fn semantic_double_array(values: &[f64], codes: &[c_int]) -> ArrayRef {
    if codes.iter().all(|&code| code != 0) {
        return zero_copy_array::<Float64Type>(values.as_ptr(), values.len());
    }
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
/// Pure: callable from any thread.
fn encode_profiled_column(
    name: &str,
    storage: StataStorage,
    temporal: TemporalKind,
    values: &[f64],
    codes: &[c_int],
) -> Result<(ArrayRef, u64, Option<FormatVersion>), String> {
    let dta_type = storage.dta_type();
    let (shift, scale) = temporal_shift_scale(temporal);
    let legacy_layout = eager_legacy_layout_conflicts(storage, shift, scale, values, codes);
    let mut replacements = 0_u64;
    let mut encoded = Vec::new();
    encoded
        .try_reserve_exact(values.len())
        .map_err(|_| "could not allocate a profiled column".to_owned())?;
    for (&value, &code) in values.iter().zip(codes) {
        let source = match missing_from_code(code) {
            Ok(Some(tag)) if legacy_layout && tag != MissingTag::System => {
                return Err(format!(
                    "column `{name}` cannot combine legacy tail values with extended missing `{tag}`"
                ));
            }
            Ok(Some(tag)) => DtaWriteNumericValue::Missing(tag),
            Ok(None) => {
                let encoded_value = write_numeric_value(value, shift, scale);
                if dta_write_numeric_value_is_representable(&dta_type, encoded_value)
                    || (legacy_layout
                        && legacy_observed_value_is_representable(storage, encoded_value))
                {
                    DtaWriteNumericValue::Value(encoded_value)
                } else {
                    replacements += 1;
                    DtaWriteNumericValue::Missing(MissingTag::System)
                }
            }
            Err(_) => {
                replacements += 1;
                DtaWriteNumericValue::Missing(MissingTag::System)
            }
        };
        encoded.push(
            if legacy_layout && source == DtaWriteNumericValue::Missing(MissingTag::System) {
                legacy_system_missing(storage)
            } else {
                encode_numeric(&dta_type, source)
            },
        );
    }
    let array: ArrayRef =
        match storage {
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
    Ok((
        array,
        replacements,
        legacy_layout.then_some(FormatVersion::V111),
    ))
}

fn legacy_system_missing(storage: StataStorage) -> DtaWriteRawNumericValue {
    match storage {
        StataStorage::Byte => DtaWriteRawNumericValue::Byte(i8::MAX),
        StataStorage::Int => DtaWriteRawNumericValue::Int(i16::MAX),
        StataStorage::Long => DtaWriteRawNumericValue::Long(i32::MAX),
        StataStorage::Float => {
            DtaWriteRawNumericValue::Float(f32::from_bits(MissingTag::System.float_bits()))
        }
        StataStorage::Double => {
            DtaWriteRawNumericValue::Double(f64::from_bits(MissingTag::System.double_bits()))
        }
    }
}

fn legacy_observed_value_is_representable(storage: StataStorage, value: f64) -> bool {
    if !value.is_finite() || value.fract() != 0.0 {
        return false;
    }
    match storage {
        StataStorage::Byte
            if (f64::from(-MissingTag::Z.byte_value())..=f64::from(i8::MAX - 1))
                .contains(&value) =>
        {
            classify_byte_missing_for_version(value as i8, FormatVersion::V111).is_none()
        }
        StataStorage::Int
            if (f64::from(-MissingTag::Z.int_value())..=f64::from(i16::MAX - 1))
                .contains(&value) =>
        {
            classify_int_missing_for_version(value as i16, FormatVersion::V111).is_none()
        }
        StataStorage::Long
            if (f64::from(-MissingTag::Z.long_value())..=f64::from(i32::MAX - 1))
                .contains(&value) =>
        {
            classify_long_missing_for_version(value as i32, FormatVersion::V111).is_none()
        }
        _ => false,
    }
}

fn eager_legacy_layout_conflicts(
    storage: StataStorage,
    shift: f64,
    scale: f64,
    values: &[f64],
    codes: &[c_int],
) -> bool {
    values.iter().zip(codes).any(|(&value, &code)| {
        missing_from_code(code).ok() == Some(None) && {
            let encoded = write_numeric_value(value, shift, scale);
            legacy_observed_value_is_representable(storage, encoded)
                && !dta_write_numeric_value_is_representable(&storage.dta_type(), encoded)
        }
    })
}

fn legacy_layout_conflicts<T: Copy>(
    values: &[T],
    version: FormatVersion,
    classify: impl Fn(T, FormatVersion) -> Option<MissingTag>,
) -> bool {
    values.iter().any(|&value| {
        classify(value, version).is_none() && classify(value, FormatVersion::V118).is_some()
    })
}

/// Copy a compact ALTREP backing into an Arrow array. Legacy missing values
/// are normalized to the modern layout unless an observed value would collide
/// with a modern sentinel; those columns retain the legacy layout and record
/// its canonical release in the field document.
/// Pure: callable from any thread.
unsafe fn compact_profiled_column(
    base: *const c_void,
    kind: NumericKind,
    version: FormatVersion,
    row_count: usize,
) -> Result<(ArrayRef, StataStorage, Option<FormatVersion>), String> {
    // Modern formats already store the sentinels the profile uses, so the
    // per-value normalization below is the identity map and the R-owned
    // backing can be aliased directly (see `zero_copy_array`).
    let legacy = matches!(
        version,
        FormatVersion::V105 | FormatVersion::V108 | FormatVersion::V110 | FormatVersion::V111
    );
    if !legacy {
        let (array, storage): (ArrayRef, StataStorage) = match kind {
            NumericKind::Byte => (
                zero_copy_array::<Int8Type>(base.cast::<i8>(), row_count),
                StataStorage::Byte,
            ),
            NumericKind::Int => (
                zero_copy_array::<Int16Type>(base.cast::<i16>(), row_count),
                StataStorage::Int,
            ),
            NumericKind::Long => (
                zero_copy_array::<Int32Type>(base.cast::<i32>(), row_count),
                StataStorage::Long,
            ),
            NumericKind::Float => (
                zero_copy_array::<Float32Type>(base.cast::<f32>(), row_count),
                StataStorage::Float,
            ),
        };
        return Ok((array, storage, None));
    }
    let layout_conflicts = match kind {
        NumericKind::Byte => legacy_layout_conflicts(
            std::slice::from_raw_parts(base.cast::<i8>(), row_count),
            version,
            classify_byte_missing_for_version,
        ),
        NumericKind::Int => legacy_layout_conflicts(
            std::slice::from_raw_parts(base.cast::<i16>(), row_count),
            version,
            classify_int_missing_for_version,
        ),
        NumericKind::Long => legacy_layout_conflicts(
            std::slice::from_raw_parts(base.cast::<i32>(), row_count),
            version,
            classify_long_missing_for_version,
        ),
        NumericKind::Float => legacy_layout_conflicts(
            std::slice::from_raw_parts(base.cast::<f32>(), row_count),
            version,
            |value, format| classify_float_missing_bits_for_version(value.to_bits(), format),
        ),
    };
    if layout_conflicts {
        let (array, storage): (ArrayRef, StataStorage) = match kind {
            NumericKind::Byte => (
                zero_copy_array::<Int8Type>(base.cast::<i8>(), row_count),
                StataStorage::Byte,
            ),
            NumericKind::Int => (
                zero_copy_array::<Int16Type>(base.cast::<i16>(), row_count),
                StataStorage::Int,
            ),
            NumericKind::Long => (
                zero_copy_array::<Int32Type>(base.cast::<i32>(), row_count),
                StataStorage::Long,
            ),
            NumericKind::Float => (
                zero_copy_array::<Float32Type>(base.cast::<f32>(), row_count),
                StataStorage::Float,
            ),
        };
        return Ok((array, storage, Some(FormatVersion::V111)));
    }
    let (array, storage): (ArrayRef, StataStorage) = match kind {
        NumericKind::Byte => {
            let values = std::slice::from_raw_parts(base.cast::<i8>(), row_count);
            let normalized = values.iter().map(|&value| {
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
            let normalized = values.iter().map(|&value| {
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
            let normalized = values.iter().map(|&value| {
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
            let normalized = values.iter().map(|&value| {
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
    Ok((array, storage, None))
}

unsafe fn value_label_table(
    descriptor: &RArrowValueLabelTableDescriptor,
    name: &str,
) -> Result<ValueLabelTable, String> {
    if descriptor.label_count == 0 {
        return Ok(ValueLabelTable {
            name: name.to_owned(),
            entries: Vec::new(),
        });
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
    for (index, (&code, text)) in codes.iter().zip(texts).enumerate() {
        poll_interrupt(index)?;
        let label = text
            .ok_or_else(|| format!("table `{name}` has a missing value-label text"))?;
        let entry = match missing_from_code(direct_r_missing_code(code))? {
            Some(tag) => ValueLabelEntry {
                value: 0,
                missing_tag: Some(tag),
                label,
            },
            None => {
                if code.fract() != 0.0 || code < f64::from(i32::MIN) || code > f64::from(i32::MAX) {
                    return Err(format!("table `{name}` has a non-integer value-label code"));
                }
                let value = code as i32;
                ValueLabelEntry {
                    value,
                    missing_tag: None,
                    label,
                }
            }
        };
        entries.push(entry);
    }
    Ok(ValueLabelTable {
        name: name.to_owned(),
        entries,
    })
}

/// Everything one column's encoding needs, captured on the R thread. The raw
/// pointers address R vector data that the caller's column specification
/// keeps protected for the duration of the save call, and `encode_column`
/// never calls the R API, so encoding may run on a worker thread.
enum ColumnInput {
    Logical {
        values: *const c_int,
    },
    Integer {
        values: *const c_int,
    },
    LabelledInteger {
        values: *const c_int,
    },
    /// Double, Date, Datetime, and Difftime columns; `kind` disambiguates.
    DoubleLike {
        values: *const f64,
    },
    CharacterEager {
        values: Vec<Option<String>>,
    },
    CharacterDict {
        data: *const c_void,
    },
    Raw {
        values: *const u8,
    },
    Factor {
        codes: *const c_int,
        levels: Vec<Option<String>>,
    },
    ProfiledEager {
        values: *const f64,
        storage: StataStorage,
    },
    ProfiledCompact {
        values: *const c_void,
        kind: NumericKind,
        version: FormatVersion,
    },
}

struct ColumnMetadata {
    name: String,
    kind: RArrowKind,
    tz: Option<String>,
    units: String,
    ordered: bool,
    haven_labelled: bool,
    base_document: ArrowFieldDocument,
    compact_version: Option<FormatVersion>,
}

struct ExtractedColumn {
    name: String,
    kind: RArrowKind,
    tz: Option<String>,
    units: String,
    ordered: bool,
    haven_labelled: bool,
    base_document: ArrowFieldDocument,
    input: ColumnInput,
    row_count: usize,
}

unsafe impl Send for ExtractedColumn {}
unsafe impl Sync for ExtractedColumn {}

/// Pull one column's metadata out of R without inspecting its cell arrays.
unsafe fn extract_column_metadata(
    descriptor: &RArrowColumnDescriptor,
    value_label_names: &[String],
) -> Result<ColumnMetadata, String> {
    let name = required_c_string(descriptor.name, "a column name")?;
    let kind = RArrowKind::try_from(descriptor.kind)?;
    let label = optional_c_string(descriptor.label, "a variable label")?;
    let format = optional_c_string(descriptor.format, "a display format")?;
    let tz = if descriptor.tz.is_null() {
        None
    } else {
        Some(required_c_string(descriptor.tz, "a time zone")?)
    };
    let units = optional_c_string(descriptor.units, "difftime units")?;
    let compact_version =
        if kind == RArrowKind::StataNumeric && !descriptor.compact_values.is_null() {
            Some(
                u16::try_from(descriptor.compact_format_version)
                    .ok()
                    .and_then(|value| FormatVersion::try_from(value).ok())
                    .ok_or_else(|| "invalid compact numeric format version".to_owned())?,
            )
        } else {
            None
        };
    let (notes, characteristics) = parse_stata_metadata_sexp(descriptor.stata_metadata)?;
    let value_label_index = if descriptor.value_label_index == -1 {
        None
    } else {
        let index = usize::try_from(descriptor.value_label_index)
            .map_err(|_| format!("column `{name}` has an invalid value-label table index"))?;
        if index >= value_label_names.len() {
            return Err(format!(
                "column `{name}` has an out-of-range value-label table index"
            ));
        }
        Some(index)
    };
    let string_storage = match descriptor.string_storage {
        -1 => None,
        0 => Some("strL".to_owned()),
        1..=2045 => Some(format!("str{}", descriptor.string_storage)),
        _ => return Err(format!("column `{name}` has invalid string storage")),
    };
    let mut base_document = base_field_document(label, format, notes, characteristics);
    if let Some(index) = value_label_index {
        base_document.value_labels = Some(value_label_names[index].clone());
    }
    if kind == RArrowKind::Character {
        base_document.string_storage = string_storage;
    }
    match kind {
        RArrowKind::Integer => base_document.r = r_semantics("integer"),
        RArrowKind::LabelledInteger => {
            base_document.missing = Some(ArrowMissingEncoding::Payload);
            base_document.r = r_semantics("haven_labelled");
        }
        RArrowKind::Double if descriptor.haven_labelled != 0 => {
            base_document.r = r_semantics("haven_labelled");
        }
        RArrowKind::Datetime => {
            base_document.r = r_semantics("POSIXct");
            if let Some(semantics) = base_document.r.as_mut() {
                semantics.tz.clone_from(&tz);
            }
        }
        RArrowKind::Difftime => {
            base_document.r = r_semantics("difftime");
            if let Some(semantics) = base_document.r.as_mut() {
                semantics.units = Some(units.clone());
            }
        }
        RArrowKind::Raw => base_document.r = r_semantics("raw"),
        RArrowKind::Factor => {
            base_document.r = Some(ArrowRSemantics {
                class: "factor".to_owned(),
                ordered: Some(descriptor.ordered != 0),
                tz: None,
                units: None,
            });
        }
        _ => {}
    }
    Ok(ColumnMetadata {
        name,
        kind,
        tz,
        units,
        ordered: descriptor.ordered != 0,
        haven_labelled: descriptor.haven_labelled != 0,
        base_document,
        compact_version,
    })
}

/// Capture one column's cell input after the metadata-only footer preflight.
unsafe fn extract_column(
    descriptor: &RArrowColumnDescriptor,
    row_count: usize,
    metadata: ColumnMetadata,
) -> Result<ExtractedColumn, String> {
    let ColumnMetadata {
        name,
        kind,
        tz,
        units,
        ordered,
        haven_labelled,
        base_document,
        compact_version,
    } = metadata;
    let input = match kind {
        RArrowKind::Logical => ColumnInput::Logical {
            values: int_slice(descriptor, row_count)?.as_ptr(),
        },
        RArrowKind::Integer => ColumnInput::Integer {
            values: int_slice(descriptor, row_count)?.as_ptr(),
        },
        RArrowKind::LabelledInteger => ColumnInput::LabelledInteger {
            values: int_slice(descriptor, row_count)?.as_ptr(),
        },
        RArrowKind::Double | RArrowKind::Date | RArrowKind::Datetime | RArrowKind::Difftime => {
            ColumnInput::DoubleLike {
                values: double_slice(descriptor, row_count)?.as_ptr(),
            }
        }
        RArrowKind::Character => {
            if descriptor.dictstring.is_null() {
                ColumnInput::CharacterEager {
                    values: read_strings(descriptor.strings, row_count, "character values")?,
                }
            } else {
                ColumnInput::CharacterDict {
                    data: descriptor.dictstring,
                }
            }
        }
        RArrowKind::Raw => {
            if descriptor.values.is_null() {
                return Err("native Arrow column data pointer is null".to_owned());
            }
            ColumnInput::Raw {
                values: descriptor.values.cast::<u8>(),
            }
        }
        RArrowKind::Factor => ColumnInput::Factor {
            codes: int_slice(descriptor, row_count)?.as_ptr(),
            levels: read_strings(descriptor.strings, descriptor.string_count, "factor levels")?,
        },
        RArrowKind::StataNumeric => {
            if descriptor.compact_values.is_null() {
                let storage = storage_from_code(descriptor.storage)?
                    .ok_or_else(|| format!("column `{name}` has no declared Stata storage"))?;
                ColumnInput::ProfiledEager {
                    values: double_slice(descriptor, row_count)?.as_ptr(),
                    storage,
                }
            } else {
                ColumnInput::ProfiledCompact {
                    values: descriptor.compact_values,
                    kind: NumericKind::try_from(descriptor.compact_kind)?,
                    version: compact_version
                        .ok_or_else(|| "compact numeric version is missing".to_owned())?,
                }
            }
        }
    };

    Ok(ExtractedColumn {
        name,
        kind,
        tz,
        units,
        ordered,
        haven_labelled,
        base_document,
        input,
        row_count,
    })
}

/// Encode one extracted column into its Arrow array and field document.
/// Pure: never calls the R API, so it may run on a worker thread.
unsafe fn encode_column(mut column: ExtractedColumn) -> Result<EncodedColumn, String> {
    let name = &column.name;
    let row_count = column.row_count;
    let base_document = std::mem::take(&mut column.base_document);
    let profiled_temporal = temporal_kind(&base_document.format);
    let needs_document = |document: &ArrowFieldDocument| *document != ArrowFieldDocument::default();

    let (field, array, replaced): (Option<ArrowFieldDocument>, ArrayRef, u64) = match &column.input
    {
        ColumnInput::Logical { values } => {
            let values = std::slice::from_raw_parts(*values, row_count);
            let mut builder = BooleanBuilder::with_capacity(row_count);
            for &value in values {
                if value == R_NaInt {
                    builder.append_null();
                } else {
                    builder.append_value(value != 0);
                }
            }
            let document = base_document;
            (
                needs_document(&document).then_some(document),
                Arc::new(builder.finish()) as ArrayRef,
                0,
            )
        }
        ColumnInput::Integer { values } => {
            let values = std::slice::from_raw_parts(*values, row_count);
            // NA-free columns alias the R vector; see `zero_copy_array`.
            let array: ArrayRef = if values.iter().all(|&value| value != R_NaInt) {
                zero_copy_array::<Int32Type>(values.as_ptr(), row_count)
            } else {
                Arc::new(Int32Array::from_iter(
                    values
                        .iter()
                        .map(|&value| (value != R_NaInt).then_some(value)),
                ))
            };
            let mut document = base_document;
            document.r = r_semantics("integer");
            (Some(document), array, 0)
        }
        ColumnInput::LabelledInteger { values } => {
            let values = std::slice::from_raw_parts(*values, row_count);
            let mut document = base_document;
            document.missing = Some(ArrowMissingEncoding::Payload);
            document.r = r_semantics("haven_labelled");
            let array = Float64Array::from_iter_values(values.iter().map(|&value| {
                if value == R_NaInt {
                    r_missing(MissingTag::System)
                } else {
                    f64::from(value)
                }
            }));
            (Some(document), Arc::new(array), 0)
        }
        ColumnInput::DoubleLike { values } => {
            let values = std::slice::from_raw_parts(*values, row_count);
            let (codes, has_tags) = classify_doubles(values, name)?;
            let kind = column.kind;
            let class = match kind {
                RArrowKind::Double if column.haven_labelled => "haven_labelled",
                RArrowKind::Double => "double",
                RArrowKind::Date => "Date",
                RArrowKind::Datetime => "POSIXct",
                RArrowKind::Difftime => "difftime",
                _ => unreachable!("double kinds"),
            };
            let mut document = base_document;
            if kind == RArrowKind::Datetime {
                document.r = r_semantics(class);
                if let Some(semantics) = document.r.as_mut() {
                    semantics.tz.clone_from(&column.tz);
                }
            } else if kind == RArrowKind::Difftime {
                document.r = r_semantics(class);
                if let Some(semantics) = document.r.as_mut() {
                    semantics.units = Some(column.units.clone());
                }
            } else if class == "haven_labelled" {
                document.r = r_semantics(class);
            }
            let payload_labels = kind == RArrowKind::Double && document.value_labels.is_some();
            if has_tags || payload_labels {
                // Tagged NAs and haven labels need bit-exact NaN payloads.
                let (mut field, array) = payload_double_column(values, document, class);
                if let Some(semantics) = field.as_mut().and_then(|document| document.r.as_mut()) {
                    if kind == RArrowKind::Datetime {
                        semantics.tz.clone_from(&column.tz);
                    } else if kind == RArrowKind::Difftime {
                        semantics.units = Some(column.units.clone());
                    }
                }
                (field, array, 0)
            } else {
                match kind {
                    RArrowKind::Double => {
                        let array = semantic_double_array(values, &codes);
                        (needs_document(&document).then_some(document), array, 0)
                    }
                    RArrowKind::Date => date32_or_fallback(values, &codes, document),
                    RArrowKind::Datetime => {
                        timestamp_or_fallback(values, &codes, document, column.tz.as_deref())
                    }
                    RArrowKind::Difftime => {
                        duration_or_fallback(values, &codes, document, &column.units)?
                    }
                    _ => unreachable!("double kinds"),
                }
            }
        }
        ColumnInput::CharacterEager { values } => {
            let document = base_document;
            (
                needs_document(&document).then_some(document),
                string_array(values, name)?,
                0,
            )
        }
        ColumnInput::CharacterDict { data } => {
            let data = &*data.cast::<crate::DictStringData>();
            let array = dictstring_array(data, row_count, name)?;
            let document = base_document;
            (needs_document(&document).then_some(document), array, 0)
        }
        ColumnInput::Raw { values } => {
            let array = zero_copy_array::<UInt8Type>(*values, row_count);
            let mut document = base_document;
            document.r = r_semantics("raw");
            (Some(document), array, 0)
        }
        ColumnInput::Factor { codes, levels } => {
            let codes = std::slice::from_raw_parts(*codes, row_count);
            let mut builder = Int32Builder::with_capacity(row_count);
            for &code in codes {
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
            let values = string_array(levels, name)?;
            let array = DictionaryArray::try_new(builder.finish(), values)
                .map_err(|error| error.to_string())?;
            let mut document = base_document;
            document.r = Some(ArrowRSemantics {
                class: "factor".to_owned(),
                ordered: Some(column.ordered),
                tz: None,
                units: None,
            });
            (Some(document), Arc::new(array), 0)
        }
        ColumnInput::ProfiledEager { values, storage } => {
            let values = std::slice::from_raw_parts(*values, row_count);
            let (codes, _) = classify_doubles(values, name)?;
            let (array, replacements, missing_release) =
                encode_profiled_column(name, *storage, profiled_temporal, values, &codes)?;
            let mut document = base_document;
            document.storage = Some(*storage);
            document.missing = Some(field_missing_for_storage(*storage));
            document.missing_release = missing_release;
            (Some(document), array, replacements)
        }
        ColumnInput::ProfiledCompact {
            values,
            kind,
            version,
        } => {
            let (array, storage, missing_release) =
                compact_profiled_column(*values, *kind, *version, row_count)?;
            let mut document = base_document;
            document.storage = Some(storage);
            document.missing = Some(field_missing_for_storage(storage));
            document.missing_release = missing_release;
            (Some(document), array, 0)
        }
    };
    Ok(EncodedColumn {
        name: column.name,
        field,
        array,
        replaced,
    })
}

// Automatic-parallelism thresholds for the encode phase, matching the fill
// phase's policy.
const MIN_PARALLEL_ENCODE_CELLS: u64 = 1_000_000;
const MAX_AUTOMATIC_ENCODE_THREADS: usize = 8;

fn encode_thread_count(requested: usize, task_count: usize, row_count: usize) -> usize {
    if requested == 1 || task_count < 2 {
        return 1;
    }
    let cells = (row_count as u64).saturating_mul(task_count as u64);
    if requested == 0 && cells < MIN_PARALLEL_ENCODE_CELLS {
        return 1;
    }
    let available = thread::available_parallelism().map_or(1, usize::from);
    let threads = if requested == 0 {
        available.min(MAX_AUTOMATIC_ENCODE_THREADS)
    } else {
        requested.min(available)
    };
    threads.min(task_count).max(1)
}

struct EncodedColumn {
    name: String,
    field: Option<ArrowFieldDocument>,
    array: ArrayRef,
    replaced: u64,
}

/// Claim encode tasks from the shared queue. `poll` runs between tasks; on
/// the R thread it checks interrupts, on workers it only observes the cancel
/// flag set by the other loops.
fn encode_task_loop(
    columns: &[std::sync::Mutex<Option<ExtractedColumn>>],
    next: &AtomicUsize,
    cancelled: &AtomicBool,
    mut poll: impl FnMut() -> bool,
) -> Result<Vec<(usize, EncodedColumn)>, String> {
    let mut results = Vec::new();
    loop {
        if poll() {
            cancelled.store(true, Ordering::Relaxed);
            return Err("Arrow write interrupted".to_owned());
        }
        if cancelled.load(Ordering::Relaxed) {
            return Ok(results);
        }
        let index = next.fetch_add(1, Ordering::Relaxed);
        let Some(column) = columns.get(index) else {
            return Ok(results);
        };
        let column = column
            .lock()
            .map_err(|_| "an Arrow encode task was poisoned".to_owned())?
            .take()
            .ok_or_else(|| "an Arrow encode task was claimed twice".to_owned())?;
        match unsafe { encode_column(column) } {
            Ok(encoded) => results.push((index, encoded)),
            Err(error) => {
                cancelled.store(true, Ordering::Relaxed);
                return Err(error);
            }
        }
    }
}

/// Encode every extracted column, in parallel when `threads` allows it. The
/// R thread participates in the queue and is the only interrupt poller.
fn run_column_encodes(
    columns: Vec<ExtractedColumn>,
    threads: usize,
) -> Result<Vec<EncodedColumn>, String> {
    if threads <= 1 {
        let mut encoded = Vec::with_capacity(columns.len());
        for column in columns {
            check_interrupt()?;
            encoded.push(unsafe { encode_column(column) }?);
        }
        return Ok(encoded);
    }
    let columns = columns
        .into_iter()
        .map(|column| std::sync::Mutex::new(Some(column)))
        .collect::<Vec<_>>();
    let next = AtomicUsize::new(0);
    let cancelled = AtomicBool::new(false);
    let columns = &columns;
    let (own_result, worker_results) = thread::scope(|scope| {
        let handles: Vec<_> = (1..threads)
            .map(|_| {
                let next = &next;
                let cancelled = &cancelled;
                scope.spawn(move || encode_task_loop(columns, next, cancelled, || false))
            })
            .collect();
        let own = encode_task_loop(columns, &next, &cancelled, coarse_interrupt);
        if own.is_err() {
            cancelled.store(true, Ordering::Relaxed);
        }
        let worker_results: Vec<_> = handles
            .into_iter()
            .map(|handle| {
                handle
                    .join()
                    .unwrap_or_else(|_| Err("an Arrow encode worker panicked".to_owned()))
            })
            .collect();
        (own, worker_results)
    });
    let mut slots: Vec<Option<EncodedColumn>> = columns.iter().map(|_| None).collect();
    let mut store = |results: Vec<(usize, EncodedColumn)>| {
        for (index, encoded) in results {
            slots[index] = Some(encoded);
        }
    };
    // Surface the R thread's error (interrupts included) first, then any
    // worker error.
    store(own_result?);
    for result in worker_results {
        store(result?);
    }
    slots
        .into_iter()
        .map(|slot| slot.ok_or_else(|| "an encode task produced no result".to_owned()))
        .collect()
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
    tz: Option<&str>,
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
        let array =
            TimestampMicrosecondArray::from_iter(values.iter().zip(codes).map(
                |(&value, &code)| (code != 0).then(|| to_micros(value).expect("checked above")),
            ));
        let array = match tz {
            None => array,
            Some("") => array.with_timezone_utc(),
            Some(tz) => array.with_timezone(tz),
        };
        (needs_document_or_none(document), Arc::new(array), 0)
    } else {
        document.r = r_semantics("POSIXct");
        if let Some(semantics) = document.r.as_mut() {
            semantics.tz = tz.map(str::to_owned);
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
) -> Result<(Option<ArrowFieldDocument>, ArrayRef, u64), String> {
    document.r = r_semantics("difftime");
    if let Some(semantics) = document.r.as_mut() {
        semantics.units = Some(units.to_owned());
    }
    let seconds_per_unit = difftime_seconds_per_unit(units)?;
    let to_nanos = |value: f64| -> Option<i64> {
        let scaled = value * seconds_per_unit * 1_000_000_000.0;
        if !scaled.is_finite() {
            return None;
        }
        let rounded = scaled.round();
        if rounded < -9.2e18
            || rounded > 9.2e18
            || rounded / 1_000_000_000.0 / seconds_per_unit != value
        {
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
    Ok((Some(document), array, 0))
}

fn difftime_seconds_per_unit(units: &str) -> Result<f64, String> {
    match units {
        "secs" => Ok(1.0),
        "mins" => Ok(60.0),
        "hours" => Ok(3_600.0),
        "days" => Ok(86_400.0),
        "weeks" => Ok(604_800.0),
        _ => Err(format!("unsupported difftime units `{units}`")),
    }
}

fn insert_value_label_tables(
    dataset: &mut DatasetDocument,
    tables: Vec<ValueLabelTable>,
) -> Result<(), String> {
    for table in tables {
        dataset
            .insert_value_label_table(table)
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

/// Shared write-driver front half: parse the dataset documents, extract every
/// column on this thread (the only one that may touch the R API), encode into
/// Arrow arrays on workers, and assemble the write dataset plus the
/// per-column numeric replacement counts. Arrow saves request the footer
/// preflight before cell extraction; datasig assembly has no footer and does
/// not inherit the file-format size limit.
///
/// # Safety
///
/// The same descriptor, label, and notes contracts as
/// [`dtatools_save_arrow_rust`].
unsafe fn assemble_write_dataset(
    dataset_label: *const c_char,
    output_container: *const c_char,
    dataset_metadata: Sexp,
    descriptors: &[RArrowColumnDescriptor],
    table_descriptors: &[RArrowValueLabelTableDescriptor],
    row_count: usize,
    requested_threads: usize,
    preflight_footer: bool,
) -> Result<(ArrowWriteDataset, Vec<u64>, Option<ArrowMetadataPreflight>), String> {
    let column_count = descriptors.len();
    let mut dataset = DatasetDocument {
        version: 0,
        label: optional_c_string(dataset_label, "the dataset label")?,
        output_container: if output_container.is_null() {
            None
        } else {
            Some(required_c_string(output_container, "the output container")?)
        },
        ..DatasetDocument::default()
    };
    (dataset.notes, dataset.characteristics) = parse_stata_metadata_sexp(dataset_metadata)?;

    let value_label_names = table_descriptors
        .iter()
        .map(|descriptor| required_c_string(descriptor.name, "a value-label table name"))
        .collect::<Result<Vec<_>, _>>()?;
    let value_label_tables = table_descriptors
        .iter()
        .zip(&value_label_names)
        .map(|(descriptor, name)| value_label_table(descriptor, name))
        .collect::<Result<Vec<_>, _>>()?;
    insert_value_label_tables(&mut dataset, value_label_tables)?;
    let mut column_metadata = Vec::new();
    column_metadata
        .try_reserve_exact(column_count)
        .map_err(|_| "could not allocate column metadata".to_owned())?;
    for descriptor in descriptors {
        check_interrupt()?;
        column_metadata.push(extract_column_metadata(descriptor, &value_label_names)?);
    }
    let metadata_preflight = if preflight_footer {
        Some(
            preflight_arrow_metadata(
                &dataset,
                column_metadata.iter().map(|column| {
                    let document = (column.base_document != ArrowFieldDocument::default())
                        .then_some(&column.base_document);
                    (column.name.as_str(), document)
                }),
            )
            .map_err(|error| error.to_string())?,
        )
    } else {
        None
    };
    let mut extracted = Vec::new();
    extracted
        .try_reserve_exact(column_count)
        .map_err(|_| "could not allocate column inputs".to_owned())?;
    for (descriptor, metadata) in descriptors.iter().zip(column_metadata) {
        check_interrupt()?;
        let column = extract_column(descriptor, row_count, metadata)?;
        extracted.push(column);
    }

    let threads = encode_thread_count(requested_threads, column_count, row_count);
    let encoded = run_column_encodes(extracted, threads)?;

    let mut write_columns = Vec::new();
    write_columns
        .try_reserve_exact(column_count)
        .map_err(|_| "could not allocate output columns".to_owned())?;
    let mut replacements = Vec::new();
    replacements
        .try_reserve_exact(column_count)
        .map_err(|_| "could not allocate replacement counts".to_owned())?;
    for column in encoded {
        replacements.push(column.replaced);
        write_columns.push(ArrowWriteColumn {
            name: column.name,
            field: column.field,
            array: column.array,
        });
    }

    Ok((
        ArrowWriteDataset {
            dataset,
            columns: write_columns,
        },
        replacements,
        metadata_preflight,
    ))
}

#[no_mangle]
/// Compute the order-sensitive content signature of an R dataset.
///
/// # Safety
///
/// The same contracts as [`dtatools_save_arrow_rust`], minus the path and
/// compression strings. `interrupted` must point to writable status storage.
pub unsafe extern "C" fn dtatools_datasig_rust(
    dataset_label: *const c_char,
    dataset_metadata: Sexp,
    columns: *const RArrowColumnDescriptor,
    column_count: usize,
    value_label_tables: *const RArrowValueLabelTableDescriptor,
    value_label_table_count: usize,
    row_count: usize,
    requested_threads: c_int,
    interrupted: *mut c_int,
    error: *mut *mut c_char,
) -> Sexp {
    arrow_boundary(interrupted, error, ptr::null_mut(), || {
        if columns.is_null() && column_count > 0 {
            return Err("column descriptor pointer is null".to_owned());
        }
        if value_label_tables.is_null() && value_label_table_count > 0 {
            return Err("value-label table descriptor pointer is null".to_owned());
        }
        let descriptors = if column_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(columns, column_count)
        };
        let table_descriptors = if value_label_table_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(value_label_tables, value_label_table_count)
        };
        let requested_threads =
            usize::try_from(requested_threads).map_err(|_| "invalid thread count".to_owned())?;
        let (dataset, replacements, metadata_preflight) = assemble_write_dataset(
            dataset_label,
            ptr::null(),
            dataset_metadata,
            descriptors,
            table_descriptors,
            row_count,
            requested_threads,
            false,
        )?;
        debug_assert!(metadata_preflight.is_none());
        if replacements.iter().any(|&count| count > 0) {
            let details = dataset
                .columns
                .iter()
                .zip(&replacements)
                .filter(|(_, count)| **count > 0)
                .map(|(column, count)| format!("`{}` ({count})", column.name))
                .collect::<Vec<_>>()
                .join(", ");
            return Err(format!(
                "cannot compute datasig after lossy numeric replacements in {details}"
            ));
        }
        let signature = dataset_signature(&dataset, requested_threads, &mut coarse_interrupt)
            .map_err(|error| error.to_string())?;
        let mut guard = ProtectGuard::new();
        scalar_string(&signature, &mut guard)
    })
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
/// `dataset_metadata` must be a protected STRSXP holding one complete internal
/// Stata metadata envelope.
/// `interrupted` must point to writable status storage. If non-null, `error`
/// must point to writable storage for one C string pointer. The caller must
/// run on R's main thread with an initialized R runtime.
pub unsafe extern "C" fn dtatools_save_arrow_rust(
    path: *const c_char,
    dataset_label: *const c_char,
    output_container: *const c_char,
    dataset_metadata: Sexp,
    columns: *const RArrowColumnDescriptor,
    column_count: usize,
    value_label_tables: *const RArrowValueLabelTableDescriptor,
    value_label_table_count: usize,
    row_count: usize,
    compression: *const c_char,
    requested_threads: c_int,
    checksums: c_int,
    interrupted: *mut c_int,
    error: *mut *mut c_char,
) -> Sexp {
    arrow_boundary(interrupted, error, ptr::null_mut(), || {
        let path = required_c_string(path, "the output path")?;
        let compression_label = required_c_string(compression, "the compression label")?;
        let compression = ArrowCompression::from_label(&compression_label)
            .ok_or_else(|| format!("unknown compression `{compression_label}`"))?;
        if columns.is_null() && column_count > 0 {
            return Err("column descriptor pointer is null".to_owned());
        }
        if value_label_tables.is_null() && value_label_table_count > 0 {
            return Err("value-label table descriptor pointer is null".to_owned());
        }
        let descriptors = if column_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(columns, column_count)
        };
        let table_descriptors = if value_label_table_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(value_label_tables, value_label_table_count)
        };

        let requested_threads =
            usize::try_from(requested_threads).map_err(|_| "invalid thread count".to_owned())?;
        let (dataset, replacements, metadata_preflight) = assemble_write_dataset(
            dataset_label,
            output_container,
            dataset_metadata,
            descriptors,
            table_descriptors,
            row_count,
            requested_threads,
            true,
        )?;
        let metadata_preflight =
            metadata_preflight.expect("Arrow save assembly requested a metadata preflight");
        save_arrow_file_with_preflight(
            &path,
            &dataset,
            metadata_preflight,
            compression,
            requested_threads,
            checksums != 0,
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

#[no_mangle]
/// Open an Arrow file once so metadata selection and decoding share its file
/// identity even if another process replaces the path.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C byte string for the
/// duration of this call. If non-null, `error` must point to writable storage
/// for one C string pointer.
pub unsafe extern "C" fn dtatools_open_arrow_rust(
    path: *const c_char,
    error: *mut *mut c_char,
) -> *mut c_void {
    boundary(error, ptr::null_mut(), || {
        let path = required_c_string(path, "the input path")?;
        let snapshot = ArrowFileSnapshot::open(&path).map_err(|error| error.to_string())?;
        Ok(Box::into_raw(Box::new(snapshot)).cast::<c_void>())
    })
}

#[no_mangle]
/// Release an Arrow snapshot returned by [`dtatools_open_arrow_rust`].
///
/// # Safety
///
/// A non-null `snapshot` must be an owned pointer returned by
/// [`dtatools_open_arrow_rust`] that has not already been released.
pub unsafe extern "C" fn dtatools_close_arrow_rust(snapshot: *mut c_void) {
    if !snapshot.is_null() {
        drop(Box::from_raw(snapshot.cast::<ArrowFileSnapshot>()));
    }
}

unsafe fn required_arrow_snapshot<'a>(
    snapshot: *const c_void,
) -> Result<&'a ArrowFileSnapshot, String> {
    snapshot
        .cast::<ArrowFileSnapshot>()
        .as_ref()
        .ok_or_else(|| "Arrow file snapshot is null".to_owned())
}

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
    value_labels: &'a HashMap<String, Sexp>,
    value_label_reference_counts: &'a HashMap<String, usize>,
}

struct ReadAttributeCache<'a> {
    value_labels: &'a HashMap<String, Sexp>,
    value_label_reference_counts: &'a HashMap<String, usize>,
    profiled: bool,
}

impl ReadAttributeCache<'_> {
    fn for_column<'a>(&'a self, column: &'a ArrowReadColumn) -> ColumnAttributes<'a> {
        ColumnAttributes {
            document: if self.profiled {
                column.field.as_ref()
            } else {
                None
            },
            value_labels: self.value_labels,
            value_label_reference_counts: self.value_label_reference_counts,
        }
    }
}

impl ColumnAttributes<'_> {
    fn label(&self) -> &str {
        self.document.map_or("", |document| document.label.as_str())
    }

    fn format(&self) -> &str {
        self.document
            .map_or("", |document| document.format.as_str())
    }

    fn value_labels(&self) -> Option<(&str, Sexp)> {
        let name = self.document?.value_labels.as_deref()?;
        self.value_labels
            .get(name)
            .copied()
            .map(|labels| (name, labels))
    }

    fn preserve_value_label_name(&self, column_name: &str) -> bool {
        let Some(name) = self
            .document
            .and_then(|document| document.value_labels.as_deref())
        else {
            return false;
        };
        should_preserve_value_label_name(
            column_name,
            name,
            self.value_label_reference_counts
                .get(name)
                .copied()
                .unwrap_or(0),
        )
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
    if let Some(document) = attributes.document {
        attach_stata_metadata(vector, &document.notes, &document.characteristics, guard)?;
    }
    if !attributes.label().is_empty() {
        let label = scalar_string(attributes.label(), guard)?;
        set_attr(vector, "label", label)?;
    }
    if !attributes.format().is_empty() {
        let format = scalar_string(attributes.format(), guard)?;
        set_attr(vector, "format.stata", format)?;
    }
    if let Some(storage) = attributes
        .document
        .and_then(|document| document.string_storage.as_deref())
    {
        let storage = scalar_string(storage, guard)?;
        set_attr(vector, "stata.string.storage", storage)?;
        set_class(vector, &["stata_string", "vctrs_vctr", "character"], guard)?;
    }
    Ok(())
}

fn chunk_error(name: &str) -> String {
    format!("column `{name}` has chunks of an unexpected Arrow type")
}

/// Iterate every (chunk, local index) pair of a column in row order. Never
/// polls interrupts: fill closures may run off the R thread, so the
/// coordinating thread polls between fill units instead.
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
            visit(row, typed, index)?;
            row += 1;
        }
    }
    Ok(())
}

/// How one Arrow column becomes an R vector. The shape drives all three
/// phases of a read: the R storage the main thread allocates, the pure
/// conversion that may run on a worker thread, and the ALTREP wrapping and
/// attribute attachment the main thread applies afterwards.
enum ColumnShape {
    ProfiledDouble {
        temporal: TemporalKind,
    },
    ProfiledCompact {
        storage: StataStorage,
        version: FormatVersion,
    },
    ProfiledEager {
        storage: StataStorage,
        temporal: TemporalKind,
        version: FormatVersion,
    },
    Logical,
    Integer,
    Raw,
    Strings {
        has_nulls: bool,
    },
    Factor,
    Date32,
    Timestamp,
    Duration {
        seconds_per_unit: f64,
    },
    PayloadDouble,
    SemanticDouble,
}

fn classify_read_column(
    column: &ArrowReadColumn,
    attributes: &ColumnAttributes<'_>,
    numeric_altrep: bool,
) -> Result<ColumnShape, String> {
    // Profiled columns with declared Stata storage reuse the DTA value
    // mapping wholesale; raw Stata missing storage drives it.
    if let Some(storage) = attributes.document.and_then(|document| document.storage) {
        let temporal = temporal_kind(attributes.format());
        let version = attributes
            .document
            .and_then(|document| document.missing_release)
            .unwrap_or(FormatVersion::V118);
        return Ok(match storage {
            StataStorage::Double => ColumnShape::ProfiledDouble { temporal },
            _ if numeric_altrep => ColumnShape::ProfiledCompact { storage, version },
            _ => ColumnShape::ProfiledEager {
                storage,
                temporal,
                version,
            },
        });
    }
    if column.data_type == DataType::Int32 && int32_contains_r_na_sentinel(column)? {
        if attributes.class() == Some("integer") {
            return Err(format!(
                "column `{}` declares R integer semantics but contains a non-null Int32 minimum value",
                column.name
            ));
        }
        return Ok(ColumnShape::SemanticDouble);
    }
    let class = attributes.class();
    let payload = attributes.document.and_then(|document| document.missing)
        == Some(ArrowMissingEncoding::Payload);
    Ok(match &column.data_type {
        DataType::Boolean => ColumnShape::Logical,
        DataType::Int8 | DataType::Int16 | DataType::Int32 | DataType::UInt8 | DataType::UInt16
            if class != Some("raw") =>
        {
            ColumnShape::Integer
        }
        DataType::UInt8 => ColumnShape::Raw,
        DataType::Utf8 | DataType::LargeUtf8 => ColumnShape::Strings {
            // The dictionary-string ALTREP class cannot represent
            // `NA_character_`, so null-bearing columns materialize eagerly.
            has_nulls: column.chunks.iter().any(|chunk| chunk.null_count() > 0),
        },
        DataType::Dictionary(_, _) => ColumnShape::Factor,
        DataType::Date32 => ColumnShape::Date32,
        DataType::Timestamp(_, _) => ColumnShape::Timestamp,
        DataType::Duration(_) => ColumnShape::Duration {
            seconds_per_unit: match attributes.class() {
                Some("difftime") => {
                    let units = attributes
                        .semantics()
                        .and_then(|semantics| semantics.units.as_deref())
                        .filter(|units| !units.is_empty())
                        .unwrap_or("secs");
                    difftime_seconds_per_unit(units)?
                }
                _ => 1.0,
            },
        },
        DataType::Float64 if payload => ColumnShape::PayloadDouble,
        DataType::Float32
        | DataType::Float64
        | DataType::Int64
        | DataType::UInt32
        | DataType::UInt64 => ColumnShape::SemanticDouble,
        other => {
            return Err(format!(
                "column `{}` has unsupported Arrow type {other}",
                column.name
            ))
        }
    })
}

fn int32_contains_r_na_sentinel(column: &ArrowReadColumn) -> Result<bool, String> {
    for chunk in &column.chunks {
        let values = chunk
            .as_any()
            .downcast_ref::<Int32Array>()
            .ok_or_else(|| chunk_error(&column.name))?;
        if (0..values.len()).any(|index| !values.is_null(index) && values.value(index) == i32::MIN)
        {
            return Ok(true);
        }
    }
    Ok(false)
}

/// The pure conversion for one column: raw output pointers plus the
/// parameters the fill loop needs. The R vectors these pointers address were
/// allocated and protected on the main thread before any worker starts, and
/// fill code never calls the R API, so moving a fill to a worker thread and
/// sharing it by reference is sound.
enum ColumnFill {
    ProfiledDouble {
        output: *mut f64,
        temporal: TemporalKind,
    },
    ProfiledCompact {
        values: *mut u8,
        kind: NumericKind,
        version: FormatVersion,
    },
    ProfiledEager {
        output: *mut f64,
        storage: StataStorage,
        temporal: TemporalKind,
        version: FormatVersion,
    },
    Logical {
        output: *mut c_int,
    },
    Integer {
        output: *mut c_int,
    },
    Raw {
        output: *mut u8,
    },
    DictStrings {
        expected_rows: usize,
    },
    FactorCodes {
        output: *mut c_int,
    },
    Date32 {
        output: *mut f64,
    },
    Timestamp {
        output: *mut f64,
    },
    Duration {
        output: *mut f64,
        seconds_per_unit: f64,
    },
    PayloadDouble {
        output: *mut f64,
    },
    SemanticDouble {
        output: *mut f64,
    },
}

unsafe impl Send for ColumnFill {}
unsafe impl Sync for ColumnFill {}

/// What a fill hands back to the main thread for finalization.
enum FillOutcome {
    Plain,
    MissingCount(usize),
    Strings(RStringData),
    Levels(Vec<Option<String>>),
}

unsafe impl Send for FillOutcome {}

/// One planned output column: its shape, the eagerly allocated R vector when
/// the shape has one, the compact ALTREP backing when it does not, and the
/// fill left to run. Eager string columns have no fill; the main thread
/// materializes them during finalization.
struct PlannedColumn {
    shape: ColumnShape,
    vector: Sexp,
    compact: Option<RNumericData>,
    fill: Option<ColumnFill>,
}

unsafe fn plan_read_column(
    column: &ArrowReadColumn,
    shape: ColumnShape,
    attributes: &ColumnAttributes<'_>,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<PlannedColumn, String> {
    let length = RLen::try_from(row_count).map_err(|_| "too long".to_owned())?;
    let _ = column;
    let (vector, compact, fill) = match &shape {
        ColumnShape::ProfiledDouble { temporal } => {
            let vector = guard.alloc(REALSXP, length)?;
            let fill = ColumnFill::ProfiledDouble {
                output: REAL(vector),
                temporal: *temporal,
            };
            (vector, None, Some(fill))
        }
        ColumnShape::ProfiledCompact { storage, version } => {
            let data = numeric_altrep_storage(
                storage.dta_type(),
                row_count,
                temporal_kind(attributes.format()),
                *version,
                guard,
            )
            .map_err(|error| error.to_string())?;
            let fill = ColumnFill::ProfiledCompact {
                values: data.values,
                kind: data.kind,
                version: *version,
            };
            (ptr::null_mut(), Some(data), Some(fill))
        }
        ColumnShape::ProfiledEager {
            storage,
            temporal,
            version,
        } => {
            let vector = guard.alloc(REALSXP, length)?;
            let fill = ColumnFill::ProfiledEager {
                output: REAL(vector),
                storage: *storage,
                temporal: *temporal,
                version: *version,
            };
            (vector, None, Some(fill))
        }
        ColumnShape::Logical => {
            let vector = guard.alloc(LGLSXP, length)?;
            let fill = ColumnFill::Logical {
                output: LOGICAL(vector),
            };
            (vector, None, Some(fill))
        }
        ColumnShape::Integer => {
            let vector = guard.alloc(INTSXP, length)?;
            let fill = ColumnFill::Integer {
                output: INTEGER(vector),
            };
            (vector, None, Some(fill))
        }
        ColumnShape::Raw => {
            let vector = guard.alloc(crate::RAWSXP, length)?;
            let fill = ColumnFill::Raw {
                output: crate::RAW(vector),
            };
            (vector, None, Some(fill))
        }
        ColumnShape::Strings { has_nulls: false } => (
            ptr::null_mut(),
            None,
            Some(ColumnFill::DictStrings {
                expected_rows: row_count,
            }),
        ),
        ColumnShape::Strings { has_nulls: true } => (ptr::null_mut(), None, None),
        ColumnShape::Factor => {
            let vector = guard.alloc(INTSXP, length)?;
            let fill = ColumnFill::FactorCodes {
                output: INTEGER(vector),
            };
            (vector, None, Some(fill))
        }
        ColumnShape::Date32 => {
            let vector = guard.alloc(REALSXP, length)?;
            let fill = ColumnFill::Date32 {
                output: REAL(vector),
            };
            (vector, None, Some(fill))
        }
        ColumnShape::Timestamp => {
            let vector = guard.alloc(REALSXP, length)?;
            let fill = ColumnFill::Timestamp {
                output: REAL(vector),
            };
            (vector, None, Some(fill))
        }
        ColumnShape::Duration { seconds_per_unit } => {
            let vector = guard.alloc(REALSXP, length)?;
            let fill = ColumnFill::Duration {
                output: REAL(vector),
                seconds_per_unit: *seconds_per_unit,
            };
            (vector, None, Some(fill))
        }
        ColumnShape::PayloadDouble => {
            let vector = guard.alloc(REALSXP, length)?;
            let fill = ColumnFill::PayloadDouble {
                output: REAL(vector),
            };
            (vector, None, Some(fill))
        }
        ColumnShape::SemanticDouble => {
            let vector = guard.alloc(REALSXP, length)?;
            let fill = ColumnFill::SemanticDouble {
                output: REAL(vector),
            };
            (vector, None, Some(fill))
        }
    };
    Ok(PlannedColumn {
        shape,
        vector,
        compact,
        fill,
    })
}

unsafe fn fill_profiled_compact(
    column: &ArrowReadColumn,
    values: *mut u8,
    kind: NumericKind,
    version: FormatVersion,
) -> Result<usize, String> {
    let mut missing_count = 0;
    match kind {
        NumericKind::Byte => for_each_value::<Int8Array>(column, |row, array, index| {
            let value = array.value(index);
            missing_count +=
                usize::from(classify_byte_missing_for_version(value, version).is_some());
            values.add(row).cast::<i8>().write_unaligned(value);
            Ok(())
        })?,
        NumericKind::Int => for_each_value::<Int16Array>(column, |row, array, index| {
            let value = array.value(index);
            missing_count +=
                usize::from(classify_int_missing_for_version(value, version).is_some());
            values.add(row * 2).cast::<i16>().write_unaligned(value);
            Ok(())
        })?,
        NumericKind::Long => for_each_value::<Int32Array>(column, |row, array, index| {
            let value = array.value(index);
            missing_count +=
                usize::from(classify_long_missing_for_version(value, version).is_some());
            values.add(row * 4).cast::<i32>().write_unaligned(value);
            Ok(())
        })?,
        NumericKind::Float => for_each_value::<Float32Array>(column, |row, array, index| {
            let value = array.value(index);
            missing_count += usize::from(
                value.is_nan()
                    || classify_float_missing_bits_for_version(value.to_bits(), version).is_some(),
            );
            values.add(row * 4).cast::<f32>().write_unaligned(value);
            Ok(())
        })?,
    }
    Ok(missing_count)
}

unsafe fn fill_profiled_eager(
    column: &ArrowReadColumn,
    output: *mut f64,
    storage: StataStorage,
    temporal: TemporalKind,
    version: FormatVersion,
) -> Result<(), String> {
    match storage {
        StataStorage::Byte => for_each_value::<Int8Array>(column, |row, values, index| {
            let value = values.value(index);
            *output.add(row) = match classify_byte_missing_for_version(value, version) {
                Some(tag) => r_missing(tag),
                None => observed_value(f64::from(value), temporal),
            };
            Ok(())
        }),
        StataStorage::Int => for_each_value::<Int16Array>(column, |row, values, index| {
            let value = values.value(index);
            *output.add(row) = match classify_int_missing_for_version(value, version) {
                Some(tag) => r_missing(tag),
                None => observed_value(f64::from(value), temporal),
            };
            Ok(())
        }),
        StataStorage::Long => for_each_value::<Int32Array>(column, |row, values, index| {
            let value = values.value(index);
            *output.add(row) = match classify_long_missing_for_version(value, version) {
                Some(tag) => r_missing(tag),
                None => observed_value(f64::from(value), temporal),
            };
            Ok(())
        }),
        StataStorage::Float => for_each_value::<Float32Array>(column, |row, values, index| {
            let value = values.value(index);
            *output.add(row) =
                match classify_float_missing_bits_for_version(value.to_bits(), version) {
                    Some(tag) => r_missing(tag),
                    None => observed_value(f64::from(value), temporal),
                };
            Ok(())
        }),
        StataStorage::Double => Err(chunk_error(&column.name)),
    }
}

unsafe fn fill_semantic_double(column: &ArrowReadColumn, output: *mut f64) -> Result<(), String> {
    match column.data_type {
        DataType::Float64 => for_each_value::<Float64Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                values.value(index)
            };
            Ok(())
        }),
        DataType::Float32 => for_each_value::<Float32Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                f64::from(values.value(index))
            };
            Ok(())
        }),
        DataType::Int32 => for_each_value::<Int32Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                f64::from(values.value(index))
            };
            Ok(())
        }),
        DataType::Int64 => for_each_value::<Int64Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                exact_i64_as_r_double(values.value(index), &column.name)?
            };
            Ok(())
        }),
        DataType::UInt16 => for_each_value::<UInt16Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                f64::from(values.value(index))
            };
            Ok(())
        }),
        DataType::UInt32 => for_each_value::<UInt32Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                f64::from(values.value(index))
            };
            Ok(())
        }),
        DataType::UInt64 => for_each_value::<UInt64Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaReal
            } else {
                exact_u64_as_r_double(values.value(index), &column.name)?
            };
            Ok(())
        }),
        _ => Err(chunk_error(&column.name)),
    }
}

fn exact_i64_as_r_double(value: i64, column: &str) -> Result<f64, String> {
    let converted = value as f64;
    if converted as i128 == value as i128 {
        Ok(converted)
    } else {
        Err(format!(
            "column `{column}` contains Int64 value {value} that cannot be represented exactly as an R double"
        ))
    }
}

fn exact_u64_as_r_double(value: u64, column: &str) -> Result<f64, String> {
    let converted = value as f64;
    if converted as u128 == value as u128 {
        Ok(converted)
    } else {
        Err(format!(
            "column `{column}` contains UInt64 value {value} that cannot be represented exactly as an R double"
        ))
    }
}

unsafe fn fill_integer(column: &ArrowReadColumn, output: *mut c_int) -> Result<(), String> {
    match column.data_type {
        DataType::Int32 => for_each_value::<Int32Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaInt
            } else {
                values.value(index)
            };
            Ok(())
        }),
        DataType::Int8 => for_each_value::<Int8Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaInt
            } else {
                c_int::from(values.value(index))
            };
            Ok(())
        }),
        DataType::Int16 => for_each_value::<Int16Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaInt
            } else {
                c_int::from(values.value(index))
            };
            Ok(())
        }),
        DataType::UInt8 => for_each_value::<UInt8Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaInt
            } else {
                c_int::from(values.value(index))
            };
            Ok(())
        }),
        DataType::UInt16 => for_each_value::<UInt16Array>(column, |row, values, index| {
            *output.add(row) = if values.is_null(index) {
                R_NaInt
            } else {
                c_int::from(values.value(index))
            };
            Ok(())
        }),
        _ => Err(chunk_error(&column.name)),
    }
}

unsafe fn fill_logical(column: &ArrowReadColumn, output: *mut c_int) -> Result<(), String> {
    for_each_value::<BooleanArray>(column, |row, values, index| {
        *output.add(row) = if values.is_null(index) {
            R_NaInt
        } else {
            c_int::from(values.value(index))
        };
        Ok(())
    })
}

unsafe fn fill_raw(column: &ArrowReadColumn, output: *mut u8) -> Result<(), String> {
    for_each_value::<UInt8Array>(column, |row, values, index| {
        if values.is_null(index) {
            return Err(format!(
                "column `{}` maps to an R raw vector but contains nulls",
                column.name
            ));
        }
        *output.add(row) = values.value(index);
        Ok(())
    })
}

unsafe fn fill_payload_double(column: &ArrowReadColumn, output: *mut f64) -> Result<(), String> {
    for_each_value::<Float64Array>(column, |row, values, index| {
        // Bit-exact: tagged NAs and NaN payloads pass through unchanged.
        *output.add(row) = values.value(index);
        Ok(())
    })
}

unsafe fn fill_date32(column: &ArrowReadColumn, output: *mut f64) -> Result<(), String> {
    for_each_value::<Date32Array>(column, |row, values, index| {
        *output.add(row) = if values.is_null(index) {
            R_NaReal
        } else {
            f64::from(values.value(index))
        };
        Ok(())
    })
}

/// Deduplicate a null-free string column into the dictionary that backs the
/// deferred string ALTREP class.
fn fill_dict_strings(
    column: &ArrowReadColumn,
    expected_rows: usize,
) -> Result<RStringData, String> {
    let mut data = RStringData::new(expected_rows).map_err(|error| error.to_string())?;
    match column.data_type {
        DataType::Utf8 => for_each_value::<StringArray>(column, |row, values, index| {
            data.push(row, values.value(index))
                .map_err(|error| error.to_string())
        })?,
        DataType::LargeUtf8 => {
            for_each_value::<arrow_array::LargeStringArray>(column, |row, values, index| {
                data.push(row, values.value(index))
                    .map_err(|error| error.to_string())
            })?
        }
        _ => return Err(chunk_error(&column.name)),
    }
    Ok(data)
}

/// Eager string materialization for columns holding `NA_character_`. Main
/// thread only: it creates CHARSXPs, so it may poll interrupts.
unsafe fn character_vector(
    column: &ArrowReadColumn,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let vector = guard.alloc(STRSXP, RLen::try_from(row_count).map_err(|_| "too long")?)?;
    match column.data_type {
        DataType::Utf8 => for_each_value::<StringArray>(column, |row, values, index| {
            poll_interrupt(row)?;
            if values.is_null(index) {
                SET_STRING_ELT(vector, row as RLen, R_NaString);
            } else {
                SET_STRING_ELT(vector, row as RLen, r_char(values.value(index))?);
            }
            Ok(())
        })?,
        DataType::LargeUtf8 => {
            for_each_value::<arrow_array::LargeStringArray>(column, |row, values, index| {
                poll_interrupt(row)?;
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

fn factor_levels(values: &ArrayRef, column: &str) -> Result<Vec<Option<String>>, String> {
    let levels: Vec<Option<String>> = match values.data_type() {
        DataType::Utf8 => {
            let values = values
                .as_any()
                .downcast_ref::<StringArray>()
                .ok_or_else(|| chunk_error(column))?;
            (0..values.len())
                .map(|index| Ok((!values.is_null(index)).then(|| values.value(index).to_owned())))
                .collect()
        }
        DataType::LargeUtf8 => {
            let values = values
                .as_any()
                .downcast_ref::<arrow_array::LargeStringArray>()
                .ok_or_else(|| chunk_error(column))?;
            (0..values.len())
                .map(|index| Ok((!values.is_null(index)).then(|| values.value(index).to_owned())))
                .collect()
        }
        _ => Err(chunk_error(column)),
    }?;
    let mut unique = HashSet::with_capacity(levels.len());
    if levels.iter().any(|level| !unique.insert(level.as_deref())) {
        return Err(format!("column `{column}` has a duplicate factor level"));
    }
    Ok(levels)
}

unsafe fn optional_string_vector(
    values: &[Option<String>],
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let vector = guard.alloc(
        STRSXP,
        RLen::try_from(values.len()).map_err(|_| "R vector is too long".to_owned())?,
    )?;
    for (index, value) in values.iter().enumerate() {
        poll_interrupt(index)?;
        let value = match value {
            Some(value) => r_char(value)?,
            None => R_NaString,
        };
        SET_STRING_ELT(vector, index as RLen, value);
    }
    Ok(vector)
}

unsafe fn fill_factor_chunk<K: ArrowDictionaryKeyType>(
    chunk: &ArrayRef,
    output: *mut c_int,
    row: &mut usize,
    levels: &mut Option<Vec<Option<String>>>,
    column: &str,
) -> Result<(), String> {
    let dictionary = chunk
        .as_any()
        .downcast_ref::<DictionaryArray<K>>()
        .ok_or_else(|| chunk_error(column))?;
    let chunk_levels = factor_levels(dictionary.values(), column)?;
    match levels {
        None => *levels = Some(chunk_levels),
        Some(existing) if *existing == chunk_levels => {}
        Some(_) => {
            return Err(format!(
                "column `{column}` has chunks with different dictionaries"
            ))
        }
    }
    let keys = dictionary.keys();
    for index in 0..keys.len() {
        *output.add(*row) = if keys.is_null(index) {
            R_NaInt
        } else {
            let key = keys.value(index).as_usize();
            if key >= dictionary.values().len() {
                return Err(format!("column `{column}` has an invalid factor code"));
            }
            c_int::try_from(key + 1)
                .map_err(|_| format!("column `{column}` has too many factor levels"))?
        };
        *row += 1;
    }
    Ok(())
}

unsafe fn fill_factor_codes(
    column: &ArrowReadColumn,
    output: *mut c_int,
) -> Result<Vec<Option<String>>, String> {
    let mut levels: Option<Vec<Option<String>>> = None;
    let mut row = 0_usize;
    let DataType::Dictionary(key, _) = &column.data_type else {
        return Err(chunk_error(&column.name));
    };
    for chunk in &column.chunks {
        match key.as_ref() {
            DataType::Int8 => {
                fill_factor_chunk::<Int8Type>(chunk, output, &mut row, &mut levels, &column.name)?
            }
            DataType::Int16 => {
                fill_factor_chunk::<Int16Type>(chunk, output, &mut row, &mut levels, &column.name)?
            }
            DataType::Int32 => {
                fill_factor_chunk::<Int32Type>(chunk, output, &mut row, &mut levels, &column.name)?
            }
            DataType::Int64 => {
                fill_factor_chunk::<Int64Type>(chunk, output, &mut row, &mut levels, &column.name)?
            }
            _ => return Err(chunk_error(&column.name)),
        }
    }
    Ok(levels.unwrap_or_default())
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

fn exact_temporal_as_r_double(
    value: i64,
    scale: f64,
    seconds_per_unit: f64,
    column: &str,
    data_type: &DataType,
) -> Result<f64, String> {
    let converted = value as f64 / scale / seconds_per_unit;
    let restored = converted * seconds_per_unit * scale;
    if restored.is_finite() && restored.fract() == 0.0 && restored as i128 == value as i128 {
        Ok(converted)
    } else {
        Err(format!(
            "column `{column}` contains {data_type} value {value} that cannot be represented exactly in R"
        ))
    }
}

unsafe fn fill_timestamp(column: &ArrowReadColumn, output: *mut f64) -> Result<(), String> {
    let DataType::Timestamp(unit, _) = &column.data_type else {
        return Err(chunk_error(&column.name));
    };
    let scale = timestamp_scale(unit);
    macro_rules! fill {
        ($array:ty) => {
            for_each_value::<$array>(column, |row, values, index| {
                *output.add(row) = if values.is_null(index) {
                    R_NaReal
                } else {
                    exact_temporal_as_r_double(
                        values.value(index),
                        scale,
                        1.0,
                        &column.name,
                        &column.data_type,
                    )?
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
    Ok(())
}

unsafe fn fill_duration(
    column: &ArrowReadColumn,
    output: *mut f64,
    seconds_per_unit: f64,
) -> Result<(), String> {
    let DataType::Duration(unit) = &column.data_type else {
        return Err(chunk_error(&column.name));
    };
    let scale = timestamp_scale(unit);
    macro_rules! fill {
        ($array:ty) => {
            for_each_value::<$array>(column, |row, values, index| {
                *output.add(row) = if values.is_null(index) {
                    R_NaReal
                } else {
                    exact_temporal_as_r_double(
                        values.value(index),
                        scale,
                        seconds_per_unit,
                        &column.name,
                        &column.data_type,
                    )?
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
    Ok(())
}

/// Run one column's pure conversion. Callable from any thread: it writes
/// through pre-allocated pointers and builds Rust-owned dictionaries, never
/// touching the R API.
unsafe fn fill_read_column(
    column: &ArrowReadColumn,
    fill: &ColumnFill,
) -> Result<FillOutcome, String> {
    match fill {
        ColumnFill::ProfiledDouble { output, temporal } => {
            let (output, temporal) = (*output, *temporal);
            // Raw Stata missing storage for doubles: classify the stored bits.
            for_each_value::<Float64Array>(column, |row, values, index| {
                let value = values.value(index);
                *output.add(row) = match classify_double_missing_bits(value.to_bits()) {
                    Some(tag) => r_missing(tag),
                    None => observed_value(value, temporal),
                };
                Ok(())
            })?;
            Ok(FillOutcome::Plain)
        }
        ColumnFill::ProfiledCompact {
            values,
            kind,
            version,
        } => Ok(FillOutcome::MissingCount(fill_profiled_compact(
            column, *values, *kind, *version,
        )?)),
        ColumnFill::ProfiledEager {
            output,
            storage,
            temporal,
            version,
        } => {
            fill_profiled_eager(column, *output, *storage, *temporal, *version)?;
            Ok(FillOutcome::Plain)
        }
        ColumnFill::Logical { output } => {
            fill_logical(column, *output)?;
            Ok(FillOutcome::Plain)
        }
        ColumnFill::Integer { output } => {
            fill_integer(column, *output)?;
            Ok(FillOutcome::Plain)
        }
        ColumnFill::Raw { output } => {
            fill_raw(column, *output)?;
            Ok(FillOutcome::Plain)
        }
        ColumnFill::DictStrings { expected_rows } => Ok(FillOutcome::Strings(fill_dict_strings(
            column,
            *expected_rows,
        )?)),
        ColumnFill::FactorCodes { output } => {
            Ok(FillOutcome::Levels(fill_factor_codes(column, *output)?))
        }
        ColumnFill::Date32 { output } => {
            fill_date32(column, *output)?;
            Ok(FillOutcome::Plain)
        }
        ColumnFill::Timestamp { output } => {
            fill_timestamp(column, *output)?;
            Ok(FillOutcome::Plain)
        }
        ColumnFill::Duration {
            output,
            seconds_per_unit,
        } => {
            fill_duration(column, *output, *seconds_per_unit)?;
            Ok(FillOutcome::Plain)
        }
        ColumnFill::PayloadDouble { output } => {
            fill_payload_double(column, *output)?;
            Ok(FillOutcome::Plain)
        }
        ColumnFill::SemanticDouble { output } => {
            fill_semantic_double(column, *output)?;
            Ok(FillOutcome::Plain)
        }
    }
}

// Automatic-parallelism thresholds for the fill phase, matching the DTA
// reader's policy.
const MIN_PARALLEL_FILL_CELLS: u64 = 1_000_000;
const MAX_AUTOMATIC_FILL_THREADS: usize = 8;

fn fill_thread_count(requested: usize, task_count: usize, row_count: usize) -> usize {
    if requested == 1 || task_count < 2 {
        return 1;
    }
    let cells = (row_count as u64).saturating_mul(task_count as u64);
    if requested == 0 && cells < MIN_PARALLEL_FILL_CELLS {
        return 1;
    }
    let available = thread::available_parallelism().map_or(1, usize::from);
    let threads = if requested == 0 {
        available.min(MAX_AUTOMATIC_FILL_THREADS)
    } else {
        requested.min(available)
    };
    threads.min(task_count).max(1)
}

/// Claim fill tasks from the shared queue. `poll` runs between tasks; on the
/// R thread it checks interrupts, on workers it only observes the cancel
/// flag set by the other loops.
fn fill_task_loop(
    columns: &[ArrowReadColumn],
    tasks: &[(usize, ColumnFill)],
    next: &AtomicUsize,
    cancelled: &AtomicBool,
    mut poll: impl FnMut() -> bool,
) -> Result<Vec<(usize, FillOutcome)>, String> {
    let mut results = Vec::new();
    loop {
        if poll() {
            cancelled.store(true, Ordering::Relaxed);
            return Err("Arrow read interrupted".to_owned());
        }
        if cancelled.load(Ordering::Relaxed) {
            return Ok(results);
        }
        let task_index = next.fetch_add(1, Ordering::Relaxed);
        let Some((column_index, fill)) = tasks.get(task_index) else {
            return Ok(results);
        };
        match unsafe { fill_read_column(&columns[*column_index], fill) } {
            Ok(outcome) => results.push((*column_index, outcome)),
            Err(error) => {
                cancelled.store(true, Ordering::Relaxed);
                return Err(error);
            }
        }
    }
}

/// Run every planned fill, in parallel when `threads` allows it. The R
/// thread participates in the queue and is the only one polling interrupts.
fn run_column_fills(
    columns: &[ArrowReadColumn],
    fills: Vec<Option<ColumnFill>>,
    threads: usize,
) -> Result<Vec<FillOutcome>, String> {
    let mut outcomes: Vec<FillOutcome> = fills.iter().map(|_| FillOutcome::Plain).collect();
    if threads <= 1 {
        for (index, fill) in fills.into_iter().enumerate() {
            let Some(fill) = fill else { continue };
            check_interrupt()?;
            outcomes[index] = unsafe { fill_read_column(&columns[index], &fill) }?;
        }
        return Ok(outcomes);
    }
    let tasks: Vec<(usize, ColumnFill)> = fills
        .into_iter()
        .enumerate()
        .filter_map(|(index, fill)| fill.map(|fill| (index, fill)))
        .collect();
    let next = AtomicUsize::new(0);
    let cancelled = AtomicBool::new(false);
    let (own_result, worker_results) = thread::scope(|scope| {
        let handles: Vec<_> = (1..threads)
            .map(|_| {
                let tasks = &tasks;
                let next = &next;
                let cancelled = &cancelled;
                scope.spawn(move || fill_task_loop(columns, tasks, next, cancelled, || false))
            })
            .collect();
        let own = fill_task_loop(columns, &tasks, &next, &cancelled, coarse_interrupt);
        if own.is_err() {
            cancelled.store(true, Ordering::Relaxed);
        }
        let worker_results: Vec<_> = handles
            .into_iter()
            .map(|handle| {
                handle
                    .join()
                    .unwrap_or_else(|_| Err("an Arrow fill worker panicked".to_owned()))
            })
            .collect();
        (own, worker_results)
    });
    let mut store = |results: Vec<(usize, FillOutcome)>| {
        for (index, outcome) in results {
            outcomes[index] = outcome;
        }
    };
    // Surface the R thread's error (interrupts included) first, then any
    // worker error.
    store(own_result?);
    for result in worker_results {
        store(result?);
    }
    Ok(outcomes)
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

unsafe fn value_label_attributes(
    vector: Sexp,
    table_name: &str,
    labels: Sexp,
    add_haven_class: bool,
    preserve_value_label_name: bool,
    guard: &mut ProtectGuard,
) -> Result<(), String> {
    set_attr(vector, "labels", labels)?;
    if preserve_value_label_name {
        let name = scalar_string(table_name, guard)?;
        set_attr(vector, "value.label.name", name)?;
    }
    if add_haven_class {
        set_class(vector, &["haven_labelled", "vctrs_vctr", "double"], guard)?;
    }
    Ok(())
}

unsafe fn attach_cached_value_labels(
    vector: Sexp,
    column_name: &str,
    attributes: &ColumnAttributes<'_>,
    guard: &mut ProtectGuard,
) -> Result<(), String> {
    if let Some((table_name, labels)) = attributes.value_labels() {
        value_label_attributes(
            vector,
            table_name,
            labels,
            false,
            attributes.preserve_value_label_name(column_name),
            guard,
        )?;
    }
    Ok(())
}

/// The declared-class attributes shared by payload and semantic doubles.
unsafe fn apply_double_class(
    vector: Sexp,
    column_name: &str,
    attributes: &ColumnAttributes<'_>,
    guard: &mut ProtectGuard,
) -> Result<(), String> {
    match attributes.class() {
        Some("haven_labelled") => {
            set_class(vector, &["haven_labelled", "vctrs_vctr", "double"], guard)?;
        }
        Some("Date") => set_class(vector, &["Date"], guard)?,
        Some("POSIXct") => {
            set_class(vector, &["POSIXct", "POSIXt"], guard)?;
            if let Some(tz) = attributes
                .semantics()
                .and_then(|semantics| semantics.tz.as_deref())
            {
                let timezone = scalar_string(tz, guard)?;
                set_attr(vector, "tzone", timezone)?;
            }
        }
        Some("difftime") => {
            apply_difftime_attributes(vector, attributes, guard)?;
        }
        _ => {}
    }
    attach_cached_value_labels(vector, column_name, attributes, guard)
}

/// Turn one filled plan into the final R vector: wrap compact numerics and
/// deferred strings in their ALTREP classes, materialize null-bearing string
/// columns eagerly, and attach classes and attributes. R main thread only.
unsafe fn finalize_read_column(
    column: &ArrowReadColumn,
    plan: PlannedColumn,
    outcome: FillOutcome,
    attribute_cache: &ReadAttributeCache<'_>,
    row_count: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let attributes = attribute_cache.for_column(column);
    let mismatch = || format!("column `{}` produced a mismatched fill result", column.name);
    let vector = match &plan.shape {
        ColumnShape::ProfiledCompact { .. } => {
            let FillOutcome::MissingCount(missing_count) = outcome else {
                return Err(mismatch());
            };
            let mut data = plan.compact.ok_or_else(mismatch)?;
            data.missing_count = missing_count;
            guard.numeric(data)?
        }
        ColumnShape::Strings { has_nulls: false } => {
            let FillOutcome::Strings(data) = outcome else {
                return Err(mismatch());
            };
            guard.dictstring(data)?
        }
        ColumnShape::Strings { has_nulls: true } => character_vector(column, row_count, guard)?,
        ColumnShape::Factor => {
            let FillOutcome::Levels(levels) = outcome else {
                return Err(mismatch());
            };
            let level_vector = optional_string_vector(&levels, guard)?;
            set_attr(plan.vector, "levels", level_vector)?;
            let ordered = attributes
                .semantics()
                .and_then(|semantics| semantics.ordered)
                .unwrap_or(column.dictionary_ordered);
            if ordered {
                set_class(plan.vector, &["ordered", "factor"], guard)?;
            } else {
                set_class(plan.vector, &["factor"], guard)?;
            }
            plan.vector
        }
        _ => plan.vector,
    };
    match &plan.shape {
        // Profiled columns with declared Stata storage reuse the DTA
        // attribute logic wholesale.
        ColumnShape::ProfiledDouble { .. }
        | ColumnShape::ProfiledCompact { .. }
        | ColumnShape::ProfiledEager { .. } => {
            let storage = attributes
                .document
                .and_then(|document| document.storage)
                .ok_or_else(mismatch)?;
            let document = attributes.document.ok_or_else(mismatch)?;
            let dta_type = storage.dta_type();
            let (value_label_name, labels_attribute) = attributes.value_labels().unzip();
            attach_variable_attribute_view(
                vector,
                super::VariableAttributeView {
                    dta_type: &dta_type,
                    format: &document.format,
                    label: &document.label,
                    notes: &document.notes,
                    characteristics: &document.characteristics,
                },
                value_label_name,
                labels_attribute,
                attributes.preserve_value_label_name(&column.name),
                guard,
            )?;
        }
        ColumnShape::Date32 => {
            set_class(vector, &["Date"], guard)?;
            attach_simple_attributes(vector, &attributes, guard)?;
            attach_cached_value_labels(vector, &column.name, &attributes, guard)?;
        }
        ColumnShape::Timestamp => {
            set_class(vector, &["POSIXct", "POSIXt"], guard)?;
            let type_tz = match &column.data_type {
                DataType::Timestamp(_, tz) => tz.as_deref(),
                _ => None,
            };
            let tz = if attributes.class() == Some("POSIXct") {
                attributes
                    .semantics()
                    .and_then(|semantics| semantics.tz.as_deref())
            } else {
                Some(type_tz.unwrap_or("UTC"))
            };
            if let Some(tz) = tz {
                let timezone = scalar_string(tz, guard)?;
                set_attr(vector, "tzone", timezone)?;
            }
            attach_simple_attributes(vector, &attributes, guard)?;
            attach_cached_value_labels(vector, &column.name, &attributes, guard)?;
        }
        ColumnShape::Duration { .. } => {
            apply_difftime_attributes(vector, &attributes, guard)?;
            attach_simple_attributes(vector, &attributes, guard)?;
            attach_cached_value_labels(vector, &column.name, &attributes, guard)?;
        }
        ColumnShape::PayloadDouble | ColumnShape::SemanticDouble => {
            apply_double_class(vector, &column.name, &attributes, guard)?;
            attach_simple_attributes(vector, &attributes, guard)?;
        }
        ColumnShape::Integer => {
            attach_simple_attributes(vector, &attributes, guard)?;
            attach_cached_value_labels(vector, &column.name, &attributes, guard)?;
        }
        ColumnShape::Logical
        | ColumnShape::Raw
        | ColumnShape::Strings { .. }
        | ColumnShape::Factor => {
            attach_simple_attributes(vector, &attributes, guard)?;
        }
    }
    Ok(vector)
}

#[no_mangle]
/// Read a dtatools Arrow profile file (or a plain Arrow IPC file) into an R
/// tibble.
///
/// # Safety
///
/// `snapshot` must point to a live [`ArrowFileSnapshot`]. Unless `all_columns`
/// is nonzero, `columns` must
/// address `column_count` readable integers. `interrupted` must point to
/// writable status storage. If non-null, `error` must point to writable
/// storage for one C string pointer. The caller must run on R's main thread
/// with an initialized R runtime.
pub unsafe extern "C" fn dtatools_read_arrow_rust(
    snapshot: *const c_void,
    columns: *const c_int,
    column_count: usize,
    all_columns: c_int,
    skip: f64,
    n_max: f64,
    verify: c_int,
    profile: c_int,
    numeric_altrep: c_int,
    requested_threads: c_int,
    record_signature: c_int,
    interrupted: *mut c_int,
    error: *mut *mut c_char,
) -> Sexp {
    arrow_boundary(interrupted, error, ptr::null_mut(), || {
        let snapshot = required_arrow_snapshot(snapshot)?;
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
        let requested =
            usize::try_from(requested_threads).map_err(|_| "invalid thread count".to_owned())?;
        let options = ArrowReadOptions {
            columns: projection,
            row_start,
            row_count,
            max_output_rows: Some(crate::R_DATA_FRAME_MAX_ROWS),
            verify: verify != 0,
            profile: profile != 0,
            record_signature: record_signature != 0,
            threads: requested,
        };
        let mut result = snapshot
            .read(&options, &mut coarse_interrupt)
            .map_err(|error| error.to_string())?;
        let profiled = result.profile_version.is_some();
        let row_count = usize::try_from(result.row_count)
            .map_err(|_| "the selection has too many rows".to_owned())?;
        let source_row_count = result.source_row_count;
        if result.row_count > crate::R_DATA_FRAME_MAX_ROWS {
            return Err("R data frames cannot contain more than 2^31-1 rows".to_owned());
        }

        let mut result_guard = ProtectGuard::new();
        let column_total =
            RLen::try_from(result.columns.len()).map_err(|_| "too many columns".to_owned())?;
        let frame = result_guard.alloc(VECSXP, column_total)?;
        let names = result_guard.alloc(STRSXP, column_total)?;

        let (
            dataset_label,
            output_container,
            dataset_notes,
            dataset_characteristics,
            mut value_label_registry,
        ) = if let Some(mut dataset) = result.dataset.take() {
            (
                std::mem::take(&mut dataset.label),
                dataset.output_container.take(),
                std::mem::take(&mut dataset.notes),
                std::mem::take(&mut dataset.characteristics),
                std::mem::take(&mut dataset.value_labels),
            )
        } else {
            (
                String::new(),
                None,
                Vec::new(),
                Vec::new(),
                Default::default(),
            )
        };

        // Convert and allocate each selected value-label table once. Every
        // referring R column then shares the same table record and protected
        // `labels` vector.
        let mut value_labels = HashMap::new();
        if profiled {
            for column in &result.columns {
                let Some(name) = column
                    .field
                    .as_ref()
                    .and_then(|field| field.value_labels.as_deref())
                else {
                    continue;
                };
                if value_labels.contains_key(name) {
                    continue;
                }
                let entries = value_label_registry.remove(name).ok_or_else(|| {
                    format!("Arrow field references missing value-label table `{name}`")
                })?;
                let labels = label_attribute_from_entries(
                    entries.len(),
                    entries.into_iter().map(|entry| {
                        let value = match (entry.value, entry.tag) {
                            (Some(value), None) => f64::from(value),
                            (None, Some(tag)) => r_missing(tag),
                            _ => {
                                return Err(
                                    "value-label entry must contain exactly one code".to_owned()
                                )
                            }
                        };
                        Ok((value, entry.label))
                    }),
                    &mut result_guard,
                )?;
                value_labels.insert(name.to_owned(), labels);
            }
        }
        drop(value_label_registry);

        let attribute_cache = ReadAttributeCache {
            value_labels: &value_labels,
            value_label_reference_counts: &result.value_label_reference_counts,
            profiled,
        };

        // Plan: allocate every output vector on the R thread so fills can
        // run anywhere.
        let mut plans = Vec::with_capacity(result.columns.len());
        let mut fills = Vec::with_capacity(result.columns.len());
        for column in &result.columns {
            check_interrupt()?;
            let attributes = attribute_cache.for_column(column);
            let shape = classify_read_column(column, &attributes, numeric_altrep != 0)?;
            let mut plan =
                plan_read_column(column, shape, &attributes, row_count, &mut result_guard)?;
            fills.push(plan.fill.take());
            plans.push(plan);
        }

        // Fill: pure conversions, in parallel when worthwhile.
        let task_count = fills.iter().filter(|fill| fill.is_some()).count();
        let threads = fill_thread_count(requested, task_count, row_count);
        let outcomes = run_column_fills(&result.columns, fills, threads)?;

        // Finalize on the R thread: ALTREP wrapping, classes, attributes.
        for (index, ((column, plan), outcome)) in
            result.columns.iter().zip(plans).zip(outcomes).enumerate()
        {
            check_interrupt()?;
            let mut column_guard = ProtectGuard::new();
            let vector = finalize_read_column(
                column,
                plan,
                outcome,
                &attribute_cache,
                row_count,
                &mut column_guard,
            )?;
            SET_VECTOR_ELT(frame, index as RLen, vector);
            SET_STRING_ELT(names, index as RLen, r_char(&column.name)?);
        }
        set_symbol_attr(frame, R_NamesSymbol, names)?;

        {
            let mut attribute_guard = ProtectGuard::new();
            let row_names = attribute_guard.alloc(INTSXP, 2)?;
            *INTEGER(row_names) = R_NaInt;
            *INTEGER(row_names).add(1) = -(row_count as c_int);
            set_symbol_attr(frame, R_RowNamesSymbol, row_names)?;
            set_class(
                frame,
                &["tbl_df", "tbl", "data.frame"],
                &mut attribute_guard,
            )?;
        }
        let _ = R_ClassSymbol;

        if !dataset_label.is_empty() {
            let mut guard = ProtectGuard::new();
            let label = scalar_string(&dataset_label, &mut guard)?;
            set_attr(frame, "label", label)?;
        }
        if let Some(output_container) = output_container {
            let mut guard = ProtectGuard::new();
            let value = scalar_string(&output_container, &mut guard)?;
            set_attr(frame, "dtatools.output.container", value)?;
        }
        let mut guard = ProtectGuard::new();
        attach_stata_metadata(
            frame,
            &dataset_notes,
            &dataset_characteristics,
            &mut guard,
        )?;
        if let Some(signature) = &result.stored_signature {
            let mut guard = ProtectGuard::new();
            let signature = scalar_string(signature, &mut guard)?;
            set_attr(frame, "datasig", signature)?;
        }
        if let Some(source_rows) = source_row_count {
            attach_source_rows(frame, source_rows)?;
        }
        Ok(frame)
    })
}

#[no_mangle]
/// Derive an Arrow file's dataset signature from its stored footer checksums
/// and schema documents, without reading data buffers.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C byte string for the
/// duration of this call. If non-null, `error` must point to writable storage
/// for one C string pointer. The caller must run on R's main thread with an
/// initialized R runtime.
pub unsafe extern "C" fn dtatools_arrow_datasig_rust(
    path: *const c_char,
    error: *mut *mut c_char,
) -> Sexp {
    boundary(error, ptr::null_mut(), || {
        let path = required_c_string(path, "the input path")?;
        let signature = arrow_stored_signature(&path).map_err(|error| error.to_string())?;
        let mut guard = ProtectGuard::new();
        scalar_string(&signature, &mut guard)
    })
}

#[no_mangle]
/// Return the column names and R proxy types of an Arrow file as a two
/// element list, for tidyselect resolution.
///
/// # Safety
///
/// `snapshot` must point to a live [`ArrowFileSnapshot`]. `interrupted` must
/// point to writable status storage.
/// If non-null, `error` must point to writable storage for one C string pointer.
/// The caller must run on R's main thread with an initialized R runtime.
pub unsafe extern "C" fn dtatools_arrow_metadata_rust(
    snapshot: *const c_void,
    apply_profile: c_int,
    scan_ambiguous_int32: c_int,
    skip: f64,
    n_max: f64,
    interrupted: *mut c_int,
    error: *mut *mut c_char,
) -> Sexp {
    arrow_boundary(interrupted, error, ptr::null_mut(), || {
        let snapshot = required_arrow_snapshot(snapshot)?;
        let (row_start, row_count) = row_window(skip, n_max);
        let mut summary = snapshot
            .summarize(
                apply_profile != 0,
                scan_ambiguous_int32 != 0,
                row_start,
                row_count,
                &mut coarse_interrupt,
            )
            .map_err(|error| error.to_string())?;
        let mut guard = ProtectGuard::new();
        let result = guard.alloc(VECSXP, 4)?;
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
        let value_label_names = summary
            .value_label_names
            .iter()
            .map(|name| name.as_deref().unwrap_or("").to_owned())
            .collect::<Vec<_>>();
        let value_label_name_vector = string_vector(&value_label_names, &mut guard)?;
        let registry_values = summary
            .dataset
            .as_mut()
            .map(|dataset| std::mem::take(&mut dataset.value_labels))
            .unwrap_or_default();
        let registry_count =
            RLen::try_from(registry_values.len()).map_err(|_| "too many value-label tables")?;
        let registry = guard.alloc(VECSXP, registry_count)?;
        let registry_names = guard.alloc(STRSXP, registry_count)?;
        for (index, (name, entries)) in registry_values.into_iter().enumerate() {
            let labels = label_attribute_from_entries(
                entries.len(),
                entries.into_iter().map(|entry| {
                    let value = match (entry.value, entry.tag) {
                        (Some(value), None) => f64::from(value),
                        (None, Some(tag)) => r_missing(tag),
                        _ => return Err("value-label entry must contain exactly one code".to_owned()),
                    };
                    Ok((value, entry.label))
                }),
                &mut guard,
            )?;
            SET_VECTOR_ELT(registry, index as RLen, labels);
            SET_STRING_ELT(registry_names, index as RLen, r_char(&name)?);
        }
        set_symbol_attr(registry, R_NamesSymbol, registry_names)?;
        SET_VECTOR_ELT(result, 0, name_vector);
        SET_VECTOR_ELT(result, 1, type_vector);
        SET_VECTOR_ELT(result, 2, value_label_name_vector);
        SET_VECTOR_ELT(result, 3, registry);
        Ok(result)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_zero_copy_arrays_ignore_ffi_sentinel_alignment() {
        let sentinel = std::ptr::NonNull::<u8>::dangling().as_ptr().cast::<i32>();
        let array = unsafe { zero_copy_array::<Int32Type>(sentinel, 0) };
        assert_eq!(array.len(), 0);
        assert_eq!(array.data_type(), &DataType::Int32);
    }

    #[test]
    fn duplicate_dictionary_values_cannot_become_factor_levels() {
        let values: ArrayRef = Arc::new(StringArray::from(vec!["same", "same"]));
        let error = factor_levels(&values, "x")
            .expect_err("duplicate Arrow dictionary values must not become R factor levels");
        assert!(error.contains("duplicate factor level"));
    }

    #[test]
    fn arrow_write_assembly_rejects_duplicate_value_label_table_names() {
        let table = ValueLabelTable {
            name: "answers".to_owned(),
            entries: vec![ValueLabelEntry {
                value: 1,
                missing_tag: None,
                label: "yes".to_owned(),
            }],
        };
        let mut dataset = DatasetDocument::default();
        let error = insert_value_label_tables(&mut dataset, vec![table.clone(), table])
            .expect_err("duplicate registry names are rejected during Arrow assembly");
        assert!(error.contains("duplicate value-label table name"));
        assert_eq!(dataset.value_labels.len(), 1);
    }

    #[test]
    fn invalid_profiled_nans_are_counted_as_replacements() {
        let values = [f64::NAN];
        let codes = [256];
        let (array, replacements, missing_release) = encode_profiled_column(
            "x",
            StataStorage::Double,
            TemporalKind::None,
            &values,
            &codes,
        )
        .expect("invalid NaN is representable as a lossy replacement");
        assert_eq!(replacements, 1);
        assert_eq!(missing_release, None);
        let values = array
            .as_any()
            .downcast_ref::<Float64Array>()
            .expect("double storage");
        assert_eq!(
            classify_double_missing_bits(values.value(0).to_bits()),
            Some(MissingTag::System)
        );
    }

    #[test]
    fn compact_float_fill_counts_generic_nan_as_missing() {
        let generic_nan = f32::from_bits(0x7fc0_0001);
        let system_missing = f32::from_bits(MissingTag::System.float_bits());
        let column = ArrowReadColumn {
            name: "x".to_owned(),
            data_type: DataType::Float32,
            nullable: false,
            dictionary_ordered: false,
            field: None,
            chunks: vec![Arc::new(Float32Array::from(vec![
                1.0,
                generic_nan,
                system_missing,
            ]))],
        };
        let mut values = vec![0_u8; 3 * std::mem::size_of::<f32>()];

        let missing_count = unsafe {
            fill_profiled_compact(
                &column,
                values.as_mut_ptr(),
                NumericKind::Float,
                FormatVersion::V118,
            )
        }
        .expect("compact float fill");

        assert_eq!(missing_count, 2);
    }

    #[test]
    fn eager_legacy_tail_values_select_the_legacy_missing_layout() {
        let values = [101.0, 102.0, -128.0, 0.0];
        let codes = [-1, -1, -1, 0];
        let (array, replacements, missing_release) =
            encode_profiled_column("x", StataStorage::Byte, TemporalKind::None, &values, &codes)
                .expect("legacy observed values and system missing are lossless");

        assert_eq!(replacements, 1);
        assert_eq!(missing_release, Some(FormatVersion::V111));
        let values = array
            .as_any()
            .downcast_ref::<Int8Array>()
            .expect("byte storage");
        assert_eq!(values.values(), &[101, 102, 127, 127]);
    }

    #[test]
    fn observed_int32_minimum_is_widened_to_double() {
        let column = ArrowReadColumn {
            name: "x".to_owned(),
            data_type: DataType::Int32,
            nullable: false,
            dictionary_ordered: false,
            field: None,
            chunks: vec![Arc::new(Int32Array::from(vec![i32::MIN, 7]))],
        };
        let value_labels = HashMap::new();
        let value_label_reference_counts = HashMap::new();
        let attributes = ColumnAttributes {
            document: None,
            value_labels: &value_labels,
            value_label_reference_counts: &value_label_reference_counts,
        };
        assert!(matches!(
            classify_read_column(&column, &attributes, true).expect("classification"),
            ColumnShape::SemanticDouble
        ));

        let document = ArrowFieldDocument {
            r: r_semantics("integer"),
            ..ArrowFieldDocument::default()
        };
        let profiled = ColumnAttributes {
            document: Some(&document),
            value_labels: &value_labels,
            value_label_reference_counts: &value_label_reference_counts,
        };
        let error = match classify_read_column(&column, &profiled, true) {
            Err(error) => error,
            Ok(_) => panic!("profiled integers cannot contain R's NA sentinel as a value"),
        };
        assert!(error.contains("declares R integer semantics"));
    }

    #[test]
    fn wide_integers_must_fit_exactly_in_r_doubles() {
        const CONSECUTIVE_INTEGER_LIMIT: i64 = 9_007_199_254_740_992;
        assert_eq!(
            exact_i64_as_r_double(CONSECUTIVE_INTEGER_LIMIT, "x").expect("boundary is exact"),
            CONSECUTIVE_INTEGER_LIMIT as f64
        );
        assert_eq!(
            exact_i64_as_r_double(-CONSECUTIVE_INTEGER_LIMIT, "x")
                .expect("negative boundary is exact"),
            -(CONSECUTIVE_INTEGER_LIMIT as f64)
        );
        assert!(exact_i64_as_r_double(CONSECUTIVE_INTEGER_LIMIT + 1, "x").is_err());
        assert!(exact_i64_as_r_double(-CONSECUTIVE_INTEGER_LIMIT - 1, "x").is_err());
        assert!(exact_i64_as_r_double(CONSECUTIVE_INTEGER_LIMIT * 2, "x").is_ok());
        assert!(exact_i64_as_r_double(i64::MIN, "x").is_ok());
        assert!(exact_i64_as_r_double(i64::MAX, "x").is_err());
        assert_eq!(
            exact_u64_as_r_double(CONSECUTIVE_INTEGER_LIMIT as u64, "x")
                .expect("unsigned boundary is exact"),
            CONSECUTIVE_INTEGER_LIMIT as f64
        );
        assert!(exact_u64_as_r_double(CONSECUTIVE_INTEGER_LIMIT as u64 + 1, "x").is_err());
        assert!(exact_u64_as_r_double(CONSECUTIVE_INTEGER_LIMIT as u64 * 2, "x").is_ok());
        assert!(exact_u64_as_r_double(u64::MAX, "x").is_err());
    }

    #[test]
    fn native_interrupts_and_large_string_offsets_are_classified() {
        assert!(native_arrow_interrupted("interrupted"));
        assert!(native_arrow_interrupted("DTA read interrupted"));
        assert!(native_arrow_interrupted("Arrow read interrupted"));
        assert!(native_arrow_interrupted("Arrow write interrupted"));
        assert!(!native_arrow_interrupted("could not read the input"));
        assert!(!uses_large_string_offsets(i32::MAX as usize));
        assert!(uses_large_string_offsets(i32::MAX as usize + 1));
    }

    #[test]
    fn temporal_counts_must_round_trip_through_r_doubles() {
        let nanos = DataType::Timestamp(TimeUnit::Nanosecond, Some("UTC".into()));
        assert_eq!(
            exact_temporal_as_r_double(1, 1_000_000_000.0, 1.0, "x", &nanos)
                .expect("one nanosecond round-trips"),
            1e-9
        );
        assert!(exact_temporal_as_r_double(
            1_700_000_000_000_000_001,
            1_000_000_000.0,
            1.0,
            "x",
            &nanos,
        )
        .is_err());
        assert_eq!(
            exact_temporal_as_r_double(
                3_600_000_000_000,
                1_000_000_000.0,
                3_600.0,
                "elapsed",
                &DataType::Duration(TimeUnit::Nanosecond),
            )
            .expect("one hour round-trips"),
            1.0
        );
    }
}
