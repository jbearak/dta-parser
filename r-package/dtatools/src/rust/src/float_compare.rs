//! Typed float comparison without expanding values and ranks into f64 records.
//! Exact missing classification preserves permissive imports. No canonical
//! column-domain assumption is made, and temporal values keep the decoder.
use super::{tagged_missing_version, CompareOperandView, CompareStorage, ComparedElement};
use std::ffi::c_int;

const DOT: u32 = 0x7f00_0000;
const STEP: u32 = 0x800;

#[cfg(test)]
std::thread_local! {
    static PAIR_EXACT_ROWS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

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
unsafe fn pair_exact<
    const X_MODERN: bool,
    const Y_MODERN: bool,
    F: Fn(f32, f32) -> bool,
    M: Fn(u8, u8) -> bool,
>(
    x: *const f32,
    y: *const f32,
    output: *mut c_int,
    length: usize,
    observed: &F,
    missing: &M,
) -> bool {
    #[cfg(test)]
    PAIR_EXACT_ROWS.with(|rows| rows.set(rows.get() + length));
    let mut valid = true;
    for index in 0..length {
        let a = x.add(index).read_unaligned();
        let b = y.add(index).read_unaligned();
        let ar = rank::<X_MODERN>(a.to_bits());
        let br = rank::<Y_MODERN>(b.to_bits());
        valid &= (ar != 0 || !a.is_nan()) & (br != 0 || !b.is_nan());
        let result = if ar | br == 0 {
            observed(a, b)
        } else {
            missing(ar, br)
        };
        output.add(index).write(c_int::from(result));
    }
    valid
}

#[inline(always)]
unsafe fn ordinary_block(x: *const f32, y: *const f32, length: usize) -> bool {
    // Below-DOT absolute bit patterns are finite and exclude every missing
    // code. Unsigned maximum vectorizes without packing per-lane booleans.
    // Large negative observed values and either infinity conservatively fail.
    let mut maximum = 0_u32;
    for index in 0..length {
        maximum = maximum
            .max(x.add(index).read_unaligned().to_bits() & 0x7fff_ffff)
            .max(y.add(index).read_unaligned().to_bits() & 0x7fff_ffff);
    }
    maximum < DOT
}

unsafe fn pair<
    const X_MODERN: bool,
    const Y_MODERN: bool,
    F: Fn(f32, f32) -> bool,
    M: Fn(u8, u8) -> bool,
>(
    x: *const f32,
    y: *const f32,
    output: *mut c_int,
    length: usize,
    observed: F,
    missing: M,
) -> bool {
    const BLOCK: usize = 64;
    let mut start = 0;
    let mut valid = true;
    let mut failed_blocks = 0;
    while start < length {
        let count = BLOCK.min(length - start);
        let xp = x.add(start);
        let yp = y.add(start);
        let result = output.add(start);
        if ordinary_block(xp, yp, count) {
            failed_blocks = 0;
            for index in 0..count {
                result.add(index).write(c_int::from(observed(
                    xp.add(index).read_unaligned(),
                    yp.add(index).read_unaligned(),
                )));
            }
        } else {
            failed_blocks += 1;
            // Repeated failed proofs only choose the exact algorithm for the
            // rest of this span. They never establish a fact about later rows.
            // This bounds wasted scans on dense missing or unusual imports.
            if failed_blocks == 4 {
                return valid
                    & pair_exact::<X_MODERN, Y_MODERN, _, _>(
                        xp,
                        yp,
                        result,
                        length - start,
                        &observed,
                        &missing,
                    );
            }
            valid &=
                pair_exact::<X_MODERN, Y_MODERN, _, _>(xp, yp, result, count, &observed, &missing);
        }
        start += count;
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
        0 => pair::<X, Y, _, _>(x, y, output, length, |a, b| a == b, |a, b| a == b),
        1 => pair::<X, Y, _, _>(x, y, output, length, |a, b| a != b, |a, b| a != b),
        2 => pair::<X, Y, _, _>(x, y, output, length, |a, b| a < b, |a, b| a < b),
        3 => pair::<X, Y, _, _>(x, y, output, length, |a, b| a <= b, |a, b| a <= b),
        4 => pair::<X, Y, _, _>(x, y, output, length, |a, b| a > b, |a, b| a > b),
        _ => pair::<X, Y, _, _>(x, y, output, length, |a, b| a >= b, |a, b| a >= b),
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
    fn float_pair_ieee_edges_and_missing_values_match_decoding() {
        let mut values = vec![
            0.0,
            -0.0,
            f32::MIN,
            f32::MAX,
            f32::NEG_INFINITY,
            f32::INFINITY,
            f32::from_bits(DOT - 1),
            f32::from_bits(DOT + 1),
            f32::NAN,
            f32::from_bits(0xffc00001),
        ];
        values.extend((0..27).map(|tag| f32::from_bits(DOT + tag * STEP)));
        for xv in [FormatVersion::V111, FormatVersion::V119] {
            for yv in [FormatVersion::V111, FormatVersion::V119] {
                for &a in &values {
                    for &b in &values {
                        let x = [a];
                        let y = [b];
                        let left = view(&x, xv);
                        let right = view(&y, yv);
                        let decoded = unsafe {
                            compare_operand_element(left, 0).zip(compare_operand_element(right, 0))
                        };
                        for op in 0..=5 {
                            let mut output = [0];
                            let valid = unsafe {
                                compare(
                                    op,
                                    left,
                                    Some(right),
                                    ComparedElement { rank: 0, value: 0. },
                                    output.as_mut_ptr(),
                                    1,
                                )
                            };
                            assert_eq!(valid, Some(decoded.is_some()));
                            if let Some((a, b)) = decoded {
                                assert_eq!(output[0], compare_decoded(op, a, b));
                            }
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn float_pair_blocks_preserve_boundaries_and_invalid_fallback() {
        let edges = [
            -0.0,
            f32::from_bits(DOT - 1),
            f32::from_bits(DOT),
            f32::from_bits(DOT + STEP),
            f32::from_bits(DOT + 26 * STEP),
            f32::from_bits(DOT + 1),
            f32::MAX,
            f32::INFINITY,
            f32::NEG_INFINITY,
            f32::NAN,
            f32::from_bits(0xffc00001),
        ];
        for length in [0_usize, 1, 15, 16, 17, 63, 64, 65, 127, 128, 129] {
            // The out-of-range position leaves full blocks and tails ordinary.
            let mut positions = vec![length, 0, length / 2, length.saturating_sub(1), 63, 64, 65];
            positions.sort_unstable();
            positions.dedup();
            for position in positions {
                for edge in edges {
                    let mut x: Vec<f32> = (0..length).map(|i| (i % 7) as f32 / 8.).collect();
                    let mut y: Vec<f32> = (0..length).map(|i| (i % 3) as f32 / 8.).collect();
                    if position < length {
                        x[position] = edge;
                        y[(position + 1) % length] = f32::from_bits(DOT + 3 * STEP);
                    }
                    for xv in [FormatVersion::V111, FormatVersion::V119] {
                        for yv in [FormatVersion::V111, FormatVersion::V119] {
                            let left = view(&x, xv);
                            let right = view(&y, yv);
                            for op in 0..=5 {
                                let expected: Option<Vec<c_int>> = (0..length)
                                    .map(|i| unsafe {
                                        compare_operand_element(left, i)
                                            .zip(compare_operand_element(right, i))
                                            .map(|(a, b)| compare_decoded(op, a, b))
                                    })
                                    .collect();
                                let mut output = vec![-19; length + 2];
                                let valid = unsafe {
                                    compare(
                                        op,
                                        left,
                                        Some(right),
                                        ComparedElement { rank: 0, value: 0. },
                                        output.as_mut_ptr().add(1),
                                        length,
                                    )
                                };
                                assert_eq!(valid, Some(expected.is_some()));
                                if let Some(expected) = expected {
                                    assert_eq!(&output[1..length + 1], expected.as_slice());
                                }
                                assert_eq!(output[0], -19);
                                assert_eq!(output[length + 1], -19);
                            }
                        }
                    }
                }
            }
        }
    }
    #[test]
    fn a_dense_prefix_does_not_keep_the_ordinary_float_tail_on_the_exact_path() {
        let length = 1_000_000;
        let prefix = 256;
        let mut x = vec![1.0; length];
        x[..prefix].fill(f32::from_bits(DOT));
        let y = vec![2.0; length];
        let mut output = vec![0; length];
        PAIR_EXACT_ROWS.with(|rows| rows.set(0));
        assert_eq!(
            unsafe {
                compare(
                    2,
                    view(&x, FormatVersion::V119),
                    Some(view(&y, FormatVersion::V119)),
                    ComparedElement { rank: 0, value: 0. },
                    output.as_mut_ptr(),
                    length,
                )
            },
            Some(true)
        );
        assert!(output[..prefix].iter().all(|&value| value == 0));
        assert!(output[prefix..].iter().all(|&value| value == 1));
        // Measure actual exact-loop work, without imposing a noisy clock limit.
        // A short exceptional prefix must not choose expensive decoding for
        // almost the entire ordinary column.
        let exact_rows = PAIR_EXACT_ROWS.with(|rows| rows.get());
        assert!(exact_rows < length / 10, "{exact_rows} exact rows");
    }

    #[test]
    fn float_pair_dense_switch_preserves_late_rows_and_invalidity() {
        for length in [255_usize, 256, 257, 320, 1025] {
            for pattern in 0..3 {
                for invalid in [None, Some(1), Some(193), Some(length - 1)] {
                    let mut x: Vec<f32> = (0..length).map(|i| (i % 7) as f32 / 8.).collect();
                    let mut y: Vec<f32> = (0..length).map(|i| (i % 3) as f32 / 8.).collect();
                    for i in 0..length {
                        let tagged = match pattern {
                            0 => i < 256,
                            1 => i >= 64,
                            _ => i / 64 % 2 == 0,
                        };
                        if tagged {
                            x[i] = f32::from_bits(DOT + (i % 27) as u32 * STEP);
                            y[i] = f32::from_bits(DOT + (26 - i % 27) as u32 * STEP);
                        }
                    }
                    if let Some(i) = invalid {
                        x[i] = f32::from_bits(0xffc00001);
                    }
                    for xv in [FormatVersion::V111, FormatVersion::V119] {
                        for yv in [FormatVersion::V111, FormatVersion::V119] {
                            let left = view(&x, xv);
                            let right = view(&y, yv);
                            for op in 0..=5 {
                                let expected: Option<Vec<c_int>> = (0..length)
                                    .map(|i| unsafe {
                                        compare_operand_element(left, i)
                                            .zip(compare_operand_element(right, i))
                                            .map(|(a, b)| compare_decoded(op, a, b))
                                    })
                                    .collect();
                                let mut output = vec![-19; length + 2];
                                let valid = unsafe {
                                    compare(
                                        op,
                                        left,
                                        Some(right),
                                        ComparedElement { rank: 0, value: 0. },
                                        output.as_mut_ptr().add(1),
                                        length,
                                    )
                                };
                                assert_eq!(valid, Some(expected.is_some()));
                                if let Some(expected) = expected {
                                    assert_eq!(&output[1..length + 1], expected.as_slice());
                                }
                                assert_eq!(output[0], -19);
                                assert_eq!(output[length + 1], -19);
                            }
                        }
                    }
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
