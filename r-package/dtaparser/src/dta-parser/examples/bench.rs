//! Dependency-free, report-only parser benchmarks.
//!
//! Run from the repository root with
//! `cargo run --release -p dta-parser --example bench`.

use std::fs;
use std::hint::black_box;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use dta_parser::{parse_metadata, read_dta, DtaFile, FileOptions, ReadOptions};

const DEFAULT_ITERATIONS: usize = 25;
const MAX_SAFE_INTEGER: u64 = 9_007_199_254_740_991;

fn repository_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..")
}

fn fixture(name: &str) -> PathBuf {
    repository_root().join("tests/fixtures/dta").join(name)
}

fn parse_iterations(value: Option<&str>) -> usize {
    let Some(value) = value else {
        return DEFAULT_ITERATIONS;
    };
    let canonical_decimal = value == "0"
        || (!value.is_empty()
            && value.as_bytes()[0] != b'0'
            && value.bytes().all(|byte| byte.is_ascii_digit()));
    if !canonical_decimal {
        return DEFAULT_ITERATIONS;
    }
    let Ok(parsed) = value.parse::<u64>() else {
        return DEFAULT_ITERATIONS;
    };
    if parsed > MAX_SAFE_INTEGER {
        return DEFAULT_ITERATIONS;
    }
    parsed.clamp(1, 10_000) as usize
}

fn iterations() -> usize {
    let value = std::env::var("DTA_BENCH_ITERATIONS").ok();
    parse_iterations(value.as_deref())
}

fn measure(mut operation: impl FnMut()) -> Duration {
    let start = Instant::now();
    for _ in 0..iterations() {
        operation();
    }
    start.elapsed()
}

fn report(case: &str, phase: &str, input_bytes: usize, elapsed: Duration) {
    let per_iteration = elapsed.as_secs_f64() * 1_000.0 / iterations() as f64;
    println!(
        "{case}\t{phase}\t{input_bytes}\t{}\t{per_iteration:.6}",
        iterations()
    );
}

fn main() {
    println!("case\tphase\tinput_bytes\titerations\tmean_ms");
    for (case, name) in [
        ("modern-all-types", "all_types_v118.dta"),
        ("wide", "wide_v118.dta"),
        ("strl", "strl_test_v118.dta"),
        ("legacy", "all_types_v115.dta"),
    ] {
        let path = fixture(name);
        let bytes = fs::read(&path).unwrap();
        let input_bytes = bytes.len();
        report(
            case,
            "file-io",
            input_bytes,
            measure(|| {
                black_box(fs::read(&path).unwrap());
            }),
        );
        report(
            case,
            "metadata",
            input_bytes,
            measure(|| {
                black_box(parse_metadata(black_box(&bytes)).unwrap());
            }),
        );
        report(
            case,
            "slice-full-decode",
            input_bytes,
            measure(|| {
                black_box(read_dta(black_box(&bytes)).unwrap());
            }),
        );

        let metadata = parse_metadata(&bytes).unwrap();
        let projection = if metadata.nvar == 0 {
            Vec::new()
        } else {
            vec![0, metadata.nvar - 1]
        };
        let options = ReadOptions {
            row_start: 1,
            row_count: Some(16),
            column_indices: Some(projection),
        };
        report(
            case,
            "slice-projected-window",
            input_bytes,
            measure(|| {
                black_box(dta_parser::read_dta_with_options(&bytes, &options).unwrap());
            }),
        );
        report(
            case,
            "bounded-file-projected-window",
            input_bytes,
            measure(|| {
                let mut file = DtaFile::from_reader_with_options(
                    fs::File::open(&path).unwrap(),
                    FileOptions {
                        max_buffer_bytes: 1024,
                    },
                )
                .unwrap();
                black_box(file.read_with_options(&options).unwrap());
            }),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::parse_iterations;

    #[test]
    fn parses_only_canonical_safe_unsigned_decimal_iterations() {
        for (value, expected) in [
            (None, 25),
            (Some("0"), 1),
            (Some("1"), 1),
            (Some("10000"), 10_000),
            (Some("10001"), 10_000),
            (Some("9007199254740991"), 10_000),
        ] {
            assert_eq!(parse_iterations(value), expected, "value: {value:?}");
        }

        for value in [
            "",
            " ",
            "01",
            "1e3",
            "1.0",
            "0x10",
            " 1",
            "1 ",
            "+1",
            "-1",
            "9007199254740992",
            "18446744073709551616",
        ] {
            assert_eq!(parse_iterations(Some(value)), 25, "value: {value:?}");
        }
    }
}
