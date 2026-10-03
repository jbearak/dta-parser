# Installed long plus float addition code

The clean 387227 installed DLL was freshly disassembled after checking the full
build/source inventories and the arithmetic header bytes against immutable Git
blobs. `candidate-codegen-binding.json` binds the actual DLL, tool, command,
source and complete output. The focused excerpts are copied from that output.
This is code inspection, not a performance result or a cross-compiler claim.

The proof loop at 0x192414–0x192480 uses four signed `smax.4s` reductions for
int32 and four unsigned `umax.4s` reductions for float magnitudes, followed by
horizontal maxima. The signed reduction preserves the INT32_MIN admission.

The ordinary writer at 0x1926ec onward uses `sshll`/`scvtf.2d` for exact integer
widening, `fcvtl` for exact binary32 widening, and `fadd.2d` plus vector stores.
The opposite operand-order branch is also vectorized. There is no per-row
missing union count or result classification inside the proved ordinary loop.
The generated function includes pointer-overlap guards and scalar short tails.

The dedicated `arithmetic_long_float_add_exact` helper starts at 0x1f4d58. Its
modern tagged path still has vectorized classification, exact widening,
binary64 addition, missing-union accumulation and NA selection. The excerpt
at 0x1f52a8–0x1f5524 shows that vector path. Scalar tails remain present. This
avoids the previously observed scalar-block failure mode where an altered
outer loop stopped the compiler vectorizing dense exceptions, but it does not
establish that the new proof and helper dispatch have zero overhead.

The 696-observation screen therefore includes random dense and all-tag inputs,
both operand orders, short chunks and plain typed/bare controls. Its input
construction, qualification and counters are outside the retained intervals.
Retained short chunks can also pay repeated chunk searches in the existing
span reader; any such attribution needs separate work counts after measuring.
