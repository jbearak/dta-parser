//! Opening a Parquet file and reading columns from it into the caller's
//! memory.

use std::collections::HashMap;
use std::ops::Range;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Condvar, Mutex, MutexGuard, PoisonError};

use crate::decode::{
    self, Booleans, Chunk, NumberOut, Numbers as NumberConsumer, Physical, Scratch, TextChunk,
    Texts,
};
use crate::format::{Codec, FileMetaData, OffsetIndex, PhysicalType};
use crate::profile::{self, Profile};
use crate::schema::{self, ColumnInfo, ColumnType, Role};
use dta::{missing, Error, ErrorKind, Result, SharedSource, Source};

/// What to do with nested columns (lists, maps, groups), which are not
/// read.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Nested {
    /// [`Reader::data_columns`] fails, naming them.
    #[default]
    Error,
    /// [`Reader::data_columns`] leaves them out.
    Skip,
}

/// Options for opening a file.
#[derive(Debug, Clone, Copy)]
pub struct ReadOptions {
    /// Worker threads for reads: 0 for the default (see
    /// [`dta::threads`]), 1 to read on the calling thread alone.
    pub threads: usize,
    pub nested: Nested,
    /// Reads of fewer uncompressed bytes than this stay on one thread.
    #[doc(hidden)]
    pub parallel_bytes: u64,
}

impl Default for ReadOptions {
    fn default() -> Self {
        let small = std::env::var("DTA_TEST_SMALL_CHUNKS").is_ok_and(|v| v == "1");
        ReadOptions {
            threads: 0,
            nested: Nested::Error,
            parallel_bytes: if small { 0 } else { 16 << 20 },
        }
    }
}

mod sealed {
    pub trait Sealed {}
    impl Sealed for i8 {}
    impl Sealed for i16 {}
    impl Sealed for i32 {}
    impl Sealed for i64 {}
    impl Sealed for u8 {}
    impl Sealed for f32 {}
    impl Sealed for f64 {}
}

/// A number type the reader can write into: `i8`, `i16`, `i32`, `i64`,
/// `u8`, `f32` or `f64`. A value the type cannot hold exactly is an error
/// naming the column and row. An integer type reads a DOUBLE column only
/// when the profile gives it an integer storage type
/// ([`ColumnInfo::storage`]).
pub trait Element: Copy + Send + Sync + std::fmt::Debug + 'static + sealed::Sealed {
    #[doc(hidden)]
    const NAME: &'static str;
    #[doc(hidden)]
    fn from_i32(v: i32) -> Option<Self>;
    #[doc(hidden)]
    fn from_i64(v: i64) -> Option<Self>;
    #[doc(hidden)]
    fn from_f32(v: f32) -> Option<Self>;
    #[doc(hidden)]
    fn from_f64(v: f64) -> Option<Self>;
    /// Whether a column of `kind` can be read into this type at all.
    #[doc(hidden)]
    fn accepts(kind: &ColumnType) -> bool;
}

macro_rules! integer_element {
    ($t:ty, $name:expr) => {
        impl Element for $t {
            const NAME: &'static str = $name;
            #[inline]
            fn from_i32(v: i32) -> Option<Self> {
                <$t>::try_from(v).ok()
            }
            #[inline]
            fn from_i64(v: i64) -> Option<Self> {
                <$t>::try_from(v).ok()
            }
            fn from_f32(_: f32) -> Option<Self> {
                None
            }
            /// Whole numbers in range only; NaN is neither.
            #[inline]
            fn from_f64(v: f64) -> Option<Self> {
                // `MAX as f64 + 1.0` is exact for every type here but i64,
                // where it rounds to 2^63, which is still the right bound.
                (v.fract() == 0.0 && v >= <$t>::MIN as f64 && v < <$t>::MAX as f64 + 1.0)
                    .then_some(v as $t)
            }
            fn accepts(kind: &ColumnType) -> bool {
                use ColumnType::*;
                matches!(
                    kind,
                    Int8 | Int16 | Int32 | Int64 | Boolean | Date | Timestamp { .. }
                )
            }
        }
    };
}

integer_element!(i8, "an 8-bit integer");
integer_element!(i16, "a 16-bit integer");
integer_element!(i32, "a 32-bit integer");
integer_element!(i64, "a 64-bit integer");
integer_element!(u8, "an unsigned 8-bit integer");

/// Below 2^63 and at least -2^63, where `as i64` does not saturate.
const I64_LIMIT: f64 = 9_223_372_036_854_775_808.0;

impl Element for f32 {
    const NAME: &'static str = "a 32-bit float";
    #[inline]
    fn from_i32(v: i32) -> Option<Self> {
        let f = v as f32;
        (f < 2_147_483_648.0 && f as i32 == v).then_some(f)
    }
    #[inline]
    fn from_i64(v: i64) -> Option<Self> {
        let f = v as f32;
        ((f as f64) < I64_LIMIT && f as i64 == v).then_some(f)
    }
    #[inline]
    fn from_f32(v: f32) -> Option<Self> {
        Some(v)
    }
    #[inline]
    fn from_f64(v: f64) -> Option<Self> {
        let f = v as f32;
        (f as f64 == v || v.is_nan()).then_some(f)
    }
    fn accepts(kind: &ColumnType) -> bool {
        kind.is_numeric()
    }
}

impl Element for f64 {
    const NAME: &'static str = "a double";
    #[inline]
    fn from_i32(v: i32) -> Option<Self> {
        Some(f64::from(v))
    }
    #[inline]
    fn from_i64(v: i64) -> Option<Self> {
        let f = v as f64;
        (f < I64_LIMIT && f as i64 == v).then_some(f)
    }
    #[inline]
    fn from_f32(v: f32) -> Option<Self> {
        Some(f64::from(v))
    }
    #[inline]
    fn from_f64(v: f64) -> Option<Self> {
        Some(v)
    }
    fn accepts(kind: &ColumnType) -> bool {
        kind.is_numeric()
    }
}

/// Where a numeric column's values go: a slice of the read's length,
/// and optionally a missing code per row.
pub struct Numbers<'a, T> {
    pub values: &'a mut [T],
    /// Per row, 0 for a value, 1 for `.` (a null) and 2 to 27 for `.a`
    /// to `.z` (a tagged NaN in a DOUBLE column).
    pub codes: Option<&'a mut [u8]>,
    /// The value written for each missing code: index 0 for `.`, 1 to 26
    /// for `.a` to `.z`.
    pub missing: [T; 27],
}

impl<'a, T: Element> Numbers<'a, T> {
    /// Values only, with `null` written for every missing value.
    pub fn new(values: &'a mut [T], null: T) -> Self {
        Numbers {
            values,
            codes: None,
            missing: [null; 27],
        }
    }

    /// Also write each row's missing code into `codes`.
    pub fn with_codes(mut self, codes: &'a mut [u8]) -> Self {
        self.codes = Some(codes);
        self
    }

    /// Write `value(code)` for the missing code `code` (1 for `.`, 2 to 27
    /// for `.a` to `.z`). R keeps `.a` to `.z` as tagged NaNs:
    /// `with_missing(|c| if c == 1 { NA } else { tagged_nan(c) })`.
    pub fn with_missing(mut self, value: impl Fn(u8) -> T) -> Self {
        for (k, m) in self.missing.iter_mut().enumerate() {
            *m = value(k as u8 + missing::SYSTEM);
        }
        self
    }
}

/// Where one selected column goes.
pub enum Output<'a> {
    Int8(Numbers<'a, i8>),
    Int16(Numbers<'a, i16>),
    Int32(Numbers<'a, i32>),
    Int64(Numbers<'a, i64>),
    UInt8(Numbers<'a, u8>),
    Float32(Numbers<'a, f32>),
    Float64(Numbers<'a, f64>),
    /// A categorical column (one with levels in the profile) as level
    /// codes: `base` for the first level, `null` for a missing value. R's
    /// factors use base 1 and `NA_integer_`.
    Levels {
        codes: &'a mut [i32],
        base: i32,
        null: i32,
    },
    /// Text or bytes, handed to the read's text callback one column chunk
    /// at a time.
    Text,
}

/// What a read did besides filling the outputs.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct ReadReport {
    /// Rows read.
    pub rows: u64,
    /// Per selected column, whether any `.a` to `.z` was read.
    pub letters: Vec<bool>,
}

/// A row group: its rows and size.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RowGroupInfo {
    pub first_row: u64,
    pub rows: u64,
    pub compressed_bytes: u64,
    pub uncompressed_bytes: u64,
}

/// An open Parquet file. Opening reads only the footer.
pub struct Reader<S: Source> {
    source: S,
    meta: FileMetaData,
    columns: Vec<ColumnInfo>,
    profile: Option<Profile>,
    warnings: Vec<String>,
    first_rows: Vec<u64>,
    rows: u64,
    /// Offset indexes read so far, by row group and leaf.
    offset_indexes: HashMap<(usize, usize), Option<OffsetIndex>>,
    options: ReadOptions,
}

const MAGIC: &[u8; 4] = b"PAR1";

impl<S: Source> Reader<S> {
    /// Open a file: check its magic numbers and read its footer, schema
    /// and profile. Damage in the profile is a warning
    /// ([`Reader::warnings`]), never an error.
    pub fn open(mut source: S, options: ReadOptions) -> Result<Self> {
        let len = source.len();
        if len < 12 {
            return Err(Error::new(
                "not a Parquet file: it is shorter than 12 bytes",
            ));
        }
        let mut tail = [0u8; 8];
        source.read_at(len - 8, &mut tail)?;
        if &tail[4..] == b"PARE" {
            return Err(Error::new(
                "the file is an encrypted Parquet file, which is not supported",
            ));
        }
        let mut head = [0u8; 4];
        source.read_at(0, &mut head)?;
        if &tail[4..] != MAGIC || &head != MAGIC {
            return Err(Error::new(
                "not a Parquet file: it does not start and end with PAR1",
            ));
        }
        let footer_len = u64::from(u32::from_le_bytes(tail[..4].try_into().expect("4 bytes")));
        if footer_len > len - 12 {
            return Err(Error::at(
                len - 8,
                format!("the footer's length, {footer_len} bytes, is more than the file holds"),
            ));
        }
        let footer_at = len - 8 - footer_len;
        let mut footer = Vec::new();
        if footer.try_reserve_exact(footer_len as usize).is_err() {
            return Err(Error::new(format!(
                "a footer of {footer_len} bytes does not fit in memory here"
            ))
            .of(ErrorKind::TooLarge));
        }
        footer.resize(footer_len as usize, 0);
        source.read_at(footer_at, &mut footer)?;
        let meta = FileMetaData::parse(&footer, footer_at)?;
        drop(footer);
        if meta.encrypted {
            return Err(Error::new(
                "the file has encrypted columns, which are not supported",
            ));
        }
        let mut columns = schema::columns(&meta)?;
        let mut first_rows = Vec::with_capacity(meta.row_groups.len());
        let mut rows = 0u64;
        for (k, g) in meta.row_groups.iter().enumerate() {
            let n = u64::try_from(g.num_rows).map_err(|_| {
                Error::new(format!("row group {} has a negative number of rows", k + 1))
            })?;
            first_rows.push(rows);
            rows = rows
                .checked_add(n)
                .ok_or_else(|| Error::new("the row groups hold too many rows"))?;
        }
        let mut warnings = Vec::new();
        let mut profile = match meta
            .key_value
            .iter()
            .find(|kv| kv.key == profile::KEY)
            .and_then(|kv| kv.value.as_ref())
        {
            Some(text) => {
                let (p, w) = Profile::parse(text);
                warnings.extend(w);
                p
            }
            None => None,
        };
        if let Some(p) = &mut profile {
            check_widened(&mut columns, p, &mut warnings);
            for c in &p.columns {
                if c.categorical.is_some() {
                    if let Some(col) = columns.iter().find(|x| x.name == c.name) {
                        if col.kind != ColumnType::Text {
                            warnings.push(format!("the dta profile gives levels for column \"{}\", which is not text; they are ignored", c.name));
                        }
                    }
                }
            }
        }
        Ok(Reader {
            source,
            meta,
            columns,
            profile,
            warnings,
            first_rows,
            rows,
            offset_indexes: HashMap::new(),
            options,
        })
    }

    /// The file's footer as it is.
    pub fn metadata(&self) -> &FileMetaData {
        &self.meta
    }

    /// The file's top-level columns, in order, including nested ones (see
    /// [`ColumnInfo::role`]).
    pub fn columns(&self) -> &[ColumnInfo] {
        &self.columns
    }

    /// The index of the column called `name`.
    pub fn column_index(&self, name: &str) -> Option<usize> {
        self.columns.iter().position(|c| c.name == name)
    }

    /// The columns a read returns by default: the data columns. With
    /// nested columns in the file, this is an error naming them unless the
    /// options say to skip them.
    pub fn data_columns(&self) -> Result<Vec<usize>> {
        let nested: Vec<&str> = self
            .columns
            .iter()
            .filter(|c| c.role == Role::Nested)
            .map(|c| c.name.as_str())
            .collect();
        if !nested.is_empty() && self.options.nested == Nested::Error {
            return Err(Error::invalid(format!(
                "the file has nested columns, which are not read: {}; select the columns wanted, or skip nested columns",
                quoted(&nested)
            )));
        }
        Ok((0..self.columns.len())
            .filter(|&k| self.columns[k].role == Role::Data)
            .collect())
    }

    /// Rows in the file.
    pub fn rows(&self) -> u64 {
        self.rows
    }

    /// The row groups, in order.
    pub fn row_groups(&self) -> Vec<RowGroupInfo> {
        self.meta
            .row_groups
            .iter()
            .zip(&self.first_rows)
            .map(|(g, &first_row)| {
                let (mut compressed, mut uncompressed) = (0u64, 0u64);
                for c in g.columns.iter().filter_map(|c| c.meta.as_ref()) {
                    compressed = compressed.saturating_add(c.total_compressed_size.max(0) as u64);
                    uncompressed =
                        uncompressed.saturating_add(c.total_uncompressed_size.max(0) as u64);
                }
                RowGroupInfo {
                    first_row,
                    rows: g.num_rows.max(0) as u64,
                    compressed_bytes: compressed,
                    uncompressed_bytes: uncompressed,
                }
            })
            .collect()
    }

    /// The codecs the file's column chunks use, each once.
    pub fn codecs(&self) -> Vec<Codec> {
        let mut out = Vec::new();
        for c in self
            .meta
            .row_groups
            .iter()
            .flat_map(|g| &g.columns)
            .filter_map(|c| c.meta.as_ref())
        {
            if !out.contains(&c.codec) {
                out.push(c.codec);
            }
        }
        out
    }

    /// The writer the file names.
    pub fn created_by(&self) -> Option<&str> {
        self.meta.created_by.as_deref()
    }

    /// The value of a key-value metadata entry.
    pub fn key_value(&self, key: &str) -> Option<&[u8]> {
        self.meta
            .key_value
            .iter()
            .find(|kv| kv.key == key)
            .and_then(|kv| kv.value.as_deref())
    }

    /// The dta profile, if the file has a usable one.
    pub fn profile(&self) -> Option<&Profile> {
        self.profile.as_ref()
    }

    /// Warnings from opening the file, about its profile.
    pub fn warnings(&self) -> &[String] {
        &self.warnings
    }

    /// The rows a read of `n` rows from row `skip` gets.
    pub fn window(&self, skip: u64, n: u64) -> Range<u64> {
        let start = skip.min(self.rows);
        start..start + n.min(self.rows - start)
    }

    /// The byte ranges of the file a read of `columns` over rows `skip`
    /// to `skip + n` needs: whole column chunks, or with an offset index
    /// the dictionary page and the pages that hold the rows. Reads the
    /// offset indexes it needs. Ranges are sorted and merged.
    pub fn plan(&mut self, columns: &[usize], skip: u64, n: u64) -> Result<Vec<Range<u64>>> {
        let window = self.window(skip, n);
        let leaves = self.leaves(columns)?;
        let mut out = Vec::new();
        let groups = self.groups(&window);
        for (g, local) in &groups {
            for &leaf in &leaves {
                self.load_offset_index(*g, leaf, local)?;
            }
        }
        let ctx = Ctx {
            reader_columns: &self.columns,
            meta: &self.meta,
            first_rows: &self.first_rows,
            offset_indexes: &self.offset_indexes,
            file_len: self.source.len(),
        };
        for (g, local) in &groups {
            for &leaf in &leaves {
                let column = self
                    .columns
                    .iter()
                    .find(|c| c.leaf == leaf && c.role != Role::Nested)
                    .expect("a flat column");
                let chunk = ctx.chunk(*g, column, local.clone())?;
                out.extend(decode::planned(&chunk).map_err(|e| chunk.error(None, e))?);
            }
        }
        out.sort_by_key(|r| r.start);
        let mut merged: Vec<Range<u64>> = Vec::with_capacity(out.len());
        for r in out {
            match merged.last_mut() {
                Some(last) if r.start <= last.end => last.end = last.end.max(r.end),
                _ => merged.push(r),
            }
        }
        Ok(merged)
    }

    /// Read rows `skip` to `skip + n` (clipped to the file) of `columns`
    /// (indices into [`Reader::columns`]) into `outputs`, one per column.
    /// Each output's slices must be as long as the rows read
    /// ([`Reader::window`]). Text columns are handed to `text(k, chunk)`,
    /// `k` being the column's position in `columns`, one column chunk at a
    /// time, in row order for each column.
    ///
    /// In a DOUBLE column, a value whose bits are exactly a tagged NaN
    /// ([`crate::tagged_nan`]) reads as that `.a` to `.z`; every other NaN
    /// is a NaN value.
    pub fn read(
        &mut self,
        columns: &[usize],
        skip: u64,
        n: u64,
        outputs: &mut [Output<'_>],
        mut text: impl FnMut(usize, &TextChunk) -> Result<()>,
    ) -> Result<ReadReport> {
        let window = self.window(skip, n);
        // More rows than this machine can index (a 32-bit one) cannot have
        // outputs.
        let rows = usize::try_from(window.end - window.start).map_err(|_| {
            Error::invalid(format!(
                "{} rows are more than this machine can read at once",
                window.end - window.start
            ))
            .of(ErrorKind::TooLarge)
        })?;
        if outputs.len() != columns.len() {
            return Err(Error::invalid(format!(
                "{} columns were selected but {} outputs given",
                columns.len(),
                outputs.len()
            )));
        }
        for (&c, out) in columns.iter().zip(outputs.iter()) {
            self.check_output(c, out, rows)?;
        }
        let groups = self.groups(&window);
        // Offset indexes, for row groups read in part.
        for (g, local) in &groups {
            for &c in columns {
                let leaf = self.columns[c].leaf;
                self.load_offset_index(*g, leaf, local)?;
            }
        }
        let levels: Vec<Option<HashMap<&[u8], i32>>> = columns
            .iter()
            .zip(outputs.iter())
            .map(|(&c, out)| match out {
                Output::Levels { base, .. } => {
                    levels_in(&self.profile, &self.columns[c].name).map(|levels| {
                        levels
                            .iter()
                            .enumerate()
                            .map(|(i, l)| (l.as_bytes(), i as i32 + base))
                            .collect()
                    })
                }
                _ => None,
            })
            .collect();
        let sizes: Vec<usize> = groups
            .iter()
            .map(|(_, r)| (r.end - r.start) as usize)
            .collect();
        // Split each output into one destination per row group.
        let mut per_column: Vec<std::vec::IntoIter<Dest<'_>>> = Vec::with_capacity(columns.len());
        for (out, lv) in outputs.iter_mut().zip(&levels) {
            per_column.push(split(out, lv.as_ref(), &sizes).into_iter());
        }
        let mut tasks = Vec::with_capacity(groups.len() * columns.len());
        let mut at = 0u64;
        for (g, local) in &groups {
            for (k, dests) in per_column.iter_mut().enumerate() {
                let dest = dests.next().expect("one per row group");
                tasks.push(Task {
                    group: *g,
                    k,
                    column: columns[k],
                    window: local.clone(),
                    first: at,
                    dest,
                });
            }
            at += local.end - local.start;
        }
        drop(per_column);
        let ctx = Ctx {
            reader_columns: &self.columns,
            meta: &self.meta,
            first_rows: &self.first_rows,
            offset_indexes: &self.offset_indexes,
            file_len: self.source.len(),
        };
        let bytes = tasks
            .iter()
            .fold(0u64, |sum, t| sum.saturating_add(ctx.uncompressed(t)));
        let threads = dta::threads::resolve(self.options.threads);
        let parallel = threads > 1 && tasks.len() > 1 && bytes >= self.options.parallel_bytes;
        let mut letters = vec![false; columns.len()];
        let mut deliver = |k: usize, done: Done| -> Result<()> {
            letters[k] |= done.letters;
            match done.text {
                Some(chunk) => text(k, &chunk),
                None => Ok(()),
            }
        };
        let shared = if parallel { self.source.shared() } else { None };
        match shared {
            Some(shared) => {
                run_parallel(tasks, &ctx, threads, shared, columns.len(), &mut deliver)?
            }
            None => {
                let source = &mut self.source;
                let mut read = |offset: u64, buf: &mut [u8]| source.read_at(offset, buf);
                let mut scratch = Scratch::default();
                for task in tasks {
                    let k = task.k;
                    let done = run(&ctx, task, &mut read, &mut scratch)?;
                    deliver(k, done)?;
                }
            }
        }
        drop(levels);
        Ok(ReadReport {
            rows: rows as u64,
            letters,
        })
    }

    fn check_output(&self, c: usize, out: &Output, rows: usize) -> Result<()> {
        let col = self.columns.get(c).ok_or_else(|| {
            Error::invalid(format!("there is no column {}", c + 1)).of(ErrorKind::OutOfRange)
        })?;
        if let ColumnType::Unsupported(why) = &col.kind {
            return Err(Error::invalid(format!("column \"{}\" is {why}", col.name)));
        }
        // A DOUBLE column written wider reads into what it was.
        let kind = col
            .storage
            .map_or_else(|| col.kind.clone(), |s| s.column_type());
        let ok = match out {
            Output::Int8(n) => accepts(n, &kind, rows),
            Output::Int16(n) => accepts(n, &kind, rows),
            Output::Int32(n) => accepts(n, &kind, rows),
            Output::Int64(n) => accepts(n, &kind, rows),
            Output::UInt8(n) => accepts(n, &kind, rows),
            Output::Float32(n) => accepts(n, &kind, rows),
            Output::Float64(n) => accepts(n, &kind, rows),
            Output::Levels { codes, .. } => {
                if levels_in(&self.profile, &col.name).is_none() || col.kind != ColumnType::Text {
                    return Err(Error::invalid(format!(
                        "column \"{}\" has no levels in the dta profile",
                        col.name
                    )));
                }
                Ok(codes.len() == rows)
            }
            Output::Text => Ok(matches!(col.kind, ColumnType::Text | ColumnType::Binary)),
        };
        match ok {
            Ok(true) => Ok(()),
            Ok(false) => Err(Error::invalid(format!(
                "the output for column \"{}\" does not hold {rows} rows",
                col.name
            ))),
            Err(target) => Err(Error::invalid(format!(
                "column \"{}\" ({:?}) cannot be read as {target}",
                col.name, col.kind
            ))),
        }
    }

    /// The leaves of `columns`.
    fn leaves(&self, columns: &[usize]) -> Result<Vec<usize>> {
        let mut out = Vec::new();
        for &c in columns {
            let col = self.columns.get(c).ok_or_else(|| {
                Error::invalid(format!("there is no column {}", c + 1)).of(ErrorKind::OutOfRange)
            })?;
            if col.role == Role::Nested {
                return Err(Error::invalid(format!(
                    "column \"{}\" is nested (a list, map or group), which is not read",
                    col.name
                )));
            }
            out.push(col.leaf);
        }
        Ok(out)
    }

    /// The row groups that hold `window`, each with the rows wanted from
    /// it, counted from its first row.
    fn groups(&self, window: &Range<u64>) -> Vec<(usize, Range<u64>)> {
        let mut out = Vec::new();
        for (g, (&first, group)) in self
            .first_rows
            .iter()
            .zip(&self.meta.row_groups)
            .enumerate()
        {
            let end = first + group.num_rows.max(0) as u64;
            if end <= window.start || first >= window.end || end == first {
                continue;
            }
            out.push((
                g,
                window.start.max(first) - first..window.end.min(end) - first,
            ));
        }
        out
    }

    /// Read the offset index of a chunk read in part, once.
    fn load_offset_index(&mut self, g: usize, leaf: usize, local: &Range<u64>) -> Result<()> {
        let group = &self.meta.row_groups[g];
        let whole = local.start == 0 && local.end >= group.num_rows.max(0) as u64;
        if whole || self.offset_indexes.contains_key(&(g, leaf)) {
            return Ok(());
        }
        let index = match group.columns[leaf].offset_index {
            Some((offset, len))
                if offset >= 0
                    && len > 0
                    && (offset as u64)
                        .checked_add(len as u64)
                        .is_some_and(|e| e <= self.source.len()) =>
            {
                let mut buf = vec![0u8; len as usize];
                self.source.read_at(offset as u64, &mut buf)?;
                // A damaged index is not used: the reader walks the page
                // headers instead.
                OffsetIndex::parse(&buf, offset as u64).ok()
            }
            _ => None,
        };
        self.offset_indexes.insert((g, leaf), index);
        Ok(())
    }
}

/// The levels the profile gives column `name`.
fn levels_in<'p>(profile: &'p Option<Profile>, name: &str) -> Option<&'p [String]> {
    profile
        .as_ref()?
        .column(name)?
        .categorical
        .as_ref()
        .map(|cat| cat.levels.as_slice())
}

fn quoted(names: &[&str]) -> String {
    names
        .iter()
        .map(|n| format!("\"{n}\""))
        .collect::<Vec<_>>()
        .join(", ")
}

fn accepts<T: Element>(
    n: &Numbers<T>,
    kind: &ColumnType,
    rows: usize,
) -> std::result::Result<bool, &'static str> {
    if !T::accepts(kind) {
        return Err(T::NAME);
    }
    Ok(n.values.len() == rows && n.codes.as_ref().is_none_or(|c| c.len() == rows))
}

/// Keep each `storage` and `logical` the profile gives a DOUBLE column;
/// drop, with a warning, one given any other column.
fn check_widened(columns: &mut [ColumnInfo], p: &mut Profile, warnings: &mut Vec<String>) {
    for entry in &mut p.columns {
        if entry.storage.is_none() && entry.logical.is_none() {
            continue;
        }
        let Some(col) = columns
            .iter_mut()
            .find(|c| c.name == entry.name && c.role == Role::Data)
        else {
            continue;
        };
        if col.kind == ColumnType::Double {
            col.storage = entry.storage;
            col.profile_logical = entry.logical;
            continue;
        }
        if entry.storage.take().is_some() {
            warnings.push(format!(
                "dropped \"columns.{}.storage\" from the dta profile: it gives a storage type to a column that is not DOUBLE",
                entry.name
            ));
        }
        if entry.logical.take().is_some() {
            warnings.push(format!(
                "dropped \"columns.{}.logical\" from the dta profile: it gives a date or timestamp type to a column that is not DOUBLE",
                entry.name
            ));
        }
    }
}

/// One output's part for one row group.
enum Dest<'a> {
    I8(NumberOut<'a, i8>),
    I16(NumberOut<'a, i16>),
    I32(NumberOut<'a, i32>),
    I64(NumberOut<'a, i64>),
    U8(NumberOut<'a, u8>),
    F32(NumberOut<'a, f32>),
    F64(NumberOut<'a, f64>),
    Levels {
        codes: &'a mut [i32],
        null: i32,
        levels: &'a HashMap<&'a [u8], i32>,
    },
    Text,
}

/// Cut `s` into pieces of `sizes`.
fn cut<'s, T>(mut s: &'s mut [T], sizes: &[usize]) -> Vec<&'s mut [T]> {
    let mut out = Vec::with_capacity(sizes.len());
    for &n in sizes {
        let (a, b) = std::mem::take(&mut s).split_at_mut(n);
        out.push(a);
        s = b;
    }
    out
}

fn split_numbers<'a, T: Copy>(n: &'a mut Numbers<'_, T>, sizes: &[usize]) -> Vec<NumberOut<'a, T>> {
    let Numbers {
        values,
        codes,
        missing,
    } = n;
    let values = cut(values, sizes);
    let codes: Vec<Option<&mut [u8]>> = match codes {
        Some(c) => cut(c, sizes).into_iter().map(Some).collect(),
        None => sizes.iter().map(|_| None).collect(),
    };
    let missing = &*missing;
    values
        .into_iter()
        .zip(codes)
        .map(|(values, codes)| NumberOut {
            values,
            codes,
            missing,
            file_row: 0,
        })
        .collect()
}

fn split<'a>(
    out: &'a mut Output<'_>,
    levels: Option<&'a HashMap<&'a [u8], i32>>,
    sizes: &[usize],
) -> Vec<Dest<'a>> {
    match out {
        Output::Int8(n) => split_numbers(n, sizes).into_iter().map(Dest::I8).collect(),
        Output::Int16(n) => split_numbers(n, sizes).into_iter().map(Dest::I16).collect(),
        Output::Int32(n) => split_numbers(n, sizes).into_iter().map(Dest::I32).collect(),
        Output::Int64(n) => split_numbers(n, sizes).into_iter().map(Dest::I64).collect(),
        Output::UInt8(n) => split_numbers(n, sizes).into_iter().map(Dest::U8).collect(),
        Output::Float32(n) => split_numbers(n, sizes).into_iter().map(Dest::F32).collect(),
        Output::Float64(n) => split_numbers(n, sizes).into_iter().map(Dest::F64).collect(),
        Output::Levels { codes, null, .. } => {
            let levels = levels.expect("checked before the read");
            let null = *null;
            cut(codes, sizes)
                .into_iter()
                .map(|codes| Dest::Levels {
                    codes,
                    null,
                    levels,
                })
                .collect()
        }
        Output::Text => sizes.iter().map(|_| Dest::Text).collect(),
    }
}

/// One column chunk to decode, and where it goes.
struct Task<'a> {
    group: usize,
    /// Position in the read's selection.
    k: usize,
    /// Index into the reader's columns.
    column: usize,
    window: Range<u64>,
    /// The row of the read where `window.start` lands.
    first: u64,
    dest: Dest<'a>,
}

/// What a task gives back to the calling thread.
struct Done {
    text: Option<TextChunk>,
    /// Whether any `.a` to `.z` was read.
    letters: bool,
}

/// What every task reads.
struct Ctx<'r> {
    reader_columns: &'r [ColumnInfo],
    meta: &'r FileMetaData,
    first_rows: &'r [u64],
    offset_indexes: &'r HashMap<(usize, usize), Option<OffsetIndex>>,
    file_len: u64,
}

impl Ctx<'_> {
    fn chunk<'c>(
        &'c self,
        g: usize,
        column: &'c ColumnInfo,
        window: Range<u64>,
    ) -> Result<Chunk<'c>> {
        let group = &self.meta.row_groups[g];
        let cc = &group.columns[column.leaf];
        let name = &column.name;
        if cc.encrypted {
            return Err(Error::new(format!(
                "column \"{name}\" is encrypted, which is not supported"
            )));
        }
        if cc.file_path.is_some() {
            return Err(Error::new(format!(
                "column \"{name}\" is stored in another file, which is not supported"
            )));
        }
        let meta = cc.meta.as_ref().ok_or_else(|| {
            Error::new(format!(
                "column \"{name}\", row group {}: the chunk has no metadata",
                g + 1
            ))
        })?;
        if Some(meta.physical) != column.physical {
            return Err(Error::new(format!(
                "column \"{name}\", row group {}: the chunk's type differs from the schema's",
                g + 1
            )));
        }
        Ok(Chunk {
            column,
            meta,
            group: g,
            group_rows: group.num_rows.max(0) as u64,
            window,
            file_row: self.first_rows[g],
            file_len: self.file_len,
            offset_index: self
                .offset_indexes
                .get(&(g, column.leaf))
                .and_then(Option::as_ref),
        })
    }

    /// Roughly the uncompressed bytes a task decodes, to decide whether a
    /// read is large enough for threads.
    fn uncompressed(&self, t: &Task) -> u64 {
        let g = &self.meta.row_groups[t.group];
        let col = &self.reader_columns[t.column];
        let size = g.columns[col.leaf]
            .meta
            .as_ref()
            .map_or(0, |m| m.total_uncompressed_size.max(0) as u64);
        let rows = g.num_rows.max(1) as u128;
        (u128::from(size) * u128::from(t.window.end - t.window.start) / rows)
            .try_into()
            .unwrap_or(u64::MAX)
    }
}

/// Decode one task's chunk into its destination.
fn run(ctx: &Ctx, task: Task, read: &mut decode::ReadAt, scratch: &mut Scratch) -> Result<Done> {
    let column = &ctx.reader_columns[task.column];
    let chunk = ctx.chunk(task.group, column, task.window.clone())?;
    let rows = (task.window.end - task.window.start) as usize;
    let file_row = chunk.file_row + task.window.start;
    let mut done = Done {
        text: None,
        letters: false,
    };
    macro_rules! numbers {
        ($out:expr) => {{
            let mut out = $out;
            out.file_row = file_row;
            done.letters = decode_numbers(&chunk, &mut out, read, scratch)?;
        }};
    }
    match task.dest {
        Dest::I8(out) => numbers!(out),
        Dest::I16(out) => numbers!(out),
        Dest::I32(out) => numbers!(out),
        Dest::I64(out) => numbers!(out),
        Dest::U8(out) => numbers!(out),
        Dest::F32(out) => numbers!(out),
        Dest::F64(out) => numbers!(out),
        Dest::Levels {
            codes,
            null,
            levels,
        } => {
            let mut t = Texts::new(task.first, rows, true);
            decode::decode(&chunk, read, scratch, &mut t)?;
            let tc = &t.chunk;
            // Map each distinct value to its level once.
            let n_values = tc.ends.len();
            let mut map = Vec::with_capacity(n_values);
            for i in 0..n_values {
                let v = tc.value(i);
                map.push(levels.get(v).copied());
            }
            for (r, code) in codes.iter_mut().enumerate() {
                let value = match &tc.codes {
                    Some(c) if c[r] == TextChunk::NULL => None,
                    Some(c) => Some(c[r] as usize),
                    None if tc.missing[r] != 0 => None,
                    None => Some(r),
                };
                *code = match value {
                    None => null,
                    Some(i) => map[i].ok_or_else(|| {
                        Error::new(format!(
                            "column \"{}\": the value \"{}\" in row {} is not one of the levels in the dta profile",
                            column.name,
                            String::from_utf8_lossy(tc.value(i)),
                            file_row + r as u64 + 1
                        ))
                    })?,
                };
            }
        }
        Dest::Text => {
            let mut t = Texts::new(task.first, rows, column.kind == ColumnType::Text);
            decode::decode(&chunk, read, scratch, &mut t)?;
            done.text = Some(t.chunk);
        }
    }
    Ok(done)
}

/// Decode a numeric chunk; returns whether it held any `.a` to `.z`.
fn decode_numbers<T: Element>(
    chunk: &Chunk,
    out: &mut NumberOut<T>,
    read: &mut decode::ReadAt,
    scratch: &mut Scratch,
) -> Result<bool> {
    fn reborrow<'s, T>(out: &'s mut NumberOut<'_, T>) -> NumberOut<'s, T> {
        NumberOut {
            values: &mut *out.values,
            codes: out.codes.as_deref_mut(),
            missing: out.missing,
            file_row: out.file_row,
        }
    }
    fn numbers<P: Physical, T: Element>(
        chunk: &Chunk,
        out: &mut NumberOut<T>,
        read: &mut decode::ReadAt,
        scratch: &mut Scratch,
    ) -> Result<bool> {
        let mut n = NumberConsumer::<P, T> {
            out: reborrow(out),
            dictionary: Vec::new(),
            letters: false,
        };
        decode::decode(chunk, read, scratch, &mut n)?;
        Ok(n.letters)
    }
    let named = |e: Error| match e.kind {
        ErrorKind::Invalid => {
            Error::invalid(format!("column \"{}\": {}", chunk.column.name, e.message))
        }
        _ => e,
    };
    match chunk.column.physical {
        Some(PhysicalType::Int32) => numbers::<i32, T>(chunk, out, read, scratch),
        Some(PhysicalType::Int64) => numbers::<i64, T>(chunk, out, read, scratch),
        Some(PhysicalType::Float) => numbers::<f32, T>(chunk, out, read, scratch),
        Some(PhysicalType::Double) => numbers::<f64, T>(chunk, out, read, scratch),
        Some(PhysicalType::Boolean) => {
            decode::decode(chunk, read, scratch, &mut Booleans { out: reborrow(out) })
                .map(|()| false)
        }
        _ => Err(Error::invalid(format!(
            "column \"{}\" is not numeric",
            chunk.column.name
        ))),
    }
    .map_err(named)
}

// ---- threads ----

struct State {
    done: Vec<Option<Result<Done>>>,
    delivered: usize,
    stop: bool,
}

fn lock(m: &Mutex<State>) -> MutexGuard<'_, State> {
    m.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Sets the stop flag and wakes everyone when the calling thread leaves,
/// by any path, so no worker waits forever.
struct StopOnDrop<'s>(&'s Mutex<State>, &'s Condvar);

impl Drop for StopOnDrop<'_> {
    fn drop(&mut self) {
        lock(self.0).stop = true;
        self.1.notify_all();
    }
}

/// Decode `tasks` on worker threads; the calling thread takes their
/// results in order and passes them to `deliver`. At most `window` tasks
/// past the last delivered one are decoded ahead, which bounds the text
/// held in memory to about two row groups'.
fn run_parallel(
    tasks: Vec<Task<'_>>,
    ctx: &Ctx,
    threads: usize,
    shared: &dyn SharedSource,
    columns: usize,
    deliver: &mut dyn FnMut(usize, Done) -> Result<()>,
) -> Result<()> {
    let n = tasks.len();
    let ks: Vec<usize> = tasks.iter().map(|t| t.k).collect();
    let window = (2 * columns).max(2 * threads);
    let slots: Vec<Mutex<Option<Task>>> = tasks.into_iter().map(|t| Mutex::new(Some(t))).collect();
    let state = Mutex::new(State {
        done: (0..n).map(|_| None).collect(),
        delivered: 0,
        stop: false,
    });
    let cv = Condvar::new();
    let next = AtomicUsize::new(0);
    let take = |i: usize| {
        slots[i]
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .take()
    };
    std::thread::scope(|s| {
        let worker = || {
            let mut scratch = Scratch::default();
            let mut read = |offset: u64, buf: &mut [u8]| shared.read_at_shared(offset, buf);
            loop {
                let i = next.fetch_add(1, Ordering::Relaxed);
                if i >= n {
                    break;
                }
                {
                    let mut st = lock(&state);
                    while !st.stop && i >= st.delivered + window {
                        st = cv.wait(st).unwrap_or_else(PoisonError::into_inner);
                    }
                    if st.stop {
                        break;
                    }
                }
                let Some(task) = take(i) else { continue };
                let result =
                    catch_unwind(AssertUnwindSafe(|| run(ctx, task, &mut read, &mut scratch)))
                        .unwrap_or_else(|p| {
                            Err(
                                Error::new(format!("a read thread panicked: {}", panic_text(&*p)))
                                    .of(ErrorKind::Internal),
                            )
                        });
                lock(&state).done[i] = Some(result);
                cv.notify_all();
            }
        };
        let mut started = 0;
        for _ in 0..threads {
            if std::thread::Builder::new().spawn_scoped(s, worker).is_ok() {
                started += 1;
            }
        }
        let _stop = StopOnDrop(&state, &cv);
        if started == 0 {
            // No thread could start: decode here, in order.
            let mut scratch = Scratch::default();
            let mut read = |offset: u64, buf: &mut [u8]| shared.read_at_shared(offset, buf);
            for (i, k) in ks.iter().enumerate() {
                let task = take(i).expect("not taken");
                deliver(*k, run(ctx, task, &mut read, &mut scratch)?)?;
            }
            return Ok(());
        }
        for (i, k) in ks.iter().enumerate() {
            let result = {
                let mut st = lock(&state);
                loop {
                    if let Some(r) = st.done[i].take() {
                        break r;
                    }
                    st = cv.wait(st).unwrap_or_else(PoisonError::into_inner);
                }
            };
            deliver(*k, result?)?;
            lock(&state).delivered = i + 1;
            cv.notify_all();
        }
        Ok(())
    })
}

fn panic_text(payload: &(dyn std::any::Any + Send)) -> String {
    payload
        .downcast_ref::<&str>()
        .map(|s| s.to_string())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "unknown panic".into())
}
