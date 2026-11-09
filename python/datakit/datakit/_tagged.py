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
    bits = e.cast(pl.Float64, strict=False).reinterpret(dtype=pl.UInt64)
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


for _fn in (tagged_na, na_tag, is_tagged_na):
    _fn.__doc__ = _fn.__doc__.replace("{guide}", GUIDE)
