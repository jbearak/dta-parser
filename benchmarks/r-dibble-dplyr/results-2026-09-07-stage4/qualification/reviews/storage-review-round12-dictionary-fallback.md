# Storage review round 12: dictionary attribute fallback

No actionable semantic, callback, attribute-order, storage or alias-safety defect was found in this bounded snapshot. All production callers handle the helper's new NULL decline result. Current fallback assignments retain the original R attribute/names setters. This is source and stored-profile review; no R, build, test, probe or benchmark workload was executed by this reviewer. It does not accept source 976cc40, establish a new native timing pass, or complete Stage 4.

## Snapshot and identities

Captured `2026-09-07T06:21:42.634713+00:00` in `/private/tmp/dta-direct-stage4`. Both HEAD and fix comparison base are `976cc403f21b9adbb454d39c9c3447717b67c29f`; logical Stage 4 base remains `ec10a6ac34602f3bd691e8043019c1b479babda4`.

The actual scoped diff is saved as `storage-review-round12-dictionary-fallback.diff`, SHA-256 `599e780dcc7e2fcc20eafbd6ff3abb97c9e138c21edf69951ce5d808b01bbcc6`. Full file copies and identities are in `storage-review-round12-snapshot/` and `storage-review-round12-snapshot.json`. End-of-review hashes match the snapshot.

Reviewed paths:

| Path | SHA-256 |
| --- | --- |
| `r-package/dtatools/R/dta-string.R` | `0f57aadac08a04c5e9eda5c3ac7868dc5cb53f412d6eaf21041bedc9dad32e6d` |
| `r-package/dtatools/R/dta-numeric.R` | `aa2a7b6442d7cb0604a249f14c25665c9a32bcd93e33e1063b9317799418d599` |
| `r-package/dtatools/tests/testthat/test-owned-atoms.R` | `c338b92d2bd9d719968eea408c56b502e54417bb3acb2d64b4b879c25eb4cadc` |
| `docs/adr/0033-share-owned-atomic-backing-and-storage-facts.md` | `fb38f2d20cb8091104a6588123a08b86b0b31a006493928819cf3c5bbc2377d4` |
| `docs/plans/dibble-result-performance-progress.md` | `65cdc4d6a37a5e2e29c5b8e360539d015c5c5d8b01e5fe9a1c578b5e94972a8d` |

Supporting C owned-string qualification/forking, capture_string and dictionary duplicate/copy implementations were inspected. Native source and the owned-atoms native runner have no diff against 976cc40. Root's separate uncommitted report was neither edited nor included in this review.

## Fallback semantics and callback order

The C attribute helper already returns NULL for unsupported cases; the R `.set_dta_string_attribute` wrapper now propagates that decline instead of performing the fallback assignment in its own frame. Search of the package's R sources found every production call in `.new_dta_string` and `.restore_dta_variable_metadata`; each now checks NULL and performs the original caller-local assignment. Remaining direct helper uses in tests either require an owned result or explicitly assert decline.

For non-character restoration, `owned <- if (is.character(value)) ...` evaluates to NULL, so it cannot reuse a prior loop result. The original attribute assignment then runs as before. For character restoration, the same `.Call` argument forcing precedes the decision as in 976cc40. A declined `source[[name]]` expression is evaluated again in the setter, but `source` is the ordinary list returned by `attributes(prototype)`, so this does not repeat a foreign [[ method or callback. The `names` promise is forced by the existing is.null guard and retains its value for helper and fallback use.

The native qualifier does not invoke a names setter on object values or attributed/foreign replacement names. The caller therefore executes the actual generic `names<-` operation, including its method dispatch and conversion behavior. The revised test first proves the helper declines without invoking the custom method, then calls the production restoration function and requires one method call, the custom names result, and unchanged source names/class.

The current constructor uses `attr(x, "class") <- classes`, matching the historical setter rather than the temporary working-21 `class<-` spelling. Storage is assigned before class and names after class. Attribute removal remains in the original loop order. This retains the compact path's attribute position behavior.

## Storage and alias disposition

Explicit construction still calls `C_dtatools_capture_string` before removing incoming class or attributes. Ordinary and foreign character inputs, including unknown removable classes, therefore cross the earlier capture boundary. Compact dictionaries retain their separate copy-on-write path. Neither C implementation nor public writable exposure policy changes here.

Qualified owned metadata assignments still fork before `Rf_setAttrib`, preserving independent metadata and shared backing until writes. Declined compact/foreign assignments execute R's original caller-local replacement, which retains its ordinary copy-on-modify and native dictionary Duplicate behavior. Removing the extra helper frame removes avoidable live bindings; it does not authorize mutation through an untracked borrowed payload. Existing large unknown-class/data.table bidirectional isolation, constructor callback validation, owned metadata facts and pointer regressions remain in the focused suite.

The new compact regression requires an actual unmaterialized dictionary fixture. Helper decline must leave its label and cache count unchanged. Empty restoration is checked for value/metadata parity against an ordinary construction and for the explicit ordered attribute list `stata.string.storage`, `class`, `label`. That ordered list matches the retained `dictionary-empty-attributes-7d56080.log` and the historical source's attr(class) policy. The test finally requires the original dictionary to remain unmaterialized with the same cache count and values.

The earlier failed assertion comparing compact attribute order directly to the ordinary constructor's order is preserved in `read-fixes-working-21b-dictionary-fallback.log`. Its only failure reports actual order storage/class/label versus ordinary storage/label/class. The current explicit historical oracle fixes that test assumption while keeping the distinct path's order observable. `read-fixes-working-21b-dictionary-parity.log` ends with DONE and no failure. This is stored focused development evidence, not a reviewer rerun or a fresh final-source gate.

## Allocation evidence and limits

Read-only inspection counted allocations of exactly 2,000,048 bytes in the stored paired Rprofmem files:

| Profile | Count |
| --- | ---: |
| Exact 7d56080 diagnostic | 2 |
| Exact 976cc40 diagnostic | 4 |
| Working 21 diagnostic | 2 |
| Current working 21b diagnostic | 2 |

The 976cc40 file places three such allocations under the setter helper; working 21b retains the historical two stacks under `[.dta_string` and caller-local `.restore_dta_variable_metadata`. This supports removal of the two additional dictionary buffers. Diagnostic scripts retain a sibling and check both the changed target endpoints and unchanged sibling endpoints. Cache counts remain zero before/after. The exact-source diagnostic validates installed source identity; the working diagnostic explicitly uses working-library identity and DLL hash instead, so it is not an exact-commit qualification.

The stored 21b log identifies DLL `76381bb143563252c58c0683af8a7f7b` and reports 0.032 seconds, as does the 7d diagnostic; 976cc40 reports 0.047 seconds in this paired profile. These are diagnostics and do not prove the unchanged original runner's strict four-times-fill bound passed. Working 21's different setter spelling is not substituted for current 21b source review or evidence.

Artifact identities and the allocation counts are saved in `storage-review-round12-evidence-identities.json`. Key hashes: 7d profile `b5cdf5f02547838fdbf1116145d83121b091a2bd2120112707515b58bd6db2ee`; 976 profile `d0ec73ef55a44b4f5b7431ae4469cb1cfafab58754f1989dfb0ef025805cffd7`; 21b profile `672838a26de278e1ada70d4ddfe279a79581d1980e7c1ff1be5ce79cbfbd3fee`; corrected focused log `958632aec1847ab70d187cafe731e2f5e930e611120d0e789ee3425337e5acd3`.

ADR accurately explains the caller-frame boundary. Progress continues to reject 976cc40 and requires renewed review, source qualification and paired acceptance; no native assertion or budget was changed in this diff. No finding remains for this bounded fix snapshot.

## Progress-only addendum

After the primary snapshot, the sole source change was five progress lines at `docs/plans/dibble-result-performance-progress.md`, now SHA-256 `e100fd7d2995e1833fe49920dadee48b9251de6debfb4f9690e1c8b6471b113f`. Its exact text is retained in `storage-review-round12-progress-addendum-source.md`. The production R functions, test and ADR hashes above remain unchanged.

The addition records the parent's completed working-21b run of the unchanged 159 native assertions and 15 readiness checks, explicitly labeled development and separate from the failed exact 976cc40 run. The retained native log and Markdown metrics carry source label `working-21b-dictionary-fallback` and source state `development`; dictionary replacement is 0.032 seconds, fill 0.012 seconds, and total profiled allocation 44,017,136 bytes. These values agree with the added prose. Both original native runner files have no diff from 976cc40. The logs emit final metrics rather than separate assertion-count lines; this bounded review does not independently reconstruct or rerun the 159+15 execution audit.

Stored native metrics identities are `native-working-21b.log` SHA-256 `f2964ea1190beae4033cb5e05bb485f76cc06790635a5ae3eb34a930c71f4bfc` and `native-working-21b.md` SHA-256 `a4c009b9c06f12e1820e855f9ab69556635f521221ffe654c1fdff5b6a208b93`. The addendum is source/evidence-clean and does not change the earlier requirement for fresh committed-source qualification. No workloads were executed for this addendum.
