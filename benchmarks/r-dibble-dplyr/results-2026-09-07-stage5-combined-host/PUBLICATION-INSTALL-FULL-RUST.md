# Stage 5 installation, full R and Rust records

This is the first partial publication of the combined host evidence. It contains
63 unchanged historical files: 23 installation records, 13 full R suite records,
20 Rust records and seven corresponding independent review files. The
[subset manifest](publication-install-full-rust.json) identifies every copied
file by source Git blob, bytes, SHA-256 and Unix mode, and retains its original
archive source identity. This note and that manifest are the only new files.

The recorded package source is
[`a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9`](https://github.com/jbearak/dta-parser/commit/a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9),
with package tree `b08c77d91bdce67032f13aced90c29d068d6e95a`.
Publishing these records does not install that source into the repository's
package. This evidence-only change retains the predecessor package tree
`f88005766aee9b9dd5827b33a3930feff6672008`.

| Recorded gate | Result | Retained evidence |
| --- | --- | --- |
| Installation | Exact source export and 106 public exports; 28 retained deployment-target linker warnings | [Receipt](candidate-combined-01/completed-receipt.json) |
| Full R suite | 16,750 passing assertions, no failures/errors/skips, four established warnings | [Results](full-combined-01/tests.csv), [receipt](full-combined-01/receipt.json) |
| Rust | Formatting, clippy, 278 tests, documentation build and package verification pass; eleven established package warnings | [Receipt](rust-combined-01/receipt.json), [review](api-review/combined-install-full-rust-review-01.md) |

The [API review](api-review/combined-install-full-rust-review-01.md) and
[semantics review](semantics-review/combined-install-rust-full-evidence-review-01.json)
describe their original completed checks. Their counts of products and bound
inputs cover the original local runs, which were larger than this published
subset. Their statements about then-pending gates remain historical. The four
R warnings and eleven Rust package warnings are retained in the logs and review;
the documentation result is a build, not a separate doctest claim.

The other 92 files from the reviewed 155-file host archive are deferred to a
second evidence publication. They include package/native records, other reviews
and the original whole-host README, selection, recipe and inclusion records.
This subset does not claim that those files have already been published here.
The complete reviewed source archive remains identified by Git commit
`ccb7182f02c65a845d8714dfb0e30c77a2d411fb` in the new subset manifest.

Historical scripts and absolute paths record their actual local dependencies.
They are immutable provenance, not portable checkout rerun commands. Referenced
source exports, installations, build products, runtime trees and other review
inputs are not all included. Original Python optimization flags and an exact
name-to-executable mapping for historical bare-command launches were not fully
recorded; no such guarantee is inferred from candidate tool bindings. The
installation commands retain their recorded absolute executable paths.

The current publication check compares the selected files with their source
Git objects and original archive identities. It is an idle-file consistency
check, not a rerun of the historical audits or their R/Rust workloads, a
standalone replay bundle, complete runtime closure or concurrent-mutation check.
No historical scripts, assertions, results or receipts were regenerated. This
partial publication does not establish performance acceptance, Stage 5
completion or completion of later optional-dplyr stages.
