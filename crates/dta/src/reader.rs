use std::collections::{BTreeMap, HashMap};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Condvar, Mutex, MutexGuard, PoisonError};
use std::time::Duration;

use crate::cursor::{uint, until_nul, ByteOrder, Cursor};
use crate::encoding::Encoding;
use crate::error::{Error, Result};
use crate::header::{self, text, Layout, Metadata, Sections};
use crate::legacy;
use crate::missing::{self, double_code, float_code, int_code};
use crate::source::{read_vec, SharedSource, Source};
use crate::threads::panic_message;
use crate::types::StorageType;

/// Options for opening a file. The defaults suit every caller; the
/// hidden fields are for tests.
#[derive(Debug, Clone, Copy)]
pub struct Options {
    /// How to decode text in files older than release 118.
    pub encoding: Encoding,
    /// Worker threads for reads: 0 for the default (see
    /// [`crate::threads`]), 1 to read on the calling thread alone.
    pub threads: usize,
    /// Rows are read and decoded this many bytes at a time.
    #[doc(hidden)]
    pub chunk_bytes: usize,
    /// Reads of fewer bytes than this (selected columns' widths times
    /// rows) stay on one thread.
    #[doc(hidden)]
    pub parallel_bytes: usize,
    /// Test only: the worker reading this chunk panics.
    #[doc(hidden)]
    pub panic_on_chunk: Option<usize>,
    /// Test only: the worker reading chunk `.0` waits `.1` ms first.
    #[doc(hidden)]
    pub delay_chunk: Option<(usize, u64)>,
}

impl Default for Options {
    /// With `DTA_TEST_SMALL_CHUNKS=1` in the environment, chunks are
    /// tiny and every read may go parallel, so the bindings' tests
    /// exercise the parallel path on small files.
    fn default() -> Self {
        let small = crate::threads::small_for_tests();
        Options {
            encoding: Encoding::default(),
            threads: 0,
            chunk_bytes: if small { 4096 } else { 2 << 20 },
            parallel_bytes: if small { 0 } else { 16 << 20 },
            panic_on_chunk: None,
            delay_chunk: None,
        }
    }
}

/// The values of one variable over a range of rows.
#[derive(Debug, Clone, PartialEq)]
pub enum Column {
    /// A numeric variable. `values[i]` is NaN where `missing[i]` is not 0
    /// (see [`crate::missing`] for the codes).
    Numbers { values: Vec<f64>, missing: Vec<u8> },
    /// A string variable, as UTF-8: row `i` is `bytes[ends[i-1]..ends[i]]`.
    /// `binary` is empty unless the variable is a strL, where it marks the
    /// rows whose strL is binary rather than text (their bytes are raw).
    Strings { bytes: Vec<u8>, ends: Vec<usize>, binary: Vec<bool> },
}

impl Column {
    pub fn len(&self) -> usize {
        match self {
            Column::Numbers { values, .. } => values.len(),
            Column::Strings { ends, .. } => ends.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn clear(&mut self) {
        match self {
            Column::Numbers { values, missing } => {
                values.clear();
                missing.clear();
            }
            Column::Strings { bytes, ends, binary } => {
                bytes.clear();
                ends.clear();
                binary.clear();
            }
        }
    }

    /// Add `other`'s rows to the end of this column.
    pub fn append(&mut self, other: &Column) {
        match (self, other) {
            (Column::Numbers { values, missing }, Column::Numbers { values: v, missing: m }) => {
                values.extend_from_slice(v);
                missing.extend_from_slice(m);
            }
            (Column::Strings { bytes, ends, binary }, Column::Strings { bytes: b, ends: e, binary: bin }) => {
                let base = bytes.len();
                bytes.extend_from_slice(b);
                ends.extend(e.iter().map(|&x| x + base));
                binary.extend_from_slice(bin);
            }
            _ => {}
        }
    }

    /// The bytes of string row `i`.
    pub fn bytes(&self, i: usize) -> &[u8] {
        match self {
            Column::Strings { bytes, ends, .. } => {
                let start = if i == 0 { 0 } else { ends[i - 1] };
                &bytes[start..ends[i]]
            }
            Column::Numbers { .. } => &[],
        }
    }
}

/// One entry of a value label set.
#[derive(Debug, Clone, PartialEq)]
pub struct ValueLabel {
    /// The labelled value; NaN when `missing` is not 0.
    pub value: f64,
    /// The missing code labelled, or 0 for a number.
    pub missing: u8,
    pub text: String,
}

/// A named table of value labels.
#[derive(Debug, Clone, PartialEq)]
pub struct ValueLabelSet {
    pub name: String,
    pub labels: Vec<ValueLabel>,
}

/// A characteristic: a named text attached to the dataset (`variable` is
/// `_dta`) or to a variable.
#[derive(Debug, Clone, PartialEq)]
pub struct Characteristic {
    pub variable: String,
    pub name: String,
    pub value: String,
}

/// The bits of 2^333.
const OLD_DOUBLE_MISSING: u64 = (1023 + 333) << 52;

/// The strL section is scanned through a window this large.
const WINDOW: u64 = 1 << 20;

/// An open `.dta` file. Opening reads only the header and descriptors;
/// data, value labels, strLs and characteristics are read when asked for.
pub struct Reader<S: Source> {
    source: S,
    meta: Metadata,
    layout: Layout,
    sections: Sections,
    /// Where each variable starts within a row.
    offsets: Vec<usize>,
    row_len: usize,
    strls: Option<HashMap<(u32, u64), StrlEntry>>,
    options: Options,
}

#[derive(Debug, Clone, Copy)]
struct StrlEntry {
    offset: u64,
    len: u32,
    binary: bool,
}

impl<S: Source> Reader<S> {
    pub fn open(mut source: S, options: Options) -> Result<Self> {
        let mut first = [0u8; 1];
        source.read_at(0, &mut first)?;
        let parsed = match first[0] {
            b'<' => header::parse_tagged(&mut source, options.encoding)?,
            _ => legacy::parse_binary(&mut source, options.encoding)?,
        };
        let mut offsets = Vec::with_capacity(parsed.meta.variables.len());
        let mut row_len = 0;
        for v in &parsed.meta.variables {
            offsets.push(row_len);
            row_len += v.storage.width();
        }
        Ok(Reader {
            source,
            meta: parsed.meta,
            layout: parsed.layout,
            sections: parsed.sections,
            offsets,
            row_len,
            strls: None,
            options,
        })
    }

    pub fn metadata(&self) -> &Metadata {
        &self.meta
    }

    /// Read `count` rows starting at row `start` of the variables at
    /// `columns` (indices into the variable list, in any order).
    pub fn read(&mut self, columns: &[usize], start: u64, count: u64) -> Result<Vec<Column>> {
        // Check the request before reserving room for it.
        let rows = self.check(columns, start, count)?;
        let mut out: Vec<Column> = columns.iter().map(|&c| self.empty_column(c, rows)).collect();
        self.read_chunks(columns, start, count, None, |_, chunk| {
            for (all, part) in out.iter_mut().zip(chunk) {
                all.append(part);
            }
            Ok(())
        })?;
        Ok(out)
    }

    /// Like [`Reader::read`], but hands over the rows a chunk at a time
    /// (about 2 MiB decoded each), so a caller can copy them where
    /// they belong without holding a second copy of the whole read.
    /// `f` gets the first row of the chunk, counted from `start`, and one
    /// column per entry of `columns`, in row order.
    ///
    /// With a `budget` in bytes, the read stops after the row at which the
    /// decoded output (values, missing codes, string bytes and offsets,
    /// strL payloads) reaches it, so the caller holds at most the budget
    /// plus one row. Returns how many rows were read.
    pub fn read_chunks(
        &mut self,
        columns: &[usize],
        start: u64,
        count: u64,
        budget: Option<usize>,
        mut f: impl FnMut(usize, &[Column]) -> Result<()>,
    ) -> Result<u64> {
        // A chunk whose rows failed to read comes with `upto` 0; `f` sees
        // only whole chunks, as a serial read gives them.
        let whole = |first, chunk: &[Column], _: &[bool], upto| if upto == chunk.len() { f(first, chunk) } else { Ok(()) };
        self.read_chunks_with(columns, start, count, budget, &|_, _, _| Ok(false), whole, || Ok(()))
    }

    /// [`Reader::read_chunks`] that may decode chunks on worker threads
    /// (see [`Options::threads`]). A worker calls `each(k, first,
    /// column)` for each column of its chunk in order; `each` puts the
    /// column where it belongs and returns `true`, or returns `false` to
    /// leave it to `rest`. The calling thread then calls `rest(first,
    /// chunk, taken, upto)` for the chunks in row order: it handles, in
    /// order, the columns before `upto` that `each` did not take. `upto`
    /// is the column count unless `each` failed at that column, whose
    /// error is returned after `rest` (unless `rest` fails first).
    /// `poll` is called on the calling thread at least once per chunk and
    /// every 100 ms while it waits; an error from it stops the read.
    ///
    /// Reads go to workers only when they are large, have no `budget`,
    /// select no strL and the source can be read from several threads;
    /// otherwise this reads on the calling thread and never calls `each`.
    #[allow(clippy::too_many_arguments)]
    pub fn read_chunks_with(
        &mut self,
        columns: &[usize],
        start: u64,
        count: u64,
        budget: Option<usize>,
        each: &(dyn Fn(usize, usize, &Column) -> Result<bool> + Sync),
        mut rest: impl FnMut(usize, &[Column], &[bool], usize) -> Result<()>,
        mut poll: impl FnMut() -> Result<()>,
    ) -> Result<u64> {
        let count = self.check(columns, start, count)?;
        if count == 0 {
            return Ok(0);
        }
        let has_strls = columns.iter().any(|&c| self.meta.variables[c].storage == StorageType::StrL);
        if has_strls && self.strls.is_none() {
            self.strls = Some(self.index_strls()?);
        }
        let (rows_per_chunk, decoded_row) = self.chunk_rows(columns, budget);
        let threads = self.threads_for(columns, count as u64, budget);
        if threads > 1 {
            if let Some(src) = self.source.shared() {
                let read = ParallelRead {
                    src,
                    decoder: self.decoder(),
                    data: self.sections.data + start * self.row_len as u64,
                    row_len: self.row_len,
                    offsets: columns.iter().map(|&c| self.offsets[c]).collect(),
                    storage: columns.iter().map(|&c| self.meta.variables[c].storage).collect(),
                    count,
                    rows_per_chunk,
                    threads,
                    panic_on: self.options.panic_on_chunk,
                    delay: self.options.delay_chunk,
                };
                return read.run(each, &mut rest, &mut poll).map(|()| count as u64);
            }
        }
        let mut chunk: Vec<Column> = columns.iter().map(|&c| self.empty_column(c, rows_per_chunk.min(count))).collect();
        let none_taken = vec![false; columns.len()];
        let decoder = self.decoder();
        let mut refs: Vec<[u8; 8]> = Vec::new();
        let mut buf = vec![0u8; rows_per_chunk.min(count) * self.row_len];
        let mut done = 0;
        let mut used = 0usize;
        while done < count {
            let mut n = rows_per_chunk.min(count - done);
            let offset = self.sections.data + (start + done as u64) * self.row_len as u64;
            self.source.read_at(offset, &mut buf[..n * self.row_len])?;
            if let Some(budget) = budget {
                // Stop after the row that reaches the budget; strL
                // payload sizes come from the index, before reading them.
                let mut take = 0;
                while take < n && used < budget {
                    let row = &buf[take * self.row_len..(take + 1) * self.row_len];
                    used += decoded_row;
                    for &c in columns.iter().filter(|&&c| self.meta.variables[c].storage == StorageType::StrL) {
                        let cell = <[u8; 8]>::try_from(&row[self.offsets[c]..self.offsets[c] + 8]).unwrap_or_default();
                        used = used.saturating_add(self.strl_entry(&cell)?.map_or(0, |e| (e.len as usize).saturating_mul(3)));
                    }
                    take += 1;
                }
                n = take;
            }
            let bytes = &buf[..n * self.row_len];
            for (k, &c) in columns.iter().enumerate() {
                chunk[k].clear();
                let cells = Cells { rows: bytes, row_len: self.row_len, offset: self.offsets[c] };
                match self.meta.variables[c].storage {
                    StorageType::StrL => {
                        refs.clear();
                        refs.extend(cells.iter(8).map(|b| <[u8; 8]>::try_from(b).unwrap_or_default()));
                        self.resolve_strls(&refs, &mut chunk[k])?;
                    }
                    storage => decoder.decode(storage, &cells, &mut chunk[k]),
                }
            }
            poll()?;
            rest(done, &chunk, &none_taken, columns.len())?;
            done += n;
            if budget.is_some_and(|b| used >= b) {
                break;
            }
        }
        Ok(done as u64)
    }

    /// Rows per chunk, and decoded bytes per row (not counting strL
    /// payloads), for a read of `columns`.
    fn chunk_rows(&self, columns: &[usize], budget: Option<usize>) -> (usize, usize) {
        // Text can grow up to 3x when decoded to UTF-8 (a Windows-1252
        // byte, or an invalid byte replaced by U+FFFD).
        let word = std::mem::size_of::<usize>();
        let decoded_row: usize = columns
            .iter()
            .map(|&c| match self.meta.variables[c].storage {
                StorageType::Str(w) => 3 * w as usize + word,
                StorageType::StrL => 1 + word,
                _ => 9,
            })
            .sum();
        // A byte decodes to 9 bytes (a double and a missing code), so size
        // chunks by whichever is larger, the rows or their decoding.
        let widest = self.row_len.max(decoded_row).max(1);
        let mut rows_per_chunk = (self.options.chunk_bytes.max(1) / widest).max(1);
        if let Some(budget) = budget {
            rows_per_chunk = rows_per_chunk.min((budget / decoded_row.max(1)).max(1));
        }
        (rows_per_chunk, decoded_row)
    }

    /// How many threads [`Reader::read_chunks_with`] would use for this
    /// read: 1 unless it is large, has no `budget`, selects no strL, has
    /// rows that fit a chunk, and the source can be read from several
    /// threads. A caller can prepare for workers with it (dtaparser
    /// touches the pages of R vectors first).
    pub fn threads_for(&self, columns: &[usize], count: u64, budget: Option<usize>) -> usize {
        let vars = &self.meta.variables;
        if budget.is_some() || columns.iter().any(|&c| vars.get(c).is_none_or(|v| v.storage == StorageType::StrL)) {
            return 1;
        }
        let (rows_per_chunk, decoded_row) = self.chunk_rows(columns, budget);
        let selected: usize = columns.iter().map(|&c| vars[c].storage.width()).sum();
        let large = self.row_len.max(decoded_row) <= self.options.chunk_bytes
            && count > rows_per_chunk as u64
            && (selected as u64).saturating_mul(count) >= self.options.parallel_bytes as u64;
        if !large || self.source.shared().is_none() {
            return 1;
        }
        let threads = crate::threads::resolve(self.options.threads);
        // A read of a few columns of wide rows mostly copies rows out of
        // the file; more threads then add more CPU than they save time
        // (wide.dta, five columns: 1.27x the CPU at four threads, 1.12x
        // at two).
        if self.options.threads == 0 && selected * 4 < self.row_len {
            return threads.min(2);
        }
        threads
    }

    fn decoder(&self) -> Decoder {
        Decoder {
            big: self.meta.byte_order == ByteOrder::Big,
            extended: self.layout.extended_missing,
            old_double_missing: self.layout.release <= 105,
            encoding: self.meta.encoding,
        }
    }

    /// The number of rows `count` as a usize, or an error if a column or
    /// a row of the request is not in the file.
    fn check(&self, columns: &[usize], start: u64, count: u64) -> Result<usize> {
        let nvar = self.meta.variables.len();
        if let Some(&bad) = columns.iter().find(|&&c| c >= nvar) {
            return Err(Error::new(format!("there is no variable {bad}; the file has {nvar}")));
        }
        if start.checked_add(count).is_none_or(|end| end > self.meta.nobs) {
            return Err(Error::new(format!(
                "rows {start} to {} are past the {} rows in the file",
                start.saturating_add(count),
                self.meta.nobs
            )));
        }
        usize::try_from(count).map_err(|_| Error::new("too many rows for one read"))
    }

    /// A column with room for `rows`, so decoding a chunk never regrows it.
    fn empty_column(&self, c: usize, rows: usize) -> Column {
        if self.meta.variables[c].storage.is_numeric() {
            Column::Numbers { values: Vec::with_capacity(rows), missing: Vec::with_capacity(rows) }
        } else {
            Column::Strings { bytes: Vec::new(), ends: Vec::with_capacity(rows), binary: Vec::new() }
        }
    }

    /// The (variable, observation) a strL cell points to, with the
    /// variable number in the first `v_len` bytes.
    fn strl_key(&self, cell: &[u8; 8], v_len: usize) -> (u32, u64) {
        let order = self.meta.byte_order;
        (uint(&cell[..v_len], order) as u32, uint(&cell[v_len..], order))
    }

    /// The strL entry a cell points to; None for the empty reference.
    fn strl_entry(&self, cell: &[u8; 8]) -> Result<Option<StrlEntry>> {
        let key = self.strl_key(cell, self.layout.strl_v_len);
        if key == (0, 0) {
            return Ok(None);
        }
        let index = self.strls.as_ref().ok_or_else(|| Error::new("strLs not indexed"))?;
        // haven 2.5.5 writes 119 cells with the 118 split (ADR 0005).
        let found = index
            .get(&key)
            .or_else(|| (self.layout.release == 119).then(|| index.get(&self.strl_key(cell, 2))).flatten());
        match found {
            Some(e) => Ok(Some(*e)),
            None => Err(Error::new(format!(
                "a strL refers to variable {} observation {}, which the strL section lacks",
                key.0, key.1
            ))),
        }
    }

    fn resolve_strls(&mut self, refs: &[[u8; 8]], out: &mut Column) -> Result<()> {
        if self.strls.is_none() {
            self.strls = Some(self.index_strls()?);
        }
        let Column::Strings { bytes, ends, binary } = out else { return Ok(()) };
        binary.reserve(refs.len());
        let enc = self.meta.encoding;
        let mut payload = Vec::new();
        for cell in refs {
            let mut is_binary = false;
            if let Some(entry) = self.strl_entry(cell)? {
                // A strL can declare up to 4 GiB; in wasm that may not fit,
                // which must be an error, not a trap.
                let len = entry.len as usize;
                let room = len.saturating_mul(3);
                if payload.try_reserve(len.saturating_sub(payload.len())).is_err() || bytes.try_reserve(room).is_err() {
                    return Err(Error::new(format!("a strL of {len} bytes is too large to read here")));
                }
                payload.resize(len, 0);
                self.source.read_at(entry.offset, &mut payload)?;
                is_binary = entry.binary;
                if is_binary {
                    bytes.extend_from_slice(&payload);
                } else {
                    // Text strLs end with a NUL.
                    let text = payload.strip_suffix(&[0]).unwrap_or(&payload);
                    enc.decode_into(text, bytes);
                }
            }
            ends.push(bytes.len());
            binary.push(is_binary);
        }
        Ok(())
    }

    /// One pass over the strL section, through a 1 MiB window,
    /// recording where each entry's payload is. Payloads themselves are
    /// read only when asked for.
    fn index_strls(&mut self) -> Result<HashMap<(u32, u64), StrlEntry>> {
        let (start, end) = self.sections.strls;
        let o_len = if self.layout.release == 117 { 4 } else { 8 };
        let head_len = 3 + 4 + o_len + 1 + 4;
        let mut index = HashMap::new();
        let mut window: Vec<u8> = Vec::new();
        let mut window_at = start;
        let mut pos = start;
        while pos < end {
            if end - pos < head_len as u64 {
                return Err(Error::at(pos, "truncated strL entry"));
            }
            if pos + head_len as u64 > window_at + window.len() as u64 {
                let len = (end - pos).min(WINDOW);
                window = read_vec(&mut self.source, pos, len)?;
                window_at = pos;
            }
            let at = (pos - window_at) as usize;
            let mut c = Cursor::new(&window[at..at + head_len], pos, self.meta.byte_order);
            c.tag("GSO")?;
            let v = c.u32()?;
            let o = c.uint(o_len)?;
            let kind = c.u8()?;
            let len = c.u32()?;
            let payload = pos + head_len as u64;
            if payload + len as u64 > end {
                return Err(Error::at(pos, "strL entry runs past the strL section"));
            }
            let binary = match kind {
                129 => true,
                130 => false,
                _ => return Err(Error::at(pos, format!("unknown strL type {kind}"))),
            };
            index.insert((v, o), StrlEntry { offset: payload, len, binary });
            pos = payload + len as u64;
        }
        Ok(index)
    }

    /// Every value label set in the file, in file order.
    pub fn value_labels(&mut self) -> Result<Vec<ValueLabelSet>> {
        let (start, end) = self.sections.value_labels;
        let section = read_vec(&mut self.source, start, end - start)?;
        let mut c = Cursor::new(&section, start, self.meta.byte_order);
        let enc = self.meta.encoding;
        let release = self.layout.release;
        let mut sets = Vec::new();
        while c.remaining() > 0 {
            if release <= 105 {
                sets.push(self.old_label_set(&mut c)?);
                continue;
            }
            if release >= 117 {
                c.tag("<lbl>")?;
            }
            let at = c.offset();
            let len = usize::try_from(c.i32()?).map_err(|_| Error::at(at, "negative value label table length"))?;
            let name = text(c.bytes(self.layout.name_len)?, enc);
            c.skip(3)?;
            let table = c.bytes(len)?;
            sets.push(ValueLabelSet { name, labels: self.label_table(table, c.offset() - len as u64)? });
            if release >= 117 {
                c.tag("</lbl>")?;
            }
        }
        Ok(sets)
    }

    /// The layout of releases 105 and earlier: a count, a name, then the
    /// values (i16) and 8-byte texts.
    fn old_label_set(&self, c: &mut Cursor) -> Result<ValueLabelSet> {
        let n = c.u16()? as usize;
        let name = text(c.bytes(9)?, self.meta.encoding);
        c.skip(1)?;
        let values: Vec<i16> = (0..n).map(|_| c.i16()).collect::<Result<_>>()?;
        let mut labels = Vec::with_capacity(n);
        for v in values {
            labels.push(ValueLabel { value: v as f64, missing: 0, text: text(c.bytes(8)?, self.meta.encoding) });
        }
        Ok(ValueLabelSet { name, labels })
    }

    /// The modern (108+) table: count, text length, text offsets, values, text.
    fn label_table(&self, table: &[u8], base: u64) -> Result<Vec<ValueLabel>> {
        let mut c = Cursor::new(table, base, self.meta.byte_order);
        let n = c.i32()?;
        let text_len = c.i32()?;
        let (Ok(n), Ok(text_len)) = (usize::try_from(n), usize::try_from(text_len)) else {
            return Err(Error::at(base, "negative count in a value label table"));
        };
        if n.checked_mul(8).and_then(|x| x.checked_add(8 + text_len)) != Some(table.len()) {
            return Err(Error::at(base, "value label table size does not add up"));
        }
        let offs: Vec<i32> = (0..n).map(|_| c.i32()).collect::<Result<_>>()?;
        let vals: Vec<i32> = (0..n).map(|_| c.i32()).collect::<Result<_>>()?;
        let txt = c.bytes(text_len)?;
        let mut labels = Vec::with_capacity(n);
        for (off, val) in offs.into_iter().zip(vals) {
            let Some(rest) = usize::try_from(off).ok().and_then(|o| txt.get(o..)) else {
                return Err(Error::at(base, "value label text offset out of range"));
            };
            // Before 113 only the type's maximum is missing, as in `decode`.
            let first = if self.layout.extended_missing { missing::LONG_MISSING } else { i32::MAX };
            let code = int_code(val as i64, first as i64, self.layout.extended_missing);
            labels.push(ValueLabel {
                value: if code == 0 { val as f64 } else { f64::NAN },
                missing: code,
                text: text(rest, self.meta.encoding),
            });
        }
        Ok(labels)
    }

    /// Every characteristic, in file order. Notes are among them.
    pub fn characteristics(&mut self) -> Result<Vec<Characteristic>> {
        let (start, end) = self.sections.characteristics;
        let section = read_vec(&mut self.source, start, end - start)?;
        let mut c = Cursor::new(&section, start, self.meta.byte_order);
        let name_len = self.layout.name_len;
        let enc = self.meta.encoding;
        let release = self.layout.release;
        let mut out = Vec::new();
        while c.remaining() > 0 {
            let len = if release >= 117 {
                c.tag("<ch>")?;
                c.u32()? as usize
            } else {
                // Records of (type, length, body); type 1 is a characteristic.
                let kind = c.u8()?;
                let len = if release >= 110 { c.i32()? as usize } else { c.i16()? as usize };
                if kind != 1 {
                    c.skip(len)?;
                    continue;
                }
                len
            };
            let at = c.offset();
            let body = c.bytes(len)?;
            if len < 2 * name_len {
                return Err(Error::at(at, "characteristic too short"));
            }
            out.push(Characteristic {
                variable: text(&body[..name_len], enc),
                name: text(&body[name_len..2 * name_len], enc),
                value: text(&body[2 * name_len..], enc),
            });
            if release >= 117 {
                c.tag("</ch>")?;
            }
        }
        Ok(out)
    }

    /// The dataset's notes in order: the `_dta` characteristics `note1`,
    /// `note2`, ... (`note0` holds their count and is not a note).
    pub fn notes(&mut self) -> Result<Vec<String>> {
        let mut notes: Vec<(u32, String)> = self
            .characteristics()?
            .into_iter()
            .filter(|ch| ch.variable == "_dta")
            .filter_map(|ch| {
                let n: u32 = ch.name.strip_prefix("note")?.parse().ok()?;
                (n > 0).then_some((n, ch.value))
            })
            .collect();
        notes.sort_by_key(|(n, _)| *n);
        Ok(notes.into_iter().map(|(_, v)| v).collect())
    }
}

/// What decoding a cell needs to know about the file.
#[derive(Clone, Copy)]
struct Decoder {
    big: bool,
    extended: bool,
    /// Releases 105 and earlier also wrote 2^333 for a missing double.
    old_double_missing: bool,
    encoding: Encoding,
}

impl Decoder {
    fn decode(&self, storage: StorageType, cells: &Cells, out: &mut Column) {
        let big = self.big;
        let ext = self.extended;
        // Before 113 each integer type's single missing value is its maximum.
        let (byte_first, int_first, long_first) = if ext {
            (missing::BYTE_MISSING as i64, missing::INT_MISSING as i64, missing::LONG_MISSING as i64)
        } else {
            (i8::MAX as i64, i16::MAX as i64, i32::MAX as i64)
        };
        match (storage, out) {
            (StorageType::Str(w), Column::Strings { bytes, ends, .. }) => {
                let enc = self.encoding;
                for b in cells.iter(w as usize) {
                    enc.decode_into(until_nul(b), bytes);
                    ends.push(bytes.len());
                }
            }
            (storage, Column::Numbers { values, missing }) => {
                match storage {
                    StorageType::Byte => numbers(cells, 1, values, missing, |b| {
                        let v = b[0] as i8 as i64;
                        (v as f64, int_code(v, byte_first, ext))
                    }),
                    StorageType::Int => numbers(cells, 2, values, missing, |b| {
                        let a = [b[0], b[1]];
                        let v = if big { i16::from_be_bytes(a) } else { i16::from_le_bytes(a) } as i64;
                        (v as f64, int_code(v, int_first, ext))
                    }),
                    StorageType::Long => numbers(cells, 4, values, missing, |b| {
                        let a = [b[0], b[1], b[2], b[3]];
                        let v = if big { i32::from_be_bytes(a) } else { i32::from_le_bytes(a) } as i64;
                        (v as f64, int_code(v, long_first, ext))
                    }),
                    StorageType::Float => numbers(cells, 4, values, missing, |b| {
                        let a = [b[0], b[1], b[2], b[3]];
                        let bits = if big { u32::from_be_bytes(a) } else { u32::from_le_bytes(a) };
                        (f32::from_bits(bits) as f64, float_code(bits, ext))
                    }),
                    StorageType::Double => {
                        // Releases 105 and earlier also wrote 2^333 for missing.
                        let old_missing = self.old_double_missing.then_some(OLD_DOUBLE_MISSING);
                        numbers(cells, 8, values, missing, |b| {
                            let a: [u8; 8] = b.try_into().unwrap_or_default();
                            let bits = if big { u64::from_be_bytes(a) } else { u64::from_le_bytes(a) };
                            let code = if Some(bits) == old_missing { missing::SYSTEM } else { double_code(bits, ext) };
                            (f64::from_bits(bits), code)
                        })
                    }
                    StorageType::Str(_) | StorageType::StrL => {}
                }
            }
            _ => {}
        }
    }
}

/// The caller's handler of a chunk's columns (see [`Reader::read_chunks_with`]).
type Rest<'f> = dyn FnMut(usize, &[Column], &[bool], usize) -> Result<()> + 'f;

/// A read shared out to workers, chunk by chunk (see
/// [`Reader::read_chunks_with`]).
struct ParallelRead<'r> {
    src: &'r dyn SharedSource,
    decoder: Decoder,
    /// Where the first row read starts.
    data: u64,
    row_len: usize,
    /// Each selected column's offset in the row and storage type.
    offsets: Vec<usize>,
    storage: Vec<StorageType>,
    count: usize,
    rows_per_chunk: usize,
    threads: usize,
    panic_on: Option<usize>,
    delay: Option<(usize, u64)>,
}

/// A chunk's buffers, reused from chunk to chunk.
struct ChunkBuf {
    raw: Vec<u8>,
    columns: Vec<Column>,
    taken: Vec<bool>,
}

/// A chunk a worker has finished: its columns, and where `each` or the
/// read failed.
struct Finished {
    buf: ChunkBuf,
    upto: usize,
    error: Option<Error>,
}

#[derive(Default)]
struct ReadState {
    /// The next chunk to take, and how many the caller has used.
    next: usize,
    used: usize,
    finished: BTreeMap<usize, Finished>,
    free: Vec<ChunkBuf>,
    stop: bool,
}

#[derive(Default)]
struct ReadShared {
    state: Mutex<ReadState>,
    /// Workers wait here for room in the window.
    room: Condvar,
    /// The caller waits here for the next chunk.
    arrived: Condvar,
}

impl ReadShared {
    fn lock(&self) -> MutexGuard<'_, ReadState> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// Stops the workers when dropped, so an early return or a panic on the
/// caller never leaves them waiting.
struct StopReadOnDrop<'s>(&'s ReadShared);

impl Drop for StopReadOnDrop<'_> {
    fn drop(&mut self) {
        self.0.lock().stop = true;
        self.0.room.notify_all();
        self.0.arrived.notify_all();
    }
}

impl ParallelRead<'_> {
    fn chunks(&self) -> usize {
        self.count.div_ceil(self.rows_per_chunk)
    }

    fn new_buf(&self) -> ChunkBuf {
        let rows = self.rows_per_chunk.min(self.count);
        let columns = self
            .storage
            .iter()
            .map(|t| match t {
                StorageType::Str(w) => {
                    // Room for the most a chunk can decode to, so the
                    // buffer never grows past the chunk size.
                    Column::Strings { bytes: Vec::with_capacity(3 * *w as usize * rows), ends: Vec::with_capacity(rows), binary: Vec::new() }
                }
                _ => Column::Numbers { values: Vec::with_capacity(rows), missing: Vec::with_capacity(rows) },
            })
            .collect();
        ChunkBuf { raw: Vec::with_capacity(rows * self.row_len), columns, taken: vec![false; self.storage.len()] }
    }

    /// Read and decode chunk `n` into `buf`, and hand its columns to `each`.
    fn process(&self, n: usize, mut buf: ChunkBuf, each: &(dyn Fn(usize, usize, &Column) -> Result<bool> + Sync)) -> Finished {
        if let Some((_, ms)) = self.delay.filter(|&(chunk, _)| chunk == n) {
            std::thread::sleep(Duration::from_millis(ms));
        }
        if self.panic_on == Some(n) {
            panic!("test panic on chunk {n}");
        }
        let first = n * self.rows_per_chunk;
        let rows = self.rows_per_chunk.min(self.count - first);
        buf.raw.resize(rows * self.row_len, 0);
        buf.taken.fill(false);
        if let Err(e) = self.src.read_at_shared(self.data + (first * self.row_len) as u64, &mut buf.raw) {
            return Finished { buf, upto: 0, error: Some(e) };
        }
        for ((column, &offset), &storage) in buf.columns.iter_mut().zip(&self.offsets).zip(&self.storage) {
            column.clear();
            self.decoder.decode(storage, &Cells { rows: &buf.raw, row_len: self.row_len, offset }, column);
        }
        for (k, column) in buf.columns.iter().enumerate() {
            match each(k, first, column) {
                Ok(taken) => buf.taken[k] = taken,
                Err(e) => return Finished { upto: k, error: Some(e), buf },
            }
        }
        Finished { upto: buf.columns.len(), error: None, buf }
    }

    /// A worker: take chunks while there are any and room in the window.
    fn work(&self, shared: &ReadShared, each: &(dyn Fn(usize, usize, &Column) -> Result<bool> + Sync)) {
        let window = self.threads + 2;
        loop {
            let (n, buf) = {
                let mut st = shared.lock();
                loop {
                    if st.stop || st.next >= self.chunks() {
                        return;
                    }
                    if st.next < st.used + window {
                        break;
                    }
                    st = shared.room.wait(st).unwrap_or_else(PoisonError::into_inner);
                }
                let n = st.next;
                st.next += 1;
                (n, st.free.pop())
            };
            let buf = buf.unwrap_or_else(|| self.new_buf());
            let finished = catch_unwind(AssertUnwindSafe(|| self.process(n, buf, each))).unwrap_or_else(|p| Finished {
                buf: self.new_buf(),
                upto: 0,
                error: Some(Error::new(format!("a reader thread failed: {}", panic_message(&*p)))),
            });
            shared.lock().finished.insert(n, finished);
            shared.arrived.notify_one();
        }
    }

    fn run(
        &self,
        each: &(dyn Fn(usize, usize, &Column) -> Result<bool> + Sync),
        rest: &mut Rest,
        poll: &mut dyn FnMut() -> Result<()>,
    ) -> Result<()> {
        let shared = ReadShared::default();
        std::thread::scope(|scope| {
            let _guard = StopReadOnDrop(&shared);
            let workers = (0..self.threads)
                .filter_map(|_| std::thread::Builder::new().spawn_scoped(scope, || self.work(&shared, each)).ok())
                .count();
            for n in 0..self.chunks() {
                let finished = if workers == 0 {
                    // No thread could start: read on this one.
                    self.process(n, shared.lock().free.pop().unwrap_or_else(|| self.new_buf()), each)
                } else {
                    let mut st = shared.lock();
                    loop {
                        if let Some(f) = st.finished.remove(&n) {
                            break f;
                        }
                        let (next, timeout) = shared
                            .arrived
                            .wait_timeout(st, Duration::from_millis(100))
                            .unwrap_or_else(PoisonError::into_inner);
                        st = next;
                        if timeout.timed_out() {
                            drop(st);
                            poll()?;
                            st = shared.lock();
                        }
                    }
                };
                poll()?;
                let Finished { buf, upto, error } = finished;
                let result = rest(n * self.rows_per_chunk, &buf.columns, &buf.taken, upto);
                {
                    let mut st = shared.lock();
                    st.used += 1;
                    st.free.push(buf);
                }
                shared.room.notify_one();
                result?;
                if let Some(e) = error {
                    return Err(e);
                }
            }
            Ok(())
        })
    }
}

/// Append the numbers in `cells` (each `width` bytes, decoded by `f` to a
/// value and missing code) to `values` and `missing`; a missing value's
/// value is NaN.
#[inline]
fn numbers(cells: &Cells, width: usize, values: &mut Vec<f64>, missing: &mut Vec<u8>, f: impl Fn(&[u8]) -> (f64, u8)) {
    let n = cells.rows.len() / cells.row_len.max(1);
    let start = values.len();
    values.resize(start + n, 0.0);
    missing.resize(start + n, 0);
    for ((b, v), m) in cells.iter(width).zip(&mut values[start..]).zip(&mut missing[start..]) {
        let (x, code) = f(b);
        *v = if code == 0 { x } else { f64::NAN };
        *m = code;
    }
}

/// One variable's cells in a run of rows.
struct Cells<'a> {
    rows: &'a [u8],
    row_len: usize,
    offset: usize,
}

impl<'a> Cells<'a> {
    fn iter(&self, width: usize) -> impl Iterator<Item = &'a [u8]> + 'a {
        let offset = self.offset;
        self.rows.chunks_exact(self.row_len).map(move |row| &row[offset..offset + width])
    }
}
