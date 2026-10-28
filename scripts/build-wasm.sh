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
