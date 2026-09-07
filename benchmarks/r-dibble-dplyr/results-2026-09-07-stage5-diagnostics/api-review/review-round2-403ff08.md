# Stage 5 API and evidence review, second round

The production diff through `403ff08` and the subsequent working grouping-order
fix have no new actionable API finding from this reviewer. The expired-column
promise recreates R's interrupted-promise warnings after the obsolete-mask
error. Its focused test distinguishes the first resolution from a later one;
intentional repeated warnings are suppressed only in unrelated expiry tests.
The grouping-order fix now retains validated existing partitions until a key
changes, with mutate/transmute and dependent group-id regression coverage.
These final changes still require the next exact installed candidate checks.

Two substantive review findings remain open:

1. The new inclusion manifest scope says "historical bytes/modes preserved".
   The minimum-study historical index did not record modes, so only observed
   current source/copy modes have been verified. Correct or explicitly supersede
   this assertion while preserving the original receipt history.
2. `run-expression-checks.py` package phase binds supplied installed files but
   does not validate their source-sidecar identity or loaded dtatools path/DLL.
   Its interoperability scripts can therefore run a stale supplied library
   while the output is labelled with `source_sha`. Add a common exact-install
   preflight before phase work. Focused/full and native have their own checks;
   this missing common boundary chiefly affects the package phase.

A third request is resolved in the working runner: it now runs a direct
`R CMD check --no-manual` under the retained output directory. The shared
conformance gate already ran its own temporary check, but removed that complete
check tree even on failure. The added direct gate preserves the required source
archive, check logs and test artifacts. Fresh-path/symlink rejection, deleted-
input diagnostics and new-package-file detection were also read, together with
the three new failure-case tests. Integrity checks use explicit exceptions.

The actual committed preparation archive has 275 files. The inclusion manifest
maps 272 copied records, comprising 181 minimum-preview files, the exact sibling
note copy, 68 original helper-proof files, 21 R 4.6.0 extension files and the copy
recipe. Every original/destination size, hash and observed current mode matches.
All 32 relative links in the wrapper and historical READMEs resolve. No upstream
download archives, installers, native products or build/install trees were
included. `inclusion-audit-01.json` preserves this independent audit. The earlier
181/66/19 primary inventory audits remain applicable. The complete helper MIT
notice, minimum-study R/dplyr license supplements, failed-attempt distinctions,
older-binary limits and partial host/replay inventories remain unchanged.

Read `expression-checks.R` and `run-expression-checks.py` in full. The base-
namespace printer correction is sound. The preserved focused-985e26b-01 result
reports 7,608 passing assertions, zero failures/errors/skips and four established
warnings, but its process exits 1 during final namespace printing. It remains
correctly labelled failed. This is not a completed gate for the final candidate.

No timings or production edits were performed by this reviewer. Final source,
exact installed checks, broader qualification and external review remain
separate from this source/evidence inspection. Reopen for the two fixes and
final qualification evidence before recording a clean final review.
