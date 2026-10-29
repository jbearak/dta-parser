# dta-parser TypeScript docs check

Source used: only `docs.md`. Scripts are in this directory: `t1.cjs`, `t1.mjs`, `t2.mjs`, `t5.mjs`, `t8.mjs`. `t2.mjs` covers tasks 2-4, `t5.mjs` covers 5-7, `t8.mjs` covers 8-10. All `.dta` files were written by the library itself. Node v26.12.1.

## Setup note (affects task 1)

I followed the Install section against the checkout at `/Users/jmb/repos/dta-parser.new/.claude/worktrees/agent-a2eb7dc5013b84836`.

- `rustup target add wasm32-unknown-unknown` failed inside the sandbox ("error opening file for download: cleaning up cached downloads: No such file or directory"). The default `stable` toolchain has no wasm target, so `scripts/build-wasm.sh` failed with `can't find crate for std`.
- I did not retry outside the sandbox. That would have installed a component into `~/.rustup`, outside the scratch directory.
- Toolchain `1.98.0` already had the wasm target. I ran `CARGO=~/.rustup/toolchains/1.98.0-.../bin/cargo scripts/build-wasm.sh`. It failed at link time: that toolchain's `rust-lld` could not load `@rpath/libLLVM.dylib` (file missing). This is an environment problem, not a docs problem.
- The checkout already contained `js/build/dta.wasm` (dated 20:25, before I started). `npm ci && npm run build` in `js/` succeeded and embedded it into `dist/`. Everything below ran against that prebuilt wasm, **not a wasm I built**.
- `npm install <path>/js` in scratch then worked.

## Task 1: Install and load. **Succeeded** (with the caveat above)

```js
const m = require("@jbearak/dta-parser"); const n = require("@jbearak/dta-parser/node");
// ESM: import { MISSING } from "@jbearak/dta-parser"; import { openDtaFile } from "@jbearak/dta-parser/node";
```

Saw:

- Root exports: `DtaReader, MISSING, formatValue, isMissing, missingValue, openDta, stataKey, stataKeys, writeDta, writeDtaTo`.
- Node exports: `openDtaFile, writeDtaFile`.
- Both `require` and `import` work, as the docs say.

Doc problems:

- The Install section never says which Rust toolchain must carry the wasm target. It does not say what to do when the default toolchain lacks it. `scripts/build-wasm.sh` mentions the `CARGO=` override in a comment, but the docs page does not.
- Nothing says the wasm build is the step that fails when no target is present. `npm ci && npm run build` in `js/` still "succeeds" when a stale `js/build/dta.wasm` exists, so a failed wasm step goes unnoticed.

## Task 2: Write a table, read it back. **Succeeded** (there is no "usual table type")

```js
writeDtaFile("t2.dta", { variables: [
  { name: "n", type: "int", values: [1,2,3,4,5,6] },
  { name: "x", type: "double", values: [1.5,2.25,3.125,4,5,6.5] },
  { name: "s", values: ["a","bb","ccc","","e","f"] },
  { name: "d", type: "long", format: "%td", values: [...days] }]});
const r = openDtaFile("t2.dta");
const cols = r.readColumns(r.variables.map((_, i) => i));
```

Saw (column, storage type in the file, what it became):

| column | storage type | became |
|---|---|---|
| `n` | int `%8.0g` | `{kind:"number", values: Float64Array, missing: Uint8Array}` |
| `x` | double `%10.0g` | `NumberColumn` |
| `s` | str3 `%-3s` | `{kind:"string", values: string[]}` |
| `d` | long `%td` | `NumberColumn` of `Float64Array` [23436, ...]: days since 1960, not a date |

`readColumns` returns an array in request order, with no names attached.

Doc problems:

- The task assumed a "usual table type". TypeScript has none. The docs say so only implicitly: the README says "typed arrays per column, or rows", and `representations.md` says "a `DtaReader`; columns on request". Nothing says plainly "there is no DataFrame/table object".
- No recipe builds a name-to-column object. The "Rows as objects" recipe covers rows only.

## Task 3: Two columns in reverse order. **Succeeded**

```js
r.readColumns(["s", "n"])      // file order is n, x, s, d
r.readColumns(["d", 1])        // names and indexes can be mixed
r.readColumns(["nope"])
```

Saw:

- Columns come back in the order requested (`s` then `n`).
- A missing name throws `RangeError: no variable "nope"`.
- A bad index (9, -1, 1.5) throws `RangeError: no variable 9` (and the same for -1 and 1.5). `readRows` behaves the same.

Doc problems:

- None. Troubleshooting says "`RangeError: no variable "incme"`", which matches.
- Out-of-range numeric indexes are covered only by "A name or index that is not in the file throws a `RangeError`", with no message example.

## Task 4: Rows 3 to 5 and rows past the end. **Succeeded**

```js
r.readColumns(["n","s"], { start: 2, count: 3 })   // n = [3,4,5], s = ['ccc','','e']
r.readRows(2, 3)
```

Saw:

- The file has 6 rows, so the window start is 2.
- Past the end: `readColumns`/`readRows` with (4,5), (6,1), (0,10) and (7,1) all throw `RangeError: rows 4 to 9 are outside 0 to 6` (and the matching message for each).
- `start:6, count:0` returns an empty result. `start:-1` throws.
- `{ start: 4 }` alone gives the last 2 rows.
- `{ count: 2 }` alone gives the first 2.

Doc problems:

- Docs say "`start` defaults to 0 and `count` to the rest of the file" for `readColumns`. The `readRows` signature is `readRows(start, count, columns?)` with both required. `r.readRows(2)` (count omitted) silently returns `[]` rather than the rest of the file or an error. A reader would expect the same defaulting as `readColumns`.
- Docs say "throws a `RangeError`" but do not say that a window straddling the end (start inside, count too large) also throws; it does. The Troubleshooting message example `rows 0 to 10 are outside 0 to 6` matches exactly.

## Task 5: Labels, formats and storage types without reading data. **Succeeded**

```js
const r = openDtaFile("t5.dta");   // no readColumns/readRows called
r.info.label; r.variables; r.notes();
```

Saw:

- `info.label` is "My data label".
- Each `variables[i]` has `{name, type, format, label, valueLabels}`: `n int %8.0g`, `x float %9.2f`, `s str3 %-3s`, `sex byte %8.0g (set "sex")`, `d long %td`.
- `r.notes()` returned `['note one']`.

Doc problems: none. "All of it is available right after opening; no rows are read" is accurate.

## Task 6: Value labels, lookup, categorical. **Partly**

```js
const set = r.valueLabels(r.variables.find(v => v.name==="sex").valueLabels);
set.get(2)                  // "Male"
set.get(MISSING[".d"])      // "Don't know"
set.get(9)                  // undefined
r.valueLabels("nope")       // undefined
```

Saw:

- Lookup works.
- No categorical/factor type exists in TypeScript. I hand-built `{levels:['Female','Male'], codes:[0,1,1,-1,0]}`.
- `formatValue(cell, fmt, set)` and `readRows(...).map(([c]) => set.get(c) ?? c)` both gave `['Female','Male','Male',"Don't know",'Female']`.

Doc problems:

- The task asked for the language's categorical type. The docs say only: "Each language page has a recipe: ... TypeScript `formatValue(cell, format, labels)`" (`value-labels.md`). The TypeScript page has no recipe that produces a categorical or labelled column; the closest is the `readRows(...).map(... labels.get(v))` snippet.
- `formatValue` takes a `Cell`, but `readColumns` gives `values` plus `missing` codes. Combining them (needs `missingValue(code)`) is not shown for labelling.
- To get the letter from a code I had to use `Object.keys(MISSING)[code-1]` or `missingValue(code).missing`. The docs show `{ missing: '.d' }` printed but never state that the property is called `missing`.

## Task 7: Date as a date, then without conversion. **Partly**

```js
const EPOCH = Date.UTC(1960,0,1);
new Date(EPOCH + days*86400000).toISOString()   // '2024-03-01T00:00:00.000Z'
formatValue(23436, "%td")                        // '01mar2024'
openDtaFile("t5.dta", { dates:false })           // same numbers as without
```

Saw:

- Reading never converts; the column is always `Float64Array` days.
- `new Date(...)` and `formatValue` both worked.
- `{dates:false}` and `{dates:true}` are both silently accepted and ignored.

Doc problems:

- The task assumes a switch. The docs do say "TypeScript keeps the numbers" (`dates.md`), but nothing says there is no `dates` option. `Options` lists only `encoding`. An unknown option silently does nothing, which is risky for people coming from the Python/Julia `dates=False` docs.
- The API-reference section lists `const EPOCH = Date.UTC(1960, 0, 1);`, but `EPOCH` is not exported (root exports listed above). A reader would think `import { EPOCH }` works. The same section lists other internals (`general`, `BLOCK`, `When`, `packTexts`, `sinks`, `read`, `part`, `put`, `write`, `WritePart`, `generation`, `resultText`) that are not public.

## Task 8: Write, release and storage types, error. **Succeeded**

```js
writeDtaFile("t8.dta", { variables: [
  {name:"a", values:[1,2,3]}, {name:"b", values:[1.5,2,3]},
  {name:"c", type:"byte", values:[1,2,3]}, {name:"t", values:["x","yy","zzz"]},
  {name:"big", values:["q".repeat(3000),"r","s"]}]});
```

Saw:

- `info.release` is 118.
- Storage types: `a` double, `b` double, `c` byte, `t` str3, `big` strL.
- Integer-valued numbers with no `type` are double, as the docs say.
- Errors (messages are readable and name the variable):
  - `type:"byte"` with 300: `Error: v row 2: 300 does not fit storage type byte`.
  - `type:"int"` with 1.5: `v row 1: 1.5 does not fit storage type int`.
  - 101 in a byte (reserved missing range): `v row 1: 101 does not fit storage type byte`.
  - Mixed values: `TypeError: v mixes strings and numbers`.
  - Strings with a numeric `type`: `TypeError: v is byte but holds strings`.
  - Bad name: `"1v" is not a valid Stata name`.
  - Unequal lengths: `RangeError: b has 1 values, not 2`.
- A failed `writeDtaFile` leaves no partial file (`existsSync` was false), as the docs say.
- A variable naming a nonexistent value-label set did not error, as the docs say ("is written with that name").
- A double written as float reads back `0.10000000149011612`, matching the docs.

Doc problems:

- The docs' error messages ("... mixes strings and numbers", "holds strings") are written loosely. The real second message is "is byte but holds strings". Not wrong.
- The release written can be seen only by reading the file back (`info.release`). That is what the docs imply, but they never say there is a write-side return value (there is none).

## Task 9: Variable label, value label set, data label, checked by reading back. **Succeeded**

```js
const bytes = writeDta({ label: "DL é", valueLabels: { yn: new Map([[0,"No"],[1,"Yes"],[MISSING[".r"],"Refused"]]) },
  variables: [{ name:"q", type:"byte", label:"Question ü", valueLabels:"yn", values:[1,0,MISSING[".r"]] }] });
const b = openDta(bytes);
```

Saw:

- `b.info.label` is "DL é".
- `variables[0]` has `label: 'Question ü'` and `valueLabels: 'yn'`.
- `valueLabels("yn")` is `Map(3){0=>'No',1=>'Yes',{missing:'.r'}=>'Refused'}`.
- Non-ASCII text survived.

Doc problems: none. The "Write a file" example output matches.

## Task 10: `.`, `.a`, `.z`; tell apart, filter, sort, write back. **Succeeded**

```js
vals = [10, MISSING["."], 5, MISSING[".a"], 7, MISSING[".z"], null, 2];
// x read as NumberColumn: values NaN where missing, missing = [0,1,0,2,0,27,1,0]
// per value: x.missing[i]  (or  cell === MISSING[".a"]  from readRows)
const keys = stataKeys(x);
// Stata-style filter x > 6 : indexes where keys[i] > 6  -> [0,1,3,4,5,6]  (10, ., .a, 7, .z, .)
// non-missing only        : [0,4]
// sort: order = indexes sorted by keys -> 2,5,7,10,.,.,.a,.z
```

Written back, the sorted data read as missing codes `[null,null,null,null,'.','.','.a','.z']`, so `.a` and `.z` survived. A filtered subset also survived (`[10], ['.'], ['.a'], [7], ['.z'], ['.']`).

- `null` and `MISSING["."]` both read back as `.`, which the docs say.

Doc problems:

- TypeScript has no filter/sort helpers; the docs give a sort snippet with `stataKey` only. Filtering and writing back needs the `missingValue(code)` conversion by hand (the "Copy a file" recipe shows it). The README feature table calls this "✓ codes", which is accurate but thin.
- In the sort snippet the docs cast `a as number`; `stataKey` accepts `number | Missing`, so the cast is needed only because `Cell` also includes strings and bytes.

## Summary

1. Succeeded. Setup needed a workaround for the Rust toolchain; I ran against a prebuilt wasm.
2. Succeeded. No table type exists; the docs do not say so plainly.
3. Succeeded.
4. Succeeded. `readRows(start)` without `count` silently returns `[]`.
5. Succeeded.
6. Partly. No categorical type and no recipe for one.
7. Partly. No date option; `{dates:false}` is silently ignored. `EPOCH` listed in the API reference but not exported.
8. Succeeded.
9. Succeeded.
10. Succeeded. Filter and sort are hand-built from `stataKeys`.
