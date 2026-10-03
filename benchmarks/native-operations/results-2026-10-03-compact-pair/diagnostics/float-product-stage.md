# Direct compact float multiplication: isolated stage

This stage compares the previous compact-pair binary64-domain proof (`f729c488`) with the direct binary32 multiplication implementation (`54d29130`). It retains the established binary64 expression and whole-column storage decision exactly, using a binary64 recomputation whenever the rounded float lands on the observed-value limit. The measured package source is unchanged by the later manifest-only commit `102d4123`.

The complete screen contains 18 cases, three representations, two builds and six balanced rounds: 648 qualified observations. Every result, storage kind, missing mask/count, source value/state and native-entry count passed. The actual worker launcher/runtime, receipt-bound packages and controllers matched before and after. The independent audit reproduced all rows and ratios. Retained CPU intervals were 51–184 ms and wall intervals 50–184 ms; calibration targeted 150 ms but some retained intervals were shorter.

Four changed multiplication cases improve 1.517–1.948× and reach 0.870–1.490× typed-double CPU. This is not a universal parity result. Of fourteen unchanged controls, twelve vary between 0.9933× and 1.0077×, missing long+float addition is 1.0371× faster, and missing int16+float addition is 0.9482× by ratio of medians (about 5.5% slower). The latter remains 2.356× typed double.

The complete table uses median per-call CPU. A gain above one is faster; a compact/typed or compact/bare ratio above one is slower. Typed double retains the package's storage/missing policy, whereas bare double arithmetic has a different output contract.

| Input | Missing | Operation | Before ms | After ms | Gain | After / typed | After / bare |
|---|---|---|---:|---:|---:|---:|---:|
| float | none | float_multiply | 0.5281 | 0.2711 | 1.948× | 0.870× | 0.987× |
| float | none | scale_binary | 0.3253 | 0.3275 | 0.993× | 1.144× | 1.228× |
| float | none | scale_general | 0.4170 | 0.4197 | 0.994× | 1.409× | 1.559× |
| float | sparse | float_multiply | 0.7922 | 0.4660 | 1.700× | 1.490× | 1.709× |
| float | sparse | scale_binary | 0.3286 | 0.3269 | 1.005× | 1.162× | 1.277× |
| float | sparse | scale_general | 0.5474 | 0.5453 | 1.004× | 1.961× | 2.058× |
| int | none | mixed_add | 0.5690 | 0.5646 | 1.008× | 1.572× | 1.918× |
| int | none | mixed_divide | 0.5910 | 0.5906 | 1.001× | 1.758× | 2.084× |
| int | none | mixed_multiply | 0.5623 | 0.3637 | 1.546× | 1.018× | 1.243× |
| int | none | mixed_subtract | 0.5600 | 0.5634 | 0.994× | 1.668× | 1.937× |
| int | none | scale_binary | 0.2440 | 0.2450 | 0.996× | 0.767× | 0.831× |
| int | sparse | mixed_add | 0.7156 | 0.7547 | 0.948× | 2.356× | 2.782× |
| int | sparse | mixed_divide | 0.7401 | 0.7413 | 0.998× | 2.240× | 2.533× |
| int | sparse | mixed_multiply | 0.7133 | 0.4701 | 1.517× | 1.354× | 1.763× |
| int | sparse | mixed_subtract | 0.7109 | 0.7153 | 0.994× | 2.149× | 2.535× |
| int | sparse | scale_binary | 0.2427 | 0.2411 | 1.007× | 0.809× | 0.894× |
| long | none | long_float_add | 0.3823 | 0.3836 | 0.997× | 1.218× | 1.405× |
| long | sparse | long_float_add | 0.5599 | 0.5399 | 1.037× | 1.720× | 1.927× |

For the missing mixed-add control, the median paired gain is 0.9739×, while the ratio of medians is 0.9482×. Candidate-second odd rounds are slower; candidate-first even rounds are near equal or faster. A fresh disassembly comparison of the entire existing binary64 pair producer finds 61,188 instructions in both builds, with only 286 verified address relocations to `R_NaReal` and one call relocation to `R_CheckUserInterrupt`. Both complete bodies were regenerated from receipt-bound installed binaries. This narrows the code-generation question but does not explain the timing difference: caller dispatch, addresses, cache behavior, allocation history and dynamic execution remain outside that static comparison.

The production mechanism is visible in the new float producer: sixteen-row vector iterations use binary32 multiplication, preserving the existing missing-union count and a maximum rounded-magnitude reduction. Promotion recomputes from captured original inputs rather than widening provisional rounded values. This instruction evidence supports the intended mechanism; timing gains are the measured public-operation results above.

Both baseline and candidate passed the same 51,818 focused assertions and all 102 untimed general arithmetic acceptance cases. Candidate full-suite qualification passed 96,418 assertions across 1,780 blocks, with no failures/errors/skips and seven preexisting warnings. A separate optimized/UBSan semantic diagnostic checked 36,914,944 products each across four rounding modes; independent rational witnesses validate the exact product and equal-limit fallback. These are single-host results for constructed deterministic columns. Retained spans, raw import encodings, all missing tags, boundary values, ownership and reentry are correctness coverage, not throughput claims in this screen.

Evidence is retained in `float-product-timings/`, `float-product-audit.{py,json}`, `float-product-validation-binding.json`, `float-product-compiler-diagnostic.json`, `mixed-add-control-audit.{py,json}`, `mixed-add-disassembly-binding.{py,json}` and `f32-equivalence/`. The broader original acceptance matrix, integrated conformance and final PR publication remain separate steps.
