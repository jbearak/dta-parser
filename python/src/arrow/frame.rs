//! Columns between the native reads and writers and pandas (plan 0024,
//! stage 4), for datakit only.
//!
//! **Reads.** `parquet_read_columns` and `dta_read_columns` return a
//! [`NativeFrame`]: each column's buffers in the read's one allocation.
//! `NativeFrame.take` converts each column once, into what a pandas
//! column is made of, and hands every buffer over as a [`Buffer`], which
//! numpy adopts without a copy:
//!
//! - a numeric column with no missing value, a timestamp or time, and a
//!   BOOLEAN: its buffer as it is (a null of a timestamp or time made
//!   `NaT`, int64's minimum, in place);
//! - a byte, int, long, float or double column with a missing value (a
//!   null, a NaN, `.a` to `.z`): float64 values and a uint8 code per row,
//!   a `DtaArray`; a double column's values in place, the others new;
//! - a date, timestamp or categorical holding `.a` to `.z` (when letters
//!   are read): Stata's days or milliseconds since 1960, or its level
//!   numbers, with codes;
//! - INT64, unsigned and BOOLEAN with nulls: the values and a new mask;
//! - DATE: new int64 seconds, `NaT` for a null;
//! - a categorical: its keys made pandas' signed codes in place, -1 for
//!   a null;
//! - text: a `str` (or `bytes`) per row, put in an object array Python
//!   made.
//!
//! The frame is taken once, so no two pandas frames share a buffer, and
//! the native side never reads a buffer after handing it out.
//!
//! **Writes.** [`build`] takes, per column, numpy arrays (values, a mask,
//! letter codes) or an object array of text, checks each array's type,
//! length, layout and alignment from its `__array_interface__`, and
//! builds over them the Arrow arrays the writers read (`write.rs`,
//! `dta.rs`), copying only what Arrow lays out otherwise: validity and
//! booleans as bits, text as offsets and bytes, a categorical's levels.

use std::ffi::{c_char, c_void};
use std::ptr::{null, null_mut};
use std::sync::{Arc, Mutex};

use pyo3::exceptions::{PyTypeError, PyValueError};
use pyo3::ffi;
use pyo3::prelude::*;
use pyo3::types::{PyDict, PyList, PyTuple};

use super::ffi::{typestr, ArrowArray, Buffer, InArray, InField, Imported, Owner, EVERY_LEVEL};
use crate::{fail, Recent};

/// Days from 1960-01-01 (Stata's epoch) to 1970-01-01.
const EPOCH_DAYS: i64 = 3653;
const DAY_SECONDS: i64 = 86_400;
const MS_1960: f64 = (EPOCH_DAYS * DAY_SECONDS * 1000) as f64;

/// One column of a read, in the read's memory.
pub(crate) struct NativeColumn {
    pub(crate) name: String,
    /// The Arrow format of the values: `c`, `s`, `i`, `l`, `C`, `S`,
    /// `I`, `L`, `f`, `g`; `b` (a byte per row); `tdD` (int32 days since
    /// 1970); `ts{unit}:{zone}`; `ttn`; `vu` or `vz` (string views). A
    /// categorical has `levels`: its keys are `I` (uint32), or `g` for
    /// level numbers held as doubles (one that may hold `.a` to `.z`).
    pub(crate) format: String,
    /// The validity bitmap's address, 0 when every row is valid.
    pub(crate) validity: usize,
    pub(crate) nulls: usize,
    pub(crate) values: usize,
    /// String views' data buffers.
    pub(crate) text: Vec<usize>,
    pub(crate) levels: Option<(Vec<String>, bool)>,
    /// `.a` to `.z`: (row, code 2 to 27), by row; their rows are null.
    pub(crate) letters: Vec<(u64, u8)>,
    /// The storage type a date or timestamp holding letters keeps as a
    /// `DtaArray` (a `.dta` column's own); "double" when None.
    pub(crate) storage: Option<&'static str>,
}

impl NativeColumn {
    pub(crate) fn new(name: &str, format: &str, values: usize) -> Self {
        NativeColumn {
            name: name.into(),
            format: format.into(),
            validity: 0,
            nulls: 0,
            values,
            text: Vec::new(),
            levels: None,
            letters: Vec::new(),
            storage: None,
        }
    }
}

/// The columns of one read, until `take` hands them to Python.
#[pyclass(frozen, module = "dta_parser._native")]
pub(crate) struct NativeFrame {
    rows: usize,
    owner: Owner,
    names: Vec<String>,
    formats: Vec<String>,
    columns: Mutex<Option<Vec<NativeColumn>>>,
}

impl NativeFrame {
    pub(crate) fn new(rows: usize, owner: Owner, columns: Vec<NativeColumn>) -> Self {
        NativeFrame {
            rows,
            owner,
            names: columns.iter().map(|c| c.name.clone()).collect(),
            formats: columns.iter().map(|c| c.format.clone()).collect(),
            columns: Mutex::new(Some(columns)),
        }
    }
}

#[inline]
fn bit(addr: usize, r: usize) -> bool {
    // SAFETY: callers pass a bitmap of at least r + 1 bits.
    unsafe { (*(addr as *const u8).add(r / 8) >> (r % 8)) & 1 == 1 }
}

/// # Safety
/// `addr` holds `n` elements of `T` that nothing else uses meanwhile.
unsafe fn slice<'a, T>(addr: usize, n: usize) -> &'a mut [T] {
    if n == 0 {
        &mut []
    } else {
        std::slice::from_raw_parts_mut(addr as *mut T, n)
    }
}

/// The storage type a `DtaArray` keeps for a numeric format.
fn storage(format: &str) -> &'static str {
    match format {
        "c" => "byte",
        "s" => "int",
        "i" => "long",
        "f" => "float",
        _ => "double",
    }
}

/// pandas' code width for `n` categories (`coerce_indexer_dtype`).
fn code_width(n: usize) -> usize {
    if n < i8::MAX as usize {
        1
    } else if n < i16::MAX as usize {
        2
    } else {
        4
    }
}

/// Write code `v` at row `r` of a buffer of `width`-byte signed codes.
///
/// # Safety
/// The buffer holds row `r` at that width.
#[inline]
unsafe fn put_code(addr: usize, width: usize, r: usize, v: i32) {
    match width {
        1 => *(addr as *mut i8).add(r) = v as i8,
        2 => *(addr as *mut i16).add(r) = v as i16,
        _ => *(addr as *mut i32).add(r) = v,
    }
}

impl NativeColumn {
    fn valid(&self, r: usize) -> bool {
        self.validity == 0 || bit(self.validity, r)
    }

    /// A code per row: 1 where `missing(r)` or the row is null, its letter
    /// where `letters` and it has one, 0 elsewhere.
    fn codes(&self, n: usize, letters: bool, missing: impl Fn(usize) -> bool) -> Vec<u8> {
        let mut codes: Vec<u8> = (0..n).map(|r| u8::from(!self.valid(r) || missing(r))).collect();
        if letters {
            for &(r, c) in &self.letters {
                codes[r as usize] = c;
            }
        }
        codes
    }

    /// Values as doubles (`f(r)` for each valid row), NaN where `codes`
    /// is not 0.
    fn doubles(&self, codes: &[u8], f: impl Fn(usize) -> f64) -> Vec<f64> {
        codes.iter().enumerate().map(|(r, &c)| if c == 0 { f(r) } else { f64::NAN }).collect()
    }
}

/// The text of each row of a string-view column, as `str` (or `bytes`
/// for `vz`), into the object array at `out`, whose `None`s stay where a
/// row is null.
///
/// # Safety
/// The GIL is held; `out` holds the column's rows, each a reference.
unsafe fn put_text(py: Python<'_>, c: &NativeColumn, n: usize, out: *mut *mut ffi::PyObject) -> PyResult<()> {
    let binary = c.format == "vz";
    let mut recent = Recent::new();
    let result = (|| {
        for r in 0..n {
            if !c.valid(r) {
                continue;
            }
            let b = super::ffi::view_at(c.values, |i| c.text[i], r);
            let obj = if binary {
                ffi::PyBytes_FromStringAndSize(b.as_ptr() as *const c_char, b.len() as ffi::Py_ssize_t)
            } else if std::str::from_utf8(b).is_ok() {
                recent.get(b)
            } else {
                let s = String::from_utf8_lossy(b);
                ffi::PyUnicode_FromStringAndSize(s.as_ptr() as *const c_char, s.len() as ffi::Py_ssize_t)
            };
            if obj.is_null() {
                return Err(PyErr::fetch(py));
            }
            let slot = out.add(r);
            let old = *slot;
            *slot = obj;
            ffi::Py_XDECREF(old);
        }
        Ok(())
    })();
    recent.clear();
    result
}

#[pymethods]
impl NativeFrame {
    /// The columns' names, in order.
    #[getter]
    fn names(&self) -> Vec<String> {
        self.names.clone()
    }

    /// Each column's format (see `NativeColumn::format`); Python makes an
    /// object array for each `vu` and `vz` column before `take`.
    #[getter]
    fn formats(&self) -> Vec<String> {
        self.formats.clone()
    }

    #[getter]
    fn rows(&self) -> usize {
        self.rows
    }

    /// Every column, converted once, as a list of tuples:
    ///
    /// - `("numpy", buffer, zone)`: one array; `zone` is a time zone name
    ///   for a timestamp adjusted to UTC, else None;
    /// - `("masked", values, mask)`: a nullable integer or boolean;
    /// - `("dta", values, codes, storage, origin, letters)`: a
    ///   `DtaArray`; `origin` is "date", "datetime" or "categorical" for a
    ///   column read as Stata's numbers because it holds `.a` to `.z`,
    ///   else None; `letters` whether any row holds one;
    /// - `("category", codes, levels, ordered)`;
    /// - `("text", binary)`: the object array in `text` filled.
    ///
    /// `letters`: False reads `.a` to `.z` as `.`. `text`: per column, an
    /// object array of the read's rows for a `vu` or `vz` column, None
    /// for the others. A frame is taken once.
    fn take<'py>(&self, py: Python<'py>, letters: bool, text: Vec<Option<Bound<'py, PyAny>>>) -> PyResult<Bound<'py, PyList>> {
        let columns = self
            .columns
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .take()
            .ok_or_else(|| PyValueError::new_err("this read's columns were taken already"))?;
        if text.len() != columns.len() {
            return Err(fail("one text target (or None) per column"));
        }
        let n = self.rows;
        let out = PyList::empty(py);
        for (c, target) in columns.iter().zip(&text) {
            let lettered = letters && !c.letters.is_empty();
            let shared = |len: usize, ts: &str| Buffer::new(self.owner.clone(), c.values, len, ts);
            let dta = |values: Buffer, codes: Vec<u8>, storage: &str, origin: Option<&str>| -> PyResult<Bound<'py, PyTuple>> {
                PyTuple::new(
                    py,
                    [
                        "dta".into_pyobject(py)?.into_any(),
                        Bound::new(py, values)?.into_any(),
                        Bound::new(py, Buffer::of(codes, "|u1"))?.into_any(),
                        storage.into_pyobject(py)?.into_any(),
                        origin.into_pyobject(py)?.into_any(),
                        lettered.into_pyobject(py)?.to_owned().into_any(),
                    ],
                )
            };
            let numpy = |b: Buffer, zone: Option<&str>| -> PyResult<Bound<'py, PyTuple>> {
                PyTuple::new(py, ["numpy".into_pyobject(py)?.into_any(), Bound::new(py, b)?.into_any(), zone.into_pyobject(py)?.into_any()])
            };
            let masked = |values: Buffer| -> PyResult<Bound<'py, PyTuple>> {
                let mask: Vec<bool> = (0..n).map(|r| !c.valid(r)).collect();
                PyTuple::new(
                    py,
                    [
                        "masked".into_pyobject(py)?.into_any(),
                        Bound::new(py, values)?.into_any(),
                        Bound::new(py, Buffer::of(mask, "|b1"))?.into_any(),
                    ],
                )
            };
            let f = c.format.as_str();
            let item = if let Some((levels, ordered)) = &c.levels {
                if f == "g" && lettered {
                    // Level numbers held as doubles: a DtaArray of them.
                    let codes = c.codes(n, true, |_| false);
                    let x = unsafe { slice::<f64>(c.values, n) };
                    for (v, &code) in x.iter_mut().zip(&codes) {
                        if code != 0 {
                            *v = f64::NAN;
                        }
                    }
                    dta(shared(n, &typestr("f", 8)), codes, "double", Some("categorical"))?
                } else {
                    // Keys made pandas' codes in place: each narrower code
                    // at row r overlaps only keys at rows <= r, already read.
                    let w = code_width(levels.len());
                    for r in 0..n {
                        let code = if !c.valid(r) {
                            -1
                        } else if f == "g" {
                            let x = unsafe { *(c.values as *const f64).add(r) };
                            dta_parquet::level_index(x, levels.len()).map_or(-1, |i| i as i32)
                        } else {
                            unsafe { *(c.values as *const u32).add(r) as i32 }
                        };
                        unsafe { put_code(c.values, w, r, code) };
                    }
                    PyTuple::new(
                        py,
                        [
                            "category".into_pyobject(py)?.into_any(),
                            Bound::new(py, shared(n, &typestr("i", w)))?.into_any(),
                            PyList::new(py, levels)?.into_any(),
                            ordered.into_pyobject(py)?.to_owned().into_any(),
                        ],
                    )?
                }
            } else {
                match f {
                    "c" | "s" | "i" | "f" | "g" => {
                        macro_rules! go {
                            ($t:ty, $kind:literal) => {{
                                let x = unsafe { slice::<$t>(c.values, n) };
                                #[allow(clippy::unnecessary_cast)]
                                let nan = |r: usize| (x[r] as f64).is_nan();
                                let any_nan = $kind == "f" && x.iter().any(|v| (*v as f64).is_nan());
                                if c.nulls == 0 && !any_nan {
                                    numpy(shared(n, &typestr($kind, std::mem::size_of::<$t>())), None)?
                                } else {
                                    let codes = c.codes(n, letters, nan);
                                    if std::mem::size_of::<$t>() == 8 && $kind == "f" {
                                        // A double column's values stay where they are.
                                        let v = unsafe { slice::<f64>(c.values, n) };
                                        for (v, &code) in v.iter_mut().zip(&codes) {
                                            if code != 0 {
                                                *v = f64::NAN;
                                            }
                                        }
                                        dta(shared(n, &typestr("f", 8)), codes, storage(f), None)?
                                    } else {
                                        let values = c.doubles(&codes, |r| x[r] as f64);
                                        dta(Buffer::of(values, &typestr("f", 8)), codes, storage(f), None)?
                                    }
                                }
                            }};
                        }
                        match f {
                            "c" => go!(i8, "i"),
                            "s" => go!(i16, "i"),
                            "i" => go!(i32, "i"),
                            "f" => go!(f32, "f"),
                            _ => go!(f64, "f"),
                        }
                    }
                    "l" | "C" | "S" | "I" | "L" | "b" => {
                        let (kind, size) = match f {
                            "l" => ("i", 8),
                            "C" => ("u", 1),
                            "S" => ("u", 2),
                            "I" => ("u", 4),
                            "L" => ("u", 8),
                            _ => ("b", 1),
                        };
                        if f == "b" {
                            // numpy's bool is a byte of 0 or 1.
                            for v in unsafe { slice::<u8>(c.values, n) } {
                                *v = u8::from(*v != 0);
                            }
                        }
                        let values = shared(n, &typestr(kind, size));
                        if c.nulls == 0 {
                            numpy(values, None)?
                        } else {
                            masked(values)?
                        }
                    }
                    "tdD" => {
                        let days = unsafe { slice::<i32>(c.values, n) };
                        if lettered {
                            let codes = c.codes(n, true, |_| false);
                            let values = c.doubles(&codes, |r| f64::from(days[r]) + EPOCH_DAYS as f64);
                            dta(Buffer::of(values, &typestr("f", 8)), codes, c.storage.unwrap_or("double"), Some("date"))?
                        } else {
                            let secs: Vec<i64> =
                                (0..n).map(|r| if c.valid(r) { i64::from(days[r]) * DAY_SECONDS } else { i64::MIN }).collect();
                            numpy(Buffer::of(secs, &typestr("M8[s]", 8)), None)?
                        }
                    }
                    t if t.starts_with("ts") || t == "ttn" => {
                        let x = unsafe { slice::<i64>(c.values, n) };
                        let (unit, zone) = if t == "ttn" {
                            ("ns", "")
                        } else {
                            let unit = match t.as_bytes()[2] {
                                b's' => "s",
                                b'm' => "ms",
                                b'u' => "us",
                                _ => "ns",
                            };
                            (unit, t.split_once(':').map_or("", |(_, z)| z))
                        };
                        if lettered && t != "ttn" {
                            let per_ms = match unit {
                                "s" => 1e-3,
                                "ms" => 1.0,
                                "us" => 1e3,
                                _ => 1e6,
                            };
                            let codes = c.codes(n, true, |_| false);
                            let values = c.doubles(&codes, |r| x[r] as f64 / per_ms + MS_1960);
                            dta(Buffer::of(values, &typestr("f", 8)), codes, c.storage.unwrap_or("double"), Some("datetime"))?
                        } else {
                            if c.nulls > 0 {
                                for (r, v) in x.iter_mut().enumerate() {
                                    if !c.valid(r) {
                                        *v = i64::MIN;
                                    }
                                }
                            }
                            let kind = if t == "ttn" { "m8[ns]".to_string() } else { format!("M8[{unit}]") };
                            numpy(shared(n, &typestr(&kind, 8)), (!zone.is_empty()).then_some(zone))?
                        }
                    }
                    "vu" | "vz" => {
                        let target = target.as_ref().ok_or_else(|| fail(format!("column \"{}\": no object array for its text", c.name)))?;
                        let at = array_at(target, "|O", n, &format!("the text of column \"{}\"", c.name))?;
                        // SAFETY: an object array of n rows, checked above.
                        unsafe { put_text(py, c, n, at as *mut *mut ffi::PyObject)? };
                        PyTuple::new(py, ["text".into_pyobject(py)?.into_any(), (f == "vz").into_pyobject(py)?.to_owned().into_any()])?
                    }
                    other => return Err(fail(format!("column \"{}\": internal: a read of format {other}", c.name))),
                }
            };
            out.append(item)?;
        }
        Ok(out)
    }
}

// ---------------------------------------------------------------- writes

/// The size in bytes of an element of numpy type string `t`.
fn item_size(t: &str) -> usize {
    match &t[1..] {
        "O" => std::mem::size_of::<usize>(),
        k if k.starts_with('M') || k.starts_with('m') => 8,
        k => k[1..].parse().unwrap_or(1),
    }
}

/// The data address of the numpy array `obj`, after checking from its
/// `__array_interface__` that it is of type `typestr`, holds `rows`
/// elements, is C-contiguous, and is aligned for its type (the writers
/// read values through typed pointers).
pub(crate) fn array_at(obj: &Bound<'_, PyAny>, typestr: &str, rows: usize, what: &str) -> PyResult<usize> {
    let ai = obj
        .getattr("__array_interface__")
        .map_err(|_| PyTypeError::new_err(format!("{what} is not a numpy array")))?;
    let ai = ai.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err(format!("{what}: its __array_interface__ is not a dict")))?;
    let get = |k: &str| -> PyResult<Bound<'_, PyAny>> {
        ai.get_item(k)?.ok_or_else(|| PyValueError::new_err(format!("{what}: its __array_interface__ has no {k}")))
    };
    let t: String = get("typestr")?.extract()?;
    if t != typestr {
        return Err(PyValueError::new_err(format!("{what} is of type {t}, not {typestr}")));
    }
    let shape: Vec<usize> = get("shape")?.extract()?;
    if shape != [rows] {
        return Err(PyValueError::new_err(format!("{what} has shape {shape:?}, not ({rows},)")));
    }
    let size = item_size(typestr);
    if let Some(strides) = ai.get_item("strides")? {
        if !strides.is_none() {
            let strides: Vec<isize> = strides.extract()?;
            if rows > 1 && strides != [size as isize] {
                return Err(PyValueError::new_err(format!("{what} is not C-contiguous (strides {strides:?})")));
            }
        }
    }
    let (addr, _readonly): (usize, bool) = get("data")?.extract()?;
    if rows > 0 && (addr == 0 || addr % size != 0) {
        return Err(PyValueError::new_err(format!("{what} is not aligned for its type (address {addr:#x})")));
    }
    Ok(addr)
}

/// What a built table's arrays point into, kept while the write runs.
#[derive(Default)]
pub(crate) struct Keep {
    // Boxed: the arrays point at each other, so each must stay put.
    #[allow(clippy::vec_box)]
    arrays: Vec<Box<ArrowArray>>,
    pointers: Vec<Vec<*const c_void>>,
    children: Vec<*mut ArrowArray>,
    bytes: Vec<Vec<u8>>,
    offsets: Vec<Vec<i64>>,
    objects: Vec<Py<PyAny>>,
}

// SAFETY: plain memory and owned references, read while a write runs.
unsafe impl Send for Keep {}
unsafe impl Sync for Keep {}

impl Keep {
    /// An array over `buffers`; its address stays put.
    fn array(&mut self, length: usize, null_count: usize, buffers: Vec<*const c_void>, dictionary: *mut ArrowArray) -> *mut ArrowArray {
        let mut buffers = buffers;
        let ptr = buffers.as_mut_ptr();
        let n = buffers.len();
        self.pointers.push(buffers);
        let mut a = Box::new(ArrowArray {
            length: length as i64,
            null_count: null_count as i64,
            offset: 0,
            n_buffers: n as i64,
            n_children: 0,
            buffers: ptr,
            children: null_mut(),
            dictionary,
            release: None,
            private_data: null_mut(),
        });
        let p: *mut ArrowArray = &mut *a;
        self.arrays.push(a);
        p
    }

    fn bytes(&mut self, v: Vec<u8>) -> *const c_void {
        let p = v.as_ptr() as *const c_void;
        self.bytes.push(v);
        p
    }

    /// Text as Arrow's large string layout: offsets and bytes.
    fn large_text<'a>(&mut self, rows: impl Iterator<Item = Option<&'a [u8]>>, n: usize) -> (*const c_void, *const c_void) {
        let mut offsets = Vec::with_capacity(n + 1);
        let mut data = Vec::new();
        offsets.push(0i64);
        for r in rows {
            if let Some(b) = r {
                data.extend_from_slice(b);
            }
            offsets.push(data.len() as i64);
        }
        let o = offsets.as_ptr() as *const c_void;
        self.offsets.push(offsets);
        (o, self.bytes(data))
    }
}

/// Bits from bytes: bit r set where `f(r)`.
fn pack(n: usize, f: impl Fn(usize) -> bool) -> Vec<u8> {
    let mut bits = vec![0u8; n.div_ceil(8)];
    for r in 0..n {
        if f(r) {
            bits[r / 8] |= 1 << (r % 8);
        }
    }
    bits
}

/// The numpy type string a column of `format` passes its values in.
fn values_typestr(format: &str) -> Option<String> {
    Some(match format {
        "c" => typestr("i", 1),
        "s" => typestr("i", 2),
        "i" | "tdD" => typestr("i", 4),
        "l" => typestr("i", 8),
        "C" => typestr("u", 1),
        "S" => typestr("u", 2),
        "I" => typestr("u", 4),
        "L" => typestr("u", 8),
        "f" => typestr("f", 4),
        "g" => typestr("f", 8),
        "b" => typestr("b", 1),
        "U" | "Z" => "|O".into(),
        t if t.starts_with("ts") || t.starts_with("tt") => typestr("i", 8),
        _ => return None,
    })
}

/// A table for the writers over the columns Python passes, as `(name,
/// format, values, mask, letters, levels, ordered)` tuples:
///
/// - `format`: an Arrow format the writers take: `c` ... `L`, `f`, `g`,
///   `b`, `tdD` (int32 days since 1970), `ts{unit}:{zone}`, `ttn`, or
///   `U` (text) or `Z` (binary) for an object array; for a categorical,
///   its codes' format (`c`, `s`, `i` or `l`);
/// - `values`: a numpy array of the rows, of the type the format names
///   (bool for `b`; int64 for timestamps and times; object for `U`, `Z`);
/// - `mask`: None, or a bool array, True where a row is missing;
/// - `letters`: None, or a uint8 array of codes, 2 to 27 for `.a` to `.z`
///   on a missing row;
/// - `levels`: a categorical's levels (text), else None; `ordered`.
///
/// Returns the table, what it points into, and each column's letters.
#[allow(clippy::type_complexity)]
pub(crate) fn build(py: Python<'_>, columns: &Bound<'_, PyList>, rows: usize) -> PyResult<(Imported, Keep, Vec<Option<Vec<u8>>>)> {
    let mut keep = Keep::default();
    let mut fields = Vec::with_capacity(columns.len());
    let mut letters = Vec::with_capacity(columns.len());
    for item in columns.iter() {
        type Spec<'py> = (String, String, Bound<'py, PyAny>, Option<Bound<'py, PyAny>>, Option<Bound<'py, PyAny>>, Option<Vec<String>>, bool);
        let (name, format, values, mask, codes, levels, _ordered): Spec = item.extract()?;
        let what = |part: &str| format!("column \"{name}\": its {part}");
        let vt = values_typestr(&format).ok_or_else(|| PyTypeError::new_err(format!("column \"{name}\": format {format} is not written")))?;
        let addr = array_at(&values, &vt, rows, &what("values"))?;
        keep.objects.push(values.clone().unbind());
        let missing: Option<&[bool]> = match &mask {
            None => None,
            Some(m) if m.is_none() => None,
            Some(m) => {
                let a = array_at(m, &typestr("b", 1), rows, &what("mask"))?;
                keep.objects.push(m.clone().unbind());
                // SAFETY: a bool array of `rows`, checked, held in `keep`.
                Some(unsafe { std::slice::from_raw_parts(a as *const bool, rows) })
            }
        };
        let is_missing = |r: usize| missing.is_some_and(|m| m[r]);
        let null_count = missing.map_or(0, |m| m.iter().filter(|&&x| x).count());
        let validity = if null_count > 0 { keep.bytes(pack(rows, |r| !is_missing(r))) } else { null() };
        letters.push(match &codes {
            Some(l) if !l.is_none() => {
                let a = array_at(l, &typestr("u", 1), rows, &what("letters"))?;
                // SAFETY: a uint8 array of `rows`, checked.
                let l = unsafe { std::slice::from_raw_parts(a as *const u8, rows) };
                if let Some(r) = l.iter().position(|&c| c != 0 && !(2..=27).contains(&c)) {
                    return Err(PyValueError::new_err(format!("column \"{name}\", row {}: {} is not a letter's code (2 to 27)", r + 1, l[r])));
                }
                l.iter().any(|&c| c != 0).then(|| l.to_vec())
            }
            _ => None,
        });
        let mut field = InField { name: name.clone(), format: format.clone(), metadata: Vec::new(), children: Vec::new(), dictionary: None };
        let array = match format.as_str() {
            "U" | "Z" => {
                let binary = format == "Z";
                let objs = addr as *const *mut ffi::PyObject;
                let mut texts: Vec<Option<&[u8]>> = Vec::with_capacity(rows);
                for r in 0..rows {
                    if is_missing(r) {
                        texts.push(None);
                        continue;
                    }
                    // SAFETY: an object array of `rows`, held; the GIL is held.
                    unsafe {
                        let obj = *objs.add(r);
                        if binary && ffi::PyBytes_Check(obj) != 0 {
                            let n = ffi::PyBytes_Size(obj) as usize;
                            let p = ffi::PyBytes_AsString(obj) as *const u8;
                            texts.push(Some(if n == 0 { &[] } else { std::slice::from_raw_parts(p, n) }));
                        } else if !binary && ffi::PyUnicode_Check(obj) != 0 {
                            let mut n: ffi::Py_ssize_t = 0;
                            let p = ffi::PyUnicode_AsUTF8AndSize(obj, &mut n) as *const u8;
                            if p.is_null() {
                                let e = PyErr::fetch(py);
                                return Err(PyValueError::new_err(format!("column \"{name}\", row {}: {e}", r + 1)));
                            }
                            texts.push(Some(if n == 0 { &[] } else { std::slice::from_raw_parts(p, n as usize) }));
                        } else {
                            let kind = Bound::from_borrowed_ptr(py, obj).get_type().name()?;
                            let want = if binary { "bytes" } else { "text" };
                            return Err(PyTypeError::new_err(format!("column \"{name}\", row {}: a {kind} in a column of {want}", r + 1)));
                        }
                    }
                }
                let (o, d) = keep.large_text(texts.into_iter(), rows);
                keep.array(rows, null_count, vec![validity, o, d], null_mut())
            }
            "b" => {
                // SAFETY: a bool array of `rows`, checked.
                let v = unsafe { std::slice::from_raw_parts(addr as *const bool, rows) };
                let bits = keep.bytes(pack(rows, |r| v[r]));
                keep.array(rows, null_count, vec![validity, bits], null_mut())
            }
            _ => {
                let dictionary = match &levels {
                    Some(levels) => {
                        let (o, d) = keep.large_text(levels.iter().map(|l| Some(l.as_bytes())), levels.len());
                        field.dictionary = Some(Box::new(InField {
                            name: String::new(),
                            format: "U".into(),
                            metadata: Vec::new(),
                            children: Vec::new(),
                            dictionary: None,
                        }));
                        field.metadata.push((EVERY_LEVEL.into(), b"1".to_vec()));
                        keep.array(levels.len(), 0, vec![null(), o, d], null_mut())
                    }
                    None => null_mut(),
                };
                keep.array(rows, null_count, vec![validity, addr as *const c_void], dictionary)
            }
        };
        keep.children.push(array);
        fields.push(field);
    }
    let schema = InField { name: String::new(), format: "+s".into(), metadata: Vec::new(), children: fields, dictionary: None };
    let top = Box::new(ArrowArray {
        length: rows as i64,
        null_count: 0,
        offset: 0,
        n_buffers: 1,
        n_children: keep.children.len() as i64,
        buffers: {
            keep.pointers.push(vec![null()]);
            keep.pointers.last_mut().expect("just pushed").as_mut_ptr()
        },
        children: keep.children.as_mut_ptr(),
        dictionary: null_mut(),
        release: None,
        private_data: null_mut(),
    });
    Ok((Imported { schema, batches: vec![InArray { raw: top }] }, keep, letters))
}

/// A read's buffers, shared by its columns.
pub(crate) fn owner<T: Send + Sync + 'static>(t: T) -> Owner {
    Arc::new(t)
}
