use std::any::Any;
use std::borrow::Cow;
use std::cell::{Cell, RefCell};
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::fs::{self, OpenOptions};
use std::io::{BufWriter, ErrorKind};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;

use ahash::AHashMap;
use dta_tools::{
    classify_byte_missing_for_version, classify_float_missing_bits_for_version,
    classify_int_missing_for_version, classify_long_missing_for_version,
    dta_write_numeric_value_is_representable, encode_numeric, valid_canonical_characteristic,
    valid_canonical_note, valid_characteristic, valid_note,
    write_prevalidated_dta_with_value_label_registry_to, ColumnValues, DtaColumnSink, DtaData,
    DtaError, DtaFile, DtaMetadata, DtaSink, DtaType, DtaWriteCharacteristic, DtaWriteColumn,
    DtaWriteColumnSource, DtaWriteColumnValues, DtaWriteData, DtaWriteError, DtaWriteLabelValue,
    DtaWriteNote, DtaWriteNumericValue, DtaWriteObservationSource, DtaWriteOptions,
    DtaWriteRawNumericValue, DtaWriteValueLabel, DtaWriteValueLabelRegistry,
    DtaWriteValueLabelTable, FormatVersion, MissingTag, ParallelDtaSink, ReadOptions,
    StataCharacteristic, StataNote, TextEncoding, ValueLabelEntry, ValueLabelTable,
    ValueLabelTableView, VariableInfo,
};

mod arrow_ffi;

type Sexp = *mut c_void;
type RLen = isize;

const INTSXP: c_int = 13;
const LGLSXP: c_int = 10;
const REALSXP: c_int = 14;
const STRSXP: c_int = 16;
const VECSXP: c_int = 19;
const RAWSXP: c_int = 24;
const CE_UTF8: c_int = 1;
const INTERRUPT_STRIDE: usize = 16_384;
const WRITE_CALLBACK_REGION_BYTES: usize = 8 * 1024 * 1024;
const DIRECT_OBSERVATION_BYTES_PER_WORKER: usize = 512 * 1024;
const R_DATA_FRAME_MAX_ROWS: u64 = c_int::MAX as u64;
const SECONDS_1960_TO_1970: f64 = 315_619_200.0;
const DAYS_1960_TO_1970: f64 = 3_653.0;

extern "C" {
    fn SET_STRING_ELT(vector: Sexp, index: RLen, value: Sexp);
    fn SET_VECTOR_ELT(vector: Sexp, index: RLen, value: Sexp) -> Sexp;
    fn INTEGER(vector: Sexp) -> *mut c_int;
    fn LOGICAL(vector: Sexp) -> *mut c_int;
    fn REAL(vector: Sexp) -> *mut f64;
    fn RAW(vector: Sexp) -> *mut u8;

    static mut R_NaString: Sexp;
    static mut R_NamesSymbol: Sexp;
    static mut R_ClassSymbol: Sexp;
    static mut R_RowNamesSymbol: Sexp;
    static mut R_NaReal: f64;
    static mut R_NaInt: c_int;

    fn dtatools_check_interrupt() -> c_int;
    fn dtatools_alloc_vector(kind: c_int, length: RLen, result: *mut Sexp) -> c_int;
    fn dtatools_release_object(object: Sexp);
    fn dtatools_make_char(
        value: *const c_char,
        length: c_int,
        encoding: c_int,
        result: *mut Sexp,
    ) -> c_int;
    fn dtatools_make_dictstring(
        data: *mut c_void,
        value_count: usize,
        transferred: *mut c_int,
        result: *mut Sexp,
    ) -> c_int;
    fn dtatools_make_numeric(
        data: *mut c_void,
        backing: Sexp,
        transferred: *mut c_int,
        result: *mut Sexp,
    ) -> c_int;
    fn dtatools_install(name: *const c_char, result: *mut Sexp) -> c_int;
    fn dtatools_set_attrib(object: Sexp, name: Sexp, value: Sexp) -> c_int;
    fn dtatools_xlength(value: Sexp) -> usize;
    fn dtatools_is_null(value: Sexp) -> c_int;
    fn dtatools_string_elt_utf8(values: Sexp, index: usize) -> *const c_char;
    fn dtatools_write_numeric_region(
        reader: *const c_void,
        start: usize,
        length: usize,
        values: *mut f64,
        missing_codes: *mut c_int,
        error_message: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
    fn dtatools_write_string_region(
        values: Sexp,
        start: usize,
        length: usize,
        ids: *mut u64,
        strings: *mut *const c_char,
        string_lengths: *mut usize,
        error_message: *mut c_char,
        error_capacity: usize,
    ) -> c_int;
}

const STATA_METADATA_MARKER: &str = "\u{1e}dtatools:stata-metadata:1";

fn parse_metadata_count(value: &str, context: &str) -> Result<usize, String> {
    value
        .parse::<usize>()
        .map_err(|_| format!("invalid internal {context} count"))
}

unsafe fn parse_stata_metadata_sexp_as<'a, N, C>(
    values: Sexp,
    note: impl Fn(u32, &'a str) -> N,
    characteristic: impl Fn(&'a str, &'a str) -> C,
    valid_note: impl Fn(u32, &str) -> bool,
    valid_characteristic: impl Fn(&str, &str) -> bool,
) -> Result<(Vec<N>, Vec<C>), String> {
    if dtatools_is_null(values) != 0 {
        return Ok((Vec::new(), Vec::new()));
    }
    let field_count = dtatools_xlength(values);
    let field = |index| {
        required_c_str(
            dtatools_string_elt_utf8(values, index),
            "internal Stata metadata field",
        )
    };
    if field_count < 2 {
        return Err("truncated internal Stata metadata envelope".to_owned());
    }
    if field(0)? != STATA_METADATA_MARKER {
        return Err("invalid internal Stata metadata marker".to_owned());
    }
    let note_count = parse_metadata_count(field(1)?, "note")?;
    if note_count > 9_999 {
        return Err("internal Stata note count exceeds 9,999".to_owned());
    }
    let mut cursor = note_count
        .checked_mul(2)
        .and_then(|count| 2_usize.checked_add(count))
        .filter(|offset| *offset < field_count)
        .ok_or_else(|| "truncated internal Stata note metadata".to_owned())?;
    let characteristic_count = parse_metadata_count(field(cursor)?, "characteristic")?;
    cursor = cursor
        .checked_add(1)
        .ok_or_else(|| "internal Stata metadata layout overflows".to_owned())?;
    let expected_end = characteristic_count
        .checked_mul(2)
        .and_then(|count| cursor.checked_add(count))
        .ok_or_else(|| "internal Stata characteristic count is too large".to_owned())?;
    if expected_end != field_count {
        return Err("internal Stata metadata counts do not match its fields".to_owned());
    }

    let mut cursor = 2;
    let mut notes = Vec::new();
    notes
        .try_reserve_exact(note_count)
        .map_err(|_| "could not allocate note metadata".to_owned())?;
    for _ in 0..note_count {
        let number = field(cursor)?
            .parse::<u32>()
            .map_err(|_| "invalid internal note number".to_owned())?;
        let text = field(cursor + 1)?;
        if !valid_note(number, text) {
            return Err("invalid internal Stata note metadata".to_owned());
        }
        notes.push(note(number, text));
        cursor += 2;
    }
    cursor += 1;
    let mut characteristics = Vec::new();
    characteristics
        .try_reserve_exact(characteristic_count)
        .map_err(|_| "could not allocate characteristic metadata".to_owned())?;
    for _ in 0..characteristic_count {
        let name = field(cursor)?;
        let value = field(cursor + 1)?;
        if !valid_characteristic(name, value) {
            return Err("invalid internal Stata characteristic metadata".to_owned());
        }
        characteristics.push(characteristic(name, value));
        cursor += 2;
    }
    Ok((notes, characteristics))
}

pub(crate) unsafe fn parse_stata_metadata_sexp(
    values: Sexp,
) -> Result<(Vec<StataNote>, Vec<StataCharacteristic>), String> {
    parse_stata_metadata_sexp_as(
        values,
        |number, text| StataNote {
            number,
            text: text.to_owned(),
        },
        |name, value| StataCharacteristic {
            name: name.to_owned(),
            value: value.to_owned(),
        },
        valid_canonical_note,
        valid_canonical_characteristic,
    )
}

unsafe fn parse_stata_metadata_sexp_borrowed<'a>(
    values: Sexp,
) -> Result<(Vec<DtaWriteNote<'a>>, Vec<DtaWriteCharacteristic<'a>>), String> {
    parse_stata_metadata_sexp_as(
        values,
        |number, text| DtaWriteNote::numbered(number, Cow::Borrowed(text)),
        |name, value| DtaWriteCharacteristic {
            name: Cow::Borrowed(name),
            value: Cow::Borrowed(value),
        },
        valid_note,
        valid_characteristic,
    )
}

#[repr(C)]
struct NumericData {
    values: *mut c_void,
    length: usize,
    kind: c_int,
    temporal: c_int,
    format_version: c_int,
    missing_count: usize,
}

impl NumericData {
    fn new(data: RNumericData) -> Self {
        Self {
            values: data.values.cast::<c_void>(),
            length: data.length,
            kind: data.kind as c_int,
            temporal: data.temporal as c_int,
            format_version: c_int::from(data.format_version.as_u16()),
            missing_count: data.missing_count,
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

impl TryFrom<c_int> for NumericKind {
    type Error = String;

    fn try_from(value: c_int) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Self::Byte),
            1 => Ok(Self::Int),
            2 => Ok(Self::Long),
            3 => Ok(Self::Float),
            _ => Err("invalid R numeric kind".into()),
        }
    }
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
    missing_count: usize,
}

#[no_mangle]
/// Release numeric storage previously transferred to an R ALTREP vector.
///
/// # Safety
///
/// `data` must be null or a live pointer created by `ProtectGuard::numeric`,
/// and it must not have been freed previously.
pub unsafe extern "C" fn dtatools_numeric_free(data: *mut c_void) {
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
pub unsafe extern "C" fn dtatools_numeric_alloc(
    values: *mut c_void,
    length: usize,
    kind: c_int,
    temporal: c_int,
    missing_count: usize,
) -> *mut c_void {
    let Ok(kind) = NumericKind::try_from(kind) else {
        return ptr::null_mut();
    };
    let Ok(temporal) = TemporalKind::try_from(temporal) else {
        return ptr::null_mut();
    };
    Box::into_raw(Box::new(NumericData {
        values,
        length,
        kind: kind as c_int,
        temporal: temporal as c_int,
        format_version: 119,
        missing_count,
    }))
    .cast::<c_void>()
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NumericGatherColumn {
    x_values: usize,
    y_values: usize,
    output: usize,
    width: usize,
    missing: [u8; 8],
    missing_count: usize,
    kind: c_int,
    format_version: c_int,
    source_has_missing: c_int,
}

unsafe fn gathered_numeric_is_missing(column: NumericGatherColumn, value: *const u8) -> bool {
    let kind = NumericKind::try_from(column.kind).expect("compact gather has a valid numeric kind");
    let release =
        u16::try_from(column.format_version).expect("compact gather has a valid format version");
    let version =
        FormatVersion::try_from(release).expect("compact gather has a supported format version");
    match kind {
        NumericKind::Byte => {
            classify_byte_missing_for_version(value.cast::<i8>().read_unaligned(), version)
                .is_some()
        }
        NumericKind::Int => {
            classify_int_missing_for_version(value.cast::<i16>().read_unaligned(), version)
                .is_some()
        }
        NumericKind::Long => {
            classify_long_missing_for_version(value.cast::<i32>().read_unaligned(), version)
                .is_some()
        }
        NumericKind::Float => {
            let value = value.cast::<f32>().read_unaligned();
            value.is_nan()
                || classify_float_missing_bits_for_version(value.to_bits(), version).is_some()
        }
    }
}

unsafe fn gather_numeric_column(
    column: NumericGatherColumn,
    x_rows: &[c_int],
    y_rows: Option<&[c_int]>,
) {
    let x_values = column.x_values as *const u8;
    let y_values = column.y_values as *const u8;
    let output = column.output as *mut u8;
    let mut missing_count = 0;
    for (output_index, &x_index) in x_rows.iter().enumerate() {
        let (source, source_index) = if x_index >= 0 {
            (x_values, x_index as usize)
        } else if !y_values.is_null() {
            let y_index = y_rows.expect("paired gather requires y rows")[output_index];
            if y_index >= 0 {
                (y_values, y_index as usize)
            } else {
                (ptr::null(), 0)
            }
        } else {
            (ptr::null(), 0)
        };

        let target = output.add(output_index * column.width);
        if source.is_null() {
            ptr::copy_nonoverlapping(column.missing.as_ptr(), target, column.width);
        } else {
            ptr::copy_nonoverlapping(
                source.add(source_index * column.width),
                target,
                column.width,
            );
        }
        if column.missing_count != 0
            && (source.is_null()
                || (column.source_has_missing != 0 && gathered_numeric_is_missing(column, target)))
        {
            missing_count += 1;
        }
    }
    if column.missing_count != 0 {
        (column.missing_count as *mut usize).write(missing_count);
    }
}

#[no_mangle]
/// Gather independent Stata numeric columns in parallel.
///
/// # Safety
///
/// `columns` must describe disjoint writable outputs and live compact or R
/// double source buffers. Row indices must be validated zero-based offsets or
/// negative for an absent row. All pointers must remain live until this call
/// returns.
pub unsafe extern "C" fn dtatools_gather_numeric_columns(
    columns: *const NumericGatherColumn,
    column_count: usize,
    x_rows: *const c_int,
    y_rows: *const c_int,
    row_count: usize,
) -> c_int {
    let call = || {
        if columns.is_null() || (row_count > 0 && x_rows.is_null()) {
            return false;
        }
        let columns = std::slice::from_raw_parts(columns, column_count);
        let x_rows = if row_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(x_rows, row_count)
        };
        let y_rows = if y_rows.is_null() {
            None
        } else {
            Some(std::slice::from_raw_parts(y_rows, row_count))
        };
        let workers = std::thread::available_parallelism()
            .map_or(1, usize::from)
            .min(column_count.max(1));
        let columns_per_worker = column_count.div_ceil(workers);

        std::thread::scope(|scope| {
            for chunk in columns.chunks(columns_per_worker) {
                scope.spawn(move || {
                    for &column in chunk {
                        unsafe { gather_numeric_column(column, x_rows, y_rows) };
                    }
                });
            }
        });
        true
    };

    match catch_unwind(AssertUnwindSafe(call)) {
        Ok(true) => 1,
        Ok(false) | Err(_) => 0,
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NumericCompareOperand {
    values: *const c_void,
    kind: c_int,
    temporal: c_int,
    format_version: c_int,
}

/// Storage of one comparison operand, validated once so the per-element
/// loop carries no `try_from` parsing.
#[derive(Clone, Copy)]
enum CompareStorage {
    Byte(FormatVersion),
    Int(FormatVersion),
    Long(FormatVersion),
    Float(FormatVersion),
    Double,
}

#[derive(Clone, Copy)]
struct CompareOperandView {
    values: usize,
    storage: CompareStorage,
    temporal: c_int,
}

fn compare_operand_view(operand: NumericCompareOperand) -> Option<CompareOperandView> {
    let storage = if operand.kind == 4 {
        CompareStorage::Double
    } else {
        let release = u16::try_from(operand.format_version).ok()?;
        let version = FormatVersion::try_from(release).ok()?;
        match NumericKind::try_from(operand.kind).ok()? {
            NumericKind::Byte => CompareStorage::Byte(version),
            NumericKind::Int => CompareStorage::Int(version),
            NumericKind::Long => CompareStorage::Long(version),
            NumericKind::Float => CompareStorage::Float(version),
        }
    };
    Some(CompareOperandView {
        values: operand.values as usize,
        storage,
        temporal: operand.temporal,
    })
}

/// One element decoded for Stata comparison: rank 0 is a finite value,
/// rank 1 is `.`, and ranks 2 through 27 are `.a` through `.z`, with the
/// payload zeroed whenever the element is missing so lexicographic
/// (rank, value) order reproduces Stata's total order.
#[derive(Clone, Copy)]
struct ComparedElement {
    rank: u8,
    value: f64,
}

/// Decode one element without materializing the vector. Returns `None`
/// for a NaN payload that is not a Stata missing value, so the caller can
/// fall back to the R implementation and its errors.
unsafe fn compare_operand_element(
    operand: CompareOperandView,
    index: usize,
) -> Option<ComparedElement> {
    let base = operand.values as *const u8;
    let raw = match operand.storage {
        CompareStorage::Double => {
            // Decoded doubles (materialized or eagerly constructed Stata
            // vectors): finite values are already in decoded units, system
            // missing is R's `NA_real_`, and `.a` through `.z` are
            // haven-style tagged NaNs whose tag byte sits in bits 32..40.
            let value = base.cast::<f64>().add(index).read_unaligned();
            if !value.is_nan() {
                return Some(ComparedElement { rank: 0, value });
            }
            const SIGN_BIT: u64 = 0x8000_0000_0000_0000;
            const QUIET_NAN_BIT: u64 = 0x0008_0000_0000_0000;
            const TAG_BITS: u64 = 0x0000_00ff_0000_0000;
            const IGNORED_BITS: u64 = SIGN_BIT | QUIET_NAN_BIT | TAG_BITS;
            const TAGGED_NA_LAYOUT: u64 = 0x7ff0_0000_0000_07a2;
            let bits = value.to_bits();
            if bits & !IGNORED_BITS != TAGGED_NA_LAYOUT & !IGNORED_BITS {
                return None;
            }
            return match ((bits & TAG_BITS) >> 32) as u8 {
                0 => Some(ComparedElement { rank: 1, value: 0.0 }),
                tag @ b'a'..=b'z' => Some(ComparedElement {
                    rank: tag - b'a' + 2,
                    value: 0.0,
                }),
                _ => None,
            };
        }
        CompareStorage::Byte(version) => {
            let value = base.cast::<i8>().add(index).read_unaligned();
            if let Some(tag) = classify_byte_missing_for_version(value, version) {
                return Some(ComparedElement {
                    rank: tag.offset() + 1,
                    value: 0.0,
                });
            }
            f64::from(value)
        }
        CompareStorage::Int(version) => {
            let value = base.cast::<i16>().add(index).read_unaligned();
            if let Some(tag) = classify_int_missing_for_version(value, version) {
                return Some(ComparedElement {
                    rank: tag.offset() + 1,
                    value: 0.0,
                });
            }
            f64::from(value)
        }
        CompareStorage::Long(version) => {
            let value = base.cast::<i32>().add(index).read_unaligned();
            if let Some(tag) = classify_long_missing_for_version(value, version) {
                return Some(ComparedElement {
                    rank: tag.offset() + 1,
                    value: 0.0,
                });
            }
            f64::from(value)
        }
        CompareStorage::Float(version) => {
            let value = base.cast::<f32>().add(index).read_unaligned();
            if let Some(tag) =
                classify_float_missing_bits_for_version(value.to_bits(), version)
            {
                return Some(ComparedElement {
                    rank: tag.offset() + 1,
                    value: 0.0,
                });
            }
            if value.is_nan() {
                return None;
            }
            f64::from(value)
        }
    };
    let value = match operand.temporal {
        1 => raw - DAYS_1960_TO_1970,
        2 => raw / 1000.0 - SECONDS_1960_TO_1970,
        _ => raw,
    };
    Some(ComparedElement { rank: 0, value })
}

fn compare_decoded(op: c_int, x: ComparedElement, y: ComparedElement) -> c_int {
    let result = match op {
        0 => x.rank == y.rank && x.value == y.value,
        1 => x.rank != y.rank || x.value != y.value,
        2 => x.rank < y.rank || (x.rank == y.rank && x.value < y.value),
        3 => x.rank < y.rank || (x.rank == y.rank && x.value <= y.value),
        4 => x.rank > y.rank || (x.rank == y.rank && x.value > y.value),
        _ => x.rank > y.rank || (x.rank == y.rank && x.value >= y.value),
    };
    c_int::from(result)
}

unsafe fn compare_numeric_range(
    op: c_int,
    x: CompareOperandView,
    y: Option<CompareOperandView>,
    scalar: ComparedElement,
    output: *mut c_int,
    start: usize,
    end: usize,
) -> bool {
    for index in start..end {
        let Some(left) = compare_operand_element(x, index) else {
            return false;
        };
        let right = match y {
            Some(operand) => match compare_operand_element(operand, index) {
                Some(element) => element,
                None => return false,
            },
            None => scalar,
        };
        output.add(index).write(compare_decoded(op, left, right));
    }
    true
}

const COMPARE_ROWS_PER_WORKER: usize = 262_144;

#[no_mangle]
/// Compare compact Stata numeric storage against a decoded scalar or a
/// second compact vector of the same length, in parallel and without
/// materializing either operand into R doubles. `op` is 0 `==`, 1 `!=`,
/// 2 `<`, 3 `<=`, 4 `>`, 5 `>=`. Returns 1 on success and 0 when the
/// caller must fall back to the R implementation.
///
/// # Safety
///
/// `x` (and `y` when non-null) must describe live compact numeric storage
/// of at least `length` elements that stays valid for the whole call, and
/// `output` must point to `length` writable `c_int` slots.
pub unsafe extern "C" fn dtatools_numeric_compare(
    op: c_int,
    x: *const NumericCompareOperand,
    y: *const NumericCompareOperand,
    scalar_value: f64,
    scalar_rank: c_int,
    output: *mut c_int,
    length: usize,
    threads: c_int,
) -> c_int {
    let call = || {
        if x.is_null() || (length > 0 && output.is_null()) || !(0..=5).contains(&op) {
            return false;
        }
        let Some(x) = compare_operand_view(unsafe { *x }) else {
            return false;
        };
        let y = if y.is_null() {
            None
        } else {
            match compare_operand_view(unsafe { *y }) {
                Some(view) => Some(view),
                None => return false,
            }
        };
        if y.is_none() && !(0..=27).contains(&scalar_rank) {
            return false;
        }
        let scalar = ComparedElement {
            rank: scalar_rank as u8,
            value: if scalar_rank == 0 { scalar_value } else { 0.0 },
        };
        if scalar.rank == 0 && scalar.value.is_nan() {
            return false;
        }
        let available = std::thread::available_parallelism().map_or(1, usize::from);
        let requested = if threads <= 0 {
            available
        } else {
            (threads as usize).min(available)
        };
        let workers = requested
            .min(length.div_ceil(COMPARE_ROWS_PER_WORKER))
            .max(1);
        if workers == 1 {
            return unsafe {
                compare_numeric_range(op, x, y, scalar, output, 0, length)
            };
        }
        let rows_per_worker = length.div_ceil(workers);
        let output_address = output as usize;
        let ok = std::sync::atomic::AtomicBool::new(true);
        std::thread::scope(|scope| {
            for worker in 0..workers {
                let start = worker * rows_per_worker;
                let end = length.min(start + rows_per_worker);
                if start >= end {
                    continue;
                }
                let ok = &ok;
                scope.spawn(move || {
                    let completed = unsafe {
                        compare_numeric_range(
                            op,
                            x,
                            y,
                            scalar,
                            output_address as *mut c_int,
                            start,
                            end,
                        )
                    };
                    if !completed {
                        ok.store(false, std::sync::atomic::Ordering::Relaxed);
                    }
                });
            }
        });
        ok.load(std::sync::atomic::Ordering::Relaxed)
    };

    match catch_unwind(AssertUnwindSafe(call)) {
        Ok(true) => 1,
        Ok(false) | Err(_) => 0,
    }
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
pub unsafe extern "C" fn dtatools_dictstring_bytes(
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
/// Clone a live dictionary-string payload for an independent R ALTREP vector.
///
/// # Safety
///
/// `data` must point to a live `DictStringData`. The caller owns the returned
/// pointer and must transfer it to R or release it with
/// `dtatools_dictstring_free`.
pub unsafe extern "C" fn dtatools_dictstring_clone(data: *const c_void) -> *mut c_void {
    if data.is_null() {
        return ptr::null_mut();
    }
    let source = &*data.cast::<DictStringData>();
    let mut ids = Vec::new();
    if ids.try_reserve_exact(source.length).is_err() {
        return ptr::null_mut();
    }
    ids.extend_from_slice(std::slice::from_raw_parts(source.value_ids, source.length));

    let mut values = AHashMap::new();
    if values.try_reserve(source._values.len()).is_err() {
        return ptr::null_mut();
    }
    for (value, &id) in &source._values {
        let mut copy = String::new();
        if copy.try_reserve_exact(value.len()).is_err() {
            return ptr::null_mut();
        }
        copy.push_str(value);
        values.insert(copy, id);
    }

    let mut views = Vec::new();
    if views.try_reserve_exact(values.len()).is_err() {
        return ptr::null_mut();
    }
    views.resize(values.len(), (ptr::null(), 0));
    for (value, &id) in &values {
        let Some(slot) = views.get_mut(id as usize) else {
            return ptr::null_mut();
        };
        *slot = (value.as_ptr(), value.len());
    }
    Box::into_raw(Box::new(DictStringData::new(ids, values, views))).cast::<c_void>()
}

#[no_mangle]
/// Release dictionary indices previously transferred to an R ALTREP vector.
///
/// # Safety
///
/// `data` must be null or a live pointer created by `ProtectGuard::dictstring`,
/// and it must not have been freed previously.
pub unsafe extern "C" fn dtatools_dictstring_free(data: *mut c_void) {
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
        if dtatools_alloc_vector(kind, length, &mut value) == 0 || value.is_null() {
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
        let ok = dtatools_make_dictstring(storage, value_count, &mut transferred, &mut result);
        if ok == 0 || result.is_null() {
            if transferred == 0 {
                dtatools_dictstring_free(storage);
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
        let ok = dtatools_make_numeric(storage, backing, &mut transferred, &mut result);
        if ok == 0 || result.is_null() {
            if transferred == 0 {
                dtatools_numeric_free(storage);
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
            unsafe { dtatools_release_object(object) };
        }
    }
}

fn check_interrupt() -> Result<(), String> {
    if unsafe { dtatools_check_interrupt() } == 0 {
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
    unsafe { dtatools_check_interrupt() != 0 }
}

fn frequent_interrupt_poller() -> impl FnMut() -> bool {
    let mut calls = 0_usize;
    move || {
        let poll = calls.is_multiple_of(INTERRUPT_STRIDE);
        calls = calls.wrapping_add(1);
        poll && unsafe { dtatools_check_interrupt() != 0 }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
enum TemporalKind {
    None = 0,
    Date = 1,
    Datetime = 2,
}

impl TryFrom<c_int> for TemporalKind {
    type Error = String;

    fn try_from(value: c_int) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Self::None),
            1 => Ok(Self::Date),
            2 => Ok(Self::Datetime),
            _ => Err("invalid direct R numeric temporal kind".into()),
        }
    }
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

fn write_numeric_value(value: f64, shift: f64, scale: f64) -> f64 {
    let encoded = (value + shift) * scale;
    if shift == SECONDS_1960_TO_1970 && scale == 1_000.0 {
        let rounded = encoded.round();
        if rounded.is_finite() && rounded / scale - shift == value {
            return rounded;
        }
    }
    encoded
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
    if dtatools_make_char(
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

unsafe fn string_vector_iter<'a>(
    values: impl ExactSizeIterator<Item = &'a str>,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let vector = guard.alloc(
        STRSXP,
        RLen::try_from(values.len()).map_err(|_| "R vector is too long".to_owned())?,
    )?;
    for (index, value) in values.enumerate() {
        poll_interrupt(index)?;
        SET_STRING_ELT(vector, index as RLen, r_char(value)?);
    }
    Ok(vector)
}

unsafe fn string_vector(values: &[String], guard: &mut ProtectGuard) -> Result<Sexp, String> {
    string_vector_iter(values.iter().map(String::as_str), guard)
}

unsafe fn scalar_string(value: &str, guard: &mut ProtectGuard) -> Result<Sexp, String> {
    string_vector_iter(std::iter::once(value), guard)
}

unsafe fn scalar_integer(value: c_int, guard: &mut ProtectGuard) -> Result<Sexp, String> {
    let vector = guard.alloc(INTSXP, 1)?;
    *INTEGER(vector) = value;
    Ok(vector)
}

unsafe fn attach_stata_metadata(
    object: Sexp,
    notes: &[StataNote],
    characteristics: &[StataCharacteristic],
    guard: &mut ProtectGuard,
) -> Result<(), String> {
    if !notes.is_empty() {
        let values = string_vector_iter(notes.iter().map(|note| note.text.as_str()), guard)?;
        set_attr(object, "notes", values)?;
        let consecutive = notes
            .iter()
            .enumerate()
            .all(|(index, note)| note.number == u32::try_from(index + 1).unwrap_or(u32::MAX));
        if !consecutive {
            let numbers = guard.alloc(
                INTSXP,
                RLen::try_from(notes.len()).map_err(|_| "too many notes".to_owned())?,
            )?;
            for (index, note) in notes.iter().enumerate() {
                *INTEGER(numbers).add(index) =
                    c_int::try_from(note.number).map_err(|_| "note number is too large")?;
            }
            set_attr(object, "stata.note.numbers", numbers)?;
        }
    }
    if !characteristics.is_empty() {
        let values = string_vector_iter(
            characteristics
                .iter()
                .map(|characteristic| characteristic.value.as_str()),
            guard,
        )?;
        let names = string_vector_iter(
            characteristics
                .iter()
                .map(|characteristic| characteristic.name.as_str()),
            guard,
        )?;
        set_symbol_attr(values, R_NamesSymbol, names)?;
        set_attr(object, "stata.characteristics", values)?;
    }
    Ok(())
}

unsafe fn set_attr(object: Sexp, name: &str, value: Sexp) -> Result<(), String> {
    let name = CString::new(name).map_err(|_| "invalid R attribute name".to_owned())?;
    let mut symbol = ptr::null_mut();
    if dtatools_install(name.as_ptr(), &mut symbol) == 0 || symbol.is_null() {
        return Err("R could not install an attribute name".to_owned());
    }
    set_symbol_attr(object, symbol, value)?;
    Ok(())
}

unsafe fn set_symbol_attr(object: Sexp, name: Sexp, value: Sexp) -> Result<(), String> {
    if dtatools_set_attrib(object, name, value) == 0 {
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

unsafe fn label_attribute_from_entries<L: AsRef<str>>(
    entry_count: usize,
    entries: impl IntoIterator<Item = Result<(f64, L), String>>,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let length = RLen::try_from(entry_count).map_err(|_| "label table is too long")?;
    let values = guard.alloc(REALSXP, length)?;
    let names = guard.alloc(STRSXP, length)?;
    let output = REAL(values);
    for (index, entry) in entries.into_iter().enumerate() {
        poll_interrupt(index)?;
        let (value, label) = entry?;
        *output.add(index) = value;
        SET_STRING_ELT(names, index as RLen, r_char(label.as_ref())?);
    }
    set_symbol_attr(values, R_NamesSymbol, names)?;
    Ok(values)
}

unsafe fn owned_label_attribute(
    entries: Vec<ValueLabelEntry>,
    guard: &mut ProtectGuard,
) -> Result<Sexp, String> {
    let entry_count = entries.len();
    label_attribute_from_entries(
        entry_count,
        entries.into_iter().map(|entry| {
            Ok((
                entry
                    .missing_tag
                    .map(r_missing)
                    .unwrap_or_else(|| f64::from(entry.value)),
                entry.label,
            ))
        }),
        guard,
    )
}

unsafe fn attach_variable_attributes(
    vector: Sexp,
    variable: &VariableInfo,
    value_label_name: Option<&str>,
    labels_attribute: Option<Sexp>,
    preserve_value_label_name: bool,
    guard: &mut ProtectGuard,
) -> Result<(), String> {
    attach_variable_attribute_view(
        vector,
        VariableAttributeView::from(variable),
        value_label_name,
        labels_attribute,
        preserve_value_label_name,
        guard,
    )
}

#[derive(Clone, Copy)]
struct VariableAttributeView<'a> {
    dta_type: &'a DtaType,
    format: &'a str,
    label: &'a str,
    notes: &'a [StataNote],
    characteristics: &'a [StataCharacteristic],
}

impl<'a> From<&'a VariableInfo> for VariableAttributeView<'a> {
    fn from(variable: &'a VariableInfo) -> Self {
        Self {
            dta_type: &variable.dta_type,
            format: &variable.format,
            label: &variable.label,
            notes: &variable.notes,
            characteristics: &variable.characteristics,
        }
    }
}

unsafe fn attach_variable_attribute_view(
    vector: Sexp,
    attributes: VariableAttributeView<'_>,
    value_label_name: Option<&str>,
    labels_attribute: Option<Sexp>,
    preserve_value_label_name: bool,
    guard: &mut ProtectGuard,
) -> Result<(), String> {
    check_interrupt()?;
    attach_stata_metadata(vector, attributes.notes, attributes.characteristics, guard)?;
    if !attributes.label.is_empty() {
        let value = scalar_string(attributes.label, guard)?;
        set_attr(vector, "label", value)?;
    }
    if !attributes.format.is_empty() {
        let value = scalar_string(attributes.format, guard)?;
        set_attr(vector, "format.stata", value)?;
    }
    let string_storage = match attributes.dta_type {
        DtaType::FixedString(width) => Some(format!("str{width}")),
        DtaType::StrL => Some("strL".to_owned()),
        _ => None,
    };
    if let Some(string_storage) = string_storage {
        let value = scalar_string(&string_storage, guard)?;
        set_attr(vector, "stata.string.storage", value)?;
        set_class(vector, &["stata_string", "vctrs_vctr", "character"], guard)?;
    }
    if let Some(table_name) = value_label_name {
        let labels = labels_attribute.ok_or_else(|| {
            format!(
                "missing cached labels for value-label table `{}`",
                table_name
            )
        })?;
        set_attr(vector, "labels", labels)?;
        if preserve_value_label_name {
            let name = scalar_string(table_name, guard)?;
            set_attr(vector, "value.label.name", name)?;
        }
    }

    let storage = match attributes.dta_type {
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

    match (temporal_kind(attributes.format), storage) {
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
        (TemporalKind::None, Some((_, storage_class))) if value_label_name.is_some() => {
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
        (TemporalKind::None, None) if value_label_name.is_some() => {
            set_class(vector, &["haven_labelled", "vctrs_vctr", "double"], guard)?;
        }
        (TemporalKind::None, None) => {}
    }
    Ok(())
}

fn value_label_reference_counts(
    metadata: &DtaMetadata,
    selected: impl IntoIterator<Item = usize>,
) -> AHashMap<&str, usize> {
    let mut counts = AHashMap::new();
    for index in selected {
        if let Some(variable) = metadata.variables.get(index) {
            if !variable.value_label_name.is_empty() {
                counts.entry(variable.value_label_name.as_str()).or_insert(0);
            }
        }
    }
    if counts.is_empty() {
        return counts;
    }
    for variable in &metadata.variables {
        if !variable.value_label_name.is_empty() {
            if let Some(count) = counts.get_mut(variable.value_label_name.as_str()) {
                *count += 1;
            }
        }
    }
    counts
}

pub(crate) fn should_preserve_value_label_name(
    column_name: &str,
    table_name: &str,
    reference_count: usize,
) -> bool {
    table_name != column_name || reference_count > 1
}

fn preserve_value_label_name(
    variable: &VariableInfo,
    value_label_name: Option<&str>,
    reference_counts: &AHashMap<&str, usize>,
) -> bool {
    value_label_name.is_some_and(|table_name| {
        should_preserve_value_label_name(
            &variable.name,
            table_name,
            reference_counts.get(table_name).copied().unwrap_or(0),
        )
    })
}

unsafe fn cached_owned_label_attribute(
    table_name: &str,
    tables: &mut AHashMap<String, Vec<ValueLabelEntry>>,
    cache: &mut AHashMap<String, Sexp>,
    guard: &mut ProtectGuard,
) -> Result<Option<Sexp>, String> {
    if let Some(&labels) = cache.get(table_name) {
        return Ok(Some(labels));
    }
    let Some(entries) = tables.remove(table_name) else {
        return Ok(None);
    };
    let labels = owned_label_attribute(entries, guard)?;
    cache.insert(table_name.to_owned(), labels);
    Ok(Some(labels))
}

unsafe fn cached_borrowed_label_attribute<'a>(
    table_name: &'a str,
    tables: &AHashMap<&'a str, &'a ValueLabelTable>,
    cache: &mut AHashMap<&'a str, Sexp>,
    guard: &mut ProtectGuard,
) -> Result<Option<Sexp>, String> {
    if let Some(&labels) = cache.get(table_name) {
        return Ok(Some(labels));
    }
    let Some(table) = tables.get(table_name) else {
        return Ok(None);
    };
    let labels = label_attribute_from_entries(
        table.entries.len(),
        table.entries.iter().map(|entry| {
            Ok((
                entry
                    .missing_tag
                    .map(r_missing)
                    .unwrap_or_else(|| f64::from(entry.value)),
                entry.label.as_str(),
            ))
        }),
        guard,
    )?;
    cache.insert(table_name, labels);
    Ok(Some(labels))
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
    value_label_reference_counts: &AHashMap<&str, usize>,
    value_label_tables: &mut AHashMap<String, Vec<ValueLabelEntry>>,
    value_label_attributes: &mut AHashMap<String, Sexp>,
    guard: &mut ProtectGuard,
    cache_guard: &mut ProtectGuard,
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
    let table_name = (!variable.value_label_name.is_empty()
        && (value_label_attributes.contains_key(&variable.value_label_name)
            || value_label_tables.contains_key(&variable.value_label_name)))
    .then_some(variable.value_label_name.as_str());
    let labels_attribute = table_name
        .map(|table_name| {
            cached_owned_label_attribute(
                table_name,
                value_label_tables,
                value_label_attributes,
                cache_guard,
            )
        })
        .transpose()?
        .flatten();
    attach_variable_attributes(
        vector,
        variable,
        table_name,
        labels_attribute,
        preserve_value_label_name(variable, table_name, value_label_reference_counts),
        guard,
    )?;
    Ok(vector)
}

unsafe fn attach_dataset_attributes(result: Sexp, metadata: &DtaMetadata) -> Result<(), String> {
    if !metadata.dataset_label.is_empty() {
        check_interrupt()?;
        let mut guard = ProtectGuard::new();
        let label = scalar_string(&metadata.dataset_label, &mut guard)?;
        set_attr(result, "label", label)?;
    }
    check_interrupt()?;
    let mut guard = ProtectGuard::new();
    attach_stata_metadata(
        result,
        &metadata.notes,
        &metadata.characteristics,
        &mut guard,
    )?;
    Ok(())
}

unsafe fn build_data_frame(mut data: DtaData) -> Result<Sexp, String> {
    let mut result_guard = ProtectGuard::new();
    let column_count = RLen::try_from(data.columns.len()).map_err(|_| "too many columns")?;
    let result = result_guard.alloc(VECSXP, column_count)?;
    let names = result_guard.alloc(STRSXP, column_count)?;

    let value_label_reference_counts = value_label_reference_counts(
        &data.metadata,
        data.columns
            .iter()
            .map(|column| column.variable_index as usize),
    );
    let mut value_label_attributes = AHashMap::new();
    let mut value_label_tables = AHashMap::new();
    for table in std::mem::take(&mut data.value_label_tables) {
        let ValueLabelTable { name, entries } = table;
        if value_label_reference_counts.contains_key(name.as_str())
            && !value_label_tables.contains_key(name.as_str())
        {
            value_label_tables.insert(name, entries);
        }
    }

    for index in 0..data.columns.len() {
        check_interrupt()?;
        {
            let mut column_guard = ProtectGuard::new();
            let column = build_column(
                &data,
                index,
                &value_label_reference_counts,
                &mut value_label_tables,
                &mut value_label_attributes,
                &mut column_guard,
                &mut result_guard,
            )?;
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

    fn push_id(&mut self, id: u32) {
        self.value_ids.push(id);
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
                self.push_id(id);
                return Ok(());
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
        self.push_id(id);
        Ok(())
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
                self.push_id(id);
                return Ok(());
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
        missing_count: 0,
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
            missing_count: 0,
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
        if !no_na {
            self.missing_count += 1;
        }
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
        self,
        metadata: DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: Vec<ValueLabelTable>,
    ) -> Result<Self::Output, DtaError> {
        self.finish_with_value_labels(
            &metadata,
            row_start,
            row_count,
            ValueLabelTableView::Owned(value_label_tables),
        )
    }

    fn finish_with_value_labels(
        mut self,
        metadata: &DtaMetadata,
        _row_start: u64,
        row_count: u64,
        value_label_tables: ValueLabelTableView<'_>,
    ) -> Result<Self::Output, DtaError> {
        let expected_string_rows = usize::try_from(row_count)
            .map_err(|_| DtaError::Output("R vector is too long".to_owned()))?;
        let value_label_reference_counts = value_label_reference_counts(
            &metadata,
            self.source_indices.iter().map(|&index| index as usize),
        );
        let mut value_label_tables_by_name = AHashMap::with_capacity(value_label_tables.len());
        for table in value_label_tables.iter() {
            if value_label_reference_counts.contains_key(table.name.as_str()) {
                value_label_tables_by_name
                    .entry(table.name.as_str())
                    .or_insert(table);
            }
        }
        unsafe {
            let mut value_label_attributes = AHashMap::new();
            for (output_index, column) in self.columns.iter_mut().enumerate() {
                check_interrupt().map_err(DtaError::Output)?;
                let vector = match column {
                    RColumn::NumericAltRep { vector, data } => {
                        let data = data.take();
                        *vector = self._guard.numeric(data).map_err(DtaError::Output)?;
                        SET_VECTOR_ELT(self.result, output_index as RLen, *vector);
                        *vector
                    }
                    RColumn::NumericEager { vector, .. } => *vector,
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
                        *vector
                    }
                };
                let source_index = self.source_indices[output_index];
                let variable = metadata
                    .variables
                    .get(source_index as usize)
                    .ok_or(DtaError::ArithmeticOverflow("output source column"))?;
                let table_name = (!variable.value_label_name.is_empty()
                    && (value_label_attributes.contains_key(variable.value_label_name.as_str())
                        || value_label_tables_by_name
                            .contains_key(variable.value_label_name.as_str())))
                .then_some(variable.value_label_name.as_str());
                let mut attribute_guard = ProtectGuard::new();
                let labels_attribute = match table_name {
                    Some(table_name) => cached_borrowed_label_attribute(
                        table_name,
                        &value_label_tables_by_name,
                        &mut value_label_attributes,
                        &mut self._guard,
                    )
                    .map_err(DtaError::Output)?,
                    None => None,
                };
                attach_variable_attributes(
                    vector,
                    variable,
                    table_name,
                    labels_attribute,
                    preserve_value_label_name(variable, table_name, &value_label_reference_counts),
                    &mut attribute_guard,
                )
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
            attach_dataset_attributes(self.result, metadata).map_err(DtaError::Output)?;
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

    fn finish_parallel_with_value_labels(
        state: Self::State,
        columns: Vec<Self::Column>,
        metadata: &DtaMetadata,
        row_start: u64,
        row_count: u64,
        value_label_tables: ValueLabelTableView<'_>,
    ) -> Result<Self::Output, DtaError> {
        DtaSink::finish_with_value_labels(
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
    include_value_labels: bool,
) -> Result<Sexp, String> {
    let mut file =
        DtaFile::open_with_encoding(path, encoding).map_err(|error| error.to_string())?;
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
    let value_label_names = variables
        .iter()
        .map(|variable| variable.value_label_name.clone())
        .collect::<Vec<_>>();
    let storage = string_vector(&storage, &mut guard)?;
    set_attr(result, "dta_storage", storage)?;
    let version = scalar_integer(metadata.format_version.as_u16().into(), &mut guard)?;
    set_attr(result, "dta_format_version", version)?;
    let value_label_names = string_vector(&value_label_names, &mut guard)?;
    set_attr(result, "dta_value_label_names", value_label_names)?;

    if include_value_labels {
        let tables = file
            .value_label_tables()
            .map_err(|error| error.to_string())?;
        let table_count =
            RLen::try_from(tables.len()).map_err(|_| "too many value-label tables")?;
        let registry = guard.alloc(VECSXP, table_count)?;
        let registry_names = guard.alloc(STRSXP, table_count)?;
        for (index, table) in tables.iter().enumerate() {
            check_interrupt()?;
            let labels = label_attribute_from_entries(
                table.entries.len(),
                table.entries.iter().map(|entry| {
                    Ok((
                        entry
                            .missing_tag
                            .map(r_missing)
                            .unwrap_or_else(|| f64::from(entry.value)),
                        entry.label.as_str(),
                    ))
                }),
                &mut guard,
            )?;
            SET_VECTOR_ELT(registry, index as RLen, labels);
            SET_STRING_ELT(registry_names, index as RLen, r_char(&table.name)?);
        }
        set_symbol_attr(registry, R_NamesSymbol, registry_names)?;
        set_attr(result, "dta_value_label_registry", registry)?;
    }
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
        build_data_frame(data)
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

unsafe fn boundary<T, F>(error: *mut *mut c_char, failure: T, call: F) -> T
where
    T: Copy,
    F: FnOnce() -> Result<T, String>,
{
    if !error.is_null() {
        *error = ptr::null_mut();
    }
    match catch_unwind(AssertUnwindSafe(call)) {
        Ok(Ok(value)) => value,
        Ok(Err(message)) => {
            set_error(error, message);
            failure
        }
        Err(payload) => {
            set_error(
                error,
                format!("native Rust panic: {}", panic_message(payload)),
            );
            failure
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
pub unsafe extern "C" fn dtatools_metadata_rust(
    path: *const c_char,
    column_start: u32,
    column_count: u32,
    encoding: *const c_char,
    include_value_labels: c_int,
    error: *mut *mut c_char,
) -> Sexp {
    boundary(error, ptr::null_mut(), || {
        if path.is_null() {
            return Err("file path is null".to_owned());
        }
        let path = CStr::from_ptr(path)
            .to_str()
            .map_err(|_| "file path is not valid UTF-8".to_owned())?;
        metadata_impl(
            path,
            text_encoding(encoding)?,
            column_start,
            column_count,
            include_value_labels != 0,
        )
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
pub unsafe extern "C" fn dtatools_read_rust(
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
    boundary(error, ptr::null_mut(), || {
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
    value_label_index: c_int,
    stata_metadata: Sexp,
    numeric_shift: f64,
    numeric_scale: f64,
    direct_numeric_values: *const c_void,
    direct_numeric_kind: c_int,
    direct_numeric_format_version: c_int,
    direct_numeric_temporal: c_int,
    direct_numeric_no_na: c_int,
    direct_string_data: *mut c_void,
}

#[cfg(target_pointer_width = "64")]
const _: () = {
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, name) == 0);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, dta_type) == 8);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, format) == 16);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, label) == 24);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, numeric_values) == 32);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, string_values) == 40);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, value_label_index) == 48);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, stata_metadata) == 56);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, numeric_shift) == 64);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, numeric_scale) == 72);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, direct_numeric_values) == 80);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, direct_numeric_kind) == 88);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, direct_numeric_format_version) == 92);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, direct_numeric_temporal) == 96);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, direct_numeric_no_na) == 100);
    assert!(std::mem::offset_of!(RWriteColumnDescriptor, direct_string_data) == 104);
    assert!(std::mem::size_of::<RWriteColumnDescriptor>() == 112);
};

#[repr(C)]
pub struct RWriteValueLabelTableDescriptor {
    name: *const c_char,
    label_values: *const c_void,
    label_texts: Sexp,
    label_count: usize,
}

#[cfg(target_pointer_width = "64")]
const _: () = {
    assert!(std::mem::offset_of!(RWriteValueLabelTableDescriptor, name) == 0);
    assert!(std::mem::offset_of!(RWriteValueLabelTableDescriptor, label_values) == 8);
    assert!(std::mem::offset_of!(RWriteValueLabelTableDescriptor, label_texts) == 16);
    assert!(std::mem::offset_of!(RWriteValueLabelTableDescriptor, label_count) == 24);
    assert!(std::mem::size_of::<RWriteValueLabelTableDescriptor>() == 32);
};

#[derive(Debug)]
enum RWriteError {
    Interrupted,
    Message(String),
}

impl From<String> for RWriteError {
    fn from(message: String) -> Self {
        Self::Message(message)
    }
}

impl From<&str> for RWriteError {
    fn from(message: &str) -> Self {
        Self::Message(message.to_owned())
    }
}

impl From<DtaWriteError> for RWriteError {
    fn from(error: DtaWriteError) -> Self {
        match error {
            DtaWriteError::Interrupted => Self::Interrupted,
            error => Self::Message(error.to_string()),
        }
    }
}

const WRITE_CALLBACK_ERROR_CAPACITY: usize = 4_096;

struct WriteCallbackErrorBuffer {
    bytes: [c_char; WRITE_CALLBACK_ERROR_CAPACITY],
}

impl WriteCallbackErrorBuffer {
    fn new() -> Self {
        Self {
            bytes: [0; WRITE_CALLBACK_ERROR_CAPACITY],
        }
    }

    fn as_mut_ptr(&mut self) -> *mut c_char {
        self.bytes.as_mut_ptr()
    }

    fn capacity(&self) -> usize {
        self.bytes.len()
    }

    fn message(&self) -> Option<String> {
        let message = unsafe { CStr::from_ptr(self.bytes.as_ptr()) }
            .to_string_lossy()
            .into_owned();
        (!message.is_empty()).then_some(message)
    }
}

fn write_callback_status(
    status: c_int,
    fallback: &str,
    error: &WriteCallbackErrorBuffer,
) -> Result<(), RWriteError> {
    match status {
        value if value > 0 => Ok(()),
        -1 => Err(RWriteError::Interrupted),
        _ => Err(RWriteError::Message(
            error.message().unwrap_or_else(|| fallback.to_owned()),
        )),
    }
}

/// Read one region of a protected STRSXP into owned strings through the
/// string region callback. `None` marks `NA_character_`.
unsafe fn fill_string_region(
    values: Sexp,
    start: usize,
    length: usize,
    what: &str,
) -> Result<Vec<Option<String>>, String> {
    if values.is_null() {
        return Err(format!("{what} vector is null"));
    }
    let mut strings: Vec<*const c_char> = vec![ptr::null(); length];
    let mut lengths: Vec<usize> = vec![0; length];
    let mut error = WriteCallbackErrorBuffer::new();
    let error_capacity = error.capacity();
    let status = dtatools_write_string_region(
        values,
        start,
        length,
        ptr::null_mut(),
        strings.as_mut_ptr(),
        lengths.as_mut_ptr(),
        error.as_mut_ptr(),
        error_capacity,
    );
    match status {
        value if value > 0 => {}
        -1 => return Err("interrupted".to_owned()),
        _ => {
            return Err(error
                .message()
                .unwrap_or_else(|| format!("could not read {what} from R")))
        }
    }
    let mut result = Vec::new();
    result
        .try_reserve_exact(length)
        .map_err(|_| format!("could not allocate {what}"))?;
    for (&bytes, &byte_length) in strings.iter().zip(&lengths) {
        if bytes.is_null() {
            result.push(None);
        } else {
            let slice = std::slice::from_raw_parts(bytes.cast::<u8>(), byte_length);
            let value =
                std::str::from_utf8(slice).map_err(|_| format!("{what} contains invalid UTF-8"))?;
            result.push(Some(value.to_owned()));
        }
    }
    Ok(result)
}

#[derive(Default)]
struct RWriteNumericRegion {
    start: u64,
    values: Vec<f64>,
    missing_codes: Vec<c_int>,
}

struct RWriteNumericRegionCache {
    rows: usize,
    region: RefCell<RWriteNumericRegion>,
}

#[derive(Default)]
struct RWriteStringRegion {
    start: u64,
    ids: Vec<u64>,
    values: Vec<*const c_char>,
    lengths: Vec<usize>,
}

struct RWriteStringRegionCache {
    rows: usize,
    region: RefCell<RWriteStringRegion>,
}

#[derive(Clone, Copy)]
enum DirectNumericKind {
    Callback,
    Integer,
    Double,
    Compact(NumericKind),
}

impl TryFrom<c_int> for DirectNumericKind {
    type Error = String;

    fn try_from(value: c_int) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Self::Callback),
            1 => Ok(Self::Integer),
            2 => Ok(Self::Double),
            3..=6 => NumericKind::try_from(value - 3)
                .map(Self::Compact)
                .map_err(|_| "invalid direct R numeric source kind".into()),
            _ => Err("invalid direct R numeric source kind".into()),
        }
    }
}

impl DirectNumericKind {
    fn is_compact(self) -> bool {
        matches!(self, Self::Compact(_))
    }
}

struct RWriteSource<'a> {
    descriptor: &'a RWriteColumnDescriptor,
    row_count: u64,
    direct_numeric_kind: DirectNumericKind,
    direct_numeric_version: Option<FormatVersion>,
    direct_numeric_temporal: TemporalKind,
    direct_numeric_no_na: bool,
    raw_numeric: bool,
    numeric_region: Option<Box<RWriteNumericRegionCache>>,
    string_region: Option<Box<RWriteStringRegionCache>>,
    numeric_replacements: Cell<u64>,
}

fn save_dta_type(code: c_int) -> Result<DtaType, String> {
    match code {
        0 => Ok(DtaType::Byte),
        1 => Ok(DtaType::Int),
        2 => Ok(DtaType::Long),
        3 => Ok(DtaType::Float),
        4 => Ok(DtaType::Double),
        width if (5..=2_049).contains(&width) => Ok(DtaType::FixedString(
            u16::try_from(width - 4).map_err(|_| "invalid fixed-string width".to_owned())?,
        )),
        2_050 => Ok(DtaType::StrL),
        _ => Err("invalid native DTA storage type".into()),
    }
}

fn wider_numeric_type(dta_type: &DtaType) -> Option<DtaType> {
    match dta_type {
        DtaType::Byte => Some(DtaType::Int),
        DtaType::Int => Some(DtaType::Long),
        DtaType::Long | DtaType::Float => Some(DtaType::Double),
        DtaType::Double | DtaType::FixedString(_) | DtaType::StrL => None,
    }
}

fn legacy_source_output_type(
    source: &RWriteSource<'_>,
    mut dta_type: DtaType,
) -> Result<DtaType, String> {
    if !source.direct_numeric_kind.is_compact()
        || source.direct_numeric_version.is_none_or(|version| {
            !matches!(
                version,
                FormatVersion::V105
                    | FormatVersion::V108
                    | FormatVersion::V110
                    | FormatVersion::V111
            )
        })
    {
        return Ok(dta_type);
    }

    for index in 0..source.row_count {
        let index = usize::try_from(index).map_err(|_| "R row index is too large".to_owned())?;
        let Some((value, missing_code)) = (unsafe { direct_numeric_at(source, index) })? else {
            return Ok(dta_type);
        };
        if missing_code != -1 {
            continue;
        }
        let value = write_numeric_value(
            value,
            source.descriptor.numeric_shift,
            source.descriptor.numeric_scale,
        );
        while !dta_write_numeric_value_is_representable(&dta_type, value) {
            let Some(wider) = wider_numeric_type(&dta_type) else {
                break;
            };
            dta_type = wider;
        }
    }
    Ok(dta_type)
}

fn direct_numeric_is_output_encoded(
    descriptor: &RWriteColumnDescriptor,
    kind: DirectNumericKind,
    temporal: TemporalKind,
) -> bool {
    descriptor.direct_numeric_format_version > 111
        && matches!(
            (kind, descriptor.dta_type),
            (DirectNumericKind::Compact(NumericKind::Byte), 0)
                | (DirectNumericKind::Compact(NumericKind::Int), 1)
                | (DirectNumericKind::Compact(NumericKind::Long), 2)
                | (DirectNumericKind::Compact(NumericKind::Float), 3)
        )
        && match temporal {
            TemporalKind::None => {
                descriptor.numeric_shift == 0.0 && descriptor.numeric_scale == 1.0
            }
            TemporalKind::Date => {
                descriptor.numeric_shift == DAYS_1960_TO_1970 && descriptor.numeric_scale == 1.0
            }
            TemporalKind::Datetime => {
                descriptor.numeric_shift == SECONDS_1960_TO_1970
                    && descriptor.numeric_scale == 1000.0
            }
        }
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

unsafe fn fill_r_numeric_region(
    reader: *const c_void,
    start: usize,
    values: &mut [f64],
    missing_codes: &mut [c_int],
    fallback_message: &str,
) -> Result<(), RWriteError> {
    if values.len() != missing_codes.len() {
        return Err("R numeric region buffers have different lengths".into());
    }
    let mut error = WriteCallbackErrorBuffer::new();
    let error_capacity = error.capacity();
    let status = dtatools_write_numeric_region(
        reader,
        start,
        values.len(),
        values.as_mut_ptr(),
        missing_codes.as_mut_ptr(),
        error.as_mut_ptr(),
        error_capacity,
    );
    write_callback_status(status, fallback_message, &error)
}

fn direct_missing_code(tag: MissingTag) -> c_int {
    let offset = tag.offset();
    if offset == 0 {
        0
    } else {
        c_int::from(b'a' + offset - 1)
    }
}

fn r_na_real_bits() -> u64 {
    #[cfg(test)]
    {
        0x7ff0_0000_0000_07a2_u64
    }
    #[cfg(not(test))]
    {
        unsafe { R_NaReal }.to_bits()
    }
}

fn direct_r_missing_code(value: f64) -> c_int {
    if !value.is_nan() {
        return -1;
    }
    let bits = value.to_bits();
    let sign_bit = 0x8000_0000_0000_0000_u64;
    let quiet_nan_bit = 0x0008_0000_0000_0000_u64;
    let tag_bits = 0x0000_00ff_0000_0000_u64;
    let layout_bits = sign_bit | quiet_nan_bit;
    let tagged_layout = 0x7ff0_0000_0000_07a2_u64;
    let tag = ((bits & tag_bits) >> 32) as u8;
    if tag != 0 && (bits & !(layout_bits | tag_bits)) == (tagged_layout & !(layout_bits | tag_bits))
    {
        return if tag.is_ascii_lowercase() {
            c_int::from(tag)
        } else {
            256
        };
    }
    if bits as u32 == r_na_real_bits() as u32 {
        0
    } else {
        256
    }
}

#[derive(Clone, Copy)]
enum DirectCompactValue {
    Byte(i8),
    Int(i16),
    Long(i32),
    Float(f32),
}

impl DirectCompactValue {
    fn as_f64(self) -> f64 {
        match self {
            Self::Byte(value) => f64::from(value),
            Self::Int(value) => f64::from(value),
            Self::Long(value) => f64::from(value),
            Self::Float(value) => f64::from(value),
        }
    }

    fn missing(self, version: FormatVersion) -> Option<MissingTag> {
        match self {
            Self::Byte(value) => classify_byte_missing_for_version(value, version),
            Self::Int(value) => classify_int_missing_for_version(value, version),
            Self::Long(value) => classify_long_missing_for_version(value, version),
            Self::Float(value) => classify_float_missing_bits_for_version(value.to_bits(), version),
        }
    }

    fn raw(self) -> DtaWriteRawNumericValue {
        match self {
            Self::Byte(value) => DtaWriteRawNumericValue::Byte(value),
            Self::Int(value) => DtaWriteRawNumericValue::Int(value),
            Self::Long(value) => DtaWriteRawNumericValue::Long(value),
            Self::Float(value) => DtaWriteRawNumericValue::Float(value),
        }
    }

    fn is_representable(self) -> bool {
        let dta_type = match self {
            Self::Byte(_) => DtaType::Byte,
            Self::Int(_) => DtaType::Int,
            Self::Long(_) => DtaType::Long,
            Self::Float(_) => DtaType::Float,
        };
        dta_write_numeric_value_is_representable(&dta_type, self.as_f64())
    }

    fn is_nan(self) -> bool {
        matches!(self, Self::Float(value) if value.is_nan())
    }
}

unsafe fn write_raw_numeric_to_ptr(output: *mut u8, value: DtaWriteRawNumericValue) {
    match value {
        DtaWriteRawNumericValue::Byte(value) => ptr::write(output, value as u8),
        DtaWriteRawNumericValue::Int(value) => {
            ptr::copy_nonoverlapping(value.to_le_bytes().as_ptr(), output, size_of::<i16>())
        }
        DtaWriteRawNumericValue::Long(value) => {
            ptr::copy_nonoverlapping(value.to_le_bytes().as_ptr(), output, size_of::<i32>())
        }
        DtaWriteRawNumericValue::Float(value) => ptr::copy_nonoverlapping(
            value.to_bits().to_le_bytes().as_ptr(),
            output,
            size_of::<f32>(),
        ),
        DtaWriteRawNumericValue::Double(value) => ptr::copy_nonoverlapping(
            value.to_bits().to_le_bytes().as_ptr(),
            output,
            size_of::<f64>(),
        ),
    }
}

fn write_type_width(dta_type: &DtaType) -> usize {
    dta_type.storage_width() as usize
}

unsafe fn direct_compact_at(
    source: &RWriteSource<'_>,
    index: usize,
) -> Option<(DirectCompactValue, Option<MissingTag>)> {
    let values = source.descriptor.direct_numeric_values;
    let value = match source.direct_numeric_kind {
        DirectNumericKind::Compact(NumericKind::Byte) => {
            DirectCompactValue::Byte(ptr::read(values.cast::<i8>().add(index)))
        }
        DirectNumericKind::Compact(NumericKind::Int) => {
            DirectCompactValue::Int(ptr::read(values.cast::<i16>().add(index)))
        }
        DirectNumericKind::Compact(NumericKind::Long) => {
            DirectCompactValue::Long(ptr::read(values.cast::<i32>().add(index)))
        }
        DirectNumericKind::Compact(NumericKind::Float) => {
            DirectCompactValue::Float(ptr::read(values.cast::<f32>().add(index)))
        }
        DirectNumericKind::Callback | DirectNumericKind::Integer | DirectNumericKind::Double => {
            return None;
        }
    };
    let missing = (!source.direct_numeric_no_na)
        .then(|| value.missing(source.direct_numeric_version.unwrap()))
        .flatten();
    Some((value, missing))
}

unsafe fn direct_numeric_at(
    source: &RWriteSource<'_>,
    index: usize,
) -> Result<Option<(f64, c_int)>, String> {
    let values = source.descriptor.direct_numeric_values;
    if values.is_null() || matches!(source.direct_numeric_kind, DirectNumericKind::Callback) {
        return Ok(None);
    }
    let (mut value, missing_code) = match source.direct_numeric_kind {
        DirectNumericKind::Integer => {
            let value = ptr::read(values.cast::<c_int>().add(index));
            if value == c_int::MIN {
                (0.0, 0)
            } else {
                (f64::from(value), -1)
            }
        }
        DirectNumericKind::Double => {
            let value = ptr::read(values.cast::<f64>().add(index));
            (value, direct_r_missing_code(value))
        }
        DirectNumericKind::Compact(_) => {
            let (value, missing) = direct_compact_at(source, index)
                .expect("compact source has a direct compact value");
            let missing_code = missing.map_or_else(
                || if value.is_nan() { 256 } else { -1 },
                direct_missing_code,
            );
            (value.as_f64(), missing_code)
        }
        DirectNumericKind::Callback => unreachable!("callback source returned above"),
    };
    if missing_code == -1 {
        value = observed_value(value, source.direct_numeric_temporal);
    }
    Ok(Some((value, missing_code)))
}

unsafe fn fill_r_string_region(
    values: Sexp,
    start: usize,
    ids: Option<&mut [u64]>,
    strings: &mut [*const c_char],
    lengths: &mut [usize],
    fallback_message: &str,
) -> Result<(), RWriteError> {
    if strings.len() != lengths.len() || ids.as_ref().is_some_and(|ids| ids.len() != strings.len())
    {
        return Err("R character region buffers have different lengths".into());
    }
    let ids = ids.map_or(ptr::null_mut(), |ids| ids.as_mut_ptr());
    let mut error = WriteCallbackErrorBuffer::new();
    let error_capacity = error.capacity();
    let status = dtatools_write_string_region(
        values,
        start,
        strings.len(),
        ids,
        strings.as_mut_ptr(),
        lengths.as_mut_ptr(),
        error.as_mut_ptr(),
        error_capacity,
    );
    write_callback_status(status, fallback_message, &error)
}

unsafe fn r_string_from_bytes<'a>(
    value: *const u8,
    length: usize,
) -> Result<Cow<'a, str>, RWriteError> {
    if value.is_null() && length != 0 {
        return Err("R character source returned a null byte pointer".into());
    }
    let bytes = if length == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(value, length)
    };
    std::str::from_utf8(bytes)
        .map(Cow::Borrowed)
        .map_err(|_| RWriteError::from("R character value is not valid UTF-8"))
}

impl<'a> RWriteSource<'a> {
    fn new(
        descriptor: &'a RWriteColumnDescriptor,
        row_count: u64,
        numeric_region_rows: usize,
        string_region_rows: usize,
    ) -> Result<Self, String> {
        let direct_numeric_kind = DirectNumericKind::try_from(descriptor.direct_numeric_kind)?;
        let direct_numeric_version = if direct_numeric_kind.is_compact() {
            let release = u16::try_from(descriptor.direct_numeric_format_version)
                .map_err(|_| "invalid direct numeric format version".to_owned())?;
            Some(
                FormatVersion::try_from(release)
                    .map_err(|_| "invalid direct numeric format version".to_owned())?,
            )
        } else {
            None
        };
        let direct_numeric_temporal = TemporalKind::try_from(descriptor.direct_numeric_temporal)?;
        let uses_numeric_callback = descriptor.dta_type <= 4
            && (descriptor.direct_numeric_values.is_null()
                || matches!(direct_numeric_kind, DirectNumericKind::Callback));
        let uses_string_callback =
            descriptor.dta_type >= 5 && descriptor.direct_string_data.is_null();
        Ok(Self {
            descriptor,
            row_count,
            direct_numeric_kind,
            direct_numeric_version,
            direct_numeric_temporal,
            direct_numeric_no_na: descriptor.direct_numeric_no_na != 0,
            raw_numeric: direct_numeric_is_output_encoded(
                descriptor,
                direct_numeric_kind,
                direct_numeric_temporal,
            ),
            numeric_region: uses_numeric_callback.then(|| {
                Box::new(RWriteNumericRegionCache {
                    rows: numeric_region_rows.max(1),
                    region: RefCell::new(RWriteNumericRegion::default()),
                })
            }),
            string_region: uses_string_callback.then(|| {
                Box::new(RWriteStringRegionCache {
                    rows: string_region_rows.max(1),
                    region: RefCell::new(RWriteStringRegion::default()),
                })
            }),
            numeric_replacements: Cell::new(0),
        })
    }

    fn callback_numeric_value_at(&self, row: u64) -> Result<(f64, c_int), RWriteError> {
        let cache = self
            .numeric_region
            .as_ref()
            .ok_or_else(|| "R numeric callback source is unavailable".to_owned())?;
        let mut region = cache.region.borrow_mut();
        let end = region
            .start
            .checked_add(region.values.len() as u64)
            .ok_or_else(|| "R numeric region is too large".to_owned())?;
        if region.values.is_empty() || row < region.start || row >= end {
            let remaining = usize::try_from(self.row_count - row)
                .map_err(|_| "R numeric region is too large".to_owned())?;
            let length = remaining.min(cache.rows);
            region.values.resize(length, 0.0);
            region.missing_codes.resize(length, -1);
            let start = usize::try_from(row).map_err(|_| "R row index is too large".to_owned())?;
            let RWriteNumericRegion {
                values,
                missing_codes,
                ..
            } = &mut *region;
            unsafe {
                fill_r_numeric_region(
                    self.descriptor.numeric_values,
                    start,
                    values,
                    missing_codes,
                    "R numeric source could not supply a region",
                )
            }?;
            region.start = row;
        }
        let offset = usize::try_from(row - region.start)
            .map_err(|_| "R numeric region index is too large".to_owned())?;
        Ok((region.values[offset], region.missing_codes[offset]))
    }

    fn raw_numeric_value_at(
        &self,
        row: u64,
    ) -> Result<Option<DtaWriteRawNumericValue>, RWriteError> {
        if !self.raw_numeric {
            return Ok(None);
        }
        let index = usize::try_from(row).map_err(|_| "R row index is too large".to_owned())?;
        let (value, missing) = unsafe { direct_compact_at(self, index) }
            .ok_or_else(|| "noncompact source reached raw numeric access".to_owned())?;
        if missing.is_none() && !value.is_representable() {
            return Ok(None);
        }
        Ok(Some(value.raw()))
    }

    fn numeric_value_at(
        &self,
        row: u64,
        dta_type: &DtaType,
    ) -> Result<DtaWriteNumericValue, RWriteError> {
        let index = usize::try_from(row).map_err(|_| "R row index is too large".to_owned())?;
        let (value, missing_code) = match unsafe { direct_numeric_at(self, index) }? {
            Some(value) => value,
            None => self.callback_numeric_value_at(row)?,
        };
        let value = match missing_from_code(missing_code) {
            Ok(Some(tag)) => return Ok(DtaWriteNumericValue::Missing(tag)),
            Ok(None) => write_numeric_value(
                value,
                self.descriptor.numeric_shift,
                self.descriptor.numeric_scale,
            ),
            Err(_) => {
                self.numeric_replacements
                    .set(self.numeric_replacements.get() + 1);
                return Ok(DtaWriteNumericValue::Missing(MissingTag::System));
            }
        };
        if dta_write_numeric_value_is_representable(dta_type, value) {
            Ok(DtaWriteNumericValue::Value(value))
        } else {
            self.numeric_replacements
                .set(self.numeric_replacements.get() + 1);
            Ok(DtaWriteNumericValue::Missing(MissingTag::System))
        }
    }

    fn callback_string_at(
        &self,
        row: u64,
    ) -> Result<(u64, *const c_char, usize, bool), RWriteError> {
        let cache = self
            .string_region
            .as_ref()
            .ok_or_else(|| "R character callback source is unavailable".to_owned())?;
        let mut region = cache.region.borrow_mut();
        let end = region
            .start
            .checked_add(region.values.len() as u64)
            .ok_or_else(|| "R character region is too large".to_owned())?;
        if region.values.is_empty() || row < region.start || row >= end {
            let remaining = usize::try_from(self.row_count - row)
                .map_err(|_| "R character region is too large".to_owned())?;
            let length = remaining.min(cache.rows);
            let has_ids = self.descriptor.dta_type == 2_050;
            region.ids.resize(if has_ids { length } else { 0 }, 0);
            region.values.resize(length, ptr::null());
            region.lengths.resize(length, 0);
            let start = usize::try_from(row).map_err(|_| "R row index is too large".to_owned())?;
            let RWriteStringRegion {
                ids,
                values,
                lengths,
                ..
            } = &mut *region;
            unsafe {
                fill_r_string_region(
                    self.descriptor.string_values,
                    start,
                    has_ids.then_some(ids.as_mut_slice()),
                    values,
                    lengths,
                    "R character source could not supply a region",
                )?;
            }
            region.start = row;
        }
        let offset = usize::try_from(row - region.start)
            .map_err(|_| "R character region index is too large".to_owned())?;
        Ok((
            region.ids.get(offset).copied().unwrap_or(0),
            region.values[offset],
            region.lengths[offset],
            region.values[offset].is_null(),
        ))
    }

    fn dictionary_value_id_at(&self, index: usize) -> Result<(&DictStringData, u32), String> {
        let data = unsafe { &*self.descriptor.direct_string_data.cast::<DictStringData>() };
        if index >= data.length {
            return Err("R row index is outside the string dictionary".into());
        }
        Ok((data, unsafe { ptr::read(data.value_ids.add(index)) }))
    }

    fn string_id_at(&self, row: u64) -> Result<Option<u64>, RWriteError> {
        let index = usize::try_from(row).map_err(|_| "R row index is too large".to_owned())?;
        if self.descriptor.direct_string_data.is_null() {
            let (id, _, _, _) = self.callback_string_at(row)?;
            return Ok(Some(id));
        }
        let (_, id) = self.dictionary_value_id_at(index)?;
        Ok(Some(u64::from(id)))
    }

    fn string_value_at(&self, row: u64) -> Result<Cow<'_, str>, RWriteError> {
        let index = usize::try_from(row).map_err(|_| "R row index is too large".to_owned())?;
        if !self.descriptor.direct_string_data.is_null() {
            let (data, id) = self.dictionary_value_id_at(index)?;
            let &(value, length) = data
                .value_views
                .get(id as usize)
                .ok_or_else(|| "R string dictionary contains an invalid value ID".to_owned())?;
            let bytes = if length == 0 {
                &[]
            } else {
                unsafe { std::slice::from_raw_parts(value, length) }
            };
            // `value_views` point into owned Rust `String` keys, so their bytes
            // remain valid UTF-8 for the lifetime of the dictionary payload.
            return Ok(Cow::Borrowed(unsafe {
                std::str::from_utf8_unchecked(bytes)
            }));
        }
        let (_, value, length, missing) = self.callback_string_at(row)?;
        if missing {
            return Ok(Cow::Borrowed(""));
        }
        if value.is_null() && length != 0 {
            return Err("R character source returned a null byte pointer".into());
        }
        let bytes = if length == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(value.cast::<u8>(), length) }
        };
        // The protected R character vector owns immutable CHARSXPs for the
        // complete native call, so their byte storage outlives this borrow.
        std::str::from_utf8(bytes)
            .map(Cow::Borrowed)
            .map_err(|_| "R character value is not valid UTF-8".into())
    }
}

impl DtaWriteColumnSource for RWriteSource<'_> {
    fn len(&self) -> u64 {
        self.row_count
    }
}

struct RWriteObservationSource<'data, 'source> {
    data: &'data DtaWriteData<'source>,
    sources: &'data [RWriteSource<'source>],
}

fn r_write_source_result<T>(
    column: &DtaWriteColumn<'_>,
    row: u64,
    result: Result<T, RWriteError>,
) -> Result<T, DtaWriteError> {
    result.map_err(|error| match error {
        RWriteError::Interrupted => DtaWriteError::Interrupted,
        RWriteError::Message(message) => DtaWriteError::Source {
            column: column.name.to_string(),
            row,
            message,
        },
    })
}

#[derive(Clone, Copy)]
struct DirectObservationRegion {
    output: usize,
    start: u64,
    start_index: usize,
    rows: usize,
    row_width: usize,
}

unsafe fn encode_direct_observation_column(
    column: &DtaWriteColumn<'_>,
    source: &RWriteSource<'_>,
    region: DirectObservationRegion,
    column_offset: usize,
) -> Result<(), DtaWriteError> {
    let DirectObservationRegion {
        output,
        start,
        start_index,
        rows,
        row_width,
    } = region;
    let output = output as *mut u8;
    match column.dta_type {
        DtaType::Byte | DtaType::Int | DtaType::Long | DtaType::Float | DtaType::Double => {
            if source.raw_numeric {
                let mut replacements = 0_u64;
                for offset in 0..rows {
                    let row_index = start_index + offset;
                    let destination = output.add(offset * row_width + column_offset);
                    let (value, missing) = direct_compact_at(source, row_index)
                        .expect("raw numeric source is compact");
                    let valid = missing.is_some() || (!value.is_nan() && value.is_representable());
                    if valid {
                        write_raw_numeric_to_ptr(destination, value.raw());
                    } else {
                        replacements += 1;
                        write_raw_numeric_to_ptr(
                            destination,
                            encode_numeric(
                                &column.dta_type,
                                DtaWriteNumericValue::Missing(MissingTag::System),
                            ),
                        );
                    }
                }
                source
                    .numeric_replacements
                    .set(source.numeric_replacements.get() + replacements);
                return Ok(());
            }
            for offset in 0..rows {
                let row = start + offset as u64;
                let value = r_write_source_result(
                    column,
                    row,
                    source.numeric_value_at(row, &column.dta_type),
                )?;
                write_raw_numeric_to_ptr(
                    output.add(offset * row_width + column_offset),
                    encode_numeric(&column.dta_type, value),
                );
            }
        }
        DtaType::FixedString(width) => {
            let data = &*source
                .descriptor
                .direct_string_data
                .cast::<DictStringData>();
            for offset in 0..rows {
                let row_index = start_index + offset;
                if row_index >= data.length {
                    return Err(DtaWriteError::Source {
                        column: column.name.to_string(),
                        row: start + offset as u64,
                        message: "R row index is outside the string dictionary".into(),
                    });
                }
                let id = ptr::read(data.value_ids.add(row_index));
                let &(value, length) =
                    data.value_views
                        .get(id as usize)
                        .ok_or_else(|| DtaWriteError::Source {
                            column: column.name.to_string(),
                            row: start + offset as u64,
                            message: "R string dictionary contains an invalid value ID".into(),
                        })?;
                if length > usize::from(width) {
                    return Err(DtaWriteError::InvalidValue {
                        column: column.name.to_string(),
                        row: start + offset as u64,
                        message: format!(
                            "string must contain at most {width} UTF-8 bytes and no NUL"
                        ),
                    });
                }
                ptr::copy_nonoverlapping(
                    value,
                    output.add(offset * row_width + column_offset),
                    length,
                );
            }
        }
        DtaType::StrL => unreachable!("strL disables the direct observation path"),
    }
    Ok(())
}

impl RWriteObservationSource<'_, '_> {
    fn source_result<T>(
        &self,
        column_index: usize,
        row: u64,
        result: Result<T, RWriteError>,
    ) -> Result<T, DtaWriteError> {
        r_write_source_result(&self.data.columns[column_index], row, result)
    }

    fn has_direct_observations(&self) -> bool {
        self.data
            .columns
            .iter()
            .zip(self.sources)
            .all(|(column, source)| match column.dta_type {
                DtaType::Byte | DtaType::Int | DtaType::Long | DtaType::Float | DtaType::Double => {
                    !source.descriptor.direct_numeric_values.is_null()
                }
                DtaType::FixedString(_) => !source.descriptor.direct_string_data.is_null(),
                DtaType::StrL => false,
            })
    }

    fn append_direct_observation_rows(
        &self,
        buffer: &mut Vec<u8>,
        start: u64,
        end: u64,
        available_parallelism: usize,
    ) -> Result<usize, DtaWriteError> {
        let start_index =
            usize::try_from(start).map_err(|_| DtaWriteError::Overflow("row index"))?;
        let rows = usize::try_from(end - start)
            .map_err(|_| DtaWriteError::Overflow("observation row count"))?;
        let row_width = self
            .data
            .columns
            .iter()
            .try_fold(0_usize, |width, column| {
                width
                    .checked_add(write_type_width(&column.dta_type))
                    .ok_or(DtaWriteError::Overflow("observation width"))
            })?;
        let region_bytes = rows
            .checked_mul(row_width)
            .ok_or(DtaWriteError::Overflow("observation buffer"))?;
        let buffer_start = buffer.len();
        buffer.resize(
            buffer_start
                .checked_add(region_bytes)
                .ok_or(DtaWriteError::Overflow("observation buffer"))?,
            0,
        );
        let output = unsafe { buffer.as_mut_ptr().add(buffer_start) };
        let mut offsets = Vec::with_capacity(self.data.columns.len());
        let mut offset = 0_usize;
        for column in &self.data.columns {
            offsets.push(offset);
            offset += write_type_width(&column.dta_type);
        }

        let useful_for_size = region_bytes
            .div_ceil(DIRECT_OBSERVATION_BYTES_PER_WORKER)
            .max(1);
        let workers = available_parallelism
            .max(1)
            .min(self.data.columns.len())
            .min(useful_for_size);
        if workers <= 1 {
            let region = DirectObservationRegion {
                output: output as usize,
                start,
                start_index,
                rows,
                row_width,
            };
            for (index, (column, source)) in self.data.columns.iter().zip(self.sources).enumerate()
            {
                unsafe {
                    encode_direct_observation_column(column, source, region, offsets[index])
                }?;
            }
            return Ok(workers);
        }

        let mut ordered = (0..self.data.columns.len()).collect::<Vec<_>>();
        ordered.sort_unstable_by_key(|&index| {
            std::cmp::Reverse(write_type_width(&self.data.columns[index].dta_type))
        });
        let mut assignments = vec![Vec::<usize>::new(); workers];
        let mut assigned_widths = vec![0_usize; workers];
        for index in ordered {
            let worker = assigned_widths
                .iter()
                .enumerate()
                .min_by_key(|&(_, width)| width)
                .map(|(index, _)| index)
                .expect("there is at least one direct observation worker");
            assignments[worker].push(index);
            assigned_widths[worker] += write_type_width(&self.data.columns[index].dta_type);
        }

        let columns_address = self.data.columns.as_ptr() as usize;
        let sources_address = self.sources.as_ptr() as usize;
        let region = DirectObservationRegion {
            output: output as usize,
            start,
            start_index,
            rows,
            row_width,
        };
        std::thread::scope(|scope| -> Result<(), DtaWriteError> {
            let mut handles = Vec::with_capacity(workers);
            for assignment in assignments {
                let offsets = &offsets;
                handles.push(scope.spawn(move || -> Result<(), DtaWriteError> {
                    // The main R thread exposed the source buffers before spawning
                    // and keeps their protected owners live. Workers only read
                    // those buffers; each column's source state and output byte
                    // ranges belong to one worker, and no worker calls the R API.
                    for index in assignment {
                        let column =
                            unsafe { &*(columns_address as *const DtaWriteColumn<'_>).add(index) };
                        let source =
                            unsafe { &*(sources_address as *const RWriteSource<'_>).add(index) };
                        unsafe {
                            encode_direct_observation_column(column, source, region, offsets[index])
                        }?;
                    }
                    Ok(())
                }));
            }
            for handle in handles {
                handle.join().map_err(|_| DtaWriteError::Source {
                    column: "<dataset>".into(),
                    row: start,
                    message: "direct observation worker panicked".into(),
                })??;
            }
            Ok(())
        })?;
        Ok(workers)
    }
}

impl DtaWriteObservationSource for RWriteObservationSource<'_, '_> {
    fn begin_row(&self, row: u64) -> Result<(), DtaWriteError> {
        if row.is_multiple_of(INTERRUPT_STRIDE as u64) && coarse_interrupt() {
            Err(DtaWriteError::Interrupted)
        } else {
            Ok(())
        }
    }

    fn check_interrupt(&self) -> Result<(), DtaWriteError> {
        if coarse_interrupt() {
            Err(DtaWriteError::Interrupted)
        } else {
            Ok(())
        }
    }

    fn append_observation_rows(
        &self,
        buffer: &mut Vec<u8>,
        start: u64,
        end: u64,
    ) -> Result<bool, DtaWriteError> {
        if !self.has_direct_observations() {
            return Ok(false);
        }
        let available = std::thread::available_parallelism().map_or(1, usize::from);
        self.append_direct_observation_rows(buffer, start, end, available)?;
        Ok(true)
    }

    fn raw_numeric_value(
        &self,
        column_index: usize,
        row: u64,
    ) -> Result<Option<DtaWriteRawNumericValue>, DtaWriteError> {
        self.source_result(
            column_index,
            row,
            self.sources[column_index].raw_numeric_value_at(row),
        )
    }

    fn numeric_value(
        &self,
        column_index: usize,
        row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        self.source_result(
            column_index,
            row,
            self.sources[column_index]
                .numeric_value_at(row, &self.data.columns[column_index].dta_type),
        )
    }

    fn string_id(&self, column_index: usize, row: u64) -> Result<Option<u64>, DtaWriteError> {
        self.source_result(
            column_index,
            row,
            self.sources[column_index].string_id_at(row),
        )
    }

    fn string_value(&self, column_index: usize, row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        self.source_result(
            column_index,
            row,
            self.sources[column_index].string_value_at(row),
        )
    }
}

unsafe fn required_c_str<'a>(value: *const c_char, description: &str) -> Result<&'a str, String> {
    if value.is_null() {
        return Err(format!("{description} is null"));
    }
    CStr::from_ptr(value)
        .to_str()
        .map_err(|_| format!("{description} is not valid UTF-8"))
}

unsafe fn required_c_string(value: *const c_char, description: &str) -> Result<String, String> {
    required_c_str(value, description).map(str::to_owned)
}

unsafe fn r_value_labels<'a>(
    descriptor: &'a RWriteValueLabelTableDescriptor,
) -> Result<Vec<DtaWriteValueLabel<'a>>, RWriteError> {
    let mut result = Vec::with_capacity(descriptor.label_count);
    if descriptor.label_count == 0 {
        return Ok(result);
    }
    let bytes_per_entry =
        size_of::<f64>() + size_of::<c_int>() + size_of::<*const c_char>() + size_of::<usize>();
    let region_capacity = descriptor
        .label_count
        .min((WRITE_CALLBACK_REGION_BYTES / bytes_per_entry).max(1));
    let mut values = vec![0.0; region_capacity];
    let mut missing_codes = vec![-1; region_capacity];
    let mut strings = vec![ptr::null(); region_capacity];
    let mut lengths = vec![0; region_capacity];
    let mut start = 0;
    while start < descriptor.label_count {
        let length = (descriptor.label_count - start).min(region_capacity);
        fill_r_numeric_region(
            descriptor.label_values,
            start,
            &mut values[..length],
            &mut missing_codes[..length],
            "R numeric source could not supply value-label keys",
        )?;
        fill_r_string_region(
            descriptor.label_texts,
            start,
            None,
            &mut strings[..length],
            &mut lengths[..length],
            "R character source could not supply value-label text",
        )?;
        for offset in 0..length {
            let value = match missing_from_code(missing_codes[offset])? {
                Some(tag) => DtaWriteLabelValue::Missing(tag),
                None if values[offset].is_finite()
                    && values[offset].fract() == 0.0
                    && values[offset] >= f64::from(i32::MIN)
                    && values[offset] <= f64::from(i32::MAX) =>
                {
                    DtaWriteLabelValue::Integer(values[offset] as i32)
                }
                None => return Err("value-label key is not a representable integer".into()),
            };
            result.push(DtaWriteValueLabel {
                value,
                label: r_string_from_bytes(strings[offset].cast(), lengths[offset])?,
            });
        }
        start += length;
    }
    Ok(result)
}

struct RWriteRequest {
    path: *const c_char,
    dataset_label: *const c_char,
    stata_metadata: Sexp,
    descriptors: *const RWriteColumnDescriptor,
    column_count: usize,
    value_label_tables: *const RWriteValueLabelTableDescriptor,
    value_label_table_count: usize,
    numeric_replacements: *mut f64,
    row_count: usize,
    timestamp: *const c_char,
}

unsafe fn write_impl(request: RWriteRequest) -> Result<(), RWriteError> {
    let RWriteRequest {
        path,
        dataset_label,
        stata_metadata,
        descriptors,
        column_count,
        value_label_tables,
        value_label_table_count,
        numeric_replacements,
        row_count,
        timestamp,
    } = request;
    let path = required_c_string(path, "output path")?;
    let dataset_label = Cow::Borrowed(required_c_str(dataset_label, "dataset label")?);
    if descriptors.is_null() && column_count != 0 {
        return Err("write column pointer is null".into());
    }
    if value_label_tables.is_null() && value_label_table_count != 0 {
        return Err("value-label table pointer is null".into());
    }
    if numeric_replacements.is_null() && column_count != 0 {
        return Err("numeric replacement output pointer is null".into());
    }
    let (notes, characteristics) = parse_stata_metadata_sexp_borrowed(stata_metadata)?;
    let descriptors = if column_count == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(descriptors, column_count)
    };
    let table_descriptors = if value_label_table_count == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(value_label_tables, value_label_table_count)
    };
    let row_count = u64::try_from(row_count).map_err(|_| "row count is too large".to_owned())?;
    let callback_numeric_count = descriptors
        .iter()
        .filter(|descriptor| descriptor.dta_type <= 4 && descriptor.direct_numeric_kind == 0)
        .count();
    let numeric_region_rows = if callback_numeric_count == 0 {
        0
    } else {
        let bytes_per_row = callback_numeric_count
            .checked_mul(size_of::<f64>() + size_of::<c_int>())
            .ok_or_else(|| "R numeric region width is too large".to_owned())?;
        (WRITE_CALLBACK_REGION_BYTES / bytes_per_row).max(1)
    };
    let string_region_bytes_per_row = descriptors
        .iter()
        .filter(|descriptor| descriptor.dta_type >= 5 && descriptor.direct_string_data.is_null())
        .try_fold(0_usize, |bytes, descriptor| {
            bytes.checked_add(
                size_of::<*const c_char>()
                    + size_of::<usize>()
                    + if descriptor.dta_type == 2_050 {
                        size_of::<u64>()
                    } else {
                        0
                    },
            )
        })
        .ok_or_else(|| "R character region width is too large".to_owned())?;
    let string_region_rows = WRITE_CALLBACK_REGION_BYTES
        .checked_div(string_region_bytes_per_row)
        .map_or(0, |rows| rows.max(1));
    let sources = descriptors
        .iter()
        .map(|descriptor| {
            RWriteSource::new(
                descriptor,
                row_count,
                numeric_region_rows,
                string_region_rows,
            )
        })
        .collect::<Result<Vec<_>, _>>()?;
    let value_label_names = table_descriptors
        .iter()
        .map(|descriptor| unsafe {
            required_c_str(descriptor.name, "value-label table name")
        })
        .collect::<Result<Vec<_>, _>>()?;
    let value_label_tables = table_descriptors
        .iter()
        .map(|descriptor| unsafe { r_value_labels(descriptor) })
        .collect::<Result<Vec<_>, _>>()?;
    let mut value_label_indices = Vec::with_capacity(column_count);
    let mut columns = Vec::with_capacity(column_count);
    for (descriptor, source) in descriptors.iter().zip(&sources) {
        if !descriptor.numeric_shift.is_finite() || !descriptor.numeric_scale.is_finite() {
            return Err("numeric write transform must be finite".into());
        }
        let dta_type = legacy_source_output_type(source, save_dta_type(descriptor.dta_type)?)?;
        let (variable_notes, variable_characteristics) =
            parse_stata_metadata_sexp_borrowed(descriptor.stata_metadata)?;
        let value_label_index = if descriptor.value_label_index == -1 {
            None
        } else {
            let index = usize::try_from(descriptor.value_label_index)
                .map_err(|_| "labelled column has an invalid value-label table index")?;
            if index >= value_label_tables.len() {
                return Err("labelled column has an out-of-range value-label table index".into());
            }
            Some(index)
        };
        value_label_indices.push(value_label_index);
        columns.push(DtaWriteColumn {
            name: Cow::Borrowed(required_c_str(descriptor.name, "variable name")?),
            dta_type,
            format: Cow::Borrowed(required_c_str(descriptor.format, "display format")?),
            label: Cow::Borrowed(required_c_str(descriptor.label, "variable label")?),
            has_value_labels: value_label_index.is_some(),
            value_labels: Vec::new(),
            notes: variable_notes,
            characteristics: variable_characteristics,
            values: DtaWriteColumnValues::Source(source),
        });
    }
    let options = DtaWriteOptions {
        timestamp: Some(required_c_string(timestamp, "timestamp")?),
    };
    let data = DtaWriteData {
        dataset_label,
        notes,
        characteristics,
        columns,
    };
    let observation_source = RWriteObservationSource {
        data: &data,
        sources: &sources,
    };
    let mut open_options = OpenOptions::new();
    open_options.write(true).create_new(true);
    #[cfg(unix)]
    open_options.mode(0o600);
    let file = open_options
        .open(path)
        .map_err(|error| format!("could not create temporary DTA output: {error}"))?;
    let mut writer = BufWriter::new(file);
    let value_label_records = value_label_names
        .iter()
        .zip(&value_label_tables)
        .map(|(name, entries)| DtaWriteValueLabelTable::new(name, entries))
        .collect::<Vec<_>>();
    let registry = DtaWriteValueLabelRegistry::new(&value_label_records, &value_label_indices);
    write_prevalidated_dta_with_value_label_registry_to(
        &mut writer,
        &data,
        &options,
        &observation_source,
        row_count,
        &registry,
    )?;
    let file = writer
        .into_inner()
        .map_err(|error| format!("could not flush DTA output: {}", error.error()))?;
    drop(file);
    for (index, source) in sources.iter().enumerate() {
        ptr::write(
            numeric_replacements.add(index),
            source.numeric_replacements.get() as f64,
        );
    }
    Ok(())
}

#[no_mangle]
/// Stream a prevalidated R data frame to a new temporary DTA file.
///
/// # Safety
///
/// All pointers must remain valid for the call. The caller must run on R's
/// main thread because column sources call back into the R runtime.
pub unsafe extern "C" fn dtatools_write_rust(
    path: *const c_char,
    dataset_label: *const c_char,
    stata_metadata: Sexp,
    descriptors: *const RWriteColumnDescriptor,
    column_count: usize,
    value_label_tables: *const RWriteValueLabelTableDescriptor,
    value_label_table_count: usize,
    numeric_replacements: *mut f64,
    row_count: usize,
    timestamp: *const c_char,
    error: *mut *mut c_char,
) -> c_int {
    boundary(error, 0, || {
        match write_impl(RWriteRequest {
            path,
            dataset_label,
            stata_metadata,
            descriptors,
            column_count,
            value_label_tables,
            value_label_table_count,
            numeric_replacements,
            row_count,
            timestamp,
        }) {
            Ok(()) => Ok(1),
            Err(RWriteError::Interrupted) => Ok(-1),
            Err(RWriteError::Message(message)) => Err(message),
        }
    })
}

#[no_mangle]
/// Classify an output destination without following its final symbolic link.
///
/// Returns zero for a missing path, one for a regular file, two for a symbolic
/// link, three for a directory, four for another existing file type, and -1 on
/// error.
///
/// # Safety
///
/// `path` must point to a readable NUL-terminated C byte string for the
/// duration of this call. If non-null, `error` must point to writable storage
/// for one C string pointer.
pub unsafe extern "C" fn dtatools_write_path_kind(
    path: *const c_char,
    error: *mut *mut c_char,
) -> c_int {
    boundary(error, -1, || {
        let path = required_c_str(path, "output destination path")?;
        match fs::symlink_metadata(path) {
            Ok(metadata) => {
                let kind = metadata.file_type();
                Ok(if kind.is_file() {
                    1
                } else if kind.is_symlink() {
                    2
                } else if kind.is_dir() {
                    3
                } else {
                    4
                })
            }
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(0),
            Err(error) => Err(format!("could not inspect output destination: {error}")),
        }
    })
}

#[no_mangle]
/// Free an error string allocated by this library.
///
/// # Safety
///
/// `error` must be null or a live pointer returned through an `error` output by
/// this library, and it must not have been freed previously.
pub unsafe extern "C" fn dtatools_free_error(error: *mut c_char) {
    if !error.is_null() {
        drop(CString::from_raw(error));
    }
}

#[cfg(test)]
mod tests {
    use std::borrow::Cow;
    use std::ffi::{c_char, c_int, c_void};
    use std::ptr;

    use ahash::AHashMap;
    use dta_tools::{DtaType, DtaWriteColumn, DtaWriteColumnValues, DtaWriteData};

    use super::{
        direct_r_missing_code, dtatools_dictstring_free, observed_value, selected_row_count,
        temporal_kind, validate_r_row_count, write_callback_status, write_numeric_value,
        DictStringData, RWriteColumnDescriptor, RWriteError, RWriteObservationSource, RWriteSource,
        TemporalKind, WriteCallbackErrorBuffer, R_DATA_FRAME_MAX_ROWS,
    };

    #[no_mangle]
    unsafe extern "C" fn dtatools_write_numeric_region(
        _reader: *const c_void,
        _start: usize,
        _length: usize,
        _values: *mut f64,
        _missing_codes: *mut c_int,
        _error_message: *mut c_char,
        _error_capacity: usize,
    ) -> c_int {
        0
    }

    fn direct_numeric_descriptor(
        dta_type: c_int,
        values: *const c_void,
        kind: c_int,
        shift: f64,
        scale: f64,
    ) -> RWriteColumnDescriptor {
        RWriteColumnDescriptor {
            name: ptr::null(),
            dta_type,
            format: ptr::null(),
            label: ptr::null(),
            numeric_values: ptr::null(),
            string_values: ptr::null_mut(),
            stata_metadata: ptr::null_mut(),
            value_label_index: -1,
            numeric_shift: shift,
            numeric_scale: scale,
            direct_numeric_values: values,
            direct_numeric_kind: kind,
            direct_numeric_format_version: 118,
            direct_numeric_temporal: 0,
            direct_numeric_no_na: 0,
            direct_string_data: ptr::null_mut(),
        }
    }

    fn direct_string_descriptor(width: c_int, data: *mut c_void) -> RWriteColumnDescriptor {
        let mut descriptor = direct_numeric_descriptor(width + 4, ptr::null(), 0, 0.0, 1.0);
        descriptor.direct_string_data = data;
        descriptor
    }

    fn encode_direct_test_rows(
        descriptors: &[RWriteColumnDescriptor],
        dta_types: &[DtaType],
        row_count: usize,
        available_parallelism: usize,
    ) -> (Vec<u8>, Vec<u64>, usize) {
        let sources = descriptors
            .iter()
            .map(|descriptor| RWriteSource::new(descriptor, row_count as u64, 1, 1).unwrap())
            .collect::<Vec<_>>();
        let columns = dta_types
            .iter()
            .enumerate()
            .map(|(index, dta_type)| DtaWriteColumn {
                name: Cow::Owned(format!("x{index}")),
                dta_type: dta_type.clone(),
                format: Cow::Borrowed(""),
                label: Cow::Borrowed(""),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Source(&sources[index]),
            })
            .collect();
        let data = DtaWriteData {
            dataset_label: Cow::Borrowed(""),
            notes: Vec::new(),
            characteristics: Vec::new(),
            columns,
        };
        let observation_source = RWriteObservationSource {
            data: &data,
            sources: &sources,
        };
        let mut output = Vec::new();
        let workers = observation_source
            .append_direct_observation_rows(&mut output, 0, row_count as u64, available_parallelism)
            .unwrap();
        let replacements = sources
            .iter()
            .map(|source| source.numeric_replacements.get())
            .collect();
        (output, replacements, workers)
    }

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
    fn decoded_stata_milliseconds_snap_back_to_integer_storage() {
        for raw in [1.0, 999.0, 1_001.0] {
            let observed = observed_value(raw, TemporalKind::Datetime);
            assert_eq!(write_numeric_value(observed, 315_619_200.0, 1_000.0), raw);
        }
    }

    #[test]
    fn direct_r_missing_codes_match_r_system_na_payloads() {
        let system_missing = 0x7ff0_0000_0000_07a2_u64;
        for bits in [
            system_missing,
            system_missing | 0x0008_0000_0000_0000,
            system_missing | 0x8000_0000_0000_0000,
            0x7ff0_0100_0000_07a2,
        ] {
            assert_eq!(direct_r_missing_code(f64::from_bits(bits)), 0);
        }
    }

    #[test]
    fn callback_errors_preserve_r_condition_messages() {
        let mut error = WriteCallbackErrorBuffer::new();
        let message = b"ALTREP callback failed\0";
        for (destination, source) in error.bytes.iter_mut().zip(message) {
            *destination = *source as _;
        }
        let result = write_callback_status(0, "generic callback failure", &error);
        assert!(matches!(
            result,
            Err(RWriteError::Message(message)) if message == "ALTREP callback failed"
        ));
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

    #[test]
    fn threaded_direct_observation_encoding_matches_the_serial_path() {
        const ROWS: usize = 48_000;

        let ordinary_integers = (0..ROWS)
            .map(|index| {
                if index.is_multiple_of(17) {
                    c_int::MIN
                } else {
                    index as c_int - 24_000
                }
            })
            .collect::<Vec<_>>();
        let ordinary_doubles = (0..ROWS)
            .map(|index| {
                if index.is_multiple_of(19) {
                    f64::NAN
                } else {
                    index as f64 / 10.0
                }
            })
            .collect::<Vec<_>>();
        let compact_bytes = (0..ROWS)
            .map(|index| [-5_i8, 100, -128, 101][index % 4])
            .collect::<Vec<_>>();
        let compact_ints = (0..ROWS)
            .map(|index| [-30_000_i16, 30_000, i16::MIN, 32_741][index % 4])
            .collect::<Vec<_>>();
        let compact_longs = (0..ROWS)
            .map(|index| [-1_000_000_i32, 1_000_000, i32::MIN, 2_147_483_621][index % 4])
            .collect::<Vec<_>>();
        let compact_floats = (0..ROWS)
            .map(|index| {
                [
                    1.5_f32,
                    -2.25,
                    f32::from_bits(0x7fc0_0001),
                    f32::from_bits(0x7f00_0000),
                ][index % 4]
            })
            .collect::<Vec<_>>();

        let mut dictionary = AHashMap::new();
        dictionary.insert("alpha".to_owned(), 0_u32);
        dictionary.insert("beta".to_owned(), 1_u32);
        let mut views = vec![(ptr::null(), 0); dictionary.len()];
        for (value, &id) in &dictionary {
            views[id as usize] = (value.as_ptr(), value.len());
        }
        let ids = (0..ROWS).map(|index| (index % 2) as u32).collect();
        let dictionary_data = Box::into_raw(Box::new(DictStringData::new(ids, dictionary, views)));

        let descriptors = vec![
            direct_numeric_descriptor(2, ordinary_integers.as_ptr().cast(), 1, 0.0, 1.0),
            direct_numeric_descriptor(4, ordinary_doubles.as_ptr().cast(), 2, 5.0, 10.0),
            direct_numeric_descriptor(0, compact_bytes.as_ptr().cast(), 3, 0.0, 1.0),
            direct_numeric_descriptor(1, compact_ints.as_ptr().cast(), 4, 0.0, 1.0),
            direct_numeric_descriptor(2, compact_longs.as_ptr().cast(), 5, 0.0, 1.0),
            direct_numeric_descriptor(3, compact_floats.as_ptr().cast(), 6, 0.0, 1.0),
            direct_string_descriptor(8, dictionary_data.cast()),
        ];
        let dta_types = vec![
            DtaType::Long,
            DtaType::Double,
            DtaType::Byte,
            DtaType::Int,
            DtaType::Long,
            DtaType::Float,
            DtaType::FixedString(8),
        ];

        let (serial, serial_replacements, serial_workers) =
            encode_direct_test_rows(&descriptors, &dta_types, ROWS, 1);
        let (threaded, threaded_replacements, threaded_workers) =
            encode_direct_test_rows(&descriptors, &dta_types, ROWS, 2);

        assert!(serial.len() > 512 * 1024);
        assert_eq!(serial_workers, 1);
        assert_eq!(threaded_workers, 2);
        assert_eq!(threaded, serial);
        assert_eq!(threaded_replacements, serial_replacements);
        assert!(threaded_replacements.iter().any(|&count| count > 0));

        unsafe { dtatools_dictstring_free(dictionary_data.cast()) };
    }
}
