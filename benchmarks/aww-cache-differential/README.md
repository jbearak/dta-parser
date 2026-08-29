# Exhaustive AWW-cache differential

This local, report-only workflow recursively inventories every regular file whose
name ends in `.dta` in any letter case beneath `/opt/aww_cache`. It does not
follow file or directory symlinks. For every supported file it compares the
public `dtatools::read_dta()` and `haven::read_dta()` readers across bounded
column batches and row windows until both readers attest the end of the file.
Both readers use their public default encoding behavior. The workflow does not
set Stata's encoding; Stata 18 opens disputed source files with an ordinary
`use` command and applies its own text semantics.
Each reader's column count is established independently with single-column
public-reader probes. Metadata comparison outputs, including projected source
names and storage types, are checkpointed in the same bounded column batches.
(The readers may still parse whole-file metadata internally to resolve a public
`col_select` expression.)

The comparison covers every cell and the following metadata:

- dataset label and ordered notes;
- variable names, order, R storage, labels, and all unexpected attributes;
- Stata display formats and complete value-label attributes;
- R classes and time zones;
- exact missing positions, ordinary `NA`/`NaN`, and Stata missing tags
  `.` and `.a` through `.z`;
- exact strings, source `byte`/`int`/`long` values, dates, datetimes, and
  nonfinite values;
- source `float`/`double` values with an absolute `1e-7` tolerance.

Stata is not a third full-corpus reader. It is started only when the two readers
actually disagree. The tracked `adjudicate.do` program reads only disputed
variables and bounded row windows, in bounded request batches, and returns
machine-readable source facts. The workflow requires Stata 18 and probes the
executable version before use. The local installation may be named either
`stata-mp` or `stata`; no IC/SE variable limit is assumed.

## Run

From any directory:

```sh
benchmarks/aww-cache-differential/benchmark.sh
```

The command builds the current R package into a content-addressed private
library, inventories `/opt/aww_cache`, resumes valid tile checkpoints, performs
all remaining comparisons and Stata adjudications, then prints and writes a
succinct report.

Useful bounded diagnostics use the same entry point:

```sh
benchmarks/aww-cache-differential/benchmark.sh --inventory-only
benchmarks/aww-cache-differential/benchmark.sh --max-files=1
benchmarks/aww-cache-differential/benchmark.sh --id=D0123456789abcdef01234567
```

Resource defaults are 100,000 rows, 256 columns, 8,000,000 aggregate reader
cells, 512 MiB per reader subprocess, and a 900-second tile timeout. They can be
overridden with `--rows=`, `--columns=`, `--cells=`, `--memory-mib=`, and
`--timeout=`. `--stata-requests=` bounds the number of
disputes in one Stata process, and `--stata-row-window=` bounds the row span of
a cell-dispute batch. `--stata=/absolute/path` overrides lazy Stata discovery.
`--retry` retries cached tile and Stata failures while continuing to reuse
successful checkpoints.

All state is private by default under:

```text
target/aww-cache-differential/
  builds/
  runs/<configuration-id>/
    inventory.rds
    checkpoints/
    stata/
    results.tsv
    report.txt
```

Checkpoints bind the workflow schema, build/configuration identity, source
SHA-256, and exact tile coordinates. Successful Stata checkpoints additionally
bind the executable and probed version. A source file is re-hashed before and
after every Stata operation and before every terminal file outcome; a changed
file is never reported as a completed comparison. The report includes local
relative paths but never raw values, labels, notes, or reader exception text.
Exact disputes remain in private RDS checkpoints.

To materialize that evidence as an exact list-column RDS plus a readable TSV
view, run:

```sh
Rscript --vanilla benchmarks/aww-cache-differential/triage.R \
  --run=target/aww-cache-differential/runs/RUN_ID
```

New runs persist their final per-file results directly. The extractor also
reconstructs older runs from their tile and Stata checkpoints.

The workflow refuses common CI environments. It does not modify or source the
historical `fertility-surveys` framework.
