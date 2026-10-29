"""Build the NSFG benchmark files: inventory CDC's public-use NSFG files,
download them, and convert each data file to a release-118 .dta with pandas.

    python bench/nsfg/make.py [--raw DIR] [--out DIR] [--only STEM ...]

Writes bench/nsfg/inventory.json and bench/nsfg/REPORT.md. See README.md.
The dictionary (.dct), label (.do) and SAS program grammars handled here
were learned from the CDC files themselves.
"""

import argparse
import hashlib
import io
import json
import re
import sys
import time
import urllib.request
import warnings
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd
import pyreadstat

HERE = Path(__file__).resolve().parent
ROOTS = [
    "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/NSFG/",
    "https://ftp.cdc.gov/pub/Health_Statistics/NCHS/nsfg/",
]
D = "Datasets/NSFG/"

# Every data file and how to read it. Paths are relative to .../NCHS/.
#   dct/do: Stata dictionary and label program; sas: SAS program (the
#   layout when there is no .dct, else a cross-check); select: (first
#   column, last column, test) keeps records whose field passes, as the
#   SAS program does for files holding two record types; ids: columns
#   that together must be unique.
SOURCES = [
    dict(stem="1973_FemResp", cycle="1973 (Cycle 1)", data=D + "1973NSFGData.dat",
         sas=D + "sas/1973FemRespSetup.sas", ids=["INT_ID"]),
    dict(stem="1976_FemResp", cycle="1976 (Cycle 2)", data=D + "1976NSFGData.dat",
         sas=D + "sas/1976FemRespSetup.sas", select=(6, 6, lambda v: v <= 4),
         ids=["RESPID"]),
    dict(stem="1976_Preg", cycle="1976 (Cycle 2)", data=D + "1976NSFGData.dat",
         sas=D + "sas/1976PregSetup.sas", select=(6, 6, lambda v: v >= 5),
         ids=["ID", "BPREC1"]),
    dict(stem="1976_PSU", cycle="1976 (Cycle 2)", data=D + "cyc2psu.sas7bdat",
         ids=["RESPID"]),
    dict(stem="1982_FemResp", cycle="1982 (Cycle 3)", data=D + "1982NSFGData.dat",
         sas=D + "sas/1982FemRespSetup.sas", select=(1499, 1500, lambda v: v == 0),
         ids=["CASEID"]),
    dict(stem="1982_Preg", cycle="1982 (Cycle 3)", data=D + "1982NSFGData.dat",
         sas=D + "sas/1982PregSetup.sas", select=(1499, 1500, lambda v: v > 0),
         ids=["CASEID", "BPRec"]),
    dict(stem="1988_FemResp", cycle="1988 (Cycle 4)", data=D + "1988FemRespData.dat",
         sas=D + "sas/1988FemRespSetup.sas", ids=["caseid"]),
    dict(stem="1988_Preg", cycle="1988 (Cycle 4)", data=D + "1988PregData.dat",
         sas=D + "sas/1988PregSetup.sas", ids=["SEQNUM", "PREG_NUM"]),
    dict(stem="1995_FemResp", cycle="1995 (Cycle 5)", data=D + "1995FemRespData.dat",
         sas=D + "sas/1995FemRespSetup.sas", ids=["CASEID"]),
    dict(stem="1995_Preg", cycle="1995 (Cycle 5)", data=D + "1995PregData.dat",
         sas=D + "sas/1995FemPregFile.sas", ids=["CASEID", "PREGORDR"]),
    dict(stem="2002_FemPreg", cycle="2002 (Cycle 6)", data=D + "2002FemPreg.dat",
         dct=D + "stata/2002FemPreg.dct", do=D + "stata/2002FemPreg.do",
         sas=D + "sas/2002FemPregInput.sas", ids=["caseid", "pregordr"]),
    dict(stem="2002_FemResp", cycle="2002 (Cycle 6)", data=D + "2002FemResp.dat",
         dct=D + "stata/2002FemResp.dct", do=D + "stata/2002FemResp.do",
         sas=D + "sas/2002FemRespInput.sas", ids=["caseid"]),
    dict(stem="2002_Male", cycle="2002 (Cycle 6)", data=D + "2002Male.dat",
         dct=D + "stata/2002Male.dct", do=D + "stata/2002Male.do",
         sas=D + "sas/2002MaleInput.sas", ids=["caseid"]),
    dict(stem="2002_HHvars", cycle="2002 (Cycle 6)", data=D + "2002HHvars.dat",
         sas=D + "sas/2002HHvars.SAS", ids=["CASEID", "R_SEX"]),
    dict(stem="2002_curr_ins", cycle="2002 (Cycle 6)", data=D + "c6_curr_ins.sas7bdat",
         ids=["CASEID", "R_SEX"]),
    dict(stem="2002_hhpartypnew", cycle="2002 (Cycle 6)", data=D + "hhpartypnew.sas7bdat",
         ids=["CASEID", "R_SEX"]),
]
for years in ["2006_2010", "2011_2013", "2013_2015", "2015_2017", "2017_2019"]:
    cycle = years.replace("_", "–")
    data = {"2006_2010": ("FemPreg", "FemResp", "Male")}.get(
        years, ("FemPregData", "FemRespData", "MaleData"))
    for kind, dat in zip(("FemPreg", "FemResp", "Male"), data):
        SOURCES.append(dict(
            stem=f"{years}_{kind}", cycle=cycle, data=f"{D}{years}_{dat}.dat",
            dct=f"{D}stata/{years}_{kind}Setup.dct", do=f"{D}stata/{years}_{kind}Setup.do",
            sas=f"{D}sas/{years}_{kind}Setup.sas",
            ids=["caseid", "pregordr"] if kind == "FemPreg" else ["caseid"]))
for sex, setup in [("Female", "Female"), ("Male", "Male")]:
    SOURCES.append(dict(
        stem=f"2011_2019_{sex}Wgt", cycle="2011–2019", data=f"{D}2011_2019_{sex}WgtData.dat",
        dct=f"{D}stata/2011_2019_{setup}WgtSetup.dct", do=f"{D}stata/2011_2019_{setup}WgtSetup.do",
        sas=f"{D}sas/2011_2019_{setup}WgtSetup.sas", ids=["caseid"]))
for kind in ["FemPreg", "FemResp", "MaleResp"]:
    SOURCES.append(dict(
        stem=f"2022_2023_{kind}", cycle="2022–2023", data=f"nsfg/NSFG-2022-2023-{kind}PUFData.sas7bdat",
        csv_zip=f"nsfg/NSFG-2022-2023-{kind}PUFData.zip",
        ids=["CaseID", "PREGORDR"] if kind == "FemPreg" else ["CaseID"]))

# Files listed but not converted, and why.
EXCLUDED = {
    D + ".cache": "zero-byte server artifact (the listing shows it; fetching it gives 404); not data",
    D + ".cache+": "zero-byte server artifact (the listing shows it; fetching it gives 404); not data",
    D + "C5FieldworkData.asc": "a Cycle 5 (1995) fieldwork file, by its name: 14,000 fixed-width "
                               "records with no layout anywhere in CDC's directories (no .dct, SAS "
                               "or SPSS program names it), so its columns cannot be named",
    D + "2002curr_ins.dat": "fixed-width copy of c6_curr_ins.sas7bdat, with no layout program; the "
                            "sas7bdat is converted and its row count is checked against this file",
    D + "HHPARTYPNEWASC.DAT": "fixed-width copy of hhpartypnew.sas7bdat, with no layout program; the "
                              "sas7bdat is converted and its row count is checked against this file",
    "nsfg/NSFG-2022-2023-PUFData-SASFiles.zip": "a zip of the three 2022–2023 sas7bdat files that are "
                                                "also published unzipped (converted from those)",
}
for k in ["FemPreg", "FemResp", "MaleResp"]:
    EXCLUDED[f"nsfg/NSFG-2022-2023-{k}PUFData.zip"] = (
        "CSV copy of the matching sas7bdat (converted from that); its row count is checked "
        "against the sas7bdat")
# a text copy published beside a sas7bdat: (copy, sas7bdat stem)
TEXT_COPIES = {D + "2002curr_ins.dat": "2002_curr_ins", D + "HHPARTYPNEWASC.DAT": "2002_hhpartypnew"}


# ---------------------------------------------------------------- download

LISTING = re.compile(
    r'\d+/\d+/\d+\s+\d+:\d+ [AP]M\s+(&lt;dir&gt;|<dir>|\d+) <A HREF="([^"]+)">')


def list_dir(url, out, depth=0):
    """Every file under an IIS directory listing, as (url, size)."""
    html = urllib.request.urlopen(url, timeout=120).read().decode("latin-1")
    for size, href in LISTING.findall(html):
        full = "https://ftp.cdc.gov" + href
        if size.isdigit():
            out.append((full, int(size)))
        elif depth < 4:
            list_dir(full.rstrip("/") + "/", out, depth + 1)
    return out


def download(url, dest, size):
    if dest.exists() and dest.stat().st_size == size:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=600) as r, open(tmp, "wb") as f:
                while chunk := r.read(1 << 20):
                    f.write(chunk)
        except OSError as e:  # connection reset and the like: try again
            print(f"  {url}: {e}", file=sys.stderr)
        if tmp.exists() and tmp.stat().st_size == size:
            tmp.replace(dest)
            return
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"{url}: could not download {size} bytes after 5 tries")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def cycle_of(rel):
    name = rel.rsplit("/", 1)[1]
    for s in SOURCES:
        if s["data"] == rel:
            return s["cycle"]
    if m := re.match(r"NSFG-(\d{4})-(\d{4})", name):
        return f"{m[1]}–{m[2]}"
    if m := re.match(r"(\d{4})_(\d{4})", name):
        return f"{m[1]}–{m[2]}"
    if m := re.match(r"(\d{4})", name):
        return next((s["cycle"] for s in SOURCES if s["cycle"].startswith(m[1])), m[1])
    return {"C5FieldworkData.asc": "1995 (Cycle 5)", "HHPARTYPNEWASC.DAT": "2002 (Cycle 6)"}.get(name, "")


def role_of(rel):
    if rel in EXCLUDED:
        return "excluded"
    if any(s["data"] == rel for s in SOURCES):
        return "data"
    ext = rel.rsplit(".", 1)[-1].lower()
    return {"dct": "stata dictionary", "do": "stata label program",
            "sas": "sas program", "sps": "spss program"}.get(ext, "other")


def inventory(raw):
    files = []
    for root in ROOTS:
        list_dir(root, files)
    items = []
    for url, size in sorted(files):
        rel = url.split("/NCHS/", 1)[1]
        item = dict(cycle=cycle_of(rel), file=rel, size=size, url=url, role=role_of(rel))
        if rel.rsplit("/", 1)[1].startswith("."):
            item["sha256"] = None
        else:
            path = raw / rel
            download(url, path, size)
            item["sha256"] = sha256(path)
        if rel in EXCLUDED:
            item["excluded"] = EXCLUDED[rel]
        if item["role"] == "spss program":
            item["note"] = "listed only; the Stata and SAS programs give the same layouts"
        items.append(item)
    listed = {i["file"] for i in items}
    for s in SOURCES:
        for k in ("data", "dct", "do", "sas", "csv_zip"):
            if k in s and s[k] not in listed:
                raise RuntimeError(f"{s['stem']}: {s[k]} is not in CDC's listing")
    return items


# ---------------------------------------------------------------- .dct

DCT_LINE = re.compile(
    r'^\s*_column\((\d+)\)\s+(byte|int|long|float|double|str\d+)\s+(\w+)\s+'
    r'%(\d+)(?:\.\d+)?([fs])\s+"(.*)"\s*$')


def parse_dct(path):
    """Stata infile dictionary -> [dict(name, start, end, type, label)]."""
    cols = []
    for line in path.read_text("latin-1").splitlines():
        s = line.strip()
        if m := DCT_LINE.match(line):
            start, typ, name, width, _, label = m.groups()
            start, width = int(start), int(width)
            cols.append(dict(name=name, start=start, end=start + width - 1, type=typ, label=label))
        elif m := re.match(r"_lines\((\d+)\)", s):
            if m[1] != "1":
                raise ValueError(f"{path.name}: {s}: multi-line records are not handled")
        elif s.startswith("_column"):
            raise ValueError(f"{path.name}: cannot parse: {s}")
    return cols


# ---------------------------------------------------------------- .do

def do_statements(text):
    """Split a .do file into statements, honouring `#delimit ;`/`cr` and
    dropping /* */ and * comments."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    out, semi, buf = [], False, []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("#delimit"):
            semi = s.split()[1].startswith(";")
            continue
        if not semi:
            if s and not s.startswith("*"):
                out.append(s)
            continue
        if not buf and s.startswith("*"):
            continue
        buf.append(line)
        if ";" in line:
            parts = split_unquoted(" ".join(buf))
            out.extend(p.strip() for p in parts[:-1] if p.strip())
            buf = [parts[-1]] if parts[-1].strip() else []
    return out


def split_unquoted(text):
    """Split on semicolons outside double quotes (labels may hold them)."""
    parts, start, quoted = [], 0, False
    for i, ch in enumerate(text):
        if ch == '"':
            quoted = not quoted
        elif ch == ";" and not quoted:
            parts.append(text[start:i])
            start = i + 1
    parts.append(text[start:])
    return parts


def parse_do(path):
    """-> (data label, {set: {value: text}}, {variable: set})."""
    sets, attach, data_label = {}, {}, None
    for st in do_statements(path.read_text("latin-1")):
        if m := re.match(r'label\s+define\s+(\w+)\s+(.*?)(,\s*(add|modify|replace))?$', st, re.S):
            pairs = re.findall(r'(-?\d+)\s+"([^"]*)"', m[2])
            sets.setdefault(m[1], {}).update({int(v): t for v, t in pairs})
        elif m := re.match(r"label\s+values\s+(.+?)\s+(\w+)$", st):
            for v in m[1].split():
                attach[v] = m[2]
        elif m := re.match(r'label\s+data\s+"(.*)"', st):
            data_label = m[1]
    return data_label, sets, attach


# ---------------------------------------------------------------- SAS

SAS_TOKEN = re.compile(r"""'(?:[^']|'')*'|"(?:[^"]|"")*"|/\*.*?\*/|;|[^'";/]+|/""", re.S)


def sas_statements(text):
    """Split a SAS program into statements, keeping quoted text intact and
    dropping /* */ comments and * comment statements."""
    out, buf = [], []
    for tok in SAS_TOKEN.findall(text):
        if tok.startswith("/*"):
            buf.append(" ")
        elif tok == ";":
            st = "".join(buf).strip()
            st = re.sub(r"^\*/\s*", "", st)  # a stray `*/` left by a commented-out section
            if st and not st.startswith("*"):
                out.append(st)
            buf = []
        else:
            buf.append(tok)
    return out


def sas_unquote(q):
    return q[1:-1].replace(q[0] * 2, q[0])


def parse_sas(path):
    """-> dict(cols, labels, sets, formats, lrecl, fixed): the INPUT layout,
    LABEL text, PROC FORMAT value sets (integer keys only) and FORMAT links."""
    text = path.read_text("latin-1")
    cols, labels, sets, formats, skipped = [], {}, {}, {}, 0
    lrecl, fixed = None, False
    for st in sas_statements(text):
        if m := re.match(r"value\s+(\$?\w+)\s+(.*)$", st, re.S | re.I):
            if m[1].startswith("$"):
                continue
            items = re.findall(r"""([^=\s][^=]*?)\s*=\s*('(?:[^']|'')*'|"(?:[^"]|"")*")""", m[2])
            d = sets.setdefault(m[1].lower(), {})
            for key, q in items:
                if re.fullmatch(r"-?\d+", key.strip()):
                    d[int(key)] = sas_unquote(q)
                else:
                    skipped += 1
        elif m := re.match(r"format\s+(.*)$", st, re.S | re.I):
            pending = []
            for tok in m[1].split():
                if tok.endswith("."):
                    for v in pending:
                        formats[v.lower()] = tok[:-1].lower()
                    pending = []
                else:
                    pending.append(tok)
        elif re.match(r"infile\b", st, re.I):
            if m := re.search(r"lrecl\s*=\s*(\d+)", st, re.I):
                lrecl = int(m[1])
            fixed = bool(re.search(r"recfm\s*=\s*f\b", st, re.I))
        elif m := re.match(r"(?:else\s+)?input\b(?!\s*\()(.*)$", st, re.S | re.I):
            body = m[1].strip()
            if body.endswith("@"):
                continue  # `input rec_type 6 @`: reads the record type only
            cols = parse_sas_input(body, path.name)
        elif m := re.match(r"label\b(.*)$", st, re.S | re.I):
            for name, q in re.findall(r"""(\w+)\s*=\s*('(?:[^']|'')*'|"(?:[^"]|"")*")""", m[1]):
                labels[name.lower()] = sas_unquote(q)
    return dict(cols=cols, labels=labels, sets=sets, formats=formats,
                lrecl=lrecl, fixed=fixed, skipped_keys=skipped)


def parse_sas_input(body, name):
    """Column input (`NAME [$] a[-b]`) or sequential formatted input
    (`NAME [$]w.`)."""
    cols, pos = [], 1
    toks = body.split()
    i = 0
    while i < len(toks):
        var = toks[i]
        if not re.fullmatch(r"[A-Za-z_]\w*", var):
            raise ValueError(f"{name}: unexpected INPUT token {var!r}")
        i += 1
        is_str = toks[i] == "$"
        if is_str:
            i += 1
        spec = toks[i]
        i += 1
        if m := re.fullmatch(r"(\d+)(?:-(\d+))?", spec):
            start, end = int(m[1]), int(m[2] or m[1])
        elif m := re.fullmatch(r"\$?(\d+)\.(\d*)", spec):
            is_str = is_str or spec.startswith("$")
            start, end = pos, pos + int(m[1]) - 1
        else:
            raise ValueError(f"{name}: unexpected INPUT spec {var} {spec!r}")
        cols.append(dict(name=var, start=start, end=end, type="str" if is_str else "num"))
        pos = end + 1
    return cols


# ---------------------------------------------------------------- read

STATA_INT = [("Int8", -127, 100), ("Int16", -32767, 32740), ("Int32", -2147483647, 2147483620)]
DECLARED = {"byte": "Int8", "int": "Int16", "long": "Int32", "float": "float32", "double": "float64"}


def records(path, lrecl, fixed):
    """The file's records as a list of bytes (CR/LF stripped)."""
    b = path.read_bytes()
    if fixed or b"\n" not in b:
        if len(b) % lrecl:
            raise ValueError(f"{len(b)} bytes is not a whole number of {lrecl}-byte records")
        return [b[i:i + lrecl] for i in range(0, len(b), lrecl)]
    recs = b.split(b"\n")
    if recs[-1] == b"":
        recs.pop()
    return [r[:-1] if r.endswith(b"\r") else r for r in recs]


def narrow(s):
    """A float column of whole numbers -> the smallest Stata integer type
    (byte when every value is missing)."""
    v = s.dropna()
    if not len(v):
        return s.astype("Int8")
    if not np.all(np.mod(v, 1) == 0):
        return s
    for dt, lo, hi in STATA_INT:
        if v.min() >= lo and v.max() <= hi:
            return s.astype(dt)
    return s


def is_numeric(s):
    return pd.api.types.is_numeric_dtype(s.dtype)


def to_type(s, typ, notes):
    """Cast a parsed column to its declared Stata type, noting surprises."""
    if not is_numeric(s):  # text in a numeric field
        num = pd.to_numeric(s, errors="coerce")
        bad = int((num.isna() & s.notna()).sum())
        notes.append(f"{s.name}: {bad} non-numeric values set to missing")
        s = num
    if typ == "num":
        return narrow(s.astype("float64"))
    dt = DECLARED[typ]
    v = s.dropna()
    if dt.startswith("Int"):
        lo, hi = next((lo, hi) for d, lo, hi in STATA_INT if d == dt)
        if len(v) and (not np.all(np.mod(v, 1) == 0) or v.min() < lo or v.max() > hi):
            notes.append(f"{s.name}: declared {typ} but holds {v.min()}..{v.max()}; kept wider")
            return narrow(s.astype("float64"))
    return s.astype(dt)


def read_fixed(src, raw, cols, lrecl, fixed, notes):
    recs = records(raw / src["data"], lrecl, fixed)
    lens = {len(r) for r in recs}
    extent = max(c["end"] for c in cols)
    if len(lens) != 1:
        raise ValueError(f"records have different lengths: {sorted(lens)[:5]}")
    (reclen,) = lens
    if reclen < extent:
        raise ValueError(f"records are {reclen} bytes; the layout needs {extent}")
    total = len(recs)
    if sel := src.get("select"):
        a, b, test = sel
        recs = [r for r in recs if test(int(r[a - 1:b]))]
        notes.append(f"{len(recs)} of {total} records selected by the record type in "
                     f"columns {a}-{b}")
        extent = max(extent, b)
    if reclen > extent:
        filled = sum(r[extent:].strip() != b"" for r in recs)
        notes.append(f"records are {reclen} bytes; the layout ends at column {extent}; "
                     + (f"{filled} records have undocumented data after it, not converted"
                        if filled else "the rest is blank"))
    data = io.BytesIO(b"\n".join(recs) + b"\n")
    dtype = {c["name"]: str for c in cols if c["type"].startswith("str")}
    df = pd.read_fwf(data, colspecs=[(c["start"] - 1, c["end"]) for c in cols],
                     names=[c["name"] for c in cols], dtype=dtype, encoding="latin-1",
                     header=None, keep_default_na=False, na_values=["", "."])
    if len(df) != len(recs):
        raise ValueError(f"read {len(df)} rows from {len(recs)} records")
    for c in cols:
        n = c["name"]
        df[n] = df[n].fillna("") if c["type"].startswith("str") else to_type(df[n], c["type"], notes)
    return df, total


def cross_check(dct_cols, sas_cols):
    """Positions in the .dct against the SAS INPUT statement."""
    a = {c["name"].lower(): (c["start"], c["end"], c["type"].startswith("str")) for c in dct_cols}
    b = {c["name"].lower(): (c["start"], c["end"], c["type"] == "str") for c in sas_cols}
    out = []
    for n in sorted(set(a) | set(b), key=lambda n: (a.get(n) or b.get(n))[0]):
        if n not in b:
            out.append(f"{n}: in .dct {a[n][:2]}, not in SAS")
        elif n not in a:
            out.append(f"{n}: in SAS {b[n][:2]}, not in .dct")
        elif a[n] != b[n]:
            out.append(f"{n}: .dct {a[n]} vs SAS {b[n]} (start, end, string)")
    return out


def convert(src, raw):
    """-> (DataFrame, variable labels, value labels {col: {v: text}}, data label, notes)."""
    notes = []
    path = raw / src["data"]
    if path.suffix == ".sas7bdat":
        df, meta = pyreadstat.read_sas7bdat(str(path))
        if meta.number_rows not in (None, len(df)):
            raise ValueError(f"header says {meta.number_rows} rows, read {len(df)}")
        sp, _ = pyreadstat.read_sas7bdat(str(path), user_missing=True)
        special = sum(int(sp[c].map(lambda x: isinstance(x, str)).sum())
                      for c in sp.columns if is_numeric(df[c]))
        if special:
            notes.append(f"{special} SAS special missing values (.A-.Z) written as `.`")
        for c in df.columns:
            df[c] = to_type(df[c], "num", notes) if is_numeric(df[c]) else df[c].fillna("")
        varlab = {k: v for k, v in meta.column_names_to_labels.items() if v}
        label = meta.file_label or None
        return df, varlab, {}, label, notes
    if "dct" in src:
        cols = parse_dct(raw / src["dct"])
        data_label, sets, attach = parse_do(raw / src["do"])
        sas = parse_sas(raw / src["sas"])
        if mism := cross_check(cols, sas["cols"]):
            notes.append(f"cross-check against {Path(src['sas']).name}: {len(mism)} mismatches: "
                         + "; ".join(mism[:20]) + (" ..." if len(mism) > 20 else ""))
        else:
            notes.append(f"positions agree with {Path(src['sas']).name} ({len(cols)} columns)")
        df, _ = read_fixed(src, raw, cols, sas["lrecl"] or max(c["end"] for c in cols),
                           False, notes)
        varlab = {c["name"]: c["label"] for c in cols if c["label"]}
        lower = {c["name"].lower(): c["name"] for c in cols}
        vallab, missing = {}, []
        for v, s in attach.items():
            if v.lower() not in lower:
                missing.append(v)
            elif s in sets:
                vallab[lower[v.lower()]] = sets[s]
        if missing:
            notes.append(f"label values names {len(missing)} variables not in the .dct: "
                         + ", ".join(missing[:10]))
    else:
        sas = parse_sas(raw / src["sas"])
        cols, data_label = sas["cols"], None
        # A name read twice holds the later field in SAS; keep only that one.
        last = {c["name"].lower(): i for i, c in enumerate(cols)}
        if dropped := [f"{c['name']} {c['start']}-{c['end']}" for i, c in enumerate(cols)
                       if last[c["name"].lower()] != i]:
            notes.append(f"INPUT reads {len(dropped)} names more than once; as in SAS the "
                         "last field is kept (dropped: " + ", ".join(dropped) + ")")
            cols = [c for i, c in enumerate(cols) if last[c["name"].lower()] == i]
        df, _ = read_fixed(src, raw, cols, sas["lrecl"], sas["fixed"], notes)
        varlab = {c["name"]: sas["labels"][c["name"].lower()] for c in cols
                  if sas["labels"].get(c["name"].lower())}
        fmts = sas["formats"] or {c["name"].lower(): c["name"].lower() for c in cols
                                  if c["name"].lower() in sas["sets"]}
        if not sas["formats"] and fmts:
            notes.append("no FORMAT statement; value labels attached by matching names")
        vallab = {c["name"]: sas["sets"][fmts[c["name"].lower()]] for c in cols
                  if fmts.get(c["name"].lower()) in sas["sets"] and sas["sets"][fmts[c["name"].lower()]]}
        if extra := sorted(set(sas["labels"]) - {c["name"].lower() for c in cols}):
            notes.append("LABEL names variables INPUT does not read (the program derives "
                         "them; not converted): " + ", ".join(extra))
        if sas["skipped_keys"]:
            notes.append(f"{sas['skipped_keys']} PROC FORMAT entries that are ranges or "
                         "non-integer keys have no Stata equivalent and were skipped")
        notes.append(f"layout from {Path(src['sas']).name} (no Stata dictionary published)")
    return df, varlab, vallab, data_label, notes


# ---------------------------------------------------------------- validate & write

def validate(src, df, raw, notes):
    ids = [next((c for c in df.columns if c.lower() == i.lower()), None) for i in src["ids"]]
    if None in ids:
        raise ValueError(f"id columns {src['ids']} not all found")
    dup = int(df.duplicated(ids).sum())
    if dup:
        raise ValueError(f"{dup} duplicate rows on ({', '.join(ids)})")
    notes.append(f"({', '.join(ids)}) unique")
    if z := src.get("csv_zip"):
        with zipfile.ZipFile(raw / z) as zf:
            csv = next(n for n in zf.namelist() if n.endswith(".csv"))
            with zf.open(csv) as f:
                n = sum(1 for _ in f) - 1
        if n != len(df):
            raise ValueError(f"{csv} has {n} rows, the sas7bdat {len(df)}")
        notes.append(f"row count matches {csv}")
    for copy, stem in TEXT_COPIES.items():
        if stem == src["stem"]:
            n = len(records(raw / copy, None, False))
            if n != len(df):
                raise ValueError(f"{copy} has {n} records, the sas7bdat {len(df)}")
            notes.append(f"row count matches {Path(copy).name}")


def write(df, varlab, vallab, data_label, path, notes):
    long_labels = 0
    for k, v in list(varlab.items()):
        v = v.strip()
        if len(v) > 80:  # pandas refuses longer variable labels
            v = v[:80]
            long_labels += 1
        varlab[k] = v
    if long_labels:
        notes.append(f"{long_labels} variable labels over 80 characters cut to 80 "
                     "(pandas' limit)")
    numeric = {k: v for k, v in vallab.items() if is_numeric(df[k])}
    if len(numeric) < len(vallab):
        notes.append(f"{len(vallab) - len(numeric)} value labels on string variables dropped")
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        df.to_stata(path, version=118, write_index=False, variable_labels=varlab,
                    value_labels=numeric or None, data_label=(data_label or "")[:80])
    for x in w:
        notes.append("pandas: " + " ".join(str(x.message).split())[:300])


# ---------------------------------------------------------------- report

def mb(n):
    return f"{n / 1e6:,.1f} MB"


def report(items, results, seconds, out):
    lines = [
        "# NSFG conversion report",
        "",
        "Made by `bench/nsfg/make.py` from CDC's public-use NSFG files "
        "(inventory: `inventory.json`). The .dta files are written by pandas "
        f"{pd.__version__} (`DataFrame.to_stata`, release 118) and are not committed.",
        "",
        f"Files listed by CDC: {len(items)} ({mb(sum(i['size'] for i in items))}). "
        f"Data files: {len(results)}; converted: "
        f"{sum(r['status'] == 'converted' for r in results)}; failed: "
        f"{sum(r['status'] != 'converted' for r in results)}. "
        f"Output: {mb(sum(r.get('dta_size', 0) for r in results))} of .dta. "
        f"Run time: {seconds:.0f} s.",
        "",
        "| cycle | output | source | rows | vars | .dta size | status |",
        "|---|---|---|---:|---:|---:|---|",
    ]
    for r in results:
        lines.append(f"| {r['cycle']} | `{r['stem']}.dta` | `{Path(r['data']).name}` | "
                     f"{r.get('rows', '')} | {r.get('vars', '')} | "
                     f"{mb(r['dta_size']) if 'dta_size' in r else ''} | {r['status']} |")
    lines += ["", "## Notes per file", ""]
    for r in results:
        lines.append(f"- `{r['stem']}`: " + "; ".join(r["notes"]) + ".")
    lines += ["", "## Listed but not converted", ""]
    for i in items:
        if i["role"] == "excluded":
            lines.append(f"- `{i['file']}`: {i['excluded']}.")
    lines.append("- `Datasets/NSFG/spss/*.sps`: SPSS programs; listed only, the Stata and SAS "
                 "programs give the same layouts.")
    lines.append("- Stata `.dct`/`.do` and SAS programs: dictionaries, used to read the data "
                 "files above.")
    (HERE / "REPORT.md").write_text("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--raw", default="/private/tmp/claude-501/nsfg-raw", type=Path)
    ap.add_argument("--out", default="/private/tmp/claude-501/nsfg-dta", type=Path)
    ap.add_argument("--only", nargs="*", help="convert only these stems (no report)")
    args = ap.parse_args()
    t0 = time.time()
    items = inventory(args.raw)
    (HERE / "inventory.json").write_text(json.dumps(items, indent=1, ensure_ascii=False) + "\n")
    print(f"inventory: {len(items)} files, {time.time() - t0:.0f} s")
    args.out.mkdir(parents=True, exist_ok=True)
    results = []
    for src in SOURCES:
        if args.only and src["stem"] not in args.only:
            continue
        r = dict(stem=src["stem"], cycle=src["cycle"], data=src["data"], notes=[])
        t1 = time.time()
        try:
            df, varlab, vallab, label, notes = convert(src, args.raw)
            r["notes"] = notes
            validate(src, df, args.raw, notes)
            path = args.out / f"{src['stem']}.dta"
            write(df, varlab, vallab, label or f"NSFG {src['cycle']} {src['stem']}", path, notes)
            r.update(status="converted", rows=len(df), vars=df.shape[1],
                     dta_size=path.stat().st_size)
        except Exception as e:  # report every failure and carry on
            r["status"] = "failed"
            r["notes"].append(f"error: {type(e).__name__}: {e}")
        print(f"{src['stem']}: {r['status']} {r.get('rows', '')}x{r.get('vars', '')} "
              f"{time.time() - t1:.0f} s", flush=True)
        results.append(r)
    if not args.only:
        report(items, results, time.time() - t0, args.out)
    print(f"done in {time.time() - t0:.0f} s")
    return any(r["status"] != "converted" for r in results)


if __name__ == "__main__":
    sys.exit(main())
