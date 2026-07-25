use std::any::Any;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

use dta_parser::{
    ColumnValues, DtaData, DtaFile, DtaType, MissingTag, ReadOptions, ValueLabelTable, VariableInfo,
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
    fn Rf_unprotect(count: c_int);
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
    fn dtaparser_make_char(
        value: *const c_char,
        length: c_int,
        encoding: c_int,
        result: *mut Sexp,
    ) -> c_int;
    fn dtaparser_install(name: *const c_char, result: *mut Sexp) -> c_int;
    fn dtaparser_set_attrib(object: Sexp, name: Sexp, value: Sexp) -> c_int;
}

struct ProtectGuard {
    count: c_int,
}

impl ProtectGuard {
    fn new() -> Self {
        Self { count: 0 }
    }

    unsafe fn alloc(&mut self, kind: c_int, length: RLen) -> Result<Sexp, String> {
        let mut value = ptr::null_mut();
        if dtaparser_alloc_vector(kind, length, &mut value) == 0 || value.is_null() {
            return Err("R could not allocate or protect a native vector".to_owned());
        }
        self.count += 1;
        Ok(value)
    }
}

impl Drop for ProtectGuard {
    fn drop(&mut self) {
        if self.count > 0 {
            unsafe { Rf_unprotect(self.count) };
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
    if index % INTERRUPT_STRIDE == 0 {
        check_interrupt()?;
    }
    Ok(())
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum TemporalKind {
    None,
    Date,
    Datetime,
}

fn temporal_kind(format: &str) -> TemporalKind {
    if format.starts_with("%td") {
        TemporalKind::Date
    } else if format.starts_with("%tc") || format.starts_with("%tC") {
        TemporalKind::Datetime
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

fn r_missing(tag: MissingTag) -> f64 {
    if tag == MissingTag::System {
        return unsafe { R_NaReal };
    }
    let letter = u64::from(b'a' + tag.offset() - 1);
    f64::from_bits(0x7ff0_0000_0000_07a2_u64 | (letter << 32))
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
        set_class(result, &["data.frame"], &mut attribute_guard)?;
    }

    if !data.metadata.dataset_label.is_empty() {
        check_interrupt()?;
        let mut attribute_guard = ProtectGuard::new();
        let label = scalar_string(&data.metadata.dataset_label, &mut attribute_guard)?;
        set_attr(result, "label", label)?;
    }
    {
        let mut attribute_guard = ProtectGuard::new();
        let version = scalar_integer(
            data.metadata.format_version.as_u16().into(),
            &mut attribute_guard,
        )?;
        set_attr(result, "dta_format_version", version)?;
    }
    Ok(result)
}

unsafe fn metadata_impl(path: &str) -> Result<Sexp, String> {
    let file = DtaFile::open(path).map_err(|error| error.to_string())?;
    let metadata = file.metadata();
    let mut guard = ProtectGuard::new();
    let names = metadata
        .variables
        .iter()
        .map(|variable| variable.name.clone())
        .collect::<Vec<_>>();
    let result = string_vector(&names, &mut guard)?;
    let storage = metadata
        .variables
        .iter()
        .map(|variable| match variable.dta_type {
            DtaType::FixedString(_) | DtaType::StrL => "character".to_owned(),
            _ => "numeric".to_owned(),
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
) -> Result<Sexp, String> {
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
    let mut file = DtaFile::open(path).map_err(|error| error.to_string())?;
    validate_r_row_count(file.metadata().nobs, row_start, row_count)?;
    let options = ReadOptions {
        row_start,
        row_count,
        column_indices: columns,
    };
    let data = file
        .read_with_interrupt(&options, || unsafe { dtaparser_check_interrupt() != 0 })
        .map_err(|error| error.to_string())?;
    build_data_frame(&data)
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

#[no_mangle]
/// Return DTA metadata as an R character vector.
///
/// # Safety
///
/// `path` must point to a valid NUL-terminated string. If non-null, `error`
/// must point to writable storage for one C string pointer. The caller must run
/// on R's main thread with an initialized R runtime.
pub unsafe extern "C" fn dtaparser_metadata_rust(
    path: *const c_char,
    error: *mut *mut c_char,
) -> Sexp {
    boundary(error, || {
        if path.is_null() {
            return Err("file path is null".to_owned());
        }
        let path = CStr::from_ptr(path)
            .to_str()
            .map_err(|_| "file path is not valid UTF-8".to_owned())?;
        metadata_impl(path)
    })
}

#[no_mangle]
/// Decode selected observations into an R data frame.
///
/// # Safety
///
/// `path` must point to a valid NUL-terminated string. Unless `all_columns` is
/// nonzero, `columns` must address `column_count` readable integers. If
/// non-null, `error` must point to writable storage for one C string pointer.
/// The caller must run on R's main thread with an initialized R runtime.
pub unsafe extern "C" fn dtaparser_read_rust(
    path: *const c_char,
    columns: *const c_int,
    column_count: usize,
    all_columns: c_int,
    skip: f64,
    n_max: f64,
    error: *mut *mut c_char,
) -> Sexp {
    boundary(error, || {
        if path.is_null() {
            return Err("file path is null".to_owned());
        }
        let path = CStr::from_ptr(path)
            .to_str()
            .map_err(|_| "file path is not valid UTF-8".to_owned())?;
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
        read_impl(path, projection, skip, n_max)
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
    use super::{selected_row_count, validate_r_row_count, R_DATA_FRAME_MAX_ROWS};

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
