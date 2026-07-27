#!/bin/sh
set -eu
umask 077

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
raw_root="$checkout_root/target/fertility-surveys/raw"
library="$raw_root/library"
provenance="$raw_root/build-provenance.tsv"
export R_ENVIRON_USER=/dev/null
export R_PROFILE_USER=/dev/null

if [ "${CI:-}" ] || [ "${GITHUB_ACTIONS:-}" ] || [ "${GITHUB_RUN_ID:-}" ] || [ "${GITHUB_WORKFLOW:-}" ]; then
    printf '%s\n' 'fertility corpus runs are refused in CI and GitHub Actions' >&2
    exit 2
fi
if [ "${DTAPARSER_FERTILITY_CORPUS:-}" != 'I_UNDERSTAND_THIS_READS_PROPRIETARY_DATA' ]; then
    printf '%s\n' 'manual opt-in required: set DTAPARSER_FERTILITY_CORPUS=I_UNDERSTAND_THIS_READS_PROPRIETARY_DATA' >&2
    exit 2
fi

mkdir -p "$raw_root/tmp"
chmod 700 "$raw_root" "$raw_root/tmp"
run_tmp=$(mktemp -d "$raw_root/tmp/run.XXXXXX")
chmod 700 "$run_tmp"
export TMPDIR="$run_tmp"
owner_state="$run_tmp/.orchestrator"
owner_helper_pid=
lock_dir="$raw_root/.run-lock"
lock_token=
build_dir=
staged_library=
staged_provenance=
cleanup() {
    [ -z "$build_dir" ] || rm -rf "$build_dir"
    [ -z "$staged_library" ] || rm -rf "$staged_library"
    [ -z "$staged_provenance" ] || rm -f "$staged_provenance"
    if [ -n "$lock_token" ]; then
        Rscript --vanilla "$script_dir/runtime.R" release-lock "$lock_dir" "$lock_token" >/dev/null 2>&1 || true
    fi
    if [ -n "$owner_helper_pid" ]; then
        kill "$owner_helper_pid" >/dev/null 2>&1 || true
        wait "$owner_helper_pid" >/dev/null 2>&1 || true
    fi
    rm -rf "$run_tmp"
}
trap cleanup EXIT HUP INT TERM
Rscript --vanilla -e 'if (!requireNamespace("ps", quietly=TRUE)) quit(status=1)' || {
    printf '%s\n' 'ps is required' >&2
    exit 1
}
Rscript --vanilla "$script_dir/runtime.R" hold-owner "$owner_state" "$$" &
owner_helper_pid=$!
owner_ready=false
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if [ -f "$owner_state/owner.tsv" ]; then
        owner_ready=true
        break
    fi
    kill -0 "$owner_helper_pid" >/dev/null 2>&1 || break
    sleep 0.05
done
if [ "$owner_ready" != true ]; then
    printf '%s\n' 'could not initialize fertility corpus owner process' >&2
    exit 1
fi
Rscript --vanilla "$script_dir/runtime.R" write-temp-owner "$run_tmp" "$owner_state"
Rscript --vanilla "$script_dir/runtime.R" clean-temp "$raw_root/tmp" "$run_tmp"

case " $* " in
    *' --inventory-only '*)
        Rscript --vanilla "$script_dir/run.R" "$@"
        exit $?
        ;;
esac

if ! lock_token=$(Rscript --vanilla "$script_dir/runtime.R" acquire-lock "$lock_dir" "$owner_state"); then
    printf '%s\n' 'another fertility corpus build or run is active' >&2
    exit 1
fi

for package in haven openssl callr ps readr rlang tibble tidyselect; do
    Rscript --vanilla -e 'if (!requireNamespace(commandArgs(TRUE)[[1L]], quietly=TRUE)) quit(status=1)' "$package" || {
        printf '%s\n' "$package is required" >&2
        exit 1
    }
done

valid_install=false
if [ -f "$provenance" ] && [ -d "$library/dtaparser" ]; then
    if Rscript --vanilla -e '
        source(commandArgs(TRUE)[[1L]]); source(commandArgs(TRUE)[[2L]]);
        fertility_verify_provenance(commandArgs(TRUE)[[3L]], commandArgs(TRUE)[[4L]], commandArgs(TRUE)[[5L]])
    ' "$script_dir/common.R" "$script_dir/provenance.R" "$checkout_root" "$library" "$provenance" >/dev/null 2>&1; then
        valid_install=true
    fi
fi

if [ "$valid_install" != true ]; then
    build_dir="$raw_root/.build.$$"
    staged_library="$raw_root/.library.$$"
    staged_provenance="$raw_root/.build-provenance.tsv.$$"
    package_source_before=$(Rscript --vanilla -e '
        source(commandArgs(TRUE)[[1L]]); source(commandArgs(TRUE)[[2L]]);
        cat(fertility_tree_digest(commandArgs(TRUE)[[3L]], "r-package/dtaparser"))
    ' "$script_dir/common.R" "$script_dir/provenance.R" "$checkout_root")
    mkdir -p "$build_dir" "$staged_library"
    (
        cd "$build_dir"
        R CMD build "$checkout_root/r-package/dtaparser"
    )
    tarball=
    tarball_count=0
    for candidate in "$build_dir"/dtaparser_*.tar.gz; do
        if [ -f "$candidate" ]; then
            tarball=$candidate
            tarball_count=$((tarball_count + 1))
        fi
    done
    if [ "$tarball_count" -ne 1 ]; then
        printf '%s\n' 'expected exactly one dtaparser source tarball' >&2
        exit 1
    fi
    tarball_sha256=$(Rscript --vanilla -e 'cat(tolower(unname(tools::sha256sum(commandArgs(TRUE)[[1L]]))))' "$tarball")
    R CMD INSTALL --library="$staged_library" "$tarball"
    package_source_after=$(Rscript --vanilla -e '
        source(commandArgs(TRUE)[[1L]]); source(commandArgs(TRUE)[[2L]]);
        cat(fertility_tree_digest(commandArgs(TRUE)[[3L]], "r-package/dtaparser"))
    ' "$script_dir/common.R" "$script_dir/provenance.R" "$checkout_root")
    if [ "$package_source_before" != "$package_source_after" ]; then
        printf '%s\n' 'package source changed during build or installation' >&2
        exit 1
    fi
    Rscript --vanilla -e '
        source(commandArgs(TRUE)[[1L]]); source(commandArgs(TRUE)[[2L]]);
        fertility_write_provenance(commandArgs(TRUE)[[3L]], commandArgs(TRUE)[[4L]], commandArgs(TRUE)[[5L]], commandArgs(TRUE)[[6L]])
    ' "$script_dir/common.R" "$script_dir/provenance.R" "$checkout_root" "$staged_library" "$staged_provenance" "$tarball_sha256"
    rm -rf "$library"
    mv "$staged_library" "$library"
    # The recorded installed path changes from the staging name to library; regenerate
    # only after the atomic directory move.
    Rscript --vanilla -e '
        source(commandArgs(TRUE)[[1L]]); source(commandArgs(TRUE)[[2L]]);
        fertility_write_provenance(commandArgs(TRUE)[[3L]], commandArgs(TRUE)[[4L]], commandArgs(TRUE)[[5L]], commandArgs(TRUE)[[6L]])
    ' "$script_dir/common.R" "$script_dir/provenance.R" "$checkout_root" "$library" "$staged_provenance" "$tarball_sha256"
    mv -f "$staged_provenance" "$provenance"
    rm -rf "$build_dir"
    build_dir=
    staged_library=
    staged_provenance=
fi

Rscript --vanilla "$script_dir/run.R" "$@"
