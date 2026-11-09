#!/bin/sh
# Build the wasm modules the npm packages embed. Needs the
# wasm32-unknown-unknown target: rustup target add wasm32-unknown-unknown
# CARGO may point at a rustup toolchain's cargo when the default one has
# no wasm target.
#
# The module includes C libzstd, so it also needs a clang and llvm-ar
# that target wasm32: Homebrew's llvm on macOS (Apple's clang does not
# target wasm32), the distribution's clang and llvm on Linux
# (apt-get install clang llvm). CC_wasm32_unknown_unknown and
# AR_wasm32_unknown_unknown choose others.
set -e
cd "$(dirname "$0")/.."
if [ -z "$CC_wasm32_unknown_unknown" ]; then
  llvm=""
  if command -v brew >/dev/null 2>&1 && [ -x "$(brew --prefix llvm)/bin/clang" ]; then
    llvm="$(brew --prefix llvm)/bin/"
  fi
  CC_wasm32_unknown_unknown="${llvm}clang"
  export CC_wasm32_unknown_unknown
fi
if [ -z "$AR_wasm32_unknown_unknown" ]; then
  for ar in "$(dirname "$(command -v "$CC_wasm32_unknown_unknown")")/llvm-ar" llvm-ar llvm-ar-20 llvm-ar-19 llvm-ar-18; do
    if command -v "$ar" >/dev/null 2>&1; then
      AR_wasm32_unknown_unknown="$ar"
      break
    fi
  done
  export AR_wasm32_unknown_unknown
fi
if ! "$CC_wasm32_unknown_unknown" --print-targets 2>/dev/null | grep -q wasm32; then
  echo "build-wasm.sh: $CC_wasm32_unknown_unknown does not target wasm32; install LLVM's clang (see above)" >&2
  exit 1
fi
# libzstd for size: as fast as -O3 in the benchmarks, 13 KB smaller with brotli.
CFLAGS_wasm32_unknown_unknown="${CFLAGS_wasm32_unknown_unknown:--Os}"
export CFLAGS_wasm32_unknown_unknown
# Two modules (plan 0021): the .dta one for @jbearak/dta-parser, and the
# Parquet and fixed-width one for @jbearak/datakit. Each also has a test
# build, for the memory tests only: its memory is capped at 64 MiB and it
# exports dta_test_set. Never published.
build() { # features, target dir, output
  ${CARGO:-cargo} build --release -p dta-ffi --target wasm32-unknown-unknown \
    --no-default-features --features "$1" --target-dir "$2"
  mkdir -p "$(dirname "$3")"
  cp "$2/wasm32-unknown-unknown/release/dta_ffi.wasm" "$3"
}
# `scripts/build-wasm.sh dta` builds dta-parser's alone (its publish
# workflow needs no other).
build wasm-dta target/wasm-dta js/build/dta.wasm
RUSTFLAGS="-C link-arg=--max-memory=67108864" build wasm-dta,test-hooks target/wasm-dta-test js/build/dta-test.wasm
if [ "$1" != "dta" ]; then
  build wasm-parquet target/wasm-parquet js/datakit/build/datakit.wasm
  RUSTFLAGS="-C link-arg=--max-memory=67108864" build wasm-parquet,test-hooks target/wasm-parquet-test js/datakit/build/datakit-test.wasm
fi
