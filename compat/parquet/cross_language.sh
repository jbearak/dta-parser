#!/bin/sh
# Files going between R's datakit and TypeScript's (plan 0019;
# TypeScript since plan 0021): each writes a file, R's from_r.parquet and
# TypeScript's from_typescript.parquet, and each reads the other's and
# checks every value, label, and letter.
#
#     sh compat/parquet/cross_language.sh [DIR]
#
# Run from the repository root. R needs dtaparser and datakit (R_LIBS
# may point at a scratch library); node needs js/ and js/datakit/ built.
set -e
DIR=${1:-$(mktemp -d)}
Rscript compat/parquet/cross_language.R write "$DIR"
node compat/parquet/cross_language.mjs write "$DIR"
Rscript compat/parquet/cross_language.R check "$DIR"
node compat/parquet/cross_language.mjs check "$DIR"
echo "cross-language checks passed"
