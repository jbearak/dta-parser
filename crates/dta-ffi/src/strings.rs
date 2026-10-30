//! String columns as the wasm module hands them to JavaScript (plan 0008
//! S1, S2): either dictionary codes plus the values first seen in this
//! call, or plain text with UTF-16 ends, so JavaScript makes each string
//! with one `decode` per call and a `substring` per value.

/// Rows a column must have shown before the half-distinct rule applies
/// (ADR 0011).
const MIN_ROWS: u64 = 65_536;
/// Most bytes of distinct values a dictionary holds.
const MAX_VALUE_BYTES: usize = 16 << 20;
/// Longest probe sequence before the values count as colliding more than
/// chance allows (wasm has no random hash keys, so a crafted file could
/// aim for collisions; it then only loses the dictionary).
const MAX_PROBE: usize = 128;

/// UTF-16 code units of valid UTF-8: one per byte that starts a
/// character, and one more for each four-byte character.
pub fn utf16_len(bytes: &[u8]) -> usize {
    bytes.iter().map(|&b| if b & 0xC0 == 0x80 { 0 } else if b >= 0xF0 { 2 } else { 1 }).sum()
}

/// `a == b`, without a call to memcmp for the short values most string
/// columns hold (wasm's memcmp is a plain loop behind a call).
#[inline]
fn same(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    if a.len() <= 16 {
        let word = |s: &[u8], from: usize| {
            let mut w = [0u8; 8];
            let end = s.len().min(from + 8);
            if from < end {
                w[..end - from].copy_from_slice(&s[from..end]);
            }
            u64::from_le_bytes(w)
        };
        return word(a, 0) == word(b, 0) && word(a, 8) == word(b, 8);
    }
    a == b
}

fn hash(bytes: &[u8]) -> u64 {
    const K: u64 = 0x9E37_79B9_7F4A_7C15;
    let mut h = bytes.len() as u64;
    let mut chunks = bytes.chunks_exact(8);
    for c in &mut chunks {
        h = (h.rotate_left(26) ^ u64::from_le_bytes(c.try_into().unwrap_or_default())).wrapping_mul(K);
    }
    let rest = chunks.remainder();
    if !rest.is_empty() {
        let mut w = [0u8; 8];
        w[..rest.len()].copy_from_slice(rest);
        h = (h.rotate_left(26) ^ u64::from_le_bytes(w)).wrapping_mul(K);
    }
    h ^ (h >> 32)
}

/// One column's dictionary over one read: distinct values in order of
/// first appearance.
#[derive(Default)]
pub struct Dict {
    /// Open addressing: 0 is empty, else the value's code plus 1.
    slots: Vec<u32>,
    hashes: Vec<u64>,
    /// The values' bytes, end to end, and each one's end.
    bytes: Vec<u8>,
    ends: Vec<usize>,
    /// Values handed to JavaScript so far.
    sent: usize,
    rows: u64,
    pub gave_up: bool,
}

/// What a call hands JavaScript for one string column.
pub enum Strings {
    /// Codes for every row of the call, and the values first seen in it
    /// (UTF-8 bytes and cumulative UTF-16 ends).
    Coded { codes: Vec<u32>, new_bytes: Vec<u8>, new_utf16: Vec<u32> },
    /// Every row: text bytes with cumulative UTF-16 ends. With binary
    /// rows, `text` is a copy of the text rows alone; JavaScript takes
    /// the binary rows from the column's own bytes, by its byte ends, so
    /// a large binary strL is not copied.
    Plain { text: Option<Vec<u8>>, utf16: Vec<u32> },
}

impl Dict {
    fn find_or_add(&mut self, value: &[u8]) -> Option<u32> {
        if self.slots.len() < 2 * (self.ends.len() + 1) && !self.grow() {
            return None;
        }
        let h = hash(value);
        let mask = self.slots.len() - 1;
        let mut i = (h >> 32) as usize & mask;
        for _ in 0..MAX_PROBE {
            match self.slots[i] {
                0 => {
                    let code = self.ends.len();
                    if self.bytes.len() + value.len() > MAX_VALUE_BYTES
                        || code >= i32::MAX as usize
                        || self.bytes.try_reserve(value.len()).is_err()
                        || self.ends.try_reserve(1).is_err()
                        || self.hashes.try_reserve(1).is_err()
                    {
                        return None;
                    }
                    self.bytes.extend_from_slice(value);
                    self.ends.push(self.bytes.len());
                    self.hashes.push(h);
                    self.slots[i] = code as u32 + 1;
                    return Some(code as u32);
                }
                s => {
                    let code = (s - 1) as usize;
                    if self.hashes[code] == h && same(self.value(code), value) {
                        return Some(code as u32);
                    }
                }
            }
            i = (i + 1) & mask;
        }
        None
    }

    fn value(&self, code: usize) -> &[u8] {
        let start = if code == 0 { 0 } else { self.ends[code - 1] };
        &self.bytes[start..self.ends[code]]
    }

    /// Double the table (or make its first); false if memory is short.
    fn grow(&mut self) -> bool {
        let size = (self.slots.len() * 2).max(1024);
        let mut slots = Vec::new();
        if slots.try_reserve_exact(size).is_err() {
            return false;
        }
        slots.resize(size, 0u32);
        let mask = size - 1;
        for (code, &h) in self.hashes.iter().enumerate() {
            let mut i = (h >> 32) as usize & mask;
            while slots[i] != 0 {
                i = (i + 1) & mask;
            }
            slots[i] = code as u32 + 1;
        }
        self.slots = slots;
        true
    }

    /// Code the rows of a call (`bytes` split at `ends`; `binary` true
    /// for binary strLs), or None if the column gives the dictionary up
    /// during it, after which it stays plain for the read.
    pub fn code(&mut self, bytes: &[u8], ends: &[usize], binary: &[bool]) -> Option<(Vec<u32>, Vec<u8>, Vec<u32>)> {
        if self.gave_up {
            return None;
        }
        let mut codes = Vec::new();
        if codes.try_reserve_exact(ends.len()).is_err() {
            self.gave_up = true;
            return None;
        }
        let mut start = 0;
        for (i, &end) in ends.iter().enumerate() {
            self.rows += 1;
            let code = if binary.get(i).copied().unwrap_or(false) { None } else { self.find_or_add(&bytes[start..end]) };
            let Some(code) = code else {
                self.gave_up = true;
                return None;
            };
            if self.rows >= MIN_ROWS && self.ends.len() as u64 * 2 > self.rows {
                self.gave_up = true;
                return None;
            }
            codes.push(code);
            start = end;
        }
        let from = if self.sent == 0 { 0 } else { self.ends[self.sent - 1] };
        let new_bytes = self.bytes[from..].to_vec();
        let mut new_utf16 = Vec::with_capacity(self.ends.len() - self.sent);
        let mut units = 0u32;
        for code in self.sent..self.ends.len() {
            units += utf16_len(self.value(code)) as u32;
            new_utf16.push(units);
        }
        self.sent = self.ends.len();
        Some((codes, new_bytes, new_utf16))
    }
}

/// The plain form of a call's string column.
pub fn plain(bytes: &[u8], ends: &[usize], binary: &[bool]) -> Strings {
    let mut utf16 = Vec::with_capacity(ends.len());
    let any_binary = binary.iter().any(|&b| b);
    let mut text = any_binary.then(Vec::new);
    let (mut start, mut units) = (0, 0u32);
    for (i, &end) in ends.iter().enumerate() {
        let value = &bytes[start..end];
        if !(any_binary && binary[i]) {
            units += if value.is_ascii() { value.len() as u32 } else { utf16_len(value) as u32 };
            if let Some(text) = text.as_mut() {
                text.extend_from_slice(value);
            }
        }
        utf16.push(units);
        start = end;
    }
    Strings::Plain { text, utf16 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf16_lengths() {
        assert_eq!(utf16_len("aé€😀".as_bytes()), "aé€😀".encode_utf16().count());
    }

    #[test]
    fn codes_and_new_values() {
        let mut d = Dict::default();
        let (codes, new, utf16) = d.code(b"abba", &[1, 2, 3, 4], &[]).unwrap();
        assert_eq!((codes, new, utf16), (vec![0, 1, 1, 0], b"ab".to_vec(), vec![1, 2]));
        let (codes, new, utf16) = d.code("bcé".as_bytes(), &[1, 2, 4], &[]).unwrap();
        assert_eq!((codes, new, utf16), (vec![1, 2, 3], "cé".as_bytes().to_vec(), vec![1, 2]));
        assert!(d.code(b"x", &[1], &[true]).is_none());
        assert!(d.gave_up);
    }

    #[test]
    fn many_distinct_values_give_up() {
        let mut d = Dict::default();
        let values: Vec<String> = (0..70_000).map(|i| i.to_string()).collect();
        let bytes = values.concat();
        let ends: Vec<usize> = values.iter().scan(0, |e, v| { *e += v.len(); Some(*e) }).collect();
        assert!(d.code(bytes.as_bytes(), &ends, &[]).is_none());
    }
}
