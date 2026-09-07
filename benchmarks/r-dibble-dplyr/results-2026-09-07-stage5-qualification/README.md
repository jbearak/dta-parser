# Stage 5 local qualification

This selective archive preserves 213 original files, totaling 135,885,448 bytes,
from exact-source installs, local gates and independent reviews. The
[inclusion manifest](inclusion-manifest.json) maps copies to original paths,
sizes, SHA-256 hashes and modes observed at inclusion. Its
[receipt](inclusion-receipt.json) binds the completed manifest; the
[copy recipe](archive-qualification.py) verifies original and copied bytes.
The copied records retain their historical source and runner identities.

The final package source is `57309d40433a92d99849fefa155ae7b22b86b337`.
`candidate-final-03` preserves its fresh Git-archive build and installation.
The earlier `candidate-final-02` uses `4427a9b`, with the same evaluator,
native source, DESCRIPTION, NAMESPACE and tests. The only package difference is
the NEWS heading, proven for all 230 package files in the
[equivalence record](news-only-package-equivalence.json). Earlier executions
remain attributed to their original packages and installations.

| Record | Result and scope |
| --- | --- |
| `full-final-01` | Exact installed `4427a9b`: 16,624 assertions, no failures or skips, four established warnings. |
| `rust-final-01` | Runner `8f6caf`, package `4427a9b`: fresh fmt, clippy, workspace tests, documentation and actual Cargo package gates passed. 278 tests passed without failures or ignored tests. |
| `native-final-01` | Same package and runner: unchanged reference-mutation gate, 18 atomic allocation cases and rename-allocation gate passed in a coordinated quiet window. |
| `package-final-01` | Earlier successful checks retained with two limits found during review: its NEWS heading added a parser sub-note, and its generated package tarball lacked a separate command-time input binding. |
| `package-final-02` | Exact final `57309d4`: conformance, source/archive checks, retained R check, macOS binary, NOTICE distribution and interoperability gates passed. The consumed package archive is bound before checks and guarded afterward. The NEWS parser sub-note is absent. |

Both final R checks report three warnings and two notes. The warnings concern
the SDK deployment linker mismatch, vendored GNU Makefiles and the Rust abort
symbol. The notes concern a vendored CITATION file and a generated C file without
a final newline. The final retained test output has 16,624 passes, no failures
or skips, and four established warnings: factor conversion, the temporal Ops
method conflict and two deprecated tibble row-name assignments.

Pinned roxygen generation, Haven and labelled interoperability, Haven
conformance, corpus framework, vendor and source-hash checks passed. NAMESPACE
remains byte-identical to the Stage 4 baseline with 106 exports. Source archive,
installed package and macOS binary all contain the complete matching NOTICE.
The Cargo crate contains 26 files from a Git archive, which has no checkout VCS
metadata file. Eleven established package warnings state that integration tests
are excluded from the published crate; those tests ran in the workspace gate.

The native log's 410 metrics match its Markdown report. All 18 integer, factor
and ordered-factor cases retain the expected first shared-write copy and zero
subsequent private-write R allocation or target copies. The rename gate records
80,112 bytes above its profiling threshold, with a 40,056-byte largest allocation, below both
800,000-byte bounds. This archive contains those bounded allocation/timing gates.
It does not supply the separate paired expression/read scaling, capture,
retained-memory, RSS or write-cost matrix results.

Every acceptance launcher rejects existing outputs, binds source and installed
inputs before execution, checks them afterward and writes a separate receipt
for its completed output manifest. Build phases also bind resolved Cargo source
dependencies and the selected compiler. Exact library, namespace and DLL checks
run before qualification. Original output indexes preserve all observed product
identities, including omitted products. The native atom subrunner records its
actual worktree HEAD separately because its existing Git check executes there;
its script/helper bytes also match the exported runner.

This is readable evidence, not a standalone replay bundle. Expanded Git exports,
source tarballs, installed packages, native binaries and build trees are omitted.
Their identities remain in the original indexes; Git revisions identify the
source needed for new builds. Full OS, SDK and Python runtime closures were not
frozen. Earlier diagnostics and failed development attempts are preserved in the
[diagnostic archive](../results-2026-09-07-stage5-diagnostics/README.md).
The [preparation archive](../results-2026-09-07-stage5-preparation/README.md)
contains the minimum study and helper proofs with their own limits.

Final minimum-runtime and independent performance evidence remains separately
attributed. External review, CI and normal merge still gate Stage 5. The twelve
base-R read costs, three Stage 6 filter flags, stages 6 through 9 and actual
downstream renv validation remain open under the canonical plan.
