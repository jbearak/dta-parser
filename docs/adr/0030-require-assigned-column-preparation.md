---
status: accepted
---

# Require assigned column preparation

An automatic rebuild can only rebind a local function parameter, so a successful `gen()` could lose its new column to the caller. Explicit helpers now mutate the supplied physical table or fail before capacity-sensitive evaluation. They never rebuild or rebind it. Callers assign `reserve_columns()` before invoking a function that adds or drops columns. This supersedes ADR 0026's automatic rebinding policy while preserving the complete physical-table requirement.

`column_capacity()` reports total usable slots or `NA` for an unprepared allocation, and `can_add_columns()` checks a requested number of additions. A zero-addition query does not promise shrink readiness. Keep/drop validate their column selections before checking the resulting size, so absent or empty selections keep their diagnostics and a validated keep-all needs no resize; rename/order, value writes, and metadata edits need no spare slots. Bracket assignments preflight all new columns together, retaining sequential value evaluation after that check.

Preparation isolates columns and creates fresh ownership bookkeeping, preserving each container and existing column classes. Base serialization and ordinary copies can lose capacity; readers, constructors, and `copy_data()` prepare their outputs. A zero-column, zero-slot allocation is not resizable. data.table readiness also checks its own self-reference so a misleading spare-slot count cannot cause its setter to allocate behind the caller.

The optional data.table dependency has a minimum version of 1.18.2.1, enforced
before operations on that container. The resizable allocation protocol and
removal of the legacy GC-accounting finalizer began in 1.18.0; that release still
uses non-API `ATTRIB`, which no longer compiles on R 4.6. Version 1.18.2.1 removes
that use and has been built and tested on the required R version. Structural commits
stage a new names vector and self-reference wrapper, preserving the validated
non-owning owner token without changing a shared wrapper. R 4.6 accounts for the
full resizable allocation; no extra data.table finalizer is needed. Releases before
1.18.0 use a different allocation protocol, so assigned preparation cannot
make their tables satisfy this contract. See [data.table 1.18.0 allocation code](https://github.com/Rdatatable/data.table/blob/1.18.0/src/assign.c).
