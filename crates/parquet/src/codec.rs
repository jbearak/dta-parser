//! Page compression: none, snappy, gzip, zstd and lz4_raw.
//!
//! zstd goes through C libzstd on native targets and the pure-Rust
//! `ruzstd` in wasm, where C would need a wasm32 C toolchain
//! (docs/research/parquet-codecs.md).

use crate::format::Codec;
use dta::{Error, ErrorKind, Result};

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
    zstd_in: Option<zstd::bulk::Decompressor<'static>>,
    #[cfg(not(target_arch = "wasm32"))]
    zstd_out: Option<(i32, zstd::bulk::Compressor<'static>)>,
    #[cfg(target_arch = "wasm32")]
    zstd_in: Option<ruzstd::decoding::FrameDecoder>,
}

impl Codecs {
    /// Decompress `input` into `out`, which is exactly the size the page
    /// header gives; a different size is an error.
    pub(crate) fn decompress(&mut self, codec: Codec, input: &[u8], out: &mut [u8]) -> Result<()> {
        let written = match codec {
            Codec::Uncompressed => {
                if input.len() != out.len() {
                    return Err(Error::new("an uncompressed page's sizes differ"));
                }
                out.copy_from_slice(input);
                out.len()
            }
            Codec::Snappy => {
                let len = snap::raw::decompress_len(input)
                    .map_err(|e| Error::new(format!("snappy: {e}")))?;
                if len != out.len() {
                    return Err(Error::new(format!(
                        "snappy data holds {len} bytes, not the {} the page header says",
                        out.len()
                    )));
                }
                snap::raw::Decoder::new()
                    .decompress(input, out)
                    .map_err(|e| Error::new(format!("snappy: {e}")))?
            }
            Codec::Gzip => gunzip(input, out)?,
            Codec::Zstd => self.unzstd(input, out)?,
            Codec::Lz4Raw => lz4_flex::block::decompress_into(input, out)
                .map_err(|e| Error::new(format!("lz4_raw: {e}")))?,
            other => return Err(unsupported(other)),
        };
        if written != out.len() {
            return Err(Error::new(format!(
                "a page decompressed to {written} bytes, not the {} its header says",
                out.len()
            )));
        }
        Ok(())
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn unzstd(&mut self, input: &[u8], out: &mut [u8]) -> Result<usize> {
        if self.zstd_in.is_none() {
            self.zstd_in = Some(zstd::bulk::Decompressor::new()?);
        }
        let d = self.zstd_in.as_mut().expect("made above");
        d.decompress_to_buffer(input, out)
            .map_err(|e| Error::new(format!("zstd: {e}")))
    }

    #[cfg(target_arch = "wasm32")]
    fn unzstd(&mut self, input: &[u8], out: &mut [u8]) -> Result<usize> {
        let d = self
            .zstd_in
            .get_or_insert_with(ruzstd::decoding::FrameDecoder::new);
        d.decode_all(input, out)
            .map_err(|e| Error::new(format!("zstd: {e}")))
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
        Codec::Brotli => "BROTLI compression is not read yet".to_string(),
        other => format!("{} is not supported", other.name()),
    };
    Error::new(what)
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

/// Inflate one or more gzip members into `out`; returns the bytes written.
fn gunzip(input: &[u8], out: &mut [u8]) -> Result<usize> {
    use miniz_oxide::inflate::core::{decompress, inflate_flags, DecompressorOxide};
    use miniz_oxide::inflate::TINFLStatus;
    let bad = |what: &str| Error::new(format!("gzip: {what}"));
    let mut at = 0;
    let mut written = 0;
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
        let (status, used, n) = decompress(
            &mut state,
            body,
            &mut out[written..],
            0,
            inflate_flags::TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF,
        );
        match status {
            TINFLStatus::Done => {}
            TINFLStatus::HasMoreOutput => {
                return Err(bad("data holds more bytes than the page header says"))
            }
            _ => return Err(bad(&format!("{status:?}"))),
        }
        let trailer = body
            .get(used..used + 8)
            .ok_or_else(|| bad("trailer missing"))?;
        let size = u32::from_le_bytes(trailer[4..8].try_into().expect("4 bytes"));
        if size != n as u32 {
            return Err(bad("member length does not match its trailer"));
        }
        written += n;
        at += p + used + 8;
    }
    Ok(written)
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
                let mut out = vec![0u8; data.len()];
                codecs
                    .decompress(c.codec(), &packed[3..], &mut out)
                    .unwrap();
                assert_eq!(out, data, "{c:?}");
                // A wrong size is an error.
                let mut short = vec![0u8; data.len() - 1];
                assert!(
                    codecs
                        .decompress(c.codec(), &packed[3..], &mut short)
                        .is_err(),
                    "{c:?}"
                );
                let mut long = vec![0u8; data.len() + 1];
                assert!(
                    codecs
                        .decompress(c.codec(), &packed[3..], &mut long)
                        .is_err(),
                    "{c:?}"
                );
                // So is damage.
                if c != Compression::None {
                    let mut out = vec![0u8; data.len()];
                    let cut = &packed[3..packed.len() / 2];
                    assert!(
                        codecs.decompress(c.codec(), cut, &mut out).is_err(),
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
            codecs.decompress(c.codec(), &packed, &mut []).unwrap();
        }
    }

    #[test]
    fn gzip_members_and_header_fields() {
        let mut two = Vec::new();
        gzip(b"hello ", 6, &mut two);
        gzip(b"world", 6, &mut two);
        let mut out = vec![0u8; 11];
        assert_eq!(gunzip(&two, &mut out).unwrap(), 11);
        assert_eq!(&out, b"hello world");
        // A member with a file name (FNAME).
        let mut named = vec![0x1f, 0x8b, 8, 8, 0, 0, 0, 0, 0, 255];
        named.extend_from_slice(b"x.txt\0");
        named.extend_from_slice(&miniz_oxide::deflate::compress_to_vec(b"abc", 6));
        named.extend_from_slice(&crc32(b"abc").to_le_bytes());
        named.extend_from_slice(&3u32.to_le_bytes());
        let mut out = vec![0u8; 3];
        assert_eq!(gunzip(&named, &mut out).unwrap(), 3);
        assert_eq!(crc32(b"123456789"), 0xcbf4_3926);
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
            (Codec::Brotli, "BROTLI"),
            (Codec::Lz4, "Hadoop"),
            (Codec::Other(42), "codec 42"),
        ] {
            let e = codecs.decompress(c, &[1, 2, 3], &mut [0; 3]).unwrap_err();
            assert!(e.message.contains(word), "{}", e.message);
        }
    }
}
