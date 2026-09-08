# Combined Stage 5 host qualification

These records qualify the combined expression evaluator, mask setup changes and
native interrupt-test correction at source
[`a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9`](https://github.com/jbearak/dta-parser/commit/a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9).
The package tree is `b08c77d91bdce67032f13aced90c29d068d6e95a`.
The preserved
[source history](https://github.com/jbearak/dta-parser/tree/codex/provenance-stage5-combined-a2d8b6a)
also contains the earlier implementation. The documentation-only commit
`ea031bec2df4d6711f1214b5dd3d00ebf029b3f1` has the same package tree.

| Gate | Recorded result | Evidence |
| --- | --- | --- |
| Fresh installation | Exact source, 234 archived source files, 106 public exports, installed NOTICE preserved | [Receipt](candidate-combined-01/completed-receipt.json) |
| Full R suite | 16,750 passing assertions, no failures/errors/skips, four established warnings | [Results](full-combined-01/tests.csv), [review](api-review/combined-install-full-rust-review-01.md) |
| Rust | Formatting, clippy, tests, documentation build and package verification pass; 278 tests and eleven established package warnings | [Review](api-review/combined-install-full-rust-review-01.md) |
| Package | Sixteen commands pass, including conformance, interoperability, documentation and source/binary notice checks | [Review](api-review/combined-package-review-01.md) |
| Native | Mutation, rollback, allocation, atomic writes and rename gates pass | [Review](api-review/combined-native-review-01.md) |

The R package check retains three established warnings for macOS deployment
targets, vendored GNU Make extensions and Rust's `_abort` entry, plus two notes
for a vendored CITATION file and a generated C file without a terminal newline.
Its test output also retains the four established test warnings. The Rust
package warnings identify intentionally omitted integration tests. A successful
documentation build is recorded separately from test execution.

The native evidence includes 18 atomic write cases. Rename records 80,112 bytes
for the dibble, with a largest allocation of 40,056 bytes, below its 800,000-byte
gate. That profiler records allocations above a 10,000-byte threshold. Native
logs do not contain a separate assertion ledger, and temporary allocation-event
files were removed by the original runners. The atomic subrunner records
worktree `ea031bec`, while both consumed helper files match the bound `a2d8b6a`
source and the installed package remains `a2d8b6a`.

Both independent source and completed-output reviews are retained. Their
statements about gates pending at the time of each review remain historical.
Eight earlier bounded-review reports cited by the combined source review are
included with their original source identities. Their experimental records are
separate; they do not replace these combined-source gates.

The archive contains 116 original gate files and 34 original review files, plus
the archive recipe, selection, README and inclusion records. The recipe checks
the five pinned gate receipts, their manifest bindings and every selected gate
product before copying. It checks all 150 selected files against the explicit
selection and checks source and destination bytes and modes after copying.
This is an idle-file consistency check, with no concurrent-mutation guarantee.

Generated source exports, installations, native binaries, source/crate archives
and build trees are omitted. Their original identities remain in the retained
indexes. Absolute paths in historical scripts and records describe the actual
execution environment. This selective archive is not a standalone replay bundle
or a fresh execution of the gates. External OS libraries, the full SDK and the
full Python runtime closure were outside the original input contract.

Clean R 4.6.0 integration, performance measurements and external PR gates have
their own evidence. This host archive alone does not establish performance
acceptance, completion of Stage 5, or the later optional-dplyr stages.
