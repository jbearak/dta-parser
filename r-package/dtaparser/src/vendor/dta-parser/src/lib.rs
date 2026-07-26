//! Native parsing primitives for Stata `.dta` files.
//!
//! The crate parses releases 113–115 and 117–119 into column-oriented data,
//! including numeric and fixed-string observations, resolved `strL` payloads,
//! exact missing tags, metadata, and value-label tables. Byte-slice APIs are
//! complemented by bounded, projected [`DtaFile`] reads over `Read + Seek`.

mod data_reader;
mod endian;
mod error;
mod file;
mod legacy;
mod metadata;
mod missing;
mod selection;
mod strl;
mod text;
mod types;
mod value_labels;

pub use data_reader::{read_dta, read_dta_with_options};
pub use error::DtaError;
pub use file::{DtaFile, DtaSink, FileOptions};
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
