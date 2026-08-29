#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
target_dir="$checkout_root/target/large-scale"
. "$script_dir/benchmark-common.sh"
iterations=${1:-7}
reference_run=${2:-}

require_positive_integer "$iterations" "iterations"
if [ -z "$reference_run" ]; then
    if [ ! -f "$target_dir/PRIMARY_WRITE_CURRENT" ]; then
        printf '%s\n' "pass the prior complete run directory" >&2
        exit 2
    fi
    IFS= read -r reference_relative < "$target_dir/PRIMARY_WRITE_CURRENT"
    reference_run="$target_dir/$reference_relative"
fi
reference_run=$(CDPATH= cd -- "$reference_run" && pwd)
for file in write-raw.tsv write-summary.tsv write-provenance.tsv \
    write-validation.tsv; do
    if [ ! -f "$reference_run/$file" ]; then
        printf 'reference run is missing %s\n' "$file" >&2
        exit 2
    fi
done

manifest="$target_dir/datasets.tsv"
if [ ! -f "$manifest" ]; then
    printf 'existing synthetic manifest is missing: %s\n' "$manifest" >&2
    exit 2
fi

R_ENVIRON_USER=/dev/null
R_PROFILE_USER=/dev/null
export R_ENVIRON_USER R_PROFILE_USER
build_dir="$target_dir/.dtatools-write-build.$$"
run_stage="$target_dir/.run.$$"
library="$build_dir/library"
trap 'rm -rf "$build_dir" "$run_stage"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

build_dtatools_library "$checkout_root" "$script_dir" "$build_dir"

export DTATOOLS_BENCH_LIB="$library"
export DTATOOLS_WRITE_WRITERS=dtatools
mkdir -p "$run_stage"
Rscript --vanilla "$script_dir/write-run.R" \
    "$manifest" "$run_stage/write-raw.tsv" \
    "$run_stage/write-summary.tsv" "$run_stage/write-provenance.tsv" \
    "$iterations"
cp "$reference_run/write-provenance.tsv" \
    "$run_stage/reference-write-provenance.tsv"
cp "$reference_run/write-validation.tsv" \
    "$run_stage/reference-write-validation.tsv"
Rscript --vanilla "$script_dir/combine-write-summary.R" \
    "$run_stage/write-raw.tsv" "$run_stage/write-summary.tsv" \
    "$run_stage/write-provenance.tsv" "$run_stage/write-validation.tsv" \
    "$reference_run/write-raw.tsv" \
    "$reference_run/write-summary.tsv" \
    "$reference_run/write-provenance.tsv" \
    "$reference_run/write-validation.tsv" \
    "$run_stage/comparison-summary.tsv"

publish_benchmark_run \
    "$target_dir" "$run_stage" "$run_stage/write-provenance.tsv" \
    "dtatools-write-runs" "DTATOOLS_WRITE_CURRENT"
