#!/bin/sh
set -eu

root=rust/dta-parser
mirror=r-package/dtaparser/src/vendor/dta-parser
archive=r-package/dtaparser/src/rust/vendor.tar.gz
integrity=r-package/dtaparser/src/rust/vendor.sha256

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

for source in "$root"/src/*.rs; do
  relative=${source#"$root"/}
  cmp "$source" "$mirror/$relative"
done
cmp "$root/README.md" "$mirror/README.md"
cmp "$root/LICENSE" "$mirror/LICENSE"
cmp Cargo.lock "$mirror/Cargo.lock"

expected_archive=$(awk '$2 == "vendor.tar.gz" { print $1 }' "$integrity")
expected_listing=$(awk '$2 == "vendor-file-list" { print $1 }' "$integrity")
actual_archive=$(sha256_file "$archive")
actual_listing=$(tar -tzf "$archive" | LC_ALL=C sort | sha256_file /dev/stdin)

test -n "$expected_archive"
test -n "$expected_listing"
test "$actual_archive" = "$expected_archive"
test "$actual_listing" = "$expected_listing"

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
tar -xzf "$archive" -C "$temporary"
test -f "$temporary/v/encoding_rs/.cargo-checksum.json"
test -f "$temporary/v/serde/.cargo-checksum.json"

echo "rust sync: PASS (root/mirror sources, Cargo lock, vendor archive identity)"
