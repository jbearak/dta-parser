use crate::FormatVersion;

/// Errors returned while parsing `.dta` metadata.
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

    /// Checked offset or size arithmetic overflowed.
    #[error("integer overflow while calculating {0}")]
    ArithmeticOverflow(&'static str),
}
