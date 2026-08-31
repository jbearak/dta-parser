use std::{collections::HashMap, sync::Arc};

use unicode_general_category::{get_general_category, GeneralCategory};

use crate::{DtaError, StataCharacteristic, StataNote, VariableInfo};

pub(crate) const MAX_NOTE_NUMBER: u32 = 9_999;
/// Maximum bytes in one DTA metadata value before source text decoding.
pub(crate) const MAX_METADATA_VALUE_BYTES: usize = 67_784;
/// Maximum canonical UTF-8 bytes after decoding a bounded legacy value.
pub(crate) const MAX_DECODED_METADATA_VALUE_BYTES: usize = MAX_METADATA_VALUE_BYTES * 3;
pub(crate) const MAX_CHARACTERISTIC_NAME_BYTES: usize = 128;

pub(crate) fn validate_raw_value_length(
    length_with_optional_nul: usize,
    offset: usize,
    context: &'static str,
) -> Result<(), DtaError> {
    if length_with_optional_nul > MAX_METADATA_VALUE_BYTES.saturating_add(1) {
        return Err(DtaError::MetadataValueTooLong {
            context,
            offset,
            length: length_with_optional_nul,
            limit: MAX_METADATA_VALUE_BYTES + 1,
        });
    }
    Ok(())
}

pub(crate) fn validate_raw_value_bytes<'a>(
    bytes: &'a [u8],
    offset: usize,
    context: &'static str,
) -> Result<&'a [u8], DtaError> {
    let length = bytes
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(bytes.len());
    if length > MAX_METADATA_VALUE_BYTES {
        return Err(DtaError::MetadataValueTooLong {
            context,
            offset,
            length,
            limit: MAX_METADATA_VALUE_BYTES,
        });
    }
    Ok(&bytes[..length])
}

pub(crate) fn note_index(name: &[u8]) -> Option<u32> {
    let index = name.strip_prefix(b"note")?;
    if index.is_empty() || index.first() == Some(&b'0') || !index.iter().all(u8::is_ascii_digit) {
        return None;
    }
    let index = std::str::from_utf8(index).ok()?.parse().ok()?;
    (1..=MAX_NOTE_NUMBER).contains(&index).then_some(index)
}

pub(crate) fn is_reserved_note_name(name: &[u8]) -> bool {
    let Some(suffix) = name.strip_prefix(b"note") else {
        return false;
    };
    !suffix.is_empty() && suffix.iter().all(u8::is_ascii_digit)
}

pub(crate) fn is_structural_characteristic(name: &str) -> bool {
    matches!(name, "_lang_list" | "_lang_c")
        || name.starts_with("_lang_v_")
        || name.starts_with("_lang_l_")
}

fn stata_name_letter(character: char) -> bool {
    matches!(
        get_general_category(character),
        GeneralCategory::UppercaseLetter
            | GeneralCategory::LowercaseLetter
            | GeneralCategory::TitlecaseLetter
            | GeneralCategory::ModifierLetter
            | GeneralCategory::OtherLetter
    )
}

fn stata_name_number(character: char) -> bool {
    matches!(
        get_general_category(character),
        GeneralCategory::DecimalNumber
            | GeneralCategory::LetterNumber
            | GeneralCategory::OtherNumber
    )
}

pub(crate) fn valid_stata_name_syntax(name: &str, maximum_characters: usize) -> bool {
    let mut characters = name.chars();
    let Some(first) = characters.next() else {
        return false;
    };
    (first == '_' || stata_name_letter(first))
        && characters.all(|character| {
            character == '_' || stata_name_letter(character) || stata_name_number(character)
        })
        && name.chars().count() <= maximum_characters
}

pub(crate) fn valid_metadata_value(value: &str) -> bool {
    !value.contains('\0') && value.len() <= MAX_METADATA_VALUE_BYTES
}

pub(crate) fn valid_decoded_metadata_value(value: &str) -> bool {
    !value.contains('\0')
        && value.chars().count() <= MAX_METADATA_VALUE_BYTES
        && value.len() <= MAX_DECODED_METADATA_VALUE_BYTES
}

pub fn valid_note(number: u32, text: &str) -> bool {
    (1..=MAX_NOTE_NUMBER).contains(&number) && valid_metadata_value(text)
}

pub(crate) fn valid_characteristic_name(name: &str) -> bool {
    valid_stata_name_syntax(name, 32)
        && name.len() <= MAX_CHARACTERISTIC_NAME_BYTES
        && !is_reserved_note_name(name.as_bytes())
        && !is_structural_characteristic(name)
}

pub fn valid_characteristic(name: &str, value: &str) -> bool {
    valid_characteristic_name(name) && valid_metadata_value(value)
}

/// Whether a note decoded from a bounded DTA source or Arrow profile is valid.
pub fn valid_canonical_note(number: u32, text: &str) -> bool {
    (1..=MAX_NOTE_NUMBER).contains(&number) && valid_decoded_metadata_value(text)
}

/// Whether a characteristic decoded from a bounded DTA source or Arrow profile is valid.
pub fn valid_canonical_characteristic(name: &str, value: &str) -> bool {
    valid_characteristic_name(name) && valid_decoded_metadata_value(value)
}

struct PendingCharacteristic {
    name: Arc<String>,
    value: String,
}

#[derive(Default)]
struct ScopeMetadata {
    notes: Vec<StataNote>,
    characteristics: Vec<PendingCharacteristic>,
    note_indexes: HashMap<u32, usize>,
    characteristic_indexes: HashMap<Arc<String>, usize>,
}

impl ScopeMetadata {
    fn push(&mut self, key: MetadataKey, value: String) {
        if let MetadataKey::Note(number) = key {
            if let Some(index) = self.note_indexes.get(&number).copied() {
                self.notes[index].text = value;
            } else {
                self.note_indexes.insert(number, self.notes.len());
                self.notes.push(StataNote {
                    number,
                    text: value,
                });
            }
        } else if let MetadataKey::Characteristic(name) = key {
            if let Some(index) = self.characteristic_indexes.get(&name).copied() {
                self.characteristics[index].value = value;
            } else {
                let name = Arc::new(name);
                self.characteristic_indexes
                    .insert(Arc::clone(&name), self.characteristics.len());
                self.characteristics
                    .push(PendingCharacteristic { name, value });
            }
        }
    }

    fn finish(mut self) -> (Vec<StataNote>, Vec<StataCharacteristic>) {
        self.notes.sort_by_key(|note| note.number);
        drop(self.characteristic_indexes);
        let characteristics = self
            .characteristics
            .into_iter()
            .map(|item| StataCharacteristic {
                name: Arc::try_unwrap(item.name).unwrap_or_else(|shared| shared.as_ref().clone()),
                value: item.value,
            })
            .collect();
        (self.notes, characteristics)
    }
}

enum MetadataKey {
    Note(u32),
    Characteristic(String),
}

pub(crate) struct AcceptedCharacteristic {
    target_index: Option<usize>,
    key: MetadataKey,
}

/// Resolves variable targets lazily so dataset-only or rejected metadata does
/// not clone or index every variable name in a wide file.
pub(crate) struct VariableTargetIndexes<'a> {
    variables: &'a [VariableInfo],
    indexes: Option<HashMap<&'a str, usize>>,
}

impl<'a> VariableTargetIndexes<'a> {
    pub(crate) fn new(variables: &'a [VariableInfo]) -> Self {
        Self {
            variables,
            indexes: None,
        }
    }

    pub(crate) fn resolve(&mut self, target: &str) -> Option<usize> {
        self.indexes
            .get_or_insert_with(|| {
                self.variables
                    .iter()
                    .enumerate()
                    .map(|(index, variable)| (variable.name.as_str(), index))
                    .collect()
            })
            .get(target)
            .copied()
    }
}

/// Classifies a raw record before a collector is allocated or its value is
/// decoded. The resolver is called only for an accepted variable-scoped key.
pub(crate) fn classify_characteristic(
    target: &str,
    name: String,
    offset: usize,
    resolve_variable: impl FnOnce(&str) -> Option<usize>,
) -> Result<Option<AcceptedCharacteristic>, DtaError> {
    if !valid_stata_name_syntax(&name, 32) || name.len() > MAX_CHARACTERISTIC_NAME_BYTES {
        return Err(DtaError::InvalidCharacteristicName { name, offset });
    }
    let key = if let Some(number) = note_index(name.as_bytes()) {
        MetadataKey::Note(number)
    } else if is_reserved_note_name(name.as_bytes()) || is_structural_characteristic(&name) {
        return Ok(None);
    } else {
        MetadataKey::Characteristic(name)
    };
    let target_index = if target == "_dta" {
        None
    } else {
        let Some(index) = resolve_variable(target) else {
            return Ok(None);
        };
        Some(index)
    };
    Ok(Some(AcceptedCharacteristic { target_index, key }))
}

/// Folds raw DTA characteristic records into their canonical scopes.
///
/// Unknown targets, numeric note control records, and known structural keys
/// are rejected before their values need to be decoded. Duplicate keys retain
/// their first position and replace their value in constant expected time.
#[derive(Default)]
pub(crate) struct CharacteristicCollector {
    dataset: Option<Box<ScopeMetadata>>,
    variables: HashMap<usize, Box<ScopeMetadata>>,
}

impl CharacteristicCollector {
    pub(crate) fn push(&mut self, accepted: AcceptedCharacteristic, value: String) {
        match accepted.target_index {
            None => self
                .dataset
                .get_or_insert_with(Default::default)
                .push(accepted.key, value),
            Some(index) => self
                .variables
                .entry(index)
                .or_default()
                .push(accepted.key, value),
        }
    }

    pub(crate) fn finish(
        self,
        dataset_notes: &mut Vec<StataNote>,
        dataset_characteristics: &mut Vec<StataCharacteristic>,
        variables: &mut [VariableInfo],
    ) {
        let (notes, characteristics) = self.dataset.unwrap_or_default().finish();
        *dataset_notes = notes;
        *dataset_characteristics = characteristics;
        for (index, metadata) in self.variables {
            if let Some(variable) = variables.get_mut(index) {
                let (notes, characteristics) = metadata.finish();
                variable.notes = notes;
                variable.characteristics = characteristics;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::DtaType;

    #[test]
    fn characteristic_records_preserve_scope_gaps_and_last_duplicate_values() {
        let mut dataset_notes = Vec::new();
        let mut dataset_characteristics = Vec::new();
        let mut variables = vec![VariableInfo {
            name: "x".into(),
            dta_type: DtaType::Byte,
            type_code: 65530,
            format: "%8.0g".into(),
            label: String::new(),
            value_label_name: String::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            byte_width: 1,
            byte_offset: 0,
        }];
        let records = [
            ("_dta", "note3", "three"),
            ("_dta", "note1", ""),
            ("_dta", "note01", "reserved"),
            ("_dta", "source", "old"),
            ("_dta", "source", "new"),
            ("_dta", "note0", "9"),
            ("_dta", "note10000", "reserved"),
            ("_dta", "_lang_list", "default"),
            ("_dta", "_lang_v_en", "English label"),
            ("x", "_lang_l_en", "English value label"),
            ("x", "note2", "variable"),
            ("x", "role", "id"),
            ("missing", "source", "ignored"),
        ]
        .into_iter();
        let mut collector = CharacteristicCollector::default();
        let mut variable_indexes = VariableTargetIndexes::new(&variables);
        for (target, name, value) in records {
            if let Some(accepted) = classify_characteristic(target, name.into(), 0, |target| {
                variable_indexes.resolve(target)
            })
            .expect("valid raw characteristic")
            {
                collector.push(accepted, value.into());
            }
        }
        drop(variable_indexes);
        collector.finish(
            &mut dataset_notes,
            &mut dataset_characteristics,
            &mut variables,
        );

        assert_eq!(
            dataset_notes,
            vec![
                StataNote {
                    number: 1,
                    text: String::new(),
                },
                StataNote {
                    number: 3,
                    text: "three".into(),
                },
            ]
        );
        assert_eq!(
            dataset_characteristics,
            vec![StataCharacteristic {
                name: "source".into(),
                value: "new".into(),
            }]
        );
        assert_eq!(
            variables[0].notes,
            vec![StataNote {
                number: 2,
                text: "variable".into(),
            }]
        );
        assert_eq!(
            variables[0].characteristics,
            vec![StataCharacteristic {
                name: "role".into(),
                value: "id".into(),
            }]
        );
    }

    #[test]
    fn duplicate_variable_names_target_the_last_variable_without_panicking() {
        let variable = VariableInfo {
            name: "x".into(),
            dta_type: DtaType::Byte,
            type_code: 65530,
            format: "%8.0g".into(),
            label: String::new(),
            value_label_name: String::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            byte_width: 1,
            byte_offset: 0,
        };
        let mut variables = vec![variable.clone(), variable];
        let mut collector = CharacteristicCollector::default();
        let mut variable_indexes = VariableTargetIndexes::new(&variables);
        let accepted = classify_characteristic("x", "role".into(), 0, |target| {
            variable_indexes.resolve(target)
        })
        .expect("valid raw characteristic")
        .expect("the duplicate target resolves");
        collector.push(accepted, "id".into());
        drop(variable_indexes);
        collector.finish(&mut Vec::new(), &mut Vec::new(), &mut variables);

        assert!(variables[0].characteristics.is_empty());
        assert_eq!(variables[1].characteristics[0].value, "id");
    }

    #[test]
    fn dataset_and_structural_records_do_not_build_variable_indexes() {
        let dataset = classify_characteristic("_dta", "source".into(), 0, |_| {
            panic!("dataset metadata must not resolve variable names")
        })
        .expect("valid raw characteristic");
        assert!(dataset.is_some());

        let structural = classify_characteristic("x", "_lang_v_en".into(), 0, |_| {
            panic!("structural metadata must not resolve variable names")
        })
        .expect("valid structural characteristic");
        assert!(structural.is_none());
    }
}
