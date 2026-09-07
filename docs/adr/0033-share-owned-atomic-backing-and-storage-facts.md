---
status: proposed
---

# Share owned atomic backing and storage facts

Ordinary strings, logicals and integer/factor columns use the same flat owned
backing model as [ordinary doubles](0032-share-owned-double-backing-with-transactional-table-writes.md).
Each result has an independent handle and attributes; unknown borrowed values
are captured before becoming owned. This preserves foreign data.table isolation
without copying retained payload at every selector. R storage types, factor
levels and orderedness remain unchanged. Public factor replacement keeps its
existing restriction; ordinary R replacement and native integer backing remain
separate contracts.

String backing records store missingness and maximum UTF-8 byte width. A class
or declaration alone never certifies values. An exact maximum can accept or
reject a declaration. A subset upper bound can accept a sufficiently wide
one, but a narrower declaration needs a scan before rejection. Padded subsets
lose the no-missing proof. Foreign index callbacks can change source facts while
gathering, so their outputs start with unknown facts. Byte-marked strings retain
the existing width behavior and the existing native generation/export errors.
Private scan counters include both width validation and missingness-only scans,
counting each pass and each value inspected; they are separate from byte counters.

Public writable pointers detach shared backing, invalidate facts and mark the
allocation exposed. Future forks capture exposed storage because a retained
pointer may write again. String element assignment detaches and invalidates
facts without claiming that a pointer escaped. Native table writes stage new
values and row positions before their final sharing and target checks, then
commit without allocating or calling R. Full replacement does not copy old
values; partial writes may copy only their target column. The existing physical
table aliases, identical slots, metadata replacement and rollback policies apply.

Native readers retain the exact allocation behind a pointer across callbacks.
Compact dictionaries additionally pin their immutable Rust descriptor through
a call-local external pointer. The descriptor reference count outlives any
materialization that releases the original handle, without changing its sharing
claims or copying dictionary data. R finalizers release these pins after normal
return or unwind. Row plans recheck each consumed position against the original
row count, including positions changed by operand callbacks.
Legacy vector transactions snapshot unknown ALTREP operands before retaining
native readers or journaling. Ordinary and internal native operands keep their
existing direct reads. Original target state is captured before operand
callbacks and validated after preparation, including a callback-capable string
declaration. The journal, write and rollback phases then read stable operands;
their existing interruption tests and allocation bounds remain required.

Ordinary atomic serialization keeps R's materializing fallback and saves values
and attributes without ownership records. Restored dibbles still satisfy class
recognition, and normal result construction or assigned preparation recaptures
plain payload as needed. The transient blank-name ALTREP used during column
append is separate from public string-column storage. Stage 3's range,
coercion, literal-expression and attribute-transaction boundaries remain intact.
