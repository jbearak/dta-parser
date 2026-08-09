use std::io::ErrorKind;

use crate::{DtaType, FormatVersion};

/// Errors returned while parsing supported `.dta` files and seekable sources.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum DtaError {
    /// The input does not start with a recognized Stata file header.
    #[error("not a valid .dta file: unrecognized format signature")]
    InvalidSignature,

    /// The release exists in the shared model but is outside this parser's
    /// supported 111, 113–115, and 117–119 releases.
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

    /// A caller requested a text encoding outside the deterministic supported
    /// set.
    #[error("unsupported text encoding {0:?}; supported encodings are UTF-8, Windows-1252, and ISO-8859-1")]
    UnsupportedTextEncoding(String),

    /// A legacy header's file-type marker was not the required data-file
    /// marker (`0x01`).
    #[error("invalid legacy file type marker 0x{0:02x}")]
    InvalidFileType(u8),

    /// A signed legacy observation count was negative.
    #[error("negative legacy observation count {0}")]
    NegativeObservationCount(i32),

    /// A legacy expansion field declared a negative payload length.
    #[error("negative expansion-field length {value} at byte offset {offset}")]
    NegativeExpansionLength { value: i32, offset: usize },

    /// A legacy expansion-field stream ended without its `(0, 0)` sentinel.
    #[error("legacy expansion fields have no (0, 0) terminator")]
    MissingExpansionTerminator,

    /// Expansion-field type zero is reserved for the zero-length sentinel.
    #[error("invalid expansion-field terminator length {value} at byte offset {offset}")]
    InvalidExpansionTerminator { value: i32, offset: usize },

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

    /// A non-null `strL` pointer had only one zero component or referenced an
    /// invalid variable/observation key.
    #[error("invalid strL pointer ({variable}, {observation}) at byte offset {offset}")]
    InvalidStrlPointer {
        variable: u32,
        observation: u64,
        offset: usize,
    },

    /// Bytes inside `<strls>` did not begin with a GSO marker.
    #[error("expected GSO marker at byte offset {offset}")]
    InvalidGsoMarker { offset: usize },

    /// A GSO key did not identify a valid `strL` variable and observation.
    #[error("invalid GSO key ({variable}, {observation}) at byte offset {offset}")]
    InvalidGsoKey {
        variable: u32,
        observation: u64,
        offset: usize,
    },

    /// Two GSO records used the same key. Duplicate payloads are still
    /// rejected because silently selecting one would hide file corruption.
    #[error("duplicate GSO key ({variable}, {observation}) at byte offset {offset}")]
    DuplicateGsoKey {
        variable: u32,
        observation: u64,
        offset: usize,
    },

    /// A selected non-null pointer had no matching GSO record.
    #[error("dangling strL pointer ({variable}, {observation})")]
    DanglingStrlPointer { variable: u32, observation: u64 },

    /// Only Stata GSO types 129 (binary) and 130 (text) are supported.
    #[error("unsupported GSO type {gso_type} at byte offset {offset}")]
    InvalidGsoType { gso_type: u8, offset: usize },

    /// Type-130 GSO strings must include a final NUL byte.
    #[error("type-130 GSO payload at byte offset {offset} is not NUL-terminated")]
    InvalidGsoText { offset: usize },

    /// File-backed scratch reads require enough space for the fixed map probe.
    #[error("max_buffer_bytes must be at least 1024 bytes")]
    InvalidBufferSize,

    /// A file-backed raw staging read exceeded the configured scratch limit.
    #[error("raw staging read requested {requested} bytes, exceeding max_buffer_bytes={limit}")]
    BufferLimitExceeded { requested: usize, limit: usize },

    /// A file-backed consumer requested cooperative interruption.
    #[error("read cancelled")]
    Cancelled,

    /// A caller-provided output collector could not materialize a decoded
    /// value. Keeping collector failures in the parser's ordinary error path
    /// ensures partially built outputs are dropped without being exposed.
    #[error("output materialization failed: {0}")]
    Output(String),

    /// A seek or read failed while accessing a file-backed source.
    #[error("I/O error while {context} at byte offset {offset}: {kind:?}")]
    Io {
        context: &'static str,
        offset: u64,
        kind: ErrorKind,
    },

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

    /// A label text offset did not point at a valid encoded-text boundary.
    #[error(
        "value-label entry {entry_index} at byte offset {offset} has invalid text offset {text_offset} for a {text_length}-byte text block"
    )]
    InvalidValueLabelTextOffset {
        entry_index: usize,
        offset: usize,
        text_offset: i32,
        text_length: usize,
    },

    /// Retained for API compatibility; tolerant readers no longer reject
    /// nonascending or duplicate value-label keys.
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
