# dtaparser

`dtaparser` is the R interface to this repository's bounded Rust DTA
reader. Its exported `read_dta()` function deliberately mirrors the formal
arguments of `haven::read_dta()`, while observation storage is decoded by Rust
and materialized through an R-specific collector. Numeric values are written
into their final R vectors during decoding; strings are batch-materialized to
avoid interleaving R allocation with the parser's hot loop.

```r
library(dtaparser)

cars <- read_dta(
  "auto.dta",
  col_select = c(model = make, price, foreign),
  skip = 10,
  n_max = 20
)
```

`file` accepts the same practical input sources as `haven::read_dta()`:
local paths, raw DTA bytes, binary connections, and URLs. Gzip files are
decompressed locally or over a URL; local bzip2, xz, and zip files are also
decompressed automatically. Source resolution is delegated to
`readr::datasource()`, the same interface used by haven 2.5.5. Character
vectors containing literal text are rejected because haven does not handle
the resulting `source_string` for DTA input.

URLs are fetched at call time. Applications that pass untrusted values to
`file` should validate or allowlist acceptable sources before calling
`read_dta()`; the reader does not impose a network allowlist.

Source resolution remains an R-layer concern. An ordinary uncompressed local
file is passed straight to the path-based Rust reader without copying its
contents. Raw bytes and readr-resolved connections, compressed inputs, and
URLs use temporary files that are removed when the read succeeds, errors, or
is interrupted. This keeps network and decompression dependencies out of the
reusable Rust parser.

The reader supports Stata releases 105, 108, 110--111, 113--115, and 117--119. It retains dataset
and variable labels, dataset notes, display formats, value-label tables,
`strL` values, and system missing values plus `.a`--`.z` tags where the release
supports them. `%td` and legacy or
custom daily-date formats beginning `%d` are converted to `Date`; `%tc` and
`%tC` are converted to UTC `POSIXct`. Other Stata calendar formats remain
numeric and retain their `format.stata` attribute.

`encoding = NULL` follows the DTA release convention: Windows-1252 for
releases 105, 108, 110--111, 113--115, and 117 and UTF-8 for releases 118--119. To recover files whose
source encoding is recorded incorrectly, pass a case-insensitive UTF-8/UTF8,
Windows-1252/CP1252, or ISO-8859-1/latin1 alias. The override is deterministic
across platforms and applies to dataset and variable metadata, fixed strings,
`strL` payloads, and value-label names and text. ISO-8859-1 remains distinct
from Windows-1252 at bytes 0x80--0x9f. Other encoding names produce an error
instead of inheriting platform-dependent `iconv` alias or lossy-conversion
behavior. Haven 2.5.5 does not apply its override to modern `strL` payloads;
`dtaparser` deliberately applies the requested encoding consistently there.
With an explicit UTF-8 override, malformed input sequences are replaced
deterministically with U+FFFD. Haven 2.5.5 may instead omit or empty an affected
label.

## Performance compared with haven

A warm-cache benchmark on an Apple M4 Max compared the public Direct-R
`dtaparser::read_dta()` path, the retained internal Rust-vector collector, and
`haven::read_dta()` in the same process and run. The deterministic mixed-type
Stata 15 files contained 40 columns; the projected workload selected eight
representative columns. Each cell used 101 measured iterations after warmup,
alternated implementation order, and ran garbage collection outside timing.

| Input | Rows | Workload | Direct-R median | Rust-vector median | haven median | Direct-R vs haven |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| 100 MB | 222,656 | Full, 40 columns | 0.303 s | 0.247 s | 1.19 s | 3.92739273927393x |
| 100 MB | 222,656 | Projected, 8 columns | 0.082 s | 0.082 s | 0.306 s | 3.73170731707317x |
| 1 GB | 2,227,111 | Full, 40 columns | 2.185 s | 2.337 s | 11.795 s | 5.39816933638444x |
| 1 GB | 2,227,111 | Projected, 8 columns | 0.755 s | 0.744 s | 2.903 s | 3.84503311258278x |

Direct-R vs haven is the haven median divided by the Direct-R median, so higher
means Direct-R was faster. Before timing, Direct-R and Rust-vector results were
required to be exactly identical. Projected 32-row windows from the start,
middle, and end were also compared with haven, subject only to the conformance
suite's `1e-7` tolerance for nonmissing floating-point values.

These are machine- and workload-specific measurements, not performance
guarantees or CI thresholds. The Rust-vector implementation remains an internal
A/B and differential-testing baseline. Its numbers above are from the same run
as Direct-R and haven; the earlier
[direct-R materialization results](../../benchmarks/r-materialization/results-2026-07-26.md)
remain useful historical evidence about the collector transition but are not
combined with these ratios. Haven is the compatibility oracle because it is the
established R reader, not because it is infallible; version-specific bugs,
encoding behavior, and native coercion edge cases remain possible. See the
[full reproducible report](../../benchmarks/large-scale/results-2026-07-27.md)
for p05/p95 values, throughput, provenance, validation, and exact artifacts. No
10 GB file was generated or measured in this scoped run.

## Scope and limitations

- Remote bzip2, xz, and zip files have the same limitations as
  `readr::datasource()`; download them locally first when readr cannot expose
  them as a decompressed source.
- `col_select` uses tidyselect and is resolved from typed metadata before
  observation data are decoded, so predicates such as `where(is.character)`
  work without reading values. If a source column is selected more than once,
  the first selection and alias win. Selection and reading open the file
  separately.
- `.name_repair` is delegated to `tibble::as_tibble()` after selection aliases
  are applied.
- Reads are synchronous. Long reads cooperatively check for R user interrupts.
- R data frames are limited to `2^31 - 1` rows. `skip` must be an exactly
  representable non-negative whole number no larger than `2^53`. For `n_max`,
  `NA`, either infinity, and any negative finite value use haven's intentional
  “all remaining rows” convention; non-negative values have the same whole
  number and `2^53` limits.

### Row-window compatibility

`skip` and `n_max` are normalized once in R, before either materialization path
enters native code. Safe scalar integers and integer-valued doubles therefore
select the same rows as `haven::read_dta()`, including zero and values beyond
the file's row count when they are representable by haven's native boundary.
At the extreme `skip = 2^53` boundary, dtaparser deterministically returns an
empty result while haven's native integer coercion is platform-dependent. The
package also follows haven's intentional upstream `n_max` normalization by
mapping `NA`, `Inf`, `-Inf`, and negative finite values to one unlimited-row
sentinel.

Some haven 2.5.5 edge behavior comes from native integer coercion rather than
its `n_max` normalization contract. This package does not inherit those
coercions: it validates or normalizes these inputs deterministically before
opening the file:

| Input | dtaparser behavior | haven 2.5.5 behavior |
| --- | --- | --- |
| fractional non-negative `n_max` | error | truncates |
| `NaN` `n_max` | error | reads all rows |
| negative, missing, or infinite `skip` | error | native-coercion-dependent window |
| fractional `skip` | error | error from the native boundary |
| non-scalar or non-numeric values | error | error |
| very large whole `skip` through `2^53` | deterministic row window | platform-dependent native coercion |
| values greater than `2^53` | error | integer overflow/coercion behavior |

These deterministic choices avoid silent truncation and platform-dependent
overflow while retaining haven parity for meaningful row-window requests.

The package includes a locked Cargo dependency graph and vendored crates so
source builds do not contact a package registry. A Rust 1.74-or-newer toolchain
and Cargo are required. Windows builds require 64-bit R and the
`x86_64-pc-windows-gnu` Rust toolchain; `configure.win` rejects a mismatched
host before compilation and the Windows Makevars passes the target explicitly.

## Conformance and release checks

The repository conformance gate compares every bundled fixture against the
checked TypeScript/Rust oracle and, when R plus its test dependencies are
available, installs the package from the current source and compares it with
haven. Missing R dependencies produce an explicit `SKIP`; CI sets
`DTA_REQUIRE_R_CONFORMANCE=1` and checks Linux, macOS, and Windows. Only
nonmissing floating values permit `1e-7` relative tolerance; missing tags,
labels, formats, value-label tables, strings, names, dimensions, projections,
and row windows are otherwise exact. Package tests also require the direct-R
collector to be identical to the retained `DtaData`/Rust-vector collector on
every bundled fixture.

```sh
DTA_REQUIRE_R_CONFORMANCE=1 scripts/conformance.sh
dtaparser_version="$(sed -n 's/^Version: //p' r-package/dtaparser/DESCRIPTION)"
dtaparser_tarball="dtaparser_${dtaparser_version}.tar.gz"
R CMD build r-package/dtaparser
R CMD check --no-manual "$dtaparser_tarball"
mkdir -p "$PWD/target"
benchmark_lib="$(mktemp -d "$PWD/target/r-benchmark-library.XXXXXX")"
R CMD INSTALL --library="$benchmark_lib" "$dtaparser_tarball"
export DTAPARSER_BENCH_LIB="$benchmark_lib"
Rscript benchmarks/r-materialization/run.R input.dta timings.tsv 21
```

The materialization benchmark runners require `DTAPARSER_BENCH_LIB` and verify
that the package is loaded from that freshly populated, checkout-local library
rather than an unrelated global installation.

The canonical Rust parser lives directly in `src/dta-parser`; there is no
first-party mirror or copy step. The separate `src/rust` crate provides the R
bridge and builds with `--locked --offline`. Its `vendor.tar.gz` contains only
third-party Cargo dependencies, and `scripts/check-r-cargo-vendor.sh` verifies
the archive against `vendor.sha256` and the bridge lock. Configure always
refreshes the extracted dependencies before building. Python 3.11 or newer is
only required for repository maintenance and CI, not R package installation.
Windows CI installs and selects `stable-x86_64-pc-windows-gnu`, confirms the
rustc host, then actually builds and checks the package through Rtools.
