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

Each backing record is an R-managed external pointer. Its protected field roots
the ordinary allocation, its tag roots the flags and facts, and its address
stores that allocation's read pointer. It owns no separate native memory and
needs no finalizer. Replacing a record changes the allocation, pointer and facts
together, while data2 retains the existing ordinary/read-view distinction.
Element reads avoid a repeated vector-record lookup. Writable access still
passes through the same preparation boundary before touching the payload.

Deep duplication of a known factor returns an independent ordinary integer
copy with its metadata. Shallow duplication and explicit metadata copies retain
owned forks. Public logical subsets return newly allocated ordinary values;
the private validated batch route adopts its fresh columns directly. These
boundaries keep R's coercion, range and mean temporaries ordinary without a
generic Coerce hook or changes to public classes. An ordinary logical subset
crossing a later table boundary is captured there under the existing ingress
rules.

Public writable pointers detach shared backing, invalidate facts and mark the
allocation exposed. Future forks capture exposed storage because a retained
pointer may write again. String element assignment detaches and invalidates
facts without claiming that a pointer escaped. Native table writes stage new
values and row positions before their final sharing and target checks, then
commit without allocating or calling R. Full replacement does not copy old
values; partial writes may copy only their target column. The existing physical
table aliases, identical slots, metadata replacement and rollback policies apply.

String construction captures borrowed character values before removing incoming
classes or attributes. Internal attribute copies fork the owned handle and use
R's attribute setter, preserving facts without a generic R metadata wrapper.
Names replacement with object dispatch or attributed names retains the R setter.
Declined assignments remain in the original caller frame; a fallback setter
helper would add a live binding and copy compact dictionary storage again.
Public attribute replacement and conservative foreign fallbacks are unchanged.
Native readers adopt completed ordinary logical, integer/factor and character
buffers without an additional capture. Writers retain exact owned string
allocations across later metadata callbacks; their internal pointers never
become untracked R results. Already UTF-8 owned strings need no DTA planning copy.

The shared row planner gathers a wholly supported integer/logical/factor batch
directly under its existing vctrs policy. Its locations are already validated,
so base R need not validate them again for every ALTREP column. The batch keeps
column attributes in their original order. Base-frame gathering retains its
separate factor attribute policy. Any foreign column, unsupported class or
attribute, names, dimensions, or callback-capable locations declines the whole
batch, preserving the existing fallback and cross-column callback order.

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

Exact Stage 4 qualification passes the correctness, allocation, native-write
and isolated-memory gates, with a measured read tradeoff. Twelve base-R read
cases add about 2 ms per million values after the getter and ordinary-temporary
fixes. Three delegated filter cases add about 2.9–3.9 ms on one million rows and
eight columns. Their repeated per-column subset planning is separate from the
element-read costs; the shared batch gatherer avoids it. These costs remain
visible in the [performance evidence](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage4.md),
with no claim that every ordinary read is as fast or that the differences are
universally negligible. Stage 6 must resolve the filter regressions using its
shared evaluator and gatherer. Stage 4's storage qualification does not complete
direct filtering or final integrated performance acceptance.
