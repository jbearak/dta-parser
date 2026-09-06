---
status: accepted
---

# Separate explicit mutation from ordinary replacement

R can copy a table before replacement dispatch, so an owner back-pointer cannot distinguish that temporary copy from a persistent copy made by base attribute replacement. Ordinary dibble replacement now uses R copy-and-rebind semantics; explicit helpers mutate the supplied physical table, and reference ownership is validated separately from `is_dibble()` to prevent copied or serialized state from redirecting writes. This supersedes [ADR 0023](0023-make-replacement-operators-by-reference-on-a-dibble.md).

Replacement results isolate all columns for later explicit writes, retaining compact backing through copy-on-write wrappers. Modern bookkeeping does not retain column vectors or an owning table reference, and reads never repair or modify a shared state environment. Explicit writes detach shared column payloads in all supported containers while preserving aliases to the supplied table. Same-storage patches preserve links among its identical column slots; promotion and metadata setters replace only the named column.

Base attribute copies and serialized tables retain their type but may lose ownership identity and spare capacity. Assigned `reserve_columns()` creates isolated columns and fresh bookkeeping; it does not repair another table through a shared state. [ADR 0030](0030-require-assigned-column-preparation.md) completes the capacity policy: helpers fail before capacity-sensitive evaluation and callers assign preparation before invoking them.

Function-local ordinary replacement no longer mutates the caller, even after conversion with `as_dibble()`. Return and assign the result, or use explicit metadata setters from [ADR 0028](0028-edit-metadata-on-the-supplied-table.md), `gen()`, `repl()`, and dibble `:=` when caller mutation is intended.

Current objects use their public `dibble` class for type identity, independently
of the reference-state flag or ownership validity. `is_dibble()` also recognizes
older objects without that class when `state$dibble` is `TRUE`, or when that flag
is absent and stored base classes include `tbl_df`. An explicit legacy `FALSE`
remains ordinary. New bookkeeping records the current type but does not override
it. The ownership token is checked separately at mutation boundaries.

Assigned conversion with `as_dibble()`, preparation with `reserve_columns()`,
copying, and dataset results produce the current class for supported legacy
dibbles. They build a fresh object and state instead of upgrading an alias or
editing a shared state environment. Serialization retains current class identity
but still loses ownership validity and spare capacity. Use `is_dibble()` for
recognition across versions, and assigned preparation before structural mutation.
