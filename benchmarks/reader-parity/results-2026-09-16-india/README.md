# India full-read comparison, September 16, 2026

This comparison runs ten full reads per tool on the India 2021 DHS women's
dataset, with 724,115 rows and 5,972 columns. The DTA is 5.196 GB and its
preconverted Arrow dataset is 5.560 GB. Sizes and memory use decimal GB.

The dtatools rows use reader optimizations that were opt-in in the measured
source, `d6b0ae454c6ba85b3b22f7574cd828196197cf54`. They subsequently became
defaults in [PR #231](https://github.com/jbearak/dta-parser/pull/231).
The measurements below retain their original source and settings. This
ten-read comparison predates default activation; the later
[full-corpus run](../../reader-corpus/results-2026-09-16/README.md) measures the
default-enabled readers.

| Reader | Median wall time | Range | Median process CPU time | Median peak RSS |
| --- | ---: | ---: | ---: | ---: |
| `dtatools::read_dta()` | 0.6135 seconds | 0.607 to 0.827 seconds | 5.1551 seconds | 5.237 GB |
| `dtatools::read_arrow()` | 0.2950 seconds | 0.289 to 1.022 seconds | 3.0291 seconds | 5.400 GB |
| `haven::read_dta()` | 472.9965 seconds | 422.801 to 572.189 seconds | 473.0478 seconds | 35.113 GB |
| Stata native `use` | 0.4725 seconds | 0.471 to 0.542 seconds | 0.5070 seconds | 5.257 GB |

## Method

Each observation starts a fresh process and performs one read. The four tools
run sequentially on an Apple M4 Max with 16 logical CPUs and 128 GiB of RAM.
Benchmark development and local tests were paused during timing.
The host was shared: a brief unrelated `rustdoc` process and macOS Spotlight
indexing were observed during round nine. All observations are retained,
including the slower late-round reads; these are not isolated-host timings.
Input hashing warms the filesystem cache before measurements; it is neither
flushed nor explicitly rewarmed between observations. There is no in-process
warmup or added pre-read garbage collection. Results remain alive until the process exits.

Five rotated orders and their reverses give ten rounds. Every pair of methods
occurs in each relative order five times; each tool occupies each position
either twice or three times. dtatools uses the default adaptive thread policy.
Stata's version and processor configuration are recorded in
[stata-configuration.json](stata-configuration.json).

Wall time covers the read call, including first reader initialization and
excluding process startup. R uses `proc.time()`; Stata uses its
[elapsed-time timer](https://www.stata.com/manuals/ptimer.pdf).
CPU time is the whole process's user plus system CPU, measured with `wait4`
for all four tools. CPU and peak RSS include startup, package loading, the
dimension check, result output, and shutdown. Their interval differs from the
read-wall interval, so their ratio does not measure CPU utilization. The raw
observations retain R read-call CPU separately.

Arrow checksum verification remains enabled. Conversion is outside the read
measurements. Each read checks the expected dimensions; complete DTA/Arrow
value-and-metadata signatures were compared in separate processes, before the
timings, and matched without warnings. No signature traversal inflates the
reported resource measurements.

## Source and experimental controls

The installed package was built from `d6b0ae454c6ba85b3b22f7574cd828196197cf54`, package
tree `853a9f6308e89d952f0b4353636b7aa006104d9b`. The measurement workers are committed at
`4901f725efb271cea2b1858af3e41c68c3357082`. The table reports this fixed
installation; later source changes are not retimed here.

```text
DTATOOLS_EXPERIMENT_ARROW_OWNED=1
DTATOOLS_EXPERIMENT_DTA_PREPARED=1
DTATOOLS_EXPERIMENT_DTA_RING=4
DTATOOLS_EXPERIMENT_DTA_RING_BLOCK_BYTES=4194304
DTATOOLS_EXPERIMENT_DTA_RING_BUDGET_BYTES=16777216
DTATOOLS_EXPERIMENT_DTA_WIDE_BATCH=1
```

These settings apply only to dtatools children. Haven and Stata run without the
experimental environment variables. Full installation, input, worker, runtime
and executable bindings matched before and after all 40 reads. The published
provenance keeps input hashes and aggregate installation-inventory hashes;
private dataset paths and per-process logs remain local.

This is a focused comparison of one large, wide file. It does not establish
performance on other inputs or satisfy the broader two-cohort reader-parity
release gate. Earlier corpus and projection measurements remain documented in
their dated reports.

## Evidence

- [Observations](observations.csv), all 40 reads and resource measurements.
- [Summary](summary.csv), medians and ranges recomputed from those observations.
- [Provenance](provenance.json), source, settings, versions and hashes.
- [Semantic qualification](qualification.json), the complete DTA/Arrow comparison.
- [Controller and protocol](../README.md#four-reader-india-comparison).
