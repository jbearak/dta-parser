# Parquet documentation rubric (Gate 2 of plan 0018)

Plan 0018 asks for Parquet documentation that two judges, Claude Sonnet
and GPT Terra, score above the documentation of the other open-source
Parquet libraries in each language. This file fixes the tasks, the
scores, the pass rule and the protocol before any judging happens. It
does not change once judging starts: a later round may change our
documentation or our API, never this file or the other libraries'
bundles.

It was committed after the R Parquet documentation was drafted (PR 3 of
plan 0018) and before the Python, Julia and TypeScript Parquet
documentation; it was written without reading that draft.

## The eleven tasks

Each task is something a user of a Parquet library does. A judge reads
a library's documentation and asks: could I do this from these docs
alone?

| # | task | what the judge looks for |
|---|---|---|
| 1 | Install the package | the install command, supported platforms and language versions, what to do when installation fails |
| 2 | Read a whole file into the language's usual table | the read call, what type comes back, what each Parquet type becomes in the language, what is lost or refused |
| 3 | Read only some columns | how to name them (names, positions), whether order is kept, what happens with a name that is not in the file |
| 4 | Read a range of rows | skip and limit (or row groups or batches), what an out-of-range request does, what it costs |
| 5 | Get the schema and metadata without the data | column names and types, what each will become, row count, row groups, compression, key-value metadata |
| 6 | Use value labels and variable labels | read a column's variable label and its value labels, look up the text of a code, turn a labelled column into the language's categorical type |
| 7 | Read and write dates and timestamps | what DATE and TIMESTAMP become, units, time zones, values out of range, how naive and zoned times differ |
| 8 | Write a table | the write call, the compression codec and its default, row group size, how each language type maps to a Parquet type, what is an error |
| 9 | Write labels and check them | attach a variable label, value labels and a data label when writing, and see them again after reading back |
| 10 | Keep `.a` to `.z` | tell `.` from `.a` ... `.z` per value, write them and read them back, and know what other tools see |
| 11 | Read a file another tool wrote | which codecs, encodings and types are read, what is not supported (nested columns, encryption), and what other tools see in files this library writes |

## What each library supports

A task is **supported** by another library when its documentation or
code at the pinned version lets a user do it at all, however
awkwardly. The table comes from the research notes
(`docs/research/parquet-*.md`) and the libraries' documentation at the
pinned versions. "no" means the library cannot do the task; its score
for that task is still given and published, but pass rule 1 does not
compare against it.

| # | arrow (R) | nanoparquet | pyarrow | pandas | polars | Parquet2.jl | hyparquet + writer | parquet-wasm |
|---|---|---|---|---|---|---|---|---|
| 1 install | yes | yes | yes | yes | yes | yes | yes | yes |
| 2 read | yes | yes | yes | yes | yes | yes | yes | yes |
| 3 columns | yes | yes | yes | yes | yes | yes | yes | yes |
| 4 rows | yes (datasets, row groups) | no (r-lib/nanoparquet#48) | yes (row groups, batches) | no | yes (`n_rows`, lazy slice) | yes (row groups) | yes (`rowStart`, `rowEnd`) | yes (`limit`, `offset`) |
| 5 metadata | yes | yes | yes | no (through pyarrow only) | yes | yes | yes | yes |
| 6 labels | yes (haven labels, in R only) | no | no | yes (`attrs`, in pandas only) | no | no | no | no |
| 7 dates | yes | yes | yes | yes | yes | yes | yes | yes |
| 8 write | yes | yes | yes | yes | yes | yes | yes | yes |
| 9 write labels | yes (in R only) | no | no | yes (`attrs`) | no | no | no | no |
| 10 `.a` to `.z` | no (apache/arrow#49149) | no | no | no | no | no | no | no |
| 11 other tools' files | yes | yes | yes | yes | yes | yes | yes | yes |

## Scores

For each library and task, a judge gives four scores from 0 to 3:
**findability**, **correctness**, **completeness** and **clarity**,
defined exactly as in `rubric.md` ("Scores"), with "what the judge looks
for" taken from the table above. Install (task 1) is scored on the
install documentation like every other task, not on whether the package
is on a registry.

A library's **task score** is the mean of its four scores (0 to 3). Its
**total** is the sum of its task scores over all eleven tasks.

## Pass rule

Our documentation passes when, for **both** judges, in **every**
language, against **every** other library in that language:

1. on each task that library supports, our task score is at least
   theirs;
2. our total over all eleven tasks is higher than theirs; and
3. each of our eleven task scores is at least 2.

Ties on a total fail rule 2. A judge's scores stand as given; the two
judges are not averaged.

If a package of ours is not published to its language's registry and
its install documentation scores below another library's, rule 1
fails for that language; plan 0018 then asks the user how to proceed.

## Protocol

**Material.** Each library's documentation is bundled as plain text.

- Ours, per language: `README.md`, `docs/parquet.md`, the language page's
  Parquet sections (`docs/r.md`, `docs/python.md`, `docs/julia.md`,
  `docs/typescript.md`), and the API reference for the Parquet functions
  (R: datakit's man pages for `read_parquet`, `read_parquet_info` and
  `save_parquet`, and dtaparser's for the label helpers they return;
  Python and Julia: the docstrings; TypeScript: the TSDoc in `js/src/`).
  The commit is recorded with each round.
- Other libraries: the documentation at the pinned version below.

**Blinding.** In both bundles, package and repository names in prose
are replaced by "Library A" and "Library B". Function names in code
stay, since removing them breaks the examples. Judges are told not to
use outside knowledge of any library. Blinding cannot hide that our
docs discuss Stata's value labels and missing codes; judges are told to
score the tasks, not to guess the library.

**Pairs and order.** Each judge scores pairs: ours against one other
library in the same language (R: two pairs; Python: three; Julia: one;
TypeScript: two). Which library is A is decided per pair by a coin flip
from a seeded random number generator; the seed and outcomes are
published with the round. Each pair is judged in a fresh session with
no memory of the others.

**Prompt.** The judge receives this file's "eleven tasks", "Scores" (with
`rubric.md`'s score definitions inlined) and the supported-task table
for the library in the pair, then bundle A, then bundle B, and returns
per library and task the four scores and one or two sentences of reason
for each score below 3.

**Judges.** Claude Sonnet and GPT Terra; exact model identifiers are
recorded in each transcript.

**Rounds.** Until the pass rule holds. After a failing round we may
revise our documentation or API, then judge again with new coin flips.
Every round's prompts, bundle commits or versions, raw responses, score
tables and disagreements between the judges are published in
`docs/judging/parquet-round-N/`.

**Fresh-agent check.** Separately from the judges, one fresh agent per
language receives only our bundle for that language and a scratch
directory, and does all eleven tasks, writing the Parquet files it
reads (and a `.dta` file with labels and `.a` to `.z` for tasks 6, 9
and 10). Its transcript and whether each task succeeded are published
with the round. This check is reported, not scored.

## Pinned documentation of the other libraries

Versions are those studied in `docs/research/parquet-*.md`. When a
round's bundles are built, each tag is resolved to its commit, and the
commit is recorded with the round.

| language | library | version | documentation |
|---|---|---|---|
| R | arrow | 26.0.0 | the R package's `README.md`, the vignettes on reading and writing data and on metadata, and the reference pages for `read_parquet`, `write_parquet`, `ParquetFileReader`, `open_dataset` and `schema`, at tag `apache-arrow-26.0.0` of apache/arrow (`r/`) |
| R | nanoparquet | 0.5.2 | `README.md`, the vignettes, and the reference pages for `read_parquet`, `write_parquet`, `read_parquet_schema`, `read_parquet_info`, `read_parquet_metadata` and `parquet_options`, at tag `v0.5.2` of r-lib/nanoparquet |
| Python | pyarrow | 26.0.1 | the Parquet page of the Python user guide (`docs/source/python/parquet.rst`) and the docstrings of `pyarrow.parquet.read_table`, `write_table`, `ParquetFile`, `read_metadata` and `read_schema`, at tag `apache-arrow-26.0.1` |
| Python | pandas | 3.1.1 | the Parquet section of `doc/source/user_guide/io.rst` and the docstrings of `read_parquet` and `DataFrame.to_parquet`, at tag `v3.1.1` |
| Python | polars | 2.1.0 | the user guide's Parquet page and the reference pages for `read_parquet`, `scan_parquet`, `read_parquet_schema`, `read_parquet_metadata` and `DataFrame.write_parquet`, at the Python 2.1.0 release |
| Julia | Parquet2.jl | 0.2.37 | `README.md` and `docs/src/`, at tag `v0.2.37` |
| TypeScript | hyparquet and hyparquet-writer | 1.32.0 and 0.18.0 | each package's `README.md` and its TypeScript declarations, as published to npm at those versions |
| TypeScript | parquet-wasm | 0.9.0 | `README.md`, the documentation site's pages for reading and writing, and the TypeScript declarations, as published to npm at 0.9.0 |
