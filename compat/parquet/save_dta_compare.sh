#!/bin/sh
# TypeScript's saveDta against Python datakit's save_dta and R's save_dta
# (plan 0021): each saves the same Parquet file (Python's from
# cross_language.py) as .dta, and compare_saved.py compares the files:
# storage types, display formats, values, missing codes and value labels
# with Python's, and the factor marker (dtaparser_factor) with R's, since
# Python's polars datakit writes none.
#
#     sh compat/parquet/save_dta_compare.sh [DIR]
#
# Run from the repository root after compat/parquet/cross_language.sh
# DIR (which writes DIR/from_python.parquet), with js/ and js/datakit/
# built, and R's datakit and Python's datakit installed.
set -e
DIR=${1:-$(mktemp -d)}
PYTHON=${PYTHON:-python3}
[ -f "$DIR/from_python.parquet" ] || "$PYTHON" compat/parquet/cross_language.py write "$DIR"
# The columns a .dta file can hold from that file: not the instants in
# zones (.dta holds clock times), "score" (its labels' code 1.5) or "long"
# (a word Stata reserves), which are errors in every language.
COLS=id,small,fl,count,region,day,seen,dup,w
"$PYTHON" - "$DIR" "$COLS" <<'EOF'
import os, sys
import datakit as dk
d, cols = sys.argv[1], sys.argv[2].split(",")
df, meta = dk.read_parquet(os.path.join(d, "from_python.parquet"), columns=cols)
dk.save_dta(df, os.path.join(d, "saved_python.dta"), meta=meta)
EOF
node -e '
const node = require("./js/datakit/dist/node.js");
const [d, cols] = process.argv.slice(1);
node.saveDta(node.readParquet(d + "/from_python.parquet", { columns: cols.split(",") }), d + "/saved_typescript.dta", { onWarning() {} });
' "$DIR" "$COLS"
# R for the factor marker only: its factor, region.
Rscript -e '
suppressPackageStartupMessages(library(datakit))
d <- read_parquet(file.path(commandArgs(TRUE)[1], "from_python.parquet"), timestamps = "truncate")
save_dta(d["region"], file.path(commandArgs(TRUE)[1], "saved_r.dta"))
' "$DIR"
"$PYTHON" compat/parquet/compare_saved.py "$DIR"
