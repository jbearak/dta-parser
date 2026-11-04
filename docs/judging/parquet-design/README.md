# Gate 1: design review of plan 0018

Plan 0018 (`docs/plans/0018-parquet.md`) asked two judges, Claude Sonnet
5.5 (`claude-sonnet-5-5`) and GPT-6.1 Terra (`gpt-6.1-terra`), whether
its API and documentation plan would serve a user better than each
other Parquet library in its language, and revised the plan until both
said yes. Each round was a fresh session given the plan, the earlier
rounds' records and the research notes in `docs/research/parquet-*.md`.

| round | revision reviewed | Sonnet | Terra |
|---|---|---|---|
| [1](round-1.md) | 1 | changes | changes |
| [2](round-2.md) | 2 | changes | changes |
| [3](round-3.md) | 3 | changes | changes |
| [4](round-4.md) | 4 | changes (every library yes) | changes |
| [5](round-5.md) | 5 | changes | approve |
| [6](round-6.md) | 6 | changes (every library yes) | approve |
| [7](round-7.md) | 7 | approve | approve |

Each file lists the findings and what the next revision did about each,
including the ones declined and why.

After approval, the code review of the plan's PR (GPT Sol) found four
errors of fact, corrected without changing the design the judges
approved: the Python and Julia round trips now name the `.dta`-only
keys they leave out (and the profile keeps the file's `timestamp`); a
strL column mixing text and binary reads back as binary; the claim that
zstd's smaller files make up for its compression time on one thread was
wrong and is replaced by the arithmetic and a measurement in PR 3 that
can switch the default to snappy; and plan 0007's default is three
threads, not four.

**Changed by the user after approval (2026-11-04).** The approved design
wrote `.a` to `.z` as nulls with their letters in a `<name>__missing`
string column. The user chose tagged NaNs in DOUBLE columns instead, as
R holds them: our readers decode the bits in every language, and the
letter column's naming, matching and validation go away. The cost,
which the judges' design avoided, is that DuckDB SQL, polars and Spark
see `.a` to `.z` as NaN rather than null. ADR 0033 records the choice.
