# Comprehensive README Design

## Goal

Rewrite `README.md` as practical package documentation for developers who
consume `@jbearak/dta-parser`.

The README should explain what the package is for, how to choose the correct
entrypoint, and how to use the public APIs without drifting into marketing
copy. The package exists because the `.dta` parsing code was first written for
[Sight](https://github.com/jbearak/sight), then extracted so it can also be
reused by other codebases such as
[manuscript-markdown](https://github.com/jbearak/manuscript-markdown).

The purpose note should briefly describe both known consumers:

- Sight uses `.dta` parsing for its editor data browser, where users can open
  Stata datasets in VS Code-like editors and inspect rows, columns, formats,
  and value labels.
- `manuscript-markdown` uses `.dta` parsing for embedded table workflows, where
  manuscript or documentation sources can include tables backed by external
  `.dta` files.

## Audience

Developers writing code that reads Stata `.dta` files.

The README does not need to sell the package, explain Stata to non-programmers,
or document maintainer-only release processes in detail.

## Tone

- Direct, code-facing, and specific.
- No marketing language.
- Prefer examples and factual behavior over broad claims.
- Name limitations plainly.

## README Structure

1. Title and short purpose statement
   - State that this is a TypeScript parser for Stata `.dta` files.
   - Mention extraction from [Sight](https://github.com/jbearak/sight) for
     reuse in Sight and
     [manuscript-markdown](https://github.com/jbearak/manuscript-markdown).
   - Briefly state that Sight uses it for editor data browsing, while
     `manuscript-markdown` uses it to read `.dta` files as embedded table
     sources.

2. Installation
   - Show npm, bun, and pnpm install commands.
   - Mention Node >=20 for the Node entrypoint.

3. Entrypoints
   - Explain `@jbearak/dta-parser` as the portable/core API.
   - Explain `@jbearak/dta-parser/node` as the Node filesystem-backed API.
   - State that `/node` is a normal npm package subpath export, not a local
     checkout, vendored copy, or filesystem path.
   - Include import examples for both entrypoints.

4. Node quickstart
   - Show `DtaFile.open()`, metadata access, row reads, column reads, value
     labels, display formatting, and `close()` in a concise example.
   - Use `try/finally` around file closing.

5. Portable buffer quickstart
   - Show `parse_metadata()` and `read_rows_from_buffer()` from the root
     entrypoint.
   - Make clear this path is for callers that already have bytes.

6. Data model
   - Briefly document `DtaMetadata`, `VariableInfo`, `Row`, `RowCell`, and
     `MissingValue`.
   - Explain that Stata missing values are preserved as tagged objects instead
     of collapsed to `null` or `NaN`.

7. Common tasks
   - Read a page of rows.
   - Read selected columns with `read_columns()`.
   - Apply display formats.
   - Resolve value labels.
   - Detect or render missing values.
   - Use cancellation with `AbortSignal` where supported.

8. Supported files
   - Supported `.dta` format versions: 113, 114, 115, 117, 118, and 119.
   - Unsupported older formats should fail fast.
   - Note that modern `strL` values are resolved by `DtaFile`.

9. API reference
   - Use compact tables grouped by entrypoint.
   - Include notable root exports and Node exports without turning the README
     into generated API docs.

10. Development
   - Keep only developer commands useful for this repo:
     install, build, typecheck, and test.

## Verification

After editing:

- Inspect `README.md` for accidental marketing language.
- Confirm the `/node` section does not imply a local path.
- Run `npm run typecheck`.
- Run `git diff --check`.
