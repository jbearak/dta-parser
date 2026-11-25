# The next `@jbearak/dta-parser` is 1.2.0, not 2.0.0

Supersedes ADR 0035's "dta-parser becomes 2.0.0, since 1.1.0 published
the Parquet exports", and the "2.0" in ADR 0037's consequences, ADR 0045,
and plan 0021. Those documents keep their wording as history; where they
say dta-parser 2.0, read 1.2.

On 2026-11-24 the user decided that the release `main` holds is 1.2.0.
It had been numbered 2.0.0 since plan 0021 because it removes things
1.1.0 published. The user was told what a minor number means for a range
such as `^1.0.0` and chose 1.2 all the same.

**`js/package.json` says 1.2.0**, and the docs that named 2.0 name 1.2:
`docs/typescript.md`, `docs/migration.md` (now "dta-parser 1.1 to 1.2"),
and `js/README.md`. The code is unchanged.

What 1.2 removes or changes from 1.1, in full in
[docs/migration.md](../migration.md#dta-parser-11-to-12):

- the Parquet functions and types (`openParquet`, `writeParquet`, and
  the rest), which 1.1.0 added;
- `NumberColumn.missing` and `WriteVariable.missing` beside a
  Float64Array (ADR 0037);
- `formatValue`'s digits for `%w.0g` (ADR 0045).

## Consequences

- A project whose range is `^1.0.0` or `^1.1.0` takes 1.2.0 the next
  time its lockfile is updated, with no edit to its `package.json`. Code
  that calls a Parquet function or reads `column.missing` then fails. The
  docs say so at the top of the migration notes, and say to pin `~1.1.0`
  to stay.
- manuscript-markdown, at `^1.0.0` with 1.0.0 locked, calls `openDta`,
  `readRows`, `formatValue`, and `isMissing`, and its tests call
  `writeDta` with plain arrays and `MISSING`. 1.2 changes none of those
  except `formatValue`'s digits, which is the change it wants.
- ADR 0037 records that table-viewer and Sight read `missing`. They need
  `missingCode(values[i])` when they take 1.2, as they would have for 2.0.
- 2.0.0 stays unused.
