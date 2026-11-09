"""`.a` to `.z` in the column: tagged NaNs in Float64 (ADR 0036).

A letter is R's `NA_real_` (a NaN whose low word is 1954) with the
letter's ASCII code in bits 32 to 39, the layout haven's `tagged_na()`,
R's dtaparser and the Parquet files' DOUBLE columns use
(`crates/parquet/src/tagged.rs`). Reading a letter back ignores the sign
and the quiet bit, which arithmetic may change.
"""

from __future__ import annotations

import struct

import polars as pl

from ._meta import GUIDE, LETTERS

NA_BITS = 0x7FF0_0000_0000_07A2
_MASK = 0xFFFF_FFFF_FFFF_FFFF ^ ((1 << 63) | (1 << 51) | (0xFF << 32))
_LETTERS = [f".{chr(c)}" for c in range(ord("a"), ord("z") + 1)]
_BYTE_TO_LETTER = {ord(t[1]): t for t in _LETTERS}


def _bits(letter):
    if not isinstance(letter, str):
        raise TypeError(f'a letter is text, ".a" to ".z" or "a" to "z", not {letter!r}')
    t = letter[1:] if letter.startswith(".") else letter
    if len(t) != 1 or not ("a" <= t <= "z"):
        raise ValueError(f'a letter is ".a" to ".z" or "a" to "z", not {letter!r}')
    return NA_BITS | (ord(t) << 32)


def tagged_na(letter):
    """The float that holds Stata's missing value `letter` (".a" to ".z",
    or "a" to "z"): a NaN tagged with the letter. Use it wherever polars
    takes a number, such as `pl.when(c).then(dk.tagged_na(".d"))`, in a
    Float64 column.

    Guide: {guide}#a-to-z-in-the-frame
    """
    return struct.unpack("<d", struct.pack("<Q", _bits(letter)))[0]


def _expr(x):
    if isinstance(x, str):
        return pl.col(x)
    if isinstance(x, (pl.Expr, pl.Series)):
        return x
    raise TypeError(f"takes a column name, a polars Expr or a polars Series, not {type(x).__name__}")


def na_tag(x):
    """The letter of each row of `x` (a column name, Expr or Series): ".a"
    to ".z" (dtype LETTERS) where the row is a tagged NaN, null
    elsewhere, `.` and plain NaN included. Only Float64 holds letters;
    any other dtype gives all null.

    Guide: {guide}#a-to-z-in-the-frame
    """
    e = _expr(x)
    if isinstance(e, pl.Series):
        if e.dtype != pl.Float64:
            return pl.Series(e.name, [None] * e.len(), dtype=LETTERS)
        return pl.select(_na_tag(pl.lit(e))).to_series().alias(e.name)
    return _na_tag(e)


def _na_tag(e):
    # Any other dtype holds no letter: cast so that the expression works
    # on it too (a cast never makes R's tag pattern).
    bits = e.to_physical().cast(pl.Float64, strict=False).reinterpret(dtype=pl.UInt64)
    byte = (bits // (1 << 32)) % 256
    tagged = (bits & pl.lit(_MASK, pl.UInt64)) == pl.lit(NA_BITS, pl.UInt64)
    letter = byte.replace_strict(_BYTE_TO_LETTER, default=None, return_dtype=LETTERS)
    return pl.when(tagged).then(letter).otherwise(pl.lit(None, LETTERS))


def is_tagged_na(x, letter=None):
    """True where a row of `x` (a column name, Expr or Series) is one of
    `.a` to `.z`, or the letter `letter` when given; false elsewhere,
    `.` (null) included.

    Guide: {guide}#a-to-z-in-the-frame
    """
    tags = na_tag(x)
    if letter is None:
        return tags.is_not_null()
    _bits(letter)
    want = letter if letter.startswith(".") else "." + letter
    return tags.eq_missing(pl.lit(want, LETTERS)) if isinstance(tags, pl.Expr) else tags.eq_missing(want)


def is_missing(x):
    """True where a row of `x` is missing: `.` (null) or `.a` to `.z`
    (tagged NaNs), as R's `is.na()` and Stata's `missing()` say. A NaN
    that is not a letter counts too, as it does for `is.na()`. `is_na`
    is the same function.

    `x` is a column name, an Expr or a Series. A Series is tested by its
    dtype: a float with `is_null() | is_nan()`, anything else with
    `is_null()`. A name or an Expr gives an Expr, which has no dtype until
    it runs; it is right for numeric, Boolean, Decimal, Date, Datetime,
    Duration, Time, Categorical, Enum and Null columns. Not for text (the
    text "nan" would count as missing) nor for Binary, List, Array or
    Struct (polars raises when it runs): use `pl.col(c).is_null()`, or
    pass the Series.

    polars' own `is_null()` sees only `.`, so `(x != 1) &
    x.is_not_null()` keeps the letters; write `(x != 1) & ~dk.is_na(x)`.

    Guide: {guide}#a-to-z-in-the-frame
    """
    if isinstance(x, pl.Series):
        if x.dtype.is_float():
            return (x.is_null() | x.is_nan()).fill_null(True)
        return x.is_null()
    e = _expr(x)
    return e.is_null() | e.to_physical().cast(pl.Float64, strict=False).is_nan().fill_null(False)


is_na = is_missing


def by(*columns, suffix="_letter"):
    """Expressions for grouping by `columns` with `.a` to `.z` kept
    apart, as R's `datakit_by()` gives: each column, then its
    letters as `<name><suffix>` (`na_tag`). polars makes every NaN equal,
    so grouping by a column alone merges the letters.

    Each column is a name or an Expr with an output name. Every argument
    gets a letter column, all null for a column that is not Float64 (an
    Expr has no dtype until it runs). A Binary, List, Array or Struct
    column raises when the expression runs; group by it alone.

        df.group_by(dk.by("x")).len()
        df.with_columns(dk.by("x")).unique(subset=["x", "x_letter"])

    To join with the letters kept apart, add the columns to both sides
    and join on the key and its letter column with `nulls_equal=True`
    (a row with no letter has a null letter column).

    Guide: {guide}#a-to-z-in-the-frame
    """
    if not isinstance(suffix, str) or not suffix:
        raise ValueError(f"suffix must be non-empty text, not {suffix!r}")
    out = []
    names = []
    for c in columns:
        e = _expr(c)
        if isinstance(e, pl.Series):
            raise TypeError("by takes column names or Exprs, not a Series")
        try:
            name = e.meta.output_name()
        except pl.exceptions.ComputeError:
            raise ValueError(f"by needs a name for {e}: give it one with .alias()") from None
        out += [e, _na_tag(e).alias(name + suffix)]
        names += [name, name + suffix]
    if not out:
        raise ValueError("by needs at least one column")
    twice = sorted({n for n in names if names.count(n) > 1})
    if twice:
        shown = ", ".join(f'"{n}"' for n in twice)
        raise ValueError(f"by would make two columns named {shown}; rename an argument or pick another suffix")
    return out


def tag(values, letters):
    """`values` (Float64) with a tagged NaN wherever `letters` (LETTERS) has
    a letter."""
    code = letters.to_physical().cast(pl.UInt64) + ord("a")
    tags = (pl.lit(NA_BITS, pl.UInt64) + code * (1 << 32)).reinterpret(dtype=pl.Float64)
    return pl.select(pl.when(letters.is_not_null()).then(tags).otherwise(values)).to_series().alias(values.name)


def untag(values):
    """`(values with every tagged NaN null, its letters)`, the letters
    None when it has none."""
    letters = na_tag(values)
    if letters.null_count() == letters.len():
        return values, None
    plain = pl.select(pl.when(letters.is_not_null()).then(None).otherwise(values)).to_series().alias(values.name)
    return plain, letters.alias(values.name)


for _fn in (tagged_na, na_tag, is_tagged_na, is_missing, by):
    _fn.__doc__ = _fn.__doc__.replace("{guide}", GUIDE)
