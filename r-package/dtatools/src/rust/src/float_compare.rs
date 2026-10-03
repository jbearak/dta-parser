//! Typed float comparison without expanding values and ranks into f64 records.
//! Exact missing classification preserves permissive imports. No canonical
//! column-domain assumption is made, and temporal values keep the decoder.
use super::{tagged_missing_version, CompareOperandView, CompareStorage, ComparedElement};
use std::ffi::c_int;

const DOT: u32 = 0x7f00_0000;
const STEP: u32 = 0x800;

/// The same typed kernel can read plain buffers and retained float spans.
pub(super) fn supports(x: CompareOperandView, y: Option<CompareOperandView>) -> bool {
    x.temporal == 0
        && matches!(x.storage, CompareStorage::Float(_))
        && y.is_none_or(|y| y.temporal == 0 && matches!(y.storage, CompareStorage::Float(_)))
}

#[inline(always)]
fn rank<const MODERN: bool>(bits: u32) -> u8 {
    if MODERN {
        let delta = bits.wrapping_sub(DOT);
        if delta <= 26 * STEP && delta & (STEP - 1) == 0 {
            (delta / STEP) as u8 + 1
        } else {
            0
        }
    } else {
        u8::from((DOT..0x8000_0000).contains(&bits))
    }
}

#[inline(always)]
fn ordered_key<const MODERN: bool>(value: f32) -> (u32, bool) {
    let bits = value.to_bits();
    let missing = rank::<MODERN>(bits);
    // Observed infinities and permissive high finite imports precede missing
    // values too. Their IEEE order keys end at 0xff800000, below these slots.
    let normalized = if value == 0.0 { 0 } else { bits };
    let observed = if normalized & 0x8000_0000 != 0 {
        !normalized
    } else {
        normalized ^ 0x8000_0000
    };
    let key = if missing != 0 {
        u32::MAX - 27 + u32::from(missing)
    } else {
        observed
    };
    (key, missing != 0 || !value.is_nan())
}

unsafe fn pair<const X_MODERN: bool, const Y_MODERN: bool, F: Fn(u32, u32) -> bool>(
    x: *const f32,
    y: *const f32,
    output: *mut c_int,
    length: usize,
    compare: F,
) -> bool {
    let mut valid = true;
    for index in 0..length {
        let (a, av) = ordered_key::<X_MODERN>(x.add(index).read_unaligned());
        let (b, bv) = ordered_key::<Y_MODERN>(y.add(index).read_unaligned());
        valid &= av & bv;
        output.add(index).write(c_int::from(compare(a, b)));
    }
    valid
}

unsafe fn scalar<const MODERN: bool, F: Fn(f64, u8) -> bool>(
    x: *const f32,
    output: *mut c_int,
    length: usize,
    compare: F,
) -> bool {
    let mut valid = true;
    for index in 0..length {
        let value = x.add(index).read_unaligned();
        let missing = rank::<MODERN>(value.to_bits());
        valid &= missing != 0 || !value.is_nan();
        // Widen the input exactly. R scalars must never be rounded to f32.
        output
            .add(index)
            .write(c_int::from(compare(f64::from(value), missing)));
    }
    valid
}

unsafe fn pair_operator<const X: bool, const Y: bool>(
    op: c_int,
    x: *const f32,
    y: *const f32,
    output: *mut c_int,
    length: usize,
) -> bool {
    match op {
        0 => pair::<X, Y, _>(x, y, output, length, |a, b| a == b),
        1 => pair::<X, Y, _>(x, y, output, length, |a, b| a != b),
        2 => pair::<X, Y, _>(x, y, output, length, |a, b| a < b),
        3 => pair::<X, Y, _>(x, y, output, length, |a, b| a <= b),
        4 => pair::<X, Y, _>(x, y, output, length, |a, b| a > b),
        _ => pair::<X, Y, _>(x, y, output, length, |a, b| a >= b),
    }
}

unsafe fn scalar_operator<const MODERN: bool>(
    op: c_int,
    x: *const f32,
    rhs: ComparedElement,
    output: *mut c_int,
    length: usize,
) -> bool {
    if rhs.rank == 0 {
        let s = rhs.value;
        match op {
            0 => scalar::<MODERN, _>(x, output, length, |v, r| r == 0 && v == s),
            1 => scalar::<MODERN, _>(x, output, length, |v, r| r != 0 || v != s),
            2 => scalar::<MODERN, _>(x, output, length, |v, r| r == 0 && v < s),
            3 => scalar::<MODERN, _>(x, output, length, |v, r| r == 0 && v <= s),
            4 => scalar::<MODERN, _>(x, output, length, |v, r| r != 0 || v > s),
            _ => scalar::<MODERN, _>(x, output, length, |v, r| r != 0 || v >= s),
        }
    } else {
        let s = rhs.rank;
        match op {
            0 => scalar::<MODERN, _>(x, output, length, |_, r| r == s),
            1 => scalar::<MODERN, _>(x, output, length, |_, r| r != s),
            2 => scalar::<MODERN, _>(x, output, length, |_, r| r < s),
            3 => scalar::<MODERN, _>(x, output, length, |_, r| r <= s),
            4 => scalar::<MODERN, _>(x, output, length, |_, r| r > s),
            _ => scalar::<MODERN, _>(x, output, length, |_, r| r >= s),
        }
    }
}

pub(super) unsafe fn compare(
    op: c_int,
    x: CompareOperandView,
    y: Option<CompareOperandView>,
    rhs: ComparedElement,
    output: *mut c_int,
    length: usize,
) -> Option<bool> {
    let CompareStorage::Float(x_version) = x.storage else {
        return None;
    };
    if !supports(x, y) || x.native_owner != 0 || !(0..=5).contains(&op) {
        return None;
    }
    let xp = x.values as *const f32;
    let xm = tagged_missing_version(x_version);
    match y {
        Some(y) => {
            let CompareStorage::Float(y_version) = y.storage else {
                return None;
            };
            if y.temporal != 0 || y.native_owner != 0 {
                return None;
            }
            let yp = y.values as *const f32;
            Some(match (xm, tagged_missing_version(y_version)) {
                (true, true) => pair_operator::<true, true>(op, xp, yp, output, length),
                (true, false) => pair_operator::<true, false>(op, xp, yp, output, length),
                (false, true) => pair_operator::<false, true>(op, xp, yp, output, length),
                (false, false) => pair_operator::<false, false>(op, xp, yp, output, length),
            })
        }
        None => Some(if xm {
            scalar_operator::<true>(op, xp, rhs, output, length)
        } else {
            scalar_operator::<false>(op, xp, rhs, output, length)
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{compare_decoded, compare_operand_element};
    use dta_tools::{classify_float_missing_bits_for_version, FormatVersion};

    fn bits() -> Vec<u32> {
        let mut result = vec![
            0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x807fffff, 0x3f800000, 0xbf800000,
            0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0xffc00000, 0x7fffffff,
            0xffffffff,
        ];
        result.extend((DOT - STEP)..=(DOT + 27 * STEP));
        let mut seed = 0x71843a21_u32;
        for _ in 0..10000 {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            result.push(seed);
        }
        result
    }
    fn view(values: &[f32], version: FormatVersion) -> CompareOperandView {
        CompareOperandView {
            values: values.as_ptr() as usize,
            storage: CompareStorage::Float(version),
            temporal: 0,
            native_owner: 0,
        }
    }
    #[test]
    fn exact_float_ranks_match_import_classification() {
        for bits in bits() {
            for (version, actual) in [
                (FormatVersion::V119, rank::<true>(bits)),
                (FormatVersion::V111, rank::<false>(bits)),
            ] {
                let expected = classify_float_missing_bits_for_version(bits, version)
                    .map_or(0, |tag| tag.offset() + 1);
                assert_eq!(actual, expected, "{bits:08x} {version:?}");
            }
        }
    }
    #[test]
    fn float_pairs_match_decoded_order_for_all_encoding_pairs() {
        for xv in [FormatVersion::V111, FormatVersion::V119] {
            for yv in [FormatVersion::V111, FormatVersion::V119] {
                let input: Vec<f32> = bits().into_iter().map(f32::from_bits).collect();
                let mut x = Vec::new();
                let mut y = Vec::new();
                for (index, &a) in input.iter().enumerate() {
                    let b = input[(index * 173 + 47) % input.len()];
                    if unsafe {
                        compare_operand_element(view(&[a], xv), 0).is_some()
                            && compare_operand_element(view(&[b], yv), 0).is_some()
                    } {
                        x.push(a);
                        y.push(b);
                    }
                }
                let left = view(&x, xv);
                let right = view(&y, yv);
                for op in 0..=5 {
                    let expected: Vec<c_int> = (0..x.len())
                        .map(|i| unsafe {
                            compare_decoded(
                                op,
                                compare_operand_element(left, i).unwrap(),
                                compare_operand_element(right, i).unwrap(),
                            )
                        })
                        .collect();
                    let mut actual = vec![0; x.len()];
                    assert_eq!(
                        unsafe {
                            compare(
                                op,
                                left,
                                Some(right),
                                ComparedElement { rank: 0, value: 0. },
                                actual.as_mut_ptr(),
                                x.len(),
                            )
                        },
                        Some(true)
                    );
                    assert_eq!(actual, expected);
                }
            }
        }
    }
    #[test]
    fn float_scalars_preserve_double_precision_and_missing_ranks() {
        for version in [FormatVersion::V111, FormatVersion::V119] {
            let values: Vec<f32> = bits()
                .into_iter()
                .map(f32::from_bits)
                .filter(|v| unsafe { compare_operand_element(view(&[*v], version), 0).is_some() })
                .collect();
            let input = view(&values, version);
            let scalars = [
                -f64::INFINITY,
                -f64::MAX,
                -0.0,
                0.0,
                f64::from_bits(1),
                1.0 - f64::EPSILON,
                1.0 + f64::EPSILON,
                1.01,
                f64::MAX,
                f64::INFINITY,
            ];
            let mut rhs: Vec<ComparedElement> = scalars
                .into_iter()
                .map(|value| ComparedElement { rank: 0, value })
                .collect();
            rhs.extend((1..=27).map(|rank| ComparedElement { rank, value: 0. }));
            for scalar in rhs {
                for op in 0..=5 {
                    let expected: Vec<c_int> = (0..values.len())
                        .map(|i| unsafe {
                            compare_decoded(op, compare_operand_element(input, i).unwrap(), scalar)
                        })
                        .collect();
                    let mut actual = vec![0; values.len()];
                    assert_eq!(
                        unsafe {
                            compare(op, input, None, scalar, actual.as_mut_ptr(), values.len())
                        },
                        Some(true)
                    );
                    assert_eq!(actual, expected);
                }
            }
        }
    }
    #[test]
    fn noncanonical_nans_and_temporal_values_keep_fallback() {
        for bits in [0x7fc00000, 0xffc00000] {
            let x = [f32::from_bits(bits)];
            let mut output = [0];
            let mut input = view(&x, FormatVersion::V119);
            assert_eq!(
                unsafe {
                    compare(
                        2,
                        input,
                        None,
                        ComparedElement { rank: 0, value: 1. },
                        output.as_mut_ptr(),
                        1,
                    )
                },
                Some(false)
            );
            input.temporal = 1;
            assert_eq!(
                unsafe {
                    compare(
                        2,
                        input,
                        None,
                        ComparedElement { rank: 0, value: 1. },
                        output.as_mut_ptr(),
                        1,
                    )
                },
                None
            );
        }
    }
}
