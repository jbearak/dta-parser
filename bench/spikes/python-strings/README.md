# Spike: making Python strings (ADR 0014)

How long CPython takes to turn one UTF-8 buffer and its offsets into a
list of 10M `str`, by the paths open to a binding. Generated data, no
files needed.

    python3 ctypes_paths.py          # pure-Python paths a ctypes binding would use
    cd pyo3s && maturin develop --release && cd ..
    python3 pyo3_time.py             # a Rust loop through PyO3

`pyo3s` is a throwaway crate, outside the workspace.
