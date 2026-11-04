//! Read and write Parquet files that keep what a `.dta` file says
//! (plan 0018, ADR 0033).
//!
//! A file this crate writes is plain Parquet that every tool opens. What
//! Parquet cannot say (variable and value labels, display formats, notes,
//! characteristics, factor levels, time zones) goes into one JSON entry
//! of the file's key-value metadata, the dta [`Profile`], under the key
//! `dta`. `.` is a null; `.a` to `.z` are tagged NaNs ([`tagged_nan`]) in
//! DOUBLE columns, so a numeric column that holds any is written as
//! DOUBLE, with its storage type in the profile ([`Storage`]), and so is
//! a date or timestamp column, as days or seconds since 1970
//! ([`Logical`]). An `ARROW:schema` entry lets pyarrow, polars and arrow
//! (R) restore categoricals and time zones.
//!
//! Like the `dta` crate, this one does no I/O of its own: a [`Reader`]
//! reads through a [`dta::Source`], and [`write`] writes to any
//! `std::io::Write`.
//!
//! **Reading.** [`Reader::open`] reads the footer. [`Reader::read`]
//! decodes a selection of columns over a window of rows straight into
//! slices the caller allocated ([`Output`]): numbers into a slice of the
//! target type, with an optional missing code per row (`.a` to `.z` from
//! the tagged NaNs of DOUBLE columns); text one column
//! chunk at a time as a [`TextChunk`], kept as dictionary and codes when
//! the file has them. Whole row groups outside the window are skipped,
//! and within a chunk only the pages that hold the window are
//! decompressed (found through the offset index, or by walking page
//! headers). Column chunks are decoded on worker threads for large reads
//! ([`dta::threads`]).
//!
//! **Writing.** [`write`] takes a [`Table`] of [`WriteColumn`]s, each
//! filled a block of rows at a time, and writes row group by row group,
//! encoding a row group's columns on worker threads.
//!
//! **Not read yet** (each an error naming the type, encoding or codec and
//! the column): DELTA and BYTE_STREAM_SPLIT encodings, brotli, INT96,
//! TIME, DECIMAL, unsigned integers, FIXED_LEN_BYTE_ARRAY and FLOAT16.
//! Nested columns are not read at all: [`Reader::data_columns`] names
//! them unless [`ReadOptions::nested`] says to skip them.

mod arrow;
mod codec;
mod decode;
pub mod format;
mod json;
pub mod profile;
mod read;
mod rle;
mod schema;
mod tagged;
mod thrift;
mod write;

pub use codec::Compression;

// Default thread counts (plan 0018, "Threads"), set by plan 0007's
// rule: each thread added must make the task at least half a thread's
// work faster, and CPU time must stay within 1.15 times one thread's.
// They are used where the caller asks for 0 threads and `DTA_THREADS`
// is not set ([`dta::threads`]), never past the machine's cores (half
// of them on x86). Measured on snappy files at 1 to 16 threads; the
// numbers are in bench/RESULTS.md, under Parquet.

/// The fewest threads a large read uses: survey files of up to about
/// 250 MiB decoded failed the rule at three.
pub const READ_THREADS: usize = 2;
/// Past that, one read thread per this many decoded bytes: long.dta
/// (777 MiB) passed the rule at four threads and failed at six.
pub const READ_BYTES_PER_THREAD: u64 = 176 << 20;
/// The most read threads: wide.dta (4.6 GB) passed at eight and failed
/// at twelve.
pub const READ_THREADS_MOST: usize = 8;

/// The fewest threads a large write uses: survey files and long.dta
/// failed the rule at three.
pub const WRITE_THREADS: usize = 2;
/// Past that, one write thread per this many bytes of values.
pub const WRITE_BYTES_PER_THREAD: u64 = 256 << 20;
/// The most write threads: wide.dta passed at six and failed at eight.
pub const WRITE_THREADS_MOST: usize = 6;
pub use decode::TextChunk;
pub use profile::{Categorical, ColumnProfile, Logical, Profile, Storage};
pub use read::{Element, Nested, Numbers, Output, ReadOptions, ReadReport, Reader, RowGroupInfo};
pub use schema::{ColumnInfo, ColumnType, Role};
pub use tagged::{tagged_code, tagged_nan, NA_BITS};
pub use write::{
    write, Fill, FillCodes, GetBytes, Table, Values, WriteColumn, WriteOptions, WriteReport, BLOCK,
    CREATED_BY,
};
