# India: ten fresh-process reads per tool

This follow-up reran all four tools ten times on the same India 2021 DHS
women's dataset (724,115 rows, 5,972 columns). It supersedes the single-read
India comparison in the initial September 12 refresh. The corpus aggregates
and other retained comparator measurements are unchanged.

| Reader | Median read time | Range | Median peak RSS |
| --- | ---: | ---: | ---: |
| `dtatools::read_dta()` | 1.847 s | 1.814–1.927 s | 5.235 GB |
| `dtatools::read_arrow()` | 0.695 s | 0.690–0.703 s | 10.278 GB |
| `haven::read_dta()` | 488.204 s | 413.645–529.616 s | 35.107 GB |
| Stata native `use` | 0.502 s | 0.468–0.503 s | 5.256 GB |

Ratios use the unrounded medians. DTA took 2.66 times Arrow's read time and
3.68 times Stata's. Arrow reduced DTA read time by 62.4%, while using 1.96
times its peak memory. Stata was faster than Arrow in every trial; the earlier
single-read result of 0.696 versus 0.718 seconds does not support a repeatable
Arrow advantage over Stata. Haven took 264.4 times DTA's median read time.

The old published fresh-process DTA time was 1.896 seconds. The initial
September refresh's 1.928 seconds was 1.7% slower. This new median of 1.8465
seconds comes from repeated measurements of the same current build, not a
new optimization. Comparing it with an old single observation cannot establish
a code-change speedup. The older in-process warm median (1.608 seconds) is a
different measurement protocol and should not be substituted for that old
fresh-process time.

A separate [optimization PR](https://github.com/jbearak/dta-parser/pull/226)
then applied Arrow's batch-filling pattern to DTA byte columns. Its matched
ten-run comparison reduced India read time from 1.826 to 0.8945 seconds
(51.0%), with peak RSS still about 5.23 GB. Those are separate stock/candidate
measurements; the four-tool table above records the unchanged current reader.

## Method

The machine remained an Apple M4 Max with 16 cores and 128 GB RAM, macOS
26.6.2, R 4.6.1, haven 2.5.5 and Stata/MP 18. dtatools 0.9.0 was the same
isolated installation used for the refresh, built from
`cf0c80d72191491d42db51d5882a9d7f9d16194e` (the direct-dibble merge).
The documentation checkout was `b2f294e6ed8bc65ba1916adccd9c5fd304185bb0`;
its reader source matched that build. No experimental reader was used here.

Each trial ran in a fresh process, with no in-process warmup. Timing covered
the reader call, excluding application startup. R's first-call setup remains
inside that timer. The output remained live until exit. Peak RSS is the
maximum resident memory of the complete child process, measured with `wait4`,
and is reported in decimal GB; it includes the runtime and native allocations.

The initial order was DTA, Arrow, haven, Stata. Each round rotated the order
by one position. All 40 reads ran sequentially. This gives each tool two or
three appearances in each position, but does not fully balance which reader
precedes another. No compilation or competing benchmark ran during this
sequence. Input hashing and repeated reads leave the filesystem cache warm;
these are not cold-storage or end-to-end application-launch measurements.

The DTA input was the original 5,196,403,097-byte file. Arrow read its retained
5,559,803,386-byte conversion with checksum verification enabled. That older
conversion has the metadata limitations documented in the [initial
report](README.md). All reads returned the expected dimensions, exited
successfully, and contributed to the summary; no timed trial was discarded.

The driver verified the input SHA-256 hashes, installed dtatools and haven
file hashes, Stata binary and library hashes, Rscript hash, and worker hashes
before and after the run. They matched. The driver writes its summary only
after this final verification.

## Evidence and reproduction

- [All 40 observations](india-10x-observations.csv)
- [Summary, including means, standard deviations and RSS ranges](india-10x-summary.csv)
- [Source, input, runtime and installation hashes](india-10x-provenance.json)
- [Driver](../repeat-india.py)

With the original private inputs and isolated library available, run from the
repository root:

```sh
python3 benchmarks/reader-refresh/repeat-india.py /tmp/reader-library target/india-10x --dta "$INDIA_DTA" --arrow "$INDIA_ARROW"
```

The driver verifies that the inputs and installed dtatools match the original
refresh's recorded hashes. It can resume completed observations only while
that binding remains unchanged.
