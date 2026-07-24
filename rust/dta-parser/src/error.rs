use crate::{DtaType, FormatVersion};

/// Errors returned while parsing modern `.dta` files.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum DtaError {
    /// The input does not start with a recognized Stata file header.
    #[error("not a valid .dta file: unrecognized format signature")]
    InvalidSignature,

    /// The release exists in the shared model but is outside this parser's
    /// current 117–119 scope.
    #[error("Stata release {0} metadata is not supported by this parser")]
    UnsupportedRelease(FormatVersion),

    /// An XML-like structural tag was absent or out of place.
    #[error("expected {expected} at byte offset {offset}")]
    UnexpectedTag {
        expected: &'static str,
        offset: usize,
    },

    /// A fixed-size value or section extended past the supplied input.
    #[error(
        "truncated {context} at byte offset {offset}: needed {needed} bytes, only {available} available"
    )]
    Truncated {
        context: &'static str,
        offset: usize,
        needed: usize,
        available: usize,
    },

    /// A byte-order marker was present but invalid.
    #[error("invalid byte order {0:?}")]
    InvalidByteOrder(String),

    /// The release field was syntactically invalid or unknown.
    #[error("invalid Stata release {0:?}")]
    InvalidRelease(String),

    /// A map entry did not point to the section it names.
    #[error("section {section} has map offset {actual}, expected {expected}")]
    MapOffsetMismatch {
        section: &'static str,
        expected: u64,
        actual: u64,
    },

    /// Section map offsets were not strictly increasing.
    #[error(
        "section map is out of order: {section} at {offset} does not follow byte offset {previous_offset}"
    )]
    SectionOrder {
        section: &'static str,
        previous_offset: u64,
        offset: u64,
    },

    /// An offset cannot be represented safely on the current platform.
    #[error("{context} offset {offset} cannot be represented on this platform")]
    OffsetOutOfRange { context: &'static str, offset: u64 },

    /// A variable type code is invalid for the detected format version.
    #[error("unknown type code {code} for format v{version}")]
    UnknownTypeCode { code: u16, version: FormatVersion },

    /// A requested source variable index is outside the metadata range.
    #[error("column index {index} is out of bounds for {nvar} variables")]
    InvalidColumnIndex { index: u32, nvar: u32 },

    /// Decoding for the selected storage type belongs to a later feature slice.
    #[error("column index {index} has unsupported storage type {dta_type}")]
    UnsupportedColumnType { index: u32, dta_type: DtaType },

    /// A signed value-label count or length was negative.
    #[error("negative {field} value {value} in value-label table at byte offset {offset}")]
    NegativeValueLabelField {
        field: &'static str,
        value: i32,
        offset: usize,
    },

    /// A value-label table's declared payload length disagreed with its fields.
    #[error(
        "value-label table at byte offset {offset} declares {declared} payload bytes, expected {expected}"
    )]
    InvalidValueLabelLength {
        offset: usize,
        declared: usize,
        expected: usize,
    },

    /// A label text offset did not point inside the table's text block.
    #[error(
        "value-label entry {entry_index} at byte offset {offset} has text offset {text_offset}, outside a {text_length}-byte text block"
    )]
    InvalidValueLabelTextOffset {
        entry_index: usize,
        offset: usize,
        text_offset: i32,
        text_length: usize,
    },

    /// Value-label keys must be strictly increasing in modern table payloads.
    #[error(
        "value-label table at byte offset {table_offset} is not strictly ascending at entry {entry_index}: {value} follows {previous}"
    )]
    UnsortedValueLabelValues {
        table_offset: usize,
        entry_index: usize,
        previous: i32,
        value: i32,
    },

    /// A required NUL terminator was absent from a bounded label field.
    #[error("unterminated {context} at byte offset {offset}")]
    MissingNulTerminator {
        context: &'static str,
        offset: usize,
    },

    /// Checked offset or size arithmetic overflowed.
    #[error("integer overflow while calculating {0}")]
    ArithmeticOverflow(&'static str),
}
