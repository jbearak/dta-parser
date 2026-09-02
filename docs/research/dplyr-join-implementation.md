# dplyr join implementation and `dta_merge()` parity

Research date: 2026-08-28

## Scope and source pins

The comparison machine has dplyr 1.2.1 and vctrs 0.7.3 installed. Their official source tags resolve to these commits:

- dplyr 1.2.1: [`95740975c465c29cdb2abdfa13effddb948444dc`](https://github.com/tidyverse/dplyr/tree/95740975c465c29cdb2abdfa13effddb948444dc). The package declares version 1.2.1, an MIT license, and vctrs 0.7.1 or newer as a dependency in its [`DESCRIPTION`](https://github.com/tidyverse/dplyr/blob/95740975c465c29cdb2abdfa13effddb948444dc/DESCRIPTION#L1-L37).
- vctrs 0.7.3: [`d452a02c9f4752f3268431a3ac8aa221dbe4040f`](https://github.com/r-lib/vctrs/tree/d452a02c9f4752f3268431a3ac8aa221dbe4040f). Its [`DESCRIPTION`](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/DESCRIPTION#L1-L25) declares version 0.7.3 and an MIT license.
- dtatools checkpoint: `21a06a28f6e4d7ca5f75646f10ac6b2cfcd133c2`.

I used only those tagged repositories, their official license files, the installed packages, and the dtatools checkpoint.

## Short answer

dplyr does not have a separate fast join matcher for data frames. It delegates row matching to `vctrs::vec_locate_matches()`, the same function that `dta_merge()` already calls. Copying dplyr's matching code would add maintenance and licensing work without changing the algorithm.

The useful idea is in column assembly. dplyr slices all output columns from `x` in one data-frame `vec_slice()` call and all output columns from `y` in a second call. vctrs validates each row index once per data frame, then loops over its columns in C with an unchecked internal slicer. The checkpoint's ordinary-column path crossed the R-to-native boundary once per column and repeated index validation, proxy lookup, and restoration each time.

A scratch override that batched ordinary columns through one data-frame `vec_slice()` per side closed the measured standard-R gap. The nine-iteration medians were 0.1015 seconds for `dta_merge()` and 0.1024 seconds for dplyr. This did not change matching or copy dplyr source.

## Execution path in dplyr

### `join_by()` only builds a specification

`join_by(caseid)` captures and parses expressions, then stores the left names, right names, conditions, and filters in a `dplyr_join_by` object. It does no row matching. See [`R/join-by.R`](https://github.com/tidyverse/dplyr/blob/95740975c465c29cdb2abdfa13effddb948444dc/R/join-by.R#L224-L268).

### `full_join()` enters `join_mutate()`

`full_join.data.frame()` dispatches to `join_mutate(type = "full")`. See [`R/join.R`](https://github.com/tidyverse/dplyr/blob/95740975c465c29cdb2abdfa13effddb948444dc/R/join.R#L389-L430).

`join_mutate()` then:

1. Resolves output and key column locations.
2. Makes shallow tibble views of the inputs.
3. Selects the key frames and casts them to a common type.
4. Calls `join_rows()` for the two row-location vectors.
5. Selects the output columns from each input.
6. Slices the entire `x` output frame once and the entire `y` output frame once.
7. Replaces only the coalesced equality keys in right-only or full-join rows.

The two assembly calls are explicit at [`R/join.R` lines 768 through 798](https://github.com/tidyverse/dplyr/blob/95740975c465c29cdb2abdfa13effddb948444dc/R/join.R#L768-L798). dplyr assigns the sliced `y` columns into the result list. It does not row-bind or assign one column at a time.

Overlapping non-key columns get suffixes. `join_cols()` retains both sides and drops the `y` equality key by default, as shown in [`R/join-cols.R`](https://github.com/tidyverse/dplyr/blob/95740975c465c29cdb2abdfa13effddb948444dc/R/join-cols.R#L27-L79). That differs from Stata's master-wins coalescing rule. On the synthetic fixture, dplyr returns 260 columns and `dta_merge()` returns 201, including `_merge`.

### Matching is a vctrs call

`join_rows()` translates full-join policy into `incomplete`, `no_match`, and `remaining` actions, then `dplyr_locate_matches()` calls `vctrs::vec_locate_matches()`. See [`R/join-rows.R`](https://github.com/tidyverse/dplyr/blob/95740975c465c29cdb2abdfa13effddb948444dc/R/join-rows.R#L1-L108).

The public vctrs R function is only an argument-checking wrapper around one `.Call`, [`ffi_locate_matches`](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/R/match.R#L300-L336). The native implementation:

- Finds a common type and casts both key frames.
- Detects incomplete values by key column.
- Replaces each key column with joint integer ranks.
- Orders the needle and haystack frames.
- Records compact match runs, then expands them into the final integer `needles` and `haystack` vectors.
- Tracks matched haystack rows and appends unmatched haystack rows for a full join.

Those stages appear in [`src/match.c` lines 148 through 255](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/src/match.c#L148-L255), [`src/match.c` lines 283 through 481](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/src/match.c#L283-L481), and the full-join remainder append at [`src/match.c` lines 2154 through 2207](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/src/match.c#L2154-L2207).

The joint transform computes dense integer ranks without concatenating both inputs. It orders each side, merges their sorted groups, and writes equal values with the same rank. See [`src/match-joint.c`](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/src/match-joint.c#L50-L195). The official algorithm note describes the next stage as sorting both inputs, taking a midpoint needle, locating its lower and upper duplicates with binary search, and recursing on the left and right ranges. See the [vctrs matching algorithm note](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/man/faq/internal/matches-algorithm.Rmd#L22-L32). vctrs itself says the algorithm was inspired by data.table's binary merge procedure in its [`NEWS`](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/NEWS.md#L501-L511).

`dta_merge()` already gets this row plan from `vec_locate_matches(remaining = NA_integer_)`. Its custom work before that call preserves the identities of Stata's 27 missing codes. Its custom work after that call enforces Stata's merge relationship over unmatched duplicate keys and assembles master-wins columns.

## Why dplyr wins on ordinary columns

vctrs validates the subscript at the outer `vec_slice()` call. For a data frame, it then allocates one output list and calls `vec_slice_unsafe()` for each column from C. See [`vec_slice_opts()`](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/src/slice.c#L434-L460) and [`df_slice()`](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/src/slice.c#L171-L204).

Bare logical, integer, double, complex, raw, and character columns then use tight native allocation-and-copy loops. Missing row locations become the type's missing value inside the same loop. See the slice macros and dispatch in [`src/slice.c`](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/src/slice.c#L6-L88) and [`src/slice.c` lines 258 through 270](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/src/slice.c#L258-L270).

At the checkpoint, the then-named `.stata_merge_slice_columns()` sent compact Stata columns through its native batch gather but looped over every other column and called `.stata_merge_slice()`. The fallback in turn called `vctrs::vec_slice(value, rows)` for one vector. See the pinned checkpoint's [`R/stata-merge.R` slicing helper](https://github.com/jbearak/dta-tools/blob/21a06a28f6e4d7ca5f75646f10ac6b2cfcd133c2/r-package/dtatools/R/stata-merge.R#L461-L474) and [column loop](https://github.com/jbearak/dta-tools/blob/21a06a28f6e4d7ca5f75646f10ac6b2cfcd133c2/r-package/dtatools/R/stata-merge.R#L476-L510). This repeated work that dplyr paid twice, once per input frame.

The profiler confirms the source reading. Over 20 joins of the standard synthetic fixture:

| Path | Total sampled time | Time in `vec_slice` | Share |
|---|---:|---:|---:|
| `dta_merge()` | 1.327 s | 1.040 s | 78.4% |
| dplyr `full_join()` | 0.900 s | 0.647 s | 71.9% |

The profiler is intrusive, so these are attribution figures rather than publishable benchmark times. The matching calls were 0.231 seconds for `dta_merge()` and 0.248 seconds for dplyr over the same 20 iterations. Matching is not the cause of the gap.

The ordinary-column batching prototype kept the checkpoint's matcher, relationship checks, overlap coalescing, metadata warnings, and `_merge` construction. It changed only the noncompact branch of the column slicer to slice `values[ordinary]` as one data frame and scatter its columns back into the result list.

| Nine-iteration median | Unmodified | Batched prototype |
|---|---:|---:|
| `dta_merge()`, standard R | 0.1468 s | 0.1015 s |
| dplyr, standard R | 0.1019 s | 0.1024 s |

The small differences between the two dplyr medians are normal run-to-run variation. The result that matters is the removal of about 45 milliseconds from `dta_merge()` with one assembly change.

`dta_merge()` still performs work that dplyr does not:

- It coalesces 60 overlapping columns under common-type and master-wins rules. dplyr retains 120 suffixed columns.
- It verifies uniqueness among unmatched keys because vctrs relationship checks apply to matched pairs.
- It checks coalesced Stata metadata, creates the labelled compact `_merge` column, and restores dataset metadata.

These costs were visible but secondary. The checkpoint's unmatched-duplicate check took about 1.6% of sampled standard-R time. Metadata warnings took less than 0.2%.

## Why Stata classes are slower in the like-for-like run

The earlier report included fresh-process compact times and separate repeated compact medians, which made comparisons across its summaries ambiguous. I reran all three methods in one `bench::mark()` call. That same-process nine-iteration run confirms a real class cost:

| Method and input | Median | Allocated memory |
|---|---:|---:|
| `dta_merge()`, Stata classes | 0.2023 s | 1.384 GB |
| `dta_merge()`, standard R | 0.1468 s | 0.657 GB |
| dplyr, standard R | 0.1019 s | 0.742 GB |

The fixture has 61 compact byte or int columns and 138 `dta_double` columns. At the checkpoint, compact byte, int, long, and float columns used the merge-private parallel gather, while Stata doubles did not. `.stata_merge_slice()` stripped metadata with `.stata_data(x)`, subset one double column, then restored the class and attributes. See the pinned checkpoint's [`R/stata-merge.R`](https://github.com/jbearak/dta-tools/blob/21a06a28f6e4d7ca5f75646f10ac6b2cfcd133c2/r-package/dtatools/R/stata-merge.R#L461-L474), [`.stata_data()`](https://github.com/jbearak/dta-tools/blob/21a06a28f6e4d7ca5f75646f10ac6b2cfcd133c2/r-package/dtatools/R/stata-numeric.R#L306-L325), and [metadata restoration](https://github.com/jbearak/dta-tools/blob/21a06a28f6e4d7ca5f75646f10ac6b2cfcd133c2/r-package/dtatools/R/stata-numeric.R#L344-L355).

The compact fixture profile over 20 joins assigned 1.186 seconds of self time to `.stata_merge_slice()`, 0.323 seconds to `.metadata_copy()`, and 0.250 seconds to `.stata_merge_coalesce_columns()`. Matching took 0.256 seconds. Per-column double slicing and attribute handling, not compact-byte copying, dominated this fixture.

The checkpoint's native batch gather validated shared row plans once and copied independent compact columns in worker threads, but its width switch accepted only byte, int, long, and float storage. See the pinned checkpoint's [`src/init.c` gather entry](https://github.com/jbearak/dta-tools/blob/21a06a28f6e4d7ca5f75646f10ac6b2cfcd133c2/r-package/dtatools/src/init.c#L1686-L1715), [supported widths](https://github.com/jbearak/dta-tools/blob/21a06a28f6e4d7ca5f75646f10ac6b2cfcd133c2/r-package/dtatools/src/init.c#L1838-L1868), and [`src/rust/src/lib.rs` worker loop](https://github.com/jbearak/dta-tools/blob/21a06a28f6e4d7ca5f75646f10ac6b2cfcd133c2/r-package/dtatools/src/rust/src/lib.rs#L208-L252).

Batching Stata doubles through a single data-frame slice lowered the compact median to 0.1486 seconds, but it remained 46% slower than the batched standard-R path at 0.1015 seconds. Each result column still paid for `.stata_data()` and metadata restoration. A native double gather with direct attribute attachment is the next useful experiment.

## Recommended implementation order

1. Batch all ordinary columns in `.dta_merge_slice_columns()` through one data-frame `vec_slice()` call. This uses the public vctrs API and already reached parity in the scratch measurement.
2. Batch Stata double columns. Allocate all result `REALSXP` columns on the R thread, validate the row plans once, copy independent columns without R API calls in workers, and attach the prototype attributes directly to the fresh results. Do not build a metadata proxy only to strip and replace its attributes.
3. Apply the same batching to ordinary overlapping columns. Compute their prototypes and casts as required by Stata semantics, slice the `x` frame once, then replace using-only rows across the frame in one operation. Benchmark `vec_assign()` at data-frame granularity before adding another native function.
4. Add a sequential cutoff to the native parallel gather. Spawning a worker for one small compact column costs more than a direct loop.
5. Treat unmatched-key uniqueness and `_merge` construction as cleanup work. Their measured shares are too small to explain the parity gap.

There is no reason to fork `vec_locate_matches()` for this work. Keep vctrs as the matcher and own only the Stata-specific key proxy and result assembly.

## Implementation outcome

The implementation following this research batched ordinary disjoint and coalesced columns through data-frame-level vctrs operations. It also generalized the existing private native gather to accept `dta_double` sources, attach metadata directly to fresh results, and copy those columns in the same worker batch as compact storage. No dplyr or vctrs source code was copied.

Nine-iteration medians on the same fixture after those changes were:

| Method and input | 1:m | m:1 |
|---|---:|---:|
| `dta_merge()`, Stata classes | 0.0843 s | 0.0856 s |
| dplyr, Stata classes | 1.4644 s | 1.3297 s |
| `dta_merge()`, standard R | 0.0924 s | 0.0978 s |
| dplyr, standard R | 0.1032 s | 0.1009 s |

The red diagnostic thresholds both passed. Standard-column `dta_merge()` reached parity in both directions, and Stata-class inputs became faster than standard inputs. Allocated memory for the compact 1:m merge fell from 1.384 GB at the checkpoint to 618 MB.
dplyr allocated 9.27 GB for the same Stata-class 1:m input because its generic
vctrs restoration path materialized or reconstructed the classed outputs.

## License consequences

dplyr's official [`LICENSE.md`](https://github.com/tidyverse/dplyr/blob/95740975c465c29cdb2abdfa13effddb948444dc/LICENSE.md#L1-L20) is MIT. It permits use, copying, modification, merging, publication, distribution, sublicensing, and sale. A distribution that contains a copy or substantial portion must retain the dplyr copyright and permission notice.

vctrs is also MIT under its official [`LICENSE.md`](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/LICENSE.md#L1-L20). The exception matters: vctrs says files matching `src/order-*.c` and `src/order-*.h` are additionally under MPL 2.0 because their radix ordering derives from data.table's `forder()`. See [`LICENSE.note`](https://github.com/r-lib/vctrs/blob/d452a02c9f4752f3268431a3ac8aa221dbe4040f/LICENSE.note#L1-L9). `src/match.c`, `src/match-joint.c`, and `src/slice.c` do not match that pattern, so the repository identifies them under the package's MIT terms. Copying the `order-*` implementation would also require MPL compliance.

dtatools is GPL-3. The Free Software Foundation classifies the Expat license, often called MIT, as GPL-compatible in its [official license list](https://www.gnu.org/licenses/license-list.html#Expat). Compatibility does not erase the MIT notice requirement.

The cleanest course has no copied third-party code. Calling the public `vctrs::vec_slice()` and `vctrs::vec_locate_matches()` APIs leaves dplyr and vctrs as dependencies. If code is later adapted, add a third-party notice containing the exact upstream file, commit, copyright, MIT text, and a short description of the dtatools package's modifications. Avoid copying vctrs `order-*` files unless the MPL obligations are reviewed and deliberately accepted.
