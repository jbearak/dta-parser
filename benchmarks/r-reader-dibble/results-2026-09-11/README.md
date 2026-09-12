# Direct dibble reader results, 2026-09-11

I recommend merging direct construction for dibble output, subject to CI. On this
host it reduces median read time by 36.1% for a 1,024-column DTA numeric table and
42.3% for its Arrow equivalent. Mixed tables improve by 20.7–22.1%. The peak-memory
benefit is small and varies by input, so this should be described as a read-time
improvement.

The baseline is `5024813cfb8523363eae46543d6e1fb24dcf6fd0`.
Both versions were installed into separate temporary libraries. The four changed
R files and both installed packages are identified in [builds.json](builds.json).
The native DLLs have identical SHA-256 hashes. R 4.6.1 ran on a 16-processor arm64
Mac with macOS 26.6.2. The [runtime and input hashes](environment.json) and
[fixture sizes](fixtures.csv) record the environment and generated data.

The public readers use `output = "dibble"`, automatic threads and compact numeric
storage. Arrow inputs are uncompressed. Arrow files stored as tibbles continue
to restore tibbles by default; the improvement applies when dibble output is
selected explicitly or through the existing default/provenance rules.

## Complete results

Times are medians of 21 batch averages across three independent processes per
build and input. Peak RSS is the median of three separate single-read processes.
MB means 1,000,000 bytes. Negative time changes mean faster reads.

| Input | Format | Baseline ms | Direct ms | Time change | Baseline peak MB | Direct peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| double-small, 1000 × 8 | DTA | 0.455 | 0.326 | -28.3% | 125.043 | 125.043 |
| double-small, 1000 × 8 | ARROW | 0.361 | 0.229 | -36.8% | 125.567 | 125.518 |
| double-wide, 1000 × 1024 | DTA | 15.312 | 9.781 | -36.1% | 143.737 | 142.557 |
| double-wide, 1000 × 1024 | ARROW | 13.000 | 7.500 | -42.3% | 144.146 | 143.868 |
| double-tall, 250000 × 16 | DTA | 9.500 | 9.281 | -2.3% | 173.507 | 173.474 |
| double-tall, 250000 × 16 | ARROW | 8.062 | 7.719 | -4.3% | 189.465 | 189.153 |
| mixed, 10000 × 128 | DTA | 3.625 | 2.875 | -20.7% | 134.644 | 134.578 |
| mixed, 10000 × 128 | ARROW | 2.797 | 2.180 | -22.1% | 136.561 | 136.511 |
| string-low, 10000 × 128 | DTA | 4.266 | 3.531 | -17.2% | 134.709 | 134.496 |
| string-low, 10000 × 128 | ARROW | 3.938 | 3.203 | -18.7% | 141.574 | 141.591 |
| string-high, 10000 × 128 | DTA | 22.625 | 22.125 | -2.2% | 288.293 | 286.835 |
| string-high, 10000 × 128 | ARROW | 17.250 | 16.250 | -5.8% | 289.636 | 289.636 |
| strL, 1000 × 32 | DTA | 10.312 | 10.062 | -2.4% | 143.966 | 143.720 |
| strL, 1000 × 32 | ARROW | 5.000 | 4.750 | -5.0% | 198.836 | 198.902 |
| ordinary-arrow, 10000 × 128 | ARROW | 9.562 | 8.281 | -13.4% | 141.918 | 141.754 |

All 15 time medians decrease. The wide numeric, mixed, low-distinct-string and
ordinary Arrow cases have separated observed timing ranges. Tall numeric,
high-distinct-string and strL ranges overlap; their smaller median gains do not
establish a repeatable benefit of that size. In particular, the high-distinct
string batches vary substantially. [All medians, ranges and signed differences](summary.csv)
and [all 720 observations](observations.csv) are retained.

Peak RSS is lower in eleven cases, tied in two and higher in two. The wide DTA
case falls by 1.180 MB, or 0.82%, with baseline/direct ranges of
143.458–143.802/142.246–142.623 MB. Its Arrow equivalent falls by 0.279 MB.
The largest median reduction, 1.458 MB for high-distinct DTA strings, has
overlapping ranges. Low-distinct Arrow strings increase by 0.016 MB and Arrow
strL by 0.066 MB. These data support modest construction-memory savings for some
inputs, without a general peak-memory claim.

## Method and qualification

The [runner and method](../README.md) use serial children with alternating build
order. Every input first passed a separate cross-install comparison of serialized
values, classes and metadata, ignoring only top-level attribute order. All
211 benchmark children exited successfully: one generator, 30 validation
children, 90 timing children and 90 memory children. Their [commands and outcomes](jobs.json)
are retained. The separate comparison processes also completed successfully.

Timing excludes startup, generation and validation, includes GC during batches,
and follows warm reads and per-process calibration. Calibration targets 150 ms;
measured batches range down to 82 ms. The observations retain actual iteration
counts and elapsed times. These are single-host, warm-filesystem measurements;
there is no cold-cache experiment, uncertainty interval or downstream full-scan
claim. Other task-owned R tests and builds were finished before timing began and
resumed after all measurements. The operating system was not reserved.

Memory children do not warm the reader or scan all returned values. Their peak
includes R startup, dependencies, GC and the read, including native allocations.
It is distinct from retained memory and R allocation counts. Ordinary deferred
string materialization remains in place.

The production path retains name repair, metadata attachment before reference
publication, column capacity and ordinary Arrow typing. It also retains string
declaration checks. A CP1252 byte can expand to two UTF-8 bytes, and an Arrow
`str1` declaration can accompany wider strings or nulls. The reader must still
normalize those cases under the existing dibble rules. Fresh native column
handles allow the repeated table preparation and capture steps to be removed.

The [six new test blocks](reader-tests.csv) pass 318 assertions. The complete
package suite passes 21,092 assertions with zero failures or skips. Its six
warnings also occur in a separate baseline dibble-suite run. [Full test output](test-suite.txt).
`R CMD check --no-manual --no-build-vignettes` completes with zero errors,
three warnings and two notes. The warnings concern the native dependency's
macOS deployment target, vendored GNU Makefiles and Rust's `abort` symbol;
the notes concern a vendored citation file and a generated C file's final
newline. [Package check log](package-check.log), [validation counts](validation.json).
The checked package's four changed R files match the measured candidate hashes.
Committed CSVs use LF line endings, and log trailing whitespace is removed;
the recorded values are unchanged.
