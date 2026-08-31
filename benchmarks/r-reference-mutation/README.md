# R reference mutation benchmark

Run the benchmark from a repository checkout:

```sh
Rscript benchmarks/r-reference-mutation/run.R
```

The runner installs `r-package/dtatools` into a temporary library, starts a
clean R child process with that library first, and records the source commit
and clean worktree state. It refuses tracked or untracked source changes. This
prevents an older installed package or an uncommitted file from satisfying the
gates. Pass `--markdown=PATH` to write the same metric registry as a Markdown
table in addition to the tab-separated standard output.

The workload times repeated one-row changes in a five-million-row compact Stata
byte column. It fails if the direct target materializes or if R reports one
allocation as large as the native byte payload. It compares the same patch on a
50,000-row column and enforces an absolute latency ceiling, so a hidden
full-column scan cannot pass because every large-column timing regressed
together. A second timing keeps an
unselected missing value at the end of the target to catch accidental
full-column cache scans. The run fails when that path is materially slower than
the direct sparse update. A third timing alternates clearing and restoring the
last missing value, which catches scans while the missing-value cache changes.
An all-row scalar replacement must stay within a bounded multiple of an
independent raw-vector fill. This catches repeated scalar decoding and
validation without comparing two paths that share the same implementation.
The benchmark also profiles a sparse full-length logical selector, an all-false
selector, and a compact explicit-position sequence. Row planning must stay
below one compact byte payload of profiled allocation. An empty logical
selection must stop after its counting pass instead of scanning the selector a
second time.
Full-length integer and compact-byte replacements then verify that the patcher
consumes source vectors directly instead of constructing a double or a second
encoded column. Their targets keep native rollback bytes outside the R heap so
an interrupt can restore the original payload without materializing it.
The full-length integer case also runs through a compact position sequence.
The native patcher must gather each source value by its selected row without
turning that sequence into a full R double index.
Another compact-position case supplies selected-length values. Its validation
must not decode row positions that cannot affect value lookup. A native
row-read counter permits at most four reads per selected position: validation,
plan construction, rollback journaling, and the write. This catches an added
selector scan even when timings fluctuate.
An ordinary double target then replaces one row from a full-dataset values
vector. Its cast and validation work must stay proportional to that one-row
selection; excluded values cannot create a full replacement temporary.
The run then generates a five-million-row compact byte column from one scalar.
It fails if the largest R allocation reaches the size of a full double column,
and uses `tracemem()` to check that neither existing column payload was copied.
Full-length integer and compact-byte generation cases apply the same allocation
limit and catch coercion or validation temporaries that scalar generation cannot
expose. The integer case also uses a compact position sequence and limits total
profiled allocation to less than one double column. Its runtime is bounded by
an independent `stata_float()` construction, so validation and encoding cannot
return to separate full-vector passes. Scalar, full-vector, and sparse character
generation may allocate their result vector once, but cannot
allocate a second full-length character-vector header. The full-vector case is
bounded by scalar generation plus an independent character-vector copy, so a
second traversal of the replacement values cannot pass the timing gate. The
sparse case is bounded by scalar generation plus half that copy time, catching
a separate dataset-sized result scan.

A shared, 250,000-value dictionary then undergoes a complete scalar overwrite.
The replacement may allocate one character result, but it must not decode the
old five-million-row payload or duplicate the fresh output because an alias
retains the compact source. Its timing is bounded relative to an independent
character-vector fill, so the former decode and duplication path cannot satisfy
the gate. Direct and shared near-unique dictionary targets are also patched at
one row. A separate R process writes that fixture, so the benchmark process
starts with a cold R string pool. Each path may allocate its unavoidable
character result once, but neither may allocate a full-cardinality cache, and
sharing cannot trigger a private clone of the old compact payload. The shared
alias must remain compact and unchanged.

A base R integer ALTREP sequence is also replaced, with a corresponding
integer-fill baseline. That path deliberately allocates one ordinary integer
vector, patches it while it is still private without a rollback journal,
installs it into dataset aliases, leaves the former standalone column alias
unchanged, and verifies the detached result's aggregate semantics. The full
replacement caps total allocation at one result and must remain materially
faster than the one-row variant, which has to copy the old source. Together
those gates reject a restored full-source scan. The one-row variant likewise
permits only one result allocation.
One row is also replaced from a five-million-row dictionary-backed values
vector with 250,000 distinct strings. That path must leave the source cache
unchanged and allocate less than two megabytes in total, preventing cache space
from scaling with either source length or dictionary cardinality.
Full generation and replacement from the same source are timed against ordinary
character-vector baselines. A transaction-private cache is permitted only when
the read count is at least four times the dictionary cardinality, enough reuse
to amortize its allocation. Separate scalar and near-unique dictionary cases
prevent the cache from scaling to unused or single-use entries, while the sparse
allocation limit prevents it from scaling to an unselected dictionary. Scalar
replacement is timed against an ordinary scalar source so the reader must
decode and retain its one value once per transaction.

The benchmark also patches a metadata proxy. Isolation requires that path to
detach and copy the full compact native byte payload. The check confirms the
copy is no larger than compact storage and never becomes a full R double
column. A second patch must stay below one compact payload, proving the detached
proxy reuses its private native storage. Direct targets do not pay the initial
detachment cost.

Finally, the benchmark profiles 400 and 1,600 consecutive `gen()` calls on the
same dataset. The larger run must remain within the linear time and allocation
budgets; rebuilding every prior generated binding on each call fails these
gates.

`Rprofmem()` reports individual R allocations. Native compact backing appears
as its raw-vector allocation, but the profiler does not measure allocator
overhead or Rust-owned memory. This benchmark is a regression gate for the two
specific promises in #86, not a process-wide peak-memory measurement.
