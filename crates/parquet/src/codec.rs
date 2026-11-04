//! Page compression: none, snappy, gzip, zstd and lz4_raw, and brotli
//! on read.
//!
//! zstd goes through C libzstd on native targets and the pure-Rust
//! `ruzstd` in wasm, where C would need a wasm32 C toolchain
//! (docs/research/parquet-codecs.md).

use crate::format::Codec;
#[cfg(not(target_arch = "wasm32"))]
use dta::ErrorKind;
use dta::{Error, Result};

/// A codec to write pages with.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Compression {
    None,
    Snappy,
    /// Levels 0 to 10; 6 by default.
    Gzip,
    /// Levels 1 to 22 (and negative levels for speed); 3 by default. In
    /// wasm, `ruzstd` has one level and the level is ignored.
    Zstd,
    Lz4Raw,
}

impl Compression {
    /// The codec of a name: `none` (or `uncompressed`), `snappy`, `gzip`,
    /// `zstd` or `lz4_raw` (or `lz4`), in any case.
    pub fn from_name(name: &str) -> Result<Self> {
        match name.to_ascii_lowercase().as_str() {
            "none" | "uncompressed" => Ok(Compression::None),
            "snappy" => Ok(Compression::Snappy),
            "gzip" => Ok(Compression::Gzip),
            "zstd" => Ok(Compression::Zstd),
            "lz4_raw" | "lz4" => Ok(Compression::Lz4Raw),
            _ => Err(Error::invalid(format!(
                "unknown compression \"{name}\"; use one of \"zstd\", \"snappy\", \"gzip\", \"lz4_raw\" or \"none\""
            ))),
        }
    }

    pub(crate) fn codec(self) -> Codec {
        match self {
            Compression::None => Codec::Uncompressed,
            Compression::Snappy => Codec::Snappy,
            Compression::Gzip => Codec::Gzip,
            Compression::Zstd => Codec::Zstd,
            Compression::Lz4Raw => Codec::Lz4Raw,
        }
    }

    /// Check a level given for this codec, and return the one to use.
    pub(crate) fn level(self, level: Option<i32>) -> Result<i32> {
        match (self, level) {
            (Compression::Zstd, None) => Ok(3),
            (Compression::Zstd, Some(l)) if (-131072..=22).contains(&l) && l != 0 => Ok(l),
            (Compression::Gzip, None) => Ok(6),
            (Compression::Gzip, Some(l)) if (0..=10).contains(&l) => Ok(l),
            (_, None) => Ok(0),
            (Compression::Zstd, Some(l)) => Err(Error::invalid(format!(
                "zstd levels run from 1 to 22, not {l}"
            ))),
            (Compression::Gzip, Some(l)) => Err(Error::invalid(format!(
                "gzip levels run from 0 to 10, not {l}"
            ))),
            (c, Some(_)) => Err(Error::invalid(format!(
                "{} has no compression levels",
                c.codec().name().to_lowercase()
            ))),
        }
    }
}

/// Codec state kept between pages by one thread, so contexts are made
/// once per read or write, not once per page.
#[derive(Default)]
pub(crate) struct Codecs {
    #[cfg(not(target_arch = "wasm32"))]
    zstd_in: Option<zstd::zstd_safe::DCtx<'static>>,
    #[cfg(not(target_arch = "wasm32"))]
    zstd_out: Option<(i32, zstd::bulk::Compressor<'static>)>,
    #[cfg(target_arch = "wasm32")]
    zstd_in: Option<ruzstd::decoding::FrameDecoder>,
}

/// The most bytes snappy can make of each compressed byte: a copy of 64
/// bytes takes a 3-byte element.
const SNAPPY_MAX_RATIO: usize = 22;
/// The same for an LZ4 block: each extra length byte adds at most 255.
const LZ4_MAX_RATIO: usize = 255;
/// gzip and zstd can expand far more than these, so their output buffer
/// starts at no more than this many bytes per compressed byte, or
/// [`FIRST_FLOOR`], and grows only as they produce output.
const FIRST_RATIO: usize = 16;
const FIRST_FLOOR: usize = 1 << 20;

/// The first output buffer for gzip or zstd data.
fn first_size(input: &[u8], declared: usize) -> usize {
    declared.min(input.len().saturating_mul(FIRST_RATIO).max(FIRST_FLOOR))
}

/// Make `out` `n` bytes long, refusing rather than aborting when the
/// memory is not there.
fn grow(out: &mut Vec<u8>, n: usize) -> Result<()> {
    if n > out.len() && out.try_reserve(n - out.len()).is_err() {
        return Err(
            Error::new(format!("a page of {n} bytes does not fit in memory here"))
                .of(dta::ErrorKind::TooLarge),
        );
    }
    out.resize(n, 0);
    Ok(())
}

/// An error for a page whose header gives more bytes than its compressed
/// bytes can make.
fn cannot_hold(name: &str, declared: usize, input: usize) -> Error {
    Error::new(format!(
        "{name}: a page's header says it holds {declared} bytes, more than its {input} compressed bytes can"
    ))
}

impl Codecs {
    /// Decompress `input` into `out` (replacing what it held), which must
    /// make exactly `declared` bytes, the size the page header gives; a
    /// different size is an error. `out` is never made larger than what
    /// `input` can produce, so a header cannot ask for memory alone.
    pub(crate) fn decompress(
        &mut self,
        codec: Codec,
        input: &[u8],
        declared: usize,
        out: &mut Vec<u8>,
    ) -> Result<()> {
        out.clear();
        match codec {
            Codec::Uncompressed => {
                if input.len() != declared {
                    return Err(Error::new("an uncompressed page's sizes differ"));
                }
                grow(out, 0)?;
                out.extend_from_slice(input);
            }
            Codec::Snappy => {
                let len = snap::raw::decompress_len(input)
                    .map_err(|e| Error::new(format!("snappy: {e}")))?;
                if len != declared {
                    return Err(Error::new(format!(
                        "snappy data holds {len} bytes, not the {declared} the page header says"
                    )));
                }
                if len > input.len().saturating_mul(SNAPPY_MAX_RATIO) {
                    return Err(cannot_hold("snappy", len, input.len()));
                }
                grow(out, len)?;
                let n = snap::raw::Decoder::new()
                    .decompress(input, out)
                    .map_err(|e| Error::new(format!("snappy: {e}")))?;
                out.truncate(n);
            }
            Codec::Gzip => gunzip(input, declared, out)?,
            Codec::Brotli => unbrotli(input, declared, out)?,
            Codec::Zstd => self.unzstd(input, declared, out)?,
            Codec::Lz4Raw => {
                if declared > input.len().saturating_mul(LZ4_MAX_RATIO) {
                    return Err(cannot_hold("lz4_raw", declared, input.len()));
                }
                grow(out, declared)?;
                let n = lz4_flex::block::decompress_into(input, out)
                    .map_err(|e| Error::new(format!("lz4_raw: {e}")))?;
                out.truncate(n);
            }
            other => return Err(unsupported(other)),
        }
        if out.len() != declared {
            return Err(Error::new(format!(
                "a page decompressed to {} bytes, not the {declared} its header says",
                out.len()
            )));
        }
        Ok(())
    }

    /// zstd can expand a few bytes into very many, so decompress into a
    /// buffer sized by the input and, when that is too small, try again
    /// with one twice as large, up to `declared`.
    #[cfg(not(target_arch = "wasm32"))]
    fn unzstd(&mut self, input: &[u8], declared: usize, out: &mut Vec<u8>) -> Result<()> {
        use zstd::zstd_safe;
        use zstd_safe::zstd_sys::{ZSTD_ErrorCode, ZSTD_getErrorCode};
        let d = match &mut self.zstd_in {
            Some(d) => d,
            None => self
                .zstd_in
                .insert(zstd_safe::DCtx::try_create().ok_or_else(|| {
                    Error::new("zstd: no memory for a decompression context")
                        .of(ErrorKind::TooLarge)
                })?),
        };
        let mut size = first_size(input, declared);
        loop {
            grow(out, size)?;
            match d.decompress(&mut out[..], input) {
                Ok(n) => {
                    out.truncate(n);
                    return Ok(());
                }
                Err(code) => {
                    // SAFETY: ZSTD_getErrorCode only reads its argument.
                    let small = unsafe { ZSTD_getErrorCode(code) }
                        == ZSTD_ErrorCode::ZSTD_error_dstSize_tooSmall;
                    if !small {
                        return Err(Error::new(format!(
                            "zstd: {}",
                            zstd_safe::get_error_name(code)
                        )));
                    }
                    if size >= declared {
                        return Err(Error::new(
                            "zstd: data holds more bytes than the page header says",
                        ));
                    }
                    size = size.saturating_mul(2).min(declared);
                }
            }
        }
    }

    /// Decode block by block, growing `out` only as bytes come, and
    /// stopping once they pass `declared`.
    #[cfg(target_arch = "wasm32")]
    fn unzstd(&mut self, input: &[u8], declared: usize, out: &mut Vec<u8>) -> Result<()> {
        use ruzstd::decoding::BlockDecodingStrategy;
        use ruzstd::io::Read as _;
        let bad = |e: &dyn std::fmt::Display| Error::new(format!("zstd: {e}"));
        let d = self
            .zstd_in
            .get_or_insert_with(ruzstd::decoding::FrameDecoder::new);
        let mut input = input;
        let mut written = 0;
        grow(out, first_size(input, declared))?;
        while !input.is_empty() {
            match d.init(&mut input) {
                Ok(()) => {}
                Err(ruzstd::decoding::errors::FrameDecoderError::ReadFrameHeaderError(
                    ruzstd::decoding::errors::ReadFrameHeaderError::SkipFrame { length, .. },
                )) => {
                    input = usize::try_from(length)
                        .ok()
                        .and_then(|l| input.get(l..))
                        .ok_or_else(|| Error::new("zstd: a skippable frame runs past the page"))?;
                    continue;
                }
                Err(e) => return Err(bad(&e)),
            }
            loop {
                d.decode_blocks(&mut input, BlockDecodingStrategy::UptoBytes(1 << 20))
                    .map_err(|e| bad(&e))?;
                while d.can_collect() > 0 {
                    if written == out.len() {
                        if written >= declared {
                            return Err(Error::new(
                                "zstd: data holds more bytes than the page header says",
                            ));
                        }
                        grow(out, written.saturating_mul(2).max(1).min(declared))?;
                    }
                    written += d.read(&mut out[written..]).map_err(|e| bad(&e))?;
                }
                if d.is_finished() {
                    break;
                }
            }
        }
        out.truncate(written);
        Ok(())
    }

    /// Compress `input` onto the end of `out`.
    pub(crate) fn compress(
        &mut self,
        c: Compression,
        level: i32,
        input: &[u8],
        out: &mut Vec<u8>,
    ) -> Result<()> {
        match c {
            Compression::None => out.extend_from_slice(input),
            Compression::Snappy => {
                let start = out.len();
                out.resize(start + snap::raw::max_compress_len(input.len()), 0);
                let n = snap::raw::Encoder::new()
                    .compress(input, &mut out[start..])
                    .map_err(|e| Error::new(format!("snappy: {e}")))?;
                out.truncate(start + n);
            }
            Compression::Gzip => gzip(input, level, out),
            Compression::Zstd => self.zstd(input, level, out)?,
            Compression::Lz4Raw => {
                let start = out.len();
                out.resize(
                    start + lz4_flex::block::get_maximum_output_size(input.len()),
                    0,
                );
                let n = lz4_flex::block::compress_into(input, &mut out[start..])
                    .map_err(|e| Error::new(format!("lz4_raw: {e}")))?;
                out.truncate(start + n);
            }
        }
        Ok(())
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn zstd(&mut self, input: &[u8], level: i32, out: &mut Vec<u8>) -> Result<()> {
        if self.zstd_out.as_ref().is_none_or(|(l, _)| *l != level) {
            self.zstd_out = Some((level, zstd::bulk::Compressor::new(level)?));
        }
        let (_, c) = self.zstd_out.as_mut().expect("made above");
        let start = out.len();
        out.resize(start + zstd::zstd_safe::compress_bound(input.len()), 0);
        let n = c
            .compress_to_buffer(input, &mut out[start..])
            .map_err(|e| Error::new(format!("zstd: {e}")).of(ErrorKind::Internal))?;
        out.truncate(start + n);
        Ok(())
    }

    #[cfg(target_arch = "wasm32")]
    fn zstd(&mut self, input: &[u8], _level: i32, out: &mut Vec<u8>) -> Result<()> {
        // ruzstd 0.8 implements only its fastest level.
        out.extend_from_slice(&ruzstd::encoding::compress_to_vec(
            input,
            ruzstd::encoding::CompressionLevel::Fastest,
        ));
        Ok(())
    }
}

pub(crate) fn unsupported(codec: Codec) -> Error {
    let what = match codec {
        Codec::Lzo => "LZO compression is not supported".to_string(),
        Codec::Lz4 => "the Hadoop framing of LZ4 is not supported (LZ4_RAW is)".to_string(),
        other => format!("{} is not supported", other.name()),
    };
    Error::new(what)
}

// ---- brotli ----

/// Decompress a brotli stream into `out` (which starts empty), growing it
/// as bytes come, to no more than `declared` bytes.
fn unbrotli(input: &[u8], declared: usize, out: &mut Vec<u8>) -> Result<()> {
    use std::io::Read;
    // The decoder sizes its window from the first block's length: check
    // that first, so that a header alone cannot ask for 16 MiB.
    if let Some(len) = brotli_first_block(input) {
        if len > declared {
            return Err(Error::new(format!(
                "brotli: a block of {len} bytes, more than the {declared} the page header says"
            )));
        }
    }
    let bad = |e: std::io::Error| Error::new(format!("brotli: {e}"));
    let mut d = brotli_decompressor::Decompressor::new(input, 4096);
    let mut written = 0;
    grow(out, first_size(input, declared))?;
    loop {
        if written == out.len() {
            if written >= declared {
                // Full: anything more is too much.
                let mut extra = [0u8; 1];
                if d.read(&mut extra).map_err(bad)? != 0 {
                    return Err(Error::new(
                        "brotli: data holds more bytes than the page header says",
                    ));
                }
                break;
            }
            grow(out, written.saturating_mul(2).max(1).min(declared))?;
        }
        let n = d.read(&mut out[written..]).map_err(bad)?;
        if n == 0 {
            break;
        }
        written += n;
    }
    out.truncate(written);
    Ok(())
}

/// The length the first meta-block header of a brotli stream gives
/// (RFC 7932, section 9.2), if it has one: `None` for an empty stream, a
/// metadata block or too few bytes.
fn brotli_first_block(input: &[u8]) -> Option<usize> {
    let mut bit = 0usize;
    let mut take = |n: usize| -> Option<usize> {
        let mut v = 0;
        for k in 0..n {
            let b = (*input.get((bit + k) / 8)? >> ((bit + k) % 8)) & 1;
            v |= usize::from(b) << k;
        }
        bit += n;
        Some(v)
    };
    // WBITS: 1, 4 or 7 bits.
    if take(1)? == 1 && take(3)? == 0 {
        take(3)?;
    }
    // ISLAST, then ISLASTEMPTY if set.
    if take(1)? == 1 && take(1)? == 1 {
        return None;
    }
    let nibbles = match take(2)? {
        3 => return None,
        n => 4 + n,
    };
    Some(take(4 * nibbles)? + 1)
}

// ---- gzip ----

const GZIP_MAGIC: [u8; 2] = [0x1f, 0x8b];

fn gzip(input: &[u8], level: i32, out: &mut Vec<u8>) {
    // Header: magic, deflate, no flags, no time, no extra flags, unknown OS.
    out.extend_from_slice(&[0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 255]);
    out.extend_from_slice(&miniz_oxide::deflate::compress_to_vec(
        input,
        level.clamp(0, 10) as u8,
    ));
    out.extend_from_slice(&crc32(input).to_le_bytes());
    out.extend_from_slice(&(input.len() as u32).to_le_bytes());
}

/// Inflate one or more gzip members into `out` (which starts empty),
/// growing it as bytes come, to no more than `declared` bytes.
fn gunzip(input: &[u8], declared: usize, out: &mut Vec<u8>) -> Result<()> {
    use miniz_oxide::inflate::core::{decompress, inflate_flags, DecompressorOxide};
    use miniz_oxide::inflate::TINFLStatus;
    let bad = |what: &str| Error::new(format!("gzip: {what}"));
    let mut at = 0;
    let mut written = 0;
    grow(out, first_size(input, declared))?;
    while at < input.len() {
        let h = &input[at..];
        if h.len() < 10 || h[..2] != GZIP_MAGIC || h[2] != 8 {
            return Err(bad("bad header"));
        }
        let flags = h[3];
        let mut p = 10;
        if flags & 4 != 0 {
            let n = h.get(p..p + 2).ok_or_else(|| bad("header ends early"))?;
            p += 2 + usize::from(u16::from_le_bytes([n[0], n[1]]));
        }
        for bit in [8u8, 16] {
            if flags & bit != 0 {
                let end = h
                    .get(p..)
                    .and_then(|r| r.iter().position(|&b| b == 0))
                    .ok_or_else(|| bad("header ends early"))?;
                p += end + 1;
            }
        }
        if flags & 2 != 0 {
            p += 2;
        }
        let body = h.get(p..).ok_or_else(|| bad("header ends early"))?;
        let mut state = DecompressorOxide::new();
        // The member's output is out[start..]; a back-reference may reach
        // only that far back.
        let start = written;
        let mut used = 0;
        loop {
            let (status, read, n) = decompress(
                &mut state,
                &body[used..],
                &mut out[start..],
                written - start,
                inflate_flags::TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF,
            );
            used += read;
            written += n;
            match status {
                TINFLStatus::Done => break,
                TINFLStatus::HasMoreOutput => {
                    if out.len() >= declared {
                        return Err(bad("data holds more bytes than the page header says"));
                    }
                    grow(out, out.len().saturating_mul(2).max(1).min(declared))?;
                }
                _ => return Err(bad(&format!("{status:?}"))),
            }
        }
        let trailer = body
            .get(used..)
            .and_then(|t| t.get(..8))
            .ok_or_else(|| bad("trailer missing"))?;
        let size = u32::from_le_bytes(trailer[4..8].try_into().expect("4 bytes"));
        if size != (written - start) as u32 {
            return Err(bad("member length does not match its trailer"));
        }
        at += p + used + 8;
    }
    out.truncate(written);
    Ok(())
}

/// CRC-32 (IEEE), for the gzip trailer.
fn crc32(data: &[u8]) -> u32 {
    static TABLE: std::sync::OnceLock<[u32; 256]> = std::sync::OnceLock::new();
    let table = TABLE.get_or_init(|| {
        let mut t = [0u32; 256];
        for (i, e) in t.iter_mut().enumerate() {
            let mut c = i as u32;
            for _ in 0..8 {
                c = if c & 1 != 0 {
                    0xedb8_8320 ^ (c >> 1)
                } else {
                    c >> 1
                };
            }
            *e = c;
        }
        t
    });
    let mut c = !0u32;
    for &b in data {
        c = table[((c ^ u32::from(b)) & 0xff) as usize] ^ (c >> 8);
    }
    !c
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Vec<u8> {
        let mut v = Vec::new();
        for i in 0..50_000u32 {
            v.extend_from_slice(&(i % 300).to_le_bytes());
        }
        v.extend_from_slice(b"some text at the end");
        v
    }

    #[test]
    fn every_codec_round_trips() {
        let data = sample();
        let mut codecs = Codecs::default();
        for c in [
            Compression::None,
            Compression::Snappy,
            Compression::Gzip,
            Compression::Zstd,
            Compression::Lz4Raw,
        ] {
            for level in [None, Some(1)] {
                let Ok(level) = c.level(level) else { continue };
                let mut packed = vec![9u8; 3];
                codecs.compress(c, level, &data, &mut packed).unwrap();
                assert_eq!(&packed[..3], &[9, 9, 9]);
                let mut out = vec![7u8; 5];
                codecs
                    .decompress(c.codec(), &packed[3..], data.len(), &mut out)
                    .unwrap();
                assert_eq!(out, data, "{c:?}");
                // A wrong size is an error.
                for wrong in [data.len() - 1, data.len() + 1] {
                    assert!(
                        codecs
                            .decompress(c.codec(), &packed[3..], wrong, &mut out)
                            .is_err(),
                        "{c:?}"
                    );
                }
                // So is damage.
                if c != Compression::None {
                    let cut = &packed[3..packed.len() / 2];
                    assert!(
                        codecs
                            .decompress(c.codec(), cut, data.len(), &mut out)
                            .is_err(),
                        "{c:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn empty_input_round_trips() {
        let mut codecs = Codecs::default();
        for c in [
            Compression::None,
            Compression::Snappy,
            Compression::Gzip,
            Compression::Zstd,
            Compression::Lz4Raw,
        ] {
            let mut packed = Vec::new();
            codecs
                .compress(c, c.level(None).unwrap(), &[], &mut packed)
                .unwrap();
            let mut out = Vec::new();
            codecs.decompress(c.codec(), &packed, 0, &mut out).unwrap();
            assert!(out.is_empty());
        }
    }

    #[test]
    fn gzip_members_and_header_fields() {
        let mut two = Vec::new();
        gzip(b"hello ", 6, &mut two);
        gzip(b"world", 6, &mut two);
        let mut out = Vec::new();
        gunzip(&two, 11, &mut out).unwrap();
        assert_eq!(&out, b"hello world");
        // A member with a file name (FNAME).
        let mut named = vec![0x1f, 0x8b, 8, 8, 0, 0, 0, 0, 0, 255];
        named.extend_from_slice(b"x.txt\0");
        named.extend_from_slice(&miniz_oxide::deflate::compress_to_vec(b"abc", 6));
        named.extend_from_slice(&crc32(b"abc").to_le_bytes());
        named.extend_from_slice(&3u32.to_le_bytes());
        let mut out = Vec::new();
        gunzip(&named, 3, &mut out).unwrap();
        assert_eq!(&out, b"abc");
        assert_eq!(crc32(b"123456789"), 0xcbf4_3926);
    }

    /// A small page whose header claims about 2 GiB is refused without
    /// the buffer ever growing near that size.
    #[test]
    fn a_header_alone_cannot_ask_for_memory() {
        let mut codecs = Codecs::default();
        let declared = i32::MAX as usize;
        for c in [
            Compression::None,
            Compression::Snappy,
            Compression::Gzip,
            Compression::Zstd,
            Compression::Lz4Raw,
        ] {
            let mut packed = Vec::new();
            codecs
                .compress(c, c.level(None).unwrap(), b"just a few bytes", &mut packed)
                .unwrap();
            if c == Compression::Snappy {
                // Snappy data begins with its length: claim the same.
                packed.splice(..1, [0xff, 0xff, 0xff, 0xff, 0x07]);
            }
            let mut out = Vec::new();
            assert!(
                codecs
                    .decompress(c.codec(), &packed, declared, &mut out)
                    .is_err(),
                "{c:?}"
            );
            assert!(out.capacity() <= FIRST_FLOOR, "{c:?}: {}", out.capacity());
        }
        // Legitimate data that expands far more than the first buffer
        // still reads: 64 MiB of zeros.
        let zeros = vec![0u8; 64 << 20];
        for c in [Compression::Gzip, Compression::Zstd] {
            let mut packed = Vec::new();
            codecs
                .compress(c, c.level(None).unwrap(), &zeros, &mut packed)
                .unwrap();
            assert!(packed.len() * FIRST_RATIO < FIRST_FLOOR, "{c:?}");
            let mut out = Vec::new();
            codecs
                .decompress(c.codec(), &packed, zeros.len(), &mut out)
                .unwrap();
            assert!(out == zeros, "{c:?}");
            // And one byte more than the header says is an error.
            assert!(codecs
                .decompress(c.codec(), &packed, zeros.len() - 1, &mut out)
                .is_err());
        }
    }

    /// A text, and the same compressed by brotli through pyarrow's
    /// `pa.compress` with its defaults.
    const BROTLI_TEXT: &[u8] = b"hello brotli, hello brotli, hello brotli!";
    const BROTLI_PACKED: &[u8] = &[
        0x1b, 0x28, 0x00, 0x00, 0xc4, 0x6d, 0x6c, 0x5d, 0xfd, 0xde, 0xe5, 0x13, 0x04, 0x21, 0xca,
        0x41, 0x14, 0xe1, 0xa7, 0x1e, 0xcf, 0xe9, 0x13, 0xbe, 0x7d, 0x23, 0x88,
    ];

    #[test]
    fn brotli_reads() {
        let mut out = Vec::new();
        unbrotli(BROTLI_PACKED, BROTLI_TEXT.len(), &mut out).unwrap();
        assert_eq!(out, BROTLI_TEXT);
        assert_eq!(brotli_first_block(BROTLI_PACKED), Some(BROTLI_TEXT.len()));
        // A wrong size, a cut stream and a damaged one are errors.
        let mut codecs = Codecs::default();
        for wrong in [BROTLI_TEXT.len() - 1, BROTLI_TEXT.len() + 1] {
            assert!(codecs.decompress(Codec::Brotli, BROTLI_PACKED, wrong, &mut out).is_err());
        }
        for cut in 1..BROTLI_PACKED.len() {
            assert!(codecs.decompress(Codec::Brotli, &BROTLI_PACKED[..cut], BROTLI_TEXT.len(), &mut out).is_err(), "cut {cut}");
        }
        // The empty stream is the byte 0x06 (WBITS 16, ISLAST, ISLASTEMPTY).
        codecs.decompress(Codec::Brotli, &[0x06], 0, &mut out).unwrap();
        assert!(out.is_empty());
        assert_eq!(brotli_first_block(&[0x06]), None);
    }

    /// A first block claiming 16 MiB is refused before the decoder sizes
    /// its window to it.
    #[test]
    fn a_brotli_block_cannot_claim_more_than_the_page() {
        // WBITS 24 (bits 1, 111), not last, 6 nibbles of length-1 =
        // 0xffffff: 16 MiB.
        let mut bits: Vec<u8> = vec![1, 1, 1, 1, 0, 0, 1];
        for _ in 0..24 {
            bits.push(1);
        }
        let mut bytes = vec![0u8; bits.len().div_ceil(8) + 4];
        for (k, b) in bits.iter().enumerate() {
            bytes[k / 8] |= b << (k % 8);
        }
        assert_eq!(brotli_first_block(&bytes), Some(1 << 24));
        let e = unbrotli(&bytes, 100, &mut Vec::new()).unwrap_err();
        assert!(e.message.contains("more than the 100"), "{}", e.message);
    }

    #[test]
    fn levels_and_names() {
        assert_eq!(Compression::from_name("ZSTD").unwrap(), Compression::Zstd);
        assert!(Compression::from_name("lzo")
            .unwrap_err()
            .message
            .contains("\"zstd\""));
        assert_eq!(Compression::Zstd.level(None).unwrap(), 3);
        assert!(Compression::Zstd.level(Some(23)).is_err());
        assert!(Compression::Snappy
            .level(Some(1))
            .unwrap_err()
            .message
            .contains("no compression levels"));
        assert_eq!(Compression::Gzip.level(Some(9)).unwrap(), 9);
    }

    #[test]
    fn codecs_not_read_name_themselves() {
        let mut codecs = Codecs::default();
        for (c, word) in [
            (Codec::Lzo, "LZO"),
            (Codec::Lz4, "Hadoop"),
            (Codec::Other(42), "codec 42"),
        ] {
            let e = codecs
                .decompress(c, &[1, 2, 3], 3, &mut Vec::new())
                .unwrap_err();
            assert!(e.message.contains(word), "{}", e.message);
        }
    }
}
