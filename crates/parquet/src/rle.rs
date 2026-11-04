//! The RLE / bit-packing hybrid that Parquet uses for definition levels,
//! dictionary indices and RLE booleans, and the older BIT_PACKED level
//! encoding.

use dta::{Error, Result};

/// A value the decoders can produce: levels go into `u8`, indices into
/// `u32`.
pub(crate) trait Small: Copy + Default + PartialEq {
    fn from_u32(v: u32) -> Self;
    fn to_u32(self) -> u32;
}

impl Small for u8 {
    #[inline]
    fn from_u32(v: u32) -> Self {
        v as u8
    }
    #[inline]
    fn to_u32(self) -> u32 {
        u32::from(self)
    }
}

impl Small for u32 {
    #[inline]
    fn from_u32(v: u32) -> Self {
        v
    }
    #[inline]
    fn to_u32(self) -> u32 {
        self
    }
}

/// Bits needed to hold every value up to `max`.
pub(crate) fn width_for(max: u32) -> u8 {
    (32 - max.leading_zeros()) as u8
}

fn varint(buf: &[u8], at: &mut usize) -> Result<u64> {
    let mut v = 0u64;
    for shift in (0..64).step_by(7) {
        let b = *buf
            .get(*at)
            .ok_or_else(|| Error::new("RLE data ends early"))?;
        *at += 1;
        v |= u64::from(b & 0x7f) << shift;
        if b & 0x80 == 0 {
            return Ok(v);
        }
    }
    Err(Error::new("bad RLE run header"))
}

/// Unpack `out.len()` (at most 8) values of `width` bits, packed from the
/// least significant bit, from `bytes` (which may be short: missing bytes
/// read as zero).
#[inline]
fn unpack8<T: Small>(bytes: &[u8], width: u8, out: &mut [T]) {
    let mut tmp = [0u8; 40];
    let n = bytes.len().min(32);
    tmp[..n].copy_from_slice(&bytes[..n]);
    let mask = if width == 32 {
        u64::from(u32::MAX)
    } else {
        (1u64 << width) - 1
    };
    let mut bit = 0usize;
    for o in out.iter_mut() {
        let at = bit >> 3;
        let word = u64::from_le_bytes(tmp[at..at + 8].try_into().expect("8 bytes"));
        *o = T::from_u32(((word >> (bit & 7)) & mask) as u32);
        bit += width as usize;
    }
}

/// Decode `out.len()` values of the hybrid encoding from the start of
/// `buf`. Returns the bytes used. Runs may hold more values than asked
/// for (the last bit-packed run is padded to a multiple of eight); the
/// rest are ignored.
pub(crate) fn decode<T: Small>(buf: &[u8], width: u8, out: &mut [T]) -> Result<usize> {
    if width > 32 {
        return Err(Error::new(format!("RLE bit width {width} is more than 32")));
    }
    let value_bytes = (width as usize).div_ceil(8);
    let mut at = 0;
    let mut filled = 0;
    while filled < out.len() {
        let header = varint(buf, &mut at)?;
        if header & 1 == 0 {
            let run = usize::try_from(header >> 1).unwrap_or(usize::MAX);
            let bytes = buf
                .get(at..at + value_bytes)
                .ok_or_else(|| Error::new("RLE data ends early"))?;
            let mut v = 0u32;
            for (k, b) in bytes.iter().enumerate() {
                v |= u32::from(*b) << (8 * k);
            }
            if width < 32 && v >> width != 0 {
                return Err(Error::new("RLE value wider than its bit width"));
            }
            at += value_bytes;
            if run == 0 {
                return Err(Error::new("empty RLE run"));
            }
            let take = run.min(out.len() - filled);
            out[filled..filled + take].fill(T::from_u32(v));
            filled += take;
        } else {
            let groups = usize::try_from(header >> 1).unwrap_or(usize::MAX);
            if groups == 0 {
                return Err(Error::new("empty bit-packed run"));
            }
            let values = groups.saturating_mul(8);
            let take = values.min(out.len() - filled);
            // Some writers end the last run's bytes early; the values
            // asked for must still be there.
            let need = (take * width as usize).div_ceil(8);
            let have = (buf.len() - at).min(groups.saturating_mul(width as usize));
            if have < need {
                return Err(Error::new("bit-packed run ends early"));
            }
            let run = &buf[at..at + have];
            let w = width as usize;
            for (g, chunk) in out[filled..filled + take].chunks_mut(8).enumerate() {
                let start = (g * w).min(run.len());
                unpack8(&run[start..(start + w).min(run.len())], width, chunk);
            }
            at += have;
            filled += take;
        }
    }
    Ok(at)
}

/// Decode the older BIT_PACKED encoding: `out.len()` values packed from
/// the most significant bit, with no header. Returns the bytes used.
pub(crate) fn decode_bit_packed(buf: &[u8], width: u8, out: &mut [u8]) -> Result<usize> {
    let bytes = (out.len() * width as usize).div_ceil(8);
    let buf = buf
        .get(..bytes)
        .ok_or_else(|| Error::new("bit-packed levels end early"))?;
    let mut bit = 0usize;
    for o in out.iter_mut() {
        let mut v = 0u8;
        for _ in 0..width {
            let b = (buf[bit >> 3] >> (7 - (bit & 7))) & 1;
            v = (v << 1) | b;
            bit += 1;
        }
        *o = v;
    }
    Ok(bytes)
}

/// Bit-packed literal runs are cut at this many groups of eight, as other
/// writers do, so a run header always fits in one byte.
const MAX_GROUPS: usize = 63;

/// Append the hybrid encoding of `values` at `width` bits each.
pub(crate) fn encode<T: Small>(values: &[T], width: u8, out: &mut Vec<u8>) {
    let value_bytes = (width as usize).div_ceil(8);
    let mut literal: Vec<u32> = Vec::with_capacity(MAX_GROUPS * 8);
    let mut at = 0;
    while at < values.len() {
        // Runs start only on a group boundary of the pending literals, so
        // every literal run but the last holds whole groups of eight.
        if literal.len() % 8 == 0 {
            let v = values[at];
            let mut run = 1;
            while at + run < values.len() && values[at + run] == v {
                run += 1;
            }
            if run >= 8 {
                flush_literal(&mut literal, width, out);
                put_varint(out, (run as u64) << 1);
                let v = v.to_u32();
                out.extend_from_slice(&v.to_le_bytes()[..value_bytes]);
                at += run;
                continue;
            }
        }
        literal.push(values[at].to_u32());
        at += 1;
        if literal.len() == MAX_GROUPS * 8 {
            flush_literal(&mut literal, width, out);
        }
    }
    flush_literal(&mut literal, width, out);
}

fn flush_literal(literal: &mut Vec<u32>, width: u8, out: &mut Vec<u8>) {
    if literal.is_empty() {
        return;
    }
    let groups = literal.len().div_ceil(8);
    literal.resize(groups * 8, 0);
    put_varint(out, (groups as u64) << 1 | 1);
    let mut acc = 0u64;
    let mut bits = 0u32;
    for &v in literal.iter() {
        acc |= u64::from(v) << bits;
        bits += u32::from(width);
        while bits >= 8 {
            out.push(acc as u8);
            acc >>= 8;
            bits -= 8;
        }
    }
    literal.clear();
}

pub(crate) fn put_varint(out: &mut Vec<u8>, mut v: u64) {
    while v >= 0x80 {
        out.push(v as u8 | 0x80);
        v >>= 7;
    }
    out.push(v as u8);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn round_trip(values: &[u32], width: u8) {
        let mut buf = Vec::new();
        encode(values, width, &mut buf);
        let mut got = vec![0u32; values.len()];
        let used = decode(&buf, width, &mut got).unwrap();
        assert_eq!(got, values);
        assert_eq!(used, buf.len());
    }

    #[test]
    fn widths_and_patterns_round_trip() {
        let mut seed = 12345u64;
        let mut next = || {
            seed = seed
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            (seed >> 33) as u32
        };
        for width in [0u8, 1, 2, 3, 7, 8, 9, 15, 16, 17, 24, 31, 32] {
            let max = if width == 32 {
                u32::MAX
            } else {
                (1u32 << width).wrapping_sub(1)
            };
            for len in [0usize, 1, 7, 8, 9, 63, 64, 500, 504, 505, 1000, 5000] {
                let random: Vec<u32> = (0..len).map(|_| next() & max).collect();
                round_trip(&random, width);
                // Runs mixed with literals.
                let runs: Vec<u32> = (0..len)
                    .map(|i| {
                        if (i / 13) % 2 == 0 {
                            max
                        } else {
                            (i as u32) & max
                        }
                    })
                    .collect();
                round_trip(&runs, width);
            }
        }
    }

    #[test]
    fn long_runs_are_one_rle_run() {
        let ones = vec![1u8; 100_000];
        let mut buf = Vec::new();
        encode(&ones, 1, &mut buf);
        assert_eq!(buf.len(), 4); // varint(200000) is 3 bytes, the value 1
        let mut got = vec![0u8; ones.len()];
        decode(&buf, 1, &mut got).unwrap();
        assert!(got.iter().all(|&v| v == 1));
    }

    #[test]
    fn known_bytes_decode() {
        // The format specification's example: values 0..7 at width 3,
        // bit-packed, one group.
        let buf = [0x03, 0b1000_1000, 0b1100_0110, 0b1111_1010];
        let mut got = [0u32; 8];
        decode(&buf, 3, &mut got).unwrap();
        assert_eq!(got, [0, 1, 2, 3, 4, 5, 6, 7]);
        // The legacy BIT_PACKED order for the same values.
        let legacy = [0b0000_0101, 0b0011_1001, 0b0111_0111];
        let mut got = [0u8; 8];
        decode_bit_packed(&legacy, 3, &mut got).unwrap();
        assert_eq!(got, [0, 1, 2, 3, 4, 5, 6, 7]);
    }

    #[test]
    fn short_last_run_is_accepted_when_values_fit() {
        // 3 values at width 1 in a run of one group, with its byte.
        let mut got = [0u8; 3];
        decode(&[0x03, 0b101], 1, &mut got).unwrap();
        assert_eq!(got, [1, 0, 1]);
    }

    #[test]
    fn damage_is_an_error() {
        let mut out = [0u32; 10];
        assert!(decode(&[], 3, &mut out).is_err());
        assert!(decode(&[0x03, 0x01], 8, &mut out).is_err());
        assert!(decode(&[0x00], 3, &mut out).is_err());
        assert!(decode(&[0x14, 0xff], 3, &mut out).is_err()); // value wider than width
        assert!(decode(&[0x02, 0], 33, &mut out).is_err());
        assert!(decode(&[0xff; 12], 3, &mut out).is_err());
        let mut out = [0u8; 9];
        assert!(decode_bit_packed(&[0xff], 1, &mut out).is_err());
    }
}
