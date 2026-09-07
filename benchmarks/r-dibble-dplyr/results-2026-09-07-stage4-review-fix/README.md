# Stage 4 review fixes: diagnosis and local qualification

This first evidence scope records the PR #195 review fixes at
[`c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe`](https://github.com/jbearak/dta-parser/commit/c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe),
package tree `f88005766aee9b9dd5827b33a3930feff6672008`. It publishes diagnosis
and exact local qualification. The complete paired benchmark records and dated
report will be added in a second focused evidence PR. This partition makes no
new performance acceptance claim. The repository package files in this
evidence-only branch retain merged Stage 3; the records identify the separately
built Stage 4 candidate.

The original 887-file Stage 4 report/evidence scope and the 161-file review
supplement remain unchanged. The [index](index.json) records every copied file's
original path, size, SHA-256 and Unix mode. It also maps byte-identical review
diffs, eleven reviewed source snapshots available as fixed Git blobs, and
historical inputs already published in the merged evidence. Earlier attempts
retain their source labels and outcomes.

| Directory | Evidence |
| --- | --- |
| `qualification/checks` | Full installed R suite, standard conformance, Haven loopback retry, bridge, archive/binary/NOTICE and native output-preflight checks |
| `qualification/native` | Original 159 native assertions and 15 readiness checks, 18 atomic allocation cases, rename allocation, source and installation guards |
| `qualification/workspace` | Five fresh Cargo gates with all clean input snapshots and the actual verified 27-member crate identity |
| `qualification/source` | Exact source inventory, execution drivers, install log and independent gate audit |
| `qualification/root-219` | Unchanged R inputs/oracles, child outputs, failed outer label check and corrected read-only audit |
| `qualification/fertility` | Strict complete-log parity and all 454 downstream file/state guards |
| `qualification/manifest-audit` | Independent completed-manifest binding and all 32 non-self file hashes |
| `qualification/archive-verifier` | Source and results for 18 synthetic integrity cases, without package workloads |
| `diagnosis/implementation` | Constructor/output-guard red-green probes, extracted width helpers, focused differential, source reviews and failed fixtures |
| `diagnosis/root-probes*` | Independent actual-package constructor and temporary-memory probes, including original attempts and corrected oracles |
| `diagnosis/external-review` | Actual review findings and the bot's unavailable-docstring-scope response |

Run the portable archive check without executing package code:

```sh
python3 benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-fix/verify.py
```

It verifies the complete scoped inventory, bytes and Git-representable executable
bits. `--originals` additionally checks retained execution files at their absolute
paths; `--external` checks listed build products. These options require the
original local evidence workspace. Full Unix modes are recorded for forensics;
Git retains only the executable distinction. Empty fixture directories are
recorded explicitly because Git does not store them. The current preflight
driver recreates them in a new destination.

Full source exports, installations, compiled probes and package artifacts stay
at the recorded external paths with hashes and build recipes. The source export
contains 1,950 files verified against Git bytes and modes. Current guarded runners
are available at the fixed
[c8 source](https://github.com/jbearak/dta-parser/tree/c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe/benchmarks).
Archived execution and diagnosis scripts retain their original path assumptions;
they record what ran and should not be run blindly from an archive copy.

The constructor probes show one initial payload capture and zero additional capture on
the first private write at one, 100,000 and one million elements, with stable backing and
complete source/result checks. Separate retained aliases still detach. These
are native copy counters, not total R allocations or timings. The actual
registered width-entry probes show that one Latin-1 character and a 1,000-element
Latin-1 vector release translation temporaries with unchanged widths and scan
counts. The extracted helper is a separate lifetime experiment; neither probe
measures temporary bytes, RSS or time.

The native runner rejects hidden, unrelated and nested existing content before
output. Its eight cases pass under default Python, `-O` and `PYTHONOPTIMIZE=1`.
Only Git is synthetic: its sentinel stops the admitted empty control before
identity output or a measured workload. All fixture bytes and modes are checked.

The full installed suite passes 16,445 assertions with no failures, errors or
skips and four established warnings. The 956-assertion focused suite, original
native gates, 18 atomic cases, rename allocation, source/binary archives, NOTICE,
roxygen and interoperability also pass. Standard R check retains three warnings
and two notes. The initial skipped Haven loopback attempt remains beside the
successful authorized rerun. All five fresh Cargo gates pass, with 278 tests and
eleven existing packaging warnings about excluded tests. The actual crate's
27 members are bound to the source; bridge tests pass all 18 cases.

Failed attempts are preserved. The final names-dispatch fixture retains only
the first escaped handle; later callbacks cannot overwrite its oracle. The same
final file passes 956 assertions on the candidate and fails exactly 18 expected
fresh-constructor assertions on e343. Root corrected an integer-versus-double
expected count and an outer audit's overly narrow DLL label parser; both original
attempts remain. The initial crate record expected a mandatory `dirty` field,
but Cargo omits it for this clean artifact; complete clean snapshots supplement
the actual VCS metadata.

The root probe manifest and 219-case post-run audit each recorded the empty hash
of their own output while it was still being written. Those self entries do not
hash the completed JSON. The [additive audit](qualification/manifest-audit/c8ca0a4-manifest-self-entry-audit.json)
verifies all 32 non-self hashes and binds both completed manifests externally,
without changing or rerunning them.

All 219 independent R comparisons pass. The isolated fertility run matches the
complete baseline log, including its four known failed/error blocks and two
skips among 499 tests; no Column reallocation warning appears. Its 454 files,
Git state and existing output size/mtime are unchanged. That result does not
replace the final actual renv install/test/original-lock restoration. The
previous twelve base-R read costs and three required Stage 6 filter fixes remain
open. Stages 5 through 9, integrated acceptance, final substantive review, CI and
normal merges remain required; issue #172 stays open.
