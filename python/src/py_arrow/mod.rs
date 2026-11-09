//! The Python binding of `crate::arrow` (plan 0025, stage 2a): the
//! functions datakit calls, which turn Python's arguments into what the
//! pyo3-free modules take, release the GIL around them where they did
//! before, and turn what they give back into the tuples, dicts and
//! exceptions datakit has always had. These functions are internal to
//! dta_parser and versioned by `ABI_VERSION`; datakit is their only
//! caller.
//!
//! Here, not in `crate::arrow`: Python's file objects (a [`dta::Source`]),
//! the PyCapsules of `__arrow_c_stream__`, the `ArrowTable` class, the
//! digest (`arrow_digest`, Python's alone) and the ABI number.

pub(crate) mod digest;
pub(crate) mod dta;
pub(crate) mod parquet;

use std::ffi::{c_void, CStr};

use pyo3::exceptions::{PyIndexError, PyKeyError, PyMemoryError, PyTypeError, PyValueError};
use pyo3::ffi;
use pyo3::prelude::*;
use pyo3::types::{PyDict, PyList, PyString, PyTuple};

use crate::arrow::error::Error;
use crate::arrow::ffi::{export_stream, import_stream, ArrowArrayStream, Imported, Table};
use crate::arrow::meta::{LabelKey, ReadMeta, ReadOutput};
use crate::arrow::parquet::Selector;

/// The version of the functions datakit calls; datakit checks it when it
/// loads. Raise it when any of them changes what it takes or gives.
pub const ABI_VERSION: u32 = 1;

/// The Python exception of an error of `crate::arrow`.
pub(crate) fn raise(e: Error) -> PyErr {
    match e {
        Error::Value(m) => PyValueError::new_err(m),
        Error::Key(m) => PyKeyError::new_err(m),
        Error::Index(m) => PyIndexError::new_err(m),
        Error::Type(m) => PyTypeError::new_err(m),
        Error::Memory(m) => PyMemoryError::new_err(m),
    }
}

// ------------------------------------------------------------ streams

const STREAM: &CStr = c"arrow_array_stream";

unsafe extern "C" fn capsule_destructor(cap: *mut ffi::PyObject) {
    let p = ffi::PyCapsule_GetPointer(cap, STREAM.as_ptr()) as *mut ArrowArrayStream;
    if p.is_null() {
        ffi::PyErr_Clear();
        return;
    }
    // A consumer that took the stream set its release to null.
    if let Some(r) = (*p).release {
        r(p);
    }
    drop(Box::from_raw(p));
}

/// `table` as a PyCapsule holding an `ArrowArrayStream`.
pub(crate) fn stream_capsule<'py>(py: Python<'py>, table: &Table) -> PyResult<Bound<'py, PyAny>> {
    let stream = Box::into_raw(Box::new(export_stream(table)));
    // SAFETY: the capsule owns `stream` and releases it unless the
    // consumer moved it out.
    unsafe {
        let cap = ffi::PyCapsule_New(stream as *mut c_void, STREAM.as_ptr(), Some(capsule_destructor));
        if cap.is_null() {
            if let Some(r) = (*stream).release {
                r(stream);
            }
            drop(Box::from_raw(stream));
            return Err(PyErr::fetch(py));
        }
        Ok(Bound::from_owned_ptr(py, cap))
    }
}

/// Take every batch of `obj.__arrow_c_stream__()`.
pub(crate) fn import(obj: &Bound<'_, PyAny>) -> PyResult<Imported> {
    let cap = obj
        .call_method0("__arrow_c_stream__")
        .map_err(|_| PyTypeError::new_err("the object does not export an Arrow stream (__arrow_c_stream__)"))?;
    // SAFETY: a capsule named arrow_array_stream holds an ArrowArrayStream,
    // which import_stream moves out, leaving the capsule's released; the
    // capsule lives until the import is done.
    unsafe {
        let p = ffi::PyCapsule_GetPointer(cap.as_ptr(), STREAM.as_ptr()) as *mut ArrowArrayStream;
        if p.is_null() {
            return Err(PyErr::fetch(obj.py()));
        }
        import_stream(p).map_err(raise)
    }
}

/// An object polars (or pyarrow) takes with `pl.DataFrame(obj)`: it
/// exports its table as often as asked, every export sharing the buffers.
#[pyclass(frozen, module = "dta_parser._native")]
pub(crate) struct ArrowTable {
    pub(crate) table: Table,
}

#[pymethods]
impl ArrowTable {
    #[pyo3(signature = (requested_schema = None))]
    fn __arrow_c_stream__<'py>(
        &self,
        py: Python<'py>,
        requested_schema: Option<Bound<'py, PyAny>>,
    ) -> PyResult<Bound<'py, PyAny>> {
        let _ = requested_schema;
        stream_capsule(py, &self.table)
    }

    /// The columns' names, in order.
    #[getter]
    fn names(&self) -> Vec<String> {
        self.table.fields.iter().map(|f| f.name.clone()).collect()
    }

    /// Rows, over every batch.
    #[getter]
    fn rows(&self) -> usize {
        self.table.batches.iter().map(|b| b.length).sum()
    }

    /// Per column, the address of its values buffer (keys for a
    /// dictionary, views for text), for tests that check polars took the
    /// buffers without a copy.
    #[getter]
    fn addresses(&self) -> Vec<usize> {
        self.table.batches.first().map_or_else(Vec::new, |b| {
            b.children.iter().map(|c| c.buffers.get(1).copied().unwrap_or(0)).collect()
        })
    }
}

// ------------------------------------------------------------ reads

/// The columns a read asks for: a `str` is a name, what extracts as an
/// integer a position, anything else an error once the file is open.
pub(crate) fn selectors(columns: Option<&[Bound<'_, PyAny>]>) -> PyResult<Option<Vec<Selector>>> {
    let Some(columns) = columns else { return Ok(None) };
    let mut out = Vec::with_capacity(columns.len());
    for w in columns {
        out.push(if let Ok(name) = w.cast::<PyString>() {
            Selector::Name(name.to_str()?.to_string())
        } else {
            match w.extract::<i64>() {
                Ok(i) => Selector::Position(i),
                Err(_) => Selector::Other,
            }
        });
    }
    Ok(Some(out))
}

/// A read's `(frame, letters, meta)`: the frame and letters (or None) as
/// `ArrowTable`s, `meta` as [`meta_dict`] makes it. Called from a read's
/// callback, without the GIL, which it takes.
pub(crate) fn read_tuple(out: ReadOutput<'_>) -> PyResult<Py<PyTuple>> {
    Python::attach(|py| {
        let meta = meta_dict(py, &out.meta)?;
        let letters: Py<PyAny> = match out.letters {
            Some(table) => Py::new(py, ArrowTable { table })?.into_any(),
            None => py.None(),
        };
        let frame = Py::new(py, ArrowTable { table: out.frame })?.into_any();
        Ok(PyTuple::new(py, [frame, letters, meta.into_any().unbind()])?.unbind())
    })
}

/// A value label's code as a Python key: an int, a float, or text.
fn label_key<'py>(py: Python<'py>, key: &LabelKey) -> PyResult<Bound<'py, PyAny>> {
    Ok(match key {
        LabelKey::Int(v) => v.into_pyobject(py)?.into_any(),
        LabelKey::Float(v) => v.into_pyobject(py)?.into_any(),
        LabelKey::Missing(c) => PyString::new(py, LabelKey::name(*c)).into_any(),
    })
}

/// What `Meta` is made from, as the dict datakit reads: rows, names,
/// columns [(name, label, format, value_labels, ordered, storage, flag,
/// eligible)], value_labels {set: {code: text}}, label, notes,
/// characteristics {variable: {name: text}}, sort, timestamp, warnings,
/// letter_columns, and a Parquet read's steps or a `.dta` read's release
/// (whose keys are in the order each read has always given).
pub(crate) fn meta_dict<'py>(py: Python<'py>, m: &ReadMeta<'_>) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    out.set_item("rows", m.rows)?;
    out.set_item("names", m.columns.iter().map(|c| c.name.as_ref()).collect::<Vec<&str>>())?;
    let list = PyList::empty(py);
    for c in &m.columns {
        list.append((
            c.name.as_ref(),
            c.label.as_deref(),
            c.format.as_deref(),
            c.value_labels.as_deref(),
            c.ordered,
            c.storage.as_deref(),
            &c.flag,
            c.eligible,
        ))?;
    }
    out.set_item("columns", list)?;
    let sets = PyDict::new(py);
    for (name, labels) in &m.value_labels {
        let d = PyDict::new(py);
        for (key, text) in labels {
            d.set_item(label_key(py, key)?, text.as_ref())?;
        }
        sets.set_item(name.as_ref(), d)?;
    }
    out.set_item("value_labels", sets)?;
    out.set_item("label", &m.label)?;
    let dta = m.release.is_some();
    if dta {
        out.set_item("timestamp", &m.timestamp)?;
    }
    out.set_item("notes", &m.notes)?;
    let chars = PyDict::new(py);
    for (variable, name, value) in &m.characteristics {
        let d = match chars.get_item(variable)? {
            Some(d) => d.cast_into::<PyDict>()?,
            None => {
                let d = PyDict::new(py);
                chars.set_item(variable, &d)?;
                d
            }
        };
        d.set_item(name, value)?;
    }
    out.set_item("characteristics", chars)?;
    out.set_item("sort", &m.sort)?;
    if !dta {
        out.set_item("timestamp", &m.timestamp)?;
    }
    out.set_item("warnings", &m.warnings)?;
    out.set_item("letter_columns", &m.letter_columns)?;
    if let Some(steps) = &m.steps {
        out.set_item("steps", steps)?;
    }
    if let Some(release) = m.release {
        out.set_item("release", release)?;
    }
    Ok(out)
}
