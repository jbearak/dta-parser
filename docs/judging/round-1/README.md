# Judging round 1

Round 1 of the protocol in [rubric.md](../rubric.md). **It passes**:
both judges score ours above every competitor in every language on the
common tasks, and no common task of ours scores below 2.

## Setup

- **Our docs:** commit `b4dade433b516519099d4d0179a73a1cf3a227c0`.
- **Competitor docs:** the pinned versions in the rubric.
- **Judges:**
  - Claude Sonnet (`claude-sonnet-5-5`, through Claude Code's `sonnet` model);
  - GPT Terra (`gpt-6.1-terra`, reasoning effort high, through Codex).

  Each pair ran in a fresh session for each judge.
- **Coin flips:** from Python's `random.Random(20261028)`, one per pair. Ours was Library B in every pair but TypeScript, where it was A. The outcomes are in [pairs.json](pairs.json).

The prompts are built by [bundle.py](../bundle.py):

    python docs/judging/bundle.py COMPETITORS OUT 20261028

COMPETITORS holds checkouts of the pinned competitor versions. The prompts
themselves are not committed, since most of their text is the
competitors' documentation.

Two departures from the protocol's wording:

- The judges got the list of common tasks for the language rather than
  the common/ours-only table, because the table names the libraries.
- "pandas" is not blinded: it is the table type in both bundles.

The raw responses are in [responses/](responses/); the tables below come
from them with [scores.py](../scores.py).

## Scores

Common totals: the sum of task scores over the common tasks (nine in R,
Python and Julia; seven in TypeScript; at most 27 and 21).

| judge | pair | ours | competitor | lowest common task of ours | pass |
|---|---|---|---|---|---|
| sonnet | R: haven | 26.50 | 16.50 | 1: 2.75 | yes |
| sonnet | R: readstata13 | 26.75 | 20.25 | 5: 2.75 | yes |
| sonnet | Python: pandas | 26.25 | 14.75 | 9: 2.50 | yes |
| sonnet | Python: pyreadstat | 27.00 | 22.75 | 1: 3.00 | yes |
| sonnet | Julia: ReadStatTables | 26.50 | 17.75 | 1: 2.75 | yes |
| sonnet | TypeScript: statfmt | 20.50 | 15.00 | 1: 2.75 | yes |
| terra | R: haven | 26.00 | 16.00 | 1: 2.75 | yes |
| terra | R: readstata13 | 23.25 | 15.75 | 5: 2.00 | yes |
| terra | Python: pandas | 26.25 | 14.00 | 7: 2.75 | yes |
| terra | Python: pyreadstat | 23.75 | 21.75 | 5: 2.25 | yes |
| terra | Julia: ReadStatTables | 25.50 | 14.75 | 1: 2.50 | yes |
| terra | TypeScript: statfmt | 20.00 | 16.25 | 1: 2.75 | yes |

## Disagreements

The judges' common totals for ours differ by at most 3.5 points (R
against readstata13: Sonnet 26.75, Terra 23.25). Terra gave findability
2 more often, because the answers are on the language page, one link
from the README. On no task did the judges' scores for ours differ by a
whole point or more. For competitors, they differed that much only on
ReadStatTables.jl:

- **Task 3:** Sonnet 1.00, Terra 0.00.
- **Task 10:** Sonnet 1.75, Terra 0.00.

## Findings acted on after the round

The round passed, so no second round was run. These points were still
fixed in our docs after commit `b4dade4`:

- **Python, migration table** (Terra, task 5, correctness 1): it mapped
  pyreadstat's `original_variable_types`, which holds display formats,
  to our storage type. It now maps that field to `format`, and
  `readstat_variable_types` to `storage`.
- **Dates guide** (Terra, task 7): "negative numbers are before 1960" is
  not true of `%ty`.

## Fresh-agent check

Following the rubric, one fresh agent per language (Claude Sonnet,
`claude-sonnet-5-5`) got only our docs for its language and a scratch
directory, and did the ten tasks. The briefs and the agents' reports are
in [fresh/](fresh/).

| language | succeeded | partly | failed |
|---|---|---|---|
| R | 1, 2, 3, 4, 6, 9, 10 | 5, 7, 8 | none |
| Python | 1 to 10 (1 after a workaround for no network) | none | none |
| Julia | 1 to 10 | none | none |
| TypeScript | 1 to 5, 8, 9, 10 | 6, 7 | none |

Every "partly" is a feature the docs said is missing, or a gap in them:

- **R:**
  - task 5: `read_meta` is named, but R has none;
  - task 7: there is no date switch, and `as.Date` needs `unclass`;
  - task 8: the release is not exposed.
- **TypeScript:**
  - task 6: there is no categorical type;
  - task 7: dates stay numbers.

The docs were then changed for the points the agents raised:

- **R:**
  - metadata without data via `read_dta(n_max = 0)`;
  - `skip = k - 1` for rows from `k`;
  - why `unclass()` comes before `as.Date()`;
  - `haven::as_factor()` does not take a `dta_num`.
- **Python:**
  - comparisons on a `StataArray` follow pandas, so use the keys for
    Stata's order;
  - installing without network access;
  - where float storage rounds (R and TypeScript only).
- **Julia:**
  - where to run the install;
  - CategoricalArrays as optional;
  - a categorical recipe safe for unlabelled codes and `missing`;
  - the letter-to-code rule;
  - the raw type with `dates = false`.
- **TypeScript:**
  - there is no table type;
  - there is no date switch;
  - building the WebAssembly module.
