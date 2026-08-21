#!/bin/sh
set -eu

if test "$#" -ne 1; then
  echo "usage: $0 path/to/dtaparser_VERSION.tar.gz" >&2
  exit 2
fi

tar -tzf "$1" | awk '
BEGIN {
  required["dtaparser/src/dta-parser/Cargo.toml"]
  required["dtaparser/src/dta-parser/src/lib.rs"]
  required["dtaparser/src/rust/Cargo.toml"]
  required["dtaparser/src/rust/Cargo.lock"]
  required["dtaparser/src/rust/vendor.tar.gz"]
  required["dtaparser/src/Makevars.rust"]
  required["dtaparser/tools/configure-rust.sh"]
  required["dtaparser/tools/rust-source-hash.R"]
}
{
  present[$0] = 1
  if ($0 ~ /\/target(\/|$)|^dtaparser\/src\/rust\/v(\/|$)|^dtaparser\/src\/dta-parser\/(tests|examples)(\/|$)|^dtaparser\/src\/Makevars(\.win)?$|\/vendor\/dta-parser/) {
    if (!excluded) {
      print "R package archive contains excluded Rust development or build files:" > "/dev/stderr"
    }
    print $0 > "/dev/stderr"
    excluded = 1
  }
}
END {
  for (path in required) {
    if (!(path in present)) {
      print "R package archive is missing " path > "/dev/stderr"
      missing = 1
    }
  }
  if (excluded || missing) {
    exit 1
  }
}
'

echo "R package archive: PASS"
