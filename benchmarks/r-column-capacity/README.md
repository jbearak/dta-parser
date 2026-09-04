# Column capacity measurements

Run with R 4.6 and the package under test installed in a private library:

```sh
R_LIBS_USER=/path/to/library Rscript benchmarks/r-column-capacity/run.R new
```

For a package built from pre-#160 main, use `baseline` as the last argument. The script compares the old native reserve helper and the new public preparation function, checks payload addresses, profiles allocations for 10-row and million-row materialized columns, and times narrow/wide preparation and within-capacity generation. The old helper does not perform the public function's validation or serialization repair, so its preparation timings are not a like-for-like public API baseline.

On macOS arm64, R 4.6.1, baseline d583f8ce versus the #160 implementation: reserving 5,000 spare pointers allocated 40,056 bytes for a one-column table, including R's vector header. Reserving 256 allocated 2,104 bytes; the difference is exactly 4,744 eight-byte slots. Payload addresses were identical and the allocation did not grow with the 8 MB column payload.

Medians of seven runs, in seconds:

| Operation | 256 spare | 5,000 spare |
| --- | ---: | ---: |
| 1,000 public preparations, one column | 0.023 | 0.032 |
| 1,000 public preparations, 1,000 columns | 0.279 | 0.284 |

Generating 200 columns on 100 rows took 0.018 seconds on baseline and 0.021 seconds with this change, within reserved capacity. Forcing reallocation on each append took 0.037 seconds. These short local measurements establish scale; rerun on the target workload for a deployment-specific budget.
