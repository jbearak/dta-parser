#!/bin/sh
# Fail if man/ is out of sync with the roxygen blocks it is generated from.
#
# roxygen2 skips NAMESPACE and the two hand-maintained pages (man/read_dta.Rd,
# man/recode.Rd) on its own, because none of them carries a roxygen2 header, so
# this check leaves them alone without needing an explicit exclusion list.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
package_root="$root/r-package/dtatools"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "roxygen check: REQUIRED but Rscript is unavailable" >&2
  exit 1
fi

if ! Rscript -e 'quit(status = !requireNamespace("roxygen2", quietly = TRUE))'; then
  echo "roxygen check: REQUIRED but roxygen2 is unavailable" >&2
  exit 1
fi

# Rd output is roxygen2-version-specific, so only compare against the pinned
# version; a mismatched local install would report churn that is not drift.
pinned=$(sed -n 's/^Config\/roxygen2\/version: //p' "$package_root/DESCRIPTION")
installed=$(Rscript -e 'cat(as.character(utils::packageVersion("roxygen2")))')
if test "$pinned" != "$installed"; then
  echo "roxygen check: SKIP (roxygen2 $installed installed, DESCRIPTION pins $pinned)"
  exit 0
fi

# load_code = "source" reads the R sources directly, so the check does not need
# a compiled copy of the Rust bridge.
(cd "$package_root" && Rscript -e 'roxygen2::roxygenise(".", load_code = "source")')

if ! git -C "$root" diff --exit-code -- "r-package/dtatools/man"; then
  echo "man/ is out of sync with the roxygen blocks; run roxygen2::roxygenise() in r-package/dtatools and commit the result" >&2
  exit 1
fi

echo "roxygen check: PASS (man/ matches the roxygen blocks)"
