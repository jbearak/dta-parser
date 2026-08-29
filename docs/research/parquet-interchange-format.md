# Parquet as a migration and interchange format

> **Deferred.** Arrow IPC was chosen first as the dtatools native format
> because full-table read and write time is the first priority; see
> [arrow-ipc-interchange-format.md](./arrow-ipc-interchange-format.md).
> Revisit this document for the planned `read_parquet()` and `save_parquet()`
> interchange functions, where generic-reader compatibility and file size
> matter more than latency.

Research date: 2026-08-28

## Conclusion

Parquet is a strong candidate for the physical foundation of a dtatools-owned
native analytical format. Parquet alone is not a lossless Stata or R
interchange format, but that is not a requirement. Exact semantics can be the
contract between dtatools readers and writers. Access through other Parquet
readers is a separate, optional goal.
Its standard representation covers long UTF-8 field names, integers, IEEE
single- and double-precision values (including infinities and NaNs), nulls,
strings, dates/times, nested values, and efficient dictionary and compression
encodings. It is designed for selective, parallel, columnar reads and can be
written in bounded row groups. Those properties fit the toolkit's goals better
than DTA when the destination is R, Rust, Arrow, DuckDB, Spark, or another
modern analytical system.

The remaining semantics include Stata's 27 missing codes, value and variable
labels, display formats, declared DTA storage types, dataset labels, and notes.
They have no standard Parquet logical types. R classes and arbitrary attributes are likewise
not standardized by Parquet. They can be preserved using file key-value
metadata and Arrow field/schema metadata, but generic Parquet readers may
ignore that metadata. The honest product claim would therefore be:

> A versioned dtatools format built on Parquet, with exact dtatools round trips.

Parquet may plausibly meet or exceed `read_dta()`/`write_dta()` for some
workloads, especially projected reads, repeated or low-cardinality columns,
compressed storage, and parallel decode. No relative performance claim is
justified before a like-for-like benchmark. DTA's row-major layout and this
repository's highly specialized decoder make full-row scans a different contest
from Parquet's columnar strengths.

## What Parquet standardizes

Parquet deliberately keeps its physical type set small: `BOOLEAN`, `INT32`,
`INT64`, `FLOAT`, `DOUBLE`, `BYTE_ARRAY`, and `FIXED_LEN_BYTE_ARRAY` (plus the
deprecated `INT96`). Logical annotations give those physical values meanings
such as UTF-8 strings, signed integer widths, dates, timestamps, decimals,
lists, and maps. A 16-bit integer, for example, is stored in `INT32` rather than
receiving a separate physical layout. This is a storage contract, not a
language-specific object model. [Parquet physical types](https://parquet.apache.org/docs/file-format/types/)
and [logical types](https://parquet.apache.org/docs/file-format/types/logicaltypes/)
are the authoritative specifications.

Parquet files are divided into row groups, column chunks, and pages. The footer
locates the column chunks, so a reader first obtains metadata and then reads the
selected chunks sequentially. The format identifies a row group as a unit of
parallelization, a column chunk as a unit of I/O, and a page as a unit of
encoding/compression. [The file layout](https://parquet.apache.org/docs/file-format/)
therefore supports projection and parallelism without requiring every column to
be decoded.

Nullness is independent of a floating-point value. Parquet encodes nulls through
definition levels, while `FLOAT` and `DOUBLE` contain IEEE values. Arrow makes
the same separation explicit through a validity bitmap alongside the primitive
value buffer. Consequently, `Inf`, `-Inf`, and a non-null `NaN` all have natural
representations distinct from null. [Arrow's validity-bitmap specification](https://arrow.apache.org/docs/format/Columnar.html#validity-bitmaps)
documents this separation. Exact preservation of arbitrary NaN payload bits is
a stronger requirement than preservation of the semantic value `NaN` and
should be tested across intended writers, encodings, and readers rather than
assumed.

Field names are schema strings rather than DTA-width fields, so Parquet does not
impose Stata's short variable-name limit. UTF-8 strings are standard Parquet
`BYTE_ARRAY` values with the `STRING` logical annotation. This directly solves
the long-name and long-string interchange problems, subject only to individual
implementation limits rather than a DTA format limit.

## Semantic mapping

| Source concept | Proposed standard storage | Interoperability status |
|---|---|---|
| Long variable names | Parquet schema field names | Standard |
| R logical | Parquet `BOOLEAN` | Standard |
| Stata `byte`, `int`, `long` values | Parquet `INT32`, with a signed-width logical annotation where useful | Values standard; original DTA declaration private |
| Stata `float` | Parquet `FLOAT` | Standard |
| Stata/R `double` | Parquet `DOUBLE` | Standard |
| `Inf`, `-Inf`, non-missing `NaN` | Non-null IEEE `FLOAT`/`DOUBLE` | Standard semantic values |
| Ordinary missing | Parquet null | Standard |
| Stata `.`, `.a` … `.z` | Nullable value plus a companion tag representation | Private profile |
| R factor | Arrow dictionary / Parquet dictionary-capable column | R/Arrow round-trip supported; factor class and orderedness are not general Parquet semantics |
| Variable label | Field metadata | Private profile |
| Value-label table | Schema/file metadata keyed by stable table ID | Private profile |
| Dataset label | File/schema metadata | Private profile |
| Stata display format | Field metadata | Private profile |
| Original Stata storage declaration | Field metadata | Private profile |
| Stata notes | Schema/file metadata, preserving order and scope | Private profile |
| Arbitrary R class/attributes | Arrow R metadata or a defined portable subset | Arrow-R convention, not general Parquet semantics |

### Factors and value labels are related but not identical

Arrow's dictionary type is the natural representation of an R factor: integer
indices refer to a dictionary of string levels. The Arrow R documentation says
that factors translate to dictionaries and back, and notes that Arrow
dictionaries are more general because their dictionary values need not be
strings. [Arrow R data types](https://arrow.apache.org/docs/r/articles/data_types.html#dictionaries-and-factors)
documents that mapping. The Arrow R implementation also records R metadata to
round-trip attributes and custom classes through Arrow/Parquet; its release
notes explicitly mention factors and `haven::labelled` subclasses.
[Arrow R release notes](https://github.com/apache/arrow/blob/main/r/NEWS.md)

That behavior is useful but should not be mistaken for a universal Parquet
factor standard. Parquet dictionary encoding is primarily an encoding choice;
a reader may decode it to ordinary values. A Stata value-label table can also
label only some numeric codes, can be reused by multiple variables, and does not
turn the underlying variable into a categorical type. The profile should
therefore preserve value-label tables as metadata independently of any optional
dictionary representation used for R factors.

For an R factor, the portable values could be stored as UTF-8 strings, or the
codes could be stored as integers with factor-level metadata. The former
degrades cleanly everywhere but loses unused levels and ordering without
metadata. The latter better preserves R internals but generic tools expose
codes. An Arrow dictionary is attractive in an Arrow-native path, but the
profile still needs explicit metadata for `ordered`, unused levels, and the
intended R class.

### Tagged missing values need per-value representation

A Parquet null carries no tag, so 27 Stata missing categories cannot all map to
null without loss. Metadata alone cannot say which tag belongs to each row.
Four defensible representations are:

1. the raw Stata storage representation, using its reserved integer codes and
   floating-point missing bit patterns, plus metadata that identifies the
   storage type and missing scheme;
2. a nullable numeric value column plus a compact companion integer tag column
   (`0` = present or ordinary null policy, `1..27` = `.`, `.a` … `.z`);
3. a struct containing `value` and `missing_tag`; or
4. reserved IEEE NaN payloads plus metadata that identifies the payload scheme.

There is no need to select the companion representation merely to accommodate
arbitrary readers. The right choice depends on measured size, speed, and the
desired degraded view. Raw Stata storage is the most direct candidate for columns that already
carry a Stata storage declaration. Stata's reserved missing codes fit their
corresponding signed integer widths, and floating missing codes already have
defined bit patterns. A dtatools reader can expose those values with the same
compact semantics it uses after `read_dta()`. An unaware reader will see
reserved integers or NaNs rather than Stata missing categories, which is
acceptable if generic semantic reconstruction is not a goal. A companion tag
is explicit and lets generic readers see ordinary values;
it costs another physical column and requires projection logic to keep the pair
together. A struct makes ownership explicit but some data-frame tools handle
nested columns less naturally. NaN payloads keep a numeric column physically
compact and closely resemble the representation already used by R/haven tagged
missings; generic readers will normally see only NaNs and lose their tags.

The Parquet encoding specification makes the payload design more credible than
a generic warning about floating point would suggest. `PLAIN` stores `FLOAT`
and `DOUBLE` as IEEE little-endian bits, and the current ALP specification
requires exact IEEE bit patterns for exceptional values, explicitly forbidding
NaN canonicalization. [Parquet encoding definitions](https://github.com/apache/parquet-format/blob/master/Encodings.md)
Nevertheless, the end-to-end contract includes the chosen R and Rust libraries,
not just the file specification. Before choosing payloads, test every enabled
encoding and codec through Arrow R/C++, `arrow-rs`, and dtatools for bit-exact
round trips. Pin or disable any path that canonicalizes NaNs. Also ensure the R
bridge does not translate tagged NaN payloads to Arrow nulls; Arrow's data model
can distinguish non-null NaN from null, but the bridge controls conversion.

Because dtatools owns both ends, a custom Arrow extension type could be backed
by either the payload or companion representation. That improves schema-level
identification but does not eliminate the need to define physical values and
metadata.

The profile should define whether ordinary R `NA` maps to tag `.` or to an
untagged Parquet null, and should preserve this distinction if the toolkit
exposes it. It should also define comparison/tabulation semantics; Parquet only
stores the representation.

### Labels, formats, declarations, and notes

The Parquet Thrift schema gives `FileMetaData` optional
`key_value_metadata`, but does not assign Stata meanings to its keys.
[The Parquet Thrift definition](https://github.com/apache/parquet-format/blob/master/src/main/thrift/parquet.thrift)
is the authoritative contract. Arrow provides key-value `custom_metadata` on
schemas and fields, reserves the `ARROW:` namespace, and recommends a
namespace-style name for third-party extension types.
[Arrow custom metadata and extension types](https://arrow.apache.org/docs/format/Columnar.html#custom-application-metadata)
provide the cleanest in-memory model.

A proposed profile should use a non-reserved namespace, for example:

```text
dtatools:profile-version = "1"
dtatools:dataset = <versioned JSON document>
dtatools:field = <versioned JSON document on each Arrow field>
```

The dataset document can contain the dataset label, ordered notes, and a
registry of value-label tables with stable IDs. Field documents can contain the
variable label, value-label-table ID, Stata display format, original DTA storage
declaration, missing-tag companion field, and portable R semantics. JSON is
inspectable across languages and Arrow's security guidance recommends a robust
metadata serialization such as JSON rather than language-native serialization
for extension metadata. [Arrow security guidance](https://arrow.apache.org/docs/format/Security.html#extension-types)

If Arrow C++ writes the file with schema storage enabled, it serializes the
original Arrow schema under the conventional `ARROW:schema` Parquet metadata
key and uses it to restore Arrow field information that Parquet alone cannot
express. [Arrow C++'s Parquet schema adapter](https://github.com/apache/arrow/blob/main/cpp/src/parquet/arrow/schema.cc)
shows this mechanism. It is valuable for Arrow implementations, but a
`dtatools` reader should also be able to reconstruct its semantics from the
public profile rather than depending solely on a private serialized Arrow
schema.

Two consequences should be explicit in documentation:

* `dtatools` readers and writers guarantee a lossless semantic round trip for a
  declared profile version;
* a generic Parquet reader still obtains useful ordinary values, but may discard
  labels, formats, notes, storage declarations, R attributes, and missing tags
  unless companion tag columns are retained and understood.

An Arrow extension type could wrap compact Stata numerics or tagged values.
Extension types annotate a standard storage type with
`ARROW:extension:name` and optional serialized metadata; implementations that
do not support an extension may treat it as its storage type and retain the
metadata. However, third-party extensions are not automatically interoperable,
and canonical names beginning `arrow.` are reserved. An extension may improve
Arrow-to-Arrow ergonomics, but it should complement the documented
storage layout and metadata profile.

## Performance and memory assessment

Parquet has architectural advantages for analytical interchange:

* column projection can avoid I/O and decode for unselected column chunks;
* row groups and columns admit parallel reads;
* dictionary, run-length, delta, bit-packing, and byte-stream-split encodings,
  combined with codecs such as Snappy or Zstandard, can reduce I/O;
* statistics and page/column indexes can support row-group and page pruning;
* Arrow arrays provide contiguous, vectorization-friendly memory and a C data
  interface for cross-language exchange.

These are format capabilities, not a benchmark result. Compression can make
writes more CPU-intensive. Parquet writers buffer enough state to finish a row
group; larger groups can improve compression and sequential I/O while raising
peak memory. The official `arrow-rs` `ArrowWriter` reports its in-progress
memory and encoded size, flushes at configurable row/byte limits, and now allows
completed pages to spill from memory through a page-store abstraction.
[The `ArrowWriter` implementation](https://github.com/apache/arrow-rs/blob/main/parquet/src/arrow/arrow_writer/mod.rs)
documents those controls. This provides a credible bounded-memory Rust design:
stream R columns into Arrow record batches, choose a bounded row group, flush
incrementally, and avoid materializing a second whole dataset.

Rust has an official Apache implementation in `arrow-rs`; its documented common
path is `ArrowWriter` for output and `ParquetRecordBatchReaderBuilder` for input,
with lower-level APIs for filters, interleaved I/O/CPU control, and parallel
column writing. [The official Rust crate documentation](https://docs.rs/parquet/latest/parquet/)
and [Apache Arrow Rust repository](https://github.com/apache/arrow-rs)
make it the lowest-risk initial implementation choice. `parquet2`/`arrow2`
offers a different design that separates I/O from CPU decoding and delegates
parallelism to consumers, but `parquet2`'s latest repository release is from
2022; it warrants compatibility and maintenance review before adoption.
[The parquet2 repository](https://github.com/jorgecarleitao/parquet2)

Arrow R's `write_parquet()` exposes row-group size, compression,
per-column dictionary use, statistics, and page-size controls. Its reader can
memory-map local files and read selected columns or row groups.
[The R writer](https://arrow.apache.org/docs/r/reference/write_parquet.html)
and [R reader source/documentation](https://github.com/apache/arrow/blob/main/r/R/parquet.R)
show that an R-facing prototype can be built without first implementing a full
Parquet codec in this repository. The tradeoff is a substantial Arrow R/C++
dependency; a direct `arrow-rs` bridge could eventually give tighter memory and
metadata control while sharing the Rust core.

### What must be benchmarked

No existing repository result compares Parquet with `read_dta()` or
`write_dta()`. The repository's current reports concern DTA implementations and
must not be extrapolated across formats. A useful qualification should first
verify semantic equality, then measure:

* full reads and writes;
* narrow projection from wide data;
* low- and high-cardinality strings/factors;
* compact Stata integer-heavy survey data;
* tagged-missing-heavy data and companion-column overhead;
* compressed and uncompressed Parquet;
* cold and warm filesystem cache;
* elapsed time, peak RSS, output bytes, and materialization behavior;
* single-thread and matched-thread-count configurations.

The comparison should include `dtaparser::read_dta()`/`write_dta()`, Arrow R's
Parquet path, and a direct Rust/`arrow-rs` path if built. It should use the same
logical table and projection, exclude one-time package loading only if excluded
for all contenders, pin codec/row-group settings, and report CPU count. The
repository already requires correctness qualification before timing its DTA
writer and measures elapsed time, peak memory, and output size; the same policy
should govern a Parquet experiment. See the local
[`0008` ADR](../adr/0008-qualify-before-benchmarking-dta-writes.md) and
[`benchmarks/README.md`](../../benchmarks/README.md).

## Recommended next experiment

Implement a deliberately small profile prototype rather than adopting Parquet
as a public promise immediately:

1. Map ordinary R/compact Stata columns to Arrow types and write Parquet with
   `ARROW:schema` plus versioned `dtatools:*` JSON metadata.
2. Prototype raw Stata storage, exact NaN payloads for R doubles, and a value
   column plus integer tag companion. Assess whether a struct improves the API
   enough to justify its cost.
3. Round-trip dataset/variable labels, shared value-label tables, display
   formats, storage declarations, ordered factors, and notes in both R and
   Rust.
4. If useful third-party access is a product goal, test the degraded view through
   an independent generic reader. This is not required for an exact dtatools
   round trip.
5. Run the qualified benchmark matrix above on synthetic cases and a permitted
   survey corpus.

If the experiment succeeds, describe Parquet as the toolkit's open migration
format and DTA as its Stata compatibility format. That framing matches the
broader mission: preserve Stata meaning at the boundary, permit incremental
translation to R/Rust semantics, and stop inheriting DTA's representational
limits once users cross that boundary.
