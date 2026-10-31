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

test("%g prints numbers as R does", () => {
  // 7 significant digits; fixed unless scientific is narrower.
  assert.equal(formatValue(0.5, "%9.0g"), "0.5");
  assert.equal(formatValue(1 / 3, "%9.0g"), "0.3333333");
  assert.equal(formatValue(0.1 + 0.2, "%9.0g"), "0.3");
  assert.equal(formatValue(123456789012, "%10.0g"), "123456789012");
  assert.equal(formatValue(1234567890123, "%10.0g"), "1.234568e+12");
  assert.equal(formatValue(100000, "%9.0g"), "1e+05");
  assert.equal(formatValue(123456, "%9.0g"), "123456");
  assert.equal(formatValue(0.0001, "%9.0g"), "1e-04");
  assert.equal(formatValue(0.001, "%9.0g"), "0.001");
  assert.equal(formatValue(-1234.5678, "%9.0g"), "-1234.568");
  assert.equal(formatValue(1e300, "%9.0g"), "1e+300");
  assert.equal(formatValue(0, "%9.0g"), "0");
  // %w.dg: d significant digits, as R's format(x, digits = d).
  assert.equal(formatValue(3.14159, "%9.3g"), "3.14");
  assert.equal(formatValue(123456, "%9.3g"), "123456");
  // Formats that are not %f, %e, %g or dates.
  assert.equal(formatValue(42, "%21x"), "42");
  assert.equal(formatValue(1 / 3, "%8.0f!"), "0.3333333");
});

test("missing values and labels", () => {
  assert.equal(formatValue(MISSING[".a"], "%9.0g"), ".a");
  const labels = new Map([[1, "Yes"], [MISSING[".d"], "Don't know"]]);
  assert.equal(formatValue(1, "%9.0g", labels), "Yes");
  assert.equal(formatValue(MISSING[".d"], "%9.0g", labels), "Don't know");
  assert.equal(formatValue(2, "%9.0g", labels), "2");
});

test("labels of copied missing values follow edits to the map", () => {
  const labels = structuredClone(new Map([[MISSING[".d"], "Don't know"], [1, "Yes"]]));
  const d = MISSING[".d"];
  assert.equal(formatValue(d, "%9.0g", labels), "Don't know");
  const [key] = labels.keys();
  labels.set(key, "Unsure");
  assert.equal(formatValue(d, "%9.0g", labels), "Unsure");
  labels.delete(key);
  assert.equal(formatValue(d, "%9.0g", labels), ".d");
  labels.set(structuredClone(MISSING[".e"]), "Refused");
  assert.equal(formatValue(MISSING[".e"], "%9.0g", labels), "Refused");
  // Same size: one missing key replaced by another.
  labels.delete(1);
  labels.set(structuredClone(d), "Back");
  labels.delete([...labels.keys()].find((k) => k.missing === ".e"));
  labels.set(structuredClone(MISSING[".f"]), "Skipped");
  assert.equal(formatValue(MISSING[".f"], "%9.0g", labels), "Skipped");
  assert.equal(formatValue(MISSING[".e"], "%9.0g", labels), ".e");
  assert.equal(formatValue(d, "%9.0g", labels), "Back");
});

test("strings pass through", () => {
  assert.equal(formatValue("abc", "%-10s"), "abc");
});

test("days and times as R shows Dates and POSIXct; other units by their mask", () => {
  assert.equal(formatValue(0, "%td"), "1960-01-01");
  assert.equal(formatValue(-1, "%td"), "1959-12-31");
  assert.equal(formatValue(22949, "%tdCCYY-NN-DD"), "2022-10-31");
  assert.equal(formatValue(22949, "%tdMonth_dd,_CCYY"), "2022-10-31");
  assert.equal(formatValue(0, "%d"), "1960-01-01");
  assert.equal(formatValue(22949, "%dD_m_Y"), "2022-10-31");
  assert.equal(formatValue(1000 * (3600 + 61) + 250, "%tc"), "1960-01-01 01:01:01");
  assert.equal(formatValue(1000 * (3600 + 61) + 250, "%tcHH:MM:SS.sss"), "1960-01-01 01:01:01");
  assert.equal(formatValue(1000 * 3600, "%tC"), "1960-01-01 01:00:00");
  assert.equal(formatValue(999.5, "%tc"), "1960-01-01 00:00:00");
  assert.equal(formatValue(0, "%tw"), "1960w1");
  assert.equal(formatValue(757, "%tm"), "2023m2");
  assert.equal(formatValue(-1, "%tq"), "1959q4");
  assert.equal(formatValue(3, "%th"), "1961h2");
  assert.equal(formatValue(2024, "%ty"), "2024");
  assert.equal(formatValue(0, "%tmCCYY"), "1960");
  assert.equal(formatValue(757, "%tmMon_CCYY"), "Feb 2023");
  assert.equal(formatValue(5, "%tqCCYY_!qq"), "1961 q2");
  assert.equal(formatValue(-1, "%twCCYY-WW"), "1959-52");
});

test("dates floor, as haven does; negative years keep their sign", () => {
  assert.equal(formatValue(0.5, "%td"), "1960-01-01");
  assert.equal(formatValue(1234.5678, "%td"), "1963-05-19");
  assert.equal(formatValue(-0.25, "%td"), "1959-12-31");
  assert.equal(formatValue(-1, "%ty"), "-0001");
  assert.equal(formatValue(-29, "%ty"), "-0029");
  assert.equal(formatValue(2024.7, "%ty"), "2024");
  assert.equal(formatValue(-715875, "%td"), "0000-01-01");
  assert.equal(formatValue(-715876, "%td"), "-001-12-31");
});

test("values a format cannot show fall back to the plain number", () => {
  assert.equal(formatValue(123456789, "%td"), "123456789");
  assert.equal(formatValue(-312267684937, "%td"), "-312267684937");
  assert.equal(formatValue(1e300, "%tdCCYY-NN-DD"), "1e+300");
  assert.equal(formatValue(8.7e15, "%tc"), "8.7e+15");
  assert.equal(formatValue(1.5, "%9.101f"), "1.5");
  assert.equal(formatValue(12345678000000, "%9.102g"), "1.234568e+13");
  for (const f of ["%tm", "%tq", "%th", "%tw", "%ty"]) assert.equal(formatValue(1e300, f), "1e+300");
  assert.equal(formatValue(2024 * 12, "%tm"), "3984m1");
});

test("formatValue never throws", () => {
  let seed = 11;
  const rnd = () => (seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31;
  const units = ["%td", "%tc", "%tC", "%tw", "%tm", "%tq", "%th", "%ty", "%d", "%tdCCYY-NN-DD_HH:MM:SS.sss", "%tcMonth_dd,_CCYY!h"];
  const numeric = () => `%${rnd() < 0.2 ? "-" : ""}${Math.floor(rnd() * 400)}.${Math.floor(rnd() * 400)}${"fge"[Math.floor(rnd() * 3)]}${rnd() < 0.3 ? "c" : ""}`;
  for (let i = 0; i < 100_000; i++) {
    const v = (rnd() - 0.5) * 10 ** Math.floor(rnd() * 600 - 300);
    const format = rnd() < 0.5 ? units[i % units.length] : numeric();
    const text = formatValue(rnd() < 0.5 ? Math.round(v) : v, format);
    assert.equal(typeof text, "string");
  }
  for (const v of [Number.MAX_VALUE, -Number.MAX_VALUE, Number.MIN_VALUE, -0, 2 ** 53]) {
    for (const f of [...units, "%9.0g", "%400.300f", "%1.0e", "%0.0gc"]) assert.equal(typeof formatValue(v, f), "string");
  }
});
