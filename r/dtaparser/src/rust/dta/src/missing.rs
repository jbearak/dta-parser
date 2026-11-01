//! Stata's numeric missing values.
//!
//! A *missing code* is a `u8`: 0 for a value that is not missing, 1 for
//! system missing `.`, and 2 to 27 for `.a` to `.z`. Releases before 113
//! have only `.`.
//!
//! From release 113 each storage type reserves its largest values for the
//! 27 codes, in order:
//!
//! | type   | `.`                  | step to the next code     |
//! |--------|----------------------|---------------------------|
//! | byte   | 101                  | 1                         |
//! | int    | 32741                | 1                         |
//! | long   | 2147483621           | 1                         |
//! | float  | bits 0x7f000000      | 0x800 added to the bits   |
//! | double | bits 0x7fe0000000000000 | 2^40 added to the bits |
//!
//! Before 113 each type has one missing value at the same place as `.`
//! is later for floats and doubles, and at the type's maximum (127,
//! 32767, 2147483647) for integers.

pub const NOT_MISSING: u8 = 0;
pub const SYSTEM: u8 = 1;
/// The largest code, `.z`.
pub const LAST: u8 = 27;

/// The name of a missing code: `.`, `.a`, ... `.z`.
pub fn name(code: u8) -> Option<String> {
    match code {
        SYSTEM => Some(".".into()),
        2..=LAST => Some(format!(".{}", (b'a' + code - 2) as char)),
        _ => None,
    }
}

/// The code of a name such as `.` or `.q`.
pub fn from_name(name: &str) -> Option<u8> {
    match name.as_bytes() {
        b"." => Some(SYSTEM),
        [b'.', c @ b'a'..=b'z'] => Some(c - b'a' + 2),
        _ => None,
    }
}

pub(crate) const BYTE_MISSING: i8 = 101;
pub(crate) const INT_MISSING: i16 = 32741;
pub(crate) const LONG_MISSING: i32 = 2_147_483_621;
pub(crate) const FLOAT_MISSING: u32 = 0x7f00_0000;
pub(crate) const DOUBLE_MISSING: u64 = 0x7fe0_0000_0000_0000;

/// Code of an integer `v` whose type reserves `first` (the value of `.`)
/// and above. Values past `.z` are not written by any tool we know; they
/// read as `.`.
#[inline]
pub(crate) fn int_code(v: i64, first: i64, extended: bool) -> u8 {
    if v < first {
        NOT_MISSING
    } else if !extended {
        SYSTEM
    } else {
        let step = v - first;
        if step < LAST as i64 { (step + 1) as u8 } else { SYSTEM }
    }
}

#[inline]
pub(crate) fn float_code(bits: u32, extended: bool) -> u8 {
    // Positive values at or above the bits of `.`; negative values are
    // numbers.
    if !(FLOAT_MISSING..0x8000_0000).contains(&bits) {
        return NOT_MISSING;
    }
    let step = (bits - FLOAT_MISSING) >> 11;
    if extended && step < LAST as u32 && (bits - FLOAT_MISSING) & 0x7ff == 0 {
        (step + 1) as u8
    } else {
        SYSTEM
    }
}

#[inline]
pub(crate) fn double_code(bits: u64, extended: bool) -> u8 {
    if !(DOUBLE_MISSING..0x8000_0000_0000_0000).contains(&bits) {
        return NOT_MISSING;
    }
    let step = (bits - DOUBLE_MISSING) >> 40;
    if extended && step < LAST as u64 && (bits - DOUBLE_MISSING) & ((1 << 40) - 1) == 0 {
        (step + 1) as u8
    } else {
        SYSTEM
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_round_trip() {
        for code in SYSTEM..=LAST {
            assert_eq!(from_name(&name(code).unwrap()), Some(code));
        }
        assert_eq!(name(2).unwrap(), ".a");
        assert_eq!(name(27).unwrap(), ".z");
        assert_eq!(from_name(".A"), None);
    }

    #[test]
    fn integer_codes() {
        assert_eq!(int_code(100, 101, true), NOT_MISSING);
        assert_eq!(int_code(101, 101, true), SYSTEM);
        assert_eq!(int_code(102, 101, true), 2);
        assert_eq!(int_code(127, 101, true), 27);
        assert_eq!(int_code(127, 127, false), SYSTEM);
    }

    #[test]
    fn float_and_double_codes() {
        assert_eq!(float_code(FLOAT_MISSING, true), SYSTEM);
        assert_eq!(float_code(FLOAT_MISSING + 0x800, true), 2);
        assert_eq!(float_code(FLOAT_MISSING + 26 * 0x800, true), 27);
        assert_eq!(float_code(1.5f32.to_bits(), true), NOT_MISSING);
        assert_eq!(float_code((-3e38f32).to_bits(), true), NOT_MISSING);
        assert_eq!(double_code(DOUBLE_MISSING + (25 << 40), true), 26);
        assert_eq!(double_code(DOUBLE_MISSING + (25 << 40), false), SYSTEM);
        assert_eq!(double_code(f64::NAN.to_bits(), true), SYSTEM);
    }
}
