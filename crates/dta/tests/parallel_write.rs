//! Parallel writes fail as serial ones do, and never hang (plan 0007):
//! the error reported is the first a variable-by-variable check meets,
//! and a panicking worker or a failing output ends the write.

use std::io::Write;
use std::sync::mpsc;
use std::time::Duration;

use dta::{write_with, Dataset, StorageType, Values, WriteOptions, WriteVariable};

const ROWS: usize = 2000;

fn serial() -> WriteOptions {
    WriteOptions { threads: 1, block_bytes: 400, slab_bytes: 64, ..WriteOptions::default() }
}

fn parallel() -> WriteOptions {
    WriteOptions { threads: 4, parallel_bytes: 0, block_bytes: 400, slab_bytes: 64, ..WriteOptions::default() }
}

fn number(name: &str, storage: StorageType, bad_row: Option<usize>) -> WriteVariable<'static> {
    WriteVariable {
        name: name.into(),
        storage,
        format: String::new(),
        label: String::new(),
        value_labels: String::new(),
        // A byte holds at most 100: 500 does not fit.
        values: Values::numbers_by_row(move |r| (if Some(r) == bad_row { 500.0 } else { (r % 50) as f64 }, 0)),
    }
}

fn text(name: &str, bad_row: Option<usize>) -> WriteVariable<'static> {
    WriteVariable {
        name: name.into(),
        storage: StorageType::Str(1),
        format: String::new(),
        label: String::new(),
        value_labels: String::new(),
        values: Values::Strings(Box::new(move |r| if Some(r) == bad_row { &[0xff][..] } else { b"ok" })),
    }
}

fn data(variables: Vec<WriteVariable<'static>>) -> Dataset<'static> {
    Dataset {
        nobs: ROWS,
        label: String::new(),
        timestamp: String::new(),
        variables,
        value_labels: Vec::new(),
        characteristics: Vec::new(),
        sort_order: Vec::new(),
    }
}

/// The error writing `make()` gives, with `options`; fails the test if
/// the write takes over 20 seconds (a hang).
fn error_of(make: fn() -> Dataset<'static>, options: WriteOptions) -> String {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let mut out = Vec::new();
        let _ = tx.send(write_with(&make(), &mut out, &options).map_err(|e| e.to_string()));
    });
    match rx.recv_timeout(Duration::from_secs(20)) {
        Ok(Err(e)) => e,
        Ok(Ok(())) => panic!("the write succeeded"),
        Err(_) => panic!("the write hung"),
    }
}

fn same_both_ways(make: fn() -> Dataset<'static>, expected: &str) {
    assert_eq!(error_of(make, serial()), expected);
    assert_eq!(error_of(make, parallel()), expected);
}

#[test]
fn a_bad_value_before_a_bad_name_is_reported() {
    same_both_ways(
        || {
            data(vec![
                number("a", StorageType::Byte, None),
                number("b", StorageType::Double, None),
                number("c", StorageType::Byte, Some(1900)),
                number("d", StorageType::Double, None),
                number("1bad", StorageType::Double, None),
            ])
        },
        "c row 1901: 500 does not fit storage type byte",
    );
}

#[test]
fn a_bad_name_before_a_bad_value_is_reported() {
    same_both_ways(
        || data(vec![number("1bad", StorageType::Double, None), number("c", StorageType::Byte, Some(5))]),
        "\"1bad\" is not a valid Stata name",
    );
}

#[test]
fn a_late_bad_value_beats_an_early_bad_string_in_a_later_column() {
    same_both_ways(
        || data(vec![number("a", StorageType::Byte, Some(1999)), text("s", Some(0))]),
        "a row 2000: 500 does not fit storage type byte",
    );
    same_both_ways(
        || data(vec![text("s", Some(1999)), number("a", StorageType::Byte, Some(0))]),
        "s row 2000 is not UTF-8 text without NULs",
    );
}

#[test]
fn a_panicking_worker_ends_the_write() {
    let options = WriteOptions { panic_on_slab: Some(3), ..parallel() };
    let e = error_of(|| data(vec![number("a", StorageType::Double, None), text("s", None)]), options);
    assert!(e.contains("test panic on slab 3"), "{e}");
}

/// Accepts `room` bytes, then fails.
struct Failing {
    room: usize,
}

impl Write for Failing {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        if self.room < buf.len() {
            return Err(std::io::Error::other("disk full"));
        }
        self.room -= buf.len();
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

#[test]
fn a_failing_output_ends_the_write_with_workers_mid_block() {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        let d = data(vec![number("a", StorageType::Double, None), number("b", StorageType::Double, None), text("s", None)]);
        let _ = tx.send(write_with(&d, Failing { room: 3000 }, &parallel()).map_err(|e| e.to_string()));
    });
    match rx.recv_timeout(Duration::from_secs(20)) {
        Ok(Err(e)) => assert!(e.contains("disk full"), "{e}"),
        Ok(Ok(())) => panic!("the write succeeded"),
        Err(_) => panic!("the write hung"),
    }
}
