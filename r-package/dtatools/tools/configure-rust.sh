rm -rf src/rust/v
tar -xzf src/rust/vendor.tar.gz -C src/rust
test -d src/rust/v

if test -n "${R_HOME:-}"; then
  rscript="$R_HOME/bin/Rscript"
else
  rscript=$(command -v Rscript)
fi
rust_namespace=$("$rscript" --vanilla tools/rust-source-hash.R)
case "$rust_namespace" in
  ''|*[!0-9a-f]*) echo "invalid Rust source hash: $rust_namespace" >&2; exit 1 ;;
esac
