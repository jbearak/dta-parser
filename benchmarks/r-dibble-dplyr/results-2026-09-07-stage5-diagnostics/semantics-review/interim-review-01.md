# Interim semantics review

Reviewed the actual Stage 5 diff against f622f1ddba04b2bb7ac07415faccf2b417aab0e6, both authoritative handoffs, current tests, ADRs 0029–0034 and NEWS. Production code was not edited by this reviewer. File hashes at this checkpoint are in interim-review-01.json.

The exploratory scripts use the exact c8 installed native library with an R source overlay. They are development witnesses only. They do not establish exact-archive package qualification, supported-runtime acceptance, performance, full provenance closure or optional-dplyr absence. Some early probes sourced their predecessor probe to reuse setup and therefore repeat those earlier cases. Logs are retained unchanged. Source was being edited concurrently, so each log describes the source read when its process started, not an immutable Git candidate.

All findings below were sent with reproducers and fixed in the inspected working diff:

- Duplicate names in unnamed data-frame results selected the first duplicate repeatedly. Numeric-position unpacking now preserves the final duplicate.
- Grouped warnings emitted separately and bypassed `last_dplyr_warnings()`. The optional adapter now invokes dplyr's aggregate warning reporting.
- Deleting a persistent grouping identifier silently dropped grouping, while transmute produced a name-repair error. The final assembly now rejects missing persistent keys. Per-operation `.by` deletion remains separate.
- Rowwise reads treated nested data-frame columns as list columns. The list-vector check now preserves nested data-frame row gathering, including newly computed named frames.
- Grouped bare-column references lost attributes through unnecessary concatenation. The symbol path now preserves the full isolated column while resolving chunks.
- Computed group_by/transmute errors were attributed to mutate. The caller is now propagated.
- Renamed selections in ungroup were silently accepted. Selection now rejects renaming.
- The adapter checked a library DESCRIPTION version rather than the loaded namespace. It now checks the actual namespace version.
- Generation history strongly retained replaced payloads until exit. Weak generation records now allow unused generations to collect while preserving cleanup access to live captures.
- Expired masks retained original columns through lexical argument bindings even after generation cleanup. Inputs are now forced and released, and group/row roots are cleared on forget.

The last cleanup finding has explicit lifetime evidence. lifetime-01.log records the failure. The unchanged runner's lifetime-02.log records the fix. lifetime-captures-01.R/log checks closure, pronoun, quosure and delayed-promise captures after normal evaluation and after a deliberate evaluation error. All eight cases release an input-only weak sentinel after two collections and still report obsolete-mask errors for deferred reads.

The across expansion correction and fixed within-call captures differ from old delegated behavior. They are authorized by the handoff and described explicitly in ADR 0034 and NEWS. Expanded outputs finish evaluation before installation. Named, aliased and unpacked helper calls retain their separate runtime behavior.

No actionable findings remain at this development checkpoint. Final semantics acceptance is pending the final source commit, exact-archive installed package, required suite/native/interoperability/runtime evidence and the quiet-window retained-memory/performance evidence. No timings were run by this reviewer.
