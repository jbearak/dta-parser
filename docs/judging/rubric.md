# Documentation rubric

Plan 0005 asks for documentation that two judges, Claude Sonnet and GPT
Terra, score above the documentation of the other open-source Stata
readers in each language. This file fixes the tasks, the scores, the
pass rule and the protocol before any judging happens. It is committed
before our documentation was written, and it does not change once
judging starts. A later round may change our docs, never this file.

## The ten tasks

Each task is something a user of a `.dta` library does. A judge reads a
library's documentation and asks: could I do this from these docs alone?

| # | task | what the judge looks for |
|---|---|---|
| 1 | Install the package | the install command, supported platforms and language versions, what to do when installation fails |
| 2 | Read a whole file into the language's usual table | the read call, what type comes back, what each Stata storage type becomes |
| 3 | Read only some columns | how to name them, whether order is kept, what happens with a name that is not in the file |
| 4 | Read a range of rows | skip and limit (or chunks), what an out-of-range request does |
| 5 | Get the metadata | variable labels, the data label, display formats, storage types; and reading them without the data |
| 6 | Use value labels | find the label set of a column, look up the text of a code, turn a labelled column into the language's categorical or labelled type |
| 7 | Read dates | which display formats become dates or times, the epoch, how to turn conversion off, what happens to values that cannot convert |
| 8 | Write a table to `.dta` | the write call, which release is written, how each column type maps to a storage type, what is an error |
| 9 | Write variable labels and value labels | attach a variable label, a value label set, and a data label when writing, and check them by reading back |
| 10 | Keep `.a` to `.z` | tell `.` from `.a` ... `.z` per value, keep them through filtering and sorting, write them back |

## Common and ours-only tasks

A task is **common** in a language when every library compared in that
language supports it; otherwise it is **ours-only** there. The pass is
decided on common tasks. Ours-only tasks are scored and published too,
but do not decide the pass.

The classification below comes from each other library's documentation and
source at the pinned version (see "Pinned documentation of the other libraries").

| # | R (haven, readstata13) | Python (pandas, pyreadstat) | Julia (ReadStatTables.jl) | TypeScript (@irbisadm/statfmt) |
|---|---|---|---|---|
| 1 install | common | common | common | common |
| 2 read | common | common | common | common |
| 3 columns | common | common | common | ours-only: statfmt reads every column |
| 4 rows | common | common | common | common |
| 5 metadata | common | common | common | common |
| 6 value labels | common | common | common | common |
| 7 dates | common | common | common | ours-only: statfmt returns the numbers |
| 8 write | common | common | common | common |
| 9 write labels | common | common | common | common |
| 10 `.a` to `.z` | ours-only: readstata13 does not keep them per value | ours-only: pandas cannot write them | ours-only: ReadStatTables reads them as `missing` | ours-only: statfmt reads them as `null` |

## Scores

For each library and task, a judge gives four scores from 0 to 3.

**Findability.** Starting at the package's front page (README or
documentation home), how directly does a reader reach the answer?

- 3: a heading, table of contents entry or index entry names the task,
  one step from the front page.
- 2: the answer is there, but the reader has to search a long page or
  follow two or more links.
- 1: the answer is only in a function reference entry with no pointer
  from the guide, or only implied by an example.
- 0: not found.

**Correctness.** Is what the docs say true of the pinned version, and
would the examples run as written?

- 3: everything stated about the task is right and the examples run.
- 2: one small error or an example that needs an obvious fix.
- 1: an error that would mislead a user into wrong results.
- 0: wrong, or the task is not covered.

**Completeness.** Does the reader learn everything needed for the task,
including options, limits and what is lost?

- 3: the main path, the options that change the result, and the edge
  cases listed in "what the judge looks for".
- 2: the main path and most options; an edge case missing.
- 1: the main path only.
- 0: not covered.

**Clarity.** Can a reader who knows the language but not Stata follow
it?

- 3: plain words, a short example with its output or result described,
  Stata terms explained where first used.
- 2: understandable with some rereading, or an example without saying
  what it gives.
- 1: hard to follow: jargon, no example, or contradictions.
- 0: not covered.

A library's **task score** is the mean of its four scores (0 to 3).
Its **common total** in a language is the sum of its task scores over
the tasks that are common in that language.

## Pass rule

Our documentation passes when, for **both** judges and in **every**
language:

1. our common total is higher than the common total of every
   other library in that language; and
2. each of our common tasks has a task score of at least 2.

Ties fail. A judge's scores stand as given; we do not average the two
judges.

## Protocol

**Material.** Each library's documentation is bundled as plain text:

- Ours, per language: `README.md`, every file in `docs/guide/`, the
  language page (`docs/r.md`, `docs/python.md`, `docs/julia.md` or
  `docs/typescript.md`), and the API reference (R: `r/dtatools/man/`;
  Python and Julia: the docstrings; TypeScript: the TSDoc in
  `js/src/`). The commit is recorded with each round.
- Other libraries: the documentation at the pinned version below: README,
  user guide or vignettes, and the reference entries for the functions
  that read and write `.dta` files and handle labels, dates and
  missing values.

**Blinding.** In both bundles, the package and repository names in prose
are replaced by "Library A" and "Library B". Function names in code stay,
since removing them breaks the examples; judges are told not to use
outside knowledge of any library.

**Pairs and order.** Each judge scores pairs: ours against one
other library in the same language (R: two pairs; Python: two; Julia: one;
TypeScript: one). Which library is A is decided per pair by a coin flip
from a seeded random number generator; the seed and the outcomes are
published with the round. Each pair is judged in a fresh session with
no memory of the others.

**Prompt.** The judge receives this file's "ten tasks", "Scores" and the
per-language common/ours-only table, then bundle A, then bundle B, and
returns, per library and task, the four scores and one or two sentences
of reason for each score below 3.

**Judges.** Claude Sonnet and GPT Terra; the exact model identifiers are
recorded in each transcript.

**Rounds.** At most three. After a round that fails, we may revise our
documentation (never the other libraries' bundles or this rubric) and judge
again with new coin flips. Every round's prompts, bundles' commit or
version, raw responses, score tables and any disagreement between the
judges are published in `docs/judging/round-N/`.

**Fresh-agent check.** Separately from the judges, one fresh agent per
language receives only our documentation for that language (the bundle
above) and a scratch directory, and does all ten tasks, writing the
`.dta` files it reads. Its transcript and whether each task succeeded
are published with the round. This check is reported, not scored.

## Pinned documentation of the other libraries

Versions are those installed on the machine where the benchmarks run
(R via `packageVersion()`, Python in the benchmark environment, Julia
in the default environment, npm's latest release).

| language | library | version | documentation source |
|---|---|---|---|
| R | haven | 2.5.5 | <https://github.com/tidyverse/haven/tree/ec7f034d1453d091d1adff36c3cdc0533c8cb8fb> (tag `v2.5.5`): `README.md`, `vignettes/semantics.Rmd`, `man/read_dta.Rd`, `man/labelled.Rd`, `man/tagged_na.Rd`, `man/as_factor.Rd`, `man/zap_labels.Rd` |
| R | readstata13 | 0.11.0 | <https://github.com/sjewo/readstata13/tree/388f9322d20ed5a537ba93d4c3cce9239b0b250f> (tag `v0.11.0`): `README.md`, `vignettes/`, `man/read.dta13.Rd`, `man/save.dta13.Rd`, `man/get.label*.Rd`, `man/set.label.Rd`, `man/varlabel.Rd` |
| Python | pandas (Stata I/O) | 3.1.0 | <https://github.com/pandas-dev/pandas/tree/c6f46769b808eb60218189d089dd67841b44f1b9> (tag `v3.1.0`): the Stata section of `doc/source/user_guide/io.rst`; docstrings of `read_stata`, `DataFrame.to_stata`, `StataReader` and `StataWriter117` in `pandas/io/stata.py` |
| Python | pyreadstat | 1.3.7 | <https://github.com/Roche/pyreadstat/tree/e6e23bc0021875f35fccc3c2707c3e5151c130bb> (tag `v1.3.7`): `README.md`, the API reference in `docs/` for `read_dta`, `write_dta`, `set_value_labels`, `read_file_in_chunks` |
| Julia | ReadStatTables.jl | 0.4.0 | <https://github.com/junyuan-chen/ReadStatTables.jl/tree/9c07e788241d44be667b9690f593491827bf2a25> (tag `v0.4.0`): `README.md`, `docs/src/` |
| TypeScript | @irbisadm/statfmt | 0.1.1 | <https://registry.npmjs.org/@irbisadm/statfmt/-/statfmt-0.1.1.tgz> (git commit `308e5155e962cb9db5c32e379423d3211550a011` of <https://github.com/irbisadm/statfmt>): `README.md` and the TSDoc in `dist/*.d.ts` |
