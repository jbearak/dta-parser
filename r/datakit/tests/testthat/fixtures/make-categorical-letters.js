// Makes the categorical-letters-*.parquet fixtures that test-parquet.R
// reads (plan 0022). R cannot write a categorical holding .a to .z, so
// TypeScript's datakit writes them. From the repository root, after
// `npm run build` in js/datakit:
//
//   node r/datakit/tests/testthat/fixtures/make-categorical-letters.js
const fs = require("fs");
const path = require("path");
const { writeParquet, MISSING } = require(path.join(__dirname, "../../../../../js/datakit/dist/index.js"));

const grade = (values) => ({
  name: "grade",
  type: "categorical",
  categorical: { levels: ["low", "mid", "high"], ordered: true },
  values,
});
const out = (name, bytes) => fs.writeFileSync(path.join(__dirname, name), bytes);

// low, .a, high, ., .z, mid
out("categorical-letters.parquet",
  writeParquet({ variables: [grade([0, MISSING[".a"], 2, null, MISSING[".z"], 1])] }));

// low, .a | high, mid in two row groups, uncompressed; then every
// float64 3.0 (high's level number) becomes 1.5, a value that is not a
// level number, in the second row group.
const clean = writeParquet({ variables: [grade([0, MISSING[".a"], 2, 1])] }, { compression: "none", rowGroupSize: 2 });
const bad = Buffer.from(clean);
const three = Buffer.alloc(8);
three.writeDoubleLE(3.0);
const half = Buffer.alloc(8);
half.writeDoubleLE(1.5);
let replaced = 0;
for (let i = bad.indexOf(three); i >= 0; i = bad.indexOf(three, i + 8)) {
  half.copy(bad, i);
  replaced++;
}
if (!replaced) throw new Error("no 3.0 in the file");
out("categorical-letters-bad.parquet", bad);

// A set named "grade" that does not fit the categorical, used by
// another column: the categorical's set is made as "grade_2".
out("categorical-letters-collision.parquet",
  writeParquet({
    variables: [
      grade([0, MISSING[".a"], 2, null, MISSING[".z"], 1]),
      { name: "other", type: "double", values: [1, null, 1, 1, null, 1], valueLabels: "grade" },
    ],
    valueLabels: { grade: new Map([[1, "yes"]]) },
  }));
