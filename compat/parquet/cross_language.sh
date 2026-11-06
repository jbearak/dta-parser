#!/bin/sh
# Files going between the languages' datakits (plan 0019): R and Python
# write; Julia checks both and writes; R checks Julia's and Python's;
# Python checks R's and Julia's. Every cell is checked.
#
#     sh compat/parquet/cross_language.sh [DIR]
#
# Run from the repository root. R needs dtaparser and datakit (R_LIBS
# may point at a scratch library); Julia uses bench/julia's environment;
# PYTHON (default python3) needs dta_parser and datakit.
set -e
DIR=${1:-$(mktemp -d)}
PYTHON=${PYTHON:-python3}
Rscript compat/parquet/cross_language.R write "$DIR"
"$PYTHON" compat/parquet/cross_language.py write "$DIR"
julia --project=bench/julia --startup-file=no compat/parquet/cross_language.jl check "$DIR"
julia --project=bench/julia --startup-file=no compat/parquet/cross_language.jl write "$DIR"
Rscript compat/parquet/cross_language.R check "$DIR"
"$PYTHON" compat/parquet/cross_language.py check "$DIR"
echo "cross-language checks passed"
