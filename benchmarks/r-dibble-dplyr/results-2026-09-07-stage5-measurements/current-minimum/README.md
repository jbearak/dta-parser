# Combined Stage 5 on clean R 4.6.0

This archive retains the clean minimum-runtime checks for source
[`a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9`](https://github.com/jbearak/dta-parser/commit/a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9),
package tree `b08c77d91bdce67032f13aced90c29d068d6e95a`.
The installation used a clean R 4.6.0 runtime and the separately built dependency
library. All eight before/after image guards recorded one clean `libR`, with no
Homebrew R namespace in the tested processes.

The public behavior check passed eight cases, and the expansion check passed
four comparisons. The focused suite recorded 8,859 passing assertions, no
failures or errors, three capability skips and four established warnings. The
22 expression-test rows contain 187 passing assertions without issues. Two
skips require Arrow and one requires the memory profiler. These checks do not
establish minimum-runtime profiling acceptance or a full R 4.6.0 package check.

The [root count reconciliation](root-r460-integration/candidate-a2d8b6a-root-summary.json)
binds the four completed run receipts and the focused-test CSV. Both independent
reviews retain their own checks and limitations:
[API review](implementation/api-review/combined-minimum-review-01.md) and
[semantics review](implementation/semantics-review/combined-minimum-evidence-review-03.json).
Earlier reviewer-only attempts remain alongside their corrected versions.

The [selection](selection.json) identifies each original file by source path,
relative archive path, size, mode and SHA-256. Executed drivers, checks, review
scripts and this description remain plain files. Repeated input indexes, logs,
saved R objects and related dependency-build records are in `records.tar.gz`.
The bundle preserves the selected bytes and Unix modes. Tar timestamps and
owner fields are normalized; they are not historical execution metadata.

Verify every selected file without extracting tar paths:

```sh
python3 bundle-evidence-v1.py verify .
```

This is a selective retained-record archive. Runtime installations, generated
source exports, source tarballs and build trees are omitted, with their
identities retained in the original records. Absolute paths describe the
original environment. The verifier checks bundle consistency, not external
authenticity, concurrent mutation, omitted runtime inputs or fresh execution.
The full external OS, SDK and Python runtime closure were not frozen. Local
reviewers inspect the selected contents; no claim is made that an external
review service inspects compressed contents.

Host package/native qualification, performance, external PR gates and the
remaining direct-operation and optional-dplyr stages remain separate.
