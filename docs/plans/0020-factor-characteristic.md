# Plan: factors survive a .dta round trip, marked by a characteristic

Status: implemented in R and Python; the user settled its questions on 2026-11-08 (below).

## Problem

`save_dta()` writes a factor as Stata's `encode` would: codes 1 to k,
stored as long, with a value label set that holds the levels in order.
Most of the factor survives: level order, level text and unused levels
are all in the label set. What is lost:

1. **That it was a factor.** `read_dta()` gives back labelled codes
   (`factors = FALSE`, the default), so `d$region == "North"` works
   only through the labelled class (plan 0017), and `levels()`,
   `table()` and models see numbers.
2. **`ordered`.** Nothing in the file says an ordered factor was
   ordered.

`read_dta(factors = TRUE)` brings back every labelled column as a
factor, but defaults to `FALSE` for a good reason: a factor drops `.a`
to `.z`, so turning every labelled column into one loses data. What is
missing is a way to tell a column that *was* a factor, and holds
nothing a factor would drop, from one that was not.

## Proposal

**Write.** For each factor column, `save_dta()` adds a characteristic
to the variable: name `dtaparser_factor`, value `unordered` or
`ordered`, followed by a space and the name of the value label set it
wrote (`ordered region`). Stata keeps characteristics it does not
know, through `save`, `rename` and `replace`; haven does not expose
characteristics, and readstata13 lists them without acting on them.

**Read.** `read_dta()` makes a marked column a factor even when
`factors = FALSE`, when all of these still hold:

- the column's value label set is the one the marker names;
- every non-missing value has a label;
- no two codes share a text (pandas categories must differ, and no
  factor `save_dta()` writes has two);
- there is no `.a` to `.z`.

The levels and codes come from the label set as `factors = TRUE` makes
them (plan 0006), and `ordered` from the marker. If a check fails, the
column is read as it is today (labelled codes), with one warning per
file naming the columns, since the file was changed after it was
written (relabelled, recoded to an unlabelled value, or given `.d`).
The characteristic is not passed through to the tibble's
`characteristics` attribute, and `save_dta()` writes it afresh, so a
stale one never survives a round trip through R.

**Why a characteristic and not a note:** notes are for people and
Stata lists them with `notes`; a characteristic is per variable, moves
with `rename`, and is the format's place for data about a variable.

## Other languages

- **Python, in the same PR as R.** `write_dta` writes a `category` with
  codes 0 to k-1, and `read_dta` has no categorical option. It will
  write the same marker, and read a marked column as `category`
  (`ordered` from the marker) under the same checks, warning the same
  way. The codes differ from R's (0-based), which the marker makes
  harmless: each side reads the label set.
- **Julia.** DtaParser does not write `CategoricalArray`; Datakit
  depends on CategoricalArrays for Parquet. Proposed: leave DtaParser
  alone and keep the marker as a characteristic its readers see.
- **npm.** No factor type for `.dta`; the marker is visible through
  `characteristics()`. No change proposed.

## Tests

- R: a factor and an ordered factor round-trip through `save_dta()` and
  `read_dta()` identically, unused levels included; each check that
  fails (label set renamed, an unlabelled value, a `.d`) gives labelled
  codes and the warning; `factors = TRUE` is unchanged.
- The readback job (`compat/readback/`): haven, readstata13, pandas
  and pyreadstat read the marked file's values and labels as before;
  readstata13 sees the characteristic.

## Out of scope

Labelled missing values as factor levels (ADR 0017 decided against
them); changing the `factors` default.

## Decisions (the user, 2026-11-08)

1. The marker is `dtaparser_factor` = `ordered region` or `unordered
   region`: the ordering, a space, and the value label set's name.
2. A stale marker gives labelled codes and one warning per file naming
   the columns.
3. Python is built in the same PR as R.
