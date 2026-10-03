# Nullable Arrow strings

This benchmark compares the public reader before and after moving nullable
string construction into one caught C call. Both builds return the same eager
nullable character representation. No-null columns retain their existing
dictionary representation.

Generate fixtures outside timing with `prepare.R LIBRARY FIXTURES`. It writes
250,000 rows and four columns per file: 32-level or unique UTF-8 strings with
zero, one, or 251 nulls per column, plus a finite-double control. Potential
null positions are empty strings in the zero-null fixture, preserving the
string byte lengths and offsets across each null-density comparison.

Build both libraries with `benchmarks/r-file-readers/build-snapshot.py`. Run
`run.py --repository REPOSITORY --baseline BASELINE_BUILD --candidate
CANDIDATE_BUILD --fixtures FIXTURES --output OUTPUT`. Use `--qualify-only` for
complete result checks without collecting times. The timed protocol requires
six rounds or a multiple of six. Each worker gets a fresh R process and runs
one public read; all expected values are loaded after measurement.

The three separate workflows measure read return, first scalar access, and
first complete byte-length/missingness traversal. The last workflow also
records a second traversal. Report both read and complete-workflow results:
a deferred representation can shift costs into later access. A dictionary
column remaining after traversal does not imply full materialization.

The controller binds both clean build receipts, the actual Rscript launcher
and R runtime, every fixture and oracle, and every controller. It rejects
incomplete matrices, changed values/encoding/metadata, nonfinite or zero read
times, inconsistent workflow accounting, and unbalanced null-order positions
or permutations. Raw single-call CPU/wall/GC intervals are retained; medians
do not improve their timer resolution. These observations use an uncontrolled
filesystem cache and a fresh R string cache, not cold storage.

Run `python3 benchmarks/nullable-arrow-strings/test-run.py` and the same command
with `python3 -O` to verify rejection gates. Timing runs should use an otherwise
idle host; qualification and builds may run together outside those windows.
