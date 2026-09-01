//! Versioned `dtatools:*` JSON documents carried in Arrow schema, field, and
//! footer metadata.

use std::{
    borrow::Cow,
    collections::{hash_map::RandomState, BTreeMap, HashMap, HashSet},
    fmt,
    hash::BuildHasher,
};

use arrow_schema::{DataType, Field};
use serde::{
    de::{DeserializeSeed, MapAccess, SeqAccess, Visitor},
    Deserialize, Serialize,
};
use serde_json::value::RawValue;

use super::ArrowProfileError;
use crate::{
    DtaType, FormatVersion, MissingTag, StataCharacteristic, StataNote, ValueLabelEntry,
    ValueLabelTable,
};

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
const MAX_VALUE_LABEL_TABLES: usize = 120_000;

/// One value-label mapping inside the dataset document: either a nonmissing
/// Stata `long` code or an extended missing tag, with its label text.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
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
#[serde(deny_unknown_fields)]
pub struct DatasetDocument {
    pub version: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_container: Option<String>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub label: String,
    #[serde(
        default,
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "deserialize_notes"
    )]
    pub notes: Vec<StataNote>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub characteristics: Vec<StataCharacteristic>,
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

    pub fn insert_value_label_table(
        &mut self,
        table: ValueLabelTable,
    ) -> Result<(), ArrowProfileError> {
        if self.value_labels.contains_key(&table.name) {
            return Err(ArrowProfileError::Invalid(format!(
                "duplicate value-label table name `{}`",
                table.name
            )));
        }
        let entries = table
            .entries
            .into_iter()
            .map(|entry| ArrowValueLabelEntry {
                value: entry.missing_tag.is_none().then_some(entry.value),
                tag: entry.missing_tag,
                label: entry.label,
            })
            .collect();
        self.value_labels.insert(table.name, entries);
        Ok(())
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
#[serde(deny_unknown_fields)]
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
#[serde(deny_unknown_fields)]
pub struct ArrowFieldDocument {
    pub version: u32,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub label: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub format: String,
    #[serde(
        default,
        skip_serializing_if = "Vec::is_empty",
        deserialize_with = "deserialize_notes"
    )]
    pub notes: Vec<StataNote>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub characteristics: Vec<StataCharacteristic>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub storage: Option<StataStorage>,
    /// Declared DTA string storage: `str1` through `str2045`, or `strL`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub string_storage: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value_labels: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub missing: Option<ArrowMissingEncoding>,
    /// Release whose compact missing range applies. Omitted when the profile's
    /// modern missing layout represents the column exactly.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub missing_release: Option<FormatVersion>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub r: Option<ArrowRSemantics>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum NoteDocument {
    Legacy(String),
    Numbered(StataNote),
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RawNumberedNote<'a> {
    number: u32,
    #[serde(borrow)]
    text: &'a RawValue,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RawCharacteristic<'a> {
    #[serde(borrow)]
    name: &'a RawValue,
    #[serde(borrow)]
    value: &'a RawValue,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DiscardedValueLabelEntry {
    #[serde(default)]
    value: Option<i32>,
    #[serde(default)]
    tag: Option<MissingTag>,
    #[serde(
        rename = "label",
        deserialize_with = "deserialize_discarded_value_label"
    )]
    _label: (),
}

macro_rules! raw_arrow_field_document {
    ($name:ident $(, $attribute:meta)*) => {
        #[derive(Deserialize)]
        $(#[$attribute])*
        struct $name<'a> {
            version: u32,
            #[serde(default)]
            label: String,
            #[serde(default)]
            format: String,
            #[serde(default, borrow, deserialize_with = "deserialize_raw_notes")]
            notes: Vec<&'a RawValue>,
            #[serde(default, deserialize_with = "deserialize_raw_characteristics")]
            characteristics: Vec<StataCharacteristic>,
            #[serde(default)]
            storage: Option<StataStorage>,
            #[serde(default)]
            string_storage: Option<String>,
            #[serde(default)]
            value_labels: Option<String>,
            #[serde(default)]
            missing: Option<ArrowMissingEncoding>,
            #[serde(default)]
            missing_release: Option<FormatVersion>,
            #[serde(default)]
            r: Option<ArrowRSemantics>,
        }

        impl $name<'_> {
            fn decode(
                self,
                version: &str,
                field: &Field,
            ) -> Result<ArrowFieldDocument, ArrowProfileError> {
                let invalid_context = format!("field document on `{}`", field.name());
                Ok(ArrowFieldDocument {
                    version: self.version,
                    label: self.label,
                    format: self.format,
                    notes: decode_raw_notes(version, "field", &invalid_context, self.notes)?,
                    characteristics: self.characteristics,
                    storage: self.storage,
                    string_storage: self.string_storage,
                    value_labels: self.value_labels,
                    missing: self.missing,
                    missing_release: self.missing_release,
                    r: self.r,
                })
            }
        }
    };
}

raw_arrow_field_document!(RawArrowFieldDocument, serde(deny_unknown_fields));
raw_arrow_field_document!(TolerantRawArrowFieldDocument);

// The Arrow reader first borrows bounded metadata strings as raw JSON. It
// then decodes only those fragments, avoiding a second parse of the complete
// dataset or field document without allocating an oversized decoded string.

fn deserialize_notes<'de, D>(deserializer: D) -> Result<Vec<StataNote>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    struct NotesVisitor;

    impl<'de> Visitor<'de> for NotesVisitor {
        type Value = Vec<StataNote>;

        fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
            formatter.write_str("an array of at most 9,999 Stata notes")
        }

        fn visit_seq<A>(self, mut sequence: A) -> Result<Self::Value, A::Error>
        where
            A: SeqAccess<'de>,
        {
            let maximum = crate::stata_metadata::MAX_NOTE_NUMBER as usize;
            let mut notes = Vec::with_capacity(sequence.size_hint().unwrap_or(0).min(maximum));
            while notes.len() < maximum {
                let Some(note) = sequence.next_element::<NoteDocument>()? else {
                    return Ok(notes);
                };
                let note = match note {
                    NoteDocument::Legacy(text) => StataNote {
                        number: u32::try_from(notes.len() + 1).map_err(serde::de::Error::custom)?,
                        text,
                    },
                    NoteDocument::Numbered(note) => note,
                };
                notes.push(note);
            }
            if sequence.next_element::<serde::de::IgnoredAny>()?.is_some() {
                return Err(serde::de::Error::custom(
                    "Stata note arrays may contain at most 9,999 entries",
                ));
            }
            Ok(notes)
        }
    }

    deserializer.deserialize_seq(NotesVisitor)
}

fn deserialize_raw_notes<'de, D>(deserializer: D) -> Result<Vec<&'de RawValue>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    struct RawNotesVisitor;

    impl<'de> Visitor<'de> for RawNotesVisitor {
        type Value = Vec<&'de RawValue>;

        fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
            formatter.write_str("an array of at most 9,999 Stata notes")
        }

        fn visit_seq<A>(self, mut sequence: A) -> Result<Self::Value, A::Error>
        where
            A: SeqAccess<'de>,
        {
            let maximum = crate::stata_metadata::MAX_NOTE_NUMBER as usize;
            let mut notes = Vec::with_capacity(sequence.size_hint().unwrap_or(0).min(maximum));
            while notes.len() < maximum {
                let Some(note) = sequence.next_element::<&'de RawValue>()? else {
                    return Ok(notes);
                };
                notes.push(note);
            }
            if sequence.next_element::<serde::de::IgnoredAny>()?.is_some() {
                return Err(serde::de::Error::custom(
                    "Stata note arrays may contain at most 9,999 entries",
                ));
            }
            Ok(notes)
        }
    }

    deserializer.deserialize_seq(RawNotesVisitor)
}

fn deserialize_raw_characteristics<'de, D>(
    deserializer: D,
) -> Result<Vec<StataCharacteristic>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    struct CharacteristicsVisitor;

    impl<'de> Visitor<'de> for CharacteristicsVisitor {
        type Value = Vec<StataCharacteristic>;

        fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
            formatter.write_str("an array of bounded Stata characteristics")
        }

        fn visit_seq<A>(self, mut sequence: A) -> Result<Self::Value, A::Error>
        where
            A: SeqAccess<'de>,
        {
            let mut decoded = Vec::new();
            let name_hash_builder = RandomState::new();
            let mut name_hashes = HashSet::new();
            while let Some(raw) = sequence.next_element::<RawCharacteristic<'de>>()? {
                if raw_string_exceeds_limit(
                    raw.name,
                    crate::stata_metadata::MAX_CHARACTERISTIC_NAME_BYTES,
                ) {
                    return Err(serde::de::Error::custom(format!(
                        "characteristic name exceeds the {}-byte Stata metadata limit",
                        crate::stata_metadata::MAX_CHARACTERISTIC_NAME_BYTES
                    )));
                }
                if raw_string_exceeds_limit(
                    raw.value,
                    crate::stata_metadata::MAX_DECODED_METADATA_VALUE_BYTES,
                ) {
                    return Err(serde::de::Error::custom(format!(
                        "characteristic value exceeds the {}-byte decoded Stata metadata limit",
                        crate::stata_metadata::MAX_DECODED_METADATA_VALUE_BYTES
                    )));
                }
                let characteristic = StataCharacteristic {
                    name: serde_json::from_str(raw.name.get()).map_err(serde::de::Error::custom)?,
                    value: serde_json::from_str(raw.value.get())
                        .map_err(serde::de::Error::custom)?,
                };
                if !crate::stata_metadata::valid_canonical_characteristic(
                    &characteristic.name,
                    &characteristic.value,
                ) {
                    return Err(serde::de::Error::custom(
                        "characteristics contain an invalid, duplicate, or reserved name",
                    ));
                }
                let name_hash = name_hash_builder.hash_one(characteristic.name.as_str());
                if name_hashes.contains(&name_hash)
                    && decoded
                        .iter()
                        .any(|existing: &StataCharacteristic| existing.name == characteristic.name)
                {
                    return Err(serde::de::Error::custom(
                        "characteristics contain an invalid, duplicate, or reserved name",
                    ));
                }
                decoded.try_reserve(1).map_err(serde::de::Error::custom)?;
                name_hashes
                    .try_reserve(1)
                    .map_err(serde::de::Error::custom)?;
                name_hashes.insert(name_hash);
                decoded.push(characteristic);
            }
            Ok(decoded)
        }
    }

    deserializer.deserialize_seq(CharacteristicsVisitor)
}

fn validate_notes(
    version: &str,
    context: &str,
    notes: &[StataNote],
) -> Result<(), ArrowProfileError> {
    let mut previous = 0;
    for note in notes {
        if !crate::stata_metadata::valid_canonical_note(note.number, &note.text)
            || note.number <= previous
        {
            return Err(malformed(
                version,
                format!(
                    "{context} notes must have unique ascending numbers from 1 through 9999 and valid bounded text"
                ),
            ));
        }
        previous = note.number;
    }
    Ok(())
}

fn validate_characteristics(
    version: &str,
    context: &str,
    characteristics: &[StataCharacteristic],
) -> Result<(), ArrowProfileError> {
    let mut names = std::collections::HashSet::with_capacity(characteristics.len());
    for characteristic in characteristics {
        if !crate::stata_metadata::valid_canonical_characteristic(
            &characteristic.name,
            &characteristic.value,
        ) || !names.insert(characteristic.name.as_str())
        {
            return Err(malformed(
                version,
                format!(
                    "{context} characteristics contain an invalid, duplicate, or reserved name"
                ),
            ));
        }
    }
    Ok(())
}

fn hex_code_unit(bytes: &[u8]) -> Option<u16> {
    if bytes.len() != 4 {
        return None;
    }
    bytes.iter().try_fold(0_u16, |value, byte| {
        let digit = match byte {
            b'0'..=b'9' => u16::from(byte - b'0'),
            b'a'..=b'f' => u16::from(byte - b'a' + 10),
            b'A'..=b'F' => u16::from(byte - b'A' + 10),
            _ => return None,
        };
        value.checked_mul(16)?.checked_add(digit)
    })
}

/// Return the decoded UTF-8 length of a raw JSON string without allocating
/// its decoded contents. Invalid JSON is left to Serde's ordinary parser.
fn decoded_json_string_length(raw: &RawValue) -> Option<usize> {
    let bytes = raw.get().as_bytes();
    if bytes.len() < 2 || bytes.first() != Some(&b'"') || bytes.last() != Some(&b'"') {
        return None;
    }
    let mut index = 1;
    let end = bytes.len() - 1;
    let mut length = 0_usize;
    while index < end {
        if bytes[index] != b'\\' {
            let character = raw.get()[index..end].chars().next()?;
            let width = character.len_utf8();
            length = length.checked_add(width)?;
            index += width;
            continue;
        }
        index += 1;
        let escape = *bytes.get(index)?;
        index += 1;
        if escape != b'u' {
            if !matches!(
                escape,
                b'"' | b'\\' | b'/' | b'b' | b'f' | b'n' | b'r' | b't'
            ) {
                return None;
            }
            length = length.checked_add(1)?;
            continue;
        }
        let first = hex_code_unit(bytes.get(index..index + 4)?)?;
        index += 4;
        let codepoint = if (0xd800..=0xdbff).contains(&first) {
            if bytes.get(index..index + 2) != Some(b"\\u") {
                return None;
            }
            index += 2;
            let second = hex_code_unit(bytes.get(index..index + 4)?)?;
            index += 4;
            if !(0xdc00..=0xdfff).contains(&second) {
                return None;
            }
            0x1_0000 + (u32::from(first) - 0xd800) * 0x400 + (u32::from(second) - 0xdc00)
        } else if (0xdc00..=0xdfff).contains(&first) {
            return None;
        } else {
            u32::from(first)
        };
        length = length.checked_add(char::from_u32(codepoint)?.len_utf8())?;
    }
    (index == end).then_some(length)
}

fn raw_string_exceeds_limit(raw: &RawValue, limit: usize) -> bool {
    let bytes = raw.get().as_bytes();
    if bytes.len() >= 2
        && bytes.first() == Some(&b'"')
        && bytes.last() == Some(&b'"')
        && bytes.len() - 2 <= limit
    {
        // JSON escapes never expand beyond their encoded representation, so
        // a bounded interior is also bounded after decoding.
        return false;
    }
    decoded_json_string_length(raw).is_some_and(|length| length > limit)
}

fn validate_raw_string_length(
    version: &str,
    context: &str,
    raw: &RawValue,
    limit: usize,
) -> Result<(), ArrowProfileError> {
    if raw_string_exceeds_limit(raw, limit) {
        return Err(malformed(
            version,
            format!("{context} exceeds the {limit}-byte Stata metadata limit"),
        ));
    }
    Ok(())
}

fn decode_raw_metadata_string(
    version: &str,
    string_context: &str,
    invalid_document_context: &str,
    raw: &RawValue,
    limit: usize,
) -> Result<String, ArrowProfileError> {
    validate_raw_string_length(version, string_context, raw, limit)?;
    serde_json::from_str(raw.get()).map_err(|error| {
        malformed(
            version,
            format!("invalid {invalid_document_context}: {error}"),
        )
    })
}

fn decode_raw_notes(
    version: &str,
    context: &str,
    invalid_document_context: &str,
    notes: Vec<&RawValue>,
) -> Result<Vec<StataNote>, ArrowProfileError> {
    let mut decoded = Vec::with_capacity(notes.len());
    let note_context = format!("{context} note text");
    for note in notes {
        let number = u32::try_from(decoded.len() + 1)
            .map_err(|_| malformed(version, "Stata note count overflows"))?;
        if note.get().starts_with('"') {
            decoded.push(StataNote {
                number,
                text: decode_raw_metadata_string(
                    version,
                    &note_context,
                    invalid_document_context,
                    note,
                    crate::stata_metadata::MAX_DECODED_METADATA_VALUE_BYTES,
                )?,
            });
        } else {
            let numbered: RawNumberedNote<'_> =
                serde_json::from_str(note.get()).map_err(|error| {
                    malformed(
                        version,
                        format!("invalid {invalid_document_context}: {error}"),
                    )
                })?;
            decoded.push(StataNote {
                number: numbered.number,
                text: decode_raw_metadata_string(
                    version,
                    &note_context,
                    invalid_document_context,
                    numbered.text,
                    crate::stata_metadata::MAX_DECODED_METADATA_VALUE_BYTES,
                )?,
            });
        }
    }
    Ok(decoded)
}

fn deserialize_discarded_value_label<'de, D>(deserializer: D) -> Result<(), D::Error>
where
    D: serde::Deserializer<'de>,
{
    struct BoundedStringVisitor;

    impl<'de> Visitor<'de> for BoundedStringVisitor {
        type Value = ();

        fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
            formatter.write_str("a string within the 64 MiB Arrow metadata limit")
        }

        fn visit_str<E>(self, value: &str) -> Result<Self::Value, E>
        where
            E: serde::de::Error,
        {
            #[cfg(test)]
            DISCARDED_VALUE_LABEL_VISIT_COUNT.with(|count| count.set(count.get() + 1));
            if value.len() > super::MAX_IPC_METADATA_BYTES {
                return Err(E::custom(
                    "value-label text exceeds the 64 MiB Arrow metadata limit",
                ));
            }
            Ok(())
        }

        fn visit_borrowed_str<E>(self, value: &'de str) -> Result<Self::Value, E>
        where
            E: serde::de::Error,
        {
            self.visit_str(value)
        }

        fn visit_string<E>(self, value: String) -> Result<Self::Value, E>
        where
            E: serde::de::Error,
        {
            self.visit_str(&value)
        }
    }

    deserializer.deserialize_str(BoundedStringVisitor)
}

struct DiscardValueLabelEntries<'a> {
    table: &'a str,
}

impl<'de> DeserializeSeed<'de> for DiscardValueLabelEntries<'_> {
    type Value = ();

    fn deserialize<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct EntriesVisitor<'a> {
            table: &'a str,
        }

        impl<'de> Visitor<'de> for EntriesVisitor<'_> {
            type Value = ();

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("an array of value-label entries")
            }

            fn visit_seq<A>(self, mut sequence: A) -> Result<Self::Value, A::Error>
            where
                A: SeqAccess<'de>,
            {
                let mut index = 0_usize;
                while let Some(entry) = sequence.next_element::<DiscardedValueLabelEntry>()? {
                    if entry.value.is_some() == entry.tag.is_some() {
                        return Err(serde::de::Error::custom(format!(
                            "value-label table `{}` entry {index} must contain exactly one of `value` or `tag`",
                            self.table
                        )));
                    }
                    if entry.tag == Some(MissingTag::System) {
                        return Err(serde::de::Error::custom(format!(
                            "value-label table `{}` entry {index} uses system missing `.`; only nonmissing values and extended missing tags `.a` through `.z` are valid",
                            self.table
                        )));
                    }
                    index += 1;
                }
                Ok(())
            }
        }

        deserializer.deserialize_seq(EntriesVisitor { table: self.table })
    }
}

struct ValueLabelRegistrySeed<'a> {
    selected: Option<&'a HashMap<String, usize>>,
}

struct ValueLabelTableName<'a>(Cow<'a, str>);

impl<'a> ValueLabelTableName<'a> {
    fn as_str(&self) -> &str {
        self.0.as_ref()
    }

    fn into_cow(self) -> Cow<'a, str> {
        self.0
    }
}

impl<'de> Deserialize<'de> for ValueLabelTableName<'de> {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct TableNameVisitor;

        impl<'de> Visitor<'de> for TableNameVisitor {
            type Value = ValueLabelTableName<'de>;

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("a value-label table name")
            }

            fn visit_borrowed_str<E>(self, value: &'de str) -> Result<Self::Value, E> {
                #[cfg(test)]
                BORROWED_VALUE_LABEL_TABLE_NAME_COUNT.with(|count| count.set(count.get() + 1));
                Ok(ValueLabelTableName(Cow::Borrowed(value)))
            }

            fn visit_str<E>(self, value: &str) -> Result<Self::Value, E> {
                #[cfg(test)]
                OWNED_VALUE_LABEL_TABLE_NAME_COUNT.with(|count| count.set(count.get() + 1));
                Ok(ValueLabelTableName(Cow::Owned(value.to_owned())))
            }

            fn visit_string<E>(self, value: String) -> Result<Self::Value, E> {
                #[cfg(test)]
                OWNED_VALUE_LABEL_TABLE_NAME_COUNT.with(|count| count.set(count.get() + 1));
                Ok(ValueLabelTableName(Cow::Owned(value)))
            }
        }

        deserializer.deserialize_str(TableNameVisitor)
    }
}

impl<'de> DeserializeSeed<'de> for ValueLabelRegistrySeed<'_> {
    type Value = BTreeMap<String, Vec<ArrowValueLabelEntry>>;

    fn deserialize<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[cfg(test)]
        DATASET_VALUE_LABEL_REGISTRY_VISIT_COUNT.with(|count| count.set(count.get() + 1));
        struct RegistryVisitor<'a> {
            selected: Option<&'a HashMap<String, usize>>,
        }

        impl<'de> Visitor<'de> for RegistryVisitor<'_> {
            type Value = BTreeMap<String, Vec<ArrowValueLabelEntry>>;

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("an object of named value-label tables")
            }

            fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
            where
                A: MapAccess<'de>,
            {
                let mut retained = BTreeMap::new();
                let mut names: HashSet<Cow<'de, str>> = HashSet::new();
                let mut table_count = 0_usize;
                while let Some(name) = map.next_key::<ValueLabelTableName<'de>>()? {
                    table_count += 1;
                    if table_count > MAX_VALUE_LABEL_TABLES {
                        return Err(serde::de::Error::custom(
                            "value-label registry may contain at most 120,000 tables",
                        ));
                    }
                    if names.contains(name.as_str()) {
                        return Err(serde::de::Error::custom(format!(
                            "duplicate value-label table name `{}`",
                            name.as_str()
                        )));
                    }
                    names.try_reserve(1).map_err(|_| {
                        serde::de::Error::custom(
                            "could not allocate the value-label table-name index",
                        )
                    })?;
                    let retain = self
                        .selected
                        .is_none_or(|selected| selected.contains_key(name.as_str()));
                    if retain {
                        let entries = map.next_value::<Vec<ArrowValueLabelEntry>>()?;
                        retained.insert(name.as_str().to_owned(), entries);
                    } else {
                        map.next_value_seed(DiscardValueLabelEntries {
                            table: name.as_str(),
                        })?;
                    }
                    names.insert(name.into_cow());
                }
                Ok(retained)
            }
        }

        deserializer.deserialize_map(RegistryVisitor {
            selected: self.selected,
        })
    }
}

struct OptionalValueLabelRegistrySeed<'a> {
    selected: Option<&'a HashMap<String, usize>>,
}

impl<'de> DeserializeSeed<'de> for OptionalValueLabelRegistrySeed<'_> {
    type Value = BTreeMap<String, Vec<ArrowValueLabelEntry>>;

    fn deserialize<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct OptionalRegistryVisitor<'a> {
            selected: Option<&'a HashMap<String, usize>>,
        }

        impl<'de> Visitor<'de> for OptionalRegistryVisitor<'_> {
            type Value = BTreeMap<String, Vec<ArrowValueLabelEntry>>;

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("an object of named value-label tables or null")
            }

            fn visit_none<E>(self) -> Result<Self::Value, E> {
                Ok(BTreeMap::new())
            }

            fn visit_unit<E>(self) -> Result<Self::Value, E> {
                Ok(BTreeMap::new())
            }

            fn visit_some<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                ValueLabelRegistrySeed {
                    selected: self.selected,
                }
                .deserialize(deserializer)
            }
        }

        deserializer.deserialize_option(OptionalRegistryVisitor {
            selected: self.selected,
        })
    }
}

struct ParsedDatasetDocument<'a> {
    version: u32,
    output_container: Option<String>,
    label: String,
    notes: Vec<&'a RawValue>,
    characteristics: Vec<StataCharacteristic>,
    value_labels: BTreeMap<String, Vec<ArrowValueLabelEntry>>,
}

#[derive(Deserialize)]
struct RawNotes<'a>(#[serde(borrow, deserialize_with = "deserialize_raw_notes")] Vec<&'a RawValue>);

#[derive(Deserialize)]
struct RawCharacteristics(
    #[serde(deserialize_with = "deserialize_raw_characteristics")] Vec<StataCharacteristic>,
);

struct DatasetDocumentSeed<'a> {
    selected_value_labels: Option<&'a HashMap<String, usize>>,
}

impl<'de> DeserializeSeed<'de> for DatasetDocumentSeed<'_> {
    type Value = ParsedDatasetDocument<'de>;

    fn deserialize<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct DatasetVisitor<'a> {
            selected_value_labels: Option<&'a HashMap<String, usize>>,
        }

        impl<'de> Visitor<'de> for DatasetVisitor<'_> {
            type Value = ParsedDatasetDocument<'de>;

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("a dtatools dataset document")
            }

            fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
            where
                A: MapAccess<'de>,
            {
                const FIELDS: &[&str] = &[
                    "version",
                    "output_container",
                    "label",
                    "notes",
                    "characteristics",
                    "value_labels",
                ];
                let mut version = None;
                let mut output_container = None;
                let mut label = None;
                let mut notes = None;
                let mut characteristics = None;
                let mut value_labels = None;
                while let Some(key) = map.next_key::<String>()? {
                    match key.as_str() {
                        "version" => {
                            if version.is_some() {
                                return Err(serde::de::Error::duplicate_field("version"));
                            }
                            version = Some(map.next_value()?);
                        }
                        "output_container" => {
                            if output_container.is_some() {
                                return Err(serde::de::Error::duplicate_field(
                                    "output_container",
                                ));
                            }
                            output_container = Some(map.next_value()?);
                        }
                        "label" => {
                            if label.is_some() {
                                return Err(serde::de::Error::duplicate_field("label"));
                            }
                            label = Some(map.next_value()?);
                        }
                        "notes" => {
                            if notes.is_some() {
                                return Err(serde::de::Error::duplicate_field("notes"));
                            }
                            notes = Some(map.next_value::<RawNotes<'de>>()?.0);
                        }
                        "characteristics" => {
                            if characteristics.is_some() {
                                return Err(serde::de::Error::duplicate_field("characteristics"));
                            }
                            characteristics = Some(map.next_value::<RawCharacteristics>()?.0);
                        }
                        "value_labels" => {
                            if value_labels.is_some() {
                                return Err(serde::de::Error::duplicate_field("value_labels"));
                            }
                            value_labels =
                                Some(map.next_value_seed(OptionalValueLabelRegistrySeed {
                                    selected: self.selected_value_labels,
                                })?);
                        }
                        _ => return Err(serde::de::Error::unknown_field(&key, FIELDS)),
                    }
                }
                Ok(ParsedDatasetDocument {
                    version: version.ok_or_else(|| serde::de::Error::missing_field("version"))?,
                    output_container: output_container.unwrap_or(None),
                    label: label.unwrap_or_default(),
                    notes: notes.unwrap_or_default(),
                    characteristics: characteristics.unwrap_or_default(),
                    value_labels: value_labels.unwrap_or_default(),
                })
            }
        }

        deserializer.deserialize_map(DatasetVisitor {
            selected_value_labels: self.selected_value_labels,
        })
    }
}

#[cfg(test)]
thread_local! {
    static DATASET_VALUE_LABEL_REGISTRY_VISIT_COUNT: std::cell::Cell<usize> = const {
        std::cell::Cell::new(0)
    };
    static DISCARDED_VALUE_LABEL_VISIT_COUNT: std::cell::Cell<usize> = const {
        std::cell::Cell::new(0)
    };
    static BORROWED_VALUE_LABEL_TABLE_NAME_COUNT: std::cell::Cell<usize> = const {
        std::cell::Cell::new(0)
    };
    static OWNED_VALUE_LABEL_TABLE_NAME_COUNT: std::cell::Cell<usize> = const {
        std::cell::Cell::new(0)
    };
}

/// Per-buffer xxHash64 checksums, in canonical buffer order, for every column
/// of every record batch and for each dictionary field's values.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChecksumsDocument {
    pub version: u32,
    pub algorithm: String,
    pub batches: Vec<BatchChecksums>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub dictionaries: BTreeMap<String, Vec<String>>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
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

#[cfg(test)]
fn parse_dataset_document(
    version: &str,
    json: Option<&str>,
) -> Result<DatasetDocument, ArrowProfileError> {
    parse_dataset_document_selected(version, json, None)
}

pub(crate) fn parse_dataset_document_selected(
    version: &str,
    json: Option<&str>,
    selected_value_labels: Option<&HashMap<String, usize>>,
) -> Result<DatasetDocument, ArrowProfileError> {
    let Some(json) = json else {
        return Ok(DatasetDocument {
            version: DOCUMENT_VERSION,
            ..DatasetDocument::default()
        });
    };
    let mut deserializer = serde_json::Deserializer::from_str(json);
    let parsed = DatasetDocumentSeed {
        selected_value_labels,
    }
    .deserialize(&mut deserializer)
    .map_err(|error| malformed(version, format!("invalid dataset document: {error}")))?;
    deserializer
        .end()
        .map_err(|error| malformed(version, format!("invalid dataset document: {error}")))?;
    let document = DatasetDocument {
        version: parsed.version,
        output_container: parsed.output_container,
        label: parsed.label,
        notes: decode_raw_notes(version, "dataset", "dataset document", parsed.notes)?,
        characteristics: parsed.characteristics,
        value_labels: parsed.value_labels,
    };
    validate_dataset_document_inner(version, &document, false)?;
    Ok(document)
}

pub(crate) fn validate_dataset_document(
    version: &str,
    document: &DatasetDocument,
) -> Result<(), ArrowProfileError> {
    validate_dataset_document_inner(version, document, true)
}

fn validate_dataset_document_inner(
    version: &str,
    document: &DatasetDocument,
    check_characteristics: bool,
) -> Result<(), ArrowProfileError> {
    if document.version != DOCUMENT_VERSION {
        return Err(malformed(
            version,
            format!("dataset document version {}", document.version),
        ));
    }
    if document
        .output_container
        .as_deref()
        .is_some_and(|value| !matches!(value, "tibble" | "data.table"))
    {
        return Err(malformed(
            version,
            "dataset output_container must be `tibble` or `data.table`",
        ));
    }
    validate_notes(version, "dataset", &document.notes)?;
    if check_characteristics {
        validate_characteristics(version, "dataset", &document.characteristics)?;
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
            if entry.tag == Some(MissingTag::System) {
                return Err(malformed(
                    version,
                    format!(
                        "value-label table `{table}` entry {index} uses system missing `.`; only nonmissing values and extended missing tags `.a` through `.z` are valid"
                    ),
                ));
            }
        }
    }
    Ok(())
}

pub(crate) fn parse_field_document(
    version: &str,
    field: &Field,
    json: &str,
) -> Result<ArrowFieldDocument, ArrowProfileError> {
    parse_field_document_inner(version, field, json, true)
}

pub(crate) fn parse_field_document_tolerant(
    version: &str,
    field: &Field,
    json: &str,
) -> Result<ArrowFieldDocument, ArrowProfileError> {
    parse_field_document_inner(version, field, json, false)
}

fn parse_field_document_inner(
    version: &str,
    field: &Field,
    json: &str,
    reject_unknown: bool,
) -> Result<ArrowFieldDocument, ArrowProfileError> {
    let invalid = |error| {
        malformed(
            version,
            format!("invalid field document on `{}`: {error}", field.name()),
        )
    };
    let document = if reject_unknown {
        serde_json::from_str::<RawArrowFieldDocument<'_>>(json)
            .map_err(invalid)?
            .decode(version, field)?
    } else {
        serde_json::from_str::<TolerantRawArrowFieldDocument<'_>>(json)
            .map_err(invalid)?
            .decode(version, field)?
    };
    validate_field_document_inner(version, field, &document, false)?;
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

pub(crate) fn validate_field_document(
    version: &str,
    field: &Field,
    document: &ArrowFieldDocument,
) -> Result<(), ArrowProfileError> {
    validate_field_document_inner(version, field, document, true)
}

fn validate_field_document_inner(
    version: &str,
    field: &Field,
    document: &ArrowFieldDocument,
    check_characteristics: bool,
) -> Result<(), ArrowProfileError> {
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
    if let Some(string_storage) = document.string_storage.as_deref() {
        let fixed_width = string_storage
            .strip_prefix("str")
            .and_then(|width| {
                if width.starts_with('0') {
                    None
                } else {
                    width.parse::<u16>().ok()
                }
            })
            .is_some_and(|width| (1..=2045).contains(&width));
        if string_storage != "strL" && !fixed_width {
            return Err(field_malformed(
                version,
                field,
                format!("declares invalid string storage `{string_storage}`"),
            ));
        }
        if document.storage.is_some() || field.data_type() != &DataType::Utf8 {
            return Err(field_malformed(
                version,
                field,
                format!(
                    "declares string storage incompatible with Arrow type {}",
                    field.data_type()
                ),
            ));
        }
    }
    let context = format!("field `{}`", field.name());
    validate_notes(version, &context, &document.notes)?;
    if check_characteristics {
        validate_characteristics(version, &context, &document.characteristics)?;
    }
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
        if document.missing_release.is_some() && storage == StataStorage::Double {
            return Err(field_malformed(
                version,
                field,
                "declares a source missing release for double storage",
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

    if document.missing_release.is_some() {
        return Err(field_malformed(
            version,
            field,
            "declares a source missing release without Stata storage",
        ));
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

pub(crate) fn validate_value_label_reference(
    version: &str,
    field: &Field,
    document: &ArrowFieldDocument,
    dataset: &DatasetDocument,
) -> Result<(), ArrowProfileError> {
    let Some(table) = document.value_labels.as_deref() else {
        return Ok(());
    };
    if dataset.value_labels.contains_key(table) {
        return Ok(());
    }
    Err(malformed(
        version,
        format!(
            "field `{}` refers to missing value-label table `{table}`",
            field.name()
        ),
    ))
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
    fn dataset_output_container_is_optional_and_validated() {
        let absent = parse_dataset_document("0", Some(r#"{"version":0}"#))
            .expect("old documents remain readable");
        assert_eq!(absent.output_container, None);

        for container in ["tibble", "data.table"] {
            let json = format!(
                r#"{{"version":0,"output_container":"{container}"}}"#
            );
            let document = parse_dataset_document("0", Some(&json))
                .expect("supported output container parses");
            assert_eq!(document.output_container.as_deref(), Some(container));
        }

        let error = parse_dataset_document(
            "0",
            Some(r#"{"version":0,"output_container":"matrix"}"#),
        )
        .expect_err("unknown output containers are rejected");
        assert!(error.to_string().contains("output_container"));
    }

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
    fn value_label_entries_reject_system_missing() {
        let error = parse_dataset_document(
            "0",
            Some(r#"{"version":0,"value_labels":{"x":[{"tag":".","label":"missing"}]}}"#),
        )
        .expect_err("system missing is not a valid value-label code");
        assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
        assert!(error.to_string().contains("system missing"));
    }

    #[test]
    fn discarded_value_label_entries_still_validate_label_types() {
        let selected = HashMap::new();
        let error = parse_dataset_document_selected(
            "0",
            Some(r#"{"version":0,"value_labels":{"unselected":[{"value":1,"label":7}]}}"#),
            Some(&selected),
        )
        .expect_err("discarded tables still validate their entry schema");
        assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
        assert!(error.to_string().contains("expected a string"));
    }

    #[test]
    fn projected_registry_is_consumed_once_without_reparsing_discarded_labels() {
        let selected = HashMap::from([("selected".to_owned(), 1)]);
        DATASET_VALUE_LABEL_REGISTRY_VISIT_COUNT.with(|count| count.set(0));
        DISCARDED_VALUE_LABEL_VISIT_COUNT.with(|count| count.set(0));

        let document = parse_dataset_document_selected(
            "0",
            Some(
                r#"{"version":0,"value_labels":{"selected":[{"value":1,"label":"one"}],"discarded":[{"value":2,"label":"t\u0077o"}]}}"#,
            ),
            Some(&selected),
        )
        .expect("the selected table is retained and the other table is validated");

        assert_eq!(document.value_labels.len(), 1);
        assert!(document.value_labels.contains_key("selected"));
        assert_eq!(
            DATASET_VALUE_LABEL_REGISTRY_VISIT_COUNT.with(std::cell::Cell::get),
            1,
            "the top-level parser must send the registry through one seed"
        );
        assert_eq!(
            DISCARDED_VALUE_LABEL_VISIT_COUNT.with(std::cell::Cell::get),
            1,
            "the active deserializer must validate each discarded label once"
        );
    }

    #[test]
    fn full_and_projected_registries_reject_more_than_stata_variable_limit() {
        let mut json = String::from(r#"{"version":0,"value_labels":{"#);
        for index in 0..MAX_VALUE_LABEL_TABLES {
            if index > 0 {
                json.push(',');
            }
            json.push_str(&format!(r#""table{index}":[]"#));
        }
        json.push_str("}}");

        let selected = HashMap::new();
        let full = parse_dataset_document_selected("0", Some(&json), None)
            .expect("the Stata table limit is accepted on a full read");
        assert_eq!(full.value_labels.len(), MAX_VALUE_LABEL_TABLES);
        let projected = parse_dataset_document_selected("0", Some(&json), Some(&selected))
            .expect("the Stata table limit is accepted on a projected read");
        assert!(projected.value_labels.is_empty());

        json.truncate(json.len() - 2);
        json.push_str(&format!(r#","table{MAX_VALUE_LABEL_TABLES}":[]}}}}"#));
        for selection in [None, Some(&selected)] {
            let error = match parse_dataset_document_selected("0", Some(&json), selection) {
                Ok(_) => panic!("a registry cannot exceed Stata's variable limit"),
                Err(error) => error,
            };
            assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
            assert!(
                error.to_string().contains("at most 120,000 tables"),
                "unexpected error: {error}"
            );
        }
    }

    #[test]
    fn projected_registry_borrows_plain_keys_until_table_limit() {
        use std::fmt::Write as _;

        const TABLE_NAME_BYTES: usize = 540;
        let padding = "x".repeat(TABLE_NAME_BYTES - "table000000".len());
        let mut json = String::with_capacity(crate::arrow::MAX_IPC_METADATA_BYTES);
        json.push_str(r#"{"version":0,"value_labels":{"#);
        for index in 0..=MAX_VALUE_LABEL_TABLES {
            if index > 0 {
                json.push(',');
            }
            write!(&mut json, "\"table{index:06}").expect("writing to a string cannot fail");
            json.push_str(&padding);
            json.push_str("\":[]");
        }
        json.push_str("}}");
        assert!(json.len() <= crate::arrow::MAX_IPC_METADATA_BYTES);
        assert!(crate::arrow::MAX_IPC_METADATA_BYTES - json.len() < 2 * 1024 * 1024);

        BORROWED_VALUE_LABEL_TABLE_NAME_COUNT.with(|count| count.set(0));
        OWNED_VALUE_LABEL_TABLE_NAME_COUNT.with(|count| count.set(0));
        let selected = HashMap::new();
        let error = parse_dataset_document_selected("0", Some(&json), Some(&selected))
            .expect_err("the extra table is rejected before its value is decoded");

        assert!(error.to_string().contains("at most 120,000 tables"));
        assert_eq!(
            BORROWED_VALUE_LABEL_TABLE_NAME_COUNT.with(std::cell::Cell::get),
            MAX_VALUE_LABEL_TABLES + 1,
            "plain registry keys should be borrowed directly from the metadata JSON"
        );
        assert_eq!(
            OWNED_VALUE_LABEL_TABLE_NAME_COUNT.with(std::cell::Cell::get),
            0,
            "duplicate detection should not allocate copies of plain registry keys"
        );
    }

    #[test]
    fn dataset_documents_reject_unknown_keys() {
        for json in [
            r#"{"version":0,"lable":"typo"}"#,
            r#"{"version":0,"notes":[{"number":1,"text":"note","extra":true}]}"#,
            r#"{"version":0,"characteristics":[{"name":"source","value":"fixture","extra":true}]}"#,
            r#"{"version":0,"value_labels":{"x":[{"value":1,"label":"one","lable":"typo"}]}}"#,
        ] {
            let error = parse_dataset_document("0", Some(json))
                .expect_err("unknown dataset keys are rejected");
            assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
            assert!(error.to_string().contains("unknown field"));
        }
    }

    #[test]
    fn dataset_documents_reject_duplicate_keys() {
        for json in [
            r#"{"version":0,"version":0}"#,
            r#"{"version":0,"label":"a","label":"b"}"#,
            r#"{"version":0,"value_labels":{},"value_labels":{}}"#,
            r#"{"version":0,"value_labels":{"x":[],"x":[]}}"#,
            r#"{"version":0,"value_labels":{"x":[],"\u0078":[]}}"#,
        ] {
            let error = parse_dataset_document("0", Some(json))
                .expect_err("duplicate dataset keys are rejected");
            assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
            assert!(error.to_string().contains("duplicate"));
        }
    }

    #[test]
    fn null_or_omitted_value_label_registries_are_empty() {
        for json in [r#"{"version":0}"#, r#"{"version":0,"value_labels":null}"#] {
            let document =
                parse_dataset_document("0", Some(json)).expect("empty registries are valid");
            assert!(document.value_labels.is_empty());
        }
    }

    #[test]
    fn note_arrays_are_bounded_during_deserialization() {
        let prefix = vec!["\"\""; 9_999].join(",");
        for final_note in ["\"\"".to_owned(), format!("\"{}\"", "x".repeat(1 << 20))] {
            let json = format!(r#"{{"version":0,"notes":[{prefix},{final_note}]}}"#);
            let error = parse_dataset_document("0", Some(&json))
                .expect_err("the ten-thousandth note is rejected while decoding JSON");
            assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
            assert!(error.to_string().contains("at most 9,999 entries"));
        }
    }

    #[test]
    fn note_and_characteristic_strings_are_bounded_before_deserialization() {
        let oversized = "x".repeat(1 << 20);
        for json in [
            format!(r#"{{"version":0,"notes":[{{"number":1,"text":"{oversized}"}}]}}"#),
            format!(
                r#"{{"version":0,"characteristics":[{{"name":"source","value":"{oversized}"}}]}}"#
            ),
            format!(r#"{{"version":0,"characteristics":[{{"name":"{oversized}","value":"x"}}]}}"#),
        ] {
            let error = parse_dataset_document("0", Some(&json))
                .expect_err("oversized metadata strings are rejected before decoding");
            assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
            assert!(error.to_string().contains("Stata metadata limit"));
        }
    }

    #[test]
    fn invalid_characteristic_stops_before_later_json_is_parsed() {
        let error = parse_dataset_document(
            "0",
            Some(r#"{"version":0,"characteristics":[{"name":"","value":""},invalid]}"#),
        )
        .expect_err("the first invalid characteristic stops the sequence");
        assert!(
            error
                .to_string()
                .contains("invalid, duplicate, or reserved name"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn decoded_duplicate_characteristic_stops_before_later_json_is_parsed() {
        let error = parse_dataset_document(
            "0",
            Some(
                r#"{"version":0,"characteristics":[{"name":"source","value":"first"},{"name":"sour\u0063e","value":"second"},invalid]}"#,
            ),
        )
        .expect_err("the decoded duplicate stops the sequence");
        assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
        assert!(
            error
                .to_string()
                .contains("invalid, duplicate, or reserved name"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn metadata_string_bounds_count_decoded_json_bytes() {
        let accepted = r#"\u754c"#.repeat(67_784);
        let json = format!(r#"{{"version":0,"notes":[{{"number":1,"text":"{accepted}"}}]}}"#);
        parse_dataset_document("0", Some(&json)).expect("203,352 decoded bytes fit");

        let oversized = r#"\u754c"#.repeat(67_785);
        let json = format!(r#"{{"version":0,"notes":[{{"number":1,"text":"{oversized}"}}]}}"#);
        let error = parse_dataset_document("0", Some(&json))
            .expect_err("203,355 decoded bytes exceed the canonical limit");
        assert!(
            error.to_string().contains("203352-byte"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn field_documents_reject_unknown_keys() {
        let field = Field::new("x", DataType::Int32, true);
        for json in [
            r#"{"version":0,"lable":"typo"}"#,
            r#"{"version":0,"r":{"class":"integer","ordred":true}}"#,
        ] {
            let error = parse_field_document("0", &field, json)
                .expect_err("unknown field-document keys are rejected");
            assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
            assert!(error.to_string().contains("unknown field"));
        }
    }

    #[test]
    fn field_documents_reject_invalid_string_storage() {
        let text = Field::new("text", DataType::Utf8, true);
        for declaration in ["str0", "str01", "str2046", "STR12"] {
            let json = format!(r#"{{"version":0,"string_storage":"{declaration}"}}"#);
            let error = parse_field_document("0", &text, &json)
                .expect_err("invalid string storage is rejected");
            assert!(error.to_string().contains("string storage"));
        }

        for field in [
            Field::new("number", DataType::Int32, true),
            Field::new("large", DataType::LargeUtf8, true),
        ] {
            let error =
                parse_field_document("0", &field, r#"{"version":0,"string_storage":"str12"}"#)
                    .expect_err("string storage requires a UTF-8 field");
            assert!(error.to_string().contains("string storage"));
        }
    }

    #[test]
    fn checksum_documents_reject_unknown_keys() {
        for json in [
            r#"{"version":0,"algorithm":"xxh64","batches":[],"batchs":[]}"#,
            r#"{"version":0,"algorithm":"xxh64","batches":[{"columns":[],"colums":[]}]}"#,
        ] {
            let error = parse_checksums_document("0", json)
                .expect_err("unknown checksum keys are rejected");
            assert!(matches!(error, ArrowProfileError::MalformedProfile { .. }));
            assert!(error.to_string().contains("unknown field"));
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
