# Stage 4 review fixes: evidence

This archive records the fixes prompted by PR #195's substantive review of
`75b0c54`. The qualified package source is
[`c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe`](https://github.com/jbearak/dta-parser/commit/c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe),
package tree `f88005766aee9b9dd5827b33a3930feff6672008`. The original 887-file Stage 4 report/evidence scope and the 161-file review
supplement are unchanged.

The [dated report](../results-2026-09-07-stage4-review-fix.md) separates passing
correctness, allocation and memory checks from fifteen remaining read flags.
The [index](index.json) records each copied file's original path, size, SHA-256 and
Unix mode. Earlier attempts retain their original source labels and outcomes.

| Directory | Evidence |
| --- | --- |
| `qualification/checks` | Complete installed R tests, standard conformance, Haven loopback retry, archive/binary/NOTICE checks, bridge gates, and the native output preflight under three Python modes |
| `qualification/native` | Original unchanged 159 native assertions and 15 readiness checks, 18 atomic allocation cases, rename allocation, and before/after source and installation guards |
| `qualification/workspace` | Five fresh Cargo gates with complete clean input snapshots and the actual verified 27-member `.crate` identity |
| `qualification/source` | Exact source inventory, execution drivers, installer log and independent root audit |
| `qualification/root-219` | Unchanged historical R inputs and oracles, four child outputs, initial outer label-check failure and the corrected read-only audit |
| `qualification/fertility` | Strict complete-log parity, all 454 file/state guards and the exact-library downstream result |
| `diagnosis/implementation` | Constructor and output-guard red/green probes, extracted width helpers, focused test differential, and preserved failed fixture/setup attempts |
| `diagnosis/root-probes*` | Independent actual-package constructor and temporary-memory probes, including original attempts and narrowly corrected oracles |
| `diagnosis/external-review` | The actual PR review and the bot's response about unavailable docstring scope |
| `benchmark` | Fresh paired atomic, double and heap outputs, complete manifests, raw logs, comparisons and executed coordinator/comparator sources |

Run the portable integrity check from any checkout:

```sh
python3 benchmarks/r-dibble-dplyr/results-2026-09-07-stage4-review-fix/verify.py
```

It checks the complete archive inventory, bytes and Git-representable executable
bits without running package code. `--originals` also checks all retained source
copies at their absolute execution paths; `--external` checks the listed large
products. Those two options require the original local evidence workspace. Full
Unix permission bits are recorded for forensics; Git preserves only the
executable distinction. The verifier's 18 synthetic integrity cases exercise
rejection under default and optimized Python without R or benchmark work.

The original absolute paths in copied manifests identify the execution inputs
and outputs. The index maps those paths to their archive copies. Full
source exports, installations, compiled probe DLLs, binary packages and Cargo
build outputs stay at their recorded external paths with exact hashes. Their
source identities and build recipes are retained; they are not silently replaced
by a different installed package. The actual source export contains 1,950 files,
each verified against the committed Git blob and mode. The eleven reviewed package, runner and document source snapshots
resolve to the exact committed blobs listed in the index. Exact-byte aliases
and three historical cross-archive inputs have explicit fixed-revision mappings. Current reusable
runners are available at the fixed
[c8 source](https://github.com/jbearak/dta-parser/tree/c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe/benchmarks).
Archived diagnostic/execution scripts retain their original path assumptions;
they record what ran and are not a replacement for the current guarded runners.

The output-preflight records use the real R runner and exact library. Only Git
is synthetic, to stop an admitted empty-directory control before identity output
or measured workloads. Fixture bytes and modes are preserved. Git does not store
empty directories; their recorded states and the executable fixture setup retain
that distinction. Run the current preflight driver with a new output directory
to recreate those cases, rather than treating an archived fixture directory as
a new qualification destination.

The extracted width helper demonstrates temporary-allocation lifetime within a
small native loop. The separate root probe calls the actual registered package
entry point before the outer `.Call` cleanup. Neither measures allocation bytes,
peak RSS or elapsed time. Constructor counters measure native captured payload
bytes; they do not include R headers or every allocation made during construction.

The full installed suite passed 16,445 assertions with zero failures, errors or
skips and the four established warnings. The standard R check retained three
warnings and two notes. Its sandbox run is supplemented by the complete installed
suite with loopback access; the initially skipped Haven attempt remains intact
beside the successful loopback rerun. All five Cargo gates passed, with 278 tests
and eleven existing package warnings about excluded test targets. Those warnings
are retained in `qualification/workspace/package.log`.

Earlier failed attempts remain visible. The final names-dispatch fixture retains
only the first escaped handle; later legitimate callbacks cannot overwrite its
oracle. The same final test file passes all 956 assertions on the candidate and
fails exactly the 18 fresh-constructor sharing/copy assertions on `e343b3b`.
Root's first constructor count comparison confused R integer and double types;
its corrected oracle and both attempts are preserved. The 219-case outer audit
first expected one DLL label in every historical child; the corrected audit
accepts only the two actual anchored labels and rechecks the unchanged outputs.
The final root probe manifest and the 219-case post-run audit each recorded the
empty hash of their own output while it was still being written. Those self
entries do not describe the completed JSON files. The
[additive audit](qualification/manifest-audit/c8ca0a4-manifest-self-entry-audit.json)
independently verifies all 32 non-self file hashes and binds both completed
manifest hashes; the original files remain unchanged. The initial root results
summarizer also had a syntax error before execution, before any output existed.
No malformed source snapshot or error log was retained for that attempt, so none
is reconstructed here.

The initial crate identity assembly expected a mandatory `dirty` field; Cargo
omits that optional field for this clean artifact. The final record combines the
actual VCS metadata with complete before/after clean Git snapshots.

The strict fertility result concerns the isolated candidate library. It does
not replace the epic's final actual renv installation, test run and original-lock
restoration. The fresh comparison repeats the same twelve base-R read flags and three
required Stage 6 filter fixes. Neither the local gates nor this archive claims
integrated epic acceptance; final substantive review, CI and normal merge also
remain separate gates.
