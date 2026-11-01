//! Where each strL's payload is (plan 0008 M1): four parallel arrays
//! sorted by key, about 20 bytes a strL. A `HashMap` took 106 to 130,
//! so tens of millions of strLs filled wasm's 4 GiB.

use std::sync::atomic::{AtomicUsize, Ordering};

use crate::error::{Error, ErrorKind, Result};

/// Largest variable number and observation a key holds: `v < 2^24`,
/// `o < 2^40`, which every release's cells fit (117: 4 + 4 bytes, but
/// variable numbers are small; 118: 2 + 6; 119: 3 + 5).
const V_BITS: u32 = 24;
const O_BITS: u32 = 40;

/// The key of strL (`v`, `o`), or None if it does not fit.
pub(crate) fn key(v: u64, o: u64) -> Option<u64> {
    (v < 1 << V_BITS && o < 1 << O_BITS).then_some((v << O_BITS) | o)
}

/// One strL's place in the file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct StrlEntry {
    pub offset: u64,
    pub len: u32,
    pub binary: bool,
}

#[derive(Debug, Default)]
pub(crate) struct StrlIndex {
    keys: Vec<u64>,
    offsets: Vec<u64>,
    lens: Vec<u32>,
    /// Bit `i` set: entry `i` is binary.
    binary: Vec<u64>,
    /// The entry after the last one found: rows are read in order, so it
    /// is usually the next one asked for.
    cursor: AtomicUsize,
}

fn too_large() -> Error {
    Error::new("the strL index does not fit in memory here").of(ErrorKind::TooLarge)
}

/// What an exported index records of its file, which an adopting reader
/// must match (plan 0008 M6).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Shape {
    pub file_len: u64,
    pub release: u32,
    pub big_endian: bool,
    pub nobs: u64,
    pub nvar: u64,
    /// The strL section's first byte and the byte after its last.
    pub start: u64,
    pub end: u64,
}

const MAGIC: &[u8; 8] = b"DTASTRLX";
const VERSION: u32 = 1;
/// Magic, version and reserved word, then the shape, then the count.
const HEAD: usize = 8 + 4 + 4 + 8 + 4 + 4 + 8 + 8 + 8 + 8 + 8;

fn mismatch(what: &str) -> Error {
    Error::new(format!("the strL index does not belong to this file: {what}"))
}

impl StrlIndex {
    /// Add an entry, in file order. Fails only for lack of memory.
    pub fn push(&mut self, key: u64, entry: StrlEntry) -> Result<()> {
        let i = self.keys.len();
        if self.keys.try_reserve(1).is_err()
            || self.offsets.try_reserve(1).is_err()
            || self.lens.try_reserve(1).is_err()
            || (i % 64 == 0 && self.binary.try_reserve(1).is_err())
        {
            return Err(too_large());
        }
        self.keys.push(key);
        self.offsets.push(entry.offset);
        self.lens.push(entry.len);
        if i % 64 == 0 {
            self.binary.push(0);
        }
        if entry.binary {
            self.binary[i / 64] |= 1 << (i % 64);
        }
        Ok(())
    }

    fn is_binary(&self, i: usize) -> bool {
        self.binary[i / 64] >> (i % 64) & 1 == 1
    }

    fn entry(&self, i: usize) -> StrlEntry {
        StrlEntry { offset: self.offsets[i], len: self.lens[i], binary: self.is_binary(i) }
    }

    /// Sort by key, if the file did not list strLs in order; then a key
    /// listed twice is an error (`at` is the strL section's start).
    pub fn finish(&mut self, at: u64) -> Result<()> {
        if !self.keys.windows(2).all(|w| w[0] <= w[1]) {
            self.sort()?;
        }
        if let Some(w) = self.keys.windows(2).find(|w| w[0] == w[1]) {
            let (v, o) = (w[0] >> O_BITS, w[0] & ((1 << O_BITS) - 1));
            return Err(Error::at(at, format!("two strLs are both variable {v} observation {o}")));
        }
        Ok(())
    }

    /// Sort the four arrays together by key. Stable, so of equal keys the
    /// first in the file stays first (`finish` then rejects them).
    fn sort(&mut self) -> Result<()> {
        let n = self.keys.len();
        let mut order: Vec<u32> = Vec::new();
        order.try_reserve_exact(n).map_err(|_| too_large())?;
        order.extend(0..n as u32);
        order.sort_by_key(|&i| self.keys[i as usize]);
        let mut keys = Vec::new();
        let mut offsets = Vec::new();
        let mut lens = Vec::new();
        let mut binary = Vec::new();
        if keys.try_reserve_exact(n).is_err()
            || offsets.try_reserve_exact(n).is_err()
            || lens.try_reserve_exact(n).is_err()
            || binary.try_reserve_exact(self.binary.len()).is_err()
        {
            return Err(too_large());
        }
        binary.resize(self.binary.len(), 0u64);
        for (j, &i) in order.iter().enumerate() {
            let i = i as usize;
            keys.push(self.keys[i]);
            offsets.push(self.offsets[i]);
            lens.push(self.lens[i]);
            if self.is_binary(i) {
                binary[j / 64] |= 1 << (j % 64);
            }
        }
        (self.keys, self.offsets, self.lens, self.binary) = (keys, offsets, lens, binary);
        Ok(())
    }

    /// The index as bytes, for another reader of the same file to adopt
    /// (layout in docs/typescript.md, all little-endian): a 72-byte
    /// header, then the keys (u64), offsets (u64), lengths (u32) and
    /// binary bits (u64 words).
    pub fn to_bytes(&self, shape: &Shape) -> Result<Vec<u8>> {
        let n = self.keys.len();
        let size = HEAD + n * 20 + self.binary.len() * 8;
        let mut out = Vec::new();
        out.try_reserve_exact(size).map_err(|_| too_large())?;
        out.extend_from_slice(MAGIC);
        out.extend_from_slice(&VERSION.to_le_bytes());
        out.extend_from_slice(&0u32.to_le_bytes());
        out.extend_from_slice(&shape.file_len.to_le_bytes());
        out.extend_from_slice(&shape.release.to_le_bytes());
        out.extend_from_slice(&u32::from(shape.big_endian).to_le_bytes());
        out.extend_from_slice(&shape.nobs.to_le_bytes());
        out.extend_from_slice(&shape.nvar.to_le_bytes());
        out.extend_from_slice(&shape.start.to_le_bytes());
        out.extend_from_slice(&shape.end.to_le_bytes());
        out.extend_from_slice(&(n as u64).to_le_bytes());
        self.keys.iter().for_each(|k| out.extend_from_slice(&k.to_le_bytes()));
        self.offsets.iter().for_each(|o| out.extend_from_slice(&o.to_le_bytes()));
        self.lens.iter().for_each(|l| out.extend_from_slice(&l.to_le_bytes()));
        self.binary.iter().for_each(|w| out.extend_from_slice(&w.to_le_bytes()));
        Ok(out)
    }

    /// An index exported by `to_bytes`, checked against `shape` and for
    /// consistency: the header matches, the version is known, the arrays
    /// have the stated lengths, keys strictly increase, and each payload
    /// lies inside the strL section. Any failure is a `Corrupt` error.
    pub fn from_bytes(bytes: &[u8], shape: &Shape) -> Result<StrlIndex> {
        let word = |at: usize| u64::from_le_bytes(bytes[at..at + 8].try_into().unwrap_or_default());
        let half = |at: usize| u32::from_le_bytes(bytes[at..at + 4].try_into().unwrap_or_default());
        if bytes.len() < HEAD || &bytes[..8] != MAGIC {
            return Err(mismatch("it is not a strL index"));
        }
        if half(8) != VERSION {
            return Err(mismatch(&format!("version {} is not known", half(8))));
        }
        let theirs = Shape {
            file_len: word(16),
            release: half(24),
            big_endian: half(28) != 0,
            nobs: word(32),
            nvar: word(40),
            start: word(48),
            end: word(56),
        };
        if theirs != *shape {
            return Err(mismatch("it was made from a file of another size or layout"));
        }
        let n = usize::try_from(word(64)).map_err(|_| mismatch("bad count"))?;
        let words = n.div_ceil(64);
        if n.checked_mul(20).and_then(|x| x.checked_add(HEAD + words * 8)) != Some(bytes.len()) {
            return Err(mismatch("its length does not match its count"));
        }
        let mut index = StrlIndex::default();
        if index.keys.try_reserve_exact(n).is_err()
            || index.offsets.try_reserve_exact(n).is_err()
            || index.lens.try_reserve_exact(n).is_err()
            || index.binary.try_reserve_exact(words).is_err()
        {
            return Err(too_large());
        }
        let (keys, offsets, lens) = (HEAD, HEAD + n * 8, HEAD + n * 16);
        let bits = HEAD + n * 20;
        for i in 0..n {
            let (k, o, l) = (word(keys + i * 8), word(offsets + i * 8), half(lens + i * 4));
            if i > 0 && k <= index.keys[i - 1] {
                return Err(mismatch("its keys are out of order"));
            }
            if o < shape.start || o.checked_add(l as u64).is_none_or(|e| e > shape.end) {
                return Err(mismatch("an entry lies outside the strL section"));
            }
            index.keys.push(k);
            index.offsets.push(o);
            index.lens.push(l);
        }
        index.binary.extend((0..words).map(|w| word(bits + w * 8)));
        Ok(index)
    }

    /// The entry for `key`, if the file has one.
    pub fn get(&self, key: u64) -> Option<StrlEntry> {
        let hint = self.cursor.load(Ordering::Relaxed);
        let i = if self.keys.get(hint) == Some(&key) {
            hint
        } else {
            self.keys.binary_search(&key).ok()?
        };
        self.cursor.store(i + 1, Ordering::Relaxed);
        Some(self.entry(i))
    }
}

#[cfg(test)]
mod tests {
    fn shape() -> Shape {
        Shape { file_len: 1000, release: 118, big_endian: false, nobs: 9, nvar: 2, start: 100, end: 900 }
    }

    #[test]
    fn round_trips_and_rejects_what_does_not_match() {
        let mut index = StrlIndex::default();
        for k in [3u64, 1, 2] {
            index.push(k, StrlEntry { offset: 100 + k * 10, len: k as u32, binary: k == 2 }).unwrap();
        }
        index.finish(0).unwrap();
        let bytes = index.to_bytes(&shape()).unwrap();
        let back = StrlIndex::from_bytes(&bytes, &shape()).unwrap();
        for k in 1..=3 {
            assert_eq!(back.get(k), index.get(k));
        }
        let other = Shape { file_len: 1001, ..shape() };
        assert!(StrlIndex::from_bytes(&bytes, &other).is_err());
        assert!(StrlIndex::from_bytes(&bytes[..bytes.len() - 1], &shape()).is_err());
        let mut version = bytes.clone();
        version[8] = 2;
        assert!(StrlIndex::from_bytes(&version, &shape()).is_err());
        let mut reordered = bytes.clone();
        reordered[HEAD..HEAD + 8].copy_from_slice(&9u64.to_le_bytes());
        assert!(StrlIndex::from_bytes(&reordered, &shape()).is_err());
        let mut outside = bytes.clone();
        outside[HEAD + 24..HEAD + 32].copy_from_slice(&900u64.to_le_bytes());
        assert!(StrlIndex::from_bytes(&outside, &shape()).is_err());
    }

    use super::*;

    fn e(offset: u64) -> StrlEntry {
        StrlEntry { offset, len: offset as u32, binary: offset % 3 == 0 }
    }

    #[test]
    fn finds_in_and_out_of_order() {
        for keys in [vec![1u64, 2, 5, 9, 70], vec![70, 2, 9, 1, 5]] {
            let mut index = StrlIndex::default();
            for &k in &keys {
                index.push(k, e(k * 10)).unwrap();
            }
            index.finish(0).unwrap();
            for &k in &keys {
                assert_eq!(index.get(k), Some(e(k * 10)));
            }
            assert_eq!(index.get(3), None);
            assert_eq!(index.get(1), Some(e(10)));
        }
    }

    #[test]
    fn binary_flags_survive_sorting_past_64_entries() {
        let mut index = StrlIndex::default();
        for k in (0..200u64).rev() {
            index.push(k, e(k)).unwrap();
        }
        index.finish(0).unwrap();
        for k in 0..200 {
            assert_eq!(index.get(k), Some(e(k)), "key {k}");
        }
    }

    #[test]
    fn a_key_twice_is_an_error() {
        let mut index = StrlIndex::default();
        for k in [4u64, 1, 4] {
            index.push(k, e(k)).unwrap();
        }
        assert!(index.finish(0).unwrap_err().message.contains("two strLs"));
    }

    #[test]
    fn keys_pack_and_bound() {
        assert_eq!(key(1, 2), Some((1 << 40) | 2));
        assert_eq!(key(1 << 24, 0), None);
        assert_eq!(key(0, 1 << 40), None);
    }
}
