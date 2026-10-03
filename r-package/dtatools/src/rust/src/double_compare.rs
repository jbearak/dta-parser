//! Pair comparisons of decoded doubles, with dispatch outside the row loop.
use super::{double_missing_rank, double_payload_canonical, CompareOperandView, CompareStorage};
use std::ffi::c_int;

unsafe fn pair<F: Fn(f64, f64) -> bool, M: Fn(u8, u8) -> bool>(
    x: *const f64,
    y: *const f64,
    output: *mut c_int,
    length: usize,
    observed: F,
    missing: M,
) -> bool {
    let mut valid = true;
    for index in 0..length {
        let a = x.add(index).read_unaligned();
        let b = y.add(index).read_unaligned();
        let a_missing = a.is_nan();
        let b_missing = b.is_nan();
        let result = if a_missing | b_missing {
            // If either side is missing, rank alone determines the result.
            // Ordinary infinities still have rank zero. Invalid NaN payloads
            // decline the whole call so the R fallback retains its errors.
            valid &= (!a_missing || double_payload_canonical(a.to_bits()))
                & (!b_missing || double_payload_canonical(b.to_bits()));
            let ar = if a_missing {
                double_missing_rank(a.to_bits())
            } else {
                0
            };
            let br = if b_missing {
                double_missing_rank(b.to_bits())
            } else {
                0
            };
            missing(ar, br)
        } else {
            observed(a, b)
        };
        output.add(index).write(c_int::from(result));
    }
    valid
}

pub(super) unsafe fn compare(
    op: c_int,
    x: CompareOperandView,
    y: Option<CompareOperandView>,
    output: *mut c_int,
    length: usize,
) -> Option<bool> {
    let y = y?;
    if !matches!(x.storage, CompareStorage::Double)
        || !matches!(y.storage, CompareStorage::Double)
        || x.native_owner != 0
        || y.native_owner != 0
        || !(0..=5).contains(&op)
    {
        return None;
    }
    // Double operands are already in decoded units, including temporal values.
    let xp = x.values as *const f64;
    let yp = y.values as *const f64;
    Some(match op {
        0 => pair(xp, yp, output, length, |a, b| a == b, |a, b| a == b),
        1 => pair(xp, yp, output, length, |a, b| a != b, |a, b| a != b),
        2 => pair(xp, yp, output, length, |a, b| a < b, |a, b| a < b),
        3 => pair(xp, yp, output, length, |a, b| a <= b, |a, b| a <= b),
        4 => pair(xp, yp, output, length, |a, b| a > b, |a, b| a > b),
        _ => pair(xp, yp, output, length, |a, b| a >= b, |a, b| a >= b),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{compare_decoded, compare_operand_element, DOUBLE_TAGGED_NA_LAYOUT};

    fn view(values: &[f64]) -> CompareOperandView {
        CompareOperandView {
            values: values.as_ptr() as usize,
            storage: CompareStorage::Double,
            temporal: 0,
            native_owner: 0,
        }
    }

    #[test]
    fn pair_matches_decoded_order_across_ieee_values_and_every_missing_payload() {
        let mut values = vec![
            f64::NEG_INFINITY,
            -f64::MAX,
            -1.0,
            -f64::MIN_POSITIVE,
            -f64::from_bits(1),
            -0.0,
            0.0,
            f64::from_bits(1),
            f64::MIN_POSITIVE,
            1.0,
            f64::MAX,
            f64::INFINITY,
        ];
        for tag in std::iter::once(0).chain(b'a'..=b'z') {
            for sign in [0, 1_u64 << 63] {
                for quiet in [0, 1_u64 << 51] {
                    values.push(f64::from_bits(
                        DOUBLE_TAGGED_NA_LAYOUT | (u64::from(tag) << 32) | sign | quiet,
                    ));
                }
            }
        }
        let mut x = Vec::new();
        let mut y = Vec::new();
        for &a in &values {
            for &b in &values {
                x.push(a);
                y.push(b);
            }
        }
        let mut seed = 0x7349_5281_8314_7243_u64;
        for _ in 0..10_000 {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
            let a = f64::from_bits(seed);
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1);
            let b = f64::from_bits(seed);
            if !a.is_nan() && !b.is_nan() {
                x.push(a);
                y.push(b);
            }
        }
        let xv = view(&x);
        let yv = view(&y);
        for op in 0..=5 {
            let mut output = vec![0; x.len()];
            assert_eq!(
                unsafe { compare(op, xv, Some(yv), output.as_mut_ptr(), x.len()) },
                Some(true)
            );
            for (index, actual) in output.into_iter().enumerate() {
                let expected = unsafe {
                    compare_decoded(
                        op,
                        compare_operand_element(xv, index).unwrap(),
                        compare_operand_element(yv, index).unwrap(),
                    )
                };
                assert_eq!(actual, expected, "op={op}, row={index}");
            }
        }
    }

    #[test]
    fn unrecognized_nan_payloads_decline_either_operand() {
        for bits in [
            0x7ff8_0000_0000_0000,
            0xfff0_0000_0000_0001,
            DOUBLE_TAGGED_NA_LAYOUT | (u64::from(b'A') << 32),
            DOUBLE_TAGGED_NA_LAYOUT ^ 1,
        ] {
            let invalid = [1.0, f64::from_bits(bits), 0.0];
            let valid = [0.0, 1.0, f64::from_bits(DOUBLE_TAGGED_NA_LAYOUT)];
            for (x, y) in [(&invalid, &valid), (&valid, &invalid)] {
                for op in 0..=5 {
                    assert_eq!(
                        unsafe { compare(op, view(x), Some(view(y)), [0; 3].as_mut_ptr(), 3) },
                        Some(false)
                    );
                }
            }
        }
    }
}
