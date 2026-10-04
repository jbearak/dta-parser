//! Allocation-specific facts collected while readers already visit numeric bytes.
//! No generic descriptor factory grants these facts. Coverage is deliberately
//! stricter than the missing-count cache: repeated or reordered writes decline.

use crate::{FormatVersion, NumericData, NumericKind, TemporalKind};

const STRICT_MODERN_FLOAT: u32 = 1;
const FLOAT_BOUNDS_KNOWN: u32 = 2;
const ZERO_COUNT_KNOWN: u32 = 4;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct NumericFacts {
    flags: u32,
    maximum: u32,
    minimum_nonzero: u32,
    zeros: usize,
}

impl NumericFacts {
    pub(crate) fn publish(self, descriptor: &mut NumericData) {
        descriptor.domain_flags = self.flags;
        descriptor.float_max_magnitude_bound = self.maximum;
        descriptor.float_min_nonzero_magnitude_bound = self.minimum_nonzero;
        descriptor.zero_count = self.zeros;
    }
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct FloatFacts {
    valid: bool,
    maximum: u32,
    minimum_nonzero: u32,
    zeros: usize,
}

impl FloatFacts {
    pub(crate) fn new() -> Self {
        Self {
            valid: true,
            maximum: 0,
            minimum_nonzero: u32::MAX,
            zeros: 0,
        }
    }

    #[inline(always)]
    pub(crate) fn observe(&mut self, bits: u32) {
        let magnitude = bits & 0x7fff_ffff;
        let observed = magnitude <= 0x7eff_ffff;
        let tag_offset = bits.wrapping_sub(0x7f00_0000);
        let canonical_tag = tag_offset <= 26 * 2048 && tag_offset & 2047 == 0;
        self.valid &= observed || canonical_tag;
        self.maximum = self.maximum.max(if observed { magnitude } else { 0 });
        self.minimum_nonzero = self.minimum_nonzero.min(if observed && magnitude != 0 {
            magnitude
        } else {
            u32::MAX
        });
        self.zeros += usize::from(observed && magnitude == 0);
    }

    fn merge(&mut self, block: Self) {
        self.valid &= block.valid;
        self.maximum = self.maximum.max(block.maximum);
        self.minimum_nonzero = self.minimum_nonzero.min(block.minimum_nonzero);
        self.zeros += block.zeros;
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Eligibility {
    Unknown,
    Integer,
    Float,
}

pub(crate) struct ReaderFacts {
    eligibility: Eligibility,
    next_row: usize,
    ordered: bool,
    float: FloatFacts,
    integer_zeros: usize,
}

impl ReaderFacts {
    pub(crate) fn new(kind: NumericKind, temporal: TemporalKind, version: FormatVersion) -> Self {
        let eligibility = if temporal != TemporalKind::None {
            Eligibility::Unknown
        } else if kind != NumericKind::Float {
            Eligibility::Integer
        } else if version.as_u16() > 111 {
            Eligibility::Float
        } else {
            Eligibility::Unknown
        };
        Self {
            eligibility,
            next_row: 0,
            ordered: true,
            float: FloatFacts::new(),
            integer_zeros: 0,
        }
    }

    pub(crate) fn unknown() -> Self {
        Self {
            eligibility: Eligibility::Unknown,
            next_row: 0,
            ordered: false,
            float: FloatFacts::new(),
            integer_zeros: 0,
        }
    }

    #[inline(always)]
    pub(crate) fn collects_float(&self) -> bool {
        self.eligibility == Eligibility::Float && self.ordered
    }

    #[inline(always)]
    pub(crate) fn collects_integer(&self) -> bool {
        self.eligibility == Eligibility::Integer && self.ordered
    }

    fn record_coverage(&mut self, start: usize, count: usize) -> bool {
        if count == 0 {
            return self.ordered;
        }
        if !self.ordered || start != self.next_row {
            self.ordered = false;
            return false;
        }
        if let Some(end) = start.checked_add(count) {
            self.next_row = end;
            true
        } else {
            self.ordered = false;
            false
        }
    }

    #[inline(always)]
    pub(crate) fn record_float(&mut self, row: usize, bits: u32) {
        if self.collects_float() && self.record_coverage(row, 1) {
            self.float.observe(bits);
        }
    }

    pub(crate) fn record_float_span(&mut self, start: usize, count: usize, block: FloatFacts) {
        if self.eligibility == Eligibility::Float && self.record_coverage(start, count) {
            self.float.merge(block);
        }
    }

    #[inline(always)]
    pub(crate) fn record_integer_span(&mut self, start: usize, count: usize, zeros: usize) {
        if self.eligibility == Eligibility::Integer && self.record_coverage(start, count) {
            if zeros > count {
                self.ordered = false;
            } else {
                self.integer_zeros += zeros;
            }
        }
    }

    pub(crate) fn finish(&self, expected_rows: usize) -> NumericFacts {
        if !self.ordered || self.next_row != expected_rows {
            return NumericFacts::default();
        }
        match self.eligibility {
            Eligibility::Float if self.float.valid => NumericFacts {
                flags: STRICT_MODERN_FLOAT | FLOAT_BOUNDS_KNOWN | ZERO_COUNT_KNOWN,
                maximum: self.float.maximum,
                minimum_nonzero: self.float.minimum_nonzero,
                zeros: self.float.zeros,
            },
            Eligibility::Integer => NumericFacts {
                flags: ZERO_COUNT_KNOWN,
                zeros: self.integer_zeros,
                ..NumericFacts::default()
            },
            _ => NumericFacts::default(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn float_facts_require_complete_ordered_strict_modern_non_temporal_values() {
        let mut bits = vec![0, 0x8000_0000, 1, 0x8000_0001, 0x7eff_ffff, 0xfeff_ffff];
        bits.extend((0..=26).map(|tag| 0x7f00_0000 + tag * 2048));
        let mut facts =
            ReaderFacts::new(NumericKind::Float, TemporalKind::None, FormatVersion::V118);
        assert_eq!(facts.finish(bits.len()), NumericFacts::default());
        for (row, &value) in bits.iter().enumerate() {
            facts.record_float(row, value);
        }
        assert_eq!(
            facts.finish(bits.len()),
            NumericFacts {
                flags: 7,
                maximum: 0x7eff_ffff,
                minimum_nonzero: 1,
                zeros: 2
            }
        );
        assert_eq!(facts.finish(bits.len() - 1), NumericFacts::default());
        facts.record_float(bits.len() - 1, 0);
        assert_eq!(facts.finish(bits.len()), NumericFacts::default());
        for (version, temporal) in [
            (FormatVersion::V111, TemporalKind::None),
            (FormatVersion::V118, TemporalKind::Date),
            (FormatVersion::V118, TemporalKind::Datetime),
        ] {
            let mut facts = ReaderFacts::new(NumericKind::Float, temporal, version);
            facts.record_float(0, 0);
            assert_eq!(facts.finish(1), NumericFacts::default());
        }
        let mut facts =
            ReaderFacts::new(NumericKind::Float, TemporalKind::None, FormatVersion::V118);
        facts.record_float(1, 0);
        facts.record_float(0, 0);
        assert_eq!(facts.finish(2), NumericFacts::default());
    }

    #[test]
    fn any_invalid_float_tail_declines_both_bounds_and_zero_count() {
        for invalid in [
            0x7f00_0001,
            0x7f00_d001,
            0xff00_0000,
            0x7f7f_ffff,
            0xff7f_ffff,
            0x7f80_0000,
            0xff80_0000,
            0x7f80_0001,
            0xff80_0001,
            0x7fc0_0000,
            0xffc0_0000,
        ] {
            let mut facts =
                ReaderFacts::new(NumericKind::Float, TemporalKind::None, FormatVersion::V118);
            let mut first = FloatFacts::new();
            for bits in [0, 0x8000_0000, 0x3f80_0000] {
                first.observe(bits);
            }
            facts.record_float_span(0, 3, first);
            let mut tail = FloatFacts::new();
            tail.observe(invalid);
            facts.record_float_span(3, 1, tail);
            assert_eq!(facts.finish(4), NumericFacts::default(), "{invalid:#x}");
        }
    }

    #[test]
    fn empty_and_nonzero_free_extents_and_integer_zeros_are_exact() {
        let mut facts =
            ReaderFacts::new(NumericKind::Float, TemporalKind::None, FormatVersion::V118);
        let expected = NumericFacts {
            flags: 7,
            maximum: 0,
            minimum_nonzero: u32::MAX,
            zeros: 0,
        };
        assert_eq!(facts.finish(0), expected);
        for (row, bits) in [0, 0x8000_0000, 0x7f00_0000, 0x7f00_d000]
            .into_iter()
            .enumerate()
        {
            facts.record_float(row, bits);
        }
        assert_eq!(
            facts.finish(4),
            NumericFacts {
                zeros: 2,
                ..expected
            }
        );
        for kind in [NumericKind::Byte, NumericKind::Int, NumericKind::Long] {
            let mut facts = ReaderFacts::new(kind, TemporalKind::None, FormatVersion::V111);
            facts.record_integer_span(0, 3, 2);
            facts.record_integer_span(3, 4, 1);
            assert_eq!(
                facts.finish(7),
                NumericFacts {
                    flags: 4,
                    zeros: 3,
                    ..NumericFacts::default()
                }
            );
            facts.record_integer_span(6, 1, 0);
            assert_eq!(facts.finish(7), NumericFacts::default());
        }
        assert_eq!(ReaderFacts::unknown().finish(0), NumericFacts::default());
    }
}
