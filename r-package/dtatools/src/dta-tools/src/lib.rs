//! Native reading and writing primitives for Stata `.dta` files.
//!
//! The crate parses releases 105, 108, 110 through 111, 113 through 115, and
//! 117 through 119 into column-oriented data. It retains numeric storage
//! widths, fixed strings, resolved `strL` values, exact missing tags, metadata,
//! and value-label tables.
//!
//! The crate is the internal read/write core used by the repository's R
//! package. It is not published to crates.io.
//!
//! # Read complete file bytes
//!
//! ```no_run
//! use dta_tools::read_dta;
//!
//! let bytes = std::fs::read("data.dta")?;
//! let data = read_dta(&bytes)?;
//! println!("{} columns", data.columns.len());
//! # Ok::<(), Box<dyn std::error::Error>>(())
//! ```
//!
//! Use [`read_dta_with_options`] for row windows and column projections. Use a
//! [`TextEncoding`] override when a pre-Unicode file is not Windows-1252.
//!
//! # Read from a seekable source
//!
//! [`DtaFile`] parses metadata when it opens and leaves observation data on
//! the source until requested. Its temporary raw-byte allocations and read
//! requests are bounded by [`FileOptions::max_buffer_bytes`].
//!
//! ```no_run
//! use dta_tools::{DtaFile, ReadOptions};
//!
//! let mut file = DtaFile::open("data.dta")?;
//! let page = file.read_with_options(&ReadOptions {
//!     row_start: 1_000,
//!     row_count: Some(100),
//!     column_indices: Some(vec![0, 4, 9]),
//! })?;
//! println!("{} selected columns", page.columns.len());
//! # Ok::<(), Box<dyn std::error::Error>>(())
//! ```
//!
//! [`ColumnValues`] retains each numeric source width and carries a parallel
//! missing-tag classification. [`DtaSink`] and [`ParallelDtaSink`] let native
//! adapters materialize another column store through the same validated
//! decoder.

pub mod arrow;
mod data_reader;
mod endian;
mod error;
mod file;
mod legacy;
mod metadata;
mod missing;
mod selection;
mod stata_metadata;
mod strl;
mod text;
mod types;
mod value_labels;
mod write;

pub use data_reader::{
    read_dta, read_dta_with_encoding, read_dta_with_options, read_dta_with_options_and_encoding,
};
pub use error::DtaError;
pub use file::{DtaColumnSink, DtaFile, DtaSink, FileOptions, ParallelDtaSink};
pub use metadata::{parse_metadata, parse_metadata_with_encoding};
pub use missing::{
    classify_byte_missing, classify_byte_missing_for_version, classify_double_missing_bits,
    classify_float_missing_bits, classify_float_missing_bits_for_version, classify_int_missing,
    classify_int_missing_for_version, classify_long_missing, classify_long_missing_for_version,
    MissingTag, DOUBLE_MISSING_DOT_BITS, DOUBLE_MISSING_STEP_BITS, DOUBLE_MISSING_Z_BITS,
    FLOAT_MISSING_DOT_BITS, FLOAT_MISSING_STEP_BITS, FLOAT_MISSING_Z_BITS,
};
pub use stata_metadata::{
    valid_canonical_characteristic, valid_canonical_note, valid_characteristic, valid_note,
};
pub use text::TextEncoding;
pub use types::{
    ByteOrder, Column, ColumnValues, DtaData, DtaMetadata, DtaType, FormatVersion, ReadOptions,
    SectionOffsets, StataCharacteristic, StataNote, ValueLabelEntry, ValueLabelTable, VariableInfo,
};
pub use value_labels::{parse_value_labels, parse_value_labels_with_encoding};
pub use write::{
    dta_write_numeric_value_is_representable, encode_numeric, save_dta_to,
    write_prevalidated_dta_with_observation_source_to, DtaWriteCharacteristic, DtaWriteColumn,
    DtaWriteColumnSource, DtaWriteColumnValues, DtaWriteData, DtaWriteError, DtaWriteLabelValue,
    DtaWriteNote, DtaWriteNumericValue, DtaWriteObservationSource, DtaWriteOptions,
    DtaWriteRawNumericValue, DtaWriteSummary, DtaWriteValueLabel,
};
#[cfg(feature = "r-adapter-internal")]
#[doc(hidden)]
pub use write::{
    write_prevalidated_dta_with_value_label_registry_to, DtaWriteValueLabelRegistry,
    DtaWriteValueLabelTable,
};
