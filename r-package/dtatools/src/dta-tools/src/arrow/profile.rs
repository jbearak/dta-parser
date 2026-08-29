//! Versioned `dtatools:*` JSON documents carried in Arrow schema, field, and
//! footer metadata.

use std::collections::BTreeMap;

use arrow_schema::{DataType, Field};
use serde::{Deserialize, Serialize};

use super::ArrowProfileError;
use crate::{DtaType, MissingTag, ValueLabelEntry, ValueLabelTable};

/// The profile version this build writes. Version "0" is experimental and
/// carries no stability promise; see ADR 0010.
pub const ARROW_PROFILE_VERSION: &str = "0";

/// Schema metadata key holding the profile version string.
pub const ARROW_PROFILE_VERSION_KEY: &str = "dtatools:profile-version";
/// Schema metadata key holding the dataset document.
pub const ARROW_DATASET_KEY: &str = "dtatools:dataset";
/// Field metadata key holding one field document.
pub const ARROW_FIELD_KEY: &str = "dtatools:field";
/// Footer custom-metadata key holding the checksums document.
pub const ARROW_CHECKSUMS_KEY: &str = "dtatools:checksums";

pub(crate) const DOCUMENT_VERSION: u32 = 0;

/// One value-label mapping inside the dataset document: either a nonmissing
/// Stata `long` code or an extended missing tag, with its label text.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ArrowValueLabelEntry {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tag: Option<MissingTag>,
    pub label: String,
}

/// The `dtatools:dataset` schema document: dataset label, ordered notes, and
/// the registry of value-label tables keyed by Stata label-table name.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DatasetDocument {
    pub version: u32,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub label: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub notes: Vec<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub value_labels: BTreeMap<String, Vec<ArrowValueLabelEntry>>,
}

impl DatasetDocument {
    pub fn value_label_table(&self, name: &str) -> Option<ValueLabelTable> {
        let entries = self.value_labels.get(name)?;
        let entries = entries
            .iter()
            .map(|entry| {
                let (value, missing_tag) = match (entry.value, entry.tag) {
                    (Some(value), None) => (value, None),
                    (None, Some(tag)) => (0, Some(tag)),
                    _ => return None,
                };
                Some(ValueLabelEntry {
                    value,
                    missing_tag,
                    label: entry.label.clone(),
                })
            })
            .collect::<Option<Vec<_>>>()?;
        Some(ValueLabelTable {
            name: name.to_owned(),
            entries,
        })
    }

    pub fn insert_value_label_table(&mut self, table: &ValueLabelTable) {
        let entries = table
            .entries
            .iter()
            .map(|entry| ArrowValueLabelEntry {
                value: entry.missing_tag.is_none().then_some(entry.value),
                tag: entry.missing_tag,
                label: entry.label.clone(),
            })
            .collect();
        self.value_labels.insert(table.name.clone(), entries);
    }
}

/// A declared Stata storage type in a field document.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum StataStorage {
    Byte,
    Int,
    Long,
    Float,
    Double,
}

impl StataStorage {
    pub fn dta_type(self) -> DtaType {
        match self {
            Self::Byte => DtaType::Byte,
            Self::Int => DtaType::Int,
            Self::Long => DtaType::Long,
            Self::Float => DtaType::Float,
            Self::Double => DtaType::Double,
        }
    }

    pub fn from_label(label: &str) -> Option<Self> {
        match label {
            "byte" => Some(Self::Byte),
            "int" => Some(Self::Int),
            "long" => Some(Self::Long),
            "float" => Some(Self::Float),
            "double" => Some(Self::Double),
            _ => None,
        }
    }
}

/// How a profiled column encodes Stata missing codes in raw Stata missing
/// storage: reserved sentinel integers, or NaN payloads.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ArrowMissingEncoding {
    Sentinel,
    Payload,
}

/// Portable R semantics for one field: the R class the reader restores, with
/// the class-specific details standard Arrow types do not carry.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ArrowRSemantics {
    pub class: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ordered: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tz: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub units: Option<String>,
}

/// The `dtatools:field` document on one Arrow field.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ArrowFieldDocument {
    pub version: u32,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub label: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub format: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub storage: Option<StataStorage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value_labels: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub missing: Option<ArrowMissingEncoding>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub r: Option<ArrowRSemantics>,
}

/// Per-buffer xxHash64 checksums, in canonical buffer order, for every column
/// of every record batch and for each dictionary field's values.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChecksumsDocument {
    pub version: u32,
    pub algorithm: String,
    pub batches: Vec<BatchChecksums>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub dictionaries: BTreeMap<String, Vec<String>>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct BatchChecksums {
    pub columns: Vec<Vec<String>>,
}

pub(crate) fn checksum_to_hex(value: u64) -> String {
    format!("{value:016x}")
}

pub(crate) fn malformed(version: &str, detail: impl Into<String>) -> ArrowProfileError {
    ArrowProfileError::MalformedProfile {
        version: version.to_owned(),
        detail: detail.into(),
    }
}

pub(crate) fn parse_dataset_document(
    version: &str,
    json: Option<&str>,
) -> Result<DatasetDocument, ArrowProfileError> {
    let Some(json) = json else {
        return Ok(DatasetDocument {
            version: DOCUMENT_VERSION,
            ..DatasetDocument::default()
        });
    };
    let document: DatasetDocument = serde_json::from_str(json)
        .map_err(|error| malformed(version, format!("invalid dataset document: {error}")))?;
    if document.version != DOCUMENT_VERSION {
        return Err(malformed(
            version,
            format!("dataset document version {}", document.version),
        ));
    }
    for (table, entries) in &document.value_labels {
        for (index, entry) in entries.iter().enumerate() {
            if entry.value.is_some() == entry.tag.is_some() {
                return Err(malformed(
                    version,
                    format!(
                        "value-label table `{table}` entry {index} must contain exactly one of `value` or `tag`"
                    ),
                ));
            }
        }
    }
    Ok(document)
}

pub(crate) fn parse_field_document(
    version: &str,
    field: &Field,
    json: &str,
) -> Result<ArrowFieldDocument, ArrowProfileError> {
    let document: ArrowFieldDocument = serde_json::from_str(json).map_err(|error| {
        malformed(
            version,
            format!("invalid field document on `{}`: {error}", field.name()),
        )
    })?;
    if document.version != DOCUMENT_VERSION {
        return Err(malformed(
            version,
            format!(
                "field document version {} on `{}`",
                document.version,
                field.name()
            ),
        ));
    }
    validate_field_document(version, field, &document)?;
    Ok(document)
}

fn field_malformed(
    version: &str,
    field: &Field,
    detail: impl std::fmt::Display,
) -> ArrowProfileError {
    malformed(version, format!("field `{}` {detail}", field.name()))
}

fn storage_type(storage: StataStorage) -> DataType {
    match storage {
        StataStorage::Byte => DataType::Int8,
        StataStorage::Int => DataType::Int16,
        StataStorage::Long => DataType::Int32,
        StataStorage::Float => DataType::Float32,
        StataStorage::Double => DataType::Float64,
    }
}

fn storage_missing(storage: StataStorage) -> ArrowMissingEncoding {
    match storage {
        StataStorage::Byte | StataStorage::Int | StataStorage::Long => {
            ArrowMissingEncoding::Sentinel
        }
        StataStorage::Float | StataStorage::Double => ArrowMissingEncoding::Payload,
    }
}

fn factor_type(data_type: &DataType) -> bool {
    matches!(
        data_type,
        DataType::Dictionary(key, value)
            if key.as_ref() == &DataType::Int32
                && matches!(value.as_ref(), DataType::Utf8 | DataType::LargeUtf8)
    )
}

fn semantic_double_type(data_type: &DataType) -> bool {
    matches!(
        data_type,
        DataType::Float32
            | DataType::Float64
            | DataType::Int64
            | DataType::UInt16
            | DataType::UInt32
            | DataType::UInt64
    )
}

fn class_matches_type(class: &str, data_type: &DataType) -> Option<bool> {
    Some(match class {
        "logical" => data_type == &DataType::Boolean,
        "integer" => matches!(
            data_type,
            DataType::Int8 | DataType::Int16 | DataType::Int32 | DataType::UInt8
        ),
        "double" => semantic_double_type(data_type),
        "character" => matches!(data_type, DataType::Utf8 | DataType::LargeUtf8),
        "factor" => factor_type(data_type),
        "raw" => data_type == &DataType::UInt8,
        "Date" => matches!(data_type, DataType::Date32 | DataType::Float64),
        "POSIXct" => matches!(data_type, DataType::Timestamp(_, _) | DataType::Float64),
        "difftime" => matches!(data_type, DataType::Duration(_) | DataType::Float64),
        "haven_labelled" => data_type == &DataType::Float64,
        _ => return None,
    })
}

fn validate_r_semantics(
    version: &str,
    field: &Field,
    semantics: &ArrowRSemantics,
) -> Result<(), ArrowProfileError> {
    let Some(compatible) = class_matches_type(&semantics.class, field.data_type()) else {
        return Err(field_malformed(
            version,
            field,
            format!("declares unsupported R class `{}`", semantics.class),
        ));
    };
    if !compatible {
        return Err(field_malformed(
            version,
            field,
            format!(
                "declares R class `{}` incompatible with Arrow type {}",
                semantics.class,
                field.data_type()
            ),
        ));
    }
    if semantics.ordered.is_some() && semantics.class != "factor" {
        return Err(field_malformed(
            version,
            field,
            "declares `r.ordered` without factor semantics",
        ));
    }
    if semantics.tz.is_some() && semantics.class != "POSIXct" {
        return Err(field_malformed(
            version,
            field,
            "declares `r.tz` without POSIXct semantics",
        ));
    }
    if semantics.units.is_some() && semantics.class != "difftime" {
        return Err(field_malformed(
            version,
            field,
            "declares `r.units` without difftime semantics",
        ));
    }
    if semantics.class == "difftime" {
        let valid_units = semantics
            .units
            .as_deref()
            .is_none_or(|units| matches!(units, "secs" | "mins" | "hours" | "days" | "weeks"));
        if !valid_units {
            return Err(field_malformed(
                version,
                field,
                "declares unsupported difftime units",
            ));
        }
    }
    Ok(())
}

fn supports_value_labels(data_type: &DataType) -> bool {
    semantic_double_type(data_type)
        || matches!(
            data_type,
            DataType::Date32 | DataType::Timestamp(_, _) | DataType::Duration(_)
        )
}

fn validate_field_document(
    version: &str,
    field: &Field,
    document: &ArrowFieldDocument,
) -> Result<(), ArrowProfileError> {
    if let Some(storage) = document.storage {
        let expected_type = storage_type(storage);
        if field.data_type() != &expected_type {
            return Err(field_malformed(
                version,
                field,
                format!(
                    "declares Stata storage incompatible with Arrow type {}",
                    field.data_type()
                ),
            ));
        }
        if document.missing != Some(storage_missing(storage)) {
            return Err(field_malformed(
                version,
                field,
                "declares a missing encoding incompatible with its Stata storage",
            ));
        }
        if field.is_nullable() {
            return Err(field_malformed(
                version,
                field,
                "declares raw Stata missing storage on a nullable Arrow field",
            ));
        }
        if let Some(semantics) = &document.r {
            let valid = semantics.class == "stata_numeric"
                && semantics.ordered.is_none()
                && semantics.tz.is_none()
                && semantics.units.is_none();
            if !valid {
                return Err(field_malformed(
                    version,
                    field,
                    "declares R semantics incompatible with its Stata storage",
                ));
            }
        }
        return Ok(());
    }

    match document.missing {
        Some(ArrowMissingEncoding::Sentinel) => {
            return Err(field_malformed(
                version,
                field,
                "declares sentinel missing encoding without Stata storage",
            ));
        }
        Some(ArrowMissingEncoding::Payload) => {
            if field.data_type() != &DataType::Float64 || field.is_nullable() {
                return Err(field_malformed(
                    version,
                    field,
                    "declares payload missing encoding on an incompatible Arrow field",
                ));
            }
            let payload_class = document.r.as_ref().map(|r| r.class.as_str());
            if !matches!(
                payload_class,
                Some("double" | "haven_labelled" | "Date" | "POSIXct" | "difftime")
            ) {
                return Err(field_malformed(
                    version,
                    field,
                    "declares payload missing encoding without compatible R semantics",
                ));
            }
        }
        None => {}
    }

    if let Some(semantics) = &document.r {
        validate_r_semantics(version, field, semantics)?;
    }
    if document.value_labels.is_some() && !supports_value_labels(field.data_type()) {
        return Err(field_malformed(
            version,
            field,
            format!(
                "declares value labels incompatible with Arrow type {}",
                field.data_type()
            ),
        ));
    }
    Ok(())
}

pub(crate) fn parse_checksums_document(
    version: &str,
    json: &str,
) -> Result<ChecksumsDocument, ArrowProfileError> {
    let document: ChecksumsDocument = serde_json::from_str(json)
        .map_err(|error| malformed(version, format!("invalid checksums document: {error}")))?;
    if document.version != DOCUMENT_VERSION {
        return Err(malformed(
            version,
            format!("checksums document version {}", document.version),
        ));
    }
    if document.algorithm != "xxh64" {
        return Err(malformed(
            version,
            format!("unknown checksum algorithm `{}`", document.algorithm),
        ));
    }
    Ok(document)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn value_label_entries_require_exactly_one_code() {
        for json in [
            r#"{"version":0,"value_labels":{"x":[{"label":"missing"}]}}"#,
            r#"{"version":0,"value_labels":{"x":[{"value":1,"tag":".a","label":"both"}]}}"#,
        ] {
            let error = parse_dataset_document("0", Some(json))
                .expect_err("malformed value-label entry is rejected");
            assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
            assert!(error
                .to_string()
                .contains("exactly one of `value` or `tag`"));
        }
    }

    #[test]
    fn field_semantics_must_match_the_arrow_field() {
        let cases = [
            (
                Field::new("day", DataType::Int32, true),
                r#"{"version":0,"r":{"class":"Date"}}"#,
            ),
            (
                Field::new("byte", DataType::Int32, false),
                r#"{"version":0,"storage":"byte","missing":"sentinel"}"#,
            ),
            (
                Field::new("payload", DataType::Float64, true),
                r#"{"version":0,"missing":"payload","r":{"class":"double"}}"#,
            ),
            (
                Field::new("mystery", DataType::Float64, true),
                r#"{"version":0,"r":{"class":"mystery"}}"#,
            ),
        ];
        for (field, json) in cases {
            let error = parse_field_document("0", &field, json)
                .expect_err("incompatible field semantics are rejected");
            assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
            assert!(error.to_string().contains(field.name()));
        }
    }

    #[test]
    fn writer_field_semantics_are_accepted() {
        let cases = [
            (
                Field::new("raw", DataType::UInt8, true),
                r#"{"version":0,"r":{"class":"raw"}}"#,
            ),
            (
                Field::new(
                    "factor",
                    DataType::Dictionary(Box::new(DataType::Int32), Box::new(DataType::Utf8)),
                    true,
                ),
                r#"{"version":0,"r":{"class":"factor","ordered":true}}"#,
            ),
            (
                Field::new(
                    "time",
                    DataType::Timestamp(arrow_schema::TimeUnit::Microsecond, Some("UTC".into())),
                    true,
                ),
                r#"{"version":0,"r":{"class":"POSIXct","tz":"UTC"}}"#,
            ),
            (
                Field::new("stata", DataType::Int8, false),
                r#"{"version":0,"storage":"byte","missing":"sentinel"}"#,
            ),
        ];
        for (field, json) in cases {
            parse_field_document("0", &field, json)
                .expect("writer-compatible field semantics are accepted");
        }
    }
}
