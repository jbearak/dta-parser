# dta-parser (Rust)

This crate is the native Rust core for `dta-parser`. It parses metadata,
numeric and fixed-string observations, and value labels from Stata 117, 118,
and 119 files into a column-oriented model:

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
`strL` variables are projected out; it does not inspect or resolve GSO payloads.

Numeric `ColumnValues` variants preserve the source storage width (`i8`,
`i16`, `i32`, `f32`, or `f64`) and carry a parallel
`Vec<Option<MissingTag>>`. Raw Stata missing values remain in the values vector,
so consumers retain both exact storage and the classified `.`, `.a`–`.z` tag.
Fixed strings are UTF-8 decoded with replacement for malformed sequences and
stop at the first NUL byte, matching the TypeScript parser.

Value-label tables retain their on-disk order and require the modern format's
strictly ascending integer keys. Declared lengths, text offsets, NUL
terminators, wrapper tags, and mapped section boundaries are validated before
the tables are returned.

`DtaMetadata` and its nested types implement `serde::Serialize` and
`serde::Deserialize`; the observation and value-label models do as well. Their
serialized forms use stable storage/type spellings, and every 64-bit integer is
encoded as a decimal string so JavaScript can consume it without precision
loss.

The parser currently supports releases 117–119 only. Releases 113–115 are
represented by `FormatVersion` for the shared model but return a typed
unsupported-version error. Selecting a `strL` variable likewise returns a typed
unsupported-column error; project those columns out until GSO resolution is
available. Legacy parsing, native R bindings, file-backed bounded-buffer APIs,
fuzzing, and benchmarks remain separate feature slices.

The crate uses Rust 2021 and has a minimum supported Rust version of 1.74.
