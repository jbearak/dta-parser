# R compact-vector optimization benchmark

Run each operation in a fresh process so R's maximum-vector-heap counter starts
from a known point. The script prints one TSV row.

```sh
R_LIBS=/tmp/dtaparser-library Rscript \
  benchmarks/r-altrep-optimization/run.R serialize baseline
R_LIBS=/tmp/dtaparser-library Rscript \
  benchmarks/r-altrep-optimization/run.R construct baseline
R_LIBS=/tmp/dtaparser-library Rscript \
  benchmarks/r-altrep-optimization/run.R recode baseline
R_LIBS=/tmp/dtaparser-library Rscript \
  benchmarks/r-altrep-optimization/run.R compact-operations baseline
R_LIBS=/tmp/dtaparser-library Rscript \
  benchmarks/r-altrep-optimization/run.R character baseline
```

Replace the library and label for the candidate. To recreate the recorded
baseline, archive `origin/main` at `6b5a07b`, install
`r-package/dtaparser` from that archive into a separate library, and run the
same commands. The `character` operation needs haven to create its temporary
DTA input. Other operations use only installed package dependencies.

The elapsed values are diagnostic single runs, not stable performance claims.
Serialized size, compactness, profiled allocation, and heap maxima are the
primary signals.
