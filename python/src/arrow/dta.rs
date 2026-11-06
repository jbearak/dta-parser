//! `.dta` files through Arrow memory, for datakit's `read_dta`,
//! `save_dta` and `read_fixed_width` (plan 0019, "`.dta` in polars"):
//! `dta_read_arrow` and `dta_write_arrow`, without pandas.
//!
//! Reading follows `dta_parser.read_dta`'s rules where they apply to
//! polars: byte, int, long, float and double as Int8, Int16, Int32,
//! Float32 and Float64 with nulls; `%td` (and `%d`) as Date and `%tc` as
//! Datetime("ms"); strN and text strLs as String, binary strLs as Binary,
//! and a strL column mixing the two as Binary (text as its UTF-8 bytes).
//! Writing makes release 118 as `write_dta` does, from polars' export.

use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU8, Ordering};
use std::sync::{Arc, Mutex};

use pyo3::exceptions::{PyKeyError, PyTypeError, PyValueError};
use pyo3::prelude::*;
use pyo3::types::{PyDict, PyList, PyString, PyTuple};

use dta::{missing, Characteristic, Column as DtaColumn, Dataset, StorageType, ValueLabelSet, Values, WriteVariable};

use super::digest::{key_at, text_at, valid};
use super::ffi::{self, import_stream, Array, ArrowTable, Field, Plan, Table};
use super::read::{label_sets, letters_table, Stamps};
use super::write::{columns, height, Column, Chunk};
use crate::{create_beside, fail};

/// Days from 1960-01-01 (Stata's epoch) to 1970-01-01.
const EPOCH_DAYS: i64 = 3653;
const DAY_MS: i64 = 86_400_000;

/// `%td`/`%d` dates and `%tc` datetimes, as `read_dta` tells them.
#[derive(Clone, Copy, PartialEq, Debug)]
enum DateKind {
    Days,
    Millis,
}

fn date_kind(format: &str) -> Option<DateKind> {
    let f = format.strip_prefix('%')?;
    let f = f.strip_prefix('-').unwrap_or(f);
    if f.starts_with("td") || f.starts_with('d') {
        Some(DateKind::Days)
    } else if f.starts_with("tc") {
        Some(DateKind::Millis)
    } else {
        None
    }
}

/// Set bits `at..at + n` of the shared `dst` from `src` (bit 0 first):
/// whole bytes stored, the edge bytes OR-ed (chunks of rows read on
/// several threads share them).
fn merge_bits(dst: &[AtomicU8], at: usize, src: &[u8], n: usize) {
    if n == 0 {
        return;
    }
    let (first, last, shift) = (at / 8, (at + n - 1) / 8, at % 8);
    for d in first..=last {
        let byte = if shift == 0 {
            src[d - first]
        } else if d == first {
            src[0] << shift
        } else {
            let lo = 8 * d - at;
            (src[lo / 8] >> (lo % 8)) | src.get(lo / 8 + 1).map_or(0, |b| b << (8 - lo % 8))
        };
        if 8 * d >= at && 8 * d + 8 <= at + n {
            dst[d].store(byte, Ordering::Relaxed);
        } else if byte != 0 {
            dst[d].fetch_or(byte, Ordering::Relaxed);
        }
    }
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Out {
    I8,
    I16,
    I32,
    F32,
    F64,
    /// Days since 1970 (Date).
    Date,
    /// Milliseconds since 1970 (Datetime("ms")).
    Stamp,
    Views,
}

impl Out {
    fn width(self) -> usize {
        match self {
            Out::I8 => 1,
            Out::I16 => 2,
            Out::I32 | Out::F32 | Out::Date => 4,
            Out::F64 | Out::Stamp => 8,
            Out::Views => 16,
        }
    }
    fn format(self) -> &'static str {
        match self {
            Out::I8 => "c",
            Out::I16 => "s",
            Out::I32 => "i",
            Out::F32 => "f",
            Out::F64 => "g",
            Out::Date => "tdD",
            Out::Stamp => "tsm:",
            Out::Views => "vu",
        }
    }
}

struct Target {
    name: String,
    out: Out,
    values: usize,
    validity: usize,
    letters: Mutex<Vec<(u64, u8)>>,
    buffers: Mutex<Vec<(u32, Vec<u8>)>>,
    counter: AtomicU32,
    binary: AtomicBool,
}

/// Put a chunk's rows of one column into its Arrow buffers.
fn put(t: &Target, rows: usize, first: usize, column: &DtaColumn, file_row: u64, mode: Stamps) -> dta::Result<()> {
    let n = column.len();
    let mut bits = vec![0u8; n.div_ceil(8)];
    let row_err = |i: usize, what: String| dta::Error::new(format!("column \"{}\", row {}: {what}", t.name, file_row + (first + i) as u64 + 1));
    match column {
        DtaColumn::Numbers { values, missing: codes } => {
            macro_rules! each {
                ($ty:ty, $conv:expr) => {{
                    // SAFETY: the buffer holds the read's rows; this chunk's
                    // rows are its own.
                    let out = unsafe { std::slice::from_raw_parts_mut((t.values as *mut $ty).add(first), n) };
                    for i in 0..n {
                        let c = codes.get(i).copied().unwrap_or(0);
                        if c == 0 && !values[i].is_nan() {
                            out[i] = $conv(i, values[i])?;
                            bits[i / 8] |= 1 << (i % 8);
                        } else if c > missing::SYSTEM {
                            t.letters.lock().unwrap_or_else(|p| p.into_inner()).push(((first + i) as u64, c));
                        }
                    }
                }};
            }
            match t.out {
                Out::I8 => each!(i8, |_, v: f64| dta::Result::Ok(v as i8)),
                Out::I16 => each!(i16, |_, v: f64| dta::Result::Ok(v as i16)),
                Out::I32 => each!(i32, |_, v: f64| dta::Result::Ok(v as i32)),
                Out::F32 => each!(f32, |_, v: f64| dta::Result::Ok(v as f32)),
                Out::F64 => each!(f64, |_, v: f64| dta::Result::Ok(v)),
                Out::Date => each!(i32, |i, v: f64| {
                    let d = v.floor();
                    if d != v && mode == Stamps::Error {
                        return Err(row_err(i, format!("the date {v} (days since 1960) has a fraction of a day; pass timestamps=\"truncate\" to drop it")));
                    }
                    let days = d - EPOCH_DAYS as f64;
                    if !(f64::from(i32::MIN)..=f64::from(i32::MAX)).contains(&days) {
                        return Err(row_err(i, format!("the date {v} (days since 1960) is outside polars' Date range")));
                    }
                    Ok(days as i32)
                }),
                Out::Stamp => each!(i64, |i, v: f64| {
                    let m = v.floor();
                    if m != v && mode == Stamps::Error {
                        return Err(row_err(i, format!("the datetime {v} (milliseconds since 1960) has a fraction of a millisecond; pass timestamps=\"truncate\" to drop it")));
                    }
                    let ms = m - (EPOCH_DAYS * DAY_MS) as f64;
                    if ms.abs() >= 9.2e18 {
                        return Err(row_err(i, format!("the datetime {v} (milliseconds since 1960) is outside polars' Datetime range")));
                    }
                    Ok(ms as i64)
                }),
                Out::Views => return Err(dta::Error::new("internal: numbers for a text column")),
            }
        }
        DtaColumn::Strings { binary, .. } => {
            // SAFETY: as above.
            let out = unsafe { std::slice::from_raw_parts_mut((t.values as *mut u128).add(first), n) };
            let mut long: Vec<u8> = Vec::new();
            let mut index: Option<u32> = None;
            for (i, o) in out.iter_mut().enumerate() {
                let b = column.bytes(i);
                if binary.get(i).copied().unwrap_or(false) {
                    t.binary.store(true, Ordering::Relaxed);
                }
                let mut v = [0u8; 16];
                v[..4].copy_from_slice(&(b.len() as u32).to_le_bytes());
                if b.len() <= 12 {
                    v[4..4 + b.len()].copy_from_slice(b);
                } else {
                    if index.is_some() && long.len() + b.len() > i32::MAX as usize {
                        t.buffers.lock().unwrap_or_else(|p| p.into_inner()).push((index.take().expect("an index"), std::mem::take(&mut long)));
                    }
                    let idx = *index.get_or_insert_with(|| t.counter.fetch_add(1, Ordering::Relaxed));
                    v[4..8].copy_from_slice(&b[..4]);
                    v[8..12].copy_from_slice(&idx.to_le_bytes());
                    v[12..16].copy_from_slice(&(long.len() as u32).to_le_bytes());
                    long.extend_from_slice(b);
                }
                *o = u128::from_le_bytes(v);
                bits[i / 8] |= 1 << (i % 8);
            }
            if let Some(idx) = index {
                t.buffers.lock().unwrap_or_else(|p| p.into_inner()).push((idx, long));
            }
        }
    }
    // SAFETY: the validity buffer holds the read's rows, as atomics.
    let validity = unsafe { std::slice::from_raw_parts(t.validity as *const AtomicU8, rows.div_ceil(8)) };
    merge_bits(validity, first, &bits, n);
    Ok(())
}

/// Read rows `skip..skip + n_max` of `columns` (names or 0-based
/// positions; all when None) of the `.dta` file at `path` into Arrow
/// memory. Returns `(frame, letters, meta)` as `parquet_read_arrow` does.
/// For datakit only.
#[pyfunction]
#[pyo3(signature = (path, columns=None, skip=0, n_max=None, encoding=None, timestamps="error"))]
pub fn dta_read_arrow<'py>(
    py: Python<'py>,
    path: &str,
    columns: Option<Vec<Bound<'py, PyAny>>>,
    skip: u64,
    n_max: Option<u64>,
    encoding: Option<&str>,
    timestamps: &str,
) -> PyResult<Bound<'py, PyTuple>> {
    let mode = Stamps::from_name(timestamps)?;
    let mut reader = crate::open(path, encoding)?;
    let vars = reader.metadata().variables.clone();
    let nobs = reader.metadata().nobs;
    let selected: Vec<usize> = match &columns {
        None => (0..vars.len()).collect(),
        Some(cs) => {
            let mut out = Vec::with_capacity(cs.len());
            for c in cs {
                let k = if let Ok(s) = c.cast::<PyString>() {
                    let s = s.to_str()?;
                    vars.iter().position(|v| v.name == s).ok_or_else(|| PyKeyError::new_err(format!("column \"{s}\" is not in the file")))?
                } else {
                    let i: i64 = c.extract().map_err(|_| PyTypeError::new_err("columns are names or 0-based positions"))?;
                    usize::try_from(i).ok().filter(|&i| i < vars.len()).ok_or_else(|| {
                        pyo3::exceptions::PyIndexError::new_err(format!("there is no column {i}; the file has {}", vars.len()))
                    })?
                };
                if !out.contains(&k) {
                    out.push(k);
                }
            }
            out
        }
    };
    let start = skip.min(nobs);
    let count = n_max.unwrap_or(u64::MAX).min(nobs - start);
    let rows = usize::try_from(count).map_err(|_| fail("too many rows to read at once"))?;
    let mut plan = Plan::default();
    let mut layout = Vec::with_capacity(selected.len());
    for &c in &selected {
        let v = &vars[c];
        let out = match v.storage {
            StorageType::Str(_) | StorageType::StrL => Out::Views,
            s => match date_kind(&v.format) {
                Some(DateKind::Days) => Out::Date,
                Some(DateKind::Millis) => Out::Stamp,
                None => match s {
                    StorageType::Byte => Out::I8,
                    StorageType::Int => Out::I16,
                    StorageType::Long => Out::I32,
                    StorageType::Float => Out::F32,
                    _ => Out::F64,
                },
            },
        };
        layout.push((out, plan.add(rows * out.width()), plan.add(rows.div_ceil(8))));
    }
    let block = plan.block()?;
    let base = block.addr();
    let targets: Vec<Target> = selected
        .iter()
        .zip(&layout)
        .map(|(&c, &(out, v, b))| Target {
            name: vars[c].name.clone(),
            out,
            values: base + v,
            validity: base + b,
            letters: Mutex::new(Vec::new()),
            buffers: Mutex::new(Vec::new()),
            counter: AtomicU32::new(0),
            binary: AtomicBool::new(false),
        })
        .collect();
    let each = |k: usize, first: usize, column: &DtaColumn| -> dta::Result<bool> {
        put(&targets[k], rows, first, column, start, mode).map(|()| true)
    };
    let result = py.detach(|| {
        reader.read_chunks_with(
            &selected,
            start,
            count,
            None,
            &each,
            |first, chunk, taken, upto| {
                for (k, column) in chunk.iter().enumerate().take(upto) {
                    if !taken[k] {
                        each(k, first, column)?;
                    }
                }
                Ok(())
            },
            || Ok(()),
        )
    });
    result.map_err(|e| fail(format!("{path}: {e}")))?;
    let sets = reader.value_labels().map_err(|e| fail(format!("{path}: {e}")))?;
    let chars = reader.characteristics().map_err(|e| fail(format!("{path}: {e}")))?;
    let notes = reader.notes().map_err(|e| fail(format!("{path}: {e}")))?;

    // The frame.
    let mut text: Vec<Vec<u8>> = Vec::new();
    let mut per_col: Vec<Vec<usize>> = Vec::with_capacity(targets.len());
    let mut letters: Vec<(usize, Vec<(u64, u8)>)> = Vec::new();
    for (k, t) in targets.iter().enumerate() {
        let mut bufs = std::mem::take(&mut *t.buffers.lock().unwrap_or_else(|p| p.into_inner()));
        bufs.sort_unstable_by_key(|(i, _)| *i);
        per_col.push(bufs.into_iter().map(|(_, b)| {
            text.push(b);
            text.len() - 1
        }).collect());
        let mut l = std::mem::take(&mut *t.letters.lock().unwrap_or_else(|p| p.into_inner()));
        if !l.is_empty() {
            l.sort_unstable_by_key(|&(r, _)| r);
            letters.push((k, l));
        }
    }
    let sizes: Vec<Vec<i64>> = per_col.iter().map(|ids| ids.iter().map(|&i| text[i].len() as i64).collect()).collect();
    let text_addr: Vec<usize> = text.iter().map(|b| b.as_ptr() as usize).collect();
    let sizes_addr: Vec<usize> = sizes.iter().map(|s| s.as_ptr() as usize).collect();
    let nulls: Vec<usize> = targets
        .iter()
        .map(|t| {
            // SAFETY: the read is done; the bits are plain bytes again.
            let bits = unsafe { std::slice::from_raw_parts(t.validity as *const u8, rows.div_ceil(8)) };
            rows - bits.iter().map(|b| b.count_ones() as usize).sum::<usize>()
        })
        .collect();
    let owner: ffi::Owner = Arc::new((block, text, sizes));
    let mut fields = Vec::new();
    let mut arrays = Vec::new();
    for (k, t) in targets.iter().enumerate() {
        let mut format = t.out.format().to_string();
        if t.out == Out::Views && t.binary.load(Ordering::Relaxed) {
            format = "vz".into();
        }
        let mut buffers = vec![if nulls[k] > 0 { t.validity } else { 0 }, t.values];
        if t.out == Out::Views {
            buffers.extend(per_col[k].iter().map(|&i| text_addr[i]));
            buffers.push(sizes_addr[k]);
        }
        fields.push(Field::new(&t.name, &format));
        arrays.push(Array { length: rows, null_count: nulls[k], offset: 0, buffers, children: Vec::new(), dictionary: None, owner: Some(owner.clone()) });
    }
    let frame = ArrowTable {
        table: Table { fields, batches: vec![Array { length: rows, null_count: 0, offset: 0, buffers: vec![0], children: arrays, dictionary: None, owner: None }] },
    };
    let names: Vec<String> = targets.iter().map(|t| t.name.clone()).collect();
    let letters_obj = letters_table(&names, &letters, rows)?;

    // What Meta is made from.
    let out = PyDict::new(py);
    out.set_item("rows", rows)?;
    out.set_item("names", &names)?;
    let list = PyList::empty(py);
    let none = |s: &str| (!s.is_empty()).then(|| s.to_string());
    for &c in &selected {
        let v = &vars[c];
        let numeric = v.storage.is_numeric();
        list.append((&v.name, none(&v.label), none(&v.format), none(&v.value_labels), None::<bool>, v.storage.name(), None::<&str>, numeric))?;
    }
    out.set_item("columns", list)?;
    out.set_item("value_labels", label_sets(py, &sets)?)?;
    let m = reader.metadata();
    out.set_item("label", none(&m.label))?;
    out.set_item("timestamp", none(&m.timestamp))?;
    out.set_item("notes", notes)?;
    let keep: std::collections::HashSet<&str> = names.iter().map(String::as_str).chain(["_dta"]).collect();
    let cd = PyDict::new(py);
    for ch in &chars {
        let is_note = ch.variable == "_dta" && ch.name.strip_prefix("note").is_some_and(|n| n.parse::<u32>().is_ok());
        if is_note || !keep.contains(ch.variable.as_str()) {
            continue;
        }
        let d = match cd.get_item(&ch.variable)? {
            Some(d) => d.cast_into::<PyDict>()?,
            None => {
                let d = PyDict::new(py);
                cd.set_item(&ch.variable, &d)?;
                d
            }
        };
        d.set_item(&ch.name, &ch.value)?;
    }
    out.set_item("characteristics", cd)?;
    let sort: Vec<&str> = m.sort_order.iter().map(|&i| vars[i].name.as_str()).collect();
    out.set_item("sort", sort)?;
    out.set_item("warnings", Vec::<String>::new())?;
    out.set_item("letter_columns", letters.iter().map(|(k, _)| names[*k].as_str()).collect::<Vec<_>>())?;
    out.set_item("release", m.release)?;
    let letters_any: Py<PyAny> = match letters_obj {
        Some(t) => Py::new(py, t)?.into_any(),
        None => py.None(),
    };
    PyTuple::new(py, [Py::new(py, frame)?.into_any(), letters_any, out.into_any().unbind()])
}

// ---------------------------------------------------------------- write

const RESERVED: &[&str] = &[
    "_all", "_b", "byte", "_coef", "_cons", "double", "float", "if", "in", "int", "long", "_n", "_N", "_pi", "_pred",
    "_rc", "_skip", "strL", "using", "with",
];

/// Whether Stata can hold `name`: a letter or _, then up to 31 letters,
/// digits or _; not reserved; not str followed by digits.
fn stata_name(name: &str) -> bool {
    let mut chars = name.chars();
    let Some(first) = chars.next() else { return false };
    let word = |c: char| c.is_alphanumeric() || c == '_';
    (first.is_alphabetic() || first == '_')
        && name.chars().count() <= 32
        && chars.all(word)
        && !RESERVED.contains(&name)
        && !(name.starts_with("str") && name.len() > 3 && name[3..].bytes().all(|b| b.is_ascii_digit()))
}

const RANGES: [(StorageType, f64, f64); 3] = [
    (StorageType::Byte, -127.0, 100.0),
    (StorageType::Int, -32767.0, 32740.0),
    (StorageType::Long, -2_147_483_647.0, 2_147_483_620.0),
];
const EXACT: f64 = 9_007_199_254_740_992.0;

/// The storage of integers between `lo` and `hi`: the first of `from` on
/// (byte, int, long) holding both, else double; an error beyond ±2^53.
fn integer_storage(name: &str, lo: f64, hi: f64, from: usize) -> PyResult<StorageType> {
    for &(s, a, b) in &RANGES[from..] {
        if lo >= a && hi <= b {
            return Ok(s);
        }
    }
    if lo < -EXACT || hi > EXACT {
        return Err(fail(format!("column \"{name}\": {} is beyond ±2^53, which Stata cannot store exactly", if lo < -EXACT { lo } else { hi })));
    }
    Ok(StorageType::Double)
}

/// A 64-bit integer column's range as doubles, or an error past ±2^53.
fn exact_range(name: &str, (lo, hi): (i128, i128)) -> PyResult<(f64, f64)> {
    const MOST: i128 = 1 << 53;
    if lo < -MOST || hi > MOST {
        return Err(fail(format!("column \"{name}\": {} is beyond ±2^53, which Stata cannot store exactly", if lo < -MOST { lo } else { hi })));
    }
    Ok((lo as f64, hi as f64))
}

/// Each row's value as a double (0 for a null) and missing code.
type Row<'a> = Box<dyn Fn(&Chunk, usize) -> f64 + Sync + 'a>;

fn get<T: Copy + Into<f64>>(c: &Chunk, j: usize) -> f64 {
    // SAFETY: the values buffer holds `T`s.
    unsafe { (*(c.a.buffer(1) as *const T).add(j)).into() }
}

/// Write the polars frame `df` as release 118 to `path`. `meta` as for
/// `parquet_write_arrow`. For datakit only.
#[pyfunction]
#[pyo3(signature = (df, path, meta, missing_letters=true, timestamps="error", timestamp=None))]
pub fn dta_write_arrow<'py>(
    _py: Python<'py>,
    df: &Bound<'py, PyAny>,
    path: &str,
    meta: Option<&Bound<'py, PyDict>>,
    missing_letters: bool,
    timestamps: &str,
    timestamp: Option<String>,
) -> PyResult<()> {
    let mode = Stamps::from_name(timestamps)?;
    let imported = import_stream(df)?;
    let nobs = height(&imported);
    let cols = columns(&imported)?;
    let item = |k: &str| -> PyResult<Option<Bound<'py, PyAny>>> {
        Ok(match meta {
            Some(m) => m.get_item(k)?.filter(|v| !v.is_none()),
            None => None,
        })
    };
    let mut seen = std::collections::HashSet::new();
    for c in &cols {
        let n = &c.field.name;
        if !stata_name(n) {
            return Err(PyValueError::new_err(format!(
                "column \"{n}\" is not a name Stata can hold: 1 to 32 letters, digits or _, not starting with a digit, and not a reserved word"
            )));
        }
        if !seen.insert(n.as_str()) {
            return Err(PyValueError::new_err(format!("column \"{n}\" appears more than once")));
        }
    }
    // Letters.
    let mut letters: Vec<Option<Vec<u8>>> = cols.iter().map(|_| None).collect();
    if let (Some(m), true) = (item("missing")?, missing_letters) {
        let m = m.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.missing is not a dict"))?;
        for (name, series) in m.iter() {
            let name: String = name.extract()?;
            let Some(k) = cols.iter().position(|c| c.field.name == name) else { continue };
            let codes = super::write::letter_codes(&name, &series, nobs)?;
            if let Some(r) = codes.iter().enumerate().position(|(r, &c)| c != 0 && cols[k].is_valid(r)) {
                return Err(fail(format!("column \"{name}\": row {} holds a value and a letter; set one of them to null", r + 1)));
            }
            if codes.iter().any(|&c| c != 0) {
                letters[k] = Some(codes);
            }
        }
    }
    let entries: Option<Bound<'py, PyDict>> = match item("columns")? {
        Some(c) => Some(c.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.columns is not a dict"))?),
        None => None,
    };
    let mut sets: Vec<ValueLabelSet> = match item("value_labels")? {
        Some(s) => super::write::label_sets(&s.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.value_labels is not a dict"))?)?,
        None => Vec::new(),
    };
    let mut made: Vec<ValueLabelSet> = Vec::new();
    let mut variables = Vec::with_capacity(cols.len());
    // Per column, the Enum's key to code (1 to k) maps, kept for the fill.
    let mut cat_maps: Vec<Option<Vec<Vec<i32>>>> = cols.iter().map(|_| None).collect();
    for (k, c) in cols.iter().enumerate() {
        let name = c.field.name.clone();
        let (mut label, mut format, mut set) = (String::new(), String::new(), String::new());
        if let Some(e) = entries.as_ref().map(|e| e.get_item(&name)).transpose()?.flatten() {
            type Entry = (Option<String>, Option<String>, Option<String>, Option<bool>);
            let (l, f, s, _): Entry = e.extract()?;
            label = l.unwrap_or_default();
            format = f.unwrap_or_default();
            set = s.unwrap_or_default();
        }
        if format.ends_with('s') {
            format.clear();
        }
        let f = c.field.format.as_str();
        // The present values' range, for the storage type.
        let range = |as_f64: &dyn Fn(&Chunk, usize) -> f64| {
            let (mut lo, mut hi) = (f64::INFINITY, f64::NEG_INFINITY);
            for ch in &c.chunks {
                for j in ch.off..ch.off + ch.len {
                    if valid(&ch.a, j) {
                        let v = as_f64(ch, j);
                        lo = lo.min(v);
                        hi = hi.max(v);
                    }
                }
            }
            if lo > hi { (0.0, 0.0) } else { (lo, hi) }
        };
        // 64-bit integers in integers: as doubles, 2^53 + 1 would pass as 2^53.
        let int_range = |as_int: &dyn Fn(&Chunk, usize) -> i128| {
            let (mut lo, mut hi) = (i128::MAX, i128::MIN);
            for ch in &c.chunks {
                for j in ch.off..ch.off + ch.len {
                    if valid(&ch.a, j) {
                        let v = as_int(ch, j);
                        lo = lo.min(v);
                        hi = hi.max(v);
                    }
                }
            }
            if lo > hi { (0, 0) } else { (lo, hi) }
        };
        let col: &Column = c;
        let l = letters[k].take();
        let (storage, row): (StorageType, Option<Row>) = if c.field.dictionary.is_some() {
            // As Stata's `encode`: codes 1 to k, long, labelled with the
            // levels in order.
            let every = c.field.meta("_PL_ENUM_VALUES2").is_some();
            let (levels, maps) = super::write::categorical(&name, c, every)?;
            made.push(ValueLabelSet {
                name: name.clone(),
                labels: levels.iter().enumerate().map(|(i, t)| dta::ValueLabel { value: (i + 1) as f64, missing: 0, text: t.clone() }).collect(),
            });
            set = name.clone();
            format.clear();
            cat_maps[k] = Some(maps);
            (StorageType::Long, None)
        } else {
            match f {
                "c" => (integer_storage(&name, range(&get::<i8>).0, range(&get::<i8>).1, 0)?, Some(Box::new(get::<i8>) as Row)),
                "s" => {
                    let (lo, hi) = range(&get::<i16>);
                    (integer_storage(&name, lo, hi, 1)?, Some(Box::new(get::<i16>) as Row))
                }
                "i" => {
                    let (lo, hi) = range(&get::<i32>);
                    (integer_storage(&name, lo, hi, 2)?, Some(Box::new(get::<i32>) as Row))
                }
                "l" => {
                    let (lo, hi) = exact_range(&name, int_range(&|c: &Chunk, j: usize| i128::from(unsafe { *(c.a.buffer(1) as *const i64).add(j) })))?;
                    let g = |c: &Chunk, j: usize| unsafe { *(c.a.buffer(1) as *const i64).add(j) } as f64;
                    (integer_storage(&name, lo, hi, 0)?, Some(Box::new(g) as Row))
                }
                "C" => (integer_storage(&name, range(&get::<u8>).0, range(&get::<u8>).1, 0)?, Some(Box::new(get::<u8>) as Row)),
                "S" => (integer_storage(&name, range(&get::<u16>).0, range(&get::<u16>).1, 0)?, Some(Box::new(get::<u16>) as Row)),
                "I" => (integer_storage(&name, range(&get::<u32>).0, range(&get::<u32>).1, 0)?, Some(Box::new(get::<u32>) as Row)),
                "L" => {
                    let (lo, hi) = exact_range(&name, int_range(&|c: &Chunk, j: usize| i128::from(unsafe { *(c.a.buffer(1) as *const u64).add(j) })))?;
                    let g = |c: &Chunk, j: usize| unsafe { *(c.a.buffer(1) as *const u64).add(j) } as f64;
                    (integer_storage(&name, lo, hi, 0)?, Some(Box::new(g) as Row))
                }
                "b" => (StorageType::Byte, Some(Box::new(|c: &Chunk, j: usize| f64::from(unsafe { (*(c.a.buffer(1) as *const u8).add(j / 8) >> (j % 8)) & 1 })) as Row)),
                "f" => (StorageType::Float, Some(Box::new(get::<f32>) as Row)),
                "g" => (StorageType::Double, Some(Box::new(get::<f64>) as Row)),
                "tdD" => {
                    if date_kind(&format) != Some(DateKind::Days) {
                        format = "%td".into();
                    }
                    let g = |c: &Chunk, j: usize| f64::from(unsafe { *(c.a.buffer(1) as *const i32).add(j) }) + EPOCH_DAYS as f64;
                    let (lo, hi) = range(&g);
                    (integer_storage(&name, lo, hi, 2)?, Some(Box::new(g) as Row))
                }
                f if f.starts_with("ts") => {
                    if f.split_once(':').is_some_and(|(_, z)| !z.is_empty()) {
                        return Err(PyTypeError::new_err(format!(
                            "column \"{name}\" has a time zone, which .dta cannot hold; convert it with dt.replace_time_zone(None) or dt.convert_time_zone"
                        )));
                    }
                    let per_ms: i64 = match f.as_bytes()[2] {
                        b's' => -1000,
                        b'm' => 1,
                        b'u' => 1000,
                        _ => 1_000_000,
                    };
                    // Check every value: whole milliseconds, held exactly.
                    for ch in &c.chunks {
                        for j in ch.off..ch.off + ch.len {
                            if !valid(&ch.a, j) {
                                continue;
                            }
                            let v = unsafe { *(ch.a.buffer(1) as *const i64).add(j) };
                            let row = ch.start + j - ch.off + 1;
                            if per_ms > 1 && v % per_ms != 0 && mode == Stamps::Error {
                                return Err(fail(format!(
                                    "column \"{name}\", row {row}: the datetime is not a whole number of milliseconds, which a .dta datetime holds; pass timestamps=\"truncate\" to drop the rest"
                                )));
                            }
                            let ms = if per_ms < 0 { v.checked_mul(-per_ms) } else { Some(v.div_euclid(per_ms)) };
                            if ms.and_then(|m| m.checked_add(EPOCH_DAYS * DAY_MS)).is_none_or(|m| m.unsigned_abs() > 1 << 53) {
                                return Err(fail(format!("column \"{name}\", row {row}: the datetime is too far from 1960 for a .dta datetime to hold exactly")));
                            }
                        }
                    }
                    if date_kind(&format) != Some(DateKind::Millis) {
                        format = "%tc".into();
                    }
                    let g = move |c: &Chunk, j: usize| {
                        let v = unsafe { *(c.a.buffer(1) as *const i64).add(j) };
                        let ms = if per_ms < 0 { v * -per_ms } else { v.div_euclid(per_ms) };
                        (ms + EPOCH_DAYS * DAY_MS) as f64
                    };
                    (StorageType::Double, Some(Box::new(g) as Row))
                }
                "u" | "U" | "vu" | "z" | "Z" | "vz" => {
                    if l.is_some() {
                        return Err(fail(format!("column \"{name}\" is text and has .a to .z, which text cannot hold")));
                    }
                    let binary = matches!(f, "z" | "Z" | "vz");
                    let col2 = col;
                    let fmt = f.to_string();
                    let values = if binary {
                        Values::StrLs(Box::new(move |r: usize| {
                            let (ch, j) = col2.at(col2.find(r), r);
                            (if valid(&ch.a, j) { unsafe { text_at(&ch.a, &fmt, j) } } else { &[][..] }, true)
                        }))
                    } else {
                        Values::Strings(Box::new(move |r: usize| {
                            let (ch, j) = col2.at(col2.find(r), r);
                            if valid(&ch.a, j) { unsafe { text_at(&ch.a, &fmt, j) } } else { &[][..] }
                        }))
                    };
                    let storage = if binary { StorageType::StrL } else { StorageType::Str(1) };
                    if format.ends_with('s') {
                        format.clear();
                    }
                    variables.push(WriteVariable { name, storage, format, label, value_labels: set, values });
                    continue;
                }
                "n" => (StorageType::Double, Some(Box::new(|_: &Chunk, _: usize| 0.0) as Row)),
                other => {
                    return Err(PyTypeError::new_err(format!(
                        "column \"{name}\" is {}, which .dta cannot hold; cast it first",
                        match other {
                            o if o.starts_with("tt") => "Time".to_string(),
                            o if o.starts_with("tD") => "Duration".to_string(),
                            o if o.starts_with("d:") => "Decimal".to_string(),
                            o => format!("Arrow type {o}"),
                        }
                    )));
                }
            }
        };
        if !set.is_empty() && !sets.iter().chain(&made).any(|s| s.name == set) {
            return Err(PyKeyError::new_err(format!("column \"{name}\" names the value label set \"{set}\", which meta.value_labels does not have")));
        }
        let maps = cat_maps[k].take();
        let kf = c.field.format.clone();
        let nan_null = matches!(f, "f" | "g");
        let values = Values::Numbers(Box::new(move |first, out: &mut [f64], codes: &mut [u8]| {
            if col.chunks.is_empty() {
                out.fill(f64::NAN);
                codes.fill(missing::SYSTEM);
                return;
            }
            let mut kk = col.find(first);
            for (i, (o, code)) in out.iter_mut().zip(codes.iter_mut()).enumerate() {
                let r = first + i;
                kk = col.seek(kk, r);
                let (ch, j) = col.at(kk, r);
                let v = if !valid(&ch.a, j) {
                    None
                } else if let Some(m) = &maps {
                    unsafe { key_at(&ch.a, &kf, j) }.and_then(|key| m[kk].get(key).copied()).filter(|&c| c >= 0).map(|c| f64::from(c + 1))
                } else {
                    let x = row.as_ref().expect("a row reader")(ch, j);
                    (!(nan_null && x.is_nan())).then_some(x)
                };
                match v {
                    Some(x) => {
                        *o = x;
                        *code = 0;
                    }
                    None => {
                        *o = f64::NAN;
                        *code = l.as_ref().map_or(missing::SYSTEM, |l| if l[r] != 0 { l[r] } else { missing::SYSTEM });
                    }
                }
            }
        }));
        variables.push(WriteVariable { name, storage, format, label, value_labels: set, values });
    }
    sets.extend(made);
    // Characteristics and notes, sort, label, time stamp.
    let names: Vec<&str> = cols.iter().map(|c| c.field.name.as_str()).collect();
    let mut characteristics = Vec::new();
    if let Some(chars) = item("characteristics")? {
        let chars = chars.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.characteristics is not a dict"))?;
        for (var, entries) in chars.iter() {
            let variable: String = var.extract()?;
            if variable != "_dta" && !names.contains(&variable.as_str()) {
                continue;
            }
            for (n, v) in entries.cast_into::<PyDict>()?.iter() {
                characteristics.push(Characteristic { variable: variable.clone(), name: n.extract()?, value: v.extract()? });
            }
        }
    }
    let notes: Vec<String> = item("notes")?.map(|v| v.extract()).transpose()?.unwrap_or_default();
    if !notes.is_empty() {
        characteristics.push(Characteristic { variable: "_dta".into(), name: "note0".into(), value: notes.len().to_string() });
        for (i, n) in notes.into_iter().enumerate() {
            characteristics.push(Characteristic { variable: "_dta".into(), name: format!("note{}", i + 1), value: n });
        }
    }
    let mut sort_order = Vec::new();
    for s in item("sort")?.map(|v| v.extract::<Vec<String>>()).transpose()?.unwrap_or_default() {
        match names.iter().position(|n| *n == s) {
            Some(i) => sort_order.push(i),
            None => break,
        }
    }
    let label: String = item("label")?.map(|v| v.extract()).transpose()?.unwrap_or_default();
    let stamp = timestamp.or(item("timestamp")?.map(|v| v.extract()).transpose()?).unwrap_or_default();
    let data = Dataset { nobs, label, timestamp: stamp, variables, value_labels: sets, characteristics, sort_order };
    let (tmp, file) = create_beside(path).map_err(|e| fail(format!("{path}: {e}")))?;
    // With the GIL held, as write_dta: text is read through polars' buffers,
    // which the GIL keeps from being freed under us.
    let result = dta::write(&data, std::io::BufWriter::with_capacity(1 << 20, file));
    if let Err(e) = result {
        let _ = std::fs::remove_file(&tmp);
        return Err(fail(format!("{path}: {e}")));
    }
    drop(data);
    std::fs::rename(&tmp, path).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        fail(format!("{path}: {e}"))
    })?;
    Ok(())
}
