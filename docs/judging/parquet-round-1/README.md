# Parquet judging, round 1

Round 1 of the protocol in [parquet-rubric.md](../parquet-rubric.md)
(Gate 2 of plan 0018). **It fails.** In Python, both judges scored our
install documentation (task 1) below pyarrow's. In TypeScript, GPT
Terra scored it below parquet-wasm's. Our packages are not published,
so under the rubric's install rule this would stop judging for the
user's decision.

**The round's blinding was broken**, so it was judged again as
[round 2](../parquet-round-2/README.md), with the same docs and new
coin flips. In the round-1 prompts, everything after the first
indented code line in a bundle was left unblinded. (The code pattern
reused from [bundle.py](../bundle.py) ran an indented line on to the
end of the text.) The judges could read the other library's name in
its own bundle: pyarrow's prose kept "pyarrow" 135 times, nanoparquet's
kept "nanoparquet" 50 times, and hyparquet's kept "hyparquet" 47 times.
Our bundles kept names such as datakit and dta_parser. The scores
below are published as given. [parquet_bundle.py](../parquet_bundle.py)
now has its own pattern, in which an indented line ends at its
newline.

## Setup

- **Our docs:** commit `eb4c5e0b204b67be63e19e47f0c120c4e8961f32`.
  After plan 0019, the Python and Julia API reference in our bundles is
  the docstrings of datakit (`python/datakit`, `julia/Datakit`), not of
  dta_parser or DtaParser.
- **Judges:**
  - Claude Sonnet (`claude-sonnet-5-5`, effort high, its default);
  - GPT Terra (`gpt-6.1-terra`, reasoning effort high, through Codex).

  Each of the 16 judge tasks ran in its own fresh session. Each judge
  was told to read only its prompt file, and not to run code or look
  anything up.
- **Coin flips:** from Python's `random.Random(2026110601)`, one per
  pair, in the order below. They are also in [pairs.json](pairs.json).

  | pair | ours is |
  |---|---|
  | R: arrow | B |
  | R: nanoparquet | A |
  | Python: pyarrow | B |
  | Python: pandas | B |
  | Python: polars | A |
  | Julia: Parquet2.jl | A |
  | TypeScript: hyparquet + hyparquet-writer | B |
  | TypeScript: parquet-wasm | B |

The prompts are built by [parquet_bundle.py](../parquet_bundle.py):

    python docs/judging/parquet_bundle.py OTHERS OUT 2026110601

OTHERS holds the other libraries' sources below. Run it with a Python
that has pyarrow 26.0.1, pandas 3.1.1 and polars 2.1.0 installed, since
their docstrings come from the installed packages. The prompts are not
committed, because most of their text is the other libraries'
documentation. The tables below come from the raw responses in
[responses/](responses/), through [parquet_scores.py](../parquet_scores.py).

## The other libraries' documentation

| library | version | source | commit |
|---|---|---|---|
| arrow (R) | 26.0.0 | apache/arrow, tag `apache-arrow-26.0.0`, `r/` | `446167169a0dc547e00e1bc29f417a40c0ca267a` |
| nanoparquet | 0.5.2 | r-lib/nanoparquet, tag `v0.5.2` | `43b9a8496b9e0278edf7b7928a47b7ea0f2ddb74` |
| pyarrow | 26.0.1 | apache/arrow, tag `apache-arrow-26.0.1`; docstrings from the pyarrow 26.0.1 wheel | `9e5d6978e9acf372cc989aaaf94e863fe8582c90` |
| pandas | 3.1.1 | pandas-dev/pandas, tag `v3.1.1`; docstrings from the pandas 3.1.1 wheel | `3dcc6fbbbebc5e85dd3e83fe49b382ca7735cae1` |
| polars | 2.1.0 | pola-rs/polars, tag `py-2.1.0`; docstrings from the polars 2.1.0 wheel | `7f902bd3ffd27ff82d14278a09a295ff2f7aed92` |
| Parquet2.jl | 0.2.37 | the package as Julia's General registry serves it; the GitLab repository has no release tags | registry tree `aeae7be9cad591ca022544c0b6645f33c3a3e69f` |
| hyparquet | 1.32.0 | npm tarball | `a32933592707c833780f9cdacc2529c3b68a41d0` (`gitHead`, tag `v1.32.0`) |
| hyparquet-writer | 0.18.0 | npm tarball | `7ad8415e5efb2519e9330fdf5f203dc45d103f74` (`gitHead`, tag `v0.18.0`) |
| parquet-wasm | 0.9.0 | npm tarball | `e25579fc548ee6ce411c15bfdabb397cf352e491` (`gitHead`, tag `v0.9.0`) |

## Departures from the protocol's wording

- **Supported tasks.** The judges got a sentence naming the tasks the
  other library supports and the ones it cannot do, not the table.
  The table names the libraries and cites their issue numbers.
- **polars is not blinded** in its pair. It is the table type in both
  bundles, as pandas was in the `.dta` round 1.
- **Blinding** was meant to replace whole words outside code (but see
  the defect above). The R package
  "arrow" is matched in lower case only, so the format "Arrow" stays.
  Our docs name other libraries in prose, for example in "Coming from
  arrow or nanoparquet". In each pair, the name of the library being
  compared is blinded in our bundle too. Names of libraries outside
  the pair stay.
- **pyarrow's Parquet page.** In 26.0.1, `docs/source/python/parquet.rst`
  has become `parquet/`: an index and four pages (single files, type
  handling, datasets and encryption). All five are included.
- **nanoparquet's vignettes.** The bundle includes the two pkgdown
  articles (`list-columns.qmd`, `benchmarks.qmd`) and the talk in
  `vignettes/2025-06-03/`.
- **hyparquet's declarations.** These are the modules `index.d.ts`
  exports (read, query, scan, metadata, indexes, utils and node; write,
  write-rows, parquet-writer, schema and bytewriter), plus each
  package's `src/types.d.ts`. The decoder internals (snappy, thrift,
  encodings) are left out.
- **parquet-wasm's documentation site** is TypeDoc built from
  `pkg/*/parquet_wasm.d.ts` (`typedoc.json` at `v0.9.0`). The bundle
  includes the ESM declaration file once, which holds the same text.
- **Our language pages.** The bundle includes each page's opening and
  contents, plus these sections:
  - Install;
  - the datakit section (Python, Julia);
  - "Plain R types: dtaparser" (R), for the label helpers;
  - Parquet files, with all its subsections;
  - Errors (TypeScript);
  - Troubleshooting;
  - API reference.

## Scores

Totals are over all eleven tasks (at most 33). Rule 1 compares only
the tasks the other library supports. Rule 3 needs each of our task
scores to be at least 2.

| judge | pair | ours | other library | rule 1: tasks behind | rule 3: tasks below 2 | pass |
|---|---|---|---|---|---|---|
| sonnet | R: arrow | 32.00 | 18.75 | none | none | yes |
| sonnet | R: nanoparquet | 28.75 | 17.25 | 5 | none | no |
| sonnet | Python: pyarrow | 30.00 | 18.25 | 1 | none | no |
| sonnet | Python: pandas | 32.50 | 12.00 | none | none | yes |
| sonnet | Python: polars | 32.25 | 14.25 | none | none | yes |
| sonnet | Julia: Parquet2 | 31.75 | 18.00 | none | none | yes |
| sonnet | TypeScript: hyparquet | 32.00 | 17.50 | none | none | yes |
| sonnet | TypeScript: parquet-wasm | 32.50 | 16.75 | none | none | yes |
| terra | R: arrow | 30.75 | 18.75 | none | none | yes |
| terra | R: nanoparquet | 32.00 | 15.50 | none | none | yes |
| terra | Python: pyarrow | 29.25 | 17.25 | 1 | none | no |
| terra | Python: pandas | 29.25 | 12.75 | none | none | yes |
| terra | Python: polars | 30.25 | 13.25 | none | none | yes |
| terra | Julia: Parquet2 | 32.75 | 16.00 | none | none | yes |
| terra | TypeScript: hyparquet | 29.00 | 14.25 | none | none | yes |
| terra | TypeScript: parquet-wasm | 28.50 | 15.75 | 1, 2 | none | no |

Task scores, ours / theirs. An asterisk marks a task the other library
cannot do.

| judge | pair | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sonnet | arrow | 3.00 / 2.75 | 3.00 / 2.50 | 2.75 / 2.25 | 2.75 / 1.25 | 2.75 / 2.00 | 3.00 / 1.25 | 2.75 / 1.25 | 3.00 / 2.50 | 3.00 / 1.75 | 3.00 / 0.00* | 3.00 / 1.25 |
| sonnet | nanoparquet | 2.50 / 2.50 | 2.50 / 2.25 | 2.50 / 2.00 | 2.75 / 1.50* | 2.50 / 2.75 | 2.75 / 0.00 | 2.25 / 0.75 | 2.75 / 2.50 | 2.75 / 1.00 | 2.75 / 0.00* | 2.75 / 2.00 |
| sonnet | pyarrow | 2.75 / 3.00 | 2.75 / 2.50 | 2.75 / 2.25 | 2.75 / 2.00 | 2.75 / 2.50 | 2.75 / 0.00 | 2.75 / 1.75 | 2.75 / 2.25 | 2.50 / 0.00 | 2.50 / 0.00* | 3.00 / 2.00 |
| sonnet | pandas | 2.75 / 2.50 | 3.00 / 2.00 | 3.00 / 2.25 | 3.00 / 0.00* | 3.00 / 0.00* | 3.00 / 0.00 | 3.00 / 1.25 | 3.00 / 2.25 | 3.00 / 0.00 | 2.75 / 0.00* | 3.00 / 1.75 |
| sonnet | polars | 2.75 / 2.25 | 3.00 / 2.00 | 3.00 / 1.75 | 3.00 / 1.75 | 3.00 / 1.75 | 3.00 / 0.00 | 3.00 / 0.00 | 3.00 / 2.25 | 3.00 / 1.25 | 2.75 / 0.00* | 2.75 / 1.25 |
| sonnet | Parquet2 | 2.75 / 2.50 | 3.00 / 2.25 | 3.00 / 2.25 | 3.00 / 2.00 | 3.00 / 2.25 | 2.75 / 0.00 | 2.50 / 1.25 | 3.00 / 2.25 | 3.00 / 1.75 | 2.75 / 0.00* | 3.00 / 1.50 |
| sonnet | hyparquet | 2.75 / 1.25 | 2.75 / 2.50 | 3.00 / 2.00 | 3.00 / 2.25 | 3.00 / 2.25 | 2.50 / 0.00 | 3.00 / 1.25 | 3.00 / 2.25 | 3.00 / 1.25 | 3.00 / 0.00* | 3.00 / 2.50 |
| sonnet | parquet-wasm | 2.75 / 2.75 | 3.00 / 2.25 | 3.00 / 1.00 | 3.00 / 1.75 | 3.00 / 2.25 | 3.00 / 0.00 | 3.00 / 1.25 | 3.00 / 2.50 | 3.00 / 1.25 | 2.75 / 0.00* | 3.00 / 1.75 |
| terra | arrow | 3.00 / 2.25 | 3.00 / 2.25 | 2.75 / 2.00 | 2.75 / 1.50 | 2.75 / 1.50 | 3.00 / 1.75 | 2.75 / 1.50 | 3.00 / 2.50 | 2.75 / 1.75 | 2.75 / 0.00* | 2.25 / 1.75 |
| terra | nanoparquet | 3.00 / 2.25 | 3.00 / 1.75 | 2.75 / 2.25 | 2.75 / 1.50* | 2.75 / 2.75 | 3.00 / 0.00 | 2.75 / 1.50 | 3.00 / 2.00 | 3.00 / 0.00 | 3.00 / 0.00* | 3.00 / 1.50 |
| terra | pyarrow | 2.75 / 3.00 | 2.25 / 2.00 | 2.75 / 2.50 | 2.75 / 2.50 | 2.75 / 2.50 | 2.75 / 0.00 | 2.75 / 1.25 | 2.75 / 1.75 | 2.75 / 0.00 | 2.75 / 0.00* | 2.25 / 1.75 |
| terra | pandas | 2.50 / 2.00 | 2.75 / 2.25 | 2.75 / 2.25 | 2.75 / 0.00* | 2.75 / 0.00* | 2.75 / 0.00 | 2.75 / 2.00 | 2.75 / 2.25 | 2.75 / 0.00 | 2.75 / 0.00* | 2.00 / 2.00 |
| terra | polars | 2.75 / 2.00 | 2.75 / 2.00 | 2.75 / 1.50 | 2.75 / 1.50 | 2.75 / 1.50 | 2.75 / 0.00 | 2.75 / 0.00 | 2.75 / 2.00 | 2.75 / 1.25 | 2.75 / 0.00* | 2.75 / 1.50 |
| terra | Parquet2 | 3.00 / 2.25 | 3.00 / 2.00 | 3.00 / 2.00 | 3.00 / 2.25 | 3.00 / 2.00 | 3.00 / 0.00 | 2.75 / 1.50 | 3.00 / 2.25 | 3.00 / 0.00 | 3.00 / 0.00* | 3.00 / 1.75 |
| terra | hyparquet | 2.75 / 0.75 | 2.25 / 2.00 | 2.75 / 2.00 | 2.75 / 2.25 | 2.75 / 2.25 | 2.50 / 0.00 | 2.75 / 1.50 | 2.75 / 2.25 | 2.75 / 0.00 | 2.75 / 0.00* | 2.25 / 1.25 |
| terra | parquet-wasm | 2.50 / 2.75 | 2.25 / 2.50 | 2.75 / 1.00 | 2.75 / 1.50 | 2.50 / 2.25 | 2.25 / 0.00 | 2.75 / 1.50 | 2.75 / 2.50 | 2.75 / 0.00 | 2.75 / 0.00* | 2.50 / 1.75 |

Our totals beat every other library's under both judges, by at least
11 points. No task of ours scores below 2. The round fails only on
rule 1, in four places:

- **Python, task 1 (install), against pyarrow, both judges:** ours
  2.75, pyarrow 3.00. The only point lost is findability. pyarrow's
  install page is one toctree entry from its front page. Our README
  says "each page says how to install", and the Python page's
  "Parquet: install" sends the reader on to "Install". Neither judge
  found an error or a gap in what our install section says.
- **TypeScript, task 1 (install), against parquet-wasm, Terra:** ours
  2.50, parquet-wasm 2.75. Findability 2: Terra gave findability 2 on
  every one of our TypeScript tasks, because the answers are on the
  TypeScript page, one link from the README. Completeness 2: no
  supported TypeScript or browser versions are named.
- **TypeScript, task 2 (read a file), against parquet-wasm, Terra:**
  ours 2.25, parquet-wasm 2.50. Correctness 1: our type table says
  every conversion is exact or an error. The same table says DECIMAL of
  precision up to 15 becomes the nearest double.
- **R, task 5 (schema and metadata), against nanoparquet, Sonnet:**
  ours 2.50, nanoparquet 2.75. Findability 2: the task heading is only
  a link on the Parquet page. Completeness 2: the R page does not show
  how to see the file's raw key-value entries.

## Disagreements

On one task the two judges' scores for ours differ by a whole point:
Python against pandas, task 11 (Sonnet 3.00, Terra 2.00). On task 9,
the two judges differ by more than a point on the other library for
nanoparquet, Parquet2.jl, hyparquet and parquet-wasm. Terra scored 0
wherever labels could be kept only in key-value metadata, by a
user's own convention. Sonnet gave 1 to 1.75 for showing that
metadata exists. They also differ on hyparquet, task 11 (Sonnet 2.50,
Terra 1.25).

## Not yet acted on

Round 2 judged the same docs again, because of the blinding defect
above. No change was made to our docs in response to this round. The
changes it points to:

- **Install, one step from the front page.** In the README, link each
  language's install section directly, rather than "each page says how
  to install". Have "Parquet: install" give the commands itself, not
  only point to Install.
- **TypeScript install.** Name the supported TypeScript, Node and
  browser versions.
- **TypeScript type table.** Say that DECIMAL of precision up to 15 is
  the nearest double, so the "exact or an error" sentence is true.
- **R metadata.** Say whether `read_parquet_info()` returns the
  footer's key-value entries, and show how to see them. Name the task
  in a heading on the R page, not only in a link list.
- **TypeScript labels.** Show how to turn a labelled numeric column
  into a categorical (Terra's task 6, and the fresh agent's one partial
  task).
- **The fresh agents' smaller gaps** (below): rows past the end, the
  error tables, the TypeScript build, and the undocumented fields.

## Fresh-agent check

Following the rubric, one fresh agent per language (Claude Sonnet,
`claude-sonnet-5-5`) got only our bundle for its language, its own
copy of the commit, and a scratch directory. It did the eleven tasks,
writing every Parquet and `.dta` file it read itself. For task 11 it
used another tool available on the machine: R's arrow for R, Julia and
TypeScript, and pyarrow, pandas and polars in its venv for Python. The
briefs and the agents' reports are in [fresh/](fresh/).

| language | succeeded | partly | failed |
|---|---|---|---|
| R | 1 to 4, 6 to 11 | 5 | none |
| Python | 1 to 11 | none | none |
| Julia | 1 to 11 | none | none |
| TypeScript | 1 to 5, 7 to 11 | 6 | none |

The two "partly" results:

- **R, task 5:** `read_parquet_info()` does not return the file's
  key-value metadata, and the R page does not say so. Sonnet's task 5
  deduction against nanoparquet is the same point.
- **TypeScript, task 6:** the docs show no way to turn a labelled
  numeric column into a categorical. Terra's task 6 deduction is the
  same point.

The agents also found smaller gaps:

- **Rows past the end.** R, Python and Julia return the rows that
  exist, or none, without an error. The docs do not say so.
- **Error tables.** The error table in `docs/parquet.md` gives R's
  wording and argument names. It has no Python or Julia rows for the
  compression errors. Its TypeScript rows are malformed Markdown.
- **TypeScript build.** The wasm build needs rustup's cargo rather
  than Homebrew's, and Homebrew's llvm. It took over ten minutes. Only
  the script's header says this.
- **Undocumented fields and types:**
  - the field names of TypeScript's `Characteristic`;
  - the form of `key_value` / `keyValue`;
  - the `local` / `UTC` suffix in `logical_type`;
  - Julia's `DtaParser.WriteError` and `DtaError`.
- **Python, task 6.** There is no example of writing a labelled `.dta`
  file.
- **Links outside the bundle.** Some links point to sections outside
  the bundle, such as "The example file" and "Write a file".
