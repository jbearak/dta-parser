use std::borrow::Cow;
use std::collections::{hash_map::Entry, HashMap, HashSet};
use std::hash::{DefaultHasher, Hasher};
use std::io::{Seek, SeekFrom, Write};
use std::mem::size_of;

use crate::dta_metadata::{
    valid_characteristic, valid_dta_name_syntax, valid_note, MAX_NOTE_NUMBER,
};
use crate::metadata::{field_widths, FieldWidths};
use crate::{
    DtaType, FormatVersion, MissingTag, SectionOffsets, DOUBLE_MISSING_DOT_BITS,
    FLOAT_MISSING_DOT_BITS,
};

const MAX_VARIABLES: usize = 120_000;
const RELEASE_118_MAX_VARIABLES: usize = 32_767;
const WRITE_FIELD_WIDTHS: FieldWidths = field_widths(FormatVersion::V118);
const MAX_VALUE_LABEL_ENTRIES: usize = 65_536;
const MAX_VALUE_LABEL_TEXT_BYTES: usize = 32_000;
const MAX_NOTES: usize = MAX_NOTE_NUMBER as usize;
const MAX_STRL_BYTES: usize = 2_000_000_000;
const WRITE_INTERRUPT_BYTES: usize = 8 * 1024 * 1024;
const WRITE_INTERRUPT_RECORDS: usize = 4_096;
const OBSERVATION_BUFFER_BYTES: usize = 64 * 1024 * 1024;
const ZERO_BLOCK: [u8; 8 * 1024] = [0; 8 * 1024];

/// A numeric value supplied to the DTA writer.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DtaWriteNumericValue {
    Value(f64),
    Missing(MissingTag),
}

/// A numeric value already encoded in the output storage type.
#[doc(hidden)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DtaWriteRawNumericValue {
    Byte(i8),
    Int(i16),
    Long(i32),
    Float(f32),
    Double(f64),
}

/// A value-label key supplied to the DTA writer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DtaWriteLabelValue {
    Integer(i32),
    Missing(MissingTag),
}

/// One value-label entry. The public writer names tables after their variables
/// unless an internal adapter supplies a preserved source-table name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DtaWriteValueLabel<'a> {
    pub value: DtaWriteLabelValue,
    pub label: Cow<'a, str>,
}

/// One note supplied to the DTA writer.
///
/// Values converted from strings receive consecutive numbers in input order.
/// Use [`DtaWriteNote::numbered`] to preserve an explicit Stata note number.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DtaWriteNote<'a> {
    number: Option<u32>,
    pub text: Cow<'a, str>,
}

impl<'a> DtaWriteNote<'a> {
    pub fn numbered(number: u32, text: impl Into<Cow<'a, str>>) -> Self {
        Self {
            number: Some(number),
            text: text.into(),
        }
    }

    pub fn number(&self) -> Option<u32> {
        self.number
    }

    fn resolved_number(&self, index: usize) -> u32 {
        self.number
            .unwrap_or_else(|| u32::try_from(index + 1).expect("note count is bounded"))
    }
}

impl<'a> From<&'a str> for DtaWriteNote<'a> {
    fn from(text: &'a str) -> Self {
        Self {
            number: None,
            text: Cow::Borrowed(text),
        }
    }
}

impl From<String> for DtaWriteNote<'static> {
    fn from(text: String) -> Self {
        Self {
            number: None,
            text: Cow::Owned(text),
        }
    }
}

/// One user-authored characteristic supplied to the DTA writer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DtaWriteCharacteristic<'a> {
    pub name: Cow<'a, str>,
    pub value: Cow<'a, str>,
}

/// On-demand values for adapters that cannot expose borrowed Rust slices.
///
/// Implementations may borrow their source and are called during a complete
/// validation pass and again while observations are streamed to the writer.
pub trait DtaWriteColumnSource {
    fn len(&self) -> u64;

    fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn numeric_value(&self, _row: u64) -> Result<DtaWriteNumericValue, String> {
        Err("column source does not provide numeric values".into())
    }

    fn string_value(&self, _row: u64) -> Result<Cow<'_, str>, String> {
        Err("column source does not provide string values".into())
    }
}

/// Dataset-wide observation access for adapters with optimized native storage.
///
/// The common writer retains row ordering, bounded buffering, and error
/// handling. The hidden bulk seam is reserved for trusted in-tree adapters
/// that already own the final DTA storage encoding.
pub trait DtaWriteObservationSource {
    fn begin_row(&self, _row: u64) -> Result<(), DtaWriteError> {
        Ok(())
    }

    fn check_interrupt(&self) -> Result<(), DtaWriteError> {
        Ok(())
    }

    /// Append a contiguous range of complete, row-major observations encoded
    /// as final DTA bytes, including little-endian numerics and zero-padded
    /// fixed strings.
    ///
    /// The implementation must append exactly `(end - start) * row_width`
    /// bytes. The common writer checks that byte count but cannot validate the
    /// encoded cells. Returning `false` leaves `buffer` unchanged and asks the
    /// common writer to use the scalar methods below.
    #[doc(hidden)]
    fn append_observation_rows(
        &self,
        _buffer: &mut Vec<u8>,
        _start: u64,
        _end: u64,
    ) -> Result<bool, DtaWriteError> {
        Ok(false)
    }

    fn raw_numeric_value(
        &self,
        _column: usize,
        _row: u64,
    ) -> Result<Option<DtaWriteRawNumericValue>, DtaWriteError> {
        Ok(None)
    }

    fn numeric_value(&self, column: usize, row: u64)
        -> Result<DtaWriteNumericValue, DtaWriteError>;

    fn string_id(&self, _column: usize, _row: u64) -> Result<Option<u64>, DtaWriteError> {
        Ok(None)
    }

    fn string_value(&self, column: usize, row: u64) -> Result<Cow<'_, str>, DtaWriteError>;
}

#[derive(Clone, Copy)]
struct ValueLabelTableRef<'a> {
    name: &'a str,
    entries: &'a [DtaWriteValueLabel<'a>],
}

trait DtaWriteValueLabelSource {
    fn value_label_table(&self, _column: usize) -> Option<ValueLabelTableRef<'_>> {
        None
    }
}

impl DtaWriteValueLabelSource for () {}

#[cfg(feature = "r-adapter-internal")]
#[doc(hidden)]
pub struct DtaWriteValueLabelTable<'a> {
    name: &'a str,
    entries: &'a [DtaWriteValueLabel<'a>],
}

#[cfg(feature = "r-adapter-internal")]
impl<'a> DtaWriteValueLabelTable<'a> {
    #[doc(hidden)]
    pub fn new(name: &'a str, entries: &'a [DtaWriteValueLabel<'a>]) -> Self {
        Self { name, entries }
    }
}

#[cfg(feature = "r-adapter-internal")]
#[doc(hidden)]
pub struct DtaWriteValueLabelRegistry<'a> {
    tables: &'a [DtaWriteValueLabelTable<'a>],
    indices: &'a [Option<usize>],
}

#[cfg(feature = "r-adapter-internal")]
impl<'a> DtaWriteValueLabelRegistry<'a> {
    #[doc(hidden)]
    pub fn new(tables: &'a [DtaWriteValueLabelTable<'a>], indices: &'a [Option<usize>]) -> Self {
        Self { tables, indices }
    }
}

#[cfg(feature = "r-adapter-internal")]
impl DtaWriteValueLabelSource for DtaWriteValueLabelRegistry<'_> {
    fn value_label_table(&self, column: usize) -> Option<ValueLabelTableRef<'_>> {
        let table_index = self.indices.get(column).copied().flatten()?;
        self.tables
            .get(table_index)
            .map(|table| ValueLabelTableRef {
                name: table.name,
                entries: table.entries,
            })
    }
}

/// Borrowed or on-demand values for one output variable.
pub enum DtaWriteColumnValues<'a> {
    Numeric(&'a [DtaWriteNumericValue]),
    Strings(&'a [String]),
    Source(&'a dyn DtaWriteColumnSource),
}

impl std::fmt::Debug for DtaWriteColumnValues<'_> {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Numeric(values) => formatter
                .debug_tuple("Numeric")
                .field(&values.len())
                .finish(),
            Self::Strings(values) => formatter
                .debug_tuple("Strings")
                .field(&values.len())
                .finish(),
            Self::Source(_) => formatter.write_str("Source(..)"),
        }
    }
}

impl DtaWriteColumnValues<'_> {
    fn len(&self) -> Result<u64, DtaWriteError> {
        match self {
            Self::Numeric(values) => {
                u64::try_from(values.len()).map_err(|_| DtaWriteError::Overflow("column length"))
            }
            Self::Strings(values) => {
                u64::try_from(values.len()).map_err(|_| DtaWriteError::Overflow("column length"))
            }
            Self::Source(source) => Ok(source.len()),
        }
    }

    fn numeric_value(&self, column: &str, row: u64) -> Result<DtaWriteNumericValue, DtaWriteError> {
        match self {
            Self::Numeric(values) => values
                .get(usize::try_from(row).map_err(|_| DtaWriteError::Overflow("row index"))?)
                .copied()
                .ok_or_else(|| DtaWriteError::Source {
                    column: column.into(),
                    row,
                    message: "row is outside the numeric source".into(),
                }),
            Self::Strings(_) => Err(DtaWriteError::Source {
                column: column.into(),
                row,
                message: "string source used for a numeric variable".into(),
            }),
            Self::Source(source) => {
                source
                    .numeric_value(row)
                    .map_err(|message| DtaWriteError::Source {
                        column: column.into(),
                        row,
                        message,
                    })
            }
        }
    }

    fn string_value<'a>(&'a self, column: &str, row: u64) -> Result<Cow<'a, str>, DtaWriteError> {
        match self {
            Self::Strings(values) => values
                .get(usize::try_from(row).map_err(|_| DtaWriteError::Overflow("row index"))?)
                .map(|value| Cow::Borrowed(value.as_str()))
                .ok_or_else(|| DtaWriteError::Source {
                    column: column.into(),
                    row,
                    message: "row is outside the string source".into(),
                }),
            Self::Numeric(_) => Err(DtaWriteError::Source {
                column: column.into(),
                row,
                message: "numeric source used for a string variable".into(),
            }),
            Self::Source(source) => {
                source
                    .string_value(row)
                    .map_err(|message| DtaWriteError::Source {
                        column: column.into(),
                        row,
                        message,
                    })
            }
        }
    }
}

/// Metadata and values for one output variable.
#[derive(Debug)]
pub struct DtaWriteColumn<'a> {
    pub name: Cow<'a, str>,
    pub dta_type: DtaType,
    pub format: Cow<'a, str>,
    pub label: Cow<'a, str>,
    /// Whether the variable is associated with a value-label table. This is
    /// distinct from the number of entries because Stata permits empty tables.
    pub has_value_labels: bool,
    pub value_labels: Vec<DtaWriteValueLabel<'a>>,
    pub notes: Vec<DtaWriteNote<'a>>,
    pub characteristics: Vec<DtaWriteCharacteristic<'a>>,
    pub values: DtaWriteColumnValues<'a>,
}

/// Purpose-built dataset model consumed by the streaming writer.
#[derive(Debug)]
pub struct DtaWriteData<'a> {
    pub dataset_label: Cow<'a, str>,
    pub notes: Vec<DtaWriteNote<'a>>,
    pub characteristics: Vec<DtaWriteCharacteristic<'a>>,
    pub columns: Vec<DtaWriteColumn<'a>>,
}

struct ColumnObservationSource<'data, 'values> {
    data: &'data DtaWriteData<'values>,
}

impl DtaWriteObservationSource for ColumnObservationSource<'_, '_> {
    fn numeric_value(
        &self,
        column_index: usize,
        row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        let column = &self.data.columns[column_index];
        column.values.numeric_value(&column.name, row)
    }

    fn string_value(&self, column_index: usize, row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        let column = &self.data.columns[column_index];
        column.values.string_value(&column.name, row)
    }
}

/// Options shared by native adapters.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DtaWriteOptions {
    /// DTA timestamp text, normally `DD Mon YYYY HH:MM`. `None` writes an
    /// empty timestamp; adapters can inject a deterministic value in tests.
    pub timestamp: Option<String>,
}

/// Facts about a completed write.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DtaWriteSummary {
    pub format_version: FormatVersion,
    pub bytes_written: u64,
}

/// Errors raised before or during DTA serialization.
#[derive(Debug, thiserror::Error)]
pub enum DtaWriteError {
    #[error("a Stata dataset must contain at least one variable")]
    NoVariables,
    #[error("{count} variables exceeds the supported maximum of {maximum}")]
    TooManyVariables { count: usize, maximum: usize },
    #[error("invalid dataset metadata: {0}")]
    InvalidDatasetMetadata(String),
    #[error("invalid variable {column:?}: {message}")]
    InvalidVariable { column: String, message: String },
    #[error("invalid value in variable {column:?} at row {row}: {message}")]
    InvalidValue {
        column: String,
        row: u64,
        message: String,
    },
    #[error("invalid value labels for variable {column:?}: {message}")]
    InvalidValueLabels { column: String, message: String },
    #[error("column source failed for variable {column:?} at row {row}: {message}")]
    Source {
        column: String,
        row: u64,
        message: String,
    },
    #[error("write interrupted")]
    Interrupted,
    #[error(
        "DTA output destination must be empty, positioned at byte zero, and honor seeked writes"
    )]
    InvalidDestination,
    #[error("integer overflow while calculating {0}")]
    Overflow(&'static str),
    #[error("I/O error while writing DTA output: {0}")]
    Io(#[from] std::io::Error),
}

fn reserved_dta_name(name: &str) -> bool {
    matches!(
        name,
        "alias"
            | "_all"
            | "_b"
            | "_coef"
            | "_cons"
            | "_n"
            | "_N"
            | "_pi"
            | "_pred"
            | "_r_b"
            | "_rc"
            | "_r_ci"
            | "_r_cri"
            | "_r_crlb"
            | "_r_crub"
            | "_r_df"
            | "_r_lb"
            | "_r_p"
            | "_r_se"
            | "_r_ub"
            | "_r_z"
            | "_r_z_abs"
            | "_se"
            | "_skip"
            | "_weight"
            | "byte"
            | "double"
            | "float"
            | "int"
            | "long"
            | "in"
            | "if"
            | "strL"
            | "using"
            | "with"
    ) || name.strip_prefix("str").is_some_and(|suffix| {
        suffix
            .as_bytes()
            .first()
            .is_some_and(|byte| matches!(*byte, b'1'..=b'9'))
            && suffix.bytes().all(|byte| byte.is_ascii_digit())
    })
}

fn valid_dta_name(name: &str) -> bool {
    valid_dta_name_syntax(name, 32)
        && name.len() < WRITE_FIELD_WIDTHS.varname
        && !reserved_dta_name(name)
}

fn format_number(value: &str) -> Option<usize> {
    (!value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit()))
        .then(|| value.parse().ok())
        .flatten()
}

fn valid_dta_decimal_format(format: &str) -> bool {
    if matches!(format, "%21x" | "%8H" | "%8L" | "%16H" | "%16L") {
        return true;
    }
    let Some(mut body) = format.strip_prefix('%') else {
        return false;
    };
    if let Some(unsigned) = body.strip_prefix('-') {
        body = unsigned;
    }
    let compact = body.ends_with('c');
    if compact {
        body = &body[..body.len() - 1];
    }
    let Some(kind) = body.as_bytes().last().copied() else {
        return false;
    };
    if !matches!(kind, b'e' | b'f' | b'g') || compact && kind == b'e' {
        return false;
    }
    body = &body[..body.len() - 1];
    let Some(separator) = body.find(['.', ',']) else {
        return false;
    };
    let Some(width) = format_number(&body[..separator]) else {
        return false;
    };
    let Some(decimals) = format_number(&body[separator + 1..]) else {
        return false;
    };
    (1..=2045).contains(&width) && decimals < width
}

fn valid_dta_string_format(format: &str) -> bool {
    let Some(mut body) = format.strip_prefix('%') else {
        return false;
    };
    if let Some(unsigned) = body.strip_prefix('-') {
        body = unsigned;
    }
    let Some(width) = body.strip_suffix('s').and_then(format_number) else {
        return false;
    };
    (1..=2045).contains(&width)
}

fn valid_dta_datetime_details(mut details: &str, tokens: &[&str]) -> bool {
    while !details.is_empty() {
        if let Some(escaped) = details.strip_prefix('!') {
            let Some(character) = escaped.chars().next() else {
                return false;
            };
            details = &escaped[character.len_utf8()..];
            continue;
        }
        if let Some(token) = tokens.iter().find(|token| details.starts_with(**token)) {
            details = &details[token.len()..];
            continue;
        }
        let character = details.chars().next().expect("details is nonempty");
        if !matches!(
            character,
            '.' | ',' | ':' | '-' | '_' | ' ' | '/' | '\\' | '+'
        ) {
            return false;
        }
        details = &details[character.len_utf8()..];
    }
    true
}

fn valid_dta_calendar_format(format: &str) -> bool {
    const TOKENS: &[&str] = &[
        "DAYNAME", "Dayname", "Month", "month", "A.M.", "a.m.", ".sss", "Mon", "mon", "JJJ", "jjj",
        "Day", "day", ".ss", "CC", "cc", "YY", "yy", "NN", "nn", "DD", "dd", "Da", "da", "HH",
        "Hh", "hH", "hh", "MM", "mm", "SS", "ss", "AM", "am", "WW", "ww", ".s", "C", "c", "Y", "y",
        "M", "m", "N", "n", "J", "j", "D", "d", "W", "w", "q", "h",
    ];

    let Some(mut body) = format.strip_prefix('%') else {
        return false;
    };
    if let Some(unsigned) = body.strip_prefix('-') {
        body = unsigned;
    }
    let (kind, details) = if let Some(details) = body.strip_prefix('d') {
        ('d', details)
    } else if let Some(body) = body.strip_prefix('t') {
        let Some(kind) = body.chars().next() else {
            return false;
        };
        (kind, &body[kind.len_utf8()..])
    } else {
        return false;
    };

    match kind {
        'c' | 'C' | 'd' | 'w' | 'm' | 'q' | 'h' | 'y' => {
            valid_dta_datetime_details(details, TOKENS)
        }
        'g' => details.is_empty(),
        'b' => {
            let (calendar, details) = details
                .split_once(':')
                .map_or((details, None), |(calendar, details)| {
                    (calendar, Some(details))
                });
            if !valid_dta_name_syntax(calendar, 10) {
                return false;
            }
            details.is_none_or(|details| {
                details.is_empty() || valid_dta_datetime_details(details, TOKENS)
            })
        }
        _ => false,
    }
}

fn valid_dta_format(dta_type: &DtaType, format: &str) -> bool {
    match dta_type {
        DtaType::FixedString(_) | DtaType::StrL => valid_dta_string_format(format),
        DtaType::Byte | DtaType::Int | DtaType::Long | DtaType::Float | DtaType::Double => {
            valid_dta_decimal_format(format) || valid_dta_calendar_format(format)
        }
    }
}

fn validate_text_field(
    value: &str,
    maximum_characters: usize,
    maximum_bytes: usize,
    description: &str,
) -> Result<(), String> {
    if value.contains('\0') {
        return Err(format!("{description} contains a NUL character"));
    }
    let character_count = value.chars().count();
    if character_count > maximum_characters {
        return Err(format!(
            "{description} has {character_count} Unicode characters; maximum is {maximum_characters}"
        ));
    }
    if value.len() > maximum_bytes {
        return Err(format!(
            "{description} has {} UTF-8 bytes; maximum is {maximum_bytes}",
            value.len()
        ));
    }
    Ok(())
}

fn label_raw_value(value: DtaWriteLabelValue) -> Result<i32, &'static str> {
    match value {
        DtaWriteLabelValue::Integer(value)
            if dta_write_numeric_value_is_representable(&DtaType::Long, f64::from(value)) =>
        {
            Ok(value)
        }
        DtaWriteLabelValue::Integer(_) => Err("integer key is outside Stata's long range"),
        DtaWriteLabelValue::Missing(MissingTag::System) => {
            Err("system missing cannot have a value label")
        }
        DtaWriteLabelValue::Missing(tag) => Ok(tag.long_value()),
    }
}

#[doc(hidden)]
pub fn dta_write_numeric_value_is_representable(dta_type: &DtaType, value: f64) -> bool {
    value.is_finite()
        && match dta_type {
            DtaType::Byte => {
                value.fract() == 0.0
                    && (f64::from(-MissingTag::Z.byte_value())
                        ..=f64::from(MissingTag::System.byte_value() - 1))
                        .contains(&value)
            }
            DtaType::Int => {
                value.fract() == 0.0
                    && (f64::from(-MissingTag::Z.int_value())
                        ..=f64::from(MissingTag::System.int_value() - 1))
                        .contains(&value)
            }
            DtaType::Long => {
                value.fract() == 0.0
                    && (f64::from(-MissingTag::Z.long_value())
                        ..=f64::from(MissingTag::System.long_value() - 1))
                        .contains(&value)
            }
            DtaType::Float => value.abs() <= f64::from(f32::from_bits(FLOAT_MISSING_DOT_BITS - 1)),
            DtaType::Double => value.abs() <= f64::from_bits(DOUBLE_MISSING_DOT_BITS - 1),
            DtaType::FixedString(_) | DtaType::StrL => false,
        }
}

fn validate_numeric_value(
    column: &DtaWriteColumn<'_>,
    row: u64,
    value: DtaWriteNumericValue,
) -> Result<(), DtaWriteError> {
    let DtaWriteNumericValue::Value(value) = value else {
        return Ok(());
    };
    if !value.is_finite() {
        return Err(DtaWriteError::InvalidValue {
            column: column.name.to_string(),
            row,
            message: "observed numeric value is not finite".into(),
        });
    }
    if !dta_write_numeric_value_is_representable(&column.dta_type, value) {
        return Err(DtaWriteError::InvalidValue {
            column: column.name.to_string(),
            row,
            message: format!("{value} is not representable as {}", column.dta_type),
        });
    }
    Ok(())
}

fn validate_value_label_entry_count(
    column_name: &str,
    entries: &[DtaWriteValueLabel<'_>],
) -> Result<(), DtaWriteError> {
    if entries.len() > MAX_VALUE_LABEL_ENTRIES {
        return Err(DtaWriteError::InvalidValueLabels {
            column: column_name.to_owned(),
            message: format!(
                "table has {} entries; maximum is {MAX_VALUE_LABEL_ENTRIES}",
                entries.len()
            ),
        });
    }
    Ok(())
}

fn validate_value_label_entries(
    column_name: &str,
    entries: &[DtaWriteValueLabel<'_>],
) -> Result<(), DtaWriteError> {
    validate_value_label_entry_count(column_name, entries)?;
    for entry in entries {
        label_raw_value(entry.value).map_err(|message| DtaWriteError::InvalidValueLabels {
            column: column_name.to_owned(),
            message: message.into(),
        })?;
        if entry.label.contains('\0') || entry.label.len() > MAX_VALUE_LABEL_TEXT_BYTES {
            return Err(DtaWriteError::InvalidValueLabels {
                column: column_name.to_owned(),
                message: format!(
                    "label text must contain at most {MAX_VALUE_LABEL_TEXT_BYTES} UTF-8 bytes and no NUL"
                ),
            });
        }
    }
    Ok(())
}

fn validate_structure(
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
) -> Result<u64, DtaWriteError> {
    if data.columns.is_empty() {
        return Err(DtaWriteError::NoVariables);
    }
    if data.columns.len() > MAX_VARIABLES {
        return Err(DtaWriteError::TooManyVariables {
            count: data.columns.len(),
            maximum: MAX_VARIABLES,
        });
    }
    let row_count = data.columns[0].values.len()?;
    validate_text_field(&data.dataset_label, 80, 320, "dataset label")
        .map_err(DtaWriteError::InvalidDatasetMetadata)?;
    validate_notes(&data.notes)
        .map_err(|message| DtaWriteError::InvalidDatasetMetadata(format!("dataset {message}")))?;
    validate_characteristics(&data.characteristics)
        .map_err(|message| DtaWriteError::InvalidDatasetMetadata(format!("dataset {message}")))?;
    if let Some(timestamp) = &options.timestamp {
        if timestamp.contains('\0') || timestamp.len() > u8::MAX as usize {
            return Err(DtaWriteError::InvalidDatasetMetadata(
                "timestamp must contain at most 255 bytes and no NUL".into(),
            ));
        }
    }

    let mut names = HashSet::with_capacity(data.columns.len());
    for column in &data.columns {
        if column.name == "_dta" && (!column.notes.is_empty() || !column.characteristics.is_empty())
        {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.to_string(),
                message: "notes and characteristics on a variable named `_dta` cannot be represented in DTA"
                    .into(),
            });
        }
        if !column.notes.is_empty() {
            validate_notes(&column.notes).map_err(|message| DtaWriteError::InvalidVariable {
                column: column.name.to_string(),
                message,
            })?;
        }
        if !column.characteristics.is_empty() {
            validate_characteristics(&column.characteristics).map_err(|message| {
                DtaWriteError::InvalidVariable {
                    column: column.name.to_string(),
                    message,
                }
            })?;
        }
        if !valid_dta_name(&column.name) {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.to_string(),
                message: "name must be a valid Stata name of at most 32 Unicode characters".into(),
            });
        }
        if !names.insert(column.name.as_ref()) {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.to_string(),
                message: "variable names must be unique".into(),
            });
        }
        if matches!(column.dta_type, DtaType::FixedString(0 | 2046..=u16::MAX)) {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.to_string(),
                message: "fixed-string width must be between 1 and 2045 bytes".into(),
            });
        }
        if column.format.is_empty()
            || column.format.contains('\0')
            || column.format.len() >= WRITE_FIELD_WIDTHS.format
        {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.to_string(),
                message: "display format must contain 1 to 56 UTF-8 bytes and no NUL".into(),
            });
        }
        if !valid_dta_format(&column.dta_type, &column.format) {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.to_string(),
                message: format!(
                    "display format {:?} is malformed or incompatible with {} storage",
                    column.format, column.dta_type
                ),
            });
        }
        validate_text_field(
            &column.label,
            80,
            WRITE_FIELD_WIDTHS.variable_label - 1,
            "variable label",
        )
        .map_err(|message| DtaWriteError::InvalidVariable {
            column: column.name.to_string(),
            message,
        })?;
        let column_row_count = column.values.len()?;
        if column_row_count != row_count {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.to_string(),
                message: format!("column has {column_row_count} rows but dataset has {row_count}"),
            });
        }
        // Keep the public writer's established precedence: an oversized table
        // wins before attachment/storage errors, while entry errors follow them.
        validate_value_label_entry_count(&column.name, &column.value_labels)?;
        if !column.has_value_labels && !column.value_labels.is_empty() {
            return Err(DtaWriteError::InvalidValueLabels {
                column: column.name.to_string(),
                message: "entries require an associated value-label table".into(),
            });
        }
        if column.has_value_labels
            && matches!(column.dta_type, DtaType::FixedString(_) | DtaType::StrL)
        {
            return Err(DtaWriteError::InvalidValueLabels {
                column: column.name.to_string(),
                message: "string variables cannot have numeric value labels".into(),
            });
        }
        validate_value_label_entries(&column.name, &column.value_labels)?;
    }
    Ok(row_count)
}

fn validate_observations(data: &DtaWriteData<'_>, row_count: u64) -> Result<(), DtaWriteError> {
    for column in &data.columns {
        for row in 0..row_count {
            match column.dta_type {
                DtaType::Byte | DtaType::Int | DtaType::Long | DtaType::Float | DtaType::Double => {
                    validate_numeric_value(
                        column,
                        row,
                        column.values.numeric_value(&column.name, row)?,
                    )?;
                }
                DtaType::FixedString(width) => {
                    let value = column.values.string_value(&column.name, row)?;
                    if value.contains('\0') || value.len() > usize::from(width) {
                        return Err(DtaWriteError::InvalidValue {
                            column: column.name.to_string(),
                            row,
                            message: format!(
                                "string must contain at most {width} UTF-8 bytes and no NUL"
                            ),
                        });
                    }
                }
                DtaType::StrL => {}
            }
        }
    }
    Ok(())
}

fn validate_data(data: &DtaWriteData<'_>, options: &DtaWriteOptions) -> Result<u64, DtaWriteError> {
    let row_count = validate_structure(data, options)?;
    validate_observations(data, row_count)?;
    Ok(row_count)
}

fn output_value_label_table<'a, S: DtaWriteValueLabelSource + ?Sized>(
    data: &'a DtaWriteData<'_>,
    source: &'a S,
    column_index: usize,
) -> Option<ValueLabelTableRef<'a>> {
    let column = &data.columns[column_index];
    if !column.has_value_labels {
        return None;
    }
    Some(
        source
            .value_label_table(column_index)
            .unwrap_or(ValueLabelTableRef {
                name: column.name.as_ref(),
                entries: &column.value_labels,
            }),
    )
}

#[cfg(feature = "r-adapter-internal")]
fn validate_value_label_names<S: DtaWriteValueLabelSource + ?Sized>(
    data: &DtaWriteData<'_>,
    source: &S,
) -> Result<(), DtaWriteError> {
    let mut tables: HashMap<&str, &[DtaWriteValueLabel<'_>]> = HashMap::new();
    for (column_index, column) in data.columns.iter().enumerate() {
        let Some(table) = output_value_label_table(data, source, column_index) else {
            continue;
        };
        if !valid_dta_name(table.name) {
            return Err(DtaWriteError::InvalidValueLabels {
                column: column.name.to_string(),
                message: format!(
                    "table name {:?} must be a valid Stata name of at most 32 Unicode characters",
                    table.name
                ),
            });
        }
        match tables.entry(table.name) {
            Entry::Vacant(entry) => {
                validate_value_label_entries(&column.name, table.entries)?;
                entry.insert(table.entries);
            }
            Entry::Occupied(entry)
                if (entry.get().len() == table.entries.len()
                    && (std::ptr::eq(entry.get().as_ptr(), table.entries.as_ptr())
                        || *entry.get() == table.entries)) => {}
            Entry::Occupied(_) => {
                return Err(DtaWriteError::InvalidValueLabels {
                    column: column.name.to_string(),
                    message: format!(
                        "table name {:?} is associated with different mappings",
                        table.name
                    ),
                });
            }
        }
    }
    Ok(())
}

fn position<W: Seek>(writer: &mut W) -> Result<u64, DtaWriteError> {
    Ok(writer.stream_position()?)
}

fn validate_destination<W: Seek>(writer: &mut W) -> Result<(), DtaWriteError> {
    if position(writer)? != 0 {
        return Err(DtaWriteError::InvalidDestination);
    }
    let length = writer.seek(SeekFrom::End(0))?;
    writer.seek(SeekFrom::Start(0))?;
    if length != 0 {
        return Err(DtaWriteError::InvalidDestination);
    }
    Ok(())
}

fn write_tag<W: Write>(writer: &mut W, tag: &[u8]) -> Result<(), DtaWriteError> {
    writer.write_all(tag)?;
    Ok(())
}

fn write_zeros<W: Write>(writer: &mut W, mut length: usize) -> Result<(), DtaWriteError> {
    while length >= ZERO_BLOCK.len() {
        writer.write_all(&ZERO_BLOCK)?;
        length -= ZERO_BLOCK.len();
    }
    writer.write_all(&ZERO_BLOCK[..length])?;
    Ok(())
}

fn write_field<W: Write>(writer: &mut W, value: &str, width: usize) -> Result<(), DtaWriteError> {
    writer.write_all(value.as_bytes())?;
    let padding = width
        .checked_sub(value.len())
        .ok_or(DtaWriteError::Overflow("fixed text field"))?;
    write_zeros(writer, padding)
}

fn write_characteristic<W: Write>(
    writer: &mut W,
    target: &str,
    name: &str,
    value: &str,
) -> Result<usize, DtaWriteError> {
    write_tag(writer, b"<ch>")?;
    let payload_length = WRITE_FIELD_WIDTHS
        .varname
        .checked_mul(2)
        .and_then(|length| length.checked_add(value.len()))
        .and_then(|length| length.checked_add(1))
        .ok_or(DtaWriteError::Overflow("characteristic"))?;
    writer.write_all(
        &u32::try_from(payload_length)
            .map_err(|_| DtaWriteError::Overflow("characteristic"))?
            .to_le_bytes(),
    )?;
    write_field(writer, target, WRITE_FIELD_WIDTHS.varname)?;
    write_field(writer, name, WRITE_FIELD_WIDTHS.varname)?;
    writer.write_all(value.as_bytes())?;
    writer.write_all(&[0])?;
    write_tag(writer, b"</ch>")?;
    payload_length
        .checked_add(b"<ch>".len() + 4 + b"</ch>".len())
        .ok_or(DtaWriteError::Overflow("characteristic"))
}

fn validate_notes(notes: &[DtaWriteNote<'_>]) -> Result<(), String> {
    if notes.len() > MAX_NOTES {
        return Err(format!("has {} notes; maximum is {MAX_NOTES}", notes.len()));
    }
    let mut numbers = HashSet::with_capacity(notes.len());
    for (index, note) in notes.iter().enumerate() {
        let number = note.resolved_number(index);
        if !(1..=MAX_NOTES as u32).contains(&number) || !numbers.insert(number) {
            return Err(format!("has an invalid or duplicate note number {number}"));
        }
        if !valid_note(number, &note.text) {
            return Err(format!(
                "note {number} must contain no NUL and have a valid bounded value"
            ));
        }
    }
    Ok(())
}

fn validate_characteristics(characteristics: &[DtaWriteCharacteristic<'_>]) -> Result<(), String> {
    let mut names = HashSet::with_capacity(characteristics.len());
    for characteristic in characteristics {
        if !valid_characteristic(&characteristic.name, &characteristic.value)
            || !names.insert(characteristic.name.as_ref())
        {
            return Err(format!(
                "has invalid, duplicate, over-limit, or reserved characteristic `{}`",
                characteristic.name
            ));
        }
    }
    Ok(())
}

fn write_header<W: Write>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
    version: FormatVersion,
    row_count: u64,
) -> Result<(), DtaWriteError> {
    write!(
        writer,
        "<stata_dta><header><release>{}</release><byteorder>LSF</byteorder><K>",
        version.as_u16()
    )?;
    let variable_count = (data.columns.len() as u32).to_le_bytes();
    let variable_count_width = if version == FormatVersion::V119 { 4 } else { 2 };
    writer.write_all(&variable_count[..variable_count_width])?;
    write_tag(writer, b"</K><N>")?;
    writer.write_all(&row_count.to_le_bytes())?;
    write_tag(writer, b"</N><label>")?;
    writer.write_all(
        &u16::try_from(data.dataset_label.len())
            .map_err(|_| DtaWriteError::Overflow("dataset label length"))?
            .to_le_bytes(),
    )?;
    writer.write_all(data.dataset_label.as_bytes())?;
    write_tag(writer, b"</label><timestamp>")?;
    let timestamp = options.timestamp.as_deref().unwrap_or("");
    writer
        .write_all(&[u8::try_from(timestamp.len())
            .map_err(|_| DtaWriteError::Overflow("timestamp length"))?])?;
    writer.write_all(timestamp.as_bytes())?;
    write_tag(writer, b"</timestamp></header>")?;
    Ok(())
}

fn write_metadata_sections<W, S, L>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    version: FormatVersion,
    offsets: &mut SectionOffsets,
    observation_source: &S,
    value_label_source: &L,
) -> Result<(), DtaWriteError>
where
    W: Write + Seek,
    S: DtaWriteObservationSource + ?Sized,
    L: DtaWriteValueLabelSource + ?Sized,
{
    offsets.variable_types = position(writer)?;
    write_tag(writer, b"<variable_types>")?;
    for column in &data.columns {
        writer.write_all(&column.dta_type.modern_code().to_le_bytes())?;
    }
    write_tag(writer, b"</variable_types>")?;
    observation_source.check_interrupt()?;

    offsets.varnames = position(writer)?;
    write_tag(writer, b"<varnames>")?;
    for column in &data.columns {
        write_field(writer, &column.name, WRITE_FIELD_WIDTHS.varname)?;
    }
    write_tag(writer, b"</varnames>")?;
    observation_source.check_interrupt()?;

    offsets.sortlist = position(writer)?;
    write_tag(writer, b"<sortlist>")?;
    let zero_width = if version == FormatVersion::V119 { 4 } else { 2 };
    let sort_bytes = data
        .columns
        .len()
        .checked_add(1)
        .and_then(|count| count.checked_mul(zero_width))
        .ok_or(DtaWriteError::Overflow("sortlist"))?;
    write_zeros(writer, sort_bytes)?;
    write_tag(writer, b"</sortlist>")?;
    observation_source.check_interrupt()?;

    offsets.formats = position(writer)?;
    write_tag(writer, b"<formats>")?;
    for column in &data.columns {
        write_field(writer, &column.format, WRITE_FIELD_WIDTHS.format)?;
    }
    write_tag(writer, b"</formats>")?;
    observation_source.check_interrupt()?;

    offsets.value_label_names = position(writer)?;
    write_tag(writer, b"<value_label_names>")?;
    for column_index in 0..data.columns.len() {
        let name = output_value_label_table(data, value_label_source, column_index)
            .map_or("", |table| table.name);
        write_field(writer, name, WRITE_FIELD_WIDTHS.value_label_name)?;
    }
    write_tag(writer, b"</value_label_names>")?;
    observation_source.check_interrupt()?;

    offsets.variable_labels = position(writer)?;
    write_tag(writer, b"<variable_labels>")?;
    for column in &data.columns {
        write_field(writer, &column.label, WRITE_FIELD_WIDTHS.variable_label)?;
    }
    write_tag(writer, b"</variable_labels>")?;
    observation_source.check_interrupt()?;

    offsets.characteristics = position(writer)?;
    write_tag(writer, b"<characteristics>")?;
    let mut bytes_since_interrupt = 0_usize;
    let mut records_since_interrupt = 0_usize;
    let mut write_scope = |writer: &mut W,
                           target: &str,
                           notes: &[DtaWriteNote<'_>],
                           characteristics: &[DtaWriteCharacteristic<'_>]|
     -> Result<(), DtaWriteError> {
        let mut record_written = |bytes: usize| -> Result<(), DtaWriteError> {
            bytes_since_interrupt = bytes_since_interrupt.saturating_add(bytes);
            records_since_interrupt = records_since_interrupt.saturating_add(1);
            if bytes_since_interrupt >= WRITE_INTERRUPT_BYTES
                || records_since_interrupt >= WRITE_INTERRUPT_RECORDS
            {
                observation_source.check_interrupt()?;
                bytes_since_interrupt = 0;
                records_since_interrupt = 0;
            }
            Ok(())
        };
        if let Some(maximum) = notes
            .iter()
            .enumerate()
            .map(|(index, note)| note.resolved_number(index))
            .max()
        {
            let maximum = maximum.to_string();
            record_written(write_characteristic(writer, target, "note0", &maximum)?)?;
        }
        for (index, note) in notes.iter().enumerate() {
            let name = format!("note{}", note.resolved_number(index));
            record_written(write_characteristic(writer, target, &name, &note.text)?)?;
        }
        for characteristic in characteristics {
            record_written(write_characteristic(
                writer,
                target,
                &characteristic.name,
                &characteristic.value,
            )?)?;
        }
        Ok(())
    };
    write_scope(writer, "_dta", &data.notes, &data.characteristics)?;
    for column in &data.columns {
        write_scope(writer, &column.name, &column.notes, &column.characteristics)?;
    }
    write_tag(writer, b"</characteristics>")?;
    observation_source.check_interrupt()?;
    Ok(())
}

fn raw_numeric_matches_type(value: DtaWriteRawNumericValue, dta_type: &DtaType) -> bool {
    matches!(
        (value, dta_type),
        (DtaWriteRawNumericValue::Byte(_), DtaType::Byte)
            | (DtaWriteRawNumericValue::Int(_), DtaType::Int)
            | (DtaWriteRawNumericValue::Long(_), DtaType::Long)
            | (DtaWriteRawNumericValue::Float(_), DtaType::Float)
            | (DtaWriteRawNumericValue::Double(_), DtaType::Double)
    )
}

fn append_raw_numeric(buffer: &mut Vec<u8>, value: DtaWriteRawNumericValue) {
    match value {
        DtaWriteRawNumericValue::Byte(value) => buffer.push(value as u8),
        DtaWriteRawNumericValue::Int(value) => buffer.extend_from_slice(&value.to_le_bytes()),
        DtaWriteRawNumericValue::Long(value) => buffer.extend_from_slice(&value.to_le_bytes()),
        DtaWriteRawNumericValue::Float(value) => {
            buffer.extend_from_slice(&value.to_bits().to_le_bytes())
        }
        DtaWriteRawNumericValue::Double(value) => {
            buffer.extend_from_slice(&value.to_bits().to_le_bytes())
        }
    }
}

#[doc(hidden)]
/// Encode one validated numeric value in the requested numeric DTA storage.
///
/// `dta_type` must be `Byte`, `Int`, `Long`, `Float`, or `Double`. Validation
/// must already have established that nonmissing values fit that storage.
pub fn encode_numeric(dta_type: &DtaType, value: DtaWriteNumericValue) -> DtaWriteRawNumericValue {
    match (dta_type, value) {
        (DtaType::Byte, DtaWriteNumericValue::Value(value)) => {
            DtaWriteRawNumericValue::Byte(value as i8)
        }
        (DtaType::Byte, DtaWriteNumericValue::Missing(tag)) => {
            DtaWriteRawNumericValue::Byte(tag.byte_value())
        }
        (DtaType::Int, DtaWriteNumericValue::Value(value)) => {
            DtaWriteRawNumericValue::Int(value as i16)
        }
        (DtaType::Int, DtaWriteNumericValue::Missing(tag)) => {
            DtaWriteRawNumericValue::Int(tag.int_value())
        }
        (DtaType::Long, DtaWriteNumericValue::Value(value)) => {
            DtaWriteRawNumericValue::Long(value as i32)
        }
        (DtaType::Long, DtaWriteNumericValue::Missing(tag)) => {
            DtaWriteRawNumericValue::Long(tag.long_value())
        }
        (DtaType::Float, DtaWriteNumericValue::Value(value)) => {
            DtaWriteRawNumericValue::Float(value as f32)
        }
        (DtaType::Float, DtaWriteNumericValue::Missing(tag)) => {
            DtaWriteRawNumericValue::Float(f32::from_bits(tag.float_bits()))
        }
        (DtaType::Double, DtaWriteNumericValue::Value(value)) => {
            DtaWriteRawNumericValue::Double(value)
        }
        (DtaType::Double, DtaWriteNumericValue::Missing(tag)) => {
            DtaWriteRawNumericValue::Double(f64::from_bits(tag.double_bits()))
        }
        _ => unreachable!("validated numeric storage type"),
    }
}

fn append_numeric(buffer: &mut Vec<u8>, dta_type: &DtaType, value: DtaWriteNumericValue) {
    append_raw_numeric(buffer, encode_numeric(dta_type, value));
}

#[derive(Debug)]
struct StrlColumnPlan {
    /// Stable source IDs mapped to their canonical source rows and GSO targets.
    ids: HashMap<u64, StrlIdTarget>,
    /// Content hashes mapped to candidate zero-based canonical observations.
    candidates: HashMap<u64, StrlHashCandidates>,
    /// One bit per row identifying values that require a canonical GSO record.
    canonical: Vec<u64>,
    /// Fingerprints of the values validated for canonical GSO records.
    canonical_fingerprints: HashMap<u64, StrlFingerprint>,
}

#[derive(Debug, Clone, Copy)]
struct StrlIdTarget {
    row: u64,
    target: u64,
    fingerprint: StrlFingerprint,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct StrlFingerprint {
    length: usize,
    hash: u64,
}

#[derive(Debug)]
enum StrlHashCandidates {
    One(u64),
    Multiple(Vec<u64>),
}

fn strl_values_equal<S: DtaWriteObservationSource + ?Sized>(
    source: &S,
    left: &str,
    right: &str,
) -> Result<bool, DtaWriteError> {
    if left.len() != right.len() {
        return Ok(false);
    }
    for (left_chunk, right_chunk) in left
        .as_bytes()
        .chunks(WRITE_INTERRUPT_BYTES)
        .zip(right.as_bytes().chunks(WRITE_INTERRUPT_BYTES))
    {
        if left_chunk != right_chunk {
            return Ok(false);
        }
        source.check_interrupt()?;
    }
    Ok(true)
}

impl StrlHashCandidates {
    fn matching_row<S: DtaWriteObservationSource + ?Sized>(
        &self,
        source: &S,
        column: usize,
        active_row: u64,
        value: &str,
    ) -> Result<Option<u64>, DtaWriteError> {
        let mut matched = None;
        let rows: &[u64] = match self {
            Self::One(row) => std::slice::from_ref(row),
            Self::Multiple(rows) => rows,
        };
        for &row in rows {
            source.begin_row(row)?;
            let equal = {
                let candidate = source.string_value(column, row)?;
                strl_values_equal(source, candidate.as_ref(), value)?
            };
            if equal {
                matched = Some(row);
                break;
            }
        }
        source.begin_row(active_row)?;
        Ok(matched)
    }
}

fn mark_canonical_strl(canonical: &mut [u64], row: u64) -> Result<(), DtaWriteError> {
    let word = usize::try_from(row / 64)
        .map_err(|_| DtaWriteError::Overflow("strL canonical row index"))?;
    canonical[word] |= 1_u64 << (row % 64);
    Ok(())
}

fn strl_fingerprint<S: DtaWriteObservationSource + ?Sized>(
    source: &S,
    value: &str,
) -> Result<StrlFingerprint, DtaWriteError> {
    let mut hasher = DefaultHasher::new();
    for chunk in value.as_bytes().chunks(WRITE_INTERRUPT_BYTES) {
        hasher.write(chunk);
        source.check_interrupt()?;
    }
    Ok(StrlFingerprint {
        length: value.len(),
        hash: hasher.finish(),
    })
}

fn validate_strl_value<S: DtaWriteObservationSource + ?Sized>(
    source: &S,
    column: &str,
    row: u64,
    value: &str,
) -> Result<(), DtaWriteError> {
    if value.len() > MAX_STRL_BYTES {
        return Err(DtaWriteError::InvalidValue {
            column: column.into(),
            row,
            message: format!(
                "strL has {} UTF-8 bytes; maximum is {MAX_STRL_BYTES}",
                value.len()
            ),
        });
    }
    for chunk in value.as_bytes().chunks(WRITE_INTERRUPT_BYTES) {
        if chunk.contains(&0) {
            return Err(DtaWriteError::InvalidValue {
                column: column.into(),
                row,
                message: "strL value contains a NUL character".into(),
            });
        }
        source.check_interrupt()?;
    }
    Ok(())
}

fn prepare_strls<S: DtaWriteObservationSource + ?Sized>(
    data: &DtaWriteData<'_>,
    source: &S,
    row_count: u64,
) -> Result<Vec<Option<Box<StrlColumnPlan>>>, DtaWriteError> {
    let mut plans = Vec::with_capacity(data.columns.len());
    for (column_index, column) in data.columns.iter().enumerate() {
        if column.dta_type != DtaType::StrL {
            plans.push(None);
            continue;
        }
        let canonical_words = usize::try_from(row_count.div_ceil(64))
            .map_err(|_| DtaWriteError::Overflow("strL canonical row index"))?;
        let mut canonical = Vec::new();
        canonical
            .try_reserve_exact(canonical_words)
            .map_err(|_| DtaWriteError::Overflow("strL canonical plan"))?;
        canonical.resize(canonical_words, 0);
        let mut ids = HashMap::<u64, StrlIdTarget>::new();
        let mut candidates = HashMap::<u64, StrlHashCandidates>::new();
        let mut canonical_fingerprints = HashMap::<u64, StrlFingerprint>::new();
        for row in 0..row_count {
            source.begin_row(row)?;
            if let Some(id) = source.string_id(column_index, row)? {
                let value = source.string_value(column_index, row)?;
                validate_strl_value(source, &column.name, row, value.as_ref())?;
                let fingerprint = strl_fingerprint(source, value.as_ref())?;
                if let Some(existing) = ids.get(&id).copied() {
                    if fingerprint != existing.fingerprint {
                        return Err(DtaWriteError::Source {
                            column: column.name.to_string(),
                            row,
                            message: "one string ID identified different strL values".into(),
                        });
                    }
                    let value = value.into_owned();
                    source.begin_row(existing.row)?;
                    let equal = {
                        let candidate = source.string_value(column_index, existing.row)?;
                        strl_values_equal(source, candidate.as_ref(), &value)?
                    };
                    if !equal {
                        return Err(DtaWriteError::Source {
                            column: column.name.to_string(),
                            row,
                            message: "one string ID identified different strL values".into(),
                        });
                    }
                } else {
                    let target = if value.is_empty() {
                        0
                    } else {
                        mark_canonical_strl(&mut canonical, row)?;
                        canonical_fingerprints.insert(row, fingerprint);
                        row.checked_add(1)
                            .ok_or(DtaWriteError::Overflow("strL observation pointer"))?
                    };
                    ids.insert(
                        id,
                        StrlIdTarget {
                            row,
                            target,
                            fingerprint,
                        },
                    );
                }
                continue;
            }

            let value = source.string_value(column_index, row)?;
            validate_strl_value(source, &column.name, row, value.as_ref())?;
            if value.is_empty() {
                continue;
            }
            let fingerprint = strl_fingerprint(source, value.as_ref())?;
            match candidates.entry(fingerprint.hash) {
                Entry::Vacant(entry) => {
                    entry.insert(StrlHashCandidates::One(row));
                    mark_canonical_strl(&mut canonical, row)?;
                    canonical_fingerprints.insert(row, fingerprint);
                }
                Entry::Occupied(mut entry) => {
                    let value = value.into_owned();
                    let matched = entry
                        .get()
                        .matching_row(source, column_index, row, &value)?
                        .is_some();
                    if !matched {
                        match entry.get_mut() {
                            StrlHashCandidates::One(candidate) => {
                                let first = *candidate;
                                *entry.get_mut() = StrlHashCandidates::Multiple(vec![first, row]);
                            }
                            StrlHashCandidates::Multiple(rows) => rows.push(row),
                        }
                        mark_canonical_strl(&mut canonical, row)?;
                        canonical_fingerprints.insert(row, fingerprint);
                    }
                }
            }
        }
        plans.push(Some(Box::new(StrlColumnPlan {
            ids,
            candidates,
            canonical,
            canonical_fingerprints,
        })));
    }
    Ok(plans)
}

fn strl_target<S: DtaWriteObservationSource + ?Sized>(
    source: &S,
    plan: &StrlColumnPlan,
    column: usize,
    column_name: &str,
    row: u64,
) -> Result<u64, DtaWriteError> {
    if let Some(id) = source.string_id(column, row)? {
        let target = plan
            .ids
            .get(&id)
            .copied()
            .ok_or_else(|| DtaWriteError::Source {
                column: column_name.into(),
                row,
                message: "string ID was absent from the validated strL plan".into(),
            })?;
        let value = source.string_value(column, row)?;
        validate_strl_value(source, column_name, row, value.as_ref())?;
        if strl_fingerprint(source, value.as_ref())? != target.fingerprint {
            return Err(DtaWriteError::Source {
                column: column_name.into(),
                row,
                message: "string ID changed value after strL planning".into(),
            });
        }
        return Ok(target.target);
    }

    let value = source.string_value(column, row)?;
    validate_strl_value(source, column_name, row, value.as_ref())?;
    if value.is_empty() {
        return Ok(0);
    }
    let fingerprint = strl_fingerprint(source, value.as_ref())?;
    let value = value.into_owned();
    let candidates =
        plan.candidates
            .get(&fingerprint.hash)
            .ok_or_else(|| DtaWriteError::Source {
                column: column_name.into(),
                row,
                message: "string value was absent from the validated strL plan".into(),
            })?;
    candidates
        .matching_row(source, column, row, &value)?
        .and_then(|candidate| candidate.checked_add(1))
        .ok_or_else(|| DtaWriteError::Source {
            column: column_name.into(),
            row,
            message: "string value was absent from the validated strL plan".into(),
        })
}

fn write_low_bytes<W: Write>(
    writer: &mut W,
    value: u64,
    width: usize,
    context: &'static str,
) -> Result<(), DtaWriteError> {
    if width < u64::BITS as usize / 8 && value >= 1_u64 << (width * 8) {
        return Err(DtaWriteError::Overflow(context));
    }
    let bytes = value.to_le_bytes();
    writer.write_all(&bytes[..width])?;
    Ok(())
}

fn write_strl_pointer<W: Write>(
    writer: &mut W,
    version: FormatVersion,
    variable: u32,
    observation: u64,
) -> Result<(), DtaWriteError> {
    let layout = crate::strl::pointer_layout(version);
    write_low_bytes(
        writer,
        u64::from(variable),
        layout.variable_width,
        "strL variable pointer",
    )?;
    write_low_bytes(
        writer,
        observation,
        layout.observation_width,
        "strL observation pointer",
    )
}

fn append_observation_value<S: DtaWriteObservationSource + ?Sized>(
    buffer: &mut Vec<u8>,
    data: &DtaWriteData<'_>,
    source: &S,
    version: FormatVersion,
    strls: &[Option<Box<StrlColumnPlan>>],
    column_index: usize,
    row: u64,
) -> Result<(), DtaWriteError> {
    let column = &data.columns[column_index];
    match column.dta_type {
        DtaType::Byte | DtaType::Int | DtaType::Long | DtaType::Float | DtaType::Double => {
            if let Some(value) = source.raw_numeric_value(column_index, row)? {
                if !raw_numeric_matches_type(value, &column.dta_type) {
                    return Err(DtaWriteError::Source {
                        column: column.name.to_string(),
                        row,
                        message: "raw numeric storage does not match the variable type".into(),
                    });
                }
                append_raw_numeric(buffer, value);
            } else {
                let value = source.numeric_value(column_index, row)?;
                validate_numeric_value(column, row, value)?;
                append_numeric(buffer, &column.dta_type, value);
            }
        }
        DtaType::FixedString(width) => {
            let value = source.string_value(column_index, row)?;
            if value.contains('\0') || value.len() > usize::from(width) {
                return Err(DtaWriteError::InvalidValue {
                    column: column.name.to_string(),
                    row,
                    message: format!("string must contain at most {width} UTF-8 bytes and no NUL"),
                });
            }
            buffer.extend_from_slice(value.as_bytes());
            buffer.resize(buffer.len() + usize::from(width) - value.len(), 0);
        }
        DtaType::StrL => {
            let target = strl_target(
                source,
                strls[column_index]
                    .as_ref()
                    .expect("strL column has a plan"),
                column_index,
                &column.name,
                row,
            )?;
            if target == 0 {
                buffer.extend_from_slice(&[0; 8]);
            } else {
                write_strl_pointer(
                    buffer,
                    version,
                    u32::try_from(column_index + 1)
                        .map_err(|_| DtaWriteError::Overflow("strL variable pointer"))?,
                    target,
                )?;
            }
        }
    }
    Ok(())
}

fn write_observations<W: Write, S: DtaWriteObservationSource + ?Sized>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    source: &S,
    version: FormatVersion,
    strls: &[Option<Box<StrlColumnPlan>>],
    observation_width: u64,
    row_count: u64,
) -> Result<(), DtaWriteError> {
    let row_width = usize::try_from(observation_width)
        .map_err(|_| DtaWriteError::Overflow("observation width"))?;
    if row_width > OBSERVATION_BUFFER_BYTES {
        let field_widths = data
            .columns
            .iter()
            .map(|column| {
                usize::try_from(column.dta_type.storage_width())
                    .map_err(|_| DtaWriteError::Overflow("observation field width"))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let mut buffer = Vec::with_capacity(OBSERVATION_BUFFER_BYTES);
        for row in 0..row_count {
            source.begin_row(row)?;
            for (column_index, &field_width) in field_widths.iter().enumerate() {
                if buffer.len() + field_width > OBSERVATION_BUFFER_BYTES {
                    writer.write_all(&buffer)?;
                    buffer.clear();
                    source.check_interrupt()?;
                }
                append_observation_value(
                    &mut buffer,
                    data,
                    source,
                    version,
                    strls,
                    column_index,
                    row,
                )?;
            }
        }
        if !buffer.is_empty() {
            writer.write_all(&buffer)?;
        }
        return Ok(());
    }

    let rows_per_buffer = OBSERVATION_BUFFER_BYTES / row_width;
    let buffered_rows = usize::try_from(row_count)
        .unwrap_or(usize::MAX)
        .min(rows_per_buffer);
    let buffer_capacity = row_width
        .checked_mul(buffered_rows)
        .ok_or(DtaWriteError::Overflow("observation buffer"))?;
    let mut buffer = Vec::with_capacity(buffer_capacity);
    let mut start = 0_u64;
    while start < row_count {
        let end = row_count.min(start + rows_per_buffer as u64);
        if !source.append_observation_rows(&mut buffer, start, end)? {
            for row in start..end {
                source.begin_row(row)?;
                for column_index in 0..data.columns.len() {
                    append_observation_value(
                        &mut buffer,
                        data,
                        source,
                        version,
                        strls,
                        column_index,
                        row,
                    )?;
                }
            }
        }
        let expected = usize::try_from(end - start)
            .ok()
            .and_then(|rows| rows.checked_mul(row_width))
            .ok_or(DtaWriteError::Overflow("observation buffer"))?;
        if buffer.len() != expected {
            return Err(DtaWriteError::Source {
                column: "<dataset>".into(),
                row: start,
                message: "bulk observation source returned the wrong byte count".into(),
            });
        }
        writer.write_all(&buffer)?;
        buffer.clear();
        source.check_interrupt()?;
        start = end;
    }
    Ok(())
}

fn write_strls<W: Write, S: DtaWriteObservationSource + ?Sized>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    source: &S,
    plans: &[Option<Box<StrlColumnPlan>>],
) -> Result<(), DtaWriteError> {
    write_tag(writer, b"<strls>")?;
    let word_count = plans
        .iter()
        .filter_map(|plan| plan.as_ref().map(|plan| plan.canonical.len()))
        .max()
        .unwrap_or(0);
    for word_index in 0..word_count {
        let mut rows = plans
            .iter()
            .filter_map(|plan| {
                plan.as_ref()
                    .and_then(|plan| plan.canonical.get(word_index).copied())
            })
            .fold(0, |left, right| left | right);
        while rows != 0 {
            let bit = rows.trailing_zeros() as usize;
            let row_index = word_index
                .checked_mul(64)
                .and_then(|value| value.checked_add(bit))
                .ok_or(DtaWriteError::Overflow("GSO observation"))?;
            for (column_index, plan) in plans.iter().enumerate() {
                let Some(plan) = plan else { continue };
                if plan.canonical[word_index] & (1_u64 << bit) == 0 {
                    continue;
                }
                let column_name = &data.columns[column_index].name;
                let row = u64::try_from(row_index)
                    .map_err(|_| DtaWriteError::Overflow("GSO observation"))?;
                source.begin_row(row)?;
                let one_based_observation = row
                    .checked_add(1)
                    .ok_or(DtaWriteError::Overflow("GSO observation"))?;
                let value = source.string_value(column_index, row)?;
                validate_strl_value(source, column_name, row, value.as_ref())?;
                let fingerprint = strl_fingerprint(source, value.as_ref())?;
                if plan.canonical_fingerprints.get(&row).copied() != Some(fingerprint) {
                    return Err(DtaWriteError::Source {
                        column: column_name.to_string(),
                        row,
                        message: "canonical strL value changed after planning".into(),
                    });
                }
                write_tag(writer, b"GSO")?;
                writer.write_all(
                    &u32::try_from(column_index + 1)
                        .map_err(|_| DtaWriteError::Overflow("GSO variable"))?
                        .to_le_bytes(),
                )?;
                writer.write_all(&one_based_observation.to_le_bytes())?;
                writer.write_all(&[130])?;
                let content_length = value
                    .len()
                    .checked_add(1)
                    .ok_or(DtaWriteError::Overflow("GSO content length"))?;
                writer.write_all(
                    &u32::try_from(content_length)
                        .map_err(|_| DtaWriteError::Overflow("GSO content length"))?
                        .to_le_bytes(),
                )?;
                for chunk in value.as_bytes().chunks(WRITE_INTERRUPT_BYTES) {
                    writer.write_all(chunk)?;
                    source.check_interrupt()?;
                }
                writer.write_all(&[0])?;
            }
            rows &= rows - 1;
        }
    }
    write_tag(writer, b"</strls>")?;
    Ok(())
}

fn write_value_labels<W, S, L>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    observation_source: &S,
    value_label_source: &L,
) -> Result<(), DtaWriteError>
where
    W: Write,
    S: DtaWriteObservationSource + ?Sized,
    L: DtaWriteValueLabelSource + ?Sized,
{
    write_tag(writer, b"<value_labels>")?;
    let mut written = HashSet::new();
    for (column_index, column) in data.columns.iter().enumerate() {
        let Some(table) = output_value_label_table(data, value_label_source, column_index) else {
            continue;
        };
        if !written.insert(table.name) {
            continue;
        }
        let mut entries = table
            .entries
            .iter()
            .map(|entry| Ok((label_raw_value(entry.value)?, entry.label.as_ref())))
            .collect::<Result<Vec<_>, &'static str>>()
            .map_err(|message| DtaWriteError::InvalidValueLabels {
                column: column.name.to_string(),
                message: message.into(),
            })?;
        entries.sort_by_key(|entry| entry.0);

        let text_length = entries.iter().try_fold(0_usize, |length, (_, label)| {
            length
                .checked_add(label.len())
                .and_then(|length| length.checked_add(1))
                .ok_or(DtaWriteError::Overflow("value-label text"))
        })?;
        let table_length = 8_usize
            .checked_add(
                entries
                    .len()
                    .checked_mul(8)
                    .ok_or(DtaWriteError::Overflow("value-label table"))?,
            )
            .and_then(|length| length.checked_add(text_length))
            .ok_or(DtaWriteError::Overflow("value-label table"))?;

        write_tag(writer, b"<lbl>")?;
        writer.write_all(
            &i32::try_from(table_length)
                .map_err(|_| DtaWriteError::Overflow("value-label table"))?
                .to_le_bytes(),
        )?;
        write_field(writer, table.name, WRITE_FIELD_WIDTHS.varname)?;
        writer.write_all(&[0; 3])?;
        writer.write_all(
            &i32::try_from(entries.len())
                .map_err(|_| DtaWriteError::Overflow("value-label count"))?
                .to_le_bytes(),
        )?;
        writer.write_all(
            &i32::try_from(text_length)
                .map_err(|_| DtaWriteError::Overflow("value-label text"))?
                .to_le_bytes(),
        )?;
        let mut text_offset = 0_usize;
        for (_, label) in &entries {
            writer.write_all(
                &i32::try_from(text_offset)
                    .map_err(|_| DtaWriteError::Overflow("value-label text offset"))?
                    .to_le_bytes(),
            )?;
            text_offset += label.len() + 1;
        }
        for (value, _) in &entries {
            writer.write_all(&value.to_le_bytes())?;
        }
        let mut bytes_since_interrupt = 0_usize;
        for (_, label) in entries {
            for chunk in label.as_bytes().chunks(WRITE_INTERRUPT_BYTES) {
                writer.write_all(chunk)?;
                bytes_since_interrupt += chunk.len();
                if bytes_since_interrupt >= WRITE_INTERRUPT_BYTES {
                    observation_source.check_interrupt()?;
                    bytes_since_interrupt = 0;
                }
            }
            writer.write_all(&[0])?;
            bytes_since_interrupt += 1;
            if bytes_since_interrupt >= WRITE_INTERRUPT_BYTES {
                observation_source.check_interrupt()?;
                bytes_since_interrupt = 0;
            }
        }
        write_tag(writer, b"</lbl>")?;
        observation_source.check_interrupt()?;
    }
    write_tag(writer, b"</value_labels>")?;
    Ok(())
}

fn save_dta_impl<W, S, L>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
    observation_source: &S,
    value_label_source: &L,
    row_count: u64,
) -> Result<DtaWriteSummary, DtaWriteError>
where
    W: Write + Seek,
    S: DtaWriteObservationSource + ?Sized,
    L: DtaWriteValueLabelSource + ?Sized,
{
    validate_destination(writer)?;
    let version = if data.columns.len() <= RELEASE_118_MAX_VARIABLES {
        FormatVersion::V118
    } else {
        FormatVersion::V119
    };
    let observation_width = data.columns.iter().try_fold(0_u64, |width, column| {
        width
            .checked_add(u64::from(column.dta_type.storage_width()))
            .ok_or(DtaWriteError::Overflow("observation width"))
    })?;
    let strls = prepare_strls(data, observation_source, row_count)?;

    let mut offsets = SectionOffsets::default();
    write_header(writer, data, options, version, row_count)?;
    offsets.map = position(writer)?;
    write_tag(writer, b"<map>")?;
    let map_payload = position(writer)?;
    for _ in 0..SectionOffsets::NAMES.len() {
        writer.write_all(&0_u64.to_le_bytes())?;
    }
    write_tag(writer, b"</map>")?;

    write_metadata_sections(
        writer,
        data,
        version,
        &mut offsets,
        observation_source,
        value_label_source,
    )?;
    offsets.data = position(writer)?;
    write_tag(writer, b"<data>")?;
    write_observations(
        writer,
        data,
        observation_source,
        version,
        &strls,
        observation_width,
        row_count,
    )?;
    write_tag(writer, b"</data>")?;

    offsets.strls = position(writer)?;
    write_strls(writer, data, observation_source, &strls)?;
    offsets.value_labels = position(writer)?;
    write_value_labels(writer, data, observation_source, value_label_source)?;
    observation_source.check_interrupt()?;
    offsets.dta_data_close = position(writer)?;
    write_tag(writer, b"</stata_dta>")?;
    offsets.end_of_file = position(writer)?;

    let end = offsets.end_of_file;
    writer.seek(SeekFrom::Start(map_payload))?;
    for offset in offsets.as_array() {
        writer.write_all(&offset.to_le_bytes())?;
    }
    let map_bytes = SectionOffsets::NAMES
        .len()
        .checked_mul(size_of::<u64>())
        .and_then(|bytes| u64::try_from(bytes).ok())
        .ok_or(DtaWriteError::Overflow("section map end"))?;
    let map_end = map_payload
        .checked_add(map_bytes)
        .ok_or(DtaWriteError::Overflow("section map end"))?;
    if position(writer)? != map_end {
        return Err(DtaWriteError::InvalidDestination);
    }
    writer.seek(SeekFrom::Start(end))?;

    Ok(DtaWriteSummary {
        format_version: version,
        bytes_written: end,
    })
}

/// Validate and stream a standalone release-118 or release-119 DTA dataset.
///
/// The destination must be empty, positioned at byte zero, and honor writes at
/// seeked positions because the section map is patched after the last section
/// offset is known; append-only streams are rejected. No output bytes are
/// written unless the complete input validates successfully.
pub fn save_dta_to<W: Write + Seek>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
) -> Result<DtaWriteSummary, DtaWriteError> {
    let source = ColumnObservationSource { data };
    let row_count = validate_data(data, options)?;
    save_dta_impl(writer, data, options, &source, &(), row_count)
}

/// Stream prevalidated data from an adapter-specific observation source.
///
/// The common writer retains row ordering, buffering, storage encoding, every
/// non-data section, structural validation, and error propagation. The
/// destination must be empty, positioned at byte zero, and honor writes at
/// seeked positions. The source must keep each row's values stable throughout
/// planning and emission and honor every
/// [`DtaWriteObservationSource::begin_row`] transition.
#[doc(hidden)]
pub fn write_prevalidated_dta_with_observation_source_to<W, S>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
    observation_source: &S,
    row_count: u64,
) -> Result<DtaWriteSummary, DtaWriteError>
where
    W: Write + Seek,
    S: DtaWriteObservationSource + ?Sized,
{
    let column_row_count = validate_structure(data, options)?;
    if column_row_count != row_count {
        return Err(DtaWriteError::InvalidDatasetMetadata(format!(
            "prevalidated row count is {row_count} but columns have {column_row_count} rows"
        )));
    }
    save_dta_impl(writer, data, options, observation_source, &(), row_count)
}

/// Typed writer seam compiled only for the in-repository R adapter.
#[cfg(feature = "r-adapter-internal")]
#[doc(hidden)]
pub fn write_prevalidated_dta_with_value_label_registry_to<W, S>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
    observation_source: &S,
    row_count: u64,
    registry: &DtaWriteValueLabelRegistry<'_>,
) -> Result<DtaWriteSummary, DtaWriteError>
where
    W: Write + Seek,
    S: DtaWriteObservationSource + ?Sized,
{
    let column_row_count = validate_structure(data, options)?;
    if column_row_count != row_count {
        return Err(DtaWriteError::InvalidDatasetMetadata(format!(
            "prevalidated row count is {row_count} but columns have {column_row_count} rows"
        )));
    }
    if registry.indices.len() != data.columns.len() {
        return Err(DtaWriteError::InvalidDatasetMetadata(
            "value-label table index count does not match the columns".to_owned(),
        ));
    }
    if registry
        .indices
        .iter()
        .flatten()
        .any(|&index| index >= registry.tables.len())
    {
        return Err(DtaWriteError::InvalidDatasetMetadata(
            "value-label table registry is inconsistent".to_owned(),
        ));
    }
    if data
        .columns
        .iter()
        .zip(registry.indices)
        .any(|(column, table_index)| column.has_value_labels != table_index.is_some())
    {
        return Err(DtaWriteError::InvalidDatasetMetadata(
            "value-label table registry does not match the columns".to_owned(),
        ));
    }
    validate_value_label_names(data, registry)?;
    save_dta_impl(
        writer,
        data,
        options,
        observation_source,
        registry,
        row_count,
    )
}

impl std::fmt::Display for DtaWriteLabelValue {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Integer(value) => value.fmt(formatter),
            Self::Missing(tag) => tag.fmt(formatter),
        }
    }
}
