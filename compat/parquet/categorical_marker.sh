#!/bin/sh
# Categoricals through .dta from TypeScript to R (plan 0023).
# TypeScript's datakit saves two categoricals from a Dataset, region (no
# letters, unordered) and grade (ordered, with .a and .z, and a label on
# .a), as .dta with the dtaparser_categorical marker. R's dtaparser reads
# them without a warning: region as a factor, and grade as labelled
# numbers with its letters, with factors = TRUE too. (R's datakit wrote
# the marker from a polars frame until its polars functions were
# removed.)
#
#     sh compat/parquet/categorical_marker.sh [DIR]
#
# Run from the repository root with js/ and js/datakit/ built and R's
# dtaparser installed (R_LIBS may point at a scratch library).
set -e
DIR=${1:-$(mktemp -d)}
mkdir -p "$DIR"

node - "$DIR" <<'EOF'
const node = require("./js/datakit/dist/node.js");
const { MISSING } = require("./js/datakit/dist/index.js");
const d = process.argv[2];
node.saveDta({
  valueLabels: { gl: new Map([[1, "low"], [2, "mid"], [3, "high"], [MISSING[".a"], "Refused"]]) },
  variables: [
    { name: "region", type: "categorical", levels: ["S", "N", "E", "W"], values: [1, 0, null, 1, 2, 0] },
    { name: "grade", type: "categorical", categorical: { levels: ["low", "mid", "high"], ordered: true }, valueLabels: "gl", values: [0, MISSING[".a"], 2, null, MISSING[".z"], 1] },
  ],
}, d + "/cat_typescript.dta");
EOF

# R reads TypeScript's file.
Rscript - "$DIR" <<'EOF'
suppressPackageStartupMessages(library(dtaparser))
f <- file.path(commandArgs(TRUE)[1], "cat_typescript.dta")
d <- withCallingHandlers(read_dta(f), warning = function(w) stop("R warned: ", conditionMessage(w)))
stopifnot(is.factor(d$region), !is.ordered(d$region), identical(levels(d$region), c("S", "N", "E", "W")),
          identical(as.character(d$region), c("N", "S", NA, "N", "E", "S")))
stopifnot(!is.factor(d$grade), identical(na_tag(unclass(d$grade))[c(2, 5)], c("a", "z")),
          identical(as.numeric(unclass(d$grade))[c(1, 3, 6)], c(1, 3, 2)))
labs <- attr(d$grade, "labels")
stopifnot(identical(names(labs)[!is.na(labs)], c("low", "mid", "high")), "Refused" %in% names(labs))
stopifnot(identical(read_dta(f, factors = TRUE)$grade, d$grade))
cat("R read TypeScript's categoricals\n")
EOF
echo "categorical marker checks passed"
