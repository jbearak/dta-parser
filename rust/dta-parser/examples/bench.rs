//! Dependency-free, report-only parser benchmarks.
//!
//! Run from the repository root with
//! `cargo run --release -p dta-parser --example bench`.

use std::fs;
use std::hint::black_box;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use dta_parser::{parse_metadata, read_dta, DtaFile, FileOptions, ReadOptions};

fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../tests/fixtures/dta")
        .join(name)
}

fn iterations() -> usize {
    std::env::var("DTA_BENCH_ITERATIONS")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(25)
        .clamp(1, 10_000)
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
