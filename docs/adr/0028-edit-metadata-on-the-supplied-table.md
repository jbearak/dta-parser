# Edit metadata on the supplied table

Explicit metadata setters mutate the supplied table by reference on every
supported table container; vector forms retain assigned-copy semantics.
`set_var_format()` and `set_var_formats()` provide the same target forms as the
label family, while `set_dta_metadata()` validates complete metadata bundles
before committing them. The generic setter protects structure, runtime state,
and storage declarations; a raw attribute write cannot enforce those boundaries.

Metadata edits stage copies of changed columns, preserve physical capacity, and
attach fresh reference bookkeeping to the supplied table. They never redirect
writes through another recorded object or update shared bookkeeping. This
separates explicit caller mutation from ordinary R replacement, whose semantics
will be addressed in the next epic change, superseding ADR 0023. Plain tables
receive the same explicit mutation contract without implicit column conversion.
