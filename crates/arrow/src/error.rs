//! The Arrow modules' error (plan 0025, stage 2a): one variant per kind
//! of failure, which the tests tell apart. R has one
//! kind of error, so its binding (`arrow_r.rs` in r/dtaparser) reports
//! every variant by its message alone.

use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum Error {
    /// Bad input: a file that cannot be read, a value that cannot be
    /// written, an argument out of its choices.
    Value(String),
    /// An unknown column name, as a selection or a value label set that
    /// `meta` names.
    Key(String),
    /// A wrong type: a column of a type a writer refuses, an Arrow stream
    /// that is not what was asked for.
    Type(String),
    /// An allocation that failed.
    Memory(String),
}

pub type Result<T> = std::result::Result<T, Error>;

/// A `Value` error with `e`'s message.
pub fn fail(e: impl fmt::Display) -> Error {
    Error::Value(e.to_string())
}

impl Error {
    /// The error, its message starting with `path` when it is a `Value`
    /// error: a read from a path names the file in what went wrong with
    /// it, and not in a wrong name or type, or a lack of memory.
    pub fn prefixed(self, path: &str) -> Error {
        match self {
            Error::Value(m) => Error::Value(format!("{path}: {m}")),
            e => e,
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Value(m) | Error::Key(m) | Error::Type(m) | Error::Memory(m) => f.write_str(m),
        }
    }
}
