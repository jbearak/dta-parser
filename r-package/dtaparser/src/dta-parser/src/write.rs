use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::hash::{DefaultHasher, Hash, Hasher};
use std::io::{Seek, SeekFrom, Write};

use crate::{
    DtaType, FormatVersion, MissingTag, DOUBLE_MISSING_DOT_BITS, DOUBLE_MISSING_STEP_BITS,
    FLOAT_MISSING_DOT_BITS, FLOAT_MISSING_STEP_BITS,
};

const MAX_VARIABLES: usize = 120_000;
const RELEASE_118_MAX_VARIABLES: usize = 32_767;
const FIELD_NAME_WIDTH: usize = 129;
const FIELD_FORMAT_WIDTH: usize = 57;
const FIELD_VARIABLE_LABEL_WIDTH: usize = 321;
const MAX_VALUE_LABEL_ENTRIES: usize = 65_536;
const MAX_VALUE_LABEL_TEXT_BYTES: usize = 32_000;
const MAX_NOTES: usize = 9_999;
const MAX_NOTE_BYTES: usize = 67_784;
const MAX_STRL_BYTES: usize = 2_000_000_000;
const OBSERVATION_BUFFER_BYTES: usize = 8 * 1024 * 1024;

/// Stata application generation that should be able to open an output file.
///
/// Stata 18 and 19 use the same release-118 and release-119 `.dta` encodings.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StataVersion {
    V18,
    V19,
}

/// A numeric value supplied to the DTA writer.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DtaWriteNumericValue {
    Value(f64),
    Missing(MissingTag),
}

/// A value-label key supplied to the DTA writer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DtaWriteLabelValue {
    Integer(i32),
    Missing(MissingTag),
}

/// One value-label entry. Tables are named after their variables in output.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DtaWriteValueLabel {
    pub value: DtaWriteLabelValue,
    pub label: String,
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
    pub name: String,
    pub dta_type: DtaType,
    pub format: String,
    pub label: String,
    /// Whether the variable is associated with a value-label table. This is
    /// distinct from the number of entries because Stata permits empty tables.
    pub has_value_labels: bool,
    pub value_labels: Vec<DtaWriteValueLabel>,
    pub values: DtaWriteColumnValues<'a>,
}

/// Purpose-built dataset model consumed by the streaming writer.
#[derive(Debug)]
pub struct DtaWriteData<'a> {
    pub dataset_label: String,
    pub notes: Vec<String>,
    pub row_count: u64,
    pub columns: Vec<DtaWriteColumn<'a>>,
}

/// Options shared by native adapters.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DtaWriteOptions {
    pub stata_version: StataVersion,
    /// DTA timestamp text, normally `DD Mon YYYY HH:MM`. `None` writes an
    /// empty timestamp; adapters can inject a deterministic value in tests.
    pub timestamp: Option<String>,
}

impl Default for DtaWriteOptions {
    fn default() -> Self {
        Self {
            stata_version: StataVersion::V19,
            timestamp: None,
        }
    }
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
    #[error("integer overflow while calculating {0}")]
    Overflow(&'static str),
    #[error("I/O error while writing DTA output: {0}")]
    Io(#[from] std::io::Error),
}

fn type_code(dta_type: &DtaType) -> u16 {
    match dta_type {
        DtaType::Byte => 65_530,
        DtaType::Int => 65_529,
        DtaType::Long => 65_528,
        DtaType::Float => 65_527,
        DtaType::Double => 65_526,
        DtaType::FixedString(width) => *width,
        DtaType::StrL => 32_768,
    }
}

fn storage_width(dta_type: &DtaType) -> u64 {
    match dta_type {
        DtaType::Byte => 1,
        DtaType::Int => 2,
        DtaType::Long | DtaType::Float => 4,
        DtaType::Double | DtaType::StrL => 8,
        DtaType::FixedString(width) => u64::from(*width),
    }
}

fn valid_stata_name(name: &str) -> bool {
    let mut characters = name.chars();
    let Some(first) = characters.next() else {
        return false;
    };
    (first == '_' || first.is_alphabetic())
        && characters.all(|character| character == '_' || character.is_alphanumeric())
        && name.chars().count() <= 32
        && name.len() < FIELD_NAME_WIDTH
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
        DtaWriteLabelValue::Integer(value) if (-2_147_483_647..=2_147_483_620).contains(&value) => {
            Ok(value)
        }
        DtaWriteLabelValue::Integer(_) => Err("integer key is outside Stata's long range"),
        DtaWriteLabelValue::Missing(MissingTag::System) => {
            Err("system missing cannot have a value label")
        }
        DtaWriteLabelValue::Missing(tag) => Ok(2_147_483_621 + i32::from(tag.offset())),
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
            column: column.name.clone(),
            row,
            message: "observed numeric value is not finite".into(),
        });
    }
    let valid = match column.dta_type {
        DtaType::Byte => value.fract() == 0.0 && (-127.0..=100.0).contains(&value),
        DtaType::Int => value.fract() == 0.0 && (-32_767.0..=32_740.0).contains(&value),
        DtaType::Long => {
            value.fract() == 0.0 && (-2_147_483_647.0..=2_147_483_620.0).contains(&value)
        }
        DtaType::Float => value.abs() <= f64::from(f32::from_bits(FLOAT_MISSING_DOT_BITS - 1)),
        DtaType::Double => value.abs() <= f64::from_bits(DOUBLE_MISSING_DOT_BITS - 1),
        DtaType::FixedString(_) | DtaType::StrL => false,
    };
    if valid {
        Ok(())
    } else {
        Err(DtaWriteError::InvalidValue {
            column: column.name.clone(),
            row,
            message: format!("{value} is not representable as {}", column.dta_type),
        })
    }
}

fn validate_data(
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
    validate_values: bool,
) -> Result<(), DtaWriteError> {
    match options.stata_version {
        StataVersion::V18 | StataVersion::V19 => {}
    }
    if data.columns.is_empty() {
        return Err(DtaWriteError::NoVariables);
    }
    if data.columns.len() > MAX_VARIABLES {
        return Err(DtaWriteError::TooManyVariables {
            count: data.columns.len(),
            maximum: MAX_VARIABLES,
        });
    }
    validate_text_field(&data.dataset_label, 80, 320, "dataset label")
        .map_err(DtaWriteError::InvalidDatasetMetadata)?;
    if data.notes.len() > MAX_NOTES {
        return Err(DtaWriteError::InvalidDatasetMetadata(format!(
            "dataset has {} notes; maximum is {MAX_NOTES}",
            data.notes.len()
        )));
    }
    for (index, note) in data.notes.iter().enumerate() {
        if note.contains('\0') {
            return Err(DtaWriteError::InvalidDatasetMetadata(format!(
                "note {} contains a NUL character",
                index + 1
            )));
        }
        if note.len() > MAX_NOTE_BYTES {
            return Err(DtaWriteError::InvalidDatasetMetadata(format!(
                "note {} has {} UTF-8 bytes; maximum is {MAX_NOTE_BYTES}",
                index + 1,
                note.len()
            )));
        }
    }
    if let Some(timestamp) = &options.timestamp {
        if timestamp.contains('\0') || timestamp.len() > u8::MAX as usize {
            return Err(DtaWriteError::InvalidDatasetMetadata(
                "timestamp must contain at most 255 bytes and no NUL".into(),
            ));
        }
    }

    let mut names = HashSet::with_capacity(data.columns.len());
    for column in &data.columns {
        if !valid_stata_name(&column.name) {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.clone(),
                message: "name must be a valid Stata name of at most 32 Unicode characters".into(),
            });
        }
        if !names.insert(column.name.as_str()) {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.clone(),
                message: "variable names must be unique".into(),
            });
        }
        if matches!(column.dta_type, DtaType::FixedString(0 | 2046..=u16::MAX)) {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.clone(),
                message: "fixed-string width must be between 1 and 2045 bytes".into(),
            });
        }
        if column.format.is_empty()
            || column.format.contains('\0')
            || column.format.len() >= FIELD_FORMAT_WIDTH
        {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.clone(),
                message: "display format must contain 1 to 56 UTF-8 bytes and no NUL".into(),
            });
        }
        validate_text_field(
            &column.label,
            80,
            FIELD_VARIABLE_LABEL_WIDTH - 1,
            "variable label",
        )
        .map_err(|message| DtaWriteError::InvalidVariable {
            column: column.name.clone(),
            message,
        })?;
        if column.values.len()? != data.row_count {
            return Err(DtaWriteError::InvalidVariable {
                column: column.name.clone(),
                message: format!(
                    "column has {} rows but dataset has {}",
                    column.values.len()?,
                    data.row_count
                ),
            });
        }
        if column.value_labels.len() > MAX_VALUE_LABEL_ENTRIES {
            return Err(DtaWriteError::InvalidValueLabels {
                column: column.name.clone(),
                message: format!(
                    "table has {} entries; maximum is {MAX_VALUE_LABEL_ENTRIES}",
                    column.value_labels.len()
                ),
            });
        }
        if !column.has_value_labels && !column.value_labels.is_empty() {
            return Err(DtaWriteError::InvalidValueLabels {
                column: column.name.clone(),
                message: "entries require an associated value-label table".into(),
            });
        }
        if column.has_value_labels
            && matches!(column.dta_type, DtaType::FixedString(_) | DtaType::StrL)
        {
            return Err(DtaWriteError::InvalidValueLabels {
                column: column.name.clone(),
                message: "string variables cannot have numeric value labels".into(),
            });
        }
        for entry in &column.value_labels {
            label_raw_value(entry.value).map_err(|message| DtaWriteError::InvalidValueLabels {
                column: column.name.clone(),
                message: message.into(),
            })?;
            if entry.label.contains('\0') || entry.label.len() > MAX_VALUE_LABEL_TEXT_BYTES {
                return Err(DtaWriteError::InvalidValueLabels {
                    column: column.name.clone(),
                    message: format!(
                        "label text must contain at most {MAX_VALUE_LABEL_TEXT_BYTES} UTF-8 bytes and no NUL"
                    ),
                });
            }
        }

        if validate_values {
            for row in 0..data.row_count {
                match column.dta_type {
                    DtaType::Byte
                    | DtaType::Int
                    | DtaType::Long
                    | DtaType::Float
                    | DtaType::Double => {
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
                                column: column.name.clone(),
                                row,
                                message: format!(
                                    "string must contain at most {width} UTF-8 bytes and no NUL"
                                ),
                            });
                        }
                    }
                    DtaType::StrL => {
                        let value = column.values.string_value(&column.name, row)?;
                        if value.contains('\0') {
                            return Err(DtaWriteError::InvalidValue {
                                column: column.name.clone(),
                                row,
                                message: "strL value contains a NUL character".into(),
                            });
                        }
                        if value.len() > MAX_STRL_BYTES {
                            return Err(DtaWriteError::InvalidValue {
                                column: column.name.clone(),
                                row,
                                message: format!(
                                    "strL has {} UTF-8 bytes; maximum is {MAX_STRL_BYTES}",
                                    value.len()
                                ),
                            });
                        }
                    }
                }
            }
        }
    }
    Ok(())
}

fn position<W: Seek>(writer: &mut W) -> Result<u64, DtaWriteError> {
    Ok(writer.stream_position()?)
}

fn write_tag<W: Write>(writer: &mut W, tag: &[u8]) -> Result<(), DtaWriteError> {
    writer.write_all(tag)?;
    Ok(())
}

fn write_field<W: Write>(writer: &mut W, value: &str, width: usize) -> Result<(), DtaWriteError> {
    writer.write_all(value.as_bytes())?;
    let padding = width
        .checked_sub(value.len())
        .ok_or(DtaWriteError::Overflow("fixed text field"))?;
    for _ in 0..padding {
        writer.write_all(&[0])?;
    }
    Ok(())
}

fn write_note_characteristic<W: Write>(
    writer: &mut W,
    name: &str,
    value: &str,
) -> Result<(), DtaWriteError> {
    write_tag(writer, b"<ch>")?;
    let payload_length = FIELD_NAME_WIDTH
        .checked_mul(2)
        .and_then(|length| length.checked_add(value.len()))
        .and_then(|length| length.checked_add(1))
        .ok_or(DtaWriteError::Overflow("note characteristic"))?;
    writer.write_all(
        &u32::try_from(payload_length)
            .map_err(|_| DtaWriteError::Overflow("note characteristic"))?
            .to_le_bytes(),
    )?;
    write_field(writer, "_dta", FIELD_NAME_WIDTH)?;
    write_field(writer, name, FIELD_NAME_WIDTH)?;
    writer.write_all(value.as_bytes())?;
    writer.write_all(&[0])?;
    write_tag(writer, b"</ch>")?;
    Ok(())
}

fn write_header<W: Write>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
    version: FormatVersion,
) -> Result<(), DtaWriteError> {
    write!(
        writer,
        "<stata_dta><header><release>{}</release><byteorder>LSF</byteorder><K>",
        version.as_u16()
    )?;
    if version == FormatVersion::V119 {
        writer.write_all(
            &u32::try_from(data.columns.len())
                .map_err(|_| DtaWriteError::Overflow("variable count"))?
                .to_le_bytes(),
        )?;
    } else {
        writer.write_all(
            &u16::try_from(data.columns.len())
                .map_err(|_| DtaWriteError::Overflow("variable count"))?
                .to_le_bytes(),
        )?;
    }
    write_tag(writer, b"</K><N>")?;
    writer.write_all(&data.row_count.to_le_bytes())?;
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

fn write_metadata_sections<W: Write + Seek>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    version: FormatVersion,
    offsets: &mut [u64; 14],
) -> Result<(), DtaWriteError> {
    offsets[2] = position(writer)?;
    write_tag(writer, b"<variable_types>")?;
    for column in &data.columns {
        writer.write_all(&type_code(&column.dta_type).to_le_bytes())?;
    }
    write_tag(writer, b"</variable_types>")?;

    offsets[3] = position(writer)?;
    write_tag(writer, b"<varnames>")?;
    for column in &data.columns {
        write_field(writer, &column.name, FIELD_NAME_WIDTH)?;
    }
    write_tag(writer, b"</varnames>")?;

    offsets[4] = position(writer)?;
    write_tag(writer, b"<sortlist>")?;
    let zero_width = if version == FormatVersion::V119 { 4 } else { 2 };
    let sort_bytes = data
        .columns
        .len()
        .checked_add(1)
        .and_then(|count| count.checked_mul(zero_width))
        .ok_or(DtaWriteError::Overflow("sortlist"))?;
    for _ in 0..sort_bytes {
        writer.write_all(&[0])?;
    }
    write_tag(writer, b"</sortlist>")?;

    offsets[5] = position(writer)?;
    write_tag(writer, b"<formats>")?;
    for column in &data.columns {
        write_field(writer, &column.format, FIELD_FORMAT_WIDTH)?;
    }
    write_tag(writer, b"</formats>")?;

    offsets[6] = position(writer)?;
    write_tag(writer, b"<value_label_names>")?;
    for column in &data.columns {
        let name = if column.has_value_labels {
            column.name.as_str()
        } else {
            ""
        };
        write_field(writer, name, FIELD_NAME_WIDTH)?;
    }
    write_tag(writer, b"</value_label_names>")?;

    offsets[7] = position(writer)?;
    write_tag(writer, b"<variable_labels>")?;
    for column in &data.columns {
        write_field(writer, &column.label, FIELD_VARIABLE_LABEL_WIDTH)?;
    }
    write_tag(writer, b"</variable_labels>")?;

    offsets[8] = position(writer)?;
    write_tag(writer, b"<characteristics>")?;
    if !data.notes.is_empty() {
        write_note_characteristic(writer, "note0", &data.notes.len().to_string())?;
    }
    for (index, note) in data.notes.iter().enumerate() {
        write_note_characteristic(writer, &format!("note{}", index + 1), note)?;
    }
    write_tag(writer, b"</characteristics>")?;
    Ok(())
}

fn missing_integer(tag: MissingTag, dot: i64) -> i64 {
    dot + i64::from(tag.offset())
}

fn append_numeric(buffer: &mut Vec<u8>, dta_type: &DtaType, value: DtaWriteNumericValue) {
    match (dta_type, value) {
        (DtaType::Byte, DtaWriteNumericValue::Value(value)) => buffer.push((value as i8) as u8),
        (DtaType::Byte, DtaWriteNumericValue::Missing(tag)) => {
            buffer.push((missing_integer(tag, 101) as i8) as u8)
        }
        (DtaType::Int, DtaWriteNumericValue::Value(value)) => {
            buffer.extend_from_slice(&(value as i16).to_le_bytes())
        }
        (DtaType::Int, DtaWriteNumericValue::Missing(tag)) => {
            buffer.extend_from_slice(&(missing_integer(tag, 32_741) as i16).to_le_bytes())
        }
        (DtaType::Long, DtaWriteNumericValue::Value(value)) => {
            buffer.extend_from_slice(&(value as i32).to_le_bytes())
        }
        (DtaType::Long, DtaWriteNumericValue::Missing(tag)) => {
            buffer.extend_from_slice(&(missing_integer(tag, 2_147_483_621) as i32).to_le_bytes())
        }
        (DtaType::Float, DtaWriteNumericValue::Value(value)) => {
            buffer.extend_from_slice(&(value as f32).to_bits().to_le_bytes())
        }
        (DtaType::Float, DtaWriteNumericValue::Missing(tag)) => {
            let bits = FLOAT_MISSING_DOT_BITS + u32::from(tag.offset()) * FLOAT_MISSING_STEP_BITS;
            buffer.extend_from_slice(&bits.to_le_bytes())
        }
        (DtaType::Double, DtaWriteNumericValue::Value(value)) => {
            buffer.extend_from_slice(&value.to_bits().to_le_bytes())
        }
        (DtaType::Double, DtaWriteNumericValue::Missing(tag)) => {
            let bits = DOUBLE_MISSING_DOT_BITS + u64::from(tag.offset()) * DOUBLE_MISSING_STEP_BITS;
            buffer.extend_from_slice(&bits.to_le_bytes())
        }
        _ => unreachable!("validated numeric storage type"),
    }
}

#[derive(Debug)]
struct StrlColumnPlan {
    /// The one-based observation holding each cell's canonical GSO record.
    /// Empty strings use `None`, which is encoded as an all-zero pointer.
    targets: Vec<Option<u64>>,
}

fn prepare_strls(data: &DtaWriteData<'_>) -> Result<Vec<Option<StrlColumnPlan>>, DtaWriteError> {
    let mut plans = Vec::with_capacity(data.columns.len());
    for column in &data.columns {
        if column.dta_type != DtaType::StrL {
            plans.push(None);
            continue;
        }
        let capacity = usize::try_from(data.row_count)
            .map_err(|_| DtaWriteError::Overflow("strL pointer index"))?;
        let mut targets = Vec::with_capacity(capacity);
        let mut candidates = HashMap::<u64, Vec<u64>>::new();
        for row in 0..data.row_count {
            let value = column.values.string_value(&column.name, row)?;
            if value.is_empty() {
                targets.push(None);
                continue;
            }
            let mut hasher = DefaultHasher::new();
            value.hash(&mut hasher);
            let hash = hasher.finish();
            let rows = candidates.entry(hash).or_default();
            let mut target = None;
            for &candidate in rows.iter() {
                if column.values.string_value(&column.name, candidate)? == value {
                    target = Some(candidate + 1);
                    break;
                }
            }
            if target.is_none() {
                rows.push(row);
                target = Some(row + 1);
            }
            targets.push(target);
        }
        plans.push(Some(StrlColumnPlan { targets }));
    }
    Ok(plans)
}

fn write_low_bytes<W: Write>(
    writer: &mut W,
    value: u64,
    width: usize,
) -> Result<(), DtaWriteError> {
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
    match version {
        FormatVersion::V118 => {
            writer.write_all(
                &u16::try_from(variable)
                    .map_err(|_| DtaWriteError::Overflow("release-118 strL variable pointer"))?
                    .to_le_bytes(),
            )?;
            write_low_bytes(writer, observation, 6)?;
        }
        FormatVersion::V119 => {
            write_low_bytes(writer, u64::from(variable), 3)?;
            write_low_bytes(writer, observation, 5)?;
        }
        _ => unreachable!("writer only emits releases 118 and 119"),
    }
    Ok(())
}

fn write_observations<W: Write>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    version: FormatVersion,
    strls: &[Option<StrlColumnPlan>],
    observation_width: u64,
) -> Result<(), DtaWriteError> {
    let row_width = usize::try_from(observation_width)
        .map_err(|_| DtaWriteError::Overflow("observation width"))?;
    let rows_per_buffer = (OBSERVATION_BUFFER_BYTES / row_width).max(1);
    let buffer_capacity = row_width
        .checked_mul(rows_per_buffer)
        .ok_or(DtaWriteError::Overflow("observation buffer"))?;
    let mut buffer = Vec::with_capacity(buffer_capacity);
    for row in 0..data.row_count {
        for (column_index, column) in data.columns.iter().enumerate() {
            match column.dta_type {
                DtaType::Byte | DtaType::Int | DtaType::Long | DtaType::Float | DtaType::Double => {
                    append_numeric(
                        &mut buffer,
                        &column.dta_type,
                        column.values.numeric_value(&column.name, row)?,
                    )
                }
                DtaType::FixedString(width) => {
                    let value = column.values.string_value(&column.name, row)?;
                    buffer.extend_from_slice(value.as_bytes());
                    buffer.resize(buffer.len() + usize::from(width) - value.len(), 0);
                }
                DtaType::StrL => {
                    let target = strls[column_index]
                        .as_ref()
                        .and_then(|plan| plan.targets[usize::try_from(row).ok()?]);
                    match target {
                        Some(observation) => write_strl_pointer(
                            &mut buffer,
                            version,
                            u32::try_from(column_index + 1)
                                .map_err(|_| DtaWriteError::Overflow("strL variable pointer"))?,
                            observation,
                        )?,
                        None => buffer.extend_from_slice(&[0; 8]),
                    }
                }
            }
        }
        if (row + 1) % rows_per_buffer as u64 == 0 {
            writer.write_all(&buffer)?;
            buffer.clear();
        }
    }
    if !buffer.is_empty() {
        writer.write_all(&buffer)?;
    }
    Ok(())
}

fn write_strls<W: Write>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    plans: &[Option<StrlColumnPlan>],
) -> Result<(), DtaWriteError> {
    write_tag(writer, b"<strls>")?;
    for (column_index, column) in data.columns.iter().enumerate() {
        let Some(plan) = &plans[column_index] else {
            continue;
        };
        for row in 0..data.row_count {
            let one_based_observation = row + 1;
            if plan.targets
                [usize::try_from(row).map_err(|_| DtaWriteError::Overflow("strL pointer index"))?]
                != Some(one_based_observation)
            {
                continue;
            }
            let value = column.values.string_value(&column.name, row)?;
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
            writer.write_all(value.as_bytes())?;
            writer.write_all(&[0])?;
        }
    }
    write_tag(writer, b"</strls>")?;
    Ok(())
}

fn write_value_labels<W: Write>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
) -> Result<(), DtaWriteError> {
    write_tag(writer, b"<value_labels>")?;
    for column in &data.columns {
        if !column.has_value_labels {
            continue;
        }
        let mut entries = column
            .value_labels
            .iter()
            .map(|entry| Ok((label_raw_value(entry.value)?, entry.label.as_str())))
            .collect::<Result<Vec<_>, &'static str>>()
            .map_err(|message| DtaWriteError::InvalidValueLabels {
                column: column.name.clone(),
                message: message.into(),
            })?;
        entries.sort_by_key(|entry| entry.0);

        let mut text_length = 0_usize;
        let mut text_offsets = Vec::with_capacity(entries.len());
        for (_, label) in &entries {
            text_offsets.push(text_length);
            text_length = text_length
                .checked_add(label.len())
                .and_then(|length| length.checked_add(1))
                .ok_or(DtaWriteError::Overflow("value-label text"))?;
        }
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
        write_field(writer, &column.name, FIELD_NAME_WIDTH)?;
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
        for offset in text_offsets {
            writer.write_all(
                &i32::try_from(offset)
                    .map_err(|_| DtaWriteError::Overflow("value-label text offset"))?
                    .to_le_bytes(),
            )?;
        }
        for (value, _) in &entries {
            writer.write_all(&value.to_le_bytes())?;
        }
        for (_, label) in entries {
            writer.write_all(label.as_bytes())?;
            writer.write_all(&[0])?;
        }
        write_tag(writer, b"</lbl>")?;
    }
    write_tag(writer, b"</value_labels>")?;
    Ok(())
}

type ObservationEncoder<'a, W> = dyn FnMut(&mut W) -> Result<(), DtaWriteError> + 'a;

fn write_dta_impl<W: Write + Seek>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
    validate_values: bool,
    mut observation_encoder: Option<&mut ObservationEncoder<'_, W>>,
) -> Result<DtaWriteSummary, DtaWriteError> {
    validate_data(data, options, validate_values)?;
    let version = if data.columns.len() <= RELEASE_118_MAX_VARIABLES {
        FormatVersion::V118
    } else {
        FormatVersion::V119
    };
    let observation_width = data.columns.iter().try_fold(0_u64, |width, column| {
        width
            .checked_add(storage_width(&column.dta_type))
            .ok_or(DtaWriteError::Overflow("observation width"))
    })?;
    let strls = prepare_strls(data)?;

    let mut offsets = [0_u64; 14];
    write_header(writer, data, options, version)?;
    offsets[1] = position(writer)?;
    write_tag(writer, b"<map>")?;
    let map_payload = position(writer)?;
    for _ in 0..14 {
        writer.write_all(&0_u64.to_le_bytes())?;
    }
    write_tag(writer, b"</map>")?;

    write_metadata_sections(writer, data, version, &mut offsets)?;
    offsets[9] = position(writer)?;
    write_tag(writer, b"<data>")?;
    if let Some(encoder) = observation_encoder.as_mut() {
        encoder(writer)?;
    } else {
        write_observations(writer, data, version, &strls, observation_width)?;
    }
    write_tag(writer, b"</data>")?;

    offsets[10] = position(writer)?;
    write_strls(writer, data, &strls)?;
    offsets[11] = position(writer)?;
    write_value_labels(writer, data)?;
    offsets[12] = position(writer)?;
    write_tag(writer, b"</stata_dta>")?;
    offsets[13] = position(writer)?;

    let end = offsets[13];
    writer.seek(SeekFrom::Start(map_payload))?;
    for offset in offsets {
        writer.write_all(&offset.to_le_bytes())?;
    }
    writer.seek(SeekFrom::Start(end))?;

    Ok(DtaWriteSummary {
        format_version: version,
        bytes_written: end,
    })
}

/// Validate and stream a standalone release-118 or release-119 DTA dataset.
///
/// The destination must be seekable because the section map is patched after
/// the last section offset is known. No output bytes are written unless the
/// complete input validates successfully.
pub fn write_dta_to<W: Write + Seek>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
) -> Result<DtaWriteSummary, DtaWriteError> {
    write_dta_impl(writer, data, options, true, None)
}

/// Stream data whose adapter has already validated every column value.
///
/// Dataset and variable structure are still validated. This internal seam
/// avoids a redundant value pass for adapters that perform equivalent checks
/// while preparing their native descriptors.
#[doc(hidden)]
pub fn write_prevalidated_dta_to<W: Write + Seek>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
) -> Result<DtaWriteSummary, DtaWriteError> {
    write_dta_impl(writer, data, options, false, None)
}

/// Stream prevalidated data with an adapter-specific observation encoder.
///
/// The encoder writes exactly the row-major observation payload between the
/// DTA data tags. The common writer retains ownership of every other section,
/// the map, structural validation, and error propagation.
#[doc(hidden)]
pub fn write_prevalidated_dta_with_observation_encoder_to<W, F>(
    writer: &mut W,
    data: &DtaWriteData<'_>,
    options: &DtaWriteOptions,
    mut observation_encoder: F,
) -> Result<DtaWriteSummary, DtaWriteError>
where
    W: Write + Seek,
    F: FnMut(&mut W) -> Result<(), DtaWriteError>,
{
    write_dta_impl(writer, data, options, false, Some(&mut observation_encoder))
}

impl std::fmt::Display for DtaWriteLabelValue {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Integer(value) => value.fmt(formatter),
            Self::Missing(tag) => tag.fmt(formatter),
        }
    }
}
