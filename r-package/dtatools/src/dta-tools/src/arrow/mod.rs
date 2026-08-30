//! The dtatools Arrow profile: Arrow IPC file reading and writing under the
//! versioned `dtatools:*` metadata contract.
//!
//! The profile stores profiled numeric columns in raw Stata missing storage
//! (sentinel integers and NaN payloads, no validity bitmaps), carries dataset
//! and field metadata as versioned JSON documents, and records per-buffer
//! xxHash64 checksums in the file footer. The prototype writes profile
//! version "0", which carries no stability promise.

mod checksum;
mod profile;
mod read;
mod write;

pub use profile::{
    ArrowFieldDocument, ArrowMissingEncoding, ArrowRSemantics, ArrowValueLabelEntry,
    DatasetDocument, StataStorage, ARROW_CHECKSUMS_KEY, ARROW_DATASET_KEY, ARROW_FIELD_KEY,
    ARROW_PROFILE_VERSION, ARROW_PROFILE_VERSION_KEY,
};
pub use read::{
    arrow_stored_signature, read_arrow_file, read_arrow_file_from, summarize_arrow_file,
    ArrowColumnSummary, ArrowFileSnapshot, ArrowFileSummary, ArrowReadColumn, ArrowReadOptions,
    ArrowReadResult,
};
pub use write::{
    dataset_signature, save_arrow_file, save_arrow_file_to, ArrowCompression, ArrowWriteColumn,
    ArrowWriteDataset, ARROW_ROWS_PER_BATCH,
};

use thiserror::Error;

/// Failure while reading or writing a dtatools Arrow profile file.
#[derive(Debug, Error)]
pub enum ArrowProfileError {
    #[error("Arrow file I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("{0} is not an Arrow IPC file (missing ARROW1 magic bytes; the IPC stream variant is not supported)")]
    NotAnArrowFile(String),
    #[error("invalid Arrow IPC file: {0}")]
    InvalidFile(String),
    #[error(
        "this file uses dtatools Arrow profile version \"{0}\", which this version of dtatools \
         does not understand; upgrade the dtatools package, or pass `profile = FALSE` to read \
         the raw storage arrays without Stata semantics"
    )]
    NewerProfile(String),
    #[error(
        "malformed dtatools Arrow profile metadata (profile version \"{version}\"): {detail}; \
         pass `profile = FALSE` to read the raw storage arrays without Stata semantics"
    )]
    MalformedProfile { version: String, detail: String },
    #[error("column `{column}` has unsupported Arrow type {data_type}")]
    UnsupportedColumn { column: String, data_type: String },
    #[error(
        "checksum mismatch in column `{column}`, record batch {batch}: the file is corrupt \
         (pass `verify = FALSE` to read it anyway)"
    )]
    ChecksumMismatch { column: String, batch: usize },
    #[error("interrupted")]
    Interrupted,
    #[error("{0}")]
    Invalid(String),
}
