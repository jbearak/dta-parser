#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
benchmark_library=${DTAPARSER_BENCH_LIB:-$checkout_root/target/large-scale/standard-r-write-library}

if [ ! -d "$benchmark_library/dtaparser" ]; then
    printf '%s\n' "set DTAPARSER_BENCH_LIB to a library containing dtaparser" >&2
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

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/dtaparser-stata-primary.XXXXXX")
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

DTAPARSER_BENCH_LIB="$benchmark_library" R_ENVIRON_USER=/dev/null \
R_PROFILE_USER=/dev/null Rscript --vanilla \
    "$script_dir/write-worker.R" dtaparser stata-storage \
    "$work_dir/input.dta" "$work_dir/output.dta" > "$work_dir/worker.tsv"
if ! grep -Eq '^SYNTHETIC_WRITE[[:space:]]+dtaparser[[:space:]]+ok' \
    "$work_dir/worker.tsv"; then
    printf '%s\n' "dtaparser did not load and save the Stata-generated file" >&2
    exit 1
fi

DTAPARSER_BENCH_LIB="$benchmark_library" R_ENVIRON_USER=/dev/null \
R_PROFILE_USER=/dev/null Rscript --vanilla -e '
    .libPaths(c(Sys.getenv("DTAPARSER_BENCH_LIB"), .libPaths()))
    before <- dtaparser::read_dta(commandArgs(TRUE)[[1L]], use_numeric_altrep = FALSE)
    after <- dtaparser::read_dta(commandArgs(TRUE)[[2L]], use_numeric_altrep = FALSE)
    storage <- vapply(before, function(column) {
        type <- attr(column, "stata.storage", exact = TRUE)
        if (is.null(type)) "string" else type
    }, character(1L))
    expected <- c(byte = 4L, int = 4L, long = 9L, float = 4L,
                  double = 9L, string = 10L)
    stopifnot(
        identical(as.integer(table(factor(storage, levels = names(expected)))),
                  unname(expected)),
        identical(before, after)
    )
' "$work_dir/input.dta" "$work_dir/output.dta"

printf '%s\n' "Stata-first primary write workflow: PASS"
