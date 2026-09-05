# TypeScript Arrow reading and DTA parity

The user confirmed this design and authorized implementation, independent
subagent reviews, and the PR/CI/CodeRabbit/merge loop. The parser implementation
and local review are in progress. Table Viewer adoption follows the parser merge.

## Agreed scope

- Add reading of dtatools-profile Arrow IPC files and ordinary Arrow IPC files
  within the existing Rust/R reader's supported coverage. IPC streams and
  broader Arrow type coverage are outside this change.
- Keep this work read-only. Do not add TypeScript writers.
- Audit TypeScript DTA reads against the documented shared parsing contract
  and fix confirmed discrepancies. Preserve documented language differences,
  including raw numeric dates with display formats and explicit Stata missing
  objects in TypeScript.
- Support synchronous reads from complete buffers in the portable entrypoint
  and asynchronous file reads in Node. Support uncompressed, LZ4, and Zstandard
  files in both entrypoints.
- Node reads support cancellation, selected columns, and row windows. Read
  selected column buffers from overlapping batches without loading the whole
  file. Compressed selections may require decoding a complete selected buffer.
- Keep application integration separate. This change covers the parser package,
  its tests, and documentation; it does not update Sight, Table Viewer, or
  Manuscript Markdown.

## Agreed value model

Arrow has its own cell and metadata types. Existing DTA types remain compatible.

| Source value | TypeScript representation |
| --- | --- |
| Stata system or extended missing | Existing `MissingValue` object |
| Arrow null | `null` |
| Boolean | `boolean` |
| Signed or unsigned 64-bit integer | `bigint` |
| Other supported integers and floats | `number` |
| UTF-8 string | `string` |
| Date, timestamp, duration | Stored numeric ticks with unit and timezone metadata; 64-bit ticks use `bigint` |
| Dictionary or factor | Codes with dictionary levels and orderedness metadata |

Keep plain Arrow nulls, non-null NaNs, and profiled missing codes distinct.
Inspect profiled floating-point missing payloads before converting them to
JavaScript numbers. Plain Arrow fields never acquire Stata missing semantics.
Preserve supported dataset and field profile metadata, including labels,
numbered notes, characteristics, value-label registries and assignments, string
storage, R class information, and stored output-container provenance.

Dictionary codes use Arrow's zero-based indexing. Preserve levels, including
unused entries, independently of the selected rows. Temporal metadata records
the storage unit and epoch separately from any recorded R class or display
format. Profiled Float64 temporal fallbacks retain their original floating-point
values and semantic units. Consumers explicitly format values and handle
`bigint` when serializing to JSON.

See [the value-model decision](./adr/0027-preserve-arrow-values-in-separate-typescript-types.md).

## Public API

Keep the current package name and entrypoints. Add a synchronous portable
`ArrowBuffer.open(buffer, options?)` and a Node
`await ArrowFile.open(path, options?)`. Both expose `nobs`, `nvar`, Arrow
variable metadata, dataset metadata, and dictionary information, with
`read_rows(start, count, col_start?, col_end?, options?)` and
`read_columns(indices, options?)`. The buffer methods return results directly;
the Node methods return promises and accept `AbortSignal`. `ArrowFile.close()`
releases its file handle.

Follow existing zero-based row and column indexing and exclusive column ends.
Validate indexes, counts, byte offsets, and allocation sizes before reading.
Keep file geometry private so editable exported metadata cannot redirect reads.
Expose Arrow types separately from `DtaMetadata`, `VariableInfo`, and `RowCell`.
Re-export the new portable API from the Node entrypoint. A format-detecting
opener and a shared application adapter are outside this change.

The portable build must work without Node filesystem imports. Existing DTA
callers retain their public API. Table Viewer currently accesses private DTA
internals, so avoid unrelated changes to those internals during this work.

## Existing contracts

The [compatibility contract](./compatibility.md) defines shared DTA behavior.
The [Arrow profile stability decision](./adr/0010-promise-stability-for-frozen-arrow-profiles.md)
defines profile version handling, validation, and checksum expectations.
The current Rust implementation writes experimental profile version `0`.
Adding a TypeScript reader does not freeze that profile.

Apply profile handling and checksum verification by default. Reject unknown
profile versions and malformed profile documents consumed by a read. An
explicit `profile: false` option exposes raw Arrow storage and disables profile
checksum verification; `verify: false` disables verification without discarding
profile semantics. Follow Rust's selected-field validation rules for projections
and full validation for full reads. Hash canonical logical buffers using the
Rust profile's rules, including bitmap padding, rebased string offsets, and
dictionary values. Hashing the compressed bytes is not equivalent.

Coverage follows the current Rust reader: booleans; signed and unsigned
8/16/32/64-bit integers; Float32/Float64; Utf8/LargeUtf8; Date32; timestamps;
durations; and UTF-8 dictionaries with supported signed integer keys. Test
dictionary sharing and delta batches against Rust. Other types and IPC streams
produce explicit unsupported-input errors.

R-specific selectors, containers, worker scheduling, and data-signature APIs
are outside the TypeScript reading API. Their recorded profile metadata remains
available where applicable.

## Initial audit evidence

The TypeScript baseline passes 308 tests with 1,538 assertions across 19 files.
Typechecking could not run because local `bun-types` and `@types/node`
dependencies were absent.

In-memory mutations of `auto_v118.dta` show that TypeScript accepts a zero
value-label table length and a damaged closing `</lbl>` tag. Damaging the
opening `<lbl>` tag can silently return no label tables. The modern parser
skips the declared length and closing tag, and stops on an unexpected opening
tag. Rust explicitly validates these structures; its rejection of these
particular mutations has been checked by code inspection, not execution.

The existing conformance gate checks metadata and projection lengths but does
not comprehensively compare decoded TypeScript cells with the canonical
oracle. Several malformed-input cases run only against Rust.

## Acceptance checks

- Compare TypeScript DTA values and metadata with the existing canonical
  oracle, across supported releases, byte orders, encodings, missing codes,
  labels, notes, characteristics, fixed strings, and resolved long strings.
  Compare row windows and column projections as well as full reads.
- Add regression cases for confirmed structural defects and compare malformed
  input handling with Rust. Classify intentional helper-level differences
  explicitly instead of silently changing public DTA representations.
- Generate Arrow fixtures through the existing Rust/R implementation, covering
  supported physical types, profiled and plain columns, all missing codes,
  profile metadata, temporal fallbacks, dictionaries, empty data, multiple
  batches, projections, and all three compression modes. Compare decoded
  content between readers, not merely array lengths.
- Test corrupted framing, invalid offsets, malformed or unknown profiles,
  checksum failures, dictionary references, and explicit raw-profile reads.
- Instrument Node reads to establish that projections skip unselected data
  buffers and non-overlapping batch bodies. Test cancellation and handle
  cleanup. Do not claim memory is independent of compressed buffer size.
- Run the existing package tests, typechecks, builds, and conformance checks
  after installing the declared development dependencies. Verify ESM and
  CommonJS exports, declarations, and an actual portable browser bundle.
- Document the new API, coverage, value representations, validation behavior,
  and any remaining intentional DTA differences. No performance claims without
  measurements.

Choose internal dependencies only when they satisfy the
agreed synchronous portable and projected Node contracts. A codec limitation
must not silently narrow compression coverage.

## Implementation feasibility notes

Apache Arrow JS's [file reader](https://github.com/apache/arrow-js/blob/main/src/ipc/reader.ts)
reads complete batch bodies and loads dictionaries on opening. Use a narrow IPC
layer shared by buffer and file readers to implement selected-buffer access,
with explicit handling of the profile's footer metadata. Keep codecs behind
internal adapters and use other readers for interoperability checks.

The implementation uses a bounded LZ4 Frame decoder and a vendored MIT-licensed
[fzstd](https://github.com/101arrowz/fzstd) decoder with wide-offset decoding
and bounds fixes. A Rust-generated frame with a backreference beyond 96 MiB
tests the offset case that the upstream decoder mishandles. Codecs validate
frame checksums and exact output sizes, without native addons or asynchronous
initialization. See the vendored-source notes for the retained license and
local changes.
