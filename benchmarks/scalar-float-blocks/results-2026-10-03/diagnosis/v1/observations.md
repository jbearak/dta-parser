# Scalar exception-loop diagnosis

The public 720-observation screen supplied the red performance signal. This static diagnostic changes no package source and records no new timings. The fresh installed-DLL extracts are tied to their actual original build receipts in binding.json. The unmodified candidate compilation uses the recorded build command and compiler with vectorization remarks added; its private object, remarks, complete source inventory and command are bound by remarks-command.json.

For modern float input with missings, float output and active fit checks, the baseline addition dispatch reaches a runtime alias guard at 0x1922c0 and then a vectorized exact loop beginning at 0x1958bc. It performs four-lane classification, fit checks, finite-anchor selection, binary64 arithmetic and narrowing, plus vector reductions.

The candidate equivalent exact loop at 0x1a1130 through 0x1a11b4 is scalar. It reloads proof bounds, branches on the lower-bound comparison, and uses scalar widening, addition, narrowing, output selection and reductions. The same candidate ordinary tile remains vectorized at 0x1a11fc. The fourth failed tile extends this scalar exact loop to the rest of the current captured span, at most 16,384 rows.

Clang reports 20 VectorizationNotBeneficial and 20 InterleavingNotBeneficial remarks for arithmetic_float_scalar_write, with 160 Vectorized and 60 VectorMixedPrecision records. It reports no illegal memory dependence for this writer. Therefore the evidence establishes lost exception-path vectorization, but does not establish whether bound loads, alias-versioning cost, reduction framing or outlining caused the cost-model choice.

The smallest first experiment is to copy the immutable lower, upper and anchor values into local scalars before the writer loops, conditionally reading lower/upper only when check_fit is true. This preserves the proof and exact loop formulas while removing repeated proof-memory accesses. Inspect emitted exception-loop code before a clean package build; any performance claim still requires the same full semantic qualification and balanced screen.
