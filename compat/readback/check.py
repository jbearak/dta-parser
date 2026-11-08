"""Check that haven, readstata13, pandas and pyreadstat read each file our
writers saved (compat/readback/write.*) as they read its input.

<dir>/original holds the inputs: the fixtures, strls.dta and binary.dta.
<dir>/<writer> holds each writer's copies. compat/readback/dump.R has
already dumped what haven and readstata13 read from every file, as
<file>.haven.json and <file>.readstata13.json; pandas and pyreadstat
are read here. Each copy must read, field by field and cell by cell, as
its input reads in the same reader, and strls.dta and binary.dta,
inputs and copies, as make_inputs.spec() gives them. Where a reader
cannot be an oracle for a field, KNOWN skips it with the reason
(docs/other-readers.md).

Run from the repository root: python3 compat/readback/check.py <dir>
"""

import ast
import fnmatch
import glob
import json
import math
import os
import sys

import pyreadstat

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from expected import dump as pandas_dump  # noqa: E402
from make_inputs import spec  # noqa: E402

WRITERS = ["dtaparser", "dtatools", "python", "julia", "npm"]
READERS = ["haven", "readstata13", "pandas", "pyreadstat"]
R_WRITERS = {"dtaparser", "dtatools"}

BUILT = ("strls", "binary")  # inputs made by make_inputs.py, checked against spec()

LATIN1 = "pandas decodes text before 118 as Latin-1, not Windows-1252; our copies are UTF-8"
NO_BINARY_IN_R = "R holds no binary strings and dtaparser reads no binary strLs, so the R writers do not save binary.dta"
DTAPARSER_META = "dtaparser's read_dta keeps no display format or storage type (plan 0006), so save_dta chooses them afresh"
STRL_AS_TEXT = "reads every strL as UTF-8 text, so it cannot open a file with a binary strL that is not UTF-8"
RS13_BINARY = "readstata13 reads a binary strL as text, which R ends at the first NUL"
HAVEN_119 = "haven 2.5.5 wrote this 119 file's strL references in the 118 layout, which this reader reads " \
    "with the 119 layout, so the input is no oracle; our copies are 118"
HAVEN_119_READ = "haven 2.5.5 reads 119 strL references in the 118 layout (fixed upstream, docs/other-readers.md); our copies are 118"
PANDAS_EMPTY_STRL = "pandas writes an empty strL as a (0, 0) reference with no entry, which readstata13 reads as NA; " \
    "our writers write an entry holding \"\", as haven does, which it reads as \"\""
OLD_LABELS = "this reader does not read value labels of this release (docs/other-readers.md); our copies are 118"

# (reader, writer or "*", file stem prefix, field pattern): why that
# reader's value is not compared there. A field is "read", "write",
# "names", "data_label", "text" (any text in a file) or
# "<variable>.<label|labels|format|type|values>"; patterns as fnmatch.
KNOWN = {
    ("pandas", "*", "haven_113", "text"): LATIN1,
    ("pandas", "*", "haven_114", "text"): LATIN1,
    ("pandas", "*", "haven_115", "text"): LATIN1,
    ("pandas", "*", "haven_117", "text"): LATIN1,
    ("readstata13", "*", "haven_119", "big.values"): HAVEN_119,
    ("pyreadstat", "*", "haven_119", "big.values"): HAVEN_119,
    ("haven", "*", "pandas_119", "strl.values"): HAVEN_119_READ,
    ("readstata13", "*", "pandas_11", "strl.values"): PANDAS_EMPTY_STRL,
    ("haven", "*", "readstat_104", "*.labels"): OLD_LABELS,
    ("haven", "*", "readstat_108", "*.labels"): OLD_LABELS,
    ("readstata13", "*", "readstat_104", "*.labels"): OLD_LABELS,
    ("readstata13", "*", "readstat_105", "*.labels"): OLD_LABELS,
    ("haven", "*", "binary", "read"): "haven 2.5.5 " + STRL_AS_TEXT,
    ("pyreadstat", "*", "binary", "read"): "pyreadstat " + STRL_AS_TEXT,
    ("readstata13", "*", "binary", "blob.values"): RS13_BINARY,
}
for r in READERS:
    KNOWN[(r, "dtaparser", "*", "*.format")] = DTAPARSER_META
    if r != "haven":  # haven gives no storage type
        KNOWN[(r, "dtaparser", "*", "*.type")] = DTAPARSER_META
    for w in R_WRITERS:
        KNOWN[(r, w, "binary", "write")] = NO_BINARY_IN_R


USED = set()


def known(reader, writer, stem, field):
    for key, why in KNOWN.items():
        r, w, prefix, pattern = key
        if r == reader and w in ("*", writer) and fnmatch.fnmatch(stem, prefix + "*") and fnmatch.fnmatch(field, pattern):
            USED.add(key)
            return why
    return None


def bytes_literal(v):
    """pandas gives a binary strL as the text of a Python bytes literal,
    b'...', holding the exact bytes: those bytes, or None."""
    if isinstance(v, str) and v[:2] in ("b'", 'b"'):
        try:
            b = ast.literal_eval(v)
        except (ValueError, SyntaxError):
            return None
        return b if isinstance(b, bytes) else None
    return None


def cell(v):
    """A cell as check.py compares it: a float, text, {"missing": ".a"},
    or {"hex": ...} for bytes."""
    if isinstance(v, dict):
        return v
    if isinstance(v, (bytes, bytearray)):
        return {"hex": bytes(v).hex()}
    if isinstance(v, bool):
        return float(v)
    if isinstance(v, (int, float)):
        return {"missing": "."} if isinstance(v, float) and math.isnan(v) else float(v)
    if hasattr(v, "item"):
        return cell(v.item())
    return v


def code_key(k):
    return k if isinstance(k, str) else float(k)


def normal(d):
    """{data_label, names, variables: {name: {...}}, values: {name: [...]}}."""
    variables = {}
    for v in d["variables"]:
        variables[v["name"]] = {
            "label": v.get("label") or "",
            "labels": {str(code_key(k)): t for k, t in (v.get("labels") or [])},
            "format": v.get("format"),
            "type": v.get("type"),
        }
    return {
        "data_label": d.get("data_label") or "",
        "names": [v["name"] for v in d["variables"]],
        "variables": variables,
        "values": {k: [cell(x) for x in xs] for k, xs in d["values"].items()},
    }


PYREADSTAT_TYPES = {"int8": "byte", "int16": "int", "int32": "long", "float": "float", "double": "double"}


def pyreadstat_dump(path):
    df, meta = pyreadstat.read_dta(path, user_missing=True, disable_datetime_conversion=True)
    variables, values = [], {}
    for i, name in enumerate(df.columns):
        kind = meta.readstat_variable_types[name]
        numeric = kind in PYREADSTAT_TYPES
        table = meta.variable_value_labels.get(name, {})
        variables.append({
            "name": name,
            "type": PYREADSTAT_TYPES[kind] if numeric else None,
            "format": meta.original_variable_types[name],
            "label": meta.column_labels[i] or "",
            "labels": [["." + k if isinstance(k, str) else k, t] for k, t in table.items()],
        })
        if numeric:
            values[name] = [{"missing": "." + v} if isinstance(v, str) else v for v in df[name].tolist()]
        else:
            values[name] = ["" if v is None or (isinstance(v, float) and v != v) else v for v in df[name].tolist()]
    return {"data_label": meta.file_label or "", "variables": variables, "values": values}


def read(reader, path):
    """What `reader` reads from `path`, normalised, or {"error": ...}."""
    try:
        if reader in ("haven", "readstata13"):
            with open(f"{path}.{reader}.json") as f:
                d = json.load(f)
            if "error" in d:
                return d
        elif reader == "pandas":
            d = pandas_dump(path)
        else:
            d = pyreadstat_dump(path)
    except Exception as e:  # a reader that fails is reported, not skipped
        return {"error": f"{type(e).__name__}: {e}"}
    return normal(d)


def release(path):
    with open(path, "rb") as f:
        head = f.read(64)
    return head[head.index(b"<release>") + 9:head.index(b"</release>")].decode()


def differences(reader, writer, stem, ours, theirs, compare_types):
    """Fields where `ours` (a writer's copy) differs from `theirs`."""
    out = []

    def check(field, a, b, text=False):
        if a == b:
            return
        why = known(reader, writer, stem, field) or (text and known(reader, writer, stem, "text"))
        if why:
            return
        if isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
            i = next(i for i, (p, q) in enumerate(zip(a, b)) if p != q)
            a, b = f"row {i + 1}: {a[i]!r:.60}", f"{b[i]!r:.60}"
        else:
            a, b = f"{a!r:.80}", f"{b!r:.80}"
        out.append(f"{reader} reading {writer}/{stem}.dta: {field}: {a}, expected {b}")

    check("data_label", ours["data_label"], theirs["data_label"], text=True)
    check("names", ours["names"], theirs["names"])
    for name, b in theirs["variables"].items():
        a = ours["variables"].get(name)
        if a is None:
            if not known(reader, writer, stem, f"{name}.values"):
                out.append(f"{reader} reading {writer}/{stem}.dta: {name} is missing")
            continue
        check(f"{name}.label", a["label"], b["label"], text=True)
        check(f"{name}.labels", a["labels"], b["labels"], text=True)
        if b.get("format") is not None and a.get("format") is not None:
            check(f"{name}.format", a["format"], b["format"])
        # Our writers choose string widths afresh; numeric types are kept.
        if compare_types and b.get("type") and not str(b["type"]).startswith("str"):
            check(f"{name}.type", a["type"], b["type"])
        got = ours["values"].get(name)
        if reader == "pandas" and got is not None and len(got) == len(theirs["values"][name]):
            got = [{"hex": bytes_literal(a).hex()} if isinstance(b, dict) and "hex" in b and bytes_literal(a) is not None
                   else a for a, b in zip(got, theirs["values"][name])]
        check(f"{name}.values", got, theirs["values"][name], text=True)
    return out


def main():
    root = sys.argv[1]
    originals = sorted(glob.glob(os.path.join(root, "original", "*.dta")))
    failures = []
    counts = {}  # (writer, reader) -> files compared

    def compare(reader, writer, stem, ours, theirs, compare_types):
        counts[(writer, reader)] = counts.get((writer, reader), 0) + 1
        if "error" in ours:
            if not known(reader, writer, stem, "read"):
                failures.append(f"{reader} cannot read {writer}/{stem}.dta: {ours['error']}")
            return
        failures.extend(differences(reader, writer, stem, ours, theirs, compare_types))

    for path in originals:
        stem = os.path.splitext(os.path.basename(path))[0]
        expected = normal(spec(stem)) if stem in BUILT else None
        for reader in READERS:
            original = read(reader, path)
            if expected:
                # The input itself must read as built.
                compare(reader, "original", stem, original, expected, False)
            theirs = expected or original
            if "error" in theirs:
                continue  # this reader cannot read the input: it is no oracle for it
            for writer in WRITERS:
                copy = os.path.join(root, writer, os.path.basename(path))
                if not os.path.exists(copy):
                    if not known(reader, writer, stem, "write"):
                        failures.append(f"{writer} wrote no {stem}.dta")
                    continue
                if reader == READERS[0] and release(copy) != "118":
                    failures.append(f"{writer}/{stem}.dta is release {release(copy)}, not 118")
                compare(reader, writer, stem, read(reader, copy), theirs, not expected)

    print("files compared, by writer and reader:")
    print(f"{'':12}" + "".join(f"{r:>13}" for r in READERS))
    for w in ["original"] + WRITERS:
        print(f"{w:12}" + "".join(f"{counts.get((w, r), 0):>13}" for r in READERS))
    unused = [k for k in KNOWN if k not in USED]
    if unused:
        # A reader that now agrees: the exception can go.
        print("\nknown exceptions that matched nothing:\n" + "\n".join(map(str, unused)))
    if failures:
        print(f"\n{len(failures)} differences:")
        print("\n".join(failures))
        sys.exit(1)
    print("\nevery copy reads as its input in every reader")


if __name__ == "__main__":
    main()
