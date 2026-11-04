//! The Thrift compact protocol, as far as Parquet's footer and page
//! headers use it.
//!
//! Reading takes untrusted bytes: every length is checked against what is
//! left, nesting is limited, and fields a reader does not know are
//! skipped, so a file from a newer writer still reads.

use dta::{Error, Result};

/// Compact protocol type codes.
pub(crate) const STOP: u8 = 0;
pub(crate) const TRUE: u8 = 1;
pub(crate) const FALSE: u8 = 2;
pub(crate) const BYTE: u8 = 3;
pub(crate) const I16: u8 = 4;
pub(crate) const I32: u8 = 5;
pub(crate) const I64: u8 = 6;
pub(crate) const DOUBLE: u8 = 7;
pub(crate) const BINARY: u8 = 8;
pub(crate) const LIST: u8 = 9;
pub(crate) const SET: u8 = 10;
pub(crate) const MAP: u8 = 11;
pub(crate) const STRUCT: u8 = 12;

/// Deeper nesting than this is damage, not a file: Parquet's own
/// structures nest about six levels.
const MAX_DEPTH: u32 = 64;

/// A reader over Thrift bytes. `base` is the file offset of `buf[0]`, for
/// error messages.
pub(crate) struct In<'a> {
    buf: &'a [u8],
    at: usize,
    depth: u32,
    base: u64,
}

/// Raised when the bytes end inside a structure; a caller that read only
/// part of a page header can read more and try again.
pub(crate) const TRUNCATED: &str = "Thrift data ends early";

impl<'a> In<'a> {
    pub(crate) fn new(buf: &'a [u8], base: u64) -> Self {
        In {
            buf,
            at: 0,
            depth: 0,
            base,
        }
    }

    /// Bytes consumed so far.
    pub(crate) fn position(&self) -> usize {
        self.at
    }

    pub(crate) fn fail(&self, what: &str) -> Error {
        Error::at(self.base + self.at as u64, what.to_string())
    }

    fn byte(&mut self) -> Result<u8> {
        let b = *self.buf.get(self.at).ok_or_else(|| self.fail(TRUNCATED))?;
        self.at += 1;
        Ok(b)
    }

    pub(crate) fn varint(&mut self) -> Result<u64> {
        let mut v = 0u64;
        for shift in (0..70).step_by(7) {
            let b = self.byte()?;
            if shift == 63 && b > 1 {
                return Err(self.fail("Thrift integer too long"));
            }
            v |= u64::from(b & 0x7f) << shift;
            if b & 0x80 == 0 {
                return Ok(v);
            }
        }
        Err(self.fail("Thrift integer too long"))
    }

    pub(crate) fn i64(&mut self) -> Result<i64> {
        let v = self.varint()?;
        Ok((v >> 1) as i64 ^ -((v & 1) as i64))
    }

    pub(crate) fn i32(&mut self) -> Result<i32> {
        let v = self.i64()?;
        i32::try_from(v).map_err(|_| self.fail("Thrift i32 out of range"))
    }

    pub(crate) fn i16(&mut self) -> Result<i16> {
        let v = self.i64()?;
        i16::try_from(v).map_err(|_| self.fail("Thrift i16 out of range"))
    }

    pub(crate) fn i8(&mut self) -> Result<i8> {
        Ok(self.byte()? as i8)
    }

    pub(crate) fn binary(&mut self) -> Result<&'a [u8]> {
        let len = self.varint()?;
        let end = usize::try_from(len)
            .ok()
            .and_then(|l| self.at.checked_add(l))
            .filter(|&e| e <= self.buf.len());
        let end = end.ok_or_else(|| self.fail(TRUNCATED))?;
        let bytes = &self.buf[self.at..end];
        self.at = end;
        Ok(bytes)
    }

    /// Text; bytes that are not UTF-8 are replaced rather than refused,
    /// since names and metadata are only shown.
    pub(crate) fn string(&mut self) -> Result<String> {
        Ok(String::from_utf8_lossy(self.binary()?).into_owned())
    }

    /// A bool field's value is in its type code; in a list it is a byte.
    pub(crate) fn bool(&mut self, ty: u8) -> Result<bool> {
        match ty {
            TRUE => Ok(true),
            FALSE => Ok(false),
            _ => Ok(self.byte()? == TRUE),
        }
    }

    /// The next field's id and type, or `None` at the end of a struct.
    /// `last` is the previous field's id in this struct.
    pub(crate) fn field(&mut self, last: &mut i16) -> Result<Option<(i16, u8)>> {
        let b = self.byte()?;
        if b == STOP {
            return Ok(None);
        }
        let ty = b & 0x0f;
        let delta = b >> 4;
        let id = if delta == 0 {
            self.i16()?
        } else {
            last.checked_add(i16::from(delta))
                .ok_or_else(|| self.fail("bad Thrift field id"))?
        };
        *last = id;
        Ok(Some((id, ty)))
    }

    /// A list or set header: element count and type. The count is
    /// checked against the bytes left (every element takes at least one
    /// byte), so it can size an allocation.
    pub(crate) fn list(&mut self) -> Result<(usize, u8)> {
        let b = self.byte()?;
        let ty = b & 0x0f;
        let n = if b >> 4 == 15 {
            self.varint()?
        } else {
            u64::from(b >> 4)
        };
        let n = usize::try_from(n)
            .ok()
            .filter(|&n| n <= self.buf.len() - self.at)
            .ok_or_else(|| self.fail(TRUNCATED))?;
        Ok((n, ty))
    }

    pub(crate) fn enter(&mut self) -> Result<()> {
        self.depth += 1;
        if self.depth > MAX_DEPTH {
            return Err(self.fail("Thrift data nested too deeply"));
        }
        Ok(())
    }

    pub(crate) fn leave(&mut self) {
        self.depth -= 1;
    }

    /// Skip a value of type `ty`.
    pub(crate) fn skip(&mut self, ty: u8) -> Result<()> {
        match ty {
            TRUE | FALSE => Ok(()),
            BYTE => self.byte().map(drop),
            I16 | I32 | I64 => self.varint().map(drop),
            DOUBLE => {
                if self.buf.len() - self.at < 8 {
                    return Err(self.fail(TRUNCATED));
                }
                self.at += 8;
                Ok(())
            }
            BINARY => self.binary().map(drop),
            LIST | SET => {
                let (n, elem) = self.list()?;
                self.enter()?;
                for _ in 0..n {
                    self.skip_element(elem)?;
                }
                self.leave();
                Ok(())
            }
            MAP => {
                let n = self.varint()?;
                if n == 0 {
                    return Ok(());
                }
                if n > (self.buf.len() - self.at) as u64 {
                    return Err(self.fail(TRUNCATED));
                }
                let kinds = self.byte()?;
                self.enter()?;
                for _ in 0..n {
                    self.skip_element(kinds >> 4)?;
                    self.skip_element(kinds & 0x0f)?;
                }
                self.leave();
                Ok(())
            }
            STRUCT => self.skip_struct(),
            _ => Err(self.fail("bad Thrift type")),
        }
    }

    /// Booleans inside containers take a byte each.
    fn skip_element(&mut self, ty: u8) -> Result<()> {
        if ty == TRUE || ty == FALSE {
            return self.byte().map(drop);
        }
        self.skip(ty)
    }

    pub(crate) fn skip_struct(&mut self) -> Result<()> {
        self.enter()?;
        let mut last = 0;
        while let Some((_, ty)) = self.field(&mut last)? {
            self.skip(ty)?;
        }
        self.leave();
        Ok(())
    }

    /// Read a struct field by field: `f` handles the fields it knows and
    /// returns `false` for the others, which are skipped.
    pub(crate) fn read_struct(
        &mut self,
        mut f: impl FnMut(&mut Self, i16, u8) -> Result<bool>,
    ) -> Result<()> {
        self.enter()?;
        let mut last = 0;
        while let Some((id, ty)) = self.field(&mut last)? {
            if !f(self, id, ty)? {
                self.skip(ty)?;
            }
        }
        self.leave();
        Ok(())
    }

    /// Read a list whose elements `f` reads.
    pub(crate) fn read_list<T>(
        &mut self,
        mut f: impl FnMut(&mut Self, u8) -> Result<T>,
    ) -> Result<Vec<T>> {
        let (n, ty) = self.list()?;
        self.enter()?;
        // `n` is at most the bytes left, but each element may be far
        // larger in memory than its one byte: let the vector grow as
        // elements are read instead.
        let mut out = Vec::with_capacity(n.min(1024));
        for _ in 0..n {
            out.push(f(self, ty)?);
        }
        self.leave();
        Ok(out)
    }
}

/// A writer of Thrift compact bytes.
#[derive(Default)]
pub(crate) struct Out {
    pub(crate) buf: Vec<u8>,
    /// The last field id written in each open struct.
    last: Vec<i16>,
}

impl Out {
    pub(crate) fn new() -> Self {
        Out {
            buf: Vec::new(),
            last: vec![0],
        }
    }

    pub(crate) fn varint(&mut self, mut v: u64) {
        while v >= 0x80 {
            self.buf.push(v as u8 | 0x80);
            v >>= 7;
        }
        self.buf.push(v as u8);
    }

    fn zigzag(&mut self, v: i64) {
        self.varint(((v << 1) ^ (v >> 63)) as u64);
    }

    fn header(&mut self, id: i16, ty: u8) {
        let last = *self.last.last().expect("a struct is open");
        let delta = id - last;
        if (1..=15).contains(&delta) {
            self.buf.push((delta as u8) << 4 | ty);
        } else {
            self.buf.push(ty);
            self.zigzag(i64::from(id));
        }
        *self.last.last_mut().expect("a struct is open") = id;
    }

    pub(crate) fn i32(&mut self, id: i16, v: i32) {
        self.header(id, I32);
        self.zigzag(i64::from(v));
    }

    pub(crate) fn i16(&mut self, id: i16, v: i16) {
        self.header(id, I16);
        self.zigzag(i64::from(v));
    }

    pub(crate) fn i64(&mut self, id: i16, v: i64) {
        self.header(id, I64);
        self.zigzag(v);
    }

    pub(crate) fn i8(&mut self, id: i16, v: i8) {
        self.header(id, BYTE);
        self.buf.push(v as u8);
    }

    pub(crate) fn bool(&mut self, id: i16, v: bool) {
        self.header(id, if v { TRUE } else { FALSE });
    }

    pub(crate) fn binary(&mut self, id: i16, v: &[u8]) {
        self.header(id, BINARY);
        self.binary_value(v);
    }

    pub(crate) fn binary_value(&mut self, v: &[u8]) {
        self.varint(v.len() as u64);
        self.buf.extend_from_slice(v);
    }

    pub(crate) fn i32_value(&mut self, v: i32) {
        self.zigzag(i64::from(v));
    }

    #[cfg(test)]
    pub(crate) fn i64_value(&mut self, v: i64) {
        self.zigzag(v);
    }

    /// Open a struct as field `id`; `None` opens a struct that is a list
    /// element or the top level.
    pub(crate) fn begin(&mut self, id: Option<i16>) {
        if let Some(id) = id {
            self.header(id, STRUCT);
        }
        self.last.push(0);
    }

    pub(crate) fn end(&mut self) {
        self.buf.push(STOP);
        self.last.pop();
    }

    pub(crate) fn list(&mut self, id: i16, elem: u8, n: usize) {
        self.header(id, LIST);
        self.list_header(elem, n);
    }

    pub(crate) fn list_header(&mut self, elem: u8, n: usize) {
        if n < 15 {
            self.buf.push((n as u8) << 4 | elem);
        } else {
            self.buf.push(0xf0 | elem);
            self.varint(n as u64);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn integers_round_trip() {
        for v in [0i64, 1, -1, 63, -64, 64, 1 << 40, i64::MAX, i64::MIN] {
            let mut o = Out::new();
            o.begin(None);
            o.i64(1, v);
            o.end();
            let mut i = In::new(&o.buf, 0);
            let mut got = None;
            i.read_struct(|i, id, ty| {
                assert_eq!((id, ty), (1, I64));
                got = Some(i.i64()?);
                Ok(true)
            })
            .unwrap();
            assert_eq!(got, Some(v));
        }
    }

    #[test]
    fn field_ids_use_deltas_and_long_form() {
        let mut o = Out::new();
        o.begin(None);
        o.i32(1, 7);
        o.i32(16, 8); // delta 15: short form
        o.i32(40, 9); // delta 24: long form
        o.i32(3, 10); // going back: long form
        o.end();
        assert_eq!(o.buf[0], 0x15);
        assert_eq!(o.buf[2], 0xf5);
        let mut i = In::new(&o.buf, 0);
        let mut seen = Vec::new();
        i.read_struct(|i, id, _| {
            seen.push((id, i.i32()?));
            Ok(true)
        })
        .unwrap();
        assert_eq!(seen, vec![(1, 7), (16, 8), (40, 9), (3, 10)]);
    }

    #[test]
    fn unknown_fields_of_every_type_are_skipped() {
        let mut o = Out::new();
        o.begin(None);
        o.bool(1, true);
        o.i8(2, -3);
        o.binary(3, b"skip me");
        o.list(4, I32, 20);
        for k in 0..20 {
            o.i32_value(k);
        }
        o.begin(Some(5));
        o.i64(1, 99);
        o.list(2, STRUCT, 1);
        o.begin(None);
        o.end();
        o.end();
        // A double and a map, written by hand.
        o.buf.push(0x17); // field 6, double
        o.buf.extend_from_slice(&1.5f64.to_le_bytes());
        o.buf.push(0x1b); // field 7, map
        o.varint(1);
        o.buf.push((BINARY << 4) | I32);
        o.binary_value(b"k");
        o.i32_value(4);
        // Field 8 (delta 1 from the hand-written field 7), i32 42.
        o.buf.push(0x15);
        o.i32_value(42);
        o.end();
        let mut i = In::new(&o.buf, 0);
        let mut got = None;
        i.read_struct(|i, id, _| {
            if id == 8 {
                got = Some(i.i32()?);
                return Ok(true);
            }
            Ok(false)
        })
        .unwrap();
        assert_eq!(got, Some(42));
        assert_eq!(i.position(), o.buf.len());
    }

    #[test]
    fn damage_is_an_error_not_a_panic() {
        // A binary longer than the buffer.
        let mut i = In::new(&[0x18, 0xff, 0x01, b'a'], 100);
        let e = i.read_struct(|_, _, _| Ok(false)).unwrap_err();
        assert!(e.message.contains(TRUNCATED));
        assert_eq!(e.offset, Some(103));
        // A list claiming more elements than there are bytes.
        let mut i = In::new(&[0x19, 0xf5, 0xff, 0xff, 0x03], 0);
        assert!(i.read_struct(|_, _, _| Ok(false)).is_err());
        // Deep nesting.
        let deep = vec![0x1c; 1000];
        assert!(In::new(&deep, 0)
            .read_struct(|_, _, _| Ok(false))
            .unwrap_err()
            .message
            .contains("deeply"));
        // A varint that never ends.
        let mut i = In::new(&[0xff; 20], 0);
        assert!(i.varint().is_err());
        // Bad type code.
        assert!(In::new(&[0x1d], 0)
            .read_struct(|_, _, _| Ok(false))
            .is_err());
        // Every prefix of a valid struct fails cleanly.
        let mut o = Out::new();
        o.begin(None);
        o.binary(1, b"hello");
        o.list(2, I64, 3);
        for k in 0..3 {
            o.i64_value(k);
        }
        o.end();
        for n in 0..o.buf.len() {
            assert!(In::new(&o.buf[..n], 0)
                .read_struct(|_, _, _| Ok(false))
                .is_err());
        }
    }
}
