---
status: accepted
---

# Trim per-group mask work

Grouped verbs evaluate each expression once per group in a fresh data mask
from `make_mask()`, through `with_group()`. Three steps repeated work whose
result was the same for every group:

- `make_mask()` called `rlang::as_data_pronoun()` on the shared bindings for
  every group. The pronoun only wraps the bindings, which change only when
  an expression adds or removes a column.
- `with_group()` called `rlang::eval_tidy(quo, mask)`, whose default
  `env = caller_env()` runs `caller_env()` and `parent.frame()` to find the
  frame that made the call.
- Installing a grouped summary's result captured each group's chunk with
  its own call of `.capture_dibble_nested()` through `lapply()`.

`make_mask()` now builds the pronoun with the bindings and gives it to every
group's mask. `with_group()` passes `environment()`, the frame the default
would find. `.capture_dibble_chunks()` calls
`C_dtatools_capture_atomic_list()`, which captures the chunks in order as
`C_dtatools_capture_atomic()` would, up to the first one it declines, and
leaves the rest to `.capture_dibble_nested()` in order.

Results are unchanged. A traced or replaced `rlang::as_data_pronoun()` sees
one call per set of bindings instead of one per group, and a traced
`rlang::caller_env()` or `parent.frame()` no longer sees the evaluation of
each group. A traced or replaced `.capture_dibble_nested()` or
`.metadata_copy()` no longer sees an atomic chunk's capture, as ADR 0055
already allows for a group's result. The maintainer approved changing
decisions that block measured speedups on 2026-10-22.
