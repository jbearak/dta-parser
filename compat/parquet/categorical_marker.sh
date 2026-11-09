#!/bin/sh
# Categoricals through .dta between the languages (plan 0023): Python's
# datakit and TypeScript's each save the same two categoricals, region
# (no letters, unordered) and grade (ordered, with a label on .a), as
# .dta with the dtaparser_categorical marker. TypeScript's grade holds
# .a and .z; Python's cannot, since a pandas category holds no letter
# (ADR 0040). Python reads TypeScript's file, its grade as labelled
# codes, a DtaArray with its letters, and as the category with
# letters=False; TypeScript reads Python's, getting the levels, the
# order and the letter label back; R reads both, region as a factor,
# grade as labelled numbers with its letters (TypeScript's) or an
# ordered factor (Python's), without a warning.
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
import pandas as pd
import datakit as dk
d = sys.argv[1]
df = pd.DataFrame({
    "region": pd.Categorical(["N", "S", None, "N", "E", "S"], categories=["S", "N", "E", "W"]),
    "grade": pd.Categorical(["low", None, "high", None, None, "mid"], categories=["low", "mid", "high"], ordered=True),
})
meta = dk.Meta(columns={"region": dk.Column(), "grade": dk.Column(value_labels="gl")},
               value_labels={"gl": {1: "low", 2: "mid", 3: "high", ".a": "Refused"}}, rows=6)
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
import pandas as pd
import datakit as dk
warnings.simplefilter("error")
texts = lambda s: [None if v != v else v for v in s.tolist()]  # noqa: E731
df, meta = dk.read_dta(os.path.join(sys.argv[1], "cat_typescript.dta"))
assert df["region"].dtype == pd.CategoricalDtype(["S", "N", "E", "W"]), df["region"].dtype
assert texts(df["region"]) == ["N", "S", None, "N", "E", "S"]
assert meta.columns["region"].ordered is False
# grade holds letters: its codes, a DtaArray with the letters, the mark kept.
assert str(df["grade"].dtype).startswith("dta["), df["grade"].dtype
assert df["grade"].array.codes.tolist() == [0, 2, 0, 1, 27, 0]
assert df["grade"].array._values[[0, 2, 5]].tolist() == [1.0, 3.0, 2.0]
assert texts(dk.na_tag(df["grade"])) == [None, ".a", None, None, ".z", None]
assert meta.labels("grade")[".a"] == "Refused", meta.labels("grade")
assert meta.characteristics == {"grade": {"dtaparser_categorical": "ordered gl"}}, meta.characteristics
# Without the letters, the category.
df, meta = dk.read_dta(os.path.join(sys.argv[1], "cat_typescript.dta"), letters=False)
assert df["grade"].dtype == pd.CategoricalDtype(["low", "mid", "high"], ordered=True)
assert meta.columns["grade"].ordered is True
assert texts(df["grade"]) == ["low", None, "high", None, None, "mid"]
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
assert.deepEqual(cells(grade), ["low", ".", "high", ".", ".", "mid"]);
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
  if (who == "python") {
    # Python's grade holds no letters, so R reads its factor.
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
