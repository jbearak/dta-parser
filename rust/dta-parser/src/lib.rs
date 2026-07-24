//! Native parsing primitives for Stata `.dta` files.
//!
//! The crate parses metadata, numeric and fixed-string observations, row and
//! column projections, missing tags, and value-label tables for format
//! versions 117 through 119. `strL` payload resolution is intentionally not
//! part of the current API.

mod data_reader;
mod endian;
mod error;
mod metadata;
mod missing;
mod types;
mod value_labels;

pub use data_reader::{read_dta, read_dta_with_options};
pub use error::DtaError;
pub use metadata::parse_metadata;
pub use missing::{
    classify_byte_missing, classify_double_missing_bits, classify_float_missing_bits,
    classify_int_missing, classify_long_missing, MissingTag, DOUBLE_MISSING_DOT_BITS,
    DOUBLE_MISSING_STEP_BITS, DOUBLE_MISSING_Z_BITS, FLOAT_MISSING_DOT_BITS,
    FLOAT_MISSING_STEP_BITS, FLOAT_MISSING_Z_BITS,
};
pub use types::{
    ByteOrder, Column, ColumnValues, DtaData, DtaMetadata, DtaType, FormatVersion, ReadOptions,
    SectionOffsets, ValueLabelEntry, ValueLabelTable, VariableInfo,
};
pub use value_labels::parse_value_labels;
