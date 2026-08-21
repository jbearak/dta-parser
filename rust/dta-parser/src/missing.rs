use std::fmt;

use crate::FormatVersion;

use serde::{de, Deserialize, Deserializer, Serialize, Serializer};

const BYTE_MISSING_DOT: i8 = 101;
const BYTE_MISSING_Z: i8 = 127;
const INT_MISSING_DOT: i16 = 32_741;
const INT_MISSING_Z: i16 = 32_767;
const LONG_MISSING_DOT: i32 = 2_147_483_621;
const LONG_MISSING_Z: i32 = 2_147_483_647;

/// Raw IEEE-754 bits for Stata's system-missing float value.
pub const FLOAT_MISSING_DOT_BITS: u32 = 0x7f00_0000;
/// Distance between adjacent float missing tags.
pub const FLOAT_MISSING_STEP_BITS: u32 = 0x0000_0800;
/// Raw IEEE-754 bits for Stata's `.z` float value.
pub const FLOAT_MISSING_Z_BITS: u32 = FLOAT_MISSING_DOT_BITS + 26 * FLOAT_MISSING_STEP_BITS;

/// Raw IEEE-754 bits for Stata's system-missing double value.
pub const DOUBLE_MISSING_DOT_BITS: u64 = 0x7fe0_0000_0000_0000;
/// Distance between adjacent double missing tags.
pub const DOUBLE_MISSING_STEP_BITS: u64 = 0x0000_0100_0000_0000;
/// Raw IEEE-754 bits for Stata's `.z` double value.
pub const DOUBLE_MISSING_Z_BITS: u64 = DOUBLE_MISSING_DOT_BITS + 26 * DOUBLE_MISSING_STEP_BITS;
const V105_DOUBLE_MISSING_BITS: u64 = 0x54c0_0000_0000_0000;

/// Stata's system missing (`.`) or one of its 26 extended tags (`.a`–`.z`).
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum MissingTag {
    System = 0,
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
}

impl MissingTag {
    const ALL: [Self; 27] = [
        Self::System,
        Self::A,
        Self::B,
        Self::C,
        Self::D,
        Self::E,
        Self::F,
        Self::G,
        Self::H,
        Self::I,
        Self::J,
        Self::K,
        Self::L,
        Self::M,
        Self::N,
        Self::O,
        Self::P,
        Self::Q,
        Self::R,
        Self::S,
        Self::T,
        Self::U,
        Self::V,
        Self::W,
        Self::X,
        Self::Y,
        Self::Z,
    ];

    pub fn from_offset(offset: u8) -> Option<Self> {
        Self::ALL.get(usize::from(offset)).copied()
    }

    pub const fn offset(self) -> u8 {
        self as u8
    }
}

impl fmt::Display for MissingTag {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        if *self == Self::System {
            formatter.write_str(".")
        } else {
            write!(formatter, ".{}", char::from(b'a' + self.offset() - 1))
        }
    }
}

impl Serialize for MissingTag {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for MissingTag {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        if value == "." {
            return Ok(Self::System);
        }
        let bytes = value.as_bytes();
        if bytes.len() == 2 && bytes[0] == b'.' && bytes[1].is_ascii_lowercase() {
            return Self::from_offset(bytes[1] - b'a' + 1)
                .ok_or_else(|| de::Error::custom(format!("invalid missing tag {value:?}")));
        }
        Err(de::Error::custom(format!("invalid missing tag {value:?}")))
    }
}

fn classify_signed(value: i64, dot: i64, z: i64) -> Option<MissingTag> {
    if !(dot..=z).contains(&value) {
        return None;
    }
    MissingTag::from_offset(u8::try_from(value - dot).ok()?)
}

pub fn classify_byte_missing(value: i8) -> Option<MissingTag> {
    classify_signed(
        i64::from(value),
        i64::from(BYTE_MISSING_DOT),
        i64::from(BYTE_MISSING_Z),
    )
}

pub fn classify_int_missing(value: i16) -> Option<MissingTag> {
    classify_signed(
        i64::from(value),
        i64::from(INT_MISSING_DOT),
        i64::from(INT_MISSING_Z),
    )
}

pub fn classify_long_missing(value: i32) -> Option<MissingTag> {
    classify_signed(
        i64::from(value),
        i64::from(LONG_MISSING_DOT),
        i64::from(LONG_MISSING_Z),
    )
}

pub fn classify_float_missing_bits(bits: u32) -> Option<MissingTag> {
    if !(FLOAT_MISSING_DOT_BITS..=FLOAT_MISSING_Z_BITS).contains(&bits) {
        return None;
    }
    let delta = bits - FLOAT_MISSING_DOT_BITS;
    if delta % FLOAT_MISSING_STEP_BITS != 0 {
        return None;
    }
    MissingTag::from_offset(u8::try_from(delta / FLOAT_MISSING_STEP_BITS).ok()?)
}

pub fn classify_double_missing_bits(bits: u64) -> Option<MissingTag> {
    if !(DOUBLE_MISSING_DOT_BITS..=DOUBLE_MISSING_Z_BITS).contains(&bits) {
        return None;
    }
    let delta = bits - DOUBLE_MISSING_DOT_BITS;
    if delta % DOUBLE_MISSING_STEP_BITS != 0 {
        return None;
    }
    MissingTag::from_offset(u8::try_from(delta / DOUBLE_MISSING_STEP_BITS).ok()?)
}

pub(crate) fn classify_byte_missing_for_version(
    value: i8,
    version: FormatVersion,
) -> Option<MissingTag> {
    if matches!(
        version,
        FormatVersion::V105 | FormatVersion::V108 | FormatVersion::V110 | FormatVersion::V111
    ) {
        return (value == BYTE_MISSING_Z).then_some(MissingTag::System);
    }
    classify_byte_missing(value)
}

pub(crate) fn classify_int_missing_for_version(
    value: i16,
    version: FormatVersion,
) -> Option<MissingTag> {
    if matches!(
        version,
        FormatVersion::V105 | FormatVersion::V108 | FormatVersion::V110 | FormatVersion::V111
    ) {
        return (value == INT_MISSING_Z).then_some(MissingTag::System);
    }
    classify_int_missing(value)
}

pub(crate) fn classify_long_missing_for_version(
    value: i32,
    version: FormatVersion,
) -> Option<MissingTag> {
    if matches!(
        version,
        FormatVersion::V105 | FormatVersion::V108 | FormatVersion::V110 | FormatVersion::V111
    ) {
        return (value == LONG_MISSING_Z).then_some(MissingTag::System);
    }
    classify_long_missing(value)
}

pub(crate) fn classify_float_missing_bits_for_version(
    bits: u32,
    version: FormatVersion,
) -> Option<MissingTag> {
    if matches!(
        version,
        FormatVersion::V105 | FormatVersion::V108 | FormatVersion::V110 | FormatVersion::V111
    ) {
        return ((FLOAT_MISSING_DOT_BITS..0x8000_0000).contains(&bits))
            .then_some(MissingTag::System);
    }
    classify_float_missing_bits(bits)
}

pub(crate) fn classify_double_missing_bits_for_version(
    bits: u64,
    version: FormatVersion,
) -> Option<MissingTag> {
    if version == FormatVersion::V105 {
        return (bits == V105_DOUBLE_MISSING_BITS).then_some(MissingTag::System);
    }
    if matches!(
        version,
        FormatVersion::V108 | FormatVersion::V110 | FormatVersion::V111
    ) {
        return ((DOUBLE_MISSING_DOT_BITS..0x8000_0000_0000_0000).contains(&bits))
            .then_some(MissingTag::System);
    }
    classify_double_missing_bits(bits)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tag(offset: u8) -> MissingTag {
        MissingTag::from_offset(offset).unwrap()
    }

    #[test]
    fn classifies_all_27_missing_tags_exactly() {
        for offset in 0_u8..=26 {
            let expected = Some(tag(offset));
            assert_eq!(classify_byte_missing(101 + offset as i8), expected);
            assert_eq!(classify_int_missing(32_741 + i16::from(offset)), expected);
            assert_eq!(
                classify_long_missing(2_147_483_621 + i32::from(offset)),
                expected
            );
            assert_eq!(
                classify_float_missing_bits(
                    FLOAT_MISSING_DOT_BITS + u32::from(offset) * FLOAT_MISSING_STEP_BITS
                ),
                expected
            );
            assert_eq!(
                classify_double_missing_bits(
                    DOUBLE_MISSING_DOT_BITS + u64::from(offset) * DOUBLE_MISSING_STEP_BITS
                ),
                expected
            );
        }
    }

    #[test]
    fn rejects_numeric_boundaries_and_misaligned_raw_bits() {
        assert_eq!(classify_byte_missing(100), None);
        assert_eq!(classify_int_missing(32_740), None);
        assert_eq!(classify_long_missing(2_147_483_620), None);
        assert_eq!(
            classify_float_missing_bits(FLOAT_MISSING_DOT_BITS - 1),
            None
        );
        assert_eq!(
            classify_float_missing_bits(FLOAT_MISSING_DOT_BITS + 1),
            None
        );
        assert_eq!(classify_float_missing_bits(FLOAT_MISSING_Z_BITS + 1), None);
        assert_eq!(
            classify_double_missing_bits(DOUBLE_MISSING_DOT_BITS - 1),
            None
        );
        assert_eq!(
            classify_double_missing_bits(DOUBLE_MISSING_DOT_BITS + 1),
            None
        );
        assert_eq!(
            classify_double_missing_bits(DOUBLE_MISSING_Z_BITS + 1),
            None
        );
    }

    #[test]
    fn release_105_uses_its_historical_double_missing_sentinel() {
        assert_eq!(
            classify_double_missing_bits_for_version(V105_DOUBLE_MISSING_BITS, FormatVersion::V105),
            Some(MissingTag::System)
        );
        assert_eq!(
            classify_double_missing_bits_for_version(DOUBLE_MISSING_DOT_BITS, FormatVersion::V105),
            None
        );
        assert_eq!(
            classify_double_missing_bits_for_version(V105_DOUBLE_MISSING_BITS, FormatVersion::V108),
            None
        );
    }

    #[test]
    fn missing_tag_serde_is_stable() {
        assert_eq!(serde_json::to_string(&MissingTag::System).unwrap(), "\".\"");
        assert_eq!(serde_json::to_string(&MissingTag::Z).unwrap(), "\".z\"");
        assert_eq!(
            serde_json::from_str::<MissingTag>("\".a\"").unwrap(),
            MissingTag::A
        );
    }
}
