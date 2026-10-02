# Full-chunk scalar cache candidate

This private candidate starts from the measured candidate-gather4-v2 source. The current package source was byte-compared with that baseline before copying; only four files differ. No production source was edited and no benchmark was run by this agent.

## Change

The previous retained scalar cache requested a region starting at the queried row and cached that suffix. Descending reads therefore missed at every earlier row even when they stayed within one immutable chunk. The new internal Rust FFI returns the complete owning chunk's base pointer and half-open row bounds. C stores those complete bounds in the existing per-descriptor scalar cache. Forward, reverse, and permuted reads within that chunk can reuse the same borrowed pointer.

The existing numeric-region ABI and implementation are unchanged, including suffix semantics, requested-length clipping and empty-region behavior. Plain DTA scalar decoding is unchanged. There is no R-call registration, public R API, descriptor layout, allocation policy or owner-lifetime change.

## Safety

The new FFI rejects null arguments, descriptors without retained owners, and indices outside either descriptor or owner length. Empty owners have no valid scalar index. Chunk lookup uses the owner's already-validated sorted cumulative ends; its returned base is the start of the retained sliced Arrow buffer or RRaw chunk. Valid output bounds contain the queried index. Buffer-size checks at owner construction bound pointer offsets and multiplication. The original descriptor continues to retain the immutable owner, and RRaw allocations continue to be rooted through the descriptor's protected slot. Cache updates occur only in the existing R scalar getter; native worker and bulk paths remain read-only. Cloned descriptors still start with an empty cache.

## Validation

Three native tests pass: complete sliced Arrow chunks in arbitrary order after dropping source arrays, all RRaw storage widths/chunk edges, and empty/plain/invalid arguments. The Arrow test also verifies unchanged bulk-region suffix pointers and lengths. Existing R owned-numeric tests now include a deterministic permutation and scalar rereads after snapshot materialization and GC, in addition to their prior native Arrow batch/tag/temporal/lifetime coverage. The targeted R suite passes; exact counts and hashes are in reverse-validation.json. Clippy for lib/tests with warnings denied and formatting checks pass. The recorded build receipt was reverified after the R run. An initial results-table CSV export failed after successful assertions because it retained a list column; the corrected validation rerun exits cleanly, and the initial log is preserved.

## Code-generation caveat

The common numeric_value stack frame grows from 48 to 64 bytes because the new cache miss returns three outputs. The plain DTA branch still performs no extra calls; the added validation and outputs are confined to the retained cache-miss branches. The getter grows from 243 to 282 assembly lines. This candidate preserves that evidence for the parent's paired performance screen; no speedup is asserted yet. Assembly and library hashes are saved in reverse-assembly.json.
