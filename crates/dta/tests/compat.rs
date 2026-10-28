//! Read every fixture in `compat/fixtures` and compare what we read with
//! what haven, readstata13 and pandas read (`compat/expected`, written by
//! `compat/expected.R` and `compat/expected.py`).
//!
//! Where a reader is known to read a fixture wrongly, the comparison is
//! skipped for that reader and field, with the reason, in `KNOWN`.

use std::fs;
use std::path::{Path, PathBuf};

use dta::{missing, Bytes, Column, Options, Reader};
use serde_json::{json, Value};

/// (reader, fixture name prefix, field): why that reader's value is not
/// an oracle there. See docs/adr/0005-oracles.md.
const KNOWN: &[(&str, &str, &str, &str)] = &[
    ("haven", "readstat_104", "b.labels", "haven 2.5.5 reads value labels before 108 with the 108 layout"),
    ("haven", "readstat_108", "b.labels", "haven 2.5.5 misreads release 108 value label tables"),
    ("readstata13", "readstat_104", "b.labels", "readstata13 does not read value labels before 108"),
    ("readstata13", "readstat_105", "b.labels", "readstata13 does not read value labels before 108"),
    ("haven", "haven_", "text", "haven 2.5.5 drops trailing blanks from strN values"),
    ("pandas", "haven_113", "text", LATIN1),
    ("pandas", "haven_114", "text", LATIN1),
    ("pandas", "haven_115", "text", LATIN1),
    ("pandas", "haven_117", "text", LATIN1),
    ("haven", "pandas_119", "strl", "haven 2.5.5 splits 119 strL references as 118 does"),
    ("readstata13", "haven_119", "big", "haven 2.5.5 wrote 118-style strL references into a 119 file"),
];

const LATIN1: &str = "pandas decodes text before 118 as Latin-1, not Windows-1252";

fn compat_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../compat")
}

fn known(reader: &str, stem: &str, field: &str) -> bool {
    KNOWN.iter().any(|&(r, prefix, f, _)| r == reader && stem.starts_with(prefix) && f == field)
}

/// What we read, in the shape of the expected JSON.
fn dump(path: &Path) -> Value {
    let bytes = fs::read(path).unwrap();
    let mut reader = Reader::open(Bytes(bytes), Options::default()).unwrap();
    let meta = reader.metadata().clone();
    let sets = reader.value_labels().unwrap();
    let all: Vec<usize> = (0..meta.variables.len()).collect();
    let columns = reader.read(&all, 0, meta.nobs).unwrap();
    let mut values = serde_json::Map::new();
    let mut variables = Vec::new();
    for (v, column) in meta.variables.iter().zip(&columns) {
        let cells: Vec<Value> = match column {
            Column::Numbers { values, missing: codes } => values
                .iter()
                .zip(codes)
                .map(|(&x, &m)| if m == 0 { json!(x) } else { json!({"missing": missing::name(m)}) })
                .collect(),
            Column::Strings { .. } => {
                (0..column.len()).map(|i| json!(String::from_utf8_lossy(column.bytes(i)))).collect()
            }
        };
        values.insert(v.name.clone(), Value::Array(cells));
        let labels: Vec<Value> = sets
            .iter()
            .find(|s| s.name == v.value_labels)
            .map(|s| {
                s.labels
                    .iter()
                    .map(|l| {
                        let code = if l.missing == 0 { json!(l.value) } else { json!(missing::name(l.missing)) };
                        json!([code, l.text])
                    })
                    .collect()
            })
            .unwrap_or_default();
        variables.push(json!({
            "name": v.name, "type": v.storage.name(), "format": v.format,
            "label": v.label, "value_labels": v.value_labels, "labels": labels,
        }));
    }
    json!({
        "release": meta.release, "nobs": meta.nobs, "data_label": meta.label,
        "timestamp": meta.timestamp, "variables": variables, "values": values,
        "notes": reader.notes().unwrap(),
    })
}

/// Numbers compare as f64, so 1 and 1.0 agree.
fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => x.as_f64() == y.as_f64(),
        (Value::Array(x), Value::Array(y)) => x.len() == y.len() && x.iter().zip(y).all(|(p, q)| same(p, q)),
        _ => a == b,
    }
}

fn compare(stem: &str, reader: &str, ours: &Value, theirs: &Value, failures: &mut Vec<String>) {
    let mut check = |field: &str, a: &Value, b: &Value| {
        if !b.is_null() && !same(a, b) && !known(reader, stem, field) {
            failures.push(format!("{stem}: {field} differs from {reader}: ours {a}, theirs {b}"));
        }
    };
    for field in ["release", "nobs", "data_label", "timestamp"] {
        check(field, &ours[field], &theirs[field]);
    }
    let ours_vars = ours["variables"].as_array().unwrap();
    let theirs_vars = theirs["variables"].as_array().unwrap();
    check("variable count", &json!(ours_vars.len()), &json!(theirs_vars.len()));
    for (a, b) in ours_vars.iter().zip(theirs_vars) {
        let name = a["name"].as_str().unwrap();
        for field in ["name", "type", "format", "label", "value_labels", "labels"] {
            check(&format!("{name}.{field}"), &a[field], &b[field]);
        }
        let mut theirs_values = theirs["values"][name].clone();
        if reader == "readstata13" && ours["release"].as_u64() < Some(113) {
            // readstata13 leaves a pre-113 missing value as the stored
            // sentinel, the type's largest value.
            let sentinels = [127.0, 32767.0, 2147483647.0, 1.7014118346046923e38, 8.988465674311579e307];
            if let Value::Array(cells) = &mut theirs_values {
                for c in cells.iter_mut() {
                    if c.as_f64().is_some_and(|x| sentinels.contains(&x)) {
                        *c = json!({"missing": "."});
                    }
                }
            }
        }
        if reader == "readstata13" {
            // readstata13 reads an empty strL as NA.
            if let Value::Array(cells) = &mut theirs_values {
                for c in cells.iter_mut().filter(|c| c.is_null()) {
                    *c = json!("");
                }
            }
        }
        check(name, &ours["values"][name], &theirs_values);
    }
    if theirs.get("notes").is_some_and(|n| !n.is_null()) {
        check("notes", &ours["notes"], &theirs["notes"]);
    }
}

#[test]
fn reads_what_open_source_readers_read() {
    let dir = compat_dir();
    let mut failures = Vec::new();
    let mut compared = 0;
    let mut paths: Vec<PathBuf> = fs::read_dir(dir.join("fixtures"))
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "dta"))
        .collect();
    paths.sort();
    for path in paths {
        let stem = path.file_stem().unwrap().to_str().unwrap().to_string();
        let ours = dump(&path);
        for reader in ["haven", "readstata13", "pandas"] {
            let expected = dir.join("expected").join(format!("{stem}.{reader}.json"));
            let theirs: Value = serde_json::from_str(&fs::read_to_string(expected).unwrap()).unwrap();
            if theirs.get("error").is_some() {
                continue;
            }
            compare(&stem, reader, &ours, &theirs, &mut failures);
            compared += 1;
        }
    }
    assert!(compared > 0, "no fixtures compared");
    assert!(failures.is_empty(), "{} differences:\n{}", failures.len(), failures.join("\n"));
}
