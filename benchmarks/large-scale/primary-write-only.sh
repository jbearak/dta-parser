#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
target_dir="$checkout_root/target/large-scale"
. "$script_dir/benchmark-common.sh"
iterations=${1:-7}

require_positive_integer "$iterations" "iterations"

R_ENVIRON_USER=/dev/null
R_PROFILE_USER=/dev/null
export R_ENVIRON_USER R_PROFILE_USER
mkdir -p "$target_dir"
manifest="$target_dir/datasets.tsv"
build_dir="$target_dir/.primary-write-build.$$"
run_stage="$target_dir/.run.$$"
library="$build_dir/library"
trap 'rm -rf "$build_dir" "$run_stage"' EXIT HUP INT TERM

build_dtaparser_library "$checkout_root" "$script_dir" "$build_dir"

export DTAPARSER_BENCH_LIB="$library"
Rscript --vanilla "$script_dir/generate-stata-fixtures.R" \
    "$script_dir/stata-write-sizes.tsv" "$manifest"
mkdir -p "$run_stage"
Rscript --vanilla "$script_dir/write-run.R" \
    "$manifest" "$run_stage/write-raw.tsv" \
    "$run_stage/write-summary.tsv" "$run_stage/write-provenance.tsv" \
    "$iterations"

publish_benchmark_run \
    "$target_dir" "$run_stage" "$run_stage/write-provenance.tsv" \
    "primary-write-runs" "PRIMARY_WRITE_CURRENT"
