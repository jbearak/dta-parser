# The writer writes release 118 only, in one streaming pass

You chose release 118, like haven's default, and asked for writes that
are faster than haven's and use less memory. A dataset release 118
cannot hold (more than 32,767 variables, or a value outside its declared
storage type) is an error, never a silent change.

The writer pulls values a row at a time from functions the caller gives
it, so R hands over its vectors without copying them. A first pass checks
every value against its storage type and sizes strings and strLs. Every
section's size is then known, so the map is written first with its final
offsets, and rows are built into an 8 MiB buffer at a time. As haven does,
identical strLs in a variable share one entry. A table of the distinct
texts (borrowed from the caller, hashed eight bytes at a time) finds
them. A small cache keyed by address skips rehashing the texts R hands
over repeatedly at one address. The benchmarks in `bench/RESULTS.md` show
dtatools faster than haven in every case, with 0–9 MB of memory over the
data, where haven uses 9–668 MB.

## Considered options

- **Release 119 for wide data, or 120/121.** You chose 118. haven and
  pandas cannot read 120 or 121.
- **One entry per strL, without sharing.** It is simpler, but files with
  repeated long texts grow by the repeated bytes, and haven shares them.
- **Storing each row's strL index.** That costs 8 bytes per row per strL
  column (121 MB at 15M rows). The table of distinct texts costs nothing
  per row.

## Consequences

In npm, columns are copied into wasm memory before writing, so a write
there holds the data twice. No TypeScript tool writes, so that is
accepted for 1.0.
