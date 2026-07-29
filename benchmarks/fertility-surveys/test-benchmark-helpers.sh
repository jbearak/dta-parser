#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
benchmark_script="$script_dir/benchmark.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/fertility-benchmark-helpers.XXXXXX")
test_root=$(CDPATH= cd -- "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
helper_definitions="$test_root/helpers.sh"

extract_function() {
    extract_function_name=$1
    awk -v signature="$extract_function_name() {" '
        $0 == signature { copying = 1 }
        copying { print }
        copying && $0 == "}" { exit }
    ' "$benchmark_script"
}

{
    extract_function assert_direct_directory
    extract_function assert_direct_file
} > "$helper_definitions"

if ! grep -q '^assert_direct_directory() {$' "$helper_definitions" ||
   ! grep -q '^assert_direct_file() {$' "$helper_definitions"; then
    printf '%s\n' 'could not extract benchmark path helper definitions' >&2
    exit 1
fi

run_assert_direct_file() {
    run_assert_direct_file_expected=$1
    run_assert_direct_file_name=$2
    run_assert_direct_file_parent=$3
    run_assert_direct_file_child=$4
    set +e
    /bin/sh -c '. "$1"; assert_direct_file "$2" "$3" "build CURRENT"' sh \
        "$helper_definitions" \
        "$run_assert_direct_file_parent" \
        "$run_assert_direct_file_child" \
        >"$test_root/$run_assert_direct_file_name.out" 2>&1
    run_assert_direct_file_status=$?
    set -e
    if [ "$run_assert_direct_file_status" -ne "$run_assert_direct_file_expected" ]; then
        printf '%s\n' \
            "$run_assert_direct_file_name: expected exit $run_assert_direct_file_expected, got $run_assert_direct_file_status" >&2
        command cat "$test_root/$run_assert_direct_file_name.out" >&2
        exit 1
    fi
}

canonical_root="$test_root/canonical"
canonical_builds="$canonical_root/builds"
mkdir -p "$canonical_builds"
printf '%s\n' 'canonical' > "$canonical_builds/CURRENT"
run_assert_direct_file 0 canonical \
    "$canonical_builds" "$canonical_builds/CURRENT"

symlink_root="$test_root/symlink-current"
mkdir -p "$symlink_root/builds"
printf '%s\n' 'outside' > "$symlink_root/outside"
ln -s "$symlink_root/outside" "$symlink_root/builds/CURRENT"
run_assert_direct_file 2 symlink-current \
    "$symlink_root/builds" "$symlink_root/builds/CURRENT"

directory_root="$test_root/directory-current"
mkdir -p "$directory_root/builds/CURRENT"
run_assert_direct_file 2 directory-current \
    "$directory_root/builds" "$directory_root/builds/CURRENT"

nonregular_root="$test_root/nonregular-current"
mkdir -p "$nonregular_root/builds"
mkfifo "$nonregular_root/builds/CURRENT"
run_assert_direct_file 2 nonregular-current \
    "$nonregular_root/builds" "$nonregular_root/builds/CURRENT"

symlinked_parent_root="$test_root/symlinked-parent"
mkdir -p "$symlinked_parent_root/real-builds"
printf '%s\n' 'canonical' > "$symlinked_parent_root/real-builds/CURRENT"
ln -s "$symlinked_parent_root/real-builds" "$symlinked_parent_root/builds"
run_assert_direct_file 2 symlinked-parent \
    "$symlinked_parent_root/builds" "$symlinked_parent_root/builds/CURRENT"

nondirect_parent_root="$test_root/nondirect-parent"
mkdir -p "$nondirect_parent_root/direct" "$nondirect_parent_root/builds"
printf '%s\n' 'canonical' > "$nondirect_parent_root/builds/CURRENT"
run_assert_direct_file 2 nondirect-parent \
    "$nondirect_parent_root/direct/../builds" \
    "$nondirect_parent_root/direct/../builds/CURRENT"
