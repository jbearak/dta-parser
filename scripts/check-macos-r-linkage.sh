#!/bin/sh
set -eu

# R symbols must bind to the host process, not another R distribution.
library=${1:?usage: check-macos-r-linkage.sh path/to/dtatools.so}
dependencies=$(otool -L "$library")
if printf '%s\n' "$dependencies" | tail -n +2 | \
    grep -E 'libR[.]dylib|R[.]framework' >/dev/null; then
    printf 'Binary links directly to an R runtime:\n%s\n' "$dependencies" >&2
    exit 1
fi
