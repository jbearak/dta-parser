#!/bin/sh
# Build the wasm module the npm package embeds. Needs the
# wasm32-unknown-unknown target: rustup target add wasm32-unknown-unknown
# CARGO may point at a rustup toolchain's cargo when the default one has
# no wasm target.
#
# The module is Rust alone (feature wasm-dta), so no C compiler is
# needed. It also has a test build, for the memory tests only: its
# memory is capped at 64 MiB and it exports dta_test_set. Never
# published.
set -e
cd "$(dirname "$0")/.."
build() { # features, target dir, output
  ${CARGO:-cargo} build --release -p dta-ffi --target wasm32-unknown-unknown \
    --no-default-features --features "$1" --target-dir "$2"
  mkdir -p "$(dirname "$3")"
  cp "$2/wasm32-unknown-unknown/release/dta_ffi.wasm" "$3"
}
# The cap is set in a subshell: an assignment before a call of a shell
# function outlives the call in some shells (macOS's sh among them),
# and would cap the module built next.
capped() {
  (RUSTFLAGS="-C link-arg=--max-memory=67108864"; export RUSTFLAGS; build "$@")
}
build wasm-dta target/wasm-dta js/build/dta.wasm
capped wasm-dta,test-hooks target/wasm-dta-test js/build/dta-test.wasm
