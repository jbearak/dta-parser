// Benchmark tasks for TypeScript's .dta readers; bench/run.py drives this.
//   node bench/cases/case.mjs READER FILE OUT TASKS RUNS COLS SKIP N
// READER is ours (@jbearak/dta-parser, built in js/) or statfmt
// (@irbisadm/statfmt, installed in bench/node/). The arguments are as in
// bench/cases/case.py.
import { createHash } from "node:crypto";
import * as fs from "node:fs";
import { createRequire } from "node:module";
import * as path from "node:path";

const [reader, file, outPath, tasks, runsArg, colsArg, skipArg, nArg] = process.argv.slice(2);
const runs = Number(runsArg), skip = Number(skipArg), n = Number(nArg);
const cols = colsArg ? colsArg.split(",") : [];
const tmp = path.dirname(path.resolve(outPath));
const here = path.dirname(new URL(import.meta.url).pathname);

const require = createRequire(import.meta.url);
const ours = reader === "ours" ? require("../../js/dist/node.js") : null;
// The checks re-read written files with statfmt.
const statfmt = reader === "statfmt" || tasks === "check" ? await import(path.join(here, "../node/node_modules/@irbisadm/statfmt/dist/index.js")) : null;
const loaded = Date.now() / 1000;

const version = reader === "ours"
  ? JSON.parse(fs.readFileSync(path.join(here, "../../js/package.json"))).version
  : JSON.parse(fs.readFileSync(path.join(here, "../node/node_modules/@irbisadm/statfmt/package.json"))).version;

// A whole file in memory, as statfmt needs; readFileSync stops at 2 GiB.
function slurp(p) {
  const size = fs.statSync(p).size;
  const buf = Buffer.allocUnsafe(size);
  const fd = fs.openSync(p, "r");
  for (let at = 0; at < size;) at += fs.readSync(fd, buf, at, Math.min(size - at, 1 << 30), at);
  fs.closeSync(fd);
  return new Uint8Array(buf.buffer, buf.byteOffset, size);
}

// Each reader's result as { names, columns: [{ kind, values, missing? }] }.
function oursRead(p, which, range) {
  const r = ours.openDtaFile(p);
  try {
    const columns = r.readColumns(which ?? r.variables.map((_, i) => i), range);
    return { columns };
  } finally {
    r.close();
  }
}

function oursMeta(p) {
  const r = ours.openDtaFile(p);
  try {
    const sets = {};
    for (const v of r.variables) if (v.valueLabels && !(v.valueLabels in sets)) sets[v.valueLabels] = r.valueLabels(v.valueLabels);
    return { info: r.info, variables: r.variables, sets, notes: r.notes(), characteristics: r.characteristics() };
  } finally {
    r.close();
  }
}

// Columns go back as readColumns gave them, with the file's metadata.
function oursWrite(result, meta, dst) {
  const variables = result.columns.map((c, i) => {
    const v = meta.variables[i];
    const type = v.type.startsWith("str") ? (v.type === "strL" ? "strL" : undefined) : v.type;
    return { name: v.name, values: c.values, missing: c.missing, type, format: v.format, label: v.label,
             valueLabels: v.valueLabels };
  });
  ours.writeDtaFile(dst, { variables, label: meta.info.label, valueLabels: meta.sets, notes: meta.notes,
                           characteristics: meta.characteristics, sortedBy: meta.info.sortedBy,
                           timestamp: meta.info.timestamp });
}

const STRING = 0, STRING_REF = 6;
function statfmtColumns(ds) {
  const columns = ds.variables.map((v) => {
    const text = v.type === STRING || v.type === STRING_REF;
    return { kind: text ? "string" : "number", values: [], var: v };
  });
  for (const row of ds.rows) for (let j = 0; j < columns.length; j++) columns[j].values.push(row[j]);
  return { columns };
}

function statfmtWrite(ds, dst) {
  const valueLabelSets = {};
  for (const v of ds.variables) {
    if (v.valueLabelsName && v.valueLabels) valueLabelSets[v.valueLabelsName] = v.valueLabels.map((l) => ({ value: l.value, label: l.label }));
  }
  const variables = ds.variables.map((v) => ({
    name: v.name, type: v.type, storageWidth: v.storageWidth, label: v.label ?? undefined,
    format: v.format ?? undefined, valueLabels: v.valueLabelsName ?? undefined,
  }));
  const bytes = statfmt.writeDta({ variables, rows: ds.rows, valueLabelSets, fileLabel: ds.metadata.fileLabel ?? undefined, version: 118 });
  fs.writeFileSync(dst, bytes);
}

const readers = {
  ours: {
    read: (p) => oursRead(p),
    five: (p, c) => oursRead(p, c),
    window: (p, s, k) => oursRead(p, undefined, { start: s, count: k }),
    meta: oursMeta,
    // Writing needs the metadata too; it is read outside the timing.
    prepare: (p, result) => { const meta = oursMeta(p); return (dst) => oursWrite(result, meta, dst); },
    frame: (result) => result,
  },
  statfmt: {
    read: (p) => statfmt.readDta(slurp(p)),
    // statfmt reads whole files; it has no column selection.
    five: (p, c) => {
      const ds = statfmt.readDta(slurp(p));
      const idx = c.map((name) => ds.variables.findIndex((v) => v.name === name));
      return ds.rows.map((row) => idx.map((j) => row[j]));
    },
    window: (p, s, k) => statfmt.readDta(slurp(p), { rowOffset: s, rowLimit: k }),
    meta: (p) => statfmt.readDta(slurp(p), { rowLimit: 1 }),
    prepare: (p, ds) => (dst) => statfmtWrite(ds, dst),
    frame: (ds) => statfmtColumns(ds),
  },
};
const r = readers[reader];
// In-process runs stop early, after at least three, once they pass this
// many seconds.
const BUDGET = 60;

// Task 2: one pass over every value.
function checksum(result) {
  let sum = 0, missing = 0, length = 0;
  if (reader === "ours") {
    for (const c of result.columns) {
      if (c.kind === "string") for (const s of c.values) length += s.length;
      else for (let i = 0; i < c.values.length; i++) c.missing[i] ? missing++ : (sum += c.values[i]);
    }
  } else {
    const text = result.variables.map((v) => v.type === STRING || v.type === STRING_REF);
    for (const row of result.rows) {
      for (let j = 0; j < row.length; j++) {
        const x = row[j];
        if (text[j]) length += x === null ? 0 : x.length;
        else if (x === null) missing++;
        else sum += x;
      }
    }
  }
  return { sum, missing, length };
}

function runTask(task) {
  if (task === 6) {
    const result = r.read(file);
    const write = r.prepare(file, result);
    const dst = path.join(tmp, `w${process.pid}.dta`);
    globalThis.gc?.();
    const t = performance.now();
    write(dst);
    const elapsed = (performance.now() - t) / 1000;
    fs.rmSync(dst, { force: true });
    return [elapsed, null];
  }
  globalThis.gc?.();
  const t = performance.now();
  let out = null;
  if (task === 1) r.read(file);
  else if (task === 2) out = checksum(r.read(file));
  else if (task === 3) r.five(file, cols);
  else if (task === 4) r.window(file, skip, n);
  else if (task === 5) r.meta(file);
  return [(performance.now() - t) / 1000, out];
}

// Correctness: each column as a hash of its canonical cells.
const short = (h) => h.digest("hex").slice(0, 16);
const hashText = (s) => (s === null || s === undefined ? null : short(createHash("sha256").update(String(s))));

function canonColumn(c) {
  if (c.kind === "string") {
    const h = createHash("sha256");
    for (const s of c.values) {
      if (s !== null) h.update(typeof s === "string" ? s : Buffer.from(s));
      h.update("\0");
    }
    h.update(String(c.values.length));
    return { kind: "str", hash: short(h) };
  }
  const len = c.values.length;
  const v = new Float64Array(len), miss = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    const missing = c.missing ? c.missing[i] !== 0 : c.values[i] === null;
    miss[i] = missing ? 1 : 0;
    v[i] = missing ? 0 : c.values[i];
  }
  const h = createHash("sha256").update(new Uint8Array(v.buffer)).update(miss);
  return { kind: "num", hash: short(h), codes: c.missing ? short(createHash("sha256").update(c.missing)) : null };
}

const canonFrame = (f) => ({ nrows: f.columns.length ? f.columns[0].values.length : 0, columns: f.columns.map(canonColumn) });

const keyText = (k) => (typeof k === "number" ? String(k) : k && k.missing ? k.missing : String(k));
function labelText(pairs) {
  if (!pairs) return hashText("");
  return hashText(pairs.map(([k, v]) => `${keyText(k)}\t${v}`).sort().join("\n"));
}

const STORAGE = { 1: "byte", 2: "int", 3: "long", 4: "float", 5: "double", 0: "str", 6: "strL" };
function canonMeta(p, who) {
  if (who === "ours") {
    const m = oursMeta(p);
    const columns = m.variables.map((v) => ({
      name: hashText(v.name), storage: v.type, format: v.format, label: hashText(v.label),
      value_labels: labelText(v.valueLabels ? [...m.sets[v.valueLabels].entries()] : null),
    }));
    return { label: hashText(m.info.label), columns };
  }
  const ds = statfmt.readDta(slurp(p), { rowLimit: 1 });
  const columns = ds.variables.map((v) => ({
    name: hashText(v.name), storage: STORAGE[v.type], format: v.format, label: hashText(v.label ?? ""),
    value_labels: labelText(v.valueLabels ? v.valueLabels.map((l) => [l.value, l.label]) : null),
  }));
  return { label: hashText(ds.metadata.fileLabel ?? ""), columns };
}

function attempt(f) {
  try {
    return f();
  } catch (e) {
    return { error: String(e && e.message ? `${e.name}: ${e.message}` : e).slice(0, 500) };
  }
}

function check() {
  const out = {};
  let result = null;
  out.full = attempt(() => { result = r.read(file); return canonFrame(r.frame(result)); });
  if (result) out.checksum = attempt(() => {
    const s = checksum(result);
    let abs = 0;
    for (const c of r.frame(result).columns) if (c.kind === "number") for (const x of c.values) if (x !== null && !Number.isNaN(x)) abs += Math.abs(x);
    return { ...s, abs };
  });
  out.five = attempt(() => {
    const f = r.five(file, cols);
    if (reader === "ours") return canonFrame(f);
    // statfmt's selection is rows of the five columns; make columns.
    const ds = statfmt.readDta(slurp(file), { rowLimit: 1 });
    const kinds = cols.map((name) => ds.variables.find((v) => v.name === name));
    return canonFrame({ columns: kinds.map((v, j) => ({
      kind: v.type === STRING || v.type === STRING_REF ? "string" : "number", values: f.map((row) => row[j]) })) });
  });
  out.window = attempt(() => canonFrame(r.frame(r.window(file, skip, n))));
  out.meta = attempt(() => canonMeta(file, reader));
  if (result) {
    const dst = path.join(tmp, `check${process.pid}.dta`);
    out.write = attempt(() => {
      try {
        r.prepare(file, result)(dst);
        result = null;
        // Re-read by the other npm reader (statfmt), as is the source.
        return { data: canonFrame(statfmtColumns(statfmt.readDta(slurp(dst)))), meta: canonMeta(dst, "statfmt") };
      } finally {
        fs.rmSync(dst, { force: true });
      }
    });
  }
  return out;
}

const report = { loaded, version };
if (tasks === "check") {
  report.check = check();
} else {
  report.tasks = {};
  for (const task of tasks.split(",").map(Number)) {
    const entry = {};
    try {
      entry.times = [];
      let nRuns = runs;
      if (runs > 1) {
        [entry.first, entry.checksum] = runTask(task);
        // Too slow to repeat: the one run counts.
        if (entry.first > BUDGET) [entry.times, nRuns] = [[entry.first], 0];
      }
      for (let i = 0; i < nRuns; i++) {
        const [seconds, sum] = runTask(task);
        entry.times.push(seconds);
        entry.checksum = sum;
        if (entry.times.length >= 3 && entry.times.reduce((a, b) => a + b) > BUDGET) break;
      }
    } catch (e) {
      entry.error = String(e && e.message ? `${e.name}: ${e.message}` : e).slice(0, 500);
    }
    report.tasks[String(task)] = entry;
  }
}
fs.writeFileSync(outPath, JSON.stringify(report));
