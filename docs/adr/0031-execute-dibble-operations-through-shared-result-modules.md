---
status: accepted
---

# Execute dibble operations through shared result modules

Dibble operations will execute through package-owned column, row, expression,
and result modules, while optional dplyr methods supply the familiar generics.
This preserves eager Stata typing and the symmetric isolation required by
[ADR 0029](0029-use-explicit-mutation-and-copy-rebind-replacement.md), while
removing repeated whole-table delegation and reconstruction. The staged
[implementation plan](../plans/dibble-result-performance.md) preserves current
functionality until dplyr can become optional.

Column selection, renaming and relocation now share a result context, isolate
retained vectors and normalize each distinct output once before a private
constructor prepares the table. Dataset metadata survives all three selectors,
including grouped and rowwise operations where prior dplyr delegation could
drop notes or custom dataset attributes. Structural row names follow the
existing selector policy: select and relocate reset explicit row names as
tibble subsetting does. Rename preserves explicit row names on ungrouped
tables, including legacy column overlays; grouped and rowwise reconstruction
resets them.
Source identity records lineage only. Ordinary
borrowed strings are validated while an existing generation kernel copies the
result. Reuse requires identical values and attributes; stale declarations,
missing strings and unsupported encodings retain their existing repair path.
This stage changes no native code. No persistent validity flag or ownership claim follows from
an S3 class or a matching address. Ordinary payload copies remain until the
later owned-column stages qualify capture, detachment and every write path.

The selector rules adapt pinned dplyr source with the provenance and full MIT
notice in the installed package's `NOTICE`. dtplyr's copy planning was studied
as a reference; its lazy execution and weaker later-write isolation are not the
dibble contract. Other operation families retain their recorded compatibility
paths until their own direct implementations pass the plan's gates.

Row brackets, `slice_dta_rows()` and the dplyr row hook now share a batch gather
module. Each entry point resolves its own locations before gathering. Brackets
use one integer column to obtain the public tibble or base row-index behavior;
column planning is shallow. Plain base frames gather fallback columns through
base subsetting, preserving named vectors, matrix/nested columns and base drop
shapes. Tibble, explicit helper and row-hook fallbacks retain vctrs semantics.
Base bracket evaluation and attribute policies adapt R 4.6.1, with its
GPL-2-or-later source notice preserved in installed `NOTICE`. The package
remains GPL-3. Existing Stata metadata wrappers retain their evaluation order
and restore both table and column metadata. Plain data.table expressions continue using that
container's own bracket method. Group validation, key extraction, empty factor
group expansion and regrouping use package-owned code and public vctrs/tibble
operations, without runtime dplyr calls.

Ordinary grouped row subsets rebuild keys from the selected values. The dplyr
row hook instead retains existing keys, remaps their row indices and honors
`preserve`. Rowwise reconstruction retains identifiers in template order;
rowwise brackets follow selected-column order. Missing character rows take the
dibble typing path before group reconstruction, keeping the group keys equal
to the normalized string values. Grouped reconstruction preserves dataset
metadata, extending the selector improvement from Stage 1. Unknown inputs to
reconstruction are isolated and validated conservatively.

Row paths preserve the automatic-versus-explicit row-name marker as well as
visible names. The common context also repairs the Stage 1 plain-rename loss
of automatic names. The explicit row helper constructs automatic result names;
its former dibble path accidentally marked them explicit. This correction can
remove an Arrow warning about discarded row-name metadata. Rowwise dibbles now
work through the helper, while ordinary unmarked rowwise frames retain their
previous unsupported status. These changes and grouped dataset metadata
preservation are improvements, separate from the retained indexing policies.

The expression-based `slice()` family remains Stage 6 work. Complete vctrs and
binding integration remains Stage 8 work, and dplyr stays in Imports until
Stage 9 qualifies all package-native features with the dependency absent.
