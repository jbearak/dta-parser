# Direct dibble reader benchmark

Compare two installed versions of `dtatools`, using explicit `output = "dibble"`
for both `read_dta()` and `read_arrow()`. Arrow normally restores its stored
output container; a file stored as a tibble needs an explicit dibble request
to exercise this change.

Install the baseline and candidate into separate libraries, then run from the
repository root on macOS or Linux:

```sh
python3 benchmarks/r-reader-dibble/run.py /tmp/baseline-lib /tmp/candidate-lib /tmp/reader-results
```

The output directory must be new. Run without other benchmarks, tests or
compilation on the host. The worker generates deterministic inputs using the
baseline writer. Seven workloads are saved as both DTA and uncompressed Arrow;
one ordinary-R-column workload is Arrow-only. Files vary table width, row count,
numeric storage and string cardinality. Each installation reads every file
in a separate validation process before measurement. Serialized snapshots must
have identical values, classes and metadata after sorting top-level attributes.

For each of the 15 inputs, three rounds alternate baseline/candidate process
order. Timing children warm the reader twice, calibrate a batch to at least
150 ms, then retain all seven batches. Garbage collection precedes each batch;
GC during the loop is included. Each batch reports elapsed time divided by its
iteration count. The summary gives the median and range of 21 batch averages,
not individual-call percentiles or confidence intervals. Inputs have already
been read, so these are warm filesystem measurements.

Peak memory uses three separate children per installation and input. Each
loads the package, collects garbage, reads once and records its dimensions.
There is no reader warmup or full value traversal. `wait4()` reports that child's
maximum RSS, in bytes on macOS and converted from KiB on Linux. This includes R
startup and package loading as well as the read, including native allocations.
It is neither an isolated reader allocation total nor retained table memory.
Timing and memory use separate processes, so repeated timing reads do not
inflate the memory estimates.

`observations.csv` retains every measured batch and peak; `summary.csv` retains
signed changes, including regressions. `jobs.json` records commands, process
outcomes and peaks. `environment.json` records runtime information and hashes
of the scripts and generated inputs. Per-child logs, CSVs and validation RDS
files stay in the output directory. Generated inputs and validation RDS files
are reproducible scratch data and need not be committed.

The native decoder, thread selection and numeric ALTREP setting are unchanged
between the two implementations. This measures the reader's complete return
time, with deferred string materialization left as before. It does not measure
cold disk reads or a subsequent analysis that forces every column.
