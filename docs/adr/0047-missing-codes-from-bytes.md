# The npm package reads missing codes from a column's bytes, not from numbers

Amends ADR 0037 for TypeScript. `NumberColumn.values` still holds `.`
as `NA` and `.a` to `.z` as tagged NaNs. What changes is that the
package no longer reads or writes a code through a JavaScript number.

1.2.0 put each value's code in its NaN's payload and read it back with
`missingCode(values[i])`. V8 keeps a NaN's payload when it loads a
`Float64Array` element into a number. JavaScriptCore, the engine of Bun
and Safari, does not. Every NaN it loads becomes `0x7ff8000000000000`.
So on Bun `missingCode(NA)` was 0, `readRows` gave `.a` as a plain NaN,
a labelled `.a` showed as `.`, and `writeDta` refused `NA`.
manuscript-markdown ships its CLI as Bun-compiled binaries and runs its
tests on Bun, so it hit all of this.

A typed array's bytes keep the payload on every engine. So do
`slice()`, `subarray()`, `set()` from another Float64Array, and
`new Float64Array(float64Array)`, which the spec defines as byte copies.

**Codes cross between the module and a `Float64Array` as 32-bit
words.** The reader writes the words of `NA` and the tagged NaNs into
the column through a `Uint32Array` over its buffer. `readRows`,
`readRowsAt`, `dtaKeys` and `writeDta` of a `Float64Array` read the
words back. None of them depends on the engine.

**`missingCodes(column)` is new.** It gives every value's code, read
from the bytes, as 1.1's `NumberColumn.missing` held them. Code that
must run on any engine reads a column's letters with it.

**The functions that pass a tagged NaN as a number keep 1.2.0's API.**
On V8 nothing changes. The package checks once, at load, whether a
tagged NaN loaded from a `Float64Array` keeps its payload. Where it
does not:

- `missingCode(x)` is 0 for every number, `naTag(x)` is undefined and
  `isTaggedNa(x)` is false. No NaN that reaches them carries a code,
  and an untagged NaN is a number, as on V8.
- `NA` is a plain NaN.
- `taggedNa(letter)` throws `DTA_INVALID`. Returning a plain NaN would
  drop the letter without a word, which is the bug this ADR fixes.
- `formatValue` and `dtaKey` of a NaN number treat it as `.`, so a
  labelled `.a` passed as `values[i]` shows as `.`. A `readRows` cell,
  or `missingValue(missingCodes(column)[i])`, shows its label.
- `writeDta` refuses a NaN that is not a missing value, as on V8, and
  the message says the engine cleared its payload. A column copied
  value by value (`Array.from(values)` or `map`) is refused. Writing
  each of its letters as `.` would be silent loss.

## Considered options

- **Bring back `NumberColumn.missing` beside the values.** Code written
  for 1.1 would work again. But it is the second source of truth ADR
  0037 removed, and a column that a caller edits would disagree with
  it. `missingCodes(column)` gives the same array on request.
- **Treat every untagged NaN as `.` on JavaScriptCore.** `NA` would
  write there, but `.a` to `.z` copied value by value would be written
  as `.` without a word.
- **Let `taggedNa` return a plain NaN on JavaScriptCore.** Code that
  makes letters as numbers would run and lose them.
- **Hold codes in something other than NaNs**, objects or a second
  array. That reverses ADR 0037 on every engine to fix two.

## Consequences

- Released as 1.2.1 even though it adds an export, `missingCodes`. The
  user approved 1.2.1 for this fix.
- On Bun and in Safari, `readRows`, `readRowsAt`, `formatValue` of
  their cells, `dtaKeys`, `missingCodes`, and `writeDta` of `MISSING`
  values or of a column as read give the same answers as on Node.
- `taggedNa`, `naTag`, `isTaggedNa`, `missingCode(values[i])`, and
  `formatValue` or `dtaKey` of `values[i]` see letters on V8 only. The
  doc comments and docs/typescript.md say so.
- CI runs the npm package's tests on Bun as well as Node, so a path
  that reads a code through a number fails there.
- `js/tsconfig.json` has no `paths`. Bun followed them to `src/`, whose
  `.wasm` import it cannot load. `src/node.ts` imports `./index`, which
  the build keeps external, as it keeps `./format-entry`.
