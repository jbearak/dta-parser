# Avoiding the cost of R strings for large string columns

Question: how do fast R packages avoid, or reduce, the cost of making
CHARSXPs for big string columns, and which of their techniques fit
dtatools (ADR 0010, `r/dtatools/src/strings.c`)?

Sources were read on 2026-10-28. R source comes from the
`wch/r-source` trunk mirror (R 4.7 devel; R 4.6.1 installed). Package
source comes from CRAN tarballs: arrow 26.0.0, vroom 1.7.1, stringfish
0.19.2, data.table 1.18.6.1, collapse 2.1.8, duckdb 2.0.0, kit 0.0.21,
fastmatch 1.1-8, qs 0.27.3 (archive), qs2 0.3.1, fst 0.9.8, fstcore
0.10.0, cheapr 1.5.2, vctrs 0.7.3 and nanoarrow 0.9.0. polars comes
from the r-polars GitHub `main` branch (2.0.0.9000). Paths are relative
to each package's root.

## What R itself forces

- **Every CHARSXP goes through the global cache.** `mkCharLenCE`
  hashes the bytes with djb2, walks a chain and, on a miss, allocates
  and links a new node (`src/main/envir.c:4743-4846`). The table starts
  at 65,536 buckets. It doubles at a load factor of 0.85, and each
  doubling rehashes every cached string from its bytes
  (`envir.c:4598-4661`, `481-496`). It never shrinks.
- **No API makes an uncached CHARSXP.** `allocVector(CHARSXP, …)` is
  defunct (`src/main/memory.c:2759`). `allocCharsxp` is
  `attribute_hidden` (`memory.c:2995`). `SET_STRING_ELT` accepts only
  CHARSXPs (`memory.c:4300`). R Internals says that uncached CHARSXPs
  "should never happen in end-user code", and that uncached creation
  was removed in R 2.8/2.9
  ([R-ints, "The CHARSXP cache"](https://cran.r-project.org/doc/manuals/r-devel/R-ints.html)).
- **Base R depends on interning.** `Seql` treats two cached strings
  with different addresses as unequal (`memory.c:5009-5017`). `unique`
  and `match` hash the pointer (`src/main/unique.c:194-236`) and fall
  back when a string is uncached, a case the source calls "not properly
  supported" (`unique.c:578-583`). An uncached string would break these
  fast paths even if one could be made.
- **The cache is weak.** The collector drops unmarked CHARSXPs from
  the chains (`memory.c:1880-1906`). It still marks every live CHARSXP,
  one node per distinct string.
- **ALTSTRING exposes only `Elt`, `Set_elt`, `Is_sorted`, `No_NA`,
  `Dataptr` and `Extract_subset`** (`R_ext/Altrep.h:113-170`). There
  is no ALTREP hook for `==`, `match`, `unique` or `order`.
  `==` calls `STRING_ELT` per element (`src/main/relop.c:566`), and
  radix `order` takes `DATAPTR` (`src/main/radixsort.c:1627`).
- **`match`/`%in%` on a classed vector calls the S3 generic `mtfrm`**
  (`unique.c:1304`), but `mtfrm` must return something `match` can
  compare with the other side, in practice a character vector.
- **R's own deferred strings** (`as.character(1:n)`) use the same
  design as dtatools: `Elt` makes and caches one string, and `Dataptr`
  expands all of them (`src/main/altclasses.c:602-794`).

Measured here with a plain C loop and no dtatools code (10M rows,
random order, `s%09d` strings, macOS M4 Max):

| case | s |
|---|---|
| format the strings only | 0.34 |
| 10M distinct, fresh session | 6.12 |
| 10M distinct again, table already grown | 4.46 |
| full `gc()` with them alive | 0.30 |
| 1M distinct, `mkChar` per row | 1.39 |
| 1M distinct, `mkChar` per distinct + pointer copy per row | 0.21 |
| 300 distinct, `mkChar` per row | 0.48 |
| 300 distinct, `mkChar` per distinct + pointer copy per row | 0.03 |

Most of the cost is chain misses and allocation. Growing the table and
the heap adds about another 1.7 s the first time. Nothing in the API
lets a package pre-size either.

## Survey

| package | storage | CHARSXPs made | without CHARSXPs | back to R | license vs GPL-3.0-only | maturity |
|---|---|---|---|---|---|---|
| R deferred strings | source vector | per `Elt`; all on `Dataptr` | nothing | lazy STRSXP | n/a | base R |
| vroom | index into mmapped file | per `Elt`; all on `Dataptr` (`src/vroom_chr.h:76-105`) | slicing, via `Extract_subset` (`src/vroom_vec.h:179`) | lazy STRSXP | MIT, compatible | CRAN 2026-03 |
| arrow | Arrow ChunkedArray (bytes + offsets) | per `Elt`; all on `Dataptr` (`src/altrep.cpp:861-930`) | all dplyr verbs on Table/Dataset run in Acero; an unmaterialized vector goes back to Arrow with no CHARSXPs (`altrep.cpp:1086`) | `collect()` (`R/dplyr-collect.R:20-33`); dictionary arrays become factors (`altrep.cpp:420-508`) | Apache-2.0, compatible (one way) | CRAN 2026-10 |
| nanoarrow | Arrow C data | ALTREP for large string arrays (`src/altrep.c:31-37`) | none in R; hands streams to arrow (`R/pkg-arrow.R:91-99`), duckdb, polars | `convert_array` | Apache-2.0, compatible | CRAN 2026-08 |
| stringfish | `std::vector<sfstring>` or slab "slice store" (`inst/include/sf_internal/slice_store.h`) | per `Elt`, not kept (made again on each call); all on `Dataptr` (`src/sf_altrep/slice_st_altrep.h:91-110`) | `sf_compare`, `sf_match`, `sf_grepl`, `sf_gsub`, `sf_nchar`, `sf_substr`, `sf_split`… (README.md:50-70), read through `RStringIndexer` (`inst/include/rstring_indexer.h:23-131`); slicing (README.md:95-96) | sf ALTREP vector | GPL-3, compatible | CRAN 2026-08 |
| qs / qs2 | serialized | qs: optional stringfish ALTREP on read (`R/RcppExports.R:88`); qs2: eager `mkCharLenCE` (`src/qd_deserializer.h:515`); ALTREP "temporarily disabled" (ChangeLog:22) | none | STRSXP | GPL-3, compatible | qs archived on CRAN (reason not checked); qs2 CRAN 2026-08 |
| data.table | plain STRSXP | eagerly in `fread` (`src/freadR.c:612`) | none; it *exploits* interning: pointer-keyed hash (`src/hash.c`), sorting only unique strings (`src/forder.c:300-330`, `284`) | STRSXP | MPL-2.0, compatible (no Exhibit B notice found) | CRAN 2026-08 |
| collapse, kit | plain STRSXP | n/a | none; pointer hashing over `STRING_PTR_RO` (collapse `src/kit_dup.c:198-210`, from kit; kit `src/dup.c:675`) | STRSXP | GPL-2+ / GPL-3, compatible | CRAN 2026-08 / 2026-01 |
| fastmatch | plain STRSXP | n/a | none; pointer hash cached as an attribute (`src/fastmatch.c:83,299-329`) | integer | **GPL-2 only: do not copy code** | CRAN 2026-01 |
| vctrs (dplyr) | plain STRSXP | n/a | none; pointer hash (`src/hash.h:99-101`) over `STRING_PTR_RO` (`src/rlang/vec.h:56`), so `Dataptr`; but `vec_slice` on ALTREP calls `.subset` → `Extract_subset` (`R/slice.R:222-240`) | n/a | MIT, compatible | CRAN 2026-04 |
| duckdb | DuckDB vectors | eagerly on result fetch (`src/transform.cpp:375-385`); duckplyr's lazy frames materialize a whole column on first `Elt` (`src/reltoaltrep.cpp:231,660-664`); scanning an R data frame takes `DATAPTR_RO`, which materializes ALTREP strings (`src/scan.cpp:120-141`) | everything inside SQL/duckplyr | STRSXP at collect | MIT, compatible | CRAN 2026-10 |
| polars | Rust/Arrow `StringChunked` | eagerly at `as.data.frame`/`as.vector` (`src/rust/src/conversion/chunked_array.rs:102-115`) | everything in the polars API | STRSXP | MIT, compatible | not on CRAN; R-multiverse/r-universe (README.md:40-60) |
| fst | compressed blocks | eagerly per element (fstcore `src/fst_blockrunner_char.cpp:147-269`) | none | STRSXP | fst **AGPL-3** (GPL-3 §13 lets GPL-3 code combine with it, but the AGPL terms stay on fst's part); fstcore MPL-2.0 | fst last on CRAN 2022-02 |
| cheapr | plain vectors | n/a | no string-specific technique found | n/a | MIT | CRAN 2026-06 |

So no surveyed package avoids the cache once a base character vector
must exist. They fall into three groups:

1. **Defer** (R, vroom, arrow, nanoarrow, stringfish, dtatools): lazy
   `Elt`, full cost on `Dataptr`.
2. **Do the work elsewhere** (stringfish's `sf_*`, arrow/Acero,
   duckdb, polars): operations run on bytes, and CHARSXPs are made only
   for results brought back into R.
3. **Exploit interning** (data.table, collapse, kit, fastmatch,
   vctrs): once the strings exist, hash pointers and sort only the
   distinct strings. This cuts the cost of the *operation*, not of
   making the strings.

I did not check polars' and duckdb's internal string kernels beyond
the conversion code, or why qs was archived.

## Recommendations for dtatools, ranked

**1. Work on packed bytes in dtatools' own functions (a).** Cost: low
to medium. Risk: low.
When every character argument is still packed (`dtatools_packed_state`
≥ 0), `dta_group_id`, `dta_group_tag`, `tab`, `dta_setequal` and
`dta_setdiff` should hash and sort `bytes`/`ends` in Rust and return
integers or logicals. They should make CHARSXPs only for results that
are strings (`tab` names, `dta_setdiff` values: one per distinct value
returned). This is the same move as arrow's bypass and stringfish's
`RStringIndexer`. Comparing bytes matches R's radix `order` on UTF-8
strings, which sorts in C locale. A made column falls back to today's R
code. Today `dta_group_id` calls radix `order`, which takes `Dataptr`,
makes every string and drops the bytes.

**2. Implement `Extract_subset`.** Cost: low. Risk: low. Return a
packed (or, with 3, coded) subset. `x[i]`, `head` and dplyr `filter`/
`slice`, which reach `.subset` through `vec_slice_altrep`, then make no
strings, and the result stays eligible for 1. vroom and stringfish do
this.

**3. Dictionary-encode in Rust, adaptively (b).** Cost: medium. Risk:
low. While reading, hash each column's values in Rust and keep
`dict_bytes`/`dict_ends` plus int32 codes. Give up and fall back to
plain packed storage once the number of distinct values passes about
half the rows. `Elt` makes and caches one CHARSXP per *code*, and
`Dataptr` copies pointers. The measurements above show 0.48 → 0.03 s at
300 distinct values and 1.39 → 0.21 s at 1M. After that, base `==`,
`%in%`, `unique`, `order`, `table` and dplyr `group_by`, all pointer
hashes, are as cheap as on any interned vector. Codes also make 1
trivial: group on integers. It does nothing for 10M distinct values.

**4. Offer an Arrow export for users who want to stay out of R (d).**
Cost: medium. Risk: low as an option, high as a default.
dtatools' packed column is almost Arrow's `large_utf8` layout (an int64
offset array that starts at 0, plus bytes). From Rust, export an
`ArrowArrayStream` through the C Data Interface and wrap it with
nanoarrow (Apache-2.0, a light Suggests). Users then pass it to
`arrow::as_arrow_table`, `duckdb_register_arrow`
(`duckdb/R/register.R:83`) or `polars::as_polars_series`
(`R/as_polars_series.R:467`) without making a single CHARSXP, and pay
only at `collect()`. The cost for users is a different API
(arrow/duckplyr/polars verbs, not base R or the dibble). It should not
replace `read_dta`'s dibble. Passing the *dibble* to duckdb would
materialize every string (`scan.cpp:131`).

**5. A classed string vector (c): no, by default.** A classed STRSXP
stays `is.character`, and `Ops.<class>` could catch `x == "a"`. But
`%in%` goes through `mtfrm`, which must return comparable strings.
vctrs equality and order proxies cannot use per-column codes, because
codes from different columns are not comparable. Many functions also
`unclass`. ADR 0010 already rejected this. The gain over 1+3 is only
scalar `==` on high-cardinality columns.

**6. Ruled out (e).**
- Uncached or "fake" CHARSXPs: no API, and base R would misbehave (see
  above).
- Making strings in hash order: already measured in ADR 0010, and it
  makes later collections slower.
- Pre-sizing `R_StringHash` or the heap: no API.
- Making strings from several threads: `mkCharLenCE` touches the
  global table and allocator and is not thread-safe.

## What cannot be avoided

If a user runs a base or dplyr operation that reads every value of a
plain character vector with *n* distinct values, R makes *n* cached
CHARSXPs. That costs about 0.45 µs per distinct string here (4.5–6 s
for 10M). It is paid once per session per column, after which those
operations are fast. dtatools can shrink *n* (dictionary), avoid the
pass in its own functions (packed kernels), avoid it for slicing
(`Extract_subset`), or let the data stay in Arrow, but no correct
package can make base R compare 10M distinct strings without interning
them.
