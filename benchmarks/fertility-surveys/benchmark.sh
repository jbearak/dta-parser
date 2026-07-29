#!/bin/sh
set -eu
umask 077

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
checkout_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
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

ensure_direct_directory() {
    ensure_direct_directory_parent=$1
    ensure_direct_directory_child=$2
    if [ -L "$ensure_direct_directory_parent" ] ||
       [ -L "$ensure_direct_directory_child" ] ||
       [ ! -d "$ensure_direct_directory_parent" ]; then
        printf '%s\n' 'fertility output paths must not contain symlinks' >&2
        exit 2
    fi
    if [ ! -d "$ensure_direct_directory_child" ]; then
        mkdir "$ensure_direct_directory_child"
    fi
    ensure_direct_directory_parent_canonical=$(
        CDPATH= cd -- "$ensure_direct_directory_parent" && pwd -P
    )
    ensure_direct_directory_child_canonical=$(
        CDPATH= cd -- "$ensure_direct_directory_child" && pwd -P
    )
    if [ "$ensure_direct_directory_child_canonical" != \
         "$ensure_direct_directory_parent_canonical/$(basename -- "$ensure_direct_directory_child")" ]; then
        printf '%s\n' 'fertility outputs must remain in the checkout-local raw root' >&2
        exit 2
    fi
}

assert_direct_directory() {
    assert_direct_directory_parent=$1
    assert_direct_directory_child=$2
    assert_direct_directory_label=$3
    if [ -L "$assert_direct_directory_parent" ] ||
       [ -L "$assert_direct_directory_child" ] ||
       [ ! -d "$assert_direct_directory_parent" ] ||
       [ ! -d "$assert_direct_directory_child" ]; then
        printf '%s\n' "$assert_direct_directory_label must be a direct non-symlink directory" >&2
        exit 2
    fi
    assert_direct_directory_parent_canonical=$(
        CDPATH= cd -- "$assert_direct_directory_parent" && pwd -P
    )
    assert_direct_directory_child_canonical=$(
        CDPATH= cd -- "$assert_direct_directory_child" && pwd -P
    )
    if [ "$assert_direct_directory_parent_canonical" != \
         "$assert_direct_directory_parent" ] ||
       [ "$assert_direct_directory_child_canonical" != \
         "$assert_direct_directory_parent_canonical/$(basename -- "$assert_direct_directory_child")" ] ||
       [ "$(dirname -- "$assert_direct_directory_child")" != \
         "$assert_direct_directory_parent" ]; then
        printf '%s\n' "$assert_direct_directory_label escaped its canonical parent" >&2
        exit 2
    fi
}

assert_direct_file() {
    assert_direct_file_parent=$1
    assert_direct_file_child=$2
    assert_direct_file_label=$3
    assert_direct_directory \
        "$(dirname -- "$assert_direct_file_parent")" \
        "$assert_direct_file_parent" \
        "$assert_direct_file_label parent"
    if [ -L "$assert_direct_file_child" ] ||
       [ ! -f "$assert_direct_file_child" ] ||
       [ -d "$assert_direct_file_child" ] ||
       [ "$(dirname -- "$assert_direct_file_child")" != \
         "$assert_direct_file_parent" ]; then
        printf '%s\n' "$assert_direct_file_label must be a direct non-symlink file" >&2
        exit 2
    fi
}

atomic_move_noreplace() {
    atomic_move_noreplace_source_path=$1
    atomic_move_noreplace_destination_path=$2
    atomic_move_noreplace_label=$3
    command -v python3 >/dev/null 2>&1 || {
        printf '%s\n' 'python3 is required for atomic no-replace publication' >&2
        exit 1
    }
    if python3 - \
        "$atomic_move_noreplace_source_path" \
        "$atomic_move_noreplace_destination_path" <<'PY'
import ctypes
import errno
import os
import sys
src = os.fsencode(sys.argv[1])
dst = os.fsencode(sys.argv[2])
libc = ctypes.CDLL(None, use_errno=True)
if sys.platform == "darwin":
    fn = libc.renamex_np
    fn.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rc = fn(src, dst, 4)
else:
    fn = getattr(libc, "renameat2", None)
    if fn is None:
        sys.exit(18)
    fn.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
                   ctypes.c_char_p, ctypes.c_uint]
    rc = fn(-100, src, -100, dst, 1)
if rc != 0:
    value = ctypes.get_errno()
    sys.exit(17 if value in (errno.EEXIST, errno.ENOTEMPTY) else 19)
PY
    then
        return 0
    else
        atomic_move_noreplace_status=$?
        if [ "$atomic_move_noreplace_status" -eq 17 ]; then
            printf '%s\n' "$atomic_move_noreplace_label destination already exists" >&2
            exit 2
        fi
        printf '%s\n' \
            "atomic no-replace publication failed for $atomic_move_noreplace_label" >&2
        exit 1
    fi
}

for output_component in \
    "$checkout_root" \
    "$checkout_root/target" \
    "$checkout_root/target/fertility-surveys" \
    "$raw_root" \
    "$raw_root/tmp"
do
    if [ -L "$output_component" ]; then
        printf '%s\n' 'fertility output paths must not contain symlinks' >&2
        exit 2
    fi
done
ensure_direct_directory "$checkout_root" "$checkout_root/target"
ensure_direct_directory "$checkout_root/target" "$checkout_root/target/fertility-surveys"
ensure_direct_directory "$checkout_root/target/fertility-surveys" "$raw_root"
ensure_direct_directory "$raw_root" "$raw_root/tmp"
raw_canonical=$(CDPATH= cd -- "$raw_root" && pwd -P)
tmp_canonical=$(CDPATH= cd -- "$raw_root/tmp" && pwd -P)
if [ "$raw_canonical" != "$raw_root" ] || [ "$tmp_canonical" != "$raw_root/tmp" ]; then
    printf '%s\n' 'fertility outputs must remain in the checkout-local raw root' >&2
    exit 2
fi
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
export DTAPARSER_FERTILITY_OWNER_STATE="$owner_state"

case " $* " in
    *' --inventory-only '*)
        Rscript --vanilla "$script_dir/run.R" "$@"
        exit $?
        ;;
    *' --capture-accepted-current-hashes '*)
        [ "$#" -eq 1 ] || {
            printf '%s\n' 'accepted-current-hash capture takes no other options' >&2
            exit 2
        }
        Rscript --vanilla "$script_dir/accepted.R" "$@"
        exit $?
        ;;
    *' --assessment-family-id='*)
        Rscript --vanilla "$script_dir/assessment.R" "$@"
        exit $?
        ;;
    *' --family-id='*)
        Rscript --vanilla "$script_dir/merge.R" "$@"
        exit $?
        ;;
    *' --republish-framework='*)
        Rscript --vanilla "$script_dir/republish.R" "$@"
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

ensure_direct_directory "$raw_root" "$builds_root"
assert_direct_directory "$raw_root" "$builds_root" 'builds root'
chmod 700 "$builds_root"
current_id=
current_pointer="$builds_root/CURRENT"
if [ -L "$current_pointer" ] || [ -d "$current_pointer" ]; then
    printf '%s\n' 'build CURRENT must be a direct non-symlink file' >&2
    exit 2
fi
if [ -f "$current_pointer" ]; then
    assert_direct_file "$builds_root" "$current_pointer" 'build CURRENT'
    current_id=$(tr -d '\r\n' < "$current_pointer")
    case "$current_id" in
        ''|*[!0-9a-f]*) current_id= ;;
    esac
    [ "${#current_id}" -eq 64 ] || current_id=
fi
valid_install=false
if [ -n "$current_id" ]; then
    generation="$builds_root/$current_id"
    library="$generation/library"
    provenance="$generation/build-provenance.tsv"
    package_dir="$library/dtaparser"
    assert_direct_directory "$builds_root" "$generation" 'selected build generation'
    assert_direct_directory "$generation" "$library" 'selected build library'
    assert_direct_file "$generation" "$provenance" 'selected build provenance'
    assert_direct_directory "$library" "$package_dir" 'selected dtaparser package'
    if Rscript --vanilla -e '
            source(commandArgs(TRUE)[[1L]]); source(commandArgs(TRUE)[[2L]]);
            fertility_verify_provenance(commandArgs(TRUE)[[3L]], commandArgs(TRUE)[[4L]], commandArgs(TRUE)[[5L]])
        ' "$script_dir/common.R" "$script_dir/provenance.R" "$checkout_root" "$library" "$provenance" >/dev/null 2>&1; then
            valid_install=true
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
    assert_direct_directory "$raw_root" "$builds_root" 'builds root'
    if [ -e "$generation" ] || [ -L "$generation" ]; then
        printf '%s\n' 'immutable corpus build generation already exists but was not reusable' >&2
        exit 1
    fi
    if [ "$(dirname -- "$generation")" != "$builds_root" ]; then
        printf '%s\n' 'build generation escaped its canonical parent' >&2
        exit 2
    fi
    atomic_move_noreplace "$staged_bundle" "$generation" \
        'immutable corpus build generation'
    staged_bundle=
    library="$generation/library"
    provenance="$generation/build-provenance.tsv"
    rm -rf "$build_dir"
    build_dir=
    current_tmp="$run_tmp/CURRENT"
    printf '%s\n' "$current_id" > "$current_tmp"
    chmod 600 "$current_tmp"
    assert_direct_directory "$raw_root" "$builds_root" 'builds root'
    assert_direct_directory "$builds_root" "$generation" 'published build generation'
    assert_direct_directory "$generation" "$library" 'published build library'
    assert_direct_file "$generation" "$provenance" 'published build provenance'
    assert_direct_directory "$library" "$library/dtaparser" 'published dtaparser package'
    if [ -L "$current_pointer" ] || [ -d "$current_pointer" ]; then
        printf '%s\n' 'build CURRENT must be a direct non-symlink file' >&2
        exit 2
    fi
    [ ! -f "$current_pointer" ] || assert_direct_file "$builds_root" "$current_pointer" 'build CURRENT'
    mv -f "$current_tmp" "$current_pointer"
fi

assert_direct_directory "$raw_root" "$builds_root" 'builds root'
assert_direct_directory "$builds_root" "$generation" 'selected build generation'
assert_direct_directory "$generation" "$library" 'selected build library'
assert_direct_file "$generation" "$provenance" 'selected build provenance'
assert_direct_directory "$library" "$library/dtaparser" 'selected dtaparser package'
assert_direct_file "$builds_root" "$current_pointer" 'build CURRENT'
selected_current_id=$(tr -d '\r\n' < "$current_pointer")
if [ "$selected_current_id" != "$current_id" ]; then
    printf '%s\n' 'selected build CURRENT changed before framework preparation' >&2
    exit 2
fi

export DTAPARSER_FERTILITY_LIBRARY="$library"
export DTAPARSER_FERTILITY_PROVENANCE="$provenance"
framework_id=$(Rscript --vanilla "$script_dir/prepare.R" "$@")
export DTAPARSER_FERTILITY_FRAMEWORK_ID="$framework_id"
if ! Rscript --vanilla "$script_dir/runtime.R" release-lock "$build_lock" "$build_lock_token"; then
    printf '%s\n' 'could not release fertility corpus build lock' >&2
    exit 1
fi
build_lock_token=

Rscript --vanilla "$script_dir/run.R" "$@"
