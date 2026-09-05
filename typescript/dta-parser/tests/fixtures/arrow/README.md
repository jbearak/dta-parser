# Arrow interoperability fixtures

Regenerate from the repository root:

```sh
cargo run -p dta-tools --locked --example typescript_arrow_fixtures -- typescript/dta-parser/tests/fixtures/arrow
```

The generator uses Apache Arrow Rust 59.2.0 and the canonical dtatools writer.
It reads every Arrow file back through the canonical reader with profile and
checksum verification enabled before writing it to this directory.

- `plain-*` cover every supported physical type, nulls, non-null NaN, infinities,
  signed zero, exact large integers, all temporal units, and signed dictionary
  key widths. Each file has two record batches and dictionaries with unused levels.
- `profile-*` cover every modern Stata missing code across all five storage
  types, dataset and field metadata, numbered notes, characteristics, value label
  assignment, temporal Float64 fallbacks, strL storage, and an ordered factor.
- `dictionary-delta.arrow` has an expanding dictionary across two batches.
- `empty.arrow` has a profiled empty dataset with one typed column.
- JSON oracles derive from the Rust arrays used to create the files. Special
  values use `{ "bigint": "..." }`, `{ "number": "NaN" }`, or
  `{ "missing": ".a" }` objects so no precision or missing distinctions are lost.
- `codec.*` exercise the portable codecs independently of IPC framing.
  `codec-wide-offset.zstd` expands to 96 MiB plus 256 KiB; its expected bytes are
  generated in the test. The 132 KiB compressed fixture exercises a five-byte
  offset bit field that the upstream fzstd decoder reads incorrectly.
