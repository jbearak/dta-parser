use pyo3::prelude::*;
use pyo3::types::{PyList, PyString};
#[pyfunction]
fn strings<'py>(py: Python<'py>, buf: &[u8], offs: Vec<u64>) -> PyResult<Bound<'py, PyList>> {
    let n = offs.len() - 1;
    let items = (0..n).map(|i| {
        let s = unsafe { std::str::from_utf8_unchecked(&buf[offs[i] as usize..offs[i + 1] as usize]) };
        PyString::new(py, s)
    });
    PyList::new(py, items)
}
#[pymodule]
fn pyo3s(m: &Bound<'_, PyModule>) -> PyResult<()> { m.add_function(wrap_pyfunction!(strings, m)?) }
