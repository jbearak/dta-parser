#!/bin/sh
# Read benchmarks: time and peak RSS of reading the files make_large.R
# writes, with dtatools, haven, readstata13, pandas and the npm package.
# Each read is a fresh process under /usr/bin/time; the page cache is
# warm (each file is read once first).
# Run from the repository root, with dtatools installed and js built:
#   sh bench/read.sh <dir>
set -e
dir=$1
log=$(mktemp)
measure() {  # label, command...
  label=$1; shift
  /usr/bin/time -l "$@" > "$log.out" 2> "$log"
  rss=$(awk '/maximum resident set size/ {printf "%d", $1 / 1048576}' "$log")
  printf "| %s | %s | %s |\n" "$label" "$(tail -1 "$log.out")" "$rss"
}
cat "$dir/long.dta" "$dir/wide.dta" > /dev/null
printf "| read | seconds | peak RSS MB |\n|---|---|---|\n"
for tool in dtatools haven readstata13; do
  measure "long.dta, all 12 variables: $tool" Rscript bench/read_case.R "$tool" full "$dir/long.dta"
done
measure "long.dta, all 12 variables: pandas" python3 bench/read_case.py full "$dir/long.dta"
measure "long.dta, all 12 variables: npm" node bench/read_case.mjs full "$dir/long.dta"
for tool in dtatools haven readstata13; do
  measure "wide.dta, 5 of 400 variables: $tool" Rscript bench/read_case.R "$tool" five "$dir/wide.dta"
done
measure "wide.dta, 5 of 400 variables: pandas" python3 bench/read_case.py five "$dir/wide.dta"
measure "wide.dta, 5 of 400 variables: npm" node bench/read_case.mjs five "$dir/wide.dta"
measure "wide.dta, 200 rows at the start: npm" node bench/read_case.mjs window-start "$dir/wide.dta"
measure "wide.dta, 200 rows at the end: npm" node bench/read_case.mjs window-end "$dir/wide.dta"
rm -f "$log" "$log.out"
