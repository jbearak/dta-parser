# Reader parity implementation

The accepted plan treats full loads and small projections as independent primary
targets. The first implementation includes owned compact numeric columns, wider
DTA kernels, bounded DTA scheduling and bounded Arrow completion. Experiments
remain disabled until the representative suite reaches matched Stata parity and
passes correctness, downstream and memory gates.

## Baseline

The implementation starts from main at `b41d8f9d8dba260b8c93d5c7d83cb12ee8102600`.
A remote fetch confirmed that revision before edits. It includes byte batching,
adaptive DTA workers and the local-source startup fix.

The baseline package was installed from clean source before implementation.
The local manifest contains 17 inputs and 209 cases: 17 full reads and 64 each
of known-name, union-safe and metadata-discovery projections. Projection sizes
are 10, 30 and 60, with clustered and scattered selections where width permits.
Current-profile Arrow files were generated once by the baseline installation;
full represented value and metadata signatures matched the DTA imports.

The first matched screen used six fresh-process observations per method. Reader
initialization is timed; process startup is excluded. Filesystem cache is warm.
This screen diagnoses the gap and cannot qualify a release.

| Case | DTA | Verified Arrow | Stata |
| --- | ---: | ---: | ---: |
| India, all columns | 0.746 s | 0.5715 s | 0.472 s |
| India, 30 scattered columns | 0.263 s | 0.071 s | 0.315 s |
| Mixed fixture, all columns | 0.017 s | 0.0165 s | 0.001 s |

India full-read median peak RSS was 5.237 GB for DTA, 10.280 GB for Arrow and
5.257 GB for Stata. The mixed fixture includes a zero Stata observation, so its
fresh timing resolution needs care; batched warm observations are separate.

## Implementation and selection

- DTA wider batches preserve raw numeric bits and version-specific missing codes.
- DTA queues keep column ownership and row order while allowing two or four
  outstanding blocks. `strL` uses the established executor.
- Arrow completion separates prepared metadata from an independent decoder,
  allocates protected destinations on R's thread, and verifies/fills chunks on
  workers. The initial R adapter uses this for selections with fixed output
  types. Value-dependent Int32, strings and dictionaries use the prepared
  fallback. No wider type inference is made from empty chunk lists.
- Arrow compact-copy kernels compare a contiguous copy plus missing reduction
  against the existing fused loop.
- Owned compact columns retain immutable Arrow buffers behind independent R
  handles. Byte, int, long and float are included. Doubles and strings are not.
  Contiguous R backing and retained native buffers share read-region operations.
  Writable compatibility access detaches to ordinary compact storage.

The owned and bounded Arrow experiments currently select separate completion
paths. Owned mode takes precedence if both are requested. Experiments have
private environment controls; public reader arguments and default verification
are unchanged. See the DTA and Arrow implementation notes for scope and memory
accounting details.

## Gates

`benchmarks/reader-parity/run.py` measures installed baseline/candidate readers
and reruns Stata. Release timing runs require two balanced cohorts with at least
12 observations per method and case; the default is 20 to balance five methods.
Each candidate median must reach its matched Stata median in both cohorts.
Full and projected results cannot offset one another. Zero Stata medians and
screening runs cannot pass. The controller binds source builds, installed files,
inputs and worker scripts by hash and rechecks files after measurement.

Timing parity alone is insufficient. Semantic qualification, downstream sparse
analysis and full traversal, first-write behavior, peak memory, ownership
lifetime, malformed input, cancellation, corpus and package conformance remain
separate gates. If screening rejects an experiment, keep it experimental and
report its measured bottleneck before spending the complete release matrix.

No defaults have been enabled by this implementation record. Final measurements
and validation results belong below once completed.
