#!/bin/sh
# Categoricals through .dta between TypeScript and R (plan 0023), both
# ways. Each datakit saves two categoricals, region (no letters,
# unordered) and grade (ordered, with a label on .a), as .dta with the
# dtaparser_categorical marker: TypeScript from a Dataset, with .a and
# .z in grade, and R from a polars frame, whose Enum holds no letters.
# TypeScript reads R's file as categoricals. R's dtaparser reads both
# without a warning: region as a factor; R's grade as an ordered factor,
# and TypeScript's as labelled numbers with its letters, with
# factors = TRUE too.
#
#     sh compat/parquet/categorical_marker.sh [DIR]
#
# Run from the repository root with js/ and js/datakit/ built and R's
# dtaparser, datakit, polars and nanoarrow installed (R_LIBS may point
# at a scratch library).
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

# R writes its file from a polars frame.
Rscript - "$DIR" <<'EOF'
suppressPackageStartupMessages({library(datakit); library(polars)})
df <- pl$DataFrame(
  region = pl$Series("region", c("N", "S", NA, "N", "E", "S"))$cast(pl$Enum(c("S", "N", "E", "W"))),
  grade = pl$Series("grade", c("low", NA, "high", NA, NA, "mid"))$cast(pl$Enum(c("low", "mid", "high")))
)
entry <- function(value_labels = NULL, ordered = NULL) list(label = NULL, format = NULL, value_labels = value_labels, ordered = ordered)
meta <- structure(list(label = NULL, notes = character(), characteristics = list(), sort = character(), timestamp = NULL,
                       columns = list(region = entry(), grade = entry("gl", TRUE)),
                       value_labels = list(gl = c(low = 1, mid = 2, high = 3, tagged_na(c(Refused = "a")))),
                       rows = 6, storage = character()), class = "datakit_meta")
save_dta(df, file.path(commandArgs(TRUE)[1], "cat_r.dta"), meta = meta)
EOF

# TypeScript reads R's file.
node - "$DIR" <<'EOF'
const assert = require("node:assert/strict");
const node = require("./js/datakit/dist/node.js");
const { MISSING } = require("./js/datakit/dist/index.js");
const ds = node.readDta(process.argv[2] + "/cat_r.dta", { onWarning: (m) => { throw new Error(m.join("\n")); } });
const [region, grade] = ds.variables;
const cells = (v) => Array.from(v.values.codes, (k, i) => (v.values.missing[i] ? (v.values.missing[i] === 1 ? "." : `.${String.fromCharCode(95 + v.values.missing[i])}`) : v.values.values[k]));
assert.equal(region.type, "categorical");
assert.deepEqual([region.categorical.levels, region.categorical.ordered], [["S", "N", "E", "W"], false]);
assert.deepEqual(cells(region), ["N", "S", ".", "N", "E", "S"]);
assert.equal(grade.type, "categorical");
assert.deepEqual([grade.categorical.levels, grade.categorical.ordered], [["low", "mid", "high"], true]);
assert.deepEqual(cells(grade), ["low", ".", "high", ".", ".", "mid"]);
assert.equal(ds.valueLabels[grade.valueLabels].get(MISSING[".a"]), "Refused");
assert.ok(!ds.characteristics.some((c) => c.name === "dtaparser_categorical" || c.name === "dtaparser_factor"));
console.log("TypeScript read R's categoricals");
EOF

# R reads both files.
Rscript - "$DIR" <<'EOF'
suppressPackageStartupMessages(library(dtaparser))
for (who in c("r", "typescript")) {
  d <- withCallingHandlers(read_dta(file.path(commandArgs(TRUE)[1], paste0("cat_", who, ".dta"))),
                           warning = function(w) stop("R warned on ", who, "'s file: ", conditionMessage(w)))
  stopifnot(is.factor(d$region), !is.ordered(d$region), identical(levels(d$region), c("S", "N", "E", "W")),
            identical(as.character(d$region), c("N", "S", NA, "N", "E", "S")))
  if (who == "r") {
    # R's grade holds no letters, so dtaparser reads its factor.
    stopifnot(is.ordered(d$grade), identical(levels(d$grade), c("low", "mid", "high")),
              identical(as.character(d$grade), c("low", NA, "high", NA, NA, "mid")))
  } else {
    stopifnot(!is.factor(d$grade), identical(na_tag(unclass(d$grade))[c(2, 5)], c("a", "z")),
              identical(as.numeric(unclass(d$grade))[c(1, 3, 6)], c(1, 3, 2)))
    labs <- attr(d$grade, "labels")
    stopifnot(identical(names(labs)[!is.na(labs)], c("low", "mid", "high")), "Refused" %in% names(labs))
    stopifnot(identical(d2 <- read_dta(file.path(commandArgs(TRUE)[1], paste0("cat_", who, ".dta")), factors = TRUE)$grade, d$grade))
  }
  cat("R read ", who, "'s categoricals\n", sep = "")
}
EOF
echo "categorical marker checks passed"
