//! datakit's Parquet functions: `parquet_read_arrow`,
//! `parquet_info_arrow` and `parquet_write_arrow`, over
//! `crate::arrow::read` and `crate::arrow::write`.

use std::collections::{HashMap, HashSet};

use pyo3::exceptions::{PyTypeError, PyValueError};
use pyo3::prelude::*;
use pyo3::types::{PyBytes, PyDict, PyList, PyString, PyTuple};

use dta::Source;

use super::{import, meta_dict, raise, read_tuple, selectors};
use crate::arrow::ffi::Imported;
use crate::arrow::meta::{Code, ColumnEntry, GivenSet, ParquetInfo, WriteMeta};
use crate::arrow::parquet::Input;
use crate::arrow::read::{parquet_info, parquet_read, Stamps};
use crate::arrow::write::{parquet_options, parquet_write};

/// A binary Python file object with `seek` and `read`, read on the
/// calling thread (it is not shared, so a read from one decodes on one
/// thread).
pub(crate) struct PyFile {
    file: Py<PyAny>,
    len: u64,
}

impl PyFile {
    pub(crate) fn new(file: &Bound<'_, PyAny>) -> PyResult<Self> {
        let len: u64 = file.call_method1("seek", (0, 2))?.extract()?;
        Ok(PyFile { file: file.clone().unbind(), len })
    }
}

impl Source for PyFile {
    fn len(&self) -> u64 {
        self.len
    }

    fn read_at(&mut self, offset: u64, buf: &mut [u8]) -> dta::Result<()> {
        Python::attach(|py| -> PyResult<()> {
            let f = self.file.bind(py);
            f.call_method1("seek", (offset,))?;
            let mut at = 0;
            while at < buf.len() {
                let got = f.call_method1("read", (buf.len() - at,))?;
                let got = got.cast::<PyBytes>().map_err(|_| PyTypeError::new_err("read() did not return bytes"))?;
                let b = got.as_bytes();
                if b.is_empty() {
                    return Err(PyValueError::new_err("the file ended early"));
                }
                buf[at..at + b.len()].copy_from_slice(b);
                at += b.len();
            }
            Ok(())
        })
        .map_err(|e| dta::Error::new(format!("reading the file object: {e}")))
    }
}

/// Where a file comes from: a path (`str`), the whole file (`bytes`), or
/// a binary file object.
fn input<'a>(source: &'a Bound<'a, PyAny>) -> PyResult<Input<'a>> {
    if let Ok(s) = source.cast::<PyString>() {
        return Ok(Input::Path(s.to_str()?.to_string()));
    }
    if let Ok(b) = source.cast::<PyBytes>() {
        return Ok(Input::Bytes(b.as_bytes()));
    }
    Ok(Input::Source(Box::new(PyFile::new(source)?)))
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
    let mode = Stamps::from_name(timestamps).map_err(raise)?;
    let input = input(source)?;
    let columns = selectors(columns.as_deref())?;
    let out = py
        .detach(|| {
            parquet_read(input, columns.as_deref(), skip, n_max, nested_skip, mode, threads, enum_metadata, &mut read_tuple)
        })
        .map_err(raise)??;
    Ok(out.into_bound(py))
}

/// The footer of a Parquet file, for datakit's `read_parquet_info`: a
/// dict of rows, row_groups [(rows, compressed, uncompressed)],
/// created_by, compression, key_value [(key, text)], meta (as
/// `parquet_read_arrow` gives it, for every data column it reads, with
/// the file's rows) and columns [(name, role, format, flag, levels,
/// physical_type, logical_type, label, value_labels, storage)], where
/// `format` is the Arrow format a read gives (None for a column it does
/// not read), `flag` as in `meta`'s columns, and `levels` an Enum's
/// levels. For datakit only.
#[pyfunction]
pub fn parquet_info_arrow<'py>(py: Python<'py>, source: &Bound<'py, PyAny>) -> PyResult<Bound<'py, PyDict>> {
    let input = input(source)?;
    let out = py.detach(|| parquet_info(input, &mut |info| Python::attach(|py| info_dict(py, &info).map(Bound::unbind))));
    Ok(out.map_err(raise)??.into_bound(py))
}

/// [`parquet_info_arrow`]'s dict.
fn info_dict<'py>(py: Python<'py>, info: &ParquetInfo<'_>) -> PyResult<Bound<'py, PyDict>> {
    let list = PyList::empty(py);
    for c in &info.columns {
        list.append((
            c.name.as_ref(),
            c.role,
            &c.format,
            &c.flag,
            &c.levels,
            &c.physical_type,
            &c.logical_type,
            c.label.as_deref(),
            c.value_labels.as_deref(),
            c.storage,
        ))?;
    }
    let m = meta_dict(py, &info.meta)?;
    let out = PyDict::new(py);
    out.set_item("rows", info.rows)?;
    out.set_item("row_groups", &info.row_groups)?;
    out.set_item("created_by", &info.created_by)?;
    out.set_item("compression", &info.compression)?;
    out.set_item("key_value", &info.key_value)?;
    out.set_item("columns", list)?;
    out.set_item("meta", m)?;
    Ok(out)
}

/// The names of an imported frame's columns.
pub(crate) fn column_names(imported: &Imported) -> Vec<&str> {
    imported.schema.children.iter().map(|f| f.name.as_str()).collect()
}

/// `meta[key]`, None when absent or None.
pub(crate) fn item<'py>(meta: Option<&Bound<'py, PyDict>>, key: &str) -> PyResult<Option<Bound<'py, PyAny>>> {
    Ok(match meta {
        Some(m) => m.get_item(key)?.filter(|v| !v.is_none()),
        None => None,
    })
}

/// `meta.value_labels`: {set: {code: text}}, a code an int, a float or
/// `.`/`.a`-`.z` as text (which the writer checks).
pub(crate) fn value_labels(sets: &Bound<'_, PyDict>) -> PyResult<Vec<GivenSet>> {
    let mut out = Vec::with_capacity(sets.len());
    for (name, table) in sets.iter() {
        let name: String = name.extract()?;
        let table = table
            .cast_into::<PyDict>()
            .map_err(|_| PyTypeError::new_err(format!("value label set \"{name}\" is not a dict")))?;
        let mut labels = Vec::with_capacity(table.len());
        for (code, text) in table.iter() {
            let text: String = text
                .extract()
                .map_err(|_| PyTypeError::new_err(format!("value label set \"{name}\": a label is not text")))?;
            let code = if let Ok(s) = code.cast::<PyString>() {
                Code::Text(s.to_str()?.to_string())
            } else {
                Code::Number(code.extract().map_err(|_| {
                    PyTypeError::new_err(format!("value label set \"{name}\": a code is not a number or a missing code"))
                })?)
            };
            labels.push((code, text));
        }
        out.push((name, labels));
    }
    Ok(out)
}

/// The entry `meta.columns` gives each of `names` that has one.
pub(crate) fn column_entries(entries: &Bound<'_, PyDict>, names: &[&str]) -> PyResult<HashMap<String, ColumnEntry>> {
    let mut out = HashMap::new();
    for &name in names {
        let Some(e) = entries.get_item(name)? else { continue };
        type Entry = (Option<String>, Option<String>, Option<String>, Option<bool>);
        let (label, format, value_labels, ordered): Entry = e.extract()?;
        out.insert(name.to_string(), ColumnEntry { label, format, value_labels, ordered });
    }
    Ok(out)
}

/// What `parquet_write_arrow` takes of `meta`, read in the order the
/// writer read it before it lost pyo3.
fn write_meta(meta: Option<&Bound<'_, PyDict>>, names: &[&str], missing_letters: bool) -> PyResult<WriteMeta> {
    let mut out = WriteMeta::default();
    let present: HashSet<&str> = names.iter().copied().collect();
    if let Some(m) = item(meta, "missing")? {
        let m = m.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.missing is not a dict"))?;
        for (name, series) in m.iter() {
            let name: String = name.extract()?;
            if !present.contains(name.as_str()) || !missing_letters {
                continue;
            }
            let letters = import(&series)?;
            out.missing.push((name, letters));
        }
    }
    out.label = item(meta, "label")?.map(|v| v.extract()).transpose()?;
    out.timestamp = item(meta, "timestamp")?.map(|v| v.extract()).transpose()?;
    out.notes = item(meta, "notes")?.map(|v| v.extract()).transpose()?.unwrap_or_default();
    out.sort = item(meta, "sort")?.map(|v| v.extract()).transpose()?.unwrap_or_default();
    if let Some(chars) = item(meta, "characteristics")? {
        let chars = chars.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.characteristics is not a dict"))?;
        for (var, entries) in chars.iter() {
            let variable: String = var.extract()?;
            let entries =
                entries.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("a characteristics entry is not a dict"))?;
            let mut list = Vec::with_capacity(entries.len());
            for (name, value) in entries.iter() {
                list.push((name.extract()?, value.extract()?));
            }
            out.characteristics.push((variable, list));
        }
    }
    if let Some(sets) = item(meta, "value_labels")? {
        let sets = sets.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.value_labels is not a dict"))?;
        out.value_labels = value_labels(&sets)?;
    }
    if let Some(c) = item(meta, "columns")? {
        let c = c.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.columns is not a dict"))?;
        out.columns = column_entries(&c, names)?;
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
    let mode = Stamps::from_name(timestamps).map_err(raise)?;
    let options =
        parquet_options(compression, compression_level, row_group_size, missing_letters, threads).map_err(raise)?;
    let imported = import(df)?;
    let meta = write_meta(meta, &column_names(&imported), missing_letters)?;
    let written = py.detach(|| parquet_write(&imported, path.as_deref(), &meta, options, mode)).map_err(raise)?;
    // The frame's buffers are released with the GIL held, as before.
    drop(meta);
    drop(imported);
    Ok(written.map(|buf| PyBytes::new(py, &buf)))
}
