#!/bin/sh
# TypeScript's readFixedWidth against R's read_fixed_width (plan 0021):
# both read compat/fixed_width/synthetic.dat through synthetic.sas, in
# each recodes mode, and every cell (value, `.` or which of `.a` to `.z`),
# variable label and value label must agree. Both call one Rust function,
# so this checks what each package makes of its output.
#
#     sh compat/fixed_width/cross_language.sh [DIR]
#
# Run from the repository root with js/ and js/datakit/ built and R's
# datakit installed (R_LIBS may point at a scratch library).
set -e
DIR=${1:-$(mktemp -d)}
mkdir -p "$DIR"
for mode in setup tagged none; do
  Rscript -e '
suppressPackageStartupMessages(library(datakit))
a <- commandArgs(TRUE)
d <- read_fixed_width("compat/fixed_width/synthetic.dat", "compat/fixed_width/synthetic.sas", recodes = a[1])
cell <- function(x) {
  v <- unclass(x)
  if (is.character(v)) return(ifelse(is.na(v), "", v))
  out <- sprintf("%.17g", v)
  tag <- ifelse(is.na(v), na_tag(v), NA)
  out[is.na(v)] <- ifelse(is.na(tag[is.na(v)]), ".", paste0(".", tag[is.na(v)]))
  out
}
labs <- function(x) {
  l <- attr(x, "labels")
  if (is.null(l)) return(list())
  t <- na_tag(l)
  as.list(setNames(names(l), ifelse(is.na(t), sprintf("%.17g", unclass(l)), paste0(".", t))))
}
out <- lapply(names(d), function(n) list(name = n, label = attr(d[[n]], "label") %||% "", cells = I(cell(d[[n]])), labels = labs(d[[n]])))
jsonlite::write_json(out, file.path(a[2], paste0("r_", a[1], ".json")), auto_unbox = TRUE)
' "$mode" "$DIR"
  node -e '
const node = require("./js/datakit/dist/node.js");
const [mode, dir] = process.argv.slice(1);
const want = JSON.parse(require("fs").readFileSync(`${dir}/r_${mode}.json`, "utf8"));
const ds = node.readFixedWidth("compat/fixed_width/synthetic.dat", "compat/fixed_width/synthetic.sas", { recodes: mode, onWarning() {} });
const NAMES = [".", ...Array.from("abcdefghijklmnopqrstuvwxyz", (c) => `.${c}`)];
const fmt = (x) => { const s = x.toPrecision(17); return String(Number(s)) === String(x) ? String(Number(s)) : s; };
let n = 0; const bad = [];
for (const w of want) {
  const v = ds.variables.find((x) => x.name === w.name);
  if (!v) { bad.push(`${w.name}: missing`); continue; }
  const c = v.values;
  const cells = c.kind === "string" ? c.values : Array.from(c.values, (x, i) => (c.missing[i] ? NAMES[c.missing[i] - 1] : x));
  cells.forEach((x, i) => { n++; const r = w.cells[i]; const ok = typeof x === "number" ? Number(r) === x : x === r; if (!ok) bad.push(`${w.name} row ${i + 1}: ${x}, R ${r}`); });
  if (v.label !== w.label) bad.push(`${w.name}: label ${v.label}, R ${w.label}`);
  const set = v.valueLabels ? ds.valueLabels[v.valueLabels] : new Map();
  const ours = Object.fromEntries([...set].map(([k, t]) => [typeof k === "object" ? k.missing : String(k), t]));
  const theirs = Object.fromEntries(Object.entries(w.labels).map(([k, t]) => [k.startsWith(".") ? k : String(Number(k)), t]));
  if (JSON.stringify(Object.entries(ours).sort()) !== JSON.stringify(Object.entries(theirs).sort())) bad.push(`${w.name}: labels ${JSON.stringify(ours)}, R ${JSON.stringify(theirs)}`);
}
if (want.length !== ds.variables.length) bad.push(`variables: ${ds.variables.length}, R ${want.length}`);
console.log(`recodes ${mode}: ${n} cells of ${want.length} variables compared with R`);
if (bad.length) { console.log(bad.slice(0, 20).join("\n")); process.exit(1); }
' "$mode" "$DIR"
done
