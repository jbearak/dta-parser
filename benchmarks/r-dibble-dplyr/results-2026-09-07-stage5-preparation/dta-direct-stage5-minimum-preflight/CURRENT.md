# Current archive navigation and verification

This guide was added for PR #200 review. The original 183 files in that PR,
including all research-note copies, raw scripts, preview README, SHA256SUMS and
original index, remain unchanged. Their words and paths retain their historical
meaning. Start with this guide when navigating the repository copy.

| Historical reference | Repository location |
| --- | --- |
| Final research note | [Promoted copy](dplyr-r46-minimum.md), [raw copy](raw/dplyr-r46-minimum.md), or [research-doc copy](../../../../docs/research/dplyr-r46-minimum.md). All three retain identical bytes. |
| `manifests/artifact-index.json` | [supplementary/original-artifact-index.json](supplementary/original-artifact-index.json). This is the unchanged 189-file historical index. |
| Other selected `manifests/` files | [raw/manifests/](raw/manifests/). |
| `verify-final-preflight.py` | [raw/verify-final-preflight.py](raw/verify-final-preflight.py), preserved with its original behavior. |
| Original preview and omission scope | [README.md](README.md), [selection-index.json](selection-index.json), and [external-inputs.json](external-inputs.json). |

The historical [SHA256SUMS](SHA256SUMS) covers the original 180 preview files
and excludes itself. It predates the promoted note and does not claim to cover
that additional file. The new [current archive index](current-archive-index.json)
covers every current file in this archive, including the promoted note and
original SHA256SUMS, plus the research-doc note and its navigation companion.
It excludes only itself and its separate
[completed receipt](current-archive-receipt.json). The receipt binds the completed
index. File modes in the new index are observations made during this inclusion;
they do not establish unrecorded historical modes.
The index and receipt detect changes to this copy; neither is an external
authenticity anchor. The new [index writer](review-fixes/write-current-index.py)
creates both only at fresh paths.

From the repository root, verify the current copy with:

```sh
python3 -B benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-preparation/dta-direct-stage5-minimum-preflight/review-fixes/verify-current-evidence.py .
```

## Original verifier limit

The old `source_archive()` loop checked byte equality for each regular file
listed in a tar archive. It skipped other member types, followed filesystem
paths when reading bytes and did not enumerate the extracted tree. Its results
therefore establish original-member byte checks, not the absence of added
`.R`, `Makevars`, other files or filesystem symlinks. This qualifies the old
verifier's coverage wherever the historical note uses the word "pristine."
No new script or receipt is presented as something run during that study.

## New pre-build replay guard

[verify-pristine-tree.py](review-fixes/verify-pristine-tree.py) is a new read-only
guard for a fresh extraction, before a build creates additional files. Given
an archive's independently expected SHA-256, it checks exact file/directory
membership, file bytes and recorded permission modes. It rejects unsafe or
duplicate archive names, links and special members, and any filesystem symlink
or unexpected entry. Archives with links or special members are unsupported.
Keep the input archive and tree idle during verification; this is not a
concurrent-mutation monitor. The guard neither extracts nor executes source.

```sh
python3 -B path/to/verify-pristine-tree.py ARCHIVE FRESH_TREE ARCHIVE_SHA256
```

[Fifteen synthetic tests](review-fixes/test-verify-pristine-tree.py) cover extra
source/Makevars files, an empty directory, missing or altered members, mode
changes, identical-byte and broken symlinks, directory links, bad archive hashes,
duplicate archive names, path traversal and archive symlinks. A separate fresh
extraction of the pinned dplyr 1.2.1 archive also passes the new guard. These
tests did not run R or repeat the source-build or minimum-version experiment.
The fresh archive check covers 468 files and 22 directories. Eight separate
[index tests](review-fixes/test-verify-current-evidence.py) check altered promoted
notes, extra or missing files, symlinks, duplicate or out-of-scope records and an
index whose receipt no longer matches.

The first new attempt passed all synthetic tests, then rejected the fresh
extraction because Python's safe extraction filter normalizes permissions.
Its [failed record](review-fixes/history/guard-checks-01/execution-result.json)
and exact executed scripts remain preserved. The
[new runner](review-fixes/run-checks.py) validates supported archive paths/types,
extracts into a new directory, and restores the pinned permission modes only
there before invoking the guard. The
[second attempt](review-fixes/history/guard-checks-02/execution-result.json)
passes the source-tree tests. Review then found two runner limits: it invoked
the unresolved Python path while binding the resolved executable, and its
output manifest excluded matching basenames at every depth. Those runner bytes
are preserved under `history/guard-checks-02-source/`. The corrected
[third attempt](review-fixes/history/guard-checks-03/execution-result.json)
invokes the bound resolved executable and excludes only the two output-root
manifest/receipt paths. All 23 synthetic cases and the fresh archive check pass
with unchanged bound inputs.

The copied check records omit their generated fresh source trees. Their full
product identities remain in the original output manifests. Full Python and
OS runtime closures were not frozen. The missing old writer/context bytes,
omitted downloads and historical host-binding limits in the original preview
remain unresolved replay limits. New guard coverage does not retroactively
strengthen them or qualify the dtatools expression adapter.
