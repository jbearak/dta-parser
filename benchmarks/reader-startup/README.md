# Local reader startup

This benchmark compares two installed dtatools versions on the same inputs.
It measures the first public reader call in a fresh R process, then optionally
measures batches of reads after an in-process warmup. It never runs haven or
Stata. See [the September 13 results](results-2026-09-13/README.md).

Build each version in its own clean checkout and isolated library with
[`reader-refresh/install.py`](../reader-refresh/install.py). The build records
bind each installed file to its source package tree. Supply the resulting
paths to the driver:

```sh
python3 benchmarks/reader-startup/run.py \
  --baseline-source "$baseline_checkout" \
  --baseline-library "$baseline_library" \
  --baseline-build "$baseline_build_record" \
  --candidate-source "$candidate_checkout" \
  --candidate-library "$candidate_library" \
  --candidate-build "$candidate_build_record" \
  --cases "$case_manifest" --repetitions 10 --output "$new_output_directory"
```

The case manifest is a JSON list. Every path must be absolute. For example:

```json
[
  {
    "id": "small-dta",
    "path": "/absolute/path/to/input.dta",
    "reader": "read_dta",
    "rows": 1000,
    "columns": 8,
    "warm_calls": 500
  }
]
```

`reader` accepts `read_dta` and `read_arrow`. Omitting `warm_calls` runs only
the fresh-process comparison. Ten repetitions give each version five turns
in each execution position, separately for every input and measurement mode.
Each child finishes before the next starts. Keep builds, tests, and other
benchmarks idle during measurement.

Fresh reads reuse the existing corpus and Arrow workers. Package loading is
outside the read clock; initialization triggered by the first reader call is
inside it. There is no added warmup or pre-read garbage collection. Arrow
checksum verification remains enabled. Each result stays live until process
exit. Peak RSS includes the runtime and the result; whole-process CPU is also
recorded to detect costs moved outside the read clock.

Warm batches start after one untimed read and garbage collection. The measured
interval includes all calls in the batch and any collection during them. The
reported wall and CPU times divide that interval by the call count. Warm
process peaks include repeated allocations and must not be presented as the
peak memory of one fresh read.

The driver checks dimensions, binds workers and input bytes, and verifies both
source trees and installations before and after execution. The output contains
every observation, summary medians and ranges, immutable child logs, and a
`COMPLETE` marker written only after the final checks. Output directories must
be new. Private paths in local bindings and child commands should stay outside
public reports.
