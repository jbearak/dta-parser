use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use dta_parser::{
    read_dta, read_dta_with_options, ColumnValues, DtaError, DtaType, MissingTag, ReadOptions,
};
use serde::Deserialize;
use sha2::{Digest, Sha256};

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/dta")
}

fn fixture(name: &str) -> Vec<u8> {
    fs::read(fixture_dir().join(name))
        .unwrap_or_else(|error| panic!("failed to read shared fixture {name}: {error}"))
}

fn options(row_start: u64, row_count: Option<u64>, columns: Vec<u32>) -> ReadOptions {
    ReadOptions {
        row_start,
        row_count,
        column_indices: Some(columns),
    }
}

fn push_field(bytes: &mut Vec<u8>, value: &[u8], width: usize) {
    assert!(value.len() <= width);
    bytes.extend_from_slice(value);
    bytes.resize(bytes.len() + width - value.len(), 0);
}

fn synthetic_big_endian_v119() -> Vec<u8> {
    const NVAR: usize = 6;
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"<stata_dta><header><release>119</release>");
    bytes.extend_from_slice(b"<byteorder>MSF</byteorder><K>");
    bytes.extend_from_slice(&(NVAR as u32).to_be_bytes());
    bytes.extend_from_slice(b"</K><N>");
    bytes.extend_from_slice(&2_u64.to_be_bytes());
    bytes.extend_from_slice(b"</N><label>");
    let label = b"big endian observations";
    bytes.extend_from_slice(&(label.len() as u16).to_be_bytes());
    bytes.extend_from_slice(label);
    bytes.extend_from_slice(b"</label><timestamp>\0</timestamp></header>");

    let map_start = bytes.len();
    bytes.extend_from_slice(b"<map>");
    let map_payload = bytes.len();
    bytes.resize(bytes.len() + 14 * 8, 0);
    bytes.extend_from_slice(b"</map>");
    let mut offsets = [0_u64; 14];
    offsets[1] = map_start as u64;

    offsets[2] = bytes.len() as u64;
    bytes.extend_from_slice(b"<variable_types>");
    for code in [65_530_u16, 65_529, 65_528, 65_527, 65_526, 4] {
        bytes.extend_from_slice(&code.to_be_bytes());
    }
    bytes.extend_from_slice(b"</variable_types>");

    offsets[3] = bytes.len() as u64;
    bytes.extend_from_slice(b"<varnames>");
    for name in [b"b".as_slice(), b"i", b"l", b"f", b"d", b"s"] {
        push_field(&mut bytes, name, 129);
    }
    bytes.extend_from_slice(b"</varnames>");

    offsets[4] = bytes.len() as u64;
    bytes.extend_from_slice(b"<sortlist>");
    bytes.resize(bytes.len() + (NVAR + 1) * 4, 0);
    bytes.extend_from_slice(b"</sortlist>");

    offsets[5] = bytes.len() as u64;
    bytes.extend_from_slice(b"<formats>");
    for format in [
        b"%8.0g".as_slice(),
        b"%8.0g",
        b"%12.0g",
        b"%9.0g",
        b"%10.0g",
        b"%4s",
    ] {
        push_field(&mut bytes, format, 57);
    }
    bytes.extend_from_slice(b"</formats>");

    offsets[6] = bytes.len() as u64;
    bytes.extend_from_slice(b"<value_label_names>");
    push_field(&mut bytes, b"yn", 129);
    for _ in 1..NVAR {
        push_field(&mut bytes, b"", 129);
    }
    bytes.extend_from_slice(b"</value_label_names>");

    offsets[7] = bytes.len() as u64;
    bytes.extend_from_slice(b"<variable_labels>");
    for variable_label in [
        b"byte".as_slice(),
        b"int",
        b"long",
        b"float",
        b"double",
        b"string",
    ] {
        push_field(&mut bytes, variable_label, 321);
    }
    bytes.extend_from_slice(b"</variable_labels>");

    offsets[8] = bytes.len() as u64;
    bytes.extend_from_slice(b"<characteristics></characteristics>");

    offsets[9] = bytes.len() as u64;
    bytes.extend_from_slice(b"<data>");
    bytes.extend_from_slice(&(-5_i8).to_ne_bytes());
    bytes.extend_from_slice(&(-1234_i16).to_be_bytes());
    bytes.extend_from_slice(&(-1_234_567_i32).to_be_bytes());
    bytes.extend_from_slice(&1.25_f32.to_bits().to_be_bytes());
    bytes.extend_from_slice(&(-2.5_f64).to_bits().to_be_bytes());
    bytes.extend_from_slice(b"ab\0\0");
    bytes.extend_from_slice(&101_i8.to_ne_bytes());
    bytes.extend_from_slice(&32_767_i16.to_be_bytes());
    bytes.extend_from_slice(&2_147_483_622_i32.to_be_bytes());
    bytes.extend_from_slice(&dta_parser::FLOAT_MISSING_Z_BITS.to_be_bytes());
    let double_b = dta_parser::DOUBLE_MISSING_DOT_BITS + 2 * dta_parser::DOUBLE_MISSING_STEP_BITS;
    bytes.extend_from_slice(&double_b.to_be_bytes());
    bytes.extend_from_slice(b"wxyz");
    bytes.extend_from_slice(b"</data>");

    offsets[10] = bytes.len() as u64;
    bytes.extend_from_slice(b"<strls></strls>");

    offsets[11] = bytes.len() as u64;
    bytes.extend_from_slice(b"<value_labels><lbl>");
    let label_text = b"no\0yes\0";
    let table_length = 8 + 2 * 4 + 2 * 4 + label_text.len();
    bytes.extend_from_slice(&(table_length as i32).to_be_bytes());
    push_field(&mut bytes, b"yn", 129);
    bytes.extend_from_slice(&[0; 3]);
    bytes.extend_from_slice(&2_i32.to_be_bytes());
    bytes.extend_from_slice(&(label_text.len() as i32).to_be_bytes());
    bytes.extend_from_slice(&0_i32.to_be_bytes());
    bytes.extend_from_slice(&3_i32.to_be_bytes());
    bytes.extend_from_slice(&(-5_i32).to_be_bytes());
    bytes.extend_from_slice(&101_i32.to_be_bytes());
    bytes.extend_from_slice(label_text);
    bytes.extend_from_slice(b"</lbl></value_labels>");

    offsets[12] = bytes.len() as u64;
    bytes.extend_from_slice(b"</stata_dta>");
    offsets[13] = bytes.len() as u64;

    for (index, offset) in offsets.into_iter().enumerate() {
        let start = map_payload + index * 8;
        bytes[start..start + 8].copy_from_slice(&offset.to_be_bytes());
    }
    bytes
}

#[derive(Debug, Deserialize)]
struct CanonicalSnapshot {
    schema_version: u32,
    source: String,
    fixtures: BTreeMap<String, CanonicalFixture>,
}

#[derive(Debug, Deserialize)]
struct CanonicalFixture {
    sha256: String,
    metadata: CanonicalMetadata,
    columns: Vec<CanonicalColumn>,
    value_label_tables: Vec<CanonicalValueLabelTable>,
}

#[derive(Debug, Deserialize)]
struct CanonicalMetadata {
    format_version: u16,
    byte_order: String,
    nvar: u32,
    nobs: u64,
    dataset_label: String,
    obs_length: u64,
    section_offsets: CanonicalSectionOffsets,
    variables: Vec<CanonicalVariable>,
}

#[derive(Debug, Deserialize)]
struct CanonicalVariable {
    name: String,
    #[serde(rename = "type")]
    storage_type: String,
    type_code: u16,
    format: String,
    label: String,
    value_label_name: String,
    byte_width: u32,
    byte_offset: u64,
}

#[derive(Debug, Deserialize)]
struct CanonicalSectionOffsets {
    stata_data: u64,
    map: u64,
    variable_types: u64,
    varnames: u64,
    sortlist: u64,
    formats: u64,
    value_label_names: u64,
    variable_labels: u64,
    characteristics: u64,
    data: u64,
    strls: u64,
    value_labels: u64,
    stata_data_close: u64,
    end_of_file: u64,
}

impl CanonicalSectionOffsets {
    fn as_array(&self) -> [u64; 14] {
        [
            self.stata_data,
            self.map,
            self.variable_types,
            self.varnames,
            self.sortlist,
            self.formats,
            self.value_label_names,
            self.variable_labels,
            self.characteristics,
            self.data,
            self.strls,
            self.value_labels,
            self.stata_data_close,
            self.end_of_file,
        ]
    }
}

fn actual_section_offsets(offsets: &dta_parser::SectionOffsets) -> [u64; 14] {
    [
        offsets.stata_data,
        offsets.map,
        offsets.variable_types,
        offsets.varnames,
        offsets.sortlist,
        offsets.formats,
        offsets.value_label_names,
        offsets.variable_labels,
        offsets.characteristics,
        offsets.data,
        offsets.strls,
        offsets.value_labels,
        offsets.stata_data_close,
        offsets.end_of_file,
    ]
}

#[derive(Debug, Deserialize)]
struct CanonicalValueLabelTable {
    name: String,
    entries: Vec<CanonicalValueLabelEntry>,
}

#[derive(Debug, Deserialize)]
struct CanonicalValueLabelEntry {
    value: i32,
    label: String,
}

#[derive(Debug, Deserialize)]
struct CanonicalColumn {
    variable_index: u32,
    name: String,
    storage_type: String,
    cells: Vec<CanonicalCell>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum CanonicalCell {
    Missing { missing: String },
    String(String),
    Number(f64),
}

fn assert_canonical_numeric(
    fixture_name: &str,
    column_name: &str,
    values: &[f64],
    missing_tags: &[Option<MissingTag>],
    expected: &[CanonicalCell],
    floating: bool,
) {
    assert_eq!(values.len(), expected.len(), "{fixture_name}:{column_name}");
    assert_eq!(
        missing_tags.len(),
        expected.len(),
        "{fixture_name}:{column_name}"
    );
    for (row, ((actual, missing_tag), expected)) in
        values.iter().zip(missing_tags).zip(expected).enumerate()
    {
        let context = format!("{fixture_name}:{column_name}:row {row}");
        match (missing_tag, expected) {
            (Some(actual_tag), CanonicalCell::Missing { missing }) => {
                assert_eq!(&actual_tag.to_string(), missing, "{context}");
            }
            (None, CanonicalCell::Number(expected)) if floating => {
                // The shared cross-implementation contract permits a 1e-7
                // relative tolerance only for nonmissing floating-point cells.
                let difference = (actual - expected).abs();
                let scale = actual.abs().max(expected.abs());
                assert!(
                    actual == expected || difference <= 1e-7 * scale,
                    "{context}: actual {actual}, expected {expected}, difference {difference}"
                );
            }
            (None, CanonicalCell::Number(expected)) => {
                assert_eq!(actual, expected, "{context}");
            }
            _ => panic!(
                "{context}: actual value {actual} with missing tag {missing_tag:?}, expected {expected:?}"
            ),
        }
    }
}

#[test]
fn every_checked_fixture_matches_the_typescript_haven_oracle() {
    let snapshot: CanonicalSnapshot =
        serde_json::from_str(include_str!("data/modern-canonical.json")).unwrap();
    assert_eq!(snapshot.schema_version, 2);
    assert!(snapshot.source.contains("Production TypeScript DtaFile"));
    let (fixture_inventory, support_inventory) = fs::read_dir(fixture_dir())
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .map(|path| {
            assert!(
                path.is_file(),
                "unexpected fixture-directory entry: {path:?}"
            );
            let is_fixture = path.extension().is_some_and(|extension| extension == "dta");
            (
                path.file_name().unwrap().to_string_lossy().into_owned(),
                is_fixture,
            )
        })
        .fold(
            (BTreeSet::new(), BTreeSet::new()),
            |(mut fixtures, mut support), (name, is_fixture)| {
                if is_fixture {
                    fixtures.insert(name);
                } else {
                    support.insert(name);
                }
                (fixtures, support)
            },
        );
    assert_eq!(
        support_inventory,
        BTreeSet::from([
            "generate_fixtures.do".to_owned(),
            "generate_legacy_fixtures.do".to_owned(),
        ])
    );
    let snapshot_inventory = snapshot.fixtures.keys().cloned().collect::<BTreeSet<_>>();
    assert_eq!(fixture_inventory, snapshot_inventory);
    assert_eq!(snapshot.fixtures.len(), 29);

    for (fixture_name, expected_fixture) in snapshot.fixtures {
        let bytes = fixture(&fixture_name);
        let actual_sha256 = format!("{:x}", Sha256::digest(&bytes));
        assert_eq!(actual_sha256, expected_fixture.sha256, "{fixture_name}");
        let data = read_dta(&bytes)
            .unwrap_or_else(|error| panic!("failed to read {fixture_name}: {error}"));
        let metadata = &data.metadata;
        let expected_metadata = &expected_fixture.metadata;
        assert_eq!(
            metadata.format_version.as_u16(),
            expected_metadata.format_version,
            "{fixture_name}"
        );
        assert_eq!(
            match metadata.byte_order {
                dta_parser::ByteOrder::Lsf => "LSF",
                dta_parser::ByteOrder::Msf => "MSF",
            },
            expected_metadata.byte_order,
            "{fixture_name}"
        );
        assert_eq!(metadata.nvar, expected_metadata.nvar, "{fixture_name}");
        assert_eq!(metadata.nobs, expected_metadata.nobs, "{fixture_name}");
        assert_eq!(
            metadata.dataset_label, expected_metadata.dataset_label,
            "{fixture_name}"
        );
        assert_eq!(
            metadata.obs_length, expected_metadata.obs_length,
            "{fixture_name}"
        );
        assert_eq!(
            actual_section_offsets(&metadata.section_offsets),
            expected_metadata.section_offsets.as_array(),
            "{fixture_name}"
        );
        assert_eq!(
            metadata.variables.len(),
            expected_metadata.variables.len(),
            "{fixture_name}"
        );
        for (actual, expected) in metadata.variables.iter().zip(&expected_metadata.variables) {
            assert_eq!(actual.name, expected.name, "{fixture_name}");
            assert_eq!(
                actual.dta_type.to_string(),
                expected.storage_type,
                "{fixture_name}"
            );
            assert_eq!(actual.type_code, expected.type_code, "{fixture_name}");
            assert_eq!(actual.format, expected.format, "{fixture_name}");
            assert_eq!(actual.label, expected.label, "{fixture_name}");
            assert_eq!(
                actual.value_label_name, expected.value_label_name,
                "{fixture_name}"
            );
            assert_eq!(actual.byte_width, expected.byte_width, "{fixture_name}");
            assert_eq!(actual.byte_offset, expected.byte_offset, "{fixture_name}");
        }
        assert_eq!(data.row_count, expected_metadata.nobs, "{fixture_name}");
        assert_eq!(data.columns.len(), expected_fixture.columns.len());

        for (column, expected_column) in data.columns.iter().zip(&expected_fixture.columns) {
            let variable = &data.metadata.variables[column.variable_index as usize];
            assert_eq!(column.variable_index, expected_column.variable_index);
            assert_eq!(variable.name, expected_column.name);
            assert_eq!(variable.dta_type.to_string(), expected_column.storage_type);
            match &column.values {
                ColumnValues::Byte {
                    values,
                    missing_tags,
                } => assert_canonical_numeric(
                    &fixture_name,
                    &variable.name,
                    &values
                        .iter()
                        .map(|value| f64::from(*value))
                        .collect::<Vec<_>>(),
                    missing_tags,
                    &expected_column.cells,
                    false,
                ),
                ColumnValues::Int {
                    values,
                    missing_tags,
                } => assert_canonical_numeric(
                    &fixture_name,
                    &variable.name,
                    &values
                        .iter()
                        .map(|value| f64::from(*value))
                        .collect::<Vec<_>>(),
                    missing_tags,
                    &expected_column.cells,
                    false,
                ),
                ColumnValues::Long {
                    values,
                    missing_tags,
                } => assert_canonical_numeric(
                    &fixture_name,
                    &variable.name,
                    &values
                        .iter()
                        .map(|value| f64::from(*value))
                        .collect::<Vec<_>>(),
                    missing_tags,
                    &expected_column.cells,
                    false,
                ),
                ColumnValues::Float {
                    values,
                    missing_tags,
                } => assert_canonical_numeric(
                    &fixture_name,
                    &variable.name,
                    &values
                        .iter()
                        .map(|value| f64::from(*value))
                        .collect::<Vec<_>>(),
                    missing_tags,
                    &expected_column.cells,
                    true,
                ),
                ColumnValues::Double {
                    values,
                    missing_tags,
                } => assert_canonical_numeric(
                    &fixture_name,
                    &variable.name,
                    values,
                    missing_tags,
                    &expected_column.cells,
                    true,
                ),
                ColumnValues::FixedString { values } => {
                    assert_eq!(values.len(), expected_column.cells.len());
                    for (row, (actual, expected)) in
                        values.iter().zip(&expected_column.cells).enumerate()
                    {
                        match expected {
                            CanonicalCell::String(expected) => assert_eq!(
                                actual, expected,
                                "{fixture_name}:{}:row {row}",
                                variable.name
                            ),
                            other => panic!(
                                "{fixture_name}:{}:row {row}: expected string, found {other:?}",
                                variable.name
                            ),
                        }
                    }
                }
                ColumnValues::StrL { values } => {
                    assert_eq!(values.len(), expected_column.cells.len());
                    for (row, (actual, expected)) in
                        values.iter().zip(&expected_column.cells).enumerate()
                    {
                        match expected {
                            CanonicalCell::String(expected) => assert_eq!(
                                actual, expected,
                                "{fixture_name}:{}:row {row}",
                                variable.name
                            ),
                            other => panic!(
                                "{fixture_name}:{}:row {row}: expected strL string, found {other:?}",
                                variable.name
                            ),
                        }
                    }
                }
            }
        }

        assert_eq!(
            data.value_label_tables.len(),
            expected_fixture.value_label_tables.len(),
            "{fixture_name}"
        );
        for (actual, expected) in data
            .value_label_tables
            .iter()
            .zip(&expected_fixture.value_label_tables)
        {
            assert_eq!(actual.name, expected.name, "{fixture_name}");
            assert_eq!(
                actual.entries.len(),
                expected.entries.len(),
                "{fixture_name}"
            );
            for (actual, expected) in actual.entries.iter().zip(&expected.entries) {
                assert_eq!(actual.value, expected.value, "{fixture_name}");
                assert_eq!(actual.label, expected.label, "{fixture_name}");
            }
        }
    }
}

#[test]
fn nominal_auto_v119_filename_does_not_override_its_release_118_header() {
    let snapshot: CanonicalSnapshot =
        serde_json::from_str(include_str!("data/modern-canonical.json")).unwrap();
    let expected = snapshot.fixtures.get("auto_v119.dta").unwrap();
    let metadata = dta_parser::parse_metadata(&fixture("auto_v119.dta")).unwrap();

    assert_eq!(metadata.format_version, dta_parser::FormatVersion::V118);
    assert_eq!(
        expected.metadata.format_version,
        metadata.format_version.as_u16()
    );
}

#[test]
fn decodes_big_endian_v119_observations_and_labels() {
    let data = read_dta(&synthetic_big_endian_v119()).unwrap();
    assert_eq!(
        data.metadata.format_version,
        dta_parser::FormatVersion::V119
    );
    assert_eq!(data.metadata.byte_order, dta_parser::ByteOrder::Msf);
    assert_eq!(data.metadata.obs_length, 23);
    assert_eq!(data.row_count, 2);

    match &data.columns[0].values {
        ColumnValues::Byte {
            values,
            missing_tags,
        } => {
            assert_eq!(values, &[-5, 101]);
            assert_eq!(missing_tags, &[None, Some(MissingTag::System)]);
        }
        other => panic!("unexpected byte storage: {other:?}"),
    }
    match &data.columns[1].values {
        ColumnValues::Int {
            values,
            missing_tags,
        } => {
            assert_eq!(values, &[-1234, 32_767]);
            assert_eq!(missing_tags[1], Some(MissingTag::Z));
        }
        other => panic!("unexpected int storage: {other:?}"),
    }
    match &data.columns[2].values {
        ColumnValues::Long {
            values,
            missing_tags,
        } => {
            assert_eq!(values, &[-1_234_567, 2_147_483_622]);
            assert_eq!(missing_tags[1], Some(MissingTag::A));
        }
        other => panic!("unexpected long storage: {other:?}"),
    }
    match &data.columns[3].values {
        ColumnValues::Float {
            values,
            missing_tags,
        } => {
            assert_eq!(values[0].to_bits(), 1.25_f32.to_bits());
            assert_eq!(values[1].to_bits(), dta_parser::FLOAT_MISSING_Z_BITS);
            assert_eq!(missing_tags[1], Some(MissingTag::Z));
        }
        other => panic!("unexpected float storage: {other:?}"),
    }
    match &data.columns[4].values {
        ColumnValues::Double {
            values,
            missing_tags,
        } => {
            assert_eq!(values[0].to_bits(), (-2.5_f64).to_bits());
            assert_eq!(missing_tags[1], Some(MissingTag::B));
        }
        other => panic!("unexpected double storage: {other:?}"),
    }
    match &data.columns[5].values {
        ColumnValues::FixedString { values } => assert_eq!(values, &["ab", "wxyz"]),
        other => panic!("unexpected string storage: {other:?}"),
    }
    let table = data.value_label_table_for_variable(0).unwrap();
    assert_eq!(table.entry(-5).unwrap().label, "no");
    assert_eq!(table.entry(101).unwrap().label, "yes");
}

#[test]
fn matches_typescript_and_haven_derived_auto_values_across_v117_and_v118() {
    let v117 = read_dta(&fixture("auto_v117.dta")).unwrap();
    let v118 = read_dta(&fixture("auto_v118.dta")).unwrap();
    assert_eq!(v117.row_count, 74);
    assert_eq!(v118.row_count, 74);
    assert_eq!(v117.columns, v118.columns);

    assert_eq!(
        v118.metadata.variables[0].dta_type,
        DtaType::FixedString(18)
    );
    assert_eq!(v118.metadata.variables[1].dta_type, DtaType::Int);
    assert_eq!(v118.metadata.variables[1].type_code, 65_529);
    assert_eq!(v118.metadata.variables[1].byte_offset, 18);

    match &v118.column_by_name("make").unwrap().values {
        ColumnValues::FixedString { values } => {
            assert_eq!(&values[..3], ["AMC Concord", "AMC Pacer", "AMC Spirit"]);
        }
        other => panic!("unexpected make storage: {other:?}"),
    }
    match &v118.column_by_name("price").unwrap().values {
        ColumnValues::Int {
            values,
            missing_tags,
        } => {
            assert_eq!(&values[..5], [4099, 4749, 3799, 4816, 7827]);
            assert_eq!(&missing_tags[..5], [None; 5]);
        }
        other => panic!("unexpected price storage: {other:?}"),
    }
    match &v118.column_by_name("gear_ratio").unwrap().values {
        ColumnValues::Float { values, .. } => {
            assert_eq!(values[0].to_bits(), 3.58_f32.to_bits());
            assert_eq!(values[1].to_bits(), 2.53_f32.to_bits());
        }
        other => panic!("unexpected gear_ratio storage: {other:?}"),
    }
    match &v118.column_by_name("rep78").unwrap().values {
        ColumnValues::Int { missing_tags, .. } => {
            assert_eq!(missing_tags[2], Some(MissingTag::System));
        }
        other => panic!("unexpected rep78 storage: {other:?}"),
    }
}

#[test]
fn decodes_every_supported_storage_width_and_projected_row_window() {
    let data = read_dta_with_options(
        &fixture("all_types_v118.dta"),
        &options(1, Some(2), vec![6, 0, 4, 0, 1, 2, 3, 5]),
    )
    .unwrap();
    assert_eq!(data.row_start, 1);
    assert_eq!(data.row_count, 2);
    assert_eq!(
        data.columns
            .iter()
            .map(|column| column.variable_index)
            .collect::<Vec<_>>(),
        [6, 0, 4, 1, 2, 3, 5]
    );

    match &data.columns[0].values {
        ColumnValues::FixedString { values } => {
            assert_eq!(values, &["longer_string_2", "longer_string_3"])
        }
        other => panic!("unexpected str20 storage: {other:?}"),
    }
    match &data.columns[1].values {
        ColumnValues::Byte { values, .. } => assert_eq!(values, &[2, 3]),
        other => panic!("unexpected byte storage: {other:?}"),
    }
    match &data.columns[2].values {
        ColumnValues::Double { values, .. } => {
            assert_eq!(values, &[2.222222222, 3.333333333])
        }
        other => panic!("unexpected double storage: {other:?}"),
    }
    match &data.columns[3].values {
        ColumnValues::Int { values, .. } => assert_eq!(values, &[200, 300]),
        other => panic!("unexpected int storage: {other:?}"),
    }
    match &data.columns[4].values {
        ColumnValues::Long { values, .. } => assert_eq!(values, &[200_000, 300_000]),
        other => panic!("unexpected long storage: {other:?}"),
    }
    match &data.columns[5].values {
        ColumnValues::Float { values, .. } => assert_eq!(
            values
                .iter()
                .map(|value| value.to_bits())
                .collect::<Vec<_>>(),
            [2.2_f32.to_bits(), 3.3_f32.to_bits()]
        ),
        other => panic!("unexpected float storage: {other:?}"),
    }
    match &data.columns[6].values {
        ColumnValues::FixedString { values } => assert_eq!(values, &["s2", "s3"]),
        other => panic!("unexpected str5 storage: {other:?}"),
    }
}

#[test]
fn preserves_raw_numeric_missing_values_and_all_storage_tags() {
    let data = read_dta(&fixture("missing_values_v118.dta")).unwrap();
    let expected_first_three = [
        Some(MissingTag::System),
        Some(MissingTag::A),
        Some(MissingTag::Z),
    ];

    match &data.columns[0].values {
        ColumnValues::Double {
            values,
            missing_tags,
        } => {
            assert_eq!(
                &missing_tags[..5],
                &[
                    Some(MissingTag::System),
                    Some(MissingTag::A),
                    Some(MissingTag::B),
                    Some(MissingTag::C),
                    Some(MissingTag::Z),
                ]
            );
            assert_eq!(values[0].to_bits(), dta_parser::DOUBLE_MISSING_DOT_BITS);
            assert_eq!(values[4].to_bits(), dta_parser::DOUBLE_MISSING_Z_BITS);
        }
        other => panic!("unexpected double storage: {other:?}"),
    }
    match &data.columns[1].values {
        ColumnValues::Byte {
            values,
            missing_tags,
        } => {
            assert_eq!(&missing_tags[..3], &expected_first_three);
            assert_eq!(&values[..3], &[101, 102, 127]);
        }
        other => panic!("unexpected byte storage: {other:?}"),
    }
    match &data.columns[2].values {
        ColumnValues::Int { missing_tags, .. } => {
            assert_eq!(&missing_tags[..3], &expected_first_three)
        }
        other => panic!("unexpected int storage: {other:?}"),
    }
    match &data.columns[3].values {
        ColumnValues::Long { missing_tags, .. } => {
            assert_eq!(&missing_tags[..3], &expected_first_three)
        }
        other => panic!("unexpected long storage: {other:?}"),
    }
    match &data.columns[4].values {
        ColumnValues::Float {
            values,
            missing_tags,
        } => {
            assert_eq!(&missing_tags[..3], &expected_first_three);
            assert_eq!(values[0].to_bits(), dta_parser::FLOAT_MISSING_DOT_BITS);
            assert_eq!(values[2].to_bits(), dta_parser::FLOAT_MISSING_Z_BITS);
        }
        other => panic!("unexpected float storage: {other:?}"),
    }
}

#[test]
fn clamps_ranges_supports_empty_projection_and_resolves_strl_columns() {
    let bytes = fixture("all_types_v118.dta");
    let past_end = read_dta_with_options(&bytes, &options(99, Some(10), vec![0])).unwrap();
    assert_eq!((past_end.row_start, past_end.row_count), (5, 0));
    assert!(past_end.columns[0].values.is_empty());

    let no_columns = read_dta_with_options(&bytes, &options(0, None, vec![])).unwrap();
    assert_eq!(no_columns.row_count, 5);
    assert!(no_columns.columns.is_empty());

    assert!(matches!(
        read_dta_with_options(&bytes, &options(0, None, vec![8])),
        Err(DtaError::InvalidColumnIndex { index: 8, nvar: 8 })
    ));
    let full = read_dta(&bytes).unwrap();
    match &full.columns[7].values {
        ColumnValues::StrL { values } => assert_eq!(
            values,
            &[
                "This is a strL value for obs 1",
                "This is a strL value for obs 2",
                "This is a strL value for obs 3",
                "This is a strL value for obs 4",
                "This is a strL value for obs 5",
            ]
        ),
        other => panic!("unexpected strL storage: {other:?}"),
    }
}

#[test]
fn validates_data_tags_geometry_and_closing_map_offset() {
    let original = fixture("auto_v118.dta");
    let metadata = dta_parser::parse_metadata(&original).unwrap();

    let mut bad_open = original.clone();
    bad_open[metadata.section_offsets.data as usize] = b'X';
    assert!(matches!(
        read_dta(&bad_open),
        Err(DtaError::UnexpectedTag {
            expected: "<data>",
            ..
        })
    ));

    let mut bad_close = original;
    let close = metadata.section_offsets.strls as usize - b"</data>".len();
    bad_close[close + 2] = b'X';
    assert!(matches!(
        read_dta(&bad_close),
        Err(DtaError::UnexpectedTag {
            expected: "</data>",
            ..
        })
    ));
}

#[test]
fn validates_strls_envelope_while_projecting_a_real_strl_fixture() {
    let original = fixture("strl_test_v118.dta");
    let metadata = dta_parser::parse_metadata(&original).unwrap();
    let projected = read_dta_with_options(&original, &options(0, None, vec![1, 2])).unwrap();
    assert_eq!(projected.row_count, 5);
    assert_eq!(
        projected
            .columns
            .iter()
            .map(|column| column.variable_index)
            .collect::<Vec<_>>(),
        [1, 2]
    );

    let strls = metadata.section_offsets.strls as usize;
    let mut missing_open = original.clone();
    missing_open[strls] = b'X';
    assert!(matches!(
        read_dta_with_options(&missing_open, &options(0, None, vec![1, 2])),
        Err(DtaError::UnexpectedTag {
            expected: "<strls>",
            ..
        })
    ));

    let truncated = &original[..strls + 3];
    assert!(matches!(
        read_dta_with_options(truncated, &options(0, None, vec![1, 2])),
        Err(DtaError::Truncated {
            context: "<strls>",
            ..
        })
    ));

    let close = metadata.section_offsets.value_labels as usize - b"</strls>".len();
    let truncated_close = &original[..close + 3];
    assert!(matches!(
        read_dta_with_options(truncated_close, &options(0, None, vec![1, 2])),
        Err(DtaError::Truncated {
            context: "</strls>",
            ..
        })
    ));

    let mut missing_close = original;
    missing_close[close + 2] = b'X';
    assert!(matches!(
        read_dta_with_options(&missing_close, &options(0, None, vec![1, 2])),
        Err(DtaError::UnexpectedTag {
            expected: "</strls>",
            ..
        })
    ));
}

#[test]
fn canonical_data_serde_keeps_u64s_decimal_and_storage_explicit() {
    let data =
        read_dta_with_options(&fixture("auto_v118.dta"), &options(2, Some(1), vec![11])).unwrap();
    let json = serde_json::to_value(data).unwrap();
    assert_eq!(json["row_start"], "2");
    assert_eq!(json["row_count"], "1");
    assert_eq!(json["columns"][0]["variable_index"], 11);
    assert_eq!(json["columns"][0]["values"]["storage_type"], "byte");
    assert_eq!(
        json["columns"][0]["values"]["values"],
        serde_json::json!([0])
    );
}
