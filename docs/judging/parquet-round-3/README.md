# Parquet judging, round 3

Round 3 of the protocol in [parquet-rubric.md](../parquet-rubric.md)
(Gate 2 of plan 0018). **It passes.** For both judges, in every
language, against every other library:

- our task score is at least theirs on every task they support;
- our total is higher than theirs, by at least 11 points;
- each of our eleven task scores is at least 2 (the lowest is 2.25).

The user decided to keep the packages unpublished, change our docs,
and judge again. Round 2 had failed on rule 1: Python's install section
was behind pyarrow's, and Julia's and TypeScript's task 2 were behind
Parquet2.jl and parquet-wasm. Round 3 judged the changed docs with new
coin flips.

## Setup

- **Our docs:** commit `1e54804f5767ce2fbcf5a5351433c5c561b379f0`
  (in [pairs.json](pairs.json)). The Python and Julia API reference is
  datakit's docstrings (`python/datakit`, `julia/Datakit`).
- **Other libraries' documentation:** unchanged since
  [round 1](../parquet-round-1/README.md#the-other-libraries-documentation),
  and blinded as in [round 2](../parquet-round-2/README.md).
- **Judges:**
  - Claude Sonnet (`claude-sonnet-5-5`, effort high, its default);
  - GPT Terra (`gpt-6.1-terra`, reasoning effort high, through Codex).

  Each of the 16 judge tasks ran in its own fresh session.
- **Coin flips:** from Python's `random.Random(2026110603)`.

  | pair | ours is |
  |---|---|
  | R: arrow | B |
  | R: nanoparquet | B |
  | Python: pyarrow | A |
  | Python: pandas | B |
  | Python: polars | B |
  | Julia: Parquet2.jl | A |
  | TypeScript: hyparquet + hyparquet-writer | A |
  | TypeScript: parquet-wasm | A |

The prompts are built with:

    python docs/judging/parquet_bundle.py OTHERS OUT 2026110603

## What changed in our docs since round 2

These are commit `1e54804`, made in response to round 2:

- **Install:**
  - Python's install is written for an install from a checkout: one
    `pip install` for `dta_parser` and datakit, with no wheel talk.
  - The same paths are used in the install command and in every
    reinstall command (`docs/python.md` and `docs/parquet.md`'s error
    table).
  - The C compiler that builds zstd is named, with what to do when the
    build fails.
  - Julia's and R's install sections name the compiler too.
  - Julia's says the first build takes minutes, with no output.
  - TypeScript's names its Node and TypeScript versions, what a
    browser needs, and the clang and llvm the build needs, and its
    Troubleshooting covers a non-rustup `cargo`.
  - Each language's "Parquet: install" gives the commands itself.
  - The README links each language's Install section, and each
    language's Parquet section.
- **DECIMAL:** every "exact or an error" statement names the exception:
  - R, Julia and TypeScript read DECIMAL as the nearest double, with
    the option that keeps every digit;
  - Python reads it as polars' `Decimal`.
- **BIT_PACKED:** values in this encoding are named as the one encoding
  not read, wherever the docs said "every encoding".
- **Categoricals:** TypeScript has a recipe that turns a labelled
  column into a `DictionaryColumn`, which is written as a categorical.
  Julia already had one.
- **R metadata:** `read_parquet_info()` returns `key_value`, every
  key-value entry of the footer. This is a small code change in
  dtaparser's bridge and datakit, with tests. The R page also documents
  positional `col_select`, and rows past the end.
- **Smaller fixes:**
  - the malformed TypeScript error table in `docs/parquet.md`;
  - Python's compression errors in that table;
  - Python's `key_value` described as a `dict`;
  - the Julia timestamp row of the type table;
  - an R help example whose comments did not match its output
    (`with_labels`);
  - `save_parquet`'s Python docstring, which put `.a` to `.z` in the
    profile.

## Scores

Totals are over all eleven tasks (at most 33).

| judge | pair | ours | other library | rule 1: tasks behind | rule 3: tasks below 2 | pass |
|---|---|---|---|---|---|---|
| sonnet | R: arrow | 32.00 | 19.75 | none | none | yes |
| sonnet | R: nanoparquet | 32.75 | 18.25 | none | none | yes |
| sonnet | Python: pyarrow | 32.50 | 19.75 | none | none | yes |
| sonnet | Python: pandas | 32.00 | 13.00 | none | none | yes |
| sonnet | Python: polars | 32.25 | 15.50 | none | none | yes |
| sonnet | Julia: Parquet2 | 32.25 | 19.50 | none | none | yes |
| sonnet | TypeScript: hyparquet | 32.50 | 15.75 | none | none | yes |
| sonnet | TypeScript: parquet-wasm | 32.00 | 16.25 | none | none | yes |
| terra | R: arrow | 30.25 | 19.00 | none | none | yes |
| terra | R: nanoparquet | 32.50 | 17.25 | none | none | yes |
| terra | Python: pyarrow | 32.50 | 17.25 | none | none | yes |
| terra | Python: pandas | 32.00 | 11.75 | none | none | yes |
| terra | Python: polars | 30.00 | 12.00 | none | none | yes |
| terra | Julia: Parquet2 | 32.50 | 17.25 | none | none | yes |
| terra | TypeScript: hyparquet | 33.00 | 15.00 | none | none | yes |
| terra | TypeScript: parquet-wasm | 33.00 | 15.25 | none | none | yes |

Task scores, ours / theirs. An asterisk marks a task the other library
cannot do.

| judge | pair | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sonnet | arrow | 2.75 / 2.75 | 2.75 / 2.00 | 3.00 / 2.50 | 3.00 / 1.75 | 3.00 / 1.75 | 2.75 / 1.25 | 2.75 / 1.75 | 3.00 / 2.50 | 3.00 / 2.25 | 3.00 / 0.00* | 3.00 / 1.25 |
| sonnet | nanoparquet | 3.00 / 2.50 | 3.00 / 2.25 | 3.00 / 2.25 | 3.00 / 1.75* | 3.00 / 2.50 | 3.00 / 0.00 | 2.75 / 1.00 | 3.00 / 2.75 | 3.00 / 1.25 | 3.00 / 0.00* | 3.00 / 2.00 |
| sonnet | pyarrow | 3.00 / 3.00 | 3.00 / 2.50 | 3.00 / 2.25 | 3.00 / 2.00 | 3.00 / 2.50 | 3.00 / 1.50 | 2.75 / 1.75 | 3.00 / 2.25 | 3.00 / 0.00 | 2.75 / 0.00* | 3.00 / 2.00 |
| sonnet | pandas | 3.00 / 2.50 | 3.00 / 1.75 | 3.00 / 2.00 | 3.00 / 1.50* | 3.00 / 0.00* | 3.00 / 0.00 | 2.50 / 1.25 | 3.00 / 2.25 | 2.75 / 0.00 | 2.75 / 0.00* | 3.00 / 1.75 |
| sonnet | polars | 3.00 / 2.25 | 3.00 / 2.25 | 3.00 / 1.75 | 3.00 / 1.75 | 3.00 / 1.75 | 2.75 / 0.00 | 3.00 / 0.00 | 3.00 / 2.75 | 2.75 / 1.25 | 2.75 / 0.00* | 3.00 / 1.75 |
| sonnet | Parquet2 | 2.75 / 2.50 | 3.00 / 2.25 | 3.00 / 2.00 | 3.00 / 2.00 | 3.00 / 2.25 | 2.75 / 1.00 | 2.75 / 1.25 | 3.00 / 2.75 | 3.00 / 1.50 | 3.00 / 0.00* | 3.00 / 2.00 |
| sonnet | hyparquet | 3.00 / 1.00 | 2.75 / 2.00 | 3.00 / 2.00 | 3.00 / 2.25 | 3.00 / 2.25 | 2.75 / 0.00 | 3.00 / 1.00 | 3.00 / 2.25 | 3.00 / 1.00 | 3.00 / 0.00* | 3.00 / 2.00 |
| sonnet | parquet-wasm | 2.75 / 2.75 | 2.75 / 2.25 | 3.00 / 1.00 | 3.00 / 1.50 | 3.00 / 1.75 | 3.00 / 0.00 | 3.00 / 1.25 | 2.75 / 2.75 | 3.00 / 1.00 | 2.75 / 0.00* | 3.00 / 2.00 |
| terra | arrow | 3.00 / 2.25 | 2.75 / 2.25 | 2.75 / 2.25 | 2.75 / 1.50 | 2.75 / 1.50 | 2.75 / 1.75 | 2.50 / 1.50 | 2.75 / 2.50 | 2.75 / 1.75 | 2.75 / 0.00* | 2.75 / 1.75 |
| terra | nanoparquet | 3.00 / 2.25 | 2.75 / 1.50 | 3.00 / 1.75 | 3.00 / 1.25* | 3.00 / 2.75 | 3.00 / 1.25 | 2.75 / 1.50 | 3.00 / 2.25 | 3.00 / 1.25 | 3.00 / 0.00* | 3.00 / 1.50 |
| terra | pyarrow | 3.00 / 3.00 | 3.00 / 2.00 | 3.00 / 2.50 | 3.00 / 2.50 | 3.00 / 2.25 | 3.00 / 0.00 | 3.00 / 1.25 | 3.00 / 1.75 | 3.00 / 0.00 | 3.00 / 0.00* | 2.50 / 2.00 |
| terra | pandas | 3.00 / 1.75 | 2.50 / 2.00 | 3.00 / 2.00 | 3.00 / 0.00* | 3.00 / 0.00* | 3.00 / 0.00 | 3.00 / 2.00 | 3.00 / 2.00 | 3.00 / 0.00 | 3.00 / 0.00* | 2.50 / 2.00 |
| terra | polars | 3.00 / 2.00 | 2.75 / 2.00 | 2.75 / 1.50 | 2.75 / 1.50 | 2.75 / 1.50 | 2.75 / 0.00 | 2.75 / 0.00 | 2.75 / 2.00 | 2.75 / 0.00 | 2.25 / 0.00* | 2.75 / 1.50 |
| terra | Parquet2 | 3.00 / 2.25 | 3.00 / 2.00 | 3.00 / 2.00 | 3.00 / 2.00 | 3.00 / 2.00 | 2.75 / 0.00 | 2.75 / 1.50 | 3.00 / 2.25 | 3.00 / 1.50 | 3.00 / 0.00* | 3.00 / 1.75 |
| terra | hyparquet | 3.00 / 0.00 | 3.00 / 1.75 | 3.00 / 1.75 | 3.00 / 2.00 | 3.00 / 2.25 | 3.00 / 0.00 | 3.00 / 1.50 | 3.00 / 2.25 | 3.00 / 1.50 | 3.00 / 0.00* | 3.00 / 2.00 |
| terra | parquet-wasm | 3.00 / 2.25 | 3.00 / 2.50 | 3.00 / 1.00 | 3.00 / 1.50 | 3.00 / 2.25 | 3.00 / 0.00 | 3.00 / 1.50 | 3.00 / 2.25 | 3.00 / 0.25 | 3.00 / 0.00* | 3.00 / 1.75 |

## Disagreements

No task score of ours differs between the judges by a whole point. For
the other libraries, they differ that much on:

- **nanoparquet, task 6:** Sonnet 0.00, Terra 1.25.
- **pyarrow, task 6:** Sonnet 1.50, Terra 0.00.
- **pandas, task 4:** Sonnet 1.50, Terra 0.00.
- **polars, task 9:** Sonnet 1.25, Terra 0.00.
- **Parquet2.jl, task 6:** Sonnet 1.00, Terra 0.00.
- **hyparquet, task 1:** Sonnet 1.00, Terra 0.00.

Each time, one judge gave some credit for generic metadata, factors or
an install hint, and the other found the task not covered.

## Findings acted on after the round

The round passed, so no fourth round was run. These points were still
fixed after commit `1e54804`:

- **DECIMAL summary** in `docs/parquet.md` (Terra, R and Python, task
  2). It now says:
  - R and Julia stop at a value with more than 15 significant digits;
  - Python's `Decimal` holds precision up to 38, and higher precision
    is text.
- **Zones** in `docs/parquet.md` (Sonnet, Python, task 7): "else UTC"
  holds for instants. A clock time has no zone, and R reads it as UTC.
- **README** (Terra, Python, task 10): `.a` to `.z` are in the values,
  not the metadata.
- **TypeScript labels example** (Sonnet, task 6; the fresh agent):
  `formatValue` takes a `Cell`, so the `readRows` cell is cast.
- **TypeScript build** (the fresh agent): when rustup's toolchains are
  not in `~/.cargo`, put the toolchain's `bin` first on `PATH`.
- **"The one encoding not read"** in `docs/parquet.md` (the fresh
  agent) now points to each language's list of what else is not read.
- **R, naive timestamps** (the R fresh agent, task 7). The R page now
  says R writes every `POSIXct` as an instant, and that another tool's
  clock time reads as that clock reading in UTC.

## Fresh-agent check

As in round 1, one fresh agent per language (Claude Sonnet,
`claude-sonnet-5-5`) got only our bundle for its language, a copy of
commit `1e54804` and a scratch directory, and did the eleven tasks. It
wrote every Parquet and `.dta` file it read. The briefs and reports are
in [fresh/](fresh/).

| language | succeeded | partly | failed |
|---|---|---|---|
| R | 1 to 6, 8 to 10 | 7, 11 | none |
| Python | 1 to 11 | none | none |
| Julia | 1 to 11 | none | none |
| TypeScript | 1 to 11 (1 after a build workaround, now in the docs) | none | none |

Round 1's two partial tasks now succeed: R's task 5, through
`read_parquet_info()$key_value`, and TypeScript's task 6, through the
categorical recipe. The partial tasks:

- **R, task 7:** R has no timestamp without a zone. A `POSIXct` whose
  `tzone` is empty is written as an instant, from the session's zone,
  and reads back with no `tzone`. The R page did not say so; it now does
  (see "Findings acted on after the round").
- **R, task 11:** only R's arrow was on the machine, so the agent could
  not read files from the other tools.

Smaller gaps the agents reported, not yet acted on:

- Julia's write errors are `DtaParser.WriteError`, a type the Julia
  page does not name.
- The first `using Datakit` precompiles for about a minute.
- A Julia or Python reader is not told that a plain `.` is a null with
  no letter.
- No example maps "rows 3 to 5" to `skip = 2, n_max = 3`.
