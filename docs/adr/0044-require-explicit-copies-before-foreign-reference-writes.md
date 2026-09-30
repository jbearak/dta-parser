---
status: accepted
---

# Require explicit copies before foreign reference writes

Dibble results preserve ordinary R copy-on-modify semantics and isolation under dtatools' own explicit mutators. They may share unchanged plain columns with their inputs. Independence from later foreign by-reference writes, such as `data.table::set()` or `data.table::setattr()`, requires an explicit `copy_data()` before the foreign write. This replaces the stronger result-isolation requirement in ADR 0029 and ADR 0031 so ordinary operations need not copy every plain column to guard against a future reference write the caller may never request.

Aliases of the same physical dibble still observe explicit dtatools mutation. Separate results and extracted column aliases remain protected from ordinary R replacement and dtatools writes in both directions, including value and metadata writes to unchanged columns. dtatools writers must detach shared columns as needed. Validation, Stata typing, grouping, evaluation order and transaction guarantees remain in force.

The foreign-write exception applies to shared values and attributes. A result may happen to survive a foreign write because it already has separate storage; that is not a general guarantee, and callers must not depend on either sharing or separation. The same public rule applies to plain and owned columns. Owned backing may retain stronger protection through its existing detachment mechanism. This decision does not permit adopting borrowed plain memory as privately owned or treating it as immutable across callbacks. Required expression snapshots and native reader lifetimes must still be preserved.

`copy_data()` remains the explicit isolation boundary for supported dibbles. Its result, input and copied metadata remain independent under later foreign reference writes in either direction. Call it before converting a dibble to another container when the exported object needs this guarantee. Reference-valued columns and attributes that cannot be isolated retain their existing rejection behavior.

Tests must retain ordinary R and dtatools mutation isolation, table-alias behavior, and two-way foreign-write isolation for `copy_data()`. Tests for ordinary results must not require blanket isolation from later foreign writes. Existing stronger implementation behavior can remain where useful; this contract does not require writes to propagate. Performance comparisons must state whether an explicit independent copy is included.
