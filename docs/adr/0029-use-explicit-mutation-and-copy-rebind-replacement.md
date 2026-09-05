---
status: accepted
---

# Separate explicit mutation from ordinary replacement

R can copy a table before replacement dispatch, so an owner back-pointer cannot distinguish that temporary copy from a persistent copy made by base attribute replacement. Ordinary dibble replacement now uses R copy-and-rebind semantics; explicit helpers mutate the supplied physical table, and reference ownership is validated separately from `is_dibble()` to prevent copied or serialized state from redirecting writes. This supersedes [ADR 0023](0023-make-replacement-operators-by-reference-on-a-dibble.md).

Replacement results isolate all columns for later explicit writes, retaining compact backing through copy-on-write wrappers. Modern bookkeeping does not retain column vectors or an owning table reference, and reads never repair or modify a shared state environment. Explicit writes detach shared column payloads in all supported containers while preserving aliases to the supplied table. Same-storage patches preserve links among its identical column slots; promotion and metadata setters replace only the named column.

Base attribute copies and serialized tables retain their type but may lose ownership identity and spare capacity. Assigned `reserve_columns()` creates isolated columns and fresh bookkeeping; it does not repair another table through a shared state. [ADR 0030](0030-require-assigned-column-preparation.md) completes the capacity policy: helpers fail before capacity-sensitive evaluation and callers assign preparation before invoking them.

Function-local ordinary replacement no longer mutates the caller, even after conversion with `as_dibble()`. Return and assign the result, or use explicit metadata setters from [ADR 0028](0028-edit-metadata-on-the-supplied-table.md), `gen()`, `repl()`, and dibble `:=` when caller mutation is intended.
