# Parquet and Arrow in TypeScript: what exists, and what to copy

We plan to add a Parquet reader and writer to the Rust core and expose
it through `@jbearak/dta-parser`. This note records how the existing
JavaScript Parquet libraries behave, then what our design should take
from them and what table-viewer needs.

Method, November 2026: each package was installed from npm into a
scratch directory and probed with small scripts on Node 26.12.1 on an
arm64 Mac. Fixtures were written by parquet-wasm (from an Arrow table)
and by hyparquet-writer, from made-up data. Claims about behaviour come
from those probes or from the packages' own source and types, linked
where they matter.

## Versions

| package | version | license | what it is |
|---|---|---|---|
| [hyparquet](https://github.com/hyparam/hyparquet) | 1.32.0 | MIT | Pure JS reader, no dependencies. Async. |
| [hyparquet-writer](https://github.com/hyparam/hyparquet-writer) | 0.18.0 | MIT | Pure JS writer. Sync. |
| [hyparquet-compressors](https://github.com/hyparam/hyparquet-compressors) | 1.1.3 | MIT | Extra decompressors for hyparquet. |
| [parquet-wasm](https://github.com/kylebarron/parquet-wasm) | 0.9.0 | MIT OR Apache-2.0 | Rust `parquet` and `arrow` crates (parquet-rs 60) in wasm. Reads to and writes from Arrow. |
| [apache-arrow](https://github.com/apache/arrow-js) | 21.2.0 | Apache-2.0 | Arrow in JS. IPC only, no Parquet. |
| [arrow-js-ffi](https://github.com/kylebarron/arrow-js-ffi) | 0.4.3 | MIT | Copies Arrow C Data Interface arrays out of wasm memory. Last published August 2025. |
| [@duckdb/duckdb-wasm](https://github.com/duckdb/duckdb-wasm) | 1.33.1-dev57.0 | MIT | DuckDB in wasm. Its `latest` npm tag is a dev build. |
| [@duckdb/node-api](https://github.com/duckdb/duckdb-node-neo) | 2.0.0-r.1 | MIT | Native DuckDB for Node. |
| [@dsnp/parquetjs](https://github.com/LibertyDSNP/parquetjs) | 1.9.4 | MIT | Maintained fork of parquetjs. Row at a time, async. |
| [parquetjs](https://github.com/ironSource/parquetjs) | 0.11.2 | MIT | The original. Last published 2022, unmaintained; not probed. |

## hyparquet (read)

### API

Everything that reads data is async, even when the bytes are already in
memory. The input is an `AsyncBuffer`, `{ byteLength: number;
slice(start, end?): ArrayBuffer | Promise<ArrayBuffer> }`; an
`ArrayBuffer` qualifies. `asyncBufferFromUrl({ url, byteLength?,
requestInit? })` uses HTTP range requests; `asyncBufferFromFile(name)`
opens a new `createReadStream` per slice; `cachedAsyncBuffer` adds a
cache. Entry points, typed in
[src/types.d.ts](https://github.com/hyparam/hyparquet/blob/master/src/types.d.ts):

- `parquetRead(options): Promise<void>`, with results through callbacks:
  `onComplete(rows)`, `onChunk({ columnName, columnData, rowStart,
  rowEnd })` per column chunk, `onPage` per page.
- `parquetReadObjects(options): Promise<Record<string, any>[]>`.
- `parquetQuery({ ...options, filter?, orderBy? })`: Mongo-style filters
  (`$eq`, `$gt`, `$in`, `$and`...) and one sort column.
- `parquetScan(options)`: a prepared scan whose `readColumn({ column,
  rowStart, rowEnd })` reads one column for one row range.
- `parquetMetadata(arrayBuffer)` (sync, needs the footer in memory),
  `parquetMetadataAsync(asyncBuffer, { initialFetchSize = 512 KiB })`,
  `parquetSchema(metadata)`.

Read options: `columns?: string[]` (default all), `rowStart?`
(inclusive), `rowEnd?` (exclusive), `rowFormat: 'array' | 'object'`,
`compressors?`, `utf8 = true` (decode unannotated `BYTE_ARRAY` as text),
`parsers?` (override how dates, timestamps, strings and JSON become
values), `includeRowIndex = false`, `useOffsetIndex = false`,
`usePageIndex = false`, `useBloomFilters = false`, `filter?`,
`metadata?` (reuse a parsed footer). Row groups are chosen only through
the row range. `onChunk` data "may contain data outside the requested
range", so the caller slices. Without the offset index (on by default
only in `parquetScan`), a row window decodes every column chunk it
touches in full.

The planned 2.0 ([#121](https://github.com/hyparam/hyparquet/issues/121))
drops array rows and the sync `parquetMetadata` export.

### What values come back

| Parquet | hyparquet value |
|---|---|
| INT32, FLOAT, DOUBLE | `number`; `NaN` survives |
| INT64 | `bigint`, always, even for small values |
| DATE | `Date` at UTC midnight |
| TIMESTAMP millis/micros/nanos | `Date`, truncated to milliseconds; `isAdjustedToUTC` ignored |
| DECIMAL | `number` (unscaled / 10^scale), lossy past 2^53 |
| STRING, and unannotated BYTE_ARRAY when `utf8` | `string` |
| BYTE_ARRAY with `utf8: false` | `Uint8Array` |
| dictionary-encoded | dereferenced; codes never visible |
| null | `null` |

`onChunk` gives a typed array only for REQUIRED columns. An OPTIONAL
column comes back as a plain `Array` even with no nulls, and Arrow-based
writers mark every column OPTIONAL: a 2-million-row double column from
such a file came back as an `Array`. Typed arrays for nullable columns
are [#157](https://github.com/hyparam/hyparquet/issues/157), open. The
lossy timestamps are [#99](https://github.com/hyparam/hyparquet/issues/99);
the maintainer's answer is the `parsers` option, not a lossless default.

### Codecs, size, memory, errors

Codecs: uncompressed and snappy built in; gzip, brotli, zstd, lz4 (with
Hadoop framing) and lz4_raw with hyparquet-compressors. hyparquet's
README also ticks LZO, but the compressors'
[`compressors.js`](https://github.com/hyparam/hyparquet-compressors/blob/main/src/compressors.js)
has none. Encodings: PLAIN, PLAIN_DICTIONARY, RLE_DICTIONARY, RLE,
BIT_PACKED, all three DELTA_*, BYTE_STREAM_SPLIT, ALP; data pages v1 and
v2.

Bundled with esbuild: the reader is 59 KB minified (18 KB gzip); the
compressors add 115 KB (75 KB gzip). ESM only, with `browser` and Node
export conditions; runs in browsers, Node and workers.

Measured on a 2,000,000-row file with four columns (int32 id, double,
4-level string, free text), 22 MB, zstd, 100,000-row groups, written by
parquet-wasm. Process baseline 71 MB:

| read | time | peak RSS |
|---|---|---|
| metadata only | 3 ms | 73 MB |
| 1,000 rows at row 1,500,000, all columns | 33 ms | 95 MB |
| one double column, whole, `onChunk` only | 34 ms | 104 MB |
| whole file as row objects | 704 ms | 688 MB |

Windows and single columns stay cheap; whole-file row objects cost
about 300 bytes a row. The maintainer's benchmark suite is
[hyparquet-perf](https://github.com/hyparam/hyparquet-perf).

Errors are plain `Error`s with decoder messages: `parquet file invalid
(footer != PAR1)`, `thrift unhandled type: 15`, `parquet unsupported
page type: undefined`. An empty input throws a bare `RangeError: Offset
is outside the bounds of the DataView`.

## hyparquet-writer

Sync. `parquetWriteBuffer({ columnData, ...options }): ArrayBuffer`;
`parquetWriteFile({ filename, columnData, ... })` (Node entry; flushes
1 MB chunks with `fs.writeFileSync`); `parquetWrite({ writer, ... })`
for any `Writer`; `parquetWriteRows({ rows, columns, ... })` for row
objects, including async iterables; and `new ParquetWriter({ writer,
schema, ... })` with repeated `.write({ columnData, rowGroupSize })`
then `.finish()` for writing a row group at a time
([types](https://github.com/hyparam/hyparquet-writer/blob/master/src/types.d.ts)).

A column is `{ name, data, type?, nullable?, encoding?, codec?,
statistics?, columnIndex?, offsetIndex?, bloomFilter? }`. `type` is a
"basic type" (`BOOLEAN`, `INT32`, `INT64`, `FLOAT`, `DOUBLE`,
`BYTE_ARRAY`, `STRING`, `JSON`, `TIMESTAMP`, `UUID`, `FLOAT16`,
`GEOMETRY`, `GEOGRAPHY`, `VARIANT`, `FILE`). DATE, DECIMAL, and narrow or
unsigned integers need a raw Parquet `schema`, or
`schemaFromColumnData({ columnData, schemaOverrides })`.

| option | default |
|---|---|
| `codec` | `'SNAPPY'`; other codecs need your own compressor in `compressors` |
| `rowGroupSize` | `[1000, 100000]`: 1,000 rows first, then 100,000, "optimized for fast previews" |
| `pageSize` | 1,048,576 bytes |
| `statistics` | `true` (min, max, null count, NaN count) |
| `statisticsTruncateLength` | 16 bytes for string min/max |
| `dictionarySize` | uncapped; a dictionary is kept if it at least halves the size |
| `offsetIndex` / `columnIndex` / `bloomFilter` | `true` / `false` / `false`, per column |
| `kvMetadata` | none; `{ key, value }[]` |
| `createdBy` | `'hyparquet'` |

It always writes data page v2 and file version 2
([datapage.js](https://github.com/hyparam/hyparquet-writer/blob/master/src/datapage.js)).
It emits PLAIN, RLE_DICTIONARY when a dictionary pays, RLE for booleans,
and DELTA_* or BYTE_STREAM_SPLIT only when asked. Without `type`, it
guessed: integers to INT32, any fraction to DOUBLE, `bigint` to INT64,
`Date` to INT64 `TIMESTAMP_MILLIS` (a legacy annotation that parquet-wasm
reads as UTC), strings to UTF8. A guessed column is REQUIRED unless it
holds a null; a typed one is OPTIONAL unless `nullable: false`. Nulls
are `null` or `undefined`. The README warns that zero rows throws.

Bundled: 64 KB minified, 20 KB gzip. It wrote the 2-million-row file in
1.2 s, 31 MB with snappy; parquet-wasm took 2.4 s for 22 MB with zstd.

Past bugs worth learning from:
[#60](https://github.com/hyparam/hyparquet-writer/issues/60) (open):
the INTEGER logical type's `bitWidth` went out as a thrift i32, not i8,
and DuckDB rejects the file.
[#35](https://github.com/hyparam/hyparquet-writer/issues/35) (closed):
dictionaries fell back to PLAIN when distinct values outgrew a page,
making long low-cardinality string columns 20 to 100 times larger.

## parquet-wasm

### API

`parquet-wasm/node` loads synchronously with `require`. The ESM entry
needs `await init()` or `initSync(bytes)` first, and otherwise fails with
`TypeError: Cannot read properties of undefined`.

Sync, whole file in memory:

- `readParquet(bytes: Uint8Array, options?: { batchSize?, rowGroups?,
  limit?, offset?, columns? }): Table`. `batchSize` defaults to 1,024
  rows, so 2 million rows came back as 1,954 record batches.
- `readMetadata(bytes)` (the footer alone is enough), `readSchema(bytes)`.
- `writeParquet(table: Table, props?: WriterProperties): Uint8Array`.

Async: `ParquetFile.fromUrl(url)` or `.fromFile(blob)`, then
`.metadata()`, `.schema()`, `.read(options): Promise<Table>`,
`.stream(options)` (with `concurrency`); `readParquetStream(url)`;
`transformParquetStream(stream, props)` to write.

The `Table` lives in wasm memory. You copy it out with
`table.intoIPCStream()` and apache-arrow's `tableFromIPC`, or with
`table.intoFFI()` and arrow-js-ffi's `parseTable(wasmMemory().buffer,
...)`, and free objects with `.free()` or `using`. Some functions free
their arguments, and using an object afterwards throws.

The sync `readParquet` in 0.9.0 ignores `columns`. Asking for one of
four columns returned all four, at the memory of a full read. Its
[src/reader.rs](https://github.com/kylebarron/parquet-wasm/blob/v0.9.0/src/reader.rs)
applies batch size, row groups, limit and offset but not the
projection; the async path's
[`apply_to_builder`](https://github.com/kylebarron/parquet-wasm/blob/v0.9.0/src/read_options.rs)
does apply it. `main` is unchanged as of 4 November 2026. Not reported
upstream; per AGENTS.md that needs the user's approval.

### Values

Arrow types, with apache-arrow 21.2.0 choosing the JS value:

| Parquet | Arrow | `vector.get(i)` | `toArray()` |
|---|---|---|---|
| INT32 | Int32 | `number` | `Int32Array` |
| INT64 | Int64 | `bigint` | `BigInt64Array` |
| DOUBLE | Float64 | `number` | `Float64Array` (nulls read as 0) |
| STRING | Utf8 | `string` | `Array` |
| DATE | Date32 | `number` (ms since 1970), not a `Date` | `Array` |
| TIMESTAMP micros | Timestamp | `number` (ms) | `BigInt64Array` |
| DECIMAL(12,2) | Decimal | unscaled integer as a string (`"125"` for 1.25) | `Uint32Array` of words |
| dictionary written from Arrow | Dictionary<Int32, Utf8> | the label | `Array` |
| null | | `null` | validity bitmap |

A dictionary comes back as a dictionary only because the writer stored
the Arrow schema in the `ARROW:schema` key-value entry. Its codes are
assigned per column chunk, so they cannot carry meaning such as Stata
value-label codes.

### Writer, codecs, size, memory, errors

Properties come from `new WriterPropertiesBuilder()...build()`, with
parquet-rs defaults. Observed: no compression, dictionary encoding on,
page-level statistics, data page v1, the Arrow schema in
`ARROW:schema`. Setters: `setCompression`, `setColumnCompression`,
`setDictionaryEnabled`, `setDictionaryPageSizeLimit`, `setEncoding`,
`setColumnEncoding`, `setStatisticsEnabled(None | Chunk | Page)`,
`setMaxRowGroupSize` (rows), `setMaxRowGroupBytes`,
`setDataPageSizeLimit`, `setWriterVersion(V1 | V2)`,
`setKeyValueMetadata(Map)`, `setCreatedBy`,
`setContentDefinedChunking`. Codecs, read and write: uncompressed,
snappy, gzip, brotli, zstd, lz4_raw (not the deprecated LZ4, not LZO).

The wasm is 5.25 MB (1.66 MB gzip). The README gives 1.2 MB brotli for
the full build and 456 KB for a read-only build without codecs, chosen
by cargo features. That is roughly what the Rust `parquet` crate's
reader would add to our module.

| read, same 2M-row file | time | peak RSS |
|---|---|---|
| metadata (`readMetadata`, after reading the file into memory) | 5 ms | 119 MB |
| 1,000 rows at 1,500,000 (`offset`, `limit`) | 59 ms | 145 MB |
| whole file, IPC copy to apache-arrow | 225 ms | 570 MB |
| whole file, FFI copy | 345 ms | 1,591 MB |
| whole file, FFI copy, hyparquet-written file | 159 ms | 419 MB |

The sync API copies the whole file into wasm memory, decodes it there
and copies the result out, so peak memory is several times the decoded
size. The README says FFI halves memory; that held for one file and not
the other (the 1.6 GB run is probably wasm memory growth; not
investigated). Older releases trapped with `RuntimeError: unreachable`
on large reads ([#577](https://github.com/kylebarron/parquet-wasm/issues/577),
closed).

Errors are `Error` with the Rust message (`Parquet error: Invalid
Parquet file. Corrupt footer`, `Required field type_ is missing`), and
no codes. It refused a file whose `ARROW:schema` entry we had damaged,
though the Parquet data was intact; hyparquet and parquetjs read it.

## apache-arrow and arrow-js-ffi

apache-arrow is how parquet-wasm and DuckDB-wasm hand data to JS. Its
IPC reader plus `tableFromArrays` bundles to 223 KB minified (51 KB
gzip); arrow-js-ffi adds about 10 KB. Its value conversions have open
problems for dates far from 1970, which survey data has
([docs](https://arrow.apache.org/docs/js/)):

| issue | problem |
|---|---|
| [#422](https://github.com/apache/arrow-js/issues/422) | Date32 `get` silently returns wrong values outside about 1685 to 2255 |
| [#421](https://github.com/apache/arrow-js/issues/421) | Timestamp `get` throws for valid values beyond the safe-integer range |
| [#83](https://github.com/apache/arrow-js/issues/83) | pre-1970 timestamps built from JS are off by a fixed amount |
| [#53](https://github.com/apache/arrow-js/issues/53) | Date round-trips changed in 16 (`get` returns numbers) |
| [#100](https://github.com/apache/arrow-js/issues/100), [#81](https://github.com/apache/arrow-js/issues/81) | decimals are hard to use |
| [#525](https://github.com/apache/arrow-js/issues/525) | opened 4 November 2026: loading apache-arrow is reported to slow every `Array.prototype.concat` in the process about 100 times, which would hit a shared VS Code extension host |

## DuckDB (briefly)

[@duckdb/node-api](https://github.com/duckdb/duckdb-node-neo) is native
(the darwin-arm64 binding is 66 MB unpacked) and Promise-based. It reads
Parquet through SQL: `read_parquet('f.parquet')`, `LIMIT`/`OFFSET`,
`parquet_metadata()`, `parquet_schema()`, `parquet_kv_metadata()`.
Results come as rows or columns (`getRows()`, `getColumns()`, plus `JS`
and `Json` variants); BIGINT is `bigint`, and DATE, TIMESTAMP and
DECIMAL are value objects unless converted. Writing is `COPY ... TO
'f.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE n,
KV_METADATA {...})`, snappy by default
([DuckDB Parquet docs](https://duckdb.org/docs/2.0/data/parquet/overview.html)).

[@duckdb/duckdb-wasm](https://github.com/duckdb/duckdb-wasm) is 149 MB
unpacked, with three wasm builds of 36 to 41 MB. Browsers run it in a
Web Worker, async; the `duckdb-node-blocking` build gives a sync
connection. In Node, the first `read_parquet` tried to download the
Parquet extension from `extensions.duckdb.org` and failed in our
sandbox with `Extension Autoloading Error`. An offline VS Code extension
cannot depend on that. DuckDB answers questions our library should not
(SQL, joins, sorts that spill to disk), and is far too large to embed
for reading one file.

## @dsnp/parquetjs

All async, row at a time. `ParquetReader.openFile(path)`, `openBuffer`,
`openUrl`, `openS3`; `reader.getCursor(columns?)`, then `await
cursor.next()` until null; `getRowCount()` (the footer's thrift Int64
object, not a number); `getSchema()`; `getMetadata()`; `close()`. No row
ranges: reaching row 1,500,000 means stepping past every earlier row.
Writing: `new ParquetSchema({ col: { type: 'UTF8', optional?,
compression?, encoding? } })`, `await ParquetWriter.openFile(schema,
path, { rowGroupSize = 4096 rows, pageSize = 8192 rows, useDataPageV2 =
true, bloomFilters? })`, `await writer.appendRow({...})`,
`writer.setMetadata(key, value)`, `await writer.close()`; compression
defaults to none, set per column.

INT64 came back as `bigint`, dates and timestamps as `Date`, a
fixed-length decimal as a raw `Buffer`, nulls as `null`. Codecs:
uncompressed, gzip, snappy, brotli, zstd. Encodings: PLAIN,
PLAIN_DICTIONARY, RLE, BYTE_STREAM_SPLIT, no DELTA_*. It needs Node
20.20.2+, depends on `@aws-sdk/client-s3` (17 packages) whether or not
you use S3, and its browser bundle is 832 KB (223 KB gzip) plus a 1 MB
brotli wasm. Errors are generic: `not valid parquet file`, `read
failed`, `TProtocolException: Unknown type: 15`.

## Codecs at a glance

| | read | write (default first) |
|---|---|---|
| hyparquet | none, snappy; gzip, brotli, zstd, lz4, lz4_raw with compressors | |
| hyparquet-writer | | snappy, none; others with your own compressor |
| parquet-wasm | none, snappy, gzip, brotli, zstd, lz4_raw | none, then the same set |
| @dsnp/parquetjs | none, gzip, snappy, brotli, zstd | none, then the same set |
| DuckDB | all common codecs | snappy, zstd, lz4_raw, brotli, gzip, none |

## Documentation quality

Does the README or official site show a working example?

| topic | hyparquet (+writer) | parquet-wasm | @dsnp/parquetjs | DuckDB node-api |
|---|---|---|---|---|
| install | no `npm install` line in either README | yes | yes | yes |
| whole file | yes | yes | yes (cursor loop) | yes (SQL) |
| some columns | yes | documented; ignored by the sync reader | yes | yes |
| some rows | yes (`rowStart`/`rowEnd`) | only in generated docs (`offset`/`limit`) | not possible | yes |
| metadata | yes | yes | `getMetadata` only | yes |
| write | yes, good type table | one example, via Arrow | yes | yes (`COPY`) |
| dates | reader README silent (`parsers` only in types); writer shows `Date` | via Arrow only | schema example | yes |
| missing values | reader README silent; writer has `nullable` | via Arrow only | "Optional fields" section | yes |

hyparquet's types file is its real documentation, and it is good, but
the README skips the two things a data user hits first: what a date
comes back as and what a null is. parquet-wasm documents memory
ownership well and leaves the read options to generated docs.

## Lessons for our design

### API ideas to adopt

1. Keep our shape: synchronous, columnar, typed arrays with a separate
   missing mask (ADR 0002). Every library here is either async
   (hyparquet, parquetjs, DuckDB) or hands back Arrow objects in wasm
   memory that must be copied out and freed (parquet-wasm). hyparquet's
   most-asked change, typed arrays for nullable columns
   ([#157](https://github.com/hyparam/hyparquet/issues/157)), is what our
   `NumberColumn` already is.
2. Give Parquet the same reader as `.dta`: `openParquetFile(path | fd)`
   and `openParquet(bytes)` returning `info`, `variables`,
   `readColumns(columns, { start, count })`, `readRows`, `readRowsAt`,
   `close()` and `using`. table-viewer could then share one data source.
3. Read only the footer on open. hyparquet's rule (fetch the last 512
   KiB, fetch more if the footer is longer) means one or two
   `fs.readSync` calls.
4. Rows as `start`/`count` and columns by name or index, as now. Also
   expose row-group boundaries in `info`, so callers can align pages.
5. Expose footer statistics per row group (min, max, null count, and
   whether min and max are exact). hyparquet returns them typed;
   parquet-wasm does not yet
   ([#863](https://github.com/kylebarron/parquet-wasm/issues/863)). A
   viewer can then show a column's range without scanning it.
6. Return dates and timestamps losslessly, as numbers with unit, epoch
   and time zone in the column metadata, as we do for Stata dates, and
   let `formatValue` render them. Then nobody needs a `parsers` hook.
7. Writer defaults that every reader handles: one documented codec
   (zstd or snappy), statistics on, dictionaries for strings, offset
   index on, data page v1 unless asked (the parquetjs README notes
   parquet-cpp's trouble with v2), INT8/INT16/INT32 logical types for
   byte/int/long. hyparquet-writer's small first row group
   (`[1000, 100000]`) makes first pages fast; worth copying.
8. Put what Parquet cannot say in key-value metadata: variable and value
   labels, display formats, notes, and which nulls are `.a` to `.z`. Our
   0.x `ArrowBuffer` already carried a "dtatools profile" for Arrow files
   that table-viewer read; Parquet should carry the same profile,
   versioned, so a `.dta` file written as Parquet reads back as the same
   dataset.
9. Errors with a name and a reason. Every library here throws plain
   `Error`s with decoder text, and hyparquet a bare `RangeError` on an
   empty file. Ours should say what is wrong and where (column, row
   group, page), and tell damage apart from an unsupported feature such
   as encryption or LZO.

### Pitfalls, with evidence

- Lossy defaults. hyparquet turns timestamps into millisecond `Date`s
  ([#99](https://github.com/hyparam/hyparquet/issues/99)) and decimals
  into floats; apache-arrow's date `get` loses precision or throws far
  from 1970 ([#422](https://github.com/apache/arrow-js/issues/422),
  [#421](https://github.com/apache/arrow-js/issues/421)). Stata dates
  count from 1960 and survey data reaches back further, so check ranges
  before any epoch-millisecond arithmetic in doubles.
- INT64. Every library returns `bigint`, always. Stata has no 64-bit
  integer, so we need a rule: `Float64Array` when every value is within
  ±2^53 (known from footer statistics or the decoded values), otherwise
  a `BigInt64Array` column of a new kind. table-viewer requires every
  digit.
- Dictionary codes are not data. They are per column chunk. Value-label
  codes must be an integer column plus a label table in metadata.
- Unannotated BYTE_ARRAY: hyparquet decodes it as UTF-8 by default.
  Write STRING for text, leave binary strL unannotated, and on read treat
  unannotated bytes that are not valid UTF-8 as binary.
- The projection must reach the decoder. parquet-wasm's sync reader
  ignores `columns` unnoticed. A test that a one-column read touches
  only that column's byte ranges (count the `readSync` calls) catches it.
- No whole-file copies into wasm. parquet-wasm's peak was 5 to 6 times
  the decoded size. Pass only the needed column-chunk bytes into the
  module, as the `.dta` reader passes row windows, and keep the 64 MiB
  per-call output cap.
- Thrift details. An i32 where i8 belongs
  ([hyparquet-writer#60](https://github.com/hyparam/hyparquet-writer/issues/60))
  made files DuckDB rejects. Check our writer's output with pyarrow,
  DuckDB and hyparquet in the compat tests.
- Damaged optional metadata. parquet-wasm refuses a file with a corrupt
  `ARROW:schema`; hyparquet ignores it. Read our own profile key
  strictly, but treat a damaged foreign key as a warning.

### What table-viewer needs from a Parquet reader

From its `.dta` sources (`src/data-source/file-dta-source.ts`,
`dta-source.ts`), its `DataSource` interface (`interface.ts`), and the
Arrow source added in 88735d4 and removed unreleased in cfc1430:

- Synchronous row windows over a column projection. `read_rows` and
  `read_columns` are sync in its interface. Today it reaches into the
  0.x `DtaFile`'s private `_fd`, `_metadata` and `_decode_rows_range`
  because the public row read returned a Promise. The Parquet API must
  be sync from the start.
- Arbitrary rows in a given order, repeats allowed
  (`read_rows_indexed`), for sorted and filtered views. For Parquet:
  group the rows by row group and page, decode each page once, return
  rows in the caller's order. That is `readRowsAt`.
- Whole-column scans in small batches, cancellable between batches.
  Sorting reads one key column at a time; histograms and filters read
  1,000 rows a batch and yield to the event loop. Consecutive ranges in
  one row group must not re-decompress the chunk each time, so the
  reader needs a small cache of decoded pages per column, with a byte
  budget.
- Memory bounds checked before allocating. It caps file-backed `.dta`
  at 2,000,000 rows and 10,000 columns, 64 MiB of metadata, 16 MiB and
  65,536 entries of value labels, and 1 MiB per observation; the Arrow
  source added a 16 MiB page cache and a 32 MiB budget for dictionaries
  and labels. Its Arrow notes record what went wrong: dictionaries were
  decoded before their size was known, so the budget could not bound
  peak memory, and whole compressed buffers were decompressed
  synchronously, stalling scrolling. Our reader should report, from the
  footer and before decoding, row and column counts, per-chunk
  compressed and uncompressed sizes, dictionary page sizes, and the
  size of the key-value metadata.
- Exact value identity. 64-bit integers keep every digit; null, NaN,
  empty string and Stata missing codes stay distinct; timestamps keep
  fractional seconds, unit, epoch and time zone (its Arrow source built
  comparison keys from all four); dictionary columns keep codes and
  labels.
- Value labels and a hint that a column holds category codes, for its
  filters.
- Reading through a file descriptor it holds, so it can hash the bytes
  and know the file it reads is the one it checked. `openDtaFile(fd)`
  exists; `openParquetFile(fd)` should too.
- Footer min, max and null counts, flagged as possibly absent or
  inexact, would let it size histogram bins without a first pass.

## Licenses

Our package is GPL-3.0-only. Everything below is compatible with
GPL-3.0; Apache-2.0 is compatible with GPL-3.0 (not with GPL-2.0).
Nothing needs flagging.

| package | license | notable dependencies |
|---|---|---|
| hyparquet | MIT | none |
| hyparquet-writer | MIT | hyparquet (MIT) |
| hyparquet-compressors | MIT | hysnappy (MIT), fzstd (MIT) |
| parquet-wasm | MIT OR Apache-2.0 | Rust `parquet`, `arrow` (Apache-2.0) |
| apache-arrow | Apache-2.0 | flatbuffers (Apache-2.0), tslib (0BSD), json-with-bigint (MIT) |
| arrow-js-ffi | MIT | apache-arrow (peer) |
| @duckdb/duckdb-wasm | MIT | apache-arrow (Apache-2.0), qs (BSD-3-Clause) |
| @duckdb/node-api | MIT | native DuckDB (MIT) |
| @dsnp/parquetjs | MIT | thrift, bson, long, brotli-wasm, @aws-sdk/client-s3 (Apache-2.0); int53 (BSD-3-Clause) |
| parquetjs | MIT | thrift 0.11 (Apache-2.0), brotli (MIT) |

If the Rust core uses the `parquet` crate, ship its Apache-2.0 notice
with the package. Code copied from an MIT project keeps its copyright
notice.
