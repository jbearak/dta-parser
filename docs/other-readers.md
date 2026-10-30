# Differences from other readers are not bugs

Read this before calling anything in another project a bug.

## What our tests found

Where a reader's value is not a usable oracle, the compatibility tests
skip it, with the reason, in the `KNOWN` list of
`crates/dta/tests/compat.rs` (see [ADR 0005](adr/0005-oracles.md) and
[compat/README.md](../compat/README.md)). None of these differences is
an open bug in another project. Each was either
fixed upstream already, or is a choice the other library is entitled
to make:

| difference | status |
|---|---|
| haven 2.5.5 fails on 105 value labels and reads 104 and 108 value labels wrongly | fixed upstream: the bug was in the ReadStat code haven bundles, fixed on ReadStat `dev` (69d8f91, September 2026) and in haven `main` since it vendored that (tidyverse/haven#851); not yet on CRAN |
| haven 2.5.5 drops trailing blanks from `str#` values | fixed upstream the same way (ReadStat 725bb90) |
| haven 2.5.5 writes and reads 119 strL references in the 118 layout | fixed upstream the same way (ReadStat 69d8f91) |
| readstata13 does not read value labels before release 108 | a deliberate limit: it reads labels only for releases after 105 |
| readstata13 returns pre-113 missing values as the stored number with `missing.type = TRUE` | documented: it warns that the option applies only to newer files; the default gives `NA` (`compat/expected.R` maps the stored numbers to `.`) |
| readstata13 reads an empty strL as `NA` (an empty `str#` as `""`) | defensible: Stata has no separate missing string and treats `""` as missing |
| pandas decodes text before release 118 as Latin-1, not Windows-1252 | defensible: those files do not record their encoding, so every reader guesses; we and haven guess Windows-1252 |

## Before reporting a difference to another project

A different answer from another reader is not, by itself, a bug in that
reader. In October 2026 we drafted reports for five of the rows above,
taking them for bugs: the three haven ones were already fixed upstream,
and the readstata13 strL and pandas encoding ones are defensible
choices, and one went out as a bug report before that was
checked (it is now a question, sjewo/readstata13#96). So, before
calling a difference a bug:

1. Reproduce it on the project's current development branch, not only
   the release we pin; fixes often wait for a release.
2. Ask whether the format settles the question. If it does not (no
   recorded encoding, no missing string), the other library's choice is
   a convention: record it here, don't report it.
3. Search the project's issues, open and closed.
4. Never file an issue, pull request or comment in another project
   without the user's approval of that specific report, and phrase a
   difference of convention as a question.
