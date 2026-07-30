use std::fs;
use std::path::{Path, PathBuf};

use dta_parser::{
    parse_metadata, read_dta, read_dta_with_encoding, ByteOrder, ColumnValues, DtaError, DtaFile,
    FormatVersion, MissingTag, ReadOptions, TextEncoding,
};
use std::io::Cursor;

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/dta")
}

fn fixture(name: &str) -> Vec<u8> {
    fs::read(fixture_dir().join(name)).unwrap()
}

fn v111_fixture() -> Vec<u8> {
    fs::read(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/data/synthetic-v111.dta")).unwrap()
}

fn synthetic_legacy_msf(version: u8) -> Vec<u8> {
    let nvar = 2_usize;
    let fixed_end = 109 + nvar + nvar * 33 + (nvar + 1) * 2 + nvar * 12 + nvar * 33 + nvar * 81;
    let mut bytes = vec![0_u8; fixed_end];
    bytes[0] = version;
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

    // One dataset note characteristic followed by the exact sentinel.
    let mut note = vec![0_u8; 2 * 33];
    note[..4].copy_from_slice(b"_dta");
    note[33..38].copy_from_slice(b"note1");
    note.extend_from_slice(b"Caf\xe9\0");
    bytes.push(1);
    bytes.extend_from_slice(&(note.len() as i32).to_be_bytes());
    bytes.extend_from_slice(&note);
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

fn synthetic_v113_msf() -> Vec<u8> {
    synthetic_legacy_msf(113)
}

#[test]
fn decodes_checked_legacy_fixtures_and_value_labels() {
    let name = "all_types_v115.dta";
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

    let labels = read_dta(&fixture("value_labels_v115.dta")).unwrap();
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
fn decodes_release_111_metadata_observations_labels_and_missing_tags() {
    let bytes = v111_fixture();
    let data = read_dta(&bytes).unwrap();
    assert_eq!(data.metadata.format_version, FormatVersion::V111);
    assert_eq!(data.metadata.byte_order, ByteOrder::Lsf);
    assert_eq!(data.metadata.dataset_label, "Stata/SE 7 Café fixture");
    assert_eq!(data.metadata.notes, ["Release 111 note"]);
    assert_eq!(data.metadata.nvar, 6);
    assert_eq!(data.metadata.nobs, 4);
    assert_eq!(data.metadata.variables[5].name, "text");
    assert_eq!(data.metadata.variables[5].label, "CP1252 text");

    for column in &data.columns[..3] {
        let missing_tags = match &column.values {
            ColumnValues::Byte { missing_tags, .. }
            | ColumnValues::Int { missing_tags, .. }
            | ColumnValues::Long { missing_tags, .. }
            | ColumnValues::Float { missing_tags, .. }
            | ColumnValues::Double { missing_tags, .. } => missing_tags,
            other => panic!("unexpected numeric storage: {other:?}"),
        };
        assert_eq!(missing_tags, &[None, None, None, Some(MissingTag::System)]);
    }
    for column in &data.columns[3..5] {
        let missing_tags = match &column.values {
            ColumnValues::Float { missing_tags, .. }
            | ColumnValues::Double { missing_tags, .. } => missing_tags,
            other => panic!("unexpected floating-point storage: {other:?}"),
        };
        assert_eq!(
            missing_tags,
            &[
                None,
                Some(MissingTag::System),
                Some(MissingTag::System),
                Some(MissingTag::System)
            ]
        );
    }
    let ColumnValues::FixedString { values } = &data.columns[5].values else {
        panic!("text must be a fixed string");
    };
    assert_eq!(values, &["alpha", "", "Café", "omega"]);
    assert_eq!(
        data.value_label_table("b_labels")
            .unwrap()
            .entry(1)
            .unwrap()
            .label,
        "One"
    );
    let old_max = data
        .value_label_table("b_labels")
        .unwrap()
        .entry(2_147_483_621)
        .unwrap();
    assert_eq!(old_max.label, "Old max");
    assert_eq!(old_max.missing_tag, None);
}

#[test]
fn release_111_slice_and_file_projection_windows_are_identical() {
    let bytes = v111_fixture();
    let options = ReadOptions {
        row_start: 1,
        row_count: Some(2),
        column_indices: Some(vec![5, 0, 5]),
    };
    let expected = dta_parser::read_dta_with_options(&bytes, &options).unwrap();
    let mut file = DtaFile::from_reader(Cursor::new(bytes)).unwrap();
    assert_eq!(file.read_with_options(&options).unwrap(), expected);
    assert_eq!(expected.row_count, 2);
    assert_eq!(expected.columns.len(), 2);
}

#[test]
fn release_111_truncation_and_malformed_expansions_fail_without_panicking() {
    let bytes = v111_fixture();
    let metadata = parse_metadata(&bytes).unwrap();
    let expansion = metadata.section_offsets.characteristics as usize;

    let truncated = bytes[..expansion].to_vec();
    let slice_error = parse_metadata(&truncated).unwrap_err();
    let file_error = DtaFile::from_reader(Cursor::new(truncated)).err().unwrap();
    assert!(matches!(slice_error, DtaError::Truncated { .. }));
    assert!(matches!(file_error, DtaError::Io { .. }));

    let mut oversized = bytes;
    oversized[expansion + 1..expansion + 5].copy_from_slice(&i32::MAX.to_le_bytes());
    let slice_error = parse_metadata(&oversized).unwrap_err();
    assert!(matches!(slice_error, DtaError::Truncated { .. }));
    let file_error = DtaFile::from_reader(Cursor::new(oversized)).err().unwrap();
    assert_eq!(file_error, slice_error);
}

#[test]
fn reads_every_checked_in_legacy_fixture_and_synthetic_v114() {
    for name in [
        "all_types_v115.dta",
        "auto_v115.dta",
        "empty_v115.dta",
        "missing_values_v115.dta",
        "value_labels_v115.dta",
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
    assert_eq!(metadata.notes, ["Café"]);
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
fn decodes_big_endian_release_111_observations_notes_and_labels() {
    let mut bytes = synthetic_legacy_msf(111);
    let data_offset = parse_metadata(&bytes).unwrap().section_offsets.data as usize;
    bytes[data_offset..data_offset + 2].copy_from_slice(&i16::MAX.to_be_bytes());
    let data = read_dta(&bytes).unwrap();
    assert_eq!(data.metadata.format_version, FormatVersion::V111);
    assert_eq!(data.metadata.byte_order, ByteOrder::Msf);
    assert_eq!(data.metadata.notes, ["Café"]);
    let ColumnValues::Int {
        values,
        missing_tags,
    } = &data.columns[0].values
    else {
        panic!("num must be an int");
    };
    assert_eq!(values, &[i16::MAX]);
    assert_eq!(missing_tags, &[Some(MissingTag::System)]);
    let ColumnValues::FixedString { values } = &data.columns[1].values else {
        panic!("text must be a fixed string");
    };
    assert_eq!(values, &["“h”"]);
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
fn explicit_encoding_overrides_every_legacy_text_surface() {
    let bytes = synthetic_v113_msf();
    let latin1 = read_dta_with_encoding(&bytes, TextEncoding::Iso8859_1).unwrap();
    assert_eq!(latin1.metadata.dataset_label, "Café");
    assert_eq!(latin1.metadata.notes, ["Café"]);
    assert_eq!(latin1.metadata.variables[0].label, "naïve");
    let ColumnValues::FixedString { values } = &latin1.columns[1].values else {
        panic!("text must be a fixed string");
    };
    assert_eq!(values, &["\u{93}h\u{94}"]);
    assert_eq!(
        latin1
            .value_label_table("num_lbl")
            .unwrap()
            .entry(321)
            .unwrap()
            .label,
        "é"
    );

    let utf8 = read_dta_with_encoding(&bytes, TextEncoding::Utf8).unwrap();
    assert_eq!(utf8.metadata.dataset_label, "Caf\u{fffd}");
    assert_eq!(utf8.metadata.notes, ["Caf\u{fffd}"]);
    assert_eq!(utf8.metadata.variables[0].label, "na\u{fffd}ve");

    let mut file =
        DtaFile::from_reader_with_encoding(Cursor::new(bytes), TextEncoding::Iso8859_1).unwrap();
    assert_eq!(file.read().unwrap(), latin1);
}

#[test]
fn omits_empty_legacy_dataset_notes() {
    let mut bytes = synthetic_v113_msf();
    let value = bytes
        .windows(5)
        .rposition(|window| window == b"Caf\xe9\0")
        .unwrap();
    bytes[value] = 0;
    assert!(parse_metadata(&bytes).unwrap().notes.is_empty());
    assert!(DtaFile::from_reader(Cursor::new(bytes))
        .unwrap()
        .metadata()
        .notes
        .is_empty());
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

    let original = synthetic_v113_msf();
    let expansion = parse_metadata(&original)
        .unwrap()
        .section_offsets
        .characteristics as usize;
    let mut oversized = original;
    oversized[expansion + 1..expansion + 5].copy_from_slice(&i32::MAX.to_be_bytes());
    let slice_error = parse_metadata(&oversized).unwrap_err();
    assert!(matches!(
        slice_error,
        DtaError::Truncated {
            context: "legacy expansion-field payload",
            ..
        }
    ));
    let file_error = DtaFile::from_reader(Cursor::new(oversized)).err().unwrap();
    assert_eq!(file_error, slice_error);
}
