#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
target_dir="$checkout_root/target/large-scale"
iterations=${1:-7}
reference_run=${2:-}

case "$iterations" in
    ''|*[!0-9]*)
        printf '%s\n' "iterations must be a positive integer" >&2
        exit 2
        ;;
esac
if [ "$iterations" -lt 1 ]; then
    printf '%s\n' "iterations must be a positive integer" >&2
    exit 2
fi
if [ -z "$reference_run" ]; then
    if [ ! -f "$target_dir/CURRENT" ]; then
        printf '%s\n' "pass the prior complete run directory" >&2
        exit 2
    fi
    IFS= read -r reference_relative < "$target_dir/CURRENT"
    reference_run="$target_dir/$reference_relative"
fi
reference_run=$(CDPATH= cd -- "$reference_run" && pwd)
for file in write-raw.tsv write-summary.tsv write-provenance.tsv; do
    if [ ! -f "$reference_run/$file" ]; then
        printf 'reference run is missing %s\n' "$file" >&2
        exit 2
    fi
done

manifest="$target_dir/datasets.tsv"
for file in "$manifest" "$target_dir/synthetic-100mb.dta" \
    "$target_dir/synthetic-1gb.dta"; do
    if [ ! -f "$file" ]; then
        printf 'existing synthetic input is missing: %s\n' "$file" >&2
        exit 2
    fi
done

R_ENVIRON_USER=/dev/null
R_PROFILE_USER=/dev/null
export R_ENVIRON_USER R_PROFILE_USER
build_dir="$target_dir/.dtaparser-write-build.$$"
run_stage="$target_dir/.run.$$"
library="$target_dir/dtaparser-write-library"
build_provenance="$library/dtaparser-benchmark-provenance.tsv"
trap 'rm -rf "$build_dir" "$run_stage"' EXIT HUP INT TERM

package_source_before=$(Rscript --vanilla -e \
    'source(commandArgs(TRUE)[[1L]]); cat(benchmark_tree_digest(commandArgs(TRUE)[[2L]], "r-package/dtaparser"))' \
    "$script_dir/provenance.R" "$checkout_root")
mkdir -p "$build_dir"
(
    cd "$build_dir"
    R CMD build "$checkout_root/r-package/dtaparser"
)
set -- "$build_dir"/dtaparser_*.tar.gz
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
    printf '%s\n' "expected exactly one dtaparser source tarball" >&2
    exit 1
fi
source_tarball="$1"
source_tarball_sha256=$(Rscript --vanilla -e \
    'cat(tolower(unname(tools::sha256sum(commandArgs(TRUE)[[1L]]))))' \
    "$source_tarball")

rm -rf "$library"
mkdir -p "$library"
R CMD INSTALL --library="$library" "$source_tarball"
package_source_after=$(Rscript --vanilla -e \
    'source(commandArgs(TRUE)[[1L]]); cat(benchmark_tree_digest(commandArgs(TRUE)[[2L]], "r-package/dtaparser"))' \
    "$script_dir/provenance.R" "$checkout_root")
if [ "$package_source_before" != "$package_source_after" ]; then
    printf '%s\n' "package source changed during build or installation" >&2
    exit 1
fi
Rscript --vanilla -e \
    'source(commandArgs(TRUE)[[1L]]); write_benchmark_provenance(commandArgs(TRUE)[[2L]], commandArgs(TRUE)[[3L]], commandArgs(TRUE)[[4L]], commandArgs(TRUE)[[5L]], commandArgs(TRUE)[[6L]])' \
    "$script_dir/provenance.R" "$checkout_root" "$library" \
    "$build_provenance" "$package_source_before" "$source_tarball_sha256"

export DTAPARSER_BENCH_LIB="$library"
export DTAPARSER_WRITE_WRITERS=dtaparser
mkdir -p "$run_stage"
Rscript --vanilla "$script_dir/write-run.R" \
    "$manifest" "$run_stage/write-raw.tsv" \
    "$run_stage/write-summary.tsv" "$run_stage/write-provenance.tsv" \
    "$iterations"
cp "$build_provenance" "$run_stage/build-provenance.tsv"
cp "$reference_run/write-provenance.tsv" \
    "$run_stage/reference-write-provenance.tsv"
Rscript --vanilla "$script_dir/combine-write-summary.R" \
    "$run_stage/write-raw.tsv" "$run_stage/write-summary.tsv" \
    "$run_stage/write-provenance.tsv" "$reference_run/write-raw.tsv" \
    "$reference_run/write-summary.tsv" \
    "$reference_run/write-provenance.tsv" \
    "$run_stage/comparison-summary.tsv"

provenance_id=$(Rscript --vanilla -e \
    'x <- read.delim(commandArgs(TRUE)[[1L]], colClasses = "character", check.names = FALSE); cat(x$provenance_id[[1L]])' \
    "$run_stage/write-provenance.tsv")
run_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
run_name="$run_stamp-$(printf '%s' "$provenance_id" | cut -c1-16)-$$"
runs_dir="$target_dir/dtaparser-write-runs"
mkdir -p "$runs_dir"
completed_run="$runs_dir/$run_name"
mv "$run_stage" "$completed_run"
current_partial="$target_dir/.DTAPARSER_WRITE_CURRENT.$$"
printf '%s\n' "dtaparser-write-runs/$run_name" > "$current_partial"
mv -f "$current_partial" "$target_dir/DTAPARSER_WRITE_CURRENT"
printf 'published %s\n' "$completed_run"
