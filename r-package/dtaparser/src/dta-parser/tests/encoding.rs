mod support;

use std::io::Cursor;
use support::fixture;

use dta_parser::{read_dta_with_encoding, ColumnValues, DtaFile, TextEncoding};

fn replace_first(bytes: &mut [u8], needle: &[u8], replacement: u8) {
    let offset = bytes
        .windows(needle.len())
        .position(|window| window == needle)
        .unwrap_or_else(|| {
            panic!(
                "fixture does not contain {:?}",
                String::from_utf8_lossy(needle)
            )
        });
    bytes[offset] = replacement;
}

#[test]
fn auto_matches_stata_18_utf8_decoding_for_pre_unicode_release_117() {
    let mut bytes = fixture("auto_v117.dta");
    replace_first(&mut bytes, b"1978 automobile data", 0x80);
    replace_first(&mut bytes, b"Make and model", 0x80);
    replace_first(&mut bytes, b"AMC Concord", 0x80);
    replace_first(&mut bytes, b"Domestic", 0x80);

    let auto = dta_parser::read_dta(&bytes).unwrap();
    assert!(auto.metadata.dataset_label.starts_with('\u{fffd}'));
    assert!(auto.metadata.variables[0].label.starts_with('\u{fffd}'));
    let ColumnValues::FixedString { values } = &auto.columns[0].values else {
        panic!("make must be a fixed string");
    };
    assert!(values[0].starts_with('\u{fffd}'));
    assert!(auto.value_label_table("origin").unwrap().entries[0]
        .label
        .starts_with('\u{fffd}'));

    let cp1252 = read_dta_with_encoding(&bytes, TextEncoding::Windows1252).unwrap();
    assert!(cp1252.metadata.dataset_label.starts_with('\u{20ac}'));
}

#[test]
fn override_reaches_modern_metadata_fixed_strings_and_value_labels() {
    let mut bytes = fixture("auto_v118.dta");
    replace_first(&mut bytes, b"1978 automobile data", 0x80);
    replace_first(&mut bytes, b"Make and model", 0x80);
    replace_first(&mut bytes, b"AMC Concord", 0x80);
    replace_first(&mut bytes, b"Domestic", 0x80);

    let cp1252 = read_dta_with_encoding(&bytes, TextEncoding::Windows1252).unwrap();
    assert!(cp1252.metadata.dataset_label.starts_with('\u{20ac}'));
    assert!(cp1252.metadata.variables[0].label.starts_with('\u{20ac}'));
    let ColumnValues::FixedString { values } = &cp1252.columns[0].values else {
        panic!("make must be a fixed string");
    };
    assert!(values[0].starts_with('\u{20ac}'));
    assert!(cp1252.value_label_table("origin").unwrap().entries[0]
        .label
        .starts_with('\u{20ac}'));

    let latin1 = read_dta_with_encoding(&bytes, TextEncoding::Iso8859_1).unwrap();
    assert!(latin1.metadata.dataset_label.starts_with('\u{80}'));
    assert!(latin1.metadata.variables[0].label.starts_with('\u{80}'));
    let ColumnValues::FixedString { values } = &latin1.columns[0].values else {
        panic!("make must be a fixed string");
    };
    assert!(values[0].starts_with('\u{80}'));
    assert!(latin1.value_label_table("origin").unwrap().entries[0]
        .label
        .starts_with('\u{80}'));

    let mut file =
        DtaFile::from_reader_with_encoding(Cursor::new(bytes), TextEncoding::Iso8859_1).unwrap();
    assert_eq!(file.read().unwrap(), latin1);
}

#[test]
fn override_reaches_modern_strl_payloads() {
    let mut bytes = fixture("strl_test_v118.dta");
    replace_first(&mut bytes, b"This is observation 1", 0x80);

    let cp1252 = read_dta_with_encoding(&bytes, TextEncoding::Windows1252).unwrap();
    let ColumnValues::StrL { values } = &cp1252.columns[0].values else {
        panic!("long_text must be strL");
    };
    assert!(values[0].starts_with('\u{20ac}'));

    let latin1 = read_dta_with_encoding(&bytes, TextEncoding::Iso8859_1).unwrap();
    let ColumnValues::StrL { values } = &latin1.columns[0].values else {
        panic!("long_text must be strL");
    };
    assert!(values[0].starts_with('\u{80}'));
}
