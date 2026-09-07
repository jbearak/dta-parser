# Stage 4 downstream comparison: framework footer difference

The two e343b3b runs have the same test outcomes and failure details as the retained baseline. Each ran 499 tests with the four existing failed or errored blocks and two skips. Neither emitted a Column reallocation warning. All 454 tracked/nonignored source files, Git state and the integration output's size/mtime stayed unchanged; the exact installed-package guard passed afterward.

Both unchanged strict-driver comparisons failed. Their logs add exactly one line, `I believe in you!`, immediately after testthat's DONE rule and before the backend count summary. No other backend byte differs. The raw logs, failure results and original driver remain unchanged, and this addendum does not claim full raw-log equality or change either recorded driver result.

The installed testthat 3.3.2 SummaryReporter source is saved in `framework-source.log`. Its end_reporter method calls encourage() from a runif(1) < 0.25 branch when failures exist. The saved encourage() body includes this exact message. This accounts for the isolated footer difference; no production package or downstream test was changed to suppress it.

The separately saved `audit-semantic-parity.py` verifies both attempts read-only. It checks every saved artifact hash, original exact-source/outcome/state/warning/provenance guards, unique backend markers and the precise footer position. Removing that one line in memory, solely for the comparison, must leave every other backend byte identical to the baseline. It creates a new audit record and does not edit or normalize any raw evidence or change the test driver. `semantic-parity-audit.json` records all inspected identities and both strict rejections.

This evidence supports behavioral parity for the Stage 4 isolated-library downstream comparison, subject to independent review of this bounded distinction. It retains the four known baseline failures. Final merged-main installation and R backend validation in the actual fertility renv, followed by restoration from the original lockfile, remain required.
