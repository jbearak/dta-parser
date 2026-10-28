# Plan: read strings into R lazily

Status: approved by Sol 6.1 and Sonnet 5.5 after two review rounds.

## Problem

The user wants `dtatools::read_dta` to read every variable of
`bench/long.dta` at least as fast as the npm package, and ideally about
5% faster: 2.04 s or less against npm's 2.15 s. Today it takes 5.5 s.

Measurements (M4 Max, R 4.6.1, warm cache, fresh processes):

| read | seconds |
|---|---|
| dtatools, all 12 variables | 5.50 |
| dtatools, `s2` only (10M distinct strings) | 4.94 |
| dtatools, all but `s2` | 0.47 |
| dtatools, `s1` only (4 distinct strings) | 0.19 |
| dtatools, `s2` again in a session whose heap had already grown | 2.28 |
| dtatools, `s2`, R started with `R_NSIZE=3e7 R_VSIZE=2e9` | 3.61 |
| npm, all 12 variables | 2.15–2.22 |
| pandas 3.0.5, all 12 variables | 2.48 |

Nearly all of the time is R making 10M CHARSXPs. Each one is hashed
into R's global string cache, and while they are made R's heap grows in
steps, with a full collection at each step. Even on a heap that has
already grown, making them costs 2.3 s, more than npm's whole read. No
eager route reaches the target.

## What the others do

- **pandas** views the row block in place as a NumPy structured array
  (`np.frombuffer`), splits it into columns, and then makes a Python
  `str` per value. CPython strings are neither interned nor traced by
  its collector, so 10M of them are cheap. R has no such string type.
- **npm** makes V8 strings, which are also neither interned nor traced
  one by one.
- **R itself** returns a lazy ("deferred") string vector from
  `as.character(1:1e7)`, which takes 0.02 s; strings are made when an
  element is first used. vroom (MIT) and arrow (Apache-2) return lazy
  character columns the same way, through ALTREP.

## Design

Every string column `read_dta` returns becomes an ALTREP character
vector whose values stay in native storage until R asks for them.

**Storage.** Two R-owned vectors in the ALTREP object's `data1` (a list):
a raw vector of the column's UTF-8 bytes, and a double vector of each
value's end offset. Being R objects, they need no finalizer, are
protected by the object that holds them, and are freed by R's collector.
For `s2` that is 90 MB plus 80 MB, against roughly 650 MB of CHARSXPs.

**Two states.** A column is *packed* while `data1` holds the bytes and
offsets, and *made* once every string exists as a CHARSXP in the cache
in `data2`; then `data1` is `R_NilValue`. Every method branches on that.

**Methods** (C, in a new `src/strings.c`, registered in
`R_init_dtatools` with `R_make_altstring_class`, written from R's
`Altrep.h`; R's deferred strings, vroom and arrow informed the design,
but no code is copied):

- `Length`: packed, the number of offsets; made, the cache's length.
- `Elt(i)`: made, the cache's element. Packed, the cached CHARSXP if
  the slot is not `NA_STRING`, else `mkCharLenCE(bytes, len, CE_UTF8)`,
  stored in the slot at once. The cache is allocated on the first
  `Elt` (or `Dataptr`), attached to `data2` before any CHARSXP is made,
  and filled with `NA_STRING`, which marks "not made yet" only while
  packed: Stata strings are never NA. A made column may hold NAs a
  user assigned; they are never mistaken for gaps.
- `Dataptr`: fill the gaps in the cache, then set `data1` to
  `R_NilValue`, then return the cache's data pointer. Clearing `data1`
  last leaves the object consistent if an allocation fails midway.
- `Dataptr_or_null`: made, the cache's pointer; packed, NULL, so code
  that can work element by element does.
- `Set_elt`: `Dataptr` first, then set the element in the cache.
- `No_NA`: true while packed, false once made (R's deferred strings use
  the same rule), so a NA written through a writable pointer is never
  hidden from `anyNA`.
- `Duplicate`: packed, a new packed vector over the same `data1` (never
  modified) with no cache, so copying a shared column (setting an
  attribute on it, `structure()`) stays cheap; made, NULL, so R copies
  it as a plain vector.
- No `Serialized_state`: `saveRDS` writes an ordinary character vector,
  element by element, so a saved file never needs dtatools to load.
  While it runs the packed bytes and the filling cache coexist.

An internal `.Call` reports a column's state (packed with how many
strings made, made, or not ours) for the tests.

The ALTREP methods are C and run only when R calls them, never under a
Rust frame, so an R error in them cannot cross Rust.

**Read path** (`src/rust/lib.rs`). Numeric columns are unchanged. For a
string column, `read_chunks`' bytes and end offsets are appended to two
Rust vectors as chunks arrive; a NUL anywhere is an error at read time,
as `mkCharLenCE` makes it today. After the last chunk the vectors are
copied into a new raw and double vector, the lazy object is made by a C
shim under `R_UnwindProtect` like the existing ones, its attributes are
set, and it is stored in the result list. `set_strings` stays for
metadata.

**Not changed:** the npm package, the Rust core, `save_dta` (which reads
a lazy column through `STRING_PTR_RO` and so makes its strings; a fast
path that writes the packed bytes directly is a follow-up, if a
workload needs it), and every R function above the bridge.

## Costs and risks

- **The string cost is deferred, not removed.** Meeting the target on
  `full` means R gets back packed columns faster than npm returns made
  strings. That is a different reading of "full read" from the one the
  other tools are timed by, and the results say so beside every `full`
  number.
- The string cost, once more: A full pass over `s2`
  (`s2 == "x"`, `unique`, `match`, `nchar`, sorting, or anything that
  takes `STRING_PTR_RO`, including some vctrs operations) makes all
  10M strings then, at about the cost the read pays today. Looking at a
  few rows, filtering on numeric columns and selecting columns stay
  cheap: subsetting a packed vector makes only the strings it keeps,
  and the source stays packed. The first `Elt` on a column does
  allocate its cache (80 MB for 10M rows).
- Until `Dataptr` runs, packed bytes and the partly filled cache coexist
  (for `s2`, 170 MB plus up to about 650 MB); after it, only the cache
  remains.
- The read copies the Rust vectors into R vectors at the end, a
  transient second 170 MB for `s2`. R cannot shrink a vector in place,
  so allocating the raw vector at an upper bound would not save it.
- ALTREP's API is marked experimental in R's headers; vroom, arrow and
  R's own deferred strings depend on it, and dtatools already requires
  R 4.2.
- Values, encoding (UTF-8 marked), empty strings and attributes must be
  identical to today's; the existing compat and fertility_surveys tests
  check this.

## Measurement

`bench/read_case.R`, `.py` and `.mjs` gain a task `touch`: the full
read, then one comparison over every string column (`sum(x == "x")` in
R, `(df[c] == "x").sum()` in pandas, a loop in Node). It is timed and
reported next to `full`. Both are reported, with peak RSS, as the
median of five fresh processes. A third task, `head`, times the
full read plus `head(df)` and a filter on a numeric column, the cheap
path the design is for.

- **Target:** `full` at or under 2.04 s (5% under npm).
- **Reported without a target:** `touch`. Every tool but dtatools
  pays its string cost inside `full`, so this is the like-for-like
  number. We expect about 3–4 s, losing to npm and pandas, and the
  results state the gap.
- Also reported: `wide.dta`, 5 of 400 variables, should not regress.

## Tests

testthat, using the internal state call:

- A packed column equals the eager strings (`identical(as.character(x),
  expected)`), with UTF-8 marking, empty strings and attributes intact.
- `head(df)`, `df[df$n > 0, ]`, `vctrs::vec_slice` and `dplyr::filter`
  through the dibble leave the source packed with only the kept strings
  made.
- `length()`, `[`, `anyNA()` and `is.na()` give the right answers after
  the column is made, including after `x[1] <- NA`.
- `y <- x; y[1] <- "a"` changes `y` and leaves `x` packed and unchanged;
  setting an attribute on a shared packed column leaves it packed. The
  same assignment on a copy of a made column leaves the original
  unchanged.
- `saveRDS`/`readRDS` gives a plain character vector with equal values.
- Zero-length string columns; repeated access and making under
  `gctorture(TRUE)` on a small column; an embedded NUL fails at read.
- dplyr `mutate` and `group_by` give the same results as on a plain
  column.
- The existing compat tests and the fertility_surveys suite pass
  unchanged.

## License

The repository becomes GPL-3 (user decision): `LICENSE` holds the GPL
version 3 text, and the npm, Cargo and R package metadata say so.
`compat/fixtures/LICENSE-pandas` stays for the pandas fixtures.
