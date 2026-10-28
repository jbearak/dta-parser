# Python binds the core through PyO3; Julia through a C ABI

Plan 0005 first proposed one native C ABI for both Python (ctypes) and
Julia (ccall). The cost to settle was making a Python `str` per value,
which dominates string-heavy reads. Measured on 10M nine-byte values in
random order (M4 Max, CPython 3.14), building the list of strings from
one UTF-8 buffer and its offsets:

| path | seconds |
|---|---|
| ctypes, then a Python loop decoding each slice | 0.87 |
| ctypes, then one decode and a slice per value (ASCII only) | 0.43 |
| ctypes, then numpy fixed-width bytes to `U` to list | 0.54 |
| PyO3, a Rust loop making each `str` | 0.16 |

PyO3 is 2.7× faster than the best ctypes path and 5× faster than the
general one, past the 1.3× threshold the plan set before measuring. (The
spike built PyO3 without `abi3`; the package uses abi3 wheels, whose
string calls are the same C API.) So the Python package is a
PyO3 extension module that calls the Rust core directly and fills numpy
arrays Python allocated; it needs no C ABI. Building and packaging use
maturin, the usual tool for PyO3, which also makes manylinux, macOS and
Windows wheels. PyO3 is a dependency of the Python binding only; the
core stays dependency-free.

Julia's `String` is made from bytes cheaply on the Julia side, and
Julia has no extension-module equivalent, so Julia uses the native C ABI
in `dta-ffi`.
