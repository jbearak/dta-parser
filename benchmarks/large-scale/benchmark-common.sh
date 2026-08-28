require_positive_integer() (
    value=$1
    name=$2
    case "$value" in
        ''|*[!0-9]*)
            printf '%s must be a positive integer\n' "$name" >&2
            exit 2
            ;;
    esac
    if [ "$value" -lt 1 ]; then
        printf '%s must be a positive integer\n' "$name" >&2
        exit 2
    fi
)

build_dtaparser_library() (
    checkout_root=$1
    script_dir=$2
    build_dir=$3
    library="$build_dir/library"
    provenance="$library/dtaparser-benchmark-provenance.tsv"

    source_before=$(Rscript --vanilla -e \
        'source(commandArgs(TRUE)[[1L]]); source(commandArgs(TRUE)[[2L]]); cat(benchmark_tree_digest(commandArgs(TRUE)[[3L]], "r-package/dtaparser"))' \
        "$script_dir/../benchmark-common.R" \
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
    tarball=$1
    tarball_sha256=$(Rscript --vanilla -e \
        'source(commandArgs(TRUE)[[1L]]); cat(benchmark_file_sha256(commandArgs(TRUE)[[2L]]))' \
        "$script_dir/../benchmark-common.R" "$tarball")

    rm -rf "$library"
    mkdir -p "$library"
    R CMD INSTALL --library="$library" "$tarball"
    source_after=$(Rscript --vanilla -e \
        'source(commandArgs(TRUE)[[1L]]); source(commandArgs(TRUE)[[2L]]); cat(benchmark_tree_digest(commandArgs(TRUE)[[3L]], "r-package/dtaparser"))' \
        "$script_dir/../benchmark-common.R" \
        "$script_dir/provenance.R" "$checkout_root")
    if [ "$source_before" != "$source_after" ]; then
        printf '%s\n' "package source changed during build or installation" >&2
        exit 1
    fi
    Rscript --vanilla -e \
        'source(commandArgs(TRUE)[[1L]]); source(commandArgs(TRUE)[[2L]]); write_benchmark_provenance(commandArgs(TRUE)[[3L]], commandArgs(TRUE)[[4L]], commandArgs(TRUE)[[5L]], commandArgs(TRUE)[[6L]], commandArgs(TRUE)[[7L]])' \
        "$script_dir/../benchmark-common.R" \
        "$script_dir/provenance.R" "$checkout_root" \
        "$library" "$provenance" "$source_before" "$tarball_sha256"
)

publish_benchmark_run() (
    target_dir=$1
    run_stage=$2
    provenance=$3
    runs_name=$4
    current_name=$5
    build_provenance="$DTAPARSER_BENCH_LIB/dtaparser-benchmark-provenance.tsv"

    cp "$build_provenance" "$run_stage/build-provenance.tsv"
    provenance_id=$(Rscript --vanilla -e \
        'x <- read.delim(commandArgs(TRUE)[[1L]], colClasses = "character", check.names = FALSE); cat(x$provenance_id[[1L]])' \
        "$provenance")
    run_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
    run_name="$run_stamp-$(printf '%s' "$provenance_id" | cut -c1-16)-$$"
    runs_dir="$target_dir/$runs_name"
    mkdir -p "$runs_dir"
    completed_run="$runs_dir/$run_name"
    mv "$run_stage" "$completed_run"
    current_partial="$target_dir/.$current_name.$$"
    printf '%s\n' "$runs_name/$run_name" > "$current_partial"
    mv -f "$current_partial" "$target_dir/$current_name"
    printf 'published %s\n' "$completed_run"
)
