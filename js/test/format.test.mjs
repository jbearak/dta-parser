import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { formatValue, MISSING } = require("../dist/index.js");

test("numbers by %f, %g, %e, with and without commas", () => {
  assert.equal(formatValue(3.14159, "%9.2f"), "3.14");
  assert.equal(formatValue(1234567.891, "%12.2fc"), "1,234,567.89");
  assert.equal(formatValue(-0.5, "%6.1f"), "-0.5");
  assert.equal(formatValue(42, "%9.0g"), "42");
  assert.equal(formatValue(1234567, "%12.0gc"), "1,234,567");
  assert.equal(formatValue(3.14159265, "%9.0g"), "3.141593");
  assert.equal(formatValue(0.000012345, "%9.0g"), "1.2345e-05");
  assert.equal(formatValue(123456.789, "%10.3e"), "1.235e+05");
  assert.equal(formatValue(2.5, "%9.3g"), "2.5");
  assert.equal(formatValue(9999999999.5, "%12.0g"), "1e+10");
  assert.equal(formatValue(-1234.5, "%12.2fc"), "-1,234.50");
});

test("missing values and labels", () => {
  assert.equal(formatValue(MISSING[".a"], "%9.0g"), ".a");
  const labels = new Map([[1, "Yes"], [MISSING[".d"], "Don't know"]]);
  assert.equal(formatValue(1, "%9.0g", labels), "Yes");
  assert.equal(formatValue(MISSING[".d"], "%9.0g", labels), "Don't know");
  assert.equal(formatValue(2, "%9.0g", labels), "2");
});

test("strings pass through", () => {
  assert.equal(formatValue("abc", "%-10s"), "abc");
});

test("dates and times, default and masked", () => {
  assert.equal(formatValue(0, "%td"), "01jan1960");
  assert.equal(formatValue(-1, "%td"), "31dec1959");
  assert.equal(formatValue(22949, "%tdCCYY-NN-DD"), "2022-10-31");
  assert.equal(formatValue(22949, "%tdMonth_dd,_CCYY"), "October 31, 2022");
  assert.equal(formatValue(0, "%d"), "01jan1960");
  assert.equal(formatValue(1000 * (3600 + 61) + 250, "%tc"), "01jan1960 01:01:01");
  assert.equal(formatValue(1000 * (3600 + 61) + 250, "%tcHH:MM:SS.sss"), "01:01:01.250");
  assert.equal(formatValue(1000 * 3600, "%tC"), "01jan1960 01:00:00");
  assert.equal(formatValue(0, "%tw"), "1960w1");
  assert.equal(formatValue(757, "%tm"), "2023m2");
  assert.equal(formatValue(-1, "%tq"), "1959q4");
  assert.equal(formatValue(3, "%th"), "1961h2");
  assert.equal(formatValue(2024, "%ty"), "2024");
  assert.equal(formatValue(22949, "%tdDD!/NN!/CCYY"), "31/10/2022");
  assert.equal(formatValue(999.5, "%tcHH:MM:SS.sss"), "00:00:00.999");
  assert.equal(formatValue(0, "%tmCCYY"), "1960");
  assert.equal(formatValue(757, "%tmMon_CCYY"), "Feb 2023");
  assert.equal(formatValue(5, "%tqCCYY_!qq"), "1961 q2");
  assert.equal(formatValue(-1, "%twCCYY-WW"), "1959-52");
  assert.equal(formatValue(-3, "%td"), "29dec1959");
  // The older %d formats show as %td.
  assert.equal(formatValue(22949, "%dD_m_Y"), "31oct2022");
});
