// Makes the categorical_letters*.parquet fixtures that julia/Datakit's
// tests read (plan 0022): Parquet categoricals holding .a to .z, which
// are DOUBLE level numbers. Julia cannot write one (a CategoricalArray
// cannot hold the letters), so TypeScript's datakit writes them. From the
// repository root, after building js/datakit (npm run build there):
//
//   node julia/Datakit/test/fixtures/make_categorical_letters.js
//
// The data is made up here.
const { writeFileSync } = require("node:fs");
const { join } = require("node:path");
const { writeParquet, MISSING } = require(join(__dirname, "..", "..", "..", "..", "js", "datakit", "dist", "index.js"));

const LEVELS = ["low", "mid", "high"];
const out = (name, bytes) => writeFileSync(join(__dirname, name), bytes);

// grade: low, .a, high, ., .z, mid (ordered, with letters: DOUBLE);
// region: a categorical without letters (text).
out("categorical_letters.parquet", writeParquet({
  variables: [
    { name: "grade", type: "categorical", categorical: { levels: LEVELS, ordered: true }, values: [0, MISSING[".a"], 2, null, MISSING[".z"], 1] },
    { name: "region", type: "categorical", categorical: { levels: ["north", "south"], ordered: false }, values: [0, 1, 0, 1, null, 0] },
  ],
}));

// grade: low, .a | high, mid in two row groups, then every 3.0 in the
// file's bytes (only high's, in the second row group) made 1.5, which is
// not a level number.
const bad = writeParquet({ variables: [{ name: "grade", type: "categorical", levels: LEVELS, values: [0, MISSING[".a"], 2, 1] }] },
                         { compression: "none", rowGroupSize: 2 });
const three = Buffer.from(new Float64Array([3]).buffer);
const half = Buffer.from(new Float64Array([1.5]).buffer);
let n = 0;
for (let i = 0; i + 8 <= bad.length; i++) {
  if (three.equals(Buffer.from(bad.subarray(i, i + 8)))) {
    bad.set(half, i);
    n++;
  }
}
if (n === 0) throw new Error("no 3.0 found");
out("categorical_letters_bad.parquet", bad);

// A set named grade that does not fit grade's levels, used by another
// column: grade records grade_2.
out("categorical_letters_collide.parquet", writeParquet({
  valueLabels: { grade: new Map([[1, "yes"]]) },
  variables: [
    { name: "grade", type: "categorical", levels: LEVELS, values: [0, MISSING[".a"], 2, null, MISSING[".z"], 1] },
    { name: "other", type: "double", valueLabels: "grade", values: [1, 0, 1, 1, MISSING[".b"], 0] },
  ],
}));
