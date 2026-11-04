//! Time a write and a full read of a large synthetic Parquet file, and a
//! 1,000-row window read with and without an offset index, so later work
//! can measure itself against these numbers.
//!
//!     cargo run --release -p dta-parquet --example bench -- DIR [ROWS]
//!
//! The table has ROWS rows (10 million by default): four doubles, two
//! 32-bit integers, an 8-bit integer with nulls and `.a` to `.z`, a date,
//! a microsecond timestamp, text with 1,000 distinct values, and a
//! categorical. Each task runs three times; the median wall time is
//! printed with the CPU time (user + system) of that run.

#[cfg(unix)]
mod unix {
    use std::time::Instant;

    use dta_parquet::format::TimeUnit;
    use dta_parquet::{write, Numbers, Output, Profile, ReadOptions, Reader, Table, TextChunk, Values, WriteColumn, WriteOptions};

    fn cpu() -> f64 {
        let mut u: libc::rusage = unsafe { std::mem::zeroed() };
        unsafe { libc::getrusage(libc::RUSAGE_SELF, &mut u) };
        let secs = |t: libc::timeval| t.tv_sec as f64 + t.tv_usec as f64 / 1e6;
        secs(u.ru_utime) + secs(u.ru_stime)
    }

    fn peak_rss_mb() -> f64 {
        let mut u: libc::rusage = unsafe { std::mem::zeroed() };
        unsafe { libc::getrusage(libc::RUSAGE_SELF, &mut u) };
        // Bytes on macOS, KiB on Linux.
        if cfg!(target_os = "macos") {
            u.ru_maxrss as f64 / 1e6
        } else {
            u.ru_maxrss as f64 / 1e3
        }
    }

    /// The median of three runs: (wall, cpu) seconds.
    fn time(mut task: impl FnMut()) -> (f64, f64) {
        let mut runs: Vec<(f64, f64)> = (0..3)
            .map(|_| {
                let c = cpu();
                let t = Instant::now();
                task();
                (t.elapsed().as_secs_f64(), cpu() - c)
            })
            .collect();
        runs.sort_by(|a, b| a.0.total_cmp(&b.0));
        runs[1]
    }

    struct Data {
        doubles: Vec<Vec<f64>>,
        ints: Vec<Vec<i32>>,
        small: Vec<i32>,
        small_codes: Vec<u8>,
        days: Vec<i32>,
        stamps: Vec<i64>,
        words: Vec<String>,
        cats: Vec<i32>,
    }

    fn data(n: usize) -> Data {
        let mut seed = 0x2545_f491_4f6c_dd1du64;
        let mut next = move || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        Data {
            doubles: (0..4).map(|k| (0..n).map(|_| (next() % 100_000) as f64 / (k + 3) as f64).collect()).collect(),
            ints: (0..2).map(|k| (0..n).map(|_| (next() % (1000 << (k * 10))) as i32).collect()).collect(),
            small: (0..n).map(|_| (next() % 100) as i32).collect(),
            small_codes: (0..n).map(|_| match next() % 50 { 0 => 1, 1 => 2, 2 => 4, _ => 0 }).collect(),
            days: (0..n).map(|r| (r % 20_000) as i32).collect(),
            stamps: (0..n).map(|r| 1_600_000_000_000_000 + r as i64 * 1_000_003).collect(),
            words: (0..1000).map(|k| format!("word number {k}")).collect(),
            cats: (0..n).map(|_| (next() % 5) as i32).collect(),
        }
    }

    fn table(d: &Data) -> Table<'_> {
        let n = d.small.len();
        let mut columns = Vec::new();
        for (k, v) in d.doubles.iter().enumerate() {
            columns.push(WriteColumn {
                name: format!("d{k}"),
                values: Values::Double(Box::new(move |first, out: &mut [f64], codes: &mut [u8]| {
                    out.copy_from_slice(&v[first..first + out.len()]);
                    codes.fill(0);
                })),
            });
        }
        for (k, v) in d.ints.iter().enumerate() {
            columns.push(WriteColumn {
                name: format!("i{k}"),
                values: Values::Int32(Box::new(move |first, out: &mut [i32], codes: &mut [u8]| {
                    out.copy_from_slice(&v[first..first + out.len()]);
                    codes.fill(0);
                })),
            });
        }
        let (small, codes) = (&d.small, &d.small_codes);
        columns.push(WriteColumn {
            name: "small".into(),
            values: Values::Int8(Box::new(move |first, out: &mut [i32], c: &mut [u8]| {
                out.copy_from_slice(&small[first..first + out.len()]);
                c.copy_from_slice(&codes[first..first + out.len()]);
            })),
        });
        let days = &d.days;
        columns.push(WriteColumn {
            name: "day".into(),
            values: Values::Date(Box::new(move |first, out: &mut [i32], c: &mut [u8]| {
                out.copy_from_slice(&days[first..first + out.len()]);
                c.fill(0);
            })),
        });
        let stamps = &d.stamps;
        columns.push(WriteColumn {
            name: "when".into(),
            values: Values::Timestamp {
                unit: TimeUnit::Micros,
                utc: true,
                zone: Some("UTC".into()),
                fill: Box::new(move |first, out: &mut [i64], c: &mut [u8]| {
                    out.copy_from_slice(&stamps[first..first + out.len()]);
                    c.fill(0);
                }),
            },
        });
        let words = &d.words;
        columns.push(WriteColumn { name: "word".into(), values: Values::Text(Box::new(move |r| Some(words[(r * 7919) % 1000].as_bytes()))) });
        let cats = &d.cats;
        columns.push(WriteColumn {
            name: "group".into(),
            values: Values::Categorical {
                levels: ["a", "b", "c", "d", "e"].map(String::from).to_vec(),
                ordered: false,
                codes: Box::new(move |first, out: &mut [i32]| out.copy_from_slice(&cats[first..first + out.len()])),
            },
        });
        Table { rows: n, columns, profile: Profile::default() }
    }

    /// Read every data column into memory a binding would allocate.
    fn read_all(path: &str, threads: usize) -> u64 {
        let mut r = Reader::open(dta::FileSource::open(path).unwrap(), ReadOptions { threads, ..Default::default() }).unwrap();
        let cols = r.data_columns().unwrap();
        let n = r.rows() as usize;
        let mut f64s: Vec<Vec<f64>> = (0..cols.len()).map(|_| vec![0.0; n]).collect();
        let mut codes: Vec<Vec<u8>> = (0..cols.len()).map(|_| vec![0; n]).collect();
        let mut levels = vec![0i32; n];
        let mut text_rows = 0u64;
        let names: Vec<String> = cols.iter().map(|&k| r.columns()[k].name.clone()).collect();
        let mut outputs: Vec<Output> = Vec::new();
        let mut levels_slot = Some(&mut levels[..]);
        for ((name, v), c) in names.iter().zip(f64s.iter_mut()).zip(codes.iter_mut()) {
            outputs.push(match name.as_str() {
                "word" => Output::Text,
                "group" => Output::Levels { codes: levels_slot.take().unwrap(), base: 1, null: i32::MIN },
                _ => Output::Float64(Numbers::new(v, f64::NAN).with_codes(c)),
            });
        }
        r.read(&cols, 0, u64::MAX, &mut outputs, |_, chunk: &TextChunk| {
            text_rows += chunk.rows as u64;
            Ok(())
        })
        .unwrap();
        text_rows
    }

    fn read_window(path: &str, skip: u64) {
        let mut r = Reader::open(dta::FileSource::open(path).unwrap(), ReadOptions::default()).unwrap();
        let cols: Vec<usize> = r.data_columns().unwrap().into_iter().filter(|&k| r.columns()[k].name.starts_with('d')).collect();
        let mut vs: Vec<Vec<f64>> = cols.iter().map(|_| vec![0.0; 1000]).collect();
        let mut outputs: Vec<Output> = vs.iter_mut().map(|v| Output::Float64(Numbers::new(v, f64::NAN))).collect();
        r.read(&cols, skip, 1000, &mut outputs, |_, _| Ok(())).unwrap();
    }

    pub fn main() {
        let mut args = std::env::args().skip(1);
        let dir = args.next().expect("usage: bench DIR [ROWS]");
        let n: usize = args.next().map_or(10_000_000, |s| s.parse().unwrap());
        std::fs::create_dir_all(&dir).unwrap();
        let d = data(n);
        let t = table(&d);
        let path = format!("{dir}/bench.parquet");
        let no_index = format!("{dir}/bench_no_index.parquet");
        println!("{n} rows, 11 columns; default threads = {}", dta::threads::resolve(0));
        for threads in [1, 0] {
            let (w, c) = time(|| {
                let f = std::io::BufWriter::with_capacity(1 << 20, std::fs::File::create(&path).unwrap());
                write(&t, f, &WriteOptions { threads, ..Default::default() }).unwrap();
            });
            println!("write zstd, threads {:>7}: wall {w:.3} s, cpu {c:.3} s", if threads == 0 { "default" } else { "1" });
        }
        let (w, c) = time(|| {
            let f = std::io::BufWriter::with_capacity(1 << 20, std::fs::File::create(&no_index).unwrap());
            write(&t, f, &WriteOptions { offset_index: false, compression: dta_parquet::Compression::Snappy, ..Default::default() }).unwrap();
        });
        println!("write snappy, no offset index: wall {w:.3} s, cpu {c:.3} s");
        let size = std::fs::metadata(&path).unwrap().len();
        println!("file: {:.1} MB (zstd)", size as f64 / 1e6);
        for threads in [1, 0] {
            let (w, c) = time(|| {
                assert_eq!(read_all(&path, threads), n as u64);
            });
            println!("full read, threads {:>7}: wall {w:.3} s, cpu {c:.3} s", if threads == 0 { "default" } else { "1" });
        }
        for (label, p) in [("with offset index", &path), ("walking page headers", &no_index)] {
            let (w, _) = time(|| read_window(p, n as u64 / 2));
            println!("1,000-row window of 4 doubles, {label}: {:.3} ms", w * 1e3);
        }
        println!("peak RSS: {:.0} MB", peak_rss_mb());
    }
}

fn main() {
    #[cfg(unix)]
    unix::main();
}
