Independent storage assessment of PR 195 review 5130642940

Both assigned findings apply to the committed source. The constructor needs a construction-only interface that preserves the existing capture boundary. The width helper can safely release each translation's temporary R allocation after computing its integer width. This is an initial assessment, not clearance of the working fix.

Reviewed identity and limits

The committed source reviewed is 75b0c54c9171bdc747e35d0896611616d151138c in /private/tmp/dta-direct-stage4. Its r-package/dtatools tree is f12a2a1dd430636a33b7f6e953023d90d1ff2589, exactly equal to e343b3b's package tree. storage-assessment-identities.json records the five reviewed source blobs and SHA-256 values, the four captured external review files, and the saved diagnostic sources/results. That identity file has SHA-256 2ec175e6727ce2a42be8fb8e12810548158d374ee296ddf6c73ce57760efc22d.

The substantive source scope was R/dta-string.R, R/dta-numeric.R, src/init.c, src/owned-columns.h and tests/testthat/test-owned-atoms.R. I read saved diagnostics but ran no R, builds, tests, probes, timed workloads or external operations. I made no production or evidence edits. Production edits began during the assessment; committed-source findings below remain bound to 75b0c54. The preliminary four-file fix observed separately is retained as storage-initial-fix-observation.diff, SHA-256 2342f01d4eb55a868532a00cb3fdfd7ebcded3bfc768d83587670fbb1bc4cdec.

Constructor finding 3948630989

The finding is valid. C_capture_string captures ordinary borrowed input into a private record. Every subsequent C_owned_string_attribute call forks the owned handle and sets OWNED_SHARED on that record. Final C_capture_column forks again. The flag remains set after intermediate handles become unreachable, so owned_prepare copies the entire payload on the first Set_elt. Removing only the final capture would leave sharing set by the metadata operations.

The saved constructor-private-red.csv covers 1, 64 and 1000 rows with and without explicit GC. All six constructor cases have shared_before TRUE, changed backing and an extra 8, 512 or 8000 captured bytes on the first write. All six direct-capture controls remain private, retain backing and report zero captured bytes. The script binds the installed e343b3b library and checks values plus borrowed source isolation. Git independently confirms the diagnostic package source equals this review's committed package tree. These are existing diagnostic results, not a newly executed reviewer test or a timing claim.

The review's literal suggestion to apply R metadata before capture is unsafe. The earlier capture exists because metadata changes on arbitrary borrowed or unknown-class strings can produce foreign metadata wrappers while retaining borrowed storage. data.table and retained source aliases must remain isolated in both directions. Prototype, storage and names handling can also execute user code. The capture boundary cannot move across those callbacks merely to eliminate a copy.

A narrow native constructor can capture borrowed values and build ordered attributes on one protected, unpublished handle before returning it. Existing owned inputs must still fork if they have real aliases; exposed inputs must still capture. Do not clear OWNED_SHARED, infer uniqueness from GC, let an R caller assert freshness, or change the general attribute helper to mutate its argument. Those approaches break retained sibling/source isolation or independent metadata. A construction-state design is also possible, but it must keep the payload handle inaccessible until completion and prevent reuse of a mutable token after publication.

Keep the conservative R fallback for prototype restoration, dispatched or attributed names, unsupported metadata, and compact dictionaries. In particular, the native attribute helper's NULL decline and the original attr/names setter in the caller frame preserve the measured dictionary allocation budget. Preserve the historical empty dictionary attribute order and class setter spelling. Fallback conservatism may retain a copy for callback-capable cases; it must be disclosed rather than removed by weakening ownership checks.

Early working-fix finding

The observed preliminary fast path uses is.null(prototype) before C_capture_string and passes storage to .Call before native capture. Both change promise forcing order. Previously prototype and storage could be forced after capture. For example, with raw borrowed from a data.table column, an explicit prototype expression that changes row 1 to "bb" and returns NULL causes the new path to capture "bb"; the old path captures the original "aa" first. A storage promise can produce the same change. This is a source-derived counterexample, not an executed probe. The parent received it immediately.

Eligibility must avoid forcing these promises before the old capture boundary. One option is a private fast entry from a public-constructor point where required inputs have already been evaluated, while keeping .new_dta_string's general fallback ordering. Another is construction state established before metadata evaluation. The current four-file snapshot is not cleared until this ordering is addressed. Its fused native handle and unchanged general attribute helper are otherwise the appropriate ownership direction.

Useful fix checks are a fresh constructor's single initial capture and zero first-write capture, unchanged backing with and without GC, retained ordinary/data.table and owned-sibling isolation, exposed-pointer isolation, and unchanged complete attributes. Retain the existing unknown-class, callback width/NA, custom names, compact dictionary and empty-metadata tests. Add an explicit callback-order case for any constructor entry whose promise order changes. Check construction allocation as well as first-write allocation so an extra copy is not merely moved earlier.

owned_string_width temporary allocation

The nitpick is valid. Rf_translateCharUTF8 can allocate temporary storage for each converted CHARSXP, and owned_scan_strings invokes it repeatedly in one .Call. The saved width probe, generated from the exact committed helper, records 1000 marker changes and retained temporary storage for 1000 Latin-1 strings. ASCII, UTF-8, the particular native-locale fixture and CE_BYTES did not change the marker. All reported widths matched the ordinary R oracle. This supports the Latin-1 case directly; it does not establish that every native-locale string allocates.

Bracket translation inside owned_string_width itself with vmaxget/vmaxset. Compute strlen and save the integer before restoring the marker. The helper returns only an integer, retains no translated pointer, and receives an ordinary rooted CHARSXP during the facts scan. CE_BYTES must continue to use LENGTH without translation. Leave NA handling, fact invalidation, exact-width semantics and publication after the completed scan unchanged. Include the public R_ext/Memory.h declaration. The observed working helper follows this safe lifetime pattern. Runtime parity and the retained-allocation regression still need the parent's authorized validation.

Disposition

Accept both external findings as actionable. Do not accept moving capture after arbitrary metadata callbacks. The preliminary constructor fast-path promise ordering remains an actionable fix-review issue. No other defect was found within this bounded source scope. Native budgets, broader performance acceptance, package gates and external review disposition are not decided by this assessment.
