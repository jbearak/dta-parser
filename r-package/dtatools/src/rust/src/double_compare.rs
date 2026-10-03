//! Pair comparisons of decoded doubles, with dispatch outside the row loop.
use super::{CompareOperandView, CompareStorage, DOUBLE_IGNORED_BITS, DOUBLE_TAGGED_NA_LAYOUT};
use std::ffi::c_int;

/// Pair-local ordering keys need only preserve the order, not the scalar
/// decoder's consecutive ranks. Observed values use zero; system missing uses
/// one; letter tags use their byte plus one. Widen before adding because an
/// observed value can have 255 in the mantissa byte used for missing tags.
#[inline]
fn missing_key(bits: u64, is_missing: bool) -> (u32, bool) {
    let tag = ((bits >> 32) & 0xff) as u32;
    let canonical = (bits & !DOUBLE_IGNORED_BITS == DOUBLE_TAGGED_NA_LAYOUT & !DOUBLE_IGNORED_BITS)
        & ((tag == 0) | ((tag >= u32::from(b'a')) & (tag <= u32::from(b'z'))));
    (
        (tag + 1) & 0_u32.wrapping_sub(u32::from(is_missing)),
        !is_missing | canonical,
    )
}

unsafe fn pair_exact<F: Fn(f64, f64) -> bool, M: Fn(u32, u32) -> bool>(
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
        let (ar, a_valid) = missing_key(a.to_bits(), a_missing);
        let (br, b_valid) = missing_key(b.to_bits(), b_missing);
        valid &= a_valid & b_valid;
        let either_missing = a_missing | b_missing;
        // Compute both comparisons without a data-dependent row branch.
        // IEEE comparison retains observed signed-zero and infinity behavior.
        // Any unsupported NaN still declines the entire call, including when
        // it occurs after a previous invalid payload.
        let result = (observed(a, b) & !either_missing) | (missing(ar, br) & either_missing);
        output.add(index).write(c_int::from(result));
    }
    valid
}

/// The maximum absolute bit pattern proves that every value is observed.
/// Infinities are valid observed doubles; only larger magnitudes are NaNs.
/// This check makes no claim about other blocks or the rest of the column.
#[inline(always)]
unsafe fn ordinary_block(x: *const f64, y: *const f64, length: usize) -> bool {
    let mut maximum = 0_u64;
    for index in 0..length {
        let a = x.add(index).read_unaligned().to_bits() & 0x7fff_ffff_ffff_ffff;
        let b = y.add(index).read_unaligned().to_bits() & 0x7fff_ffff_ffff_ffff;
        maximum = maximum.max(a).max(b);
    }
    maximum <= 0x7ff0_0000_0000_0000
}

unsafe fn pair<F: Fn(f64, f64) -> bool, M: Fn(u32, u32) -> bool>(
    x: *const f64,
    y: *const f64,
    output: *mut c_int,
    length: usize,
    observed: F,
    missing: M,
) -> bool {
    let mut valid = true;
    let mut start = 0;
    let mut failed_blocks = 0;
    while start < length {
        let count = (length - start).min(64);
        let xp = x.add(start);
        let yp = y.add(start);
        let target = output.add(start);
        if ordinary_block(xp, yp, count) {
            failed_blocks = 0;
            for index in 0..count {
                target.add(index).write(c_int::from(observed(
                    xp.add(index).read_unaligned(),
                    yp.add(index).read_unaligned(),
                )));
            }
        } else {
            valid &= pair_exact(xp, yp, target, count, &observed, &missing);
            failed_blocks += 1;
            if failed_blocks == 4 {
                start += count;
                // Stop spending proof work on this span. The exact loop
                // validates every remaining row; this is not a domain fact.
                return valid
                    & pair_exact(
                        x.add(start),
                        y.add(start),
                        output.add(start),
                        length - start,
                        &observed,
                        &missing,
                    );
            }
        }
        start += count;
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
    fn local_keys_accept_every_observed_tag_byte_and_only_canonical_nan_tags() {
        for tag in 0_u32..=255 {
            for sign in [0, 1_u64 << 63] {
                for quiet in [0, 1_u64 << 51] {
                    let bits = DOUBLE_TAGGED_NA_LAYOUT | (u64::from(tag) << 32) | sign | quiet;
                    let value = f64::from_bits(bits);
                    assert!(value.is_nan());
                    assert_eq!(
                        missing_key(bits, true),
                        (tag + 1, crate::double_payload_canonical(bits))
                    );
                    // Change only the exponent, retaining tag byte 255 and
                    // the same sign/mantissa variants in ordinary numbers.
                    let observed = bits & !(1_u64 << 62);
                    assert!(!f64::from_bits(observed).is_nan());
                    assert_eq!(missing_key(observed, false), (0, true));
                }
            }
        }
    }

    #[test]
    fn invalid_nan_in_a_late_lane_declines_the_whole_pair() {
        for length in [1, 2, 3, 4, 7, 8, 15, 16, 17, 63, 64, 65, 257, 1025] {
            for index in [0, length / 2, length - 1] {
                let mut x = vec![f64::from_bits(DOUBLE_TAGGED_NA_LAYOUT); length];
                let y = vec![0.0; length];
                x[index] = f64::from_bits(0x7ff8_0000_0000_0000);
                for (a, b) in [(&x, &y), (&y, &x)] {
                    for op in 0..=5 {
                        let mut output = vec![0; length];
                        assert_eq!(
                            unsafe {
                                compare(op, view(a), Some(view(b)), output.as_mut_ptr(), length)
                            },
                            Some(false)
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn block_proofs_and_dense_switch_preserve_all_comparisons() {
        for length in [0, 1, 2, 63, 64, 65, 127, 128, 129, 255, 256, 257, 320, 1025] {
            for dense_prefix in [0, 64, 192, 256, 320] {
                let observed = [f64::NEG_INFINITY, -0.0, 0.0, f64::INFINITY, 1.5, -2.5];
                let mut x: Vec<_> = (0..length).map(|i| observed[i % observed.len()]).collect();
                let y: Vec<_> = (0..length)
                    .map(|i| observed[(i + 2) % observed.len()])
                    .collect();
                for (index, value) in x.iter_mut().take(dense_prefix).enumerate() {
                    let tag = if index % 27 == 0 {
                        0
                    } else {
                        b'a' + (index % 27 - 1) as u8
                    };
                    *value = f64::from_bits(DOUBLE_TAGGED_NA_LAYOUT | (u64::from(tag) << 32));
                }
                for op in 0..=5 {
                    let mut output = vec![0; length];
                    assert_eq!(
                        unsafe {
                            compare(op, view(&x), Some(view(&y)), output.as_mut_ptr(), length)
                        },
                        Some(true)
                    );
                    for (index, actual) in output.iter().enumerate() {
                        let expected = unsafe {
                            compare_decoded(
                                op,
                                compare_operand_element(view(&x), index).unwrap(),
                                compare_operand_element(view(&y), index).unwrap(),
                            )
                        };
                        assert_eq!(
                            *actual, expected,
                            "length={length}, prefix={dense_prefix}, op={op}, index={index}"
                        );
                    }
                    if length != 0 {
                        let saved = x[length - 1];
                        x[length - 1] = f64::from_bits(0x7ff8_0000_0000_0000);
                        assert_eq!(
                            unsafe {
                                compare(op, view(&x), Some(view(&y)), output.as_mut_ptr(), length)
                            },
                            Some(false)
                        );
                        x[length - 1] = saved;
                    }
                }
            }
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
