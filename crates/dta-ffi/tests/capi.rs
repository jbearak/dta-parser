//! The native C ABI, driven as a C caller would: every fixture read
//! through it gives what the core reads, in full and in windows; writes
//! read back; errors arrive in the caller's buffer.

#![cfg(not(target_arch = "wasm32"))]

use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::fs;
use std::path::{Path, PathBuf};
use std::ptr::{null, null_mut};

use dta::{Bytes, Column, Options, Reader};
use dta_ffi::native::*;
use serde_json::{json, Value};

fn fixtures() -> Vec<PathBuf> {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat/fixtures");
    let mut paths: Vec<_> = fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()).collect();
    paths.retain(|p| p.extension().is_some_and(|e| e == "dta"));
    paths.sort();
    paths
}

fn c(s: &str) -> CString {
    CString::new(s).unwrap()
}

struct ErrBuf([u8; 512]);

impl ErrBuf {
    fn new() -> Self {
        ErrBuf([0xff; 512])
    }
    fn ptr(&mut self) -> *mut c_char {
        self.0.as_mut_ptr() as *mut c_char
    }
    fn text(&self) -> String {
        CStr::from_bytes_until_nul(&self.0).unwrap().to_str().unwrap().to_string()
    }
}

fn open(path: &Path) -> *mut DtaFile {
    let mut err = ErrBuf::new();
    let f = unsafe { dta_open(c(path.to_str().unwrap()).as_ptr(), null(), err.ptr(), 512) };
    assert!(!f.is_null(), "{}", err.text());
    assert_eq!(err.text(), "");
    f
}

fn meta(f: *mut DtaFile) -> Value {
    let mut err = ErrBuf::new();
    let mut len = 0;
    let s = unsafe { dta_meta_json(f, &mut len, err.ptr(), 512) };
    assert!(!s.is_null(), "{}", err.text());
    let text = unsafe { CStr::from_ptr(s) }.to_str().unwrap().to_string();
    assert_eq!(text.len(), len);
    unsafe { dta_string_free(s) };
    serde_json::from_str(&text).unwrap()
}

/// One row: a number and its code, or string bytes and the binary flag.
type Row = (f64, u8, Vec<u8>, bool);

/// What the callback collected: per column, numbers as (f64, code) or
/// strings as (bytes, binary); and the chunks' first rows.
#[derive(Default)]
struct Collected {
    columns: Vec<Vec<Row>>,
    firsts: Vec<u64>,
    stop_after: Option<usize>,
}

unsafe extern "C" fn collect(user: *mut c_void, first: u64, n: u64, cols: *const DtaColumn) -> c_int {
    let out = &mut *(user as *mut Collected);
    out.firsts.push(first);
    let n = n as usize;
    for (k, col) in std::slice::from_raw_parts(cols, out.columns.len()).iter().enumerate() {
        for i in 0..n {
            let row = if col.storage == STR || col.storage == STRL {
                let o = std::slice::from_raw_parts(col.offsets, n + 1);
                let bytes = std::slice::from_raw_parts(col.bytes.add(o[i] as usize), (o[i + 1] - o[i]) as usize);
                let binary = !col.binary.is_null() && *col.binary.add(i) != 0;
                (0.0, 0, bytes.to_vec(), binary)
            } else {
                let x = match (col.storage, col.value_type) {
                    (BYTE, I8) => *(col.values as *const i8).add(i) as f64,
                    (INT, I16) => *(col.values as *const i16).add(i) as f64,
                    (LONG, I32) => *(col.values as *const i32).add(i) as f64,
                    (FLOAT, F32) => *(col.values as *const f32).add(i) as f64,
                    (DOUBLE, F64) => *(col.values as *const f64).add(i),
                    other => panic!("unexpected storage and value type {other:?}"),
                };
                let code = if col.codes.is_null() { 0 } else { *col.codes.add(i) };
                (x, code, Vec::new(), false)
            };
            out.columns[k].push(row);
        }
    }
    match out.stop_after {
        Some(k) if out.firsts.len() >= k => 1,
        _ => 0,
    }
}

fn read(f: *mut DtaFile, cols: &[u32], start: u64, count: u64) -> (i64, Collected, String) {
    let mut got = Collected { columns: vec![Vec::new(); cols.len()], ..Default::default() };
    let mut err = ErrBuf::new();
    let n = unsafe {
        dta_read(f, cols.as_ptr(), cols.len(), start, count, Some(collect), &mut got as *mut _ as *mut c_void, err.ptr(), 512)
    };
    (n, got, err.text())
}

/// The core's read, in the collector's shape.
fn core_read(path: &Path, cols: &[usize], start: u64, count: u64) -> Vec<Vec<Row>> {
    let mut r = Reader::open(Bytes(fs::read(path).unwrap()), Options::default()).unwrap();
    let storage: Vec<_> = r.metadata().variables.iter().map(|v| v.storage).collect();
    r.read(cols, start, count)
        .unwrap()
        .into_iter()
        .zip(cols)
        .map(|(col, &c)| match &col {
            Column::Numbers { values, missing } => values
                .iter()
                .zip(missing)
                .map(|(&x, &m)| {
                    // Integers come through in their type, so a missing value reads 0.
                    let x = if m != 0 && !matches!(storage[c], dta::StorageType::Float | dta::StorageType::Double) { 0.0 } else { x };
                    (x, m, Vec::new(), false)
                })
                .collect(),
            Column::Strings { binary, .. } => {
                (0..col.len()).map(|i| (0.0, 0, col.bytes(i).to_vec(), binary.get(i).copied().unwrap_or(false))).collect()
            }
        })
        .collect()
}

/// Debug strings compare NaN equal to NaN.
fn same(a: &[Vec<Row>], b: &[Vec<Row>]) -> bool {
    format!("{a:?}") == format!("{b:?}")
}

#[test]
fn version() {
    assert_eq!(dta_abi_version(), 1);
}

#[test]
fn every_fixture_reads_as_the_core_reads_it() {
    for path in fixtures() {
        let f = open(&path);
        let m = meta(f);
        let nobs = m["nobs"].as_u64().unwrap();
        let nvar = m["variables"].as_array().unwrap().len();
        assert!(m["valueLabels"].is_array() && m["characteristics"].is_array() && m["notes"].is_array());
        // Every column, then the columns reversed over a window.
        let all: Vec<u32> = (0..nvar as u32).collect();
        let (n, got, err) = read(f, &all, 0, nobs);
        assert_eq!(n, nobs as i64, "{path:?}: {err}");
        let want = core_read(&path, &(0..nvar).collect::<Vec<_>>(), 0, nobs);
        assert!(same(&got.columns, &want), "{path:?}");
        if nobs >= 3 {
            let rev: Vec<u32> = all.iter().rev().copied().collect();
            let (n, got, _) = read(f, &rev, 1, nobs - 2);
            assert_eq!(n, (nobs - 2) as i64);
            let want = core_read(&path, &rev.iter().map(|&c| c as usize).collect::<Vec<_>>(), 1, nobs - 2);
            assert!(same(&got.columns, &want), "{path:?} window");
        }
        unsafe { dta_close(f) };
    }
}

#[test]
fn metadata_json_lists_labels_and_notes() {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat/fixtures");
    let f = open(&dir.join("haven_118.dta"));
    let m = meta(f);
    unsafe { dta_close(f) };
    assert_eq!(m["release"], 118);
    assert_eq!(m["label"], "haven fixture");
    let answer = m["variables"].as_array().unwrap().iter().find(|v| v["name"] == "answer").unwrap();
    assert_eq!(answer["type"], "double");
    let set = answer["valueLabels"].as_str().unwrap();
    let labels = &m["valueLabels"].as_array().unwrap().iter().find(|s| s["name"] == set).unwrap()["labels"];
    assert!(labels.as_array().unwrap().contains(&json!([".d", "Don't know"])), "{labels}");
}

#[test]
fn a_nonzero_callback_return_cancels() {
    let path = &fixtures()[0];
    let f = open(path);
    let mut got = Collected { columns: vec![Vec::new()], stop_after: Some(1), ..Default::default() };
    let mut err = ErrBuf::new();
    let cols = [0u32];
    let n = unsafe { dta_read(f, cols.as_ptr(), 1, 0, 1, Some(collect), &mut got as *mut _ as *mut c_void, err.ptr(), 512) };
    unsafe { dta_close(f) };
    assert_eq!(n, -2);
    assert_eq!(got.firsts, [0]);
}

#[test]
fn big_reads_come_in_chunks() {
    let dir = std::env::temp_dir().join(format!("dta-capi-chunks-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join("big.dta");
    let n = 3_000_000u64;
    let values: Vec<f64> = (0..n).map(|i| i as f64).collect();
    let cols = [DtaColumn {
        storage: DOUBLE,
        value_type: F64,
        values: values.as_ptr() as *const c_void,
        codes: null(),
        bytes: null(),
        offsets: null(),
        binary: null(),
    }];
    let mut err = ErrBuf::new();
    let meta = c(r#"{"variables":[{"name":"x"}]}"#);
    let rc = unsafe { dta_write(c(path.to_str().unwrap()).as_ptr(), n, cols.as_ptr(), 1, meta.as_ptr(), err.ptr(), 512) };
    assert_eq!(rc, 0, "{}", err.text());
    let f = open(&path);
    let (got_n, got, _) = read(f, &[0], 0, n);
    unsafe { dta_close(f) };
    fs::remove_dir_all(&dir).unwrap();
    assert_eq!(got_n, n as i64);
    assert!(got.firsts.len() > 1);
    assert!(got.firsts.windows(2).all(|w| w[0] < w[1]));
    assert!(got.columns[0].iter().enumerate().all(|(i, r)| r.0 == i as f64 && r.1 == 0));
}

#[test]
fn errors_land_in_the_callers_buffer() {
    let mut err = ErrBuf::new();
    let f = unsafe { dta_open(c("/no/such/file.dta").as_ptr(), null(), err.ptr(), 512) };
    assert!(f.is_null());
    assert!(err.text().contains("/no/such/file.dta"), "{}", err.text());

    let path = &fixtures()[0];
    let f = unsafe { dta_open(c(path.to_str().unwrap()).as_ptr(), c("ebcdic").as_ptr(), err.ptr(), 512) };
    assert!(f.is_null());
    assert!(err.text().contains("ebcdic"));

    // A NULL buffer is fine, and a short one is cut at a character.
    assert!(unsafe { dta_open(c("/no/such/file.dta").as_ptr(), null(), null_mut(), 0) }.is_null());
    let mut short = [0xffu8; 4];
    let f = unsafe { dta_open(c("/é/x.dta").as_ptr(), null(), short.as_mut_ptr() as *mut c_char, 4) };
    assert!(f.is_null());
    assert_eq!(CStr::from_bytes_until_nul(&short).unwrap().to_bytes(), "/é".as_bytes());

    let f = open(path);
    let nobs = meta(f)["nobs"].as_u64().unwrap();
    let (n, _, e) = read(f, &[0], nobs, 1);
    assert_eq!(n, -1);
    assert!(e.contains("past the"), "{e}");
    let (n, _, e) = read(f, &[9999], 0, 1);
    assert_eq!(n, -1);
    assert!(e.contains("no variable 9999"), "{e}");
    let (n, got, _) = read(f, &[], 0, nobs);
    assert_eq!((n, got.firsts.len()), (nobs as i64, 0));
    unsafe { dta_close(f) };
    unsafe { dta_close(null_mut()) };
}

fn numbers(storage: u32, value_type: u32, values: *const c_void, codes: *const u8) -> DtaColumn {
    DtaColumn { storage, value_type, values, codes, bytes: null(), offsets: null(), binary: null() }
}

fn strings(storage: u32, bytes: &[u8], offsets: &[u64], binary: *const u8) -> DtaColumn {
    DtaColumn {
        storage,
        value_type: 0,
        values: null(),
        codes: null(),
        bytes: bytes.as_ptr(),
        offsets: offsets.as_ptr(),
        binary,
    }
}

#[test]
fn writes_read_back() {
    let dir = std::env::temp_dir().join(format!("dta-capi-write-{}", std::process::id()));
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join("é out.dta");

    let ints: Vec<i64> = vec![1, -5, 0, 100];
    let codes: Vec<u8> = vec![0, 0, 2, 1];
    let doubles: Vec<f64> = vec![1.5, f64::NAN, -2.0, 1e300];
    let flags: Vec<u8> = vec![1, 0, 1, 0];
    let text = b"abcdeffoo";
    let text_offsets = [0u64, 3, 3, 6, 9];
    let blob = b"\0\x01\xffhi";
    let blob_offsets = [0u64, 3, 5, 5, 5];
    let cols = [
        numbers(BYTE, I64, ints.as_ptr() as *const c_void, codes.as_ptr()),
        numbers(DOUBLE, F64, doubles.as_ptr() as *const c_void, null()),
        strings(STR, text, &text_offsets, null()),
        strings(STRL, blob, &blob_offsets, flags.as_ptr()),
    ];
    let doc = json!({
        "label": "written through the C ABI",
        "timestamp": "28 Oct 2026 14:38",
        "variables": [
            {"name": "small", "format": "%8.0g", "label": "Small", "valueLabels": "yn"},
            {"name": "x", "format": "", "label": "", "valueLabels": ""},
            {"name": "s", "label": "Text"},
            {"name": "b"},
        ],
        "valueLabels": [{"name": "yn", "labels": [[1, "Yes"], [0, "No"], [".a", "Refused"]]}],
        "characteristics": [{"variable": "x", "name": "source", "value": "made up"}],
        "notes": ["first", "second"],
        "sortedBy": [0],
    });
    let mut err = ErrBuf::new();
    let meta_c = c(&doc.to_string());
    let rc = unsafe { dta_write(c(path.to_str().unwrap()).as_ptr(), 4, cols.as_ptr(), 4, meta_c.as_ptr(), err.ptr(), 512) };
    assert_eq!(rc, 0, "{}", err.text());

    let f = open(&path);
    let m = meta(f);
    assert_eq!(m["label"], "written through the C ABI");
    assert_eq!(m["notes"], json!(["first", "second"]));
    assert_eq!(m["characteristics"], json!([{"variable": "x", "name": "source", "value": "made up"}]));
    assert_eq!(m["sortedBy"], json!([0]));
    let types: Vec<&str> = m["variables"].as_array().unwrap().iter().map(|v| v["type"].as_str().unwrap()).collect();
    assert_eq!(types, ["byte", "double", "str3", "strL"]);
    assert_eq!(m["variables"][0]["label"], "Small");
    assert_eq!(m["valueLabels"][0]["labels"], json!([[0, "No"], [1, "Yes"], [".a", "Refused"]]));
    let (n, got, e) = read(f, &[0, 1, 2, 3], 0, 4);
    unsafe { dta_close(f) };
    assert_eq!(n, 4, "{e}");
    let small: Vec<(f64, u8)> = got.columns[0].iter().map(|r| (r.0, r.1)).collect();
    assert_eq!(small, [(1.0, 0), (-5.0, 0), (0.0, 2), (0.0, 1)]);
    let x: Vec<u8> = got.columns[1].iter().map(|r| r.1).collect();
    assert_eq!(x, [0, 1, 0, 0]);
    assert_eq!(got.columns[1][3].0, 1e300);
    let s: Vec<&[u8]> = got.columns[2].iter().map(|r| r.2.as_slice()).collect();
    assert_eq!(s, [&b"abc"[..], b"", b"def", b"foo"]);
    let b: Vec<(&[u8], bool)> = got.columns[3].iter().map(|r| (r.2.as_slice(), r.3)).collect();
    assert_eq!(b, [(&b"\0\x01\xff"[..], true), (b"hi", false), (b"", true), (b"", false)]);

    // A value that does not fit is an error naming the column, and the
    // file already there is left alone.
    let before = fs::read(&path).unwrap();
    let wide: Vec<i32> = vec![1, 2, 3, 1000];
    let cols = [numbers(BYTE, I32, wide.as_ptr() as *const c_void, null())];
    let meta_c = c(r#"{"variables":[{"name":"small"}]}"#);
    let rc = unsafe { dta_write(c(path.to_str().unwrap()).as_ptr(), 4, cols.as_ptr(), 1, meta_c.as_ptr(), err.ptr(), 512) };
    assert_eq!(rc, -1);
    assert!(err.text().contains("small row 4"), "{}", err.text());
    assert_eq!(fs::read(&path).unwrap(), before);
    assert_eq!(fs::read_dir(&dir).unwrap().count(), 1, "a temporary file was left behind");

    // Malformed input.
    let cols = [numbers(LONG, I32, wide.as_ptr() as *const c_void, null())];
    for (meta, want) in [
        (r#"{"variables":[]}"#, "describes 0 variables"),
        (r#"{"variables":[{"name":"1x"}]}"#, "not a valid Stata name"),
        (r#"{"variables":[{"name":"x"}], "valueLabels":[{"name":"l","labels":[[".", "dot"]]}]}"#, "labels `.`"),
        ("{", "bad metadata JSON"),
    ] {
        let meta_c = c(meta);
        let rc = unsafe { dta_write(c(path.to_str().unwrap()).as_ptr(), 4, cols.as_ptr(), 1, meta_c.as_ptr(), err.ptr(), 512) };
        assert_eq!(rc, -1, "{meta}");
        assert!(err.text().contains(want), "{meta}: {}", err.text());
    }
    let bad_offsets = [0u64, 3, 2, 6, 9];
    let cols = [strings(STR, text, &bad_offsets, null())];
    let meta_c = c(r#"{"variables":[{"name":"s"}]}"#);
    let rc = unsafe { dta_write(c(path.to_str().unwrap()).as_ptr(), 4, cols.as_ptr(), 1, meta_c.as_ptr(), err.ptr(), 512) };
    assert_eq!(rc, -1);
    assert!(err.text().contains("offsets"), "{}", err.text());
    let cols = [strings(STR, text, &text_offsets, flags.as_ptr())];
    let rc = unsafe { dta_write(c(path.to_str().unwrap()).as_ptr(), 4, cols.as_ptr(), 1, meta_c.as_ptr(), err.ptr(), 512) };
    assert_eq!(rc, -1);
    assert!(err.text().contains("only a strL"), "{}", err.text());
    fs::remove_dir_all(&dir).unwrap();
}
