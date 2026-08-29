//! Versioned `dtatools:*` JSON documents carried in Arrow schema, field, and
//! footer metadata.

use std::collections::BTreeMap;

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
        Some(ValueLabelTable {
            name: name.to_owned(),
            entries: entries
                .iter()
                .map(|entry| ValueLabelEntry {
                    value: entry.value.unwrap_or(0),
                    missing_tag: entry.tag,
                    label: entry.label.clone(),
                })
                .collect(),
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
    Ok(document)
}

pub(crate) fn parse_field_document(
    version: &str,
    field_name: &str,
    json: &str,
) -> Result<ArrowFieldDocument, ArrowProfileError> {
    let document: ArrowFieldDocument = serde_json::from_str(json).map_err(|error| {
        malformed(
            version,
            format!("invalid field document on `{field_name}`: {error}"),
        )
    })?;
    if document.version != DOCUMENT_VERSION {
        return Err(malformed(
            version,
            format!(
                "field document version {} on `{field_name}`",
                document.version
            ),
        ));
    }
    Ok(document)
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
