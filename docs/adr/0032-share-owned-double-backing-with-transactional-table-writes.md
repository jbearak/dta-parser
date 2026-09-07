---
status: proposed
---

# Share owned double backing with transactional table writes

[ADR 0033](0033-share-owned-atomic-backing-and-storage-facts.md) extends this
Stage 3 decision to ordinary strings, logicals and integer/factor backing.

Ordinary doubles captured by dtatools use distinct ALTREP handles with backing
on R's vector heap. Column results can share that backing while keeping their
attributes independent. Unknown input requires an isolation copy; only native
allocation code can adopt a completed, unexposed buffer without copying it.
This extends [ADR 0029](0029-use-explicit-mutation-and-copy-rebind-replacement.md)
without changing the public REALSXP type, column classes, ordinary replacement
rules, or the assigned capacity preparation required by [ADR 0030](0030-require-assigned-column-preparation.md).

Backing records contain sharing, writable-pointer exposure and validated read
facts. They contain no table pointer, and no global registry retains them.
Forks share one flat record. Public writable pointer access detaches as needed
and permanently prevents later forks from trusting that backing as immutable.
Internal reads use the read-only API; ordinary aggregate implementations read
the ALTREP handle without receiving its private plain vector as an R argument.
Initial ordinary-double serialization may materialize values, but never saves
live ownership records. Existing compact numeric and dictionary storage retain
their public representations.

Read loops retain the exact payload they read across allocations and callbacks.
Missing-code and bare missing-mask scans use one read-only pointer. Valid bare
owned double constructors reuse the complete native storage-fit scan; attributed,
classed, foreign or invalid values retain the detailed R validation path.
Integer and logical exports use R's native coercion API after taking the normal
snapshot. Extra arguments and traced base coercions retain the existing R call.
There is no generic ALTREP Coerce hook, which would change attribute-copy timing
around coercion warnings. Double and deferred character exports remain tracked.

Base range flattens arguments with repeated writable pointer requests. Owned
range arguments therefore receive one independent ordinary snapshot before
the existing base call. This replaces the copy that writable access otherwise
requires, keeps range's argument and warning behavior, and avoids handing an R
callback a private backing vector. The source's exposure and sharing flags are
unchanged by this snapshot, including when a writable pointer already exists.
Sum, min and max keep R's ordinary aggregate implementation and read-only
pointer path. No R aggregation or coercion algorithm is copied.

Explicit value helpers inspect physical column sharing before creating R
evaluation objects and again at the native table boundary after callbacks.
Supported preflight views carry native sizes and cannot enter R methods.
Arbitrary expressions receive a complete snapshot, including columns they have
not read when they retain their evaluation environment. Literal values, direct
symbol reads and literal `.env` members can avoid constructing that mask.
Grouping callbacks and R fallbacks use the same exposure boundary. Unsupported
classes retain conservative validation and copying.
Backing ownership alone cannot certify a handle retained by another R object.

Numeric and ordinary atomic table writes stage validated new values before
choosing the destination.
Their final commit performs no allocation, callback or interrupt check. Private
backing can therefore receive a full replacement without an old-value rollback
copy. Shared full replacements allocate new destination backing without reading
old values. Partial writes may capture the changed column once; later proven
private writes retain their sparse allocation bounds. Other native transaction
paths retain explicit rollback, including real after-write interrupt coverage.
Deterministic fault injection enters R's native interrupt handler directly so
Windows exercises the same transaction unwind. Separate asynchronous POSIX
tests retain OS signal delivery. An injected interrupt disarms before entering
the handler and retains an error fallback if suspension or a resume restart
returns from it.
Failed or zero-match work must preserve original claims while retaining sharing
introduced by a legitimate callback. Identical slots in the supplied physical
table commit together; metadata and promotion keep their named-slot policies.

Ordinary strings have temporary internal read handles during preflight. These
handles release their physical source reference when evaluation finishes, while
any escaped snapshot keeps its own reference. They do not change the public
string representation or implement shared owned string backing. These preflight
views borrow read-only pointers only from ordinary contiguous strings.
A data-pointer request materializes a private ordinary copy and honors writable
access there; direct element assignment on a temporary view is unsupported.
Public exposure returns an ordinary string vector. Supported cast
prototypes use metadata without decoding full target values. Native numeric fit
checks scan selected replacement values without constructing full R temporaries;
unknown classes still use their existing R validation methods. Remaining
dictionary and foreign ALTREP targets prepare detached work and revalidate the
original table slot after operand callbacks before committing it.

The existing repeated-generation gate also requires a structural prerequisite.
Assigned preparation isolates and reserves the names vector alongside the
column list. Append reuses names only after their actual sharing and capacity
checks; an exposed or attributed names vector gets an isolated replacement.
Fresh physical reference states retain counts without retaining names. Legacy
overlay states keep their existing names fields. Narrow internal names reads
use R 4.6's experimental `R_mapAttrib` API, because `Rf_getAttrib` marks returned
attributes immutable even when they are used only for native validation.
The iterator never publishes names to R or changes reference counts. Public
name and attribute reads keep their usual isolation behavior.

Structural append first replaces the existing names attribute value with an
O(1) blank-string placeholder, then removes that attribute before resizing.
The public setter releases the old cell's reference to the real names; merely
unlinking the cell retains that reference until collection. `R_resizeVector`
also removes names and its internal getter marks retained names immutable.
Append reinstalls the real names with the public attribute setter. The temporary
placeholder holds only a length, has no operand callbacks or old names reference,
and never becomes the completed table's string representation. Rollback uses a
second placeholder when needed so reinstalling original private names does not
make them shared solely through the removed attribute cell. Operand callbacks and
large allocation finish before the final shape, capacity and sharing checks.
The small attribute-cell allocation inside this commit is unavoidable with the
supported API. An `R_UnwindProtect` journal restores the original list length,
slots, names length, attribute order and reference-state identity after errors
or interrupts. Its roots use preallocated protection slots; the attribute
iterator callback only replaces those roots and never publishes names.

This structural path cannot promise allocation-free atomicity. Rollback itself
uses public attribute setters and may allocate, so catastrophic out-of-memory
failure during cleanup cannot be guaranteed recoverable. Ordinary allocation
on the supported R build does not run pending R finalizers, but builds enabling
immediate finalizers can observe intermediate structural state. These limits
are separate from the callback-free, allocation-free owned-value commit.
Tests inject failures after names removal, slot insertion and names restoration,
including native after-write interrupts, and verify restoration and retry.
These public API behaviors were checked against R 4.6.1's
[attribute implementation](https://svn.r-project.org/R/tags/R-4-6-1/src/main/attrib.c)
and [memory implementation](https://svn.r-project.org/R/tags/R-4-6-1/src/main/memory.c).
The installed NOTICE records this source study; no implementation from those
files was copied or adapted.

Simple full-row generation can validate a known physical shape without making
column views. A fixed 32 KiB stack budget supports at most 2,048 ASCII names;
wider tables, encoded or classed names, foreign ALTREP and unknown column classes
use the complete R path. Validation runs before and after argument capture.
Only already evaluated, unclassed, ordinary scalar values qualify for direct
generation. Promises, active bindings, formulas, groups and possible mask reads
use the existing snapshot path. This bounded shortcut makes no general claim
about generation scaling for arbitrary table widths or expressions.

The staged [epic plan](../plans/dibble-result-performance.md) requires fresh
source-bound builds and measurement of both R allocations and native buffers.
Benchmark preparation must assert ownership after setup. An R constructor,
spare capacity, or an unshared handle is not proof of private backing, and
serializing the measured fixture can itself request public pointer access.
