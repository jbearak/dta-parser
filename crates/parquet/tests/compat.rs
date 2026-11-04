//! Read the fixtures other tools wrote (compat/parquet/fixtures) and
//! compare with what pyarrow reads from them (compat/parquet/expected).

use std::path::Path;

use dta_parquet::format::{LogicalType, TimeUnit};
use dta_parquet::{ColumnType, LevelsFrom, Nested, Numbers, Output, ReadOptions, Reader, Role, TextChunk};
use serde_json::Value;

fn root() -> &'static Path {
    Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../../compat/parquet"))
}

/// The column type an Arrow type (as pyarrow prints it) should read as.
fn kind_of(arrow: &str) -> ColumnType {
    let unit = |u: &str| match u {
        "ms" => TimeUnit::Millis,
        "us" => TimeUnit::Micros,
        _ => TimeUnit::Nanos,
    };
    match arrow {
        "int8" => ColumnType::Int8,
        "int16" => ColumnType::Int16,
        "int32" => ColumnType::Int32,
        "int64" => ColumnType::Int64,
        "uint8" => ColumnType::UInt8,
        "uint16" => ColumnType::UInt16,
        "uint32" => ColumnType::UInt32,
        "uint64" => ColumnType::UInt64,
        "time32[ms]" => ColumnType::Time { unit: TimeUnit::Millis, utc: false },
        "time64[us]" => ColumnType::Time { unit: TimeUnit::Micros, utc: false },
        "time64[ns]" => ColumnType::Time { unit: TimeUnit::Nanos, utc: false },
        "extension<arrow.json>" => ColumnType::Text,
        "extension<arrow.uuid>" => ColumnType::Binary,
        t if t.starts_with("fixed_size_binary[") => ColumnType::Binary,
        t if t.starts_with("decimal128(") || t.starts_with("decimal256(") => {
            let inner = &t[11..t.len() - 1];
            let (p, s) = inner.split_once(", ").unwrap();
            ColumnType::Decimal { precision: p.parse().unwrap(), scale: s.parse().unwrap() }
        }
        "float" => ColumnType::Float,
        "double" => ColumnType::Double,
        "bool" => ColumnType::Boolean,
        "string" | "large_string" => ColumnType::Text,
        "binary" | "large_binary" => ColumnType::Binary,
        "date32[day]" => ColumnType::Date,
        t if t.starts_with("dictionary<values=string") => ColumnType::Text,
        t if t.starts_with("timestamp[") => {
            let inner = &t["timestamp[".len()..t.len() - 1];
            let (u, zone) = inner.split_once(", tz=").map_or((inner, None), |(u, z)| (u, Some(z)));
            ColumnType::Timestamp { unit: unit(u), utc: zone.is_some() }
        }
        t => panic!("no expected type for {t}"),
    }
}

/// What one column reads as, made comparable with the JSON.
fn read_column<S: dta::Source>(r: &mut Reader<S>, name: &str, skip: u64, n: u64) -> Vec<Value> {
    let k = r.column_index(name).unwrap();
    let window = r.window(skip, n);
    let rows = (window.end - window.start) as usize;
    let kind = r.columns()[k].kind.clone();
    match kind {
        ColumnType::Float | ColumnType::Double => {
            let mut v = vec![0.0; rows];
            let mut codes = vec![0u8; rows];
            r.read(&[k], skip, n, &mut [Output::Float64(Numbers::new(&mut v, 0.0).with_codes(&mut codes))], |_, _| Ok(())).unwrap();
            v.iter()
                .zip(&codes)
                .map(|(&x, &c)| {
                    if c != 0 {
                        Value::Null
                    } else if x.is_nan() {
                        Value::from("NaN")
                    } else {
                        Value::from(x)
                    }
                })
                .collect()
        }
        ColumnType::UInt8 | ColumnType::UInt16 | ColumnType::UInt32 | ColumnType::UInt64 => {
            let mut v = vec![0u64; rows];
            let mut codes = vec![0u8; rows];
            r.read(&[k], skip, n, &mut [Output::UInt64(Numbers::new(&mut v, 0).with_codes(&mut codes))], |_, _| Ok(())).unwrap();
            v.iter().zip(&codes).map(|(&x, &c)| if c == 0 { Value::from(x) } else { Value::Null }).collect()
        }
        ColumnType::Text | ColumnType::Binary | ColumnType::Decimal { .. } => {
            let mut out: Vec<Value> = Vec::with_capacity(rows);
            r.read(&[k], skip, n, &mut [Output::Text], |_, chunk: &TextChunk| {
                assert_eq!(chunk.first as usize, out.len());
                for row in 0..chunk.rows {
                    out.push(match chunk.row(row) {
                        None => Value::Null,
                        Some(b) if kind != ColumnType::Binary => Value::from(std::str::from_utf8(b).unwrap()),
                        Some(b) => Value::from(b.to_vec()),
                    });
                }
                Ok(())
            })
            .unwrap();
            if r.columns()[k].levels == Some(LevelsFrom::Rows) {
                check_found_levels(r, k, skip, n, &out);
            }
            out
        }
        _ => {
            let mut v = vec![0i64; rows];
            let mut codes = vec![0u8; rows];
            r.read(&[k], skip, n, &mut [Output::Int64(Numbers::new(&mut v, 0).with_codes(&mut codes))], |_, _| Ok(())).unwrap();
            v.iter()
                .zip(&codes)
                .map(|(&x, &c)| match (c, &kind) {
                    (0, ColumnType::Boolean) => Value::from(x == 1),
                    (0, _) => Value::from(x),
                    _ => Value::Null,
                })
                .collect()
        }
    }
}

/// A dictionary of text in `ARROW:schema` reads as levels: the distinct
/// values of the rows read, in order of first appearance, and a code per
/// row that gives the row's value.
fn check_found_levels<S: dta::Source>(r: &mut Reader<S>, k: usize, skip: u64, n: u64, values: &[Value]) {
    let mut codes = vec![0i32; values.len()];
    let report = r.read(&[k], skip, n, &mut [Output::Levels { codes: &mut codes, base: 1, null: -1 }], |_, _| Ok(())).unwrap();
    let levels = report.levels[0].as_ref().expect("levels found");
    let mut first_seen: Vec<&str> = Vec::new();
    for (v, &c) in values.iter().zip(&codes) {
        match v.as_str() {
            None => assert_eq!(c, -1),
            Some(s) => {
                assert_eq!(levels[c as usize - 1], s);
                if !first_seen.contains(&s) {
                    first_seen.push(s);
                }
            }
        }
    }
    assert_eq!(levels, &first_seen);
}

fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => {
            let (x, y) = (x.as_f64().unwrap(), y.as_f64().unwrap());
            // Integers compare exactly through i64 when both are.
            match (a.as_i64(), b.as_i64()) {
                (Some(p), Some(q)) => p == q,
                _ => x == y && x.is_sign_negative() == y.is_sign_negative(),
            }
        }
        _ => a == b,
    }
}

fn fixtures() -> Vec<(String, Value)> {
    let mut out = Vec::new();
    for entry in std::fs::read_dir(root().join("expected")).unwrap() {
        let path = entry.unwrap().path();
        let stem = path.file_stem().unwrap().to_string_lossy().into_owned();
        let doc: Value = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
        out.push((stem, doc));
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    assert!(out.len() >= 10, "the fixtures are missing");
    out
}

fn check(options: ReadOptions, windows: &[(u64, u64)]) {
    for (stem, doc) in fixtures() {
        let bytes = std::fs::read(root().join("fixtures").join(format!("{stem}.parquet"))).unwrap();
        let nested: Vec<&str> = doc["nested"].as_array().map_or(Vec::new(), |a| a.iter().map(|v| v.as_str().unwrap()).collect());
        let options = if nested.is_empty() { options } else { ReadOptions { nested: Nested::Skip, ..options } };
        let mut r = Reader::open(dta::Bytes(&bytes[..]), options).unwrap();
        assert!(r.warnings().is_empty(), "{stem}: {:?}", r.warnings());
        let rows = doc["rows"].as_u64().unwrap();
        assert_eq!(r.rows(), rows, "{stem}");
        for name in &nested {
            let k = r.column_index(name).unwrap();
            assert_eq!(r.columns()[k].role, Role::Nested, "{stem}.{name}");
        }
        let columns = doc["columns"].as_array().unwrap();
        assert_eq!(r.data_columns().unwrap().len(), columns.len(), "{stem}");
        for col in columns {
            let name = col["name"].as_str().unwrap();
            let k = r.column_index(name).unwrap();
            let arrow = col["arrow_type"].as_str().unwrap();
            // pyarrow reads ENUM as binary; plan 0018 reads it as text.
            let is_enum = r.columns()[k].logical == Some(LogicalType::Enum) || r.columns()[k].converted == Some(dta_parquet::format::converted::ENUM);
            let want_kind = if is_enum && arrow == "binary" { ColumnType::Text } else { kind_of(arrow) };
            assert_eq!(r.columns()[k].kind, want_kind, "{stem}.{name}: {arrow}");
            let want = col["values"].as_array().unwrap();
            for &(skip, n) in windows {
                let mut got = read_column(&mut r, name, skip, n);
                if is_enum && arrow == "binary" {
                    for v in &mut got {
                        if let Value::String(s) = v {
                            *v = Value::from(s.as_bytes().to_vec());
                        }
                    }
                }
                let start = (skip as usize).min(want.len());
                let end = (skip.saturating_add(n) as usize).min(want.len());
                let want = &want[start..end];
                assert_eq!(got.len(), want.len(), "{stem}.{name}");
                for (i, (a, b)) in want.iter().zip(&got).enumerate() {
                    assert!(same(a, b), "{stem}.{name} row {}: pyarrow {a}, ours {b}", start + i + 1);
                }
            }
        }
    }
}

#[test]
fn every_fixture_reads_as_pyarrow_reads_it() {
    check(ReadOptions { threads: 1, ..Default::default() }, &[(0, u64::MAX)]);
}

#[test]
fn row_windows_of_every_fixture() {
    // Windows inside a page, across pages and across row groups.
    check(ReadOptions { threads: 1, ..Default::default() }, &[(0, 1), (199, 2), (250, 100), (311, 250), (599, 10)]);
}

#[test]
fn every_fixture_with_threads() {
    check(ReadOptions { threads: 4, parallel_bytes: 0, ..Default::default() }, &[(0, u64::MAX), (123, 400)]);
}

#[test]
fn the_fixtures_cover_what_they_should() {
    use dta_parquet::format::{Codec, Encoding};
    let mut codecs = Vec::new();
    let mut encodings = Vec::new();
    let mut with_index = false;
    let mut v2 = false;
    for (stem, _) in fixtures() {
        let bytes = std::fs::read(root().join("fixtures").join(format!("{stem}.parquet"))).unwrap();
        let r = Reader::open(dta::Bytes(&bytes[..]), ReadOptions::default()).unwrap();
        for g in &r.metadata().row_groups {
            for c in &g.columns {
                with_index |= c.offset_index.is_some();
                let m = c.meta.as_ref().unwrap();
                if !codecs.contains(&m.codec) {
                    codecs.push(m.codec);
                }
                for e in &m.encodings {
                    if !encodings.contains(e) {
                        encodings.push(*e);
                    }
                }
            }
        }
        v2 |= stem.contains("v2");
    }
    for c in [Codec::Snappy, Codec::Gzip, Codec::Zstd, Codec::Uncompressed, Codec::Brotli] {
        assert!(codecs.contains(&c), "no fixture uses {c:?}");
    }
    for e in [
        Encoding::Plain,
        Encoding::PlainDictionary,
        Encoding::RleDictionary,
        Encoding::Rle,
        Encoding::DeltaBinaryPacked,
        Encoding::DeltaLengthByteArray,
        Encoding::DeltaByteArray,
        Encoding::ByteStreamSplit,
    ] {
        assert!(encodings.contains(&e), "no fixture uses {e:?}");
    }
    assert!(with_index && v2);
}

#[test]
fn nested_columns_are_named_unless_skipped() {
    let bytes = std::fs::read(root().join("fixtures/pyarrow_nested.parquet")).unwrap();
    let r = Reader::open(dta::Bytes(&bytes[..]), ReadOptions::default()).unwrap();
    let e = r.data_columns().unwrap_err();
    for name in ["\"tags\"", "\"point\"", "\"props\""] {
        assert!(e.message.contains(name), "{}", e.message);
    }
    assert!(e.message.contains("skip"), "{}", e.message);
    let r = Reader::open(dta::Bytes(&bytes[..]), ReadOptions { nested: Nested::Skip, ..Default::default() }).unwrap();
    let names: Vec<&str> = r.data_columns().unwrap().iter().map(|&k| r.columns()[k].name.as_str()).collect();
    assert_eq!(names, vec!["id", "name"]);
    // Selecting a nested column is an error naming it.
    let mut r = Reader::open(dta::Bytes(&bytes[..]), ReadOptions::default()).unwrap();
    let k = r.column_index("tags").unwrap();
    let e = r.read(&[k], 0, 10, &mut [Output::Text], |_, _| Ok(())).unwrap_err();
    assert!(e.message.contains("\"tags\""), "{}", e.message);
}

/// Every column pyarrow reads as a dictionary of text (and that has no dta
/// profile) is one whose levels come from the rows read; no other is.
#[test]
fn dictionaries_of_text_are_categoricals() {
    let mut seen = 0;
    for (stem, doc) in fixtures() {
        let bytes = std::fs::read(root().join("fixtures").join(format!("{stem}.parquet"))).unwrap();
        let r = Reader::open(dta::Bytes(&bytes[..]), ReadOptions { nested: Nested::Skip, ..Default::default() }).unwrap();
        for col in doc["columns"].as_array().unwrap() {
            let name = col["name"].as_str().unwrap();
            let dictionary = col["arrow_type"].as_str().unwrap().starts_with("dictionary<values=string");
            let k = r.column_index(name).unwrap();
            assert_eq!(r.columns()[k].levels == Some(LevelsFrom::Rows), dictionary, "{stem}.{name}");
            seen += usize::from(dictionary);
        }
    }
    assert!(seen >= 5, "{seen}");
}

/// A DECIMAL column reads as doubles, each the nearest double to its
/// decimal, while every value has at most 15 significant digits; the first
/// value with more is an error naming the column and its row.
#[test]
fn decimals_as_doubles() {
    let mut checked = (0, 0);
    for (stem, doc) in fixtures() {
        let bytes = std::fs::read(root().join("fixtures").join(format!("{stem}.parquet"))).unwrap();
        let mut r = Reader::open(dta::Bytes(&bytes[..]), ReadOptions::default()).unwrap();
        for col in doc["columns"].as_array().unwrap() {
            let name = col["name"].as_str().unwrap();
            let k = r.column_index(name).unwrap();
            if !matches!(r.columns()[k].kind, ColumnType::Decimal { .. }) {
                continue;
            }
            let want = col["values"].as_array().unwrap();
            let too_long = want
                .iter()
                .position(|v| v.as_str().is_some_and(|s| dta_parquet::decimal::significant_digits(s) > dta_parquet::decimal::DOUBLE_DIGITS));
            let mut v = vec![0.0; want.len()];
            let mut codes = vec![0u8; want.len()];
            let result = r.read(&[k], 0, u64::MAX, &mut [Output::Float64(Numbers::new(&mut v, -1.0).with_codes(&mut codes))], |_, _| Ok(()));
            match too_long {
                Some(row) => {
                    let e = result.unwrap_err();
                    assert!(e.message.contains(&format!("\"{name}\"")) && e.message.contains(&format!("row {}", row + 1)), "{stem}.{name}: {}", e.message);
                    checked.1 += 1;
                }
                None => {
                    result.unwrap();
                    for (i, w) in want.iter().enumerate() {
                        match w.as_str() {
                            None => assert_eq!(codes[i], 1),
                            Some(s) => assert_eq!((v[i], codes[i]), (s.parse::<f64>().unwrap(), 0), "{stem}.{name} row {}", i + 1),
                        }
                    }
                    checked.0 += 1;
                }
            }
        }
    }
    assert!(checked.0 >= 4 && checked.1 >= 2, "{checked:?}");
}
