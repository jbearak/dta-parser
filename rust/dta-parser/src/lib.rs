//! Native parsing primitives for Stata `.dta` files.
//!
//! The foundation release parses metadata for format versions 117 through
//! 119. It intentionally does not decode observations or metadata payloads
//! such as value-label tables and `strL` objects.

mod endian;
mod error;
mod metadata;
mod missing;
mod types;

pub use error::DtaError;
pub use metadata::parse_metadata;
pub use missing::{
    classify_byte_missing, classify_double_missing_bits, classify_float_missing_bits,
    classify_int_missing, classify_long_missing, MissingTag, DOUBLE_MISSING_DOT_BITS,
    DOUBLE_MISSING_STEP_BITS, DOUBLE_MISSING_Z_BITS, FLOAT_MISSING_DOT_BITS,
    FLOAT_MISSING_STEP_BITS, FLOAT_MISSING_Z_BITS,
};
pub use types::{ByteOrder, DtaMetadata, DtaType, FormatVersion, SectionOffsets, VariableInfo};
