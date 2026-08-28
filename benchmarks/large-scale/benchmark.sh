#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
target_dir="$checkout_root/target/large-scale"
. "$script_dir/benchmark-common.sh"
R_ENVIRON_USER=/dev/null
R_PROFILE_USER=/dev/null
export R_ENVIRON_USER R_PROFILE_USER
iterations=${1:-101}
write_iterations=${2:-7}

require_positive_integer "$iterations" "iterations"
require_positive_integer "$write_iterations" "write iterations"

mkdir -p "$target_dir"
manifest="$target_dir/datasets.tsv"
build_dir="$target_dir/.build.$$"
run_stage="$target_dir/.run.$$"
benchmark_library="$build_dir/library"
trap 'rm -rf "$build_dir" "$run_stage"' EXIT HUP INT TERM

build_dtaparser_library "$checkout_root" "$script_dir" "$build_dir"
export DTAPARSER_BENCH_LIB="$benchmark_library"

Rscript --vanilla "$script_dir/generate-stata-fixtures.R" \
    "$script_dir/stata-write-sizes.tsv" "$manifest"

mkdir -p "$run_stage"
Rscript --vanilla "$script_dir/run.R" \
    "$manifest" "$run_stage/raw.tsv" "$iterations" \
    "$run_stage/run-provenance.tsv"
Rscript --vanilla "$script_dir/summarize.R" \
    "$run_stage/raw.tsv" "$run_stage/summary.tsv" \
    "$run_stage/run-provenance.tsv"
Rscript --vanilla "$script_dir/write-run.R" \
    "$manifest" "$run_stage/write-raw.tsv" \
    "$run_stage/write-summary.tsv" "$run_stage/write-provenance.tsv" \
    "$write_iterations"
Rscript --vanilla "$script_dir/standard-r-write-run.R" \
    "$script_dir/standard-r-write-sizes.tsv" "$run_stage/r-write-raw.tsv" \
    "$run_stage/r-write-summary.tsv" "$run_stage/r-write-provenance.tsv" \
    "$write_iterations"

publish_benchmark_run \
    "$target_dir" "$run_stage" "$run_stage/run-provenance.tsv" \
    "runs" "CURRENT"
rm -f "$target_dir/raw.tsv" "$target_dir/summary.tsv" \
    "$target_dir/run-provenance.tsv"
