"""`.a` to `.z` in the column (ADR 0040): a `DtaArray`'s codes, which
compare as missing, or tagged NaNs in a plain float column.

A `DtaArray` (dta_parser's) keeps a code per row: 0 for a number, 1 for
`.`, 2 to 27 for `.a` to `.z`. Every numeric column a read gives with a
missing value is one. `tagged_na(".a")` is `dta_parser.missing.a`, the
value a `DtaArray` gives back for `.a` and takes in assignment.

A plain `float64` column may hold a letter as a tagged NaN: R's
`NA_real_` (a NaN whose low word is 1954) with the letter's ASCII code in
bits 32 to 39, the layout haven's `tagged_na()`, R's dtaparser and the
Parquet files' DOUBLE columns use. `na_tag` and `is_tagged_na` read
those too, ignoring the sign and the quiet bit, which arithmetic may
change, and saving writes them as their letters.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from dta_parser import DtaArray, missing

from ._meta import GUIDE, LETTERS

NA_BITS = 0x7FF0_0000_0000_07A2
_MASK = 0xFFFF_FFFF_FFFF_FFFF ^ ((1 << 63) | (1 << 51) | (0xFF << 32))
_NAMES = [f".{chr(c)}" for c in range(ord("a"), ord("z") + 1)]


def _code(letter):
    """The missing code (2 to 27) of ".a" to ".z" or "a" to "z"."""
    if not isinstance(letter, str):
        raise TypeError(f'a letter is text, ".a" to ".z" or "a" to "z", not {letter!r}')
    t = letter[1:] if letter.startswith(".") else letter
    if len(t) != 1 or not ("a" <= t <= "z"):
        raise ValueError(f'a letter is ".a" to ".z" or "a" to "z", not {letter!r}')
    return ord(t) - ord("a") + 2


def tagged_na(letter):
    """Stata's missing value `letter` (".a" to ".z", or "a" to "z"):
    `dta_parser.missing.a` ... `missing.z`. Assign it into a `DtaArray`
    column, `df.loc[rows, "x"] = dk.tagged_na(".r")`, or compare with
    it, `df["x"] == dk.tagged_na(".a")`, which is true exactly on the
    `.a` rows.

    Guide: {guide}#a-to-z-in-the-frame
    """
    return missing.from_code(_code(letter))


def float_codes(values):
    """The code of each row of a float64 numpy array: 2 to 27 where it is
    a tagged NaN, 1 for any other NaN, 0 for a number."""
    values = np.asarray(values, dtype=np.float64)
    bits = values.view(np.uint64)
    tagged = (bits & np.uint64(_MASK)) == np.uint64(NA_BITS)
    byte = ((bits >> np.uint64(32)) & np.uint64(0xFF)).astype(np.int16)
    tagged &= (byte >= ord("a")) & (byte <= ord("z"))
    codes = np.isnan(values).astype(np.uint8)
    codes[tagged] = (byte[tagged] - ord("a") + 2).astype(np.uint8)
    return codes


def tag(codes):
    """Float64 tagged NaNs for codes 2 to 27 (others 0)."""
    codes = np.asarray(codes, dtype=np.uint64)
    return (np.uint64(NA_BITS) | ((codes - np.uint64(2) + np.uint64(ord("a"))) << np.uint64(32))).view(np.float64)


def _codes_of(x):
    """The codes of `x` (a Series or array): a DtaArray's, a float
    column's from its tagged NaNs, else None."""
    a = x.array if isinstance(x, (pd.Series, pd.Index)) else x
    if isinstance(a, DtaArray):
        return a.codes
    if isinstance(a, pd.arrays.NumpyExtensionArray):
        a = a.to_numpy()
    if isinstance(a, np.ndarray) and a.dtype.kind == "f":
        return float_codes(a)
    return None


def na_tag(x):
    """The letter of each row of `x` (a Series or array): ".a" to ".z"
    where the row holds one, NaN elsewhere, `.` included. A Series of
    dtype `LETTERS`, a categorical of ".a" to ".z", with `x`'s index and
    name. It reads a `DtaArray`'s codes and the tagged NaNs of a plain
    float column; any other column gives NaN on every row.

    Guide: {guide}#a-to-z-in-the-frame
    """
    if not isinstance(x, (pd.Series, pd.Index, np.ndarray, pd.api.extensions.ExtensionArray, list)):
        raise TypeError(f"na_tag takes a Series or an array, not {type(x).__name__}")
    if isinstance(x, list):
        x = pd.array(x, dtype="dta[double]")
    codes = _codes_of(x)
    n = len(x)
    out = np.full(n, -1, dtype=np.int8)
    if codes is not None:
        letters = codes > 1
        out[letters] = codes[letters].astype(np.int8) - 2
    cat = pd.Categorical.from_codes(out, dtype=LETTERS)
    if isinstance(x, pd.Series):
        return pd.Series(cat, index=x.index, name=x.name)
    return pd.Series(cat, name=getattr(x, "name", None))


def is_tagged_na(x, letter=None):
    """A numpy bool array: True where a row of `x` (a Series or array)
    is one of `.a` to `.z`, or the letter `letter` when given; False
    elsewhere, `.` included.

    Guide: {guide}#a-to-z-in-the-frame
    """
    want = None if letter is None else _code(letter)
    if not isinstance(x, (pd.Series, pd.Index, np.ndarray, pd.api.extensions.ExtensionArray, list)):
        raise TypeError(f"is_tagged_na takes a Series or an array, not {type(x).__name__}")
    if isinstance(x, list):
        x = pd.array(x, dtype="dta[double]")
    codes = _codes_of(x)
    if codes is None:
        return np.zeros(len(x), dtype=bool)
    return np.asarray(codes > 1 if want is None else codes == want)


for _fn in (tagged_na, na_tag, is_tagged_na):
    _fn.__doc__ = _fn.__doc__.replace("{guide}", GUIDE)

__all__ = ["tagged_na", "na_tag", "is_tagged_na", "LETTERS", "_NAMES"]
