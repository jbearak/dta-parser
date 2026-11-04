#!/bin/sh
# Make the R source packages r/dtaparser_<version>.tar.gz, which carries
# its own copy of the Rust core, r/datakit_<version>.tar.gz, which
# imports dtaparser, and r/dtatools_<version>.tar.gz, which imports both.
# Install dtaparser first, then datakit.
#
# dtaparser's tarball also carries the crates the core takes from
# crates.io (cargo vendor), packed as src/rust/vendor.tar.xz since R CMD
# build would drop files cargo checksums, and a .cargo/config.toml that
# builds from them; Makevars unpacks them. So installing it needs no
# network (plan 0018). The checkout keeps neither: an install from GitHub
# fetches the crates.
set -e
cd "$(dirname "$0")/../r/dtaparser"
rust="$(pwd)/src/rust"
./configure
rm -rf "$rust/target" "$rust/vendor" "$rust/vendor.tar.xz" "$rust/.cargo"
cleanup() {
  rm -rf "$rust/vendor" "$rust/vendor.tar.xz" "$rust/.cargo"
}
trap cleanup EXIT
mkdir -p "$rust/.cargo"
(cd "$rust" && cargo vendor --locked vendor 2>/dev/null > .cargo/config.toml)
grep -q vendored-sources "$rust/.cargo/config.toml"
(cd "$rust" && tar -cJf vendor.tar.xz vendor && rm -rf vendor)
cd ..
R CMD build --no-build-vignettes dtaparser
R CMD build --no-build-vignettes datakit
R CMD build --no-build-vignettes dtatools
