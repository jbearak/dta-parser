# Plan: dictionary-encode string columns in R

Status: approved by Sol 6.1 and Sonnet 5.5 after three review rounds.

## Problem

ADR 0010 made `read_dta` return string columns packed, so reading is
fast. But the first full pass over a column (`==`, `unique`, `table`,
`order`, and so `tab` and `dta_group_id`) still makes one R string per
row. Every R string is inserted into R's global string cache, and
nothing in R's API avoids that (`docs/research/r-string-cost.md`). The
user asked for a way not to pay that cost from inside R, and whether
the research's strategies 1–3 are more work for less benefit than
strategy 4 (an Arrow export).

## The workload

Survey files hold many rows and string columns with few distinct
values: country, survey, region, answer text. The typical operation
groups or tabulates such a column. A synthetic stand-in, used for every
number below: 15M rows, a string column of 300 distinct values in
random order, and a `dta_num` column of 5 values plus `.`.

Measured on R vectors already made (so without any read):

| operation | seconds |
|---|---|
| `dta_group_id(s, a, missing = TRUE)` on the strings | 1.33 |
| the same with `s` replaced by integer codes | 1.09 |
| `tab(s)` | 0.34 |

And on 10M rows of 300 values (from the research note), making the
strings costs 0.48 s one per row, against 0.03 s one per distinct value
plus a pointer copy per row.

## Assessment of the strategies

- **3, dictionary encoding**, makes R strings once per distinct value
  and copies pointers for the rest. After that, base R's `unique`,
  `match`, `table` and radix `order` are as fast as on any R strings,
  so `tab`, `dta_group_id`, `dta_setdiff`, dplyr and base R all
  benefit with no change to any R function. Packed memory also falls to
  4 bytes per row plus the distinct values. Cost: a hash per row at
  read time and a second state in `strings.c`. Nothing for columns of
  mostly distinct values.
- **1, kernels on packed bytes.** In full (hashing and sorting bytes in
  Rust for any column) it is the most code and not needed. But with 3 a
  cheap form comes almost free, and it is in scope: for a dictionary
  column, `tab` counts codes with `tabulate` and sorts only the distinct
  values; `dta_group_id` (and so `dta_group_tag`) groups on each row's
  rank among the distinct values; `is_missing` tests the distinct values.
  On a fresh read these otherwise reach every row's string through
  ALTREP one at a time; measured on the workload file, `tab` falls from
  1.0 s to 0.02 s and `dta_group_id` from 1.2–1.9 s to 0.9–1.1 s, with
  identical results. Other columns take today's code.
- **2, `Extract_subset`.** With 3, `Elt` is a pointer lookup, so slicing
  is already cheap. Little gain; not now.
- **4, an Arrow export**, avoids R strings entirely, but only for users
  who work in arrow, duckdb or polars instead of base R and the dibble;
  the workload above gains nothing. It needs the Arrow C data interface
  in Rust (release callbacks, missing codes as nulls, metadata) and a
  nanoarrow dependency: a speculative feature. Not now.

So 3, with the cheap form of 1 it enables, is less work and more benefit
for this workload. Full 1, 2 and 4 stay in the research note as
follow-ups.

**Why at read, not lazily on first `Dataptr`:** building the dictionary
when the column is first made would leave the read untouched, but (a)
`==`, `nchar` and `is_missing` reach values through `Elt`, one row at a
time, so they would still make a string per row; (b) the memory saving
would be lost. The read pays a hash per row instead, kept small by a
direct-mapped front cache of recent values. The benchmark gates on
read time as well as first use.

## Design

**Building the dictionary** (in the R bridge, `src/rust/lib.rs`; the
core is unchanged). Per string column, while reading:

- `dict_bytes`, `dict_ends`: the distinct values in order of first
  appearance.
- `codes`: one `i32` per row.
- A lookup table keyed by index, not by text: a `HashMap<u64, u32>` (with a pass-through hasher, the key being a hash already)
  from a value's hash to the newest entry with that hash, plus a
  `next: Vec<u32>` chaining older entries with the same hash. Lookup
  hashes the value, walks the chain comparing bytes against
  `dict_bytes`. No text is stored twice and nothing borrows from a
  growing buffer.
- The hash is the writer's multiply-rotate word hash, copied into the
  bridge (it is a dozen lines; the core's stays private). A 4,096-slot
  front cache, indexed by its top bits after a multiply, holds recent
  values' indices, so most rows of a low-cardinality column skip the
  table; the table's key is the hash with MurmurHash3's final mix. A crafted file could make many values collide; a chain
  walk longer than 32 makes the column give up, so the work stays
  linear.

A column **gives up** (writes its rows so far out as plain bytes and
ends from the dictionary and codes, frees the dictionary, and stays
plain for the rest of the read) when, on adding a new distinct value:

- at least `WINDOW` rows (65,536) have been seen and the dictionary
  holds more than half of them; or
- the dictionary would exceed `LIMIT` entries (`i32::MAX`); or
- a chain walk is too long.

The rule is checked per new value, not per chunk, so it does not depend
on how many rows a chunk holds. A column with mostly distinct values
gives up after `WINDOW` rows; a column that starts distinct and repeats
later may give up early and is then plain, which is still correct.
`WINDOW` and `LIMIT` can be lowered by two environment variables read
at the start of each read, for tests only (`DTATOOLS_DICT_WINDOW`,
`DTATOOLS_DICT_LIMIT`).

Memory: dictionary text never exceeds the plain text it replaces; the
table adds about 16 bytes (more with its load factor) and the chain 4 bytes per distinct value; codes
are 4 bytes per row. A late give-up briefly holds dictionary, codes and
the new plain text together. The table is dropped before the R vectors
are made, and the Rust vectors are copied into R vectors at the end, as
today. The benchmark reports peak RSS.

**ALTREP** (`src/strings.c`, `init.c`). `dtatools_new_packed` gains a
row count and makes `data1 = list(bytes, ends, codes)`, with `codes`
R_NilValue for a plain column or an integer vector of 0-based codes.

- `Length`: `codes`' length if present, else `ends`' (packed);
  `data2`'s (made).
- The cache in `data2` has one slot per dictionary entry (one per row
  for a plain column), `NA_STRING` until made, as today.
- `Elt(i)`: made, the full vector's element; packed, the cache's string
  for slot `codes[i]` (or `i`), made if need be.
- `Dataptr`: make every slot of the cache; for a dictionary column,
  allocate the full character vector (protected), fill it with pointers
  from the cache, and store it in `data2`; then set `data1` to
  `R_NilValue`.
- `Duplicate`, `No_NA`, `Dataptr_or_null`, `Set_elt`, serialization:
  today's rules. `codes` is never modified, so a packed copy may share
  it.
- The tests' state call reports -2 (not ours), -1 (made), or for a
  packed column the number of cache slots made, plus whether it has a
  dictionary.
- An internal call returns a dictionary column's distinct values (made,
  a copy of the cache) and its codes (the column's own vector, marked
  not mutable), or NULL for any other vector; `tab`, `dta_group_id`
  and `is_missing` use it.

**Not changed:** the npm package, the Rust core, `save_dta`, and every R
function but `tab`, `dta_group_id` and `is_missing`.

## Measurement

`bench/group_case.R` gains a fresh-read case, comparing dtatools before
(main) and after on a file `bench/make_large.R` writes with the
workload above (15M rows, 300 values; plus `long.dta` as today):

- read alone; read then `dta_group_id`; read then `tab`; the second
  call of each; peak RSS of each, in fresh processes, median of five;
- `long.dta`'s `full`, `touch` and `head` through `bench/read.sh`, for
  the give-up overhead on 10M distinct values (`s2`) and the gain on 4
  (`s1`).

Gate: read-then-first-use faster than today on the workload file; read
alone and `long.dta`'s `full` no more than 10% slower. (Measured while
building: dictionary building cost about 6 ns per row before the front
cache and is within run-to-run noise after it.)

The downstream suite must pass; it is a pass/fail check, not a source
of numbers.

## Tests

testthat, with the two environment variables lowered where needed so
every case is small:

- A dictionary column equals the plain strings: empty strings,
  non-ASCII UTF-8, a release-115 file in Windows-1252, a strL column;
  attributes intact; state shows a dictionary.
- Zero rows, and a column of only empty strings: a dictionary of one
  entry (or none for zero rows), values correct.
- Repeated rows share one cache slot (making row 1 makes its repeats).
- A mostly distinct column comes back plain; one that turns distinct
  after the window gives up mid-chunk and still equals the input; one
  over the lowered `LIMIT` gives up.
- Assigning into one row of a dictionary column changes only that row;
  a copy taken before stays packed and unchanged, as does the original
  when the copy is made.
- `Dataptr` under `gctorture` after some rows were made through `Elt`.
- `saveRDS`/`readRDS` gives a plain character vector.
- dplyr `filter`, `mutate`, `group_by` agree with plain columns.
- `tab` (with and without `missing`), `dta_group_id`, `dta_group_tag`
  and `is_missing` give identical results on dictionary and plain
  columns, including empty strings, non-ASCII values and values that
  sort differently by locale and by bytes; the column stays packed.
- The existing tests, compat tests and the downstream suite pass.
