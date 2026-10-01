# India reader refresh, October 1, 2026

This run updates only `dtatools::read_dta()` and `dtatools::read_arrow()`,
for both tibble and dibble output. The Haven and Stata values below are retained
unchanged from September 16. Neither comparator was rerun.

The DTA input is 5,196,403,097 bytes and the existing Arrow copy is
5,559,834,970 bytes. Both SHA-256 hashes match the historical India inputs.
The data contain 724,115 rows and 5,972 columns. Four separate qualification
processes read every value and compare complete DTA/Arrow signatures within
each output container; all passed without warnings.

| Reader and output | Median read wall | Range | Median read CPU | Median process CPU | Median peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `read_dta()`, tibble | 0.6280 s | 0.618–0.646 s | 4.8310 s | 5.1377 s | 5.250 GB |
| `read_dta()`, dibble | 0.6415 s | 0.631–0.682 s | 4.8575 s | 5.1698 s | 5.250 GB |
| `read_arrow()`, tibble | 0.2275 s | 0.224–0.230 s | 2.4180 s | 2.7540 s | 5.436 GB |
| `read_arrow()`, dibble | 0.2400 s | 0.238–0.244 s | 2.4160 s | 2.7497 s | 5.436 GB |
| `haven::read_dta()` | 472.9965 s | 422.801–572.189 s | n/a | 473.0478 s | 35.113 GB |
| Stata native `use` | 0.4725 s | 0.471–0.542 s | n/a | 0.5070 s | 5.257 GB |

There are ten fresh-process observations per current method, forty in total.
Read CPU sums work across cores during the same interval as read wall time.
Whole-process CPU and peak RSS include startup, loading, checks and shutdown.
Memory uses decimal GB. All observations are retained, including their ranges.
The retained comparator summary does not report read-call CPU separately.

## Protocol and limitations

The worker preserves the historical India worker's setup and timer boundaries.
It parses the job with jsonlite, loads dtatools, and times the first public
reader call with `proc.time()`. It adds no forced garbage collection,
compiled timing wrapper or in-process warmup. Results stay live until exit.
Automatic threads, numeric ALTREP, Arrow verification and profile restoration
are enabled. Output is now explicit; the historical dtatools rows used dibbles.
Conversion and full-signature qualification are outside all timed processes.

Full-file hashing before qualification and before timing warms the filesystem
cache. The ten four-method rounds use rotated orders followed by their reverse,
so each method pair appears five times in either order. Timing ran sequentially
from 20:42:07 to 20:42:38 UTC. This task ran no other builds, tests or benchmarks
during that interval. Seven five-second host samples observed no other process
at or above 50% CPU. These coarse samples do not establish an idle or isolated host.

The machine is the same Apple M4 Max with 16 logical CPUs and 128 GiB RAM,
using R 4.6.1. The current OS is macOS 26.7; the historical comparison used
macOS 26.6.2. The current and historical tools ran on different dates, so the
table is not a newly paired comparison with Haven or Stata. The separately
[paired reader optimization experiment](../../r-file-readers/results-2026-10-01.md)
uses a different setup and supplies the baseline and uncertainty intervals.

## Source and evidence

The candidate installation was built from
[`b89e532d`](https://github.com/jbearak/dta-parser/commit/b89e532d4a90fb0b3daa93d66ed679bc3617295c).
All 449 source snapshot files equal that commit. The six reader implementation
files are unchanged from the build used for the full survey-cache and Stata
oracle results. The build receipt binds source, toolchain and installed files.
Source, installation, loaded dependencies, runtime, worker scripts, historical
artifacts and both complete input hashes match before and after the run.

- [New observations](observations.csv) and [summary](summary.csv).
- [Unchanged historical summary](historical-summary.csv) and
  [retained comparator rows](historical-comparators.csv).
- [Qualification](qualification.json), [protocol](protocol.json),
  [before binding](binding-before.json) and [after binding](binding-after.json).
- [Completion](completion.json), [source audit](source-commit-audit.json),
  [host samples](host-observations.json) and [publication hashes](publication.json).
- [Controller and reproduction](../refresh-india.md).

Private input paths, job files and process logs stay outside the repository.
A preliminary runtime-binding check failed before creating results or running
any reads because base R's namespace does not expose a package path through
`getNamespaceInfo()`. The corrected helper was checked before this full run;
there were no failed or retried timed children.
