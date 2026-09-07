# Stage 5 helper context feasibility proof

A package-owned rlang evaluator can supply the context used by real dplyr
helpers without invoking a whole dplyr verb or replacing namespace functions.
The final standalone matrix passes 35 cases on installed dplyr 1.2.1 and
R 4.6.1. This proves a small adapter is feasible. It does not complete Stage 5.

The executable candidate is [adapter-v2.R](adapter-v2.R), with
[cases-v4.R](cases-v4.R). The accepted run is
[run-v4-after-empty-fix/execution.log](run-v4-after-empty-fix/execution.log).
Full values, conditions, context binding presence, method calls, package paths,
and runtime metadata are retained in that directory's `observations.rds` and
`observations.txt`. The 35 cases include expected-error and explicit-difference
checks, so this is not a claim that 35 complete production operations passed.

The adapter writes only four entries in dplyr's private context environment:
`mask`, `column`, `across_if_fn`, and `across_frame`. It preserves their original
values and whether each binding existed. A plain R list implements the helper
method contract. The evaluator creates a fresh rlang mask for each group and
evaluates one expression into raw chunks. It performs no result assembly,
expression sequencing, Stata typing, ownership adoption, or S3 dispatch.

Private version-specific access is isolated in `proof_adapter`. In addition to
the context environment it calls installed `expand_pick()` and
`expand_across()`. Those functions prepare expressions, and the package-owned
loop evaluates them. Qualified and aliased public helpers still run their real
dplyr implementations through the installed context. Production must decide
whether to adapt the expansion algorithms or keep explicitly supported private
calls. This experiment is not permission to make the core depend on dplyr when
the optional adapter is absent.

The observed methods are:

- `get_current_group_size()` and `get_current_group_id()`.
- `current_key()` and `current_rows()`.
- `current_non_group_vars()`, `current_cols()`, and `get_current_data()`.
- `get_rlang_mask()` and `pick_current()`.

The prototype also defines nine supporting methods suggested by the upstream
mask contract. The final matrix does not call them, so their definitions are
not qualification evidence. Future error formatting, selection bookkeeping,
and `.keep` behavior may need more methods or package-owned responsibilities.

The accepted observations include these distinctions:

| Witness | Observed behavior |
| --- | --- |
| Plain rlang mask without the adapter | Qualified `dplyr::n()` fails with the expected missing-context error. |
| Qualified helpers, lexical aliases, arbitrary helper closures | `n()`, group id, keys, and original row positions match real dplyr. |
| `.data`, `.env`, helper-created selection quosures | Values and lexical selection environments match. |
| Visible `pick()` expansion | Selection sees full current columns and stays consistent across groups. |
| Aliased `pick()` fallback | Selection sees group-specific slices and may choose different columns. The zero-value witness selects no columns through expansion, but `x` then `y` through fallback. |
| Unnamed expanded `across()` | Evaluation proceeds by column then group. The function factory runs once overall. |
| Aliased runtime `across()` | Evaluation proceeds by group then column. In this exact runtime the function factory runs twice per group. |
| Extra dots in `across()` | Expansion is refused and the extra argument is evaluated once per group. The real deprecation warning is retained. |
| `.unpack = TRUE` | Expansion is refused and runtime helper results unpack correctly. |
| `if_any()`, `if_all()`, `c_across()`, nested `cur_column()` | Runtime helpers use the adapter and match real dplyr values. |
| Rowwise list columns | Nonempty groups extract list elements. At zero rows, list-of columns expose their element prototype, while untyped empty lists expose `logical()`. |
| Empty groups, zero groups, zero-row rowwise input | The expression still executes with size zero and the expected group state. |
| `.by` | Supplied first-appearance group keys and row positions are visible correctly. |
| Nested prototype and real dplyr calls in both directions | Outer group and current-column state is restored. Nested prototype calls also preserve independent group scalars. |
| Errors, deliberate warnings, and an R interrupt condition | Context is restored during unwinding. The interrupt case signals an R condition; it does not deliver an OS signal. |
| Saved group scalars, keys, row positions | Earlier results remain unchanged after later groups and nested calls. |

The factory-count diagnostic is retained separately in
[run-factory-diagnostic/factory-calls.R](run-factory-diagnostic/factory-calls.R).
Actual call stacks show one runtime factory evaluation through
`is_missing(.fns)` and another through `quo_eval_fns()`, in both implementations.
The original assumed count of one per group was wrong. Do not encode that
assumption in a replacement evaluator.

Captures require a production decision. Ordinary columns, pronouns, quosures,
closures, and deferred promises remain readable in this prototype because each
group receives a snapshot. Real dplyr invalidates deferred column resolution
with an obsolete-data-mask error. Root's separate c8 baseline finds the same
existing dtatools error behavior. The prototype records this difference as an
explicit passing observation, not as parity or a proposed change to dtatools.
It proves no native write isolation or safe capture of foreign storage.

All 828 dplyr namespace functions have identical function objects, bodies,
formals, environments, and binding-lock state before and after the final run.
All 828 bindings remain locked. The 51 top-level helper function definitions
parsed from pristine `R/context.R`, `R/across.R`, and `R/pick.R` also match the
installed function bodies and formals exactly. No namespace body was patched.

The source reference is the clean dplyr checkout at
`95740975c465c29cdb2abdfa13effddb948444dc`, under
`/private/tmp/dta-direct-stage1-validation/upstream/dplyr`. Its full tracked
inventory is hashed before each run and checked afterward. Installed dplyr is
the existing CRAN 1.2.1 installation at
`/opt/homebrew/lib/R/4.6/site-library/dplyr`; it is not claimed to have been
installed from that Git checkout. Its metadata says it was built with R 4.6.0.
The running R is Homebrew 4.6.1, revision 90187. This proof does not establish
the supported adapter minimum or run the helper matrix on clean R 4.6.0.
The separate minimum-version research and its older-binary limitations remain
applicable.

Each R run binds 3,595 input files before execution, including its exact runner,
adapter, cases, full pristine dplyr checkout, installed R tree, and 15 installed
package trees. The final audit verifies all 22 loaded namespace descriptions
and 13 registered non-base DLLs occur in that input inventory. Every bound
input remains unchanged. `getLoadedDLLs()` is not a complete OS loaded-image
inventory. External OS/Homebrew dylibs and the full Python runtime closure
were not frozen, so this is not a self-contained host replay bundle.

The final dplyr DLL SHA-256 is
`14f6ce8c524f8451867c5811046eac45887f494b9d0b9d8b647ea83385e77966`.
The final adapter SHA-256 is
`c17300a7ff1f30a2389c8ac033c2982ef14f8dd0601c460783bd372182445d0d`.
The final cases SHA-256 is
`3f4540ad6e931127d652382790017fbc11e07265992982542a609a487d1e2ce9`.
The completed run receipt SHA-256 is
`bf0aaa716db4c4b860f11265378bd09c6dcad0f52849f5295fa0eb6b6c738cbe`.

The runner refuses an existing output or receipt before launching R. Its output
manifest is computed before opening the destination and excludes itself; a
separate receipt binds the completed manifest. The post-auditor exercised the
real existing-output rejection and verified that no completed output changed.
The second audit binds all 59 then-existing local proof files, including its
launcher and auditor, before executing the auditor. Its receipt SHA-256 is
`c6f127ec9d3a86f7c80acaa626f664ff3b6f2c9ce2dfede4b542e9213f1dc00c`.

All failed attempts are preserved:

| Run | Result and disposition |
| --- | --- |
| `run-v1` | Four failed checks plus an inventory-printer error. Whole-case binding-presence checks counted real dplyr's creation of NULL slots as an adapter failure; the first factory-count expectation was wrong; the printer mishandled the base namespace. The raw log remains; no final observations file was produced. |
| `run-v2` | 29 of 30 cases pass. Exact restoration is now checked around each prototype invocation, while whole-case records retain real dplyr's slot-presence changes. The only failure is the assumed factory count. |
| `run-factory-diagnostic` | Both paths call the factory four times for two groups, and all 51 parsed helper definitions match installed code. |
| `run-v3` | 33 of 34 cases pass. The new zero-row rowwise witness exposes the real list-prototype gap and a separately incorrect manually assembled zero-row key representation. |
| `run-v4-before-empty-fix` | 33 of 35 pass with `adapter-v1.R`. The helper fixture now consumes real rowwise group keys. Both untyped and typed empty-list cases fail on the actual list-prototype rule. |
| `run-v4-after-empty-fix` | The unchanged `cases-v4.R` passes all 35 cases using `adapter-v2.R`. Two warning records remain intentional: across dots deprecation and the nested deliberate-warning case. |

To repeat the accepted R proof, choose a fresh direct-child output name:

```sh
python3 /private/tmp/dta-direct-stage5-helper-proof/run-proof.py \
  run-new-name adapter-v2.R cases-v4.R
```

The script intentionally requires this exact host runtime, source checkout,
and installed dplyr version. Read and qualify those requirements before moving
it to another host. Do not execute historical absolute-path recipes in place.

Stage 5 still needs the actual evaluator and supported-version decision,
sequential Stata typing, result sizing/installation, deletion and repeated names,
computed grouping, `.keep`, full warning/error contracts, capture invalidation,
unknown/foreign input adoption, source/result write isolation, native lifetime
qualification, absence-capable core execution, and all required package checks.
The current-column slot must reset between sequential expressions, and expanded
across expressions must all evaluate before their results are installed.
Group metadata assembly is outside this helper proof. No timings, package
installs, production edits, Git changes, or downstream renv operations were run.

[PROVENANCE.md](PROVENANCE.md) records adapted source and test patterns, exact
files, modifications, and the full dplyr MIT notice. Any eventual incorporation
must update the installed package NOTICE and README in the implementation PR.
