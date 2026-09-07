# Stage 5 measured results and retained diagnosis

These selective archives preserve exact source-specific qualification and
measurement records for the direct expression engine. Combined measurements
use `a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9`; historical variants and baselines
keep their own source identities. The implementation PR follows separately.

- [Clean minimum-runtime integration](current-minimum/README.md) records the
  fresh R 4.6.0 installation, focused assertions and helper comparisons.
- [Combined expression, write and memory measurements](current-expressions/README.md)
  records the full expression grid, pipeline repeats, writes and isolated memory.
- [Broader owned-column results](current-owned/README.md) retains the atomic,
  double and memory matrices and their original diagnostic flags.
- [Historical width and setup investigation](historical-expressions/README.md)
  preserves earlier source variants, sampling profiles and rejected reporting.
- [Read costs and native controls](read-diagnosis/README.md) records repeated
  base-R read costs, setup corrections and public-API diagnostic scans.

The combined direct expression grid has no flag above both 10% and 1 ms.
Twelve base-R reads still have repeatable costs, and three whole-filter flags
remain Stage 6 work. The original isolated timing flags stay in their records
even when fresh repeats do not reproduce them. No overall performance
acceptance or completion of issue #172 is claimed by this evidence PR.

Each directory retains plain functional drivers, descriptions and review files,
plus a selection index and compressed logs/data. Its verifier checks exact
selected bytes, Unix modes and membership without extracting paths. Local
reviewers inspected selected contents. This does not claim that an external
review service reads compressed data or that omitted runtime/build trees can
be reconstructed. Each directory describes its original warnings, failed
attempts, input-binding limits and scope. No package source changes here.
