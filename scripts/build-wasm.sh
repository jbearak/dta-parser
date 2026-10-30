#!/bin/sh
# Build the wasm module the npm package embeds. Needs the
# wasm32-unknown-unknown target: rustup target add wasm32-unknown-unknown
# CARGO may point at a rustup toolchain's cargo when the default one has
# no wasm target.
set -e
cd "$(dirname "$0")/.."
${CARGO:-cargo} build --release -p dta-ffi --target wasm32-unknown-unknown
mkdir -p js/build
cp target/wasm32-unknown-unknown/release/dta_ffi.wasm js/build/dta.wasm
# A test build, for js/test/memory.test.mjs only: its memory is capped at
# 64 MiB and it exports dta_test_set. Never published.
RUSTFLAGS="-C link-arg=--max-memory=67108864" ${CARGO:-cargo} build --release -p dta-ffi \
  --target wasm32-unknown-unknown --features test-hooks --target-dir target/wasm-test
cp target/wasm-test/wasm32-unknown-unknown/release/dta_ffi.wasm js/build/dta-test.wasm
