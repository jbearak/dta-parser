# Stage 5 preparation evidence

This archive preserves the minimum-version study and bounded helper proofs
that preceded the production evaluator. It contains no production qualification
or performance results. Historical reports keep their original words, paths,
identities and limits.

Read the [minimum-version preview](dta-direct-stage5-minimum-preflight/README.md),
[original helper proof](dta-direct-stage5-helper-proof/README.md), and
[clean R 4.6.0 extension](dta-direct-stage5-helper-proof-r460/README.md).
The source mappings and full MIT notice for adapted helper material are in
[PROVENANCE.md](dta-direct-stage5-helper-proof/PROVENANCE.md). Production source
adaptations have their separate installed package NOTICE.

The minimum study remains a selective archive: 181 prepared files preserve the
readable evidence and classify 33 omitted indexed inputs, including large
upstream downloads and generated native products. Primary URLs, hashes and
build references are retained. The helper proofs include all 66 and 19 indexed
files, respectively, plus each index and receipt. A second exact copy of the
minimum note at its historical sibling-relative location keeps the helper
report's link usable. No archive, installed library, installer or expanded
upstream build tree was added by this inclusion.

The historical [copy recipe](archive-preparation.py) checked the pinned preview
checksum list and the indexed helper-proof inputs before copying them. Its
additional sibling-note copy checked source/destination byte equality and
recorded the copied hash, but did not compare that source with the preview's
indexed raw note before copying. The [inclusion manifest](inclusion-manifest.json)
maps 272 copied files to their original absolute paths, current modes, lengths
and hashes; its [receipt](inclusion-receipt.json) binds the completed manifest.
Those counts include the recipe itself and the additional note copy. This
wrapper and the two inclusion records are new documentation, separate from
those copied historical bytes. Historical absolute-path recipes are review
records and must not be executed against this archive in place.

The new [note consistency check](review-fixes/verify-note-consistency.py) verifies
both archived note copies against the raw note's entry in the original pinned
preview checksum list and against their original inclusion records. It also
checks that the historical recipe, manifest and receipt retain their pinned
bytes. This is a current archive check; it does not establish that the missing
comparison ran during preparation. Run it with the preparation archive path:

```sh
python3 -B benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-preparation/review-fixes/verify-note-consistency.py benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-preparation
```

The checker requires an idle archive and checks only these six named inputs.
Its pins preserve the reviewed record; they are not an external authenticity
anchor. [Bounded tests](review-fixes/test-note-consistency.py) alter temporary
copies to exercise corruption and missing/link inputs without changing this
archive. The [new check record](review-fixes/note-checks-01/execution-result.json)
retains the actual command results and bound inputs. No experiment was rerun.

The additive [inclusion correction](inclusion-correction.json) qualifies the
new manifest's phrase “historical bytes/modes preserved.” Historical indexes
establish the copied bytes; file modes were observed when this archive was
made. The original minimum-study index did not record historical modes, so
those observations cannot establish equality with its earlier modes. The
original manifest, receipt and copy recipe remain unchanged.

The original minimum study's missing historical writer/context bytes and
unfrozen host binaries remain explicit limits. The later R 4.6.0 helper run
adds new external dylib observations; it does not strengthen older records
retroactively. The prototype's readable deferred snapshots, lack of Stata
sequencing and result assembly remain prototype limits, not accepted behavior
of the production evaluator.

Review is split into the minimum-version evidence, helper-context evidence,
and production/qualification changes so each external review can inspect its
actual scope. This preserves every required proof and does not change review
filters. The direct expression implementation and the dplyr 1.2.1 minimum
decision are described in ADR 0034 and remain subject to production checks.
