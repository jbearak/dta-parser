#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
profile=${1:-quick}
repetitions=${2:-7}
case "$profile" in quick|full|india|all) ;; *) printf '%s\n' 'profile must be quick, full, india, or all' >&2; exit 2 ;; esac
case "$repetitions" in ''|*[!0-9]*) printf '%s\n' 'repetitions must be a positive integer' >&2; exit 2 ;; esac
if [ "$repetitions" -lt 1 ]; then printf '%s\n' 'repetitions must be a positive integer' >&2; exit 2; fi

target_dir="$checkout_root/target/projection-introspection"
build_dir="$target_dir/.build.$$"
run_dir="$target_dir/run-$profile-$(date -u '+%Y%m%dT%H%M%SZ')"
library="$build_dir/library"
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
mkdir -p "$build_dir" "$library" "$run_dir"

(cd "$build_dir" && R CMD build "$checkout_root/r-package/dtaparser")
set -- "$build_dir"/dtaparser_*.tar.gz
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    printf '%s\n' 'expected one dtaparser source tarball' >&2
    exit 1
fi
R CMD INSTALL --library="$library" "$1"
DTAPARSER_BENCH_LIB="$library"
export DTAPARSER_BENCH_LIB
R_ENVIRON_USER=/dev/null
R_PROFILE_USER=/dev/null
export R_ENVIRON_USER R_PROFILE_USER

Rscript --vanilla "$script_dir/run.R" "$profile" "$repetitions" "$run_dir"
printf '%s\n' "$run_dir"
