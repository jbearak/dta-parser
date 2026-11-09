#!/bin/sh
# Categoricals through .dta between the languages (plan 0023): Python's
# datakit and TypeScript's each save the same two categoricals, region
# (no letters, unordered) and grade (ordered, with .a and .z, and a
# label on .a), as .dta with the dtaparser_categorical marker; Python
# reads TypeScript's file and TypeScript reads Python's, each getting
# the levels, the order, the letters by row and the letter label back;
# R reads both, region as a factor and grade as labelled numbers with
# its letters, without a warning.
#
#     sh compat/parquet/categorical_marker.sh [DIR]
#
# Run from the repository root with js/ and js/datakit/ built, PYTHON
# (default python3) with datakit, and R's dtaparser (R_LIBS may point at
# a scratch library).
set -e
DIR=${1:-$(mktemp -d)}
PYTHON=${PYTHON:-python3}
mkdir -p "$DIR"

"$PYTHON" - "$DIR" <<'EOF'
import os, sys
import polars as pl
import datakit as dk
d = sys.argv[1]
df = pl.DataFrame({
    "region": pl.Series(["N", "S", None, "N", "E", "S"], dtype=pl.Enum(["S", "N", "E", "W"])),
    "grade": pl.Series(["low", None, "high", None, None, "mid"], dtype=pl.Enum(["low", "mid", "high"])),
})
meta = dk.Meta(columns={"region": dk.Column(), "grade": dk.Column(value_labels="gl", ordered=True)},
               value_labels={"gl": {1: "low", 2: "mid", 3: "high", ".a": "Refused"}},
               missing={"grade": pl.Series("grade", [None, ".a", None, None, ".z", None], dtype=dk.LETTERS)}, rows=6)
dk.save_dta(df, os.path.join(d, "cat_python.dta"), meta=meta)
EOF

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

# Python reads TypeScript's file.
"$PYTHON" - "$DIR" <<'EOF'
import os, sys, warnings
import polars as pl
import datakit as dk
warnings.simplefilter("error")
df, meta = dk.read_dta(os.path.join(sys.argv[1], "cat_typescript.dta"))
assert df["region"].dtype == pl.Enum(["S", "N", "E", "W"]), df["region"].dtype
assert df["region"].to_list() == ["N", "S", None, "N", "E", "S"]
assert meta.columns["region"].ordered is False
assert df["grade"].dtype == pl.Enum(["low", "mid", "high"]) and meta.columns["grade"].ordered is True
assert df["grade"].to_list() == ["low", None, "high", None, None, "mid"]
assert meta.missing["grade"].to_list() == [None, ".a", None, None, ".z", None]
assert meta.labels("grade")[".a"] == "Refused", meta.labels("grade")
assert not any(n in ("dtaparser_categorical", "dtaparser_factor") for c in meta.characteristics.values() for n in c)
print("Python read TypeScript's categoricals")
EOF

# TypeScript reads Python's file.
node - "$DIR" <<'EOF'
const assert = require("node:assert/strict");
const node = require("./js/datakit/dist/node.js");
const { MISSING } = require("./js/datakit/dist/index.js");
const ds = node.readDta(process.argv[2] + "/cat_python.dta", { onWarning: (m) => { throw new Error(m.join("\n")); } });
const [region, grade] = ds.variables;
const cells = (v) => Array.from(v.values.codes, (k, i) => (v.values.missing[i] ? (v.values.missing[i] === 1 ? "." : `.${String.fromCharCode(95 + v.values.missing[i])}`) : v.values.values[k]));
assert.equal(region.type, "categorical");
assert.deepEqual([region.categorical.levels, region.categorical.ordered], [["S", "N", "E", "W"], false]);
assert.deepEqual(cells(region), ["N", "S", ".", "N", "E", "S"]);
assert.equal(grade.type, "categorical");
assert.deepEqual([grade.categorical.levels, grade.categorical.ordered], [["low", "mid", "high"], true]);
assert.deepEqual(cells(grade), ["low", ".a", "high", ".", ".z", "mid"]);
assert.equal(ds.valueLabels[grade.valueLabels].get(MISSING[".a"]), "Refused");
assert.ok(!ds.characteristics.some((c) => c.name === "dtaparser_categorical" || c.name === "dtaparser_factor"));
console.log("TypeScript read Python's categoricals");
EOF

# R reads both.
Rscript - "$DIR" <<'EOF'
suppressPackageStartupMessages(library(dtaparser))
for (who in c("python", "typescript")) {
  d <- withCallingHandlers(read_dta(file.path(commandArgs(TRUE)[1], paste0("cat_", who, ".dta"))),
                           warning = function(w) stop("R warned on ", who, "'s file: ", conditionMessage(w)))
  stopifnot(is.factor(d$region), !is.ordered(d$region), identical(levels(d$region), c("S", "N", "E", "W")),
            identical(as.character(d$region), c("N", "S", NA, "N", "E", "S")))
  stopifnot(!is.factor(d$grade), identical(na_tag(unclass(d$grade))[c(2, 5)], c("a", "z")),
            identical(as.numeric(unclass(d$grade))[c(1, 3, 6)], c(1, 3, 2)))
  labs <- attr(d$grade, "labels")
  stopifnot(identical(names(labs)[!is.na(labs)], c("low", "mid", "high")), "Refused" %in% names(labs))
  stopifnot(identical(d2 <- read_dta(file.path(commandArgs(TRUE)[1], paste0("cat_", who, ".dta")), factors = TRUE)$grade, d$grade))
  cat("R read ", who, "'s categoricals\n", sep = "")
}
EOF
echo "categorical marker checks passed"
