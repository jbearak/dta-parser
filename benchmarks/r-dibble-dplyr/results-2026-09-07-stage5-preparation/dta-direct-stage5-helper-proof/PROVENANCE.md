# Temporary helper context feasibility proof

This directory contains preparation for Stage 5. Nothing here is production
dtatools code, a full mutation implementation, or a qualification of Stage 5.

`adapter-v1.R` and `adapter-v2.R` adapt the context method contract and expansion ordering from
dplyr 1.2.1 at commit `95740975c465c29cdb2abdfa13effddb948444dc`.
The exact pristine checkout is
`/private/tmp/dta-direct-stage1-validation/upstream/dplyr`.

Source mapping:

- `R/context.R`, `context_env`, `context_poke`, `local_mask`, and public helpers.
  The prototype installs a plain list of package-owned methods into dplyr's
  context and restores four slots with their original binding presence.
- `R/data-mask.R`, `DataMask` group helpers, `current_cols`, `pick_current`,
  `get_current_data`, and `get_rlang_mask`. The prototype uses ordinary R slices
  and fresh snapshot masks. It does not use R6, dplyr's native chop/evaluation
  routines, or the upstream obsolete-promise implementation.
- `R/across.R`, `expand_across`, and `R/pick.R`, `expand_pick`. The prototype
  calls these exact installed private expansion functions through its one
  optional adapter. It does not copy their implementation. Production must
  decide and document whether to adapt these implementations or retain a
  version-specific optional call. Public fallback helpers remain real dplyr.
- `R/mutate.R`, `mutate_col`, is the reference for expansion before group
  evaluation and separate evaluation of each expanded expression. The prototype
  deliberately stops before result assembly or expression sequencing.
- `tests/testthat/test-pick.R` is the source of the full-column versus
  group-specific selection witness and lexical selection-environment cases.
- `tests/testthat/test-across.R` informs current-column cleanup, unpacking,
  function setup and extra-dot evaluation counts.
- `tests/testthat/test-mutate.R` informs empty-group execution, saved group
  scalar independence, fresh lexical masks and nested regression #6762.
- `src/chop.cpp`, `dplyr_lazy_vec_chop_grouped`, supplies the rule added in
  `adapter-v2.R` for zero-row rowwise list columns. An empty list-of exposes its
  element prototype, while an untyped empty list exposes `logical()`. The
  before/after run uses the same `cases-v4.R` to demonstrate this difference.

The source-derived algorithms and test patterns are modified to use the small
standalone evaluator and base-R explicit checks. Additional tests compare it
with real dplyr verbs used only as independent oracles or nested user calls.
The owned evaluator never invokes a whole dplyr verb.

This prototype has no dtatools NOTICE change because no repository code is
modified. Any eventual incorporation must update installed NOTICE and package
README in the implementation PR with its exact destination and modifications.

The dplyr copyright and full MIT license below apply to source-derived material.

Copyright (c) 2026 dplyr authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
