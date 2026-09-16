# Reader architecture evidence and constraints

Research dated September 15, 2026. This note supplies the common brief for the language explorers and architecture agents. It records existing measurements and inspected source. It contains no new benchmark results or diagnosed cause of the remaining Stata gap.

The user requires optimization of both loading all columns and projections. Both are primary workloads in the [architecture recommendation](parser-architecture-review-2026-09-15.md#primary-workloads). Typical analyses use at most a few dozen columns, so measurements also include sparse downstream use after an all-column load. Full-load and projection timing, CPU and memory results must be assessed separately.

## Revision scope

The working checkout is `573e636611d5b73afde47f5d5f232c3c4bcc506f`, on `codex/refresh-reader-benchmarks`. Its latest report describes a different measured implementation. The locally stored `origin/main` points to `b41d8f9d8dba260b8c93d5c7d83cb12ee8102600`, which includes further reader work. We inspected that revision through `git show` without changing the checkout or fetching a remote update. It is a local reference, not a claim about the live remote head.

| Revision | What it establishes |
| --- | --- |
| `573e6366`, working checkout | Direct dibble completion is present. Native readers still cap automatic decoding/filling at eight workers. |
| `92020d4d`, earlier measured build | Compact-byte batching and available-CPU automatic threading. India DTA 0.821 s, verified Arrow 0.5995 s. |
| `03e054da`, adaptive policy | Compact-output worker selection accounts for selected decode work per block and per read. Serial compact-byte batches poll for interruption. |
| `8bb746b0`, latest locally retained measured candidate | Ordinary local reads avoid unnecessary source-adapter namespace loading. India DTA 0.7520 s, verified Arrow 0.5580 s. |
| `b41d8f9d`, locally stored `origin/main` | Includes adaptive policy and local-source changes, plus their published reports. Use this as the architecture reference for identifying genuinely new work. |

Sources: [working core](https://github.com/jbearak/dta-parser/blob/573e636611d5b73afde47f5d5f232c3c4bcc506f/r-package/dtatools/src/dta-tools/src/file.rs), [earlier benchmark](../../benchmarks/reader-refresh/results-2026-09-12-auto/README.md), [adaptive report](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/reader-refresh/results-2026-09-12-defaults/README.md), [local-reader report](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/reader-startup/results-2026-09-13/README.md). Git objects were inspected locally.

## Remaining measured gap

The latest locally retained India comparison uses a 5.2 GB DTA with 724,115 rows and 5,972 columns and its retained 5.6 GB Arrow conversion. Each dtatools reader has ten fresh-process observations with a warm filesystem cache. The reader clock includes first-call work and excludes application startup. Stata observations are retained from the September 12 comparison.

| Reader | Median wall time | Median CPU time | Median process peak RSS |
| --- | ---: | ---: | ---: |
| `read_dta()` | 0.7520 s | 5.3480 s | 5.231 GB |
| Verified `read_arrow()` | 0.5580 s | 4.5260 s | 10.275 GB |
| Stata native `use` | 0.5015 s | Unavailable | 5.256 GB |

Arithmetic targets, not predicted gains: matching the retained Stata median requires about 33.3% less DTA read time and 10.1% less Arrow read time. Arrow is the nearer elapsed-time target and has the larger memory opportunity. CPU medians sum threads and cannot be compared with Stata because that CPU measurement is unavailable. [Measurement and provenance](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/reader-startup/results-2026-09-13/README.md).

Do not compare these Stata numbers with the separate repeated warm-reader cohort. That cohort measured DTA at 0.5435 s and verified Arrow at 0.3120 s after an untimed read and with GC between reads. It did not supply a matched new Stata result. The retained Arrow files also omit value-label table names, declared string widths and some variable notes; equality checks explicitly exclude those fields. [Balanced warm-reader report](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/reader-refresh/results-2026-09-12-balanced/README.md).

The corpus contains other regimes. With the local-source fix, total DHS read time is below retained Stata, while MICS and NSFG totals remain above it. Those are single observations per file. The India full-load gap is not a universal ordering of readers. [Corpus results](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/reader-startup/results-2026-09-13/README.md).

## Existing implementation

### DTA

The observation executor reads bounded full-width row blocks. A coordinator overlaps the next read with decoding the preceding block. Workers own selected columns. Each worker acknowledges a block before the coordinator can recycle it and dispatch the next one. Projection reduces output and decoding but this executor still traverses full observation rows. Existing compact-byte batching and adaptive worker selection must be included in any new control build. [Latest reference executor and worker policy](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/dta-tools/src/file.rs).

The R thread allocates/protects output and completes R classes and metadata after workers finish. Numeric workers fill native compact storage or preallocated R memory; string construction uses column-level dictionaries. The production sink owns complete columns, which complicates changing to independently scheduled row tasks for mixed strings. [R sink](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/rust/src/lib.rs).

### Arrow

The IPC reader already plans selected batch/column work, reads selected buffers, handles compression, validates layouts and profile metadata, verifies checksums, and schedules parallel decode tasks. Its result retains a list of decoded Arrow chunks per column. [IPC reader](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/dta-tools/src/arrow/read.rs).

`dtatools_read_arrow_rust()` obtains the decoded result, allocates destinations for all selected columns, fills them, then finalizes R columns. `fill_profiled_compact()` copies values into compact storage and counts missing codes. This establishes overlapping ownership of decoded Arrow payloads and final destinations; the exact share of time and RSS attributable to that overlap still needs measurement. [R Arrow adapter](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/r-package/dtatools/src/rust/src/arrow_ffi.rs).

## Work already explored

| Approach | Existing evidence and consequence |
| --- | --- |
| Direct native-to-dibble construction | Implemented. Do not re-propose the general constructor shortcut as new work. |
| Compact-byte batches | Implemented in the latest reference. The earlier matched eight-worker India experiment measured about 51% less time. |
| Contiguous weighted column groups | An earlier three-run screen found no benefit. Byte batching alone took 0.894 s; batching with contiguous groups took 0.895 s. The existing least-loaded assignment remained. Do not repeat this as an untested locality idea. |
| Automatic worker geometry | Implemented. A narrow India projection uses about two workers. Refinements need a control with this policy enabled. |
| Avoiding local-source namespace setup | Implemented. The 350-byte fresh DTA case fell from 57 to 2 ms. Remaining setup work needs new profiling. |
| Deferred numeric decoding over owned DTA rows | Prior prototype lost on every full-traversal/signature comparison against direct eager construction. Some copied handles repeated decoding. Default adoption was rejected. |
| Positioned numeric row tasks | Prototype commit `87448f9a07ddf5692e705a4139c5b6b3e0cc84f7` already exists locally. It excludes strings/strL, uses a 16 MiB aggregate observation-staging budget, and preserves the opened file handle. The README records tests but does not establish a qualified elapsed-time win. |
| Borrowed row microtiles | Prototype commit `bb3957da31994fe50027d63d40498c31cff8ec95` exists locally. The adaptive-default report explicitly excludes row-task and tiling experiments from production measurements. An architecture proposal must identify how it differs before requesting another experiment. |

Sources: [direct/deferred study](read-dta-construction-and-deferred-decoding.md), [batching study](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/dta-reader-performance/README.md), [adaptive report](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/reader-refresh/results-2026-09-12-defaults/README.md), [startup report](https://github.com/jbearak/dta-parser/blob/b41d8f9d8dba260b8c93d5c7d83cb12ee8102600/benchmarks/reader-startup/results-2026-09-13/README.md), [row-task prototype](https://github.com/jbearak/dta-parser/blob/87448f9a07ddf5692e705a4139c5b6b3e0cc84f7/benchmarks/row-task-experiment/README.md), [microtile source](https://github.com/jbearak/dta-parser/blob/bb3957da31994fe50027d63d40498c31cff8ec95/r-package/dtatools/src/dta-tools/src/file.rs).

The batching study also retains historical instrumented Arrow phases: 0.197 s allocating output and labels, 0.167 s reading buffers, 0.239 s filling output and 0.008 s finalizing. Those probes used an earlier setup, omit some wrapper work and differ in phase definitions across formats. They justify measuring conversion again; they are not a phase breakdown of the newer 0.558 s result.

## Architecture constraints

- Preserve semantic read parity, Stata missing-code identity, variable and dataset metadata, row order, output-container behavior and supported mutation semantics. Use the vocabulary in [CONTEXT.md](../../CONTEXT.md).
- Keep default Arrow verification and consumed-profile validation. Preserve frozen-profile compatibility commitments and projected-field validation scope. [ADR 0010](../adr/0010-promise-stability-for-frozen-arrow-profiles.md).
- Keep R allocation, callbacks, attribute mutation and GC interactions on the R thread. Give worker threads owned native storage or protected, disjoint, preallocated destinations. Publication must wait for worker completion.
- Preserve interruption, cleanup, checked lengths, malformed-input behavior and source lifetime. An open file descriptor protects against pathname replacement; it does not prove that another process cannot mutate or truncate the file. A file mapping alone does not provide an immutable snapshot.
- Keep staging bounded in bytes. A bounded number of batches can still allocate unbounded bytes as schemas grow.
- Treat codecs, decoding, checksums and planning as in-process dependencies. Files are local-substitutable dependencies using real fixture files or memory readers where behavior permits. R is an in-process runtime with GC/thread rules; qualify it in real R child processes. External ecosystem implementations supply research evidence, not a reason to add a runtime dependency on Python or Julia.

## Evaluation brief

Architecture sketches may show private interfaces; they are not public feature commitments. Each proposal should name what it hides, what the caller must know, where ownership transfers, and how the same interface is tested. Different formats should share a seam only where their behavior genuinely varies behind a common contract.

Before implementation claims, establish a same-source, same-file control using the existing reader workers. This research pass skips reproduction and fix phases because it proposes experiments and makes no causal or performance claim for new code.

Measure first-call read time, repeated warm read time, full traversal, representative native and ordinary R consumers, first mutation, CPU, process peak RSS and retained memory separately. Add cold or cache-constrained runs if that use case matters; current evidence is warm-cache only. Do not treat delayed work, disabled verification or missing metadata as a faster equivalent read. Qualify values, missing codes and metadata outside timed sections. Bind source, installed library, input and worker identities. Run timed work sequentially without competing builds or research processes.

For each proposed experiment, require a falsifiable prediction and a stop condition. Candidate priorities can reflect the remaining 33.3% DTA and 10.1% Arrow gaps, but those percentages do not predict how much any mechanism can save.
