use std::collections::BTreeSet;
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};

use dta_parser::{read_dta, read_dta_with_options, DtaFile, ReadOptions};
use serde::Deserialize;
use sha2::{Digest, Sha256};

#[derive(Deserialize)]
struct Manifest {
    schema_version: u32,
    identity: Identity,
    fixture_cases: Vec<FixtureCase>,
    deterministic_cases: Vec<DeterministicCase>,
}

#[derive(Deserialize)]
struct Identity {
    canonical_oracle: String,
    canonical_sha256: String,
    fixture_count: usize,
    case_count: usize,
    fixture_oracle_gate: Gate,
    float_contract: String,
}

#[derive(Deserialize)]
struct FixtureCase {
    name: String,
    sha256: String,
}

#[derive(Deserialize)]
struct DeterministicCase {
    name: String,
    kind: String,
    coverage: String,
    gate: Gate,
}

#[derive(Deserialize)]
struct Gate {
    binary: String,
    test: String,
}

fn repository_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn manifest() -> Manifest {
    serde_json::from_slice(&fs::read(repository_root().join("conformance/cases.json")).unwrap())
        .unwrap()
}

fn projected_options(nvar: u32, nobs: u64) -> ReadOptions {
    let mut columns = Vec::new();
    if nvar > 0 {
        columns.push(nvar - 1);
        columns.push(0);
        columns.push(nvar - 1);
    }
    ReadOptions {
        row_start: nobs.min(1),
        row_count: Some(nobs.saturating_sub(1).min(2)),
        column_indices: Some(columns),
    }
}

#[test]
fn checked_manifest_has_an_honest_immutable_29_case_inventory() {
    let root = repository_root();
    let manifest = manifest();
    assert_eq!(manifest.schema_version, 1);
    assert_eq!(
        manifest.fixture_cases.len(),
        manifest.identity.fixture_count
    );
    assert_eq!(
        manifest.fixture_cases.len() + manifest.deterministic_cases.len(),
        manifest.identity.case_count
    );
    assert_eq!(manifest.identity.fixture_count, 22);
    assert_eq!(manifest.identity.case_count, 29);
    assert!(manifest.identity.float_contract.contains("1e-7"));
    assert_eq!(manifest.identity.fixture_oracle_gate.binary, "observations");
    assert_eq!(
        manifest.identity.fixture_oracle_gate.test,
        "every_checked_fixture_matches_the_typescript_haven_oracle"
    );

    let canonical = fs::read(root.join(&manifest.identity.canonical_oracle)).unwrap();
    assert_eq!(
        format!("{:x}", Sha256::digest(&canonical)),
        manifest.identity.canonical_sha256
    );

    let fixtures = root.join("tests/fixtures/dta");
    let disk = fs::read_dir(&fixtures)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|extension| extension == "dta"))
        .map(|path| path.file_name().unwrap().to_string_lossy().into_owned())
        .collect::<BTreeSet<_>>();
    let checked = manifest
        .fixture_cases
        .iter()
        .map(|case| case.name.clone())
        .collect::<BTreeSet<_>>();
    assert_eq!(disk, checked);

    let deterministic = manifest
        .deterministic_cases
        .iter()
        .map(|case| case.name.as_str())
        .collect::<BTreeSet<_>>();
    assert_eq!(
        deterministic,
        BTreeSet::from([
            "synthetic-v113-layout",
            "synthetic-v114-layout",
            "synthetic-v119-big-endian",
            "projected-row-window",
            "invalid-signature",
            "truncated-observations",
            "dangling-strl-pointer",
        ])
    );
    let gates = manifest
        .deterministic_cases
        .iter()
        .map(|case| format!("{}::{}", case.gate.binary, case.gate.test))
        .collect::<BTreeSet<_>>();
    assert_eq!(gates.len(), manifest.deterministic_cases.len());
    assert!(!gates.contains(&format!(
        "{}::{}",
        manifest.identity.fixture_oracle_gate.binary, manifest.identity.fixture_oracle_gate.test
    )));
    assert!(manifest.deterministic_cases.iter().all(|case| {
        !case.kind.is_empty()
            && !case.coverage.is_empty()
            && !case.gate.binary.is_empty()
            && !case.gate.test.is_empty()
    }));
}

#[test]
fn every_fixture_has_exact_hash_and_slice_file_projection_parity() {
    let root = repository_root();
    for case in manifest().fixture_cases {
        let bytes = fs::read(root.join("tests/fixtures/dta").join(&case.name)).unwrap();
        assert_eq!(
            format!("{:x}", Sha256::digest(&bytes)),
            case.sha256,
            "{}",
            case.name
        );

        let slice = read_dta(&bytes).unwrap_or_else(|error| panic!("{}: {error}", case.name));
        let mut file = DtaFile::from_reader(Cursor::new(bytes.clone()))
            .unwrap_or_else(|error| panic!("{}: {error}", case.name));
        assert_eq!(file.read().unwrap(), slice, "{} full read", case.name);

        let options = projected_options(slice.metadata.nvar, slice.metadata.nobs);
        let expected = read_dta_with_options(&bytes, &options).unwrap();
        let actual = file.read_with_options(&options).unwrap();
        assert_eq!(actual, expected, "{} projected row window", case.name);
    }
}

#[test]
fn invalid_signatures_do_not_disagree_between_slice_and_file() {
    let invalid = vec![0_u8; 32];
    let file_error = match DtaFile::from_reader(Cursor::new(invalid.clone())) {
        Ok(_) => panic!("invalid signature unexpectedly opened"),
        Err(error) => error,
    };
    assert_eq!(read_dta(&invalid).unwrap_err(), file_error);
}

#[test]
fn truncated_closing_tag_does_not_disagree_between_slice_and_file() {
    let root = repository_root();
    let mut truncated = fs::read(root.join("tests/fixtures/dta/all_types_v118.dta")).unwrap();
    truncated.truncate(truncated.len() - 1);
    let slice_error = read_dta(&truncated).unwrap_err();
    let file_error = match DtaFile::from_reader(Cursor::new(truncated)) {
        Ok(mut file) => file.read().unwrap_err(),
        Err(error) => error,
    };
    assert_eq!(file_error, slice_error);
}
