# Scalar callback paths in the measured R installation

This is static inspection of the installed arm64 libraries. No new benchmark,
profile, compilation, or package modification was performed for this note.
The instruction addresses identify this build, not a portable R API guarantee.

## Bound installation

The screen's `provenance-before.json` records R version 4.6.1 (2026-06-24),
platform `aarch64-apple-darwin25.4.0`.

| Artifact | SHA-256 |
| --- | --- |
| `/opt/homebrew/Cellar/r/4.6.1/lib/R/lib/libR.dylib` | `b32773dcfe9563dd3b71154ff333115e52453ed279f2ee9e2b337e4ec88de990` |
| R executable, recorded by the screen | `a548d8126764a013e73c25438e39984adcfce5d8573cf0000d40a3a65502fc34` |
| `/opt/homebrew/Cellar/r/4.6.1/bin/Rscript` | `6bd8b8412ef511087496292e1ec58ecc25a22e998e6bad88a6f16fa7f06b402f` |
| `scalar_access_probe.so` | `1f88f7b429a44d0696ae399b4eaaa87bf1d80eca3287f76d716141cbeca17445` |
| Screen worker, `scalar-worker.R` | `66851d08551144a04d5b534b24cc7083f7876b45f80bf121ac00282f561ec8a9` |
| Screen controller, `scalar-benchmark.py` | `dc336e357c31bd44d97a772694dd59c126f9616b8d09bf4f65ef5f5b37f4aab8` |

Package role `current` is the previous gather4-v2 candidate, not the release
baseline. Its library is in
`${DTATOOLS_DECODE_WORK}/candidate-gather4-v2/library`.
Role `dispatch` is `candidate-dispatch-v2/library` beneath this note's directory.
Their exact package inventories and source receipts are in the screen provenance.

## Public scalar access calls the length method per element

The installed `_REAL_ELT` checks the vector type and index. For an ALTREP input,
it calls `_ALTREP_LENGTH` before dispatching `_ALTREAL_ELT`. Selected instructions:

```text
00000000000d96f8 <_REAL_ELT>:
 d9708: and x9, x8, #0x1f
 d970c: cmp x9, #0xe                    ; REALSXP
 d9718: tbnz x1, #0x3f, 0xd9778         ; negative index error
 d9720: tbnz w8, #0x7, 0xd972c          ; ALTREP branch
 d9730: bl 0x12f80 <_ALTREP_LENGTH>
 d9734: cmp x19, x0
 d9738: b.gt 0xd9778                    ; bounds error
 d9774: b 0x130d8 <_ALTREAL_ELT>

0000000000012f80 <_ALTREP_LENGTH>:
 12f80: ldr x8, [x0, #0x30]
 12f84: ldr x1, [x8, #0x68]
 12f88: br x1                          ; registered length method

00000000000130d8 <_ALTREAL_ELT>:
 130d8: ldr x8, [x0, #0x30]
 130dc: ldr x2, [x8, #0x88]
 130e0: br x2                          ; registered element method
```

For an unmaterialized metadata proxy, the registered length method is
`metadata_proxy_length`: resolve source, then `XLENGTH(source)`. On the compact
source this dispatches `numeric_length`, which checks data2, retrieves data1 and
the external-pointer descriptor, then reads `data->length`. The installed
`numeric_length` has calls to `R_altrep_data2`, `R_altrep_data1`, and
`R_ExternalPtrAddr` at `0x2409c`, `0x240c4`, and `0x240c8` respectively.

## Base is.na bypasses public REAL_ELT inside its double loop

`_do_isna` obtains the input length once before allocating its output.
Its REALSXP loop then calls the element method directly. The loop contains no
call to `_REAL_ELT` or `_ALTREP_LENGTH`:

```text
0000000000049874 <_do_isna>:
 49978: bl 0x12f80 <_ALTREP_LENGTH>      ; setup, before output allocation
 ...
 49d30: ldrb w8, [x19]
 49d34: tbnz w8, #0x7, 0x49d44
 49d38: add x8, x19, x22, lsl #3       ; ordinary-double branch
 49d3c: ldr d0, [x8, #0x30]
 49d40: b 0x49d50
 49d44: mov x0, x19                    ; ALTREP branch
 49d48: mov x1, x22
 49d4c: bl 0x130d8 <_ALTREAL_ELT>
 49d50: fcmp d0, d0                    ; NaN test
 49d54: cset w8, vs
 49d58: str w8, [x21, x22, lsl #2]     ; logical output
 49d5c: add x22, x22, #0x1
 49d60: cmp x20, x22
 49d64: b.ne 0x49d30
```

For the bare proxies in the benchmark, this reaches `metadata_real_value`
without a new outer length lookup for every value. The one-time R dispatch,
length lookup, allocation, and final attribute handling still occur.

## What direct metadata forwarding removes

The current package's `metadata_real_value` resolves its source and tail-branches
at `0x152cc` to stub `0x47917c`, which the indirect-symbol table identifies as
`REAL_ELT`. Therefore the compact source undergoes another length lookup before
its scalar getter runs.

Dispatch-v2 retains the materialized-source fallback and checks the compact
ALTREP class. Its matched branch tail-jumps directly from `0x152f4` to
`numeric_value` at `0x26900`. That getter still checks materialization, descriptor
availability, index bounds, and numeric storage kind before decoding.

The following counts are derived from the disassembly and package source for
an unmaterialized, one-level metadata proxy over a compact numeric source.
They count per-element callbacks only, excluding scan setup:

| Caller and package role | metadata_proxy_length | numeric_length | metadata_proxy_source | numeric_value |
| --- | ---: | ---: | ---: | ---: |
| Base is.na, current | 0 | 1 | 1 | 1 |
| Base is.na, dispatch-v2 | 0 | 0 | 1 | 1 |
| Probe REAL_ELT, current | 1 | 2 | 2 | 1 |
| Probe REAL_ELT, dispatch-v2 | 1 | 1 | 2 | 1 |

Thus direct forwarding removes an inner length lookup and R dispatch in both
callers. Public probe access retains its outer proxy-length traversal. This is
a concrete difference in executed work; it does not assign a measured percentage
of the total runtime to each callback.

## The C probe also computes more than a missingness mask

`scalar_access_scan` calls the public API at `0x17c8`, through stub `0x19ac`,
identified as `REAL_ELT`. After its NaN test at `0x17cc`, each non-NaN value calls
`R_finite` at `0x17d8`, through stub `0x1a00`. It then updates the finite checksum
and infinity counts, and maintains traversal state. Coarse interrupt checks are
also present. Base is.na's loop instead compares NaN and stores one logical.

The C-probe/base-is.na ratio therefore includes different API and consumer work.
It cannot be interpreted as pure callback overhead or as an R-versus-C ratio.
Within each benchmark case, all package variants use the same probe binary,
traversal, repetition count, and exact validation.

## Reproduce the static inspection

```sh
xcrun llvm-objdump -d --disassemble-symbols=_REAL_ELT,_ALTREP_LENGTH,_ALTREAL_ELT,_do_isna /opt/homebrew/Cellar/r/4.6.1/lib/R/lib/libR.dylib
xcrun llvm-objdump -d --disassemble-symbols=_metadata_proxy_length,_metadata_real_value,_numeric_length ${DTATOOLS_DECODE_WORK}/candidate-gather4-v2/library/dtatools/libs/dtatools.so
xcrun llvm-objdump -d --disassemble-symbols=_metadata_real_value ${DTATOOLS_SCALAR_WORK}/candidate-dispatch-v2/library/dtatools/libs/dtatools.so
xcrun llvm-objdump -d --disassemble-symbols=_scalar_access_scan ${DTATOOLS_SCALAR_WORK}/scalar_access_probe.so
xcrun llvm-objdump --macho --indirect-symbols ${DTATOOLS_SCALAR_WORK}/scalar_access_probe.so
```

The measured worker calls `.Call('scalar_access_scan', x, order, NULL,
PACKAGE='scalar_access_probe')`; `order` is `sequential`, `reverse`, or
`permuted`. Its mask operation is `base::is.na(x)`. The worker is executed by the
bound `Rscript --vanilla`, with the selected source-bound package library first
in `.libPaths()`. Exact invocation arrays are retained in each screen raw record.
