# Arrow IPC as the dtatools native format

Research date: 2026-08-28. Design decisions confirmed: 2026-08-29.

## Conclusion

Arrow IPC is the physical foundation of the dtatools native format. Its
purpose is fast local caching and dtatools-to-dtatools interchange of large
survey files, where full-table and projected read and write time is the first
priority and file size is the second. Generic Arrow readability is
best-effort, not a design goal; Parquet remains the deferred candidate for a
compatibility-oriented interchange format (see
[parquet-interchange-format.md](./parquet-interchange-format.md) and the
planned `read_parquet()`/`save_parquet()` functions).

Arrow IPC's serialized buffers closely match Arrow's in-memory columnar
layout. An IPC reader can reconstruct Arrow arrays from record-batch metadata
without decoding Parquet pages or copying the underlying uncompressed buffers.
IPC files support random access to record batches through a footer and can be
memory-mapped.

The implementation uses Rust's official `arrow-ipc` crate directly. It does
not route dtatools files through the Arrow R package. This keeps Arrow
decoding beside the existing Rust DTA parser and lets the R adapter construct
dtatools compact ALTREP columns without first creating ordinary R vectors.
Arrow R remains useful as an independent compatibility reader and benchmark
comparison.

Arrow IPC alone is not a lossless Stata or R interchange format. Exact
semantics are the contract between dtatools readers and writers, carried by a
versioned `dtatools:*` metadata profile: value and variable labels, display
formats, declared storage types, dataset label, notes, and the raw-storage
missing-value encoding. The product claim is:

> A versioned, durable dtatools format built on Arrow IPC, with exact dtatools
> round trips, projected reads, and per-buffer integrity checksums.

No speed claim is justified before a like-for-like benchmark against DTA,
uncompressed IPC, LZ4 IPC, and Parquet. Arrow IPC is the recommendation
because its design avoids most storage-layer encoding and decoding work. The
benchmark must still include conversion costs between R vectors and Arrow
arrays and filesystem caching. Arrow R comparisons must distinguish an Arrow
table result from a materialized R data frame.

## Decisions

Settled 2026-08-29; the sections below give the reasoning.

1. **Purpose**: fast local cache and dtatools-to-dtatools interchange.
   Generic-Arrow readability is best-effort. DTA remains the cross-tool
   compatibility format.
2. **Naming**: R and Rust package `dtatools`, metadata namespace `dtatools:*`,
   R functions `read_arrow()` and `save_arrow()`, extension `.arrow`.
3. **Missing values**: raw Stata storage. Profiled numeric columns carry no
   Arrow validity bitmaps; system and tagged missing codes are stored as
   Stata sentinel integers and NaN payloads. A generic-reader compatibility
   representation is deferred to
   [issue #82](https://github.com/jbearak/dta-parser/issues/82).
4. **Profile safety**: a newer profile version or malformed profile metadata
   consumed by the read is a hard error, with an explicit escape hatch to read
   the raw storage arrays. A projection validates the dataset and selected
   field documents, and discards unselected field documents without parsing
   them. A full read validates every field. Plain Arrow files never acquire
   Stata semantics.
5. **Projection is a v1 requirement**: `read_arrow()` mirrors `read_dta()`'s
   `col_select`, `skip`, and `n_max`, and projected reads must cost I/O
   proportional to the selected columns' buffers.
6. **Bounded record batches** with a benchmark-pinned default rows-per-batch.
   The prototype writes 65,536 rows per batch; the value is provisional until
   the read/write benchmarks pin it.
7. **Compression default is `"uncompressed"`**, fixed; `"lz4"` and `"zstd"`
   are explicit options; readers auto-detect.
8. **Durability**: a long-horizon stability promise for frozen profile
   versions and per-buffer xxHash64 checksums, verified on read by default.
   See [ADR 0010](../adr/0010-promise-stability-for-frozen-arrow-profiles.md).
9. **Out of scope for v1**: the IPC stream variant, in-place append
   (permanently — the footer sits at the end of the file), zero-copy
   memory-mapped reads (deferred optimization), and nested data types as
   user-facing columns.

## What Arrow IPC standardizes

The Arrow columnar format defines language-independent layouts for booleans,
signed and unsigned integers of several widths, floating-point values, binary
and UTF-8 strings, dates, timestamps, dictionaries, structs, lists, and other
types. Arrays separate nullness from values using a validity bitmap. `Inf`,
`-Inf`, and a non-null `NaN` therefore have natural representations distinct
from null. [The Arrow columnar format](https://arrow.apache.org/docs/format/Columnar.html)
is the authoritative specification.

The IPC protocol serializes a schema followed by dictionary and record batches.
Each record batch contains FlatBuffers metadata describing the location and
size of its buffers, followed by the aligned buffers themselves. A reader can
reconstruct uncompressed arrays without moving their data. Because every
buffer's offset and length is recorded per batch, a reader can also fetch only
the buffers of selected columns, which is the basis of the projection
requirement below.

Arrow defines two IPC variants:

* the stream format sends a schema and an ordered sequence of record batches;
* the file format adds `ARROW1` magic bytes and a footer containing the schema
  and offsets for random access to dictionaries and record batches.

The dtatools native file uses the file variant. The stream variant is out of
scope for v1; it has no footer, so it supports neither random access nor
projection-by-seek, and nothing in the caching and interchange use case needs
pipes or sockets yet.

### File extension

dtatools Arrow IPC files use the `.arrow` extension, for example
`survey.arrow`. The Arrow specification recommends `.arrow` for IPC files and
`.arrows` for stored IPC streams. dtatools uses the file variant, so `.arrows`
does not apply.

The extension identifies the Arrow IPC container. It does not imply that every
Arrow reader understands the `dtatools:*` metadata profile. Generic readers
can read the storage arrays, with the caveats described under missing-value
encoding, and ignore unknown metadata. dtatools readers use the profile
version, extension types, and metadata to restore labels, formats, notes,
storage declarations, and missing values.

A custom extension such as `.dtarrow` would make ordinary Arrow tooling less
likely to recognize the file without adding protection or semantics. A
`.feather` extension would also be technically valid for Feather V2, but
`.arrow` names the current IPC format directly. The format therefore uses
`.arrow` and records its dtatools identity inside the schema:

```text
dtatools:profile-version = "0"   # experimental, no stability promise
dtatools:profile-version = "1"   # first frozen profile
```

The prototype writes profile version `"0"`, which carries no stability
promise and which released readers may reject. Version `"1"` is stamped only
when the layout decisions survive the qualification and benchmark gate. From
the first frozen version onward, every frozen profile version remains readable
by all future package versions
([ADR 0010](../adr/0010-promise-stability-for-frozen-arrow-profiles.md)).

### R function names

The public R functions are `read_arrow()` and `save_arrow()`. They match the
`.arrow` extension and follow the existing `read_dta()` and `save_dta()` pair:

```r
library(dtatools)

data <- read_arrow("survey.arrow")
save_arrow(data, "survey.arrow")
save_arrow(data, "survey-lz4.arrow", compression = "lz4")
```

`save_arrow()` defaults to uncompressed IPC:

```r
save_arrow(x, file,
           compression = c("uncompressed", "lz4", "zstd"))
```

The default is fixed at `"uncompressed"`. It minimizes CPU work, and combined
with the eventual memory-mapped read path it means projected reads touch no
pages of unselected columns at all. Callers can select `"lz4"` when reduced
I/O may improve elapsed time on slow storage and `"zstd"` when file size
matters more. The writer records compression in the standard IPC record-batch
metadata, so `read_arrow()` detects it from the file and needs no matching
compression argument. Unsupported values are errors.

Benchmarks and examples must state the compression setting. Results from
uncompressed, LZ4, and Zstandard files are separate configurations and should
not be reported as a single Arrow IPC result.

Users do not need to write `dtatools::` after attaching the package. The Arrow
R package calls its generic IPC file functions `read_ipc_file()` and
`write_ipc_file()`, and uses `write_*` names throughout, so `save_arrow()`
cannot collide with anything Arrow R ships now or later.
[Arrow R's IPC file documentation](https://arrow.apache.org/docs/r/reference/read_ipc_file.html)
documents that API. Explicit calls such as `dtatools::read_arrow()` remain
available for scripts that prefer qualified names.

### Projection and row ranges

`read_arrow()` mirrors `read_dta()`'s selection idiom:

```r
read_arrow(file, col_select = NULL, skip = 0, n_max = Inf, verify = TRUE)
```

* `col_select` uses tidyselect, exactly as in `read_dta()`. The Rust
  `arrow-ipc` `FileReader` accepts a column projection, and the IPC file
  layout records per-buffer offsets, so a projected read fetches and (when
  compressed) decompresses only the selected columns' buffers.
* `skip` and `n_max` resolve at record-batch granularity: seek past whole
  batches, then slice within the boundary batches.

**Acceptance criterion**: reading *k* of *N* columns must cost I/O
proportional to the selected columns' buffers, verified by benchmark. An
implementation that reads whole batches and drops columns afterward does not
satisfy the projection requirement.

### Standard R data

The functions are general R data-frame readers and writers with extra support
for dtatools classes. They are not restricted to data returned by `read_dta()`.
`save_arrow()` must accept ordinary data frames and tibbles, dtatools-classed
data frames, and data frames that mix ordinary and dtatools columns.

The first implementation must support ordinary R logical, integer, double,
character, raw, factor, `Date`, `POSIXct`, and `difftime` columns. It writes
them with their standard Arrow types. dtatools metadata is added only to
fields where it carries semantics that standard Arrow types do not express.
The file still carries the schema-level dtatools profile version. An
unsupported column must produce an error that names the column and its class.

**R-side fidelity contract**: for the supported classes, `save_arrow()`
followed by `read_arrow()` restores the class-level semantics — factor levels,
orderedness, and unused levels; `POSIXct` timezone; `difftime` units; the
integer-versus-double distinction; `raw` as bytes. Attributes the profile does
not recognize are dropped with a report, mirroring the reported lossy export
conversions of the DTA writer. Decided during the prototype: haven `labelled`
bare double columns are supported input. They are written as Float64 with the
NaN-payload missing convention plus a value-label table and an
`r.class = "haven_labelled"` field document, and they read back with their
`labels` attribute and haven classes. This matches `save_dta()`, which already
accepts them, and costs nothing beyond the value-label machinery the profile
carries anyway.

`read_arrow()` must read both dtatools-profiled IPC files and ordinary IPC
files whose fields use the supported Arrow types. It restores dtatools classes
only when the file contains valid dtatools metadata. Otherwise it returns the
corresponding standard R columns. A single result may contain both kinds. This
keeps the interface useful for ordinary R work and prevents a standard Arrow
integer or double from acquiring Stata semantics merely because dtatools read
the file.

List columns, structs, and other nested Arrow types can be added after the
first implementation. Their absence must not weaken support for ordinary flat
R data frames, which is part of the initial interface contract.

### `dta_merge()` inputs

`dta_merge()` currently accepts a data frame or DTA file path for either `x`
or `y`. It should also accept `.arrow` paths in either position. The input
resolver will choose the reader from the extension:

```r
dta_merge("master.arrow", "using.arrow",
          by = "id", relationship = "1:1")

dta_merge("master.dta", "using.arrow",
          by = "id", relationship = "m:1")
```

An `.arrow` path will use `read_arrow()` with its defaults. A `.dta` path will
continue to use `read_dta()`. Extensionless paths will retain the existing DTA
behavior for compatibility. Callers who need non-default read arguments should
read the file first and pass the resulting data frame, which is already the
rule for DTA inputs.

The merge must produce the same result for equivalent data-frame, DTA, and
Arrow inputs. That includes Stata missing-code identity, labels, master-first
metadata reconciliation, dataset notes, and the labeled `_merge` column. Tests
should cover Arrow on both sides and mixed DTA/Arrow inputs for each supported
relationship.

## Semantic mapping

| Source concept | Arrow storage | Interoperability status |
|---|---|---|
| Long variable names | Arrow field names | Standard |
| R logical | Arrow `Bool` | Standard |
| R integer | Arrow `Int32` | Standard |
| R double | Arrow `Float64` | Standard |
| R character | Arrow `Utf8` or `LargeUtf8` | Standard |
| R raw | Arrow `UInt8` | Standard |
| R factor | Arrow dictionary with R ordering metadata | Standard storage; orderedness in metadata |
| R `Date` | Arrow `Date32` | Standard |
| R `POSIXct` | Arrow timestamp with unit and timezone | Standard |
| R `difftime` | Arrow duration with unit | Standard |
| Stata `byte`, `int`, `long` values | Arrow `Int8`, `Int16`, `Int32` per the declared compact representation | Values readable; missing sentinels private |
| Stata `float` | Arrow `Float32` | Values readable; missing payloads private |
| Stata/R `double` | Arrow `Float64` | Values readable; missing payloads private |
| `Inf`, `-Inf`, non-missing `NaN` | Non-null Arrow floating-point value | Standard semantic values |
| R `NA` in ordinary (non-profiled) columns | Arrow null | Standard |
| Stata `.` and `.a` through `.z` in profiled columns | Raw Stata storage: sentinel integers and NaN payloads, no validity bitmap | Private profile |
| Variable label | Field metadata | Private profile |
| Value-label table | Schema metadata keyed by Stata label-table name | Private profile |
| Dataset label | Schema metadata | Private profile |
| Stata display format | Field metadata | Private profile |
| Original Stata storage declaration | Field metadata | Private profile |
| Stata notes | Schema metadata, preserving order and scope | Private profile |
| Portable R semantics | Field or schema metadata | Private profile |
| Per-buffer checksums | Footer metadata | Private profile |

### Factors and value labels are related but not identical

Arrow's dictionary type is the natural representation of an R factor. Integer
indices refer to a dictionary of values. The Arrow R bindings map factors to
dictionaries and back, although the profile still needs to preserve orderedness
and unused levels explicitly. [Arrow R data types](https://arrow.apache.org/docs/r/articles/data_types.html#dictionaries-and-factors)
documents the mapping.

A Stata value-label table is different. It may label only some numeric codes,
may be shared by several variables, and does not turn the underlying variable
into a categorical type. Value-label tables are stored as schema metadata,
keyed by their Stata label-table name — Stata names them, the names are unique
within a dataset, and they survive round trips. Labeled Stata columns stay
numeric unless the caller explicitly requests factor conversion.

### Missing values use raw Stata storage

An Arrow null carries no tag, so 27 Stata missing categories cannot all map to
null without loss. The profile stores profiled numeric columns in their raw
Stata storage form:

* compact integer columns (`byte`, `int`, `long`) keep Stata's reserved
  sentinel values for `.` and `.a` through `.z`;
* floating-point columns keep the NaN payloads of the in-memory dtatools
  representation, in which `NA_real_` is the payload for system missing `.`;
* profiled columns carry **no Arrow validity bitmap**. The write path is a
  near-memcpy from the compact ALTREP backing, no bitmap or tag buffer is
  built, and the file is as small as the in-memory data.

Stata's compact missing ranges differ between older and modern DTA releases.
The writer normalizes a legacy column to the modern layout when that conversion
is lossless. If an observed value would collide with a modern missing sentinel,
it instead keeps the legacy layout and records its canonical release in the
field document. The reader then applies that layout's missing ranges,
preserving the tail value. Value-label entries separately identify observed
values and tagged missings, so they remain unambiguous across layouts.

Semantically, R `NA` and Stata `.` are the same value throughout dtatools.
Only the physical encoding differs by column provenance: an ordinary
(non-profiled) R column stores `NA` as a standard Arrow null; a profiled
column stores `.` as its sentinel or payload. Either encoding reads back as
`NA_real_`.

The trade-off is explicit: a generic Arrow reader that ignores `dtatools:*`
metadata sees sentinel integers and NaN payloads as ordinary values, including
for ordinary missings, so aggregates computed by unaware tools over profiled
columns silently include missing codes. That is acceptable for the
cache-and-interchange purpose, where dtatools is both writer and reader. A
compatibility representation (nullable values plus a companion tag array, or a
`Struct<value, tag>`) is recorded as super-low-priority follow-up in
[issue #82](https://github.com/jbearak/dta-parser/issues/82) and is more
relevant to the planned Parquet interchange functions.

A dtatools Arrow extension type identifies the raw-storage layout on each
profiled field. Extension types annotate a standard storage type with a
namespaced name and optional metadata; implementations that do not recognize
the extension can still handle its storage type. The extension complements the
documented storage layout, it does not replace it.

### Labels, formats, declarations, notes, and characteristics

Arrow supplies application-defined key-value metadata on schemas and fields.
The `ARROW` namespace is reserved, so dtatools uses its own namespace.
[Arrow custom metadata and extension types](https://arrow.apache.org/docs/format/Columnar.html#custom-application-metadata)
define the underlying mechanism.

The profile uses:

```text
dtatools:profile-version = "0"
dtatools:dataset = <versioned JSON document>
dtatools:field = <versioned JSON document on each Arrow field>
dtatools:checksums = <versioned JSON document in the file footer>
```

The dataset document contains the dataset label, numbered notes, arbitrary
Stata characteristics, and a registry of value-label tables keyed by Stata
label-table name. Field documents contain the same variable-scoped note and
characteristic arrays alongside the variable label, value-label-table name,
Stata display format, original storage declaration, missing-value encoding, a
release discriminator when a legacy missing layout must be retained, and
portable R semantics. The relevant profile-0 members are:

```json
{
  "version": 0,
  "label": "Survey",
  "notes": [{"number": 3, "text": "Checked"}],
  "characteristics": [{"name": "source", "value": "baseline"}],
  "value_labels": {}
}
```

Notes must have unique ascending numbers from 1 through 9,999. Characteristics
must have unique valid Stata names and cannot use numeric `note*` keys. Older
profile-0 string note arrays remain readable as consecutive notes beginning at
one. Writers omit empty arrays; omission and an explicit empty array have the
same behavior. JSON is inspectable across languages and avoids embedding
language-native serialized objects in extension metadata.
[Arrow's security guidance](https://arrow.apache.org/docs/format/Security.html#extension-types)
recommends a robust metadata serialization rather than native object
serialization.

**Profile-version handling**: a file whose profile version is newer than the
reader understands is a hard error naming the version and suggesting a package
upgrade. The reader also rejects any profile document it consumes that fails
to parse or validate. A projected read consumes the dataset document and the
selected fields' documents; it discards unselected fields' private documents
without parsing them. A full read consumes every field document. An explicit
escape hatch (for example `read_arrow(file, profile = FALSE)`) reads the raw
storage arrays as plain Arrow data. Silent degradation is not permitted: a
labeled, tagged-missing dataset must not quietly become plain numerics, which
is exactly the loss the package exists to prevent.

The consequences are explicit:

* dtatools readers and writers guarantee a lossless semantic round trip for a
  declared frozen profile version, indefinitely;
* a generic Arrow reader obtains the storage arrays, subject to the
  raw-storage missing-value caveat, and may ignore labels, formats, notes,
  characteristics, storage declarations, R semantics, and checksums.

### Integrity checksums

Arrow IPC has no native data integrity mechanism: neither the format nor the
`arrow-ipc` crate detects a flipped bit in a buffer, which would read back
silently as a wrong value. The profile therefore records an xxHash64 checksum
**per buffer** — per column per record batch — in a `dtatools:checksums`
document stored in the file footer's custom metadata, which is written last,
after all data has been hashed.

Per-buffer granularity is the only choice compatible with projection and row
ranges: a projected read verifies exactly the buffers it touches, and a
corrupt file is reported by column and batch. A whole-file or per-batch
checksum could only be verified by reading everything. The bytes hashed are
identical at any granularity, so the cost is the same; only the verifiability
differs. The metadata overhead is trivial (a 3,000-column, 10-batch file needs
about 240 KB of hashes).

`read_arrow()` verifies the checksums of every buffer it reads by default;
`verify = FALSE` opts out for benchmarking and trusted re-reads. xxHash64 runs
at multiple GB/s and hashing can be parallelized with decoding, so default
verification should not add user-perceivable latency; the benchmark suite
measures both settings so the cost is a known number.

## Performance and memory assessment

Arrow IPC has several properties aligned with the stated priorities:

* uncompressed record-batch buffers need no page decoding and can support
  zero-copy reconstruction;
* IPC files can be memory-mapped and accessed by record batch and by buffer,
  which is what makes projected reads cheap;
* writers can emit bounded record batches instead of retaining the whole table;
* Arrow arrays have contiguous buffers suitable for vectorized processing and
  cross-language transfer through the Arrow C Data Interface;
* optional LZ4 compression trades a small amount of CPU work for less I/O;
* dictionary arrays avoid repeating low-cardinality factor strings.

These are format capabilities, not benchmark results. The native dtatools path
returns its classed tibble and must include that construction in its timing.
For the Arrow R comparison, report both `as_data_frame = FALSE`, which leaves
the result as an Arrow table, and a fully materialized R data frame. Comparing
an Arrow table with a DTA reader that returns R vectors would not be fair.

Rust's official `arrow-ipc` crate provides `FileReader` and `FileWriter` for IPC
files and `StreamReader` and `StreamWriter` for IPC streams. The file writer
accepts record batches incrementally, which supports bounded-memory output.
[The `arrow-ipc` `FileWriter` documentation](https://docs.rs/arrow-ipc/latest/arrow_ipc/writer/struct.FileWriter.html)
documents the write path.

**Record batches are bounded**: the writer emits a fixed rows-per-batch rather
than one batch per file. This bounds writer memory, gives `skip` and `n_max`
batches to seek past, and costs the reader one concatenation of per-batch
chunks into single R vectors — a copy the v1 read path performs anyway. The
default rows-per-batch is pinned by benchmark and recorded with the results,
in the spirit of [ADR 0008](../adr/0008-qualify-before-benchmarking-dta-writes.md).
Writing small tables as a single batch remains an internal detail, not a
promise.

The native reader should transfer compact Arrow integer and floating-point
storage into the package's existing ALTREP classes and attach profile metadata
through the current R adapter. The initial implementation may copy an IPC
buffer once into Rust-owned ALTREP backing. It must not widen compact integers
into ordinary R doubles as an intermediate step. Reusing memory-mapped IPC
buffers without a copy would require the ALTREP backing to retain the mapping's
lifetime; it is a deferred optimization, and combined with uncompressed
buffers and projection it is the eventual path to reads that touch no pages of
unselected columns.

The native writer should inspect dtatools compact ALTREP backing directly and
form Arrow arrays from that storage. With raw Stata storage this is a
near-memcpy: no validity bitmaps or tag buffers are constructed. It should
avoid forcing an ALTREP column to materialize as an R double vector merely to
write it. Ordinary R vectors can use the existing native write-source adapter
pattern.

This creates one implementation behind the `read_arrow()` and `save_arrow()`
interface. There is no need for a swappable adapter seam until a second
implementation exists. Arrow R's `read_ipc_file()` and `write_ipc_file()` remain
an independent interoperability oracle and a useful performance comparison.

### What must be benchmarked

No repository result currently compares Arrow IPC with `read_dta()` or
`save_dta()`. First verify semantic equality, then measure:

* full reads and writes;
* projected reads: *k* of *N* columns must cost I/O proportional to the
  selected columns' buffers, across narrow and wide selections;
* `skip`/`n_max` row-range reads at batch boundaries and mid-batch;
* checksum verification on and off;
* standard-only, dtatools-only, and mixed R data frames;
* ordinary IPC files written by an independent Arrow implementation;
* `dta_merge()` with DTA, Arrow, and mixed file inputs;
* Arrow table results and fully materialized R data frames;
* low- and high-cardinality strings and factors;
* compact Stata integer-heavy survey data;
* tagged-missing-heavy data (raw storage should make this free);
* uncompressed, LZ4, and Zstandard IPC;
* Parquet with a fast codec as a size-oriented comparison;
* candidate rows-per-batch defaults;
* cold and warm filesystem cache;
* elapsed time, CPU time, peak RSS, and output bytes;
* single-thread and matched-thread-count configurations.

The comparison should include `dtatools::read_dta()` and `save_dta()`, the
native Rust `arrow-ipc` path, and Arrow R's IPC path as an independent
comparison. Use the same logical table and result materialization. Exclude
one-time package loading only if it is excluded for every contender. Pin codec
and batch-size settings and report CPU count. The repository already requires
correctness qualification before timing its DTA writer. Apply the same policy
here. See the local
[`0008` ADR](../adr/0008-qualify-before-benchmarking-dta-writes.md) and
[`benchmarks/README.md`](../../benchmarks/README.md).

## Recommended next experiment

Implement a small Arrow IPC profile prototype under profile version `"0"`
rather than freezing the format immediately:

1. Add `arrow-ipc` to the native Rust crate and map ordinary R and compact
   Stata columns to Arrow arrays with versioned `dtatools:*` JSON metadata.
   Qualify standard-only, dtatools-only, and mixed data frames independently.
2. Implement raw Stata storage for profiled columns and confirm bit-exact
   round trips of sentinel integers and NaN payloads through every R, Rust,
   and Arrow conversion path.
3. Round-trip dataset and variable labels, shared value-label tables keyed by
   label-table name, display formats, storage declarations, ordered factors,
   and notes in R and Rust.
4. Implement projection, `skip`/`n_max`, and per-buffer checksums; verify the
   I/O-proportionality criterion.
5. Extend `dta_merge()` path resolution and equivalence tests to `.arrow` and
   mixed `.dta`/`.arrow` inputs.
6. Benchmark uncompressed and LZ4 IPC first. Include Zstandard IPC and Parquet
   to measure the cost and size benefit of stronger encoding and compression.
7. Test native dtatools-tibble reads on synthetic cases and a permitted survey
   corpus. Use Arrow R to verify generic IPC compatibility and to measure the
   cost of its Arrow-table and R-data-frame paths separately.
8. Freeze profile version `"1"` only when these decisions survive the
   qualification and benchmark gate ([ADR 0010](../adr/0010-promise-stability-for-frozen-arrow-profiles.md)).

If the experiment succeeds, describe Arrow IPC as the toolkit's durable fast
native format and DTA as its cross-tool compatibility format. Keep Parquet as
the deferred interchange format for `read_parquet()` and `save_parquet()`,
where smaller files, generic readability, projection statistics, and
query-engine integration matter more than full-table latency.
