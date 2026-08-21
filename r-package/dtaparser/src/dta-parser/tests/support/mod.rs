use std::fs;
use std::path::{Path, PathBuf};

#[allow(dead_code)]
pub fn fixture(name: &str) -> Vec<u8> {
    fs::read(fixture_dir().join(name))
        .unwrap_or_else(|error| panic!("failed to read shared fixture {name}: {error}"))
}

#[allow(dead_code)]
pub fn repository_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..")
}

#[allow(dead_code)]
pub fn fixture_dir() -> PathBuf {
    repository_root().join("tests/fixtures/dta")
}

#[allow(dead_code)]
pub fn parser_data_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/data")
}
