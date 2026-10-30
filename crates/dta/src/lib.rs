//! Read and write Stata `.dta` files.
//!
//! The crate does no I/O of its own: a [`Reader`] reads through a
//! [`Source`] and [`write`] writes to any `std::io::Write`, so the same code serves files on disk (R) and byte ranges
//! supplied by JavaScript (wasm).

mod cursor;
mod encoding;
mod error;
mod header;
mod legacy;
pub mod missing;
mod reader;
mod source;
pub mod threads;
mod types;
mod writer;

pub use cursor::ByteOrder;
pub use encoding::Encoding;
pub use error::{Error, Result};
pub use header::{Metadata, Variable};
pub use reader::{Characteristic, Column, Options, Reader, ValueLabel, ValueLabelSet};
pub use source::{Bytes, FileSource, Source};
pub use types::StorageType;
pub use writer::{write, write_with, Dataset, Values, WriteOptions, WriteVariable, BLOCK};
