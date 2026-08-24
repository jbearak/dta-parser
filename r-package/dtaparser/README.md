# dtaparser

`dtaparser` is the R interface to this repository's bounded Rust DTA
reader. Its exported `read_dta()` function deliberately mirrors the formal
arguments of `haven::read_dta()`, while observation storage is decoded by Rust
and materialized through an R-specific collector. Numeric values are written
into their final R vectors during decoding. Each character column interns its
distinct normalized UTF-8 values once and keeps compact row-to-dictionary
indices behind an ordinary R character vector through ALTREP. Element access
resolves the dictionary immediately; allocation of the complete row-level
string-pointer vector is deferred, without retaining the source file.

## Installation

Published GitHub Releases include compiled R packages for Windows x86_64,
Linux x86_64, and macOS ARM64. The R version, platform, and architecture are
part of each asset name. A matching asset URL can be installed with its required
dependencies by `pak` without compiling `dtaparser` locally:

```r
pak::pkg_install("url::https://github.com/jbearak/dta-parser/releases/download/vX.Y.Z/<matching-asset>")
```

Base R can also install one matching URL with
`install.packages(url, repos = NULL)` after the package's Imports are installed;
the archive extension lets R detect the binary format. GitHub does not select
an asset for the current platform, so callers must use the URL whose R version,
operating system, and architecture match their R installation.

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

`encoding = NULL` uses Windows-1252 for pre-Unicode releases 105, 108,
110--111, 113--115, and 117, and UTF-8 for releases 118--119. Pre-Unicode DTA
files do not record a code page, so Windows-1252 is a pragmatic guess that
commonly recovers the intended text rather than a fact encoded in the file.
Use `encoding = "UTF-8"` for strict Stata 18 behavior. A known source encoding
can instead be selected with a case-insensitive UTF-8/UTF8,
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

## Performance compared with haven and Stata

On an Apple M4 Max with 128 GB RAM, the new dictionary-backed implementation
was benchmarked against haven 2.5.5 and Stata/MP 18. The synthetic files are
deterministic mixed-type Stata 15 datasets with 40 columns; their time cells are
seven-run warm-cache medians. The DHS, MICS, and NSFG suite visited all 1,823
regular DTA files under the local corpus cache in fresh processes. Its time
cells are sums and its memory cells are the largest per-file peak RSS on the
common set that all three readers loaded with identical dimensions.

| Dataset/workload | Common files | Input | dta-parser time | haven time | Stata time | dta-parser vs haven | dta-parser vs Stata | dta-parser peak RSS | haven peak RSS | Stata peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Synthetic 100 MB, full 40 columns | 1 | 0.100 GB | 0.139 s | 1.053 s | 0.011 s | 7.58x | 0.079x | 0.273 GB | 0.253 GB | 0.143 GB |
| Synthetic 100 MB, projected 8 columns | 1 | 0.100 GB | 0.051 s | 0.271 s | 0.014 s | 5.31x | 0.275x | 0.198 GB | 0.168 GB | 0.058 GB |
| Synthetic 1 GB, full 40 columns | 1 | 1.000 GB | 0.911 s | 10.958 s | 0.101 s | 12.03x | 0.111x | 0.834 GB | 0.888 GB | 1.133 GB |
| Synthetic 1 GB, projected 8 columns | 1 | 1.000 GB | 0.333 s | 3.120 s | 0.140 s | 9.37x | 0.420x | 0.299 GB | 0.292 GB | 0.365 GB |
| DHS | 641 | 46.903 GB | 297.810 s | 2,727.051 s | 68.806 s | 9.16x | 0.231x | 35.183 GB | 35.103 GB | 5.256 GB |
| MICS | 949 | 3.690 GB | 31.815 s | 216.732 s | 1.155 s | 6.81x | 0.036x | 0.649 GB | 0.669 GB | 0.100 GB |
| NSFG | 222 | 5.772 GB | 34.634 s | 234.588 s | 0.885 s | 6.77x | 0.026x | 2.458 GB | 2.470 GB | 0.435 GB |

Both ratio columns are comparator time divided by dta-parser time. Values above
1x mean dta-parser was faster; values below 1x mean the comparator was faster.

Stata's result is not a metadata-only or lazy `use`. The official
[`use` manual](https://www.stata.com/manuals/duse.pdf) says that `use` loads a
Stata-format dataset into memory, and the
[User's Guide](https://www.stata.com/manuals/u.pdf) says Stata works with a copy
of the data loaded into memory and stores data in memory. The measured RSS also
supports a real load: the 1 GB full synthetic file produced a 1.133 GB Stata
process, and the largest DHS read produced 5.256 GB. Stata's exact loader is
closed source, but its advantage plausibly comes from reading its native format
into compact native storage widths, plus mature implementation work and the
warm operating-system page cache. Dta-parser must additionally construct R
objects; in particular, its numeric result vectors use R's eight-byte doubles.
Matching Stata while returning ordinary R-compatible objects is therefore a
different engineering target, but the Stata time is still a valid eager-load
reference rather than an unattainable lazy-open measurement.

For the synthetic loads, dta-parser was 5.31--12.03 times as fast as haven. On
the real corpora it was 6.77--9.16 times as fast, with peak RSS 3.0% lower on
MICS, 0.5% lower on NSFG, and 0.2% higher on the largest DHS file. Stata was
faster than dta-parser: 4.33 times on DHS, 27.55 times on MICS, and 39.13 times
on NSFG. Stata also used 82.3--85.1% less peak RSS on those corpus maxima. On
the 1 GB full synthetic load, however, dta-parser used 26.4% less peak RSS than
Stata. These are workload- and machine-specific observations, not guarantees.

The corpus comparison is deliberately paired. Two MICS files were rejected by
all three readers. Nine additional files (two DHS and seven NSFG) were read with
matching dimensions by dta-parser and Stata but did not yield a comparable
haven result, so they are excluded from every aggregate rather than giving one
reader a different input set. Private paths and values are not published.

R elapsed time covers the reader call, while Stata elapsed time covers its
`use` command; application startup is excluded from both. Peak RSS comes from a
fresh process and includes the complete runtime. The synthetic R timings
alternate reader order after warmup; Stata's full and projected reads use the
same generated files. Exact dta-parser collector identity and sampled haven
parity are checked before synthetic timing. The corpus suite rotates reader
order between files and retains only successful, dimension-identical triples.

Compared with the old eager collector rebuilt under Rust 1.98.0, the new 1 GB
full-load median fell from 2.354 s to 0.911 s (61.3%) and dimensions-only peak
RSS fell from 2.184 GB to 0.834 GB (61.8%). Forcing every character vector with
`object.size()` still completes in 1.722 s versus 2.256 s for the eager
collector and uses 0.975 GB peak RSS versus haven's 1.313 GB. Thus the deferred
dictionary representation keeps its partial-access benefit without imposing
the earlier raw-deferral prototype's forcing cliff.

See the [synthetic benchmark report](../../benchmarks/large-scale/results-2026-08-24.md)
and [DHS/MICS/NSFG report](../../benchmarks/r-corpus-performance/results-2026-08-24.md)
for exact methodology, provenance, validation, and reproduction commands. The
benchmark harnesses and raw private outputs are report-only evidence, not CI
performance thresholds.

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
- Character columns use dictionary-backed ALTREP vectors. Loading does not
  depend on the source path after `read_dta()` returns. Distinct R strings are
  created once during the load; operations that request a contiguous pointer
  to every row defer only that pointer-vector allocation until it is needed.
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
source builds do not contact a package registry. A Rust 1.98.0-or-newer toolchain
and Cargo are required for the R bridge on every platform. The Rust target
architecture must match R. On Windows, Rtools additionally requires a
MinGW-compatible Rust host: `x86_64-pc-windows-gnu` for x86_64 R or
`aarch64-pc-windows-gnullvm` for aarch64 R. `configure.win` rejects a mismatched
host before compilation and the Windows Makevars passes the target explicitly.

## Conformance and release checks

The repository conformance gate compares every bundled fixture against the
checked TypeScript/Rust oracle and, when R plus its test dependencies are
available, installs the package from the current source and compares it with
haven. Missing R dependencies produce an explicit `SKIP`; CI sets
`DTA_REQUIRE_R_CONFORMANCE=1` and checks Linux, macOS, and Windows. Only
nonmissing floating values permit `1e-7` relative tolerance; missing tags,
labels, formats, value-label tables, strings, names, dimensions, projections,
and row windows are otherwise exact. Package tests also require the dta-parser
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
Windows CI installs and selects Rust 1.98.0 with the
`x86_64-pc-windows-gnu` host matching R, confirms the exact version and host,
then builds and checks the package through Rtools.
