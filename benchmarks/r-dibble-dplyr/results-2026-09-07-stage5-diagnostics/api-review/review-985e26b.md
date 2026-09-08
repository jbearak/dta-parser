# Stage 5 API, tests, documentation and provenance review

Reviewed source checkpoint: `985e26b42590da400466a40ea6a41e7032e96cf4` in
`/private/tmp/dta-direct-stage5`, against actual predecessor
`f622f1ddba04b2bb7ac07415faccf2b417aab0e6`.

No actionable source findings remain at this checkpoint. This is an interim
source review, not final Stage 5 acceptance. Final evidence inclusion, complete
package and R-minimum qualification, performance findings, and external gates
remain outside the completed review.

Both full handoffs, repository CONTRIBUTING/CONTEXT, the operative plan,
ADRs 0029 through 0034, actual changed production/tests/docs, installed NOTICE,
DESCRIPTION, and the new exact installer/helper were read. The unslop skill
was applied. No production files were edited by this reviewer and no timings
were run.

## Findings resolved

- Transmute and computed group_by inherited mutate caller labels. The evaluator
  now receives the actual caller; dedicated error/warning tests were added.
- Direct ungroup allowed renamed tidyselect expressions and retained the wrong
  grouping variable. `allow_rename = FALSE` restores rejection, with regression
  coverage.
- Plain ungroup reset explicit raw row names. It now preserves those row names
  only for already ungrouped input, matching the predecessor; the regression
  also checks later-write isolation.
- Every obsolete generation was retained strongly until call exit. Weak
  references allow uncaptured generations to be collected; the later cleanup
  fix forces arguments and releases original columns/group metadata. Semantics
  review independently examined this lifetime issue.
- The documented stronger within-call snapshot contract lacked a direct
  witness. Tests now force saved closures, pronouns, quosures and promises after
  later replacement/groups and retain the post-call obsolete-mask behavior.
- NOTICE now names the new ungroup source-function policies. The minimum
  correction, across setup/order correction and within-call capture change are
  explicit in ADR 0034 and NEWS. Candidate install output now uses candidate
  labels. One failure-only helper string still says "Tiny baseline load check
  failed"; this cosmetic wording does not affect evidence or qualification.

All 106 public exports and complete NAMESPACE bytes are unchanged from the
predecessor. The adapter confines private context/expansion/warning access to
one file and retains installed dplyr implementations. It does not change
namespace function bodies or move dplyr out of Imports.

## Independent checks

`probe-01.R` compares ten API cases using the exact installed predecessor and
an early working-R development overlay. It reproduced the ungroup renamed-
selector defect and verified the caller correction. Its explicit scope is a
development diagnostic, not an installed-candidate qualification.

`probe-02.R` compares selected installed predecessor/candidate row-name and
zero-column cases. It reproduced the plain-ungroup row-name loss in 27d700d.
Other new methods matched the predecessor row-name policy; zero-column input
with zero or two rows worked.

`installed-api-985e26b-output/result.json` records the successful independent
checks on the exact installed 985e26b artifact. These cover namespace-only
loading, the 106 exports, corrected selectors/row names/callers, source/result
isolation, within-call captures/post-call expiry, zero-column inputs, and
sequential Stata typing. Bound probe/helper/installed files remain unchanged.
The actual package source archive and installed NOTICE bytes match SHA-256
`2b7092d0e91ef0012dc4496edfcef267781ef8a4c9165c2bfee72691408cda98`.
The exact installer receipt supplies source/artifact identity. This API probe
does not newly freeze the complete runtime/dependency closure, validate a
release binary, or replace the full package/R-minimum/performance gates.

## Preparation evidence

The full minimum-version note, selective-preview README, original helper
README/PROVENANCE and R 4.6.0 extension README were read. Their claims distinguish
six pristine source compilation failures, one bounded older-binary load failure,
a 35-case standalone helper proof, and production obligations. They preserve
rejected mixed-runtime attempts, missing historical writer/context identities,
unfrozen host closure limits and the later R 4.6.0 extension's separate scope.
No blanket claim that every older installed binary is unusable is made.

`preparation-inventory-audit.json` independently verifies every size/hash/current
mode in the 66-record helper and 19-record extension indexes, and the complete
181-file minimum-preview checksum inventory. The selected minimum preview has
4,657,534 bytes and explains all 33 omitted indexed artifacts. This is preparatory
inventory review; it does not yet verify final repository inclusion or execute
historical absolute-path recipes.

Reopen this reviewer for the final evidence destinations, latest source changes
and complete installed qualification results before recording final clean review.
