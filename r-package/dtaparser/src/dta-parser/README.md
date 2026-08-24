# dta-parser (Rust)

This crate is the native Rust core for `dta-parser`. It parses Stata releases
105, 108, 110–111, 113–115, and 117–119 into a storage-preserving,
column-oriented model. Metadata,
numeric and fixed-string observations, resolved `strL` values, exact missing
tags, and value-label tables are retained.

```rust,no_run
use dta_parser::{read_dta_with_options, ColumnValues, ReadOptions};

let bytes = std::fs::read("data.dta")?;
let data = read_dta_with_options(
    &bytes,
    &ReadOptions {
        row_start: 10,
        row_count: Some(100),
        column_indices: Some(vec![0, 3, 7]),
    },
)?;
for column in &data.columns {
    println!("variable {}: {} values", column.variable_index, column.values.len());
}
# Ok::<(), Box<dyn std::error::Error>>(())
```

`read_dta(&bytes)` is the full-read shorthand. Row ranges are clamped to the
dataset. Explicit column projections preserve request order, discard duplicate
indices after their first occurrence, and reject out-of-range indices with a
typed error. `DtaData::column_by_name`, `DtaData::value_label_table`, and
`DtaData::value_label_table_for_variable` provide name-based lookup and label
association without changing the source order retained in the public vectors.
The reader validates the complete `<data>` and `<strls>` envelopes even when
`strL` variables are projected out. It scans and resolves GSO records only when
a selected variable is `strL`; duplicate, invalid, partial, and dangling keys
are reported as typed errors.

Numeric `ColumnValues` variants preserve the source storage width (`i8`,
`i16`, `i32`, `f32`, or `f64`) and carry a parallel
`Vec<Option<MissingTag>>`. Raw Stata missing values remain in the values vector,
so consumers retain both exact storage and the classified `.`, `.a`–`.z` tag.
Releases 118–119 use UTF-8 replacement for malformed text sequences. Releases
105, 108, 110–111, 113–115, and 117 use Windows-1252 for textual metadata, fixed strings, and
value labels. All fixed fields stop at their first NUL byte.

Every byte-slice and seekable-file path also accepts a deterministic
`TextEncoding` override. `Utf8`, `Windows1252`, and true `Iso8859_1` decoding
apply to dataset and variable metadata, fixed strings, `strL` payloads, and
value-label names and text; malformed input uses replacement decoding.
`TextEncoding::Auto` is the default used by the original APIs. Use
`read_dta_with_encoding`, `read_dta_with_options_and_encoding`,
`parse_metadata_with_encoding`, `parse_value_labels_with_encoding`,
`DtaFile::open_with_encoding`, or the corresponding reader constructors for
an override. `TextEncoding::from_label` accepts case-insensitive UTF-8/UTF8,
Windows-1252/CP1252, and ISO-8859-1/latin1 aliases and rejects other names;
ISO-8859-1 is intentionally distinct from Windows-1252 at bytes 0x80--0x9f.

Value-label tables retain their on-disk order, including nonascending or
duplicate integer keys found in real-world files. Lookups return the first
matching entry. Declared lengths, text offsets, NUL terminators, modern wrapper
tags, legacy table boundaries, and mapped section boundaries are validated.

For seekable inputs, `DtaFile<R: Read + Seek>` provides bounded-buffer random
access without loading observation data at construction:

```rust,no_run
use dta_parser::{DtaFile, FileOptions, ReadOptions, TextEncoding};

let mut file = DtaFile::open("data.dta")?;
let page = file.read_with_options(&ReadOptions {
    row_start: 1_000,
    row_count: Some(100),
    column_indices: Some(vec![0, 4, 9]),
})?;

let mut checks = 0_u32;
let result = file.read_with_interrupt(&ReadOptions::default(), || {
    checks += 1;
    checks > 10_000
});

let configured = FileOptions { max_buffer_bytes: 64 * 1024 };
let latin1 = DtaFile::open_with_encoding("legacy.dta", TextEncoding::Iso8859_1)?;
# let _ = (page, result, configured, latin1);
# Ok::<(), Box<dyn std::error::Error>>(())
```

`max_buffer_bytes` must be at least 1024. It bounds every temporary raw-byte
staging allocation and read request; caller-visible decoded strings, metadata,
columns, label-table results, and their derived indexes or caches are not
capped. Row windows seek directly to selected observations, and only selected
cells are decoded. GSO headers are scanned without retaining unrequested
payloads, selected payloads are streamed and cached per read, and value-label
tables are streamed and cached lazily. The cooperative callback is checked
between chunks and returns `DtaError::Cancelled` without exposing a partial
output or partially initialized label cache.

`DtaFile::read_with_sink_and_interrupt` runs the same validation, I/O, typed
cell decoding, `strL`, and value-label pipeline through a caller-provided
`DtaSink`. The built-in sink retains the public `DtaData`/`ColumnValues` model;
foreign-runtime adapters can instead materialize their own column store. The
generic sink is statically dispatched, avoiding a dynamic callback boundary in
the per-cell loop.

The file reader builds one format-neutral observation plan for every release
before decoding. `DtaFile::parallel_thread_count` gates the current multicore
executor to sufficiently large projections in every supported release;
oversized rows or small workloads return one and use the synchronous
column-oriented executor.
`DtaFile::read_with_parallel_interrupt` materializes the built-in Rust model,
while `read_with_parallel_sink_and_interrupt` accepts a `ParallelDtaSink` that
splits independently owned `DtaColumnSink` values across persistent workers.
Workers share immutable bounded input blocks and retain the ordinary scalar
decoding rules. For `strL` columns, workers collect observation pointers and
the coordinator validates the GSO index, streams selected payloads, and writes
the resolved strings after the workers join.

`DtaMetadata` and its nested types implement `serde::Serialize` and
`serde::Deserialize`; the observation and value-label models do as well. Their
serialized forms use stable storage/type spellings, and every 64-bit integer is
encoded as a decimal string so JavaScript can consume it without precision
loss.

Native R bindings live in `r-package/dtaparser`; display/date conversion is an
R-wrapper concern while the core preserves the original format metadata.
Releases 105, 108, 110, and 111 use the historical system-missing-only
semantics; releases 105, 108, and 110 also use the pre-111 storage-code family.

From the repository root, `scripts/conformance.sh` checks the immutable fixture
oracle and exact slice/file parity, including projections, row windows, `strL`,
value labels, missing tags, legacy layouts, big-endian v119, and representative
rejection errors. `cargo test -p dta-parser --locked --test fuzz_smoke -- --nocapture`
runs deterministic, bounded, fixture-seeded mutations without
nightly Rust or network access. Report-only
metadata/full/projected/bounded-file/wide/`strL`/legacy measurements are
available with `cargo run --release -p dta-parser --example bench`; see
`benchmarks/README.md` for environment and correctness-reporting requirements.

This is the canonical Rust parser for the R package. Make parser fixes here,
add a regression, and run the repository checks; there is no mirrored
first-party source tree.

The crate uses Rust 2021 and has a minimum supported Rust version of 1.74.
