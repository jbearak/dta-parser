mod support;

use dta_parser::{
    parse_metadata, parse_value_labels, read_dta, ByteOrder, DtaError, DtaMetadata, FormatVersion,
    MissingTag, SectionOffsets,
};
use support::fixture;

fn find(bytes: &[u8], needle: &[u8]) -> usize {
    bytes
        .windows(needle.len())
        .position(|window| window == needle)
        .unwrap_or_else(|| panic!("fixture is missing {:?}", String::from_utf8_lossy(needle)))
}

#[test]
fn matches_typescript_tables_exactly_in_disk_order_across_v117_and_v118() {
    let v117_bytes = fixture("value_labels_v117.dta");
    let v117_metadata = parse_metadata(&v117_bytes).unwrap();
    let v117 = parse_value_labels(&v117_bytes, &v117_metadata).unwrap();

    let v118_bytes = fixture("value_labels_v118.dta");
    let v118_metadata = parse_metadata(&v118_bytes).unwrap();
    let v118 = parse_value_labels(&v118_bytes, &v118_metadata).unwrap();
    assert_eq!(v117, v118);
    assert_eq!(
        v118.iter()
            .map(|table| table.name.as_str())
            .collect::<Vec<_>>(),
        ["region_lbl", "rep_lbl", "foreign_lbl"]
    );
    assert_eq!(
        v118[0]
            .entries
            .iter()
            .map(|entry| (entry.value, entry.label.as_str()))
            .collect::<Vec<_>>(),
        [(1, "Northeast"), (2, "Midwest"), (3, "South"), (4, "West"),]
    );
    assert_eq!(v118[1].entry(5).unwrap().label, "Excellent");
    assert_eq!(v118[2].entry(0).unwrap().label, "Domestic");
    assert_eq!(v118[2].entry(1).unwrap().label, "Foreign");
    assert!(v118
        .iter()
        .flat_map(|table| &table.entries)
        .all(|entry| entry.missing_tag.is_none()));
}

#[test]
fn resolves_variable_to_table_associations_by_stata_name() {
    let data = read_dta(&fixture("value_labels_v118.dta")).unwrap();
    let foreign = data.value_label_table_for_variable(0).unwrap();
    let rep78 = data.value_label_table_for_variable(1).unwrap();
    let region = data.value_label_table_for_variable(2).unwrap();
    assert_eq!(foreign.name, "foreign_lbl");
    assert_eq!(foreign.entry(1).unwrap().label, "Foreign");
    assert_eq!(rep78.name, "rep_lbl");
    assert_eq!(region.name, "region_lbl");
    assert!(data.value_label_table_for_variable(3).is_none());

    let auto = read_dta(&fixture("auto_v118.dta")).unwrap();
    assert_eq!(
        auto.value_label_table_for_variable(11)
            .unwrap()
            .entry(0)
            .unwrap()
            .label,
        "Domestic"
    );
    assert!(auto.value_label_table_for_variable(0).is_none());
}

#[test]
fn parses_empty_sections_and_classifies_labeled_missing_codes() {
    let empty_bytes = fixture("empty_v118.dta");
    let empty_metadata = parse_metadata(&empty_bytes).unwrap();
    assert!(parse_value_labels(&empty_bytes, &empty_metadata)
        .unwrap()
        .is_empty());

    let mut bytes = fixture("value_labels_v118.dta");
    let metadata = parse_metadata(&bytes).unwrap();
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let payload_start = table_start + b"<lbl>".len() + 4 + 129 + 3;
    let entry_count = 4_usize;
    let first_value = payload_start + 8 + entry_count * 4;
    for entry_index in 0..entry_count {
        let value = 2_147_483_621_i32 + i32::try_from(entry_index).unwrap();
        let position = first_value + entry_index * 4;
        bytes[position..position + 4].copy_from_slice(&value.to_le_bytes());
    }
    let tables = parse_value_labels(&bytes, &metadata).unwrap();
    assert_eq!(tables[0].entries[0].value, 2_147_483_621);
    assert_eq!(tables[0].entries[0].missing_tag, Some(MissingTag::System));
    assert_eq!(tables[0].entries[1].missing_tag, Some(MissingTag::A));
    assert_eq!(tables[0].entries[3].missing_tag, Some(MissingTag::C));
}

#[test]
fn parses_a_strict_big_endian_v119_label_table() {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"<value_labels><lbl>");
    let text = b"big\0";
    let payload_length = 8 + 4 + 4 + text.len();
    bytes.extend_from_slice(&(payload_length as i32).to_be_bytes());
    bytes.extend_from_slice(b"answer");
    bytes.resize(bytes.len() + 129 - b"answer".len(), 0);
    bytes.extend_from_slice(&[0; 3]);
    bytes.extend_from_slice(&1_i32.to_be_bytes());
    bytes.extend_from_slice(&(text.len() as i32).to_be_bytes());
    bytes.extend_from_slice(&0_i32.to_be_bytes());
    bytes.extend_from_slice(&42_i32.to_be_bytes());
    bytes.extend_from_slice(text);
    bytes.extend_from_slice(b"</lbl></value_labels>");
    let stata_data_close = bytes.len() as u64;
    bytes.extend_from_slice(b"</stata_dta>");
    let end_of_file = bytes.len() as u64;

    let metadata = DtaMetadata {
        format_version: FormatVersion::V119,
        byte_order: ByteOrder::Msf,
        nvar: 0,
        nobs: 0,
        dataset_label: String::new(),
        notes: Vec::new(),
        variables: vec![],
        section_offsets: SectionOffsets {
            stata_data: 0,
            map: 1,
            variable_types: 2,
            varnames: 3,
            sortlist: 4,
            formats: 5,
            value_label_names: 6,
            variable_labels: 7,
            characteristics: 8,
            data: 9,
            strls: 10,
            value_labels: 0,
            stata_data_close,
            end_of_file,
        },
        obs_length: 0,
    };
    let tables = parse_value_labels(&bytes, &metadata).unwrap();
    assert_eq!(tables.len(), 1);
    assert_eq!(tables[0].name, "answer");
    assert_eq!(tables[0].entry(42).unwrap().label, "big");
}

#[test]
fn rejects_negative_lengths_bad_offsets_and_missing_nuls() {
    let original = fixture("value_labels_v118.dta");
    let metadata = parse_metadata(&original).unwrap();
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let length_offset = table_start + b"<lbl>".len();
    let name_start = length_offset + 4;
    let payload_start = name_start + 129 + 3;

    let mut negative_length = original.clone();
    negative_length[length_offset..length_offset + 4].copy_from_slice(&(-1_i32).to_le_bytes());
    assert!(matches!(
        parse_value_labels(&negative_length, &metadata),
        Err(DtaError::NegativeValueLabelField {
            field: "table length",
            ..
        })
    ));

    let mut wrong_length = original.clone();
    wrong_length[length_offset..length_offset + 4].copy_from_slice(&70_i32.to_le_bytes());
    assert!(matches!(
        parse_value_labels(&wrong_length, &metadata),
        Err(DtaError::InvalidValueLabelLength {
            declared: 70,
            expected: 69,
            ..
        })
    ));

    let mut negative_count = original.clone();
    negative_count[payload_start..payload_start + 4].copy_from_slice(&(-1_i32).to_le_bytes());
    assert!(matches!(
        parse_value_labels(&negative_count, &metadata),
        Err(DtaError::NegativeValueLabelField {
            field: "entry count",
            ..
        })
    ));

    let mut bad_offset = original.clone();
    bad_offset[payload_start + 8..payload_start + 12].copy_from_slice(&29_i32.to_le_bytes());
    assert!(matches!(
        parse_value_labels(&bad_offset, &metadata),
        Err(DtaError::InvalidValueLabelTextOffset {
            text_offset: 29,
            text_length: 29,
            ..
        })
    ));

    let mut missing_name_nul = original.clone();
    missing_name_nul[name_start..name_start + 129].fill(b'x');
    assert!(matches!(
        parse_value_labels(&missing_name_nul, &metadata),
        Err(DtaError::MissingNulTerminator {
            context: "value-label table name",
            ..
        })
    ));

    let mut missing_text_nul = original;
    let west = find(&missing_text_nul, b"West\0");
    missing_text_nul[west + 4] = b'x';
    assert!(matches!(
        parse_value_labels(&missing_text_nul, &metadata),
        Err(DtaError::MissingNulTerminator {
            context: "value-label text",
            ..
        })
    ));
}

#[test]
fn preserves_duplicate_and_descending_value_label_keys_in_source_order() {
    let original = fixture("value_labels_v118.dta");
    let metadata = parse_metadata(&original).unwrap();
    let table_start = metadata.section_offsets.value_labels as usize + b"<value_labels>".len();
    let payload_start = table_start + b"<lbl>".len() + 4 + 129 + 3;
    let values_start = payload_start + 8 + 4 * 4;

    let mut duplicate = original.clone();
    duplicate[values_start + 4..values_start + 8].copy_from_slice(&1_i32.to_le_bytes());
    let duplicate_tables = parse_value_labels(&duplicate, &metadata).unwrap();
    assert_eq!(duplicate_tables[0].entries[0].value, 1);
    assert_eq!(duplicate_tables[0].entries[0].label, "Northeast");
    assert_eq!(duplicate_tables[0].entries[1].value, 1);
    assert_eq!(duplicate_tables[0].entries[1].label, "Midwest");
    assert_eq!(duplicate_tables[0].entry(1).unwrap().label, "Northeast");

    let mut descending = original;
    descending[values_start + 4..values_start + 8].copy_from_slice(&0_i32.to_le_bytes());
    let descending_tables = parse_value_labels(&descending, &metadata).unwrap();
    assert_eq!(descending_tables[0].entries[0].value, 1);
    assert_eq!(descending_tables[0].entries[0].label, "Northeast");
    assert_eq!(descending_tables[0].entries[1].value, 0);
    assert_eq!(descending_tables[0].entries[1].label, "Midwest");
}

#[test]
fn association_is_none_when_a_named_table_definition_is_absent() {
    let mut bytes = fixture("value_labels_v118.dta");
    let old_name = b"foreign_lbl\0";
    let table_name = bytes
        .windows(old_name.len())
        .rposition(|window| window == old_name)
        .unwrap();
    bytes[table_name..table_name + 129].fill(0);
    bytes[table_name..table_name + b"renamed_lbl".len()].copy_from_slice(b"renamed_lbl");
    let data = read_dta(&bytes).unwrap();
    assert_eq!(data.metadata.variables[0].value_label_name, "foreign_lbl");
    assert!(data.value_label_table("renamed_lbl").is_some());
    assert!(data.value_label_table_for_variable(0).is_none());
}

#[test]
fn rejects_bad_table_and_section_closes_truncation_and_trailing_bytes() {
    let original = fixture("value_labels_v118.dta");
    let metadata = parse_metadata(&original).unwrap();

    let mut bad_table_close = original.clone();
    let close = find(&bad_table_close, b"</lbl>");
    bad_table_close[close + 2] = b'X';
    assert!(matches!(
        parse_value_labels(&bad_table_close, &metadata),
        Err(DtaError::UnexpectedTag {
            expected: "</lbl>",
            ..
        })
    ));

    let mut bad_section_close = original.clone();
    let close = find(&bad_section_close, b"</value_labels>");
    bad_section_close[close + 2] = b'X';
    assert!(parse_value_labels(&bad_section_close, &metadata).is_err());

    let truncated = &original[..original.len() - 1];
    assert!(matches!(
        parse_value_labels(truncated, &metadata),
        Err(DtaError::Truncated {
            context: "</stata_dta>",
            ..
        })
    ));

    let mut trailing = original;
    trailing.push(0);
    assert!(matches!(
        parse_value_labels(&trailing, &metadata),
        Err(DtaError::MapOffsetMismatch {
            section: "file length",
            ..
        })
    ));
}
