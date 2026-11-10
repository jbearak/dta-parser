#!/bin/sh
# Write the legacy fixtures again (README.md here): R's datakit and
# TypeScript's write the files, R's datakit reads them all, and pyarrow
# reads them all.
#
#     sh compat/parquet/legacy/make.sh
#
# Run from the repository root with js/ and js/datakit/ built, R's
# dtaparser and datakit installed (R_LIBS may point at a scratch
# library), and pyarrow and numpy importable by python3 (PYTHON may name
# another interpreter).
set -e
rm -f compat/parquet/legacy/*.parquet compat/parquet/legacy/*.rds compat/parquet/legacy/expected/*.json
Rscript compat/parquet/legacy/make.R write
node compat/parquet/legacy/make.mjs
Rscript compat/parquet/legacy/make.R read
${PYTHON:-python3} compat/parquet/legacy/expected.py
