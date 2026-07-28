#!/bin/sh
set -eu
umask 077

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
raw_root="$checkout_root/target/fertility-surveys/raw"
builds_root="$raw_root/builds"
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
build_lock="$raw_root/.build-lock"
build_lock_token=
build_dir=
staged_bundle=
cleanup() {
    [ -z "$build_dir" ] || rm -rf "$build_dir"
    [ -z "$staged_bundle" ] || rm -rf "$staged_bundle"
    if [ -n "$build_lock_token" ]; then
        Rscript --vanilla "$script_dir/runtime.R" release-lock "$build_lock" "$build_lock_token" >/dev/null 2>&1 || true
    fi
    if [ -n "$owner_helper_pid" ]; then
        kill "$owner_helper_pid" >/dev/null 2>&1 || true
        wait "$owner_helper_pid" >/dev/null 2>&1 || true
    fi
    rm -rf "$run_tmp"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
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
    *' --family-id='*)
        Rscript --vanilla "$script_dir/merge.R" "$@"
        exit $?
        ;;
esac

if ! build_lock_token=$(Rscript --vanilla "$script_dir/runtime.R" acquire-lock-wait "$build_lock" "$owner_state"); then
    printf '%s\n' 'could not acquire fertility corpus build lock' >&2
    exit 1
fi

for package in haven openssl callr ps readr rlang tibble tidyselect; do
    Rscript --vanilla -e 'if (!requireNamespace(commandArgs(TRUE)[[1L]], quietly=TRUE)) quit(status=1)' "$package" || {
        printf '%s\n' "$package is required" >&2
        exit 1
    }
done

mkdir -p "$builds_root"
chmod 700 "$builds_root"
current_id=
if [ -f "$builds_root/CURRENT" ]; then
    current_id=$(tr -d '\r\n' < "$builds_root/CURRENT")
    case "$current_id" in
        ''|*[!0-9a-f]*) current_id= ;;
    esac
    [ "${#current_id}" -eq 64 ] || current_id=
fi
valid_install=false
if [ -n "$current_id" ]; then
    library="$builds_root/$current_id/library"
    provenance="$builds_root/$current_id/build-provenance.tsv"
    if [ -f "$provenance" ] && [ -d "$library/dtaparser" ]; then
        if Rscript --vanilla -e '
            source(commandArgs(TRUE)[[1L]]); source(commandArgs(TRUE)[[2L]]);
            fertility_verify_provenance(commandArgs(TRUE)[[3L]], commandArgs(TRUE)[[4L]], commandArgs(TRUE)[[5L]])
        ' "$script_dir/common.R" "$script_dir/provenance.R" "$checkout_root" "$library" "$provenance" >/dev/null 2>&1; then
            valid_install=true
        fi
    fi
fi

if [ "$valid_install" != true ]; then
    build_dir="$run_tmp/build"
    staged_bundle="$run_tmp/generation"
    staged_library="$staged_bundle/library"
    staged_provenance="$staged_bundle/build-provenance.tsv"
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
    current_id=$(Rscript --vanilla -e 'x <- read.delim(commandArgs(TRUE)[[1L]], colClasses="character", check.names=FALSE); cat(x$provenance_id[[1L]])' "$staged_provenance")
    generation="$builds_root/$current_id"
    if [ -e "$generation" ]; then
        printf '%s\n' 'immutable corpus build generation already exists but was not reusable' >&2
        exit 1
    fi
    mv "$staged_bundle" "$generation"
    staged_bundle=
    library="$generation/library"
    provenance="$generation/build-provenance.tsv"
    rm -rf "$build_dir"
    build_dir=
    current_tmp="$run_tmp/CURRENT"
    printf '%s\n' "$current_id" > "$current_tmp"
    chmod 600 "$current_tmp"
    mv -f "$current_tmp" "$builds_root/CURRENT"
fi

export DTAPARSER_FERTILITY_LIBRARY="$library"
export DTAPARSER_FERTILITY_PROVENANCE="$provenance"
framework_id=$(Rscript --vanilla "$script_dir/prepare.R")
export DTAPARSER_FERTILITY_FRAMEWORK_ID="$framework_id"
if ! Rscript --vanilla "$script_dir/runtime.R" release-lock "$build_lock" "$build_lock_token"; then
    printf '%s\n' 'could not release fertility corpus build lock' >&2
    exit 1
fi
build_lock_token=

export DTAPARSER_FERTILITY_OWNER_STATE="$owner_state"
Rscript --vanilla "$script_dir/run.R" "$@"
