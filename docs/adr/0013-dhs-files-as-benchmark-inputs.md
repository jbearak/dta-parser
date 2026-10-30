# DHS files are benchmark inputs only

The user asked for benchmarks on DHS files and pointed to local copies
of 322 surveys. They first chose the India rounds (1992 to 2021, up to
5.2 GB), then replaced them: files that large are not typical of DHS
data. The benchmark uses one survey per DHS Program region instead, each
near the median size of the local copies (women's recode 47 MB,
birth-history recode 29 MB), so that together they stand for the files
people usually read:

| region | survey | women (wm) | birth history (bh) |
|---|---|---|---|
| Sub-Saharan Africa | Senegal 2019 | 49 MB | 29 MB |
| North Africa, West Asia and Europe | Turkey 2013 | 53 MB | 23 MB |
| Central Asia | Tajikistan 2017 | 64 MB | 29 MB |
| South and Southeast Asia | Myanmar 2016 | 72 MB | 31 MB |
| Latin America and the Caribbean | Dominican Republic 2013 | 40 MB | 22 MB |

All ten files are release 113. They were written by Stata. AGENTS.md
forbids running Stata, using its output as an expected result and making
fixtures with it; it does not forbid reading a Stata-written file as
input, and the user's request settles that these may be read.

So they are used only as inputs to timing runs:

- never fixtures, never expected values: correctness checks compare our
  readers with the open-source ones (haven, pandas, pyreadstat,
  ReadStatTables), never with anything Stata produced;
- never committed, copied into the repository or redistributed (the DHS
  Program's terms bar redistribution); scripts read them from the
  directory in `DTA_DHS_DIR`;
- `bench/RESULTS.md` reports only each file's country, round, recode,
  release, size, row count and variable count, never names, values or
  labels; disagreements are reported by column position and kind.

Public-use NSFG files are different: CDC publishes them openly, and the
benchmark builds its `.dta` copies from CDC's own downloads with pandas.
