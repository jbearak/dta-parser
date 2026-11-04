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
//! **What is read.** Every flat column of every type plan 0018 lists
//! ([`ColumnType`]): integers signed and unsigned, floats, booleans,
//! text (STRING, ENUM, JSON), bytes (BYTE_ARRAY and FIXED_LEN_BYTE_ARRAY,
//! UUID), DATE, TIMESTAMP (INT64, and INT96 as nanoseconds), TIME and
//! DECIMAL (as text with every digit, or the nearest double:
//! [`decimal`]); encoded PLAIN, with a dictionary, RLE,
//! DELTA_BINARY_PACKED, DELTA_LENGTH_BYTE_ARRAY, DELTA_BYTE_ARRAY or
//! BYTE_STREAM_SPLIT, in data pages v1 and v2; uncompressed, snappy,
//! gzip, zstd, lz4_raw or brotli. A text column that the file's
//! `ARROW:schema` makes a dictionary (pandas `category`, an arrow factor)
//! reads as a categorical whose levels are the rows' values
//! ([`LevelsFrom::Rows`]).
//!
//! **Not read** (each an error naming the type or codec and the column):
//! FLOAT16, INTERVAL, LZO and the Hadoop framing of LZ4. Nested columns
//! are not read at all: [`Reader::data_columns`] names them unless
//! [`ReadOptions::nested`] says to skip them.

mod arrow;
mod codec;
pub mod decimal;
mod decode;
mod encoding;
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
pub use decode::TextChunk;
pub use profile::{Categorical, ColumnProfile, Logical, Profile, Storage};
pub use read::{Element, Nested, Numbers, Output, ReadOptions, ReadReport, Reader, RowGroupInfo};
pub use schema::{ColumnInfo, ColumnType, LevelsFrom, Role};
pub use tagged::{tagged_code, tagged_nan, NA_BITS};
pub use write::{
    write, Fill, FillCodes, GetBytes, Table, Values, WriteColumn, WriteOptions, WriteReport, BLOCK,
    CREATED_BY,
};
