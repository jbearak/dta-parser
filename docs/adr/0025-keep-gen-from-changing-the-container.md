---
status: accepted
---

# Keep explicit mutation independent of container conversion

Explicit helpers mutate the supplied physical table on every supported container:
ordinary base data frames, tibbles, dibbles, and data.tables. Existing columns keep
their classes. Generation types its new column under the Stata generation rules,
but the container remains the same. Only explicit `as_dibble()` conversion asks
for Stata typing of the whole dataset. Ordinary replacement uses copy-and-rebind
semantics, as recorded in [ADR 0029](0029-use-explicit-mutation-and-copy-rebind-replacement.md).

Supporting plain containers avoids an implicit conversion that changes the meaning
of existing columns. An expression on a bare character column still distinguishes
`NA` and `""`; a Stata string column treats them as the same missing value. Returning
a copy from the same explicit helper on some containers would make caller mutation
depend on an input class, so that alternative is rejected.

Support covers complete known class chains and the package's reference and metadata
markers. Arbitrary subclasses may have invariants that a physical column commit
cannot preserve. Helpers reject them before evaluating runtime targets or updates.
The recovery is explicit and assigned: `data <- as_dibble(data)` discards additional
container classes, keeps recognized grouped or rowwise structure and metadata, and
types columns. It does not preserve the discarded subclass's invariants. A stray
reference marker on data.table is rejected and can be recovered by the same conversion.

Grouped tibbles and dibbles supply groups to `gen()`, `egen()`, and `repl()`.
The validator checks that group rows cover the table in physical row order and agree with distinct group keys;
value replacement rebuilds grouping after a grouping column changes. Metadata
helpers support grouped and rowwise tables without changing their groups. Column
structure and row-reordering helpers require assigned ungrouping first. Rowwise
value mutation is unsupported. Assigned `copy_data()` and `reserve_columns()`
accept valid grouped and rowwise inputs.

[ADR 0030](0030-require-assigned-column-preparation.md) defines capacity and assigned
preparation. Helpers never convert or rebind a target to repair capacity. Metadata
and same-size value edits need no spare slots; structural edits use the same early
checks on every container. data.table requires version 1.18.2.1 or newer and retains
its native zero-row empty-table convention: dropping its last column clears stored
row names as well. Base data frames, tibbles, and dibbles retain their row count with
zero columns. Copies, serialization, and later generation must agree with those shapes.

This revises the original ADR 0025 and supersedes ADR 0021's automatic tibble-to-dibble
conversion. Reference bookkeeping is separate from dibble type, and no helper routes
writes through an object retained in shared state. Converting a function parameter
still does not make ordinary nested attribute replacement reach its caller. Use the
explicit metadata setters from [ADR 0028](0028-edit-metadata-on-the-supplied-table.md).

Dibble identity is the leading public S3 class `dibble`. An ungrouped dibble has
`c("dibble", "dtatools_ref_data", "tbl_df", "tbl", "data.frame")`; grouping and
metadata classes follow the two package classes. `dtatools_ref_data` remains
shared support for explicit reference mutation, so ordinary tibbles and base
frames can carry it without becoming dibbles or typing existing columns.
Creation and restoration build this class chain centrally. Ordinary-container
conversions and internal delegation snapshots remove both classes. Printing
uses the real `dibble` dispatch and pillar summary hook, retaining dataset
identity on a display snapshot without changing stored columns.
