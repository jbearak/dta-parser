#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
target_dir="$checkout_root/target/large-scale"
. "$script_dir/benchmark-common.sh"
iterations=${1:-7}

require_positive_integer "$iterations" "iterations"

sizes="$script_dir/standard-r-write-sizes.tsv"
if [ ! -f "$sizes" ]; then
    printf 'standard-R size specification is missing: %s\n' "$sizes" >&2
    exit 2
fi

R_ENVIRON_USER=/dev/null
R_PROFILE_USER=/dev/null
TZ=UTC
export R_ENVIRON_USER R_PROFILE_USER TZ
build_dir="$target_dir/.standard-r-write-build.$$"
run_stage="$target_dir/.run.$$"
library="$build_dir/library"
trap 'rm -rf "$build_dir" "$run_stage"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

build_dtatools_library "$checkout_root" "$script_dir" "$build_dir"

export DTATOOLS_BENCH_LIB="$library"
mkdir -p "$run_stage"
Rscript --vanilla "$script_dir/standard-r-write-run.R" \
    "$sizes" "$run_stage/r-write-raw.tsv" \
    "$run_stage/r-write-summary.tsv" "$run_stage/r-write-provenance.tsv" \
    "$iterations"

publish_benchmark_run \
    "$target_dir" "$run_stage" "$run_stage/r-write-provenance.tsv" \
    "standard-r-write-runs" "STANDARD_R_WRITE_CURRENT"
