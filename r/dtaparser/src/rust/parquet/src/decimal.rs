//! DECIMAL values: an integer (the unscaled value) times 10^-scale.
//!
//! A reader gives them as text, every digit kept (`"-123.45"`, `"0.050"`:
//! as many digits after the point as the scale, never an exponent), or as
//! the nearest double. A double holds any value of at most 15 significant
//! digits so that it prints back as the same decimal, and no more in
//! general; so reading a value with more than 15 into a double is an
//! error naming the column and row, and [`significant_digits`] lets a
//! binding apply the same rule to text it already has.

use dta::{Error, Result};

/// The most significant digits a double holds exactly enough to give
/// the same decimal back.
pub const DOUBLE_DIGITS: usize = 15;

/// The significant digits of a decimal written as text: its digits
/// without sign, point, leading zeros or trailing zeros. `"-0.0500"` has
/// one; `"0"` none; `"1200"` two.
pub fn significant_digits(text: &str) -> usize {
    let digits = text.bytes().filter(u8::is_ascii_digit);
    let lead = text
        .bytes()
        .filter(u8::is_ascii_digit)
        .take_while(|&d| d == b'0')
        .count();
    let trail = text
        .bytes()
        .rev()
        .filter(u8::is_ascii_digit)
        .take_while(|&d| d == b'0')
        .count();
    digits.count().saturating_sub(lead + trail)
}

/// Powers of ten a double holds exactly.
const POW10: [f64; 23] = [
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16,
    1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
];

/// An unscaled value: its sign and its magnitude's decimal digits, with
/// no leading zeros (empty for zero).
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Unscaled {
    negative: bool,
    digits: Vec<u8>,
}

impl Unscaled {
    pub(crate) fn from_i64(v: i64) -> Self {
        let mut digits = Vec::with_capacity(20);
        if v != 0 {
            digits.extend_from_slice(v.unsigned_abs().to_string().as_bytes());
        }
        Unscaled {
            negative: v < 0,
            digits,
        }
    }

    /// From big-endian two's complement of 1 to 32 bytes, as a
    /// BYTE_ARRAY or FIXED_LEN_BYTE_ARRAY holds it.
    pub(crate) fn from_be(bytes: &[u8]) -> Result<Self> {
        if bytes.is_empty() || bytes.len() > crate::schema::DECIMAL_BYTES {
            return Err(Error::new(format!(
                "a DECIMAL value of {} bytes; it must take 1 to {}",
                bytes.len(),
                crate::schema::DECIMAL_BYTES
            )));
        }
        let negative = bytes[0] & 0x80 != 0;
        if bytes.len() <= 8 {
            let mut b = [if negative { 0xff } else { 0 }; 8];
            b[8 - bytes.len()..].copy_from_slice(bytes);
            return Ok(Self::from_i64(i64::from_be_bytes(b)));
        }
        // Sign-extend to 256 bits, little-endian limbs, and negate a
        // negative value to its magnitude.
        let mut wide = [if negative { 0xff } else { 0 }; 32];
        wide[32 - bytes.len()..].copy_from_slice(bytes);
        let mut limbs = [0u64; 4];
        for (k, limb) in limbs.iter_mut().enumerate() {
            let at = 32 - 8 * (k + 1);
            *limb = u64::from_be_bytes(wide[at..at + 8].try_into().expect("8 bytes"));
        }
        if negative {
            let mut carry = true;
            for limb in &mut limbs {
                let (v, c) = (!*limb).overflowing_add(u64::from(carry));
                *limb = v;
                carry = c;
            }
        }
        // Divide by 10^19 until nothing is left; each remainder is 19
        // digits, least significant first.
        const CHUNK: u64 = 10_000_000_000_000_000_000;
        let mut parts = Vec::with_capacity(5);
        while limbs.iter().any(|&l| l != 0) {
            let mut rem = 0u128;
            for limb in limbs.iter_mut().rev() {
                let cur = rem << 64 | u128::from(*limb);
                *limb = (cur / u128::from(CHUNK)) as u64;
                rem = cur % u128::from(CHUNK);
            }
            parts.push(rem as u64);
        }
        let mut digits = Vec::with_capacity(parts.len() * 19);
        for (k, p) in parts.iter().rev().enumerate() {
            if k == 0 {
                digits.extend_from_slice(p.to_string().as_bytes());
            } else {
                digits.extend_from_slice(format!("{p:019}").as_bytes());
            }
        }
        Ok(Unscaled { negative, digits })
    }

    /// Significant digits: without trailing zeros.
    pub(crate) fn significant(&self) -> usize {
        let trail = self.digits.iter().rev().take_while(|&&d| d == b'0').count();
        self.digits.len() - trail
    }

    /// Append the value, scaled, as text.
    pub(crate) fn write(&self, scale: u32, out: &mut Vec<u8>) {
        let scale = scale as usize;
        if self.negative && !self.digits.is_empty() {
            out.push(b'-');
        }
        let digits: &[u8] = if self.digits.is_empty() {
            b"0"
        } else {
            &self.digits
        };
        if scale == 0 {
            out.extend_from_slice(digits);
        } else if digits.len() <= scale {
            out.extend_from_slice(b"0.");
            out.resize(out.len() + scale - digits.len(), b'0');
            out.extend_from_slice(digits);
        } else {
            let point = digits.len() - scale;
            out.extend_from_slice(&digits[..point]);
            out.push(b'.');
            out.extend_from_slice(&digits[point..]);
        }
    }

    /// The nearest double to the value, scaled.
    pub(crate) fn to_f64(&self, scale: u32) -> f64 {
        let sig = self.significant();
        let trail = self.digits.len() - sig;
        // Exactly m * 10^e, with m below 2^53 and 10^|e| a double: one
        // correctly rounded operation.
        if sig <= 15 {
            let m: u64 = self.digits[..sig]
                .iter()
                .fold(0, |m, &d| m * 10 + u64::from(d - b'0'));
            let e = trail as i64 - i64::from(scale);
            if e.unsigned_abs() <= 22 {
                let p = POW10[e.unsigned_abs() as usize];
                let v = if e >= 0 { m as f64 * p } else { m as f64 / p };
                return if self.negative { -v } else { v };
            }
        }
        // Otherwise through text, which Rust parses correctly rounded.
        let mut text = Vec::with_capacity(self.digits.len() + 8);
        if self.negative {
            text.push(b'-');
        }
        text.extend_from_slice(if self.digits.is_empty() {
            b"0"
        } else {
            &self.digits
        });
        text.extend_from_slice(format!("e-{scale}").as_bytes());
        std::str::from_utf8(&text)
            .expect("ASCII")
            .parse()
            .expect("a number")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(u: &Unscaled, scale: u32) -> String {
        let mut out = Vec::new();
        u.write(scale, &mut out);
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn values_as_text() {
        for (v, scale, want) in [
            (0i64, 0u32, "0"),
            (0, 2, "0.00"),
            (5, 3, "0.005"),
            (-5, 3, "-0.005"),
            (-12345, 2, "-123.45"),
            (150, 2, "1.50"),
            (i64::MIN, 0, "-9223372036854775808"),
            (i64::MAX, 18, "9.223372036854775807"),
            (7, 0, "7"),
        ] {
            assert_eq!(text(&Unscaled::from_i64(v), scale), want);
        }
    }

    #[test]
    fn big_endian_values_of_every_width() {
        // Every width from 1 to 32 bytes, for a few values, against i128
        // where it holds them.
        for v in [
            0i128,
            1,
            -1,
            127,
            -128,
            255,
            1 << 70,
            -(1 << 70) - 3,
            i128::MAX,
            i128::MIN,
        ] {
            let be = v.to_be_bytes();
            for len in 1..=32usize {
                let mut bytes = [if v < 0 { 0xff } else { 0 }; 32];
                bytes[16..].copy_from_slice(&be);
                let bytes = &bytes[32 - len..];
                // Only widths that hold v.
                let fits =
                    len >= 16 || (v >= -(1i128 << (8 * len - 1)) && v < (1i128 << (8 * len - 1)));
                if !fits {
                    continue;
                }
                let u = Unscaled::from_be(bytes).unwrap();
                assert_eq!(text(&u, 0), v.to_string(), "{v} in {len} bytes");
            }
        }
        // 2^255 - 1 and -2^255, the extremes of 32 bytes.
        let mut max = [0xffu8; 32];
        max[0] = 0x7f;
        assert_eq!(
            text(&Unscaled::from_be(&max).unwrap(), 0),
            "57896044618658097711785492504343953926634992332820282019728792003956564819967"
        );
        let mut min = [0u8; 32];
        min[0] = 0x80;
        assert_eq!(
            text(&Unscaled::from_be(&min).unwrap(), 0),
            "-57896044618658097711785492504343953926634992332820282019728792003956564819968"
        );
        assert!(Unscaled::from_be(&[]).is_err());
        assert!(Unscaled::from_be(&[0; 33]).is_err());
    }

    #[test]
    fn significant_digits_and_doubles() {
        assert_eq!(significant_digits("-0.0500"), 1);
        assert_eq!(significant_digits("0"), 0);
        assert_eq!(significant_digits("0.00"), 0);
        assert_eq!(significant_digits("1200"), 2);
        assert_eq!(significant_digits("123456789012345.6"), 16);
        for (v, scale, sig, want) in [
            (12345i64, 2u32, 5usize, 123.45f64),
            (-5, 3, 1, -0.005),
            (1_000_000, 0, 1, 1e6),
            (999_999_999_999_999, 0, 15, 999_999_999_999_999.0),
            (123_456_789_012_345, 10, 15, 12345.6789012345),
            (1, 30, 1, 1e-30),
        ] {
            let u = Unscaled::from_i64(v);
            assert_eq!(u.significant(), sig);
            assert_eq!(u.to_f64(scale), want, "{v}e-{scale}");
            assert_eq!(significant_digits(&text(&u, scale)), sig);
        }
        // Past the fast path: through text, still the nearest double.
        let u = Unscaled::from_i64(1_234_567_890_123_456_789);
        assert_eq!(u.to_f64(5), "12345678901234.56789".parse::<f64>().unwrap());
        assert_eq!(u.significant(), 19);
    }
}
