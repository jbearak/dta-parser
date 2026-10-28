use std::fmt;

/// Everything that can go wrong reading or writing a `.dta` file.
///
/// `offset` is the byte position in the file where a reader found the
/// problem, when there is one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error {
    pub offset: Option<u64>,
    pub message: String,
}

pub type Result<T> = std::result::Result<T, Error>;

impl Error {
    pub fn new(message: impl Into<String>) -> Self {
        Error { offset: None, message: message.into() }
    }

    pub fn at(offset: u64, message: impl Into<String>) -> Self {
        Error { offset: Some(offset), message: message.into() }
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
        Error::new(e.to_string())
    }
}
