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
