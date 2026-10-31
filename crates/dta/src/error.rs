use std::fmt;

/// Everything that can go wrong reading or writing a `.dta` file.
///
/// `offset` is the byte position in the file where a reader found the
/// problem, when there is one. `kind` says what sort of problem it is,
/// so a binding can tell a damaged file from one too large to read
/// without reading the message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error {
    pub offset: Option<u64>,
    pub message: String,
    pub kind: ErrorKind,
}

/// What sort of problem an [`Error`] is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorKind {
    /// The file is damaged or not a `.dta` file (the default).
    Corrupt,
    /// The file is fine, but a value or read does not fit in memory.
    TooLarge,
    /// The file or output could not be read or written, or the caller
    /// stopped the work.
    Io,
    /// The caller asked for something impossible: data that cannot be
    /// written, or an option that cannot hold.
    Invalid,
    /// The caller asked for a variable or rows the file does not have.
    OutOfRange,
    /// A bug: a thread panicked or could not start.
    Internal,
}

pub type Result<T> = std::result::Result<T, Error>;

impl Error {
    /// A damaged-file error (kind `Corrupt`) with no position.
    pub fn new(message: impl Into<String>) -> Self {
        Error { offset: None, message: message.into(), kind: ErrorKind::Corrupt }
    }

    /// A damaged-file error (kind `Corrupt`) at byte `offset`.
    pub fn at(offset: u64, message: impl Into<String>) -> Self {
        Error { offset: Some(offset), message: message.into(), kind: ErrorKind::Corrupt }
    }

    /// An error in what the caller asked for (kind `Invalid`).
    pub fn invalid(message: impl Into<String>) -> Self {
        Error::new(message).of(ErrorKind::Invalid)
    }

    /// The same error, of kind `kind`.
    pub fn of(self, kind: ErrorKind) -> Self {
        Error { kind, ..self }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.offset {
            Some(offset) => write!(f, "{} (at byte {})", self.message, offset),
            None => f.write_str(&self.message),
        }
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::new(e.to_string()).of(ErrorKind::Io)
    }
}
