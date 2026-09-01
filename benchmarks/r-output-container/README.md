# R output-container benchmark

This benchmark separates table-container finalization from file decoding. It
compares the direct data-table path used by dtatools with the user-level
alternative of receiving a tibble and calling `data.table::setDT()`.

Run it from the repository root after installing the local R package:

```sh
Rscript benchmarks/r-output-container/run.R
```

The synthetic cases cover a tall, narrow table and a short, wide table. The
DTA case reports complete warm-cache reads separately, so decoding cost does
not get mistaken for container-conversion cost. Results are descriptive; this
benchmark is not a CI timing gate.
