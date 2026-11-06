"""`Meta`, `Column`, `ParquetInfo` and `LETTERS`: what polars cannot hold,
kept beside the frame."""

from __future__ import annotations

import copy as _copy
from dataclasses import dataclass, field, fields

import polars as pl

GUIDE = "https://github.com/jbearak/dta-parser/blob/main/docs/python.md"

LETTERS = pl.Enum([f".{chr(c)}" for c in range(ord("a"), ord("z") + 1)])


def _same(a, b):
    """Equal values, with polars Series and frames compared by `equals`."""
    if isinstance(a, (pl.Series, pl.DataFrame)) or isinstance(b, (pl.Series, pl.DataFrame)):
        if type(a) is not type(b):
            return False
        if isinstance(a, pl.Series):
            return a.dtype == b.dtype and a.name == b.name and a.equals(b, check_dtypes=True, check_names=True)
        return a.schema == b.schema and a.equals(b)
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(_same(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_same(x, y) for x, y in zip(a, b))
    return a == b


def _deep(value):
    if isinstance(value, (pl.Series, pl.DataFrame)):
        return value.clone()
    if isinstance(value, dict):
        return {k: _deep(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_deep(v) for v in value]
    return _copy.deepcopy(value)


@dataclass
class Column:
    """What `meta.columns[name]` says about one column.

    label: the variable label, or None.
    format: the display format, such as "%9.2f" or "%td", or None.
    value_labels: the name of the column's value label set in
        `meta.value_labels`, or None. Several columns may share a set.
    ordered: for an Enum column read from a file's categorical, the
        file's "ordered"; written back as it is. None otherwise.

    Guide: {guide}#labels-in-parquet-files
    """

    label: str | None = None
    format: str | None = None
    value_labels: str | None = None
    ordered: bool | None = None


Column.__doc__ = Column.__doc__.replace("{guide}", GUIDE)


@dataclass(eq=False)
class Meta:
    """Labels, formats, notes and `.a` to `.z` of a polars frame.

    Every read returns `(df, meta)`; `save_parquet(df, path, meta=meta)`
    and `save_dta` write it back. The fields are plain values for you to
    change:

    label: the data label, or None.
    notes: the notes, a list of text.
    characteristics: {variable or "_dta": {name: text}}.
    sort: the columns the rows are sorted by, as Stata keeps it. Saving
        checks it against the frame's rows and leaves it out, with a
        warning, if the rows are no longer in that order.
    timestamp: the file's time stamp, such as "05 Nov 2026 10:00", or None.
    columns: {name: Column}, one per column read.
    value_labels: {set name: {code: text}}. A code is an int or float, or
        a missing code as text: ".", ".a" to ".z".
    missing: {name: Series of LETTERS}: for each column holding `.a` to
        `.z` in the rows read, the letter of each row (null elsewhere),
        aligned with the frame as read. Saving checks that the column
        has not changed since the read; see `letters_to_columns` to keep
        letters through row operations.
    letter_columns: {name: companion}: columns whose letters are in a
        companion column of the frame, such as {"x": "x_letter"}.
    rows: the frame's height as read.

    Methods: `labels(name)`, `letters(name)`, `rename(mapping)`,
    `select(names)` and `copy()`. `==` compares every field (Series with
    `Series.equals`). Meta does not follow polars operations: a filter,
    sort or join is yours to mirror (the guide shows how).

    Guide: {guide}#labels-and-a-to-z-through-polars-operations
    """

    label: str | None = None
    notes: list[str] = field(default_factory=list)
    characteristics: dict[str, dict[str, str]] = field(default_factory=dict)
    sort: list[str] = field(default_factory=list)
    timestamp: str | None = None
    columns: dict[str, Column] = field(default_factory=dict)
    value_labels: dict[str, dict[int | float | str, str]] = field(default_factory=dict)
    missing: dict[str, pl.Series] = field(default_factory=dict)
    letter_columns: dict[str, str] = field(default_factory=dict)
    rows: int = 0
    # The digest of each column of `missing` as read, which saving
    # compares; not part of equality.
    _digests: dict[str, int] = field(default_factory=dict, repr=False, compare=False)

    def __eq__(self, other):
        if not isinstance(other, Meta):
            return NotImplemented
        return all(_same(getattr(self, f.name), getattr(other, f.name)) for f in fields(self) if f.compare)

    __hash__ = None

    def copy(self):
        """A deep copy: every container new, every Series cloned."""
        out = Meta(**{f.name: _deep(getattr(self, f.name)) for f in fields(self)})
        return out

    def _known(self, name):
        if name not in self.columns:
            raise KeyError(f'meta.columns has no column "{name}"')

    def labels(self, name):
        """The value labels of column `name`: its set in `value_labels`
        itself (a change to it changes meta), or {} if it has none.
        KeyError if meta.columns has no `name`."""
        self._known(name)
        set_name = self.columns[name].value_labels
        if set_name is None:
            return {}
        return self.value_labels.get(set_name, {})

    def letters(self, name):
        """Column `name`'s `.a` to `.z` as a Series of LETTERS, null where a
        row has none: `missing[name]`, or all null (of `rows` rows) for a
        column without letters. KeyError if meta.columns has no `name`;
        ValueError if its letters are in a companion column, which is
        where to look instead."""
        self._known(name)
        if name in self.letter_columns:
            raise ValueError(f'the letters of column "{name}" are in the frame\'s column "{self.letter_columns[name]}", '
                             "not in meta.missing")
        if name in self.missing:
            return self.missing[name]
        return pl.Series(name, [None] * self.rows, dtype=LETTERS)

    def _names(self):
        """Every name a rename or select may give: columns and companions."""
        return set(self.columns) | set(self.letter_columns.values())

    def rename(self, mapping):
        """A new Meta for `df.rename(mapping)`: the names in `columns`,
        `missing` (each Series aliased), `letter_columns` (both sides),
        `characteristics` and `sort` renamed. KeyError for a name meta
        does not have; ValueError for a rename onto a name that stays."""
        names = self._names()
        for old in mapping:
            if old not in names:
                raise KeyError(f'meta.columns has no column "{old}"')
        staying = names - set(mapping)
        for old, new in mapping.items():
            if new in staying:
                raise ValueError(f'renaming "{old}" to "{new}": meta already has a column "{new}"')
        if len(set(mapping.values())) != len(mapping):
            raise ValueError("two columns renamed to one name")
        r = lambda n: mapping.get(n, n)  # noqa: E731
        out = self.copy()
        out.columns = {r(k): v for k, v in out.columns.items()}
        out.missing = {r(k): v.alias(r(k)) for k, v in out.missing.items()}
        out._digests = {r(k): v for k, v in out._digests.items()}
        out.letter_columns = {r(k): r(v) for k, v in out.letter_columns.items()}
        out.characteristics = {r(k): v for k, v in out.characteristics.items()}
        out.sort = [r(n) for n in out.sort]
        return out

    def select(self, names):
        """A new Meta for `df.select(names)`: only those columns in
        `columns`, `missing`, `letter_columns` and `characteristics`
        ("_dta" kept), and `sort` up to its first column not selected.
        Every value label set is kept. KeyError for a name meta does not
        have."""
        if isinstance(names, str):
            names = [names]
        known = self._names()
        for n in names:
            if n not in known:
                raise KeyError(f'meta.columns has no column "{n}"')
        keep = set(names)
        out = self.copy()
        out.columns = {n: out.columns[n] for n in names if n in out.columns}
        out.missing = {k: v for k, v in out.missing.items() if k in keep}
        out._digests = {k: v for k, v in out._digests.items() if k in keep}
        out.letter_columns = {k: v for k, v in out.letter_columns.items() if k in keep}
        out.characteristics = {k: v for k, v in out.characteristics.items() if k in keep or k == "_dta"}
        sort = []
        for n in out.sort:
            if n not in keep:
                break
            sort.append(n)
        out.sort = sort
        return out


Meta.__doc__ = Meta.__doc__.replace("{guide}", GUIDE)


@dataclass(eq=False)
class ParquetInfo:
    """What `read_parquet_info` reads from a Parquet file's footer.

    rows: the number of rows.
    row_groups: a polars DataFrame of `rows`, `compressed_bytes` and
        `uncompressed_bytes` per row group.
    compression: the codecs the column chunks use, such as ["snappy"].
    created_by: the writer the file names, or None.
    key_value: every key-value entry of the footer as text, the "dta"
        profile and "ARROW:schema" among them.
    meta: the Meta a whole-file read gives, with `missing` empty and
        `rows` the file's.
    columns: a polars DataFrame with a row per Parquet column: `name`;
        `role` ("data", or "nested" for a list, map or struct, which is
        not read); `dtype`, the polars dtype `read_parquet` gives it, as
        text (null for a column it does not read); `physical_type` and
        `logical_type`, Parquet's; `label`; `value_labels`, the set's
        name; and `storage`, the Stata storage type a DOUBLE column
        written for `.a` to `.z` has in the profile.

    Guide: {guide}#a-parquet-files-schema-and-metadata
    """

    rows: int
    row_groups: pl.DataFrame
    compression: list[str]
    created_by: str | None
    key_value: dict[str, str]
    meta: Meta
    columns: pl.DataFrame

    def __eq__(self, other):
        if not isinstance(other, ParquetInfo):
            return NotImplemented
        return all(_same(getattr(self, f.name), getattr(other, f.name)) for f in fields(self))

    __hash__ = None


ParquetInfo.__doc__ = ParquetInfo.__doc__.replace("{guide}", GUIDE)
