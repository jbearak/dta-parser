#!/bin/sh
# Files going between the languages' datakits (plan 0019; TypeScript
# since plan 0021): R, Python and TypeScript write; Julia checks them and
# writes; R checks Julia's, Python's and TypeScript's; Python checks R's,
# Julia's and TypeScript's; TypeScript checks R's, Python's and Julia's.
# Every cell is checked.
#
#     sh compat/parquet/cross_language.sh [DIR]
#
# Run from the repository root. R needs dtaparser and datakit (R_LIBS
# may point at a scratch library); Julia uses bench/julia's environment;
# PYTHON (default python3) needs dta_parser and datakit; node needs js/
# and js/datakit/ built.
set -e
DIR=${1:-$(mktemp -d)}
PYTHON=${PYTHON:-python3}
Rscript compat/parquet/cross_language.R write "$DIR"
"$PYTHON" compat/parquet/cross_language.py write "$DIR"
node compat/parquet/cross_language.mjs write "$DIR"
julia --project=bench/julia --startup-file=no compat/parquet/cross_language.jl check "$DIR"
julia --project=bench/julia --startup-file=no compat/parquet/cross_language.jl write "$DIR"
Rscript compat/parquet/cross_language.R check "$DIR"
"$PYTHON" compat/parquet/cross_language.py check "$DIR"
node compat/parquet/cross_language.mjs check "$DIR"
echo "cross-language checks passed"
