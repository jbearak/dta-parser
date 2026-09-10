---
status: accepted
---

# Grow column capacity automatically

Column additions through `gen()`, `egen()`, and dibble `:=` grow capacity
automatically by default. The user chose automatic growth with a defensive
return-and-assign pattern over the unconditional error introduced by
[ADR 0030](0030-require-assigned-column-preparation.md). Set
`options(dtatools.auto_grow = FALSE)` to retain that strict behavior. The
package-controlled allocation default is 1,024 spare column-pointer slots,
matching [data.table's default](https://rdatatable.gitlab.io/data.table/reference/truelength.html);
`dtatools.alloccol` remains configurable. Growth allows the requested additions
as well as those spare slots.

Within capacity, mutation preserves the supplied table's identity. Reallocation
creates an isolated table, warns about alias separation, updates a supported
mutation target after a successful write, and returns the result. A function
must return its updated table and its caller must assign it, as in
`x <- func(x)`. This preserves the caller's result but cannot move other aliases
to the new table. A function that returns `NULL` can still discard a grown
result; the warning and documentation make that consequence explicit. Callers
that need all aliases to see additions must reserve before creating the aliases
or use strict mode to catch exhausted capacity.

The complete physical-table requirement and isolation of old aliases remain.
This decision changes column growth only. Helpers that remove columns or need
other structural preparation retain their explicit preparation requirements.
