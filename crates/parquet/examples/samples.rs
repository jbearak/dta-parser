//! Write Parquet files with this crate's writer, from data made here, for
//! other tools to read back (compat/parquet/readback.py and readback.R),
//! with `expected.json` saying what each holds.
//!
//!     cargo run -p dta-parquet --example samples -- DIR

#[path = "../tests/support/mod.rs"]
mod support;

use dta::{ValueLabel, ValueLabelSet};
use dta_parquet::format::TimeUnit;
use dta_parquet::{write, ColumnProfile, Compression, Profile, WriteOptions};
use serde_json::{json, Map, Value};
use support::{every_type, table, Col, Data};

fn profile() -> Profile {
    Profile {
        label: Some("Every type".into()),
        notes: vec!["Written by the samples example.".into()],
        columns: vec![ColumnProfile {
            name: "i8".into(),
            label: Some("Small numbers".into()),
            value_labels: Some("small".into()),
            ..Default::default()
        }],
        value_labels: vec![ValueLabelSet {
            name: "small".into(),
            labels: vec![
                ValueLabel { value: -100.0, missing: 0, text: "lowest".into() },
                ValueLabel { value: f64::NAN, missing: 2, text: "refused".into() },
            ],
        }],
        ..Default::default()
    }
}

fn number(v: f64) -> Value {
    if v.is_nan() {
        json!("NaN")
    } else {
        json!(v)
    }
}

/// What a column holds, for the readback scripts.
fn describe(c: &Col) -> Value {
    let n = c.rows();
    let missing = |r: usize| c.codes.get(r).is_some_and(|&k| k != 0);
    let ints = |v: Vec<i64>| -> Vec<Value> { (0..n).map(|r| if missing(r) { Value::Null } else { json!(v[r]) }).collect() };
    let mut o = Map::new();
    let (kind, values): (&str, Vec<Value>) = match &c.data {
        Data::I8(v) => ("int8", ints(v.iter().map(|&x| i64::from(x)).collect())),
        Data::I16(v) => ("int16", ints(v.iter().map(|&x| i64::from(x)).collect())),
        Data::I32(v) => ("int32", ints(v.iter().map(|&x| i64::from(x)).collect())),
        Data::I64(v) => ("int64", ints(v.clone())),
        Data::Date(v) => ("date", ints(v.iter().map(|&x| i64::from(x)).collect())),
        Data::Bool(v) => ("bool", (0..n).map(|r| if missing(r) { Value::Null } else { json!(v[r] == 1) }).collect()),
        Data::F32(v) => ("float32", (0..n).map(|r| if missing(r) { Value::Null } else { number(f64::from(v[r])) }).collect()),
        Data::F64(v) => ("float64", (0..n).map(|r| if missing(r) { Value::Null } else { number(v[r]) }).collect()),
        Data::Ts { unit, utc, zone, v } => {
            o.insert(
                "unit".into(),
                json!(match unit {
                    TimeUnit::Millis => "ms",
                    TimeUnit::Micros => "us",
                    TimeUnit::Nanos => "ns",
                }),
            );
            o.insert("utc".into(), json!(utc));
            o.insert("zone".into(), json!(zone));
            ("timestamp", ints(v.clone()))
        }
        Data::Text(v) => ("text", v.iter().map(|s| json!(s)).collect()),
        Data::Binary(v) => ("binary", v.iter().map(|s| json!(s)).collect()),
        Data::Cat { levels, ordered, codes } => {
            o.insert("levels".into(), json!(levels));
            o.insert("ordered".into(), json!(ordered));
            ("categorical", codes.iter().map(|&k| if k < 0 { Value::Null } else { json!(levels[k as usize]) }).collect())
        }
    };
    o.insert("type".into(), json!(kind));
    o.insert("values".into(), Value::Array(values));
    if c.codes.iter().any(|&k| k > 1) {
        let letters: Vec<Value> = c.codes.iter().map(|&k| if k > 1 { json!(format!(".{}", (b'a' + k - 2) as char)) } else { Value::Null }).collect();
        o.insert("letters".into(), Value::Array(letters));
    }
    Value::Object(o)
}

fn main() {
    let dir = std::env::args().nth(1).expect("usage: samples DIR");
    std::fs::create_dir_all(&dir).unwrap();
    let mut expected = Map::new();
    let mut put = |name: &str, cols: &[Col], profile: Profile, options: WriteOptions| {
        let path = format!("{dir}/{name}.parquet");
        let file = std::io::BufWriter::new(std::fs::File::create(&path).unwrap());
        write(&table(cols, profile), file, &options).unwrap();
        let mut columns = Map::new();
        for c in cols {
            columns.insert(c.name.clone(), describe(c));
        }
        let order: Vec<&str> = cols.iter().map(|c| c.name.as_str()).collect();
        expected.insert(name.into(), json!({"rows": cols.first().map_or(0, Col::rows), "order": order, "columns": columns}));
        println!("wrote {path}");
    };
    let cols = every_type(1000);
    put("every_type", &cols, profile(), WriteOptions::default());
    for (suffix, c) in [("snappy", Compression::Snappy), ("gzip", Compression::Gzip), ("none", Compression::None), ("lz4_raw", Compression::Lz4Raw)] {
        put(&format!("every_type_{suffix}"), &cols, profile(), WriteOptions { compression: c, ..Default::default() });
    }
    put(
        "row_groups",
        &every_type(5000),
        profile(),
        WriteOptions { row_group_rows: Some(1000), page_bytes: 4096, ..Default::default() },
    );
    put("empty", &every_type(0), Profile::default(), WriteOptions::default());
    // 5,000 columns with large label sets (plan 0018, "Risks").
    let wide: Vec<Col> = (0..5000).map(|k| Col { name: format!("v{k}"), data: Data::I32(vec![k, k + 1, k + 2]), codes: vec![0, 1, 0] }).collect();
    let wide_profile = Profile {
        columns: (0..5000).map(|k| ColumnProfile { name: format!("v{k}"), value_labels: Some(format!("set{}", k % 50)), ..Default::default() }).collect(),
        value_labels: (0..50)
            .map(|s| ValueLabelSet {
                name: format!("set{s}"),
                labels: (0..1000).map(|v| ValueLabel { value: f64::from(v), missing: 0, text: format!("label {v} of set {s}") }).collect(),
            })
            .collect(),
        ..Default::default()
    };
    put("wide", &wide, wide_profile, WriteOptions::default());
    std::fs::write(format!("{dir}/expected.json"), serde_json::to_string_pretty(&Value::Object(expected)).unwrap()).unwrap();
}
