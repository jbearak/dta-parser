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
column planning is shallow. Plain data.table expressions continue using that
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

The expression-based `slice()` family remains Stage 6 work. Complete vctrs and
binding integration remains Stage 8 work, and dplyr stays in Imports until
Stage 9 qualifies all package-native features with the dependency absent.
