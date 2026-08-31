use std::borrow::Cow;

use encoding_rs::{CoderResult, Decoder, UTF_8, WINDOWS_1252};

use crate::{DtaError, FormatVersion};

/// Source encoding used for textual fields in a Stata file.
///
/// [`TextEncoding::Auto`] uses Windows-1252 for pre-Unicode releases and UTF-8
/// for releases 118--119. Pre-Unicode DTA releases do not record a code page,
/// so callers can override this pragmatic default when the source encoding is
/// known or strict compatibility with current Stata is required.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
pub enum TextEncoding {
    #[default]
    Auto,
    Utf8,
    Windows1252,
    Iso8859_1,
}

impl TextEncoding {
    /// Resolve a deterministic, case-insensitive encoding label.
    ///
    /// ASCII hyphens, underscores, and spaces are ignored. Supported labels
    /// are `UTF-8`/`UTF8`, `Windows-1252`/`CP1252`, and
    /// `ISO-8859-1`/`latin1`.
    pub fn from_label(label: &str) -> Result<Self, DtaError> {
        let normalized = label
            .bytes()
            .filter(|byte| !matches!(byte, b'-' | b'_' | b' '))
            .map(|byte| byte.to_ascii_lowercase())
            .collect::<Vec<_>>();
        match normalized.as_slice() {
            b"utf8" => Ok(Self::Utf8),
            b"windows1252" | b"cp1252" => Ok(Self::Windows1252),
            b"iso88591" | b"latin1" => Ok(Self::Iso8859_1),
            _ => Err(DtaError::UnsupportedTextEncoding(label.to_owned())),
        }
    }

    pub(crate) fn resolve(self, version: FormatVersion) -> Self {
        match self {
            Self::Auto if version.uses_utf8_text() => Self::Utf8,
            Self::Auto => Self::Windows1252,
            explicit => explicit,
        }
    }

    pub(crate) fn decode(self, bytes: &[u8]) -> String {
        self.decode_cow(bytes).into_owned()
    }

    pub(crate) fn decode_cow(self, bytes: &[u8]) -> Cow<'_, str> {
        match self {
            Self::Utf8 => String::from_utf8_lossy(bytes),
            Self::Windows1252 => WINDOWS_1252.decode_without_bom_handling(bytes).0,
            Self::Iso8859_1 => Cow::Owned(decode_iso_8859_1(bytes)),
            Self::Auto => unreachable!("text encoding must be resolved before decoding"),
        }
    }

    pub(crate) fn is_utf8(self) -> bool {
        matches!(self, Self::Utf8)
    }

    pub(crate) fn new_decoder(self) -> TextDecoder {
        match self {
            Self::Utf8 => TextDecoder::EncodingRs(UTF_8.new_decoder_without_bom_handling()),
            Self::Windows1252 => {
                TextDecoder::EncodingRs(WINDOWS_1252.new_decoder_without_bom_handling())
            }
            Self::Iso8859_1 => TextDecoder::Iso8859_1,
            Self::Auto => unreachable!("text encoding must be resolved before decoding"),
        }
    }
}

pub(crate) enum TextDecoder {
    EncodingRs(Decoder),
    Iso8859_1,
}

impl TextDecoder {
    pub(crate) fn decode_to_string(
        &mut self,
        input: &[u8],
        output: &mut String,
        last: bool,
    ) -> (CoderResult, usize) {
        match self {
            Self::EncodingRs(decoder) => {
                let (result, read, _) = decoder.decode_to_string(input, output, last);
                (result, read)
            }
            Self::Iso8859_1 => {
                for &byte in input {
                    output.push(char::from(byte));
                }
                (CoderResult::InputEmpty, input.len())
            }
        }
    }
}

fn decode_iso_8859_1(bytes: &[u8]) -> String {
    let mut output = String::with_capacity(bytes.len());
    for &byte in bytes {
        output.push(char::from(byte));
    }
    output
}

pub(crate) fn field_bytes(bytes: &[u8]) -> &[u8] {
    let end = bytes
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(bytes.len());
    &bytes[..end]
}

pub(crate) fn is_utf8_continuation(byte: u8) -> bool {
    byte & 0xc0 == 0x80
}

/// Whether `offset` lies between decoded UTF-8 code points. Malformed bytes
/// are replacement characters of their own, so an offset before a standalone
/// continuation byte remains a valid boundary.
pub(crate) fn is_utf8_boundary(bytes: &[u8], offset: usize) -> bool {
    if offset == 0 || offset >= bytes.len() || !is_utf8_continuation(bytes[offset]) {
        return true;
    }
    let mut start = offset;
    while start > 0 && is_utf8_continuation(bytes[start]) {
        start -= 1;
    }
    let width = match bytes[start] {
        0xc2..=0xdf => 2,
        0xe0..=0xef => 3,
        0xf0..=0xf4 => 4,
        _ => return true,
    };
    let Some(end) = start.checked_add(width) else {
        return true;
    };
    if offset >= end || end > bytes.len() {
        return true;
    }
    std::str::from_utf8(&bytes[start..end]).is_err()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_only_the_documented_aliases() {
        assert_eq!(
            TextEncoding::from_label("UTF-8").unwrap(),
            TextEncoding::Utf8
        );
        assert_eq!(
            TextEncoding::from_label("utf_8").unwrap(),
            TextEncoding::Utf8
        );
        assert_eq!(
            TextEncoding::from_label("CP1252").unwrap(),
            TextEncoding::Windows1252
        );
        assert_eq!(
            TextEncoding::from_label("iso 8859-1").unwrap(),
            TextEncoding::Iso8859_1
        );
        assert!(matches!(
            TextEncoding::from_label("native.enc"),
            Err(DtaError::UnsupportedTextEncoding(_))
        ));
    }

    #[test]
    fn latin1_and_windows_1252_are_distinct() {
        assert_eq!(TextEncoding::Windows1252.decode(&[0x80]), "\u{20ac}");
        assert_eq!(TextEncoding::Iso8859_1.decode(&[0x80]), "\u{80}");
    }

    #[test]
    fn malformed_utf8_uses_replacement_decoding() {
        assert_eq!(TextEncoding::Utf8.decode(&[0xff]), "\u{fffd}");
    }

    #[test]
    fn utf8_boundaries_distinguish_valid_codepoints_from_malformed_bytes() {
        assert!(!is_utf8_boundary("é".as_bytes(), 1));
        assert!(!is_utf8_boundary("€".as_bytes(), 2));
        assert!(is_utf8_boundary(&[b'x', 0x80], 1));
        assert!(is_utf8_boundary(&[0x80], 0));
    }
}
