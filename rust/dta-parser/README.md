# dta-parser (Rust)

This crate is the native Rust core for `dta-parser`. Its initial API parses
metadata from Stata 117, 118, and 119 files without decoding observations:

```rust,no_run
use dta_parser::parse_metadata;

let bytes = std::fs::read("data.dta")?;
let metadata = parse_metadata(&bytes)?;
println!("{} variables", metadata.nvar);
# Ok::<(), Box<dyn std::error::Error>>(())
```

`DtaMetadata` and its nested types implement `serde::Serialize` and
`serde::Deserialize`. Their serialized form is the canonical cross-language
metadata representation: enum values use the TypeScript spellings, and every
64-bit integer is encoded as a decimal string so JavaScript can consume it
without precision loss.

The parser currently supports metadata for releases 117–119 only. Releases
113–115 are represented by `FormatVersion` for the shared model but return a
typed unsupported-version error. Observation data, value-label payloads,
`strL` payloads, and R bindings are deliberately outside this foundation.

The crate uses Rust 2021 and has a minimum supported Rust version of 1.74.
