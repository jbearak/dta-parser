//! datakit's `.dta` functions: `dta_read_arrow` and `dta_write_arrow`,
//! over `dta_arrow::dta`.

use std::collections::HashSet;

use pyo3::exceptions::PyTypeError;
use pyo3::prelude::*;
use pyo3::types::{PyDict, PyTuple};

use super::parquet::{column_entries, column_names, item, value_labels};
use super::{import, raise, read_tuple, selectors};
use dta_arrow::dta::{dta_read, dta_write, CATEGORICAL_MARK, FACTOR_MARK};
use dta_arrow::meta::WriteMeta;
use dta_arrow::read::Stamps;

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
    let mode = Stamps::from_name(timestamps).map_err(raise)?;
    let columns = selectors(columns.as_deref())?;
    let out = py.detach(|| dta_read(path, columns.as_deref(), skip, n_max, encoding, mode, &mut read_tuple)).map_err(raise)??;
    Ok(out.into_bound(py))
}

/// What `dta_write_arrow` takes of `meta`, read in the order the writer
/// read it before it lost pyo3: characteristics only of the frame's
/// columns and `_dta`, and without the markers the writer drops.
fn write_meta(meta: Option<&Bound<'_, PyDict>>, names: &[&str], missing_letters: bool) -> PyResult<WriteMeta> {
    let mut out = WriteMeta::default();
    let present: HashSet<&str> = names.iter().copied().collect();
    if let (Some(m), true) = (item(meta, "missing")?, missing_letters) {
        let m = m.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.missing is not a dict"))?;
        for (name, series) in m.iter() {
            let name: String = name.extract()?;
            if !present.contains(name.as_str()) {
                continue;
            }
            let letters = import(&series)?;
            out.missing.push((name, letters));
        }
    }
    let entries = match item(meta, "columns")? {
        Some(c) => Some(c.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.columns is not a dict"))?),
        None => None,
    };
    if let Some(s) = item(meta, "value_labels")? {
        out.value_labels =
            value_labels(&s.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.value_labels is not a dict"))?)?;
    }
    if let Some(entries) = &entries {
        out.columns = column_entries(entries, names)?;
    }
    if let Some(chars) = item(meta, "characteristics")? {
        let chars = chars.cast_into::<PyDict>().map_err(|_| PyTypeError::new_err("meta.characteristics is not a dict"))?;
        for (var, entries) in chars.iter() {
            let variable: String = var.extract()?;
            if variable != "_dta" && !present.contains(variable.as_str()) {
                continue;
            }
            let mut list = Vec::new();
            for (n, v) in entries.cast_into::<PyDict>()?.iter() {
                let name: String = n.extract()?;
                if variable != "_dta" && (name == FACTOR_MARK || name == CATEGORICAL_MARK) {
                    continue;
                }
                list.push((name, v.extract()?));
            }
            out.characteristics.push((variable, list));
        }
    }
    out.notes = item(meta, "notes")?.map(|v| v.extract()).transpose()?.unwrap_or_default();
    out.sort = item(meta, "sort")?.map(|v| v.extract()).transpose()?.unwrap_or_default();
    out.label = item(meta, "label")?.map(|v| v.extract()).transpose()?;
    out.timestamp = item(meta, "timestamp")?.map(|v| v.extract()).transpose()?;
    Ok(out)
}

/// Write the polars frame `df` as release 118 to `path`. `meta` as for
/// `parquet_write_arrow`. Each Enum or Categorical is codes 1 to k with
/// its levels, the letter labels of the set meta names for it, and a
/// `dtaparser_categorical` characteristic; meta's markers are dropped.
/// For datakit only.
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
    let mode = Stamps::from_name(timestamps).map_err(raise)?;
    let imported = import(df)?;
    let meta = write_meta(meta, &column_names(&imported), missing_letters)?;
    // With the GIL held, as write_dta: text is read through polars'
    // buffers, which the GIL keeps from being freed under us.
    dta_write(&imported, path, &meta, missing_letters, mode, timestamp).map_err(raise)
}
