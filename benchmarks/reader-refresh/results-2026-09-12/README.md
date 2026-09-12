# Reader benchmark refresh, 2026-09-12

The [automatic-thread and byte-batch rerun](../results-2026-09-12-auto/README.md)
supersedes the dtatools measurements below. This report retains the earlier
reader build and protocol as historical evidence.


The India single-read comparison below is superseded by the
[ten-run follow-up](india-10x.md), which reran all four tools and found Stata
faster than Arrow. The original corpus refresh and its retained comparators
remain as recorded below.


Only `dtatools::read_dta()` and `dtatools::read_arrow()` were rerun. Haven and
Stata were not invoked. Their recorded times and peak memory are reused on the
same computer and inputs. The refresh covers the full survey corpus, the DTA
and Arrow read comparison, two representative memory checks, and projected
reads. Write and conversion benchmarks retain their earlier measurements.

The current dtatools build is 0.9.0 from merged commit
`cf0c80d72191491d42db51d5882a9d7f9d16194e`, including the direct-dibble readers
from PR #224. Both readers use their default dibble output and automatic thread
count. The machine is an Apple M4 Max with 16 cores and 128 GB RAM. This run
reports macOS 26.6.2, R 4.6.1, tibble 3.3.1, vctrs 0.7.3, rlang 1.3.0 and
tidyselect 1.2.1. The archived comparators used haven 2.5.5 and Stata/MP 18.

## Representative read time and peak memory

Each observation below uses one fresh process and a warm filesystem cache.
Elapsed time covers only the reader call, excluding application startup. Peak
RSS is the maximum resident memory of the whole process, including the runtime
and the loaded result retained through exit. It includes native allocations
and excludes other processes. GB means 10^9 bytes.

India 2021 DHS women has 724,115 rows and 5,972 columns. The source DTA is
5.196 GB; its retained uncompressed Arrow conversion is 5.560 GB.

| Reader | Measurement date | Read time | Peak RSS |
| --- | --- | ---: | ---: |
| `dtatools::read_dta()` | September 12 | 1.928 s | 5.235 GB |
| `dtatools::read_arrow()` | September 12 | 0.696 s | 10.278 GB |
| `haven::read_dta()` | August 24, reused | 437.088 s | 35.103 GB |
| Stata native `use` | August 24, reused | 0.718 s | 5.256 GB |

Haven took 226.7 times as long as `read_dta()` and reached 35.103 GB peak RSS;
`read_dta()` used 85.1% less peak RSS. Arrow used nearly twice the peak RSS of DTA in
these checks. The 22 ms difference between Arrow and native Stata is too small
to rank them from single observations measured on different dates.

The NSFG 2017–2019 women's file has 6,141 rows and 2,610 columns in a 0.020 GB
DTA file:

| Reader | Measurement date | Read time | Peak RSS |
| --- | --- | ---: | ---: |
| `dtatools::read_dta()` | September 12 | 0.101 s | 0.175 GB |
| `haven::read_dta()` | August 24, reused | 1.002 s | 0.308 GB |
| Stata native `use` | August 24, reused | 0.003 s | 0.051 GB |

The [August 25 dtatools spot checks](../../r-corpus-performance/results-2026-08-24.md)
were 1.896 s / 5.218 GB for India and 0.068 s / 0.142 GB for NSFG. This refresh
does not show an improvement in either single-read spot check. Those older
builds predate several package changes, so this is not an isolated estimate of
PR #224's effect.

## Full survey corpus

All 1,823 inventoried files were read with current dtatools in separate R
processes. The same 1,812 files qualify for comparison as in the original
three-reader run. Every one still reads successfully with matching dimensions.
Two MICS inputs fail to read; nine additional files remain excluded because
haven rejected them in the original run. The comparison has 641 DHS, 949 MICS
and 222 NSFG files. Every source file's size and modification time matched the
original inventory before and after the refresh.

Times below are sums over those common files. Peak RSS is the largest process
peak within each group, not a sum. The haven and Stata columns retain the
August 24 observations exactly. A format label identifies when the format was
introduced, not the application that created the survey file.

| Corpus | Format introduced with | Files | Input GB | dtatools s | haven s | Stata s | dtatools RSS GB | haven RSS GB | Stata RSS GB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DHS | Stata 7/SE | 129 | 8.320 | 15.325 | 435.302 | 63.506 | 0.811 | 4.526 | 0.725 |
| DHS | Stata 8 | 484 | 37.343 | 61.080 | 2,226.568 | 5.124 | 5.234 | 35.103 | 5.256 |
| DHS | Stata 10 | 24 | 1.162 | 2.744 | 61.036 | 0.163 | 0.278 | 0.914 | 0.149 |
| DHS | Stata 13 | 1 | 0.028 | 0.104 | 1.505 | 0.004 | 0.180 | 0.344 | 0.056 |
| DHS | Stata 14 | 3 | 0.050 | 0.241 | 2.640 | 0.009 | 0.197 | 0.430 | 0.077 |
| DHS | All formats | 641 | 46.903 | 79.494 | 2,727.051 | 68.806 | 5.234 | 35.103 | 5.256 |
| MICS | Stata 13 | 494 | 1.634 | 31.792 | 98.402 | 0.567 | 0.207 | 0.367 | 0.073 |
| MICS | Stata 14 | 455 | 2.056 | 30.316 | 118.330 | 0.588 | 0.230 | 0.669 | 0.100 |
| MICS | All formats | 949 | 3.690 | 62.108 | 216.732 | 1.155 | 0.230 | 0.669 | 0.100 |
| NSFG | Stata 5 | 4 | 0.005 | 0.239 | 0.196 | 0.028 | 0.130 | 0.121 | 0.054 |
| NSFG | Stata 6 | 4 | 0.001 | 0.235 | 0.097 | 0.006 | 0.120 | 0.104 | 0.030 |
| NSFG | Stata 7 | 7 | 0.015 | 0.424 | 0.497 | 0.106 | 0.130 | 0.123 | 0.041 |
| NSFG | Stata 8 | 28 | 0.673 | 2.083 | 7.389 | 0.079 | 0.559 | 0.543 | 0.435 |
| NSFG | Stata 10 | 44 | 1.171 | 4.281 | 47.892 | 0.156 | 0.308 | 0.765 | 0.208 |
| NSFG | Stata 12 | 9 | 0.100 | 0.652 | 3.512 | 0.015 | 0.196 | 0.414 | 0.068 |
| NSFG | Stata 13 | 69 | 2.180 | 7.406 | 107.544 | 0.288 | 0.344 | 1.330 | 0.201 |
| NSFG | Stata 14 | 57 | 1.626 | 5.569 | 67.461 | 0.207 | 0.544 | 2.470 | 0.375 |
| NSFG | All formats | 222 | 5.772 | 20.889 | 234.588 | 0.885 | 0.559 | 2.470 | 0.435 |

The complete DHS batch was 34.3 times faster than the retained haven total;
the mean per-file speedup was 20.8 times. The MICS and NSFG total speedups were
3.5 and 11.2 times. Native Stata's saved batch time is lower in all three
corpora.

Across all common files, dtatools was faster than haven on 1,444, tied on 12
and slower on 356. For the 1,534 files larger than 1 MB, the counts were 1,422,
11 and 101. Dtatools was faster on every DHS file. The old claim that dtatools
won on every file above 1 MB no longer holds.

Compared with the [previous dtatools corpus refresh](../../r-corpus-performance/results-2026-08-24.md),
DHS elapsed time fell from 93.152 to 79.494 s, a 14.7% reduction. MICS increased
from 29.341 to 62.108 s, and NSFG from 19.130 to 20.889 s. Peak RSS fell from
35.127 to 5.234 GB for DHS, 0.651 to 0.230 GB for MICS, and 2.460 to 0.559 GB
for NSFG. The older corpus refresh preceded numeric ALTREP as well as direct
dibble construction, so these changes cannot be attributed to direct dibble
construction alone.

## Repeated DTA and Arrow reads

These use the existing Arrow worker and the retained August files. Each method
runs in its own process with one untimed warmup, then 11 timed synthetic reads
or five India reads. Full garbage collection occurs between reads. These
in-process medians are separate from the single-read memory checks above.

| Input | `read_dta()` median, range | `read_arrow(verify = TRUE)` median, range | `read_arrow(verify = FALSE)` median, range |
| --- | ---: | ---: | ---: |
| Synthetic 100 MB, 231,956 × 40 | 0.047 s, 0.046–0.050 | 0.024 s, 0.023–0.028 | 0.024 s, 0.022–0.026 |
| Synthetic 1 GB, 2,320,123 × 40 | 0.193 s, 0.182–0.202 | 0.088 s, 0.087–0.098 | 0.091 s, 0.083–0.103 |
| India 2021 women, 724,115 × 5,972 | 1.547 s, 1.527–1.578 | 0.398 s, 0.389–0.437 | 0.383 s, 0.351–0.479 |

With verification enabled, Arrow was 2.0, 2.2 and 3.9 times faster than DTA.
Disabling verification made no consistent difference in the synthetic cases;
India's median fell by 3.8%. These runs do not support a fixed percentage cost
for verification.

The [August 29 read medians](../../arrow-interchange/results-2026-08-29.md)
were 0.048 / 0.184 / 1.608 s for DTA and 0.028 / 0.097 / 0.416 s for verified
Arrow. Current DTA medians are similar, with the 1 GB case slightly slower.
Verified Arrow medians fell by 14.3%, 9.3% and 4.3%. These are comparisons with
historical observations, without uncertainty intervals or a claim that each
small change reflects an implementation improvement.

The synthetic files are the Stata-first-save fixtures used in the original
Arrow report. The older synthetic haven/native Stata read matrix used a
different fixture generation with different row counts. Its times are not
attached to these inputs.

### Retained Arrow metadata

The original Arrow files were kept unchanged. They predate preservation of
value-label table names, declared string widths and some variable notes. The
current readers therefore do not return identical metadata from each DTA/Arrow
pair. India's Arrow file lacks notes on 116 variables that the current DTA
reader returns.

Initial qualification rejected exact data-signature equality because of those
differences. Qualification then verified matching dimensions, column names,
and content signatures after excluding value-label names, declared string
widths and variable notes missing from the older Arrow files. Those signatures
still cover all values in order, numeric storage types, labels, formats,
remaining notes and characteristics. All three pairs passed. Qualification
runs are separate from timing. The metadata exclusions apply only to comparing
the outputs; the timed reads use the original files and default readers.

## Projected reads

The retained projection fixtures and name lists are unchanged. Each dtatools
method has 11 timed reads after warmups, using the original R worker. Stata's
medians and ranges are reused from August 28. Each synthetic case returns ten
columns from a 100-name union; India returns 100 columns from a 200-name union.

| Input shape | `read_dta(any_of(union))` | `read_dta(all_of(present))` | Stata full `use`, inspect, `keep` | Stata direct projected `use` |
| --- | ---: | ---: | ---: | ---: |
| Tall, 500,000 × 100 | 0.014 s | 0.014 s | 0.016 s | 0.028 s |
| Wide, 50,000 × 1,000 | 0.013 s | 0.013 s | 0.017 s | 0.015 s |
| Tall-wide, 250,000 × 500 | 0.025 s | 0.025 s | 0.039 s | 0.041 s |
| India, 724,115 × 5,972 | 0.248 s | 0.248 s | 0.552 s | 0.482 s |

The India `any_of()` median fell from 0.301 to 0.248 s. Its current range is
0.248–0.267 s, against the retained Stata union-safe range of 0.531–0.630 s and
direct range of 0.444–0.515 s. Dtatools' median is 55.1% lower than the
union-safe Stata workflow and 48.5% lower than direct Stata projection. The
direct Stata command requires known-present names and errors on absent names.
`any_of()` and `all_of()` have the same median in each refreshed case.

## Recommendation

Use `read_dta()` for direct survey imports into R, especially when peak memory
matters. It retains a large advantage over haven on the DHS batch, but the
small-file results rule out a blanket speed claim. Native Stata remains fast
when the analysis will stay in Stata.

Use `read_arrow()` for repeated full reads when an Arrow copy is appropriate
and the measured memory requirement fits. Keep checksum verification enabled.
For a subset of variables, use `read_dta(col_select = any_of(...))`; the India
projection measured 0.248 s without a separate conversion. Conversion cost and
metadata requirements belong in the choice too. The retained India conversion
cost was 1.367 s on August 29 and was not remeasured here. The experimental Arrow
profile still has no cross-version stability promise.

## Reproduction and recorded results

The [reader-only driver](../README.md) uses the existing benchmark workers and
an isolated installation of the current package. It never dispatches haven,
Stata, fixture generation or a writer task. It binds each phase to the package
source tree, installed library hashes, worker hashes and archived inputs.
The corpus controller records child peak RSS with `wait4()`, using the same
whole-process metric as the original macOS time wrapper. No compilation or
other benchmark runs overlap the measured reads.

Public records contain aggregates and named cases. Private corpus paths,
survey values and per-file corpus observations remain in ignored local output.

- [Corpus summary by file format](corpus-summary.csv) and [per-file comparison counts](corpus-statistics.json)
- [Fresh-process time and peak RSS](spot-comparison.csv)
- [Warm-read medians and ranges](warm-read-summary.csv) and [observations](warm-read-observations.csv)
- [Projection medians and ranges](projection-summary.csv) and [observations](projection-observations.csv)
- [DTA and Arrow input sizes and SHA-256 hashes](read-inputs.csv)
- [Package, worker and private-record provenance](provenance.json)
