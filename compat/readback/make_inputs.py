"""What compat/readback/strls.dta and binary.dta hold: inputs that every
writer saves again (compat/readback/write.*), and that every reader
must read as `spec(stem)` gives them (compat/readback/check.py).

The two files are committed. They were written on 2026-11-08, from the
definitions below, by the Python writer this repository had then, which
has since been removed. Nothing here writes them now: running this
script exits with a message saying so. A replacement writer must be
able to write a binary strL that is not UTF-8.

strls.dta has several strL variables over many rows, texts repeated
within a variable and across variables (one entry per distinct text
and variable), empty strLs, `.` and `.a` to `.z`, value labels with a
long text and a missing code, and an 80-character variable label.
binary.dta adds a binary strL beside a text one. It is a file of its
own because haven and pyreadstat read every strL as UTF-8 text and so
cannot open a file holding a binary strL that is not UTF-8.
"""

import sys

import numpy as np

N = 30


def text(seed, n):
    """`n` characters of mixed ASCII and multibyte UTF-8, different per seed."""
    pieces = ["a", "Z", "7", " ", "é", "€", "ß", str(seed)]
    return "".join(pieces[(seed * 7 + i * 3 + i // 5) % len(pieces)] for i in range(n))


LONG = [text(1, 2100), text(2, 2600), text(3, 3000)]
# A, B, A, "", C, B, repeated.
NOTE = [[LONG[0], LONG[1], LONG[0], "", LONG[2], LONG[1]][i % 6] for i in range(N)]
# Short texts stored as strL, repeated, one shared with `note`.
REMARK = [["yes", "no", "", "yes", LONG[0]][i % 5] for i in range(N)]
# Ten distinct texts just over strN's limit, then the same ten again.
ESSAY = [text(100 + i % 10, 2046 + i % 10) for i in range(N)]
# Binary: NULs and bytes that are not UTF-8, repeated, and one empty.
BLOBS = [b"\x00\x01\xff\xfe", b"\x89PNG\r\n\x1a\n\x00\x00", b"", b"\xc3\x28\x00tail"]
BLOB = [BLOBS[(i * 3) % 4] for i in range(N)]
# (value, missing code): .a to .z on rows 0 to 25, then ., then numbers.
SCORE = [(np.nan, 2 + i) for i in range(26)] + [(np.nan, 1), (1.5, 0), (-2.25, 0), (1e300, 0)]
# 0, 1 and 9 (whose label is long), with .d (labelled) on row 7.
ANSWER = [(np.nan, 5) if i == 7 else (float([0, 1, 9, 0, 1][i % 5]), 0) for i in range(N)]
LONG_LABEL = "Answered after a long follow-up: " + text(7, 1500)
PREFIX = "Note with a long label, éé €€ ßß: "
VARIABLE_LABEL = PREFIX + "x" * (80 - len(PREFIX))
DATA_LABEL = "strL readback dataset"
VARIABLES = {
    "strls": [
        ("id", "Row"),
        ("note", VARIABLE_LABEL),
        ("remark", "Short texts stored as strL"),
        ("essay", "Distinct long texts, repeated"),
        ("score", "Every missing code"),
        ("answer", "Labelled answer"),
    ],
    "binary": [
        ("id", "Row"),
        ("blob", "Binary strL"),
        ("note", "Text strL"),
    ],
}


def _cell(v, code=0):
    if code == 1:
        return {"missing": "."}
    if code > 1:
        return {"missing": "." + chr(ord("a") + code - 2)}
    if isinstance(v, bytes):
        return {"hex": v.hex()}
    return v


def spec(stem):
    """File `stem` as check.py compares it: cells are numbers, text,
    {"missing": ".a"} or {"hex": ...} for binary."""
    labels = {"answer": [[0.0, "No"], [1.0, "Yes"], [9.0, LONG_LABEL], [".d", "Don't know"]]}
    values = {
        "id": [float(i) for i in range(1, N + 1)],
        "note": NOTE,
        "remark": REMARK,
        "essay": ESSAY,
        "blob": [_cell(b) for b in BLOB],
        "score": [_cell(v, c) for v, c in SCORE],
        "answer": [_cell(v, c) for v, c in ANSWER],
    }
    return {
        "data_label": DATA_LABEL,
        "nobs": N,
        "variables": [{"name": n, "label": l, "labels": labels.get(n, [])} for n, l in VARIABLES[stem]],
        "values": {n: values[n] for n, _ in VARIABLES[stem]},
    }


def main():
    sys.exit(
        "compat/readback/strls.dta and binary.dta are committed files, written on\n"
        "2026-11-08 by the Python writer this repository had then. That writer is\n"
        "gone, so this script no longer writes them. To write them again from the\n"
        "definitions here, a writer must be able to write release 118 with strL\n"
        "variables, `.` and `.a` to `.z`, value labels on a missing code, and, for\n"
        "binary.dta, a binary strL that is not UTF-8 (BLOB). spec() must then still\n"
        "describe what was written."
    )


if __name__ == "__main__":
    main()
