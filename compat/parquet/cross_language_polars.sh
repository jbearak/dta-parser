#!/bin/sh
# One frame in both languages (plan 0025, stage 4): R's datakit
# (read_parquet_pl, read_dta_pl) and Python's (read_parquet, read_dta)
# read the same files, and the files each other's save_parquet and
# save_dta wrote, into polars; Python compares the two, cell by cell and
# field by field (cross_language_polars.py says how).
#
#     sh compat/parquet/cross_language_polars.sh [DIR]
#
# Run from the repository root. R needs dtaparser, datakit, polars,
# nanoarrow and jsonlite (R_LIBS may point at a scratch library); PYTHON
# (default python3) needs dta_parser, datakit, polars and pyarrow. Use
# the same polars version on both sides.
set -e
DIR=${1:-$(mktemp -d)}
PYTHON=${PYTHON:-python3}
rm -rf "$DIR/r" "$DIR/python"
"$PYTHON" compat/parquet/cross_language_polars.py fixtures "$DIR"
"$PYTHON" compat/parquet/cross_language_polars.py save "$DIR"
Rscript compat/parquet/cross_language_polars.R save "$DIR"
"$PYTHON" compat/parquet/cross_language_polars.py dump "$DIR"
Rscript compat/parquet/cross_language_polars.R dump "$DIR"
"$PYTHON" compat/parquet/cross_language_polars.py compare "$DIR"
