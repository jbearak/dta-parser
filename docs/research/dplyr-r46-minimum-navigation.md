# Reading the archived minimum-version study

The [research note](dplyr-r46-minimum.md) is an unchanged historical record.
Its relative paths describe the original study directory, rather than this
repository's selective archive. Use the
[current archive guide](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-preparation/dta-direct-stage5-minimum-preflight/CURRENT.md)
for repository links, checksum coverage and the verifier's limits.

In particular, the note's `manifests/artifact-index.json` is preserved here as
[supplementary/original-artifact-index.json](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-preparation/dta-direct-stage5-minimum-preflight/supplementary/original-artifact-index.json).
Other selected `manifests/` records are under
[raw/manifests/](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-preparation/dta-direct-stage5-minimum-preflight/raw/manifests/).

The old verifier compared each original regular tar member's bytes. It did not
establish that an expanded source tree contained no added files or symlinks.
The new replay guard in the current guide tests that stronger condition only
on a fresh extraction. It does not change the historical experiment's scope.
