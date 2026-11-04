//! The encodings other writers use beside PLAIN and dictionary:
//! DELTA_BINARY_PACKED (integers), DELTA_LENGTH_BYTE_ARRAY and
//! DELTA_BYTE_ARRAY (byte arrays), and BYTE_STREAM_SPLIT (fixed-width
//! values, one stream per byte).
//!
//! Every decoder here reads untrusted bytes: lengths and counts are
//! checked against what is left, arithmetic on them is checked, and
//! memory follows the values asked for, not the counts a header gives.
//! A run of values that takes no bytes (a miniblock of bit width 0) is
//! skipped in one step.

use dta::{Error, Result};

/// An unsigned LEB128 varint at `*at`, moving `*at` past it.
fn varint(buf: &[u8], at: &mut usize) -> Result<u64> {
    let mut v = 0u64;
    for shift in (0..64).step_by(7) {
        let b = *buf.get(*at).ok_or_else(|| short(DBP))?;
        *at += 1;
        v |= u64::from(b & 0x7f) << shift;
        if b & 0x80 == 0 {
            return Ok(v);
        }
    }
    Err(Error::new(format!("{DBP}: a varint longer than 10 bytes")))
}

fn short(what: &str) -> Error {
    Error::new(format!("{what} data ends early"))
}

const DBP: &str = "DELTA_BINARY_PACKED";

/// Read a zigzag varint as the two's-complement bits of an i64.
fn zigzag(buf: &[u8], at: &mut usize) -> Result<u64> {
    let v = varint(buf, at).map_err(|_| short(DBP))?;
    Ok((v >> 1) ^ (v & 1).wrapping_neg())
}

/// A count from a varint, as a usize this machine can index with.
fn count(buf: &[u8], at: &mut usize, what: &str) -> Result<usize> {
    let v = varint(buf, at).map_err(|_| short(DBP))?;
    usize::try_from(v).map_err(|_| Error::new(format!("{DBP}: {what} {v} is too large")))
}

/// `width` bits (1 to 64) at bit `bit` of `data`, packed from the least
/// significant bit; bytes past the end read as zero.
#[inline]
fn bits_at(data: &[u8], bit: usize, width: u32) -> u64 {
    let at = bit >> 3;
    let mut tmp = [0u8; 16];
    if let Some(rest) = data.get(at..) {
        let n = rest.len().min(16);
        tmp[..n].copy_from_slice(&rest[..n]);
    }
    let word = u128::from_le_bytes(tmp) >> (bit & 7);
    let mask = if width == 64 {
        u128::from(u64::MAX)
    } else {
        (1u128 << width) - 1
    };
    (word & mask) as u64
}

/// A DELTA_BINARY_PACKED stream: a header (values per block, miniblocks
/// per block, the count of values, the first value), then blocks of
/// deltas, each a minimum delta, a bit width per miniblock and the
/// miniblocks bit-packed. Values are produced as the two's-complement
/// bits of an i64 (an INT32 column takes the low 32 bits; the arithmetic
/// wraps either way).
pub(crate) struct DeltaPacked<'a> {
    buf: &'a [u8],
    /// The next unread byte: a block header or a miniblock.
    at: usize,
    miniblocks: usize,
    per_mini: usize,
    /// Values not yet produced, the first included.
    left: u64,
    /// The first value, until it is produced.
    first: Option<u64>,
    last: u64,
    min_delta: u64,
    widths: &'a [u8],
    /// The current miniblock: its index in its block (`miniblocks` when
    /// a new block is due), bytes, bit width and values used.
    mini: usize,
    data: &'a [u8],
    width: u32,
    used: usize,
}

impl<'a> DeltaPacked<'a> {
    pub(crate) fn new(buf: &'a [u8]) -> Result<Self> {
        let mut at = 0;
        let per_block = count(buf, &mut at, "a block of")?;
        let miniblocks = count(buf, &mut at, "a block of")?;
        let total = varint(buf, &mut at).map_err(|_| short(DBP))?;
        let first = zigzag(buf, &mut at)?;
        if per_block == 0 || per_block % 128 != 0 {
            return Err(Error::new(format!(
                "{DBP}: a block of {per_block} values, which is not a multiple of 128"
            )));
        }
        if miniblocks == 0 || per_block % miniblocks != 0 || (per_block / miniblocks) % 32 != 0 {
            return Err(Error::new(format!(
                "{DBP}: {miniblocks} miniblocks in a block of {per_block} values"
            )));
        }
        Ok(DeltaPacked {
            buf,
            at,
            miniblocks,
            per_mini: per_block / miniblocks,
            left: total,
            first: (total > 0).then_some(first),
            last: first,
            min_delta: 0,
            widths: &[],
            mini: miniblocks,
            data: &[],
            width: 0,
            used: per_block / miniblocks,
        })
    }

    /// The values the header says the stream holds.
    #[cfg(test)]
    fn total(&self) -> u64 {
        self.left
    }

    /// Move to the next miniblock, reading a block header when one is due.
    fn next_mini(&mut self) -> Result<()> {
        if self.mini + 1 >= self.miniblocks {
            self.min_delta = zigzag(self.buf, &mut self.at)?;
            self.widths = self
                .buf
                .get(self.at..)
                .and_then(|b| b.get(..self.miniblocks))
                .ok_or_else(|| short(DBP))?;
            self.at += self.miniblocks;
            self.mini = 0;
        } else {
            self.mini += 1;
        }
        let width = u32::from(self.widths[self.mini]);
        if width > 64 {
            return Err(Error::new(format!("{DBP}: a bit width of {width}")));
        }
        // per_mini is a multiple of 32, so this is whole bytes.
        let len = self
            .per_mini
            .checked_mul(width as usize)
            .ok_or_else(|| short(DBP))?
            / 8;
        // The last miniblock may be cut short; the values used must be
        // there (checked as they are read).
        let start = self.at.min(self.buf.len());
        let end = self.at.saturating_add(len).min(self.buf.len());
        self.data = &self.buf[start..end];
        self.at = self.at.saturating_add(len);
        self.width = width;
        self.used = 0;
        Ok(())
    }

    /// Produce the next `n` values, calling `f` with each, or (`f` being
    /// `None`) skip them. A miniblock of width 0 is skipped in one step.
    fn advance(&mut self, mut n: usize, mut f: Option<&mut dyn FnMut(u64)>) -> Result<()> {
        if n == 0 {
            return Ok(());
        }
        if let Some(v) = self.first.take() {
            if let Some(f) = f.as_deref_mut() {
                f(v);
            }
            self.left -= 1;
            n -= 1;
        }
        while n > 0 {
            if self.left == 0 {
                return Err(Error::new(format!(
                    "{DBP} data holds fewer values than its page"
                )));
            }
            if self.used == self.per_mini {
                self.next_mini()?;
            }
            let k = n
                .min(self.per_mini - self.used)
                .min(usize::try_from(self.left).unwrap_or(usize::MAX));
            if self.width == 0 {
                match f.as_deref_mut() {
                    None => {
                        self.last = self
                            .last
                            .wrapping_add(self.min_delta.wrapping_mul(k as u64))
                    }
                    Some(f) => {
                        for _ in 0..k {
                            self.last = self.last.wrapping_add(self.min_delta);
                            f(self.last);
                        }
                    }
                }
            } else {
                let w = self.width as usize;
                let end_bit = (self.used + k).checked_mul(w).ok_or_else(|| short(DBP))?;
                if end_bit.div_ceil(8) > self.data.len() {
                    return Err(short(DBP));
                }
                for j in self.used..self.used + k {
                    let d = bits_at(self.data, j * w, self.width);
                    self.last = self.last.wrapping_add(self.min_delta).wrapping_add(d);
                    if let Some(f) = f.as_deref_mut() {
                        f(self.last);
                    }
                }
            }
            self.used += k;
            self.left -= k as u64;
            n -= k;
        }
        Ok(())
    }

    pub(crate) fn skip(&mut self, n: usize) -> Result<()> {
        self.advance(n, None)
    }

    /// Fill `out` with the next values.
    pub(crate) fn take(&mut self, out: &mut [u64]) -> Result<()> {
        let mut i = 0;
        self.advance(
            out.len(),
            Some(&mut |v| {
                out[i] = v;
                i += 1;
            }),
        )
    }

    /// The bytes the whole stream takes, found by walking its blocks
    /// without decoding them. Byte-array encodings put more data after
    /// it. Must be called before any value is produced.
    pub(crate) fn end(&self) -> Result<usize> {
        let mut at = self.at;
        let mut left = self.left.saturating_sub(1);
        while left > 0 {
            zigzag(self.buf, &mut at)?;
            let widths = self
                .buf
                .get(at..)
                .and_then(|b| b.get(..self.miniblocks))
                .ok_or_else(|| short(DBP))?;
            at += self.miniblocks;
            for &w in widths {
                if left == 0 {
                    // Miniblocks with no values take no bytes.
                    break;
                }
                if w > 64 {
                    return Err(Error::new(format!("{DBP}: a bit width of {w}")));
                }
                at = self
                    .per_mini
                    .checked_mul(usize::from(w))
                    .and_then(|bits| at.checked_add(bits / 8))
                    .filter(|&a| a <= self.buf.len())
                    .ok_or_else(|| short(DBP))?;
                left = left.saturating_sub(self.per_mini as u64);
            }
        }
        Ok(at)
    }
}

/// Values a batch decodes at a time, on the stack.
const BATCH: usize = 256;

/// Decode values `skip..skip + out.len()` of a DELTA_BINARY_PACKED stream.
pub(crate) fn delta_values(bytes: &[u8], skip: usize, out: &mut [u64]) -> Result<()> {
    let mut d = DeltaPacked::new(bytes)?;
    d.skip(skip)?;
    d.take(out)
}

/// A length from a DELTA_BINARY_PACKED stream of INT32 lengths.
fn length(v: u64, what: &str) -> Result<usize> {
    usize::try_from(v as u32 as i32).map_err(|_| Error::new(format!("{what}: a negative length")))
}

/// Byte-array values `skip..skip + n` of a page, handed to `push` in
/// order. `values` is the page's value bytes.
pub(crate) fn delta_length_byte_array(
    values: &[u8],
    skip: usize,
    n: usize,
    mut push: impl FnMut(&[u8]) -> Result<()>,
) -> Result<()> {
    const WHAT: &str = "DELTA_LENGTH_BYTE_ARRAY";
    let mut lengths = DeltaPacked::new(values)?;
    let data = &values[lengths.end()?..];
    let past = || Error::new(format!("{WHAT}: a value runs past the end of its page"));
    let mut at = 0usize;
    let mut batch = [0u64; BATCH];
    let mut done = 0;
    while done < skip + n {
        let k = BATCH.min(skip + n - done);
        lengths.take(&mut batch[..k])?;
        for (j, &v) in batch[..k].iter().enumerate() {
            let len = length(v, WHAT)?;
            let end = at
                .checked_add(len)
                .filter(|&e| e <= data.len())
                .ok_or_else(past)?;
            if done + j >= skip {
                push(&data[at..end])?;
            }
            at = end;
        }
        done += k;
    }
    Ok(())
}

/// The same for DELTA_BYTE_ARRAY: each value is a prefix of the one
/// before and a suffix. Every value up to the last wanted is rebuilt, in
/// `current`, which never holds more than the page's suffix bytes.
pub(crate) fn delta_byte_array(
    values: &[u8],
    skip: usize,
    n: usize,
    current: &mut Vec<u8>,
    mut push: impl FnMut(&[u8]) -> Result<()>,
) -> Result<()> {
    const WHAT: &str = "DELTA_BYTE_ARRAY";
    let mut prefixes = DeltaPacked::new(values)?;
    let p_end = prefixes.end()?;
    let mut suffixes = DeltaPacked::new(&values[p_end..])?;
    let s_end = p_end + suffixes.end()?;
    let data = &values[s_end..];
    current.clear();
    let mut at = 0usize;
    let (mut p, mut s) = ([0u64; BATCH], [0u64; BATCH]);
    let mut done = 0;
    while done < skip + n {
        let k = BATCH.min(skip + n - done);
        prefixes.take(&mut p[..k])?;
        suffixes.take(&mut s[..k])?;
        for j in 0..k {
            let prefix = length(p[j], WHAT)?;
            let len = length(s[j], WHAT)?;
            if prefix > current.len() {
                return Err(Error::new(format!(
                    "{WHAT}: a prefix longer than the value before it"
                )));
            }
            let end = at
                .checked_add(len)
                .filter(|&e| e <= data.len())
                .ok_or_else(|| {
                    Error::new(format!("{WHAT}: a value runs past the end of its page"))
                })?;
            current.truncate(prefix);
            current.extend_from_slice(&data[at..end]);
            at = end;
            if done + j >= skip {
                push(current)?;
            }
        }
        done += k;
    }
    Ok(())
}

/// BYTE_STREAM_SPLIT: a page of `count` values of `width` bytes holds
/// byte 0 of every value, then byte 1 of every value, and so on. Returns
/// the count, checking that the bytes are whole values.
pub(crate) fn split_count(values: &[u8], width: usize) -> Result<usize> {
    if width == 0 || values.len() % width != 0 {
        return Err(Error::new(format!(
            "BYTE_STREAM_SPLIT: {} bytes are not whole values of {width} bytes",
            values.len()
        )));
    }
    Ok(values.len() / width)
}

/// Value `i` of a BYTE_STREAM_SPLIT page of `count` values, gathered into
/// `out` (of the value's width).
#[inline]
pub(crate) fn split_value(values: &[u8], count: usize, i: usize, out: &mut [u8]) {
    for (k, b) in out.iter_mut().enumerate() {
        *b = values[k * count + i];
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::rle::put_varint;

    fn put_zigzag(out: &mut Vec<u8>, v: i64) {
        put_varint(out, ((v << 1) ^ (v >> 63)) as u64);
    }

    /// A DELTA_BINARY_PACKED encoder, for tests only: blocks of
    /// `per_block` values in `miniblocks` miniblocks; with `short_last`,
    /// the last miniblock's bytes stop after its last value.
    pub(crate) fn encode(
        values: &[i64],
        per_block: usize,
        miniblocks: usize,
        short_last: bool,
    ) -> Vec<u8> {
        let mut out = Vec::new();
        put_varint(&mut out, per_block as u64);
        put_varint(&mut out, miniblocks as u64);
        put_varint(&mut out, values.len() as u64);
        put_zigzag(&mut out, values.first().copied().unwrap_or(0));
        let deltas: Vec<i64> = values.windows(2).map(|w| w[1].wrapping_sub(w[0])).collect();
        let per_mini = per_block / miniblocks;
        let blocks = deltas.chunks(per_block).count();
        for (b, block) in deltas.chunks(per_block).enumerate() {
            let min = *block.iter().min().unwrap();
            put_zigzag(&mut out, min);
            let minis: Vec<&[i64]> = block.chunks(per_mini).collect();
            let widths: Vec<u8> = (0..miniblocks)
                .map(|m| {
                    minis.get(m).map_or(0, |mb| {
                        let max = mb
                            .iter()
                            .map(|&d| d.wrapping_sub(min) as u64)
                            .max()
                            .unwrap();
                        (64 - max.leading_zeros()) as u8
                    })
                })
                .collect();
            out.extend_from_slice(&widths);
            for (m, mb) in minis.iter().enumerate() {
                let w = u32::from(widths[m]);
                let mut bits = vec![0u8; per_mini * w as usize / 8];
                for (j, &d) in mb.iter().enumerate() {
                    let v = d.wrapping_sub(min) as u64;
                    for b in 0..w as usize {
                        if v >> b & 1 == 1 {
                            let bit = j * w as usize + b;
                            bits[bit / 8] |= 1 << (bit % 8);
                        }
                    }
                }
                if short_last && b + 1 == blocks && m + 1 == minis.len() {
                    bits.truncate((mb.len() * w as usize).div_ceil(8));
                }
                out.extend_from_slice(&bits);
            }
        }
        out
    }

    pub(crate) fn encode_lengths(values: &[&[u8]]) -> Vec<u8> {
        let lens: Vec<i64> = values.iter().map(|v| v.len() as i64).collect();
        let mut out = encode(&lens, 128, 4, false);
        for v in values {
            out.extend_from_slice(v);
        }
        out
    }

    pub(crate) fn encode_prefixed(values: &[&[u8]]) -> Vec<u8> {
        let mut prefixes = Vec::new();
        let mut suffixes: Vec<&[u8]> = Vec::new();
        let mut prev: &[u8] = &[];
        for v in values {
            let p = prev
                .iter()
                .zip(v.iter())
                .take_while(|(a, b)| a == b)
                .count();
            prefixes.push(p as i64);
            suffixes.push(&v[p..]);
            prev = v;
        }
        let mut out = encode(&prefixes, 128, 4, false);
        let lens: Vec<i64> = suffixes.iter().map(|s| s.len() as i64).collect();
        out.extend_from_slice(&encode(&lens, 128, 4, false));
        for s in suffixes {
            out.extend_from_slice(s);
        }
        out
    }

    fn rng(seed: &mut u64) -> u64 {
        *seed ^= *seed << 13;
        *seed ^= *seed >> 7;
        *seed ^= *seed << 17;
        *seed
    }

    #[test]
    fn delta_binary_packed_round_trips_in_windows() {
        let mut seed = 99u64;
        let sets: Vec<Vec<i64>> = vec![
            vec![],
            vec![7],
            (0..1000).collect(),
            (0..777).map(|i| i * 3 - 1000).collect(),
            (0..1300).map(|_| rng(&mut seed) as i64).collect(),
            (0..500)
                .map(|_| (rng(&mut seed) % 1000) as i64 - 500)
                .collect(),
            vec![i64::MIN, i64::MAX, 0, -1, 1, i64::MIN, i64::MAX],
            (0..300)
                .map(|i| if i % 2 == 0 { i64::MAX } else { i64::MIN })
                .collect(),
        ];
        for values in &sets {
            for (per_block, minis) in [(128, 4), (256, 8), (128, 1), (1024, 2)] {
                for short_last in [false, true] {
                    let bytes = encode(values, per_block, minis, short_last);
                    let d = DeltaPacked::new(&bytes).unwrap();
                    assert_eq!(d.total(), values.len() as u64);
                    if !short_last {
                        assert_eq!(d.end().unwrap(), bytes.len(), "{per_block}/{minis}");
                    }
                    let len = values.len();
                    let windows = [
                        (0, len),
                        (1, len.saturating_sub(1)),
                        (len / 2, len / 3),
                        (len.saturating_sub(1), len.min(1)),
                    ];
                    for (skip, n) in windows.into_iter().filter(|&(skip, n)| skip + n <= len) {
                        let mut out = vec![0u64; n];
                        delta_values(&bytes, skip, &mut out).unwrap();
                        let want: Vec<u64> =
                            values[skip..skip + n].iter().map(|&v| v as u64).collect();
                        assert_eq!(out, want, "{per_block}/{minis} {skip}+{n}");
                    }
                    // Asking for one more than it holds is an error.
                    let mut out = vec![0u64; values.len() + 1];
                    assert!(delta_values(&bytes, 0, &mut out).is_err());
                }
            }
        }
    }

    #[test]
    fn int32_deltas_wrap_in_32_bits() {
        // parquet-mr computes INT32 deltas in 32 bits: from i32::MAX to
        // i32::MIN is a delta of 1.
        let values = [i32::MAX, i32::MIN, 0, i32::MIN, i32::MAX];
        let mut bytes = Vec::new();
        put_varint(&mut bytes, 128);
        put_varint(&mut bytes, 4);
        put_varint(&mut bytes, values.len() as u64);
        put_zigzag(&mut bytes, i64::from(values[0]));
        let deltas: Vec<i32> = values.windows(2).map(|w| w[1].wrapping_sub(w[0])).collect();
        let min = *deltas.iter().min().unwrap();
        put_zigzag(&mut bytes, i64::from(min));
        bytes.extend_from_slice(&[32, 0, 0, 0]);
        let mut mini = vec![0u8; 32 * 4];
        for (j, d) in deltas.iter().enumerate() {
            mini[j * 4..j * 4 + 4].copy_from_slice(&(d.wrapping_sub(min) as u32).to_le_bytes());
        }
        bytes.extend_from_slice(&mini);
        let mut out = [0u64; 5];
        delta_values(&bytes, 0, &mut out).unwrap();
        let got: Vec<i32> = out.iter().map(|&v| v as u32 as i32).collect();
        assert_eq!(got, values);
    }

    #[test]
    fn width_zero_miniblocks_skip_in_one_step() {
        // One block of 2^31 values in one miniblock of width 0: an
        // arithmetic sequence, skipped to its end at once.
        let mut bytes = Vec::new();
        put_varint(&mut bytes, 1 << 31);
        put_varint(&mut bytes, 1);
        put_varint(&mut bytes, (1 << 31) + 1);
        put_zigzag(&mut bytes, 5);
        put_zigzag(&mut bytes, 3);
        bytes.push(0);
        let mut out = [0u64; 2];
        delta_values(&bytes, (1 << 31) - 1, &mut out).unwrap();
        assert_eq!(out, [5 + 3 * ((1u64 << 31) - 1), 5 + 3 * (1u64 << 31)]);
        assert_eq!(
            DeltaPacked::new(&bytes).unwrap().end().unwrap(),
            bytes.len()
        );
    }

    #[test]
    fn damaged_delta_streams_are_errors() {
        let good = encode(&(0..500).map(|i| i * i).collect::<Vec<_>>(), 128, 4, false);
        let mut out = vec![0u64; 500];
        assert!(delta_values(&good, 0, &mut out).is_ok());
        // The last miniblock holds 19 values of 8 bits in 32 bytes; the 13
        // bytes of padding may be missing, the values may not.
        assert!(delta_values(&good[..good.len() - 13], 0, &mut out).is_ok());
        for cut in [0, 1, 3, 5, 10, good.len() / 2, good.len() - 14] {
            assert!(
                delta_values(&good[..cut], 0, &mut out).is_err(),
                "cut at {cut}"
            );
        }
        let headers: [&[u8]; 5] = [
            &[0, 4, 5, 0],       // a block of 0 values
            &[100, 4, 5, 0],     // not a multiple of 128
            &[0x80, 1, 0, 5, 0], // 0 miniblocks
            &[0x80, 1, 3, 5, 0], // 128 values in 3 miniblocks
            &[0x80, 1, 8, 5, 0], // 16 values a miniblock
        ];
        for header in headers {
            assert!(DeltaPacked::new(header).is_err(), "{header:?}");
        }
        // A bit width over 64: the first block's minimum delta (1) takes
        // one byte after the header.
        let mut bad = good.clone();
        let widths_at = DeltaPacked::new(&good).unwrap().at + 1;
        bad[widths_at] = 65;
        assert!(delta_values(&bad, 0, &mut out).is_err());
        assert!(DeltaPacked::new(&bad).unwrap().end().is_err());
    }

    #[test]
    fn byte_array_encodings_round_trip_in_windows() {
        let owned: Vec<Vec<u8>> = (0..700)
            .map(|i| {
                if i % 50 == 7 {
                    Vec::new()
                } else {
                    format!("prefix {} and {}", i / 10, i % 13).into_bytes()
                }
            })
            .collect();
        let values: Vec<&[u8]> = owned.iter().map(|v| &v[..]).collect();
        let dlba = encode_lengths(&values);
        let dba = encode_prefixed(&values);
        for (skip, n) in [(0, 700), (0, 1), (1, 2), (129, 300), (699, 1), (700, 0)] {
            let mut got = Vec::new();
            delta_length_byte_array(&dlba, skip, n, |v| {
                got.push(v.to_vec());
                Ok(())
            })
            .unwrap();
            assert_eq!(got, &owned[skip..skip + n], "DLBA {skip}+{n}");
            let mut got = Vec::new();
            let mut current = Vec::new();
            delta_byte_array(&dba, skip, n, &mut current, |v| {
                got.push(v.to_vec());
                Ok(())
            })
            .unwrap();
            assert_eq!(got, &owned[skip..skip + n], "DBA {skip}+{n}");
        }
        // Past the end, and damage.
        let none = |_: &[u8]| Ok(());
        assert!(delta_length_byte_array(&dlba, 0, 701, none).is_err());
        assert!(delta_byte_array(&dba, 0, 701, &mut Vec::new(), none).is_err());
        assert!(delta_length_byte_array(&dlba[..dlba.len() - 1], 0, 700, none).is_err());
        assert!(delta_byte_array(&dba[..dba.len() - 1], 0, 700, &mut Vec::new(), none).is_err());
        // A negative length, and a prefix longer than the value before.
        let neg = encode(&[3, -1], 128, 4, false);
        assert!(delta_length_byte_array(&[neg.as_slice(), b"abc"].concat(), 0, 2, none).is_err());
        let mut long = encode(&[2], 128, 4, false);
        long.extend_from_slice(&encode(&[1], 128, 4, false));
        long.push(b'x');
        let e = delta_byte_array(&long, 0, 1, &mut Vec::new(), none).unwrap_err();
        assert!(e.message.contains("prefix"), "{}", e.message);
    }

    #[test]
    fn byte_stream_split_gathers_each_value() {
        let values: Vec<f64> = (0..37).map(|i| i as f64 * 1.5 - 7.0).collect();
        let n = values.len();
        let mut split = vec![0u8; n * 8];
        for (i, v) in values.iter().enumerate() {
            for (k, b) in v.to_le_bytes().iter().enumerate() {
                split[k * n + i] = *b;
            }
        }
        assert_eq!(split_count(&split, 8).unwrap(), n);
        for (i, v) in values.iter().enumerate() {
            let mut b = [0u8; 8];
            split_value(&split, n, i, &mut b);
            assert_eq!(f64::from_le_bytes(b), *v);
        }
        assert!(split_count(&split[..split.len() - 1], 8).is_err());
        assert!(split_count(&split, 0).is_err());
    }
}
