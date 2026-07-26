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

The reader supports Stata releases 113--115 and 117--119. It retains dataset
and variable labels, display formats, value-label tables, `strL` values, and
system or `.a`--`.z` missing values. `%td` is converted to `Date`; `%tc` and
`%tC` are converted to UTC `POSIXct`. Other Stata calendar formats remain
numeric and retain their `format.stata` attribute.

`encoding = NULL` follows the DTA release convention: Windows-1252 for
releases 113--115 and UTF-8 for releases 117--119. To recover files whose
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

A warm-cache benchmark on an Apple M4 Max compared full reads by
`dtaparser::read_dta()` and `haven::read_dta()` on deterministic, mixed-type
Stata 15 files. Each file contained 40 columns spanning numeric, labelled,
date/time, and string data. The run warmed each implementation, alternated
their execution order, and ran garbage collection outside the timed intervals.

| Input | Rows | Iterations | dtaparser median | haven median | Relative throughput |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 MB | 222,656 | 101 | 0.236 s | 1.122 s | 4.754x |
| 1 GB | 2,227,111 | 101 | 2.187 s | 11.045 s | 5.050x |

Relative throughput is the haven median divided by the dtaparser median, so
higher is faster for dtaparser. Before timing, eight representative columns in
32-row samples from the start, middle, and end of each file were compared with
haven after removing dtaparser's additional top-level `dta_format_version`
attribute. The remaining attributes and values matched, subject to the
conformance suite's `1e-7` tolerance for nonmissing floating-point values.

These are machine- and workload-specific measurements, not performance
guarantees or CI thresholds. The haven comparison used the Rust-vector
materialization path that is now retained as an internal differential-testing
baseline. The current direct-R collector was benchmarked separately and was
faster than that retained path, but haven was not measured in the same run, so
the ratios above are not extrapolated; see the
[direct-R materialization results](../../benchmarks/r-materialization/results-2026-07-26.md).
No repeated 10 GB comparison was completed, so no 10 GB result is reported.

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
- R data frames are limited to `2^31 - 1` rows; `skip` and finite `n_max` must
  be exactly representable non-negative whole numbers no larger than `2^53`.

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
R CMD build r-package/dtaparser
R CMD check --no-manual dtaparser_0.1.0.tar.gz
mkdir -p "$PWD/target"
benchmark_lib="$(mktemp -d "$PWD/target/r-benchmark-library.XXXXXX")"
R CMD INSTALL --library="$benchmark_lib" dtaparser_0.1.0.tar.gz
export DTAPARSER_BENCH_LIB="$benchmark_lib"
Rscript benchmarks/r-materialization/run.R input.dta timings.tsv 21
```

The materialization benchmark runners require `DTAPARSER_BENCH_LIB` and verify
that the package is loaded from that freshly populated, checkout-local library
rather than an unrelated global installation.

The Rust source of truth is `rust/dta-parser`. After a root-first change,
mirror it here and run `scripts/check-rust-sync.sh`; the check also verifies the
Cargo locks and deterministic offline `vendor.tar.gz` identity. Windows CI
installs and selects `stable-x86_64-pc-windows-gnu`, confirms the rustc host,
then actually builds and checks the package through Rtools.
