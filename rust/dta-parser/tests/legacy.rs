use std::fs;
use std::path::{Path, PathBuf};

use dta_parser::{
    parse_metadata, read_dta, ByteOrder, ColumnValues, DtaError, FormatVersion, MissingTag,
};

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/dta")
}

fn fixture(name: &str) -> Vec<u8> {
    fs::read(fixture_dir().join(name)).unwrap()
}

fn synthetic_v113_msf() -> Vec<u8> {
    let nvar = 2_usize;
    let fixed_end = 109 + nvar + nvar * 33 + (nvar + 1) * 2 + nvar * 12 + nvar * 33 + nvar * 81;
    let mut bytes = vec![0_u8; fixed_end];
    bytes[0] = 113;
    bytes[1] = 1;
    bytes[2] = 1;
    bytes[4..6].copy_from_slice(&(nvar as u16).to_be_bytes());
    bytes[6..10].copy_from_slice(&1_i32.to_be_bytes());
    bytes[10..14].copy_from_slice(b"Caf\xe9");

    let mut cursor = 109;
    bytes[cursor..cursor + 2].copy_from_slice(&[252, 4]);
    cursor += 2;
    bytes[cursor..cursor + 3].copy_from_slice(b"num");
    bytes[cursor + 33..cursor + 37].copy_from_slice(b"text");
    cursor += nvar * 33;
    cursor += (nvar + 1) * 2;
    bytes[cursor..cursor + 5].copy_from_slice(b"%9.0g");
    bytes[cursor + 12..cursor + 15].copy_from_slice(b"%4s");
    cursor += nvar * 12;
    bytes[cursor..cursor + 7].copy_from_slice(b"num_lbl");
    cursor += nvar * 33;
    bytes[cursor..cursor + 5].copy_from_slice(b"na\xefve");
    bytes[cursor + 81..cursor + 87].copy_from_slice(b"quoted");

    // One nonempty expansion field followed by the exact sentinel.
    bytes.push(1);
    bytes.extend_from_slice(&3_i32.to_be_bytes());
    bytes.extend_from_slice(b"abc");
    bytes.extend_from_slice(&[0, 0, 0, 0, 0]);
    bytes.extend_from_slice(&321_i16.to_be_bytes());
    bytes.extend_from_slice(&[0x93, b'h', 0x94, 0]);

    // One CP1252 value-label table: 321 -> "é".
    bytes.extend_from_slice(&18_i32.to_be_bytes());
    let table_name = bytes.len();
    bytes.resize(table_name + 33, 0);
    bytes[table_name..table_name + 7].copy_from_slice(b"num_lbl");
    bytes.extend_from_slice(&[0; 3]);
    bytes.extend_from_slice(&1_i32.to_be_bytes());
    bytes.extend_from_slice(&2_i32.to_be_bytes());
    bytes.extend_from_slice(&0_i32.to_be_bytes());
    bytes.extend_from_slice(&321_i32.to_be_bytes());
    bytes.extend_from_slice(&[0xe9, 0]);
    bytes
}

#[test]
fn decodes_checked_legacy_fixtures_and_value_labels() {
    for name in ["all_types_v114.dta", "all_types_v115.dta"] {
        let data = read_dta(&fixture(name)).unwrap_or_else(|error| panic!("{name}: {error}"));
        assert_eq!(data.metadata.format_version, FormatVersion::V115);
        assert_eq!(data.metadata.byte_order, ByteOrder::Lsf);
        assert_eq!(data.row_count, 5);
        assert_eq!(data.columns.len(), 7);
        match &data.columns[0].values {
            ColumnValues::Byte { values, .. } => assert_eq!(values, &[1, 2, 3, 4, 5]),
            other => panic!("unexpected byte storage: {other:?}"),
        }
        match &data.columns[6].values {
            ColumnValues::FixedString { values } => {
                assert_eq!(values[0], "longer_string_1")
            }
            other => panic!("unexpected string storage: {other:?}"),
        }
    }

    let labels = read_dta(&fixture("value_labels_v114.dta")).unwrap();
    assert_eq!(
        labels
            .value_label_table("foreign_lbl")
            .unwrap()
            .entry(1)
            .unwrap()
            .label,
        "Foreign"
    );
    assert_eq!(
        labels.value_label_table("rep_lbl").unwrap().entries.len(),
        5
    );

    let missing = read_dta(&fixture("missing_values_v115.dta")).unwrap();
    match &missing.columns[1].values {
        ColumnValues::Byte { missing_tags, .. } => assert_eq!(
            &missing_tags[..3],
            &[
                Some(MissingTag::System),
                Some(MissingTag::A),
                Some(MissingTag::Z)
            ]
        ),
        other => panic!("unexpected missing byte storage: {other:?}"),
    }
}

#[test]
fn reads_every_checked_in_legacy_fixture_and_true_v114() {
    for name in [
        "all_types_v114.dta",
        "all_types_v115.dta",
        "auto_v114.dta",
        "auto_v115.dta",
        "empty_v114.dta",
        "empty_v115.dta",
        "missing_values_v114.dta",
        "missing_values_v115.dta",
        "value_labels_v114.dta",
        "value_labels_v115.dta",
        "wide_v114.dta",
        "wide_v115.dta",
    ] {
        read_dta(&fixture(name)).unwrap_or_else(|error| panic!("{name}: {error}"));
    }

    let mut true_v114 = fixture("all_types_v115.dta");
    true_v114[0] = 114;
    assert_eq!(
        read_dta(&true_v114).unwrap().metadata.format_version,
        FormatVersion::V114
    );
}

#[test]
fn decodes_true_big_endian_v113_and_windows_1252() {
    let bytes = synthetic_v113_msf();
    let metadata = parse_metadata(&bytes).unwrap();
    assert_eq!(metadata.format_version, FormatVersion::V113);
    assert_eq!(metadata.byte_order, ByteOrder::Msf);
    assert_eq!(metadata.dataset_label, "Café");
    assert_eq!(metadata.variables[0].label, "naïve");
    let data = read_dta(&bytes).unwrap();
    match &data.columns[0].values {
        ColumnValues::Int { values, .. } => assert_eq!(values, &[321]),
        other => panic!("unexpected int storage: {other:?}"),
    }
    match &data.columns[1].values {
        ColumnValues::FixedString { values } => assert_eq!(values, &["“h”"]),
        other => panic!("unexpected fixed string storage: {other:?}"),
    }
    assert_eq!(
        data.value_label_table("num_lbl")
            .unwrap()
            .entry(321)
            .unwrap()
            .label,
        "é"
    );
}

#[test]
fn rejects_malformed_legacy_counts_filetype_and_expansion_fields() {
    let original = synthetic_v113_msf();

    let mut filetype = original.clone();
    filetype[2] = 2;
    assert_eq!(parse_metadata(&filetype), Err(DtaError::InvalidFileType(2)));

    let mut negative_nobs = original.clone();
    negative_nobs[6..10].copy_from_slice(&(-1_i32).to_be_bytes());
    assert_eq!(
        parse_metadata(&negative_nobs),
        Err(DtaError::NegativeObservationCount(-1))
    );

    let metadata = parse_metadata(&original).unwrap();
    let terminator = metadata.section_offsets.data as usize - 5;
    let mut invalid_terminator = original;
    invalid_terminator[terminator + 1..terminator + 5].copy_from_slice(&1_i32.to_be_bytes());
    assert!(matches!(
        parse_metadata(&invalid_terminator),
        Err(DtaError::InvalidExpansionTerminator { value: 1, .. })
    ));
}
