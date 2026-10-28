# NSFG benchmark files

`make.py` turns every public-use data file of the National Survey of
Family Growth (NSFG) into a release-118 `.dta` file, for the read
benchmarks.

## Run

```sh
python bench/nsfg/make.py                  # everything
python bench/nsfg/make.py --only 2002_Male # one file, no report
```

It needs Python 3.10 or later with pandas (3.x tested), numpy and
pyreadstat. Options:

- `--raw DIR`: where CDC's files are downloaded (default
  `/private/tmp/claude-501/nsfg-raw`). Files already there at the
  listed size are not fetched again.
- `--out DIR`: where the `.dta` files go (default
  `/private/tmp/claude-501/nsfg-dta`).

A full run downloads about 920 MB once, then takes under two minutes and
writes about 490 MB of `.dta` files. It exits non-zero if any file fails.

## What it does

1. Lists CDC's two NSFG directories,
   <https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/NSFG/> and
   <https://ftp.cdc.gov/pub/Health_Statistics/NCHS/nsfg/>, downloads
   every file, and records each one's cycle, size, SHA-256, URL and
   role in `inventory.json`. Files it does not convert carry the reason.
2. Reads each data file:
   - 2002 to 2017–2019 fixed-width files: column positions, storage
     types, names and variable labels from CDC's Stata dictionary
     (`.dct`), value labels from its label program (`.do`), then
     `pandas.read_fwf` with those exact columns. Positions are checked
     against CDC's SAS program for the same file.
   - 1973 to 1995 and the 2002 household file, which have no Stata
     dictionary: positions, names, labels and value labels from CDC's
     SAS program. Where one data file holds two record types (1976 and
     1982), records are split by the record-type field the SAS
     programs test. Storage types are the smallest Stata type that
     holds every value.
   - 2022–2023 and the helper SAS datasets: the `.sas7bdat` files
     through pyreadstat.
3. Checks every file: all records have one length and reach the end of
   the layout, the rows read equal the records, and the respondent ID
   is unique (with the pregnancy number in pregnancy files, and with sex
   in 2002 files that cover women and men, whose IDs overlap). CSV and
   text copies that CDC publishes beside a SAS dataset must have the
   same number of rows.
4. Writes each file with `pandas.DataFrame.to_stata(version=118)`, with
   variable labels, value labels and a data label. pandas is the writer
   on purpose: it shares no code with this repository.
5. Writes `REPORT.md`: per file, the cycle, rows, variables, size,
   status and anything worth knowing (cross-check results, columns the
   layout does not describe, labels pandas cut to 80 characters).

The parsers for `.dct`, `.do` and SAS programs cover only what CDC's
files use. That grammar was learned from the files themselves.

Values are kept as published: codes such as 98 (refused) or 99 (don't
know) stay numbers with their value labels, as CDC's programs leave them
unless the user turns on their optional recodes.

## Provenance

The NSFG public-use files are published by the National Center for
Health Statistics (CDC) and are in the public domain. Neither the
downloaded files nor the `.dta` files are committed; only
`inventory.json` and `REPORT.md` are. The `.dta` files are benchmark
inputs, never test oracles.

## Release variants

`bench/make_release_variants.py` is the companion for the synthetic
files: it rewrites `long.dta` (from `bench/make_large.R`) with pandas as
releases 114, 117 and 119, reads each back and compares it with the
source.
