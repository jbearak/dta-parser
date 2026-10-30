//! Time one task with 1, 2, 4 and 8 threads (plan 0007): wall time, user
//! and system CPU time of the task alone (getrusage before and after),
//! the median of five runs.
//!
//!     cargo run --release -p dta --example threads -- FILE.dta [read|columns|write] ...
//!     cargo run --release -p dta --example threads -- --synthetic DIR
//!
//! `--synthetic` writes a 1.5 GB file of 200 doubles and two strings into
//! DIR, then times every task on it (CI runs it on x86 Linux).

use std::time::Instant;

use dta::{write_with, Column, FileSource, Options, Reader, StorageType, Values, WriteOptions, WriteVariable};

fn cpu() -> (f64, f64) {
    let mut u: libc::rusage = unsafe { std::mem::zeroed() };
    unsafe { libc::getrusage(libc::RUSAGE_SELF, &mut u) };
    let secs = |t: libc::timeval| t.tv_sec as f64 + t.tv_usec as f64 / 1e6;
    (secs(u.ru_utime), secs(u.ru_stime))
}

/// (wall, user, system) seconds of `task`.
fn measure(mut task: impl FnMut()) -> (f64, f64, f64) {
    let (u0, s0) = cpu();
    let t = Instant::now();
    task();
    let wall = t.elapsed().as_secs_f64();
    let (u1, s1) = cpu();
    (wall, u1 - u0, s1 - s0)
}

fn median(mut runs: Vec<(f64, f64, f64)>) -> (f64, f64, f64) {
    runs.sort_by(|a, b| a.0.total_cmp(&b.0));
    runs[runs.len() / 2]
}

fn read(path: &str, threads: usize, columns: Option<usize>) {
    let mut r = Reader::open(FileSource::open(path).unwrap(), Options::default()).unwrap();
    let _ = threads; // reads gain threads in the next stage
    let meta = r.metadata().clone();
    let k = columns.unwrap_or(meta.variables.len()).min(meta.variables.len());
    let cols: Vec<usize> = (0..k).collect();
    let mut cells = 0;
    r.read_chunks(&cols, 0, meta.nobs, None, |_, chunk| {
        cells += chunk.iter().map(Column::len).sum::<usize>();
        Ok(())
    })
    .unwrap();
    assert_eq!(cells as u64, meta.nobs * k as u64);
}

fn write(columns: &[Column], meta: &dta::Metadata, out: &str, threads: usize) {
    let variables = meta
        .variables
        .iter()
        .zip(columns)
        .map(|(v, c)| WriteVariable {
            name: v.name.clone(),
            storage: v.storage,
            format: String::new(),
            label: String::new(),
            value_labels: String::new(),
            values: match c {
                Column::Numbers { values, missing } => Values::Numbers(Box::new(move |first, v, m| {
                    v.copy_from_slice(&values[first..first + v.len()]);
                    m.copy_from_slice(&missing[first..first + m.len()]);
                })),
                c @ Column::Strings { .. } => Values::Strings(Box::new(move |i| c.bytes(i))),
            },
        })
        .collect();
    let data = dta::Dataset {
        nobs: meta.nobs as usize,
        label: String::new(),
        timestamp: String::new(),
        variables,
        value_labels: vec![],
        characteristics: vec![],
        sort_order: vec![],
    };
    let file = std::fs::File::create(out).unwrap();
    write_with(&data, file, &WriteOptions { threads, ..WriteOptions::default() }).unwrap();
}

fn run(path: &str, task: &str) {
    let out = format!("{path}.threads-out.dta");
    let loaded = (task == "write").then(|| {
        let mut r = Reader::open(FileSource::open(path).unwrap(), Options::default()).unwrap();
        let meta = r.metadata().clone();
        let all: Vec<usize> = (0..meta.variables.len()).collect();
        (r.read(&all, 0, meta.nobs).unwrap(), meta)
    });
    println!("{path} {task}");
    println!("threads  wall s  user s  sys s  cpu/1-thread  speedup");
    let mut base = None;
    for threads in [1, 2, 4, 8] {
        let runs = (0..5)
            .map(|_| {
                measure(|| match (task, &loaded) {
                    ("write", Some((columns, meta))) => write(columns, meta, &out, threads),
                    ("columns", _) => read(path, threads, Some(5)),
                    _ => read(path, threads, None),
                })
            })
            .collect();
        let (wall, user, sys) = median(runs);
        let (w1, c1) = *base.get_or_insert((wall, user + sys));
        println!("{threads:>7}  {wall:>6.3}  {user:>6.3}  {sys:>5.3}  {:>12.2}  {:>7.2}", (user + sys) / c1, w1 / wall);
    }
    let _ = std::fs::remove_file(out);
}

fn synthetic(dir: &str) -> String {
    let path = format!("{dir}/threads-synthetic.dta");
    let (rows, k) = (900_000, 200);
    let words: Vec<String> = (0..1000).map(|i| format!("word {i}")).collect();
    let mut variables: Vec<WriteVariable> = (0..k)
        .map(|j| WriteVariable {
            name: format!("x{j}"),
            storage: StorageType::Double,
            format: String::new(),
            label: String::new(),
            value_labels: String::new(),
            values: Values::numbers_by_row(move |r| (((r * 31 + j * 7) % 1000) as f64 / 7.0, (r % 97 == 0) as u8)),
        })
        .collect();
    for j in 0..2 {
        let words = &words;
        variables.push(WriteVariable {
            name: format!("s{j}"),
            storage: StorageType::Str(1),
            format: String::new(),
            label: String::new(),
            value_labels: String::new(),
            values: Values::Strings(Box::new(move |r| words[(r * (j + 3)) % words.len()].as_bytes())),
        });
    }
    let data = dta::Dataset {
        nobs: rows,
        label: String::new(),
        timestamp: String::new(),
        variables,
        value_labels: vec![],
        characteristics: vec![],
        sort_order: vec![],
    };
    write_with(&data, std::fs::File::create(&path).unwrap(), &WriteOptions::default()).unwrap();
    path
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    println!("available parallelism: {:?}", std::thread::available_parallelism());
    if args.first().map(String::as_str) == Some("--synthetic") {
        let path = synthetic(&args[1]);
        for task in ["read", "columns", "write"] {
            run(&path, task);
        }
        let _ = std::fs::remove_file(path);
        return;
    }
    let path = &args[0];
    for task in &args[1..] {
        run(path, task);
    }
}
