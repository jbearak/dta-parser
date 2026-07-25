#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname -- "$script_dir")
crate="$root/rust/dta-parser"
mirror="$root/r-package/dtaparser/src/vendor/dta-parser"
archive="$root/r-package/dtaparser/src/rust/vendor.tar.gz"
integrity="$root/r-package/dtaparser/src/rust/vendor.sha256"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
root_manifest="$temporary/root-rust-sources"
mirror_manifest="$temporary/mirror-rust-sources"

(cd "$crate" && find src -type f -name '*.rs' -print | LC_ALL=C sort) > "$root_manifest"
(cd "$mirror" && find src -type f -name '*.rs' -print | LC_ALL=C sort) > "$mirror_manifest"
cmp "$root_manifest" "$mirror_manifest"
while IFS= read -r relative; do
  cmp "$crate/$relative" "$mirror/$relative"
done < "$root_manifest"

cmp "$crate/README.md" "$mirror/README.md"
cmp "$crate/LICENSE" "$mirror/LICENSE"
cmp "$root/Cargo.lock" "$mirror/Cargo.lock"

expected_archive=$(awk '$2 == "vendor.tar.gz" { print $1 }' "$integrity")
expected_listing=$(awk '$2 == "vendor-file-list" { print $1 }' "$integrity")
actual_archive=$(sha256_file "$archive")
actual_listing=$(tar -tzf "$archive" | LC_ALL=C sort | sha256_file /dev/stdin)

test -n "$expected_archive"
test -n "$expected_listing"
test "$actual_archive" = "$expected_archive"
test "$actual_listing" = "$expected_listing"

vendor_extract="$temporary/vendor"
mkdir "$vendor_extract"
tar -xzf "$archive" -C "$vendor_extract"
test -f "$vendor_extract/v/encoding_rs/.cargo-checksum.json"
test -f "$vendor_extract/v/serde/.cargo-checksum.json"

echo "rust sync: PASS (symmetric recursive sources, Cargo lock, vendor archive identity)"
