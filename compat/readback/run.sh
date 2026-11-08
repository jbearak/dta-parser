#!/bin/sh
# Save every input again with each of our writers, then check that
# haven, readstata13, pandas and pyreadstat read each copy as its input.
# Run from the repository root, with dtaparser and dtatools installed in
# R, dta_parser and pyreadstat in Python, DtaParser built for Julia and
# js/dist built:
#   sh compat/readback/run.sh <dir>
# PYTHON and JULIA name the interpreters (default python3, julia).
set -e
dir="$1"
python="${PYTHON:-python3}"
julia="${JULIA:-julia}"
rm -rf "$dir"
mkdir -p "$dir/original"
cp compat/fixtures/*.dta compat/readback/strls.dta compat/readback/binary.dta "$dir/original/"
Rscript compat/readback/write.R "$dir/dtaparser" dtaparser
Rscript compat/readback/write.R "$dir/dtatools" dtatools
"$python" compat/readback/write.py "$dir/python"
"$julia" --project=julia/DtaParser compat/readback/write.jl "$dir/julia"
node compat/readback/write.mjs "$dir/npm"
Rscript compat/readback/dump.R "$dir"
"$python" compat/readback/check.py "$dir"
