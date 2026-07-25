//! Deterministic, bounded property smoke tests.
//!
//! This is intentionally stable-Rust and dependency-free rather than a
//! nightly/libFuzzer target. It runs in ordinary offline CI and exercises the
//! same parser entrypoints with reproducible fixture-seeded mutations.
//! Cooperative cancellation is exercised by dedicated bounded file-reader
//! tests; byte mutation cannot meaningfully generate interrupt timing.

use std::fs;
use std::io::Cursor;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};

use dta_parser::{
    parse_metadata, read_dta, read_dta_with_options, DtaData, DtaError, DtaFile, FileOptions,
    ReadOptions,
};

const MAX_INPUT_BYTES: usize = 2 * 1024 * 1024;
const DEFAULT_MUTATIONS_PER_FIXTURE: usize = 8;

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/dta")
}

fn next(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}

fn mutations_per_fixture() -> usize {
    std::env::var("DTA_FUZZ_CASES")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(DEFAULT_MUTATIONS_PER_FIXTURE)
        .min(64)
}

#[derive(Debug, PartialEq)]
enum NormalizedError {
    Exact(String),
    StructuralRejection,
}

#[derive(Debug, PartialEq)]
enum NormalizedOutcome {
    Success(Box<DtaData>),
    Rejected(NormalizedError),
}

fn normalize(result: Result<DtaData, DtaError>) -> NormalizedOutcome {
    match result {
        Ok(data) => NormalizedOutcome::Success(Box::new(data)),
        Err(error) => {
            let exact = matches!(
                error,
                DtaError::InvalidSignature
                    | DtaError::UnsupportedRelease(_)
                    | DtaError::InvalidByteOrder(_)
                    | DtaError::InvalidRelease(_)
                    | DtaError::InvalidFileType(_)
                    | DtaError::NegativeObservationCount(_)
                    | DtaError::NegativeExpansionLength { .. }
                    | DtaError::MissingExpansionTerminator
                    | DtaError::InvalidExpansionTerminator { .. }
                    | DtaError::UnknownTypeCode { .. }
                    | DtaError::InvalidColumnIndex { .. }
                    | DtaError::InvalidStrlPointer { .. }
                    | DtaError::InvalidGsoMarker { .. }
                    | DtaError::InvalidGsoKey { .. }
                    | DtaError::DuplicateGsoKey { .. }
                    | DtaError::DanglingStrlPointer { .. }
                    | DtaError::InvalidGsoType { .. }
                    | DtaError::InvalidGsoText { .. }
                    | DtaError::NegativeValueLabelField { .. }
                    | DtaError::InvalidValueLabelLength { .. }
                    | DtaError::InvalidValueLabelTextOffset { .. }
                    | DtaError::UnsortedValueLabelValues { .. }
                    | DtaError::MissingNulTerminator { .. }
                    | DtaError::InvalidBufferSize
                    | DtaError::BufferLimitExceeded { .. }
                    | DtaError::Cancelled
            );
            if exact {
                NormalizedOutcome::Rejected(NormalizedError::Exact(format!("{error:?}")))
            } else {
                NormalizedOutcome::Rejected(NormalizedError::StructuralRejection)
            }
        }
    }
}

fn exercise(bytes: &[u8], seed_name: &str) {
    assert!(
        bytes.len() <= MAX_INPUT_BYTES,
        "oversized seed: {seed_name}"
    );
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        let _ = parse_metadata(bytes);
        let full = read_dta(bytes);
        let options = ReadOptions {
            row_start: 1,
            row_count: Some(2),
            column_indices: Some(vec![0]),
        };
        let projected = read_dta_with_options(bytes, &options);
        let file_full =
            DtaFile::from_reader(Cursor::new(bytes.to_vec())).and_then(|mut file| file.read());
        assert_eq!(
            normalize(file_full),
            normalize(full),
            "{seed_name}: full slice/file outcome mismatch"
        );

        let file_projected = DtaFile::from_reader(Cursor::new(bytes.to_vec()))
            .and_then(|mut file| file.read_with_options(&options));
        assert_eq!(
            normalize(file_projected),
            normalize(projected),
            "{seed_name}: projected slice/file outcome mismatch"
        );
    }));
    assert!(outcome.is_ok(), "parser panicked for {seed_name}");
}

fn find(bytes: &[u8], needle: &[u8]) -> usize {
    bytes
        .windows(needle.len())
        .position(|window| window == needle)
        .unwrap_or_else(|| panic!("missing marker {:?}", String::from_utf8_lossy(needle)))
}

fn assert_rejected_with_bounded_file_scratch(bytes: Vec<u8>, case: &str) {
    assert!(
        bytes.len() <= MAX_INPUT_BYTES,
        "oversized crafted case: {case}"
    );
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        assert!(
            read_dta(&bytes).is_err(),
            "{case}: slice unexpectedly succeeded"
        );
        if let Ok(mut file) = DtaFile::from_reader_with_options(
            Cursor::new(bytes),
            FileOptions {
                max_buffer_bytes: 1024,
            },
        ) {
            assert!(file.read().is_err(), "{case}: file unexpectedly succeeded");
            assert!(
                file.max_scratch_bytes_used() <= 1024,
                "{case}: scratch bound"
            );
        }
    }));
    assert!(outcome.is_ok(), "crafted parser case panicked: {case}");
}

#[test]
fn deterministic_fixture_seeded_mutations_never_panic_or_diverge_when_valid() {
    let mut fixtures = fs::read_dir(fixture_dir())
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|extension| extension == "dta"))
        .collect::<Vec<_>>();
    fixtures.sort();
    assert_eq!(fixtures.len(), 22);

    for (fixture_index, path) in fixtures.iter().enumerate() {
        let original = fs::read(path).unwrap();
        let name = path.file_name().unwrap().to_string_lossy();
        exercise(&original, &name);

        for mutation in 0..mutations_per_fixture() {
            let mut bytes = original.clone();
            let mut state = 0xd7a5_eed5_u64 ^ ((fixture_index as u64) << 32) ^ mutation as u64;
            let edit_count = 1 + (next(&mut state) as usize % 4);
            for _ in 0..edit_count {
                if bytes.is_empty() {
                    break;
                }
                let offset = next(&mut state) as usize % bytes.len();
                bytes[offset] ^= (next(&mut state) as u8) | 1;
            }
            if mutation % 3 == 0 && !bytes.is_empty() {
                let keep = next(&mut state) as usize % bytes.len();
                bytes.truncate(keep);
            }
            exercise(&bytes, &format!("{name} mutation {mutation}"));
        }
    }
}

#[test]
fn hostile_declared_lengths_reject_before_materializing_unbounded_results() {
    let modern = fs::read(fixture_dir().join("value_labels_v118.dta")).unwrap();

    let mut nvar = modern.clone();
    let nvar_at = find(&nvar, b"<K>") + 3;
    nvar[nvar_at..nvar_at + 2].copy_from_slice(&u16::MAX.to_le_bytes());
    exercise(&nvar, "crafted nvar=u16::MAX");
    assert_rejected_with_bounded_file_scratch(nvar, "crafted nvar=u16::MAX");

    let mut nobs = modern.clone();
    let nobs_at = find(&nobs, b"</K><N>") + b"</K><N>".len();
    nobs[nobs_at..nobs_at + 8].copy_from_slice(&u64::MAX.to_le_bytes());
    exercise(&nobs, "crafted nobs=u64::MAX");
    assert_rejected_with_bounded_file_scratch(nobs, "crafted nobs=u64::MAX");

    let metadata = parse_metadata(&modern).unwrap();
    let mut section = modern.clone();
    let data_map_at = metadata.section_offsets.map as usize + b"<map>".len() + 9 * 8;
    section[data_map_at..data_map_at + 8].copy_from_slice(&u64::MAX.to_le_bytes());
    exercise(&section, "crafted data section offset=u64::MAX");
    assert_rejected_with_bounded_file_scratch(section, "crafted data section offset=u64::MAX");

    let mut label_length = modern;
    let table =
        metadata.section_offsets.value_labels as usize + b"<value_labels>".len() + b"<lbl>".len();
    let payload = table + 4 + 129 + 3;
    label_length[payload + 4..payload + 8].copy_from_slice(&i32::MAX.to_le_bytes());
    exercise(&label_length, "crafted value-label text length=i32::MAX");
    assert_rejected_with_bounded_file_scratch(
        label_length,
        "crafted value-label text length=i32::MAX",
    );

    let mut gso = fs::read(fixture_dir().join("strl_test_v118.dta")).unwrap();
    let gso_metadata = parse_metadata(&gso).unwrap();
    let gso_length = gso_metadata.section_offsets.strls as usize + b"<strls>".len() + 16;
    gso[gso_length..gso_length + 4].copy_from_slice(&u32::MAX.to_le_bytes());
    exercise(&gso, "crafted GSO length=u32::MAX");
    assert_rejected_with_bounded_file_scratch(gso, "crafted GSO length=u32::MAX");

    let mut legacy = fs::read(fixture_dir().join("auto_v115.dta")).unwrap();
    legacy[6..10].copy_from_slice(&i32::MAX.to_le_bytes());
    exercise(&legacy, "crafted legacy nobs=i32::MAX");
    assert_rejected_with_bounded_file_scratch(legacy, "crafted legacy nobs=i32::MAX");
}
