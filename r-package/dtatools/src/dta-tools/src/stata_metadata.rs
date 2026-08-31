use std::collections::HashMap;

use unicode_general_category::{get_general_category, GeneralCategory};

use crate::{DtaError, StataCharacteristic, StataNote, VariableInfo};

pub(crate) const MAX_NOTE_NUMBER: u32 = 9_999;
pub(crate) const MAX_METADATA_VALUE_BYTES: usize = 67_784;
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

pub(crate) fn note_index(name: &[u8]) -> Option<u32> {
    let index = name.strip_prefix(b"note")?;
    if index.is_empty() || !index.iter().all(u8::is_ascii_digit) {
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

pub(crate) fn valid_note(number: u32, text: &str) -> bool {
    (1..=MAX_NOTE_NUMBER).contains(&number) && valid_metadata_value(text)
}

pub(crate) fn valid_characteristic(name: &str, value: &str) -> bool {
    valid_stata_name_syntax(name, 32)
        && name.len() <= MAX_CHARACTERISTIC_NAME_BYTES
        && !is_reserved_note_name(name.as_bytes())
        && !is_structural_characteristic(name)
        && valid_metadata_value(value)
}

#[derive(Default)]
struct ScopeMetadata {
    notes: Vec<StataNote>,
    characteristics: Vec<StataCharacteristic>,
    note_indexes: HashMap<u32, usize>,
    characteristic_indexes: HashMap<String, usize>,
}

impl ScopeMetadata {
    fn push(&mut self, name: String, value: String) {
        if let Some(number) = note_index(name.as_bytes()) {
            if let Some(index) = self.note_indexes.get(&number).copied() {
                self.notes[index].text = value;
            } else {
                self.note_indexes.insert(number, self.notes.len());
                self.notes.push(StataNote {
                    number,
                    text: value,
                });
            }
        } else if let Some(index) = self.characteristic_indexes.get(&name).copied() {
            self.characteristics[index].value = value;
        } else {
            self.characteristic_indexes
                .insert(name.clone(), self.characteristics.len());
            self.characteristics
                .push(StataCharacteristic { name, value });
        }
    }

    fn finish(mut self) -> (Vec<StataNote>, Vec<StataCharacteristic>) {
        self.notes.sort_by_key(|note| note.number);
        (self.notes, self.characteristics)
    }
}

/// Folds raw DTA characteristic records into their canonical scopes.
///
/// Unknown targets, numeric note control records, and known structural keys
/// are rejected before their values need to be decoded. Duplicate keys retain
/// their first position and replace their value in constant expected time.
pub(crate) struct CharacteristicCollector {
    dataset: ScopeMetadata,
    variables: Vec<ScopeMetadata>,
    variable_indexes: HashMap<String, usize>,
}

impl CharacteristicCollector {
    pub(crate) fn new(variables: &[VariableInfo]) -> Self {
        Self::from_variable_names(variables.iter().map(|variable| variable.name.clone()))
    }

    pub(crate) fn from_variable_names(variable_names: impl IntoIterator<Item = String>) -> Self {
        let variable_indexes = variable_names
            .into_iter()
            .enumerate()
            .map(|(index, name)| (name, index))
            .collect::<HashMap<_, _>>();
        Self {
            dataset: ScopeMetadata::default(),
            variables: (0..variable_indexes.len())
                .map(|_| ScopeMetadata::default())
                .collect(),
            variable_indexes,
        }
    }

    fn target_index(&self, target: &str) -> Option<Option<usize>> {
        if target == "_dta" {
            Some(None)
        } else {
            self.variable_indexes.get(target).copied().map(Some)
        }
    }

    pub(crate) fn accepts(&self, target: &str, name: &str) -> bool {
        self.target_index(target).is_some()
            && (note_index(name.as_bytes()).is_some()
                || (!is_reserved_note_name(name.as_bytes()) && !is_structural_characteristic(name)))
    }

    pub(crate) fn push(&mut self, target: String, name: String, value: String) {
        let Some(target_index) = self.target_index(&target) else {
            return;
        };
        if !self.accepts(&target, &name) {
            return;
        }
        match target_index {
            None => self.dataset.push(name, value),
            Some(index) => self.variables[index].push(name, value),
        }
    }

    pub(crate) fn finish(
        self,
        dataset_notes: &mut Vec<StataNote>,
        dataset_characteristics: &mut Vec<StataCharacteristic>,
        variables: &mut [VariableInfo],
    ) {
        let (notes, characteristics) = self.dataset.finish();
        *dataset_notes = notes;
        *dataset_characteristics = characteristics;
        for (variable, metadata) in variables.iter_mut().zip(self.variables) {
            let (notes, characteristics) = metadata.finish();
            variable.notes = notes;
            variable.characteristics = characteristics;
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
            ("_dta", "source", "old"),
            ("_dta", "source", "new"),
            ("_dta", "note0", "9"),
            ("_dta", "note10000", "reserved"),
            ("_dta", "_lang_list", "default"),
            ("x", "note2", "variable"),
            ("x", "role", "id"),
            ("missing", "source", "ignored"),
        ]
        .into_iter();
        let mut collector = CharacteristicCollector::new(&variables);
        for (target, name, value) in records {
            collector.push(target.into(), name.into(), value.into());
        }
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
}
