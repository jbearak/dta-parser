"""The thin builder plan 0019's PR 2a measures: dta_parser's native Arrow
functions, and the whole `Meta` datakit will return, made eagerly (every
`Column`, the value labels, `meta.missing`, the digests), so that 2b's
public functions cannot add a cost 2a did not measure.

Not datakit: no checks, no `letters="columns"`, no `factors`; the
smallest code that makes what `datakit.read_parquet` returns and calls
what `datakit.save_parquet` will.

It loads the extension module alone, as datakit will: dta_parser's
`__init__` imports pandas, which datakit must not need.
"""

import glob
import importlib.util
import os
from dataclasses import dataclass, field

import polars as pl


def _load_native():
    spec = importlib.util.find_spec("dta_parser")
    here = os.path.dirname(spec.origin)
    so = glob.glob(os.path.join(here, "_native*.so")) + glob.glob(os.path.join(here, "_native*.pyd"))
    s = importlib.util.spec_from_file_location("dta_parser._native", so[0])
    m = importlib.util.module_from_spec(s)
    s.loader.exec_module(m)
    return m


native = _load_native()

LETTERS = pl.Enum([f".{chr(c)}" for c in range(ord("a"), ord("z") + 1)])


@dataclass
class Column:
    label: str | None = None
    format: str | None = None
    value_labels: str | None = None
    ordered: bool | None = None


@dataclass(eq=False)
class Meta:
    label: str | None = None
    notes: list = field(default_factory=list)
    characteristics: dict = field(default_factory=dict)
    sort: list = field(default_factory=list)
    timestamp: str | None = None
    columns: dict = field(default_factory=dict)
    value_labels: dict = field(default_factory=dict)
    missing: dict = field(default_factory=dict)
    letter_columns: dict = field(default_factory=dict)
    rows: int = 0
    _digests: dict = field(default_factory=dict, repr=False, compare=False)


def read_parquet(source, columns=None, skip=0, n_max=None, threads=0):
    frame, letters, m = native.parquet_read_arrow(source, columns, skip, n_max, False, "error", threads)
    df = pl.DataFrame(frame)
    flagged = [(c[0], c[6]) for c in m["columns"] if c[6] is not None]
    if flagged:
        df = df.with_columns(
            pl.col(n).cast(pl.Categorical) if f == "categorical" else pl.col(n).cast(pl.Decimal(*map(int, f[8:-1].split(","))))
            for n, f in flagged
        )
    meta = Meta(
        label=m["label"],
        notes=list(m["notes"]),
        characteristics=m["characteristics"],
        sort=list(m["sort"]),
        timestamp=m["timestamp"],
        columns={c[0]: Column(c[1], c[2], c[3], c[4]) for c in m["columns"]},
        value_labels=m["value_labels"],
        rows=m["rows"],
    )
    if letters is not None:
        ldf = pl.DataFrame(letters)
        meta.missing = {name: ldf.get_column(name) for name in ldf.columns}
    meta._digests = {name: native.arrow_digest(df.get_column(name)) for name in meta.missing}
    return df, meta


def save_parquet(df, path=None, meta=None, compression="snappy", compression_level=None, threads=0):
    return native.parquet_write_arrow(df, path, _profile(meta), compression, compression_level, None, True, "error", threads)


def _profile(meta):
    """What the native writer takes of `meta`."""
    if meta is None:
        return None
    return {
        "label": meta.label,
        "notes": meta.notes,
        "characteristics": meta.characteristics,
        "sort": meta.sort,
        "timestamp": meta.timestamp,
        "columns": {k: (c.label, c.format, c.value_labels, c.ordered) for k, c in meta.columns.items()},
        "value_labels": meta.value_labels,
        "missing": meta.missing,
    }
