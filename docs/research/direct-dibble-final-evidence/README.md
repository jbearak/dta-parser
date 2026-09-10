# Final direct-dibble evidence

This bundle accompanies [the final acceptance report](../direct-dibble-final-acceptance.md). Measurements and functional checks refer to merged source `4c2d1f9c2683c15345bb06294ff5fe2d55980f51`, package tree `abc1117250e874353d3cc4fe90f2d8e770b25558`. Each predecessor retains its own identity in the report and records.

The canonical archive contains **8,409 regular files**, totaling **2,007,394,542 uncompressed bytes**. Its compressed size is **178,620,522 bytes**.

| Artifact | SHA-256 |
| --- | --- |
| Canonical `records.tar.gz` | `c03edfc4a2013737b6fd36b5e0d859ba6a82b53513c50208960ccf02eaa7e66e` |
| `selection.json` | `863e78d3bf0bad61b11ee68e98215a10e882b9be93bc609bfd8cc138d9337df2` |

The selected contents passed separate functional, performance, bracket/pipeline and final prose reviews. The archive transport checks every member's order, path, regular-file type, mode, byte count and SHA-256; the independent stream verifier repeats those member checks without extracting or executing producers. Publication copies and staged Git blobs are checked separately. These checks establish the selected bytes, not a reproducible copy of the entire host environment.

## Verify and locate records

The archive is published as three ordered parts: two of 79 MiB and a final 12,945,514-byte part. Each part's size and SHA-256 are recorded in `archive-parts.json`. The parts were compared byte-for-byte with the canonical archive and independently reassembled to its exact digest. They are pieces of one archive, not separate tar files. Reconstruct into a fresh destination:

```sh
python3 reassemble-publication-archive-01.py archive-parts.json records.tar.gz
```

From this directory, verify the canonical archive against the published selection and transport receipt:

```sh
python3 verify-archive-01.py . /tmp/dibble-final-archive-verification.json
```

Use a fresh result path. Exit zero accepts the full member comparison. The verification script uses Python's standard library and does not load R, install dependencies or run a benchmark. `selection.json` lists the exact members and their original absolute paths. Original records retain those paths unchanged: `/private/tmp/PATH` maps to `records/PATH` in the archive. Referenced paths are not additional archive members.

| Record family | Prefix below `records/` |
| --- | --- |
| Final installation, present/native and package checks | `dta-direct-final-acceptance-validation/` |
| Functional reviews and Cargo metadata substitution | `dta-direct-final-acceptance-preparation-01/` |
| Broad atomic/double/memory measurements, including original comparator failure | `dta-direct-final-owned-validation-01/` |
| Separate corrected heap comparison | `dta-direct-final-owned-heap-comparison-01/` |
| Rows, groups, high-cardinality nesting and joins | `dta-direct-final-later-workloads-01/` |
| Three bracket pairs and their comparisons | `dta-direct-final-bracket-validation-01/` through `-03/`, and corresponding assessment prefixes |
| Bracket recurrence and scalar observations | `dta-direct-final-bracket-recurrence-assessment-01/`, `dta-direct-final-bracket-state-observation-01/` |
| Pipeline repeats and saved-data audit | `dta-direct-final-performance-preparation-01/safe-pipeline-repeat-preparation-01/` |
| Failed restricted binding attempt | `dta-direct-final-joins-repeat-validation-01/` |
| Six corrected restricted binding runs | `dta-direct-final-joins-repeat-validation-02/` |
| Result, content-origin and source reviews | `dta-direct-final-performance-preparation-01/api-review/` and `semantics-review/` |

## Replay scope

The selected CSV timing/state tables, allocation profiles, checkpoint logs and narrow scalar/timing RDS records support saved-data inspection and arithmetic. Keep raw timing units, per-case iteration and route order, signed changes and separate repeat pairs. A timing flag requires both a ratio above 1.1 and an increase above 1 ms. The report retains slower cases below that threshold and all allocation increases. Broad timings retain aggregate medians/iteration/GC fields; their absent raw timing vectors cannot be reconstructed.

The task-owned producers, assessors and comparison scripts are included at their selected historical paths. Their original complete input-chain checks require excluded runtimes, installed libraries, source/build exports and some raw consoles. A relocated saved-data replay must map both command arguments and embedded record paths, use fresh output paths, and retain any reader adaptation separately. In particular, the native decoder's outer root and embedded child-summary directories both need relocation. An arithmetic-only replay cannot claim to rerun the original installation or full input-chain checks. New benchmark measurements require a separately prepared source checkout, dependencies, installation and quiet measurement window.

Rprofmem allocation, native counters, retained heap and whole-child RSS are different observations. Scalar backing addresses/depth/byte extents do not independently establish full values, alias isolation or retained memory. Source-bound producer assertions and recorded functional qualification provide those separate claims. Original failed receipts and pending acceptance fields remain unchanged; later scoped reviews supply the final interpretation.

## Included content and exclusions

Only the explicit reviewed file lists are archived. This includes task-owned source, observations from this project's synthetic fixtures, scalar status/environment/file identities, reviews, and governing LICENSE/NOTICE. The Cargo substitution retains 100 package identities and the dependency graph; the original metadata with upstream author/description prose stays local. Its digest and exact allowlisted derivation remain recorded.

Other repositories' source, data, test names, logs and detailed results are excluded, including all detailed fertility records. Only the aggregate no-new-regression and verified-restoration statements in the report are public. Dependency source, installed/runtime/compiler payloads, source/binary package archives, unrestricted session/package-description objects, unrelated RDS graphs, private inspection catalogs, mutable state pointers and unreviewed consoles are also excluded. Metadata may identify excluded files by path and digest without supplying their bytes. Selected runtime facts do not provide complete locale, timezone, RNG, BLAS or environment reconstruction.

The original broad heap-comparator schema failure and first restricted binding terminal-count failure remain visible beside their separate corrections. The latter's failed-run samples are excluded from accepted repeat totals. Historical preparation notes retain their original pending language; completed result and review records determine current status. LICENSE and NOTICE preserve attribution without including the associated dependency source trees.
