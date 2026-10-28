# India DHS files are benchmark inputs only

The user asked for benchmarks on each India DHS file and pointed to
local copies (1992, 1998, 2006, 2016 and 2021 rounds; the women's and
birth-history recodes; up to 5.2 GB). Those files were written by
Stata. AGENTS.md forbids running Stata, using its output as an expected
result and making fixtures with it; it does not forbid reading a
Stata-written file as input, and the user's request settles that these
may be read.

So they are used only as inputs to timing runs:

- never fixtures, never expected values: correctness checks compare our
  readers with the open-source ones (haven, pandas, pyreadstat,
  ReadStatTables), never with anything Stata produced;
- never committed, copied into the repository or redistributed (the DHS
  Program's terms bar redistribution); scripts read them from the
  directory in `DTA_DHS_DIR`;
- `bench/RESULTS.md` reports only each file's round, recode, release,
  size, row count and variable count, never values, names or labels.

Public-use NSFG files are different: CDC publishes them openly, and the
benchmark builds its `.dta` copies from CDC's own downloads with pandas.
