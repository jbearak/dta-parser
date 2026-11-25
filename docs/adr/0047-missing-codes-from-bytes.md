# The npm package reads missing codes from a column's bytes, not from numbers

Amends ADR 0037 for TypeScript: `NumberColumn.values` still holds `.`
as `NA` and `.a` to `.z` as tagged NaNs, but nothing in the package
reads or writes a code through a JavaScript number any more.

1.2.0 put each value's code in its NaN's payload and read it back with
`missingCode(values[i])`. V8 keeps a NaN's payload when it loads a
`Float64Array` element into a number. JavaScriptCore (Bun, Safari) does
not: every NaN it loads becomes `0x7ff8000000000000`. So on Bun
`missingCode(NA)` was 0, `readRows` gave `.a` as a plain NaN, a labelled
`.a` showed as `.`, and `writeDta` refused `NA`. manuscript-markdown,
whose CLI ships as Bun-compiled binaries and whose tests run on Bun, hit
all of this. The bytes of a typed array keep the payload on every engine,
and so do `slice()`, `set()`, `subarray()` and `Float64Array.from` of
one, which copy bytes.

**Codes cross between the module and a `Float64Array` as 32-bit words.**
The reader writes `NA`'s and the tagged NaNs' words into the column
through a `Uint32Array` over its buffer; `readRows`, `readRowsAt`,
`dtaKeys` and `writeDta` of a `Float64Array` read the words. None of
them depends on the engine.

**`missingCodes(column)` is new**: every value's code, read from the
bytes, as 1.1's `NumberColumn.missing` held them. It is how code that
must run on any engine reads a column's letters, and it is the
replacement for `missing` that 1.2.0 lacked on JavaScriptCore.

**The functions that pass a tagged NaN as a number keep 1.2.0's API.**
On V8 they are unchanged. Where numbers lose NaN payloads, which the
package checks once at load by loading a tagged NaN from a
`Float64Array`:

- `missingCode(x)` is 0 for every number, `naTag(x)` undefined and
  `isTaggedNa(x)` false: no NaN that reaches them carries a code, and
  an untagged NaN is a number, as on V8.
- `NA` is a plain NaN.
- `taggedNa(letter)` throws `DTA_INVALID`. A plain NaN in its place
  would lose the letter without a word, which is the defect this ADR
  fixes.
- `writeDta` refuses a NaN that is not a missing value, as on V8, and
  says the engine cleared its payload. A column copied value by value
  (`Array.from(values)`, `map`) is refused rather than written with
  every letter turned into `.`.

## Considered options

- **Bring back `NumberColumn.missing` beside the values.** Code written
  for 1.1 would work again, but it is the second source of truth ADR
  0037 removed, and a column a caller edits would disagree with it.
  `missingCodes(column)` gives the same array on request.
- **Treat every untagged NaN as `.` on JavaScriptCore.** `NA` would
  write there, but `.a` to `.z` copied value by value would be written
  as `.`, silently.
- **Have `taggedNa` return a plain NaN on JavaScriptCore.** Code that
  makes letters as numbers would run and lose them.
- **Hold codes in something other than NaNs** (objects, or a second
  array only). Reverses ADR 0037 for every engine, to fix two.

## Consequences

- Released as 1.2.1, though it adds an export
  (`missingCodes`); the user approved 1.2.1 for this fix.
- On Bun and in Safari, `readRows`, `readRowsAt`, `formatValue` of their
  cells, `dtaKeys`, `missingCodes` and `writeDta` of `MISSING` values or
  of a column read give the same answers as on Node.
- Code that uses `taggedNa`, `naTag`, `isTaggedNa` or
  `missingCode(values[i])` still works on V8 only; the doc comments and
  docs/typescript.md say so.
- CI runs the npm package's tests on Bun as well as Node, so a path that
  reads a code through a number fails there.
- `js/tsconfig.json` has no `paths`: `src/node.ts` imports `./index`,
  which the build keeps external as it keeps `./format-entry`, because
  Bun follows `paths` to `src/`, whose `.wasm` import it cannot load.
