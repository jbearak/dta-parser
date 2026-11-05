//! Writing a polars frame as Parquet from polars' own Arrow export
//! (`DataFrame.__arrow_c_stream__()`): `parquet_write_arrow`, for datakit
//! only (plan 0019, `save_parquet`).
//!
//! The writer reads polars' buffers in place: numbers a block of rows at
//! a time, text through string views (or offsets), an Enum or Categorical
//! through its dictionary, whose keys polars makes 8, 16 or 32 bits wide
//! by the number of categories. A frame may come in several chunks, and
//! an array may be a slice. Nothing is copied but the values the encoder
//! takes.

use std::collections::HashMap;

use pyo3::exceptions::{PyKeyError, PyTypeError, PyValueError};
use pyo3::prelude::*;
use pyo3::types::{PyBytes, PyDict, PyString};

use dta::{missing, Characteristic, ValueLabel, ValueLabelSet};
use dta_parquet::format::TimeUnit;
use dta_parquet::{ColumnProfile, Compression, Fill, GetBytes, Profile, Table, Values, WriteColumn, WriteOptions};

use super::digest::{key_at, text_at, valid};
use super::ffi::{import_stream, ArrayRef, InField};
use super::read::Stamps;
use crate::{create_beside, fail};

/// One chunk of a column: the array, the frame's row of its first, and
/// the offset its parent adds.
#[derive(Clone, Copy)]
pub(crate) struct Chunk<'a> {
    pub(crate) a: ArrayRef<'a>,
    pub(crate) start: usize,
    pub(crate) len: usize,
    /// Index of the chunk's first row in its buffers.
    pub(crate) off: usize,
}

// SAFETY: the producer's buffers are read only while the write runs,
// and the stream that owns them outlives it.
unsafe impl Send for Chunk<'_> {}
unsafe impl Sync for Chunk<'_> {}

/// A column over every batch.
pub(crate) struct Column<'a> {
    pub(crate) field: &'a InField,
    pub(crate) chunks: Vec<Chunk<'a>>,
    pub(crate) rows: usize,
}

impl<'a> Column<'a> {
    /// The chunk holding row `r`, from chunk `k` on.
    #[inline]
    pub(crate) fn seek(&self, mut k: usize, r: usize) -> usize {
        while k + 1 < self.chunks.len() && r >= self.chunks[k].start + self.chunks[k].len {
            k += 1;
        }
        k
    }

    pub(crate) fn find(&self, r: usize) -> usize {
        self.chunks.partition_point(|c| c.start + c.len <= r).min(self.chunks.len().saturating_sub(1))
    }

    /// Row `r`'s place: its chunk and index in the chunk's buffers.
    #[inline]
    pub(crate) fn at(&self, k: usize, r: usize) -> (&Chunk<'a>, usize) {
        let c = &self.chunks[k];
        (c, c.off + r - c.start)
    }

    pub(crate) fn is_valid(&self, r: usize) -> bool {
        let (c, j) = self.at(self.find(r), r);
        valid(&c.a, j)
    }
}

/// The columns of an imported frame.
pub(crate) fn columns(imported: &super::ffi::Imported) -> PyResult<Vec<Column<'_>>> {
    let schema = &imported.schema;
    if schema.format != "+s" {
        return Err(PyTypeError::new_err("the Arrow stream is not a table (a struct of columns)"));
    }
    let mut out: Vec<Column> =
        schema.children.iter().map(|field| Column { field, chunks: Vec::new(), rows: 0 }).collect();
    let mut start = 0;
    for b in &imported.batches {
        let top = b.get();
        let n = top.len();
        for (k, col) in out.iter_mut().enumerate() {
            let a = top.child(k).ok_or_else(|| fail("a batch lacks a column"))?;
            if n > 0 {
                col.chunks.push(Chunk { a, start, len: n, off: a.offset() + top.offset() });
            }
            col.rows = start + n;
        }
        start += n;
    }
    Ok(out)
}

/// The frame's rows.
pub(crate) fn height(imported: &super::ffi::Imported) -> usize {
    imported.batches.iter().map(|b| b.get().len()).sum()
}

/// A block fill of a numeric column: `get(chunk, index)` reads a value;
/// a null's code is `.`, or its letter where `letters` has one.
fn numbers<'a, T: Copy + Default + Send + Sync + 'a>(
    col: &'a Column<'a>,
    letters: Option<&'a [u8]>,
    get: impl Fn(&Chunk, usize) -> T + Sync + 'a,
) -> Box<Fill<'a, T>> {
    Box::new(move |first, out: &mut [T], codes: &mut [u8]| {
        if col.chunks.is_empty() {
            out.fill(T::default());
            codes.fill(missing::SYSTEM);
            return;
        }
        let mut k = col.find(first);
        for (i, (o, c)) in out.iter_mut().zip(codes.iter_mut()).enumerate() {
            let r = first + i;
            k = col.seek(k, r);
            let (chunk, j) = col.at(k, r);
            if valid(&chunk.a, j) {
                *o = get(chunk, j);
                *c = 0;
            } else {
                *o = T::default();
                *c = letters.map_or(missing::SYSTEM, |l| if l[r] != 0 { l[r] } else { missing::SYSTEM });
            }
        }
    })
}

/// Value `j` of a buffer of `T`.
#[inline]
fn value<T: Copy>(c: &Chunk, j: usize) -> T {
    // SAFETY: the array's values buffer holds its rows in `T`.
    unsafe { *(c.a.buffer(1) as *const T).add(j) }
}

fn bit(c: &Chunk, j: usize) -> u8 {
    // SAFETY: a boolean array's values are bits.
    unsafe { (*(c.a.buffer(1) as *const u8).add(j / 8) >> (j % 8)) & 1 }
}

/// Row `r`'s bytes of a text or binary column.
fn texts<'a>(col: &'a Column<'a>, format: &'a str) -> Box<GetBytes<'a>> {
    Box::new(move |r: usize| {
        if col.chunks.is_empty() {
            return None;
        }
        let (c, j) = col.at(col.find(r), r);
        // SAFETY: the format says the buffers' layout.
        valid(&c.a, j).then(|| unsafe { text_at(&c.a, format, j) })
    })
}

/// An Enum or Categorical: its levels (an Enum's every category; a
/// Categorical's that its rows use, in polars' order) and each chunk's
/// key to level map.
fn categorical<'a>(name: &str, col: &'a Column<'a>, every: bool) -> PyResult<(Vec<String>, Vec<Vec<i32>>)> {
    let dict_field = col.field.dictionary.as_deref().expect("a dictionary");
    let df = dict_field.format.as_str();
    if !matches!(df, "u" | "U" | "vu") {
        return Err(fail(format!("column \"{name}\": a dictionary of Arrow type {df} is not written")));
    }
    let kf = col.field.format.as_str();
    let mut levels: Vec<String> = Vec::new();
    let mut index: HashMap<&[u8], i32> = HashMap::new();
    let mut maps = Vec::with_capacity(col.chunks.len());
    for c in &col.chunks {
        let d = c.a.dictionary().ok_or_else(|| fail(format!("column \"{name}\": a dictionary array without its dictionary")))?;
        let used: Vec<bool> = if every {
            vec![true; d.len()]
        } else {
            let mut u = vec![false; d.len()];
            for j in c.off..c.off + c.len {
                if valid(&c.a, j) {
                    // SAFETY: the keys are of the field's format.
                    let k = unsafe { key_at(&c.a, kf, j) }.ok_or_else(|| fail(format!("column \"{name}\": a bad dictionary key")))?;
                    *u.get_mut(k).ok_or_else(|| fail(format!("column \"{name}\": a key past its dictionary")))? = true;
                }
            }
            u
        };
        let mut map = vec![-1i32; d.len()];
        for (k, &u) in used.iter().enumerate() {
            if !u || !valid(&d, d.offset() + k) {
                continue;
            }
            // SAFETY: the dictionary is text of format `df`.
            let v: &'a [u8] = unsafe { text_at(&d, df, d.offset() + k) };
            let next = levels.len() as i32;
            let level = *index.entry(v).or_insert_with(|| {
                levels.push(String::from_utf8_lossy(v).into_owned());
                next
            });
            map[k] = level;
        }
        maps.push(map);
    }
    Ok((levels, maps))
}

/// Each row's `.a` to `.z` (2 to 27), or 0, from a `LETTERS` Series or a
/// String one.
fn letter_codes(name: &str, obj: &Bound<'_, PyAny>, rows: usize) -> PyResult<Vec<u8>> {
    let imported = import_stream(obj)?;
    let (field, child) = if imported.schema.format == "+s" {
        (imported.schema.children.first().ok_or_else(|| fail("an empty letters frame"))?, true)
    } else {
        (&imported.schema, false)
    };
    let mut out = Vec::with_capacity(rows);
    for b in &imported.batches {
        let top = b.get();
        let (a, extra) = if child { (top.child(0).ok_or_else(|| fail("a batch lacks its column"))?, top.offset()) } else { (top, 0) };
        let n = if child { top.len() } else { a.len() };
        for i in 0..n {
            let j = a.offset() + extra + i;
            if !valid(&a, j) {
                out.push(0);
                continue;
            }
            // SAFETY: the formats say the buffers' layout.
            let text = unsafe {
                match field.dictionary.as_deref() {
                    Some(d) => {
                        let dict = a.dictionary().ok_or_else(|| fail("a dictionary array without its dictionary"))?;
                        let k = key_at(&a, &field.format, j).ok_or_else(|| fail("a bad dictionary key"))?;
                        text_at(&dict, &d.format, dict.offset() + k)
                    }
                    None if matches!(field.format.as_str(), "u" | "U" | "vu") => text_at(&a, &field.format, j),
                    None => {
                        return Err(PyTypeError::new_err(format!(
                            "the letters of column \"{name}\" are of Arrow type {}, not LETTERS or String",
                            field.format
                        )))
                    }
                }
            };
            let code = std::str::from_utf8(text).ok().and_then(missing::from_name).filter(|&c| c > missing::SYSTEM);
            out.push(code.ok_or_else(|| {
                fail(format!(
                    "the letters of column \"{name}\" hold \"{}\" in row {}, which is not one of .a to .z",
                    String::from_utf8_lossy(text),
                    out.len() + 1
                ))
            })?);
        }
    }
    if out.len() != rows {
        return Err(fail(format!(
            "the letters of column \"{name}\" have {} rows, but the frame has {rows}; carry them with letters_to_columns before changing rows, or drop them with meta.missing.pop(\"{name}\")",
            out.len()
        )));
    }
    Ok(out)
}

/// Seconds since 1970 as the core's writer makes them from microseconds.
fn seconds_of(us: i64) -> f64 {
    if us.unsigned_abs() <= 1 << 53 {
        us as f64 / 1e6
    } else {
        (us / 1_000_000) as f64 + (us % 1_000_000) as f64 / 1e6
    }
}

/// A polars dtype's name for an Arrow format, for errors.
fn dtype_of(format: &str) -> String {
    match format {
        f if f.starts_with("d:") => "Decimal".into(),
        f if f.starts_with("tD") => "Duration".into(),
        "+l" | "+L" | "+vl" | "+vL" => "List".into(),
        f if f.starts_with("+w") => "Array".into(),
        "+s" => "Struct".into(),
        "e" => "Float16".into(),
        f => format!("Arrow type {f}"),
    }
}

/// The value label sets of `meta`: {name: {code: text}}, a code an int,
/// a float or `.`/`.a`-`.z` as text.
fn label_sets(sets: &Bound<'_, PyDict>) -> PyResult<Vec<ValueLabelSet>> {
    const MAX_EXACT: f64 = 9_007_199_254_740_992.0;
    let mut out = Vec::with_capacity(sets.len());
    for (name, table) in sets.iter() {
        let name: String = name.extract()?;
        let table = table.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err(format!("value label set \"{name}\" is not a dict")))?;
        let mut labels = Vec::with_capacity(table.len());
        for (code, text) in table.iter() {
            let text: String = text.extract().map_err(|_| PyTypeError::new_err(format!("value label set \"{name}\": a label is not text")))?;
            let label = if let Ok(s) = code.cast::<PyString>() {
                let s = s.to_str()?;
                let m = missing::from_name(s).ok_or_else(|| fail(format!("value label set \"{name}\": the code \"{s}\" is not . or .a to .z")))?;
                ValueLabel { value: f64::NAN, missing: m, text }
            } else {
                let v: f64 = code.extract().map_err(|_| PyTypeError::new_err(format!("value label set \"{name}\": a code is not a number or a missing code")))?;
                if !v.is_finite() || (v.fract() == 0.0 && v.abs() > MAX_EXACT) {
                    return Err(fail(format!("value label set \"{name}\": the code {v} is not finite or beyond ±2^53")));
                }
                ValueLabel { value: v, missing: 0, text }
            };
            labels.push(label);
        }
        out.push(ValueLabelSet { name, labels });
    }
    Ok(out)
}

/// Write the polars frame `df` (any object with `__arrow_c_stream__`) as
/// Parquet to `path`, or return the file as `bytes` when `path` is None.
/// `meta` is None or a dict: label, notes, characteristics {variable:
/// {name: text}}, sort, timestamp, columns {name: (label, format,
/// value_labels, ordered)}, value_labels {set: {code: text}}, and missing
/// {name: Series of `.a` to `.z` or null}. For datakit only.
#[pyfunction]
#[pyo3(signature = (df, path, meta, compression="snappy", compression_level=None, row_group_size=None, missing_letters=true, timestamps="error", threads=0))]
#[allow(clippy::too_many_arguments)]
pub fn parquet_write_arrow<'py>(
    py: Python<'py>,
    df: &Bound<'py, PyAny>,
    path: Option<String>,
    meta: Option<&Bound<'py, PyDict>>,
    compression: &str,
    compression_level: Option<i32>,
    row_group_size: Option<usize>,
    missing_letters: bool,
    timestamps: &str,
    threads: usize,
) -> PyResult<Option<Bound<'py, PyBytes>>> {
    let mode = Stamps::from_name(timestamps)?;
    let compression = Compression::from_name(compression).map_err(fail)?;
    let options = WriteOptions { compression, compression_level, row_group_rows: row_group_size, missing_letters, threads, ..WriteOptions::default() };
    let imported = import_stream(df)?;
    let rows = height(&imported);
    let cols = columns(&imported)?;
    let get = |k: &str| -> PyResult<Option<Bound<'py, PyAny>>> {
        match meta {
            Some(m) => Ok(m.get_item(k)?.filter(|v| !v.is_none())),
            None => Ok(None),
        }
    };
    // The letters of each column that has some, checked: only on nulls.
    let mut letters: Vec<Option<Vec<u8>>> = cols.iter().map(|_| None).collect();
    if let Some(m) = get("missing")? {
        let m = m.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.missing is not a dict"))?;
        for (name, series) in m.iter() {
            let name: String = name.extract()?;
            let Some(k) = cols.iter().position(|c| c.field.name == name) else { continue };
            if !missing_letters {
                continue;
            }
            let codes = letter_codes(&name, &series, rows)?;
            if !codes.iter().any(|&c| c != 0) {
                continue;
            }
            if let Some(r) = codes.iter().enumerate().position(|(r, &c)| c != 0 && cols[k].is_valid(r)) {
                return Err(fail(format!(
                    "column \"{name}\": row {} holds a value and the letter {}; set one of them to null",
                    r + 1,
                    missing::name(codes[r]).unwrap_or_default()
                )));
            }
            letters[k] = Some(codes);
        }
    }
    // Datetimes with letters are written as seconds in doubles: whole
    // microseconds only, and only as far from 1970 as a double holds them.
    let mut micros: Vec<Option<Vec<i64>>> = cols.iter().map(|_| None).collect();
    for (k, c) in cols.iter().enumerate() {
        let f = c.field.format.as_str();
        if letters[k].is_none() || !f.starts_with("ts") {
            continue;
        }
        let per_us: i64 = match f.as_bytes().get(2) {
            Some(b's') => -1_000_000,
            Some(b'm') => -1_000,
            Some(b'u') => 1,
            _ => 1_000,
        };
        let mut out = vec![0i64; rows];
        let mut kk = 0;
        for (r, o) in out.iter_mut().enumerate() {
            kk = c.seek(kk, r);
            let (chunk, j) = c.at(kk, r);
            if !valid(&chunk.a, j) {
                continue;
            }
            let v: i64 = value(chunk, j);
            let us = if per_us < 0 {
                v.checked_mul(-per_us)
            } else if v % per_us != 0 && mode == Stamps::Error {
                return Err(fail(format!(
                    "column \"{}\", row {}: the timestamp has a part below a microsecond, which a column with .a to .z (written as seconds) cannot hold; pass timestamps=\"truncate\" to drop it",
                    c.field.name,
                    r + 1
                )));
            } else {
                Some(v.div_euclid(per_us))
            };
            let us = us.filter(|&us| {
                let x = seconds_of(us);
                let back = (x * 1e6).round();
                back == us as f64 && back / 1e6 == x
            });
            *o = us.ok_or_else(|| {
                fail(format!(
                    "column \"{}\", row {}: the timestamp is too far from 1970 for seconds in a double to hold its microseconds, which a column with .a to .z needs",
                    c.field.name,
                    r + 1
                ))
            })?;
        }
        micros[k] = Some(out);
    }
    // The profile.
    let mut p = Profile::default();
    if meta.is_some() {
        p.label = get("label")?.map(|v| v.extract()).transpose()?;
        p.timestamp = get("timestamp")?.map(|v| v.extract()).transpose()?;
        p.notes = get("notes")?.map(|v| v.extract()).transpose()?.unwrap_or_default();
        p.sort = get("sort")?.map(|v| v.extract()).transpose()?.unwrap_or_default();
        if let Some(chars) = get("characteristics")? {
            let chars = chars.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.characteristics is not a dict"))?;
            for (var, entries) in chars.iter() {
                let variable: String = var.extract()?;
                let entries = entries.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("a characteristics entry is not a dict"))?;
                for (name, value) in entries.iter() {
                    p.characteristics.push(Characteristic { variable: variable.clone(), name: name.extract()?, value: value.extract()? });
                }
            }
        }
        if let Some(sets) = get("value_labels")? {
            let sets = sets.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.value_labels is not a dict"))?;
            p.value_labels = label_sets(&sets)?;
        }
    }
    let entries: Option<Bound<'py, PyDict>> = match get("columns")? {
        Some(c) => Some(c.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.columns is not a dict"))?),
        None => None,
    };
    let mut ordered_of: HashMap<String, bool> = HashMap::new();
    if let Some(entries) = &entries {
        for c in &cols {
            let name = &c.field.name;
            let Some(e) = entries.get_item(name)? else { continue };
            type Entry = (Option<String>, Option<String>, Option<String>, Option<bool>);
            let (label, format, set, ordered): Entry = e.extract()?;
            let is_cat = c.field.dictionary.is_some();
            let set = if is_cat { None } else { set };
            if let Some(s) = &set {
                if !p.value_labels.iter().any(|v| &v.name == s) {
                    return Err(PyKeyError::new_err(format!(
                        "column \"{name}\" names the value label set \"{s}\", which meta.value_labels does not have"
                    )));
                }
            }
            if let Some(o) = ordered {
                ordered_of.insert(name.clone(), o);
            }
            p.columns.push(ColumnProfile { name: name.clone(), label, format, value_labels: set, ..ColumnProfile::default() });
        }
    }
    // The columns.
    let mut out = Vec::with_capacity(cols.len());
    let mut has_letters = Vec::with_capacity(cols.len());
    for (k, c) in cols.iter().enumerate() {
        let name = c.field.name.clone();
        let f = c.field.format.as_str();
        let l = letters[k].as_deref();
        let refuse = |what: &str| -> PyResult<()> {
            if l.is_some() {
                return Err(fail(format!("column \"{name}\" is {what} and has .a to .z, which {what} cannot hold; {}", match what {
                    "an Enum or Categorical" => "save it as .dta, drop its letters (meta.missing.pop), or read without factors",
                    _ => "drop its letters or cast it",
                })));
            }
            Ok(())
        };
        let values = if c.field.dictionary.is_some() {
            refuse("an Enum or Categorical")?;
            let every = c.field.meta("_PL_ENUM_VALUES2").is_some() || c.field.meta("_PL_ENUM_VALUES").is_some();
            let (levels, maps) = categorical(&name, c, every)?;
            let kf = c.field.format.clone();
            let col = c;
            Values::Categorical {
                levels,
                ordered: ordered_of.get(&name).copied().unwrap_or(false),
                codes: Box::new(move |first, out: &mut [i32]| {
                    if col.chunks.is_empty() {
                        out.fill(-1);
                        return;
                    }
                    let mut kk = col.find(first);
                    for (i, o) in out.iter_mut().enumerate() {
                        let r = first + i;
                        kk = col.seek(kk, r);
                        let (chunk, j) = col.at(kk, r);
                        *o = if valid(&chunk.a, j) {
                            // SAFETY: keys of the field's format.
                            unsafe { key_at(&chunk.a, &kf, j) }.and_then(|key| maps[kk].get(key).copied()).unwrap_or(-1)
                        } else {
                            -1
                        };
                    }
                }),
            }
        } else {
            match f {
                "c" => Values::Int8(numbers(c, l, |ch, j| i32::from(value::<i8>(ch, j)))),
                "s" => Values::Int16(numbers(c, l, |ch, j| i32::from(value::<i16>(ch, j)))),
                "i" => Values::Int32(numbers(c, l, value::<i32>)),
                "l" => {
                    refuse("Int64")?;
                    Values::Int64(numbers(c, l, value::<i64>))
                }
                "C" => {
                    refuse("UInt8")?;
                    Values::UInt8(numbers(c, l, |ch, j| u32::from(value::<u8>(ch, j))))
                }
                "S" => {
                    refuse("UInt16")?;
                    Values::UInt16(numbers(c, l, |ch, j| u32::from(value::<u16>(ch, j))))
                }
                "I" => {
                    refuse("UInt32")?;
                    Values::UInt32(numbers(c, l, value::<u32>))
                }
                "L" => {
                    refuse("UInt64")?;
                    Values::UInt64(numbers(c, l, value::<u64>))
                }
                "f" => Values::Float(numbers(c, l, value::<f32>)),
                "g" => Values::Double(numbers(c, l, value::<f64>)),
                "b" => {
                    refuse("Boolean")?;
                    Values::Bool(numbers(c, l, bit))
                }
                "tdD" => Values::Date(numbers(c, l, value::<i32>)),
                "ttn" | "ttu" => {
                    refuse("Time")?;
                    let scale = if f == "ttu" { 1_000 } else { 1 };
                    Values::Time(numbers(c, l, move |ch, j| value::<i64>(ch, j) * scale))
                }
                "tts" | "ttm" => {
                    refuse("Time")?;
                    let scale = if f == "tts" { 1_000_000_000 } else { 1_000_000 };
                    Values::Time(numbers(c, l, move |ch, j| i64::from(value::<i32>(ch, j)) * scale))
                }
                f if f.starts_with("ts") => {
                    let zone = f.split_once(':').map(|(_, z)| z.to_string()).filter(|z| !z.is_empty());
                    let utc = zone.is_some();
                    match micros[k].as_deref() {
                        Some(us) => Values::Timestamp {
                            unit: TimeUnit::Micros,
                            utc,
                            zone,
                            fill: numbers(c, l, move |ch, j| us[ch.start + j - ch.off]),
                        },
                        None => {
                            let (unit, scale) = match f.as_bytes()[2] {
                                b's' => (TimeUnit::Millis, 1_000),
                                b'm' => (TimeUnit::Millis, 1),
                                b'u' => (TimeUnit::Micros, 1),
                                _ => (TimeUnit::Nanos, 1),
                            };
                            Values::Timestamp { unit, utc, zone, fill: numbers(c, l, move |ch, j| value::<i64>(ch, j) * scale) }
                        }
                    }
                }
                "u" | "U" | "vu" => {
                    refuse("String")?;
                    Values::Text(texts(c, f))
                }
                "z" | "Z" | "vz" => {
                    refuse("Binary")?;
                    Values::Binary(texts(c, f))
                }
                // An all-null column (pl.lit(None)), as Stata's `gen x = .`.
                "n" => Values::Double(Box::new(|_, out: &mut [f64], codes: &mut [u8]| {
                    out.fill(0.0);
                    codes.fill(missing::SYSTEM);
                })),
                other => {
                    let dtype = dtype_of(other);
                    let to = if dtype == "Decimal" { "Float64 or String" } else { "a type save_parquet writes" };
                    return Err(PyTypeError::new_err(format!(
                        "column \"{name}\" is {dtype}, which save_parquet does not write; cast it to {to}"
                    )));
                }
            }
        };
        has_letters.push(Some(l.is_some()));
        out.push(WriteColumn { name, values });
    }
    let table = Table { rows, columns: out, profile: p };
    let result = py.detach(|| -> Result<Option<Vec<u8>>, String> {
        match &path {
            None => {
                let mut buf = Vec::new();
                dta_parquet::write_with_letters(&table, &mut buf, &options, &has_letters).map_err(|e| e.to_string())?;
                Ok(Some(buf))
            }
            Some(path) => {
                let (tmp, file) = create_beside(path).map_err(|e| format!("{path}: {e}"))?;
                let w = std::io::BufWriter::with_capacity(1 << 20, file);
                if let Err(e) = dta_parquet::write_with_letters(&table, w, &options, &has_letters) {
                    let _ = std::fs::remove_file(&tmp);
                    return Err(e.to_string());
                }
                std::fs::rename(&tmp, path).map_err(|e| {
                    let _ = std::fs::remove_file(&tmp);
                    format!("{path}: {e}")
                })?;
                Ok(None)
            }
        }
    });
    drop(table);
    drop(cols);
    drop(imported);
    match result {
        Ok(Some(buf)) => Ok(Some(PyBytes::new(py, &buf))),
        Ok(None) => Ok(None),
        Err(e) => Err(PyValueError::new_err(e)),
    }
}
