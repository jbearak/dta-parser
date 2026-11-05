#!/bin/sh
# Files going between the languages' datakits (plan 0019): R writes and
# Julia reads, then Julia writes and R reads, each checking every cell.
# Python's half comes with Python's datakit.
#
#     sh compat/parquet/cross_language.sh [DIR]
#
# Run from the repository root. R needs dtaparser and datakit (R_LIBS
# may point at a scratch library); Julia uses bench/julia's environment.
set -e
DIR=${1:-$(mktemp -d)}
Rscript compat/parquet/cross_language.R write "$DIR"
julia --project=bench/julia --startup-file=no compat/parquet/cross_language.jl check "$DIR"
julia --project=bench/julia --startup-file=no compat/parquet/cross_language.jl write "$DIR"
Rscript compat/parquet/cross_language.R check "$DIR"
echo "cross-language checks passed"
