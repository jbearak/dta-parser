#!/bin/sh
# Save every input again with each of our writers, then check that
# haven, readstata13, pandas and pyreadstat read each copy as its input.
# Our writers are R's dtaparser and dtatools and the npm package. Run
# from the repository root, with dtaparser, dtatools, haven and
# readstata13 installed in R, pandas and pyreadstat in Python (the
# readers check.py runs) and js/dist built:
#   sh compat/readback/run.sh <dir>
# PYTHON names the Python interpreter (default python3).
set -e
dir="$1"
python="${PYTHON:-python3}"
rm -rf "$dir"
mkdir -p "$dir/original"
cp compat/fixtures/*.dta compat/readback/strls.dta compat/readback/binary.dta "$dir/original/"
Rscript compat/readback/write.R "$dir/dtaparser" dtaparser
Rscript compat/readback/write.R "$dir/dtatools" dtatools
node compat/readback/write.mjs "$dir/npm"
Rscript compat/readback/dump.R "$dir"
"$python" compat/readback/check.py "$dir"
