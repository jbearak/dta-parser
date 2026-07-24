use std::fs;
use std::path::{Path, PathBuf};

use dta_parser::{parse_metadata, ByteOrder, DtaError, DtaType, FormatVersion};

const MODERN_FIXTURES: &[&str] = &[
    "all_types.dta",
    "all_types_v117.dta",
    "all_types_v118.dta",
    "auto_v117.dta",
    "auto_v118.dta",
    "auto_v119.dta",
    "empty.dta",
    "empty_v118.dta",
    "missing_values.dta",
    "missing_values_v118.dta",
    "strl_test.dta",
    "strl_test_v118.dta",
    "value_labels.dta",
    "value_labels_v117.dta",
    "value_labels_v118.dta",
    "wide.dta",
    "wide_v118.dta",
];

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/dta")
}

fn fixture(name: &str) -> Vec<u8> {
    fs::read(fixture_dir().join(name))
        .unwrap_or_else(|error| panic!("failed to read shared fixture {name}: {error}"))
}

fn find(bytes: &[u8], needle: &[u8]) -> usize {
    bytes
        .windows(needle.len())
        .position(|window| window == needle)
        .unwrap_or_else(|| panic!("fixture is missing {:?}", String::from_utf8_lossy(needle)))
}

#[test]
fn parses_every_checked_in_modern_fixture() {
    let mut discovered = fs::read_dir(fixture_dir())
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|extension| extension == "dta"))
        .filter_map(|path| {
            let bytes = fs::read(&path).unwrap();
            let modern = [117, 118, 119].iter().any(|release| {
                bytes.starts_with(
                    format!("<stata_dta><header><release>{release}</release>").as_bytes(),
                )
            });
            modern.then(|| path.file_name().unwrap().to_string_lossy().into_owned())
        })
        .collect::<Vec<_>>();
    discovered.sort();
    assert_eq!(discovered, MODERN_FIXTURES);

    for name in MODERN_FIXTURES {
        let metadata = parse_metadata(&fixture(name))
            .unwrap_or_else(|error| panic!("failed to parse {name}: {error}"));
        assert_eq!(metadata.variables.len(), metadata.nvar as usize, "{name}");
        assert_eq!(
            metadata.obs_length,
            metadata
                .variables
                .iter()
                .map(|variable| u64::from(variable.byte_width))
                .sum::<u64>(),
            "{name}"
        );
    }
}

#[test]
fn matches_known_shared_fixture_metadata() {
    let metadata = parse_metadata(&fixture("auto_v118.dta")).unwrap();
    assert_eq!(metadata.format_version, FormatVersion::V118);
    assert_eq!(metadata.byte_order, ByteOrder::Lsf);
    assert_eq!(metadata.nvar, 12);
    assert_eq!(metadata.nobs, 74);
    assert_eq!(metadata.dataset_label, "1978 automobile data");
    assert_eq!(metadata.variables[0].name, "make");
    assert_eq!(metadata.variables[0].dta_type, DtaType::FixedString(18));
    assert_eq!(metadata.variables[0].label, "Make and model");
    assert_eq!(metadata.variables[11].name, "foreign");
    assert_eq!(metadata.variables[11].dta_type, DtaType::Byte);
    assert_eq!(metadata.variables[11].value_label_name, "origin");

    let v117 = parse_metadata(&fixture("auto_v117.dta")).unwrap();
    assert_eq!(v117.format_version, FormatVersion::V117);
    assert_eq!(v117.variables[11].type_code, 65_530);
    assert_eq!(v117.variables[11].dta_type, DtaType::Byte);
}

fn push_field(bytes: &mut Vec<u8>, value: &[u8], width: usize) {
    assert!(value.len() <= width);
    bytes.extend_from_slice(value);
    bytes.resize(bytes.len() + width - value.len(), 0);
}

/// A deterministic metadata-only v119 fixture. Stata saves the repository's
/// nominal `auto_v119.dta` as release 118 because it does not need v119's
/// wider K/N fields.
fn synthetic_v119_metadata_fixture() -> Vec<u8> {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"<stata_dta><header><release>119</release>");
    bytes.extend_from_slice(b"<byteorder>MSF</byteorder>");
    bytes.extend_from_slice(b"<K>");
    bytes.extend_from_slice(&1_u32.to_be_bytes());
    bytes.extend_from_slice(b"</K><N>");
    bytes.extend_from_slice(&9_007_199_254_740_993_u64.to_be_bytes());
    bytes.extend_from_slice(b"</N><label>");
    let label = b"synthetic v119";
    bytes.extend_from_slice(&(label.len() as u16).to_be_bytes());
    bytes.extend_from_slice(label);
    bytes.extend_from_slice(b"</label><timestamp>");
    bytes.push(0);
    bytes.extend_from_slice(b"</timestamp></header>");

    let map_start = bytes.len();
    bytes.extend_from_slice(b"<map>");
    let map_payload = bytes.len();
    bytes.resize(bytes.len() + 14 * 8, 0);
    bytes.extend_from_slice(b"</map>");

    let mut offsets = [0_u64; 14];
    offsets[0] = 0;
    offsets[1] = map_start as u64;

    offsets[2] = bytes.len() as u64;
    bytes.extend_from_slice(b"<variable_types>");
    bytes.extend_from_slice(&65_530_u16.to_be_bytes());
    bytes.extend_from_slice(b"</variable_types>");

    offsets[3] = bytes.len() as u64;
    bytes.extend_from_slice(b"<varnames>");
    push_field(&mut bytes, b"x", 129);
    bytes.extend_from_slice(b"</varnames>");

    offsets[4] = bytes.len() as u64;
    bytes.extend_from_slice(b"<sortlist>");
    bytes.extend_from_slice(&[0; 8]);
    bytes.extend_from_slice(b"</sortlist>");

    offsets[5] = bytes.len() as u64;
    bytes.extend_from_slice(b"<formats>");
    push_field(&mut bytes, b"%8.0g", 57);
    bytes.extend_from_slice(b"</formats>");

    offsets[6] = bytes.len() as u64;
    bytes.extend_from_slice(b"<value_label_names>");
    push_field(&mut bytes, b"", 129);
    bytes.extend_from_slice(b"</value_label_names>");

    offsets[7] = bytes.len() as u64;
    bytes.extend_from_slice(b"<variable_labels>");
    push_field(&mut bytes, b"Synthetic variable", 321);
    bytes.extend_from_slice(b"</variable_labels>");

    offsets[8] = bytes.len() as u64;
    for index in 9..14 {
        offsets[index] = offsets[index - 1] + 1;
    }
    for (index, offset) in offsets.into_iter().enumerate() {
        let start = map_payload + index * 8;
        bytes[start..start + 8].copy_from_slice(&offset.to_be_bytes());
    }
    bytes
}

#[test]
fn parses_deterministic_big_endian_v119_metadata_prefix() {
    let bytes = synthetic_v119_metadata_fixture();
    let metadata = parse_metadata(&bytes).unwrap();
    assert_eq!(metadata.format_version, FormatVersion::V119);
    assert_eq!(metadata.byte_order, ByteOrder::Msf);
    assert_eq!(metadata.nvar, 1);
    assert_eq!(metadata.nobs, 9_007_199_254_740_993);
    assert_eq!(metadata.variables[0].name, "x");
    assert_eq!(metadata.variables[0].dta_type, DtaType::Byte);
    assert_eq!(metadata.section_offsets.characteristics, bytes.len() as u64);

    let json = serde_json::to_value(metadata).unwrap();
    assert_eq!(json["nobs"], "9007199254740993");
    assert_eq!(
        json["section_offsets"]["characteristics"],
        bytes.len().to_string()
    );
}

#[test]
fn accepts_a_valid_metadata_prefix_but_rejects_required_section_truncation() {
    let full = fixture("auto_v118.dta");
    let metadata = parse_metadata(&full).unwrap();
    let prefix_end = metadata.section_offsets.characteristics as usize;
    let prefix = &full[..prefix_end];
    assert_eq!(parse_metadata(prefix).unwrap(), metadata);

    for length in [0, 1, 40, prefix_end / 2, prefix_end - 1] {
        assert!(
            parse_metadata(&prefix[..length]).is_err(),
            "length {length}"
        );
    }
}

#[test]
fn rejects_malformed_tags_maps_and_type_codes() {
    let original = fixture("auto_v118.dta");
    let metadata = parse_metadata(&original).unwrap();

    let mut bad_close = original.clone();
    let close = find(&bad_close, b"</variable_labels>");
    bad_close[close + 2] = b'X';
    assert!(matches!(
        parse_metadata(&bad_close),
        Err(DtaError::UnexpectedTag {
            expected: "</variable_labels>",
            ..
        })
    ));

    let mut bad_order = original.clone();
    let map_payload = metadata.section_offsets.map as usize + b"<map>".len();
    let varnames_entry = map_payload + 3 * 8;
    bad_order[varnames_entry..varnames_entry + 8]
        .copy_from_slice(&metadata.section_offsets.variable_types.to_le_bytes());
    assert!(matches!(
        parse_metadata(&bad_order),
        Err(DtaError::SectionOrder {
            section: "varnames",
            ..
        })
    ));

    let mut bad_map_target = original.clone();
    let variable_types_entry = map_payload + 2 * 8;
    bad_map_target[variable_types_entry..variable_types_entry + 8]
        .copy_from_slice(&(metadata.section_offsets.variable_types + 1).to_le_bytes());
    assert!(matches!(
        parse_metadata(&bad_map_target),
        Err(DtaError::MapOffsetMismatch {
            section: "variable_types",
            ..
        })
    ));

    let mut unknown_type = original;
    let first_type = metadata.section_offsets.variable_types as usize + b"<variable_types>".len();
    unknown_type[first_type..first_type + 2].copy_from_slice(&0_u16.to_le_bytes());
    assert!(matches!(
        parse_metadata(&unknown_type),
        Err(DtaError::UnknownTypeCode {
            code: 0,
            version: FormatVersion::V118
        })
    ));
}

#[test]
fn replaces_invalid_utf8_like_typescript_text_decoder() {
    let mut bytes = synthetic_v119_metadata_fixture();
    let label_start = find(&bytes, b"synthetic v119");
    bytes[label_start] = 0xff;
    let metadata = parse_metadata(&bytes).unwrap();
    assert_eq!(metadata.dataset_label, "�ynthetic v119");
}
