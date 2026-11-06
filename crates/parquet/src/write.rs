//! Writing a table as Parquet with a dta profile (plan 0018, "What we
//! write").
//!
//! Row groups are written in order; their column chunks are encoded on
//! worker threads, the next row group's while this one's go out, and
//! only a bounded number of bytes of encoded chunks wait for the output. Values come from the caller a block of
//! rows at a time, so nothing holds a second copy of the table.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};
use std::io::Write;
use std::ops::Range;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Condvar, Mutex, PoisonError};

use crate::arrow::{self, ArrowType};
use crate::codec::{Codecs, Compression};
use crate::format::{
    converted, Codec, ColumnChunk, ColumnMetaData, ColumnOrder, DataPageHeader,
    DictionaryPageHeader, Encoding, FileMetaData, KeyValue, LogicalType, OffsetIndex, PageHeader,
    PageLocation, PageType, PhysicalType, Repetition, RowGroup, SchemaElement, Statistics,
    TimeUnit,
};
use crate::profile::{self, Categorical, ColumnProfile, Logical, Profile, Storage};
use crate::rle;
use crate::tagged::tagged_nan;
use dta::{missing, Error, ErrorKind, Result};

/// A numbers dictionary is given up once this many values of its first
/// page are at least 90% different values.
const DISTINCT_SAMPLE: usize = 32_768;

/// The most rows a fill is asked for at once.
pub const BLOCK: usize = 1024;

/// Fills a block of rows: called with the block's first row and buffers
/// of the block's length, it writes each row's value and missing code
/// (0 for a value, 1 for a null, 2 to 27 for `.a` to `.z`). `.a` to `.z`
/// may be given only for `Int8`, `Int16`, `Int32`, `Float`, `Double`,
/// `Date` and `Timestamp` columns, unless [`WriteOptions::missing_letters`]
/// is off.
pub type Fill<'a, T> = dyn Fn(usize, &mut [T], &mut [u8]) + Sync + 'a;

/// Gives a row's bytes, or `None` for a null.
pub type GetBytes<'a> = dyn Fn(usize) -> Option<&'a [u8]> + Sync + 'a;

/// Fills a block of level codes: from 0 for the first level, negative for
/// a null.
pub type FillCodes<'a> = dyn Fn(usize, &mut [i32]) + Sync + 'a;

/// A column's values and the type to write them as (plan 0018, "Column
/// types we write"). Every column is written OPTIONAL.
pub enum Values<'a> {
    /// INT32 annotated INT(8): every value must fit in 8 bits.
    Int8(Box<Fill<'a, i32>>),
    /// INT32 annotated INT(16).
    Int16(Box<Fill<'a, i32>>),
    Int32(Box<Fill<'a, i32>>),
    Int64(Box<Fill<'a, i64>>),
    /// INT32 annotated INT(8, false): every value must fit in 8 bits.
    UInt8(Box<Fill<'a, u32>>),
    /// INT32 annotated INT(16, false).
    UInt16(Box<Fill<'a, u32>>),
    /// INT32 annotated INT(32, false), its statistics ordered unsigned.
    UInt32(Box<Fill<'a, u32>>),
    /// INT64 annotated INT(64, false).
    UInt64(Box<Fill<'a, u64>>),
    Float(Box<Fill<'a, f32>>),
    /// DOUBLE. A `logical` given for the column in [`Table::profile`]
    /// is kept: days or seconds since 1970 that DATE or TIMESTAMP cannot
    /// hold exactly.
    Double(Box<Fill<'a, f64>>),
    /// Values 0 and 1.
    Bool(Box<Fill<'a, u8>>),
    /// Days since 1970-01-01.
    Date(Box<Fill<'a, i32>>),
    /// Units since 1970-01-01 00:00. `utc`: the values are instants
    /// (adjusted to UTC); `zone` is the time zone to show them in, kept in
    /// the profile and `ARROW:schema`. An instant without a zone is
    /// recorded as having none.
    Timestamp {
        unit: TimeUnit,
        utc: bool,
        zone: Option<String>,
        fill: Box<Fill<'a, i64>>,
    },
    /// Nanoseconds since midnight: INT64 annotated TIME(NANOS), not
    /// adjusted to UTC (a time of day, as polars' `Time`).
    Time(Box<Fill<'a, i64>>),
    /// UTF-8 text, checked.
    Text(Box<GetBytes<'a>>),
    /// Bytes.
    Binary(Box<GetBytes<'a>>),
    /// Codes into `levels`, written dictionary-encoded with every level in
    /// order in every row group.
    Categorical {
        levels: Vec<String>,
        ordered: bool,
        codes: Box<FillCodes<'a>>,
    },
}

impl<'a> Values<'a> {
    /// Build a fill from a function giving each row's value, or `None`
    /// for a null.
    pub fn by_row<T: Default + Copy>(
        get: impl Fn(usize) -> Option<T> + Sync + 'a,
    ) -> Box<Fill<'a, T>> {
        Box::new(move |first, values: &mut [T], codes: &mut [u8]| {
            for (i, (v, c)) in values.iter_mut().zip(codes.iter_mut()).enumerate() {
                match get(first + i) {
                    Some(x) => {
                        *v = x;
                        *c = 0;
                    }
                    None => {
                        *v = T::default();
                        *c = missing::SYSTEM;
                    }
                }
            }
        })
    }

    /// Bytes per value of the plain encoding, for sizing row groups; text
    /// adds its length.
    fn width(&self) -> usize {
        match self {
            Values::Int8(_)
            | Values::Int16(_)
            | Values::Int32(_)
            | Values::Float(_)
            | Values::Date(_)
            | Values::UInt8(_)
            | Values::UInt16(_)
            | Values::UInt32(_)
            | Values::Categorical { .. } => 4,
            Values::Int64(_) | Values::UInt64(_) | Values::Time(_) | Values::Double(_) | Values::Timestamp { .. } => 8,
            Values::Bool(_) => 1,
            Values::Text(_) | Values::Binary(_) => 4,
        }
    }
}

/// One column to write.
pub struct WriteColumn<'a> {
    pub name: String,
    pub values: Values<'a>,
}

/// A table to write.
pub struct Table<'a> {
    pub rows: usize,
    pub columns: Vec<WriteColumn<'a>>,
    /// Labels, formats, notes and the rest. The writer adds what it knows
    /// from the columns: levels, time zones, and the storage and logical
    /// types of columns written as DOUBLE.
    pub profile: Profile,
}

/// How to write. The defaults are plan 0018's.
#[derive(Debug, Clone, Copy)]
pub struct WriteOptions {
    pub compression: Compression,
    /// The codec's level; `None` for its default (zstd 3, gzip 6).
    pub compression_level: Option<i32>,
    /// Rows per row group; `None` sizes them to about 1 GiB of values,
    /// at most 262,144 rows (polars' default). A survey file of thousands
    /// of columns is then one row group, as pyarrow and polars write it:
    /// with four, pyarrow took 2.4 times as long to read one (plan 0018's
    /// 64 MiB, changed by the measurements in bench/RESULTS.md).
    pub row_group_rows: Option<usize>,
    /// Write `.a` to `.z` as tagged NaNs, a numeric, date or timestamp
    /// column that holds any as DOUBLE; with `false` they are plain
    /// nulls, and every column keeps its type.
    pub missing_letters: bool,
    /// Worker threads: 0 for the default (from
    /// [`WRITE_THREADS`](crate::WRITE_THREADS) up with the write's size,
    /// or `DTA_THREADS`), 1 for none.
    pub threads: usize,
    /// About this many uncompressed bytes per data page.
    #[doc(hidden)]
    pub page_bytes: usize,
    /// About this many uncompressed bytes per row group.
    #[doc(hidden)]
    pub row_group_bytes: usize,
    #[doc(hidden)]
    pub row_group_max_rows: usize,
    /// A dictionary stops growing at this size.
    #[doc(hidden)]
    pub dictionary_bytes: usize,
    /// Write offset indexes (for measuring reads without them).
    #[doc(hidden)]
    pub offset_index: bool,
    /// Writes of fewer bytes of values than this are encoded on one
    /// thread.
    #[doc(hidden)]
    pub parallel_bytes: usize,
    /// At most about this many bytes of encoded column chunks wait for
    /// the ones before them to be written.
    #[doc(hidden)]
    pub pipeline_bytes: usize,
    /// The default thread rule for this write, in place of
    /// [`WRITE_BYTES_PER_THREAD`](crate::WRITE_BYTES_PER_THREAD),
    /// [`WRITE_THREADS`](crate::WRITE_THREADS) and
    /// [`WRITE_THREADS_MOST`](crate::WRITE_THREADS_MOST): one thread per
    /// `.0` bytes of values, at least `.1` and at most `.2`. For inputs
    /// measured to have their own (polars' Arrow export, plan 0019).
    #[doc(hidden)]
    pub thread_rule: Option<(u64, usize, usize)>,
}

impl Default for WriteOptions {
    fn default() -> Self {
        let small = std::env::var("DTA_TEST_SMALL_CHUNKS").is_ok_and(|v| v == "1");
        WriteOptions {
            // Snappy, not plan 0018's zstd 3: pyarrow and DuckDB took up to
            // 1.4 times as long to read our zstd files as their own snappy
            // ones (target 4), and on dictionary-encoded survey data zstd
            // saved only about a sixth (bench/RESULTS.md, Parquet).
            compression: Compression::Snappy,
            compression_level: None,
            row_group_rows: None,
            missing_letters: true,
            threads: 0,
            page_bytes: 1 << 20,
            row_group_bytes: 1 << 30,
            row_group_max_rows: 262_144,
            dictionary_bytes: 1 << 20,
            offset_index: true,
            parallel_bytes: if small { 0 } else { 16 << 20 },
            pipeline_bytes: if small { 1 } else { 256 << 20 },
            thread_rule: None,
        }
    }
}

/// What a write produced.
#[derive(Debug, Clone, PartialEq)]
pub struct WriteReport {
    pub bytes: u64,
    pub row_groups: usize,
}

/// The library and version, for the footer's `created_by`.
pub const CREATED_BY: &str = concat!("dta-parquet version ", env!("CARGO_PKG_VERSION"));

/// Write `table` to `out` as a Parquet file.
pub fn write(table: &Table, out: impl Write, options: &WriteOptions) -> Result<WriteReport> {
    write_with_letters(table, out, options, &[])
}

/// [`write`], told which columns hold `.a` to `.z`, so the writer need not
/// read every column once more to find out before it encodes. `letters[k]`
/// is `Some(found)` where the caller has looked at column `k`'s missing
/// codes and found them all 0 to 27, with any of `.a` to `.z` only in a
/// column that can be written as DOUBLE (byte, int, long, float, double,
/// date or timestamp); a letter in a column said to have none is written
/// as a null. `None`, or a column past the end of `letters`, is read as
/// [`write`] reads it.
pub fn write_with_letters(
    table: &Table,
    out: impl Write,
    options: &WriteOptions,
    letters: &[Option<bool>],
) -> Result<WriteReport> {
    let level = options.compression.level(options.compression_level)?;
    let mut names = std::collections::HashSet::with_capacity(table.columns.len());
    for c in &table.columns {
        if !names.insert(c.name.as_str()) {
            return Err(Error::invalid(format!(
                "two columns are named \"{}\"",
                c.name
            )));
        }
        if let Values::Categorical { levels, .. } = &c.values {
            let mut seen = std::collections::HashSet::with_capacity(levels.len());
            if let Some(l) = levels.iter().find(|l| !seen.insert(l.as_str())) {
                return Err(Error::invalid(format!(
                    "column \"{}\" has the level \"{l}\" twice",
                    c.name
                )));
            }
            if u32::try_from(levels.len()).is_err() {
                return Err(
                    Error::invalid(format!("column \"{}\" has too many levels", c.name))
                        .of(ErrorKind::TooLarge),
                );
            }
        }
    }
    // What the write encodes: every row's values at their widths.
    let work = table.columns.iter().fold(0u64, |sum, c| {
        sum.saturating_add((c.values.width() as u64).saturating_mul(table.rows as u64))
    });
    let (per_thread, least, most) = options.thread_rule.unwrap_or((
        crate::WRITE_BYTES_PER_THREAD,
        crate::WRITE_THREADS,
        crate::WRITE_THREADS_MOST,
    ));
    let threads = dta::threads::resolve_scaled(options.threads, work, per_thread, least, most);
    let scratch: Vec<Mutex<Scratch>> = (0..threads.max(1))
        .map(|_| Mutex::new(Scratch::default()))
        .collect();

    // Which columns hold `.a` to `.z`, found before anything is written:
    // those are DOUBLE in every row group.
    let tagged: Vec<bool> = if options.missing_letters {
        let scan = |k: usize, _: &mut Scratch| match letters.get(k).copied().flatten() {
            Some(found) => Ok(found),
            None => holds_letters(&table.columns[k], table.rows),
        };
        let big = table.rows.saturating_mul(table.columns.len() * 8) >= options.parallel_bytes;
        parallel(
            if big { threads } else { 1 },
            table.columns.len(),
            &scratch,
            &scan,
        )
        .into_iter()
        .collect::<Result<_>>()?
    } else {
        vec![false; table.columns.len()]
    };

    let profile = profile_for(table, &tagged)?;
    let schema = schema_for(table, &tagged);
    let arrow_schema = arrow_schema_for(table, &tagged);

    let mut out = Counter { inner: out, at: 0 };
    out.put(b"PAR1")?;
    let ranges = row_groups(table, options);
    let n_cols = table.columns.len();
    let mut groups: Vec<RowGroup> = Vec::with_capacity(ranges.len());
    let mut indexes: Vec<Vec<OffsetIndex>> = Vec::with_capacity(ranges.len());
    // One job per column of each row group, in file order: workers move
    // on to the next row group's columns while the writer is still
    // putting out this one's, so a row group of few columns does not
    // leave threads idle. Chunks are written in order as soon as they
    // and those before them are encoded; the encoded chunks waiting
    // for the writer are held to `pipeline_bytes`, so peak memory stays
    // bounded however many row groups are in flight.
    let job = |j: usize, s: &mut Scratch| {
        let enc = Encoder {
            options,
            compression: options.compression,
            level,
        };
        let k = j % n_cols;
        enc.column(&table.columns[k], ranges[j / n_cols].clone(), tagged[k], s)
    };
    let pipelined = if work >= options.parallel_bytes as u64 {
        threads
    } else {
        1
    };
    let (mut start, mut total, mut compressed) = (0u64, 0i64, 0i64);
    let mut chunks = Vec::with_capacity(n_cols);
    let mut group_index = Vec::with_capacity(n_cols);
    let jobs = if n_cols == 0 { 0 } else { ranges.len() * n_cols };
    parallel_ordered(
        pipelined,
        jobs,
        &scratch,
        &job,
        &|e: &Encoded| e.dict.len() + e.data.len(),
        options.pipeline_bytes,
        |j, e| {
            let (g, k) = (j / n_cols, j % n_cols);
            if k == 0 {
                start = out.at;
                (total, compressed) = (0, 0);
            }
            let (cc, oi) = put_chunk(
                &mut out,
                &table.columns[k].name,
                e,
                options.compression.codec(),
            )?;
            total += cc.meta.as_ref().map_or(0, |m| m.total_uncompressed_size);
            compressed += cc.meta.as_ref().map_or(0, |m| m.total_compressed_size);
            chunks.push(cc);
            group_index.push(oi);
            if k + 1 == n_cols {
                groups.push(RowGroup {
                    columns: std::mem::replace(&mut chunks, Vec::with_capacity(n_cols)),
                    total_byte_size: total,
                    num_rows: ranges[g].len() as i64,
                    file_offset: Some(start as i64),
                    total_compressed_size: Some(compressed),
                    ordinal: i16::try_from(g).ok(),
                });
                indexes.push(std::mem::replace(&mut group_index, Vec::with_capacity(n_cols)));
            }
            Ok(())
        },
    )?;
    if n_cols == 0 {
        for (g, rows) in ranges.iter().enumerate() {
            groups.push(RowGroup {
                columns: Vec::new(),
                total_byte_size: 0,
                num_rows: rows.len() as i64,
                file_offset: Some(out.at as i64),
                total_compressed_size: Some(0),
                ordinal: i16::try_from(g).ok(),
            });
            indexes.push(Vec::new());
        }
    }
    if options.offset_index {
        for (g, group_index) in groups.iter_mut().zip(indexes) {
            for (cc, oi) in g.columns.iter_mut().zip(group_index) {
                let bytes = oi.to_bytes();
                cc.offset_index = Some((out.at as i64, bytes.len() as i32));
                out.put(&bytes)?;
            }
        }
    }
    let leaves = schema.len() - 1;
    let meta = FileMetaData {
        version: 2,
        schema,
        num_rows: table.rows as i64,
        row_groups: groups,
        key_value: vec![
            KeyValue {
                key: profile::KEY.into(),
                value: Some(profile.into_bytes()),
            },
            KeyValue {
                key: "ARROW:schema".into(),
                value: Some(arrow_schema.into_bytes()),
            },
        ],
        created_by: Some(CREATED_BY.into()),
        column_orders: Some(vec![ColumnOrder::TypeDefined; leaves]),
        encrypted: false,
    };
    let footer = meta.to_bytes();
    let row_groups = meta.row_groups.len();
    out.put(&footer)?;
    out.put(&(footer.len() as u32).to_le_bytes())?;
    out.put(b"PAR1")?;
    out.inner.flush()?;
    Ok(WriteReport {
        bytes: out.at,
        row_groups,
    })
}

/// Counts the bytes written, for the offsets in the footer.
struct Counter<W: Write> {
    inner: W,
    at: u64,
}

impl<W: Write> Counter<W> {
    fn put(&mut self, bytes: &[u8]) -> Result<()> {
        self.inner.write_all(bytes)?;
        self.at += bytes.len() as u64;
        Ok(())
    }
}

/// Write one encoded chunk; return its footer entry and offset index.
fn put_chunk<W: Write>(
    out: &mut Counter<W>,
    name: &str,
    e: Encoded,
    codec: Codec,
) -> Result<(ColumnChunk, OffsetIndex)> {
    let start = out.at;
    out.put(&e.dict)?;
    let data_start = out.at;
    out.put(&e.data)?;
    let pages = e
        .pages
        .iter()
        .map(|p| PageLocation {
            offset: (data_start + p.offset) as i64,
            compressed_page_size: p.len,
            first_row_index: p.first_row as i64,
        })
        .collect();
    let meta = ColumnMetaData {
        physical: e.physical,
        encodings: e.encodings,
        path: vec![name.to_string()],
        codec,
        num_values: e.rows as i64,
        total_uncompressed_size: e.uncompressed as i64,
        total_compressed_size: (e.dict.len() + e.data.len()) as i64,
        data_page_offset: data_start as i64,
        dictionary_page_offset: (!e.dict.is_empty()).then_some(start as i64),
        statistics: Some(e.stats),
    };
    Ok((
        ColumnChunk {
            file_path: None,
            meta: Some(meta),
            offset_index: None,
            encrypted: false,
        },
        OffsetIndex { pages },
    ))
}

/// Whether a column holds any of `.a` to `.z`. A code past `.z` is an
/// error, and so is a letter in a column that cannot be written as DOUBLE
/// (64-bit integers, which a double cannot hold exactly, and booleans).
fn holds_letters(c: &WriteColumn, rows: usize) -> Result<bool> {
    fn scan<T: Default + Copy>(
        fill: &Fill<T>,
        rows: usize,
        name: &str,
        widens: bool,
    ) -> Result<bool> {
        let mut values = [T::default(); BLOCK];
        let mut codes = vec![0u8; BLOCK];
        let mut found = false;
        for first in (0..rows).step_by(BLOCK) {
            let n = BLOCK.min(rows - first);
            codes[..n].fill(0);
            fill(first, &mut values[..n], &mut codes[..n]);
            for (i, &c) in codes[..n].iter().enumerate() {
                if c > missing::LAST {
                    return Err(bad_code(name, first + i, c));
                }
                if c > missing::SYSTEM {
                    if !widens {
                        return Err(Error::invalid(format!(
                            "column \"{name}\": row {} holds {}, but .a to .z can be written only in byte, int, long, float, double, date and timestamp columns; turn missing_letters off to write them as nulls",
                            first + i + 1,
                            missing::name(c).unwrap_or_default()
                        )));
                    }
                    found = true;
                }
            }
        }
        Ok(found)
    }
    let name = &c.name;
    match &c.values {
        Values::Int8(f) | Values::Int16(f) | Values::Int32(f) => scan(f.as_ref(), rows, name, true),
        Values::Float(f) => scan(f.as_ref(), rows, name, true),
        Values::Double(f) => scan(f.as_ref(), rows, name, true),
        Values::Date(f) => scan(f.as_ref(), rows, name, true),
        Values::Timestamp { fill: f, .. } => scan(f.as_ref(), rows, name, true),
        Values::Int64(f) | Values::Time(f) => scan(f.as_ref(), rows, name, false),
        Values::UInt8(f) | Values::UInt16(f) | Values::UInt32(f) => scan(f.as_ref(), rows, name, false),
        Values::UInt64(f) => scan(f.as_ref(), rows, name, false),
        Values::Bool(f) => scan(f.as_ref(), rows, name, false),
        Values::Text(_) | Values::Binary(_) | Values::Categorical { .. } => Ok(false),
    }
}

/// What a column written as DOUBLE because it holds `.a` to `.z` was.
fn storage_of(values: &Values) -> Option<Storage> {
    match values {
        Values::Int8(_) => Some(Storage::Byte),
        Values::Int16(_) => Some(Storage::Int),
        Values::Int32(_) => Some(Storage::Long),
        Values::Float(_) => Some(Storage::Float),
        _ => None,
    }
}

/// What a column written as DOUBLE because it holds `.a` to `.z` was,
/// when it was a date or a timestamp.
fn logical_of(values: &Values) -> Option<Logical> {
    match values {
        Values::Date(_) => Some(Logical::Date),
        Values::Timestamp { .. } => Some(Logical::Timestamp),
        _ => None,
    }
}

fn bad_code(name: &str, row: usize, code: u8) -> Error {
    Error::invalid(format!(
        "column \"{name}\": row {} has missing code {code}, which is not one of . and .a to .z",
        row + 1
    ))
}

fn profile_for(table: &Table, tagged: &[bool]) -> Result<String> {
    let mut p = table.profile.clone();
    let mut at: HashMap<String, usize> =
        p.columns.iter().enumerate().map(|(k, c)| (c.name.clone(), k)).collect();
    for (k, c) in table.columns.iter().enumerate() {
        let i = *at.entry(c.name.clone()).or_insert_with(|| {
            p.columns.push(ColumnProfile::named(c.name.clone()));
            p.columns.len() - 1
        });
        let entry = &mut p.columns[i];
        // A Double column keeps the date or timestamp type its caller
        // gives it: R's `Date` and `POSIXct` are written so when DATE or
        // TIMESTAMP cannot hold their values exactly.
        let given = match c.values {
            Values::Double(_) => entry.logical,
            _ => None,
        };
        (entry.storage, entry.logical) = if tagged[k] {
            (storage_of(&c.values), logical_of(&c.values).or(given))
        } else {
            (None, given)
        };
        match &c.values {
            Values::Categorical {
                levels, ordered, ..
            } => {
                entry.categorical = Some(Categorical {
                    levels: levels.clone(),
                    ordered: *ordered,
                })
            }
            Values::Timestamp { utc, zone, .. } => {
                entry.tz = match (zone, utc) {
                    (Some(z), _) => Some(z.clone()),
                    // An instant without a zone.
                    (None, true) => Some(String::new()),
                    (None, false) => None,
                }
            }
            _ => {}
        }
    }
    p.to_json()
}

fn schema_for(table: &Table, tagged: &[bool]) -> Vec<SchemaElement> {
    let mut schema = Vec::with_capacity(table.columns.len() + 1);
    schema.push(SchemaElement {
        name: "schema".into(),
        num_children: Some(table.columns.len() as i32),
        ..Default::default()
    });
    let int = |bits| Some(LogicalType::Integer { bits, signed: true });
    let uint = |bits| Some(LogicalType::Integer { bits, signed: false });
    for (c, &tagged) in table.columns.iter().zip(tagged) {
        let (physical, logical, conv) = match &c.values {
            _ if tagged => (PhysicalType::Double, None, None),
            Values::Int8(_) => (PhysicalType::Int32, int(8), Some(converted::INT_8)),
            Values::Int16(_) => (PhysicalType::Int32, int(16), Some(converted::INT_16)),
            Values::Int32(_) => (PhysicalType::Int32, None, None),
            Values::Int64(_) => (PhysicalType::Int64, None, None),
            Values::UInt8(_) => (PhysicalType::Int32, uint(8), Some(converted::UINT_8)),
            Values::UInt16(_) => (PhysicalType::Int32, uint(16), Some(converted::UINT_16)),
            Values::UInt32(_) => (PhysicalType::Int32, uint(32), Some(converted::UINT_32)),
            Values::UInt64(_) => (PhysicalType::Int64, uint(64), Some(converted::UINT_64)),
            // TIME_MICROS and TIME_MILLIS mean times adjusted to UTC, and
            // there is no converted type for nanoseconds.
            Values::Time(_) => (
                PhysicalType::Int64,
                Some(LogicalType::Time { utc: false, unit: Some(TimeUnit::Nanos) }),
                None,
            ),
            Values::Float(_) => (PhysicalType::Float, None, None),
            Values::Double(_) => (PhysicalType::Double, None, None),
            Values::Bool(_) => (PhysicalType::Boolean, None, None),
            Values::Date(_) => (
                PhysicalType::Int32,
                Some(LogicalType::Date),
                Some(converted::DATE),
            ),
            Values::Timestamp { unit, utc, .. } => {
                // The converted types mean instants in milliseconds or
                // microseconds only.
                let conv = match (utc, unit) {
                    (true, TimeUnit::Millis) => Some(converted::TIMESTAMP_MILLIS),
                    (true, TimeUnit::Micros) => Some(converted::TIMESTAMP_MICROS),
                    _ => None,
                };
                (
                    PhysicalType::Int64,
                    Some(LogicalType::Timestamp {
                        utc: *utc,
                        unit: Some(*unit),
                    }),
                    conv,
                )
            }
            Values::Text(_) | Values::Categorical { .. } => (
                PhysicalType::ByteArray,
                Some(LogicalType::String),
                Some(converted::UTF8),
            ),
            Values::Binary(_) => (PhysicalType::ByteArray, None, None),
        };
        schema.push(SchemaElement {
            name: c.name.clone(),
            physical: Some(physical),
            repetition: Some(Repetition::Optional),
            logical,
            converted: conv,
            ..Default::default()
        });
    }
    schema
}

fn arrow_schema_for(table: &Table, tagged: &[bool]) -> String {
    let fields: Vec<(String, ArrowType)> = table
        .columns
        .iter()
        .zip(tagged)
        .map(|(c, &tagged)| {
            let ty = match &c.values {
                _ if tagged => ArrowType::Float64,
                Values::Int8(_) => ArrowType::Int { bits: 8 },
                Values::Int16(_) => ArrowType::Int { bits: 16 },
                Values::Int32(_) => ArrowType::Int { bits: 32 },
                Values::Int64(_) => ArrowType::Int { bits: 64 },
                Values::UInt8(_) => ArrowType::UInt { bits: 8 },
                Values::UInt16(_) => ArrowType::UInt { bits: 16 },
                Values::UInt32(_) => ArrowType::UInt { bits: 32 },
                Values::UInt64(_) => ArrowType::UInt { bits: 64 },
                Values::Time(_) => ArrowType::Time64Nanos,
                Values::Float(_) => ArrowType::Float32,
                Values::Double(_) => ArrowType::Float64,
                Values::Bool(_) => ArrowType::Bool,
                Values::Date(_) => ArrowType::Date32,
                Values::Timestamp {
                    unit, utc, zone, ..
                } => ArrowType::Timestamp {
                    unit: *unit,
                    zone: match (zone, utc) {
                        (Some(z), _) => Some(z.clone()),
                        (None, true) => Some("UTC".into()),
                        (None, false) => None,
                    },
                },
                Values::Text(_) => ArrowType::Utf8,
                Values::Binary(_) => ArrowType::Binary,
                Values::Categorical { ordered, .. } => ArrowType::Dictionary { ordered: *ordered },
            };
            (c.name.clone(), ty)
        })
        .collect();
    arrow::schema_entry(&fields)
}

/// The rows of each row group.
fn row_groups(table: &Table, options: &WriteOptions) -> Vec<Range<usize>> {
    let rows = table.rows;
    if let Some(n) = options.row_group_rows {
        let n = n.max(1);
        return (0..rows).step_by(n).map(|s| s..(s + n).min(rows)).collect();
    }
    let max_rows = options.row_group_max_rows.max(1);
    let fixed: usize = table.columns.iter().map(|c| c.values.width()).sum();
    let texts: Vec<&GetBytes> = table
        .columns
        .iter()
        .filter_map(|c| match &c.values {
            Values::Text(g) | Values::Binary(g) => Some(g.as_ref()),
            _ => None,
        })
        .collect();
    if texts.is_empty() {
        let n = (options.row_group_bytes / fixed.max(1)).clamp(1, max_rows);
        return (0..rows).step_by(n).map(|s| s..(s + n).min(rows)).collect();
    }
    // Text widths vary, so add them up row by row.
    let mut out = Vec::new();
    let mut start = 0;
    let mut bytes = 0usize;
    for r in 0..rows {
        bytes += fixed
            + texts
                .iter()
                .map(|g| g(r).map_or(0, <[u8]>::len))
                .sum::<usize>();
        if r + 1 - start >= max_rows || bytes >= options.row_group_bytes {
            out.push(start..r + 1);
            start = r + 1;
            bytes = 0;
        }
    }
    if start < rows {
        out.push(start..rows);
    }
    out
}

/// Run `f(k)` for `k` in `0..n` on up to `threads` threads; results in
/// order. Each thread has its own scratch, kept between calls.
fn parallel<T: Send>(
    threads: usize,
    n: usize,
    scratch: &[Mutex<Scratch>],
    f: &(dyn Fn(usize, &mut Scratch) -> Result<T> + Sync),
) -> Vec<Result<T>> {
    let lock = |k: usize| scratch[k].lock().unwrap_or_else(PoisonError::into_inner);
    if threads <= 1 || n <= 1 {
        let mut s = lock(0);
        return (0..n).map(|k| f(k, &mut s)).collect();
    }
    let results: Vec<Mutex<Option<Result<T>>>> = (0..n).map(|_| Mutex::new(None)).collect();
    let next = AtomicUsize::new(0);
    let work = |w: usize| {
        let mut s = lock(w);
        loop {
            let k = next.fetch_add(1, Ordering::Relaxed);
            if k >= n {
                break;
            }
            let r = catch_unwind(AssertUnwindSafe(|| f(k, &mut s))).unwrap_or_else(|p| {
                Err(
                    Error::new(format!("a write thread panicked: {}", panic_text(&*p)))
                        .of(ErrorKind::Internal),
                )
            });
            *results[k].lock().unwrap_or_else(PoisonError::into_inner) = Some(r);
        }
    };
    let work = &work;
    std::thread::scope(|scope| {
        let mut started = 0;
        for w in 0..threads.min(n).min(scratch.len()) {
            if std::thread::Builder::new()
                .spawn_scoped(scope, move || work(w))
                .is_ok()
            {
                started += 1;
            }
        }
        if started == 0 {
            work(0);
        }
    });
    results
        .into_iter()
        .map(|m| {
            m.into_inner()
                .unwrap_or_else(PoisonError::into_inner)
                .unwrap_or_else(|| {
                    Err(Error::new("a column was not encoded").of(ErrorKind::Internal))
                })
        })
        .collect()
}

/// Run `f(k)` for `k` in `0..n` on up to `threads` threads, and give
/// each result to `sink` on the calling thread, in order, as soon as it
/// and those before it are done. Workers run at most two results per
/// thread ahead of `sink`, and start nothing new while the results
/// waiting for `sink` come to `budget` bytes or more (by `size`), so
/// few are held at once. Stops at the first error.
fn parallel_ordered<T: Send>(
    threads: usize,
    n: usize,
    scratch: &[Mutex<Scratch>],
    f: &(dyn Fn(usize, &mut Scratch) -> Result<T> + Sync),
    size: &(dyn Fn(&T) -> usize + Sync),
    budget: usize,
    mut sink: impl FnMut(usize, T) -> Result<()>,
) -> Result<()> {
    let lock = |k: usize| scratch[k].lock().unwrap_or_else(PoisonError::into_inner);
    let threads = threads.min(n).min(scratch.len());
    if threads <= 1 {
        let mut s = lock(0);
        for k in 0..n {
            let t = f(k, &mut s)?;
            sink(k, t)?;
        }
        return Ok(());
    }
    struct State<T> {
        results: Vec<Option<Result<T>>>,
        /// The next column to hand to a worker.
        next: usize,
        /// Results given to `sink` so far.
        done: usize,
        /// Bytes of the results done but not yet given to `sink`.
        held: usize,
        stop: bool,
    }
    let window = 2 * threads;
    let state = Mutex::new(State {
        results: (0..n).map(|_| None).collect(),
        next: 0,
        done: 0,
        held: 0,
        stop: false,
    });
    let changed = Condvar::new();
    let guard = || state.lock().unwrap_or_else(PoisonError::into_inner);
    let work = |w: usize| {
        let mut s = lock(w);
        loop {
            let k = {
                let mut st = guard();
                // While results are held, the one `sink` waits for is
                // being encoded (jobs start in order), so this ends.
                while !st.stop
                    && st.next < n
                    && (st.next >= st.done + window || (st.held >= budget && st.next > st.done))
                {
                    st = changed.wait(st).unwrap_or_else(PoisonError::into_inner);
                }
                if st.stop || st.next >= n {
                    break;
                }
                st.next += 1;
                st.next - 1
            };
            let r = catch_unwind(AssertUnwindSafe(|| f(k, &mut s))).unwrap_or_else(|p| {
                Err(
                    Error::new(format!("a write thread panicked: {}", panic_text(&*p)))
                        .of(ErrorKind::Internal),
                )
            });
            let bytes = r.as_ref().map_or(0, size);
            let mut st = guard();
            st.results[k] = Some(r);
            st.held += bytes;
            drop(st);
            changed.notify_all();
        }
    };
    let work = &work;
    std::thread::scope(|scope| {
        let mut started = 0;
        for w in 0..threads {
            if std::thread::Builder::new()
                .spawn_scoped(scope, move || work(w))
                .is_ok()
            {
                started += 1;
            }
        }
        let mut outcome = Ok(());
        for k in 0..n {
            let r = {
                let mut st = guard();
                loop {
                    if let Some(r) = st.results[k].take() {
                        st.held -= r.as_ref().map_or(0, size);
                        break Some(r);
                    }
                    if started == 0 {
                        break None;
                    }
                    st = changed.wait(st).unwrap_or_else(PoisonError::into_inner);
                }
            };
            // No worker started: encode here.
            let r = r.unwrap_or_else(|| f(k, &mut lock(0)));
            outcome = r.and_then(|t| sink(k, t));
            let mut st = guard();
            st.done = k + 1;
            if outcome.is_err() {
                st.stop = true;
            }
            drop(st);
            changed.notify_all();
            if outcome.is_err() {
                break;
            }
        }
        outcome
    })
}

fn panic_text(payload: &(dyn std::any::Any + Send)) -> String {
    payload
        .downcast_ref::<&str>()
        .map(|s| s.to_string())
        .or_else(|| payload.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "unknown panic".into())
}

// ---- encoding ----

/// A thread's reused buffers.
#[derive(Default)]
struct Scratch {
    codecs: Codecs,
    page: Vec<u8>,
    packed: Vec<u8>,
    levels: Vec<u8>,
    /// The largest numbers dictionary's table so far, empty, for the
    /// next chunk: growing one from nothing to its limit took a third of
    /// the time to write wide.dta.
    numbers_map: NumbersMap,
}

type NumbersMap = HashMap<u64, u32, BuildHasherDefault<Fx>>;

impl Scratch {
    /// A table for a chunk of `rows` rows: the kept one, unless emptying
    /// it again would cost more than the chunk's rows do.
    fn numbers_map(&mut self, rows: usize) -> NumbersMap {
        if self.numbers_map.capacity() <= rows.saturating_mul(4) {
            std::mem::take(&mut self.numbers_map)
        } else {
            NumbersMap::default()
        }
    }

    /// Keep a chunk's table, emptied, if it is the largest so far.
    fn keep_numbers_map(&mut self, mut map: NumbersMap) {
        if map.capacity() > self.numbers_map.capacity() {
            map.clear();
            self.numbers_map = map;
        }
    }
}

/// A page's place in its chunk's data pages.
struct Page {
    offset: u64,
    len: i32,
    first_row: u64,
}

/// One column chunk, encoded.
struct Encoded {
    physical: PhysicalType,
    /// The dictionary page, header included, or nothing.
    dict: Vec<u8>,
    /// The data pages, headers included.
    data: Vec<u8>,
    pages: Vec<Page>,
    uncompressed: usize,
    encodings: Vec<Encoding>,
    stats: Statistics,
    rows: usize,
}

struct Encoder<'o> {
    options: &'o WriteOptions,
    compression: Compression,
    level: i32,
}

/// The pages of a chunk as they are written.
struct Pages {
    physical: PhysicalType,
    dict: Vec<u8>,
    data: Vec<u8>,
    pages: Vec<Page>,
    uncompressed: usize,
    encodings: Vec<Encoding>,
}

impl Pages {
    fn new(physical: PhysicalType) -> Self {
        Pages {
            physical,
            dict: Vec::new(),
            data: Vec::new(),
            pages: Vec::new(),
            uncompressed: 0,
            encodings: vec![Encoding::Rle],
        }
    }

    fn uses(&mut self, e: Encoding) {
        if !self.encodings.contains(&e) {
            self.encodings.push(e);
        }
    }

    fn finish(self, stats: Statistics, rows: usize) -> Encoded {
        Encoded {
            physical: self.physical,
            dict: self.dict,
            data: self.data,
            pages: self.pages,
            uncompressed: self.uncompressed,
            encodings: self.encodings,
            stats,
            rows,
        }
    }
}

impl Encoder<'_> {
    /// Compress `s.page` and append it with its header to `out`; returns
    /// the header and page's length.
    fn put_page(
        &self,
        s: &mut Scratch,
        mut header: PageHeader,
        out: &mut Vec<u8>,
        uncompressed: &mut usize,
    ) -> Result<i32> {
        let Scratch {
            codecs,
            page,
            packed,
            ..
        } = s;
        packed.clear();
        codecs.compress(self.compression, self.level, page, packed)?;
        let too_big = || {
            Error::invalid(format!(
                "a page of {} bytes is larger than Parquet allows",
                page.len()
            ))
            .of(ErrorKind::TooLarge)
        };
        header.uncompressed_page_size = i32::try_from(page.len()).map_err(|_| too_big())?;
        header.compressed_page_size = i32::try_from(packed.len()).map_err(|_| too_big())?;
        let start = out.len();
        header.write(out);
        let header_len = out.len() - start;
        out.extend_from_slice(packed);
        *uncompressed += header_len + page.len();
        i32::try_from(out.len() - start).map_err(|_| too_big())
    }

    /// Write a data page of `rows` rows whose levels are `s.levels` and
    /// whose encoded values are `values`.
    fn data_page(
        &self,
        s: &mut Scratch,
        p: &mut Pages,
        first_row: u64,
        encoding: Encoding,
        values: &[u8],
    ) -> Result<()> {
        let rows = s.levels.len();
        s.page.clear();
        s.page.extend_from_slice(&[0; 4]);
        rle::encode(&s.levels, 1, &mut s.page);
        let len = (s.page.len() - 4) as u32;
        s.page[..4].copy_from_slice(&len.to_le_bytes());
        s.page.extend_from_slice(values);
        let header = PageHeader {
            kind: PageType::Data,
            uncompressed_page_size: 0,
            compressed_page_size: 0,
            data: Some(DataPageHeader {
                num_values: i32::try_from(rows).map_err(|_| {
                    Error::invalid("too many rows in a page").of(ErrorKind::TooLarge)
                })?,
                encoding,
                definition_level_encoding: Encoding::Rle,
                repetition_level_encoding: Encoding::Rle,
            }),
            dictionary: None,
            data_v2: None,
        };
        let offset = p.data.len() as u64;
        let len = self.put_page(s, header, &mut p.data, &mut p.uncompressed)?;
        p.pages.push(Page {
            offset,
            len,
            first_row,
        });
        p.uses(encoding);
        s.levels.clear();
        Ok(())
    }

    fn dictionary_page(
        &self,
        s: &mut Scratch,
        p: &mut Pages,
        count: usize,
        values: &[u8],
    ) -> Result<()> {
        s.page.clear();
        s.page.extend_from_slice(values);
        let header = PageHeader {
            kind: PageType::Dictionary,
            uncompressed_page_size: 0,
            compressed_page_size: 0,
            data: None,
            dictionary: Some(DictionaryPageHeader {
                num_values: count as i32,
                encoding: Encoding::Plain,
            }),
            data_v2: None,
        };
        let mut dict = Vec::new();
        self.put_page(s, header, &mut dict, &mut p.uncompressed)?;
        p.dict = dict;
        p.uses(Encoding::Plain);
        Ok(())
    }

    /// Encode a column's rows; `tagged`: the column holds `.a` to `.z`
    /// and is written as DOUBLE.
    fn column(
        &self,
        c: &WriteColumn,
        rows: Range<usize>,
        tagged: bool,
        s: &mut Scratch,
    ) -> Result<Encoded> {
        use PhysicalType::{Double, Float, Int32, Int64};
        let name = &c.name;
        match &c.values {
            // A byte or int column still checks its values fit.
            Values::Int8(f) if tagged => self.numbers(&mut tag(f), rows, s, name, Double, Some(8)),
            Values::Int16(f) if tagged => {
                self.numbers(&mut tag(f), rows, s, name, Double, Some(16))
            }
            Values::Int32(f) if tagged => self.numbers(&mut tag(f), rows, s, name, Double, None),
            Values::Float(f) if tagged => self.numbers(&mut tag(f), rows, s, name, Double, None),
            Values::Double(f) if tagged => self.numbers(&mut tag(f), rows, s, name, Double, None),
            // Days since 1970, as R's Date holds them.
            Values::Date(f) if tagged => self.numbers(&mut tag(f), rows, s, name, Double, None),
            // Seconds since 1970, as R's POSIXct holds them.
            Values::Timestamp { unit, fill: f, .. } if tagged => {
                let per_second: i64 = match unit {
                    TimeUnit::Millis => 1_000,
                    TimeUnit::Micros => 1_000_000,
                    TimeUnit::Nanos => 1_000_000_000,
                };
                let seconds = move |x: i64| {
                    if x.unsigned_abs() <= 1 << 53 {
                        // Exact as a double, so one rounding.
                        x as f64 / per_second as f64
                    } else {
                        // Whole seconds and the fraction apart, both with
                        // the sign of `x`, so that nothing cancels.
                        (x / per_second) as f64 + (x % per_second) as f64 / per_second as f64
                    }
                };
                self.numbers(&mut tag_with(f, seconds), rows, s, name, Double, None)
            }
            Values::Int8(f) => self.numbers(&mut f.as_ref(), rows, s, name, Int32, Some(8)),
            Values::Int16(f) => self.numbers(&mut f.as_ref(), rows, s, name, Int32, Some(16)),
            Values::Int32(f) | Values::Date(f) => {
                self.numbers(&mut f.as_ref(), rows, s, name, Int32, None)
            }
            Values::Int64(f) | Values::Time(f) | Values::Timestamp { fill: f, .. } => {
                self.numbers(&mut f.as_ref(), rows, s, name, Int64, None)
            }
            Values::UInt8(f) => self.numbers(&mut f.as_ref(), rows, s, name, Int32, Some(8)),
            Values::UInt16(f) => self.numbers(&mut f.as_ref(), rows, s, name, Int32, Some(16)),
            Values::UInt32(f) => self.numbers(&mut f.as_ref(), rows, s, name, Int32, None),
            Values::UInt64(f) => self.numbers(&mut f.as_ref(), rows, s, name, Int64, None),
            Values::Float(f) => self.numbers(&mut f.as_ref(), rows, s, name, Float, None),
            Values::Double(f) => self.numbers(&mut f.as_ref(), rows, s, name, Double, None),
            Values::Bool(f) => self.booleans(f.as_ref(), rows, s, name),
            Values::Text(g) => self.texts(g.as_ref(), rows, s, name, true),
            Values::Binary(g) => self.texts(g.as_ref(), rows, s, name, false),
            Values::Categorical { levels, codes, .. } => {
                self.categorical(levels, codes.as_ref(), rows, s, name)
            }
        }
    }

    /// A numeric chunk: dictionary-encoded while that pays (plan 0018),
    /// else PLAIN. Every missing code is a null; `.a` to `.z` that are to
    /// be kept arrive as tagged NaN values ([`tag`]).
    fn numbers<T: Number>(
        &self,
        fill: &mut Block<T>,
        rows: Range<usize>,
        s: &mut Scratch,
        name: &str,
        physical: PhysicalType,
        bits: Option<u32>,
    ) -> Result<Encoded> {
        let mut p = Pages::new(physical);
        let mut values = [T::default(); BLOCK];
        let mut codes = vec![0u8; BLOCK];
        // The dictionary is written or dropped by the time it holds
        // dictionary_bytes of values, so its table is made that size (or
        // the chunk's) at once, reusing this thread's largest table.
        let most = rows.len().min(self.options.dictionary_bytes / T::WIDTH + 1);
        let mut map = s.numbers_map(rows.len());
        map.reserve(most);
        let mut dict: Option<Dictionary<u64, T>> = Some(Dictionary { map, ..Dictionary::default() });
        let mut plain = Vec::new();
        let mut stats = Stats::<T>::default();
        let mut page_first = 0usize;
        s.levels.clear();
        for first in rows.clone().step_by(BLOCK) {
            let n = BLOCK.min(rows.end - first);
            codes[..n].fill(0);
            fill(first, &mut values[..n], &mut codes[..n]);
            if let Some(d) = &dict {
                // A first page whose values so far are nearly all
                // different will not make a dictionary pay (60% of the
                // plain values), so stop building one: for a column of
                // measurements most of the write was the hashing.
                let seen = d.indices.len();
                if p.pages.is_empty() && seen >= DISTINCT_SAMPLE && d.values.len() * 10 >= seen * 9 {
                    plain.clear();
                    for &i in &d.indices {
                        d.values[i as usize].put(&mut plain);
                    }
                    if let Some(d) = dict.take() {
                        s.keep_numbers_map(d.map);
                    }
                }
            }
            for i in 0..n {
                let row = first + i - rows.start;
                let code = codes[i];
                if code == 0 {
                    let v = values[i];
                    if let Some(bits) = bits {
                        if !v.fits(bits) {
                            return Err(Error::invalid(format!("column \"{name}\": the value {v:?} in row {} does not fit in {bits} bits", first + i + 1)));
                        }
                    }
                    stats.add(v);
                    s.levels.push(1);
                    match &mut dict {
                        Some(d) => {
                            if d.add(v.key(), v, T::WIDTH)
                                && d.bytes >= self.options.dictionary_bytes
                            {
                                // The dictionary is full: this page ends
                                // here, and the rest of the chunk is PLAIN.
                                self.flush_numbers(s, &mut p, &mut dict, &mut plain, page_first)?;
                                page_first = row + 1;
                                if dict.is_some() {
                                    self.numbers_dictionary(s, &mut p, &mut dict)?;
                                }
                            }
                        }
                        None => v.put(&mut plain),
                    }
                } else {
                    if code > missing::LAST {
                        return Err(bad_code(name, first + i, code));
                    }
                    stats.nulls += 1;
                    s.levels.push(0);
                }
                let size = match &dict {
                    Some(d) => d.indices.len() * width(d.values.len()) as usize / 8,
                    None => plain.len(),
                };
                if size + s.levels.len() / 8 >= self.options.page_bytes {
                    self.flush_numbers(s, &mut p, &mut dict, &mut plain, page_first)?;
                    page_first = row + 1;
                }
            }
        }
        if !s.levels.is_empty() || p.pages.is_empty() {
            self.flush_numbers(s, &mut p, &mut dict, &mut plain, page_first)?;
        }
        if dict.is_some() {
            self.numbers_dictionary(s, &mut p, &mut dict)?;
        }
        Ok(p.finish(stats.finish(), rows.len()))
    }

    /// Write the numbers' dictionary page, once.
    fn numbers_dictionary<T: Number>(
        &self,
        s: &mut Scratch,
        p: &mut Pages,
        dict: &mut Option<Dictionary<u64, T>>,
    ) -> Result<()> {
        let Some(d) = dict.take() else { return Ok(()) };
        s.keep_numbers_map(d.map);
        if !p.dict.is_empty() {
            return Ok(());
        }
        let mut bytes = Vec::with_capacity(d.values.len() * T::WIDTH);
        for v in &d.values {
            v.put(&mut bytes);
        }
        self.dictionary_page(s, p, d.values.len(), &bytes)
    }

    /// Write the current page. On the first page, a dictionary that is
    /// too large, or not smaller than 60% of the values it replaces, is
    /// dropped and the chunk is PLAIN from the start.
    fn flush_numbers<T: Number>(
        &self,
        s: &mut Scratch,
        p: &mut Pages,
        dict: &mut Option<Dictionary<u64, T>>,
        plain: &mut Vec<u8>,
        first_row: usize,
    ) -> Result<()> {
        if let Some(d) = dict {
            let first_page = p.pages.is_empty();
            if first_page && !d.pays(T::WIDTH * d.indices.len(), self.options.dictionary_bytes) {
                plain.clear();
                for &i in &d.indices {
                    d.values[i as usize].put(plain);
                }
                if let Some(d) = dict.take() {
                    s.keep_numbers_map(d.map);
                }
            } else {
                let mut values = Vec::new();
                d.encode_indices(&mut values);
                self.data_page(s, p, first_row as u64, Encoding::RleDictionary, &values)?;
                d.indices.clear();
                if d.bytes >= self.options.dictionary_bytes {
                    // Full: the dictionary page is written now with what it
                    // has, and later pages are PLAIN.
                    self.numbers_dictionary(s, p, dict)?;
                }
                return Ok(());
            }
        }
        let values = std::mem::take(plain);
        self.data_page(s, p, first_row as u64, Encoding::Plain, &values)?;
        *plain = values;
        plain.clear();
        Ok(())
    }

    fn booleans(
        &self,
        fill: &Fill<u8>,
        rows: Range<usize>,
        s: &mut Scratch,
        name: &str,
    ) -> Result<Encoded> {
        let mut p = Pages::new(PhysicalType::Boolean);
        let mut values = vec![0u8; BLOCK];
        let mut codes = vec![0u8; BLOCK];
        let mut bits = Vec::new();
        let (mut acc, mut n_bits) = (0u8, 0u32);
        let mut stats = Stats::<u8>::default();
        let mut page_first = 0;
        s.levels.clear();
        let flush = |s: &mut Scratch,
                     p: &mut Pages,
                     bits: &mut Vec<u8>,
                     acc: &mut u8,
                     n_bits: &mut u32,
                     first: usize|
         -> Result<()> {
            if *n_bits > 0 {
                bits.push(*acc);
            }
            self.data_page(s, p, first as u64, Encoding::Plain, bits)?;
            bits.clear();
            (*acc, *n_bits) = (0, 0);
            Ok(())
        };
        for first in rows.clone().step_by(BLOCK) {
            let n = BLOCK.min(rows.end - first);
            codes[..n].fill(0);
            fill(first, &mut values[..n], &mut codes[..n]);
            for i in 0..n {
                if codes[i] == 0 {
                    let v = values[i];
                    if v > 1 {
                        return Err(Error::invalid(format!(
                            "column \"{name}\": row {} holds {v}, not a boolean",
                            first + i + 1
                        )));
                    }
                    stats.add(v);
                    s.levels.push(1);
                    acc |= v << n_bits;
                    n_bits += 1;
                    if n_bits == 8 {
                        bits.push(acc);
                        (acc, n_bits) = (0, 0);
                    }
                } else {
                    if codes[i] > missing::LAST {
                        return Err(bad_code(name, first + i, codes[i]));
                    }
                    stats.nulls += 1;
                    s.levels.push(0);
                }
                if bits.len() + s.levels.len() / 8 >= self.options.page_bytes {
                    let row = first + i - rows.start;
                    flush(s, &mut p, &mut bits, &mut acc, &mut n_bits, page_first)?;
                    page_first = row + 1;
                }
            }
        }
        if !s.levels.is_empty() || p.pages.is_empty() {
            flush(s, &mut p, &mut bits, &mut acc, &mut n_bits, page_first)?;
        }
        Ok(p.finish(stats.finish(), rows.len()))
    }

    fn texts<'a>(
        &self,
        get: &GetBytes<'a>,
        rows: Range<usize>,
        s: &mut Scratch,
        name: &str,
        utf8: bool,
    ) -> Result<Encoded> {
        let mut p = Pages::new(PhysicalType::ByteArray);
        let mut dict: Option<Dictionary<&'a [u8], &'a [u8]>> = Some(Dictionary::default());
        let mut plain = Vec::new();
        let mut plain_size = 0usize;
        let (mut min, mut max): (Option<&[u8]>, Option<&[u8]>) = (None, None);
        let mut nulls = 0u64;
        let mut page_first = 0;
        s.levels.clear();
        let check = |v: &[u8], row: usize| {
            if utf8 && std::str::from_utf8(v).is_err() {
                return Err(Error::invalid(format!(
                    "column \"{name}\": the text in row {} is not UTF-8",
                    row + 1
                )));
            }
            Ok(())
        };
        for row in rows.clone() {
            match get(row) {
                Some(v) => {
                    if u32::try_from(v.len()).is_err() {
                        return Err(Error::invalid(format!(
                            "column \"{name}\": the value in row {} is longer than Parquet allows",
                            row + 1
                        ))
                        .of(ErrorKind::TooLarge));
                    }
                    s.levels.push(1);
                    if min.is_none_or(|m| v < m) {
                        min = Some(v);
                    }
                    if max.is_none_or(|m| v > m) {
                        max = Some(v);
                    }
                    plain_size += 4 + v.len();
                    match &mut dict {
                        Some(d) => {
                            if d.add(v, v, 4 + v.len()) {
                                check(v, row)?;
                                if d.bytes >= self.options.dictionary_bytes {
                                    self.flush_texts(
                                        s,
                                        &mut p,
                                        &mut dict,
                                        &mut plain,
                                        &mut plain_size,
                                        page_first,
                                    )?;
                                    page_first = row - rows.start + 1;
                                    self.texts_dictionary(s, &mut p, &mut dict)?;
                                }
                            }
                        }
                        None => {
                            check(v, row)?;
                            plain.extend_from_slice(&(v.len() as u32).to_le_bytes());
                            plain.extend_from_slice(v);
                        }
                    }
                }
                None => {
                    nulls += 1;
                    s.levels.push(0);
                }
            }
            let size = match &dict {
                Some(d) => d.indices.len() * width(d.values.len()) as usize / 8,
                None => plain.len(),
            };
            if size + s.levels.len() / 8 >= self.options.page_bytes {
                self.flush_texts(
                    s,
                    &mut p,
                    &mut dict,
                    &mut plain,
                    &mut plain_size,
                    page_first,
                )?;
                page_first = row - rows.start + 1;
            }
        }
        if !s.levels.is_empty() || p.pages.is_empty() {
            self.flush_texts(
                s,
                &mut p,
                &mut dict,
                &mut plain,
                &mut plain_size,
                page_first,
            )?;
        }
        self.texts_dictionary(s, &mut p, &mut dict)?;
        let mut stats = Statistics {
            null_count: Some(nulls as i64),
            ..Default::default()
        };
        if let (Some(lo), Some(hi)) = (min, max) {
            // Long values would bloat the footer.
            if lo.len() <= 64 && hi.len() <= 64 {
                stats.min_value = Some(lo.to_vec());
                stats.max_value = Some(hi.to_vec());
            }
        }
        Ok(p.finish(stats, rows.len()))
    }

    fn texts_dictionary(
        &self,
        s: &mut Scratch,
        p: &mut Pages,
        dict: &mut Option<Dictionary<&[u8], &[u8]>>,
    ) -> Result<()> {
        let Some(d) = dict.take() else { return Ok(()) };
        if !p.dict.is_empty() {
            return Ok(());
        }
        let mut bytes = Vec::with_capacity(d.bytes);
        for v in &d.values {
            bytes.extend_from_slice(&(v.len() as u32).to_le_bytes());
            bytes.extend_from_slice(v);
        }
        self.dictionary_page(s, p, d.values.len(), &bytes)
    }

    fn flush_texts(
        &self,
        s: &mut Scratch,
        p: &mut Pages,
        dict: &mut Option<Dictionary<&[u8], &[u8]>>,
        plain: &mut Vec<u8>,
        plain_size: &mut usize,
        first_row: usize,
    ) -> Result<()> {
        if let Some(d) = dict {
            if p.pages.is_empty() && !d.pays(*plain_size, self.options.dictionary_bytes) {
                // Every value was checked when it entered the dictionary.
                plain.clear();
                for &i in &d.indices {
                    let v = d.values[i as usize];
                    plain.extend_from_slice(&(v.len() as u32).to_le_bytes());
                    plain.extend_from_slice(v);
                }
                *dict = None;
            } else {
                let mut values = Vec::new();
                d.encode_indices(&mut values);
                self.data_page(s, p, first_row as u64, Encoding::RleDictionary, &values)?;
                d.indices.clear();
                *plain_size = 0;
                return Ok(());
            }
        }
        let values = std::mem::take(plain);
        self.data_page(s, p, first_row as u64, Encoding::Plain, &values)?;
        *plain = values;
        plain.clear();
        *plain_size = 0;
        Ok(())
    }

    /// Every level in the dictionary, in order, in every row group: the
    /// codes are the level numbers.
    fn categorical(
        &self,
        levels: &[String],
        fill: &FillCodes,
        rows: Range<usize>,
        s: &mut Scratch,
        name: &str,
    ) -> Result<Encoded> {
        let mut p = Pages::new(PhysicalType::ByteArray);
        let w = width(levels.len());
        let mut codes = vec![0i32; BLOCK];
        let mut indices: Vec<u32> = Vec::new();
        let mut used = vec![false; levels.len()];
        let mut nulls = 0i64;
        let mut page_first = 0;
        s.levels.clear();
        let mut dict_bytes = Vec::new();
        for l in levels {
            dict_bytes.extend_from_slice(&(l.len() as u32).to_le_bytes());
            dict_bytes.extend_from_slice(l.as_bytes());
        }
        self.dictionary_page(s, &mut p, levels.len(), &dict_bytes)?;
        let flush =
            |s: &mut Scratch, p: &mut Pages, indices: &mut Vec<u32>, first: usize| -> Result<()> {
                let mut values = vec![w];
                rle::encode(indices, w, &mut values);
                self.data_page(s, p, first as u64, Encoding::RleDictionary, &values)?;
                indices.clear();
                Ok(())
            };
        for first in rows.clone().step_by(BLOCK) {
            let n = BLOCK.min(rows.end - first);
            codes[..n].fill(-1);
            fill(first, &mut codes[..n]);
            for (i, &c) in codes[..n].iter().enumerate() {
                if c < 0 {
                    nulls += 1;
                    s.levels.push(0);
                } else {
                    let c = c as usize;
                    if c >= levels.len() {
                        return Err(Error::invalid(format!(
                            "column \"{name}\": row {} has level code {c}, but there are {} levels",
                            first + i + 1,
                            levels.len()
                        )));
                    }
                    used[c] = true;
                    indices.push(c as u32);
                    s.levels.push(1);
                }
                if indices.len() * w as usize / 8 + s.levels.len() / 8 >= self.options.page_bytes {
                    flush(s, &mut p, &mut indices, page_first)?;
                    page_first = first + i - rows.start + 1;
                }
            }
        }
        if !s.levels.is_empty() || p.pages.is_empty() {
            flush(s, &mut p, &mut indices, page_first)?;
        }
        let mut stats = Statistics {
            null_count: Some(nulls),
            ..Default::default()
        };
        let used: Vec<&[u8]> = levels
            .iter()
            .zip(&used)
            .filter(|(_, &u)| u)
            .map(|(l, _)| l.as_bytes())
            .collect();
        if let (Some(lo), Some(hi)) = (used.iter().min(), used.iter().max()) {
            if lo.len() <= 64 && hi.len() <= 64 {
                stats.min_value = Some(lo.to_vec());
                stats.max_value = Some(hi.to_vec());
            }
        }
        Ok(p.finish(stats, rows.len()))
    }
}

/// A block of rows to encode, as [`Fill`] gives them.
type Block<'f, T> = dyn FnMut(usize, &mut [T], &mut [u8]) + 'f;

/// A numeric column that holds `.a` to `.z`, as doubles: each value
/// widened, and each letter its tagged NaN (plan 0018, "Missing values").
fn tag<'f, S: Number + Into<f64>>(
    fill: &'f Fill<'_, S>,
) -> impl FnMut(usize, &mut [f64], &mut [u8]) + 'f {
    tag_with(fill, S::into)
}

/// [`tag`], with each value made a double by `widen`.
fn tag_with<'f, S: Number>(
    fill: &'f Fill<'_, S>,
    widen: impl Fn(S) -> f64 + 'f,
) -> impl FnMut(usize, &mut [f64], &mut [u8]) + 'f {
    let mut narrow = [S::default(); BLOCK];
    move |first, values: &mut [f64], codes: &mut [u8]| {
        let n = values.len();
        fill(first, &mut narrow[..n], codes);
        for ((v, c), &x) in values.iter_mut().zip(codes.iter_mut()).zip(&narrow[..n]) {
            if (missing::SYSTEM + 1..=missing::LAST).contains(c) {
                *v = tagged_nan(*c);
                *c = 0;
            } else {
                *v = widen(x);
            }
        }
    }
}

/// Bits for dictionary indices: at least 1, which every reader takes.
fn width(entries: usize) -> u8 {
    rle::width_for(entries.saturating_sub(1) as u32).max(1)
}

/// A dictionary being built: distinct values in order of first
/// appearance, and the indices of the current page's values.
struct Dictionary<K, V> {
    map: HashMap<K, u32, BuildHasherDefault<Fx>>,
    values: Vec<V>,
    indices: Vec<u32>,
    /// The dictionary page's size.
    bytes: usize,
}

impl<K, V> Default for Dictionary<K, V> {
    fn default() -> Self {
        Dictionary {
            map: HashMap::default(),
            values: Vec::new(),
            indices: Vec::new(),
            bytes: 0,
        }
    }
}

impl<K: std::hash::Hash + Eq, V: Copy> Dictionary<K, V> {
    /// Add a value; returns whether it was new.
    #[inline]
    fn add(&mut self, key: K, v: V, size: usize) -> bool {
        let next = self.values.len() as u32;
        let i = *self.map.entry(key).or_insert(next);
        self.indices.push(i);
        if i == next {
            self.values.push(v);
            self.bytes += size;
            true
        } else {
            false
        }
    }

    /// Plan 0018's rule for the first page: under the size limit and
    /// smaller than 60% of the plain values it replaces.
    fn pays(&self, plain: usize, limit: usize) -> bool {
        self.bytes < limit && (self.bytes as f64) < 0.6 * plain as f64
    }

    fn encode_indices(&self, out: &mut Vec<u8>) {
        let w = width(self.values.len());
        out.push(w);
        rle::encode(&self.indices, w, out);
    }
}

/// A fast hash for dictionary keys: a folded multiply, which carries
/// every input bit into both halves of the result. (A plain multiply
/// does not: doubles such as 3086.25 have all-zero low bits, their hashes
/// then share their low bits, and the table's buckets collide.) The keys
/// are the caller's values; a hash flood only slows the write.
#[derive(Default)]
struct Fx(u64);

impl Hasher for Fx {
    #[inline]
    fn finish(&self) -> u64 {
        self.0
    }

    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        let mut chunks = bytes.chunks_exact(8);
        for c in &mut chunks {
            self.write_u64(u64::from_le_bytes(c.try_into().expect("8 bytes")));
        }
        let mut tail = [0u8; 8];
        let rest = chunks.remainder();
        tail[..rest.len()].copy_from_slice(rest);
        self.write_u64(u64::from_le_bytes(tail));
    }

    #[cfg(not(target_arch = "wasm32"))]
    #[inline]
    fn write_u64(&mut self, v: u64) {
        let m = u128::from(self.0 ^ v) * 0x9e37_79b9_7f4a_7c15_u128;
        self.0 = (m as u64) ^ ((m >> 64) as u64);
    }

    /// wasm has no 64-by-64-bit multiply to 128 bits (it is a call to a
    /// helper, as slow as the rest of the insert), so there the bits are
    /// mixed with MurmurHash3's 64-bit finalizer, which also carries every
    /// input bit into the low bits, with plain 64-bit multiplies.
    #[cfg(target_arch = "wasm32")]
    #[inline]
    fn write_u64(&mut self, v: u64) {
        let mut x = self.0 ^ v;
        x ^= x >> 33;
        x = x.wrapping_mul(0xff51_afd7_ed55_8ccd);
        x ^= x >> 33;
        x = x.wrapping_mul(0xc4ce_b9fe_1a85_ec53);
        self.0 = x ^ (x >> 33);
    }

    #[inline]
    fn write_usize(&mut self, v: usize) {
        self.write_u64(v as u64);
    }
}

/// A number type the writer encodes.
trait Number: Copy + Default + Send + std::fmt::Debug + PartialOrd {
    const WIDTH: usize;
    fn put(self, out: &mut Vec<u8>);
    /// The bits, for the dictionary: -0.0 and 0.0, and NaNs with
    /// different payloads, stay distinct.
    fn key(self) -> u64;
    fn fits(self, bits: u32) -> bool;
    fn is_nan(self) -> bool {
        false
    }
    fn is_zero(self) -> bool {
        false
    }
    fn negative_zero() -> Self {
        Self::default()
    }
}

impl Number for i32 {
    const WIDTH: usize = 4;
    fn put(self, out: &mut Vec<u8>) {
        out.extend_from_slice(&self.to_le_bytes());
    }
    fn key(self) -> u64 {
        self as u32 as u64
    }
    fn fits(self, bits: u32) -> bool {
        let lim = 1i32 << (bits - 1);
        (-lim..lim).contains(&self)
    }
}

impl Number for i64 {
    const WIDTH: usize = 8;
    fn put(self, out: &mut Vec<u8>) {
        out.extend_from_slice(&self.to_le_bytes());
    }
    fn key(self) -> u64 {
        self as u64
    }
    fn fits(self, _: u32) -> bool {
        true
    }
}

impl Number for f32 {
    const WIDTH: usize = 4;
    fn put(self, out: &mut Vec<u8>) {
        out.extend_from_slice(&self.to_le_bytes());
    }
    fn key(self) -> u64 {
        u64::from(self.to_bits())
    }
    fn fits(self, _: u32) -> bool {
        true
    }
    fn is_nan(self) -> bool {
        f32::is_nan(self)
    }
    fn is_zero(self) -> bool {
        self == 0.0
    }
    fn negative_zero() -> Self {
        -0.0
    }
}

impl Number for f64 {
    const WIDTH: usize = 8;
    fn put(self, out: &mut Vec<u8>) {
        out.extend_from_slice(&self.to_le_bytes());
    }
    fn key(self) -> u64 {
        self.to_bits()
    }
    /// For a byte or int column written as DOUBLE: a whole number in
    /// range, or a tagged NaN.
    fn fits(self, bits: u32) -> bool {
        let lim = f64::from(1u32 << (bits - 1));
        self.is_nan() || (self.fract() == 0.0 && (-lim..lim).contains(&self))
    }
    fn is_nan(self) -> bool {
        f64::is_nan(self)
    }
    fn is_zero(self) -> bool {
        self == 0.0
    }
    fn negative_zero() -> Self {
        -0.0
    }
}

/// INT32 annotated unsigned: written as its bits, compared unsigned, so
/// the statistics follow the column's unsigned order.
impl Number for u32 {
    const WIDTH: usize = 4;
    fn put(self, out: &mut Vec<u8>) {
        out.extend_from_slice(&self.to_le_bytes());
    }
    fn key(self) -> u64 {
        u64::from(self)
    }
    fn fits(self, bits: u32) -> bool {
        bits >= 32 || self < 1 << bits
    }
}

impl Number for u64 {
    const WIDTH: usize = 8;
    fn put(self, out: &mut Vec<u8>) {
        out.extend_from_slice(&self.to_le_bytes());
    }
    fn key(self) -> u64 {
        self
    }
    fn fits(self, _: u32) -> bool {
        true
    }
}

impl Number for u8 {
    const WIDTH: usize = 1;
    fn put(self, out: &mut Vec<u8>) {
        out.push(self);
    }
    fn key(self) -> u64 {
        u64::from(self)
    }
    fn fits(self, _: u32) -> bool {
        true
    }
}

/// Minimum, maximum and nulls of a chunk, by the format's rules for
/// floating point: NaN is left out, and a zero minimum is written -0.0
/// and a zero maximum +0.0.
struct Stats<T> {
    min: Option<T>,
    max: Option<T>,
    nulls: u64,
}

impl<T> Default for Stats<T> {
    fn default() -> Self {
        Stats {
            min: None,
            max: None,
            nulls: 0,
        }
    }
}

impl<T: Number> Stats<T> {
    #[inline]
    fn add(&mut self, v: T) {
        if v.is_nan() {
            return;
        }
        if self.min.is_none_or(|m| v < m) {
            self.min = Some(v);
        }
        if self.max.is_none_or(|m| v > m) {
            self.max = Some(v);
        }
    }

    fn finish(self) -> Statistics {
        let mut s = Statistics {
            null_count: Some(self.nulls as i64),
            ..Default::default()
        };
        if let (Some(mut lo), Some(mut hi)) = (self.min, self.max) {
            if lo.is_zero() {
                lo = T::negative_zero();
            }
            if hi.is_zero() {
                hi = T::default();
            }
            let (mut a, mut b) = (Vec::new(), Vec::new());
            lo.put(&mut a);
            hi.put(&mut b);
            s.min_value = Some(a);
            s.max_value = Some(b);
        }
        s
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table_of(rows: usize, columns: Vec<WriteColumn<'_>>) -> Table<'_> {
        Table {
            rows,
            columns,
            profile: Profile::default(),
        }
    }

    #[test]
    fn row_groups_are_sized_by_bytes_and_rows() {
        let opts = WriteOptions {
            row_group_bytes: 1000,
            row_group_max_rows: 30,
            ..Default::default()
        };
        let doubles = |n| {
            table_of(
                n,
                vec![WriteColumn {
                    name: "x".into(),
                    values: Values::Double(Values::by_row(|_| Some(1.0))),
                }],
            )
        };
        // 8 bytes a row: 125 rows of bytes, but at most 30 rows.
        let g = row_groups(&doubles(100), &opts);
        assert_eq!(g.len(), 4);
        assert_eq!(g[3], 90..100);
        let opts = WriteOptions {
            row_group_bytes: 1000,
            row_group_max_rows: 1000,
            ..Default::default()
        };
        assert_eq!(
            row_groups(&doubles(300), &opts),
            vec![0..125, 125..250, 250..300]
        );
        // A row wider than the limit is a row group by itself.
        let wide = table_of(
            3,
            vec![WriteColumn {
                name: "t".into(),
                values: Values::Text(Box::new(|_| Some(&[b'x'; 5000][..]))),
            }],
        );
        assert_eq!(row_groups(&wide, &opts), vec![0..1, 1..2, 2..3]);
        // Text adds its length.
        let text = table_of(
            10,
            vec![WriteColumn {
                name: "t".into(),
                values: Values::Text(Box::new(|_| Some(&[b'x'; 196][..]))),
            }],
        );
        assert_eq!(row_groups(&text, &opts), vec![0..5, 5..10]);
        // Given rows win.
        let opts = WriteOptions {
            row_group_rows: Some(4),
            ..Default::default()
        };
        assert_eq!(row_groups(&doubles(10), &opts), vec![0..4, 4..8, 8..10]);
        assert!(row_groups(&doubles(0), &opts).is_empty());
        let opts = WriteOptions {
            row_group_rows: Some(0),
            ..Default::default()
        };
        assert_eq!(row_groups(&doubles(2), &opts).len(), 2);
    }

    #[test]
    fn float_statistics_follow_the_format() {
        let mut s = Stats::<f64>::default();
        for v in [f64::NAN, 3.0, 0.0, f64::NAN] {
            s.add(v);
        }
        let st = s.finish();
        // NaN is left out; the zero minimum is written -0.0.
        assert_eq!(st.min_value, Some((-0.0f64).to_le_bytes().to_vec()));
        assert_eq!(st.max_value, Some(3.0f64.to_le_bytes().to_vec()));
        let mut s = Stats::<f64>::default();
        s.add(-0.0);
        s.add(0.0);
        let st = s.finish();
        assert_eq!(st.min_value, Some((-0.0f64).to_le_bytes().to_vec()));
        assert_eq!(st.max_value, Some(0.0f64.to_le_bytes().to_vec()));
        let mut s = Stats::<f32>::default();
        s.add(f32::NAN);
        s.nulls = 2;
        let st = s.finish();
        assert_eq!(
            (st.min_value, st.max_value, st.null_count),
            (None, None, Some(2))
        );
        let mut s = Stats::<f32>::default();
        s.add(-2.5);
        s.add(0.0);
        let st = s.finish();
        assert_eq!(st.max_value, Some(0.0f32.to_le_bytes().to_vec()));
        assert_eq!(st.min_value, Some((-2.5f32).to_le_bytes().to_vec()));
        let mut s = Stats::<i32>::default();
        for v in [5, -7, 0] {
            s.add(v);
        }
        let st = s.finish();
        assert_eq!(st.min_value, Some((-7i32).to_le_bytes().to_vec()));
        assert_eq!(st.max_value, Some(5i32.to_le_bytes().to_vec()));
    }

    #[test]
    fn hashes_of_doubles_with_zero_low_bits_spread() {
        use std::hash::BuildHasher;
        let b = BuildHasherDefault::<Fx>::default();
        let mut low = std::collections::HashSet::new();
        for k in 0..4096u32 {
            low.insert(b.hash_one((f64::from(k) / 4.0).to_bits()) & 0xfff);
        }
        // Spread over most of the 4,096 buckets, not a few.
        assert!(low.len() > 2000, "{}", low.len());
    }

    #[test]
    fn the_dictionary_rule() {
        let mut d = Dictionary::<u64, i32>::default();
        for v in [1, 2, 1, 1, 2] {
            d.add(v as u64, v, 4);
        }
        assert_eq!(d.values, vec![1, 2]);
        assert_eq!(d.indices, vec![0, 1, 0, 0, 1]);
        // 8 bytes of dictionary against 20 of plain values: 40%.
        assert!(d.pays(20, 1 << 20));
        // Against 12: 67%, more than 60%.
        assert!(!d.pays(12, 1 << 20));
        assert!(!d.pays(1000, 8));
    }
}
