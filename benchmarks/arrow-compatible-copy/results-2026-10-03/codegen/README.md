# Compatible-fill candidate code generation

This is the installed arm64 library from clean `9ee3916c`. The receipt, native
library, bridge source, disassembler and three complete function excerpts
are bound by binding.json. The indirect symbol table identifies address
0x67fab8 as `_memcpy`.

After one per-chunk empty/null-count check, the compatible path calls this
bulk-copy stub at `0x4ed454` (Int32 integer), `0x4f98f0` (payload Float64) and
`0x4fb164` (semantic Float64). Each loads the selected source pointer and byte
length once for that copy. The nullable scalar loops remain beside the new
branch. The separately bound `9e6977a4` baseline excerpts contain scalar loops
on these routes, including per-element pointer/length/validity work.

No R element callback was removed: the old loops were already native.
This proves the compiled transfer changed as intended on this compiler and
host. It is not an end-to-end speed result or a cross-platform claim.
