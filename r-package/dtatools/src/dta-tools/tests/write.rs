use std::borrow::Cow;
use std::cell::Cell;
use std::io::{Cursor, Seek, SeekFrom, Write};

use dta_tools::{
    parse_metadata, read_dta, read_dta_with_options, save_dta_to,
    write_prevalidated_dta_with_observation_source_to, ByteOrder, ColumnValues, DtaError, DtaFile,
    DtaType, DtaWriteCharacteristic, DtaWriteColumn, DtaWriteColumnSource, DtaWriteColumnValues,
    DtaWriteData, DtaWriteError, DtaWriteLabelValue, DtaWriteNote, DtaWriteNumericValue,
    DtaWriteObservationSource, DtaWriteOptions, DtaWriteRawNumericValue, DtaWriteValueLabel,
    FormatVersion, MissingTag, ReadOptions, StataCharacteristic, StataNote,
};
#[cfg(feature = "r-adapter-internal")]
use dta_tools::{
    write_prevalidated_dta_with_value_label_registry_to, DtaWriteValueLabelRegistry,
    DtaWriteValueLabelTable,
};
use sha2::{Digest, Sha256};

const ADAPTED_NUMERIC_VALUES: [DtaWriteNumericValue; 3] = [
    DtaWriteNumericValue::Value(-1.0),
    DtaWriteNumericValue::Missing(MissingTag::System),
    DtaWriteNumericValue::Value(1.0),
];

struct AppendWriter(Cursor<Vec<u8>>);

impl Write for AppendWriter {
    fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
        self.0.seek(SeekFrom::End(0))?;
        self.0.write(buffer)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.0.flush()
    }
}

impl Seek for AppendWriter {
    fn seek(&mut self, position: SeekFrom) -> std::io::Result<u64> {
        self.0.seek(position)
    }
}

struct CountingSource {
    calls: Cell<usize>,
}

impl DtaWriteColumnSource for CountingSource {
    fn len(&self) -> u64 {
        ADAPTED_NUMERIC_VALUES.len() as u64
    }

    fn numeric_value(&self, row: u64) -> Result<DtaWriteNumericValue, String> {
        self.calls.set(self.calls.get() + 1);
        ADAPTED_NUMERIC_VALUES
            .get(row as usize)
            .copied()
            .ok_or_else(|| "row is outside test source".into())
    }
}

struct AdaptedObservationSource;

impl DtaWriteObservationSource for AdaptedObservationSource {
    fn numeric_value(
        &self,
        _column: usize,
        row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        ADAPTED_NUMERIC_VALUES
            .get(row as usize)
            .copied()
            .ok_or(DtaWriteError::Overflow("adapted test row"))
    }

    fn string_value(&self, _column: usize, _row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        unreachable!("adapted test source is numeric")
    }
}

struct BulkObservationSource {
    calls: Cell<usize>,
}

impl DtaWriteObservationSource for BulkObservationSource {
    fn append_observation_rows(
        &self,
        buffer: &mut Vec<u8>,
        start: u64,
        end: u64,
    ) -> Result<bool, DtaWriteError> {
        self.calls.set(self.calls.get() + 1);
        for value in &ADAPTED_NUMERIC_VALUES[start as usize..end as usize] {
            let raw = match value {
                DtaWriteNumericValue::Value(value) => *value as i32,
                DtaWriteNumericValue::Missing(MissingTag::System) => 2_147_483_621,
                DtaWriteNumericValue::Missing(_) => unreachable!("test data has system missing"),
            };
            buffer.extend_from_slice(&raw.to_le_bytes());
        }
        Ok(true)
    }

    fn numeric_value(
        &self,
        _column: usize,
        _row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        unreachable!("the bulk test source must bypass scalar values")
    }

    fn string_value(&self, _column: usize, _row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        unreachable!("the bulk test source is numeric")
    }
}

struct WrongLengthBulkObservationSource;

impl DtaWriteObservationSource for WrongLengthBulkObservationSource {
    fn append_observation_rows(
        &self,
        buffer: &mut Vec<u8>,
        _start: u64,
        _end: u64,
    ) -> Result<bool, DtaWriteError> {
        buffer.push(0);
        Ok(true)
    }

    fn numeric_value(
        &self,
        _column: usize,
        _row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        unreachable!("the malformed bulk source reports that it handled the rows")
    }

    fn string_value(&self, _column: usize, _row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        unreachable!("the malformed bulk source is numeric")
    }
}

struct InterruptingStrlSource {
    value: String,
    interrupt_at: usize,
    checks: Cell<usize>,
}

impl DtaWriteObservationSource for InterruptingStrlSource {
    fn check_interrupt(&self) -> Result<(), DtaWriteError> {
        let checks = self.checks.get() + 1;
        self.checks.set(checks);
        if checks == self.interrupt_at {
            Err(DtaWriteError::Interrupted)
        } else {
            Ok(())
        }
    }

    fn numeric_value(
        &self,
        _column: usize,
        _row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        unreachable!("the interrupt test source is string-valued")
    }

    fn string_value(&self, _column: usize, _row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        Ok(Cow::Borrowed(&self.value))
    }
}

struct CountingObservationSource {
    checks: Cell<usize>,
}

impl DtaWriteObservationSource for CountingObservationSource {
    fn check_interrupt(&self) -> Result<(), DtaWriteError> {
        self.checks.set(self.checks.get() + 1);
        Ok(())
    }

    fn numeric_value(
        &self,
        _column: usize,
        _row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        Ok(DtaWriteNumericValue::Value(0.0))
    }

    fn string_value(&self, _column: usize, _row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        unreachable!("the value-label interrupt test source is numeric")
    }
}

struct MismatchedRawSource;

struct StaticObservationSource {
    numeric: DtaWriteNumericValue,
    string: &'static str,
    string_id: Option<u64>,
}

impl DtaWriteObservationSource for StaticObservationSource {
    fn numeric_value(
        &self,
        _column: usize,
        _row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        Ok(self.numeric)
    }

    fn string_id(&self, _column: usize, _row: u64) -> Result<Option<u64>, DtaWriteError> {
        Ok(self.string_id)
    }

    fn string_value(&self, _column: usize, _row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        Ok(Cow::Borrowed(self.string))
    }
}

struct StatefulStrlSource {
    active_row: Cell<u64>,
    values: [&'static str; 2],
    string_ids: Option<[u64; 2]>,
}

impl DtaWriteObservationSource for StatefulStrlSource {
    fn begin_row(&self, row: u64) -> Result<(), DtaWriteError> {
        self.active_row.set(row);
        Ok(())
    }

    fn numeric_value(
        &self,
        _column: usize,
        _row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        unreachable!("the stateful test source is string-valued")
    }

    fn string_id(&self, column: usize, row: u64) -> Result<Option<u64>, DtaWriteError> {
        if column == 0 {
            Ok(self.string_ids.map(|ids| ids[row as usize]))
        } else {
            Ok(None)
        }
    }

    fn string_value(&self, column: usize, row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        if self.active_row.get() != row {
            return Err(DtaWriteError::Source {
                column: format!("column{column}"),
                row,
                message: "begin_row was not called for the requested row".into(),
            });
        }
        Ok(Cow::Borrowed(if column == 0 {
            self.values[row as usize]
        } else {
            "x"
        }))
    }
}

struct ChangingCanonicalStrlSource {
    calls: Cell<usize>,
}

impl DtaWriteObservationSource for ChangingCanonicalStrlSource {
    fn numeric_value(
        &self,
        _column: usize,
        _row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        unreachable!("the changing test source is string-valued")
    }

    fn string_id(&self, _column: usize, _row: u64) -> Result<Option<u64>, DtaWriteError> {
        Ok(Some(1))
    }

    fn string_value(&self, _column: usize, _row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        let calls = self.calls.get() + 1;
        self.calls.set(calls);
        Ok(Cow::Borrowed(if calls < 3 {
            "planned value"
        } else {
            "changed value"
        }))
    }
}

impl DtaWriteObservationSource for MismatchedRawSource {
    fn raw_numeric_value(
        &self,
        _column: usize,
        _row: u64,
    ) -> Result<Option<DtaWriteRawNumericValue>, DtaWriteError> {
        Ok(Some(DtaWriteRawNumericValue::Byte(1)))
    }

    fn numeric_value(
        &self,
        _column: usize,
        _row: u64,
    ) -> Result<DtaWriteNumericValue, DtaWriteError> {
        unreachable!("the raw test source always provides a value")
    }

    fn string_value(&self, _column: usize, _row: u64) -> Result<Cow<'_, str>, DtaWriteError> {
        unreachable!("the raw test source is numeric")
    }
}

#[test]
fn prevalidated_adapter_avoids_a_redundant_value_pass() {
    let source = CountingSource {
        calls: Cell::new(0),
    };
    let mut data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "value".into(),
            dta_type: DtaType::Long,
            format: "%12.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Source(&source),
        }],
    };

    let mut checked = Cursor::new(Vec::new());
    save_dta_to(&mut checked, &data, &DtaWriteOptions::default()).unwrap();
    assert_eq!(source.calls.get(), 6);
    let checked = checked.into_inner();

    source.calls.set(0);
    let mut adapted = Cursor::new(Vec::new());
    write_prevalidated_dta_with_observation_source_to(
        &mut adapted,
        &data,
        &DtaWriteOptions::default(),
        &AdaptedObservationSource,
        3,
    )
    .unwrap();
    assert_eq!(source.calls.get(), 0);
    assert_eq!(adapted.into_inner(), checked);

    let bulk_source = BulkObservationSource {
        calls: Cell::new(0),
    };
    let mut bulk = Cursor::new(Vec::new());
    write_prevalidated_dta_with_observation_source_to(
        &mut bulk,
        &data,
        &DtaWriteOptions::default(),
        &bulk_source,
        3,
    )
    .unwrap();
    assert_eq!(bulk_source.calls.get(), 1);
    assert_eq!(bulk.into_inner(), checked);

    let row_count_error = write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &AdaptedObservationSource,
        2,
    )
    .unwrap_err();
    assert!(matches!(
        row_count_error,
        DtaWriteError::InvalidDatasetMetadata(_)
    ));
    assert_eq!(source.calls.get(), 0);

    data.columns[0].name = "not valid".into();
    let structure_error = write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &AdaptedObservationSource,
        3,
    )
    .unwrap_err();
    assert!(matches!(
        structure_error,
        DtaWriteError::InvalidVariable { .. }
    ));
    assert_eq!(source.calls.get(), 0);
}

#[cfg(feature = "r-adapter-internal")]
#[test]
fn internal_value_label_registry_rejects_both_presence_mismatches() {
    let labels = [DtaWriteValueLabel {
        value: DtaWriteLabelValue::Integer(0),
        label: "zero".into(),
    }];
    let tables = [DtaWriteValueLabelTable::new("shared", &labels)];

    for (has_value_labels, table_index) in [(true, None), (false, Some(0))] {
        let data = DtaWriteData {
            dataset_label: String::new().into(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            columns: vec![DtaWriteColumn {
                name: "value".into(),
                dta_type: DtaType::Long,
                format: "%12.0g".into(),
                label: String::new().into(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                has_value_labels,
                value_labels: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&ADAPTED_NUMERIC_VALUES),
            }],
        };
        let indices = [table_index];
        let registry = DtaWriteValueLabelRegistry::new(&tables, &indices);
        let error = write_prevalidated_dta_with_value_label_registry_to(
            &mut Cursor::new(Vec::new()),
            &data,
            &DtaWriteOptions::default(),
            &AdaptedObservationSource,
            ADAPTED_NUMERIC_VALUES.len() as u64,
            &registry,
        )
        .unwrap_err();
        assert!(matches!(
            error,
            DtaWriteError::InvalidDatasetMetadata(message)
                if message == "value-label table registry does not match the columns"
        ));
    }
}

#[cfg(feature = "r-adapter-internal")]
#[test]
fn internal_value_label_registry_keeps_each_table_name_and_entries_together() {
    let labels = [
        DtaWriteValueLabel {
            value: DtaWriteLabelValue::Integer(-1),
            label: "negative".into(),
        },
        DtaWriteValueLabel {
            value: DtaWriteLabelValue::Integer(1),
            label: "positive".into(),
        },
    ];
    let tables = [DtaWriteValueLabelTable::new("shared_codes", &labels)];
    let indices = [Some(0)];
    let registry = DtaWriteValueLabelRegistry::new(&tables, &indices);
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "value".into(),
            dta_type: DtaType::Long,
            format: "%12.0g".into(),
            label: String::new().into(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            has_value_labels: true,
            value_labels: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&ADAPTED_NUMERIC_VALUES),
        }],
    };

    let mut output = Cursor::new(Vec::new());
    write_prevalidated_dta_with_value_label_registry_to(
        &mut output,
        &data,
        &DtaWriteOptions::default(),
        &AdaptedObservationSource,
        ADAPTED_NUMERIC_VALUES.len() as u64,
        &registry,
    )
    .unwrap();

    let parsed = read_dta(&output.into_inner()).unwrap();
    assert_eq!(
        parsed.metadata.variables[0].value_label_name,
        "shared_codes"
    );
    let table = parsed.value_label_table_for_variable(0).unwrap();
    assert_eq!(table.name, "shared_codes");
    assert_eq!(
        table
            .entries
            .iter()
            .map(|entry| (entry.value, entry.label.as_str()))
            .collect::<Vec<_>>(),
        vec![(-1, "negative"), (1, "positive")]
    );
}

#[cfg(feature = "r-adapter-internal")]
#[test]
fn public_and_registry_writers_share_value_label_entry_validation() {
    let oversized = DtaWriteValueLabel {
        value: DtaWriteLabelValue::Integer(0),
        label: String::new().into(),
    };
    let cases = vec![
        (
            vec![DtaWriteValueLabel {
                value: DtaWriteLabelValue::Missing(MissingTag::System),
                label: "missing".into(),
            }],
            "system missing cannot have a value label",
        ),
        (
            vec![DtaWriteValueLabel {
                value: DtaWriteLabelValue::Integer(0),
                label: "nul\0text".into(),
            }],
            "no NUL",
        ),
        (
            vec![DtaWriteValueLabel {
                value: DtaWriteLabelValue::Integer(0),
                label: "x".repeat(32_001).into(),
            }],
            "at most 32000 UTF-8 bytes",
        ),
        (vec![oversized; 65_537], "maximum is 65536"),
    ];

    let make_data = |value_labels| DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "value".into(),
            dta_type: DtaType::Long,
            format: "%12.0g".into(),
            label: String::new().into(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            has_value_labels: true,
            value_labels,
            values: DtaWriteColumnValues::Numeric(&ADAPTED_NUMERIC_VALUES),
        }],
    };

    for (entries, expected) in cases {
        let public_error = save_dta_to(
            &mut Cursor::new(Vec::new()),
            &make_data(entries.clone()),
            &DtaWriteOptions::default(),
        )
        .unwrap_err()
        .to_string();

        let tables = [DtaWriteValueLabelTable::new("shared", &entries)];
        let indices = [Some(0)];
        let registry = DtaWriteValueLabelRegistry::new(&tables, &indices);
        let registry_error = write_prevalidated_dta_with_value_label_registry_to(
            &mut Cursor::new(Vec::new()),
            &make_data(Vec::new()),
            &DtaWriteOptions::default(),
            &AdaptedObservationSource,
            ADAPTED_NUMERIC_VALUES.len() as u64,
            &registry,
        )
        .unwrap_err()
        .to_string();

        assert_eq!(registry_error, public_error);
        assert!(public_error.contains(expected), "{public_error}");
    }
}

#[test]
fn prevalidated_bulk_sources_must_return_complete_rows() {
    let values = [DtaWriteNumericValue::Value(0.0)];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "value".into(),
            dta_type: DtaType::Long,
            format: "%12.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };
    let error = write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &WrongLengthBulkObservationSource,
        1,
    )
    .unwrap_err();
    assert!(matches!(error, DtaWriteError::Source { .. }));
}

#[test]
fn large_strl_hashing_and_tail_writes_poll_for_interrupts() {
    let placeholder = [String::new()];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "text".into(),
            dta_type: DtaType::StrL,
            format: "%9s".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Strings(&placeholder),
        }],
    };

    for interrupt_at in [1, 12] {
        let source = InterruptingStrlSource {
            value: "x".repeat(9 * 1024 * 1024),
            interrupt_at,
            checks: Cell::new(0),
        };
        let error = write_prevalidated_dta_with_observation_source_to(
            &mut Cursor::new(Vec::new()),
            &data,
            &DtaWriteOptions::default(),
            &source,
            1,
        )
        .unwrap_err();
        assert!(matches!(error, DtaWriteError::Interrupted));
        assert_eq!(source.checks.get(), interrupt_at);
    }
}

fn value_label_write_interrupt_checks(labels: Vec<DtaWriteValueLabel<'static>>) -> usize {
    let values = [DtaWriteNumericValue::Value(0.0)];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "value".into(),
            dta_type: DtaType::Long,
            format: "%12.0g".into(),
            label: String::new().into(),
            has_value_labels: true,
            value_labels: labels,
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };
    let source = CountingObservationSource {
        checks: Cell::new(0),
    };
    write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &source,
        1,
    )
    .unwrap();
    source.checks.get()
}

#[test]
fn large_value_label_payloads_poll_for_interrupts() {
    let small_checks = value_label_write_interrupt_checks(vec![DtaWriteValueLabel {
        value: DtaWriteLabelValue::Integer(0),
        label: "x".into(),
    }]);
    let large_labels = (0..300)
        .map(|value| DtaWriteValueLabel {
            value: DtaWriteLabelValue::Integer(value),
            label: "x".repeat(32_000).into(),
        })
        .collect();
    let large_checks = value_label_write_interrupt_checks(large_labels);
    assert!(large_checks > small_checks);
}

#[test]
fn rejects_reserved_dta_variable_names() {
    let values = [DtaWriteNumericValue::Value(1.0)];
    for name in [
        "alias", "_all", "_b", "_coef", "_cons", "_n", "_N", "_pi", "_pred", "_r_b", "_rc",
        "_r_ci", "_r_cri", "_r_crlb", "_r_crub", "_r_df", "_r_lb", "_r_p", "_r_se", "_r_ub",
        "_r_z", "_r_z_abs", "_se", "_skip", "_weight", "byte", "double", "float", "int", "long",
        "in", "if", "strL", "using", "with", "str1", "str2045", "str2046",
    ] {
        let data = DtaWriteData {
            dataset_label: String::new().into(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            columns: vec![DtaWriteColumn {
                name: name.into(),
                dta_type: DtaType::Double,
                format: "%10.0g".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&values),
            }],
        };
        let error = save_dta_to(
            &mut Cursor::new(Vec::new()),
            &data,
            &DtaWriteOptions::default(),
        )
        .unwrap_err();
        assert!(
            matches!(error, DtaWriteError::InvalidVariable { .. }),
            "{name}"
        );
    }

    for name in ["str0", "str00", "str01", "str02046"] {
        let data = DtaWriteData {
            dataset_label: String::new().into(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            columns: vec![DtaWriteColumn {
                name: name.into(),
                dta_type: DtaType::Double,
                format: "%10.0g".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&values),
            }],
        };
        save_dta_to(
            &mut Cursor::new(Vec::new()),
            &data,
            &DtaWriteOptions::default(),
        )
        .unwrap_or_else(|error| panic!("rejected {name:?}: {error}"));
    }

    for name in ["\u{345}x", "x\u{345}"] {
        let data = DtaWriteData {
            dataset_label: String::new().into(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            columns: vec![DtaWriteColumn {
                name: name.into(),
                dta_type: DtaType::Double,
                format: "%10.0g".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&values),
            }],
        };
        assert!(matches!(
            save_dta_to(
                &mut Cursor::new(Vec::new()),
                &data,
                &DtaWriteOptions::default()
            ),
            Err(DtaWriteError::InvalidVariable { .. })
        ));
    }
}

#[test]
fn rejects_metadata_on_variable_named_dta_before_writing() {
    let values = [DtaWriteNumericValue::Value(1.0)];
    let mut data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "_dta".into(),
            dta_type: DtaType::Double,
            format: "%10.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: vec!["cannot be encoded".into()],
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };

    for use_characteristic in [false, true] {
        if use_characteristic {
            data.columns[0].notes.clear();
            data.columns[0]
                .characteristics
                .push(DtaWriteCharacteristic {
                    name: "role".into(),
                    value: "id".into(),
                });
        }
        let mut output = Cursor::new(Vec::new());
        let error = save_dta_to(&mut output, &data, &DtaWriteOptions::default()).unwrap_err();
        assert!(matches!(error, DtaWriteError::InvalidVariable { .. }));
        assert!(output.into_inner().is_empty());
    }
}

#[test]
fn variable_metadata_validation_reports_variable_scope() {
    let values = [DtaWriteNumericValue::Value(1.0)];
    let mut data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "answer".into(),
            dta_type: DtaType::Double,
            format: "%10.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: vec![DtaWriteNote::numbered(0, "invalid")],
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };

    let error = save_dta_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
    )
    .expect_err("invalid variable note numbers are rejected");
    assert!(matches!(
        error,
        DtaWriteError::InvalidVariable { ref column, .. } if column == "answer"
    ));

    data.columns[0].notes.clear();
    data.columns[0].characteristics = vec![DtaWriteCharacteristic {
        name: "note2".into(),
        value: "reserved".into(),
    }];
    let error = save_dta_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
    )
    .expect_err("invalid variable characteristics are rejected");
    assert!(matches!(
        error,
        DtaWriteError::InvalidVariable { ref column, .. } if column == "answer"
    ));
}

#[test]
fn dense_metadata_writes_poll_at_bounded_byte_intervals() {
    let values: [DtaWriteNumericValue; 0] = [];
    let characteristics = (0..130)
        .map(|index| DtaWriteCharacteristic {
            name: format!("c{index}").into(),
            value: "x".repeat(67_784).into(),
        })
        .collect();
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics,
        columns: vec![DtaWriteColumn {
            name: "value".into(),
            dta_type: DtaType::Double,
            format: "%10.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };
    let source = InterruptingStrlSource {
        value: String::new(),
        interrupt_at: 7,
        checks: Cell::new(0),
    };
    let error = write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &source,
        0,
    )
    .unwrap_err();
    assert!(matches!(error, DtaWriteError::Interrupted));
    assert_eq!(source.checks.get(), 7);
}

#[test]
fn metadata_free_wide_writes_do_not_poll_per_column() {
    let values: [DtaWriteNumericValue; 0] = [];
    let columns = (0..4_096)
        .map(|index| DtaWriteColumn {
            name: format!("x{index}").into(),
            dta_type: DtaType::Double,
            format: "%10.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        })
        .collect();
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns,
    };
    let source = CountingObservationSource {
        checks: Cell::new(0),
    };
    write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &source,
        0,
    )
    .unwrap();
    assert!(source.checks.get() < 100);
}

#[test]
fn validates_display_format_grammar_and_storage_compatibility() {
    let numeric = [DtaWriteNumericValue::Value(1.0)];
    let mut data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "value".into(),
            dta_type: DtaType::Double,
            format: "%10.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&numeric),
        }],
    };
    for format in [
        "%9s",
        "not-a-format",
        "%9.9g",
        "%9.2ec",
        "%tmjunk",
        "%tdQ",
        "%thH",
        "%tg_",
        "%tg!X",
        "%tbaaaaaaaaaaa",
        "%tb1cal:HH",
    ] {
        data.columns[0].format = format.into();
        assert!(matches!(
            save_dta_to(
                &mut Cursor::new(Vec::new()),
                &data,
                &DtaWriteOptions::default()
            ),
            Err(DtaWriteError::InvalidVariable { .. })
        ));
    }
    for format in [
        "%09.2f",
        "%-9.0gc",
        "%21x",
        "%16H",
        "%tdMonth_dd,_CCYY",
        "%tdHH",
        "%tcCCYY.NN.DD-HH:MM:SS",
        "%tcq",
        "%twMon",
        "%tmDD",
        "%tqMonth",
        "%thWW",
        "%tyMonth",
        "%tmcY_m",
        "%tbcal:CCYY-NN-DD",
        "%tbcal:HH",
        "%tbä:HH",
        "%tbcal:",
        "%tbaaaaaaaaaa",
        "%tg",
    ] {
        data.columns[0].format = format.into();
        save_dta_to(
            &mut Cursor::new(Vec::new()),
            &data,
            &DtaWriteOptions::default(),
        )
        .unwrap_or_else(|error| panic!("rejected {format:?}: {error}"));
    }

    let strings = ["value".to_owned()];
    data.columns[0].dta_type = DtaType::FixedString(5);
    data.columns[0].values = DtaWriteColumnValues::Strings(&strings);
    data.columns[0].format = "%8.0g".into();
    assert!(matches!(
        save_dta_to(
            &mut Cursor::new(Vec::new()),
            &data,
            &DtaWriteOptions::default()
        ),
        Err(DtaWriteError::InvalidVariable { .. })
    ));
    for format in ["%0009s", "%-2045s"] {
        data.columns[0].format = format.into();
        save_dta_to(
            &mut Cursor::new(Vec::new()),
            &data,
            &DtaWriteOptions::default(),
        )
        .unwrap_or_else(|error| panic!("rejected {format:?}: {error}"));
    }
}

#[test]
fn rejects_raw_numeric_storage_that_does_not_match_the_column() {
    let values = [DtaWriteNumericValue::Value(1.0)];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "value".into(),
            dta_type: DtaType::Double,
            format: "%10.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };
    let error = write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &MismatchedRawSource,
        1,
    )
    .unwrap_err();
    assert!(matches!(error, DtaWriteError::Source { .. }));
}

#[test]
fn rejects_invalid_destination_streams() {
    let values = [DtaWriteNumericValue::Value(1.0)];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "value".into(),
            dta_type: DtaType::Long,
            format: "%12.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };

    let mut nonempty = Cursor::new(vec![0; 16]);
    let error = save_dta_to(&mut nonempty, &data, &DtaWriteOptions::default()).unwrap_err();
    assert!(matches!(error, DtaWriteError::InvalidDestination));
    assert_eq!(nonempty.into_inner(), vec![0; 16]);

    let mut nonzero = Cursor::new(Vec::new());
    nonzero.set_position(1);
    let error = save_dta_to(&mut nonzero, &data, &DtaWriteOptions::default()).unwrap_err();
    assert!(matches!(error, DtaWriteError::InvalidDestination));
    assert!(nonzero.into_inner().is_empty());

    let mut append = AppendWriter(Cursor::new(Vec::new()));
    let error = save_dta_to(&mut append, &data, &DtaWriteOptions::default()).unwrap_err();
    assert!(matches!(error, DtaWriteError::InvalidDestination));
}

#[test]
fn prevalidated_numeric_values_are_checked_while_encoding() {
    let values = [DtaWriteNumericValue::Value(0.0)];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "value".into(),
            dta_type: DtaType::Byte,
            format: "%8.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };
    let source = StaticObservationSource {
        numeric: DtaWriteNumericValue::Value(128.0),
        string: "",
        string_id: None,
    };

    let error = write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &source,
        1,
    )
    .unwrap_err();
    assert!(matches!(error, DtaWriteError::InvalidValue { .. }));
}

#[test]
fn prevalidated_fixed_strings_are_checked_while_encoding() {
    let values = [String::new()];
    for invalid in ["ab", "a\0"] {
        let data = DtaWriteData {
            dataset_label: String::new().into(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            columns: vec![DtaWriteColumn {
                name: "text".into(),
                dta_type: DtaType::FixedString(1),
                format: "%9s".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Strings(&values),
            }],
        };
        let source = StaticObservationSource {
            numeric: DtaWriteNumericValue::Value(0.0),
            string: invalid,
            string_id: None,
        };

        let error = write_prevalidated_dta_with_observation_source_to(
            &mut Cursor::new(Vec::new()),
            &data,
            &DtaWriteOptions::default(),
            &source,
            1,
        )
        .unwrap_err();
        assert!(matches!(error, DtaWriteError::InvalidValue { .. }));
    }
}

#[test]
fn prevalidated_strls_are_always_checked_during_planning() {
    let values = [String::new()];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "text".into(),
            dta_type: DtaType::StrL,
            format: "%9s".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Strings(&values),
        }],
    };
    let source = StaticObservationSource {
        numeric: DtaWriteNumericValue::Value(0.0),
        string: "invalid\0strL",
        string_id: Some(1),
    };

    let error = write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &source,
        1,
    )
    .unwrap_err();
    assert!(matches!(error, DtaWriteError::InvalidValue { .. }));
}

#[test]
fn strl_row_switches_call_begin_row_and_restore_the_active_row() {
    let long_values = ["same".to_owned(), "same".to_owned()];
    let fixed_values = ["x".to_owned(), "x".to_owned()];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![
            DtaWriteColumn {
                name: "long_text".into(),
                dta_type: DtaType::StrL,
                format: "%9s".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Strings(&long_values),
            },
            DtaWriteColumn {
                name: "fixed".into(),
                dta_type: DtaType::FixedString(1),
                format: "%9s".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Strings(&fixed_values),
            },
        ],
    };
    let source = StatefulStrlSource {
        active_row: Cell::new(0),
        values: ["same", "same"],
        string_ids: None,
    };

    write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &source,
        2,
    )
    .unwrap();
}

#[test]
fn one_stable_strl_id_cannot_alias_different_values() {
    let values = ["first".to_owned(), "second".to_owned()];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "text".into(),
            dta_type: DtaType::StrL,
            format: "%9s".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Strings(&values),
        }],
    };
    let source = StatefulStrlSource {
        active_row: Cell::new(0),
        values: ["first", "second"],
        string_ids: Some([7, 7]),
    };

    let error = write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &source,
        2,
    )
    .unwrap_err();
    assert!(matches!(error, DtaWriteError::Source { .. }));
}

#[test]
fn canonical_strl_payloads_cannot_change_after_planning() {
    let values = ["planned value".to_owned()];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "text".into(),
            dta_type: DtaType::StrL,
            format: "%9s".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Strings(&values),
        }],
    };
    let source = ChangingCanonicalStrlSource {
        calls: Cell::new(0),
    };

    let error = write_prevalidated_dta_with_observation_source_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
        &source,
        1,
    )
    .unwrap_err();
    assert!(matches!(error, DtaWriteError::Source { .. }));
}

#[test]
fn writes_a_release_118_dataset_that_the_public_parser_can_read() {
    let values = [
        DtaWriteNumericValue::Value(-5.0),
        DtaWriteNumericValue::Missing(MissingTag::A),
    ];
    let data = DtaWriteData {
        dataset_label: "writer tracer bullet".into(),
        notes: vec!["written by dta-tools".into(), String::new().into()],
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "answer".into(),
            dta_type: DtaType::Byte,
            format: "%8.0g".into(),
            label: "the answer".into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };
    let options = DtaWriteOptions {
        timestamp: Some("27 Aug 2026 12:34".into()),
    };

    let mut output = Cursor::new(Vec::new());
    let summary = save_dta_to(&mut output, &data, &options).unwrap();
    let bytes = output.into_inner();

    assert_eq!(summary.format_version, FormatVersion::V118);
    assert!(bytes.starts_with(b"<stata_dta><header><release>118</release><byteorder>LSF"));
    assert_eq!(
        format!("{:x}", Sha256::digest(&bytes)),
        "38a35efd2f68a867724965f1d845c6476b7505f73916e62901b1d0fc2bf7b045"
    );

    let parsed = read_dta(&bytes).unwrap();
    assert_eq!(parsed.metadata.format_version, FormatVersion::V118);
    assert_eq!(parsed.metadata.byte_order, ByteOrder::Lsf);
    assert_eq!(parsed.metadata.dataset_label, "writer tracer bullet");
    assert_eq!(
        parsed
            .metadata
            .notes
            .iter()
            .map(|note| note.text.as_str())
            .collect::<Vec<_>>(),
        ["written by dta-tools", ""]
    );
    assert_eq!(parsed.metadata.variables[0].name, "answer");
    assert_eq!(parsed.metadata.variables[0].label, "the answer");
    assert_eq!(parsed.metadata.variables[0].dta_type, DtaType::Byte);
    assert_eq!(
        parsed.columns[0].values,
        ColumnValues::Byte {
            values: vec![-5, 102],
            missing_tags: vec![None, Some(MissingTag::A)],
        }
    );
}

#[test]
fn writes_numbered_notes_and_characteristics_at_both_scopes() {
    let values = [DtaWriteNumericValue::Value(1.0)];
    let mut data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: vec![
            DtaWriteNote::numbered(3, "three"),
            DtaWriteNote::numbered(1, String::new()),
        ],
        characteristics: vec![
            DtaWriteCharacteristic {
                name: "source".into(),
                value: String::new().into(),
            },
            DtaWriteCharacteristic {
                name: "café".into(),
                value: "naïve".into(),
            },
        ],
        columns: vec![DtaWriteColumn {
            name: "answer".into(),
            dta_type: DtaType::Byte,
            format: "%8.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: vec![DtaWriteNote::numbered(2, "variable")],
            characteristics: vec![DtaWriteCharacteristic {
                name: "role".into(),
                value: "id".into(),
            }],
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };

    let mut output = Cursor::new(Vec::new());
    save_dta_to(&mut output, &data, &DtaWriteOptions::default()).unwrap();
    let bytes = output.into_inner();
    let parsed = read_dta(&bytes).unwrap();
    assert_eq!(
        parsed.metadata.notes,
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
        parsed.metadata.characteristics,
        vec![
            StataCharacteristic {
                name: "source".into(),
                value: String::new(),
            },
            StataCharacteristic {
                name: "café".into(),
                value: "naïve".into(),
            },
        ]
    );
    assert_eq!(
        parsed.metadata.variables[0].notes,
        vec![StataNote {
            number: 2,
            text: "variable".into(),
        }]
    );
    assert_eq!(
        parsed.metadata.variables[0].characteristics,
        vec![StataCharacteristic {
            name: "role".into(),
            value: "id".into(),
        }]
    );

    let metadata = parse_metadata(&bytes).unwrap();
    let first_record =
        metadata.section_offsets.characteristics as usize + b"<characteristics><ch>".len();
    let first_payload =
        u32::from_le_bytes(bytes[first_record..first_record + 4].try_into().unwrap()) as usize;
    let record = first_record + 4 + first_payload + b"</ch><ch>".len();
    let old_payload_length =
        u32::from_le_bytes(bytes[record..record + 4].try_into().unwrap()) as usize;
    let names_length = 2 * 129;
    let desired_value_length = 67_785;
    let extra = desired_value_length - (old_payload_length - names_length);
    let close = record + 4 + old_payload_length;
    let mut exact_value = vec![b'x'; desired_value_length];
    *exact_value.last_mut().unwrap() = 0;
    let mut exact_with_nul = bytes.clone();
    exact_with_nul.splice(record + 4 + names_length..close, exact_value);
    exact_with_nul[record..record + 4].copy_from_slice(
        &u32::try_from(old_payload_length + extra)
            .unwrap()
            .to_le_bytes(),
    );
    let map_payload = metadata.section_offsets.map as usize + b"<map>".len();
    for index in 9..14 {
        let offset = map_payload + index * 8;
        let old = u64::from_le_bytes(exact_with_nul[offset..offset + 8].try_into().unwrap());
        exact_with_nul[offset..offset + 8]
            .copy_from_slice(&(old + u64::try_from(extra).unwrap()).to_le_bytes());
    }
    assert_eq!(parse_metadata(&exact_with_nul).unwrap().notes.len(), 2);
    DtaFile::from_reader(Cursor::new(exact_with_nul.clone())).unwrap();

    let mut oversized = exact_with_nul;
    let final_value_byte = record + 4 + names_length + desired_value_length - 1;
    assert_eq!(oversized[final_value_byte], 0);
    oversized[final_value_byte] = b'x';
    assert!(matches!(
        parse_metadata(&oversized),
        Err(DtaError::MetadataValueTooLong { .. })
    ));
    let mut reserved_oversized = oversized.clone();
    let name = record + 4 + 129;
    reserved_oversized[name..name + 129].fill(0);
    reserved_oversized[name..name + 5].copy_from_slice(b"note0");
    let mut invalid_oversized = oversized.clone();
    invalid_oversized[name..name + 129].fill(0);
    invalid_oversized[name..name + 4].copy_from_slice(b"2bad");
    assert!(matches!(
        DtaFile::from_reader(Cursor::new(oversized)),
        Err(DtaError::MetadataValueTooLong { .. })
    ));
    assert!(matches!(
        parse_metadata(&reserved_oversized),
        Err(DtaError::MetadataValueTooLong { .. })
    ));
    assert!(matches!(
        DtaFile::from_reader(Cursor::new(reserved_oversized)),
        Err(DtaError::MetadataValueTooLong { .. })
    ));
    assert!(matches!(
        parse_metadata(&invalid_oversized),
        Err(DtaError::MetadataValueTooLong { .. })
    ));
    assert!(matches!(
        DtaFile::from_reader(Cursor::new(invalid_oversized)),
        Err(DtaError::MetadataValueTooLong { .. })
    ));

    let mut invalid_raw_name = bytes.clone();
    invalid_raw_name[name..name + 129].fill(0);
    invalid_raw_name[name..name + 4].copy_from_slice(b"2bad");
    assert!(matches!(
        parse_metadata(&invalid_raw_name),
        Err(DtaError::InvalidCharacteristicName { .. })
    ));
    assert!(matches!(
        DtaFile::from_reader(Cursor::new(invalid_raw_name)),
        Err(DtaError::InvalidCharacteristicName { .. })
    ));

    for invalid_name in [
        "note2",
        "2invalid",
        "_lang_list",
        "_lang_c",
        "_lang_v_en",
        "_lang_l_en",
        "fralias_from",
        "fralias_varname",
    ] {
        data.characteristics = vec![DtaWriteCharacteristic {
            name: invalid_name.into(),
            value: "bad".into(),
        }];
        let error = save_dta_to(
            &mut Cursor::new(Vec::new()),
            &data,
            &DtaWriteOptions::default(),
        )
        .expect_err("invalid or reserved characteristic names are rejected");
        assert!(matches!(error, DtaWriteError::InvalidDatasetMetadata(_)));
    }

    data.characteristics.clear();
    data.notes = vec![DtaWriteNote::numbered(0, "invalid")];
    let error = save_dta_to(
        &mut Cursor::new(Vec::new()),
        &data,
        &DtaWriteOptions::default(),
    )
    .expect_err("an explicit zero note number is rejected");
    assert!(matches!(error, DtaWriteError::InvalidDatasetMetadata(_)));
}

#[test]
fn writes_every_storage_width_fixed_utf8_and_sorted_value_labels() {
    let byte = [
        DtaWriteNumericValue::Value(-127.0),
        DtaWriteNumericValue::Missing(MissingTag::Z),
    ];
    let int = [
        DtaWriteNumericValue::Value(-32_767.0),
        DtaWriteNumericValue::Value(32_740.0),
    ];
    let long = [
        DtaWriteNumericValue::Value(-1.0),
        DtaWriteNumericValue::Value(1.0),
    ];
    let float = [
        DtaWriteNumericValue::Value(1.25),
        DtaWriteNumericValue::Missing(MissingTag::System),
    ];
    let double = [
        DtaWriteNumericValue::Value(-2.5),
        DtaWriteNumericValue::Missing(MissingTag::C),
    ];
    let strings = ["é".to_owned(), "abcd".to_owned()];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![
            DtaWriteColumn {
                name: "b".into(),
                dta_type: DtaType::Byte,
                format: "%8.0g".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&byte),
            },
            DtaWriteColumn {
                name: "i".into(),
                dta_type: DtaType::Int,
                format: "%8.0g".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&int),
            },
            DtaWriteColumn {
                name: "l".into(),
                dta_type: DtaType::Long,
                format: "%12.0g".into(),
                label: String::new().into(),
                has_value_labels: true,
                value_labels: vec![
                    DtaWriteValueLabel {
                        value: DtaWriteLabelValue::Integer(1),
                        label: "positive".into(),
                    },
                    DtaWriteValueLabel {
                        value: DtaWriteLabelValue::Integer(-1),
                        label: "negative".into(),
                    },
                ],
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&long),
            },
            DtaWriteColumn {
                name: "f".into(),
                dta_type: DtaType::Float,
                format: "%9.0g".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&float),
            },
            DtaWriteColumn {
                name: "d".into(),
                dta_type: DtaType::Double,
                format: "%10.0g".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Numeric(&double),
            },
            DtaWriteColumn {
                name: "s".into(),
                dta_type: DtaType::FixedString(4),
                format: "%9s".into(),
                label: String::new().into(),
                has_value_labels: false,
                value_labels: Vec::new(),
                notes: Vec::new(),
                characteristics: Vec::new(),
                values: DtaWriteColumnValues::Strings(&strings),
            },
        ],
    };

    let mut output = Cursor::new(Vec::new());
    save_dta_to(&mut output, &data, &DtaWriteOptions::default()).unwrap();
    let parsed = read_dta(&output.into_inner()).unwrap();
    assert_eq!(
        parsed.columns[0].values,
        ColumnValues::Byte {
            values: vec![-127, 127],
            missing_tags: vec![None, Some(MissingTag::Z)]
        }
    );
    assert_eq!(
        parsed.columns[1].values,
        ColumnValues::Int {
            values: vec![-32_767, 32_740],
            missing_tags: vec![None, None]
        }
    );
    assert_eq!(
        parsed.columns[2].values,
        ColumnValues::Long {
            values: vec![-1, 1],
            missing_tags: vec![None, None]
        }
    );
    assert_eq!(
        parsed.columns[3].values,
        ColumnValues::Float {
            values: vec![1.25, f32::from_bits(dta_tools::FLOAT_MISSING_DOT_BITS)],
            missing_tags: vec![None, Some(MissingTag::System)]
        }
    );
    assert_eq!(
        parsed.columns[4].values,
        ColumnValues::Double {
            values: vec![
                -2.5,
                f64::from_bits(
                    dta_tools::DOUBLE_MISSING_DOT_BITS + 3 * dta_tools::DOUBLE_MISSING_STEP_BITS
                )
            ],
            missing_tags: vec![None, Some(MissingTag::C)]
        }
    );
    assert_eq!(
        parsed.columns[5].values,
        ColumnValues::FixedString {
            values: strings.to_vec()
        }
    );
    let labels = parsed.value_label_table_for_variable(2).unwrap();
    assert_eq!(
        labels
            .entries
            .iter()
            .map(|entry| (entry.value, entry.label.as_str()))
            .collect::<Vec<_>>(),
        vec![(-1, "negative"), (1, "positive")]
    );
}

#[test]
fn writes_an_attached_empty_value_label_table() {
    let values = [DtaWriteNumericValue::Value(1.0)];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "coded".into(),
            dta_type: DtaType::Double,
            format: "%10.0g".into(),
            label: String::new().into(),
            has_value_labels: true,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&values),
        }],
    };

    let mut output = Cursor::new(Vec::new());
    save_dta_to(&mut output, &data, &DtaWriteOptions::default()).unwrap();
    let parsed = read_dta(&output.into_inner()).unwrap();
    let table = parsed.value_label_table_for_variable(0).unwrap();
    assert!(table.entries.is_empty());
}

#[test]
fn release_119_uses_three_variable_bytes_in_strl_pointers() {
    let numeric = [DtaWriteNumericValue::Value(0.0)];
    let text = ["wide strL".to_owned()];
    let mut columns = Vec::with_capacity(32_768);
    for index in 0..32_767 {
        columns.push(DtaWriteColumn {
            name: format!("x{index}").into(),
            dta_type: DtaType::Byte,
            format: "%8.0g".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Numeric(&numeric),
        });
    }
    columns.push(DtaWriteColumn {
        name: "wide_text".into(),
        dta_type: DtaType::StrL,
        format: "%9s".into(),
        label: String::new().into(),
        has_value_labels: false,
        value_labels: Vec::new(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        values: DtaWriteColumnValues::Strings(&text),
    });
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns,
    };

    let mut output = Cursor::new(Vec::new());
    let summary = save_dta_to(&mut output, &data, &DtaWriteOptions::default()).unwrap();
    assert_eq!(summary.format_version, FormatVersion::V119);

    let bytes = output.into_inner();
    assert_eq!(
        format!("{:x}", Sha256::digest(&bytes)),
        "65a4eefafbc550066f61cfe9f9d7898137af21c80cde587b6cbeb8c83cbcc4ed"
    );
    let parsed = read_dta_with_options(
        &bytes,
        &ReadOptions {
            row_start: 0,
            row_count: None,
            column_indices: Some(vec![32_767]),
        },
    )
    .unwrap();
    assert_eq!(
        parsed.columns[0].values,
        ColumnValues::StrL {
            values: text.to_vec()
        }
    );
}

#[test]
fn writes_deduplicated_strl_values_and_null_pointers_for_empty_strings() {
    let values = vec![
        "a repeated long value".to_owned(),
        "a repeated long value".to_owned(),
        "a different long value".to_owned(),
        String::new(),
    ];
    let data = DtaWriteData {
        dataset_label: String::new().into(),
        notes: Vec::new(),
        characteristics: Vec::new(),
        columns: vec![DtaWriteColumn {
            name: "text".into(),
            dta_type: DtaType::StrL,
            format: "%9s".into(),
            label: String::new().into(),
            has_value_labels: false,
            value_labels: Vec::new(),
            notes: Vec::new(),
            characteristics: Vec::new(),
            values: DtaWriteColumnValues::Strings(&values),
        }],
    };

    let mut output = Cursor::new(Vec::new());
    save_dta_to(&mut output, &data, &DtaWriteOptions::default()).unwrap();
    let bytes = output.into_inner();

    let parsed = read_dta(&bytes).unwrap();
    assert_eq!(
        parsed.columns[0].values,
        ColumnValues::StrL {
            values: values.clone()
        }
    );
    assert_eq!(
        bytes.windows(3).filter(|window| *window == b"GSO").count(),
        2,
        "the repeated value should reference its first GSO record"
    );
}
