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

/// Unpack whole groups of eight `W`-bit values from `buf` at `at` into
/// `out` (a multiple of eight long), reading the bytes where they lie:
/// value `i` of a group loads eight bytes from bit `i * W`, so a group
/// needs `W + 8` bytes of `buf` from its start. Stops at the first group
/// without them (one near the buffer's end, which [`unpack8`] pads) and
/// returns the groups unpacked. `W` is a constant, so the shifts are.
#[inline]
fn unpack_in_place<const W: usize>(buf: &[u8], mut at: usize, out: &mut [u32]) -> usize {
    let mask = if W >= 32 { u64::from(u32::MAX) } else { (1u64 << W) - 1 };
    let mut done = 0;
    for group in out.chunks_exact_mut(8) {
        let Some(b) = at.checked_add(W + 8).and_then(|end| buf.get(at..end)) else {
            break;
        };
        for (i, o) in group.iter_mut().enumerate() {
            let bit = i * W;
            let word = u64::from_le_bytes(b[bit >> 3..(bit >> 3) + 8].try_into().expect("8 bytes"));
            *o = ((word >> (bit & 7)) & mask) as u32;
        }
        at += W;
        done += 1;
    }
    done
}

/// [`unpack_in_place`] for `width`, which is at most 32.
fn unpack_groups(buf: &[u8], at: usize, width: u8, out: &mut [u32]) -> usize {
    macro_rules! by_width {
        ($($w:literal)*) => {
            match width {
                $($w => unpack_in_place::<$w>(buf, at, out),)*
                _ => 0,
            }
        };
    }
    by_width!(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32)
}

/// Decode `out.len()` values of the hybrid encoding from the start of
/// `buf`. Returns the bytes used. Runs may hold more values than asked
/// for (the last bit-packed run is padded to a multiple of eight); the
/// rest are ignored.
#[cfg(test)]
pub(crate) fn decode<T: Small>(buf: &[u8], width: u8, out: &mut [T]) -> Result<usize> {
    decode_from(buf, width, 0, out, |_, _| {})
}

/// Like [`decode`], but for values `skip..skip + out.len()`: the first
/// `skip` values are passed to `skipped(value, count)` instead of being
/// stored, so a caller wanting a few values deep into a page needs room
/// for those alone. Long runs are skipped whole.
pub(crate) fn decode_from<T: Small>(
    buf: &[u8],
    width: u8,
    skip: usize,
    out: &mut [T],
    mut skipped: impl FnMut(u32, usize),
) -> Result<usize> {
    if width > 32 {
        return Err(Error::new(format!("RLE bit width {width} is more than 32")));
    }
    let value_bytes = (width as usize).div_ceil(8);
    let total = skip
        .checked_add(out.len())
        .ok_or_else(|| Error::new("RLE data asked for too many values"))?;
    let mut at = 0;
    // Values decoded so far, counting the skipped ones.
    let mut pos = 0;
    // Stores a run of `n` values `v` from `pos`.
    let fill =
        |pos: usize, n: usize, v: u32, out: &mut [T], skipped: &mut dyn FnMut(u32, usize)| {
            let end = pos + n;
            if pos < skip {
                skipped(v, end.min(skip) - pos);
            }
            if end > skip {
                out[pos.max(skip) - skip..end - skip].fill(T::from_u32(v));
            }
        };
    while pos < total {
        let header = varint(buf, &mut at)?;
        if header & 1 == 0 {
            let run = usize::try_from(header >> 1).unwrap_or(usize::MAX);
            let bytes = buf
                .get(at..)
                .and_then(|b| b.get(..value_bytes))
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
            let n = run.min(total - pos);
            fill(pos, n, v, out, &mut skipped);
            pos += n;
        } else {
            let groups = usize::try_from(header >> 1).unwrap_or(usize::MAX);
            if groups == 0 {
                return Err(Error::new("empty bit-packed run"));
            }
            let n = groups.saturating_mul(8).min(total - pos);
            if width == 0 {
                // Every value is 0 and takes no bytes.
                fill(pos, n, 0, out, &mut skipped);
                pos += n;
                continue;
            }
            // Some writers end the last run's bytes early; the values
            // asked for must still be there.
            let w = width as usize;
            let need = (n as u64 * w as u64).div_ceil(8);
            let have = (buf.len() - at).min(groups.saturating_mul(w));
            if (have as u64) < need {
                return Err(Error::new("bit-packed run ends early"));
            }
            let run = &buf[at..at + have];
            let group = |g: usize| {
                let start = (g * w).min(run.len());
                &run[start..(start + w).min(run.len())]
            };
            let groups_used = n.div_ceil(8);
            // Groups that start before `skip`, a value at a time.
            let mut g = 0;
            while g < groups_used && pos + 8 * g < skip {
                let first = pos + 8 * g;
                let count = 8.min(pos + n - first);
                let mut tmp = [T::default(); 8];
                unpack8(group(g), width, &mut tmp[..count]);
                for (i, &v) in tmp[..count].iter().enumerate() {
                    if first + i < skip {
                        skipped(v.to_u32(), 1);
                    } else {
                        out[first + i - skip] = v;
                    }
                }
                g += 1;
            }
            // The rest straight into `out`, eight at a time.
            if g < groups_used {
                let dest = &mut out[pos + 8 * g - skip..pos + n - skip];
                for (k, chunk) in dest.chunks_mut(8).enumerate() {
                    unpack8(group(g + k), width, chunk);
                }
            }
            at += have;
            pos += n;
        }
    }
    Ok(at)
}

/// Decode the older BIT_PACKED encoding of a page's `rows` values, packed
/// from the most significant bit with no header: values `skip..skip +
/// out.len()` go into `out`, and the count of 1s before `skip` is
/// returned with the bytes all `rows` take.
pub(crate) fn decode_bit_packed(
    buf: &[u8],
    width: u8,
    rows: usize,
    skip: usize,
    out: &mut [u8],
) -> Result<(usize, usize)> {
    let short = || Error::new("bit-packed levels end early");
    let bytes =
        usize::try_from((rows as u64 * u64::from(width)).div_ceil(8)).map_err(|_| short())?;
    let buf = buf.get(..bytes).ok_or_else(short)?;
    if skip.checked_add(out.len()).is_none_or(|e| e > rows) {
        return Err(Error::new("bit-packed levels asked for past the page"));
    }
    let mut bit = 0usize;
    let mut next = || {
        let mut v = 0u8;
        for _ in 0..width {
            let b = (buf[bit >> 3] >> (7 - (bit & 7))) & 1;
            v = (v << 1) | b;
            bit += 1;
        }
        v
    };
    let ones = (0..skip).filter(|_| next() == 1).count();
    for o in out.iter_mut() {
        *o = next();
    }
    Ok((bytes, ones))
}

/// The hybrid encoding read a batch at a time, keeping its place between
/// calls: for decoding a page's dictionary indices in small batches that
/// stay in cache, where [`decode_from`] would start from the page's first
/// value each time. Used by the Arrow outputs ([`crate::columnar`]).
pub(crate) struct Hybrid<'a> {
    buf: &'a [u8],
    at: usize,
    width: u8,
    /// Values left in the current RLE run, and its value.
    rle_left: usize,
    rle_value: u32,
    /// The current bit-packed run: the next group's first byte, the
    /// values left in groups not yet unpacked, and the end of its bytes.
    packed_at: usize,
    packed_left: usize,
    packed_end: usize,
    /// The group unpacked last: its values, how many are there, and how
    /// many have been taken.
    group: [u32; 8],
    group_len: usize,
    group_pos: usize,
}

impl<'a> Hybrid<'a> {
    pub(crate) fn new(buf: &'a [u8], width: u8) -> Result<Self> {
        if width > 32 {
            return Err(Error::new(format!("RLE bit width {width} is more than 32")));
        }
        Ok(Hybrid {
            buf,
            at: 0,
            width,
            rle_left: 0,
            rle_value: 0,
            packed_at: 0,
            packed_left: 0,
            packed_end: 0,
            group: [0; 8],
            group_len: 0,
            group_pos: 0,
        })
    }

    /// Start the next run.
    fn header(&mut self) -> Result<()> {
        let header = varint(self.buf, &mut self.at)?;
        let w = self.width as usize;
        if header & 1 == 0 {
            let run = usize::try_from(header >> 1).unwrap_or(usize::MAX);
            if run == 0 {
                return Err(Error::new("empty RLE run"));
            }
            let value_bytes = w.div_ceil(8);
            let bytes = self
                .buf
                .get(self.at..)
                .and_then(|b| b.get(..value_bytes))
                .ok_or_else(|| Error::new("RLE data ends early"))?;
            let mut v = 0u32;
            for (k, b) in bytes.iter().enumerate() {
                v |= u32::from(*b) << (8 * k);
            }
            if w < 32 && v >> w != 0 {
                return Err(Error::new("RLE value wider than its bit width"));
            }
            self.at += value_bytes;
            self.rle_left = run;
            self.rle_value = v;
        } else {
            let groups = usize::try_from(header >> 1).unwrap_or(usize::MAX);
            if groups == 0 {
                return Err(Error::new("empty bit-packed run"));
            }
            // Some writers end the last run's bytes early: the values
            // asked for must still be there, which `load` checks.
            let end = self.at.saturating_add(groups.saturating_mul(w)).min(self.buf.len());
            self.packed_at = self.at;
            self.packed_end = end;
            self.packed_left = groups.saturating_mul(8);
            self.at = end;
        }
        Ok(())
    }

    /// Unpack the current run's next group into `group`.
    fn load(&mut self) -> Result<()> {
        let w = self.width as usize;
        let start = self.packed_at.min(self.packed_end);
        let end = (start + w).min(self.packed_end);
        let have = ((end - start) * 8).checked_div(w).map_or(8, |n| n.min(8));
        if have == 0 {
            return Err(Error::new("bit-packed run ends early"));
        }
        unpack8(&self.buf[start..end], self.width, &mut self.group);
        self.group_len = have;
        self.group_pos = 0;
        self.packed_at = start + w;
        self.packed_left -= 8;
        Ok(())
    }

    /// The current RLE run, if the next values are one: its value and
    /// how many of them (at most `most`), which are taken.
    #[inline]
    pub(crate) fn run(&mut self, most: usize) -> Result<Option<(u32, usize)>> {
        if self.rle_left == 0 && self.group_pos >= self.group_len && self.packed_left == 0 {
            self.header()?;
        }
        if self.rle_left > 0 {
            let n = self.rle_left.min(most);
            self.rle_left -= n;
            return Ok(Some((self.rle_value, n)));
        }
        Ok(None)
    }

    /// Values left in the current bit-packed run (0 inside an RLE run).
    #[inline]
    pub(crate) fn literal_left(&self) -> usize {
        if self.rle_left > 0 {
            0
        } else {
            self.group_len - self.group_pos.min(self.group_len) + self.packed_left
        }
    }

    /// Fill `out` with the next values.
    pub(crate) fn next(&mut self, out: &mut [u32]) -> Result<()> {
        let w = self.width as usize;
        let mut i = 0;
        while i < out.len() {
            if self.rle_left > 0 {
                let n = self.rle_left.min(out.len() - i);
                out[i..i + n].fill(self.rle_value);
                self.rle_left -= n;
                i += n;
                continue;
            }
            if self.group_pos < self.group_len {
                let n = (self.group_len - self.group_pos).min(out.len() - i);
                out[i..i + n].copy_from_slice(&self.group[self.group_pos..self.group_pos + n]);
                self.group_pos += n;
                i += n;
                continue;
            }
            if self.packed_left > 0 {
                // Whole groups straight into `out`, while their bytes are
                // all there.
                let mut groups = (out.len() - i).min(self.packed_left) / 8;
                // The groups whose bytes are all in the run, read in place
                // while the buffer has room for their loads.
                let whole = (self.packed_end - self.packed_at.min(self.packed_end)).checked_div(w).map_or(groups, |n| n.min(groups));
                let done = unpack_groups(self.buf, self.packed_at, self.width, &mut out[i..i + whole * 8]);
                self.packed_at += done * w;
                self.packed_left -= done * 8;
                i += done * 8;
                groups -= done;
                while groups > 0 && self.packed_at + w <= self.packed_end {
                    unpack8(&self.buf[self.packed_at..self.packed_at + w], self.width, &mut out[i..i + 8]);
                    self.packed_at += w;
                    self.packed_left -= 8;
                    i += 8;
                    groups -= 1;
                }
                if i < out.len() && self.packed_left > 0 {
                    self.load()?;
                }
                continue;
            }
            self.header()?;
        }
        Ok(())
    }

    /// Pass over the next `n` values.
    pub(crate) fn skip(&mut self, mut n: usize) -> Result<()> {
        let w = self.width as usize;
        while n > 0 {
            if self.rle_left > 0 {
                let k = self.rle_left.min(n);
                self.rle_left -= k;
                n -= k;
                continue;
            }
            if self.group_pos < self.group_len {
                let k = (self.group_len - self.group_pos).min(n);
                self.group_pos += k;
                n -= k;
                continue;
            }
            if self.packed_left > 0 {
                let groups = n.min(self.packed_left) / 8;
                if groups > 0 {
                    self.packed_at = self.packed_at.saturating_add(groups * w);
                    self.packed_left -= groups * 8;
                    n -= groups * 8;
                } else {
                    self.load()?;
                }
                continue;
            }
            self.header()?;
        }
        Ok(())
    }
}

/// Set `len` bits of `dst` from bit `to`, copied from `src` from bit
/// `from`; `dst`'s bits there are zero.
fn copy_bits(dst: &mut [u8], to: usize, src: &[u8], from: usize, len: usize) {
    let mut k = 0;
    // A source byte at a time, shifted into place.
    while k < len {
        let s = from + k;
        let byte = (src[s / 8] >> (s % 8)) | src.get(s / 8 + 1).map_or(0, |b| b.checked_shl(8 - (s % 8) as u32).unwrap_or(0));
        let n = (len - k).min(8);
        let byte = if n < 8 { byte & ((1u8 << n) - 1) } else { byte };
        let d = to + k;
        dst[d / 8] |= byte << (d % 8);
        if d % 8 != 0 && d % 8 + n > 8 {
            dst[d / 8 + 1] |= byte >> (8 - d % 8);
        }
        k += n;
    }
}

/// OR `len` bits of `src` from bit `from` into `dst` from bit `to`, and
/// count the ones among them. When both start on a byte, as a page's
/// first bit-packed run does in a chunk read from its first row, whole
/// bytes are OR-ed and counted eight at a time.
fn or_bits(dst: &mut [u8], to: usize, src: &[u8], from: usize, len: usize) -> usize {
    if to % 8 != 0 || from % 8 != 0 {
        copy_bits(dst, to, src, from, len);
        return count_bits(src, from, len);
    }
    let whole = len / 8;
    let s = &src[from / 8..from / 8 + whole];
    for (d, b) in dst[to / 8..to / 8 + whole].iter_mut().zip(s) {
        *d |= *b;
    }
    let mut ones = 0;
    let mut words = s.chunks_exact(8);
    for w in &mut words {
        ones += u64::from_le_bytes(w.try_into().expect("8 bytes")).count_ones() as usize;
    }
    ones += words.remainder().iter().map(|b| b.count_ones() as usize).sum::<usize>();
    let rest = len % 8;
    if rest > 0 {
        // The bits past `len` are the run's padding, or another page's.
        let byte = src[from / 8 + whole] & ((1u8 << rest) - 1);
        dst[to / 8 + whole] |= byte;
        ones += byte.count_ones() as usize;
    }
    ones
}

/// The ones among `len` bits of `src` from bit `from`.
fn count_bits(src: &[u8], from: usize, len: usize) -> usize {
    let mut ones = 0;
    let mut k = from;
    while k < from + len {
        let m = (from + len - k).min(8 - k % 8);
        ones += ((src[k / 8] >> (k % 8)) & ((1u16 << m) - 1) as u8).count_ones() as usize;
        k += m;
    }
    ones
}

/// Set bits `to..to + len` of `dst`.
fn set_bits(dst: &mut [u8], to: usize, len: usize) {
    let end = to + len;
    let mut i = to;
    while i < end && i % 8 != 0 {
        dst[i / 8] |= 1 << (i % 8);
        i += 1;
    }
    let whole = (end - i) / 8;
    dst[i / 8..i / 8 + whole].fill(0xff);
    i += whole * 8;
    while i < end {
        dst[i / 8] |= 1 << (i % 8);
        i += 1;
    }
}

/// Decode a page's RLE definition levels (width 1) for rows `take` into
/// validity bits: row `take.start + k` is bit `to + k` of `bits`, set
/// where the row has a value (`bits` is zero there). Runs of values set
/// a range, runs of nulls cost nothing, and bit-packed groups are copied
/// as they are, being already one bit per row, the first lowest. Returns
/// the values before `take` and within it.
pub(crate) fn levels_bits(buf: &[u8], take: std::ops::Range<usize>, bits: &mut [u8], to: usize) -> Result<(usize, usize)> {
    let (mut before, mut ones) = (0usize, 0usize);
    let mut at = 0;
    let mut pos = 0usize;
    while pos < take.end {
        let header = varint(buf, &mut at)?;
        if header & 1 == 0 {
            let run = usize::try_from(header >> 1).unwrap_or(usize::MAX);
            if run == 0 {
                return Err(Error::new("empty RLE run"));
            }
            let v = *buf.get(at).ok_or_else(|| Error::new("RLE data ends early"))?;
            at += 1;
            if v > 1 {
                return Err(Error::new("RLE value wider than its bit width"));
            }
            let end = pos.saturating_add(run).min(take.end);
            if v == 1 {
                before += end.min(take.start).saturating_sub(pos);
                let (s, e) = (pos.max(take.start), end);
                if e > s {
                    set_bits(bits, to + s - take.start, e - s);
                    ones += e - s;
                }
            }
            pos = end;
        } else {
            let groups = usize::try_from(header >> 1).unwrap_or(usize::MAX);
            if groups == 0 {
                return Err(Error::new("empty bit-packed run"));
            }
            let n = groups.saturating_mul(8).min(take.end - pos);
            let have = (buf.len() - at).min(groups);
            if have * 8 < n {
                return Err(Error::new("bit-packed run ends early"));
            }
            let run = &buf[at..at + have];
            // Ones before the window: whole bytes by count, then the part.
            let skip = take.start.saturating_sub(pos).min(n);
            before += run[..skip / 8].iter().map(|b| b.count_ones() as usize).sum::<usize>();
            if skip % 8 != 0 {
                before += (run[skip / 8] & ((1u8 << (skip % 8)) - 1)).count_ones() as usize;
            }
            if n > skip {
                let d = to + pos + skip - take.start;
                ones += or_bits(bits, d, run, skip, n - skip);
            }
            at += have;
            pos += n;
        }
    }
    Ok((before, ones))
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
    fn a_window_decodes_as_the_whole_does() {
        let values: Vec<u32> = (0..2000u32)
            .map(|i| if (i / 50) % 3 == 0 { 1 } else { (i * 7919) % 2 })
            .collect();
        let mut buf = Vec::new();
        encode(&values, 1, &mut buf);
        for (skip, len) in [
            (0, 2000),
            (1, 5),
            (7, 9),
            (8, 8),
            (13, 600),
            (1999, 1),
            (2000, 0),
        ] {
            let mut got = vec![0u32; len];
            let mut ones = 0;
            decode_from(&buf, 1, skip, &mut got, |v, n| ones += v as usize * n).unwrap();
            assert_eq!(got, &values[skip..skip + len], "{skip} {len}");
            assert_eq!(ones, values[..skip].iter().sum::<u32>() as usize);
        }
        // Legacy BIT_PACKED, from the middle.
        let legacy = [0b1010_1010, 0b1111_0000];
        let mut got = [0u8; 4];
        assert_eq!(
            decode_bit_packed(&legacy, 1, 16, 6, &mut got).unwrap(),
            (2, 3)
        );
        assert_eq!(got, [1, 0, 1, 1]);
        // A run of a billion values costs nothing to skip.
        let mut buf = Vec::new();
        put_varint(&mut buf, 2_000_000_000 << 1);
        buf.push(1);
        let mut got = [0u8; 1];
        let mut ones = 0;
        decode_from(&buf, 1, 1_999_999_999, &mut got, |v, n| {
            ones += v as usize * n
        })
        .unwrap();
        assert_eq!((got[0], ones), (1, 1_999_999_999));
    }

    #[test]
    fn the_stateful_reader_gives_what_decode_gives() {
        let mut seed = 99u64;
        let mut next = || {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (seed >> 33) as usize
        };
        for width in [0u8, 1, 3, 8, 13, 32] {
            let max = if width == 32 { u32::MAX } else { (1u32 << width).wrapping_sub(1) };
            let values: Vec<u32> = (0..3000)
                .map(|i| if (i / 40) % 3 == 0 { max } else { (i as u32).wrapping_mul(2654435761) & max })
                .collect();
            let mut buf = Vec::new();
            encode(&values, width, &mut buf);
            for _ in 0..50 {
                let mut h = Hybrid::new(&buf, width).unwrap();
                let mut at = 0;
                while at < values.len() {
                    let n = (next() % 70).min(values.len() - at);
                    if next() % 3 == 0 {
                        h.skip(n).unwrap();
                    } else if next() % 2 == 0 {
                        match h.run(n).unwrap() {
                            Some((v, k)) => {
                                assert!(values[at..at + k].iter().all(|&x| x == v));
                                at += k;
                                continue;
                            }
                            None => {
                                let k = n.min(h.literal_left());
                                let mut got = vec![0u32; k];
                                h.next(&mut got).unwrap();
                                assert_eq!(got, &values[at..at + k]);
                                at += k;
                                continue;
                            }
                        }
                    } else {
                        let mut got = vec![0u32; n];
                        h.next(&mut got).unwrap();
                        assert_eq!(got, &values[at..at + n], "width {width} at {at}");
                    }
                    at += n;
                }
            }
        }
        // Damage is an error, not a panic.
        let mut out = [0u32; 10];
        assert!(Hybrid::new(&[0x03, 0x01], 8).unwrap().next(&mut out).is_err());
        assert!(Hybrid::new(&[], 3).unwrap().next(&mut out).is_err());
        assert!(Hybrid::new(&[0x00], 3).unwrap().skip(4).is_err());
    }

    #[test]
    fn groups_unpack_in_place_as_padded_ones_do() {
        let mut seed = 0x9e37_79b9_7f4a_7c15u64;
        let mut next = move || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        for width in 0..=32u8 {
            let w = width as usize;
            for groups in [1usize, 2, 5, 130] {
                // Nothing, a few bytes and plenty after the groups' own.
                for extra in [0usize, 3, 7, 8, 40] {
                    let buf: Vec<u8> = (0..groups * w + extra).map(|_| next() as u8).collect();
                    let mut fast = vec![u32::MAX; groups * 8];
                    let done = unpack_groups(&buf, 0, width, &mut fast);
                    // Every group whose loads fit, and no other.
                    let fit = (0..groups).take_while(|g| g * w + w + 8 <= buf.len()).count();
                    assert_eq!(done, fit, "width {width}, {groups} groups, {extra} more bytes");
                    for g in 0..done {
                        let mut slow = [0u32; 8];
                        unpack8(&buf[g * w..(g + 1) * w], width, &mut slow);
                        assert_eq!(fast[g * 8..g * 8 + 8], slow, "width {width} group {g}");
                    }
                    assert!(fast[done * 8..].iter().all(|&v| v == u32::MAX), "width {width}: wrote past what it unpacked");
                }
            }
        }
        // The stateful reader gives the same values whether its groups
        // are read in place or padded: a buffer cut right after the run.
        for width in [1u8, 3, 7, 12, 20, 32] {
            let values: Vec<u32> = (0..1000).map(|_| (next() as u32) & (((1u64 << width) - 1) as u32)).collect();
            let mut buf = Vec::new();
            encode(&values, width, &mut buf);
            for batch in [8usize, 64, 1000, 37] {
                let mut h = Hybrid::new(&buf, width).unwrap();
                let mut out = vec![0u32; values.len()];
                for part in out.chunks_mut(batch) {
                    h.next(part).unwrap();
                }
                assert_eq!(out, values, "width {width} batch {batch}");
            }
        }
    }

    #[test]
    fn whole_bytes_or_as_single_bits_do() {
        let mut seed = 0x2545_f491_4f6c_dd1du64;
        let mut next = move || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        for case in 0..4000 {
            let src: Vec<u8> = (0..40).map(|_| next() as u8).collect();
            // Bits already set, inside the range and around it, survive.
            let before: Vec<u8> = (0..48).map(|_| (next() & next()) as u8).collect();
            let from = if case % 2 == 0 { 8 * (next() % 4) as usize } else { (next() % 32) as usize };
            let to = if case % 2 == 0 { 8 * (next() % 4) as usize } else { (next() % 32) as usize };
            let len = (next() % 280) as usize;
            let (mut fast, mut slow) = (before.clone(), before.clone());
            let ones = or_bits(&mut fast, to, &src, from, len);
            copy_bits(&mut slow, to, &src, from, len);
            assert_eq!(fast, slow, "case {case}: from {from} to {to} len {len}");
            let bit = |b: &[u8], k: usize| (b[k / 8] >> (k % 8)) & 1;
            assert_eq!(ones, (0..len).filter(|&k| bit(&src, from + k) == 1).count(), "case {case}");
            for k in 0..before.len() * 8 {
                let inside = k >= to && k < to + len;
                let want = if inside { bit(&before, k) | bit(&src, from + k - to) } else { bit(&before, k) };
                assert_eq!(bit(&fast, k), want, "case {case} bit {k}");
            }
        }
    }

    #[test]
    fn levels_decode_straight_into_bits() {
        let mut seed = 7u64;
        let mut next = || {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (seed >> 33) as usize
        };
        for case in 0..60 {
            let n = 1 + next() % 3000;
            // Runs of nulls and values mixed with scattered ones.
            let levels: Vec<u8> = (0..n)
                .map(|i| match case % 3 {
                    0 => u8::from((i / 37) % 2 == 0),
                    1 => u8::from(next() % 5 != 0),
                    _ => u8::from((i / 300) % 3 != 1 && i % 7 != 3),
                })
                .collect();
            let mut buf = Vec::new();
            encode(&levels, 1, &mut buf);
            for _ in 0..10 {
                let s = next() % n;
                let e = s + next() % (n - s + 1);
                let to = next() % 13;
                let mut bits = vec![0u8; (to + e - s).div_ceil(8) + 1];
                let (before, ones) = levels_bits(&buf, s..e, &mut bits, to).unwrap();
                assert_eq!(before, levels[..s].iter().filter(|&&l| l == 1).count());
                assert_eq!(ones, levels[s..e].iter().filter(|&&l| l == 1).count());
                for k in 0..e - s {
                    assert_eq!((bits[(to + k) / 8] >> ((to + k) % 8)) & 1, levels[s + k], "case {case} row {k}");
                }
                assert!((to + e - s..bits.len() * 8).all(|b| (bits[b / 8] >> (b % 8)) & 1 == 0));
            }
        }
        let mut bits = [0u8; 4];
        assert!(levels_bits(&[0x03], 0..8, &mut bits, 0).is_err());
        assert!(levels_bits(&[0x04, 2], 0..2, &mut bits, 0).is_err());
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
        decode_bit_packed(&legacy, 3, 8, 0, &mut got).unwrap();
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
        assert!(decode_bit_packed(&[0xff], 1, 9, 0, &mut out).is_err());
    }
}
