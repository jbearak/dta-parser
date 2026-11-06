//! The digest of a finished column (plan 0019, "Letters" under
//! `save_parquet`): datakit computes it for each column that has a
//! `meta.missing` entry when it reads, and again when it saves, to see
//! that the column's rows are as they were read.
//!
//! Each row adds its null flag and, for a value, a form that is the same
//! across lossless casts and different for different values: an integer,
//! or a float that is a whole number within ±2^127, as its exact integer;
//! any other float as the bits of its value as a double (a float32
//! widened first; every NaN one pattern); a date as its day count; a
//! datetime as its count of nanoseconds in 128 bits; text, and an Enum's
//! or Categorical's values, as their UTF-8 bytes.

use pyo3::prelude::*;

use super::ffi::{import_stream, ArrayRef, InField};
use crate::fail;

/// Mixes words into a 64-bit state; order matters.
struct Hasher(u64);

impl Hasher {
    #[inline]
    fn word(&mut self, x: u64) {
        // splitmix64's finaliser on the word, then a multiply-rotate step.
        let mut z = x.wrapping_add(0x9E37_79B9_7F4A_7C15);
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^= z >> 31;
        self.0 = (self.0.rotate_left(23) ^ z).wrapping_mul(0x51_7C_C1_B7_27_22_0A_95);
    }

    #[inline]
    fn null(&mut self) {
        self.word(0x6E75_6C6C);
    }

    #[inline]
    fn integer(&mut self, v: i128) {
        self.word(1);
        self.word(v as u64);
        self.word((v >> 64) as u64);
    }

    #[inline]
    fn float(&mut self, x: f64) {
        const LIMIT: f64 = 170_141_183_460_469_231_731_687_303_715_884_105_728.0; // 2^127
        if x.is_finite() && x.fract() == 0.0 && x.abs() < LIMIT {
            self.integer(x as i128);
        } else {
            self.word(2);
            self.word(if x.is_nan() { 0x7FF8_0000_0000_0000 } else { x.to_bits() });
        }
    }

    #[inline]
    fn bytes(&mut self, b: &[u8]) {
        self.word(3);
        self.word(b.len() as u64);
        let mut chunks = b.chunks_exact(8);
        for c in &mut chunks {
            self.word(u64::from_le_bytes(c.try_into().expect("8 bytes")));
        }
        let mut last = [0u8; 8];
        last[..chunks.remainder().len()].copy_from_slice(chunks.remainder());
        self.word(u64::from_le_bytes(last));
    }
}

/// Whether row `i` (counting the array's offset) has a value.
#[inline]
pub(crate) fn valid(a: &ArrayRef, i: usize) -> bool {
    let v = a.buffer(0);
    v == 0 || a.null_count() == 0 || unsafe { (*(v as *const u8).add(i / 8) >> (i % 8)) & 1 == 1 }
}

/// The bytes of row `i` of a string array (`u`, `U`, `vu` and the binary
/// ones), counting its offset.
///
/// # Safety
/// The array's buffers are of the format given.
pub(crate) unsafe fn text_at<'a>(a: &ArrayRef<'a>, format: &str, i: usize) -> &'a [u8] {
    match format {
        "u" | "z" => {
            let o = a.buffer(1) as *const i32;
            let (s, e) = (*o.add(i) as usize, *o.add(i + 1) as usize);
            std::slice::from_raw_parts((a.buffer(2) as *const u8).add(s), e - s)
        }
        "U" | "Z" => {
            let o = a.buffer(1) as *const i64;
            let (s, e) = (*o.add(i) as usize, *o.add(i + 1) as usize);
            std::slice::from_raw_parts((a.buffer(2) as *const u8).add(s), e - s)
        }
        _ => {
            // A view: 16 bytes, inline up to 12.
            let v = (a.buffer(1) as *const u8).add(16 * i);
            let len = u32::from_le_bytes(std::ptr::read_unaligned(v as *const [u8; 4])) as usize;
            if len <= 12 {
                std::slice::from_raw_parts(v.add(4), len)
            } else {
                let buf = u32::from_le_bytes(std::ptr::read_unaligned(v.add(8) as *const [u8; 4])) as usize;
                let off = u32::from_le_bytes(std::ptr::read_unaligned(v.add(12) as *const [u8; 4])) as usize;
                std::slice::from_raw_parts((a.buffer(2 + buf) as *const u8).add(off), len)
            }
        }
    }
}

/// A dictionary array's key at row `i`.
///
/// # Safety
/// The keys buffer holds row `i` in `format`.
pub(crate) unsafe fn key_at(a: &ArrayRef, format: &str, i: usize) -> Option<usize> {
    let p = a.buffer(1);
    Some(match format {
        "C" => *(p as *const u8).add(i) as usize,
        "c" => usize::try_from(*(p as *const i8).add(i)).ok()?,
        "S" => *(p as *const u16).add(i) as usize,
        "s" => usize::try_from(*(p as *const i16).add(i)).ok()?,
        "I" => *(p as *const u32).add(i) as usize,
        "i" => usize::try_from(*(p as *const i32).add(i)).ok()?,
        "L" => usize::try_from(*(p as *const u64).add(i)).ok()?,
        "l" => usize::try_from(*(p as *const i64).add(i)).ok()?,
        _ => return None,
    })
}

/// Nanoseconds per unit of a `ts` or `tt` format's unit letter.
pub(crate) fn per_unit(c: u8) -> Option<i128> {
    Some(match c {
        b's' => 1_000_000_000,
        b'm' => 1_000_000,
        b'u' => 1_000,
        b'n' => 1,
        _ => return None,
    })
}

/// Hash `a`'s rows; `extra` is its parent's offset, which a struct's
/// children share.
fn hash_array(h: &mut Hasher, field: &InField, a: &ArrayRef, extra: usize) -> PyResult<()> {
    let f = field.format.as_str();
    let (off, n) = (a.offset() + extra, a.len());
    macro_rules! ints {
        ($t:ty) => {{
            let p = a.buffer(1) as *const $t;
            for i in off..off + n {
                if valid(a, i) {
                    h.integer(unsafe { *p.add(i) } as i128);
                } else {
                    h.null();
                }
            }
        }};
    }
    match f {
        "c" => ints!(i8),
        "s" => ints!(i16),
        "i" | "tdD" => ints!(i32),
        "l" => ints!(i64),
        "C" if field.dictionary.is_none() => ints!(u8),
        "S" if field.dictionary.is_none() => ints!(u16),
        "I" if field.dictionary.is_none() => ints!(u32),
        "L" if field.dictionary.is_none() => ints!(u64),
        "b" => {
            let p = a.buffer(1) as *const u8;
            for i in off..off + n {
                if valid(a, i) {
                    h.integer(i128::from(unsafe { (*p.add(i / 8) >> (i % 8)) & 1 }));
                } else {
                    h.null();
                }
            }
        }
        "f" | "g" => {
            for i in off..off + n {
                if !valid(a, i) {
                    h.null();
                    continue;
                }
                let x = unsafe {
                    if f == "f" {
                        f64::from(*(a.buffer(1) as *const f32).add(i))
                    } else {
                        *(a.buffer(1) as *const f64).add(i)
                    }
                };
                h.float(x);
            }
        }
        "n" => (0..n).for_each(|_| h.null()),
        "u" | "U" | "vu" | "z" | "Z" | "vz" => {
            for i in off..off + n {
                if valid(a, i) {
                    h.bytes(unsafe { text_at(a, f, i) });
                } else {
                    h.null();
                }
            }
        }
        _ if f.starts_with("ts") || f.starts_with("tt") => {
            let scale = per_unit(f.as_bytes().get(2).copied().unwrap_or(0))
                .ok_or_else(|| fail(format!("a digest of Arrow type {f} is not made")))?;
            let narrow = f == "tts" || f == "ttm";
            for i in off..off + n {
                if !valid(a, i) {
                    h.null();
                    continue;
                }
                let v = unsafe {
                    if narrow {
                        i128::from(*(a.buffer(1) as *const i32).add(i))
                    } else {
                        i128::from(*(a.buffer(1) as *const i64).add(i))
                    }
                };
                h.integer(v * scale);
            }
        }
        _ => {
            let Some(dict_field) = field.dictionary.as_deref() else {
                return Err(fail(format!("a digest of Arrow type {f} is not made")));
            };
            let d = a.dictionary().ok_or_else(|| fail("a dictionary array without its dictionary"))?;
            let df = dict_field.format.as_str();
            if !matches!(df, "u" | "U" | "vu") {
                return Err(fail(format!("a digest of a dictionary of {df} is not made")));
            }
            for i in off..off + n {
                if !valid(a, i) {
                    h.null();
                    continue;
                }
                let k = unsafe { key_at(a, f, i) }.ok_or_else(|| fail("a negative dictionary key"))?;
                if k >= d.len() {
                    return Err(fail("a dictionary key past its dictionary"));
                }
                h.bytes(unsafe { text_at(&d, df, d.offset() + k) });
            }
        }
    }
    Ok(())
}

/// The digest of a column: any object with `__arrow_c_stream__` (a
/// polars Series) of one column. For datakit only.
#[pyfunction]
pub fn arrow_digest(column: &Bound<'_, PyAny>) -> PyResult<u64> {
    let imported = import_stream(column)?;
    // A frame's stream is a struct of one column; a Series' may be the
    // column itself.
    let (field, child) = if imported.schema.format == "+s" {
        if imported.schema.children.len() != 1 {
            return Err(fail("a digest is of one column"));
        }
        (&imported.schema.children[0], true)
    } else {
        (&imported.schema, false)
    };
    let mut h = Hasher(0x6474_615F_6469_6731);
    let mut rows = 0u64;
    for b in &imported.batches {
        let top = b.get();
        let (a, extra) = if child {
            (top.child(0).ok_or_else(|| fail("a batch without its column"))?, top.offset())
        } else {
            (top, 0)
        };
        let n = if child { top.len() } else { a.len() };
        rows += n as u64;
        hash_array(&mut h, field, &a, extra)?;
    }
    h.word(rows);
    Ok(h.0)
}
