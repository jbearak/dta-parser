//! Time the Arrow read of a Parquet file: the path datakit's polars
//! frames come from in R, without R around it.
//!
//!     cargo run --release -p dta-arrow --example read_bench -- FILE [RUNS] [THREADS] [COLUMNS]
//!
//! Reads FILE once to warm up, then RUNS times (default 20), with
//! THREADS worker threads (default 0: the Arrow thread rule). COLUMNS is
//! how many columns to read, spread over the file (default 0: all).
//! Prints the best and median wall time, the median CPU time (user plus
//! system), and the steps of the best run.

use std::time::Instant;

use dta_arrow::parquet::Input;
use dta_arrow::read::{parquet_info, parquet_read, Stamps};

#[cfg(unix)]
fn cpu() -> f64 {
    let mut u: libc::rusage = unsafe { std::mem::zeroed() };
    unsafe { libc::getrusage(libc::RUSAGE_SELF, &mut u) };
    let secs = |t: libc::timeval| t.tv_sec as f64 + t.tv_usec as f64 / 1e6;
    secs(u.ru_utime) + secs(u.ru_stime)
}

#[cfg(not(unix))]
fn cpu() -> f64 {
    0.0
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let Some(file) = args.get(1) else {
        eprintln!("usage: read_bench FILE [RUNS] [THREADS] [COLUMNS]");
        std::process::exit(2);
    };
    let number = |i: usize, default: usize| args.get(i).map_or(default, |s| s.parse().expect("a number"));
    let (runs, threads, n_columns) = (number(2, 20), number(3, 0), number(4, 0));

    let names: Vec<String> = parquet_info(Input::Path(file.clone()), &mut |info| {
        info.columns.iter().filter(|c| c.format.is_some()).map(|c| c.name.to_string()).collect()
    })
    .expect("the file's footer");
    let columns: Option<Vec<String>> = (n_columns > 0 && n_columns < names.len()).then(|| {
        (0..n_columns)
            .map(|i| names[i * (names.len() - 1) / (n_columns - 1).max(1)].clone())
            .collect()
    });

    let one = || {
        let (c0, t0) = (cpu(), Instant::now());
        let (rows, cols, steps) = parquet_read(
            Input::Path(file.clone()),
            columns.as_deref(),
            None,
            0,
            None,
            true,
            Stamps::Error,
            threads,
            &mut |out| (out.frame.batches[0].length, out.frame.fields.len(), out.meta.steps.clone().unwrap_or_default()),
        )
        .expect("the read");
        (t0.elapsed().as_secs_f64(), cpu() - c0, rows, cols, steps)
    };
    one();
    let mut results: Vec<_> = (0..runs).map(|_| one()).collect();
    results.sort_by(|a, b| a.0.total_cmp(&b.0));
    let best = &results[0];
    let median = &results[results.len() / 2];
    let mut cpus: Vec<f64> = results.iter().map(|r| r.1).collect();
    cpus.sort_by(f64::total_cmp);
    println!(
        "{} rows, {} columns: best {:.2} ms, median {:.2} ms, median CPU {:.2} ms",
        best.2,
        best.3,
        best.0 * 1e3,
        median.0 * 1e3,
        cpus[cpus.len() / 2] * 1e3
    );
    let steps: Vec<String> = best.4.iter().map(|(name, s)| format!("{name} {:.2}", s * 1e3)).collect();
    println!("steps (ms): {}", steps.join(", "));
}
