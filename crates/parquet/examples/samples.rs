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
use support::{dated_columns, every_type, storage_columns, table, Col, Data};

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

/// The nearest double to `v` units of `per_second` a second: the exact
/// decimal, parsed.
fn seconds(v: i64, per_second: u64) -> f64 {
    let (q, r) = (v.unsigned_abs() / per_second, v.unsigned_abs() % per_second);
    let digits = per_second.ilog10() as usize;
    let sign = if v < 0 { "-" } else { "" };
    format!("{sign}{q}.{r:0digits$}").parse().unwrap()
}

/// What a column holds, for the readback scripts. `.a` to `.z` are null
/// in `values` and named in `letters`; with `letters_on` the column is
/// then written as DOUBLE (`type` is `float64`; `storage` names what it
/// was, or `logical` says it was a date, in days since 1970, or a
/// timestamp, in seconds, with `tz` its zone in the profile), and
/// without, they are plain nulls.
fn describe(c: &Col, letters_on: bool) -> Value {
    let n = c.rows();
    let missing = |r: usize| c.codes.get(r).is_some_and(|&k| k != 0);
    let ints = |v: Vec<i64>| -> Vec<Value> { (0..n).map(|r| if missing(r) { Value::Null } else { json!(v[r]) }).collect() };
    let mut o = Map::new();
    let (mut kind, values): (&str, Vec<Value>) = match &c.data {
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
    let mut values = values;
    // A categorical holding .a to .z (plan 0022): DOUBLE level numbers
    // from 1, `logical` categorical in the profile.
    if let Data::Cat { codes, .. } = &c.data {
        if letters_on && codes.iter().any(|&k| (-27..=-2).contains(&k)) {
            let letters: Vec<Value> =
                codes.iter().map(|&k| if (-27..=-2).contains(&k) { json!(format!(".{}", (b'a' + (-k) as u8 - 2) as char)) } else { Value::Null }).collect();
            o.insert("letters".into(), Value::Array(letters));
            o.insert("logical".into(), json!("categorical"));
            values = codes.iter().map(|&k| if k < 0 { Value::Null } else { json!(f64::from(k + 1)) }).collect();
            kind = "float64";
        }
    }
    if letters_on && c.codes.iter().any(|&k| k > 1) {
        let letters: Vec<Value> = c.codes.iter().map(|&k| if k > 1 { json!(format!(".{}", (b'a' + k - 2) as char)) } else { Value::Null }).collect();
        o.insert("letters".into(), Value::Array(letters));
        let storage = match &c.data {
            Data::I8(_) => Some("byte"),
            Data::I16(_) => Some("int"),
            Data::I32(_) => Some("long"),
            Data::F32(_) => Some("float"),
            _ => None,
        };
        if let Some(st) = storage {
            o.insert("storage".into(), json!(st));
        }
        match &c.data {
            Data::Date(_) => {
                o.insert("logical".into(), json!("date"));
            }
            Data::Ts { unit, utc, zone, v } => {
                for key in ["unit", "utc", "zone"] {
                    o.remove(key);
                }
                o.insert("logical".into(), json!("timestamp"));
                // The profile's tz: the zone, "" for an instant without
                // one, absent for a local time.
                let tz = zone.clone().or_else(|| utc.then(String::new));
                if let Some(tz) = tz {
                    o.insert("tz".into(), json!(tz));
                }
                let per_second = match unit {
                    TimeUnit::Millis => 1_000,
                    TimeUnit::Micros => 1_000_000,
                    TimeUnit::Nanos => 1_000_000_000,
                };
                values = (0..n).map(|r| if missing(r) { Value::Null } else { json!(seconds(v[r], per_second)) }).collect();
            }
            _ => {}
        }
        kind = "float64";
    }
    o.insert("type".into(), json!(kind));
    o.insert("values".into(), Value::Array(values));
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
            columns.insert(c.name.clone(), describe(c, options.missing_letters));
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
    // .a to .z from every storage type, beside `.` and a NaN value; and the
    // same with missing_letters off, as plain nulls.
    put("letters", &storage_columns(), Profile::default(), WriteOptions::default());
    put("letters_off", &storage_columns(), Profile::default(), WriteOptions { missing_letters: false, ..Default::default() });
    // A date and timestamps with .a to .z, written as days and seconds
    // since 1970; and with missing_letters off, as dates and timestamps.
    put("dated", &dated_columns(), Profile::default(), WriteOptions::default());
    put("dated_off", &dated_columns(), Profile::default(), WriteOptions { missing_letters: false, ..Default::default() });
    // A categorical holding .a to .z, written as DOUBLE level numbers
    // (plan 0022), beside one without; with missing_letters off, both text.
    let cats = [
        Col {
            name: "grade".into(),
            data: Data::Cat { levels: vec!["low".into(), "mid".into(), "high".into()], ordered: true, codes: vec![0, -2, 2, -1, -27, 1] },
            codes: vec![],
        },
        Col { name: "plain".into(), data: Data::Cat { levels: vec!["a".into(), "b".into()], ordered: false, codes: vec![0, 1, -1, 0, 1, 0] }, codes: vec![] },
    ];
    put("categorical_letters", &cats, Profile::default(), WriteOptions::default());
    put("categorical_letters_off", &cats, Profile::default(), WriteOptions { missing_letters: false, ..Default::default() });
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
