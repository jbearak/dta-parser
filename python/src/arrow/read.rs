//! A Parquet read into Arrow memory that polars adopts (plan 0019, "How
//! the frame is built"): `parquet_read_arrow`, for datakit only.
//!
//! Every column's buffers are laid out in one zeroed allocation, filled
//! by the core's Arrow outputs on its worker threads, finished here
//! (booleans packed to bits, days and seconds held as doubles made dates
//! and timestamps, times made nanoseconds, categorical keys narrowed to
//! polars' width), and handed over through `__arrow_c_stream__` with no
//! copy. `.a` to `.z` come back as a second table of `LETTERS` columns.

use std::sync::Arc;
use std::time::Instant;

use pyo3::prelude::*;
use pyo3::types::{PyDict, PyList, PyString, PyTuple};

use dta_parquet::format::TimeUnit;
use dta_parquet::{ArrowData, ArrowOutput, ColumnType, Logical, Nested, Output, ReadOptions, Storage, TextChunk};

use super::ffi::{self, Array, ArrowTable, Block, Field, Plan, Table, DICTIONARY_ORDERED};
use crate::fail;
use crate::parquet::{entries, kind_of, no_nulls, read_error, select, unit_code, with_reader_for, Access, Kind};

/// The thread rule of Arrow reads (plan 0019, step 3): one thread per
/// this many bytes decoded, at least `ARROW_THREADS`, at most
/// `ARROW_THREADS_MOST` (and never more than the machine's cores).
pub(crate) const ARROW_BYTES_PER_THREAD: u64 = 8 << 20;
pub(crate) const ARROW_THREADS: usize = 1;
pub(crate) const ARROW_THREADS_MOST: usize = 16;
/// Reads of fewer bytes than this stay on one thread.
pub(crate) const ARROW_PARALLEL_BYTES: u64 = 256 << 10;

/// polars' Enum of `.a` to `.z` (datakit's `LETTERS`).
pub(crate) fn letter_names() -> Vec<String> {
    (b'a'..=b'z').map(|c| format!(".{}", c as char)).collect()
}

/// The field metadata that makes polars import a dictionary array as
/// `Enum(levels)` (polars 2's own export writes it; not a documented
/// interface, so a test checks polars still honours it).
pub(crate) fn enum_metadata(levels: &[String]) -> Vec<u8> {
    let mut v = Vec::new();
    for l in levels {
        v.extend_from_slice(l.len().to_string().as_bytes());
        v.push(b';');
        v.extend_from_slice(l.as_bytes());
    }
    ffi::metadata(&[("_PL_ENUM_VALUES2", &v)])
}

/// The key width polars gives an Enum of `n` levels.
pub(crate) fn key_width(n: usize) -> usize {
    if n <= 1 << 8 {
        1
    } else if n <= 1 << 16 {
        2
    } else {
        4
    }
}

pub(crate) fn key_format(width: usize) -> &'static str {
    match width {
        1 => "C",
        2 => "S",
        _ => "I",
    }
}

/// An Arrow utf8 array of `values` (for a dictionary), with its owner.
pub(crate) fn utf8_array(values: &[String]) -> Array {
    let mut offsets: Vec<i32> = Vec::with_capacity(values.len() + 1);
    let mut data = Vec::new();
    offsets.push(0);
    for v in values {
        data.extend_from_slice(v.as_bytes());
        offsets.push(data.len() as i32);
    }
    let buffers = vec![0, offsets.as_ptr() as usize, data.as_ptr() as usize];
    Array {
        length: values.len(),
        null_count: 0,
        offset: 0,
        buffers,
        children: Vec::new(),
        dictionary: None,
        owner: Some(Arc::new((offsets, data))),
    }
}

/// How dates and timestamps held as doubles that are not whole days or
/// microseconds read: an error, or truncated.
#[derive(Clone, Copy, PartialEq)]
pub(crate) enum Stamps {
    Error,
    Truncate,
}

impl Stamps {
    pub(crate) fn from_name(s: &str) -> PyResult<Self> {
        match s {
            "error" => Ok(Stamps::Error),
            "truncate" => Ok(Stamps::Truncate),
            other => Err(fail(format!("timestamps is \"error\" or \"truncate\", not \"{other}\""))),
        }
    }
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Elem {
    I8,
    I16,
    I32,
    I64,
    U8,
    U16,
    U32,
    U64,
    F32,
    F64,
    Views,
    Keys,
}

impl Elem {
    fn width(self) -> usize {
        match self {
            Elem::I8 | Elem::U8 => 1,
            Elem::I16 | Elem::U16 => 2,
            Elem::I32 | Elem::U32 | Elem::F32 | Elem::Keys => 4,
            Elem::I64 | Elem::U64 | Elem::F64 => 8,
            Elem::Views => 16,
        }
    }
}

/// What is done to a column after the read.
#[derive(Clone, PartialEq, Debug)]
enum Post {
    None,
    /// 0 and 1 bytes packed into bits.
    Bool,
    /// Days held as doubles, made Date (int32).
    Days,
    /// Seconds held as doubles, made microseconds.
    Seconds,
    /// Times made nanoseconds.
    Scale(i64),
    /// Keys narrowed to polars' width for this many levels.
    Narrow(usize),
}

struct Col {
    index: usize,
    name: String,
    elem: Elem,
    format: String,
    validity: bool,
    post: Post,
    values_at: usize,
    validity_at: usize,
    /// Booleans' value bits.
    bits_at: usize,
    /// A categorical's levels and whether ordered.
    levels: Option<(Vec<String>, bool)>,
    /// A DECIMAL read as text, every digit kept.
    decimal: Option<(u32, u32)>,
    /// For datakit: "categorical" (polars should make it Categorical),
    /// "decimal(p,s)" (cast the text to Decimal), or None.
    flag: Option<String>,
    /// A column `.a` to `.z` can be written to (plan 0019, "letters"):
    /// byte, int, long, float, double, date or timestamp in the file.
    eligible: bool,
}

/// Which polars dtype each Parquet column becomes (plan 0019's table).
/// `zone`: the profile's zone of a timestamp held as seconds (`Some("")`
/// for an instant written without one, read as UTC; `None` for a time
/// without a zone).
fn plan_column(index: usize, name: &str, kind: &Kind, may_null: bool, zone: Option<&str>) -> Col {
    let col = |elem: Elem, format: &str, validity: bool, post: Post| Col {
        index,
        name: name.to_string(),
        elem,
        format: format.to_string(),
        validity,
        post,
        values_at: 0,
        validity_at: 0,
        bits_at: 0,
        levels: None,
        decimal: None,
        flag: None,
        eligible: false,
    };
    let unit = |u: TimeUnit| match u {
        TimeUnit::Millis => 'm',
        TimeUnit::Micros => 'u',
        TimeUnit::Nanos => 'n',
    };
    let mut c = match kind {
        Kind::Int { width: 1, .. } => col(Elem::I8, "c", may_null, Post::None),
        Kind::Int { width: 2, .. } => col(Elem::I16, "s", may_null, Post::None),
        Kind::Int { .. } => col(Elem::I32, "i", may_null, Post::None),
        Kind::UInt { width: 1, .. } => col(Elem::U8, "C", may_null, Post::None),
        Kind::UInt { width: 2, .. } => col(Elem::U16, "S", may_null, Post::None),
        Kind::UInt { width: 4, .. } => col(Elem::U32, "I", may_null, Post::None),
        Kind::UInt { .. } => col(Elem::U64, "L", may_null, Post::None),
        Kind::Int64 { .. } => col(Elem::I64, "l", may_null, Post::None),
        Kind::Bool { .. } => col(Elem::U8, "b", may_null, Post::Bool),
        Kind::Float32 => col(Elem::F32, "f", may_null, Post::None),
        // A DOUBLE can hold tagged NaNs, so it always has a bitmap.
        Kind::Double { logical: Some(Logical::Date), .. } => col(Elem::F64, "tdD", true, Post::Days),
        Kind::Double { logical: Some(Logical::Timestamp), .. } => {
            let zone = match zone {
                Some("") => "UTC",
                Some(z) => z,
                None => "",
            };
            col(Elem::F64, &format!("tsu:{zone}"), true, Post::Seconds)
        }
        Kind::Double { storage: Some(Storage::Byte), .. } => col(Elem::I8, "c", true, Post::None),
        Kind::Double { storage: Some(Storage::Int), .. } => col(Elem::I16, "s", true, Post::None),
        Kind::Double { storage: Some(Storage::Long), .. } => col(Elem::I32, "i", true, Post::None),
        Kind::Double { storage: Some(Storage::Float), .. } => col(Elem::F32, "f", true, Post::None),
        Kind::Double { .. } => col(Elem::F64, "g", true, Post::None),
        Kind::DecimalFloat | Kind::DecimalText => col(Elem::Views, "vu", true, Post::None),
        Kind::Date => col(Elem::I32, "tdD", may_null, Post::None),
        Kind::Timestamp { unit: u, tz, .. } => {
            col(Elem::I64, &format!("ts{}:{}", unit(*u), tz.clone().unwrap_or_default()), may_null, Post::None)
        }
        Kind::Time { unit: u, .. } => {
            let scale = match u {
                TimeUnit::Millis => 1_000_000,
                TimeUnit::Micros => 1_000,
                TimeUnit::Nanos => 1,
            };
            col(Elem::I64, "ttn", may_null, Post::Scale(scale))
        }
        Kind::Category { levels, ordered, rows: false } => {
            let mut c = col(Elem::Keys, key_format(key_width(levels.len())), may_null, Post::Narrow(levels.len()));
            c.levels = Some((levels.clone(), *ordered));
            c
        }
        Kind::Category { rows: true, .. } => {
            let mut c = col(Elem::Views, "vu", may_null, Post::None);
            c.flag = Some("categorical".into());
            c
        }
        Kind::Text => col(Elem::Views, "vu", may_null, Post::None),
        Kind::Binary => col(Elem::Views, "vz", may_null, Post::None),
    };
    c.eligible = matches!(
        kind,
        Kind::Int { .. } | Kind::Float32 | Kind::Double { .. } | Kind::Date | Kind::Timestamp { .. }
    );
    c
}

/// # Safety
/// `addr` points at `n` elements of `T`, alive and used by nothing else
/// while the slice is.
unsafe fn slice<'a, T>(addr: usize, n: usize) -> &'a mut [T] {
    if n == 0 {
        &mut []
    } else {
        std::slice::from_raw_parts_mut(addr as *mut T, n)
    }
}

fn bit(bits: &[u8], r: usize) -> bool {
    (bits[r / 8] >> (r % 8)) & 1 == 1
}

/// A row's message: the column, the file's row (1-based), and the text.
fn at_row(name: &str, row: u64, what: &str) -> PyErr {
    fail(format!("column \"{name}\", row {row}: {what}"))
}

/// Make days held as doubles Date values, in place (`i32`s over the
/// front of the doubles' buffer).
fn days(name: &str, values: usize, bits: &[u8], rows: usize, first_row: u64, mode: Stamps) -> PyResult<()> {
    for r in 0..rows {
        // SAFETY: the buffer holds `rows` doubles; the i32 written at r
        // overlaps only doubles at r / 2 <= r, already read.
        let x = unsafe { *(values as *const f64).add(r) };
        let v = if bit(bits, r) {
            if !x.is_finite() {
                return Err(at_row(name, first_row + r as u64 + 1, &format!("{x} is not a date")));
            }
            let d = x.floor();
            if d != x && mode == Stamps::Error {
                return Err(at_row(
                    name,
                    first_row + r as u64 + 1,
                    &format!("the date {x} (days since 1970) has a fraction of a day; pass timestamps=\"truncate\" to drop it"),
                ));
            }
            if d < f64::from(i32::MIN) || d > f64::from(i32::MAX) {
                return Err(at_row(name, first_row + r as u64 + 1, &format!("the date {x} (days since 1970) is outside polars' Date range")));
            }
            d as i32
        } else {
            0
        };
        unsafe { *(values as *mut i32).add(r) = v };
    }
    Ok(())
}

/// Make seconds held as doubles microseconds, in place: a value is read
/// as the whole number of microseconds that gives it back exactly, else
/// it is an error, or truncated.
fn seconds(name: &str, values: usize, bits: &[u8], rows: usize, first_row: u64, mode: Stamps) -> PyResult<()> {
    const LIMIT: f64 = 9_223_372_036_854_775_808.0;
    for r in 0..rows {
        let x = unsafe { *(values as *const f64).add(r) };
        let v = if bit(bits, r) {
            if !x.is_finite() {
                return Err(at_row(name, first_row + r as u64 + 1, &format!("{x} is not a timestamp")));
            }
            let n = (x * 1e6).round();
            if n.abs() >= LIMIT {
                return Err(at_row(name, first_row + r as u64 + 1, &format!("the timestamp {x} (seconds since 1970) is outside polars' Datetime range")));
            }
            if n / 1e6 == x {
                n as i64
            } else if mode == Stamps::Truncate {
                (x * 1e6).floor() as i64
            } else {
                return Err(at_row(
                    name,
                    first_row + r as u64 + 1,
                    &format!("the timestamp {x} (seconds since 1970) is not a whole number of microseconds; pass timestamps=\"truncate\" to truncate it"),
                ));
            }
        } else {
            0
        };
        unsafe { *(values as *mut i64).add(r) = v };
    }
    Ok(())
}

/// A DECIMAL's text, a chunk at a time, as views.
struct DecimalViews {
    views: usize,
    validity: usize,
    long: Vec<u8>,
}

impl DecimalViews {
    fn add(&mut self, chunk: &TextChunk) {
        for r in 0..chunk.rows {
            let row = chunk.first as usize + r;
            if let Some(b) = chunk.row(r) {
                let mut v = [0u8; 16];
                v[..4].copy_from_slice(&(b.len() as u32).to_le_bytes());
                if b.len() <= 12 {
                    v[4..4 + b.len()].copy_from_slice(b);
                } else {
                    v[4..8].copy_from_slice(&b[..4]);
                    v[12..16].copy_from_slice(&(self.long.len() as u32).to_le_bytes());
                    self.long.extend_from_slice(b);
                }
                // SAFETY: the views hold the read's rows.
                unsafe {
                    *(self.views as *mut u128).add(row) = u128::from_le_bytes(v);
                    *(self.validity as *mut u8).add(row / 8) |= 1 << (row % 8);
                }
            }
        }
    }
}

/// What every column's buffers hang from.
struct Buffers {
    _block: Block,
    _text: Vec<Vec<u8>>,
}

/// Read rows `skip..skip + n_max` of `columns` (names or positions; every
/// data column when None) into Arrow memory. Returns `(frame, letters,
/// meta)`: `frame` and `letters` export Arrow streams (`letters` is None
/// when no column read holds `.a` to `.z`; its columns are the data
/// columns that do, each an Enum of `.a` to `.z`); `meta` is a dict of
/// what `Meta` is made from. For datakit only.
#[pyfunction]
#[pyo3(signature = (source, columns=None, skip=0, n_max=None, nested_skip=false, timestamps="error", threads=0, enum_metadata=true))]
#[allow(clippy::too_many_arguments)]
pub fn parquet_read_arrow<'py>(
    py: Python<'py>,
    source: &Bound<'py, PyAny>,
    columns: Option<Vec<Bound<'py, PyAny>>>,
    skip: u64,
    n_max: Option<u64>,
    nested_skip: bool,
    timestamps: &str,
    threads: usize,
    enum_metadata: bool,
) -> PyResult<Bound<'py, PyTuple>> {
    let t0 = Instant::now();
    let mode = Stamps::from_name(timestamps)?;
    let options = ReadOptions {
        threads,
        nested: if nested_skip { Nested::Skip } else { Nested::Error },
        lazy_value_labels: true,
        thread_rule: Some((ARROW_BYTES_PER_THREAD, ARROW_THREADS, ARROW_THREADS_MOST)),
        ..ReadOptions::default()
    };
    let options = ReadOptions { parallel_bytes: options.parallel_bytes.min(ARROW_PARALLEL_BYTES), ..options };
    let names: Option<Vec<String>> = columns.as_ref().and_then(|c| c.iter().map(|w| w.extract::<String>().ok()).collect());
    let names: Option<Vec<&str>> = names.as_ref().map(|n| n.iter().map(String::as_str).collect());
    with_reader_for(source, options, names.as_deref(), &mut |r| {
        read_arrow(py, r, columns.as_deref(), skip, n_max, nested_skip, mode, enum_metadata, t0)
    })
}

#[allow(clippy::too_many_arguments)]
fn read_arrow<'py>(
    py: Python<'py>,
    r: &mut dyn Access,
    wanted: Option<&[Bound<'py, PyAny>]>,
    skip: u64,
    n_max: Option<u64>,
    nested_skip: bool,
    mode: Stamps,
    enum_meta: bool,
    t0: Instant,
) -> PyResult<Bound<'py, PyTuple>> {
    let mut steps = vec![("open", t0.elapsed().as_secs_f64())];
    let t = Instant::now();
    let selected = select(r, wanted, nested_skip)?;
    let n = n_max.unwrap_or(u64::MAX);
    let window = r.window(skip, n);
    let rows = usize::try_from(window.end - window.start).map_err(|_| fail("too many rows to read at once"))?;
    let by_name = entries(r.profile());
    let meta = r.metadata();
    let infos = r.columns();
    steps.push(("setup: select", t.elapsed().as_secs_f64()));
    let mut plan = Plan::default();
    let mut cols = Vec::with_capacity(selected.len());
    for &c in &selected {
        let info = &infos[c];
        let entry = by_name.get(info.name.as_str()).copied();
        let kind = kind_of(info, entry, meta).map_err(fail)?;
        let mut col = plan_column(c, &info.name, &kind, !no_nulls(meta, info), entry.and_then(|e| e.tz.as_deref()));
        if let ColumnType::Decimal { precision, scale } = info.kind {
            col.decimal = Some((precision, scale));
            col.flag = Some(format!("decimal({precision},{scale})"));
        }
        col.values_at = plan.add(rows * col.elem.width());
        if col.validity {
            col.validity_at = plan.add(rows.div_ceil(8));
        }
        if col.post == Post::Bool {
            col.bits_at = plan.add(rows.div_ceil(8));
        }
        cols.push(col);
    }
    steps.push(("setup: kinds", t.elapsed().as_secs_f64()));
    let block = plan.block()?;
    let base = block.addr();
    steps.push(("setup: block", t.elapsed().as_secs_f64()));
    let mut outputs: Vec<Output> = Vec::with_capacity(cols.len());
    let mut decimals: Vec<Option<DecimalViews>> = Vec::with_capacity(cols.len());
    for col in &cols {
        let v = base + col.values_at;
        let validity = col.validity.then(|| unsafe { slice::<u8>(base + col.validity_at, rows.div_ceil(8)) });
        if col.decimal.is_some() {
            decimals.push(Some(DecimalViews { views: v, validity: base + col.validity_at, long: Vec::new() }));
            outputs.push(Output::Text);
            continue;
        }
        decimals.push(None);
        // SAFETY: the block holds each column's values at its offset, and
        // nothing else uses them until the read returns.
        let data = unsafe {
            match col.elem {
                Elem::I8 => ArrowData::Int8(slice(v, rows)),
                Elem::I16 => ArrowData::Int16(slice(v, rows)),
                Elem::I32 => ArrowData::Int32(slice(v, rows)),
                Elem::I64 => ArrowData::Int64(slice(v, rows)),
                Elem::U8 => ArrowData::UInt8(slice(v, rows)),
                Elem::U16 => ArrowData::UInt16(slice(v, rows)),
                Elem::U32 => ArrowData::UInt32(slice(v, rows)),
                Elem::U64 => ArrowData::UInt64(slice(v, rows)),
                Elem::F32 => ArrowData::Float32(slice(v, rows)),
                Elem::F64 => ArrowData::Float64(slice(v, rows)),
                Elem::Views => ArrowData::Views(slice(v, rows)),
                Elem::Keys => ArrowData::Keys(slice(v, rows)),
            }
        };
        outputs.push(Output::Arrow(ArrowOutput { validity, data }));
    }
    let ix: Vec<usize> = cols.iter().map(|c| c.index).collect();
    let decimal_names: Vec<String> =
        cols.iter().filter(|c| c.decimal.is_some()).map(|c| format!("column \"{}\":", c.name)).collect();
    drop(by_name);
    steps.push(("setup", t.elapsed().as_secs_f64()));

    let t = Instant::now();
    let report = py.detach(|| {
        let mut text = |k: usize, chunk: &TextChunk| -> dta::Result<()> {
            match decimals[k].as_mut() {
                Some(d) => {
                    d.add(chunk);
                    Ok(())
                }
                None => Err(dta::Error::new("internal: text for a column that is not text")),
            }
        };
        r.read(&ix, skip, n, &mut outputs, &mut text)
    });
    drop(outputs);
    let mut report = report.map_err(|e| fail(read_error(e.to_string(), &decimal_names)))?;
    steps.push(("read", t.elapsed().as_secs_f64()));

    // Finish each column, and make its Arrow array.
    let t = Instant::now();
    let mut text_buffers: Vec<Vec<u8>> = Vec::new();
    // (column, buffer indices into text_buffers)
    let mut col_text: Vec<Vec<usize>> = vec![Vec::new(); cols.len()];
    let mut nulls: Vec<usize> = vec![0; cols.len()];
    let mut letters: Vec<(usize, Vec<(u64, u8)>)> = Vec::new();
    for (k, col) in cols.iter().enumerate() {
        let bits = if col.validity { unsafe { slice::<u8>(base + col.validity_at, rows.div_ceil(8)) } } else { &mut [][..] };
        if let Some(d) = decimals[k].take() {
            nulls[k] = rows - bits.iter().map(|b| b.count_ones() as usize).sum::<usize>();
            if !d.long.is_empty() {
                col_text[k].push(text_buffers.len());
                text_buffers.push(d.long);
            }
            continue;
        }
        let a = report.arrow[k].as_mut().expect("an Arrow report per Arrow column");
        nulls[k] = a.nulls as usize;
        for b in a.buffers.drain(..) {
            col_text[k].push(text_buffers.len());
            text_buffers.push(b);
        }
        if !a.letters.is_empty() {
            letters.push((k, std::mem::take(&mut a.letters)));
        }
        let first_row = window.start;
        let v = base + col.values_at;
        match &col.post {
            Post::None => {}
            Post::Bool => {
                let src = unsafe { slice::<u8>(v, rows) };
                let dst = unsafe { slice::<u8>(base + col.bits_at, rows.div_ceil(8)) };
                for (i, &b) in src.iter().enumerate() {
                    dst[i / 8] |= (b & 1) << (i % 8);
                }
            }
            Post::Days => days(&col.name, v, bits, rows, first_row, mode)?,
            Post::Seconds => seconds(&col.name, v, bits, rows, first_row, mode)?,
            Post::Scale(s) if *s != 1 => {
                for x in unsafe { slice::<i64>(v, rows) } {
                    *x *= *s;
                }
            }
            Post::Scale(_) => {}
            Post::Narrow(n) => {
                let w = key_width(*n);
                let keys = v as *mut u32;
                for i in 0..rows {
                    // SAFETY: forward compaction: the narrower key at i
                    // overlaps only keys at indices <= i, already read.
                    unsafe {
                        let x = *keys.add(i);
                        match w {
                            1 => *(v as *mut u8).add(i) = x as u8,
                            2 => *(v as *mut u16).add(i) = x as u16,
                            _ => {}
                        }
                    }
                }
            }
        }
    }
    let sizes: Vec<Vec<i64>> = col_text
        .iter()
        .map(|ids| ids.iter().map(|&i| text_buffers[i].len() as i64).collect())
        .collect();
    let text_addr: Vec<usize> = text_buffers.iter().map(|b| b.as_ptr() as usize).collect();
    let sizes_addr: Vec<usize> = sizes.iter().map(|s| s.as_ptr() as usize).collect();
    let owner: ffi::Owner = Arc::new((Buffers { _block: block, _text: text_buffers }, sizes));
    let mut fields = Vec::with_capacity(cols.len());
    let mut arrays = Vec::with_capacity(cols.len());
    for (k, col) in cols.iter().enumerate() {
        let validity = if col.validity && nulls[k] > 0 { base + col.validity_at } else { 0 };
        let values = if col.post == Post::Bool { base + col.bits_at } else { base + col.values_at };
        let mut buffers = vec![validity, values];
        if col.elem == Elem::Views {
            buffers.extend(col_text[k].iter().map(|&i| text_addr[i]));
            buffers.push(sizes_addr[k]);
        }
        let mut field = Field::new(&col.name, &col.format);
        let mut dictionary = None;
        if let Some((levels, _)) = &col.levels {
            field.dictionary = Some(Box::new(Field::new("", "u")));
            field.flags |= DICTIONARY_ORDERED;
            if enum_meta {
                field.metadata = Some(enum_metadata(levels));
            }
            dictionary = Some(Box::new(utf8_array(levels)));
        }
        fields.push(field);
        arrays.push(Array {
            length: rows,
            null_count: nulls[k],
            offset: 0,
            buffers,
            children: Vec::new(),
            dictionary,
            owner: Some(owner.clone()),
        });
    }
    let frame = ArrowTable {
        table: Table {
            fields,
            batches: vec![Array { length: rows, null_count: 0, offset: 0, buffers: vec![0], children: arrays, dictionary: None, owner: None }],
        },
    };
    let letters_table = letters_table(&cols.iter().map(|c| c.name.clone()).collect::<Vec<_>>(), &letters, rows)?;
    steps.push(("finish", t.elapsed().as_secs_f64()));

    let t = Instant::now();
    let names: Vec<&str> = cols.iter().map(|c| c.name.as_str()).collect();
    let out = meta_dict(py, r, &cols, &names, rows)?;
    out.set_item("letter_columns", letters.iter().map(|(k, _)| cols[*k].name.as_str()).collect::<Vec<_>>())?;
    steps.push(("meta", t.elapsed().as_secs_f64()));
    out.set_item("steps", steps)?;
    let letters_obj: Option<Py<ArrowTable>> = match letters_table {
        Some(t) => Some(Py::new(py, t)?),
        None => None,
    };
    PyTuple::new(py, [Py::new(py, frame)?.into_any(), letters_obj.map_or_else(|| py.None(), Py::into_any), out.into_any().unbind()])
}

/// The `.a` to `.z` of each column holding any, as a table of Enum
/// columns (`LETTERS`), null where a row has none.
pub(crate) fn letters_table(names: &[String], letters: &[(usize, Vec<(u64, u8)>)], rows: usize) -> PyResult<Option<ArrowTable>> {
    if letters.is_empty() {
        return Ok(None);
    }
    let mut plan = Plan::default();
    let at: Vec<(usize, usize)> = letters.iter().map(|_| (plan.add(rows), plan.add(rows.div_ceil(8)))).collect();
    let block = plan.block()?;
    let base = block.addr();
    let levels = letter_names();
    let dict = utf8_array(&levels);
    let owner: ffi::Owner = Arc::new(block);
    let meta = enum_metadata(&levels);
    let mut fields = Vec::new();
    let mut arrays = Vec::new();
    for ((k, list), &(keys_at, bits_at)) in letters.iter().zip(&at) {
        let keys = unsafe { slice::<u8>(base + keys_at, rows) };
        let bits = unsafe { slice::<u8>(base + bits_at, rows.div_ceil(8)) };
        for &(r, code) in list {
            let r = r as usize;
            keys[r] = code - 2;
            bits[r / 8] |= 1 << (r % 8);
        }
        let mut f = Field::new(&names[*k], "C");
        f.dictionary = Some(Box::new(Field::new("", "u")));
        f.flags |= DICTIONARY_ORDERED;
        f.metadata = Some(meta.clone());
        fields.push(f);
        arrays.push(Array {
            length: rows,
            null_count: rows - list.len(),
            offset: 0,
            buffers: vec![base + bits_at, base + keys_at],
            children: Vec::new(),
            dictionary: Some(Box::new(dict.clone())),
            owner: Some(owner.clone()),
        });
    }
    Ok(Some(ArrowTable {
        table: Table {
            fields,
            batches: vec![Array { length: rows, null_count: 0, offset: 0, buffers: vec![0], children: arrays, dictionary: None, owner: None }],
        },
    }))
}

/// A value label code as datakit keys it: an int where whole, else a
/// float; `.` and `.a` to `.z` as text.
pub(crate) fn label_key<'py>(py: Python<'py>, value: f64, missing: u8) -> PyResult<Bound<'py, PyAny>> {
    Ok(if missing != 0 {
        PyString::new(py, &dta::missing::name(missing).unwrap_or_else(|| ".".into())).into_any()
    } else if value.fract() == 0.0 && value.abs() < 9.0e15 {
        (value as i64).into_pyobject(py)?.into_any()
    } else {
        value.into_pyobject(py)?.into_any()
    })
}

/// The value label sets as {name: {code: text}}.
pub(crate) fn label_sets<'py>(py: Python<'py>, sets: &[dta::ValueLabelSet]) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    for set in sets {
        let d = PyDict::new(py);
        for l in &set.labels {
            d.set_item(label_key(py, l.value, l.missing)?, &l.text)?;
        }
        out.set_item(&set.name, d)?;
    }
    Ok(out)
}

/// One value-label set's JSON, `[[code, "text"], ...]`, straight into a
/// dict, for the common case: numbers or `.`/`.a`-`.z` as codes, text
/// without escapes, no code twice. `None` for anything else, which the
/// core's parser then reads (and warns about, as it would have).
fn fast_set<'py>(py: Python<'py>, json: &[u8]) -> PyResult<Option<Bound<'py, PyDict>>> {
    const EXACT: f64 = 9_007_199_254_740_992.0;
    let out = PyDict::new(py);
    let mut at = 0usize;
    let ws = |at: &mut usize| {
        while json.get(*at).is_some_and(|b| matches!(b, b' ' | b'\t' | b'\n' | b'\r')) {
            *at += 1;
        }
    };
    let eat = |at: &mut usize, c: u8| -> bool {
        ws(at);
        if json.get(*at) == Some(&c) {
            *at += 1;
            true
        } else {
            false
        }
    };
    // A string without escapes or control characters, as its text.
    let string = |at: &mut usize| -> Option<&str> {
        if !eat(at, b'"') {
            return None;
        }
        let start = *at;
        let n = json[start..].iter().position(|&b| b == b'"' || b == b'\\' || b < 0x20)?;
        if json[start + n] != b'"' {
            return None;
        }
        *at = start + n + 1;
        std::str::from_utf8(&json[start..start + n]).ok()
    };
    if !eat(&mut at, b'[') {
        return Ok(None);
    }
    let mut pairs = 0usize;
    if !eat(&mut at, b']') {
        loop {
            if !eat(&mut at, b'[') {
                return Ok(None);
            }
            ws(&mut at);
            let key: Bound<'py, PyAny> = if json.get(at) == Some(&b'"') {
                let Some(code) = string(&mut at) else { return Ok(None) };
                if dta::missing::from_name(code).is_none() {
                    return Ok(None);
                }
                PyString::new(py, code).into_any()
            } else {
                let start = at;
                while json.get(at).is_some_and(|b| matches!(b, b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9')) {
                    at += 1;
                }
                let text = std::str::from_utf8(&json[start..at]).unwrap_or("");
                match text.parse::<i64>() {
                    Ok(v) if v.unsigned_abs() < 9_000_000_000_000_000 => v.into_pyobject(py)?.into_any(),
                    _ => match text.parse::<f64>() {
                        Ok(v) if v.is_finite() && !(v.fract() == 0.0 && v.abs() > EXACT) => label_key(py, v, 0)?,
                        _ => return Ok(None),
                    },
                }
            };
            if !eat(&mut at, b',') {
                return Ok(None);
            }
            let Some(text) = string(&mut at) else { return Ok(None) };
            if !eat(&mut at, b']') {
                return Ok(None);
            }
            out.set_item(key, text)?;
            pairs += 1;
            if eat(&mut at, b']') {
                break;
            }
            if !eat(&mut at, b',') {
                return Ok(None);
            }
        }
    }
    ws(&mut at);
    Ok((at == json.len() && out.len() == pairs).then_some(out))
}

/// The profile's value-label sets as {name: {code: text}}, and a warning
/// for each set dropped: built from the profile's JSON where
/// [`fast_set`] takes a set, through the core's parser otherwise.
fn profile_label_sets<'py>(py: Python<'py>, r: &dyn Access) -> PyResult<(Bound<'py, PyDict>, Vec<String>)> {
    let read: Vec<dta::ValueLabelSet> = r.profile().map_or_else(Vec::new, |p| p.value_labels.clone());
    let out = label_sets(py, &read)?;
    let mut warnings = Vec::new();
    let (text, spans) = r.label_set_spans();
    for (name, span) in spans {
        if let Some(d) = text.get(span.clone()).map(|j| fast_set(py, j)).transpose()?.flatten() {
            out.set_item(name, d)?;
            continue;
        }
        match dta_parquet::Profile::parse_label_set(text, name, span.clone()) {
            Ok(set) => out.set_item(name, label_sets(py, std::slice::from_ref(&set))?.get_item(name)?)?,
            Err(w) => warnings.push(w),
        }
    }
    Ok((out, warnings))
}

/// What `Meta` is made from: rows, names, columns [(name, label, format,
/// value_labels, ordered, storage, flag, eligible)], value_labels, label,
/// notes, characteristics {variable: {name: text}}, sort, timestamp and
/// warnings.
fn meta_dict<'py>(py: Python<'py>, r: &dyn Access, cols: &[Col], names: &[&str], rows: usize) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    out.set_item("rows", rows)?;
    out.set_item("names", names)?;
    let p = r.profile();
    let by_name = entries(p);
    let infos = r.columns();
    let list = PyList::empty(py);
    for c in cols {
        let e = by_name.get(c.name.as_str()).copied();
        list.append((
            &c.name,
            e.and_then(|e| e.label.as_deref()),
            e.and_then(|e| e.format.as_deref()),
            e.and_then(|e| e.value_labels.as_deref()),
            c.levels.as_ref().map(|(_, o)| *o),
            infos[c.index].storage.map(|s| s.name()),
            c.flag.as_deref(),
            c.eligible,
        ))?;
    }
    out.set_item("columns", list)?;
    let (sets, mut warnings) = profile_label_sets(py, r)?;
    out.set_item("value_labels", sets)?;
    out.set_item("label", p.and_then(|p| p.label.as_deref()))?;
    out.set_item("notes", p.map_or(&[][..], |p| p.notes.as_slice()))?;
    let chars = PyDict::new(py);
    for c in p.map_or(&[][..], |p| p.characteristics.as_slice()) {
        let d = match chars.get_item(&c.variable)? {
            Some(d) => d.cast_into::<PyDict>()?,
            None => {
                let d = PyDict::new(py);
                chars.set_item(&c.variable, &d)?;
                d
            }
        };
        d.set_item(&c.name, &c.value)?;
    }
    out.set_item("characteristics", chars)?;
    out.set_item("sort", p.map_or(&[][..], |p| p.sort.as_slice()))?;
    out.set_item("timestamp", p.and_then(|p| p.timestamp.as_deref()))?;
    let mut all = r.warnings().to_vec();
    all.append(&mut warnings);
    out.set_item("warnings", all)?;
    let _ = unit_code;
    Ok(out)
}
