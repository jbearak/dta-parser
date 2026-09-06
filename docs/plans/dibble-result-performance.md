# Direct dibble operations and optional dplyr

Status: proposed implementation sequence, revised 2026-09-06 to include
[issue #172](https://github.com/jbearak/dta-parser/issues/172). The user has
chosen package-owned direct operations as the target architecture. Benchmarking
and a limited validation prototype are complete; production implementation has
not started. Current checkout: `5ad44406f9b80db81789dcf7b7e1756c28502559`,
including printing PR #190 and explicit dibble-class PR #191, both merged.
The recorded performance baseline remains `3a8189933a8ddd32a1bc1c5c6194956382586a20`.

## Evidence and decision

The [controlled benchmark](../../benchmarks/r-dibble-dplyr/results-2026-09-05.md)
compares identical Stata columns in tibbles and dibbles. On one million rows
and 16 columns, renaming regular doubles allocates 128 MB. Renaming ordinary
`dta_string` columns allocates 640 MB and takes about 219 ms; 512 MB comes from
repeated validation. A prototype that retains all isolation but skips those
redundant checks reduced 213 ms to 31.6 ms and 640 MB to 128 MB in a paired run.

The roughly 0.01 ms snapshot measurement covers only the initial table view.
It does not establish that direct operations offer little benefit. In the same
benchmark, filtering typed tibble columns allocated 1.37 GB for 64 MB of double
output, before dibble finalization. Direct execution must be compared with
optimized delegation using the same typing and isolation guarantees.

Adopt four cooperating modules:

1. A direct-operation module that selects and reorders columns, gathers rows,
   and installs computed columns using dibble storage and metadata.
2. A result-finalization module that owns storage validation, promotion,
   column lineage, and construction of a fresh dibble.
3. An owned-column module that owns payload sharing, capture of borrowed
   values, detachment before writes, and reusable storage facts.
4. An optional dplyr adapter that connects dplyr generics and helper context
   to those implementations, and registers methods without loading dplyr.

Start with direct `select()`, `rename()`, and `relocate()` implementations and
the shared result finalizer in the first PR. Migrate the other operation
families in the sequence below. The completed dibble path must not execute
whole dplyr verbs on temporary tibbles and then reconstruct dibbles.

Direct implementation means dtatools owns execution and result construction.
Public rlang, tidyselect, and vctrs functions and existing native gather and
mutation routines remain available. It does not require writing every loop
in C or Rust, removing tibble inheritance, or replacing working vector algorithms.

Preserve eager behavior: each dataset operation returns a usable dibble;
explicit `repl()` and `:=` mutate the supplied physical table. Preserve the
existing plain-container behavior for tables that acquired reference state
without becoming dibbles. Preserve the merged printing and explicit-class work,
including legacy recognition and separation of type from reference ownership.
A lazy query interface and issue #189's
opt-in mutable dplyr interface remain separate feature decisions.

The dependency goal now includes #172: all existing package functionality must
work without dplyr installed, and optional integration must retain its behavior
when dplyr is present. Changing `Imports` alone cannot satisfy that goal.

### Alternatives considered

| Design | Benefit | Limitation | Decision |
| --- | --- | --- | --- |
| Direct verbs over shared operation, finalization, and ownership modules | Controls result assembly and avoids whole-table delegation for migrated verbs | Needs explicit compatibility coverage for each verb family | Adopt, starting in the first PR |
| Unified finalizer with operation-local validation evidence | Removes repeat scans and table reconstruction; measured string benefit | Still copies retained ordinary payloads by itself | Shared by direct operations and remaining compatibility paths |
| Independent fast paths in each verb | Can make selected verbs cheaper sooner | Spreads validity and ownership decisions | Keep those rules in shared modules |
| Owned backing and independent column handles | Makes retained-column forks cheap across dplyr, metadata edits, copies, and preparation | Broad native storage and mutation work; read/interop regressions must be tested | Follow the finalizer with staged implementation |
| Replace every verb and the dependency in one PR | Removes delegation at once | Mixes native ownership, evaluation semantics, and dependency changes | Split into the reviewable PRs below |

Do not simply delete `.isolate_shared_columns()` or treat every dibble column
as exclusively owned. Existing constructors can retain already typed, logical,
and factor vectors borrowed from elsewhere. A foreign `data.table::set()` can
modify an ordinary borrowed vector without invoking dtatools' write checks.

The main implementation locations are
[`R/mutate-data.R`](../../r-package/dtatools/R/mutate-data.R) for masks, typing,
closure, and mutation transactions;
[`R/dibble.R`](../../r-package/dtatools/R/dibble.R) for construction; and
[`src/init.c`](../../r-package/dtatools/src/init.c) for metadata proxies,
payload copying, and native writes. Preserve the semantics in
[ADR 0029](../adr/0029-use-explicit-mutation-and-copy-rebind-replacement.md).

## Direct-operation interface and scope

Users continue to call `dplyr::select()`, `dplyr::filter()`, and the other
generics on dibbles. The migrated methods perform their data operations through
dtatools' column and row kernels and return a dibble directly. They do not call
the corresponding whole-table verb on a tibble snapshot and then call public
`as_dibble()` on the result. Small column lists and row-index vectors are normal
internal working data; this is not a ban on temporary R objects.

Use three private operations with a shared result context:

```r
.dibble_select_columns(context, locations)
.dibble_take_rows(context, locations)
.dibble_modify_columns(context, values)
```

Column locations carry their output names, including renamed or repeated
selections. Row locations have already been checked against the current row
count and the calling verb's indexing rules. Modified values are named and
already typed, with `NULL` representing removal. Each operation records where
its result columns came from and finishes through the common result module.
Expression evaluation and input checking happen before a result is published.

| Family | Direct work | Compatibility requirements |
| --- | --- | --- |
| `select()`, `rename()`, `relocate()` | Resolve selectors once; select or reorder column handles and update names; construct one result | Renaming within selection, duplicated source columns, group keys, rowwise metadata, `.before`/`.after`, empty outputs and existing errors |
| `slice()`, `filter()`, `arrange()` | Produce row locations and gather columns through one shared storage-aware implementation | Each verb's missing/index rules, ordering, grouping, `.by`, `.preserve`, observation-dependent metadata and compact backing |
| `mutate()`, `transmute()` | Evaluate expressions sequentially against the current columns, type each value immediately, then install replacements and retained columns once | Promotion, recycling, deletion, `.keep`, `across()`, data-frame results, pronouns, grouped/rowwise evaluation and expressions that capture earlier results |

Reuse [tidyselect's public selector evaluators](https://tidyselect.r-lib.org/reference/eval_select.html)
for selection syntax and rlang for expression capture. Predicate selectors
must see the actual Stata columns. Direct execution does not require a new
selection language or removing these dependencies.

For rows, extract and extend the shared gatherer already used by
[`slice_dta_rows()`](../../r-package/dtatools/R/slice-dta-rows.R) and
[`.dta_merge_slice_columns()`](../../r-package/dtatools/R/dta-merge.R).
Their public wrappers have their own container and indexing policies, so calling
those wrappers unchanged is not the proposed implementation. Validate locations
once and reuse the gather machinery, with fresh-output ownership and validation
evidence passed to finalization. Preserve batching for ordinary fallback columns.

Implement the [dplyr row, column, and reconstruction hooks](https://dplyr.tidyverse.org/reference/dplyr_extending.html)
through these same kernels where their contracts permit. Reuse expression and
grouping machinery across entry points while keeping each operation's policy
explicit. Immediate Stata typing remains mandatory during expression evaluation.

Migration is by verb family. Existing delegation is a temporary compatibility
path for unmigrated verbs. Each PR lists its direct coverage and remaining
delegation; passing an ordinary ungrouped example does not complete a verb with
grouped and rowwise contracts. Summaries, joins, binding integration, and
callbacks have explicit stages below. Generic hooks must also remain compatible
with dplyr functionality outside the migrated method inventory.

## Grouping and expression compatibility

The grouping implementation owns validated partitions, keys, ordering, and
group metadata. Reuse current vctrs grouping/order operations and Stata proxies.
Preserve distinct policies for Stata `by`/`bysort`, persistent dplyr grouping,
per-operation `.by`, and rowwise execution. Cover empty factor groups and
`.drop`, group-key replacement, and `.preserve`; do not assume one ordering
policy fits every entry point. Read and write supported `grouped_df`/`rowwise_df`
metadata without requiring dplyr to be installed, including serialized inputs.

The expression implementation owns a call-local data mask, group iteration,
recycling, sequential visibility, column removal/unpacking, and result typing.
Use rlang quosures and data masks. An output such as `y = c(NA_real_, 1)` must
become a Stata value before evaluating `z = y > 0`. Preserve `.data`, `.env`,
injection, unnamed expressions, repeated names, `.keep`, used-column tracking,
and captured intermediate values. Share machinery across computed group keys,
`mutate()`, predicates, `distinct()`, and summaries; keep output-size rules
specific to the operation.

Full dplyr helper compatibility is required. Installed dplyr 1.2.1's `n()`
calls `peek_mask()`, and `across()` and `pick()` also consult dplyr context.
Replacing visible syntax alone fails for qualified calls or helpers invoked
inside user functions. The public
[context contract](https://dplyr.tidyverse.org/reference/context.html) must keep
working through the optional adapter.

Before migrating computed verbs, prove a small adapter between the package mask
and dplyr helper context. Prefer supported extension points where available.
If context installation requires dplyr internals, isolate that version-specific
access in one optional adapter, record the source assumptions, and test the
supported minimum and current releases. Never patch namespace function bodies.
Restore prior context after errors, interrupts, and nested operations. Test
`dplyr::n()`, `cur_group*()`, `cur_column()`, `across()`, `pick()`, `if_any()`,
`if_all()`, wrappers around them, and nested calls to ordinary dplyr verbs.
Do not silently delegate difficult cases back to whole dplyr verbs and declare
the direct implementation complete. This compatibility adapter is the largest
unproven interface in the plan and must be qualified before the computed-verb PR.

The [dtplyr research](../research/dtplyr-copying-and-mutation.md) supports
reusing private intermediates and operation information, but its query flags
do not prove ownership. In particular, retain the independently reproduced
`filter(TRUE)` followed by grouped mutation as a regression case. Delaying
Stata typing until collection is incompatible with the current dibble contract.

## Result-finalization interface

Use three private entry points. Keep argument capture in the S3 methods;
centralize result policy for direct execution and compatibility delegation.

```r
context <- .begin_dibble_result(data, caller = "mutate()", operation = "computed")
# Type each computed value before the next expression sees it:
typed <- .type_dibble_result_value(context, value, name, prior)
# The operation kernel supplies result columns and their origin/ownership facts:
out <- .finish_dibble_result(context, result)
```

`operation` is a closed internal category, chosen by the adapter, not a user
option or a collection of independent skip flags:

- `columns`: direct `select()`, `rename()`, and `relocate()` methods. Every
  retained vector must match a source vector by identity, independently of its
  name. Unexpected outputs take the conservative path.
- `rows`: direct `filter()`, `slice()`, and `arrange()` methods. Audited subset
  paths can preserve storage facts because they neither widen strings nor add
  missing padding. An unchanged vector still needs safe isolation.
- `computed`: mask verbs and replacement paths, preserving their existing
  promotion policies. Type each expression immediately so subsequent
  expressions see Stata missing ordering and string normalization.
- `unknown`: joins, binds, public reconstruction hooks, and arbitrary callback
  results. Validate unknown columns once. Do not assume generic
  `dplyr_row_slice()` excludes missing indices merely because `filter()` does.

The context holds the source column references and metadata, source identity/name
lookup tables, and the latest validated value per output name. A tibble snapshot
is created only if a compatibility fallback needs it. Retain each referenced vector
while its address is used as evidence; discard replaced records. Do not keep
all grouped intermediates or a permanent address registry. Group concatenation
and other assembled results fall back to one validation pass unless the owned
backing itself proves validity.

At finish, classify each output once as unchanged, already validated, or
unknown. Validation evidence never proves ownership. Preserve name repair,
grouping, row counts, observation-dependent metadata, capacity, and errors.
Build one final table shell using an internal validated constructor; do not
send known-valid output through the public `.as_dibble()` conversion loop.
Public ingress continues to validate arbitrary inputs using the same normalizer.

Source identity alone also cannot certify validity after an external write.
Audit constructor capture and every supported mutation path before trusting
source evidence. Borrowed or externally writable storage without reliable
provenance must receive one validation pass until owned backing can certify it.
Do not introduce a stale per-table validity flag. The prototype's exact-source
shortcut is qualified only for its controlled, valid fixtures; stage 1 must
establish these preconditions before enabling that shortcut in production.

The [dtplyr research](../research/dtplyr-copying-and-mutation.md) reinforces two
requirements: source identity or a subset flag does not prove independent
storage, and typing only after evaluation can change sequential results. Keep
mask wrappers on delegated paths until the direct evaluator meets that contract.

## Owned-column interface and invariants

Keep `.metadata_copy()` as the R isolation interface. Underneath it, implement
capture, fork, storage-fact lookup, and native writable preparation in one
module. Callers supply values and requested metadata, not ownership guesses.

Support existing compact numeric/dictionary backing and new ordinary backing
for regular doubles, characters, logicals, and integer/factor columns. Preserve
their R types and public S3 classes. Unsupported classes, arrays, lists, raw
vectors, and unfamiliar ALTREP classes retain the current conservative fallback.

- A column handle owns its attributes; a backing record owns values and their
  validation facts. Distinct package-created table results receive distinct
  handles, while handles can share backing. Flatten forks so pipeline length
  does not increase proxy depth.
- Capture unknown ordinary input with one isolation copy on adoption. Existing
  owned backing can fork without copying values. Only a native routine that
  has just allocated an unexposed buffer may adopt it without copying; an R
  constructor or `dta_*` class alone is not proof. This moves necessary copying
  to ingress and writes instead of repeating it at every verb.
- Backing records are retained through their handles. Do not introduce owning
  table back-pointers or a global registry that roots tables/columns. Mark
  sharing conservatively; false-positive sharing may copy, never corrupt.
- Keep the existing early `MAYBE_SHARED` check before data masks are built.
  Base shallow copies and standalone vector aliases may share the same handle
  without invoking the new fork routine. Detach such handles at the table write
  boundary and preserve the existing identical-slot commit behavior.
- Same-table aliases continue to observe explicit mutation. Same-storage
  patches update identical column slots together; named promotion/metadata
  replacement keeps its existing named-slot behavior. Ordinary replacement
  continues to isolate other bindings according to ADR 0029.
- Prepare writable backing inside native transactions, detaching only the
  target when necessary. Full-column replacement can install fresh values
  without copying the overwritten payload. Rollback includes backing state,
  sharing claims, attributes, and validation facts.
- Public writable ALTREP `Dataptr` and string `Set_elt` access must detach and
  invalidate facts. Once a writable pointer escapes, mark its backing
  non-shareable for future forks and copy it there: a retained pointer could
  otherwise modify a later sibling. Internal transactional access uses a
  separate private path. Read-only access must follow R's pointer contract.
- Implement direct element/region reads, duplicate/fork methods, appropriate
  aggregate delegation, and native subset support. Do not make common reads
  materialize an ordinary backing merely to pass through another wrapper.

Store storage facts on backing, not permanent "valid" attributes. For strings,
keep missingness and maximum UTF-8 byte width; compare them with the current
declaration. Native subsets propagate valid facts only when the subset permits
it. Missing padding invalidates the no-missing proof. For numeric/temporal
subsets, retain proof for the same storage/temporal representation; casts or
unknown results are validated. This also gives vector restoration a way to
avoid re-encoding already validated slices.

Writes update facts transactionally when cheap, otherwise invalidate them and
allow one scan on demand. Metadata changes must recheck compatibility with
existing facts. Unknown writable access invalidates facts. A bare class tag is
never sufficient, since join padding and stale declarations are supported
recovery cases.

For ordinary owned backing, initial serialization may use R's materializing
fallback; preserve values, classes, and metadata. Do not serialize live ownership
tokens. Restored objects must rebuild ownership safely. Preserve existing compact
serialization and assigned-preparation requirements.

## Upstream reference code and attribution

The user explicitly authorizes studying dplyr and dtplyr as reference code and
adapting useful implementations with proper attribution. Include this source
review in PR 1 and repeat it for the operation families each later PR changes.
Do not make independent reimplementation a constraint when adapting qualified
upstream code gives a better result.

License inspection on 2026-09-06 found:

| Project and source revision | Inspected license | Copyright notice |
| --- | --- | --- |
| dtatools at `5ad4440` | `GPL-3` in DESCRIPTION; GPL version 3 repository license | Preserve the project's existing notices |
| dplyr 1.2.1, `95740975c465c29cdb2abdfa13effddb948444dc` | [MIT license](https://github.com/tidyverse/dplyr/blob/95740975c465c29cdb2abdfa13effddb948444dc/LICENSE.md) | 2026 dplyr authors |
| dtplyr 1.3.3, `2cc627511c34ed461093ae4c5dc94faccffeb93c` | [MIT license](https://github.com/tidyverse/dtplyr/blob/2cc627511c34ed461093ae4c5dc94faccffeb93c/LICENSE.md) | 2023 dtplyr authors |

These MIT/Expat terms are compatible with including the code in this GPL-3
package while retaining the upstream notices. See the
[GNU license compatibility classification](https://www.gnu.org/philosophy/license-list.html#Expat).
The inspected MIT texts require retaining their copyright and permission
notices with copies or substantial portions. Inspect each candidate file's
headers and any bundled third-party notices too; a package-level label does
not settle every file's provenance.

Use dplyr's selector, mask, grouping, reconstruction, and recode code to identify
behavior worth retaining. Use dtplyr's operation records and copy planning as
reference for avoiding repeated work. Inspect upstream tests as well as runtime
code. Retain Stata typing and ownership guarantees when adapting an algorithm;
upstream behavior alone is not sufficient acceptance for dibbles.

For every copied or adapted portion, record upstream project, exact commit,
file/function, copyright/license, local destination, and the changes made.
Keep a short source comment pointing to that record. Implementations studied
only for ideas can be acknowledged as references without implying that their
code was copied. Calling a public dependency does not imply that its source
has been incorporated.

Create `r-package/dtatools/inst/NOTICE` with the attribution inventory and full
required upstream license/copyright text when code is incorporated. R installs
this as `NOTICE` in the package directory. Add an acknowledgements section at
the bottom of `r-package/dtatools/README.md` crediting dplyr and dtplyr for the
relevant reference/adapted work and linking to the detailed notice. Keep those
credits accurate as the implementation develops. A README citation is useful
credit but is not a substitute for retaining required license text.

Verify that the source archive, installed package, and release binaries carry
the notices. Update attribution in the same PR that introduces derived code;
do not defer it until PR 9. Check R DESCRIPTION author/copyright metadata for
any corresponding attribution needed for incorporated contributions. If the
review reaches vctrs or data.table source, audit those specific files separately;
do not assume their notices are identical to dplyr's or dtplyr's. The existing
[join-source research](../research/dplyr-join-implementation.md) records relevant
vctrs file-level distinctions.

## Implementation sequence

Start direct implementation immediately in PR 1. The sequence uses nine
reviewable PRs because storage ownership, expression semantics, and optional
dependency handling have different failure modes. No preliminary PR is needed
solely to optimize an adapter that the next PR replaces.

| PR | Deliverable | Completion evidence |
| --- | --- | --- |
| 1 | Shared result finalizer and direct `select()`, `rename()`, `relocate()` | Typed selectors, groups, name repair, metadata, and future mutation isolation pass; migrated methods no longer call the whole dplyr verb on a tibble |
| 2 | Shared row gathering and grouping metadata; direct row slicing and reconstruction hooks | Indices are resolved once, native gathering is reused, group partitions work without dplyr, and source/result isolation covers no-op and shallow subsets |
| 3 | Owned ordinary-double columns | Ingress capture, forks, native writes, metadata edits, serialization, and first-write isolation pass; retained double columns avoid payload copies |
| 4 | Owned strings, logicals, and integer/factor columns | Writable character access and storage-fact invalidation pass; unchanged supported strings require neither payload copies nor repeated scans |
| 5 | Package-owned expression engine; direct `mutate()`, `transmute()`, and computed grouping | Sequential Stata semantics, helper-context interoperability, grouped/rowwise behavior, `.by`, `.keep`, unpacking, and nested calls pass |
| 6 | Direct `filter()`, `arrange()`, `distinct()`, and remaining `slice_*()` methods | The shared evaluator produces row plans consumed by the shared gatherer; missing/order/group semantics and allocation scaling pass |
| 7 | Direct `summarise()`, `reframe()`, `group_modify()`, `group_nest()`, and `nest_by()` | Size rules, grouping transitions, zero groups, nested results, arbitrary callbacks, and captured-source isolation pass |
| 8 | Direct join assembly, base binding, and full dplyr/vctrs reconstruction integration | Join policy remains distinct from `dta_merge()`; binding, padded/widened columns, mixed containers, and `rows_*()` preserve the established contracts |
| 9 | Independent recoding, optional dplyr registration/declaration, installation and CI | The complete #172 acceptance matrix passes with dplyr absent and present; only then move it out of `Imports` and close #172 |

PR 1 extracts the validated constructor and removes duplicate type checks as
part of real direct operations. It keeps conservative isolation for ordinary
borrowed storage until PRs 3 and 4. Source identity is validation evidence only
under the provenance rules above. Its performance claim is reduced repeated
work, not that all retained payload copies have already disappeared.

PR 2 centralizes grouped-data validation, key extraction, `.drop` handling,
regrouping, and row-index rebuilding currently spread across mutation, egen,
and slicing. Ordinary base `[` and the direct `dplyr_row_slice()` hook share
gathering but retain their indexing policies. Direct `slice()` requires its
expression/context support; complete that method in PR 6 if the support has
not landed earlier. PR 2 must not route grouping metadata work back to dplyr.

PRs 3 and 4 preserve the existing early sharing check and every native mutation
transaction. Ordinary-string writes need explicit integration: today's ALTREP
patch path can assume `data2` contains materialized dictionary output, which
is unsafe for a new ordinary-string handle. Qualify reads and serialization
before enabling the new backing by default. Keep unsupported representations
on the safe fallback described above.

PR 5 begins with the helper-context compatibility proof. Keep the old evaluator
available only for families not yet migrated, and remove its wrapping and
condition-relabeling layers once their replacements cover the same behavior.
PRs 6 and 7 reuse that tested evaluator rather than creating new masks per verb.
Preserve valid unsupported column classes through the established fallback;
full compatibility does not require accepting inputs the package already rejects.

PR 8 reuses public vctrs matching/casting and the package gather/assembly module.
Do not substitute `dta_merge()` for a dplyr join: suffixes, coalescing, key
missingness, relationship checks, non-equi joins, and output order have their
own contracts. Test the existing integration and the supported join arguments.
`dplyr::bind_rows()` and `bind_cols()` are not S3 generics in the inspected
release. Preserve them through their vctrs and reconstruction extension points;
do not claim a `bind_rows.dibble()` method could replace their internal loop.
Package-owned base binding and result construction are direct. Non-dispatching
functions owned by dplyr can continue orchestrating their own public operations
when users explicitly call them; no namespace patching is part of this plan.

PR 9's recoding implementation can be developed independently of native
ownership. All previous stages must already remove their core dplyr calls.
The final dependency declaration is a consequence of passing the absence tests,
not a substitute for that work. Each earlier PR can land independently with
the current dependency declaration and full compatibility intact.

Rebase each PR onto the preceding merged result, starting after PR #191.
Keep implementation and review diffs focused. Per-PR validation
includes behavior tests, relevant native/allocation checks, the package build
and check, documentation generation, and the repository conformance gates for
affected behavior. Use the actual repository PR/review requirements at execution
time. This plan does not itself publish, merge, or close an issue.

## Issue #172 dependency audit and public interface

Public interface for this sequence: keep the current public dtatools functions. dplyr supplies
its own generics only when installed; their dibble methods call the same
package-owned implementations. Adding a second family of same-named public
generics such as `dtatools::mutate()` is not included in this sequence. This
does not permit removing any existing dtatools feature or requiring dplyr from
a package-native helper. Audit every existing export and documented contract.

| Current runtime dependency | Replacement and PR |
| --- | --- |
| `recode.R`: character/factor fallback and metadata-vector recoding use `dplyr::recode()` | Extend the existing package-owned numeric recode implementation with character/factor behavior and normal unsupported-input errors, PR 9 |
| `mutate-data.R`: grouped validation and regrouping | Shared grouping metadata implementation, PR 2 |
| `egen.R`: `group_vars()` for grouped inputs | Shared group-key reader, PR 2 |
| `slice-dta-rows.R`: grouped key extraction, `.drop`, and regrouping | Shared grouping and row module, PR 2 |
| `mutate-data.R`: verb delegation, `getExportedValue("dplyr", ...)`, and dplyr-dependent argument defaults | Direct methods in PRs 1, 5, 6, and 7; package-owned group defaults in PR 2 |
| dplyr row/column/reconstruction callbacks | Thin optional adapters to the shared operation/result modules, PRs 1, 2, and 8 |
| `NAMESPACE` and `zzz.R`: registration and labelled interoperability | Delayed optional method registration plus guarded, reversible load hooks, PR 9 |
| `DESCRIPTION`, CI, release installation lists, examples, and documentation | Optional declaration and explicit dependency configurations, PR 9 |

Optional registration must support dplyr loading before or after dtatools,
namespace loading without attachment, and unload/reload. Preserve the existing
numeric recode dispatch and labelled/haven interoperability across load orders.
Hooks must not call `asNamespace("dplyr")` before confirming it is loaded.
Audit the current labelled load hook as well as a later dplyr load; registering
only when dtatools initially loads misses the latter case.

Keep character/factor recode details, including named replacements, defaults,
missing values, factor-level collapse/order, zero-length inputs, type checks,
warnings, and the existing `.missing` restriction for factors. Numeric recode
must retain exact Stata missing payloads, temporal classes, and metadata.
Unsupported input behavior remains ordinary validation, never an instruction
to install dplyr to recover an existing supported feature.

### Absence and compatibility configurations

- Build/install/run the source package in a fresh process and an isolated
  library containing only the declared mandatory dependency closure and an
  explicit test-dependency allowlist. Assert that dplyr is absent from every
  visible library and remains absent from loaded namespaces. Prevent site or
  user libraries and transitive optional test packages from making it available.
- Exercise readers/writers, constructors, storage operations, recoding, labels,
  metadata, egen, explicit mutation, ordinary replacement, slicing, grouping
  metadata, serialization, and container preservation through existing package
  entry points. Include validated grouped fixtures produced with dplyr and
  serialized before entering the isolated process. Direct operation-module
  tests supplement this public coverage; they cannot replace it.
- Split optional integration tests from core tests so that absence does not
  silently skip a test containing both. Audit examples and vignettes; optional
  dplyr examples can be guarded, but package-native examples must run.
- Keep a separate dplyr-present configuration with the supported minimum and
  current versions, full verb/helper parity, load-order permutations, and
  labelled/haven interoperability. Retain the installed-dplyr namespace-only
  load check showing that loading dtatools does not force dplyr to load.
- Update both `.github/workflows/ci.yml` and the release package setup. Do not
  interpret `R CMD check` skips or `_R_CHECK_FORCE_SUGGESTS_=false` alone as proof
  of independence. Record the dependency inventory and successfully exercised
  feature matrix before declaring #172 complete.

## Acceptance and tests

Test public operations using real dplyr/vctrs. Dependencies here are in-process
or locally available libraries; mocks would conceal the dispatch and copying
behavior under investigation.

- Preserve values, Stata storage/promotion, tagged missings, dates/datetimes,
  string widths, variable/dataset metadata, observation metadata, grouping,
  names, and empty-table behavior across verbs, joins/binds, and replacement.
- Cover `.by`, grouped/rowwise inputs, `.keep`, `across()`, unnamed/unpacked
  results, `.data`/`.env`, repeated output names, sequential expressions, and
  expressions that retain a previous result in an external binding.
- Cover helper functions that call qualified dplyr context functions, nested
  verb execution, and cleanup after errors. Include the dtplyr shallow-subset
  regression and both directions of later explicit writes.
- Test source-to-result and result-to-source mutation, aliases to both tables,
  duplicated column slots, standalone column aliases, ordinary base copies,
  metadata changes, materialized/compact inputs, and serialized pairs.
- Capture columns from a foreign data.table through constructors, `mutate()`,
  binds, and callbacks; mutate the foreign source with `data.table::set()` and
  confirm captured results remain unchanged. Test documented conversions and
  exports in the opposite direction too. Arbitrary native writes that violate
  R's read-only pointer contract cannot be supported by a wrapper.
- Check stale string declarations and externally modified borrowed sources
  before enabling source-validation shortcuts. Preserve the current repair of
  missing strings and insufficient widths on conservative reconstruction.
- Add small native test helpers to exercise writable `Dataptr`, retained
  writable pointers, and string `Set_elt`. Check writes before/after forks,
  missingness/width invalidation, error/interrupt rollback, and GC safety.
- Test row subsets with and without missing indices, outer-join string padding,
  wider binds, factors/logicals, foreign ALTREP, and fallback columns.

Performance acceptance is primarily allocation/scaling based:

- After stage 1, a certified-valid 1M × 16 ordinary-string rename should allocate
  at most 130 MB while retaining the isolation guarantee. On the baseline host, target
  under 60 ms for both ordinary string representations; use allocation and
  correctness rather than this host-specific time as portable gates.
- After owned backing, rename/select/relocate of the supported 1M × 16 owned
  columns must allocate under 1 MB, without scans of unchanged string values.
  The saved future rename allocation check must pass. Increasing row
  count tenfold with fixed columns must not introduce a column-sized allocation.
- A changed single column must not copy untouched payloads. First-write cost
  may scale with that one column; subsequent private writes must retain the
  existing sparse-mutation guarantees. Full replacement must not copy old values.
- Five-verb pipelines must have bounded handle depth and no retained history
  of obsolete results. Measure retained/peak memory as well as cumulative R
  allocation, since deferred copies change lifetime costs.
- Compare migrated direct verbs with the recorded baseline and an equivalently
  safe optimized-delegation reference where practical. Use identical Stata
  columns, classes, metadata, and alias guarantees. Separate operation planning,
  expression evaluation, gathering, result construction, and first-write costs.
  The initial snapshot microbenchmark alone cannot establish total benefit.
- Rerun filtering, arithmetic, aggregates, coercion, and read/write workloads.
  Investigate any repeatable median regression above 10% that also exceeds
  1 ms; new handles must not achieve cheap rename by making ordinary reads
  substantially slower. Use isolated processes for peak-memory comparisons.
- Require the complete R test suite, package build/check without new warnings,
  and existing reference-mutation allocation/rollback gates after native changes.

The safe validation prototype establishes only stage 1's opportunity. The
complete owned-column architecture has not been implemented or benchmarked;
its first-write, reader, and interoperability acceptance checks are required
before claiming the broader performance improvement.
