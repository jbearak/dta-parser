# Stage 5 package, native and complete host records

This second publication adds the 92 original host files deferred by the
[installation, full R and Rust publication](PUBLICATION-INSTALL-FULL-RUST.md).
The [completion manifest](publication-completion.json) identifies these 92 copies
and their exact source Git objects. All 155 files in the original reviewed host
archive are now present with their original bytes and modes. The original [README](README.md),
[selection](selection.json) and [inclusion manifest](inclusion-manifest.json)
retain their original scope. The separate publication notes and manifests are
additions outside that original archive membership. The first publication's
statements about deferred files describe its earlier partial state.

The recorded package source remains
[`a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9`](https://github.com/jbearak/dta-parser/commit/a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9),
package tree `b08c77d91bdce67032f13aced90c29d068d6e95a`. The original assembled
archive is preserved at source commit `ccb7182f02c65a845d8714dfb0e30c77a2d411fb`
on the `codex/provenance-stage5-source-ccb7182` branch. Publishing these records
does not install that package source into main. This evidence change retains
the predecessor package tree `f88005766aee9b9dd5827b33a3930feff6672008`.

The [package review](api-review/combined-package-review-01.md) covers sixteen
successful commands, including conformance, interoperability, documentation,
source/binary packaging and NOTICE checks. R package check retains three known
warnings and two notes, as described in the original README. Those observations
are historical executions on the recorded package, not new checks on this
publication commit.

The [native review](semantics-review/combined-native-evidence-review-01.json)
covers four successful commands and eighteen atomic write/allocation/isolation
cases. The dibble rename record reports 80,112 bytes with a largest allocation
of 40,056 bytes, below its 800,000-byte gate. The profiler's 10,000-byte reporting
threshold and the original omitted allocation-event files limit that result.
Native counters describe their own categories and cannot be added as a total
process allocation or RSS measure.

Both attempts at the separate static AST reader remain intact. The
[first reader log](semantics-review/combined-native-record-reader-01.log)
records failure on missing formal arguments. The
[second reader log](semantics-review/combined-native-record-reader-02.log)
records the corrected traversal. Its 38 stopifnot call sites, 174 assertion
expressions and 17 readiness sites are static source counts, including function
bodies and loop bodies. They are not dynamic assertion execution counts. No
historical script, result or receipt was rewritten to remove that failure.

Historical local paths, omitted source/build/runtime products, unrecorded
optimization flags and incomplete bare-command executable mappings retain
their original limits. The archived scripts and recipe describe their original
local dependencies; they are not portable checkout rerun commands. Current
publication checks establish selected byte/mode consistency and Git identity,
not fresh R/Rust execution, a complete runtime closure or protection against
concurrent input mutation.

The Stage 5 implementation remains in PR #205. Minimum-runtime, performance and
external PR gates retain their separate records and acceptance requirements.
Publishing the complete host archive does not finish Stage 5 or issue #172.
