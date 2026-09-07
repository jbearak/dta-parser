# Read and callback diagnosis

These are development experiments and preserved failure evidence. They do not
replace the final exact-source operation, allocation or memory matrices.

The original `read-fixes-red.log` includes the Arrow callback failure: a later
metadata callback replaces the source after the writer has inspected it, and
the old writer emits the replacement values. Other failures in that log concern
the proposed planning/adoption behavior. The new bounded
`owned-string-writer-callback-reproduction.R` replays the correctness failure
with exact installation guards. Its `7d56080` log fails after a real callback
write; its `e343b3b` log preserves the original writer output. These new replays
are distinct from the original red run.

The independent unknown-class constructor probe retains its original red and
working logs. The later `unknown-string-constructor-reproduction.R` adds exact
installation guards and checks both mutation directions at 64, 1,000 and
1,000,000 rows. It fails on `7d56080` after foreign `data.table::set()` changes the
captured result. The final source preserves the captured values and removes the
unknown class and encoded attribute as expected.

`accessor-prototype/` contains the source, build logs, controls and results for
the bounded getter experiment. The original four variants compare record and
direct-payload lookup with element and typed-pointer access. The fifth uses an
external pointer whose protected field roots ordinary storage. The prototype
has no production write/subset contract and cannot qualify mean or range.
The first external-pointer run overlapped a brief R source inspection and is
superseded for quiet timing by `accessor-probe-repeat*`. Compiled prototype
artifacts are represented by digests; rebuild the retained C source with
`R CMD SHLIB` using the recorded R version.

The first attempted working-17 header rebuild reused the working-16 object.
Its install/test/aggregate logs are retained with
`working-17-stale-object-disclosure.json` and must not be attributed to the new
record. The rebuilt working-17 logs have the corrected DLL identity. Explicit
header dependencies now prevent that stale-object path. No exact archive
qualification used that stale development object.

Working-19 and working-20 aggregate logs show the effects of ordinary factor
deep duplication and ordinary public logical subset results. The 30-case
working-20 matrix includes the remaining missingness/coercion costs. These
medians and the getter experiment inform diagnosis; the final unchanged paired
runner determines the residual operations and their repeatability. Source/API
constraints alone do not turn a flagged regression into a passing result.

The preserved `976cc40` native failure led to the dictionary allocation profiles.
At five million rows and 250,000 dictionary entries, `976cc40` adds two
2,000,048-byte buffers in an R fallback helper. Working-21b restores assignments
to their original caller frames and removes both buffers. Working-21 used the
`class<-` spelling during development; its recorded function body is
retained. Working-21b and final source use the original `attr(x, "class") <-`
spelling. The final unchanged native runner records 32 ms against an 11.4 ms
fill reference and 44,017,136 bytes, matching the prior allocation.

Two test-fixture corrections are kept explicit. Working-20's full suite failed
an obsolete nullable-Arrow expectation; the replacement assertion distinguishes
eager owned storage from dictionary storage and retains exact value/type/NA
checks. The first compact fallback test compared its attribute order with an
ordinary-vector constructor. The corrected test uses the independently observed
`7d56080` compact order. Both original failed logs remain here; final full R
check and all unchanged native budgets pass.

The [implementation evidence index](../qualification/implementation-evidence-index.json)
records copied sources and logs. The small getter binary-digest file is authored
metadata rather than a copied raw artifact. Reproduction scripts refer to the
recorded isolated libraries; obtain new libraries with the archive installer
before replaying a revision on another machine.

The later [filter-planning supplement](filter-planning/filter-planning-diagnosis-findings.md)
preserves 21 exact-installation boundary measurements, all samples, the first
failed runner attempt and its source, and the successful runner. Its separate
archive index leaves the original 247-artifact index unchanged. Sampling's
1 ms minimum and the ineffective cached-closure trace are disclosed. The three
filter regressions remain required Stage 6 work, distinct from twelve measured
per-element read costs; this diagnosis does not claim broad performance acceptance.
