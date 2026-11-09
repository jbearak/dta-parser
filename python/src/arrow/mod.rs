//! Arrow memory for datakit (plan 0019): reads that polars adopts without
//! a copy, writes from polars' own export, and `.dta` files read and
//! written through the same buffers.
//!
//! Nothing here uses pyo3 (plan 0025, stage 2a): it takes paths, bytes
//! or a [`dta::Source`], raw Arrow C streams and plain Rust structs
//! ([`meta::ReadMeta`], [`meta::WriteMeta`]), and returns [`error::Error`].
//! `crate::py_arrow` is the Python binding, which datakit calls.

pub(crate) mod dta;
pub(crate) mod error;
pub(crate) mod ffi;
pub(crate) mod meta;
pub(crate) mod parquet;
pub(crate) mod read;
pub(crate) mod write;

/// A new file beside `path` that no one else has: created exclusively
/// (so neither an existing file nor a symlink at the name is touched).
pub(crate) fn create_beside(path: &str) -> std::io::Result<(String, std::fs::File)> {
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
