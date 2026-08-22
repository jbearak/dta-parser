#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
package_root="$root/r-package/dtaparser"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

if test -n "${R_HOME:-}"; then
  rscript="$R_HOME/bin/Rscript"
else
  rscript=$(command -v Rscript)
fi

inputs=$(
  cd "$package_root"
  DTA_RUST_HASH_LIST_INPUTS=1 \
    "$rscript" --vanilla tools/rust-source-hash.R
)
fixture="$temporary/dtaparser"
for path in $inputs; do
  mkdir -p "$fixture/$(dirname -- "$path")"
  cp -R "$package_root/$path" "$fixture/$path"
done
cd "$fixture"

baseline=$("$rscript" --vanilla tools/rust-source-hash.R)
case "$baseline" in
  ''|*[!0-9a-f]*) echo "Rust source hash is malformed: $baseline" >&2; exit 1 ;;
esac
if test "${#baseline}" -ne 32; then
  echo "Rust source hash is malformed: $baseline" >&2
  exit 1
fi

source_file=src/rust/src/lib.rs
cp "$source_file" "$source_file.saved"
printf '\n' >> "$source_file"
changed=$("$rscript" --vanilla tools/rust-source-hash.R)
if test "$changed" = "$baseline"; then
  echo "Rust source hash ignored a source change" >&2
  exit 1
fi
mv "$source_file.saved" "$source_file"

real_rustc=$(command -v rustc)
mkdir fake-bin
cat > fake-bin/rustc <<'EOF'
#!/bin/sh
"$REAL_RUSTC" "$@"
printf '%s\n' 'test toolchain identity'
EOF
chmod +x fake-bin/rustc
toolchain_changed=$(
  REAL_RUSTC="$real_rustc" PATH="$PWD/fake-bin:$PATH" \
    "$rscript" --vanilla tools/rust-source-hash.R
)
if test "$toolchain_changed" = "$baseline"; then
  echo "Rust source hash ignored the toolchain identity" >&2
  exit 1
fi
rm -rf fake-bin

for path in $inputs; do
  case "$path" in
    tools/rust-source-hash.R|*/build.rs) continue ;;
  esac
  mv "$path" "$path.saved"
  if "$rscript" --vanilla tools/rust-source-hash.R >hash.out 2>hash.err; then
    echo "Rust source hash accepted missing input: $path" >&2
    exit 1
  fi
  grep -q "Rust source hash input is missing" hash.err
  mv "$path.saved" "$path"
done

mv src/rust/Cargo.lock src/rust/Cargo.lock.saved
mkdir src/rust/Cargo.lock
if "$rscript" --vanilla tools/rust-source-hash.R >hash.out 2>hash.err; then
  echo "Rust source hash accepted a directory as Cargo.lock" >&2
  exit 1
fi
grep -q "Rust source hash input is missing" hash.err
rm -rf src/rust/Cargo.lock
mv src/rust/Cargo.lock.saved src/rust/Cargo.lock

echo "Rust source hash validation: PASS"
