//! Arrow-layout outputs of a read (plan 0019, "How the frame is built"):
//! what a binding hands to polars through the Arrow C data interface.
//!
//! - **Numbers** go into a slice of their type, and nulls into a validity
//!   bitmap (a bit per row, set where the row has a value, least
//!   significant bit first). `.a` to `.z` (tagged NaNs in DOUBLE columns)
//!   are nulls too, listed apart as (row, code): they are rare, so a list
//!   costs less than a code per row.
//! - **Text and bytes** become Arrow string views: 16 bytes a row, values
//!   of up to 12 bytes inline, longer ones pointing into data buffers the
//!   read hands back ([`ArrowReport::buffers`]). A dictionary's values
//!   are made into views once per column chunk, and each row copies its
//!   value's view.
//! - **Categoricals** with levels in the dta profile become keys (level
//!   codes from 0) for an Arrow dictionary array of the levels.
//!
//! Each column chunk is decoded on a worker thread straight into its rows
//! of these outputs; nothing passes through the calling thread, so an
//! Arrow read needs no delivery in row order. A chunk builds its rows'
//! validity bits in its own buffer and merges them into the column's
//! bitmap when done: whole bytes are stored, and the bytes it shares with
//! the chunks before and after it (row groups need not start on a
//! multiple of eight) are combined atomically.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, AtomicU8, Ordering};

use crate::decode::{self, cannot_hold, Chunk, Consumer, DataPage, Int96, Physical, ReadAt, Scratch};
use crate::encoding;
use crate::format::{Encoding, PhysicalType};
use crate::read::Element;
use crate::rle::Hybrid;
use crate::schema::ColumnType;
use dta::{Error, ErrorKind, Result};

/// Where one column of an Arrow read goes.
pub struct ArrowOutput<'a> {
    /// A bit per row, all zero on entry (`rows.div_ceil(8)` bytes): set
    /// where the row has a value. `None` for a column that the file says
    /// has no nulls and that cannot hold `.a` to `.z` (it is not DOUBLE);
    /// a null in it is then an error.
    pub validity: Option<&'a mut [u8]>,
    pub data: ArrowData<'a>,
}

/// The values of an Arrow read's column: one element per row.
pub enum ArrowData<'a> {
    Int8(&'a mut [i8]),
    Int16(&'a mut [i16]),
    Int32(&'a mut [i32]),
    Int64(&'a mut [i64]),
    /// Also booleans, as 0 and 1.
    UInt8(&'a mut [u8]),
    UInt16(&'a mut [u16]),
    UInt32(&'a mut [u32]),
    UInt64(&'a mut [u64]),
    Float32(&'a mut [f32]),
    Float64(&'a mut [f64]),
    /// Text or bytes as Arrow string views (`u128`s laid out as the
    /// format says, little-endian).
    Views(&'a mut [u128]),
    /// A categorical with levels in the dta profile: each row's level,
    /// counted from 0.
    Keys(&'a mut [u32]),
}

impl ArrowData<'_> {
    pub(crate) fn len(&self) -> usize {
        match self {
            ArrowData::Int8(v) => v.len(),
            ArrowData::Int16(v) => v.len(),
            ArrowData::Int32(v) => v.len(),
            ArrowData::Int64(v) => v.len(),
            ArrowData::UInt8(v) => v.len(),
            ArrowData::UInt16(v) => v.len(),
            ArrowData::UInt32(v) => v.len(),
            ArrowData::UInt64(v) => v.len(),
            ArrowData::Float32(v) => v.len(),
            ArrowData::Float64(v) => v.len(),
            ArrowData::Views(v) => v.len(),
            ArrowData::Keys(v) => v.len(),
        }
    }

    pub(crate) fn width(&self) -> usize {
        match self {
            ArrowData::Int8(_) | ArrowData::UInt8(_) => 1,
            ArrowData::Int16(_) | ArrowData::UInt16(_) => 2,
            ArrowData::Int32(_) | ArrowData::UInt32(_) | ArrowData::Float32(_) | ArrowData::Keys(_) => 4,
            ArrowData::Int64(_) | ArrowData::UInt64(_) | ArrowData::Float64(_) => 8,
            ArrowData::Views(_) => 16,
        }
    }

    /// The name of the element type, for errors.
    pub(crate) fn name(&self) -> &'static str {
        match self {
            ArrowData::Int8(_) => i8::NAME,
            ArrowData::Int16(_) => i16::NAME,
            ArrowData::Int32(_) => i32::NAME,
            ArrowData::Int64(_) => i64::NAME,
            ArrowData::UInt8(_) => u8::NAME,
            ArrowData::UInt16(_) => u16::NAME,
            ArrowData::UInt32(_) => u32::NAME,
            ArrowData::UInt64(_) => u64::NAME,
            ArrowData::Float32(_) => f32::NAME,
            ArrowData::Float64(_) => f64::NAME,
            ArrowData::Views(_) => "text",
            ArrowData::Keys(_) => "level codes",
        }
    }

    /// Whether a column of `kind` can be read into this.
    pub(crate) fn accepts(&self, kind: &ColumnType) -> bool {
        match self {
            ArrowData::Int8(_) => i8::accepts(kind),
            ArrowData::Int16(_) => i16::accepts(kind),
            ArrowData::Int32(_) => i32::accepts(kind),
            ArrowData::Int64(_) => i64::accepts(kind),
            ArrowData::UInt8(_) => u8::accepts(kind),
            ArrowData::UInt16(_) => u16::accepts(kind),
            ArrowData::UInt32(_) => u32::accepts(kind),
            ArrowData::UInt64(_) => u64::accepts(kind),
            // Not DECIMAL: Float64 reads it only through Output::Float64.
            ArrowData::Float32(_) => f32::accepts(kind),
            ArrowData::Float64(_) => f64::accepts(kind) && !matches!(kind, ColumnType::Decimal { .. }),
            ArrowData::Views(_) => matches!(kind, ColumnType::Text | ColumnType::Binary),
            ArrowData::Keys(_) => *kind == ColumnType::Text,
        }
    }
}

/// What an Arrow read leaves besides its outputs, per column.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ArrowReport {
    /// Rows without a value: `.` and `.a` to `.z`.
    pub nulls: u64,
    /// The rows (of the read) holding `.a` to `.z`, with their codes (2
    /// to 27), in row order.
    pub letters: Vec<(u64, u8)>,
    /// A string-view column's data buffers, in the order their views
    /// number them.
    pub buffers: Vec<Vec<u8>>,
}

/// One column chunk's part of an Arrow output.
pub(crate) struct ArrowDest<'a> {
    pub(crate) data: ArrowData<'a>,
    pub(crate) validity: Option<&'a [AtomicU8]>,
    /// The read's row of `data[0]`.
    pub(crate) first: usize,
    /// Numbers the column's string-view data buffers.
    pub(crate) buffers: &'a AtomicU32,
    /// A categorical's levels, with their codes from 0.
    pub(crate) levels: Option<&'a HashMap<&'a [u8], i32>>,
}

/// What a chunk decoded into an Arrow output gives back.
pub(crate) struct ArrowDone {
    pub(crate) nulls: u64,
    pub(crate) letters: Vec<(u64, u8)>,
    pub(crate) buffers: Vec<(u32, Vec<u8>)>,
}

/// The bytes of `v` as atomics, shared by the tasks that fill them.
fn atomic(v: &mut [u8]) -> &[AtomicU8] {
    // SAFETY: AtomicU8 has the size, alignment and bit validity of u8,
    // and the exclusive borrow is given up for the shared one.
    unsafe { &*(v as *mut [u8] as *const [AtomicU8]) }
}

fn cut<'s, T>(mut s: &'s mut [T], sizes: &[usize]) -> Vec<&'s mut [T]> {
    let mut out = Vec::with_capacity(sizes.len());
    for &n in sizes {
        let (a, b) = std::mem::take(&mut s).split_at_mut(n);
        out.push(a);
        s = b;
    }
    out
}

/// Split an output into one destination per row group of `sizes` rows.
pub(crate) fn split<'a>(
    out: &'a mut ArrowOutput<'_>,
    sizes: &[usize],
    buffers: &'a AtomicU32,
    levels: Option<&'a HashMap<&'a [u8], i32>>,
) -> Vec<ArrowDest<'a>> {
    let validity: Option<&'a [AtomicU8]> = out.validity.as_deref_mut().map(atomic);
    macro_rules! pieces {
        ($v:expr, $variant:ident) => {
            cut(&mut **$v, sizes).into_iter().map(ArrowData::$variant).collect::<Vec<_>>()
        };
    }
    let data: Vec<ArrowData<'a>> = match &mut out.data {
        ArrowData::Int8(v) => pieces!(v, Int8),
        ArrowData::Int16(v) => pieces!(v, Int16),
        ArrowData::Int32(v) => pieces!(v, Int32),
        ArrowData::Int64(v) => pieces!(v, Int64),
        ArrowData::UInt8(v) => pieces!(v, UInt8),
        ArrowData::UInt16(v) => pieces!(v, UInt16),
        ArrowData::UInt32(v) => pieces!(v, UInt32),
        ArrowData::UInt64(v) => pieces!(v, UInt64),
        ArrowData::Float32(v) => pieces!(v, Float32),
        ArrowData::Float64(v) => pieces!(v, Float64),
        ArrowData::Views(v) => pieces!(v, Views),
        ArrowData::Keys(v) => pieces!(v, Keys),
    };
    let mut first = 0;
    data.into_iter()
        .map(|data| {
            let d = ArrowDest { first, validity, buffers, levels, data };
            first += d.data.len();
            d
        })
        .collect()
}

// ---- validity bits ----

/// Eight levels (0 or 1 each) as eight bits, the first lowest.
#[inline]
fn pack8(levels: &[u8]) -> u8 {
    let w = u64::from_le_bytes(levels[..8].try_into().expect("8 bytes")) & 0x0101_0101_0101_0101;
    (w.wrapping_mul(0x0102_0408_1020_4080) >> 56) as u8
}

/// Set bits `at..at + n` of `bits`.
fn set_range(bits: &mut [u8], at: usize, n: usize) {
    let end = at + n;
    let mut i = at;
    while i < end && i % 8 != 0 {
        bits[i / 8] |= 1 << (i % 8);
        i += 1;
    }
    let whole = (end - i) / 8;
    bits[i / 8..i / 8 + whole].fill(0xff);
    i += whole * 8;
    while i < end {
        bits[i / 8] |= 1 << (i % 8);
        i += 1;
    }
}

/// Set bit `at + k` of `bits` where `levels[k]` is 1.
fn pack_into(bits: &mut [u8], at: usize, levels: &[u8]) {
    let mut k = 0;
    while k < levels.len() && (at + k) % 8 != 0 {
        bits[(at + k) / 8] |= (levels[k] & 1) << ((at + k) % 8);
        k += 1;
    }
    while k + 8 <= levels.len() {
        bits[(at + k) / 8] = pack8(&levels[k..k + 8]);
        k += 8;
    }
    while k < levels.len() {
        bits[(at + k) / 8] |= (levels[k] & 1) << ((at + k) % 8);
        k += 1;
    }
}

/// Combine the first `n` bits of `src` into `dst` from bit `at`: bytes
/// wholly inside the range are this chunk's alone and are stored; the
/// two at its ends are shared with the neighbouring chunks and are OR-ed.
fn merge(dst: &[AtomicU8], at: usize, src: &[u8], n: usize) {
    if n == 0 {
        return;
    }
    let first = at / 8;
    let last = (at + n - 1) / 8;
    let shift = at % 8;
    for (d, slot) in dst.iter().enumerate().take(last + 1).skip(first) {
        let byte = if shift == 0 {
            src[d - first]
        } else if d == first {
            src[0] << shift
        } else {
            // Bits 8 * d - at onwards of `src`.
            let lo = 8 * d - at;
            let a = src[lo / 8] >> (lo % 8);
            let b = src.get(lo / 8 + 1).map_or(0, |b| b << (8 - lo % 8));
            a | b
        };
        if 8 * d >= at && 8 * d + 8 <= at + n {
            slot.store(byte, Ordering::Relaxed);
        } else if byte != 0 {
            slot.fetch_or(byte, Ordering::Relaxed);
        }
    }
}

/// Set a page's rows' validity bits, decoding its levels when they come
/// undecoded; returns the page's values before its wanted rows and up to
/// their end.
#[inline]
fn page_levels(bits: &mut [u8], page: &DataPage) -> Result<(usize, usize)> {
    match (page.raw_levels, page.levels) {
        (Some(raw), _) => {
            let (before, ones) = crate::rle::levels_bits(raw, page.take.clone(), bits, page.out_at)?;
            Ok((before, before + ones))
        }
        (None, Some(l)) => {
            pack_into(bits, page.out_at, l);
            Ok((page.before, page.present))
        }
        (None, None) => {
            set_range(bits, page.out_at, page.take.len());
            Ok((page.before, page.present))
        }
    }
}

/// Bits `start..start + len` (at most 64) of `bits`, the first lowest.
#[inline]
fn bits_at(bits: &[u8], start: usize, len: usize) -> u64 {
    let mut b = [0u8; 16];
    let from = start / 8;
    let n = (bits.len() - from).min(9);
    b[..n].copy_from_slice(&bits[from..from + n]);
    let w = u128::from_le_bytes(b) >> (start % 8);
    let w = w as u64;
    if len >= 64 {
        w
    } else {
        w & ((1u64 << len) - 1)
    }
}

/// Whether row `r` has a value.
#[inline]
fn valid_at(bits: &[u8], r: usize) -> bool {
    (bits[r / 8] >> (r % 8)) & 1 == 1
}

// ---- filling a page's rows ----

const BATCH: usize = 1024;

/// Fill a page's rows `out` with its values, taken in order by `next`,
/// which writes the next `dst.len()` present values into `dst` and
/// returns false if one needs the slow path (a letter, or a value the
/// output type cannot hold). Which rows have a value is in `bits` from
/// bit `at`; `dense` says every row has. Rows without a value are left
/// as they are.
#[inline]
fn scatter<T: Copy + Default>(
    out: &mut [T],
    bits: &[u8],
    at: usize,
    dense: bool,
    tmp: &mut Vec<T>,
    mut next: impl FnMut(&mut [T]) -> Result<bool>,
) -> Result<bool> {
    if dense {
        for block in out.chunks_mut(BATCH) {
            if !next(block)? {
                return Ok(false);
            }
        }
        return Ok(true);
    }
    for (b, block) in out.chunks_mut(BATCH).enumerate() {
        let first = at + b * BATCH;
        let n = block.len();
        let mut present = 0usize;
        let mut k = 0;
        while k < n {
            let len = (n - k).min(64);
            present += bits_at(bits, first + k, len).count_ones() as usize;
            k += len;
        }
        if present == 0 {
            continue;
        }
        if present == n {
            if !next(block)? {
                return Ok(false);
            }
            continue;
        }
        tmp.clear();
        tmp.resize(present, T::default());
        if !next(tmp)? {
            return Ok(false);
        }
        let mut j = 0;
        let mut k = 0;
        while k < n {
            let len = (n - k).min(64);
            let mut w = bits_at(bits, first + k, len);
            if w == u64::MAX {
                block[k..k + 64].copy_from_slice(&tmp[j..j + 64]);
                j += 64;
            } else {
                while w != 0 {
                    let t = w.trailing_zeros() as usize;
                    block[k + t] = tmp[j];
                    j += 1;
                    w &= w - 1;
                }
            }
            k += len;
        }
    }
    Ok(true)
}

/// The next `dst.len()` dictionary entries `h` points to.
#[inline]
fn gather<T: Copy>(h: &mut Hybrid, dict: &[T], dst: &mut [T], idx: &mut Vec<u32>) -> Result<()> {
    let past = || Error::new("a dictionary index is past the end of the dictionary");
    let mut i = 0;
    while i < dst.len() {
        if let Some((v, n)) = h.run(dst.len() - i)? {
            let d = *dict.get(v as usize).ok_or_else(past)?;
            dst[i..i + n].fill(d);
            i += n;
            continue;
        }
        let n = h.literal_left().min(dst.len() - i).min(BATCH);
        if n == 0 {
            return Err(Error::new("RLE data ends early"));
        }
        idx.clear();
        idx.resize(n, 0);
        h.next(idx)?;
        let max = idx.iter().copied().max().unwrap_or(0);
        if max as usize >= dict.len() {
            return Err(past());
        }
        for (d, &k) in dst[i..i + n].iter_mut().zip(idx.iter()) {
            // SAFETY: every index was checked against the dictionary.
            *d = unsafe { *dict.get_unchecked(k as usize) };
        }
        i += n;
    }
    Ok(())
}

/// The dictionary indices of a page, from its value `before`.
fn indices<'p>(page: &DataPage<'p>, before: usize) -> Result<Hybrid<'p>> {
    let width = *page
        .values
        .first()
        .ok_or_else(|| Error::new("a dictionary-encoded page has no bit width"))?;
    let mut h = Hybrid::new(&page.values[1..], width)?;
    h.skip(before)?;
    Ok(h)
}

/// Convert PLAIN values to `T`; false if any is a letter or cannot be
/// held.
#[inline]
fn convert<P: Physical, T: Element>(src: &[u8], dst: &mut [T]) -> bool {
    #[cfg(target_endian = "little")]
    if !P::LETTERS && same::<P, T>() {
        // SAFETY: P and T are the same plain number type, and `src` holds
        // `dst.len()` of them, little-endian like this machine.
        unsafe {
            std::ptr::copy_nonoverlapping(src.as_ptr(), dst.as_mut_ptr() as *mut u8, std::mem::size_of_val(dst));
        }
        return true;
    }
    let mut ok = true;
    for (d, c) in dst.iter_mut().zip(src.chunks_exact(P::WIDTH)) {
        let p = P::from_le(c);
        ok &= p.letter() == 0;
        match p.convert::<T>() {
            Some(v) => *d = v,
            None => ok = false,
        }
    }
    ok
}

fn same<P: 'static, T: 'static>() -> bool {
    std::any::TypeId::of::<P>() == std::any::TypeId::of::<T>()
}

/// What every consumer of a chunk shares: the chunk's validity bits and
/// letters, by row of the chunk's output.
struct State {
    bits: Vec<u8>,
    letters: Vec<(usize, u8)>,
    /// The file's row of the output's first, for messages.
    file_row: u64,
}

/// A page's rows a value at a time: nulls skipped, each value converted,
/// a tagged NaN recorded as its letter. For pages the fast path cannot
/// take, and to find the row of a value that cannot be held.
fn slow<P: Physical, T: Element + Default>(
    out: &mut [T],
    page: &DataPage,
    before: usize,
    st: &mut State,
    mut value: impl FnMut(usize) -> P,
) -> Result<()> {
    let at = page.out_at;
    let mut vi = before;
    for (k, o) in out.iter_mut().enumerate() {
        if !valid_at(&st.bits, at + k) {
            continue;
        }
        let p = value(vi);
        vi += 1;
        let c = p.letter();
        if c != 0 {
            *o = T::default();
            st.letters.push((at + k, c));
            continue;
        }
        *o = p
            .convert()
            .ok_or_else(|| cannot_hold(&p, st.file_row + (at + k) as u64, T::NAME))?;
    }
    Ok(())
}

// ---- numbers ----

struct Num<'o, P, T> {
    out: &'o mut [T],
    st: &'o mut State,
    dict: Vec<P>,
    /// The dictionary converted, and whether every entry converted to a
    /// value (no letter, nothing that cannot be held).
    dict_t: Vec<T>,
    dict_clean: bool,
    tmp: Vec<T>,
    idx: Vec<u32>,
    decoded: Vec<u64>,
}

impl<P: Physical, T: Element + Default> Consumer for Num<'_, P, T> {
    fn dictionary(&mut self, count: usize, values: &[u8]) -> Result<()> {
        let bytes = values
            .get(..count.saturating_mul(P::WIDTH))
            .ok_or_else(|| Error::new("a dictionary page ends early"))?;
        self.dict = bytes.chunks_exact(P::WIDTH).map(P::from_le).collect();
        self.dict_t.clear();
        self.dict_clean = true;
        for &p in &self.dict {
            match p.convert::<T>() {
                Some(v) if p.letter() == 0 => self.dict_t.push(v),
                _ => {
                    self.dict_t.push(T::default());
                    self.dict_clean = false;
                }
            }
        }
        Ok(())
    }

    fn page(&mut self, page: &DataPage, _: &mut Vec<u32>, _: &mut Vec<u8>) -> Result<()> {
        let (before, present) = page_levels(&mut self.st.bits, page)?;
        if present == before {
            return Ok(());
        }
        let n = page.take.len();
        let at = page.out_at;
        let dense = present - before == n;
        let out = &mut self.out[at..at + n];
        match page.encoding {
            Encoding::Plain => {
                let need = present.saturating_mul(P::WIDTH);
                let bytes = page
                    .values
                    .get(..need)
                    .ok_or_else(|| Error::new("a page holds fewer values than its levels say"))?;
                let mut from = before * P::WIDTH;
                let fast = scatter(out, &self.st.bits, at, dense, &mut self.tmp, |dst| {
                    let end = from + dst.len() * P::WIDTH;
                    let ok = convert::<P, T>(&bytes[from..end], dst);
                    from = end;
                    Ok(ok)
                })?;
                if !fast {
                    slow(out, page, before, self.st, |i| P::from_le(&bytes[i * P::WIDTH..]))?;
                }
                Ok(())
            }
            Encoding::PlainDictionary | Encoding::RleDictionary => {
                if self.dict_clean {
                    let mut h = indices(page, before)?;
                    let (dict, idx) = (&self.dict_t, &mut self.idx);
                    scatter(out, &self.st.bits, at, dense, &mut self.tmp, |dst| gather(&mut h, dict, dst, idx).map(|()| true))?;
                    return Ok(());
                }
                // Letters (or values the output cannot hold) in the
                // dictionary: a row at a time, which says which rows.
                let mut h = indices(page, before)?;
                self.idx.clear();
                self.idx.resize(present - before, 0);
                h.next(&mut self.idx)?;
                if self.idx.iter().any(|&i| i as usize >= self.dict.len()) {
                    return Err(Error::new("a dictionary index is past the end of the dictionary"));
                }
                let (dict, idx) = (&self.dict, &self.idx);
                slow(out, page, before, self.st, |i| dict[idx[i - before] as usize])
            }
            Encoding::DeltaBinaryPacked if P::from_bits(0).is_some() => {
                let mut buf = std::mem::take(&mut self.decoded);
                buf.clear();
                buf.resize(present - before, 0);
                let result = encoding::delta_values(page.values, before, &mut buf).and_then(|()| {
                    slow(out, page, before, self.st, |i| P::from_bits(buf[i - before]).expect("an integer type"))
                });
                self.decoded = buf;
                result
            }
            Encoding::ByteStreamSplit => {
                let count = encoding::split_count(page.values, P::WIDTH)?;
                if count < present {
                    return Err(Error::new("a page holds fewer values than its levels say"));
                }
                let values = page.values;
                slow(out, page, before, self.st, |i| {
                    let mut b = [0u8; 16];
                    encoding::split_value(values, count, i, &mut b[..P::WIDTH]);
                    P::from_le(&b)
                })
            }
            other => Err(decode::unsupported_encoding(other)),
        }
    }
}

/// Booleans into 0 and 1.
struct Bools<'o, T> {
    out: &'o mut [T],
    st: &'o mut State,
}

impl<T: Element + Default> Consumer for Bools<'_, T> {
    fn dictionary(&mut self, _: usize, _: &[u8]) -> Result<()> {
        Err(Error::new("a boolean column has a dictionary page"))
    }

    fn page(&mut self, page: &DataPage, _: &mut Vec<u32>, bools: &mut Vec<u8>) -> Result<()> {
        let (before, present) = page_levels(&mut self.st.bits, page)?;
        decode::booleans(page, before, present, bools)?;
        let out = &mut self.out[page.out_at..page.out_at + page.take.len()];
        let bools = &*bools;
        slow(out, page, before, self.st, |i| i32::from(bools[i - before]))
    }
}

fn numbers<T: Element + Default>(
    chunk: &Chunk,
    out: &mut [T],
    st: &mut State,
    read: &mut ReadAt,
    scratch: &mut Scratch,
) -> Result<()> {
    fn run<P: Physical, T: Element + Default>(
        chunk: &Chunk,
        out: &mut [T],
        st: &mut State,
        read: &mut ReadAt,
        scratch: &mut Scratch,
    ) -> Result<()> {
        let mut c = Num::<P, T> {
            out,
            st,
            dict: Vec::new(),
            dict_t: Vec::new(),
            dict_clean: true,
            tmp: Vec::new(),
            idx: Vec::new(),
            decoded: Vec::new(),
        };
        decode::decode(chunk, read, scratch, &mut c)
    }
    let unsigned = matches!(
        chunk.column.kind,
        ColumnType::UInt8 | ColumnType::UInt16 | ColumnType::UInt32 | ColumnType::UInt64
    );
    match chunk.column.physical {
        Some(PhysicalType::Int32) if unsigned => run::<u32, T>(chunk, out, st, read, scratch),
        Some(PhysicalType::Int64) if unsigned => run::<u64, T>(chunk, out, st, read, scratch),
        Some(PhysicalType::Int32) => run::<i32, T>(chunk, out, st, read, scratch),
        Some(PhysicalType::Int64) => run::<i64, T>(chunk, out, st, read, scratch),
        Some(PhysicalType::Int96) => run::<Int96, T>(chunk, out, st, read, scratch),
        Some(PhysicalType::Float) => run::<f32, T>(chunk, out, st, read, scratch),
        Some(PhysicalType::Double) => run::<f64, T>(chunk, out, st, read, scratch),
        Some(PhysicalType::Boolean) => decode::decode(chunk, read, scratch, &mut Bools { out, st }),
        _ => Err(Error::invalid(format!("column \"{}\" is not numeric", chunk.column.name))),
    }
}

// ---- text ----

/// The view of `b`, inline when it is 12 bytes or fewer; otherwise
/// pointing at `offset` in data buffer `buffer`.
#[inline]
fn view(b: &[u8], buffer: u32, offset: u32) -> u128 {
    let mut v = [0u8; 16];
    v[..4].copy_from_slice(&(b.len() as u32).to_le_bytes());
    if b.len() <= 12 {
        v[4..4 + b.len()].copy_from_slice(b);
    } else {
        v[4..8].copy_from_slice(&b[..4]);
        v[8..12].copy_from_slice(&buffer.to_le_bytes());
        v[12..16].copy_from_slice(&offset.to_le_bytes());
    }
    u128::from_le_bytes(v)
}

/// Arrow's views hold a buffer's offsets as 32-bit signed integers.
const BUFFER_MOST: usize = i32::MAX as usize;

struct Views<'o> {
    out: &'o mut [u128],
    st: &'o mut State,
    utf8: bool,
    fixed: Option<usize>,
    counter: &'o AtomicU32,
    /// Values longer than 12 bytes, copied into the chunk's data buffer.
    long: Vec<u8>,
    index: Option<u32>,
    done: Vec<(u32, Vec<u8>)>,
    dict: Vec<u128>,
    tmp: Vec<u128>,
    idx: Vec<u32>,
}

impl Views<'_> {
    fn view(&mut self, b: &[u8]) -> Result<u128> {
        if self.utf8 && std::str::from_utf8(b).is_err() {
            return Err(Error::new("a text value is not UTF-8"));
        }
        if b.len() <= 12 {
            return Ok(view(b, 0, 0));
        }
        if b.len() > BUFFER_MOST {
            return Err(Error::new("a value is longer than an Arrow string view holds").of(ErrorKind::TooLarge));
        }
        if self.index.is_some() && self.long.len() + b.len() > BUFFER_MOST {
            let full = std::mem::take(&mut self.long);
            self.done.push((self.index.take().expect("an index"), full));
        }
        let index = *self.index.get_or_insert_with(|| self.counter.fetch_add(1, Ordering::Relaxed));
        let offset = self.long.len() as u32;
        if self.long.try_reserve(b.len()).is_err() {
            return Err(Error::new(format!("{} bytes of text do not fit in memory here", b.len())).of(ErrorKind::TooLarge));
        }
        self.long.extend_from_slice(b);
        Ok(view(b, index, offset))
    }

    /// The views of `count` PLAIN values from `values`, skipping the first
    /// `skip`; returns the views of values `skip..count`.
    fn plain(&mut self, values: &[u8], skip: usize, count: usize, into: &mut Vec<u128>) -> Result<()> {
        if let Some(w) = self.fixed {
            let need = count.checked_mul(w).filter(|&n| n <= values.len());
            if need.is_none() {
                return Err(Error::new("a page holds fewer values than its levels say"));
            }
            for i in skip..count {
                let v = self.view(&values[i * w..(i + 1) * w])?;
                into.push(v);
            }
            return Ok(());
        }
        let mut at = 0usize;
        for i in 0..count {
            let len = values
                .get(at..at + 4)
                .map(|b| u32::from_le_bytes(b.try_into().expect("4 bytes")) as usize)
                .ok_or_else(|| Error::new("a page holds fewer values than its levels say"))?;
            let v = values
                .get(at + 4..)
                .and_then(|b| b.get(..len))
                .ok_or_else(|| Error::new("a text value runs past the end of its page"))?;
            at += 4 + len;
            if i >= skip {
                let v = self.view(v)?;
                into.push(v);
            }
        }
        Ok(())
    }

    fn finish(mut self) -> Vec<(u32, Vec<u8>)> {
        if let Some(i) = self.index.take() {
            self.done.push((i, std::mem::take(&mut self.long)));
        }
        self.done
    }
}

impl Consumer for Views<'_> {
    fn dictionary(&mut self, count: usize, values: &[u8]) -> Result<()> {
        let mut dict = Vec::with_capacity(count);
        self.plain(values, 0, count, &mut dict)?;
        self.dict = dict;
        Ok(())
    }

    fn page(&mut self, page: &DataPage, _: &mut Vec<u32>, scratch: &mut Vec<u8>) -> Result<()> {
        let (before, count) = page_levels(&mut self.st.bits, page)?;
        if count == before {
            return Ok(());
        }
        let n = page.take.len();
        let at = page.out_at;
        let dense = count - before == n;
        let mut present = std::mem::take(&mut self.tmp);
        present.clear();
        let result = match page.encoding {
            Encoding::PlainDictionary | Encoding::RleDictionary => {
                let mut h = indices(page, before)?;
                let (dict, idx) = (&self.dict, &mut self.idx);
                let out = &mut self.out[at..at + n];
                let r = scatter(out, &self.st.bits, at, dense, &mut present, |dst| gather(&mut h, dict, dst, idx).map(|()| true));
                self.tmp = present;
                return r.map(|_| ());
            }
            Encoding::Plain => self.plain(page.values, before, count, &mut present),
            Encoding::DeltaLengthByteArray if self.fixed.is_none() => {
                let mut vals = Vec::new();
                let r = encoding::delta_length_byte_array(page.values, before, count - before, |v| {
                    vals.push(self.view(v)?);
                    Ok(())
                });
                present = vals;
                r
            }
            Encoding::DeltaByteArray => {
                let mut vals = Vec::new();
                let r = encoding::delta_byte_array(page.values, before, count - before, scratch, |v| {
                    vals.push(self.view(v)?);
                    Ok(())
                });
                present = vals;
                r
            }
            Encoding::ByteStreamSplit if self.fixed.is_some() => {
                let w = self.fixed.expect("fixed");
                let stored = encoding::split_count(page.values, w)?;
                if stored < count {
                    return Err(Error::new("a page holds fewer values than its levels say"));
                }
                let mut b = vec![0u8; w];
                let mut r = Ok(());
                for i in before..count {
                    encoding::split_value(page.values, stored, i, &mut b);
                    match self.view(&b) {
                        Ok(v) => present.push(v),
                        Err(e) => {
                            r = Err(e);
                            break;
                        }
                    }
                }
                r
            }
            other => Err(decode::unsupported_encoding(other)),
        };
        result?;
        if present.len() != count - before {
            return Err(Error::new("a page holds fewer values than its levels say"));
        }
        let out = &mut self.out[at..at + n];
        let mut from = 0;
        let mut tmp = Vec::new();
        scatter(out, &self.st.bits, at, dense, &mut tmp, |dst| {
            dst.copy_from_slice(&present[from..from + dst.len()]);
            from += dst.len();
            Ok(true)
        })?;
        self.tmp = present;
        Ok(())
    }
}

// ---- categoricals ----

/// A dictionary entry that is not one of the levels.
const UNKNOWN: u32 = u32::MAX;

struct Keys<'o> {
    out: &'o mut [u32],
    st: &'o mut State,
    levels: &'o HashMap<&'o [u8], i32>,
    name: &'o str,
    dict: Vec<u32>,
    /// The text of each dictionary entry that is not a level.
    unknown: HashMap<u32, Vec<u8>>,
    tmp: Vec<u32>,
}

impl Keys<'_> {
    fn not_a_level(&self, value: &[u8], row: usize) -> Error {
        Error::invalid(format!(
            "column \"{}\": the value \"{}\" in row {} is not one of the levels in the dta profile",
            self.name,
            String::from_utf8_lossy(value),
            self.st.file_row + row as u64 + 1
        ))
    }

    fn code(&self, value: &[u8]) -> u32 {
        self.levels.get(value).map_or(UNKNOWN, |&c| c as u32)
    }
}

/// Each PLAIN byte array of a page, in order.
fn byte_arrays(values: &[u8], count: usize, mut f: impl FnMut(&[u8]) -> Result<()>) -> Result<()> {
    let mut at = 0usize;
    for _ in 0..count {
        let len = values
            .get(at..at + 4)
            .map(|b| u32::from_le_bytes(b.try_into().expect("4 bytes")) as usize)
            .ok_or_else(|| Error::new("a page holds fewer values than its levels say"))?;
        let v = values
            .get(at + 4..)
            .and_then(|b| b.get(..len))
            .ok_or_else(|| Error::new("a text value runs past the end of its page"))?;
        at += 4 + len;
        f(v)?;
    }
    Ok(())
}

impl Consumer for Keys<'_> {
    fn dictionary(&mut self, count: usize, values: &[u8]) -> Result<()> {
        let mut dict = Vec::with_capacity(count);
        let mut unknown = HashMap::new();
        byte_arrays(values, count, |v| {
            let c = self.code(v);
            if c == UNKNOWN {
                unknown.insert(dict.len() as u32, v.to_vec());
            }
            dict.push(c);
            Ok(())
        })?;
        self.dict = dict;
        self.unknown = unknown;
        Ok(())
    }

    fn page(&mut self, page: &DataPage, _: &mut Vec<u32>, _: &mut Vec<u8>) -> Result<()> {
        let (before, count) = page_levels(&mut self.st.bits, page)?;
        if count == before {
            return Ok(());
        }
        let n = page.take.len();
        let at = page.out_at;
        let dense = count - before == n;
        // The page's present values as level codes, or for each value
        // not a level, its dictionary entry or its text.
        let mut codes = std::mem::take(&mut self.tmp);
        codes.clear();
        let mut bad: Option<Vec<u8>> = None;
        match page.encoding {
            Encoding::PlainDictionary | Encoding::RleDictionary => {
                let mut h = indices(page, before)?;
                codes.resize(count - before, 0);
                // Entries, then codes: the entry of a value not a level is
                // needed for its message.
                h.next(&mut codes)?;
                if codes.iter().any(|&i| i as usize >= self.dict.len()) {
                    return Err(Error::new("a dictionary index is past the end of the dictionary"));
                }
                for c in codes.iter_mut() {
                    let k = self.dict[*c as usize];
                    if k == UNKNOWN && bad.is_none() {
                        bad = self.unknown.get(c).cloned();
                    }
                    *c = k;
                }
            }
            Encoding::Plain => {
                let mut i = 0;
                let levels = self.levels;
                byte_arrays(page.values, count, |v| {
                    if i >= before {
                        let k = levels.get(v).map_or(UNKNOWN, |&c| c as u32);
                        if k == UNKNOWN && bad.is_none() {
                            bad = Some(v.to_vec());
                        }
                        codes.push(k);
                    }
                    i += 1;
                    Ok(())
                })?;
            }
            other => return Err(decode::unsupported_encoding(other)),
        }
        let out = &mut self.out[at..at + n];
        let mut from = 0;
        let mut tmp = Vec::new();
        scatter(out, &self.st.bits, at, dense, &mut tmp, |dst| {
            dst.copy_from_slice(&codes[from..from + dst.len()]);
            from += dst.len();
            Ok(true)
        })?;
        if let Some(value) = bad {
            let k = (0..n).find(|&k| out[k] == UNKNOWN && valid_at(&self.st.bits, at + k)).unwrap_or(0);
            return Err(self.not_a_level(&value, at + k));
        }
        self.tmp = codes;
        Ok(())
    }
}

// ---- a chunk ----

/// Decode one column chunk's window into its part of an Arrow output.
pub(crate) fn decode_task(
    chunk: &Chunk,
    dest: ArrowDest,
    read: &mut ReadAt,
    scratch: &mut Scratch,
) -> Result<ArrowDone> {
    let rows = dest.data.len();
    let mut bits = std::mem::take(&mut scratch.arrow_bits);
    bits.clear();
    bits.resize(rows.div_ceil(8), 0);
    let mut st = State { bits, letters: Vec::new(), file_row: chunk.file_row + chunk.window.start };
    let mut buffers = Vec::new();
    let result = match dest.data {
        ArrowData::Int8(v) => numbers(chunk, v, &mut st, read, scratch),
        ArrowData::Int16(v) => numbers(chunk, v, &mut st, read, scratch),
        ArrowData::Int32(v) => numbers(chunk, v, &mut st, read, scratch),
        ArrowData::Int64(v) => numbers(chunk, v, &mut st, read, scratch),
        ArrowData::UInt8(v) => numbers(chunk, v, &mut st, read, scratch),
        ArrowData::UInt16(v) => numbers(chunk, v, &mut st, read, scratch),
        ArrowData::UInt32(v) => numbers(chunk, v, &mut st, read, scratch),
        ArrowData::UInt64(v) => numbers(chunk, v, &mut st, read, scratch),
        ArrowData::Float32(v) => numbers(chunk, v, &mut st, read, scratch),
        ArrowData::Float64(v) => numbers(chunk, v, &mut st, read, scratch),
        ArrowData::Views(v) => {
            let fixed = (chunk.column.physical == Some(PhysicalType::FixedLenByteArray))
                .then(|| chunk.column.type_length.and_then(|n| usize::try_from(n).ok()))
                .flatten()
                .filter(|&n| n > 0);
            let mut c = Views {
                out: v,
                st: &mut st,
                utf8: chunk.column.kind == ColumnType::Text,
                fixed,
                counter: dest.buffers,
                long: Vec::new(),
                index: None,
                done: Vec::new(),
                dict: Vec::new(),
                tmp: Vec::new(),
                idx: Vec::new(),
            };
            let r = decode::decode(chunk, read, scratch, &mut c);
            buffers = c.finish();
            r
        }
        ArrowData::Keys(v) => {
            let levels = dest.levels.ok_or_else(|| Error::new("internal: a categorical without levels"))?;
            let mut c = Keys {
                out: v,
                st: &mut st,
                levels,
                name: &chunk.column.name,
                dict: Vec::new(),
                unknown: HashMap::new(),
                tmp: Vec::new(),
            };
            decode::decode(chunk, read, scratch, &mut c)
        }
    };
    let State { mut bits, letters, .. } = st;
    let finish = || -> Result<ArrowDone> {
        result.map_err(|e| match e.kind {
            ErrorKind::Invalid if !e.message.starts_with("column \"") => {
                Error::invalid(format!("column \"{}\": {}", chunk.column.name, e.message))
            }
            _ => e,
        })?;
        for &(r, _) in &letters {
            bits[r / 8] &= !(1 << (r % 8));
        }
        let present: usize = bits.iter().map(|b| b.count_ones() as usize).sum();
        let nulls = (rows - present) as u64;
        match dest.validity {
            Some(v) => merge(v, dest.first, &bits, rows),
            None if nulls > 0 => {
                return Err(Error::new(format!(
                    "column \"{}\" has missing values, which its statistics said it had not",
                    chunk.column.name
                ))
                .of(ErrorKind::Corrupt))
            }
            None => {}
        }
        Ok(ArrowDone {
            nulls,
            letters: letters.iter().map(|&(r, c)| ((dest.first + r) as u64, c)).collect(),
            buffers: std::mem::take(&mut buffers),
        })
    };
    let done = finish();
    scratch.arrow_bits = bits;
    done
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bits_pack_and_merge_at_any_offset() {
        let levels: Vec<u8> = (0..203).map(|i| u8::from(i % 3 != 0 && i % 7 != 1)).collect();
        for at in [0usize, 1, 5, 8, 13] {
            let mut local = vec![0u8; levels.len().div_ceil(8) + 2];
            pack_into(&mut local, at, &levels);
            for (k, &l) in levels.iter().enumerate() {
                assert_eq!((local[(at + k) / 8] >> ((at + k) % 8)) & 1, l, "at {at} row {k}");
            }
        }
        // Chunks of a column merged in any order give the bits of the whole.
        let sizes = [5usize, 11, 64, 3, 120];
        let total: usize = sizes.iter().sum();
        let all: Vec<u8> = (0..total).map(|i| u8::from(i % 5 != 2)).collect();
        let mut dst_bytes = vec![0u8; total.div_ceil(8)];
        let dst = atomic(&mut dst_bytes);
        let mut starts = Vec::new();
        let mut s = 0;
        for &n in &sizes {
            starts.push(s);
            s += n;
        }
        for k in [3usize, 0, 4, 1, 2] {
            let (s, n) = (starts[k], sizes[k]);
            let mut local = vec![0u8; n.div_ceil(8)];
            pack_into(&mut local, 0, &all[s..s + n]);
            merge(dst, s, &local, n);
        }
        for (k, &l) in all.iter().enumerate() {
            assert_eq!((dst_bytes[k / 8] >> (k % 8)) & 1, l, "row {k}");
        }
        let mut b = vec![0u8; 4];
        set_range(&mut b, 3, 22);
        assert_eq!(b, [0b1111_1000, 0xff, 0xff, 0b0000_0001]);
    }

    #[test]
    fn views_follow_the_format() {
        let v = view(b"hello", 0, 0).to_le_bytes();
        assert_eq!(&v[..4], &5u32.to_le_bytes());
        assert_eq!(&v[4..9], b"hello");
        assert!(v[9..].iter().all(|&b| b == 0));
        let v = view(b"a longer value", 3, 77).to_le_bytes();
        assert_eq!(&v[..4], &14u32.to_le_bytes());
        assert_eq!(&v[4..8], b"a lo");
        assert_eq!(&v[8..12], &3u32.to_le_bytes());
        assert_eq!(&v[12..16], &77u32.to_le_bytes());
    }
}
