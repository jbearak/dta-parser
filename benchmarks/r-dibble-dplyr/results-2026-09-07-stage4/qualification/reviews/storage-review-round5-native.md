# Stage 4 storage review, round 5 native runner fix

Reviewed at 2026-09-07T03:44:48.905994+00:00.

- Worktree: `/private/tmp/dta-direct-stage4`
- Branch: `codex/direct-dibble-owned-atoms`
- Logical Stage 4 base: `ec10a6ac34602f3bd691e8043019c1b479babda4`
- Fix-review base and current HEAD: `7d56080f3e97bc4d73a848e363d729767b9629c0`
- Unchanged package tree: `82b95507e3ea9fe8b8658d7c2098b1f95f5c3756`
- Runner-only working diff SHA-256: `e131883e669f94849502f1a88a6dc83250d172b07b95f0b5d465a0123001bb8b`
- Saved runner diff: `/private/tmp/dta-direct-stage4-validation/storage-review-round5-native.diff`
- Full current logical Stage 4 diff SHA-256: `305f6b55f5f45e94364a51f6bb469c7c784b8b942608b0447b2e858d92745acf`
- Saved full diff: `/private/tmp/dta-direct-stage4-validation/storage-review-round5-native.full.diff`

The native fix diff is `git diff --binary HEAD -- benchmarks/r-reference-mutation/owned-atoms.R`. The full logical diff is `git diff --binary BASE` plus sorted untracked-file patches. The unrelated root-owned README clarification remains in the full diff; this round's fix disposition applies to the native runner. `git diff HEAD -- r-package/dtatools` is empty.

## Disposition

No actionable finding in the native runner fix. It corrects fixture eligibility and strengthens readiness assertions without changing measured operations, allocation budgets or semantic/alias oracles. The runner must still be committed and executed against the exact package installation after the timed quiet window. This review does not claim that the corrected 18-case supplement has passed.

## Actual fix review

The prior factor setup attached attributes to an existing large integer vector. The supplied diagnosis logs show that R converted this fixture into foreign metadata ALTREP at 100,000 rows. Native capture correctly declined the foreign representation, and both owned-info queries returned NULL. Comparing their backing fields therefore accepted `identical(NULL, NULL)`, allowing an invalid fixture to reach the later private-backing gate.

The revised setup constructs factor and ordered-factor values through `factor`, with explicit first, second and unused levels. It preserves the original repeating codes 1, 2 and missing, the same factor classes and the same six kind/size combinations. An explicit integer-type and non-ALTREP check precedes the independent source snapshot and native capture. Separate non-NULL and exact depth-one checks for the column and sibling now precede backing equality. These diagnostics read storage metadata and do not retain the owned payload or expose a pointer.

The loop's kind/size message occurs before profiling. All other changes occur in fixture preparation. The independent serialized source snapshot remains before capture, and expected states derive from it. The measured patch calls and all code after table construction are unchanged from the committed runner. The first shared write still requires exactly `rows * 4` target-copy bytes and a largest R allocation at most `rows * 4 + 1000`. The subsequent private write still requires zero target-copy and capture bytes, total R allocation below 100,000 and largest allocation below 10,000. Full replacement still requires zero target-copy, capture and old-journal bytes. Both standalone alias directions, retained full-replacement alias, independent source values, column attributes, complete table attributes and raw row names remain checked outside profiles.

The previously committed identity guards fail on nonzero command status, missing/multiline results and malformed hashes before output creation. Both git object identities and SHA-256 output are validated, with own-source/shared-helper identity rechecked after work. This fixture change leaves those guards intact.

## Evidence read, not rerun

- `native-factor-large-fixture-probe.log` shows ordinary integer capture succeeds, while the old factor and ordered fixtures become ALTREP and produce NULL owned info.
- `native-factor-constructor-probe.log` shows canonical factor and ordered construction produces ordinary storage captured at depth one.
- `checks-7d56080/native-identity-guards/results.json` records eight failed/malformed git and shasum cases, each exit 1 with the intended diagnostic and no output artifacts.
- `native-7d56080/commands.json` records exact-install identity validation and the original native runner exiting 0. It also records the initial supplement exiting 1. Its log fails at the backing-privacy assertion, consistent with the fixture diagnosis. No success result for the corrected supplement is claimed.
- Parent reports exact package gates and all original 159 plus 15 added native-runner assertions passed for package commit `7d56080f3e97bc4d73a848e363d729767b9629c0`. This round reviewed the fixture fix, not a rerun of those gates.

No R processes, tests, builds, probes or timing workloads were run by this reviewer. Only source/evidence reads and durable review artifacts were produced during the candidate timed quiet window.

## Reviewed file identities

- `benchmarks/r-reference-mutation/owned-atoms.R`: `0542e6943cf1b708bb17d86305483eac011ccedb30e4394d04aeace42ff6759a`
- `benchmarks/r-reference-mutation/README.md`: `05247604a53e97aad4263e1b26179f62f707e7cf99b9eeccc68322a073a876bf`
- `benchmarks/r-dibble-dplyr/helpers.R`: `38be0d6709ba66af9307446c58dce5c6c953e3390da1c3d90258b8c727cf7219`
- `r-package/dtatools/src/owned-columns.h`: `ece57105403f174edcb5dfef977df4b4a5bcc8a0b1105a7a54ecdffb967e6886`
