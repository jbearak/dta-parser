# Acknowledgements: Parquet

The Parquet reader and writer in `crates/parquet`, and the datakits'
Parquet functions built on it (`@jbearak/datakit`'s in TypeScript), are
our own code. Before
writing them we studied the Parquet specification and the open-source
Parquet libraries below: their documentation, their behaviour on files
we made, and in places their source. No code was copied from any of
them. The [judging rounds](judging/parquet-rubric.md) compared our
documentation with theirs.

The research notes record what we measured:
[R and Julia](research/parquet-r-julia.md),
[Python](research/parquet-python.md),
[TypeScript](research/parquet-typescript.md) and
[codecs](research/parquet-codecs.md).
For the `.dta` side (ReadStat, pandas' Stata reader, haven,
readstata13, pyreadstat and ReadStatTables.jl), see the README's
[Acknowledgements](../README.md#acknowledgements).

Each license below is the one in the project's own LICENSE file at the
version we studied.

## The format

- **[Apache Parquet format](https://github.com/apache/parquet-format)**
  (Apache Software Foundation, Apache-2.0; `parquet.thrift`,
  `LogicalTypes.md` and `Encodings.md`, and the
  [implementation status](https://parquet.apache.org/docs/file-format/implementationstatus/)
  page). The footer and page headers we read and write follow its
  Thrift definitions, and its logical types decide what each column
  becomes. The implementation status page told us which codecs and
  encodings the other readers handle, and so which ones we write by
  default.

## Libraries we studied

- **[arrow](https://github.com/apache/arrow) (R) 26.0.0 and pyarrow
  26.0.1** (Apache Software Foundation, Apache-2.0). Their
  `ARROW:schema` key is how other tools learn time zones, dictionary
  types and field metadata, so we write it. arrow (R) keeps haven's
  labels only through R's `serialize()`, which no other language reads;
  that is why our labels live in a JSON profile instead. Converting
  pyarrow's tables to pandas doubled the memory used, which set our
  goal of decoding straight into each language's own arrays.
- **[nanoparquet](https://github.com/r-lib/nanoparquet) 0.5.2** (Hannes
  Mühleisen, Posit Software, PBC, and others; MIT). A small,
  dependency-free reader and writer like ours. Its
  `read_parquet_info()`, `read_parquet_schema()` and
  `read_parquet_metadata()` shaped our footer-only `read_parquet_info()`;
  its open request for a row range (r-lib/nanoparquet#48) showed the
  need for `skip` and `n_max`.
- **[polars](https://github.com/pola-rs/polars) 2.1.0** (Ritchie Vink
  and contributors; MIT). Its `compression`, `compression_level` and
  `row_group_size` arguments are the names we use, and its errors on an
  unknown column name, listing the valid ones, are the model for ours.
  Plan 0027 read how its
  Parquet reader, `polars-parquet`, decodes (at commit 0925185), to see
  why it was faster than ours on some files, and took these ideas from
  it, with no code: a chunk's validity bitmap built from the level
  bytes themselves, a byte or more at a time; dictionary indices
  unpacked by functions in which the bit width is a constant; UTF-8
  checked less often than once per value (ours skips the decoder for
  ASCII); and page buffers that are not zeroed before a codec fills
  them. It also showed what we left alone: its fused unpack-and-gather
  and its branch-free placing of values among nulls. That crate began
  as Jorge Leitão's arrow2 and parquet2 and has parts ported from
  [arrow-rs](https://github.com/apache/arrow-rs) (all Apache-2.0); its
  later changes are under polars' MIT license.
- **[pandas](https://github.com/pandas-dev/pandas) 3.1.1** (AQR Capital
  Management, Lambda Foundry, the PyData Development Team and open
  source contributors; BSD-3-Clause). Its `df.attrs` in Parquet showed what
  JSON does to label codes (numbers become strings, and missing codes
  cannot be keys), so our profile stores value labels as arrays of
  pairs.
- **[fastparquet](https://github.com/dask/fastparquet) 2026.9.0**
  (Apache-2.0). It decodes pages straight into numpy arrays, and
  peaked at 524 MB reading a table that took 1,330 MB through pyarrow
  into pandas; so we decode in place. It cannot read the
  DELTA_LENGTH_BYTE_ARRAY, DELTA_BYTE_ARRAY and BYTE_STREAM_SPLIT
  encodings, and our writer does not use them.
- **[DuckDB](https://github.com/duckdb/duckdb) 2.0.0** (Stichting
  DuckDB Foundation; MIT). One of the readers our files are checked
  against, and a measure of how fast a footer can be read.
- **[Parquet2.jl](https://gitlab.com/ExpandingMan/Parquet2.jl) 0.2.37**
  (Expanding Man and contributors; MIT). It reads columns and row
  groups lazily, as our readers do. It reads `.a` to `.z` as `missing`,
  and cannot write a column with value labels: the gap the profile
  fills.
- **[Arrow.jl](https://github.com/apache/arrow-julia) 2.8.1** (Apache
  Software Foundation; Apache-2.0). How Julia tables carry field
  metadata and dictionary columns through Arrow memory; it keeps a
  categorical column but not whether it is ordered, which our profile
  keeps.
- **[ReadStatTables.jl](https://github.com/junyuan-chen/ReadStatTables.jl)
  0.4.0** (Junyuan Chen; MIT). How a Julia table holds Stata's value
  labels; it reads `.a` to `.z` as `missing`, which our files keep.
- **[hyparquet](https://github.com/hyparam/hyparquet) 1.32.0 and
  [hyparquet-writer](https://github.com/hyparam/hyparquet-writer)
  0.18.0** (MIT). hyparquet reads only a file's footer when
  it opens it, as our readers do, and returns footer statistics typed,
  which the npm package's `info` gives too.
- **[parquet-wasm](https://github.com/kylebarron/parquet-wasm) 0.9.0**
  (Kyle Barron; MIT or Apache-2.0). A Parquet library in WebAssembly,
  like the npm package's core; it hands back Arrow memory that the
  caller copies out and frees, which our synchronous typed-array
  columns avoid.

## Codecs we use

These crates are compiled into our packages; their notices ship with
them ([js/datakit/THIRD-PARTY-NOTICES](../js/datakit/THIRD-PARTY-NOTICES)
and `r/dtaparser/inst/NOTICE`). The versions
are those in `Cargo.lock`.

| codec | crate | version | license |
|---|---|---|---|
| snappy | [snap](https://github.com/BurntSushi/rust-snappy) | 1.1.2 | BSD-3-Clause |
| lz4_raw | [lz4_flex](https://github.com/pseitz/lz4_flex) | 0.11.6 | MIT |
| gzip | [miniz_oxide](https://github.com/Frommi/miniz_oxide) (with adler2 2.0.1) | 0.8.9 | MIT OR Zlib OR Apache-2.0 |
| brotli (read) | [brotli-decompressor](https://github.com/dropbox/rust-brotli-decompressor) (with alloc-no-stdlib 3.0.0 and alloc-stdlib 0.3.0) | 6.2.0 | BSD-3-Clause/MIT |
| zstd | [zstd](https://github.com/gyscos/zstd-rs), zstd-safe 7.4.0 and zstd-sys | 0.13.4 | BSD-3-Clause |
| zstd | [Zstandard](https://github.com/facebook/zstd) (C libzstd 1.5.7, compiled in by zstd-sys 2.1.2) | 1.5.7 | BSD-3-Clause, chosen from BSD or GPLv2 |

Plan 0018 chose these codecs from the measurements in
[parquet-codecs.md](research/parquet-codecs.md).
