#!/bin/sh
# Make a self-contained dtatools source package (r/dtatools_<version>.tar.gz)
# that carries its own copy of the Rust core.
set -e
cd "$(dirname "$0")/../r/dtatools"
./configure
rm -rf src/rust/target
cd ..
R CMD build --no-build-vignettes dtatools
