---
status: accepted
---

# Mutate by reference only on dibbles

Every explicit by-reference helper accepts only a dibble as its mutation
target: the value helpers `gen()`, `egen()`, `repl()`, `replace_values()`, and
dibble `:=`; the structural helpers `keep_vars()`, `drop_vars()`,
`rename_vars()`, `order_vars()`, and `reorder_dta_rows()`; the table forms of
the metadata setters of [ADR 0028](0028-edit-metadata-on-the-supplied-table.md);
and the capacity helpers `reserve_columns()`, `copy_data()`, `column_capacity()`,
and `can_add_columns()`. Copying operations such as `slice_dta_rows()` and
`dta_merge()` keep accepting every output container. A base data frame,
tibble, or data.table is rejected with an error that names the assigned
recovery, `data <- as_dibble(data)`. A data.table user who wants by-reference
mutation without Stata typing uses data.table's own operators. The
`dtatools_ref_data` class and its reference state are internal to the dibble;
no plain container carries them, and every method registered on that class
moves to the dibble.

Mutation by reference was implemented before the dibble existed, so
[ADR 0025](0025-keep-gen-from-changing-the-container.md) supported it on all
four output containers and forbade implicit conversion. In hindsight the plain
containers were the wrong place for it: the marker class doubled the method
surface (37 methods, 21 one-line delegates, 31 `is_dibble()` preludes), every
writer carried a per-container commit branch, `is_dibble()` had to consult a
stored flag rather than the class, and the by-reference contract on a tibble
or data frame contradicted R's own copy semantics for those classes. The
dibble is the container built for this contract. Returning a modified copy
from plain containers was rejected for the reason 0025 gives: caller mutation
would depend on the input class. A one-release deprecation period was rejected
because it keeps the whole marker path alive for the period.

This supersedes ADR 0025, narrows [ADR 0017](0017-support-data-table-as-a-package-wide-container.md)
to reading, table-producing, and copying operations (data.table remains an
output container but is no longer a mutation target), narrows ADR 0028 to
dibbles for the table forms while the vector forms are unchanged, and
withdraws the sentence in
[ADR 0034](0034-evaluate-dibble-expressions-with-call-local-group-context.md)
that retained compatibility methods for reference-marked plain containers.
The legacy overlay reference state, which no code path produces, is removed
together with its readers. The `benchmarks/r-reference-mutation` gate moves
its fixtures to dibbles and re-baselines its bounds. The change ships as a
hard break with a NEWS entry, before 1.0.
