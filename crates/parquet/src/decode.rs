//! Decoding one column chunk, or the part of it a row window needs.
//!
//! A chunk is fetched as one or two runs of bytes (the dictionary page
//! and the data pages that hold the window), its pages decompressed one
//! at a time into a reused buffer, and their values written straight
//! into the caller's slices.

use std::collections::HashMap;
use std::ops::Range;
use std::sync::{Mutex, PoisonError};

use crate::codec::Codecs;
use crate::encoding;
use crate::format::{Codec, ColumnMetaData, Encoding, OffsetIndex, PageHeader, PageType};
use crate::rle;
use crate::schema::ColumnInfo;
use crate::thrift::TRUNCATED;
use dta::{Error, ErrorKind, Result};

/// Buffers a thread reuses from chunk to chunk.
#[derive(Default)]
pub(crate) struct Scratch {
    pub(crate) codecs: Codecs,
    raw: Vec<u8>,
    page: Vec<u8>,
    levels: Vec<u8>,
    indices: Vec<u32>,
    bools: Vec<u8>,
    /// A chunk's validity bits, for Arrow outputs.
    pub(crate) arrow_bits: Vec<u8>,
}

/// Reads bytes of the file.
pub(crate) type ReadAt<'a> = dyn FnMut(u64, &mut [u8]) -> Result<()> + 'a;

/// One column chunk and the rows wanted from it.
pub(crate) struct Chunk<'r> {
    pub(crate) column: &'r ColumnInfo,
    pub(crate) meta: &'r ColumnMetaData,
    /// Row group, counted from 0.
    pub(crate) group: usize,
    pub(crate) group_rows: u64,
    /// The rows wanted, counted from the row group's first.
    pub(crate) window: Range<u64>,
    /// The row group's first row in the file, for messages.
    pub(crate) file_row: u64,
    pub(crate) file_len: u64,
    pub(crate) offset_index: Option<&'r OffsetIndex>,
    /// Decompressed pages kept between reads, used when the window is
    /// only part of the chunk.
    pub(crate) cache: Option<&'r Mutex<PageCache>>,
    /// Hand RLE definition levels to the consumer undecoded
    /// ([`DataPage::raw_levels`]): the Arrow outputs decode them straight
    /// into a validity bitmap.
    pub(crate) raw_levels: bool,
}

/// Decompressed pages kept between reads, by each page's offset in the
/// file, up to a byte budget; the least recently used go first. A reader
/// that reads many small windows of the same pages (a viewer scrolling,
/// or a scan in batches) then decompresses each page once
/// ([`crate::Reader::set_page_cache`]).
#[derive(Debug, Default)]
pub struct PageCache {
    budget: usize,
    used: usize,
    tick: u64,
    pages: HashMap<u64, (Vec<u8>, u64)>,
    hits: u64,
    misses: u64,
}

impl PageCache {
    /// A cache holding up to `budget` bytes of decompressed pages.
    pub fn new(budget: usize) -> Self {
        PageCache { budget, ..Default::default() }
    }

    /// Bytes held now.
    pub fn bytes(&self) -> usize {
        self.used
    }

    /// Pages found and not found in the cache so far.
    pub fn hits_and_misses(&self) -> (u64, u64) {
        (self.hits, self.misses)
    }

    /// Copy the page at `offset` into `out`, if held.
    fn take(&mut self, offset: u64, out: &mut Vec<u8>) -> bool {
        self.tick += 1;
        let tick = self.tick;
        match self.pages.get_mut(&offset) {
            Some((bytes, used)) => {
                *used = tick;
                out.clear();
                out.extend_from_slice(bytes);
                self.hits += 1;
                true
            }
            None => {
                self.misses += 1;
                false
            }
        }
    }

    /// Keep a copy of `bytes` as the page at `offset`, dropping the least
    /// recently used pages to make room. A page larger than half the
    /// budget is not kept.
    fn put(&mut self, offset: u64, bytes: &[u8]) {
        if bytes.len() > self.budget / 2 || self.pages.contains_key(&offset) {
            return;
        }
        while self.used + bytes.len() > self.budget {
            let Some((&oldest, _)) = self.pages.iter().min_by_key(|(_, (_, t))| *t) else { break };
            if let Some((b, _)) = self.pages.remove(&oldest) {
                self.used -= b.len();
            }
        }
        let mut copy = Vec::new();
        if copy.try_reserve_exact(bytes.len()).is_err() {
            return;
        }
        copy.extend_from_slice(bytes);
        self.used += copy.len();
        self.tick += 1;
        self.pages.insert(offset, (copy, self.tick));
    }
}

/// The cache and a page's offset, when the page may be kept.
type Cached<'c> = Option<(&'c Mutex<PageCache>, u64)>;

fn lock(c: &Mutex<PageCache>) -> std::sync::MutexGuard<'_, PageCache> {
    // A panic while the lock was held leaves a cache that is still whole.
    c.lock().unwrap_or_else(PoisonError::into_inner)
}

impl Chunk<'_> {
    /// An error about this chunk, at `offset` when known.
    pub(crate) fn error(&self, offset: Option<u64>, e: Error) -> Error {
        if e.kind != ErrorKind::Corrupt && e.kind != ErrorKind::TooLarge {
            return e;
        }
        let message = format!(
            "column \"{}\", row group {}: {}",
            self.column.name,
            self.group + 1,
            e.message
        );
        Error {
            offset: offset.or(e.offset),
            message,
            kind: e.kind,
        }
    }

    /// The chunk's first byte and length, checked against the file.
    pub(crate) fn range(&self) -> Result<Range<u64>> {
        let m = self.meta;
        let data = u64::try_from(m.data_page_offset).ok();
        // Some writers set dictionary_page_offset to 0 or past the data
        // page when there is no dictionary.
        let dict = m
            .dictionary_page_offset
            .and_then(|d| u64::try_from(d).ok())
            .filter(|&d| d > 0 && data.is_some_and(|p| d < p));
        let start = dict
            .or(data)
            .ok_or_else(|| Error::new("the column chunk has a negative offset"))?;
        let len = u64::try_from(m.total_compressed_size)
            .map_err(|_| Error::new("the column chunk has a negative size"))?;
        let end = start
            .checked_add(len)
            .filter(|&e| e <= self.file_len)
            .ok_or_else(|| Error::at(start, "the column chunk runs past the end of the file"))?;
        Ok(start..end)
    }
}

/// A run of fetched bytes: where it is in the file and in `raw`, and the
/// row (in the row group) of its first data page.
struct Segment {
    offset: u64,
    bytes: Range<usize>,
    first_row: u64,
}

fn read_into(read: &mut ReadAt, raw: &mut Vec<u8>, offset: u64, len: u64) -> Result<Range<usize>> {
    let start = raw.len();
    let len = usize::try_from(len).map_err(|_| {
        Error::at(offset, "a column chunk too large for this machine").of(ErrorKind::TooLarge)
    })?;
    if raw.try_reserve(len).is_err() {
        return Err(
            Error::at(offset, format!("{len} bytes do not fit in memory here"))
                .of(ErrorKind::TooLarge),
        );
    }
    raw.resize(start + len, 0);
    read(offset, &mut raw[start..])?;
    Ok(start..start + len)
}

/// The data pages of an offset index that hold `window`, if the index is
/// usable: offsets increasing within the chunk, rows from 0 increasing.
fn pages_for(
    index: &OffsetIndex,
    chunk: &Range<u64>,
    rows: u64,
    window: &Range<u64>,
) -> Option<(Range<u64>, u64)> {
    let pages = &index.pages;
    let first = pages.first()?;
    if first.first_row_index != 0 {
        return None;
    }
    let mut last_end = chunk.start;
    let mut last_row = -1i64;
    for p in pages {
        let off = u64::try_from(p.offset).ok()?;
        let len = u64::try_from(p.compressed_page_size).ok()?;
        if off < last_end
            || off + len > chunk.end
            || p.first_row_index <= last_row
            || p.first_row_index as u64 >= rows.max(1)
        {
            return None;
        }
        last_end = off + len;
        last_row = p.first_row_index;
    }
    let row_end = |k: usize| pages.get(k + 1).map_or(rows, |p| p.first_row_index as u64);
    let from = (0..pages.len()).find(|&k| row_end(k) > window.start)?;
    let to = (from..pages.len())
        .take_while(|&k| (pages[k].first_row_index as u64) < window.end)
        .last()?;
    let start = pages[from].offset as u64;
    let end = pages[to].offset as u64 + pages[to].compressed_page_size as u64;
    Some((start..end, pages[from].first_row_index as u64))
}

/// The byte ranges a read of `chunk`'s window fetches: with a usable
/// offset index, the dictionary page and the pages that hold the window;
/// otherwise the whole chunk (a read without an index fetches less, after
/// walking the page headers).
pub(crate) fn planned(chunk: &Chunk) -> Result<Vec<Range<u64>>> {
    let range = chunk.range()?;
    let whole = chunk.window.start == 0 && chunk.window.end >= chunk.group_rows;
    if !whole {
        if let Some(oi) = chunk.offset_index {
            if let Some((pages, _)) = pages_for(oi, &range, chunk.group_rows, &chunk.window) {
                let first_page = oi.pages[0].offset as u64;
                let mut out = Vec::with_capacity(2);
                if first_page > range.start {
                    out.push(range.start..first_page);
                }
                out.push(pages);
                return Ok(out);
            }
        }
    }
    Ok(vec![range])
}

/// Fetch the bytes `chunk` needs for its window into `raw`.
fn fetch(chunk: &Chunk, read: &mut ReadAt, raw: &mut Vec<u8>) -> Result<Vec<Segment>> {
    raw.clear();
    let range = chunk.range()?;
    let whole = chunk.window.start == 0 && chunk.window.end >= chunk.group_rows;
    if !whole {
        if let Some((pages, first_row)) = chunk
            .offset_index
            .and_then(|oi| pages_for(oi, &range, chunk.group_rows, &chunk.window))
        {
            let mut out = Vec::with_capacity(2);
            let first_page = chunk
                .offset_index
                .and_then(|oi| oi.pages.first())
                .map_or(range.start, |p| p.offset as u64);
            if first_page > range.start {
                // The dictionary page comes before the first data page.
                let bytes = read_into(read, raw, range.start, first_page - range.start)?;
                out.push(Segment {
                    offset: range.start,
                    bytes,
                    first_row: 0,
                });
            }
            let bytes = read_into(read, raw, pages.start, pages.end - pages.start)?;
            out.push(Segment {
                offset: pages.start,
                bytes,
                first_row,
            });
            return Ok(out);
        }
        // No usable index: walk the page headers, reading only them, and
        // then the pages that hold the window.
        let walked = walk(chunk, read, &range)?;
        let mut out = Vec::with_capacity(2);
        if let Some(d) = walked.iter().find(|p| p.dictionary) {
            let bytes = read_into(read, raw, d.offset, d.len)?;
            out.push(Segment {
                offset: d.offset,
                bytes,
                first_row: 0,
            });
        }
        let wanted: Vec<&Walked> = walked
            .iter()
            .filter(|p| {
                !p.dictionary && p.rows.end > chunk.window.start && p.rows.start < chunk.window.end
            })
            .collect();
        if let (Some(a), Some(b)) = (wanted.first(), wanted.last()) {
            let bytes = read_into(read, raw, a.offset, b.offset + b.len - a.offset)?;
            out.push(Segment {
                offset: a.offset,
                bytes,
                first_row: a.rows.start,
            });
        }
        return Ok(out);
    }
    let bytes = read_into(read, raw, range.start, range.end - range.start)?;
    Ok(vec![Segment {
        offset: range.start,
        bytes,
        first_row: 0,
    }])
}

/// A page found by walking headers.
struct Walked {
    offset: u64,
    len: u64,
    rows: Range<u64>,
    dictionary: bool,
}

/// Read each page header of the chunk in turn, skipping the pages'
/// bodies, until the window's last row.
fn walk(chunk: &Chunk, read: &mut ReadAt, range: &Range<u64>) -> Result<Vec<Walked>> {
    let mut out = Vec::new();
    let mut at = range.start;
    let mut row = 0u64;
    let mut buf = Vec::new();
    while at < range.end && row < chunk.window.end {
        // Headers are usually tens of bytes; statistics can make them
        // longer, so read more until the header parses.
        let mut want = 256u64;
        let (header, len) = loop {
            let n = want.min(range.end - at);
            // Within the chunk, which is within the file.
            buf.resize(
                usize::try_from(n).map_err(|_| Error::at(at, "a page header is too long"))?,
                0,
            );
            read(at, &mut buf)?;
            match PageHeader::parse(&buf, at) {
                Ok(h) => break h,
                Err(e) if e.message == TRUNCATED && n < range.end - at => {
                    want = want.saturating_mul(4)
                }
                Err(e) => return Err(e),
            }
        };
        let body = u64::try_from(header.compressed_page_size)
            .map_err(|_| Error::at(at, "a page has a negative size"))?;
        let total = len as u64 + body;
        if at + total > range.end {
            return Err(Error::at(
                at,
                "a page runs past the end of its column chunk",
            ));
        }
        let rows = page_rows(&header).map_err(|e| Error::at(at, e.message))?;
        let dictionary = header.kind == PageType::Dictionary;
        out.push(Walked {
            offset: at,
            len: total,
            rows: row..row + rows,
            dictionary,
        });
        row += rows;
        at += total;
    }
    Ok(out)
}

/// Rows in a data page of a flat column (0 for other pages).
fn page_rows(h: &PageHeader) -> Result<u64> {
    let n = match h.kind {
        PageType::Data => h
            .data
            .as_ref()
            .map(|d| d.num_values)
            .ok_or_else(|| Error::new("a data page has no data page header"))?,
        PageType::DataV2 => h
            .data_v2
            .as_ref()
            .map(|d| d.num_rows)
            .ok_or_else(|| Error::new("a data page has no data page header"))?,
        _ => 0,
    };
    u64::try_from(n).map_err(|_| Error::new("a page has a negative number of values"))
}

/// One data page, decompressed, with its definition levels decoded.
pub(crate) struct DataPage<'p> {
    /// Rows of the page to write, counted from its first.
    pub(crate) take: Range<usize>,
    /// Where `take.start` goes in the chunk's output.
    pub(crate) out_at: usize,
    /// Per row of `take`, 1 where there is a value; `None` when every
    /// one has a value.
    pub(crate) levels: Option<&'p [u8]>,
    /// With [`Chunk::raw_levels`], a page's RLE definition levels as the
    /// page holds them (width 1, every row of the page); `levels`,
    /// `before` and `present` are then not filled in.
    pub(crate) raw_levels: Option<&'p [u8]>,
    /// The number of values (non-null rows) in the page before `take`,
    /// and up to its end.
    pub(crate) before: usize,
    pub(crate) present: usize,
    pub(crate) encoding: Encoding,
    pub(crate) values: &'p [u8],
}

/// What a column's values become; one per output kind.
pub(crate) trait Consumer {
    /// The chunk's dictionary page.
    fn dictionary(&mut self, count: usize, values: &[u8]) -> Result<()>;
    /// A data page, of which rows `page.take` are wanted.
    fn page(&mut self, page: &DataPage, indices: &mut Vec<u32>, bools: &mut Vec<u8>) -> Result<()>;
}

/// Decode the window of `chunk` into `out`.
pub(crate) fn decode(
    chunk: &Chunk,
    read: &mut ReadAt,
    scratch: &mut Scratch,
    out: &mut dyn Consumer,
) -> Result<()> {
    let segments = fetch(chunk, read, &mut scratch.raw).map_err(|e| chunk.error(None, e))?;
    let Scratch {
        codecs,
        raw,
        page,
        levels,
        indices,
        bools,
        ..
    } = scratch;
    let codec = chunk.meta.codec;
    let optional = !chunk.column.required;
    let partial = !(chunk.window.start == 0 && chunk.window.end >= chunk.group_rows);
    let cache = chunk.cache.filter(|_| partial);
    let mut seen_dictionary = false;
    let mut covered = chunk.window.start;
    for seg in &segments {
        let bytes = &raw[seg.bytes.clone()];
        let mut at = 0usize;
        let mut row = seg.first_row;
        while at < bytes.len() && row < chunk.window.end {
            let offset = seg.offset + at as u64;
            let fail = |e: Error| chunk.error(Some(offset), e);
            let (header, header_len) = PageHeader::parse(&bytes[at..], offset).map_err(fail)?;
            let body_len = usize::try_from(header.compressed_page_size)
                .map_err(|_| fail(Error::new("a page has a negative size")))?;
            let body_start = at + header_len;
            let body = bytes[body_start..]
                .get(..body_len)
                .ok_or_else(|| fail(Error::new("a page runs past the end of its column chunk")))?;
            at = body_start + body_len;
            match header.kind {
                PageType::Dictionary => {
                    if seen_dictionary {
                        return Err(fail(Error::new(
                            "the column chunk has two dictionary pages",
                        )));
                    }
                    seen_dictionary = true;
                    let d = header.dictionary.as_ref().ok_or_else(|| {
                        fail(Error::new(
                            "a dictionary page has no dictionary page header",
                        ))
                    })?;
                    if !matches!(d.encoding, Encoding::Plain | Encoding::PlainDictionary) {
                        return Err(fail(Error::new(format!(
                            "a dictionary page is encoded {}, which is not read",
                            d.encoding.name()
                        ))));
                    }
                    let count = usize::try_from(d.num_values)
                        .map_err(|_| fail(Error::new("a dictionary page has a negative size")))?;
                    let values = inflate(
                        codecs,
                        codec,
                        body,
                        header.uncompressed_page_size,
                        page,
                        cache.map(|c| (c, offset)),
                    )
                    .map_err(fail)?;
                    out.dictionary(count, &page[values]).map_err(fail)?;
                }
                PageType::Data | PageType::DataV2 => {
                    let rows = page_rows(&header).map_err(fail)?;
                    let end = row
                        .checked_add(rows)
                        .filter(|&e| e <= chunk.group_rows)
                        .ok_or_else(|| {
                            fail(Error::new("the pages hold more rows than the row group"))
                        })?;
                    if end <= chunk.window.start || rows == 0 {
                        row = end;
                        continue;
                    }
                    let take = (chunk.window.start.max(row) - row) as usize
                        ..(chunk.window.end.min(end) - row) as usize;
                    let out_at = (row + take.start as u64 - chunk.window.start) as usize;
                    let p = prepare(
                        codecs,
                        codec,
                        &header,
                        body,
                        rows as usize,
                        &take,
                        optional,
                        chunk.raw_levels,
                        page,
                        levels,
                        cache.map(|c| (c, offset)),
                    )
                    .map_err(fail)?;
                    let values = match &p.values {
                        Where::Body(r) => &body[r.clone()],
                        Where::Page(r) => &page[r.clone()],
                    };
                    let raw_levels = p.raw.as_ref().map(|w| match w {
                        Where::Body(r) => &body[r.clone()],
                        Where::Page(r) => &page[r.clone()],
                    });
                    let data = DataPage {
                        take,
                        out_at,
                        levels: if p.all_present || raw_levels.is_some() {
                            None
                        } else {
                            Some(&levels[..])
                        },
                        raw_levels,
                        before: p.before,
                        present: p.present,
                        encoding: p.encoding,
                        values,
                    };
                    if matches!(
                        data.encoding,
                        Encoding::PlainDictionary | Encoding::RleDictionary
                    ) && !seen_dictionary
                    {
                        return Err(fail(Error::new(
                            "a dictionary-encoded page comes before any dictionary page",
                        )));
                    }
                    out.page(&data, indices, bools).map_err(fail)?;
                    covered = covered.max(chunk.window.start.max(row) + data.take.len() as u64);
                    row = end;
                }
                // Index pages and pages of kinds added later are skipped.
                _ => {}
            }
        }
    }
    if covered < chunk.window.end {
        return Err(chunk.error(
            None,
            Error::new(format!(
                "the column chunk ends before row {} of its row group",
                covered + 1
            )),
        ));
    }
    Ok(())
}

/// Where a page's values are: still in the page body (uncompressed
/// pages), or in the decompression buffer.
enum Where {
    Body(Range<usize>),
    Page(Range<usize>),
}

struct Prepared {
    values: Where,
    /// The RLE definition levels, undecoded ([`Chunk::raw_levels`]).
    raw: Option<Where>,
    /// Values before the wanted rows, and up to their end.
    before: usize,
    present: usize,
    /// Every wanted row has a value.
    all_present: bool,
    encoding: Encoding,
}

/// Decompress `body` into `page`, which must make `uncompressed` bytes;
/// returns the range of `page` holding them. With a cache, a page decompressed
/// before is copied from it, and one decompressed now is kept in it.
fn inflate(
    codecs: &mut Codecs,
    codec: Codec,
    body: &[u8],
    uncompressed: i32,
    page: &mut Vec<u8>,
    cache: Cached,
) -> Result<Range<usize>> {
    let n = usize::try_from(uncompressed)
        .map_err(|_| Error::new("a page has a negative uncompressed size"))?;
    if let Some((c, offset)) = cache {
        if lock(c).take(offset, page) && page.len() == n {
            return Ok(0..n);
        }
    }
    codecs.decompress(codec, body, n, page)?;
    if let Some((c, offset)) = cache {
        lock(c).put(offset, &page[..n]);
    }
    Ok(0..n)
}

/// The bytes after a 4-byte little-endian length, and how many bytes the
/// length and they take.
fn prefixed<'b>(bytes: &'b [u8], what: &str) -> Result<(&'b [u8], usize)> {
    let short = || Error::new(what.to_string());
    let len = bytes
        .get(..4)
        .map(|b| u32::from_le_bytes(b.try_into().expect("4 bytes")))
        .ok_or_else(short)?;
    let len = usize::try_from(len).map_err(|_| short())?;
    let data = bytes[4..].get(..len).ok_or_else(short)?;
    Ok((data, 4 + len))
}

/// Decode RLE definition levels for rows `take` of a page into `levels`;
/// returns the values before `take`.
fn rle_levels(bytes: &[u8], take: &Range<usize>, levels: &mut [u8]) -> Result<usize> {
    let mut before = 0;
    rle::decode_from(bytes, 1, take.start, levels, |v, n| {
        if v == 1 {
            before += n;
        }
    })?;
    Ok(before)
}

/// Decompress a data page and decode its definition levels for rows
/// `take` (of `rows`), so that memory follows the rows wanted rather than
/// the count the page header gives.
#[allow(clippy::too_many_arguments)]
fn prepare(
    codecs: &mut Codecs,
    codec: Codec,
    header: &PageHeader,
    body: &[u8],
    rows: usize,
    take: &Range<usize>,
    optional: bool,
    raw: bool,
    page: &mut Vec<u8>,
    levels: &mut Vec<u8>,
    cache: Cached,
) -> Result<Prepared> {
    levels.clear();
    if optional && !raw {
        // At most the rows the caller asked for, whose output is already
        // allocated.
        levels.resize(take.len(), 0);
    }
    let finish = |values: Where, before: usize, levels: &[u8], encoding: Encoding| {
        if !optional {
            return Prepared {
                values,
                raw: None,
                before: take.start,
                present: take.end,
                all_present: true,
                encoding,
            };
        }
        let here = levels.iter().filter(|&&l| l == 1).count();
        Prepared {
            values,
            raw: None,
            before,
            present: before + here,
            all_present: here == take.len(),
            encoding,
        }
    };
    if let Some(d) = &header.data_v2 {
        let rep = usize::try_from(d.repetition_levels_byte_length)
            .map_err(|_| Error::new("negative level length"))?;
        let def = usize::try_from(d.definition_levels_byte_length)
            .map_err(|_| Error::new("negative level length"))?;
        if rep != 0 {
            return Err(Error::new("a flat column's page has repetition levels"));
        }
        let level_bytes = body
            .get(..def)
            .ok_or_else(|| Error::new("a page's levels run past the page"))?;
        let before = if optional && !raw {
            rle_levels(level_bytes, take, levels)?
        } else {
            0
        };
        let rest = &body[def..];
        let values_len = usize::try_from(header.uncompressed_page_size)
            .ok()
            .and_then(|n| n.checked_sub(def))
            .ok_or_else(|| Error::new("a page's uncompressed size is smaller than its levels"))?;
        let values = if d.is_compressed && codec != Codec::Uncompressed {
            let n = i32::try_from(values_len).map_err(|_| Error::new("a page is too large"))?;
            Where::Page(inflate(codecs, codec, rest, n, page, cache)?)
        } else {
            if rest.len() != values_len {
                return Err(Error::new("an uncompressed page's sizes differ"));
            }
            Where::Body(def..body.len())
        };
        if optional && raw {
            return Ok(Prepared {
                values,
                raw: Some(Where::Body(0..def)),
                before: 0,
                present: 0,
                all_present: false,
                encoding: d.encoding,
            });
        }
        return Ok(finish(values, before, levels, d.encoding));
    }
    let d = header
        .data
        .as_ref()
        .ok_or_else(|| Error::new("a data page has no data page header"))?;
    let (bytes, base): (&[u8], Option<usize>) = if codec == Codec::Uncompressed {
        if usize::try_from(header.uncompressed_page_size).ok() != Some(body.len()) {
            return Err(Error::new("an uncompressed page's sizes differ"));
        }
        (body, None)
    } else {
        inflate(codecs, codec, body, header.uncompressed_page_size, page, cache)?;
        (&page[..], Some(0))
    };
    let mut at = 0;
    let mut before = 0;
    if optional && raw && d.definition_level_encoding == Encoding::Rle {
        let (_, used) = prefixed(bytes, "a page's levels run past the page")?;
        let (values, raw) = match base {
            None => (Where::Body(used..bytes.len()), Where::Body(4..used)),
            Some(_) => (Where::Page(used..bytes.len()), Where::Page(4..used)),
        };
        return Ok(Prepared { values, raw: Some(raw), before: 0, present: 0, all_present: false, encoding: d.encoding });
    }
    if optional && raw {
        // The older BIT_PACKED levels: decoded here, as for every output.
        levels.resize(take.len(), 0);
    }
    if optional {
        (at, before) = match d.definition_level_encoding {
            Encoding::Rle => {
                let (level_bytes, used) = prefixed(bytes, "a page's levels run past the page")?;
                (used, rle_levels(level_bytes, take, levels)?)
            }
            Encoding::BitPacked => rle::decode_bit_packed(bytes, 1, rows, take.start, levels)?,
            other => {
                return Err(Error::new(format!(
                    "definition levels encoded {}, which is not read",
                    other.name()
                )))
            }
        };
    }
    let values = match base {
        None => Where::Body(at..bytes.len()),
        Some(_) => Where::Page(at..bytes.len()),
    };
    Ok(finish(values, before, levels, d.encoding))
}

/// Decode the dictionary indices of a page's wanted rows into
/// `indices`: index `i` there is the page's value `page.before + i`.
fn dictionary_indices(
    page: &DataPage,
    indices: &mut Vec<u32>,
    dictionary_len: usize,
) -> Result<()> {
    let width = *page
        .values
        .first()
        .ok_or_else(|| Error::new("a dictionary-encoded page has no bit width"))?;
    indices.clear();
    indices.resize(page.present - page.before, 0);
    if !indices.is_empty() {
        rle::decode_from(
            &page.values[1..],
            width,
            page.before,
            &mut indices[..],
            |_, _| {},
        )?;
    }
    if indices.iter().any(|&i| i as usize >= dictionary_len) {
        return Err(Error::new(
            "a dictionary index is past the end of the dictionary",
        ));
    }
    Ok(())
}

pub(crate) fn unsupported_encoding(e: Encoding) -> Error {
    Error::new(format!(
        "values encoded {}, which this version does not read yet",
        e.name()
    ))
}

// ---- numbers ----

/// A Parquet physical number type.
pub(crate) trait Physical: Copy + Send + Sync + std::fmt::Debug + 'static {
    const WIDTH: usize;
    /// Whether values can be tagged NaNs (`.a` to `.z`): doubles only.
    const LETTERS: bool = false;
    fn from_le(b: &[u8]) -> Self;
    fn convert<T: crate::read::Element>(self) -> Option<T>;
    /// The value from the bits DELTA_BINARY_PACKED gives, for the integer
    /// types it encodes; `None` for the others.
    #[inline]
    fn from_bits(_: u64) -> Option<Self> {
        None
    }
    /// The missing code of a tagged NaN (2 to 27 for `.a` to `.z`), or 0.
    /// Only doubles hold them.
    #[inline]
    fn letter(self) -> u8 {
        0
    }
}

impl Physical for i32 {
    const WIDTH: usize = 4;
    #[inline]
    fn from_le(b: &[u8]) -> Self {
        i32::from_le_bytes(b[..4].try_into().expect("4 bytes"))
    }
    #[inline]
    fn convert<T: crate::read::Element>(self) -> Option<T> {
        T::from_i32(self)
    }
    #[inline]
    fn from_bits(v: u64) -> Option<Self> {
        Some(v as u32 as i32)
    }
}

impl Physical for i64 {
    const WIDTH: usize = 8;
    #[inline]
    fn from_le(b: &[u8]) -> Self {
        i64::from_le_bytes(b[..8].try_into().expect("8 bytes"))
    }
    #[inline]
    fn convert<T: crate::read::Element>(self) -> Option<T> {
        T::from_i64(self)
    }
    #[inline]
    fn from_bits(v: u64) -> Option<Self> {
        Some(v as i64)
    }
}

/// An INT32 column annotated unsigned: the same bits, read as a u32.
impl Physical for u32 {
    const WIDTH: usize = 4;
    #[inline]
    fn from_le(b: &[u8]) -> Self {
        u32::from_le_bytes(b[..4].try_into().expect("4 bytes"))
    }
    #[inline]
    fn convert<T: crate::read::Element>(self) -> Option<T> {
        T::from_u64(u64::from(self))
    }
    #[inline]
    fn from_bits(v: u64) -> Option<Self> {
        Some(v as u32)
    }
}

/// An INT64 column annotated unsigned.
impl Physical for u64 {
    const WIDTH: usize = 8;
    #[inline]
    fn from_le(b: &[u8]) -> Self {
        u64::from_le_bytes(b[..8].try_into().expect("8 bytes"))
    }
    #[inline]
    fn convert<T: crate::read::Element>(self) -> Option<T> {
        T::from_u64(self)
    }
    #[inline]
    fn from_bits(v: u64) -> Option<Self> {
        Some(v)
    }
}

/// An INT96 timestamp: nanoseconds since midnight (8 bytes), then the
/// Julian day (4 bytes, unsigned), as Impala and Spark wrote them. It
/// reads as nanoseconds since 1970-01-01 00:00.
#[derive(Clone, Copy)]
pub(crate) struct Int96(pub(crate) [u8; 12]);

/// The Julian day of 1970-01-01.
const UNIX_JULIAN_DAY: i64 = 2_440_588;
const NANOS_PER_DAY: i64 = 86_400_000_000_000;

impl Int96 {
    fn parts(self) -> (i64, u32) {
        let nanos = i64::from_le_bytes(self.0[..8].try_into().expect("8 bytes"));
        let day = u32::from_le_bytes(self.0[8..].try_into().expect("4 bytes"));
        (nanos, day)
    }

    /// Nanoseconds since 1970, if an i64 holds them.
    pub(crate) fn nanos(self) -> Option<i64> {
        let (nanos, day) = self.parts();
        (i64::from(day) - UNIX_JULIAN_DAY)
            .checked_mul(NANOS_PER_DAY)?
            .checked_add(nanos)
    }
}

impl std::fmt::Debug for Int96 {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let (nanos, day) = self.parts();
        write!(f, "INT96 (Julian day {day}, {nanos} ns)")
    }
}

impl Physical for Int96 {
    const WIDTH: usize = 12;
    #[inline]
    fn from_le(b: &[u8]) -> Self {
        Int96(b[..12].try_into().expect("12 bytes"))
    }
    #[inline]
    fn convert<T: crate::read::Element>(self) -> Option<T> {
        T::from_i64(self.nanos()?)
    }
}

impl Physical for f32 {
    const WIDTH: usize = 4;
    #[inline]
    fn from_le(b: &[u8]) -> Self {
        f32::from_le_bytes(b[..4].try_into().expect("4 bytes"))
    }
    #[inline]
    fn convert<T: crate::read::Element>(self) -> Option<T> {
        T::from_f32(self)
    }
}

impl Physical for f64 {
    const WIDTH: usize = 8;
    const LETTERS: bool = true;
    #[inline]
    fn from_le(b: &[u8]) -> Self {
        f64::from_le_bytes(b[..8].try_into().expect("8 bytes"))
    }
    #[inline]
    fn convert<T: crate::read::Element>(self) -> Option<T> {
        T::from_f64(self)
    }
    #[inline]
    fn letter(self) -> u8 {
        crate::tagged::tagged_code(self)
    }
}

/// Where a chunk's numbers go: its part of the caller's slices.
pub(crate) struct NumberOut<'o, T> {
    pub(crate) values: &'o mut [T],
    pub(crate) codes: Option<&'o mut [u8]>,
    /// The value written for `.` (index 0) and `.a` to `.z`.
    pub(crate) missing: &'o [T; 27],
    /// The file row of `values[0]`, for messages.
    pub(crate) file_row: u64,
}

/// An error for a value the output type cannot hold.
pub(crate) fn cannot_hold(value: &dyn std::fmt::Debug, row: u64, target: &str) -> Error {
    Error::invalid(format!(
        "the value {value:?} in row {} cannot be held exactly as {target}",
        row + 1
    ))
}

pub(crate) struct Numbers<'o, P, T> {
    pub(crate) out: NumberOut<'o, T>,
    pub(crate) dictionary: Vec<P>,
    /// Values decoded from a DELTA_BINARY_PACKED page, the wanted ones.
    pub(crate) decoded: Vec<u64>,
    /// Whether any `.a` to `.z` was read.
    pub(crate) letters: bool,
}

/// Put one present value into `d`: a tagged NaN as its missing value and
/// code, anything else converted. Returns whether it was `.a` to `.z`.
#[inline]
fn put_one<P: Physical, T: crate::read::Element>(
    p: P,
    d: &mut T,
    code: Option<&mut u8>,
    missing: &[T; 27],
    row: u64,
) -> Result<bool> {
    let letter = p.letter();
    if letter != 0 {
        *d = missing[usize::from(letter - 1)];
        if let Some(c) = code {
            *c = letter;
        }
        return Ok(true);
    }
    *d = p.convert().ok_or_else(|| cannot_hold(&p, row, T::NAME))?;
    Ok(false)
}

impl<P: Physical, T: crate::read::Element> Numbers<'_, P, T> {
    #[inline]
    fn put(&mut self, page: &DataPage, mut value: impl FnMut(usize) -> P) -> Result<()> {
        let out = &mut self.out;
        let take = page.take.clone();
        let rows = page.out_at..page.out_at + take.len();
        let dest = &mut out.values[rows.clone()];
        let mut codes = out.codes.as_deref_mut().map(|c| &mut c[rows]);
        if let Some(codes) = codes.as_deref_mut() {
            match page.levels {
                None => codes.fill(0),
                Some(l) => {
                    for (c, &l) in codes.iter_mut().zip(l) {
                        *c = 1 - l;
                    }
                }
            }
        }
        let missing = out.missing;
        let first_row = out.file_row + page.out_at as u64;
        let mut vi = page.before;
        let mut letters = false;
        match page.levels {
            None => {
                for (k, d) in dest.iter_mut().enumerate() {
                    let code = codes.as_deref_mut().map(|c| &mut c[k]);
                    letters |= put_one(value(vi + k), d, code, missing, first_row + k as u64)?;
                }
            }
            Some(levels) => {
                let null = missing[0];
                for (k, (d, &l)) in dest.iter_mut().zip(levels).enumerate() {
                    if l == 1 {
                        let code = codes.as_deref_mut().map(|c| &mut c[k]);
                        letters |= put_one(value(vi), d, code, missing, first_row + k as u64)?;
                        vi += 1;
                    } else {
                        *d = null;
                    }
                }
            }
        }
        self.letters |= letters;
        Ok(())
    }
}

impl<P: Physical, T: crate::read::Element> Numbers<'_, P, T> {
    /// Pages encoded DELTA_BINARY_PACKED or BYTE_STREAM_SPLIT, kept out of
    /// [`Consumer::page`] so that its PLAIN and dictionary paths compile
    /// as they did before these encodings were read.
    #[inline(never)]
    fn page_other(&mut self, page: &DataPage) -> Result<()> {
        match page.encoding {
            Encoding::DeltaBinaryPacked if P::from_bits(0).is_some() => {
                // Only the wanted values, whose output is allocated.
                let mut buf = std::mem::take(&mut self.decoded);
                buf.clear();
                buf.resize(page.present - page.before, 0);
                let before = page.before;
                let result = encoding::delta_values(page.values, before, &mut buf).and_then(|()| {
                    self.put(page, |i| {
                        P::from_bits(buf[i - before]).expect("an integer type")
                    })
                });
                self.decoded = buf;
                result
            }
            Encoding::ByteStreamSplit => {
                let count = encoding::split_count(page.values, P::WIDTH)?;
                if count < page.present {
                    return Err(Error::new("a page holds fewer values than its levels say"));
                }
                let values = page.values;
                self.put(page, |i| {
                    let mut b = [0u8; 16];
                    encoding::split_value(values, count, i, &mut b[..P::WIDTH]);
                    P::from_le(&b)
                })
            }
            other => Err(unsupported_encoding(other)),
        }
    }
}

impl<P: Physical, T: crate::read::Element> Consumer for Numbers<'_, P, T> {
    fn dictionary(&mut self, count: usize, values: &[u8]) -> Result<()> {
        let bytes = values
            .get(..count.saturating_mul(P::WIDTH))
            .ok_or_else(|| Error::new("a dictionary page ends early"))?;
        self.dictionary = bytes.chunks_exact(P::WIDTH).map(P::from_le).collect();
        Ok(())
    }

    fn page(&mut self, page: &DataPage, indices: &mut Vec<u32>, _: &mut Vec<u8>) -> Result<()> {
        match page.encoding {
            Encoding::Plain => {
                let need = page.present.saturating_mul(P::WIDTH);
                let bytes = page
                    .values
                    .get(..need)
                    .ok_or_else(|| Error::new("a page holds fewer values than its levels say"))?;
                self.put(page, |i| P::from_le(&bytes[i * P::WIDTH..]))
            }
            Encoding::PlainDictionary | Encoding::RleDictionary => {
                dictionary_indices(page, indices, self.dictionary.len())?;
                let dict = std::mem::take(&mut self.dictionary);
                let before = page.before;
                let result = self.put(page, |i| dict[indices[i - before] as usize]);
                self.dictionary = dict;
                result
            }
            Encoding::DeltaBinaryPacked | Encoding::ByteStreamSplit => self.page_other(page),
            other => Err(unsupported_encoding(other)),
        }
    }
}

/// A page's wanted booleans, 0 or 1 each: `bools[i]` is value
/// `page.before + i`.
pub(crate) fn booleans(page: &DataPage, before: usize, present: usize, bools: &mut Vec<u8>) -> Result<()> {
    bools.clear();
    match page.encoding {
        Encoding::Plain => {
            let bytes = page
                .values
                .get(..present.div_ceil(8))
                .ok_or_else(|| Error::new("a page holds fewer values than its levels say"))?;
            bools.extend((before..present).map(|i| (bytes[i >> 3] >> (i & 7)) & 1));
        }
        Encoding::Rle => {
            let (data, _) = prefixed(page.values, "an RLE page ends early")?;
            bools.resize(present - before, 0);
            rle::decode_from(data, 1, before, &mut bools[..], |_, _| {})?;
        }
        other => return Err(unsupported_encoding(other)),
    }
    Ok(())
}

/// Booleans: PLAIN bit-packed or RLE, into any number type as 0 and 1.
pub(crate) struct Booleans<'o, T> {
    pub(crate) out: NumberOut<'o, T>,
}

impl<T: crate::read::Element> Consumer for Booleans<'_, T> {
    fn dictionary(&mut self, _: usize, _: &[u8]) -> Result<()> {
        Err(Error::new("a boolean column has a dictionary page"))
    }

    fn page(&mut self, page: &DataPage, _: &mut Vec<u32>, bools: &mut Vec<u8>) -> Result<()> {
        let before = page.before;
        booleans(page, page.before, page.present, bools)?;
        let mut n = Numbers::<i32, T> {
            out: NumberOut {
                values: &mut *self.out.values,
                codes: self.out.codes.as_deref_mut(),
                missing: self.out.missing,
                file_row: self.out.file_row,
            },
            dictionary: Vec::new(),
            decoded: Vec::new(),
            letters: false,
        };
        let bools = &*bools;
        // Booleans are 0 and 1, which every output type holds.
        n.put(page, |i| i32::from(bools[i - before]))
    }
}

// ---- text ----

/// The text of one column chunk: distinct values and a code per row when
/// the chunk is dictionary-encoded, otherwise a value per row.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct TextChunk {
    /// The row of the read this chunk starts at.
    pub first: u64,
    /// Rows in the chunk.
    pub rows: usize,
    /// The values: value `i` is `bytes[ends[i-1]..ends[i]]` (from 0 for
    /// `i == 0`).
    pub bytes: Vec<u8>,
    pub ends: Vec<usize>,
    /// With a dictionary, row `r`'s value is `codes[r]`, or missing when
    /// that is [`TextChunk::NULL`]. Without one, row `r` is value `r`.
    pub codes: Option<Vec<u32>>,
    /// Without a dictionary, 1 for each missing row (whose value is
    /// empty). Empty with a dictionary.
    pub missing: Vec<u8>,
    /// The column holds text (UTF-8, checked) rather than bytes.
    pub utf8: bool,
}

impl TextChunk {
    /// The code of a missing row.
    pub const NULL: u32 = u32::MAX;

    /// Value `i`'s bytes.
    pub fn value(&self, i: usize) -> &[u8] {
        let start = if i == 0 { 0 } else { self.ends[i - 1] };
        &self.bytes[start..self.ends[i]]
    }

    /// Row `r`'s bytes, or `None` when it is missing.
    pub fn row(&self, r: usize) -> Option<&[u8]> {
        match &self.codes {
            Some(codes) => match codes[r] {
                Self::NULL => None,
                c => Some(self.value(c as usize)),
            },
            None if self.missing[r] != 0 => None,
            None => Some(self.value(r)),
        }
    }
}

pub(crate) struct Texts {
    pub(crate) chunk: TextChunk,
    /// The column's values are checked as UTF-8.
    pub(crate) utf8: bool,
    dictionary_len: usize,
    /// The width of a FIXED_LEN_BYTE_ARRAY column's values.
    fixed: Option<usize>,
    budget: Option<TextBudget>,
    /// The chunk's bytes already counted against the budget.
    charged: usize,
}

/// A limit on the text one read gathers, over all its columns and row
/// groups ([`Reader::set_text_budget`](crate::Reader::set_text_budget)).
#[derive(Clone)]
pub(crate) struct TextBudget {
    pub(crate) held: std::sync::Arc<std::sync::atomic::AtomicUsize>,
    pub(crate) most: usize,
}

/// The error a read gives when its text passes its budget.
pub(crate) const OVER_TEXT_BUDGET: &str = "the text read passed the read's budget";

impl Texts {
    pub(crate) fn new(first: u64, rows: usize, utf8: bool) -> Self {
        Texts {
            chunk: TextChunk {
                first,
                rows,
                utf8,
                ..Default::default()
            },
            utf8,
            dictionary_len: 0,
            fixed: None,
            budget: None,
            charged: 0,
        }
    }

    /// Count the text against `budget`, page by page.
    pub(crate) fn budget(mut self, budget: Option<TextBudget>) -> Self {
        self.budget = budget;
        self
    }

    /// Count the bytes added since the last call; past the budget, fail.
    fn charge(&mut self) -> Result<()> {
        let Some(b) = &self.budget else { return Ok(()) };
        let added = self.chunk.bytes.len() - self.charged;
        self.charged = self.chunk.bytes.len();
        let held = b.held.fetch_add(added, std::sync::atomic::Ordering::Relaxed) + added;
        if held > b.most {
            return Err(Error::new(OVER_TEXT_BUDGET).of(ErrorKind::TooLarge));
        }
        Ok(())
    }

    /// With a budget, before `more` bytes are added: an error if they
    /// would pass it (as [`Texts::charge`] would after the page), else
    /// room for them reserved, an error rather than an abort if there is
    /// none. A large value then fails before it is copied.
    #[inline]
    fn room_for(&mut self, more: usize) -> Result<()> {
        let Some(b) = &self.budget else { return Ok(()) };
        let pending = self.chunk.bytes.len() - self.charged;
        let held = b.held.load(std::sync::atomic::Ordering::Relaxed);
        if held.saturating_add(pending).saturating_add(more) > b.most {
            // Counted as held, as `charge` would, so the reader reports
            // the budget passed.
            b.held.fetch_add(pending.saturating_add(more), std::sync::atomic::Ordering::Relaxed);
            self.charged = self.chunk.bytes.len();
            return Err(Error::new(OVER_TEXT_BUDGET).of(ErrorKind::TooLarge));
        }
        self.chunk.bytes.try_reserve(more).map_err(|_| {
            Error::new(format!("no memory for a text value of {more} bytes")).of(ErrorKind::TooLarge)
        })
    }

    /// Values of a FIXED_LEN_BYTE_ARRAY column, each `width` bytes.
    pub(crate) fn fixed(mut self, width: Option<usize>) -> Self {
        self.fixed = width;
        self
    }

    /// Append values `page.before..page.present` of a page encoded other
    /// than PLAIN or with a dictionary. `scratch` holds the value being
    /// rebuilt.
    fn push_encoded(&mut self, page: &DataPage, scratch: &mut Vec<u8>) -> Result<()> {
        let start = self.chunk.bytes.len();
        let first = self.chunk.ends.len();
        let (skip, n) = (page.before, page.present - page.before);
        let chunk = &mut self.chunk;
        let push = |v: &[u8]| {
            chunk.bytes.extend_from_slice(v);
            chunk.ends.push(chunk.bytes.len());
            Ok(())
        };
        match (page.encoding, self.fixed) {
            (Encoding::DeltaLengthByteArray, None) => {
                encoding::delta_length_byte_array(page.values, skip, n, push)?
            }
            (Encoding::DeltaByteArray, _) => {
                encoding::delta_byte_array(page.values, skip, n, scratch, push)?
            }
            (Encoding::ByteStreamSplit, Some(width)) => {
                let count = encoding::split_count(page.values, width)?;
                if count < page.present {
                    return Err(Error::new("a page holds fewer values than its levels say"));
                }
                let mut push = push;
                if n == 0 {
                    // An all-null window: `width` comes from the file and
                    // is bounded by the value bytes only when there are
                    // values, so allocate nothing.
                    return Ok(());
                }
                scratch.clear();
                scratch.resize(width, 0);
                for i in skip..page.present {
                    encoding::split_value(page.values, count, i, scratch);
                    push(scratch)?;
                }
            }
            (other, _) => return Err(unsupported_encoding(other)),
        }
        if self.utf8 {
            check_utf8(&self.chunk.bytes, start, &self.chunk.ends[first..])?;
        }
        Ok(())
    }

    /// Append PLAIN byte arrays (`count` of them) as values; returns how
    /// many bytes they took.
    fn push_plain(&mut self, values: &[u8], count: usize, keep: Range<usize>) -> Result<usize> {
        if let Some(width) = self.fixed {
            return self.push_fixed(values, width, count, keep);
        }
        let mut at = 0;
        let start = self.chunk.bytes.len();
        for i in 0..count {
            let rest = &values[at..];
            if rest.len() < 4 {
                return Err(Error::new("a page holds fewer values than its levels say"));
            }
            let (v, used) = prefixed(rest, "a text value runs past the end of its page")?;
            at += used;
            if keep.contains(&i) {
                self.room_for(v.len())?;
                self.chunk.bytes.extend_from_slice(v);
                self.chunk.ends.push(self.chunk.bytes.len());
            }
        }
        if self.utf8 {
            check_utf8(
                &self.chunk.bytes,
                start,
                &self.chunk.ends[self.chunk.ends.len() - keep.len().min(self.chunk.ends.len())..],
            )?;
        }
        Ok(at)
    }
}

impl Texts {
    /// PLAIN values of a FIXED_LEN_BYTE_ARRAY column: `count` values of
    /// `width` bytes, no lengths.
    fn push_fixed(
        &mut self,
        values: &[u8],
        width: usize,
        count: usize,
        keep: Range<usize>,
    ) -> Result<usize> {
        let need = count
            .checked_mul(width)
            .filter(|&n| n <= values.len())
            .ok_or_else(|| Error::new("a page holds fewer values than its levels say"))?;
        let start = self.chunk.bytes.len();
        let first = self.chunk.ends.len();
        for i in keep.start..keep.end.min(count) {
            self.chunk
                .bytes
                .extend_from_slice(&values[i * width..(i + 1) * width]);
            self.chunk.ends.push(self.chunk.bytes.len());
        }
        if self.utf8 {
            check_utf8(&self.chunk.bytes, start, &self.chunk.ends[first..])?;
        }
        Ok(need)
    }
}

/// Check that `bytes[start..]` is UTF-8 and that every value boundary in
/// `ends` falls between characters.
fn check_utf8(bytes: &[u8], start: usize, ends: &[usize]) -> Result<()> {
    let s = std::str::from_utf8(&bytes[start..])
        .map_err(|_| Error::new("a text value is not UTF-8"))?;
    if ends.iter().all(|&e| s.is_char_boundary(e - start)) {
        Ok(())
    } else {
        Err(Error::new("a text value is not UTF-8"))
    }
}

impl Consumer for Texts {
    fn dictionary(&mut self, count: usize, values: &[u8]) -> Result<()> {
        if !self.chunk.ends.is_empty() {
            return Err(Error::new("a dictionary page comes after data pages"));
        }
        // Not checked against the budget either (below).
        let budget = self.budget.take();
        let pushed = self.push_plain(values, count, 0..count);
        self.budget = budget;
        pushed?;
        self.dictionary_len = count;
        self.chunk.codes = Some(Vec::with_capacity(self.chunk.rows));
        // Not counted: the dictionary is decoded whole however few rows
        // are read (writers keep it to about a megabyte), so a smaller
        // window would not make it smaller.
        self.charged = self.chunk.bytes.len();
        Ok(())
    }

    fn page(
        &mut self,
        page: &DataPage,
        indices: &mut Vec<u32>,
        scratch: &mut Vec<u8>,
    ) -> Result<()> {
        self.fill_page(page, indices, scratch)?;
        self.charge()
    }
}

impl Texts {
    fn fill_page(
        &mut self,
        page: &DataPage,
        indices: &mut Vec<u32>,
        scratch: &mut Vec<u8>,
    ) -> Result<()> {
        let wanted = page.before..page.present;
        // Values arrive in row order: the chunk's output so far ends at
        // this page's out_at.
        match page.encoding {
            Encoding::Plain
            | Encoding::DeltaLengthByteArray
            | Encoding::DeltaByteArray
            | Encoding::ByteStreamSplit => {
                let base = self.chunk.ends.len();
                if page.encoding == Encoding::Plain {
                    self.push_plain(page.values, page.present, wanted)?;
                } else {
                    self.push_encoded(page, scratch)?;
                }
                match &mut self.chunk.codes {
                    // In a chunk with a dictionary, PLAIN pages (after a
                    // writer gave up on the dictionary) add values to it.
                    Some(codes) => {
                        let mut next = base as u32;
                        rows_of(page, |present| {
                            codes.push(if present {
                                next += 1;
                                next - 1
                            } else {
                                TextChunk::NULL
                            })
                        });
                    }
                    None => {
                        let missing = &mut self.chunk.missing;
                        let ends = &mut self.chunk.ends;
                        // Missing rows get empty values, so that value
                        // `r` is row `r`.
                        let mut values: Vec<usize> = ends.drain(base..).collect();
                        let mut prev = if base == 0 { 0 } else { ends[base - 1] };
                        let mut it = values.drain(..);
                        rows_of(page, |present| {
                            if present {
                                prev = it.next().unwrap_or(prev);
                                missing.push(0);
                            } else {
                                missing.push(1);
                            }
                            ends.push(prev);
                        });
                    }
                }
                Ok(())
            }
            Encoding::PlainDictionary | Encoding::RleDictionary => {
                dictionary_indices(page, indices, self.dictionary_len)?;
                let codes = self.chunk.codes.as_mut().ok_or_else(|| {
                    Error::new("a dictionary-encoded page in a chunk without a dictionary")
                })?;
                let mut vi = 0;
                rows_of(page, |present| {
                    codes.push(if present {
                        vi += 1;
                        indices[vi - 1]
                    } else {
                        TextChunk::NULL
                    })
                });
                Ok(())
            }
            other => Err(unsupported_encoding(other)),
        }
    }
}

/// Call `f(present)` for each wanted row of `page`, in order.
fn rows_of(page: &DataPage, mut f: impl FnMut(bool)) {
    match page.levels {
        None => (0..page.take.len()).for_each(|_| f(true)),
        Some(l) => l.iter().for_each(|&v| f(v == 1)),
    }
}
