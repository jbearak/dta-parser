#!/bin/sh
set -eu
umask 077

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
checkout=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
cache_root=${AWW_CACHE_ROOT:-/opt/aww_cache}
selection=${1:-full}
argument=${2:-}
second_argument=${3:-}

if test -n "${CI:-}${GITHUB_ACTIONS:-}${GITHUB_RUN_ID:-}${GITHUB_WORKFLOW:-}"; then
    echo "the private corpus verification is manual and refuses CI" >&2
    exit 2
fi
case "$selection" in
    full) test -z "$argument$second_argument" || { echo "full takes no argument" >&2; exit 2; } ;;
    from) test -n "$argument" && test -n "$second_argument" || { echo "from requires PREVIOUS_RUN and POSITION" >&2; exit 2; } ;;
    smallest) test -n "$argument" && test -z "$second_argument" || { echo "smallest requires one count" >&2; exit 2; } ;;
    id) test -n "$argument" && test -z "$second_argument" || { echo "id requires one stable corpus ID" >&2; exit 2; } ;;
    *) echo "usage: verify.sh [full | from PREVIOUS_RUN POSITION | smallest COUNT | id STABLE_ID]" >&2; exit 2 ;;
esac

run_root="$checkout/target/r-corpus-roundtrip-verification"
mkdir -p "$run_root"
stamp=$(date -u '+%Y%m%dT%H%M%SZ')
run_dir=$(mktemp -d "$run_root/$stamp-$$.XXXXXX")
build_dir="$run_dir/build"
library="$run_dir/library"
mkdir -p "$build_dir" "$library"

(cd "$build_dir" && R CMD build "$checkout/r-package/dtatools")
set -- "$build_dir"/dtatools_*.tar.gz
if test "$#" -ne 1 || ! test -f "$1"; then
    echo "expected exactly one dtatools source package" >&2
    exit 1
fi
R CMD INSTALL --library="$library" "$1"
export DTATOOLS_BENCH_LIB="$library"
export R_ENVIRON_USER=/dev/null
export R_PROFILE_USER=/dev/null

if test -n "$second_argument"; then
    Rscript --vanilla "$script_dir/verify.R" "$cache_root" "$run_dir" "$selection" "$argument" "$second_argument"
elif test -n "$argument"; then
    Rscript --vanilla "$script_dir/verify.R" "$cache_root" "$run_dir" "$selection" "$argument"
else
    Rscript --vanilla "$script_dir/verify.R" "$cache_root" "$run_dir" "$selection"
fi
printf 'published %s\n' "$run_dir"
