//! Text encodings. Release 118 and later store UTF-8. Older releases
//! store whatever single-byte code page the writer's system used; we
//! read them as Windows-1252 unless told otherwise (see ADR 0004).

/// How to decode text in a file older than release 118.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Encoding {
    #[default]
    Windows1252,
    Latin1,
    Utf8,
}

impl Encoding {
    pub fn name(self) -> &'static str {
        match self {
            Encoding::Windows1252 => "windows-1252",
            Encoding::Latin1 => "latin1",
            Encoding::Utf8 => "utf-8",
        }
    }

    pub fn from_name(name: &str) -> Option<Self> {
        match name.to_ascii_lowercase().as_str() {
            "windows-1252" | "cp1252" => Some(Encoding::Windows1252),
            "latin1" | "latin-1" | "iso-8859-1" => Some(Encoding::Latin1),
            "utf-8" | "utf8" => Some(Encoding::Utf8),
            _ => None,
        }
    }

    /// Append `bytes`, decoded, to `out` as UTF-8.
    pub(crate) fn decode_into(self, bytes: &[u8], out: &mut Vec<u8>) {
        if bytes.is_ascii() {
            out.extend_from_slice(bytes);
            return;
        }
        match self {
            Encoding::Utf8 => out.extend_from_slice(String::from_utf8_lossy(bytes).as_bytes()),
            Encoding::Latin1 | Encoding::Windows1252 => {
                let mut tmp = [0u8; 4];
                for &b in bytes {
                    let c = match (self, b) {
                        (Encoding::Windows1252, 0x80..=0x9f) => WINDOWS_1252[(b - 0x80) as usize],
                        _ => b as char,
                    };
                    out.extend_from_slice(c.encode_utf8(&mut tmp).as_bytes());
                }
            }
        }
    }

    pub(crate) fn decode(self, bytes: &[u8]) -> String {
        let mut out = Vec::with_capacity(bytes.len());
        self.decode_into(bytes, &mut out);
        // decode_into only appends valid UTF-8.
        String::from_utf8(out).unwrap_or_default()
    }
}

/// Windows-1252 bytes 0x80 to 0x9f. The five bytes the code page leaves
/// undefined map to the C1 control of the same number, as Latin-1 does.
const WINDOWS_1252: [char; 32] = [
    '\u{20ac}', '\u{81}', '\u{201a}', '\u{192}', '\u{201e}', '\u{2026}', '\u{2020}', '\u{2021}',
    '\u{2c6}', '\u{2030}', '\u{160}', '\u{2039}', '\u{152}', '\u{8d}', '\u{17d}', '\u{8f}',
    '\u{90}', '\u{2018}', '\u{2019}', '\u{201c}', '\u{201d}', '\u{2022}', '\u{2013}', '\u{2014}',
    '\u{2dc}', '\u{2122}', '\u{161}', '\u{203a}', '\u{153}', '\u{9d}', '\u{17e}', '\u{178}',
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_code_pages() {
        let bytes = [b'a', 0xe9, 0x80];
        assert_eq!(Encoding::Windows1252.decode(&bytes), "aé€");
        assert_eq!(Encoding::Latin1.decode(&bytes), "aé\u{80}");
        assert_eq!(Encoding::Utf8.decode("é".as_bytes()), "é");
        assert_eq!(Encoding::Utf8.decode(&[0xff]), "\u{fffd}");
    }
}
