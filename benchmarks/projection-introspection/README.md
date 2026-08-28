# Projection after dataset introspection

This benchmark tests a pipeline that carries the union of raw variable names
used across many surveys. A particular DTA file usually contains only a subset
of that union. It includes synthetic fixtures and an optional real DHS file.

For each case, every measured method returns the same selected columns in the
same order. The benchmark compares:

- `dtaparser-any-of`: `read_dta(..., col_select = any_of(union))`;
- `dtaparser-all-of`: `read_dta(..., col_select = all_of(present))`, which
  isolates the cost of allowing absent names;
- `stata-load-inspect-keep`: a full `use`, followed by `confirm variable` for
  every union member and then `keep`;
- `stata-use-present`: `use present_varlist using ...`, Stata's fastest direct
  projection when the caller already knows which requested variables exist.

The last method is not union-safe. Stata errors if its varlist contains a name
that is absent from the file. It is included as a lower bound, not as an
implementation of the introspective pipeline.

The fixture matrix varies row count and width. Every tenth variable is a fixed
string; the rest rotate through byte, int, float, and double storage. The union
contains the ten present names plus ninety deliberately absent names. Fixture
generation, process startup, warm-up reads, garbage collection, and result
validation are outside the timed regions. Repetitions run in one process, so
the reported measurements describe warm filesystem-cache behavior. This is the
relevant condition when hundreds of surveys are read sequentially, but it does
not estimate first-read storage latency.

Run the quick matrix with:

```sh
benchmarks/projection-introspection/benchmark.sh quick 7
```

Run the larger matrix with:

```sh
benchmarks/projection-introspection/benchmark.sh full 11
```

Run the India 2021 DHS women's file case with:

```sh
benchmarks/projection-introspection/benchmark.sh india 11
```

The India case uses the 5.2 GB `wm.dta`, selects 100 variables evenly across
its 5,972-column schema, and adds 100 absent sentinels to the `any_of()` union.
It defaults to `/opt/aww_cache/DHS/Original_Data/India 2021/wm.dta`; set
`INDIA_2021_WM` to use another location. The runner creates a symlink in its
private output directory and never copies or publishes the source path. Use the
`all` profile to run the full synthetic matrix followed by this real-file case.

Results are written below `target/projection-introspection/`. The runner builds
and installs the package from the current checkout into an isolated library.
Set `STATA_BIN` to override Stata discovery.
