//! A read with a byte budget stops after the row that reaches it.

use std::fs;
use std::path::Path;

use dta::{Bytes, Column, Options, Reader};

fn open(name: &str) -> Reader<Bytes<Vec<u8>>> {
    let bytes = fs::read(Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat/fixtures").join(name)).unwrap();
    Reader::open(Bytes(bytes), Options::default()).unwrap()
}

fn rows_read(reader: &mut Reader<Bytes<Vec<u8>>>, start: u64, budget: usize) -> (u64, usize) {
    let nobs = reader.metadata().nobs;
    let all: Vec<usize> = (0..reader.metadata().variables.len()).collect();
    let mut seen = 0;
    let n = reader
        .read_chunks(&all, start, nobs - start, Some(budget), |_, chunk| {
            seen += chunk[0].len();
            Ok(())
        })
        .unwrap();
    (n, seen)
}

#[test]
fn a_budget_bounds_the_rows_read() {
    let mut r = open("pandas_118_le.dta");
    let nobs = r.metadata().nobs;
    assert_eq!(rows_read(&mut r, 0, 1 << 30), (nobs, nobs as usize));
    // Each row decodes to more than one byte, so a budget of 1 takes one row.
    assert_eq!(rows_read(&mut r, 0, 1), (1, 1));
    assert_eq!(rows_read(&mut r, 2, 1), (1, 1));
}

#[test]
fn a_strl_larger_than_the_budget_is_still_read_whole() {
    // Row 1's strL is 3000 bytes.
    let mut r = open("pandas_118_le.dta");
    let col = r.metadata().variables.iter().position(|v| v.name == "strl").unwrap();
    let mut got = Vec::new();
    let n = r
        .read_chunks(&[col], 0, 3, Some(100), |_, chunk| {
            if let Column::Strings { .. } = &chunk[0] {
                got.extend((0..chunk[0].len()).map(|i| chunk[0].bytes(i).len()));
            }
            Ok(())
        })
        .unwrap();
    assert_eq!(n, 1);
    assert_eq!(got, vec![3000]);
}

#[test]
fn the_budget_allows_for_text_growing_when_decoded() {
    // haven_113's text is str10, read as Windows-1252: a row can decode to
    // 30 bytes of UTF-8 plus its offset, so a 20-byte budget takes one row.
    let mut r = open("haven_113.dta");
    let col = r.metadata().variables.iter().position(|v| v.name == "text").unwrap();
    let n = r.read_chunks(&[col], 0, 6, Some(20), |_, _| Ok(())).unwrap();
    assert_eq!(n, 1);
}
