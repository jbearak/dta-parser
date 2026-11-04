//! Read and write Parquet files that keep what a `.dta` file says
//! (plan 0018, ADR 0033).
//!
//! A file this crate writes is plain Parquet that every tool opens. What
//! Parquet cannot say (variable and value labels, display formats, notes,
//! characteristics, factor levels, time zones) goes into one JSON entry
//! of the file's key-value metadata, the dta [`Profile`], under the key
//! `dta`. Each of `.a` to `.z` is a null in its column, and its letter
//! goes into a text column named `<name>__missing`, which [`Reader`]
//! folds back in. An `ARROW:schema` entry lets pyarrow, polars and arrow
//! (R) restore categoricals and time zones.
//!
//! Like the `dta` crate, this one does no I/O of its own: a [`Reader`]
//! reads through a [`dta::Source`], and [`write`] writes to any
//! `std::io::Write`.
//!
//! **Reading.** [`Reader::open`] reads the footer. [`Reader::read`]
//! decodes a selection of columns over a window of rows straight into
//! slices the caller allocated ([`Output`]): numbers into a slice of the
//! target type, with an optional missing code per row; text one column
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
mod thrift;
mod write;

pub use codec::Compression;
pub use decode::TextChunk;
pub use profile::{Categorical, ColumnProfile, Profile};
pub use read::{Element, Nested, Numbers, Output, ReadOptions, ReadReport, Reader, RowGroupInfo};
pub use schema::{ColumnInfo, ColumnType, Role};
pub use write::{
    write, Fill, FillCodes, GetBytes, Table, Values, WriteColumn, WriteOptions, WriteReport, BLOCK,
    CREATED_BY,
};
