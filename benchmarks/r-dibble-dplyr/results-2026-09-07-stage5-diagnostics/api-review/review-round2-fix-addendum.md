# Second-round fix review

This addendum supersedes the two open findings in
`review-round2-403ff08.md`. No actionable source, evidence-inclusion or runner
finding remains in the reviewed working files. Final exact-candidate execution,
full package/minimum-runtime qualification, measured results and external gates
remain pending; this is not final Stage 5 acceptance.

The new `expression-preflight.R` runs through the tracked Python runner before
every phase. It validates the supplied installation's provenance against the
requested source revision, then verifies the actual loaded namespace/DLL path
and 106 exports. It retains an identity record. A bounded independent functional
probe, `preflight-review-01`, accepts the known exact 985e26b installation with
its matching source identity and rejects a mismatched identity before producing
a passing record. All bound helper and installed-package files remain unchanged.
This probe does not newly freeze the full runtime/dependency closure or qualify
the next production candidate.

The package phase now retains a direct `R CMD check --no-manual` output tree
under its fresh output, in addition to the shared conformance check. Source
inventory guards reject new package files, missing or changed bound inputs are
recorded, dangling outputs are rejected before resolution, and integrity failures
set the final receipt status to failed. The associated guard tests exercise the
three failure classes. The installer also rejects unresolved dangling output
symlinks before doing work.

The additive `inclusion-correction.json` correctly limits file-mode observations
to inclusion time and retains the original manifest, receipt and copy recipe.
Its three source bindings match exactly. `inclusion-audit-02.json` verifies that
all 272 copied records are unchanged and that the current 276-file inventory has
only the intended wrapper/correction records in addition to those copies. The
README links and explains the correction. Correction SHA-256:
`b26d487b3c4cca6654546995e33a89b74526953db879293535001ea0ad67771c`.
The original minimum preview and helper proofs retain their qualified limits
and required license notices.

The expired-promise warning fix and grouping-order fix were reviewed together
with their focused tests. No new API problem was identified. Run and review the
next exact installed candidate before treating these final runtime changes as
qualified. No timings or production edits were performed by this reviewer.
