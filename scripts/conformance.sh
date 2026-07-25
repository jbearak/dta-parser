#!/bin/sh
set -eu

bun scripts/check-conformance.ts
bun scripts/run-conformance-gates.ts

required=${DTA_REQUIRE_R_CONFORMANCE:-0}
if ! command -v Rscript >/dev/null 2>&1; then
  if test "$required" = 1; then
    echo "R conformance: REQUIRED but Rscript is unavailable" >&2
    exit 1
  fi
  echo "R conformance: SKIP (Rscript unavailable; set DTA_REQUIRE_R_CONFORMANCE=1 to make this fatal)"
  exit 0
fi

if ! Rscript -e 'quit(status = !all(vapply(c("rlang", "tibble", "tidyselect", "testthat", "haven"), requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))))'; then
  if test "$required" = 1; then
    echo "R conformance: REQUIRED but one or more declared test dependencies are unavailable" >&2
    exit 1
  fi
  echo "R conformance: SKIP (dependencies unavailable; set DTA_REQUIRE_R_CONFORMANCE=1 to make this fatal)"
  exit 0
fi

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
cp -R r-package/dtaparser "$temporary/dtaparser"
(cd "$temporary" && R CMD build dtaparser)
(cd "$temporary" && R CMD check --no-manual dtaparser_0.1.0.tar.gz)
echo "R/haven conformance: PASS (current source built and checked with offline Cargo archive)"
