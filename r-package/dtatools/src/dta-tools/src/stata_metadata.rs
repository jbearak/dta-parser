use std::collections::HashMap;

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
    matches!(
        name,
        "_lang_list" | "_lang_c" | "fralias_from" | "fralias_varname"
    ) || name.starts_with("_lang_v_")
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

#[derive(Debug, PartialEq, Eq, Hash)]
enum MetadataKey {
    Note(u32),
    Characteristic(String),
}

#[derive(Debug, PartialEq, Eq, Hash)]
pub(crate) struct AcceptedCharacteristic {
    target_index: Option<usize>,
    key: MetadataKey,
}

/// How a source adapter should handle a framed characteristic value. Retained
/// values are decoded after the complete section has been framed. Rejected
/// values still require bounded validation so their errors keep source order.
/// Once an earlier semantic error exists, later values only need framing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CharacteristicValueUse {
    Retain,
    Validate,
    Skip,
}

struct PlannedCharacteristic<L> {
    first_ordinal: usize,
    value_ordinal: usize,
    value: L,
}

struct DecodedCharacteristic {
    first_ordinal: usize,
    accepted: AcceptedCharacteristic,
    value: String,
}

/// Unique decoded records in first-occurrence order. The framing plan already
/// resolves duplicates, so final materialization needs no per-scope indexes or
/// staging objects.
pub(crate) struct DecodedCharacteristics {
    records: Vec<DecodedCharacteristic>,
}

/// Source-independent characteristic policy. Format adapters frame records and
/// provide a lazy value locator; this plan owns classification, accepted-only
/// retention, deferred semantic errors, and source-order decoding.
pub(crate) struct CharacteristicPlan<L> {
    accepted: HashMap<AcceptedCharacteristic, PlannedCharacteristic<L>>,
    deferred_error: Option<(usize, DtaError)>,
}

impl<L> Default for CharacteristicPlan<L> {
    fn default() -> Self {
        Self {
            accepted: HashMap::new(),
            deferred_error: None,
        }
    }
}

impl<L> CharacteristicPlan<L> {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn push_record<R, P>(
        &mut self,
        ordinal: usize,
        target: &str,
        name: String,
        name_offset: usize,
        resolve_variable: R,
        prepare_value: P,
    ) -> Result<(), DtaError>
    where
        R: FnOnce(&str) -> Option<usize>,
        P: FnOnce(CharacteristicValueUse) -> Result<Option<L>, DtaError>,
    {
        self.push_record_replacing(
            ordinal,
            target,
            name,
            name_offset,
            resolve_variable,
            prepare_value,
        )
        .map(drop)
    }

    /// Adds one fully framed record and returns a superseded lazy value with
    /// its source ordinal. Streaming adapters validate that value before it is
    /// discarded, so duplicate compaction does not skip malformed payloads.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn push_record_replacing<R, P>(
        &mut self,
        ordinal: usize,
        target: &str,
        name: String,
        name_offset: usize,
        resolve_variable: R,
        prepare_value: P,
    ) -> Result<Option<(usize, L)>, DtaError>
    where
        R: FnOnce(&str) -> Option<usize>,
        P: FnOnce(CharacteristicValueUse) -> Result<Option<L>, DtaError>,
    {
        if self.deferred_error.is_some() {
            prepare_value(CharacteristicValueUse::Skip)?;
            return Ok(None);
        }

        let classified = classify_characteristic(target, name, name_offset, resolve_variable);
        let value_use = if matches!(classified, Ok(Some(_))) {
            CharacteristicValueUse::Retain
        } else {
            CharacteristicValueUse::Validate
        };
        let prepared = prepare_value(value_use);

        let replaced = match (classified, prepared) {
            (_, Err(error)) => {
                self.deferred_error = Some((ordinal, error));
                None
            }
            (Err(error), Ok(_)) => {
                self.deferred_error = Some((ordinal, error));
                None
            }
            (Ok(None), Ok(_)) => None,
            (Ok(Some(accepted)), Ok(Some(value))) => {
                if let Some(previous) = self.accepted.get_mut(&accepted) {
                    let replaced = (
                        previous.value_ordinal,
                        std::mem::replace(&mut previous.value, value),
                    );
                    previous.value_ordinal = ordinal;
                    Some(replaced)
                } else {
                    self.accepted.try_reserve(1).map_err(|_| {
                        DtaError::ArithmeticOverflow("accepted characteristic framing plan")
                    })?;
                    self.accepted.insert(
                        accepted,
                        PlannedCharacteristic {
                            first_ordinal: ordinal,
                            value_ordinal: ordinal,
                            value,
                        },
                    );
                    None
                }
            }
            (Ok(Some(_)), Ok(None)) => {
                return Err(DtaError::ArithmeticOverflow(
                    "retained characteristic value locator",
                ));
            }
        };
        Ok(replaced)
    }

    pub(crate) fn defer_value_error(&mut self, ordinal: usize, error: DtaError) {
        debug_assert!(self.deferred_error.is_none());
        self.deferred_error = Some((ordinal, error));
    }

    pub(crate) fn decode<D>(self, mut decode_value: D) -> Result<DecodedCharacteristics, DtaError>
    where
        D: FnMut(L) -> Result<String, DtaError>,
    {
        let mut deferred_error = self.deferred_error;
        let mut records = Vec::new();
        records
            .try_reserve_exact(self.accepted.len())
            .map_err(|_| DtaError::ArithmeticOverflow("accepted characteristic decode plan"))?;
        records.extend(self.accepted);
        records.sort_unstable_by_key(|(_, record)| record.value_ordinal);

        let mut decoded = Vec::new();
        decoded
            .try_reserve_exact(records.len())
            .map_err(|_| DtaError::ArithmeticOverflow("decoded characteristic plan"))?;
        for (accepted, record) in records {
            if deferred_error
                .as_ref()
                .is_some_and(|(ordinal, _)| *ordinal < record.value_ordinal)
            {
                return Err(deferred_error.take().expect("deferred error exists").1);
            }
            decoded.push(DecodedCharacteristic {
                first_ordinal: record.first_ordinal,
                accepted,
                value: decode_value(record.value)?,
            });
        }
        if let Some((_, error)) = deferred_error {
            return Err(error);
        }

        decoded.sort_unstable_by_key(|record| record.first_ordinal);
        Ok(DecodedCharacteristics { records: decoded })
    }

    #[cfg(test)]
    pub(crate) fn retained_len(&self) -> usize {
        self.accepted.len()
    }

    pub(crate) fn has_deferred_error(&self) -> bool {
        self.deferred_error.is_some()
    }
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

impl DecodedCharacteristics {
    pub(crate) fn finish(
        self,
        dataset_notes: &mut Vec<StataNote>,
        dataset_characteristics: &mut Vec<StataCharacteristic>,
        variables: &mut [VariableInfo],
    ) {
        dataset_notes.clear();
        dataset_characteristics.clear();
        for variable in variables.iter_mut() {
            variable.notes.clear();
            variable.characteristics.clear();
        }

        for record in self.records {
            let (notes, characteristics) = match record.accepted.target_index {
                None => (&mut *dataset_notes, &mut *dataset_characteristics),
                Some(index) => {
                    let Some(variable) = variables.get_mut(index) else {
                        continue;
                    };
                    (&mut variable.notes, &mut variable.characteristics)
                }
            };
            match record.accepted.key {
                MetadataKey::Note(number) => notes.push(StataNote {
                    number,
                    text: record.value,
                }),
                MetadataKey::Characteristic(name) => {
                    characteristics.push(StataCharacteristic {
                        name,
                        value: record.value,
                    });
                }
            }
        }

        dataset_notes.sort_unstable_by_key(|note| note.number);
        for variable in variables {
            variable.notes.sort_unstable_by_key(|note| note.number);
        }
    }

    #[cfg(test)]
    fn len(&self) -> usize {
        self.records.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::DtaType;

    #[test]
    fn characteristic_plan_preserves_source_order_and_stops_retaining_after_errors() {
        let mut plan = CharacteristicPlan::default();
        plan.push_record(
            0,
            "_dta",
            "source".into(),
            0,
            |_| None,
            |value_use| {
                assert_eq!(value_use, CharacteristicValueUse::Retain);
                Ok(Some("first"))
            },
        )
        .unwrap();
        plan.push_record(
            1,
            "_dta",
            String::new(),
            7,
            |_| None,
            |value_use| {
                assert_eq!(value_use, CharacteristicValueUse::Validate);
                Ok(None)
            },
        )
        .unwrap();
        plan.push_record(
            2,
            "_dta",
            "later".into(),
            14,
            |_| None,
            |value_use| {
                assert_eq!(value_use, CharacteristicValueUse::Skip);
                Ok(None)
            },
        )
        .unwrap();
        assert_eq!(plan.retained_len(), 1);
        assert!(matches!(
            plan.decode(|_| Err(DtaError::InvalidSignature)),
            Err(DtaError::InvalidSignature)
        ));

        let mut plan = CharacteristicPlan::default();
        plan.push_record(
            0,
            "_dta",
            "source".into(),
            0,
            |_| None,
            |_| Ok(Some("first")),
        )
        .unwrap();
        plan.push_record(1, "_dta", String::new(), 7, |_| None, |_| Ok(None))
            .unwrap();
        assert!(matches!(
            plan.decode(|value| Ok(value.to_owned())),
            Err(DtaError::InvalidCharacteristicName { offset: 7, .. })
        ));
    }

    #[test]
    fn characteristic_plan_validates_but_compacts_duplicate_records() {
        const DUPLICATES: usize = 20_000;
        let mut plan = CharacteristicPlan::default();
        let mut prepared = 0_usize;
        plan.push_record(
            0,
            "_dta",
            "source".into(),
            0,
            |_| None,
            |value_use| {
                prepared += 1;
                assert_eq!(value_use, CharacteristicValueUse::Retain);
                Ok(Some(("source", 0)))
            },
        )
        .unwrap();
        plan.push_record(
            1,
            "_dta",
            "other".into(),
            0,
            |_| None,
            |value_use| {
                prepared += 1;
                assert_eq!(value_use, CharacteristicValueUse::Retain);
                Ok(Some(("other", 1)))
            },
        )
        .unwrap();
        for ordinal in 2..DUPLICATES {
            plan.push_record(
                ordinal,
                "_dta",
                "source".into(),
                0,
                |_| None,
                |value_use| {
                    prepared += 1;
                    assert_eq!(value_use, CharacteristicValueUse::Retain);
                    Ok(Some(("source", ordinal)))
                },
            )
            .unwrap();
        }
        assert_eq!(prepared, DUPLICATES);
        assert_eq!(plan.retained_len(), 2);

        let mut decoded_order = Vec::new();
        let collector = plan
            .decode(|(name, value)| {
                decoded_order.push(name);
                Ok(value.to_string())
            })
            .unwrap();
        assert_eq!(decoded_order, ["other", "source"]);
        let mut characteristics = Vec::new();
        collector.finish(&mut Vec::new(), &mut characteristics, &mut []);
        assert_eq!(
            characteristics,
            vec![
                StataCharacteristic {
                    name: "source".into(),
                    value: (DUPLICATES - 1).to_string(),
                },
                StataCharacteristic {
                    name: "other".into(),
                    value: "1".into(),
                },
            ]
        );
    }

    #[test]
    fn malformed_duplicate_keeps_source_order_and_stops_later_retention() {
        let mut plan = CharacteristicPlan::default();
        plan.push_record(
            0,
            "_dta",
            "source".into(),
            0,
            |_| None,
            |_| Ok(Some("first")),
        )
        .unwrap();
        plan.push_record(
            1,
            "_dta",
            "source".into(),
            0,
            |_| None,
            |_| {
                Err(DtaError::MetadataValueTooLong {
                    context: "characteristic value",
                    offset: 10,
                    length: 2,
                    limit: 1,
                })
            },
        )
        .unwrap();
        plan.push_record(
            2,
            "_dta",
            "later".into(),
            0,
            |_| None,
            |value_use| {
                assert_eq!(value_use, CharacteristicValueUse::Skip);
                Ok(None)
            },
        )
        .unwrap();

        assert_eq!(plan.retained_len(), 1);
        assert!(matches!(
            plan.decode(|value| Ok(value.to_owned())),
            Err(DtaError::MetadataValueTooLong { offset: 10, .. })
        ));
    }

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
            ("_dta", "fralias_from", "source frame"),
            ("x", "fralias_varname", "source variable"),
            ("x", "note2", "variable"),
            ("x", "role", "id"),
            ("missing", "source", "ignored"),
        ]
        .into_iter();
        let mut plan = CharacteristicPlan::default();
        let mut variable_indexes = VariableTargetIndexes::new(&variables);
        for (ordinal, (target, name, value)) in records.enumerate() {
            plan.push_record(
                ordinal,
                target,
                name.into(),
                0,
                |target| variable_indexes.resolve(target),
                |_| Ok(Some(value)),
            )
            .expect("valid raw characteristic");
        }
        drop(variable_indexes);
        plan.decode(|value| Ok(value.into())).unwrap().finish(
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
        let mut plan = CharacteristicPlan::default();
        let mut variable_indexes = VariableTargetIndexes::new(&variables);
        plan.push_record(
            0,
            "x",
            "role".into(),
            0,
            |target| variable_indexes.resolve(target),
            |_| Ok(Some("id")),
        )
        .expect("the duplicate target resolves");
        drop(variable_indexes);
        plan.decode(|value| Ok(value.into())).unwrap().finish(
            &mut Vec::new(),
            &mut Vec::new(),
            &mut variables,
        );

        assert!(variables[0].characteristics.is_empty());
        assert_eq!(variables[1].characteristics[0].value, "id");
    }

    #[test]
    fn decoded_plan_materializes_120_000_scopes_without_scope_staging() {
        const SCOPES: usize = 120_000;
        let template = VariableInfo {
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
        let mut variables = vec![template; SCOPES];
        let mut plan = CharacteristicPlan::default();
        for index in 0..SCOPES {
            plan.push_record(
                index,
                "x",
                "role".into(),
                0,
                |_| Some(index),
                |_| Ok(Some(index)),
            )
            .unwrap();
        }

        let decoded = plan.decode(|index| Ok(index.to_string())).unwrap();
        assert_eq!(decoded.len(), SCOPES);
        assert_eq!(
            std::mem::size_of_val(&decoded),
            std::mem::size_of::<Vec<DecodedCharacteristic>>(),
            "decoded state must be one flat record vector, not per-scope containers"
        );
        decoded.finish(&mut Vec::new(), &mut Vec::new(), &mut variables);

        assert!(variables
            .iter()
            .all(|variable| variable.notes.is_empty() && variable.characteristics.len() == 1));
        assert_eq!(variables[0].characteristics[0].value, "0");
        assert_eq!(
            variables[SCOPES - 1].characteristics[0].value,
            (SCOPES - 1).to_string()
        );
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

        for name in ["fralias_from", "fralias_varname"] {
            let structural = classify_characteristic("x", name.into(), 0, |_| {
                panic!("alias metadata must not resolve variable names")
            })
            .expect("valid alias metadata");
            assert!(structural.is_none());
        }
    }
}
