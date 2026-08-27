#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
target_dir="$checkout_root/target/large-scale"
R_ENVIRON_USER=/dev/null
R_PROFILE_USER=/dev/null
export R_ENVIRON_USER R_PROFILE_USER
iterations=${1:-101}
write_iterations=${2:-7}

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
case "$write_iterations" in
    ''|*[!0-9]*)
        printf '%s\n' "write iterations must be a positive integer" >&2
        exit 2
        ;;
esac
if [ "$write_iterations" -lt 1 ]; then
    printf '%s\n' "write iterations must be a positive integer" >&2
    exit 2
fi
if test -z "${STATA_BIN:-}" && test -x /Applications/Stata/StataMP.app/Contents/MacOS/stata-mp; then
    STATA_BIN=/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp
    export STATA_BIN
fi

mkdir -p "$target_dir"
base="$target_dir/base.dta"
manifest="$target_dir/datasets.tsv"
staged_manifest="$target_dir/.datasets.tsv.$$"
build_dir="$target_dir/.build.$$"
run_stage="$target_dir/.run.$$"
runs_dir="$target_dir/runs"
benchmark_library="$target_dir/library"
build_provenance="$benchmark_library/dtaparser-benchmark-provenance.tsv"
trap 'rm -rf "$build_dir" "$run_stage"; rm -f "$staged_manifest" "$staged_manifest.partial"' EXIT HUP INT TERM

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

rm -rf "$benchmark_library"
mkdir -p "$benchmark_library"
R CMD INSTALL --library="$benchmark_library" "$source_tarball"

package_source_after=$(Rscript --vanilla -e \
    'source(commandArgs(TRUE)[[1L]]); cat(benchmark_tree_digest(commandArgs(TRUE)[[2L]], "r-package/dtaparser"))' \
    "$script_dir/provenance.R" "$checkout_root")
if [ "$package_source_before" != "$package_source_after" ]; then
    printf '%s\n' "package source changed during build or installation" >&2
    exit 1
fi
Rscript --vanilla -e \
    'source(commandArgs(TRUE)[[1L]]); write_benchmark_provenance(commandArgs(TRUE)[[2L]], commandArgs(TRUE)[[3L]], commandArgs(TRUE)[[4L]], commandArgs(TRUE)[[5L]], commandArgs(TRUE)[[6L]])' \
    "$script_dir/provenance.R" "$checkout_root" "$benchmark_library" \
    "$build_provenance" "$package_source_before" "$source_tarball_sha256"
export DTAPARSER_BENCH_LIB="$benchmark_library"

Rscript --vanilla "$script_dir/generate-base.R" "$base"
python3 -B "$script_dir/scale-dta.py" \
    --base "$base" \
    --output "$target_dir/synthetic-100mb.dta" \
    --target-bytes 100000000 \
    --label 100mb \
    --manifest "$staged_manifest"
python3 -B "$script_dir/scale-dta.py" \
    --base "$base" \
    --output "$target_dir/synthetic-1gb.dta" \
    --target-bytes 1000000000 \
    --label 1gb \
    --manifest "$staged_manifest"
mv -f "$staged_manifest" "$manifest"

mkdir -p "$run_stage"
Rscript --vanilla "$script_dir/run.R" \
    "$manifest" "$run_stage/raw.tsv" "$iterations" \
    "$run_stage/run-provenance.tsv"
cp "$build_provenance" "$run_stage/build-provenance.tsv"
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

run_id=$(Rscript --vanilla -e \
    'x <- read.delim(commandArgs(TRUE)[[1L]], colClasses = "character", check.names = FALSE); cat(x$provenance_id[[1L]])' \
    "$run_stage/run-provenance.tsv")
run_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
run_name="$run_stamp-$(printf '%s' "$run_id" | cut -c1-16)-$$"
mkdir -p "$runs_dir"
completed_run="$runs_dir/$run_name"
mv "$run_stage" "$completed_run"
current_partial="$target_dir/.CURRENT.$$"
printf '%s\n' "runs/$run_name" > "$current_partial"
mv -f "$current_partial" "$target_dir/CURRENT"
rm -f "$target_dir/raw.tsv" "$target_dir/summary.tsv" \
    "$target_dir/run-provenance.tsv"
printf 'published %s\n' "$completed_run"
