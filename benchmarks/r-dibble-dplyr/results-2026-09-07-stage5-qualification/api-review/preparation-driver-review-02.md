# Stage 5 preparation driver and completed-output review

Reviewed 2026-09-07. This is a bounded preparation/evidence review, not measured
Stage 5 acceptance or completion of external review and CI. No timing workload
was launched by this reviewer, and no production files were edited.

No actionable findings remain in the inspected expression measurement,
retained-memory, qualification, or clean-minimum drivers. The current set is
`measure.py`, `measure.R`, `memory.py`, `memory.R`, `cases-v10.R`,
`qualify-v14.py`, `qualify-v5.R`, `install-candidate-v3.py`,
`finish-minimum-install.R`, `runtime-guard.R`, `check-candidate-v3.py`, and
`check-candidate.R`. Driver source identities are recorded separately in
`preparation-driver-identities-02.json`.

Earlier findings are resolved:

- Missing or unreadable inputs now produce retained integrity failures instead
  of interrupting final receipt creation. The minimum installer marks changed
  input/output-source conditions failed and verifies consumed archive identity
  before and after installation commands.
- The minimum checker validates `installed-files.json` and `inputs-before.json`
  against the completed installation manifest before trusting those inventories.
- Expression qualification and measurement record and assert mixed double/string
  owned backing, depth, size and exposure after correctness setup and immediately
  before profiling/timing. Sharing and private backing are recorded separately.
- Original rowwise source/result metadata writes are checked before the disclosed
  conversion required for later payload-write checks.

`driver-guard-review.py` executes the actual parsed hash/identity/change helpers
under Python `-O`, without launching driver main functions or R. All five current
Python drivers pass unchanged, modified, missing, and broken-symlink cases.
`driver-guard-review-02/result.json` contains exact source hashes and observations.
The first reviewer harness stopped because one driver hashes inline rather than
defining a separate hash helper; that harness failure is explicitly retained in
the second result. This probe does not exercise every complete driver failure
path or claim to freeze the full Python runtime closure.

Measurement scope remains bounded. The expression matrix measures public
dispatch and the qualified safe reference over row, column, group and rowwise
scaling, including a five-verb pipeline. On f622f1d, public dispatch still uses
the predecessor implementation. Rprofmem, native counters and bench allocation
overlap and must not be summed. Retained R heap after GC and whole-process peak
RSS are separate measurements; RSS includes startup, fixtures, GC and checks.
The separate first/shared/private write-cost experiment remains pending. The
performance README's historical preparation notes need a dated update when
these current drivers and subsequent measurements are archived.

The clean minimum runtime guards require R 4.6.0, the qualified R home and exact
library paths, one clean libR, and loaded namespace/DLL/image coverage. Full OS,
SDK and Python runtime closures remain outside the advertised scope. This
qualified dplyr 1.2.1 result does not enlarge the earlier bounded source/binary
minimum-version study.

Completed outputs independently audited:

- `full-final-01-output-audit.json`: all 2,855 products and receipt identities
  pass. The full R gate records 16,624 passed assertions, no failures/errors/skips,
  and four established warnings.
- `rust-final-01-output-audit.json`: all 8,869 products and receipt identities
  pass. Five Rust gates pass; reported suites total 278 tests with no failures or
  ignored tests. The actual 26-file Cargo archive matches source, examples and
  LICENSE. Its original manifest and lock match the exported source/workspace;
  Cargo's normalized manifest is consistent. Eleven package warnings omit
  integration tests from the published archive; those tests ran separately in
  the workspace gate.
- `minimum-and-prequalification-output-audit-01.json`: all seven completed
  inventories pass: clean v3 installation, behavior, expansion observations,
  focused suite, expression-only suite, and both qualify-14 source revisions.
  Clean expression-only has 179 passed assertions and zero failures/errors/skips/
  warnings. The wider clean focused suite has 4,960 passed assertions, three
  classified skips (two Arrow unavailable, one R without memory profiling), and
  four established warnings. The expansion observations match tibble factory
  setup/order for all four recorded expression forms.
- `diagnostics-inclusion-audit-01.json`: all 174 historical copies match their
  sources in bytes, size and currently observed mode. The 177-file inventory and
  five README links pass. The README was subsequently corrected to acknowledge
  the included completed full-test output audit; historical copies and manifest
  remain unchanged.

These audits verify frozen completed output products. The execution runners
report unchanged inputs at their recorded endpoints. Later authorized edits of
live source paths are not retroactively treated as changes during those runs.
Final package gates, measurement results, write costs and final evidence
inclusion still require their own review.
