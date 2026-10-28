use crate::error::{Error, Result};

/// Byte order of the numbers in a file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ByteOrder {
    Little,
    Big,
}

/// Reads numbers and fixed-width fields from a buffer that was read at
/// file offset `base`, reporting errors by file offset.
pub(crate) struct Cursor<'a> {
    buf: &'a [u8],
    pos: usize,
    base: u64,
    pub order: ByteOrder,
}

impl<'a> Cursor<'a> {
    pub fn new(buf: &'a [u8], base: u64, order: ByteOrder) -> Self {
        Cursor { buf, pos: 0, base, order }
    }

    /// File offset of the next byte.
    pub fn offset(&self) -> u64 {
        self.base + self.pos as u64
    }

    pub fn remaining(&self) -> usize {
        self.buf.len() - self.pos
    }

    pub fn bytes(&mut self, n: usize) -> Result<&'a [u8]> {
        if n > self.remaining() {
            return Err(Error::at(self.offset(), "unexpected end of file"));
        }
        let out = &self.buf[self.pos..self.pos + n];
        self.pos += n;
        Ok(out)
    }

    pub fn skip(&mut self, n: usize) -> Result<()> {
        self.bytes(n).map(|_| ())
    }

    /// Consume `tag` exactly, such as `<header>`.
    pub fn tag(&mut self, tag: &str) -> Result<()> {
        let at = self.offset();
        match self.bytes(tag.len()) {
            Ok(b) if b == tag.as_bytes() => Ok(()),
            _ => Err(Error::at(at, format!("expected {tag}"))),
        }
    }

    fn array<const N: usize>(&mut self) -> Result<[u8; N]> {
        let mut a = [0; N];
        a.copy_from_slice(self.bytes(N)?);
        if self.order == ByteOrder::Big {
            a.reverse();
        }
        Ok(a)
    }

    pub fn u8(&mut self) -> Result<u8> {
        Ok(self.bytes(1)?[0])
    }

    pub fn u16(&mut self) -> Result<u16> {
        Ok(u16::from_le_bytes(self.array()?))
    }

    pub fn i16(&mut self) -> Result<i16> {
        Ok(i16::from_le_bytes(self.array()?))
    }

    pub fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.array()?))
    }

    pub fn i32(&mut self) -> Result<i32> {
        Ok(i32::from_le_bytes(self.array()?))
    }

    pub fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.array()?))
    }

    /// An unsigned integer `width` bytes wide (1 to 8).
    pub fn uint(&mut self, width: usize) -> Result<u64> {
        let b = self.bytes(width)?;
        Ok(uint(b, self.order))
    }
}

/// An unsigned integer stored in `b` (1 to 8 bytes) in byte order `order`.
pub(crate) fn uint(b: &[u8], order: ByteOrder) -> u64 {
    let fold = |acc: u64, &x: &u8| (acc << 8) | x as u64;
    match order {
        ByteOrder::Big => b.iter().fold(0, fold),
        ByteOrder::Little => b.iter().rev().fold(0, fold),
    }
}

/// The bytes of a fixed-width text field up to its first NUL.
pub(crate) fn until_nul(b: &[u8]) -> &[u8] {
    match b.iter().position(|&c| c == 0) {
        Some(n) => &b[..n],
        None => b,
    }
}
