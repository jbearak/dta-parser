#!/bin/sh
# Read benchmarks: time and peak RSS of reading the files make_large.R
# writes, with dtatools, haven, readstata13, pandas and the npm package.
# Each read is a fresh process under /usr/bin/time, run five times; the
# table shows the median time and median peak RSS. The page cache is
# warm (each file is read once first).
# Needs: dtatools, haven and readstata13 installed in R; a python3 with
# pandas (pip install pandas); the npm package built (scripts/build-wasm.sh,
# then npm ci && npm run build in js/). Make the files first with
#   Rscript bench/make_large.R <dir>
# then run from the repository root:
#   sh bench/read.sh <dir>
set -e
dir=$1
log=$(mktemp)
median() { sort -n | awk '{ v[NR] = $1 } END { print v[int((NR + 1) / 2)] }'; }
measure() {  # label, command...
  label=$1; shift
  : > "$log.times"; : > "$log.rss"
  for run in 1 2 3 4 5; do
    /usr/bin/time -l "$@" > "$log.out" 2> "$log"
    tail -1 "$log.out" >> "$log.times"
    awk '/maximum resident set size/ {printf "%d\n", $1 / 1048576}' "$log" >> "$log.rss"
  done
  printf "| %s | %s | %s |\n" "$label" "$(median < "$log.times")" "$(median < "$log.rss")"
}
cat "$dir/long.dta" "$dir/wide.dta" "$dir/groups.dta" > /dev/null
printf "| read | seconds | peak RSS MB |\n|---|---|---|\n"
for tool in dtatools haven readstata13; do
  measure "long.dta, all 12 variables: $tool" Rscript bench/read_case.R "$tool" full "$dir/long.dta"
done
measure "long.dta, all 12 variables: pandas" python3 bench/read_case.py full "$dir/long.dta"
measure "long.dta, all 12 variables: npm" node bench/read_case.mjs full "$dir/long.dta"
measure "long.dta, all, then every string compared: dtatools" Rscript bench/read_case.R dtatools touch "$dir/long.dta"
measure "long.dta, all, then every string compared: pandas" python3 bench/read_case.py touch "$dir/long.dta"
measure "long.dta, all, then every string compared: npm" node bench/read_case.mjs touch "$dir/long.dta"
measure "long.dta, all, then head() and a filter: dtatools" Rscript bench/read_case.R dtatools head "$dir/long.dta"
for task in read group tab again; do
  measure "groups.dta, $task: dtatools" Rscript bench/fresh_case.R "$task" "$dir/groups.dta"
done
for tool in dtatools haven readstata13; do
  measure "wide.dta, 5 of 400 variables: $tool" Rscript bench/read_case.R "$tool" five "$dir/wide.dta"
done
measure "wide.dta, 5 of 400 variables: pandas" python3 bench/read_case.py five "$dir/wide.dta"
measure "wide.dta, 5 of 400 variables: npm" node bench/read_case.mjs five "$dir/wide.dta"
measure "wide.dta, 200 rows at the start: npm" node bench/read_case.mjs window-start "$dir/wide.dta"
measure "wide.dta, 200 rows at the end: npm" node bench/read_case.mjs window-end "$dir/wide.dta"
rm -f "$log" "$log.out" "$log.times" "$log.rss"
