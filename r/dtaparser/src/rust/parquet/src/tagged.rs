//! `.a` to `.z` as tagged NaNs (plan 0018, "Missing values"): R's
//! `NA_real_` with the letter's ASCII code in bits 32 to 39, the layout
//! haven's `tagged_na()` and dtaparser use.

use dta::missing;

/// R's `NA_real_`: a NaN whose low word is 1954.
pub const NA_BITS: u64 = 0x7ff0_0000_0000_07a2;

/// The tagged NaN for missing code `code`, 2 (`.a`) to 27 (`.z`).
///
/// # Panics
///
/// If `code` is not one of `.a` to `.z`.
pub fn tagged_nan(code: u8) -> f64 {
    assert!(
        (missing::SYSTEM + 1..=missing::LAST).contains(&code),
        "missing code {code} is not one of .a to .z"
    );
    f64::from_bits(NA_BITS | (u64::from(b'a' + code - 2) << 32))
}

/// The missing code of a tagged NaN: 2 to 27 when the bits of `v` are
/// exactly R's `NA_real_` with a letter `a` to `z` in bits 32 to 39, and
/// 0 for every other value, other NaNs included.
#[inline]
pub fn tagged_code(v: f64) -> u8 {
    let bits = v.to_bits();
    let letter = (bits >> 32) as u8;
    if bits & !(0xff << 32) == NA_BITS && letter.is_ascii_lowercase() {
        letter - b'a' + 2
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_bits_are_rs() {
        // .a is NA_real_ with 'a' (0x61) in byte 4.
        assert_eq!(tagged_nan(2).to_bits(), 0x7ff0_0061_0000_07a2);
        assert_eq!(tagged_nan(27).to_bits(), 0x7ff0_007a_0000_07a2);
        for code in 2..=27 {
            assert!(tagged_nan(code).is_nan());
            assert_eq!(tagged_code(tagged_nan(code)), code);
        }
    }

    #[test]
    fn other_nans_are_not_letters() {
        for bits in [
            f64::NAN.to_bits(),
            NA_BITS,                           // R's NA, no letter
            NA_BITS | (u64::from(b'A') << 32), // not lowercase
            0x7ff8_0061_0000_07a2,             // quieted
            0xfff0_0061_0000_07a2,             // negative
            0x7ff0_0061_0000_07a3,             // another low word
        ] {
            assert_eq!(tagged_code(f64::from_bits(bits)), 0, "{bits:#x}");
        }
        assert_eq!(tagged_code(1.5), 0);
    }
}
