# Refresh the India reader comparison

`refresh-india.py` measures only `dtatools::read_dta()` and verified
`dtatools::read_arrow()`, each returning a tibble and a dibble. It preserves the
September 16 India comparison's read timer and whole-process resource
boundaries. The historical Haven and Stata observations are copied unchanged;
neither comparator runs.

First create a candidate installation with
[`build-snapshot.py`](../r-file-readers/build-snapshot.py). Supply that build's
work directory, which contains its source snapshot, library and verified build
receipt. The full run requires the exact historical India DTA and Arrow bytes,
with 724,115 rows and 5,972 columns. It does not convert the input.

```sh
python3 benchmarks/reader-parity/refresh-india.py \
  --candidate-build-work /absolute/candidate-build \
  --dta /absolute/input.dta --arrow /absolute/input.arrow \
  --output /absolute/new-results
```

Test the same controller first using a small DTA and its qualified Arrow copy:

```sh
python3 benchmarks/reader-parity/refresh-india.py \
  --candidate-build-work /absolute/candidate-build \
  --dta /absolute/small.dta --arrow /absolute/small.arrow \
  --rows 3 --columns 2 --smoke --output /absolute/new-smoke-results
python3 -m unittest discover -s benchmarks/reader-parity -p test_refresh_india.py
```

Smoke executes one round; its results are not benchmark estimates. A full run
executes ten rounds and forty fresh R processes. Each rotated order is followed
by its reverse, balancing each method pair five times in each relative order.
Run sequentially with other task-owned builds, tests and benchmarks paused.
Record background host activity separately; the controller does not isolate
the machine.

Four separate qualification processes compare complete DTA/Arrow value and
metadata signatures within each output container, require the expected shape
and container, and reject warnings. A tibble and dibble may legitimately differ
in declared string storage; qualification does not require their signatures to
match each other. Qualification traversal never enters timed process resources.

As in the historical worker, jsonlite parses each job before dtatools loads.
Wall and read CPU cover the first public reader call; they exclude process and
namespace startup. No extra garbage collection, compiled timing wrapper or
in-process warmup is added. Whole-process `wait4` CPU and peak RSS also include
startup, namespace loading, dimension checks, reporting and shutdown. The
result remains live through process exit. Numeric ALTREP is enabled, threads
use the adaptive default (`0`), and Arrow checksum verification and profile
restoration are enabled. Experimental reader environment variables are removed.

Hashing both input files before qualification and again before timing warms
the filesystem cache. It is not flushed or explicitly warmed between reads.
Source, installed package, loaded dependency inventories, R runtime, inputs,
worker code and historical comparator artifacts are bound before and after the
run. Every successful observation is retained in order. A failed child leaves
its private job and log; the controller stops and never silently retries.
`COMPLETE` appears only after all reads and final binding checks pass.

Publish the sanitized `summary.csv`, `observations.csv`, qualification,
protocol, binding and completion records. `historical-summary.csv` is an exact
copy of the September 16 source table; `historical-comparators.csv` selects its
Haven and Stata cells unchanged and adds their measurement date. Keep those
dates visible alongside the refreshed dtatools rows. These are measurements
from separate runs, not a new paired comparison with the historical tools.
The historical dtatools rows used dibbles; fresh tibble rows provide another
explicit output choice. Preserve host and operating-system differences in the
report. Private job files, configuration paths and process logs stay local.
