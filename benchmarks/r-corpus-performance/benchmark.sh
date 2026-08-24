#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
checkout=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
cache_root=${AWW_CACHE_ROOT:-/opt/aww_cache}
max_files=${1:-}
if test -z "${STATA_BIN:-}" && test -x /Applications/Stata/StataMP.app/Contents/MacOS/stata-mp; then
    STATA_BIN=/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp
    export STATA_BIN
fi

if test -n "${CI:-}${GITHUB_ACTIONS:-}${GITHUB_RUN_ID:-}${GITHUB_WORKFLOW:-}"; then
    echo "the private corpus benchmark is manual and refuses CI" >&2
    exit 2
fi
if test -n "$max_files"; then
    case "$max_files" in
        *[!0-9]*|'') echo "MAX_FILES_PER_CORPUS must be a positive integer" >&2; exit 2 ;;
    esac
    if test "$max_files" -lt 1; then
        echo "MAX_FILES_PER_CORPUS must be a positive integer" >&2
        exit 2
    fi
fi

stamp=$(date -u '+%Y%m%dT%H%M%SZ')
run_dir="$checkout/target/r-corpus-performance/$stamp"
build_dir="$run_dir/build"
library="$run_dir/library"
mkdir -p "$build_dir" "$library"

(
    cd "$build_dir"
    R CMD build "$checkout/r-package/dtaparser"
)
set -- "$build_dir"/dtaparser_*.tar.gz
if test "$#" -ne 1 || ! test -f "$1"; then
    echo "expected exactly one dtaparser source package" >&2
    exit 1
fi
R CMD INSTALL --library="$library" "$1"

export DTAPARSER_BENCH_LIB="$library"
export R_ENVIRON_USER=/dev/null
export R_PROFILE_USER=/dev/null
if test -n "$max_files"; then
    Rscript --vanilla "$script_dir/run.R" "$cache_root" "$run_dir" "$max_files"
else
    Rscript --vanilla "$script_dir/run.R" "$cache_root" "$run_dir"
fi
printf 'published %s\n' "$run_dir"
