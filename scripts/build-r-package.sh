#!/bin/sh
# Make the R source packages r/dtaparser_<version>.tar.gz, which carries
# its own copy of the Rust core, and r/dtatools_<version>.tar.gz, which
# imports dtaparser. Install dtaparser first.
set -e
cd "$(dirname "$0")/../r/dtaparser"
./configure
rm -rf src/rust/target
cd ..
R CMD build --no-build-vignettes dtaparser
R CMD build --no-build-vignettes dtatools
