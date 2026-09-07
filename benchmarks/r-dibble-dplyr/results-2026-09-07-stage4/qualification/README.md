# Package and native qualification

The final package source is `e343b3b56a8529e9ee0ac40f8bd88beebcd2be15`, package
tree `f12a2a1dd430636a33b7f6e953023d90d1ff2589`. Its exact installed DLL has MD5
`18837c14dcd6597169dc0e3d99186dab`. The
[final manifest](e343b3b/checks/exact-gates-manifest.json) records local gates,
30 log hashes, source/archive identities and the retained failed attempts.
Performance acceptance and external review/CI are separate gates.

| Source | Disposition |
| --- | --- |
| `7d56080` | Initial exact R/package checks and original 159 native assertions passed. Its atomic supplement exposed a foreign factor fixture, and the independent read matrix rejected 43 regressions. |
| `976cc40` | Exact R/package checks passed. The original native runner rejected dictionary replacement timing. Profiles showed two additional dictionary copies; this source was not accepted. |
| `e343b3b` | All local package/native gates pass. Paired read and performance qualification remains separate. |

The final standard conformance run covers 22 TypeScript fixtures, 32,085 decoded
cells, ten deterministic native cases and the canonical oracle. Full R check
and testthat pass with the established three warnings and two notes. Haven
conformance has no skips; helper/labelled interoperability, roxygen and archive
checks pass. The complete NOTICE is identical in the source and macOS binary
archives and three installed copies. The binary smoke checks six atomic storage
families and both mutation directions.

The [native qualification](e343b3b/native/qualification.json) retains every
original assertion and numerical budget, plus the 15 existing readiness checks.
Its 18 supplemental cases cover native integer, factor and ordered-factor first
shared, subsequent private and full replacement at 100,000 and 1,000,000 rows.
These are lower-level storage checks; public factor replacement remains rejected.
The saved rename gate records 80,112 bytes total and 40,056 bytes largest for a
dibble, and zero recorded allocation for the typed tibble. Source files and
installed identities are checked before and after the native run.

The final Rust bridge formatting/check/18-test run uses the exact exported
source. Its first direct Cargo attempt lacked the generated vendor directory;
that setup failure remains in the archive. Extraction of the verified tracked
vendor archive precedes the successful run. Five core workspace gates, including
278 tests, are reused with an explicit equality proof for the workspace manifest,
lockfile and complete `dta-tools` Git tree. They were not silently rerun or
relabeled as new results.

[The index](implementation-evidence-index.json) maps every copied artifact to
its original validation path and SHA-256. Copies preserve original bytes,
including failed logs and trailing whitespace. Large source archives, libraries
and compiled binaries remain at their recorded `/private/tmp` paths; their
digests are retained. Review reports preserve their original snapshot and scope.
Later source fixes do not retroactively change an earlier review or measurement.

To reproduce the gates, use a clean checkout of the recorded source, the pinned
dependencies, the archive installer in `benchmarks/r-dibble-dplyr/install.R`,
and the commands recorded in each manifest. The normal reference-mutation entry
point installs its checkout itself. The retained execution scripts record the
exact child-library route used here. Use new output directories; these tools
reject existing outputs.
