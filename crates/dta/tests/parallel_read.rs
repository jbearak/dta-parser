//! Parallel reads give what serial ones give, in the same order, fail
//! as serial ones do, and never hang (plan 0007).

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::time::Duration;

use dta::{
    write, Bytes, Column, Dataset, Error, FileSource, Options, Reader, SharedSource, Source, StorageType, Values,
    WriteVariable,
};

fn fixtures() -> Vec<PathBuf> {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat/fixtures");
    let mut out: Vec<PathBuf> =
        fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()).filter(|p| p.extension().is_some_and(|x| x == "dta")).collect();
    out.sort();
    out
}

/// Small chunks, no size threshold, four threads: tiny files read in
/// parallel.
fn parallel() -> Options {
    Options { threads: 4, chunk_bytes: 64, parallel_bytes: 0, ..Options::default() }
}

fn serial() -> Options {
    Options { threads: 1, chunk_bytes: 64, ..Options::default() }
}

fn read_all<S: Source>(source: S, options: Options) -> Vec<Column> {
    let mut r = Reader::open(source, options).unwrap();
    let all: Vec<usize> = (0..r.metadata().variables.len()).collect();
    let nobs = r.metadata().nobs;
    r.read(&all, 0, nobs).unwrap()
}

/// Columns equal, NaN equal to NaN.
fn same(a: &[Column], b: &[Column]) -> bool {
    a.len() == b.len()
        && a.iter().zip(b).all(|(x, y)| match (x, y) {
            (Column::Numbers { values: v1, missing: m1 }, Column::Numbers { values: v2, missing: m2 }) => {
                m1 == m2 && v1.iter().zip(v2).all(|(p, q)| p.to_bits() == q.to_bits() || (p.is_nan() && q.is_nan()))
            }
            _ => x == y,
        })
}

#[test]
fn every_fixture_reads_the_same_in_parallel() {
    for path in fixtures() {
        let one = read_all(FileSource::open(&path).unwrap(), serial());
        let four = read_all(FileSource::open(&path).unwrap(), parallel());
        assert!(same(&one, &four), "{}", path.display());
        let bytes = read_all(Bytes(fs::read(&path).unwrap()), parallel());
        assert!(same(&one, &bytes), "{} from memory", path.display());
    }
}

/// A file of `rows` rows: a double and a short string.
fn file(rows: usize) -> Vec<u8> {
    let words = ["a", "bé", "c d"];
    let data = Dataset {
        nobs: rows,
        label: String::new(),
        timestamp: String::new(),
        variables: vec![
            WriteVariable {
                name: "x".into(),
                storage: StorageType::Double,
                format: String::new(),
                label: String::new(),
                value_labels: String::new(),
                values: Values::numbers_by_row(|r| (r as f64, (r % 7 == 0) as u8)),
            },
            WriteVariable {
                name: "s".into(),
                storage: StorageType::Str(1),
                format: String::new(),
                label: String::new(),
                value_labels: String::new(),
                values: Values::Strings(Box::new(move |r| words[r % 3].as_bytes())),
            },
        ],
        value_labels: Vec::new(),
        characteristics: Vec::new(),
        sort_order: Vec::new(),
    };
    let mut out = Vec::new();
    write(&data, &mut out).unwrap();
    out
}

/// Runs `f` on another thread; fails the test if it takes over 20 s.
fn within_time<T: Send + 'static>(f: impl FnOnce() -> T + Send + 'static) -> T {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let _ = tx.send(f());
    });
    rx.recv_timeout(Duration::from_secs(20)).expect("the read hung")
}

#[test]
fn chunks_arrive_in_row_order_and_each_takes_columns() {
    let bytes = file(5000);
    let (firsts, taken_rows) = within_time(move || {
        let mut r = Reader::open(Bytes(bytes), Options { delay_chunk: Some((0, 50)), ..parallel() }).unwrap();
        let mut firsts = Vec::new();
        let mut taken_rows = 0;
        // Take the doubles in the worker; leave the strings.
        let each = |k: usize, _: usize, _: &Column| Ok(k == 0);
        r.read_chunks_with(&[0, 1], 0, 5000, None, &each, |first, chunk, taken, upto| {
            assert_eq!((taken, upto), (&[true, false][..], 2));
            firsts.push(first);
            taken_rows += chunk[1].len();
            Ok(())
        }, || Ok(()))
        .unwrap();
        (firsts, taken_rows)
    });
    assert!(firsts.windows(2).all(|w| w[0] < w[1]) && firsts[0] == 0, "{firsts:?}");
    assert_eq!(taken_rows, 5000);
}

/// A source whose shared reads of the rows near `fail_at` fail.
struct Failing {
    bytes: Vec<u8>,
    fail_at: u64,
}

impl SharedSource for Failing {
    fn read_at_shared(&self, offset: u64, buf: &mut [u8]) -> dta::Result<()> {
        if offset + buf.len() as u64 > self.fail_at && offset >= self.fail_at.saturating_sub(4096) {
            return Err(Error::at(offset, "test read failure"));
        }
        let start = offset as usize;
        buf.copy_from_slice(&self.bytes[start..start + buf.len()]);
        Ok(())
    }
}

impl Source for Failing {
    fn len(&self) -> u64 {
        self.bytes.len() as u64
    }

    // Opening reads the header and the sections after the data through
    // here; only the workers' reads of rows fail.
    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> dta::Result<()> {
        let start = offset as usize;
        buf.copy_from_slice(&self.bytes[start..start + buf.len()]);
        Ok(())
    }

    fn shared(&self) -> Option<&dyn SharedSource> {
        Some(self)
    }
}

#[test]
fn an_earlier_chunk_s_error_wins_over_a_later_one_that_finished_first() {
    let bytes = file(5000);
    let (message, seen) = within_time(move || {
        // 64-byte chunks hold two rows here, so chunk 1 starts at row 2
        // and chunk 3 at row 6, both inside the window. Chunk 1 is slow,
        // so chunk 3 fails first.
        let mut r = Reader::open(Bytes(bytes), Options { delay_chunk: Some((1, 200)), ..parallel() }).unwrap();
        let each = |_: usize, first: usize, _: &Column| match first {
            2 => Err(Error::new("chunk 1")),
            6 => Err(Error::new("chunk 3")),
            _ => Ok(true),
        };
        let mut seen = Vec::new();
        let e = r
            .read_chunks_with(&[0, 1], 0, 5000, None, &each, |first, _, _, _| {
                seen.push(first);
                Ok(())
            }, || Ok(()))
            .unwrap_err()
            .to_string();
        (e, seen)
    });
    assert_eq!(message, "chunk 1");
    // rest ran for chunk 0 and for chunk 1's columns before the failure.
    assert_eq!(seen, [0, 2]);
}

#[test]
fn a_failed_read_of_rows_is_returned_after_the_rows_before_it() {
    let bytes = file(5000);
    let fail_at = (bytes.len() - 2000) as u64;
    let (message, rows) = within_time(move || {
        let mut r = Reader::open(Failing { bytes, fail_at }, parallel()).unwrap();
        let mut rows = 0;
        let e = r
            .read_chunks(&[0, 1], 0, 5000, None, |_, chunk| {
                rows += chunk[0].len();
                Ok(())
            })
            .unwrap_err()
            .to_string();
        (e, rows)
    });
    assert!(message.starts_with("test read failure"), "{message}");
    assert!(rows > 0 && rows < 5000, "{rows}");
}

#[test]
fn a_failed_first_chunk_calls_no_callback() {
    let bytes = file(5000);
    // Fail the shared reads of the first rows: the first chunk's read.
    let data = bytes.windows(6).position(|w| w == b"<data>").unwrap() + 6;
    let fail_at = data as u64 + 1;
    let (message, calls) = within_time(move || {
        let mut r = Reader::open(Failing { bytes, fail_at }, parallel()).unwrap();
        let mut calls = 0;
        let e = r
            .read_chunks(&[0, 1], 0, 5000, None, |_, _| {
                calls += 1;
                Ok(())
            })
            .unwrap_err()
            .to_string();
        (e, calls)
    });
    assert!(message.starts_with("test read failure"), "{message}");
    assert_eq!(calls, 0);
}

#[test]
fn within_a_chunk_rest_s_earlier_column_wins_over_each() {
    let bytes = file(5000);
    let run = move |rest_fails_at: usize| {
        let bytes = bytes.clone();
        within_time(move || {
            let mut r = Reader::open(Bytes(bytes), parallel()).unwrap();
            // each fails at column 2 of the chunk at row 0; rest handles
            // columns 0 and 1 and fails at `rest_fails_at`.
            let each = |k: usize, first: usize, _: &Column| {
                if first == 0 && k == 2 {
                    Err(Error::new("each at column 2"))
                } else {
                    Ok(false)
                }
            };
            r.read_chunks_with(
                &[0, 1, 0, 1],
                0,
                5000,
                None,
                &each,
                |_, _, taken, upto| {
                    for k in (0..upto).filter(|&k| !taken[k]) {
                        if k == rest_fails_at {
                            return Err(Error::new(format!("rest at column {k}")));
                        }
                    }
                    Ok(())
                },
                || Ok(()),
            )
            .unwrap_err()
            .to_string()
        })
    };
    assert_eq!(run(1), "rest at column 1");
    assert_eq!(run(3), "each at column 2");
}

#[test]
fn a_panicking_worker_ends_the_read() {
    let bytes = file(5000);
    let message = within_time(move || {
        let mut r = Reader::open(Bytes(bytes), Options { panic_on_chunk: Some(5), ..parallel() }).unwrap();
        r.read_chunks(&[0, 1], 0, 5000, None, |_, _| Ok(())).unwrap_err().to_string()
    });
    assert!(message.contains("test panic on chunk 5"), "{message}");
}

#[test]
fn a_panicking_callback_with_a_full_window_does_not_hang() {
    let bytes = file(5000);
    let panicked = within_time(move || {
        std::panic::catch_unwind(move || {
            let mut r = Reader::open(Bytes(bytes), parallel()).unwrap();
            let _ = r.read_chunks(&[0, 1], 0, 5000, None, |first, _| {
                if first > 0 {
                    // Let the workers fill the window first.
                    std::thread::sleep(Duration::from_millis(50));
                    panic!("callback panic");
                }
                Ok(())
            });
        })
        .is_err()
    });
    assert!(panicked);
}

#[test]
fn a_rest_error_with_a_full_window_returns() {
    let bytes = file(5000);
    let message = within_time(move || {
        let mut r = Reader::open(Bytes(bytes), parallel()).unwrap();
        r.read_chunks(&[0, 1], 0, 5000, None, |first, _| {
            std::thread::sleep(Duration::from_millis(20));
            if first > 0 {
                Err(Error::new("stop here"))
            } else {
                Ok(())
            }
        })
        .unwrap_err()
        .to_string()
    });
    assert_eq!(message, "stop here");
}

#[test]
fn poll_stops_the_read() {
    let bytes = file(5000);
    let polled = std::sync::Arc::new(AtomicBool::new(false));
    let seen = polled.clone();
    let message = within_time(move || {
        let mut r = Reader::open(Bytes(bytes), parallel()).unwrap();
        r.read_chunks_with(&[0, 1], 0, 5000, None, &|_, _, _| Ok(false), |_, _, _, _| Ok(()), || {
            seen.store(true, Ordering::Relaxed);
            Err(Error::new("interrupted"))
        })
        .unwrap_err()
        .to_string()
    });
    assert!(polled.load(Ordering::Relaxed));
    assert_eq!(message, "interrupted");
}

#[cfg(unix)]
#[test]
fn shared_file_reads_match_serial_ones() {
    let path = fixtures().into_iter().find(|p| p.ends_with("haven_118.dta")).unwrap();
    let bytes = fs::read(&path).unwrap();
    let mut serial = FileSource::open(&path).unwrap();
    let shared = FileSource::open(&path).unwrap();
    let len = bytes.len() as u64;
    for (offset, n) in [(0, 1), (0, bytes.len()), (17, 100), (len - 3, 3)] {
        let (mut a, mut b) = (vec![0; n], vec![0; n]);
        serial.read_at(offset, &mut a).unwrap();
        shared.shared().unwrap().read_at_shared(offset, &mut b).unwrap();
        assert_eq!(a, b);
        assert_eq!(&a[..], &bytes[offset as usize..offset as usize + n]);
    }
    // A shared read leaves the serial position alone.
    let mut next = vec![0; 10];
    serial.read_at(len - 10, &mut next).unwrap();
    assert_eq!(&next[..], &bytes[bytes.len() - 10..]);
    let past = |s: &FileSource| s.shared().unwrap().read_at_shared(len - 2, &mut [0; 3]).unwrap_err().to_string();
    assert_eq!(past(&shared), serial.read_at(len - 2, &mut [0; 3]).unwrap_err().to_string());
}
