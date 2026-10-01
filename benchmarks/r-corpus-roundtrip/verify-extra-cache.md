# Stata oracle for five survey corpora without Haven reads

The exact Stata verifier in `verify.R` covers the established DHS, MICS and
NSFG corpus. Its full gate remains unchanged: 1,823 files must produce
1,821 passes and the two known MICS exclusions, each bound to its stable ID,
byte length and SHA-256. `verify-extra-cache.py` adds the 58 regular DTA files
in ENADID and WFS. The two gates together cover 1,881 files in these five
survey directories. Directory and file symlinks are excluded by the shared
inventory walker.

The supplement requires exactly 17 ENADID files and 41 WFS files, all
release 118, with 58 passes and no exclusions. Changed corpus counts
or releases fail the gate. The runner copies the canonical verifier, worker,
comparator and helpers into a private work directory. Guarded text replacements
change the corpus list and full-gate assertions; the Stata comparator and
reader/writer worker remain byte-identical. Missing or ambiguous replacement
targets fail before execution. `adapter.patch` and `adapter-record.json` make
the adaptation reproducible and bind both source inventories.

Both gates read each DTA with `read_dta()`, write a direct DTA with
`save_dta()`, save and read a profiled Arrow file, then write that result as
another DTA. Live Stata compares the source against both DTA outputs. It
checks dimensions, column order and names, storage types, display formats,
dataset and variable labels, value-label assignments and definitions, dataset
notes, and every stored value. The public writer names are `save_dta()` and
`save_arrow()`.

The worker uses public default containers, currently dibble, and Arrow restores
the stored container. This gate does not independently rerun all files as
tibbles, exercise projected reads or add a synthetic release-119 wide fixture.
Variable characteristics and variable notes remain outside this unchanged
Stata comparator's coverage. The comparator normalizes legacy Windows-1252
and modern UTF-8 text under the established suite's rules; it checks semantic round trips,
not byte-for-byte equality of the original files.

No Haven reader or test runs in either gate. The shared runtime binder hashes
the installed Haven package as an incidental dependency, so Haven must be
installed. Do not use the neighboring `benchmark.sh`, `wide-verify.R` or the
AWW-cache differential workflow for this request, because those invoke Haven.

## Run

Use Stata/MP 18 or later, R, processx, and a source-bound dtatools library.
The exact comparator requires `set maxvar 120000`. Run the existing
`stata-preflight.do` in a private working directory before launching the
corpus. All corpus paths, generated datasets and detailed logs stay private.

Run the original gate against the selected installed library without rebuilding:

```sh
DTATOOLS_BENCH_LIB=/path/to/source-bound/library \
  STATA_BIN=/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp \
  DTATOOLS_VERIFY_JOBS=16 DTATOOLS_VERIFY_MEMORY_GIB=96 \
  R_ENVIRON_USER=/dev/null R_PROFILE_USER=/dev/null \
  Rscript --vanilla benchmarks/r-corpus-roundtrip/verify.R \
  /opt/aww_cache /private/path/canonical-results full
```

Then run the supplement with the same library and successful build record:

```sh
python3 benchmarks/r-corpus-roundtrip/verify-extra-cache.py \
  --library /path/to/source-bound/library \
  --build-records /private/path/build-bindings.json \
  --work /private/path/extra-results
```

`--prepare-only` stages the source, patch and command records without launching
R or Stata. Use another fresh work directory for the actual run. `--cache`,
`--stata`, `--jobs` and `--memory-gib` override the documented defaults. Run
the two gates sequentially so their separate 96 GiB memory budgets do not
overlap. The gate reserves the larger of 512 MiB or 16 times each input size
and uses one Stata processor per comparison. Benchmark timing must wait until
these oracle processes finish.

The supplement checks that the installed package matches the candidate
inventory in the build record. It rehashes the package, source files and
executables after completion and reruns `roundtrip_cached_inventory()` to
verify the complete input bytes. A drift or failed post-check fails the run.
Apply the same before/after audit around the original gate, whose canonical
runner records an initial binding only.

Keep the source build receipts, exact private command, source tarball and
private inventories. Publish the adapter record and patch, sanitized
`verification.tsv`, binding records, totals, exclusion identities and log
hashes. Review failure records before publishing; retained work directories
can contain source paths, variable names and values. A recovered tail or
smallest-file run does not replace either complete gate.

Run the lightweight adapter tests with:

```sh
python3 benchmarks/r-corpus-roundtrip/test-verify-extra-cache.py -v
```
