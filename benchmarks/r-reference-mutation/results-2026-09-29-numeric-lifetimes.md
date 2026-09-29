# Numeric lifetime and copy-path regression check, 2026-09-29

The focused change preserves the validated replacement and contiguous-generation
improvements. None of the eight measured workloads shows a material slowdown.
Public generation and grouped assignment are effectively unchanged. This is a
regression check against main, with no requirement to beat other packages.

Source versions are main `922e4b0ef9824f2731511a473a078debfec16058` and candidate
`63233be065831cabf5fa859e7573cf0739341a54`. Each was installed from source into its
own library. The later native-test manifest refresh and this report do not
change compiled code, R code or test bodies.

[The runner](compare-numeric-lifetimes.R) constructs deterministic 100,000-row
fixtures and checks results before and after each timed workload. Setup and
assertions are outside timing. Four fresh R processes ran sequentially in
main/candidate/candidate/main order, with 100 iterations per workload per process.
The table combines 200 observations per version and workload. Medians include
GC iterations; GC counts sum all three collection levels. Measured R allocation
was identical between versions for each workload. Native entry points measure
existing kernels; the last three rows call public mutation APIs.

| Workload | Main median, us | Candidate median, us | Candidate / main | GC main / candidate |
| --- | ---: | ---: | ---: | ---: |
| `fit_plain` | 263.08 | 59.20 | 0.225 | 0 / 0 |
| `replace_owned` | 395.67 | 99.88 | 0.252 | 0 / 0 |
| `generate_plain` | 350.67 | 13.57 | 0.039 | 2 / 2 |
| `generate_owned` | 350.39 | 13.33 | 0.038 | 2 / 2 |
| `gather_retained` | 56.91 | 38.42 | 0.675 | 0 / 0 |
| `public_replace` | 415.92 | 112.71 | 0.271 | 0 / 0 |
| `public_gen` | 2833.71 | 2845.09 | 1.004 | 114 / 114 |
| `public_grouped` | 22464.72 | 22459.98 | 1.000 | 164 / 160 |

These local measurements do not establish universal performance bounds or
improved performance for unfamiliar ALTREP wrappers. Those wrappers continue
through the existing reader. The public generation cases include table copying
and ordinary expression evaluation.

The host runs macOS on arm64 with R 4.6.1, Apple clang 21.0.0, Rust 1.98.1,
bench 1.1.4, vctrs 0.7.3 and rlang 1.3.0. The candidate installed DLL SHA256 was
`de8e2462dab0062c0b689714f3a3f4752cedf21611f3335c4da9b15c771db1c7`.

Reproduce with fresh installations of the two revisions, then run the following
four commands from the repository root. `MAIN_LIB` and `CANDIDATE_LIB` name the
separate R libraries. Each invocation requires bench.

```sh
Rscript --vanilla benchmarks/r-reference-mutation/compare-numeric-lifetimes.R "$MAIN_LIB" main main-1.csv
Rscript --vanilla benchmarks/r-reference-mutation/compare-numeric-lifetimes.R "$CANDIDATE_LIB" candidate candidate-1.csv
Rscript --vanilla benchmarks/r-reference-mutation/compare-numeric-lifetimes.R "$CANDIDATE_LIB" candidate candidate-2.csv
Rscript --vanilla benchmarks/r-reference-mutation/compare-numeric-lifetimes.R "$MAIN_LIB" main main-2.csv
```

The candidate passed its full installed suite before timing: 1,293 blocks in
74 test files, 23,053 passing assertions, no failures, errors or skips, and seven
warnings from existing tests. The suite includes the new allocation-GC and
numeric boundary tests. Rust bridge tests passed all 23 cases; rustfmt, Clippy,
source-archive and Cargo-vendor checks passed. `R CMD check --no-manual --no-tests`
completed with the same three warnings and two notes on main and candidate:
macOS deployment-target linker warnings, vendored Makefile extensions, the Rust
abort symbol, a vendored CITATION location, and a generated C file without a
final newline. Tests were run separately against the installed candidate.

The runner now writes iteration timing and GC data to the requested CSV and
one separate allocation observation per workload to `<output>.allocations.csv`.
`expression_allocated_bytes` measures the expression's separate allocation run;
it is not per-iteration timing data. The original archived CSVs below repeat
that value in `allocated_bytes` on each timing row. Use it once per workload,
not as a quantity to sum across rows. This schema correction does not change
the timing measurements or the allocation comparison above.

Raw measurement artifacts, 800 observations each, were retained with these hashes:

- `benchmark-candidate-1.csv`: `1cf2df420605290b7efcb0b1abe9c05f9a25bb07131dc7080cb24a1a90f7f8c2`
- `benchmark-candidate-2.csv`: `c3f4dd8472e282da4dcfe0b83b246ef8eff8d8f121714384eeea66e72ccbbfc9`
- `benchmark-main-1.csv`: `8867ab943eddc2239a11feaf2f78b62b7c23a9e4fd1d8bf4dc27853fae455ccb`
- `benchmark-main-2.csv`: `f90a15c99db065e3f73f57b3021d5ac7c6e3ad6b7733bd654cd9df29fcb7e732`
