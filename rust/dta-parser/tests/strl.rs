use std::fs;
use std::path::{Path, PathBuf};

use dta_parser::{read_dta, read_dta_with_options, ColumnValues, DtaError, ReadOptions};

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/dta")
}

fn fixture(name: &str) -> Vec<u8> {
    fs::read(fixture_dir().join(name)).unwrap()
}

fn projected(indices: Vec<u32>) -> ReadOptions {
    ReadOptions {
        row_start: 0,
        row_count: None,
        column_indices: Some(indices),
    }
}

#[test]
fn resolves_v117_and_v118_strl_values_nulls_and_projection() {
    for name in ["all_types_v117.dta", "all_types_v118.dta"] {
        let data = read_dta(&fixture(name)).unwrap();
        match &data.columns[7].values {
            ColumnValues::StrL { values } => {
                assert_eq!(values[0], "This is a strL value for obs 1");
                assert_eq!(values[4], "This is a strL value for obs 5");
            }
            other => panic!("{name}: unexpected strL storage: {other:?}"),
        }
    }
    let data = read_dta(&fixture("strl_test_v118.dta")).unwrap();
    match &data.columns[0].values {
        ColumnValues::StrL { values } => {
            assert_eq!(values.len(), 5);
            assert_eq!(values[3], "");
        }
        other => panic!("unexpected strL storage: {other:?}"),
    }
}

#[test]
fn rejects_partial_dangling_duplicate_and_invalid_gso_records() {
    let original = fixture("strl_test_v118.dta");
    let metadata = dta_parser::parse_metadata(&original).unwrap();
    let pointer = metadata.section_offsets.data as usize + 6;
    let first_gso = metadata.section_offsets.strls as usize + 7;
    let first_len =
        u32::from_le_bytes(original[first_gso + 16..first_gso + 20].try_into().unwrap()) as usize;
    let second_gso = first_gso + 20 + first_len;

    let mut partial = original.clone();
    partial[pointer..pointer + 2].fill(0);
    assert!(matches!(
        read_dta(&partial),
        Err(DtaError::InvalidStrlPointer {
            variable: 0,
            observation: 1,
            ..
        })
    ));

    let mut dangling = original.clone();
    dangling[pointer + 2..pointer + 8].copy_from_slice(&[4, 0, 0, 0, 0, 0]);
    assert!(matches!(
        read_dta(&dangling),
        Err(DtaError::DanglingStrlPointer {
            variable: 1,
            observation: 4
        })
    ));

    let mut duplicate = original.clone();
    duplicate[second_gso + 3..second_gso + 15]
        .copy_from_slice(&original[first_gso + 3..first_gso + 15]);
    assert!(matches!(
        read_dta(&duplicate),
        Err(DtaError::DuplicateGsoKey {
            variable: 1,
            observation: 1,
            ..
        })
    ));

    let mut invalid_type = original.clone();
    invalid_type[first_gso + 15] = 42;
    assert!(matches!(
        read_dta(&invalid_type),
        Err(DtaError::InvalidGsoType { gso_type: 42, .. })
    ));

    let mut missing_nul = original;
    let last_content = first_gso + 20 + first_len - 1;
    missing_nul[last_content] = b'x';
    assert!(matches!(
        read_dta(&missing_nul),
        Err(DtaError::InvalidGsoText { .. })
    ));
}

#[test]
fn non_strl_projection_does_not_scan_gso_records() {
    let mut bytes = fixture("strl_test_v118.dta");
    let metadata = dta_parser::parse_metadata(&bytes).unwrap();
    bytes[metadata.section_offsets.strls as usize + 7] = b'X';
    let data = read_dta_with_options(&bytes, &projected(vec![1, 2])).unwrap();
    assert_eq!(data.columns.len(), 2);
    assert!(matches!(
        read_dta_with_options(&bytes, &projected(vec![0])),
        Err(DtaError::InvalidGsoMarker { .. })
    ));
}
