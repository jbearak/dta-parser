#!/bin/sh
set -eu
umask 077

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
checkout=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
cache_root=${AWW_CACHE_ROOT:-/opt/aww_cache}
max_files=${1:-}

if test -n "${CI:-}${GITHUB_ACTIONS:-}${GITHUB_RUN_ID:-}${GITHUB_WORKFLOW:-}"; then
    echo "the private DTA write qualification is manual and refuses CI" >&2
    exit 2
fi
for command in R Rscript; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "required command is unavailable: $command" >&2
        exit 2
    fi
done
if test -n "$max_files"; then
    case "$max_files" in
        *[!0-9]*|'') echo "MAX_FILES_PER_CORPUS must be a positive integer" >&2; exit 2 ;;
    esac
    if test "$max_files" -lt 1; then
        echo "MAX_FILES_PER_CORPUS must be a positive integer" >&2
        exit 2
    fi
fi
if ! Rscript --vanilla -e 'quit(status = !all(vapply(c("haven", "processx"), requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))))'; then
    echo "the R packages haven and processx are required" >&2
    exit 2
fi

run_root="$checkout/target/r-corpus-roundtrip"
mkdir -p "$run_root"
if test -n "${DTAPARSER_ROUNDTRIP_RUN_DIR:-}"; then
    run_dir=$DTAPARSER_ROUNDTRIP_RUN_DIR
else
    stamp=$(date -u '+%Y%m%dT%H%M%SZ')
    run_dir=$(mktemp -d "$run_root/$stamp-$$.XXXXXX")
fi
lock_dir="$run_dir.lock"
if ! mkdir "$lock_dir"; then
    echo "round-trip run directory is already active: $run_dir" >&2
    exit 2
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
trap 'exit 130' HUP INT TERM
build_dir="$run_dir/build"
library="$run_dir/library"
mkdir -p "$build_dir" "$library"

set -- "$build_dir"/dtaparser_*.tar.gz
if test "$#" -eq 1 && test -f "$1"; then
    source_tarball=$1
    if ! test -d "$library/dtaparser"; then
        R CMD INSTALL --library="$library" "$source_tarball"
    fi
elif test "$#" -eq 1 && test "$1" = "$build_dir/dtaparser_*.tar.gz" &&
     ! test -d "$library/dtaparser"; then
    (cd "$build_dir" && R CMD build "$checkout/r-package/dtaparser")
    set -- "$build_dir"/dtaparser_*.tar.gz
    if test "$#" -ne 1 || ! test -f "$1"; then
        echo "expected exactly one dtaparser source package" >&2
        exit 1
    fi
    source_tarball=$1
    R CMD INSTALL --library="$library" "$source_tarball"
else
    echo "run directory has an incomplete or ambiguous package build" >&2
    exit 1
fi

source_sha256=$(Rscript --vanilla -e \
    'source(commandArgs(TRUE)[[1L]]); cat(benchmark_file_sha256(commandArgs(TRUE)[[2L]]))' \
    "$script_dir/../benchmark-common.R" "$source_tarball")
export DTAPARSER_BENCH_LIB="$library"
export DTAPARSER_SOURCE_TARBALL="$source_tarball"
export DTAPARSER_SOURCE_SHA256="$source_sha256"
export R_ENVIRON_USER=/dev/null
export R_PROFILE_USER=/dev/null

if test -n "$max_files"; then
    Rscript --vanilla "$script_dir/run.R" qualify "$cache_root" "$run_dir" "$max_files"
    Rscript --vanilla "$script_dir/run.R" benchmark "$cache_root" "$run_dir" "$max_files"
else
    Rscript --vanilla "$script_dir/run.R" qualify "$cache_root" "$run_dir"
    Rscript --vanilla "$script_dir/run.R" benchmark "$cache_root" "$run_dir"
fi
printf 'published %s\n' "$run_dir"
