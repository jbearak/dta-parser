// Shared by the Parquet tests: compare what the npm package reads from
// compat/parquet/fixtures with what pyarrow reads (compat/parquet/expected).
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { createRequire } from "node:module";
const { NA, missingCode, taggedNa } = createRequire(import.meta.url)("../dist/index.js");

/**
 * A column's missing codes, 0 a value, 1 `.`, 2 to 27 `.a` to `.z`: a
 * number column's from its values (ADR 0037), any other's from `missing`.
 */
export function codesOf(c) {
  if (c.kind === "number") return Array.from(c.values, missingCode);
  return Array.from(c.missing ?? new Uint8Array(c.kind === "dictionary" ? c.codes.length : c.values.length));
}

/** A NumberColumn of `values`, with the missing value of each nonzero code in `codes`. */
export function numbers(values, codes = []) {
  const out = Float64Array.from(values, (x) => (x === null ? 0 : x));
  codes.forEach((k, i) => {
    if (k === 1) out[i] = NA;
    else if (k > 1) out[i] = taggedNa(String.fromCharCode(0x61 + k - 2));
  });
  return { kind: "number", values: out };
}

export const parquetCompat = new URL("../../../compat/parquet/", import.meta.url);

/** The fixtures, each with its expected JSON (integers past 2^53 as bigints). */
export function parquetFixtures() {
  const names = readdirSync(new URL("expected/", parquetCompat)).filter((f) => f.endsWith(".json"));
  return names.sort().map((f) => {
    const stem = f.replace(/\.json$/, "");
    const text = readFileSync(new URL(`expected/${f}`, parquetCompat), "utf8");
    // JSON.parse with the source text keeps every digit of large integers.
    const doc = JSON.parse(text, (_, v, ctx) =>
      typeof v === "number" && Number.isInteger(v) && !Number.isSafeInteger(v) && ctx?.source && /^-?\d+$/.test(ctx.source) ? BigInt(ctx.source) : v,
    );
    return { stem, doc, bytes: readFileSync(new URL(`fixtures/${stem}.parquet`, parquetCompat)) };
  });
}

/** One of our cells, comparable with pyarrow's JSON. */
function ours(column, i, variable, arrowType) {
  const c = column;
  if (c.kind === "number") {
    const x = c.values[i];
    if (missingCode(x)) return null;
    if (Number.isNaN(x)) return "NaN";
    if (arrowType === "bool") return x === 1;
    return x;
  }
  if (c.kind === "bigint") return c.missing[i] ? null : c.values[i];
  if (c.kind === "dictionary") return c.missing[i] ? null : c.values[c.codes[i]];
  if (c.missing[i]) return null;
  const v = c.values[i];
  if (v instanceof Uint8Array) return Array.from(v);
  // pyarrow reads ENUM as binary; plan 0018 reads it as text.
  if (arrowType === "binary" && /ENUM/.test(variable.logicalType)) return Array.from(new TextEncoder().encode(v));
  return v;
}

function same(a, b) {
  if (typeof a === "bigint" || typeof b === "bigint") {
    return (typeof a === "number" ? BigInt(a) : a) === (typeof b === "number" ? BigInt(b) : b);
  }
  if (typeof a === "number" && typeof b === "string" && /^-?\d+(\.\d+)?$/.test(b)) return a === Number(b);
  return Object.is(a, b) || (a === 0 && b === 0) || JSON.stringify(a) === JSON.stringify(b);
}

/** Check every column of `doc` read over rows start..start+count. */
export function checkFixture(reader, stem, doc, start, count) {
  for (const col of doc.columns) {
    const k = reader.variables.findIndex((v) => v.name === col.name);
    assert.ok(k >= 0, `${stem}.${col.name}`);
    const v = reader.variables[k];
    const [c] = reader.readColumns([k], { start, count });
    for (let i = 0; i < count; i++) {
      const want = col.values[start + i];
      const got = ours(c, i, v, col.arrow_type);
      assert.ok(same(got, want), `${stem}.${col.name} row ${start + i}: got ${String(got)}, want ${String(want)} (${col.arrow_type}, ${c.kind})`);
    }
  }
}
