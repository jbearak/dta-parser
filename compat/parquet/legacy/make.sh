#!/bin/sh
# Write the legacy fixtures again (README.md here): R's datakit writes
# its files, R's datakit reads them all, and pyarrow reads them all.
#
#     sh compat/parquet/legacy/make.sh
#
# Run from the repository root with R's dtaparser and datakit installed
# (R_LIBS may point at a scratch library), and pyarrow and numpy
# importable by python3 (PYTHON may name another interpreter).
#
# The TypeScript half, ts_*.parquet, is kept as committed: make.mjs needs
# the npm package @jbearak/datakit, which was removed (ADR 0044), so it
# runs only in a checkout of commit 408c350 or earlier, after `npm run
# build` in js/ and js/datakit/. This script leaves those files alone and
# reads them again with the rest.
set -e
rm -f compat/parquet/legacy/r_*.parquet compat/parquet/legacy/*.rds compat/parquet/legacy/expected/*.json
Rscript compat/parquet/legacy/make.R write
Rscript compat/parquet/legacy/make.R read
${PYTHON:-python3} compat/parquet/legacy/expected.py
