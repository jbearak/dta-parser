//! dta_parser's bridge from Python to the dta core (ADR 0014).
//!
//! Python allocates the numpy arrays a read fills and holds them for the
//! call; it passes their data addresses, which is how this module reaches
//! numpy without its C API (the buffer protocol is not in the abi3 API
//! before Python 3.11). Writing borrows numpy buffers the same way.
//! Strings are made here, one Python object per distinct recent value.

use std::ffi::c_char;
use std::slice;

use pyo3::exceptions::PyValueError;
use pyo3::ffi;
use pyo3::prelude::*;
use pyo3::types::PyDict;

use dta::{
    Characteristic, Column, Dataset, Encoding, FileSource, Options, Reader, StorageType, ValueLabel, ValueLabelSet,
    Values, WriteVariable,
};

fn fail(e: impl std::fmt::Display) -> PyErr {
    PyValueError::new_err(e.to_string())
}

fn open(path: &str, encoding: Option<&str>) -> PyResult<Reader<FileSource>> {
    let encoding = match encoding {
        Some(name) => Encoding::from_name(name).ok_or_else(|| fail(format!("unknown encoding \"{name}\"")))?,
        None => Encoding::default(),
    };
    let source = FileSource::open(path).map_err(|e| fail(format!("{path}: {e}")))?;
    Reader::open(source, Options { encoding }).map_err(|e| fail(format!("{path}: {e}")))
}

/// The header, descriptors, value labels and characteristics of a file.
#[pyfunction]
#[pyo3(signature = (path, encoding=None))]
fn meta<'py>(py: Python<'py>, path: &str, encoding: Option<&str>) -> PyResult<Bound<'py, PyDict>> {
    let mut reader = open(path, encoding)?;
    let sets = reader.value_labels().map_err(|e| fail(format!("{path}: {e}")))?;
    let chars = reader.characteristics().map_err(|e| fail(format!("{path}: {e}")))?;
    let m = reader.metadata();
    let out = PyDict::new(py);
    out.set_item("release", m.release)?;
    out.set_item("byte_order", if m.byte_order == dta::ByteOrder::Big { "big" } else { "little" })?;
    out.set_item("nobs", m.nobs)?;
    out.set_item("label", &m.label)?;
    out.set_item("timestamp", &m.timestamp)?;
    out.set_item("encoding", m.encoding.name())?;
    let vars: Vec<_> = m
        .variables
        .iter()
        .map(|v| (&v.name, v.storage.name(), &v.format, &v.label, &v.value_labels))
        .collect();
    out.set_item("variables", vars)?;
    out.set_item("sort_order", &m.sort_order)?;
    let sets: Vec<_> = sets
        .iter()
        .map(|s| (&s.name, s.labels.iter().map(|l| (l.value, l.missing, &l.text)).collect::<Vec<_>>()))
        .collect();
    out.set_item("value_labels", sets)?;
    let chars: Vec<_> = chars.iter().map(|c| (&c.variable, &c.name, &c.value)).collect();
    out.set_item("characteristics", chars)?;
    Ok(out)
}

/// Rows `start..start + count` of the variables at `cols` into the arrays
/// at `targets`: for a numeric variable, (values, codes), the values in
/// the storage type's numpy dtype (int8, int16, int32, float32, float64)
/// and the codes uint8 zeros; for a string variable, (an object array of
/// `count` Nones, 0). Returns per variable the largest missing code seen,
/// or for strings 1 if any value is binary.
#[pyfunction]
#[pyo3(signature = (path, encoding, cols, start, count, targets))]
fn read(
    py: Python<'_>,
    path: &str,
    encoding: Option<&str>,
    cols: Vec<usize>,
    start: u64,
    count: u64,
    targets: Vec<(usize, usize)>,
) -> PyResult<Vec<u8>> {
    let mut reader = open(path, encoding)?;
    if targets.len() != cols.len() {
        return Err(fail("one target per column"));
    }
    let storage: Vec<StorageType> = {
        let vars = &reader.metadata().variables;
        cols.iter().map(|&c| vars.get(c).map(|v| v.storage)).collect::<Option<_>>().ok_or_else(|| fail("no such column"))?
    };
    let mut flags = vec![0u8; cols.len()];
    let mut recent: Vec<Recent> = cols.iter().map(|_| Recent::new()).collect();
    // A Python error raised while making strings, kept to re-raise.
    let mut raised: Option<PyErr> = None;
    let result = py.detach(|| {
        reader.read_chunks(&cols, start, count, None, |first, chunk| {
            for (k, column) in chunk.iter().enumerate() {
                let (a, b) = targets[k];
                match column {
                    Column::Numbers { values, missing } => unsafe {
                        put_numbers(storage[k], a, first, values);
                        let codes = slice::from_raw_parts_mut((b as *mut u8).add(first), missing.len());
                        for (i, &m) in missing.iter().enumerate() {
                            if m != 0 {
                                codes[i] = m;
                                flags[k] = flags[k].max(m);
                            }
                        }
                    },
                    Column::Strings { binary, .. } => {
                        let out = a as *mut *mut ffi::PyObject;
                        let made = Python::attach(|py| unsafe { put_strings(py, out, first, column, &mut recent[k]) });
                        if let Err(e) = made {
                            raised = Some(e);
                            return Err(dta::Error::new("a string could not be made"));
                        }
                        if binary.contains(&true) {
                            flags[k] = 1;
                        }
                    }
                }
            }
            Ok(())
        })
    });
    for r in &mut recent {
        unsafe { r.clear() };
    }
    if let Some(e) = raised {
        return Err(e);
    }
    result.map_err(|e| fail(format!("{path}: {e}")))?;
    Ok(flags)
}

/// Copy a chunk's numbers into the array at `addr` from row `first`, in
/// the storage type's width. Missing values become 0 in integer arrays
/// and NaN in float ones.
///
/// # Safety
/// `addr` holds at least `first + values.len()` elements of that type.
unsafe fn put_numbers(storage: StorageType, addr: usize, first: usize, values: &[f64]) {
    macro_rules! put {
        ($t:ty, $missing:expr) => {{
            let out = slice::from_raw_parts_mut((addr as *mut $t).add(first), values.len());
            for (o, &v) in out.iter_mut().zip(values) {
                *o = if v.is_nan() { $missing } else { v as $t };
            }
        }};
    }
    match storage {
        StorageType::Byte => put!(i8, 0),
        StorageType::Int => put!(i16, 0),
        StorageType::Long => put!(i32, 0),
        StorageType::Float => put!(f32, f32::NAN),
        _ => put!(f64, f64::NAN),
    }
}

/// Strings made lately, so that a column with few distinct values shares
/// one `str` per value instead of making one per row: 1024 slots by hash.
/// A column whose values mostly differ stops using it after 4096 rows.
struct Recent {
    /// (the `str` as an address, its UTF-8); address 0 when empty.
    slots: Vec<(usize, Vec<u8>)>,
    lookups: usize,
    hits: usize,
}

impl Recent {
    const SLOTS: usize = 1024;
    const LONGEST: usize = 64;

    fn new() -> Self {
        Recent { slots: vec![(0, Vec::new()); Self::SLOTS], lookups: 0, hits: 0 }
    }

    /// A new reference to a `str` of `b`, or NULL with a Python error set.
    ///
    /// # Safety
    /// The GIL is held; `b` is UTF-8.
    unsafe fn get(&mut self, b: &[u8]) -> *mut ffi::PyObject {
        let make = || ffi::PyUnicode_FromStringAndSize(b.as_ptr() as *const c_char, b.len() as ffi::Py_ssize_t);
        if b.len() > Self::LONGEST || (self.lookups >= 4096 && self.hits * 2 < self.lookups) {
            return make();
        }
        self.lookups += 1;
        let slot = &mut self.slots[hash(b) % Self::SLOTS];
        if slot.0 != 0 && slot.1 == b {
            self.hits += 1;
            let obj = slot.0 as *mut ffi::PyObject;
            ffi::Py_INCREF(obj);
            return obj;
        }
        let obj = make();
        if !obj.is_null() {
            if slot.0 != 0 {
                ffi::Py_DECREF(slot.0 as *mut ffi::PyObject);
            }
            ffi::Py_INCREF(obj);
            slot.0 = obj as usize;
            slot.1.clear();
            slot.1.extend_from_slice(b);
        }
        obj
    }

    /// Drop the references held.
    ///
    /// # Safety
    /// The GIL is held.
    unsafe fn clear(&mut self) {
        for slot in &mut self.slots {
            if slot.0 != 0 {
                ffi::Py_DECREF(slot.0 as *mut ffi::PyObject);
                slot.0 = 0;
            }
        }
    }
}

/// Eight bytes at a time, multiply and rotate (as rustc's FxHash).
fn hash(b: &[u8]) -> usize {
    let mut h: u64 = b.len() as u64;
    let mut add = |w: u64| h = (h.rotate_left(5) ^ w).wrapping_mul(0x51_7c_c1_b7_27_22_0a_95);
    let mut chunks = b.chunks_exact(8);
    for c in &mut chunks {
        add(u64::from_le_bytes(c.try_into().unwrap_or_default()));
    }
    let mut last = [0u8; 8];
    last[..chunks.remainder().len()].copy_from_slice(chunks.remainder());
    add(u64::from_le_bytes(last));
    (h >> 32) as usize
}

/// Fill the object array at `out` from row `first` with a `str` per
/// value (a `bytes` for a binary strL), replacing what was there.
///
/// # Safety
/// The GIL is held; `out` holds at least `first + column.len()` objects.
unsafe fn put_strings(
    py: Python<'_>,
    out: *mut *mut ffi::PyObject,
    first: usize,
    column: &Column,
    recent: &mut Recent,
) -> PyResult<()> {
    let Column::Strings { binary, .. } = column else { return Ok(()) };
    for i in 0..column.len() {
        let b = column.bytes(i);
        let obj = if binary.get(i) == Some(&true) {
            ffi::PyBytes_FromStringAndSize(b.as_ptr() as *const c_char, b.len() as ffi::Py_ssize_t)
        } else {
            recent.get(b)
        };
        if obj.is_null() {
            return Err(PyErr::fetch(py));
        }
        let slot = out.add(first + i);
        let old = *slot;
        *slot = obj;
        ffi::Py_XDECREF(old);
    }
    Ok(())
}

/// One numeric column's values and missing codes, read in place from a
/// numpy buffer of dtype `kind` (`i1` ... `f8`, `b1`). Without codes, NaN
/// is `.`.
///
/// # Safety
/// `addr` (and `codes`, unless 0) hold `nobs` elements, alive and
/// unchanged while the result is used.
unsafe fn numbers<'a>(kind: &str, addr: usize, codes: usize, nobs: usize) -> Result<Values<'a>, String> {
    let codes: Option<&'a [u8]> = (codes != 0 && nobs > 0).then(|| slice::from_raw_parts(codes as *const u8, nobs));
    macro_rules! data {
        ($t:ty) => {
            if nobs == 0 { &[] } else { slice::from_raw_parts(addr as *const $t, nobs) }
        };
    }
    macro_rules! ints {
        ($t:ty) => {{
            let x: &'a [$t] = data!($t);
            Values::Numbers(Box::new(move |r| match codes {
                Some(c) if c[r] != 0 => (f64::NAN, c[r]),
                _ => (x[r] as f64, 0),
            }))
        }};
    }
    macro_rules! floats {
        ($t:ty) => {{
            let x: &'a [$t] = data!($t);
            Values::Numbers(Box::new(move |r| {
                let code = codes.map_or(0, |c| c[r]);
                if code != 0 {
                    (f64::NAN, code)
                } else if x[r].is_nan() {
                    (f64::NAN, dta::missing::SYSTEM)
                } else {
                    (x[r] as f64, 0)
                }
            }))
        }};
    }
    Ok(match kind {
        "i1" => ints!(i8),
        "i2" => ints!(i16),
        "i4" => ints!(i32),
        "i8" => ints!(i64),
        "u1" | "b1" => ints!(u8),
        "u2" => ints!(u16),
        "u4" => ints!(u32),
        "u8" => ints!(u64),
        "f4" => floats!(f32),
        "f8" => floats!(f64),
        other => return Err(format!("cannot write numbers of dtype {other}")),
    })
}

/// A string row of the object array: its bytes and whether it is a
/// `bytes` (binary). Callers have checked every row is a `str` or a
/// `bytes` and that each `str` encodes to UTF-8.
///
/// # Safety
/// The GIL is held and `obj` lives while the slice is used. The UTF-8 of
/// a `str` is cached in the object, so it stays put.
unsafe fn string_row<'a>(obj: *mut ffi::PyObject) -> (&'a [u8], bool) {
    if ffi::PyBytes_Check(obj) != 0 {
        let n = ffi::PyBytes_Size(obj) as usize;
        let p = ffi::PyBytes_AsString(obj) as *const u8;
        (if n == 0 { &[] } else { slice::from_raw_parts(p, n) }, true)
    } else {
        let mut n: ffi::Py_ssize_t = 0;
        let p = ffi::PyUnicode_AsUTF8AndSize(obj, &mut n) as *const u8;
        (if n <= 0 || p.is_null() { &[] } else { slice::from_raw_parts(p, n as usize) }, false)
    }
}

/// Check every row of a string column is a `str` (with a UTF-8 form) or
/// a `bytes`; returns whether any is a `bytes`.
///
/// # Safety
/// The GIL is held; `rows` holds `nobs` objects.
unsafe fn check_strings(py: Python<'_>, name: &str, rows: *const *mut ffi::PyObject, nobs: usize) -> PyResult<bool> {
    let mut any_binary = false;
    for r in 0..nobs {
        let obj = *rows.add(r);
        if ffi::PyBytes_Check(obj) != 0 {
            any_binary = true;
        } else if ffi::PyUnicode_Check(obj) != 0 {
            let mut n: ffi::Py_ssize_t = 0;
            if ffi::PyUnicode_AsUTF8AndSize(obj, &mut n).is_null() {
                let e = PyErr::fetch(py);
                return Err(fail(format!("{name} row {}: {e}", r + 1)));
            }
        } else {
            let value = Bound::from_borrowed_ptr(py, obj);
            let kind = value.get_type().name()?;
            return Err(fail(format!("{name} row {}: cannot write a {kind} as a string", r + 1)));
        }
    }
    Ok(any_binary)
}

fn storage_type(name: &str) -> Option<StorageType> {
    Some(match name {
        "byte" => StorageType::Byte,
        "int" => StorageType::Int,
        "long" => StorageType::Long,
        "float" => StorageType::Float,
        "double" => StorageType::Double,
        "strL" => StorageType::StrL,
        "str" => StorageType::Str(1),
        _ => return None,
    })
}

/// (name, storage, format, label, value label set, dtype, data, codes)
type WriteColumn = (String, String, String, String, String, String, usize, usize);

/// (name, [(value, missing code, text)])
type LabelSet = (String, Vec<(f64, u8, String)>);

/// Write release 118 to `path`. Each column's `data` is the address of a
/// numpy buffer of `nobs` elements of dtype `i1` ... `f8` or `b1` (numbers,
/// with `codes` the address of uint8 codes or 0) or `O` (objects, each a
/// `str` or `bytes`). The caller keeps the arrays alive for the call.
#[pyfunction]
#[allow(clippy::too_many_arguments)]
fn write(
    py: Python<'_>,
    path: &str,
    nobs: usize,
    columns: Vec<WriteColumn>,
    value_labels: Vec<LabelSet>,
    characteristics: Vec<(String, String, String)>,
    label: String,
    timestamp: String,
    sort_order: Vec<usize>,
) -> PyResult<()> {
    let mut variables = Vec::with_capacity(columns.len());
    for (name, storage, format, var_label, set, kind, addr, codes) in columns {
        let storage = storage_type(&storage).ok_or_else(|| fail(format!("{name}: unknown storage type {storage}")))?;
        let values = if kind == "O" {
            let rows = addr as *const *mut ffi::PyObject;
            let binary = unsafe { check_strings(py, &name, rows, nobs)? };
            let get = move |r: usize| unsafe { string_row(*rows.add(r)) };
            if binary {
                Values::StrLs(Box::new(get))
            } else {
                Values::Strings(Box::new(move |r| get(r).0))
            }
        } else {
            unsafe { numbers(&kind, addr, codes, nobs) }.map_err(|e| fail(format!("{name}: {e}")))?
        };
        variables.push(WriteVariable { name, storage, format, label: var_label, value_labels: set, values });
    }
    let value_labels = value_labels
        .into_iter()
        .map(|(name, labels)| ValueLabelSet {
            name,
            labels: labels.into_iter().map(|(value, missing, text)| ValueLabel { value, missing, text }).collect(),
        })
        .collect();
    let characteristics =
        characteristics.into_iter().map(|(variable, name, value)| Characteristic { variable, name, value }).collect();
    let data = Dataset { nobs, label, timestamp, variables, value_labels, characteristics, sort_order };
    // Write beside the target and rename, so a failed write leaves any
    // existing file as it was.
    let (tmp, file) = create_beside(path).map_err(|e| fail(format!("{path}: {e}")))?;
    if let Err(e) = dta::write(&data, file) {
        let _ = std::fs::remove_file(&tmp);
        return Err(fail(format!("{path}: {e}")));
    }
    std::fs::rename(&tmp, path).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        fail(format!("{path}: {e}"))
    })
}

/// A new file beside `path` that no one else has: created exclusively
/// (so neither an existing file nor a symlink at the name is touched).
fn create_beside(path: &str) -> std::io::Result<(String, std::fs::File)> {
    let pid = std::process::id();
    for n in 0..1000 {
        let tmp = format!("{path}.{pid}.{n}.tmp");
        match std::fs::OpenOptions::new().write(true).create_new(true).open(&tmp) {
            Ok(file) => return Ok((tmp, file)),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(std::io::Error::other("no free name for a temporary file"))
}

#[pymodule]
fn _native(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(meta, m)?)?;
    m.add_function(wrap_pyfunction!(read, m)?)?;
    m.add_function(wrap_pyfunction!(write, m)?)?;
    Ok(())
}
