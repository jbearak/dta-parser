use std::any::Any;
use std::borrow::Cow;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::fs::OpenOptions;
use std::io::{BufWriter, Write};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

use ahash::AHashMap;
use dta_parser::{
    write_dta_to, ColumnValues, DtaColumnSink, DtaData, DtaError, DtaFile, DtaMetadata, DtaSink,
    DtaType, DtaWriteColumn, DtaWriteColumnSource, DtaWriteColumnValues, DtaWriteData,
    DtaWriteLabelValue, DtaWriteNumericValue, DtaWriteOptions, DtaWriteValueLabel, FormatVersion,
    MissingTag, ParallelDtaSink, ReadOptions, StataVersion, TextEncoding, ValueLabelTable,
    VariableInfo,
};

type Sexp = *mut c_void;
type RLen = isize;

const INTSXP: c_int = 13;
const REALSXP: c_int = 14;
const STRSXP: c_int = 16;
const VECSXP: c_int = 19;
const RAWSXP: c_int = 24;
const CE_UTF8: c_int = 1;
const INTERRUPT_STRIDE: usize = 16_384;
const R_DATA_FRAME_MAX_ROWS: u64 = c_int::MAX as u64;
const SECONDS_1960_TO_1970: f64 = 315_619_200.0;
const DAYS_1960_TO_1970: f64 = 3_653.0;

extern "C" {
    fn SET_STRING_ELT(vector: Sexp, index: RLen, value: Sexp);
    fn SET_VECTOR_ELT(vector: Sexp, index: RLen, value: Sexp) -> Sexp;
    fn INTEGER(vector: Sexp) -> *mut c_int;
    fn REAL(vector: Sexp) -> *mut f64;
    fn RAW(vector: Sexp) -> *mut u8;

    static mut R_NamesSymbol: Sexp;
    static mut R_ClassSymbol: Sexp;
    static mut R_RowNamesSymbol: Sexp;
    static mut R_NaReal: f64;
    static mut R_NaInt: c_int;

    fn dtaparser_check_interrupt() -> c_int;
    fn dtaparser_alloc_vector(kind: c_int, length: RLen, result: *mut Sexp) -> c_int;
    fn dtaparser_release_object(object: Sexp);
    fn dtaparser_make_char(
        value: *const c_char,
        length: c_int,
        encoding: c_int,
        result: *mut Sexp,
    ) -> c_int;
    fn dtaparser_make_dictstring(
        data: *mut c_void,
        value_count: usize,
        transferred: *mut c_int,
        result: *mut Sexp,
    ) -> c_int;
    fn dtaparser_make_numeric(
        data: *mut c_void,
        backing: Sexp,
        transferred: *mut c_int,
        result: *mut Sexp,
    ) -> c_int;
    fn dtaparser_install(name: *const c_char, result: *mut Sexp) -> c_int;
    fn dtaparser_set_attrib(object: Sexp, name: Sexp, value: Sexp) -> c_int;
    fn dtaparser_write_numeric_at(
        reader: *const c_void,
        index: usize,
        value: *mut f64,
        missing_code: *mut c_int,
    ) -> c_int;
    fn dtaparser_write_string_at(
        values: Sexp,
        index: usize,
        value: *mut *const c_char,
        length: *mut usize,
        missing: *mut c_int,
    ) -> c_int;
}

#[repr(C)]
struct NumericData {
    values: *mut c_void,
    length: usize,
    kind: c_int,
    temporal: c_int,
    format_version: c_int,
    no_na: c_int,
}

impl NumericData {
    fn new(data: RNumericData) -> Self {
        Self {
            values: data.values.cast::<c_void>(),
            length: data.length,
            kind: data.kind as c_int,
            temporal: data.temporal as c_int,
            format_version: c_int::from(data.format_version.as_u16()),
            no_na: c_int::from(data.no_na),
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
enum NumericKind {
    Byte = 0,
    Int = 1,
    Long = 2,
    Float = 3,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum EagerNumericKind {
    Byte,
    Int,
    Long,
    Float,
    Double,
}

struct RNumericData {
    backing: Sexp,
    values: *mut u8,
    length: usize,
    kind: NumericKind,
    temporal: TemporalKind,
    format_version: FormatVersion,
    no_na: bool,
}

#[no_mangle]
/// Release numeric storage previously transferred to an R ALTREP vector.
///
/// # Safety
///
/// `data` must be null or a live pointer created by `ProtectGuard::numeric`,
/// and it must not have been freed previously.
pub unsafe extern "C" fn dtaparser_numeric_free(data: *mut c_void) {
    if data.is_null() {
        return;
    }
    drop(Box::from_raw(data.cast::<NumericData>()));
}

#[no_mangle]
/// Allocate the descriptor for compact numeric storage created by R code.
///
/// # Safety
///
/// `values` must point into an R raw vector that remains protected by the
/// resulting ALTREP external pointer. `kind` and `temporal` must use the
/// `NumericKind` and `TemporalKind` discriminants shared with `init.c`.
pub unsafe extern "C" fn dtaparser_numeric_alloc(
    values: *mut c_void,
    length: usize,
    kind: c_int,
    temporal: c_int,
    no_na: c_int,
) -> *mut c_void {
    let kind = match kind {
        0 => NumericKind::Byte,
        1 => NumericKind::Int,
        2 => NumericKind::Long,
        3 => NumericKind::Float,
        _ => return ptr::null_mut(),
    };
    let temporal = match temporal {
        0 => TemporalKind::None,
        1 => TemporalKind::Date,
        2 => TemporalKind::Datetime,
        _ => return ptr::null_mut(),
    };
    Box::into_raw(Box::new(NumericData {
        values,
        length,
        kind: kind as c_int,
        temporal: temporal as c_int,
        format_version: 119,
        no_na,
    }))
    .cast::<c_void>()
}

#[repr(C)]
struct DictStringData {
    value_ids: *mut u32,
    length: usize,
    value_views: Vec<(*const u8, usize)>,
    // Owns the string buffers referenced by `value_views`. Declared after the
    // views so it is dropped after them.
    _values: AHashMap<String, u32>,
}

impl DictStringData {
    fn new(
        value_ids: Vec<u32>,
        values: AHashMap<String, u32>,
        value_views: Vec<(*const u8, usize)>,
    ) -> Self {
        let ids = value_ids.into_boxed_slice();
        let length = ids.len();
        let value_ids = Box::into_raw(ids).cast::<u32>();
        Self {
            value_ids,
            length,
            value_views,
            _values: values,
        }
    }
}

#[no_mangle]
/// Borrow UTF-8 bytes from a live dictionary-string ALTREP payload.
///
/// # Safety
///
/// `data` must point to a live `DictStringData`. `value` and `length` must
/// point to writable output storage. The returned byte pointer remains valid
/// until `data` is released.
pub unsafe extern "C" fn dtaparser_dictstring_bytes(
    data: *mut c_void,
    id: u32,
    value: *mut *const c_char,
    length: *mut c_int,
) -> c_int {
    if data.is_null() || value.is_null() || length.is_null() {
        return 0;
    }
    let data = &*data.cast::<DictStringData>();
    let Some(&(bytes, byte_length)) = data.value_views.get(id as usize) else {
        return 0;
    };
    let Ok(byte_length) = c_int::try_from(byte_length) else {
        return 0;
    };
    *value = bytes.cast::<c_char>();
    *length = byte_length;
    1
}

#[no_mangle]
/// Release dictionary indices previously transferred to an R ALTREP vector.
///
/// # Safety
///
/// `data` must be null or a live pointer created by `ProtectGuard::dictstring`,
/// and it must not have been freed previously.
pub unsafe extern "C" fn dtaparser_dictstring_free(data: *mut c_void) {
    if data.is_null() {
        return;
    }
    let data = Box::from_raw(data.cast::<DictStringData>());
    let values = ptr::slice_from_raw_parts_mut(data.value_ids, data.length);
    drop(Box::from_raw(values));
    drop(data);
}

struct ProtectGuard {
    objects: Vec<Sexp>,
}

impl ProtectGuard {
    fn new() -> Self {
        Self {
            objects: Vec::new(),
        }
    }

    unsafe fn alloc(&mut self, kind: c_int, length: RLen) -> Result<Sexp, String> {
        self.objects
            .try_reserve(1)
            .map_err(|_| "R could not track a preserved native vector".to_owned())?;
        let mut value = ptr::null_mut();
        if dtaparser_alloc_vector(kind, length, &mut value) == 0 || value.is_null() {
            return Err("R could not allocate or preserve a native vector".to_owned());
        }
        self.objects.push(value);
        Ok(value)
    }

    unsafe fn dictstring(&mut self, mut data: RStringData) -> Result<Sexp, String> {
        self.objects
            .try_reserve(1)
            .map_err(|_| "R could not track a preserved native vector".to_owned())?;
        for &(_, length) in &data.value_views {
            c_int::try_from(length).map_err(|_| "R string is too long".to_owned())?;
        }

        let value_count = data.values.len();
        let storage = Box::into_raw(Box::new(DictStringData::new(
            std::mem::take(&mut data.value_ids),
            std::mem::replace(&mut data.values, AHashMap::new()),
            std::mem::take(&mut data.value_views),
        )))
        .cast::<c_void>();
        let mut transferred = 0;
        let mut result = ptr::null_mut();
        let ok = dtaparser_make_dictstring(storage, value_count, &mut transferred, &mut result);
        if ok == 0 || result.is_null() {
            if transferred == 0 {
                dtaparser_dictstring_free(storage);
            }
            return Err("R could not allocate a dictionary string vector".to_owned());
        }
        self.objects.push(result);
        Ok(result)
    }

    unsafe fn numeric(&mut self, data: RNumericData) -> Result<Sexp, String> {
        self.objects
            .try_reserve(1)
            .map_err(|_| "R could not track a preserved native vector".to_owned())?;
        let backing = data.backing;
        let storage = Box::into_raw(Box::new(NumericData::new(data))).cast::<c_void>();
        let mut transferred = 0;
        let mut result = ptr::null_mut();
        let ok = dtaparser_make_numeric(storage, backing, &mut transferred, &mut result);
        if ok == 0 || result.is_null() {
            if transferred == 0 {
                dtaparser_numeric_free(storage);
            }
            return Err("R could not allocate a numeric ALTREP vector".to_owned());
        }
        self.objects.push(result);
        Ok(result)
    }
}

impl Drop for ProtectGuard {
    fn drop(&mut self) {
        for &object in self.objects.iter().rev() {
            unsafe { dtaparser_release_object(object) };
        }
    }
}

fn check_interrupt() -> Result<(), String> {
    if unsafe { dtaparser_check_interrupt() } == 0 {
        Ok(())
    } else {
        Err("DTA read interrupted".to_owned())
    }
}

fn poll_interrupt(index: usize) -> Result<(), String> {
    if index.is_multiple_of(INTERRUPT_STRIDE) {
        check_interrupt()?;
    }
    Ok(())
}

fn coarse_interrupt() -> bool {
    unsafe { dtaparser_check_interrupt() != 0 }
}

fn frequent_interrupt_poller() -> impl FnMut() -> bool {
    let mut calls = 0_usize;
    move || {
        let poll = calls.is_multiple_of(INTERRUPT_STRIDE);
        calls = calls.wrapping_add(1);
        poll && unsafe { dtaparser_check_interrupt() != 0 }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
enum TemporalKind {
    None = 0,
    Date = 1,
    Datetime = 2,
}

fn temporal_kind(format: &str) -> TemporalKind {
    if format.starts_with("%tC") || format.starts_with("%tc") {
        TemporalKind::Datetime
    } else if format.starts_with("%td") || format.starts_with("%d") {
        TemporalKind::Date
    } else {
        TemporalKind::None
    }
}

fn observed_value(value: f64, temporal: TemporalKind) -> f64 {
    match temporal {
        TemporalKind::None => value,
        TemporalKind::Date => value - DAYS_1960_TO_1970,
        TemporalKind::Datetime => value / 1_000.0 - SECONDS_1960_TO_1970,
    }
}

fn r_missing_with_system(tag: MissingTag, system_missing: f64) -> f64 {
    if tag == MissingTag::System {
        return system_missing;
    }
    let letter = u64::from(b'a' + tag.offset() - 1);
    f64::from_bits(0x7ff0_0000_0000_07a2_u64 | (letter << 32))
}

fn r_missing(tag: MissingTag) -> f64 {
    r_missing_with_system(tag, unsafe { R_NaReal })
}

unsafe fn r_char(value: &str) -> Result<Sexp, String> {
    let length = c_int::try_from(value.len()).map_err(|_| "R string is too long".to_owned())?;
    let mut result = ptr::null_mut();
    if dtaparser_make_char(
        value.as_ptr().cast::<c_char>(),
        length,
        CE_UTF8,
        &mut result,
    ) == 0
        || result.is_null()
    {
        return Err("R could not allocate a character value".to_owned());
    }
    Ok(result)
}

unsafe fn string_vector(values: &[String], guard: &mut ProtectGuard) -> Result<Sexp, String> {
    let vector = guard.alloc(
        STRSXP,
        RLen::try_from(values.len()).map_err(|_| "R vector is too long".to_owned())?,
    )?;
    for (index, value) in values.iter().enumerate() {
        poll_interrupt(index)?;
        SET_STRING_ELT(vector, index as RLen, r_char(value)?);
    }
    Ok(vector)
}

unsafe fn scalar_string(value: &str, guard: &mut ProtectGuard) -> Result<Sexp, String> {
    string_vector(&[value.to_owned()], guard)
}

unsafe fn scalar_integer(value: c_int, guard: &mut ProtectGuard) -> Result<Sexp, String> {
    let vector = guard.alloc(INTSXP, 1)?;
    *INTEGER(vector) = value;
    Ok(vector)
}

unsafe fn set_attr(object: Sexp, name: &str, value: Sexp) -> Result<(), String> {
    let name = CString::new(name).map_err(|_| "invalid R attribute name".to_owned())?;
    let mut symbol = ptr::null_mut();
    if dtaparser_install(name.as_ptr(), &mut symbol) == 0 || symbol.is_null() {
        return Err("R could not install an attribute name".to_owned());
    }
    set_symbol_attr(object, symbol, value)?;
    Ok(())
}

unsafe fn set_symbol_attr(object: Sexp, name: Sexp, value: Sexp) -> Result<(), String> {
    if dtaparser_set_attrib(object, name, value) == 0 {
        return Err("R could not attach a native vector attribute".to_owned());
    }
    Ok(())
}

unsafe fn set_class(
    object: Sexp,
    classes: &[&str],
    guard: &mut ProtectGuard,
) -> Result<(), String> {
    let values = classes
        .iter()
        .map(|value| (*value).to_owned())
        .collect::<Vec<_>>();
    let class = string_vector(&values, guard)?;
    set_symbol_attr(object, R_ClassSymbol, class)
}

unsafe fn label_attribute(
    table: &ValueLabelTable,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let length = RLen::try_from(table.entries.len()).map_err(|_| "label table is too long")?;
    let values = guard.alloc(REALSXP, length)?;
    let names = guard.alloc(STRSXP, length)?;
    let output = REAL(values);
    for (index, entry) in table.entries.iter().enumerate() {
        poll_interrupt(index)?;
        *output.add(index) = entry
            .missing_tag
            .map(r_missing)
            .unwrap_or_else(|| f64::from(entry.value));
        SET_STRING_ELT(names, index as RLen, r_char(&entry.label)?);
    }
    set_symbol_attr(values, R_NamesSymbol, names)?;
    Ok(values)
}

unsafe fn attach_variable_attributes(
    vector: Sexp,
    variable: &VariableInfo,
    table: Option<&ValueLabelTable>,
    guard: &mut ProtectGuard,
) -> Result<(), String> {
    check_interrupt()?;
    if !variable.label.is_empty() {
        let label = scalar_string(&variable.label, guard)?;
        set_attr(vector, "label", label)?;
    }
    if !variable.format.is_empty() {
        let format = scalar_string(&variable.format, guard)?;
        set_attr(vector, "format.stata", format)?;
    }
    if let Some(table) = table {
        let labels = label_attribute(table, guard)?;
        set_attr(vector, "labels", labels)?;
    }

    let storage = match variable.dta_type {
        DtaType::Byte => Some(("byte", "stata_byte")),
        DtaType::Int => Some(("int", "stata_int")),
        DtaType::Long => Some(("long", "stata_long")),
        DtaType::Float => Some(("float", "stata_float")),
        DtaType::Double => Some(("double", "stata_double")),
        DtaType::FixedString(_) | DtaType::StrL => None,
    };
    if let Some((storage_name, _)) = storage {
        let storage_value = scalar_string(storage_name, guard)?;
        set_attr(vector, "stata.storage", storage_value)?;
    }

    match (temporal_kind(&variable.format), storage) {
        (TemporalKind::Date, Some(_)) => {
            set_class(vector, &["stata_temporal", "stata_date", "Date"], guard)?;
        }
        (TemporalKind::Datetime, Some(_)) => {
            set_class(
                vector,
                &["stata_temporal", "stata_datetime", "POSIXct", "POSIXt"],
                guard,
            )?;
            let timezone = scalar_string("UTC", guard)?;
            set_attr(vector, "tzone", timezone)?;
        }
        (TemporalKind::None, Some((_, storage_class))) if table.is_some() => {
            set_class(
                vector,
                &[
                    "stata_numeric",
                    storage_class,
                    "haven_labelled",
                    "vctrs_vctr",
                    "double",
                ],
                guard,
            )?;
        }
        (TemporalKind::None, Some((_, storage_class))) => set_class(
            vector,
            &["stata_numeric", storage_class, "vctrs_vctr", "double"],
            guard,
        )?,
        (TemporalKind::Date, None) => set_class(vector, &["Date"], guard)?,
        (TemporalKind::Datetime, None) => {
            set_class(vector, &["POSIXct", "POSIXt"], guard)?;
            let timezone = scalar_string("UTC", guard)?;
            set_attr(vector, "tzone", timezone)?;
        }
        (TemporalKind::None, None) if table.is_some() => {
            set_class(vector, &["haven_labelled", "vctrs_vctr", "double"], guard)?;
        }
        (TemporalKind::None, None) => {}
    }
    Ok(())
}

unsafe fn numeric_column<T: Copy + Into<f64>>(
    values: &[T],
    missing: &[Option<MissingTag>],
    temporal: TemporalKind,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let length = RLen::try_from(values.len()).map_err(|_| "R vector is too long")?;
    let vector = guard.alloc(REALSXP, length)?;
    let output = REAL(vector);
    for index in 0..values.len() {
        poll_interrupt(index)?;
        *output.add(index) = missing[index]
            .map(r_missing)
            .unwrap_or_else(|| observed_value(values[index].into(), temporal));
    }
    Ok(vector)
}

unsafe fn build_column(
    data: &DtaData,
    column_index: usize,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let column = &data.columns[column_index];
    let variable = data
        .metadata
        .variables
        .get(column.variable_index as usize)
        .ok_or_else(|| "decoded column metadata index is invalid".to_owned())?;
    let temporal = temporal_kind(&variable.format);
    let vector = match &column.values {
        ColumnValues::Byte {
            values,
            missing_tags,
        } => numeric_column(values, missing_tags, temporal, guard)?,
        ColumnValues::Int {
            values,
            missing_tags,
        } => numeric_column(values, missing_tags, temporal, guard)?,
        ColumnValues::Long {
            values,
            missing_tags,
        } => numeric_column(values, missing_tags, temporal, guard)?,
        ColumnValues::Float {
            values,
            missing_tags,
        } => numeric_column(values, missing_tags, temporal, guard)?,
        ColumnValues::Double {
            values,
            missing_tags,
        } => numeric_column(values, missing_tags, temporal, guard)?,
        ColumnValues::FixedString { values } | ColumnValues::StrL { values } => {
            string_vector(values, guard)?
        }
    };
    let table = data.value_label_table_for_variable(column.variable_index);
    attach_variable_attributes(vector, variable, table, guard)?;
    Ok(vector)
}

unsafe fn attach_dataset_attributes(result: Sexp, metadata: &DtaMetadata) -> Result<(), String> {
    if !metadata.dataset_label.is_empty() {
        check_interrupt()?;
        let mut guard = ProtectGuard::new();
        let label = scalar_string(&metadata.dataset_label, &mut guard)?;
        set_attr(result, "label", label)?;
    }
    if !metadata.notes.is_empty() {
        check_interrupt()?;
        let mut guard = ProtectGuard::new();
        let notes = string_vector(&metadata.notes, &mut guard)?;
        set_attr(result, "notes", notes)?;
    }
    Ok(())
}

unsafe fn build_data_frame(data: &DtaData) -> Result<Sexp, String> {
    let mut result_guard = ProtectGuard::new();
    let column_count = RLen::try_from(data.columns.len()).map_err(|_| "too many columns")?;
    let result = result_guard.alloc(VECSXP, column_count)?;
    let names = result_guard.alloc(STRSXP, column_count)?;

    for index in 0..data.columns.len() {
        check_interrupt()?;
        {
            let mut column_guard = ProtectGuard::new();
            let column = build_column(data, index, &mut column_guard)?;
            SET_VECTOR_ELT(result, index as RLen, column);
            let variable = &data.metadata.variables[data.columns[index].variable_index as usize];
            SET_STRING_ELT(names, index as RLen, r_char(&variable.name)?);
        }
    }
    set_symbol_attr(result, R_NamesSymbol, names)?;

    let row_count = c_int::try_from(data.row_count)
        .map_err(|_| "R data frames cannot contain more than 2^31-1 rows".to_owned())?;
    {
        let mut attribute_guard = ProtectGuard::new();
        let row_names = attribute_guard.alloc(INTSXP, 2)?;
        *INTEGER(row_names) = R_NaInt;
        *INTEGER(row_names).add(1) = -row_count;
        set_symbol_attr(result, R_RowNamesSymbol, row_names)?;
    }
    {
        let mut attribute_guard = ProtectGuard::new();
        set_class(
            result,
            &["tbl_df", "tbl", "data.frame"],
            &mut attribute_guard,
        )?;
    }

    attach_dataset_attributes(result, &data.metadata)?;
    Ok(result)
}

struct RStringData {
    value_ids: Vec<u32>,
    values: AHashMap<String, u32>,
    value_views: Vec<(*const u8, usize)>,
    cycle_period: Option<usize>,
    cycle_rejected: bool,
}

impl RStringData {
    fn new(expected_rows: usize) -> Result<Self, DtaError> {
        let mut value_ids = Vec::new();
        value_ids
            .try_reserve_exact(expected_rows)
            .map_err(|_| DtaError::Output("could not allocate R string indices".to_owned()))?;
        Ok(Self {
            value_ids,
            values: AHashMap::new(),
            value_views: Vec::new(),
            cycle_period: None,
            cycle_rejected: false,
        })
    }

    fn push_id(&mut self, id: u32) -> Result<(), DtaError> {
        self.value_ids
            .try_reserve(1)
            .map_err(|_| DtaError::Output("could not grow R string indices".to_owned()))?;
        self.value_ids.push(id);
        Ok(())
    }

    fn value_matches(&self, id: u32, value: &str) -> bool {
        let Some(&(bytes, length)) = self.value_views.get(id as usize) else {
            return false;
        };
        // The views point into immutable String keys owned by `values`. Moving
        // a String during a hash-table resize does not move its heap buffer.
        let cached = unsafe { std::slice::from_raw_parts(bytes, length) };
        cached == value.as_bytes()
    }

    fn push(&mut self, row: usize, value: &str) -> Result<(), DtaError> {
        if self.value_ids.len() != row {
            return Err(DtaError::Output(format!(
                "string output row mismatch: expected {}, got {row}",
                self.value_ids.len()
            )));
        }
        if let Some(period) = self.cycle_period {
            let id = self.value_ids[row % period];
            if self.value_matches(id, value) {
                return self.push_id(id);
            }
            self.cycle_period = None;
            self.cycle_rejected = true;
        }
        let id = if let Some(&id) = self.values.get(value) {
            id
        } else {
            let id = u32::try_from(self.values.len())
                .map_err(|_| DtaError::Output("too many distinct R strings".to_owned()))?;
            self.values
                .try_reserve(1)
                .map_err(|_| DtaError::Output("could not grow the R string cache".to_owned()))?;
            let mut owned = String::new();
            owned
                .try_reserve_exact(value.len())
                .map_err(|_| DtaError::Output("could not cache an R string".to_owned()))?;
            owned.push_str(value);
            self.value_views
                .try_reserve(1)
                .map_err(|_| DtaError::Output("could not grow R string views".to_owned()))?;
            let view = (owned.as_ptr(), owned.len());
            self.values.insert(owned, id);
            self.value_views.push(view);
            id
        };
        if !self.cycle_rejected && row > 0 && id == self.value_ids[0] {
            self.cycle_period = Some(row);
        }
        self.push_id(id)
    }

    fn push_utf8_bytes(&mut self, row: usize, value: &[u8]) -> Result<(), DtaError> {
        if self.value_ids.len() != row {
            return Err(DtaError::Output(format!(
                "string output row mismatch: expected {}, got {row}",
                self.value_ids.len()
            )));
        }
        if let Some(period) = self.cycle_period {
            let id = self.value_ids[row % period];
            let Some(&(cached, length)) = self.value_views.get(id as usize) else {
                return Err(DtaError::Output("invalid R string index".to_owned()));
            };
            // Valid UTF-8 is stored byte-for-byte in the canonical dictionary.
            // Checking it before UTF-8 validation makes repeated modern string
            // cycles a raw-byte operation. Malformed input falls through to
            // the ordinary replacement decoder, preserving exact semantics.
            let cached = unsafe { std::slice::from_raw_parts(cached, length) };
            if cached == value {
                return self.push_id(id);
            }
        }
        let decoded = String::from_utf8_lossy(value);
        self.push(row, &decoded)
    }
}

enum RColumn {
    NumericAltRep {
        vector: Sexp,
        data: RNumericData,
    },
    NumericEager {
        vector: Sexp,
        output: *mut f64,
        length: usize,
        source_kind: EagerNumericKind,
        temporal: TemporalKind,
        system_missing: f64,
    },
    String {
        vector: Sexp,
        data: RStringData,
    },
}

// Parallel workers receive disjoint columns. Numeric workers write to compact
// raw or eager double vectors allocated before threads start, while string
// workers mutate Rust-owned dictionaries. Workers never invoke the R API.
unsafe impl Send for RColumn {}

unsafe fn numeric_altrep_storage(
    dta_type: DtaType,
    length: usize,
    temporal: TemporalKind,
    format_version: FormatVersion,
    guard: &mut ProtectGuard,
) -> Result<RNumericData, DtaError> {
    let (kind, width) = match dta_type {
        DtaType::Byte => (NumericKind::Byte, std::mem::size_of::<i8>()),
        DtaType::Int => (NumericKind::Int, std::mem::size_of::<i16>()),
        DtaType::Long => (NumericKind::Long, std::mem::size_of::<i32>()),
        DtaType::Float => (NumericKind::Float, std::mem::size_of::<f32>()),
        DtaType::Double => {
            return Err(DtaError::Output(
                "double storage used for a narrow numeric ALTREP".to_owned(),
            ));
        }
        DtaType::FixedString(_) | DtaType::StrL => {
            return Err(DtaError::Output(
                "string type used for numeric output".to_owned(),
            ));
        }
    };
    let byte_length = length
        .checked_mul(width)
        .ok_or(DtaError::ArithmeticOverflow("numeric output bytes"))?;
    let byte_length = RLen::try_from(byte_length)
        .map_err(|_| DtaError::Output("R vector is too long".to_owned()))?;
    let backing = guard.alloc(RAWSXP, byte_length).map_err(DtaError::Output)?;
    Ok(RNumericData {
        backing,
        values: RAW(backing),
        length,
        kind,
        temporal,
        format_version,
        no_na: true,
    })
}

struct RDataFrameSink {
    result: Sexp,
    columns: Vec<RColumn>,
    source_indices: Vec<u32>,
    _guard: ProtectGuard,
}

impl RDataFrameSink {
    unsafe fn new(
        metadata: &DtaMetadata,
        row_count: u64,
        source_indices: &[u32],
        numeric_altrep: bool,
    ) -> Result<Self, DtaError> {
        let length = RLen::try_from(row_count)
            .map_err(|_| DtaError::Output("R vector is too long".to_owned()))?;
        let native_length = usize::try_from(length)
            .map_err(|_| DtaError::Output("R vector is too long".to_owned()))?;
        let column_count = RLen::try_from(source_indices.len())
            .map_err(|_| DtaError::Output("too many columns".to_owned()))?;
        let mut guard = ProtectGuard::new();
        let result = guard
            .alloc(VECSXP, column_count)
            .map_err(DtaError::Output)?;
        let names = guard
            .alloc(STRSXP, column_count)
            .map_err(DtaError::Output)?;
        let mut columns = Vec::new();
        columns
            .try_reserve_exact(source_indices.len())
            .map_err(|_| DtaError::Output("could not track R output columns".to_owned()))?;

        for (output_index, &source_index) in source_indices.iter().enumerate() {
            let variable = metadata
                .variables
                .get(source_index as usize)
                .ok_or(DtaError::ArithmeticOverflow("output source column"))?;
            let column = match variable.dta_type {
                DtaType::FixedString(_) | DtaType::StrL => RColumn::String {
                    vector: ptr::null_mut(),
                    data: RStringData::new(
                        usize::try_from(row_count)
                            .map_err(|_| DtaError::Output("R vector is too long".to_owned()))?,
                    )?,
                },
                _ if !numeric_altrep || matches!(variable.dta_type, DtaType::Double) => {
                    let vector = guard.alloc(REALSXP, length).map_err(DtaError::Output)?;
                    let source_kind = match variable.dta_type {
                        DtaType::Byte => EagerNumericKind::Byte,
                        DtaType::Int => EagerNumericKind::Int,
                        DtaType::Long => EagerNumericKind::Long,
                        DtaType::Float => EagerNumericKind::Float,
                        DtaType::Double => EagerNumericKind::Double,
                        DtaType::FixedString(_) | DtaType::StrL => unreachable!(),
                    };
                    RColumn::NumericEager {
                        vector,
                        output: REAL(vector),
                        length: native_length,
                        source_kind,
                        temporal: temporal_kind(&variable.format),
                        system_missing: R_NaReal,
                    }
                }
                _ => RColumn::NumericAltRep {
                    vector: ptr::null_mut(),
                    data: numeric_altrep_storage(
                        variable.dta_type.clone(),
                        native_length,
                        temporal_kind(&variable.format),
                        metadata.format_version,
                        &mut guard,
                    )?,
                },
            };
            let vector = match &column {
                RColumn::NumericAltRep { vector, .. }
                | RColumn::NumericEager { vector, .. }
                | RColumn::String { vector, .. } => *vector,
            };
            if !vector.is_null() {
                SET_VECTOR_ELT(result, output_index as RLen, vector);
            }
            SET_STRING_ELT(
                names,
                output_index as RLen,
                r_char(&variable.name).map_err(DtaError::Output)?,
            );
            columns.push(column);
        }
        set_symbol_attr(result, R_NamesSymbol, names).map_err(DtaError::Output)?;

        Ok(Self {
            result,
            columns,
            source_indices: source_indices.to_vec(),
            _guard: guard,
        })
    }

    #[inline(always)]
    fn numeric_column_mut(&mut self, column: usize) -> Result<&mut RColumn, DtaError> {
        match self.columns.get_mut(column) {
            Some(column @ (RColumn::NumericAltRep { .. } | RColumn::NumericEager { .. })) => {
                Ok(column)
            }
            _ => Err(DtaError::Output(
                "numeric output column mismatch".to_owned(),
            )),
        }
    }

    #[inline(always)]
    fn push_string_value(
        &mut self,
        column: usize,
        row: usize,
        value: &str,
    ) -> Result<(), DtaError> {
        match self.columns.get_mut(column) {
            Some(RColumn::String { data, .. }) => data.push(row, value),
            _ => Err(DtaError::Output("string output column mismatch".to_owned())),
        }
    }
}

impl RNumericData {
    fn take(&mut self) -> Self {
        let replacement = Self {
            backing: ptr::null_mut(),
            values: ptr::null_mut(),
            length: 0,
            kind: self.kind,
            temporal: self.temporal,
            format_version: self.format_version,
            no_na: true,
        };
        std::mem::replace(self, replacement)
    }

    #[inline(always)]
    fn write_value<T: Copy>(
        &mut self,
        row: usize,
        value: T,
        kind: NumericKind,
        no_na: bool,
    ) -> Result<(), DtaError> {
        if self.kind != kind {
            return Err(DtaError::Output(
                "value used for another numeric storage type".to_owned(),
            ));
        }
        if row >= self.length {
            return Err(Self::row_error(row, self.length));
        }
        self.no_na &= no_na;
        unsafe {
            self.values
                .add(row * std::mem::size_of::<T>())
                .cast::<T>()
                .write_unaligned(value);
        }
        Ok(())
    }

    fn row_error(row: usize, length: usize) -> DtaError {
        DtaError::Output(format!(
            "numeric output row {row} is out of bounds for length {length}"
        ))
    }

    #[inline(always)]
    fn write_byte(
        &mut self,
        row: usize,
        value: i8,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_value(row, value, NumericKind::Byte, missing.is_none())
    }

    #[inline(always)]
    fn write_int(
        &mut self,
        row: usize,
        value: i16,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_value(row, value, NumericKind::Int, missing.is_none())
    }

    #[inline(always)]
    fn write_long(
        &mut self,
        row: usize,
        value: i32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_value(row, value, NumericKind::Long, missing.is_none())
    }

    #[inline(always)]
    fn write_float(
        &mut self,
        row: usize,
        value: f32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_value(
            row,
            value,
            NumericKind::Float,
            missing.is_none() && !value.is_nan(),
        )
    }
}

impl RColumn {
    #[inline(always)]
    fn write_eager_numeric(
        &mut self,
        row: usize,
        value: f64,
        missing: Option<MissingTag>,
        expected_kind: EagerNumericKind,
    ) -> Result<(), DtaError> {
        let Self::NumericEager {
            output,
            length,
            source_kind,
            temporal,
            system_missing,
            ..
        } = self
        else {
            return Err(DtaError::Output(
                "numeric output column mismatch".to_owned(),
            ));
        };
        if *source_kind != expected_kind {
            return Err(DtaError::Output(
                "value used for another numeric storage type".to_owned(),
            ));
        }
        if row >= *length {
            return Err(RNumericData::row_error(row, *length));
        }
        unsafe {
            *output.add(row) = missing
                .map(|tag| r_missing_with_system(tag, *system_missing))
                .unwrap_or_else(|| observed_value(value, *temporal));
        }
        Ok(())
    }

    #[inline(always)]
    fn store_byte(
        &mut self,
        row: usize,
        value: i8,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        match self {
            Self::NumericAltRep { data, .. } => data.write_byte(row, value, missing),
            Self::NumericEager { .. } => {
                self.write_eager_numeric(row, f64::from(value), missing, EagerNumericKind::Byte)
            }
            Self::String { .. } => Err(DtaError::Output(
                "numeric output column mismatch".to_owned(),
            )),
        }
    }

    #[inline(always)]
    fn store_int(
        &mut self,
        row: usize,
        value: i16,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        match self {
            Self::NumericAltRep { data, .. } => data.write_int(row, value, missing),
            Self::NumericEager { .. } => {
                self.write_eager_numeric(row, f64::from(value), missing, EagerNumericKind::Int)
            }
            Self::String { .. } => Err(DtaError::Output(
                "numeric output column mismatch".to_owned(),
            )),
        }
    }

    #[inline(always)]
    fn store_long(
        &mut self,
        row: usize,
        value: i32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        match self {
            Self::NumericAltRep { data, .. } => data.write_long(row, value, missing),
            Self::NumericEager { .. } => {
                self.write_eager_numeric(row, f64::from(value), missing, EagerNumericKind::Long)
            }
            Self::String { .. } => Err(DtaError::Output(
                "numeric output column mismatch".to_owned(),
            )),
        }
    }

    #[inline(always)]
    fn store_float(
        &mut self,
        row: usize,
        value: f32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        match self {
            Self::NumericAltRep { data, .. } => data.write_float(row, value, missing),
            Self::NumericEager { .. } => {
                self.write_eager_numeric(row, f64::from(value), missing, EagerNumericKind::Float)
            }
            Self::String { .. } => Err(DtaError::Output(
                "numeric output column mismatch".to_owned(),
            )),
        }
    }

    #[inline(always)]
    fn store_double(
        &mut self,
        row: usize,
        value: f64,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_eager_numeric(row, value, missing, EagerNumericKind::Double)
    }
}

impl DtaColumnSink for RColumn {
    fn push_byte(
        &mut self,
        row: usize,
        value: i8,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.store_byte(row, value, missing)
    }

    fn push_int(
        &mut self,
        row: usize,
        value: i16,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.store_int(row, value, missing)
    }

    fn push_long(
        &mut self,
        row: usize,
        value: i32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.store_long(row, value, missing)
    }

    fn push_float(
        &mut self,
        row: usize,
        value: f32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.store_float(row, value, missing)
    }

    fn push_double(
        &mut self,
        row: usize,
        value: f64,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.store_double(row, value, missing)
    }

    fn push_fixed_string(&mut self, row: usize, value: &str) -> Result<(), DtaError> {
        let Self::String { data, .. } = self else {
            return Err(DtaError::Output("string output column mismatch".to_owned()));
        };
        data.push(row, value)
    }

    fn try_push_fixed_string_bytes(
        &mut self,
        row: usize,
        value: &[u8],
        encoding: TextEncoding,
    ) -> Result<bool, DtaError> {
        if encoding != TextEncoding::Utf8 {
            return Ok(false);
        }
        let Self::String { data, .. } = self else {
            return Err(DtaError::Output("string output column mismatch".to_owned()));
        };
        data.push_utf8_bytes(row, value)?;
        Ok(true)
    }

    fn push_strl(&mut self, row: usize, value: &str) -> Result<(), DtaError> {
        let Self::String { data, .. } = self else {
            return Err(DtaError::Output("string output column mismatch".to_owned()));
        };
        data.push(row, value)
    }
}

impl DtaSink for RDataFrameSink {
    type Output = Sexp;

    #[inline(always)]
    fn push_byte(
        &mut self,
        column: usize,
        row: usize,
        value: i8,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.numeric_column_mut(column)?
            .store_byte(row, value, missing)
    }

    #[inline(always)]
    fn push_int(
        &mut self,
        column: usize,
        row: usize,
        value: i16,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.numeric_column_mut(column)?
            .store_int(row, value, missing)
    }

    #[inline(always)]
    fn push_long(
        &mut self,
        column: usize,
        row: usize,
        value: i32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.numeric_column_mut(column)?
            .store_long(row, value, missing)
    }

    #[inline(always)]
    fn push_float(
        &mut self,
        column: usize,
        row: usize,
        value: f32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.numeric_column_mut(column)?
            .store_float(row, value, missing)
    }

    #[inline(always)]
    fn push_double(
        &mut self,
        column: usize,
        row: usize,
        value: f64,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.numeric_column_mut(column)?
            .store_double(row, value, missing)
    }

    #[inline(always)]
    fn push_fixed_string(
        &mut self,
        column: usize,
        row: usize,
        value: &str,
    ) -> Result<(), DtaError> {
        self.push_string_value(column, row, value)
    }

    fn try_push_fixed_string_bytes(
        &mut self,
        column: usize,
        row: usize,
        value: &[u8],
        encoding: TextEncoding,
    ) -> Result<bool, DtaError> {
        if encoding != TextEncoding::Utf8 {
            return Ok(false);
        }
        match self.columns.get_mut(column) {
            Some(RColumn::String { data, .. }) => {
                data.push_utf8_bytes(row, value)?;
                Ok(true)
            }
            _ => Err(DtaError::Output("string output column mismatch".to_owned())),
        }
    }

    #[inline(always)]
    fn push_strl(&mut self, column: usize, row: usize, value: &str) -> Result<(), DtaError> {
        self.push_string_value(column, row, value)
    }

    fn finish(
        mut self,
        metadata: DtaMetadata,
        _row_start: u64,
        row_count: u64,
        value_label_tables: Vec<ValueLabelTable>,
    ) -> Result<Self::Output, DtaError> {
        let expected_string_rows = usize::try_from(row_count)
            .map_err(|_| DtaError::Output("R vector is too long".to_owned()))?;
        unsafe {
            for (output_index, column) in self.columns.iter_mut().enumerate() {
                match column {
                    RColumn::NumericAltRep { vector, data } => {
                        let data = data.take();
                        *vector = self._guard.numeric(data).map_err(DtaError::Output)?;
                        SET_VECTOR_ELT(self.result, output_index as RLen, *vector);
                    }
                    RColumn::NumericEager { .. } => {}
                    RColumn::String { vector, data } => {
                        if data.value_ids.len() != expected_string_rows {
                            return Err(DtaError::Output(format!(
                                "string output row count mismatch: expected {expected_string_rows}, got {}",
                                data.value_ids.len()
                            )));
                        }
                        let data = std::mem::replace(data, RStringData::new(0)?);
                        *vector = self._guard.dictstring(data).map_err(DtaError::Output)?;
                        SET_VECTOR_ELT(self.result, output_index as RLen, *vector);
                    }
                }
            }

            for (output_index, &source_index) in self.source_indices.iter().enumerate() {
                check_interrupt().map_err(DtaError::Output)?;
                let variable = metadata
                    .variables
                    .get(source_index as usize)
                    .ok_or(DtaError::ArithmeticOverflow("output source column"))?;
                let table = if variable.value_label_name.is_empty() {
                    None
                } else {
                    value_label_tables
                        .iter()
                        .find(|table| table.name == variable.value_label_name)
                };
                let vector = match &self.columns[output_index] {
                    RColumn::NumericAltRep { vector, .. }
                    | RColumn::NumericEager { vector, .. }
                    | RColumn::String { vector, .. } => *vector,
                };
                let mut attribute_guard = ProtectGuard::new();
                attach_variable_attributes(vector, variable, table, &mut attribute_guard)
                    .map_err(DtaError::Output)?;
            }

            let row_count = c_int::try_from(row_count).map_err(|_| {
                DtaError::Output("R data frames cannot contain more than 2^31-1 rows".to_owned())
            })?;
            {
                let mut attribute_guard = ProtectGuard::new();
                let row_names = attribute_guard.alloc(INTSXP, 2).map_err(DtaError::Output)?;
                *INTEGER(row_names) = R_NaInt;
                *INTEGER(row_names).add(1) = -row_count;
                set_symbol_attr(self.result, R_RowNamesSymbol, row_names)
                    .map_err(DtaError::Output)?;
            }
            {
                let mut attribute_guard = ProtectGuard::new();
                set_class(
                    self.result,
                    &["tbl_df", "tbl", "data.frame"],
                    &mut attribute_guard,
                )
                .map_err(DtaError::Output)?;
            }
            attach_dataset_attributes(self.result, &metadata).map_err(DtaError::Output)?;
        }
        let result = self.result;
        Ok(result)
    }
}

struct RParallelState {
    result: Sexp,
    source_indices: Vec<u32>,
    guard: ProtectGuard,
}

impl ParallelDtaSink for RDataFrameSink {
    type Output = Sexp;
    type Column = RColumn;
    type State = RParallelState;

    fn split(self) -> (Self::State, Vec<Self::Column>) {
        (
            RParallelState {
                result: self.result,
                source_indices: self.source_indices,
                guard: self._guard,
            },
            self.columns,
        )
    }

    fn finish_parallel(
        state: Self::State,
        columns: Vec<Self::Column>,
        metadata: DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: Vec<ValueLabelTable>,
    ) -> Result<Self::Output, DtaError> {
        DtaSink::finish(
            RDataFrameSink {
                result: state.result,
                columns,
                source_indices: state.source_indices,
                _guard: state.guard,
            },
            metadata,
            row_start,
            row_count,
            value_label_tables,
        )
    }
}

unsafe fn metadata_impl(
    path: &str,
    encoding: TextEncoding,
    column_start: u32,
    column_count: u32,
) -> Result<Sexp, String> {
    let file = DtaFile::open_with_encoding(path, encoding).map_err(|error| error.to_string())?;
    let metadata = file.metadata();
    let start = usize::try_from(column_start)
        .map_err(|_| "metadata column start is out of range".to_owned())?
        .min(metadata.variables.len());
    let count = usize::try_from(column_count)
        .map_err(|_| "metadata column count is out of range".to_owned())?;
    let end = start.saturating_add(count).min(metadata.variables.len());
    let variables = &metadata.variables[start..end];
    let mut guard = ProtectGuard::new();
    let names = variables
        .iter()
        .map(|variable| variable.name.clone())
        .collect::<Vec<_>>();
    let result = string_vector(&names, &mut guard)?;
    let storage = variables
        .iter()
        .map(|variable| match variable.dta_type {
            DtaType::Byte => "byte".to_owned(),
            DtaType::Int => "int".to_owned(),
            DtaType::Long => "long".to_owned(),
            DtaType::Float => "float".to_owned(),
            DtaType::Double => "double".to_owned(),
            DtaType::FixedString(_) | DtaType::StrL => "character".to_owned(),
        })
        .collect::<Vec<_>>();
    let storage = string_vector(&storage, &mut guard)?;
    set_attr(result, "dta_storage", storage)?;
    let version = scalar_integer(metadata.format_version.as_u16().into(), &mut guard)?;
    set_attr(result, "dta_format_version", version)?;
    Ok(result)
}

fn selected_row_count(nobs: u64, row_start: u64, row_count: Option<u64>) -> u64 {
    let start = row_start.min(nobs);
    let available = nobs - start;
    row_count.map_or(available, |count| count.min(available))
}

fn validate_r_row_count(nobs: u64, row_start: u64, row_count: Option<u64>) -> Result<u64, String> {
    let output_rows = selected_row_count(nobs, row_start, row_count);
    if output_rows > R_DATA_FRAME_MAX_ROWS {
        return Err(format!(
            "selected row window contains {output_rows} rows; R data frames cannot contain more than {} rows",
            R_DATA_FRAME_MAX_ROWS
        ));
    }
    Ok(output_rows)
}

struct RReadConfig {
    direct_to_r: bool,
    numeric_altrep: bool,
    encoding: TextEncoding,
    requested_threads: usize,
}

unsafe fn read_impl(
    path: &str,
    columns: Option<Vec<u32>>,
    skip: f64,
    n_max: f64,
    config: RReadConfig,
) -> Result<Sexp, String> {
    // Public semantics are normalized once by the R wrapper. These checks are
    // only a defensive ABI guard for exact representability and +Inf as the
    // single unlimited sentinel.
    if !skip.is_finite() || skip < 0.0 || skip.fract() != 0.0 || skip > (1_u64 << 53) as f64 {
        return Err("invalid skip value".to_owned());
    }
    if n_max.is_nan()
        || n_max < 0.0
        || (n_max.is_finite() && (n_max.fract() != 0.0 || n_max > (1_u64 << 53) as f64))
    {
        return Err("invalid n_max value".to_owned());
    }
    let row_start = skip as u64;
    let row_count = if n_max.is_infinite() {
        None
    } else {
        Some(n_max as u64)
    };
    let mut file =
        DtaFile::open_with_encoding(path, config.encoding).map_err(|error| error.to_string())?;
    validate_r_row_count(file.metadata().nobs, row_start, row_count)?;
    let options = ReadOptions {
        row_start,
        row_count,
        column_indices: columns,
    };
    if config.direct_to_r {
        let threads = file
            .parallel_thread_count(&options, config.requested_threads)
            .map_err(|error| error.to_string())?;
        let columnar = file
            .supports_columnar_sink(&options)
            .map_err(|error| error.to_string())?;
        if threads > 1 || columnar {
            file.read_with_parallel_sink_and_interrupt(
                &options,
                threads,
                |metadata, _row_start, row_count, indices| unsafe {
                    RDataFrameSink::new(metadata, row_count, indices, config.numeric_altrep)
                },
                coarse_interrupt,
            )
            .map_err(|error| error.to_string())
        } else {
            file.read_with_sink_and_interrupts(
                &options,
                |metadata, _row_start, row_count, indices| unsafe {
                    RDataFrameSink::new(metadata, row_count, indices, config.numeric_altrep)
                },
                coarse_interrupt,
                frequent_interrupt_poller(),
            )
            .map_err(|error| error.to_string())
        }
    } else {
        let data = file
            .read_with_interrupts(&options, coarse_interrupt, frequent_interrupt_poller())
            .map_err(|error| error.to_string())?;
        build_data_frame(&data)
    }
}

fn panic_message(payload: Box<dyn Any + Send>) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        (*message).to_owned()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "native Rust panic".to_owned()
    }
}

unsafe fn set_error(error: *mut *mut c_char, message: String) {
    if error.is_null() {
        return;
    }
    let message = message.replace('\0', "\\0");
    *error = CString::new(message).unwrap().into_raw();
}

unsafe fn boundary<F>(error: *mut *mut c_char, call: F) -> Sexp
where
    F: FnOnce() -> Result<Sexp, String>,
{
    if !error.is_null() {
        *error = ptr::null_mut();
    }
    match catch_unwind(AssertUnwindSafe(call)) {
        Ok(Ok(value)) => value,
        Ok(Err(message)) => {
            set_error(error, message);
            ptr::null_mut()
        }
        Err(payload) => {
            set_error(
                error,
                format!("native Rust panic: {}", panic_message(payload)),
            );
            ptr::null_mut()
        }
    }
}

unsafe fn text_encoding(encoding: *const c_char) -> Result<TextEncoding, String> {
    if encoding.is_null() {
        return Ok(TextEncoding::Auto);
    }
    let label = CStr::from_ptr(encoding)
        .to_str()
        .map_err(|_| "encoding name is not valid UTF-8".to_owned())?;
    TextEncoding::from_label(label).map_err(|error| error.to_string())
}

#[no_mangle]
/// Return DTA metadata as an R character vector.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C byte string for the
/// duration of this call. `encoding` may be null; otherwise it must likewise
/// point to a readable NUL-terminated C byte string for the duration of this
/// call. Neither string's bytes need to be valid UTF-8; invalid UTF-8 is
/// returned as an ordinary error. If non-null, `error` must point to writable
/// storage for one C string pointer. The caller must run on R's main thread
/// with an initialized R runtime.
pub unsafe extern "C" fn dtaparser_metadata_rust(
    path: *const c_char,
    column_start: u32,
    column_count: u32,
    encoding: *const c_char,
    error: *mut *mut c_char,
) -> Sexp {
    boundary(error, || {
        if path.is_null() {
            return Err("file path is null".to_owned());
        }
        let path = CStr::from_ptr(path)
            .to_str()
            .map_err(|_| "file path is not valid UTF-8".to_owned())?;
        metadata_impl(path, text_encoding(encoding)?, column_start, column_count)
    })
}

#[no_mangle]
/// Decode selected observations into an R data frame.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C byte string for the
/// duration of this call. `encoding` may be null; otherwise it must likewise
/// point to a readable NUL-terminated C byte string for the duration of this
/// call. Neither string's bytes need to be valid UTF-8; invalid UTF-8 is
/// returned as an ordinary error. Unless `all_columns` is nonzero, `columns`
/// must address `column_count` readable integers. If non-null, `error` must
/// point to writable storage for one C string pointer. The caller must run on
/// R's main thread with an initialized R runtime.
pub unsafe extern "C" fn dtaparser_read_rust(
    path: *const c_char,
    columns: *const c_int,
    column_count: usize,
    all_columns: c_int,
    skip: f64,
    n_max: f64,
    direct_to_r: c_int,
    requested_threads: c_int,
    numeric_altrep: c_int,
    encoding: *const c_char,
    error: *mut *mut c_char,
) -> Sexp {
    boundary(error, || {
        if path.is_null() {
            return Err("file path is null".to_owned());
        }
        let path = CStr::from_ptr(path)
            .to_str()
            .map_err(|_| "file path is not valid UTF-8".to_owned())?;
        let requested_threads = usize::try_from(requested_threads)
            .map_err(|_| "thread count must be non-negative".to_owned())?;
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
        read_impl(
            path,
            projection,
            skip,
            n_max,
            RReadConfig {
                direct_to_r: direct_to_r != 0,
                numeric_altrep: numeric_altrep != 0,
                encoding: text_encoding(encoding)?,
                requested_threads,
            },
        )
    })
}

#[repr(C)]
pub struct RWriteColumnDescriptor {
    name: *const c_char,
    dta_type: c_int,
    format: *const c_char,
    label: *const c_char,
    numeric_values: *const c_void,
    string_values: Sexp,
    label_values: *const c_void,
    label_texts: Sexp,
    label_count: usize,
    has_value_labels: c_int,
    numeric_shift: f64,
    numeric_scale: f64,
}

struct RWriteSource<'a> {
    descriptor: &'a RWriteColumnDescriptor,
    row_count: u64,
}

fn missing_from_code(code: c_int) -> Result<Option<MissingTag>, String> {
    match code {
        -1 => Ok(None),
        0 => Ok(Some(MissingTag::System)),
        value if (c_int::from(b'a')..=c_int::from(b'z')).contains(&value) => {
            Ok(MissingTag::from_offset(
                u8::try_from(value - c_int::from(b'a') + 1)
                    .map_err(|_| "invalid extended missing code".to_owned())?,
            ))
        }
        _ => Err("R NaN or an invalid tagged missing reached the native writer".into()),
    }
}

unsafe fn r_numeric_at(reader: *const c_void, index: usize) -> Result<(f64, c_int), String> {
    let mut value = 0.0;
    let mut missing_code = -1;
    if dtaparser_write_numeric_at(reader, index, &mut value, &mut missing_code) == 0 {
        return Err("R numeric source could not supply a value".into());
    }
    Ok((value, missing_code))
}

unsafe fn r_string_bytes(values: Sexp, index: usize) -> Result<(*const u8, usize), String> {
    let mut value = ptr::null();
    let mut length = 0_usize;
    let mut missing = 0;
    if dtaparser_write_string_at(values, index, &mut value, &mut length, &mut missing) == 0 {
        return Err("R character source could not supply a value".into());
    }
    if missing != 0 {
        return Ok((ptr::null(), 0));
    }
    if value.is_null() && length != 0 {
        return Err("R character source returned a null byte pointer".into());
    }
    Ok((value.cast::<u8>(), length))
}

unsafe fn r_string_at(values: Sexp, index: usize) -> Result<String, String> {
    let (value, length) = r_string_bytes(values, index)?;
    let bytes = if length == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(value, length)
    };
    String::from_utf8(bytes.to_vec()).map_err(|_| "R character value is not valid UTF-8".to_owned())
}

impl DtaWriteColumnSource for RWriteSource<'_> {
    fn len(&self) -> u64 {
        self.row_count
    }

    fn numeric_value(&self, row: u64) -> Result<DtaWriteNumericValue, String> {
        if row % INTERRUPT_STRIDE as u64 == 0 && unsafe { dtaparser_check_interrupt() } != 0 {
            return Err("write interrupted".into());
        }
        let index = usize::try_from(row).map_err(|_| "R row index is too large".to_owned())?;
        let (value, missing_code) = unsafe { r_numeric_at(self.descriptor.numeric_values, index) }?;
        Ok(match missing_from_code(missing_code)? {
            Some(tag) => DtaWriteNumericValue::Missing(tag),
            None => DtaWriteNumericValue::Value(
                (value + self.descriptor.numeric_shift) * self.descriptor.numeric_scale,
            ),
        })
    }

    fn string_value(&self, row: u64) -> Result<Cow<'_, str>, String> {
        if row % INTERRUPT_STRIDE as u64 == 0 && unsafe { dtaparser_check_interrupt() } != 0 {
            return Err("write interrupted".into());
        }
        let index = usize::try_from(row).map_err(|_| "R row index is too large".to_owned())?;
        let (value, length) = unsafe { r_string_bytes(self.descriptor.string_values, index) }?;
        let bytes = if length == 0 {
            &[]
        } else {
            // The protected R character vector owns immutable CHARSXPs for the
            // complete native call, so their byte storage outlives this borrow.
            unsafe { std::slice::from_raw_parts(value, length) }
        };
        std::str::from_utf8(bytes)
            .map(Cow::Borrowed)
            .map_err(|_| "R character value is not valid UTF-8".to_owned())
    }
}

unsafe fn required_c_string(value: *const c_char, description: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{description} is null"));
    }
    CStr::from_ptr(value)
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{description} is not valid UTF-8"))
}

unsafe fn write_impl(
    path: *const c_char,
    dataset_label: *const c_char,
    notes: *const *const c_char,
    note_count: usize,
    descriptors: *const RWriteColumnDescriptor,
    column_count: usize,
    row_count: usize,
    stata_version: c_int,
    timestamp: *const c_char,
) -> Result<(), String> {
    let path = required_c_string(path, "output path")?;
    let dataset_label = required_c_string(dataset_label, "dataset label")?;
    if notes.is_null() && note_count != 0 {
        return Err("dataset note pointer is null".into());
    }
    if descriptors.is_null() && column_count != 0 {
        return Err("write column pointer is null".into());
    }
    let note_pointers = if note_count == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(notes, note_count)
    };
    let notes = note_pointers
        .iter()
        .map(|note| required_c_string(*note, "dataset note"))
        .collect::<Result<Vec<_>, _>>()?;
    let descriptors = if column_count == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(descriptors, column_count)
    };
    let row_count = u64::try_from(row_count).map_err(|_| "row count is too large".to_owned())?;
    let sources = descriptors
        .iter()
        .map(|descriptor| RWriteSource {
            descriptor,
            row_count,
        })
        .collect::<Vec<_>>();
    let mut columns = Vec::with_capacity(column_count);
    for (descriptor, source) in descriptors.iter().zip(&sources) {
        if !descriptor.numeric_shift.is_finite() || !descriptor.numeric_scale.is_finite() {
            return Err("numeric write transform must be finite".into());
        }
        let dta_type = match descriptor.dta_type {
            0 => DtaType::Byte,
            1 => DtaType::Int,
            2 => DtaType::Long,
            3 => DtaType::Float,
            4 => DtaType::Double,
            width if (5..=2_049).contains(&width) => DtaType::FixedString(
                u16::try_from(width - 4).map_err(|_| "invalid fixed-string width".to_owned())?,
            ),
            2_050 => DtaType::StrL,
            _ => return Err("invalid native DTA storage type".into()),
        };
        let mut value_labels = Vec::with_capacity(descriptor.label_count);
        for index in 0..descriptor.label_count {
            let (value, missing_code) = r_numeric_at(descriptor.label_values, index)?;
            let value = match missing_from_code(missing_code)? {
                Some(tag) => DtaWriteLabelValue::Missing(tag),
                None if value.is_finite()
                    && value.fract() == 0.0
                    && value >= f64::from(i32::MIN)
                    && value <= f64::from(i32::MAX) =>
                {
                    DtaWriteLabelValue::Integer(value as i32)
                }
                None => return Err("value-label key is not a representable integer".into()),
            };
            value_labels.push(DtaWriteValueLabel {
                value,
                label: r_string_at(descriptor.label_texts, index)?,
            });
        }
        columns.push(DtaWriteColumn {
            name: required_c_string(descriptor.name, "variable name")?,
            dta_type,
            format: required_c_string(descriptor.format, "display format")?,
            label: required_c_string(descriptor.label, "variable label")?,
            has_value_labels: descriptor.has_value_labels != 0,
            value_labels,
            values: DtaWriteColumnValues::Source(source),
        });
    }
    let options = DtaWriteOptions {
        stata_version: match stata_version {
            18 => StataVersion::V18,
            19 => StataVersion::V19,
            _ => return Err("`version` must be 18 or 19".into()),
        },
        timestamp: Some(required_c_string(timestamp, "timestamp")?),
    };
    let data = DtaWriteData {
        dataset_label,
        notes,
        row_count,
        columns,
    };
    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|error| format!("could not create temporary DTA output: {error}"))?;
    let mut writer = BufWriter::new(file);
    write_dta_to(&mut writer, &data, &options).map_err(|error| error.to_string())?;
    writer
        .flush()
        .map_err(|error| format!("could not flush DTA output: {error}"))?;
    let file = writer
        .into_inner()
        .map_err(|error| format!("could not close DTA output: {error}"))?;
    file.sync_all()
        .map_err(|error| format!("could not synchronize DTA output: {error}"))?;
    Ok(())
}

#[no_mangle]
/// Stream a prevalidated R data frame to a new temporary DTA file.
///
/// # Safety
///
/// All pointers must remain valid for the call. The caller must run on R's
/// main thread because column sources call back into the R runtime.
pub unsafe extern "C" fn dtaparser_write_rust(
    path: *const c_char,
    dataset_label: *const c_char,
    notes: *const *const c_char,
    note_count: usize,
    descriptors: *const RWriteColumnDescriptor,
    column_count: usize,
    row_count: usize,
    stata_version: c_int,
    timestamp: *const c_char,
    error: *mut *mut c_char,
) -> c_int {
    if !error.is_null() {
        *error = ptr::null_mut();
    }
    match catch_unwind(AssertUnwindSafe(|| {
        write_impl(
            path,
            dataset_label,
            notes,
            note_count,
            descriptors,
            column_count,
            row_count,
            stata_version,
            timestamp,
        )
    })) {
        Ok(Ok(())) => 1,
        Ok(Err(message)) => {
            set_error(error, message);
            0
        }
        Err(payload) => {
            set_error(
                error,
                format!("native Rust panic: {}", panic_message(payload)),
            );
            0
        }
    }
}

#[no_mangle]
/// Free an error string allocated by this library.
///
/// # Safety
///
/// `error` must be null or a live pointer returned through an `error` output by
/// this library, and it must not have been freed previously.
pub unsafe extern "C" fn dtaparser_free_error(error: *mut c_char) {
    if !error.is_null() {
        drop(CString::from_raw(error));
    }
}

#[cfg(test)]
mod tests {
    use super::{
        selected_row_count, temporal_kind, validate_r_row_count, TemporalKind,
        R_DATA_FRAME_MAX_ROWS,
    };

    #[test]
    fn temporal_formats_match_haven_prefix_rules() {
        for format in ["%td", "%tdDD/NN/CCYY", "%d", "%dCY-N-D", "%dollars"] {
            assert!(
                matches!(temporal_kind(format), TemporalKind::Date),
                "{format} should be a daily date"
            );
        }
        for format in ["%tc", "%tcDDmonCCYY_HH:MM:SS", "%tC", "%tCCustom"] {
            assert!(
                matches!(temporal_kind(format), TemporalKind::Datetime),
                "{format} should be a datetime"
            );
        }
        for format in [
            "%D", "%9d", "%tw", "%tm", "%tq", "%th", "%ty", "%t", "d", "",
        ] {
            assert!(
                matches!(temporal_kind(format), TemporalKind::None),
                "{format} should remain numeric"
            );
        }
    }

    #[test]
    fn selected_row_windows_are_clamped_before_decode() {
        assert_eq!(selected_row_count(10, 3, Some(4)), 4);
        assert_eq!(selected_row_count(10, 9, Some(8)), 1);
        assert_eq!(selected_row_count(10, 12, None), 0);
    }

    #[test]
    fn oversized_r_data_frames_are_rejected_before_decode() {
        let error = validate_r_row_count(R_DATA_FRAME_MAX_ROWS + 1, 0, None)
            .expect_err("the R data-frame cap must be enforced");
        assert!(error.contains("cannot contain more than"));
        assert_eq!(
            validate_r_row_count(R_DATA_FRAME_MAX_ROWS + 1, 1, None).unwrap(),
            R_DATA_FRAME_MAX_ROWS
        );
    }
}
