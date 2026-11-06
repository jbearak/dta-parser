# Parquet judging, round 2

Round 2 of the protocol in [parquet-rubric.md](../parquet-rubric.md)
(Gate 2 of plan 0018). **It fails, and judging stops here for the
user's decision.** Claude Sonnet scored our Python install
documentation (task 1) below pyarrow's: 2.50 against 2.75. Our packages
are not published, so under the rubric's install rule, rule 1 fails
for Python and plan 0018 asks the user how to proceed.

The user chose to keep the packages unpublished and change our docs;
[round 3](../parquet-round-3/README.md) judged them and passes.

Round 2 judged the same docs as [round 1](../parquet-round-1/README.md),
whose blinding was broken. Our bundled files are unchanged from
`eb4c5e0`. Only the prompts changed: blinding now works, and the coin
flips are new.

## Setup

- **Our docs:** commit `2bacd0730bbcfe3baf8a56b2f00c6b926b391cfe`
  (recorded in [pairs.json](pairs.json)). Every file in our bundles is
  as at `eb4c5e0`, which round 1 judged. After plan 0019, the Python and
  Julia API reference is datakit's docstrings (`python/datakit`,
  `julia/Datakit`).
- **Other libraries' documentation:** the same versions, sources and
  commits as round 1. See
  [round 1's table](../parquet-round-1/README.md#the-other-libraries-documentation).
- **Judges:**
  - Claude Sonnet (`claude-sonnet-5-5`, effort high, its default);
  - GPT Terra (`gpt-6.1-terra`, reasoning effort high, through Codex).

  Each of the 16 judge tasks ran in its own fresh session. Each was told
  to read only its prompt file, and not to run code or look anything up.
- **Coin flips:** from Python's `random.Random(2026110602)`.

  | pair | ours is |
  |---|---|
  | R: arrow | B |
  | R: nanoparquet | A |
  | Python: pyarrow | A |
  | Python: pandas | B |
  | Python: polars | B |
  | Julia: Parquet2.jl | B |
  | TypeScript: hyparquet + hyparquet-writer | A |
  | TypeScript: parquet-wasm | A |

The prompts are built with:

    python docs/judging/parquet_bundle.py OTHERS OUT 2026110602

The departures from the protocol's wording are as in round 1, with one
change to blinding. Names are now replaced outside code wherever no
letter or digit adjoins them. That takes in plurals ("datakits"),
compounds (`pyarrow-core`, `nanoparquet-types`) and link anchors, and
each indented code line now ends at its newline. The prompts are not
committed.

## Scores

Totals are over all eleven tasks (at most 33).

| judge | pair | ours | other library | rule 1: tasks behind | rule 3: tasks below 2 | pass |
|---|---|---|---|---|---|---|
| sonnet | R: arrow | 31.25 | 19.25 | none | none | yes |
| sonnet | R: nanoparquet | 31.50 | 19.50 | none | none | yes |
| sonnet | Python: pyarrow | 32.00 | 18.25 | 1 | none | no |
| sonnet | Python: pandas | 32.25 | 11.75 | none | none | yes |
| sonnet | Python: polars | 32.00 | 14.25 | none | none | yes |
| sonnet | Julia: Parquet2 | 31.50 | 19.50 | none | none | yes |
| sonnet | TypeScript: hyparquet | 31.50 | 16.75 | none | none | yes |
| sonnet | TypeScript: parquet-wasm | 31.50 | 17.50 | none | none | yes |
| terra | R: arrow | 31.25 | 19.00 | none | none | yes |
| terra | R: nanoparquet | 31.50 | 16.00 | none | none | yes |
| terra | Python: pyarrow | 29.75 | 17.50 | none | none | yes |
| terra | Python: pandas | 31.50 | 12.25 | none | none | yes |
| terra | Python: polars | 29.50 | 12.25 | none | none | yes |
| terra | Julia: Parquet2 | 28.25 | 14.75 | 2 | none | no |
| terra | TypeScript: hyparquet | 31.75 | 13.50 | none | none | yes |
| terra | TypeScript: parquet-wasm | 28.75 | 15.25 | 2 | none | no |

Task scores, ours / theirs. An asterisk marks a task the other library
cannot do.

| judge | pair | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sonnet | arrow | 2.75 / 2.50 | 2.75 / 2.25 | 2.75 / 2.25 | 2.75 / 1.25 | 2.75 / 1.75 | 3.00 / 1.25 | 2.75 / 1.50 | 3.00 / 2.75 | 3.00 / 2.00 | 3.00 / 0.00* | 2.75 / 1.75 |
| sonnet | nanoparquet | 2.75 / 2.50 | 3.00 / 2.50 | 2.75 / 2.25 | 2.75 / 2.00* | 2.75 / 2.75 | 3.00 / 0.00 | 2.75 / 1.25 | 3.00 / 2.75 | 3.00 / 1.25 | 3.00 / 0.00* | 2.75 / 2.25 |
| sonnet | pyarrow | 2.50 / 2.75 | 3.00 / 2.25 | 3.00 / 2.25 | 3.00 / 2.50 | 3.00 / 2.50 | 3.00 / 0.00 | 2.75 / 1.75 | 3.00 / 2.25 | 3.00 / 0.00 | 2.75 / 0.00* | 3.00 / 2.00 |
| sonnet | pandas | 2.75 / 2.25 | 3.00 / 2.00 | 3.00 / 2.00 | 3.00 / 0.00* | 3.00 / 0.00* | 3.00 / 0.00 | 3.00 / 1.50 | 3.00 / 2.25 | 3.00 / 0.00 | 2.75 / 0.00* | 2.75 / 1.75 |
| sonnet | polars | 2.50 / 2.25 | 3.00 / 2.00 | 3.00 / 1.75 | 3.00 / 1.75 | 3.00 / 1.75 | 2.75 / 0.00 | 3.00 / 0.00 | 3.00 / 2.00 | 3.00 / 1.25 | 3.00 / 0.00* | 2.75 / 1.50 |
| sonnet | Parquet2 | 2.75 / 2.50 | 3.00 / 2.50 | 3.00 / 2.00 | 3.00 / 1.75 | 3.00 / 2.25 | 2.75 / 1.25 | 2.50 / 1.00 | 3.00 / 2.75 | 3.00 / 1.75 | 2.75 / 0.00* | 2.75 / 1.75 |
| sonnet | hyparquet | 2.75 / 1.50 | 2.75 / 2.50 | 3.00 / 1.75 | 3.00 / 2.00 | 3.00 / 2.25 | 2.50 / 0.00 | 3.00 / 1.25 | 3.00 / 2.25 | 2.75 / 1.00 | 2.75 / 0.00* | 3.00 / 2.25 |
| sonnet | parquet-wasm | 2.50 / 2.50 | 2.75 / 2.50 | 3.00 / 1.50 | 3.00 / 1.75 | 3.00 / 2.25 | 2.25 / 0.00 | 3.00 / 1.25 | 3.00 / 2.75 | 3.00 / 1.00 | 3.00 / 0.00* | 3.00 / 2.00 |
| terra | arrow | 3.00 / 2.25 | 3.00 / 2.25 | 2.75 / 2.00 | 2.75 / 1.50 | 2.75 / 1.75 | 2.75 / 1.75 | 2.75 / 1.50 | 3.00 / 2.50 | 2.75 / 1.75 | 3.00 / 0.00* | 2.75 / 1.75 |
| terra | nanoparquet | 3.00 / 2.25 | 3.00 / 2.00 | 3.00 / 2.25 | 2.75 / 1.75* | 2.75 / 2.75 | 3.00 / 0.00 | 2.75 / 1.50 | 3.00 / 2.00 | 2.75 / 0.00 | 3.00 / 0.00* | 2.50 / 1.50 |
| terra | pyarrow | 2.75 / 2.75 | 2.75 / 2.00 | 2.75 / 2.50 | 2.75 / 2.50 | 2.75 / 2.50 | 2.75 / 0.00 | 2.75 / 1.50 | 2.75 / 1.75 | 2.75 / 0.00 | 2.75 / 0.00* | 2.25 / 2.00 |
| terra | pandas | 2.75 / 2.00 | 3.00 / 2.00 | 3.00 / 2.25 | 3.00 / 0.00* | 3.00 / 0.00* | 3.00 / 0.00 | 3.00 / 2.00 | 3.00 / 2.25 | 3.00 / 0.00 | 2.50 / 0.00* | 2.25 / 1.75 |
| terra | polars | 2.75 / 2.00 | 2.75 / 2.00 | 2.75 / 1.50 | 2.75 / 1.50 | 2.75 / 1.50 | 2.75 / 0.00 | 2.75 / 0.00 | 2.75 / 2.00 | 2.75 / 0.00 | 2.75 / 0.00* | 2.00 / 1.75 |
| terra | Parquet2 | 2.75 / 2.25 | 2.00 / 2.50 | 2.75 / 2.00 | 2.75 / 1.75 | 2.75 / 2.00 | 2.75 / 0.00 | 2.25 / 0.00 | 2.75 / 2.50 | 2.75 / 0.00 | 2.75 / 0.00* | 2.00 / 1.75 |
| terra | hyparquet | 3.00 / 0.00 | 2.50 / 2.00 | 3.00 / 1.75 | 3.00 / 2.00 | 3.00 / 2.50 | 2.75 / 0.00 | 3.00 / 1.50 | 3.00 / 2.00 | 3.00 / 0.00 | 3.00 / 0.00* | 2.50 / 1.75 |
| terra | parquet-wasm | 2.50 / 2.50 | 2.00 / 2.50 | 2.75 / 1.00 | 2.75 / 1.50 | 2.75 / 2.00 | 2.25 / 0.00 | 2.75 / 1.75 | 2.75 / 2.25 | 2.75 / 0.00 | 2.75 / 0.00* | 2.75 / 1.75 |

Our totals beat every other library's under both judges, by at least
12 points. No task of ours scores below 2. The round fails only on
rule 1, in three places:

- **Python, task 1 (install), against pyarrow, Sonnet:** ours 2.50,
  pyarrow 2.75. Terra tied them at 2.75. Sonnet gave correctness 2 for
  two points:
  - "Wheels are built for macOS, Linux and Windows" sits beside "not on
    PyPI; install from a checkout" (`docs/python.md`, Install).
  - The `--force-reinstall ./python ./python/datakit` fix uses
    different paths from the install command (`./dta-parser/python`).

  Sonnet gave clarity 2 because the two packages were hard to tell
  apart. Part of that is the blinding: both of our package names,
  datakit and dta_parser, become the same letter. So "Library A needs
  polars 2" and "install both packages" read as one name.
- **Julia, task 2 (read a file), against Parquet2.jl, Terra:** ours
  2.00, Parquet2.jl 2.50. Correctness 1: the type table says every
  conversion is exact or an error (`docs/julia.md`), but it also says
  DECIMAL becomes the nearest `Float64` by default. Sonnet gave ours
  3.00.
- **TypeScript, task 2, against parquet-wasm, Terra:** ours 2.00,
  parquet-wasm 2.50. Correctness 1, for the same sentence in
  `docs/typescript.md`. Terra raised it in round 1 too.

## Disagreements

On one task the two judges' scores for ours differ by a whole point:
Julia task 2 (Sonnet 3.00, Terra 2.00), the DECIMAL sentence above.
For the other libraries, they differ that much on:

- **Task 9**, wherever labels could be kept only in key-value
  metadata, by a user's own convention: nanoparquet, polars,
  Parquet2.jl, hyparquet and parquet-wasm. Terra gave 0, as in round 1.
- **Parquet2.jl, tasks 6 and 7.**
- **hyparquet, task 1:** Sonnet 1.50, Terra 0.00. Terra found no
  install command.

## Findings not yet acted on

The rubric's install rule stops judging here. So these are recorded
for a third round, if the user wants one:

- **Python install** (`docs/python.md`). Make clear that the wheels are
  built in CI and not published, and that a user builds from the
  checkout. Use the same paths in the install command and in the
  `--force-reinstall` fix. Say which package needs what.
- **"Exact or an error"** (`docs/julia.md`, `docs/typescript.md`,
  `docs/python.md`). Name the DECIMAL exception, or drop the blanket
  sentence.
- **"Every encoding"** (`docs/r.md`, `docs/python.md`, `docs/julia.md`;
  every judge in R, Python and Julia). Name BIT_PACKED as the
  exception, as the error table does.
- **TypeScript and Julia task 6.** Show how to turn a labelled numeric
  column into a categorical.
- **R task 5.** Say that `read_parquet_info()` does not list the
  footer's raw key-value entries.
- **Rows past the end.** Say what a window past the end gives.
- **Findability.** Against pyarrow, polars, Parquet2.jl and
  parquet-wasm, Terra gave our docs findability 2 on every task:
  from the README, a reader goes to `docs/parquet.md` or the language
  page, then to the task section. Against pandas and hyparquet, it gave
  the same docs 3.
  Linking each language's install section and Parquet task list from
  the README would put them one step from the front page.

The [round 1 README](../parquet-round-1/README.md#not-yet-acted-on)
lists the fresh agents' smaller gaps.

## Fresh-agent check

Not run again: our docs are unchanged since round 1. See
[round 1's fresh-agent check](../parquet-round-1/README.md#fresh-agent-check).
