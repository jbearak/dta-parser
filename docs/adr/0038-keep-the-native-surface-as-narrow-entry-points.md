---
status: accepted
---

# Keep the native surface as narrow entry points

The R-to-native interface stays a table of narrow `.Call` entry points,
each doing one thing, sequenced from R. An architecture review proposed
regrouping them into a few deep transactions (read, write, replace,
storage fit, one probe, one debug entry), moving native-internal tests to
Rust, and folding `dta_temporal` into `dta_numeric`. The review itself
marked the proposal speculative and asked for a re-measurement after the
candidates that each removed a slice of the surface had landed
([ADR 0031](0031-share-result-modules-across-dibble-verbs.md),
[ADR 0036](0036-mutate-by-reference-only-on-dibbles.md),
[ADR 0037](0037-classify-exported-columns-once.md)). This ADR records that
re-measurement and what follows from it.

On the day of the measurement `src/init.c` registered 117 symbols. R code
used 91 of them, 67 exactly once. Tests alone used 23 (the owned-column
probes, the callback vectors, the failure injectors and the patch helper,
reached through about 200 `.Call` sites in 13 test files). Three were
registered but called from nowhere: `C_dtatools_arrow_datasig`,
`C_dtatools_patch_data_column`, and `C_dtatools_replace_table_columns`.
The three dead symbols are deleted with this decision. The rest stays,
for these reasons.

The write cluster in `R/mutate-data.R` is the one place that looks like a
transaction spelled as six calls. Its ordering invariants already live
natively: staging validates before commit, commit performs no allocation,
callback or interrupt check, and the views are released on exit
([ADR 0032](0032-share-owned-double-backing-with-transactional-table-writes.md),
[ADR 0033](0033-share-owned-atomic-backing-and-storage-facts.md)). What R
interleaves between those calls is the evaluation of the caller's
expressions, per group when `by` is set
([ADR 0034](0034-evaluate-dibble-expressions-with-call-local-group-context.md)).
One native transaction would have to run arbitrary R code in its middle,
which is the case the staging design exists to keep out of the commit.
The reference-mutation benchmark also pins the allocation profile at
these call boundaries, so a fold would re-baseline it without reducing
any allocation.

The test-only symbols are a harness, not the interface. Hiding them
behind one probe and one injector dispatcher would leave the 91 symbols R
uses untouched and rewrite about 200 test call sites across 13 pinned
test files for a smaller registration table. The native test manifest
pins those files, so the churn would also reach the release lanes.

Folding `dta_temporal` into `dta_numeric` touches no native entry point.
Both classes share the same native encode and decode primitives; the
distinction is R-level dispatch carrying temporal-kind validation. It is
an R class refactor with its own costs and no bearing on the native
surface, so it is not decided here.

The consequence is that a future review should measure the surface
against this baseline, 114 symbols with 91 used from R and 23 test-only,
rather than re-proposing the transaction grouping. A regrouping becomes
worth designing when a native call sequence carries an ordering invariant
that R alone enforces, which the write cluster does not.
