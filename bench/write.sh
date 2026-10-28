#!/bin/sh
# Time and peak memory of writing .dta files with dtatools and haven.
# Each run is a fresh R process under /usr/bin/time; the "none" run makes
# the same data without writing, so peak RSS minus that is the write's.
# Run from the repository root with dtatools installed: sh bench/write.sh
set -e
out=$(mktemp -d)
printf "| case | tool | write s | peak RSS MB | RSS over data MB | file MB |\n|---|---|---|---|---|---|\n"
for case in numeric strn strl_repeated strl_distinct strl_several; do
  base=0
  for tool in none haven dtatools; do
    file="$out/$case-$tool.dta"
    log="$out/time.txt"
    /usr/bin/time -l Rscript bench/write_case.R "$case" "$tool" "$file" > "$out/run.txt" 2> "$log"
    secs=$(awk '{print $3}' "$out/run.txt")
    rss=$(awk '/maximum resident set size/ {printf "%d", $1 / 1048576}' "$log")
    [ "$tool" = none ] && base=$rss && continue
    size=$(ls -l "$file" | awk '{printf "%d", $5 / 1048576}')
    printf "| %s | %s | %s | %s | %s | %s |\n" "$case" "$tool" "$secs" "$rss" $((rss - base)) "$size"
    rm -f "$file"
  done
done
rm -rf "$out"
