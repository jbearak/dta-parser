# AGENTS.md

dta-parser reads and writes Stata `.dta` files. This repository holds the
format library, the npm package `@jbearak/dta-parser` built on it, and
dtatools, a small R package built on it. Plans live in `docs/plans/`,
decisions in `docs/adr/`.

## Rules that override everything else

- Never run Stata. It is not installed on this machine; do not install it
  or look for another copy.
- Never read Stata's installed files: ado files, help files, or anything
  else that ships with Stata. Do not use tools or data extracted from them.
- Never use output Stata produced as a test oracle or expected result.
  Expected values come only from open-source libraries (haven, ReadStat,
  pandas, readstata13 and the like) and from the fertility_surveys tests'
  own assertions.
- Make fixtures without Stata: write them with this library's writer, or
  with haven, pandas or ReadStat, from data you create. Versions none of
  those can write may use `.dta` files from open-source projects' test
  suites as inputs, if their licenses allow, with credit. Expected values
  still come only from the open-source readers. Do not use example
  datasets that ship with Stata.
- Take facts about the format only from general knowledge and from
  open-source projects' documentation and code. Do not look up or use
  official Stata documentation, and never copy text from it; write in
  your own words. Copy open-source code only if its license allows, with
  credit.
- If you think you have found a bug in another project (haven,
  ReadStat, readstata13, pandas or any other), read
  `docs/other-readers.md` first: the differences found so far were
  either fixed upstream already or defensible choices. Never file an
  issue, pull request or comment in another project without the user's
  approval of that specific report.
- Work only in this repository. Other repositories may be read only as
  described below, and never pushed to.

## Other repositories

- manuscript-markdown, Sight and table-viewer read `.dta` files through
  this library. Read them only to learn how they read `.dta` files and
  what they need. In Sight, read nothing else; in particular not its
  Stata command database. Never push to them.
- fertility_surveys is private. dtatools exists for its testthat suite
  (`tests/testthat/`). Read only its R code and tests. Ignore its `.do`
  files, and never treat a log, CSV, workbook or dataset in it as an
  expected result. Never copy its paths, data or code into this
  repository, its tests, docs or PRs. Never push to it, and ask before
  changing any of its code.

## Publishing

Ask before publishing anything to npm or any other registry.
