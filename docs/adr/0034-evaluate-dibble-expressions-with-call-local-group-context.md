---
status: proposed
---

# Evaluate dibble expressions with call-local group context

The shared expression module owns group iteration, sizing, sequential visibility
and column installation. Direct mutate, transmute and computed group_by use it;
rowwise and ungroup assemble metadata through the existing grouping module.
Dibble output remains eager, typed and isolated under ADR 0029. Dataset attributes
also survive grouped expression and grouping operations, extending the earlier
direct selector/row metadata preservation to paths whose delegation could drop
them. This includes arbitrary dataset attributes as well as DTA metadata.
No public generic
or export is added. Reference-marked plain containers retain their ordinary
container behavior through the existing compatibility methods.

Each call captures isolated public column handles before invoking expressions.
Fresh lexical masks bind fixed groups and column generations. Reading a value
marks that column used, including arbitrary helpers accessing `.data`. Later
expressions see newly typed values, including Stata missing ordering and normalized
strings. Foreign callback values are captured before another group can mutate
their source. The evaluator never passes private ordinary backing to R code.

Closures, pronouns, promises and quosures can retain these masks. During the call
they resolve the generation and group they captured, so later replacement cannot
change an earlier capture. At exit, deferred column resolution raises the existing
obsolete-mask error and the generations release their payloads. Already evaluated
values remain usable and isolated. All exits, including interrupts, restore the
outer helper context. This strengthens within-call captures relative to the old
live bindings, while preserving the established post-call invalidation contract.

Mask setup keeps a unique history of column names for expiry, including names
removed and later re-added during the call. Each internal addition supplies one
plain character name, so a membership check and append preserve first-seen order
without rebuilding that set. Every generation still receives its isolated
metadata copy and weak cleanup reference. Metadata copying returns non-data.table
values before table repair checks; actual data.tables retain their existing
marker and capacity repair. Both changes followed a reproduced wide-column
overhead and ordinary sampling profiles, with separate exact-source variants
and public timing checks before integration.

Qualified and aliased dplyr helpers execute their real implementations against
a narrow optional adapter. It isolates private context installation, across/pick
expansion and warning aggregation. Group metadata and the core evaluator contain
no whole-verb calls. The adapter restores both values and presence of its four
context slots, including nested operations. Warning records feed dplyr's existing
aggregate reporting and `last_dplyr_warnings()` when the adapter is active.
The namespace is inspected only when already loaded.

Unnamed across now follows dplyr's expansion order: each selected column runs
across all groups, with function setup once for the whole expression. Every
expanded result evaluates before any of them enters the mask. The old typing
wrapper prevented expansion and caused group-first evaluation and repeated
factory side effects. This is an explicit correction toward dplyr helper
interoperability. Named, aliased, extra-dot and unpacked calls retain the runtime
helper path, including its measured setup counts. Expanded pick selects against
full current columns; arbitrary helper fallback selects against group slices.
These paths deliberately differ for value-dependent selectors.

The supported dplyr minimum is explicitly corrected from 1.1.0 to 1.2.1 while
it remains in Imports. The [minimum-version study](../research/dplyr-r46-minimum.md)
finds 1.2.1 is the first pristine source-installable release on the supported
R 4.6.0 floor. Six older source releases fail before execution. One older CRAN
binary also fails loading; this bounded result does not establish that all older
binaries are unusable. No reproducible usable older binary was qualified for
this adapter. The standalone helper proof passes on both R 4.6.0 and 4.6.1;
production integration still requires exact-source qualification on both.

Pinned dplyr implementation and tests informed these policies. Installed NOTICE
records each adaptation and optional call and retains the full MIT terms.
The full absence declaration and load-order matrix remain Stage 9 work.
Filtering, arrangement, distinct and the slice family still await Stage 6;
summary/nesting/callback evaluation remains Stage 7; joins and binding remain
Stage 8. Their existing delegation is not described as direct execution.
