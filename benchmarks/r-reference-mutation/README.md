# R reference mutation benchmark

Run the benchmark from a repository checkout:

```sh
Rscript benchmarks/r-reference-mutation/run.R
```

The package dependencies and the suggested `callr` package must be installed.
The R build must report `capabilities("profmem") == TRUE`.

The runner exports the current clean git revision, builds its source archive,
and installs it into a temporary library through the shared dibble benchmark
installer. The child validates source provenance and installed-file hashes,
then checks the loaded package and native-library paths. The normal entry point
refuses tracked or untracked changes. Explicit development child runs remain
labelled diagnostic and cannot establish source-bound qualification. Pass
`--markdown=PATH` to write the same metric registry as a Markdown table.

Stage 4 adds `owned-atoms.R LIBRARY SOURCE_SHA OUTPUT_DIRECTORY` for native
integer, factor and ordered-factor backing. Run it from the checkout with a
fresh exact-source installation and an existing empty output directory. It
verifies the installed package and DLL, its own committed bytes and the shared
installer helper, then records all identities alongside 18 allocation cases at
100,000 and 1,000,000 rows. Each case checks independent values, attributes and
raw row names. The first shared sparse write copies one target payload; the
next private write changes a different row without that copy. Full native
replacement preserves a retained alias and copies no old values. Standalone
metadata-copy aliases are checked in both mutation directions. These are
lower-level native integer writes; public factor replacement retains its
existing rejection. Public strings/logicals and table selectors for all new
types are qualified by `benchmarks/r-dibble-dplyr/owned-atomic.R`.

The output preflight rejects every existing entry, including unrelated files,
hidden files and empty child directories, before writing identity or results.
`python3 benchmarks/r-reference-mutation/test-owned-atoms-preflight.py LIBRARY
SOURCE_SHA NEW_EVIDENCE_DIRECTORY` checks that boundary with the real R runner
and exact installed package. A clearly labelled synthetic git command stops an
admitted empty-directory control before any measured workload. Rejected cases
must leave every fixture byte and mode unchanged; child logs and a manifest are
retained. This is a preflight test, not native performance qualification.

Every fixture is a dibble, the package's only mutation target since
[ADR 0036](../../docs/adr/0036-mutate-by-reference-only-on-dibbles.md);
the assertions check dibble identity and capacity where they once checked
base-frame dispatch, and compare values through `as.double()` and
`as.character()` because dibble columns carry Stata storage classes. String
targets declare the width their replacement needs so no measured write pays
for storage promotion. Fixtures assign `reserve_columns()` before generation,
outside the measured operation.
Borrowed numeric fixtures measure a same-value capture separately before the
strict private-write gates. Native diagnostics verify that those physical
handles and backing are private without exporting or serializing a column.
The first write after native generation remains cold. Shared proxy/dictionary
and foreign integer ALTREP cases retain their original first-write aliases.
The declared string target for sparse dictionary RHS decoding also reports
its borrowed first capture separately. That fixture retains its character
representation and checks physical handle privacy before the sparse write;
numeric backing-ownership checks do not apply to strings.

Two operand fixtures move outside timing: the second proxy row index and the
sparse dictionary RHS column handle. Their measured operations begin with
prepared operands and retain all original source/cache assertions. Arbitrary
arithmetic and nested-member expressions can retain their full evaluation
mask; their separate snapshot allocation and lifetime costs are measured by
`benchmarks/r-dibble-dplyr/owned-double.R`. The near-unique dictionary source
explicitly uses `read_arrow(..., output = "tibble")`, preserving the ordinary
character target expected by the historical assertions. Its attribute-free
character representation, dictionary backing and untouched cache are checked
before timing. Other reader fixtures keep their Stata typing.

Each profiled operation reports R allocations and the native capture, target
copy, staged-value, journal and scratch counters separately. Native byte
categories describe overlapping work and must not be added together as one
memory total. No fixture change waives alias isolation, rollback or allocation
bounds; the byte-identical historical runner is not claimed to pass.

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
Full-length integer and compact-byte replacements verify direct reading and
native encoding without full R double or logical validation temporaries. Numeric
table transactions stage new bytes before the final write boundary. Legacy
direct-vector and materialized transactions retain their separate after-write
interruption and rollback tests.
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
an independent `dta_float()` construction, so validation and encoding cannot
return to separate full-vector passes. Scalar, full-vector, and sparse character
generation may allocate their result vector once, but cannot
allocate a second full-length character-vector header. The full-vector case is
timed five times against five independent character-vector copies. The median
must stay below a stable absolute floor and 3.75 copy passes, so a second
traversal of the replacement values cannot pass the gate. The sparse case is
bounded by scalar generation plus half the median copy time, catching a
separate dataset-sized result scan.

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

A column built from a base R integer ALTREP sequence, which the dibble types
as a compact `long`, is also replaced, with a corresponding integer-fill
baseline. The full replacement caps total allocation at one compact result,
leaves the former standalone column alias unchanged, and keeps the column
compact; the one-row variant likewise permits only one result allocation.
Because both writes finish below `system.time()`'s resolution, each is then
repeated on the owned column, and the median per-write time over five
batches must stay under the median time of one integer fill pass. A compact
write costs well under a fill; a restored full-source scan adds more than
one fill per write, so it cannot pass either timing gate.
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
same dataset. The larger run must remain within the original eightfold
allocation budget and a sixteenfold time budget: a per-call cost linear in
the column count stays under sixteenfold whatever the fixed per-call cost, and
a quadratic per-call cost reaches sixty-fourfold. This qualifies the stated
400/1,600-column fixtures,
not arbitrary widths: the direct scalar shape check has a fixed 2,048-name
bound and uses the complete R path beyond it.

`Rprofmem(threshold = 1000)` reports individual R allocations above its
1,000-byte threshold. Zero profiled bytes does not mean zero total allocation.
Native compact backing appears
as its raw-vector allocation. Native counters expose additional staging and
journal work, but neither source measures allocator overhead or process peak
memory. Separate isolated-process measurements cover those memory lifetimes.
