//! Tables made from data created here, written with the crate's writer
//! and read back, for the round-trip tests and the readback example.
#![allow(dead_code)]

use dta_parquet::format::TimeUnit;
use dta_parquet::{Numbers, Output, Profile, ReadOptions, Reader, Table, TextChunk, Values, WriteColumn};

/// A column's values as the tests hold them.
#[derive(Debug, Clone, PartialEq)]
pub enum Data {
    I8(Vec<i32>),
    I16(Vec<i32>),
    I32(Vec<i32>),
    I64(Vec<i64>),
    F32(Vec<f32>),
    F64(Vec<f64>),
    Bool(Vec<u8>),
    Date(Vec<i32>),
    Ts { unit: TimeUnit, utc: bool, zone: Option<String>, v: Vec<i64> },
    Text(Vec<Option<String>>),
    Binary(Vec<Option<Vec<u8>>>),
    Cat { levels: Vec<String>, ordered: bool, codes: Vec<i32> },
}

/// A column: its values and, for numbers, a missing code per row (0 for
/// a value, 1 for `.`, 2 to 27 for `.a` to `.z`).
#[derive(Debug, Clone, PartialEq)]
pub struct Col {
    pub name: String,
    pub data: Data,
    pub codes: Vec<u8>,
}

impl Col {
    pub fn rows(&self) -> usize {
        match &self.data {
            Data::I8(v) | Data::I16(v) | Data::I32(v) | Data::Date(v) => v.len(),
            Data::I64(v) | Data::Ts { v, .. } => v.len(),
            Data::F32(v) => v.len(),
            Data::F64(v) => v.len(),
            Data::Bool(v) => v.len(),
            Data::Text(v) => v.len(),
            Data::Binary(v) => v.len(),
            Data::Cat { codes, .. } => codes.len(),
        }
    }
}

fn fill<'a, T: Copy + Sync>(v: &'a [T], codes: &'a [u8]) -> Box<dta_parquet::Fill<'a, T>> {
    Box::new(move |first, out: &mut [T], c: &mut [u8]| {
        let n = out.len();
        out.copy_from_slice(&v[first..first + n]);
        c.copy_from_slice(&codes[first..first + n]);
    })
}

/// The writer's view of a column.
pub fn values(c: &Col) -> Values<'_> {
    let codes = &c.codes;
    match &c.data {
        Data::I8(v) => Values::Int8(fill(v, codes)),
        Data::I16(v) => Values::Int16(fill(v, codes)),
        Data::I32(v) => Values::Int32(fill(v, codes)),
        Data::I64(v) => Values::Int64(fill(v, codes)),
        Data::F32(v) => Values::Float(fill(v, codes)),
        Data::F64(v) => Values::Double(fill(v, codes)),
        Data::Bool(v) => Values::Bool(fill(v, codes)),
        Data::Date(v) => Values::Date(fill(v, codes)),
        Data::Ts { unit, utc, zone, v } => Values::Timestamp { unit: *unit, utc: *utc, zone: zone.clone(), fill: fill(v, codes) },
        Data::Text(v) => Values::Text(Box::new(move |r| v[r].as_deref().map(str::as_bytes))),
        Data::Binary(v) => Values::Binary(Box::new(move |r| v[r].as_deref())),
        Data::Cat { levels, ordered, codes: k } => Values::Categorical {
            levels: levels.clone(),
            ordered: *ordered,
            codes: Box::new(move |first, out: &mut [i32]| {
                let n = out.len();
                out.copy_from_slice(&k[first..first + n]);
            }),
        },
    }
}

pub fn table<'a>(cols: &'a [Col], profile: Profile) -> Table<'a> {
    let rows = cols.first().map_or(0, Col::rows);
    Table { rows, columns: cols.iter().map(|c| WriteColumn { name: c.name.clone(), values: values(c) }).collect(), profile }
}

/// Every type, with nulls, letters, categoricals and time zones, over
/// `n` rows; values are simple functions of the row.
pub fn every_type(n: usize) -> Vec<Col> {
    let rows = 0..n;
    let codes = |every: usize, letter: Option<(usize, u8)>| -> Vec<u8> {
        (0..n)
            .map(|r| {
                if r % every == 3 {
                    1
                } else {
                    match letter {
                        Some((m, code)) if r % every == m => code,
                        _ => 0,
                    }
                }
            })
            .collect()
    };
    let none = |every: usize| -> Vec<u8> { (0..n).map(|r| u8::from(r % every == 3)).collect() };
    let col = |name: &str, data: Data, codes: Vec<u8>| Col { name: name.into(), data, codes };
    vec![
        col("i8", Data::I8(rows.clone().map(|r| (r % 200) as i32 - 100).collect()), codes(10, Some((4, 2)))),
        col("i16", Data::I16(rows.clone().map(|r| (r as i32 * 7) % 30_000 - 15_000).collect()), codes(17, Some((5, 27)))),
        col("i32", Data::I32(rows.clone().map(|r| (r as i32).wrapping_mul(100_003) - 50_000_000).collect()), none(13)),
        col("i64", Data::I64(rows.clone().map(|r| r as i64 * 1_000_000_000_007 - 3).collect()), none(11)),
        col("f32", Data::F32(rows.clone().map(|r| if r == 7 { f32::NAN } else { r as f32 * 0.5 - 100.0 }).collect()), none(19)),
        col(
            "f64",
            Data::F64(rows.clone().map(|r| if r == 1 { -0.0 } else { r as f64 / 3.0 }).collect()),
            codes(23, Some((6, 3))),
        ),
        col("flag", Data::Bool(rows.clone().map(|r| u8::from(r % 3 == 0)).collect()), none(29)),
        col(
            "name",
            Data::Text(rows.clone().map(|r| if r % 31 == 3 { None } else { Some(format!("name {} é", r % 50)) }).collect()),
            vec![],
        ),
        col(
            "blob",
            Data::Binary(rows.clone().map(|r| if r % 37 == 3 { None } else { Some(vec![(r % 256) as u8, 0, 255]) }).collect()),
            vec![],
        ),
        col("day", Data::Date(rows.clone().map(|r| r as i32 - 500).collect()), none(41)),
        col(
            "when_ny",
            Data::Ts {
                unit: TimeUnit::Micros,
                utc: true,
                zone: Some("America/New_York".into()),
                v: rows.clone().map(|r| 1_700_000_000_000_000 + r as i64 * 3_600_000_000).collect(),
            },
            none(43),
        ),
        col(
            "when_utc",
            Data::Ts { unit: TimeUnit::Millis, utc: true, zone: None, v: rows.clone().map(|r| 1_600_000_000_000 + r as i64 * 1000).collect() },
            none(47),
        ),
        col(
            "local",
            Data::Ts { unit: TimeUnit::Nanos, utc: false, zone: None, v: rows.clone().map(|r| r as i64 * 1_000_000_123).collect() },
            none(53),
        ),
        col(
            "region",
            Data::Cat {
                levels: vec!["North".into(), "South".into(), "West".into(), "Unused".into()],
                ordered: false,
                codes: rows.clone().map(|r| if r % 59 == 3 { -1 } else { (r % 3) as i32 }).collect(),
            },
            vec![],
        ),
        col(
            "size",
            Data::Cat {
                levels: vec!["small".into(), "medium".into(), "large".into()],
                ordered: true,
                codes: rows.clone().map(|r| ((r / 2) % 3) as i32).collect(),
            },
            vec![],
        ),
    ]
}

/// A column as read back: numbers as `f64` (or exact `i64`) with codes,
/// text as optional bytes, categoricals as codes.
#[derive(Debug, Clone, PartialEq)]
pub enum Got {
    Ints(Vec<i64>, Vec<u8>),
    Floats(Vec<f64>, Vec<u8>),
    Bytes(Vec<Option<Vec<u8>>>),
    Levels(Vec<i32>),
}

/// What a column should read back as over `rows`.
pub fn expected(c: &Col, rows: std::ops::Range<usize>) -> Got {
    let codes = || c.codes[rows.clone()].to_vec();
    let ints = |v: Vec<i64>| {
        let k = codes();
        Got::Ints(v.into_iter().zip(&k).map(|(x, &c)| if c == 0 { x } else { i64::MIN }).collect(), k)
    };
    match &c.data {
        Data::I8(v) | Data::I16(v) | Data::I32(v) | Data::Date(v) => ints(v[rows.clone()].iter().map(|&x| i64::from(x)).collect()),
        Data::I64(v) | Data::Ts { v, .. } => ints(v[rows.clone()].to_vec()),
        Data::Bool(v) => ints(v[rows.clone()].iter().map(|&x| i64::from(x)).collect()),
        Data::F32(v) => {
            let k = codes();
            Got::Floats(v[rows.clone()].iter().zip(&k).map(|(&x, &c)| if c == 0 { f64::from(x) } else { -1e300 }).collect(), k)
        }
        Data::F64(v) => {
            let k = codes();
            Got::Floats(v[rows.clone()].iter().zip(&k).map(|(&x, &c)| if c == 0 { x } else { -1e300 }).collect(), k)
        }
        Data::Text(v) => Got::Bytes(v[rows].iter().map(|s| s.as_ref().map(|s| s.as_bytes().to_vec())).collect()),
        Data::Binary(v) => Got::Bytes(v[rows].to_vec()),
        Data::Cat { codes, .. } => Got::Levels(codes[rows].iter().map(|&c| if c < 0 { -1 } else { c }).collect()),
    }
}

/// Read `names` over rows `skip..skip + n` with `options`; each column
/// read the way its kind suggests. Returns the columns, the report's
/// letters flags and warnings.
pub fn read(bytes: &[u8], names: &[&str], skip: u64, n: u64, options: ReadOptions) -> (Vec<Got>, Vec<bool>, Vec<String>) {
    let mut r = Reader::open(dta::Bytes(bytes), options).unwrap();
    read_with(&mut r, names, skip, n).unwrap()
}

pub fn read_with<S: dta::Source>(r: &mut Reader<S>, names: &[&str], skip: u64, n: u64) -> dta::Result<(Vec<Got>, Vec<bool>, Vec<String>)> {
    use dta_parquet::ColumnType::*;
    let window = r.window(skip, n);
    let rows = (window.end - window.start) as usize;
    let idx: Vec<usize> = names.iter().map(|n| r.column_index(n).unwrap_or_else(|| panic!("no column {n}"))).collect();
    let kinds: Vec<_> = idx.iter().map(|&k| r.columns()[k].kind.clone()).collect();
    let cats: Vec<bool> = names.iter().map(|n| r.profile().and_then(|p| p.column(n)).is_some_and(|c| c.categorical.is_some())).collect();
    let mut ints: Vec<(Vec<i64>, Vec<u8>)> = vec![(vec![0; rows], vec![0; rows]); names.len()];
    let mut floats: Vec<(Vec<f64>, Vec<u8>)> = vec![(vec![0.0; rows], vec![0; rows]); names.len()];
    let mut levels: Vec<Vec<i32>> = vec![vec![0; rows]; names.len()];
    let mut texts: Vec<Vec<Option<Vec<u8>>>> = vec![Vec::new(); names.len()];
    let mut outputs: Vec<Output> = Vec::new();
    for ((((kind, &cat), i), f), l) in kinds.iter().zip(&cats).zip(ints.iter_mut()).zip(floats.iter_mut()).zip(levels.iter_mut()) {
        outputs.push(match kind {
            Float | Double => Output::Float64(Numbers::new(&mut f.0, -1e300).with_codes(&mut f.1)),
            Text if cat => Output::Levels { codes: l, base: 0, null: -1 },
            Text | Binary => Output::Text,
            _ => Output::Int64(Numbers::new(&mut i.0, i64::MIN).with_codes(&mut i.1)),
        });
    }
    let report = r.read(&idx, skip, n, &mut outputs, |k, chunk: &TextChunk| {
        assert_eq!(chunk.first as usize, texts[k].len(), "text chunks come in row order");
        for row in 0..chunk.rows {
            texts[k].push(chunk.row(row).map(<[u8]>::to_vec));
        }
        Ok(())
    })?;
    drop(outputs);
    let mut out = Vec::new();
    for (k, kind) in kinds.iter().enumerate() {
        out.push(match kind {
            Float | Double => Got::Floats(floats[k].0.clone(), floats[k].1.clone()),
            Text if cats[k] => Got::Levels(levels[k].clone()),
            Text | Binary => Got::Bytes(std::mem::take(&mut texts[k])),
            _ => Got::Ints(ints[k].0.clone(), ints[k].1.clone()),
        });
    }
    Ok((out, report.letters, report.warnings))
}

/// Compare, treating NaN as equal to NaN and -0.0 as distinct from 0.0.
pub fn same(a: &Got, b: &Got) -> bool {
    match (a, b) {
        (Got::Floats(x, cx), Got::Floats(y, cy)) => {
            cx == cy && x.len() == y.len() && x.iter().zip(y).all(|(p, q)| p.to_bits() == q.to_bits() || (p.is_nan() && q.is_nan()))
        }
        _ => a == b,
    }
}
