# DTA reader experiments

September 15, 2026. These changes extend the locally retained `b41d8f9d` reader. The experiments are disabled by default. They do not establish a speedup or Stata parity.

## Controls

| Environment variable | Behavior |
| --- | --- |
| `DTATOOLS_EXPERIMENT_DTA_WIDE_BATCH=1` | Offers `int`, `long`, `float`, and `double` row spans to a bulk sink hook. Existing byte batching is unchanged. |
| `DTATOOLS_EXPERIMENT_DTA_RING=2` or `4` | Enables persistent column owners with that maximum number of outstanding observation blocks. Other values disable the ring. |
| `DTATOOLS_EXPERIMENT_DTA_RING_BUDGET_BYTES` | Caps requested observation-buffer storage. Default is the requested slot count times the requested block bytes. Insufficient budget reduces slots; fewer than two slots falls back. |
| `DTATOOLS_EXPERIMENT_DTA_RING_BLOCK_BYTES` | Optional block target, capped at 8 MiB and the existing scratch bound; default 8 MiB. Permits equal-budget comparisons such as two 8 MiB blocks versus four 4 MiB blocks. Whole-row alignment can reduce each block's requested size. |
| `DTATOOLS_EXPERIMENT_DTA_PREPARED=1` | Selected R reads retain one open DTA file across metadata discovery and the actual read. Direct selected and full reads also reuse one decode plan for worker choice, eligibility and execution. Full reads have no extra metadata discovery. |
| `DTATOOLS_EXPERIMENT_TRACE=1` | Reports chosen ring geometry, wider-batch flag, workers, dimensions, requested buffer bytes and peak observed total `Vec` capacity. Use only for untimed qualification. |

The controls are independent, allowing default, wider batches alone, ring alone, and combined comparisons. Worker selection and least-loaded column assignment remain the existing adaptive policy.

## Implementation

`DtaColumnSink::try_push_numeric_rows()` receives one storage type, byte order, format version and a checked strided source span. A false return leaves the destination untouched and selects scalar decoding for only that span. Serial execution bounds spans by the existing interrupt interval. The core vector sink provides typed bulk loops; the R sink implements the same hook separately. Missing tags and raw floating-point bits follow the scalar decoder.

The ring in `file.rs` gives each existing column owner an ordered bounded queue. Owners can advance to a later block independently. The coordinator reuses a block only after every owner acknowledges it. The staging slots include the coordinator's next read allocation. Blocks contain complete rows and are at most 8 MiB, or the smaller configured `FileOptions` bound. Budget calculations use the row-aligned block size.

String owners retain their existing column dictionaries and receive ascending rows. There is no local-dictionary merge, row-task scheduling, or extra string scan. Selections containing `strL`, single-worker reads, empty reads and unsupported row geometry use the existing executor. Wider numeric batching may still apply independently on that executor.

The coordinator polls while awaiting acknowledgements. Cancellation stops admission and drains already admitted blocks, at most the configured two or four, before joining. Workers never invoke R. A decode failure from an earlier block precedes a later speculative read failure. Worker panics and stopped channels return errors after all workers join; no partial result is published.

The prepared-selection bridge returns metadata and a private external pointer containing `Option<DtaFile<File>>`. The metadata uses the same helper as the existing preflight. An attempted native read takes the file exactly once, then uses the existing direct or collector reader. Success, errors and panics drop that file; repeated consumption is an error. Explicit close and the finalizer are idempotent at the R pointer boundary. C allocates and registers the external pointer before Rust transfers ownership. R closes the handle before removing a temporary source, including selector errors and interrupts. Replacing the pathname during selection therefore does not change the retained file identity. This is not a snapshot of concurrently modified file contents.

With the same flag, direct R reads call one feature-gated internal core method. It resolves indices, row bounds and `ObservationPlan` once, applies the existing worker-count and columnar-eligibility policy, then moves the private plan directly into the chosen executor. The existing decode loops, layout validation, interrupts, `strL` resolution and value-label handling are unchanged. The plan cannot escape for reuse against a different file or selection. Full reads use this method without metadata discovery; the collector already builds its decode plan once. Existing public core methods retain their behavior.

## Memory and scope limits

The budget covers requested raw observation-buffer storage only. It excludes final columns, string dictionaries, metadata, channel/task descriptors, allocator overhead and legacy `strL` indexes. Allocators may give a `Vec` more capacity than requested; optional tracing sums capacities of the reading, outstanding and reusable blocks without counting shared `Arc` references twice. This is diagnostic accounting, not an RSS or allocator-capacity cap. Existing `max_scratch_bytes_used()` still describes the largest individual scratch request, not aggregate RSS. A ring can increase the live input working set, and lower budget can change effective depth. Compare fixed block size separately from fixed total staging bytes.

These changes retain eager result construction and all existing format checks. They do not improve DTA projection's full-row input volume. Wider kernels need mixed-storage controls because India is predominantly byte storage. The earlier negative contiguous-group experiment remains relevant; this implementation retains current assignment.

## Validation performed

- Seven experimental library tests passed for endian conversion, all missing tags, float bit preservation, bounded serial interrupts, budget/`strL` eligibility, equal-budget geometry, capacity accounting, mixed-string row order, and cleanup/error precedence.
- The 67 library tests matching `file::tests` passed, including three new prepared-plan equivalence/error/interrupt tests and existing profile tests whose module names match that filter. The core also checked successfully without the R adapter feature.
- All 32 existing file-reader integration tests passed with default controls.
- The cross-release serial/parallel parity test passed with both experiments enabled, including the existing `strL` compatibility path.
- Core Clippy passed for library and tests with warnings denied.
- The rebuilt R package passed 1,145 focused assertions: 713 for kernel/ring combinations and 432 for prepared selected/full reads. The latter cover retained file identity, single-use/error/close behavior, raw/gzip/connection cleanup ordering, selector interrupts and warning/error parity, legacy/wide/empty reads, projection order, storage choices, labels and the collector path. The 713 kernel/ring assertions also passed with prepared-plan reuse enabled throughout. No failures, warnings or skips were reported by these test runs.

Full-package qualification and matched elapsed/CPU/RSS comparisons belong to the coordinating experiment. No timing result is claimed here.
