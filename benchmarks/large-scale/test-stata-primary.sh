#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
benchmark_library=${DTATOOLS_BENCH_LIB:-}

if [ -z "$benchmark_library" ] || [ ! -d "$benchmark_library/dtatools" ]; then
    printf '%s\n' "set DTATOOLS_BENCH_LIB to a library containing dtatools" >&2
    exit 2
fi
if test -z "${STATA_BIN:-}" && test -x /Applications/Stata/StataMP.app/Contents/MacOS/stata-mp; then
    STATA_BIN=/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp
fi
if [ -z "${STATA_BIN:-}" ] || [ ! -x "$STATA_BIN" ]; then
    printf '%s\n' "set STATA_BIN to the Stata executable" >&2
    exit 2
fi
if grep -Eq '^[[:space:]]*(use|sysuse|webuse)[[:space:]]' \
    "$script_dir/stata-generate-fixture.do"; then
    printf '%s\n' "Stata primary generator must not load an existing dataset" >&2
    exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/dtatools-stata-primary.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
cp "$script_dir/stata-generate-fixture.do" "$work_dir/"
(
    cd "$work_dir"
    "$STATA_BIN" -q -b do stata-generate-fixture.do \
        input.dta 1000 smoke result.tsv
)

fields=$(awk -F '\t' 'NR == 1 { print $1, $2, $4 + 0, $5 + 0 }' \
    "$work_dir/result.tsv")
if [ "$fields" != "stata ok 1000 40" ]; then
    printf 'unexpected Stata generator result: %s\n' "$fields" >&2
    exit 1
fi

DTATOOLS_BENCH_LIB="$benchmark_library" R_ENVIRON_USER=/dev/null \
R_PROFILE_USER=/dev/null Rscript --vanilla \
    "$script_dir/write-worker.R" dtatools stata-storage \
    "$work_dir/input.dta" "$work_dir/dtatools-output.dta" \
    > "$work_dir/dtatools-worker.tsv"
if ! grep -Eq '^SYNTHETIC_WRITE[[:space:]]+dtatools[[:space:]]+ok' \
    "$work_dir/dtatools-worker.tsv"; then
    printf '%s\n' "dtatools did not load and save the Stata-generated file" >&2
    exit 1
fi

DTATOOLS_BENCH_LIB="$benchmark_library" R_ENVIRON_USER=/dev/null \
R_PROFILE_USER=/dev/null Rscript --vanilla \
    "$script_dir/write-worker.R" haven stata-storage \
    "$work_dir/input.dta" "$work_dir/haven-output.dta" \
    > "$work_dir/haven-worker.tsv"
if ! grep -Eq '^SYNTHETIC_WRITE[[:space:]]+haven[[:space:]]+ok' \
    "$work_dir/haven-worker.tsv"; then
    printf '%s\n' "Haven did not load and save the Stata-generated file" >&2
    exit 1
fi

for writer in dtatools haven; do
    DTATOOLS_BENCH_LIB="$benchmark_library" R_ENVIRON_USER=/dev/null \
    R_PROFILE_USER=/dev/null Rscript --vanilla \
        "$script_dir/validate-write-output.R" "$writer" \
        "$work_dir/input.dta" "$work_dir/${writer}-output.dta"
done

printf '%s\n' "Stata-first primary write workflow: PASS"
