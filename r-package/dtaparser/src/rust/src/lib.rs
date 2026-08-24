use std::any::Any;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

use ahash::AHashMap;
use dta_parser::{
    ColumnValues, DtaColumnSink, DtaData, DtaError, DtaFile, DtaMetadata, DtaSink, DtaType,
    MissingTag, ParallelDtaSink, ReadOptions, TextEncoding, ValueLabelTable, VariableInfo,
};

type Sexp = *mut c_void;
type RLen = isize;

const INTSXP: c_int = 13;
const REALSXP: c_int = 14;
const STRSXP: c_int = 16;
const VECSXP: c_int = 19;
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
    fn dtaparser_install(name: *const c_char, result: *mut Sexp) -> c_int;
    fn dtaparser_set_attrib(object: Sexp, name: Sexp, value: Sexp) -> c_int;
}

#[repr(C)]
struct DictStringData {
    value_ids: *mut u32,
    length: usize,
    _values: AHashMap<String, u32>,
    value_views: Vec<(*const u8, usize)>,
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
            _values: values,
            value_views,
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
        let ok = dtaparser_make_dictstring(
            storage,
            value_count,
            &mut transferred,
            &mut result,
        );
        if ok == 0 || result.is_null() {
            if transferred == 0 {
                dtaparser_dictstring_free(storage);
            }
            return Err("R could not allocate a dictionary string vector".to_owned());
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
enum TemporalKind {
    None,
    Date,
    Datetime,
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

    match temporal_kind(&variable.format) {
        TemporalKind::Date => set_class(vector, &["Date"], guard)?,
        TemporalKind::Datetime => {
            set_class(vector, &["POSIXct", "POSIXt"], guard)?;
            let timezone = scalar_string("UTC", guard)?;
            set_attr(vector, "tzone", timezone)?;
        }
        TemporalKind::None if table.is_some() => {
            set_class(vector, &["haven_labelled", "vctrs_vctr", "double"], guard)?;
        }
        TemporalKind::None => {}
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
    Numeric {
        vector: Sexp,
        output: *mut f64,
        temporal: TemporalKind,
        system_missing: f64,
    },
    String {
        vector: Sexp,
        data: RStringData,
    },
}

// Parallel workers receive disjoint columns. Numeric workers only write to
// non-overlapping memory obtained before the threads start; string workers
// mutate Rust-owned dictionaries. They never invoke the R API.
unsafe impl Send for RColumn {}

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
    ) -> Result<Self, DtaError> {
        let length = RLen::try_from(row_count)
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
                _ => {
                    let vector = guard.alloc(REALSXP, length).map_err(DtaError::Output)?;
                    RColumn::Numeric {
                        vector,
                        output: REAL(vector),
                        temporal: temporal_kind(&variable.format),
                        system_missing: R_NaReal,
                    }
                }
            };
            let vector = match &column {
                RColumn::Numeric { vector, .. } | RColumn::String { vector, .. } => *vector,
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
    fn numeric_column(
        &self,
        column: usize,
    ) -> Result<(*mut f64, TemporalKind, f64), DtaError> {
        match self.columns.get(column) {
            Some(RColumn::Numeric {
                output,
                temporal,
                system_missing,
                ..
            }) => Ok((*output, *temporal, *system_missing)),
            _ => Err(DtaError::Output(
                "numeric output column mismatch".to_owned(),
            )),
        }
    }

    #[inline(always)]
    fn write_numeric(
        &mut self,
        column: usize,
        row: usize,
        value: f64,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        let (output, temporal, system_missing) = self.numeric_column(column)?;
        unsafe {
            *output.add(row) = missing
                .map(|tag| r_missing_with_system(tag, system_missing))
                .unwrap_or_else(|| observed_value(value, temporal));
        }
        Ok(())
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

impl RColumn {
    #[inline(always)]
    fn write_numeric_value(
        &mut self,
        row: usize,
        value: f64,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        let Self::Numeric {
            output,
            temporal,
            system_missing,
            ..
        } = self
        else {
            return Err(DtaError::Output(
                "numeric output column mismatch".to_owned(),
            ));
        };
        unsafe {
            *output.add(row) = missing
                .map(|tag| r_missing_with_system(tag, *system_missing))
                .unwrap_or_else(|| observed_value(value, *temporal));
        }
        Ok(())
    }
}

impl DtaColumnSink for RColumn {
    fn push_byte(
        &mut self,
        row: usize,
        value: i8,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_numeric_value(row, f64::from(value), missing)
    }

    fn push_int(
        &mut self,
        row: usize,
        value: i16,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_numeric_value(row, f64::from(value), missing)
    }

    fn push_long(
        &mut self,
        row: usize,
        value: i32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_numeric_value(row, f64::from(value), missing)
    }

    fn push_float(
        &mut self,
        row: usize,
        value: f32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_numeric_value(row, f64::from(value), missing)
    }

    fn push_double(
        &mut self,
        row: usize,
        value: f64,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_numeric_value(row, value, missing)
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
        self.write_numeric(column, row, f64::from(value), missing)
    }

    #[inline(always)]
    fn push_int(
        &mut self,
        column: usize,
        row: usize,
        value: i16,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_numeric(column, row, f64::from(value), missing)
    }

    #[inline(always)]
    fn push_long(
        &mut self,
        column: usize,
        row: usize,
        value: i32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_numeric(column, row, f64::from(value), missing)
    }

    #[inline(always)]
    fn push_float(
        &mut self,
        column: usize,
        row: usize,
        value: f32,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_numeric(column, row, f64::from(value), missing)
    }

    #[inline(always)]
    fn push_double(
        &mut self,
        column: usize,
        row: usize,
        value: f64,
        missing: Option<MissingTag>,
    ) -> Result<(), DtaError> {
        self.write_numeric(column, row, value, missing)
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
                let RColumn::String { vector, data } = column else {
                    continue;
                };
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
                    RColumn::Numeric { vector, .. } | RColumn::String { vector, .. } => *vector,
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

unsafe fn read_impl(
    path: &str,
    columns: Option<Vec<u32>>,
    skip: f64,
    n_max: f64,
    direct_to_r: bool,
    encoding: TextEncoding,
    requested_threads: usize,
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
        DtaFile::open_with_encoding(path, encoding).map_err(|error| error.to_string())?;
    validate_r_row_count(file.metadata().nobs, row_start, row_count)?;
    let options = ReadOptions {
        row_start,
        row_count,
        column_indices: columns,
    };
    if direct_to_r {
        let threads = file
            .parallel_thread_count(&options, requested_threads)
            .map_err(|error| error.to_string())?;
        let columnar = file
            .supports_columnar_sink(&options)
            .map_err(|error| error.to_string())?;
        if threads > 1 || columnar {
            file.read_with_parallel_sink_and_interrupt(
                &options,
                threads,
                |metadata, _row_start, row_count, indices| unsafe {
                    RDataFrameSink::new(metadata, row_count, indices)
                },
                coarse_interrupt,
            )
            .map_err(|error| error.to_string())
        } else {
            file.read_with_sink_and_interrupts(
                &options,
                |metadata, _row_start, row_count, indices| unsafe {
                    RDataFrameSink::new(metadata, row_count, indices)
                },
                coarse_interrupt,
                frequent_interrupt_poller(),
            )
            .map_err(|error| error.to_string())
        }
    } else {
        let data = file
            .read_with_interrupts(
                &options,
                coarse_interrupt,
                frequent_interrupt_poller(),
            )
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
            direct_to_r != 0,
            text_encoding(encoding)?,
            requested_threads,
        )
    })
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
