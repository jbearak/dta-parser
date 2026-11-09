"""DtaArray: numbers that keep Stata's missing codes (`.`, `.a` to `.z`).

A DtaArray holds float64 values and a uint8 missing code per row (see
`dta_parser.missing`); values are NaN where the code is not 0. Sorting
and factorising (so `groupby`) use the Stata key, which puts missing
values after every number in the order `.`, `.a`, ..., `.z`.
"""

import functools
import numbers
import operator
import re

import numpy as np
import pandas as pd
from pandas.api.extensions import ExtensionArray, ExtensionDtype, register_extension_dtype
from pandas.api.extensions import take as _take
from pandas.api.indexers import check_array_indexer
from pandas.api.types import is_integer, is_list_like, pandas_dtype

from .missing import _KEYS, MissingValue, from_code

STORAGE = ("byte", "int", "long", "float", "double")
_INTEGERS = ("byte", "int", "long")

_MISSING_BITS = np.uint64(0x7FE0000000000000)
_STEP = np.uint64(40)


def _wider(a, b):
    """The narrowest storage type holding every value of both."""
    if a == b:
        return a
    if a in _INTEGERS and b in _INTEGERS:
        return a if _INTEGERS.index(a) > _INTEGERS.index(b) else b
    if {a, b} <= {"byte", "int", "float"}:
        return "float"
    return "double"


@register_extension_dtype
class DtaDtype(ExtensionDtype):
    """The dtype of a DtaArray: `dta[byte]` ... `dta[double]`, after the
    Stata storage type the values are written in."""

    _metadata = ("storage",)
    type = float
    kind = "f"
    na_value = np.nan
    _is_numeric = True

    def __init__(self, storage="double"):
        if storage not in STORAGE:
            raise ValueError(f"storage must be one of {', '.join(STORAGE)}, not {storage!r}")
        self.storage = storage

    @property
    def name(self):
        return f"dta[{self.storage}]"

    @classmethod
    def construct_array_type(cls):
        return DtaArray

    @classmethod
    def construct_from_string(cls, string):
        if not isinstance(string, str):
            raise TypeError(f"'construct_from_string' expects a string, got {type(string)}")
        if string == "dta":
            return cls()
        m = re.fullmatch(r"dta\[(\w+)\]", string)
        if m and m.group(1) in STORAGE:
            return cls(m.group(1))
        raise TypeError(f"Cannot construct a 'DtaDtype' from '{string}'")

    def _get_common_dtype(self, dtypes):
        # A numpy or nullable type joins as the narrowest storage holding its
        # whole range exactly; int64 and uint64 do not fit a double, so
        # pandas falls back to object rather than round them.
        storages = [_storage_of(d) for d in dtypes]
        if any(s is None for s in storages):
            return None
        return DtaDtype(functools.reduce(_wider, storages))


# The storage that holds every value of a numpy dtype exactly.
_STORAGE_OF_KIND = {
    "b1": "byte", "i1": "int", "u1": "int", "i2": "long", "u2": "long",
    "i4": "double", "u4": "double", "f4": "float", "f8": "double",
}


def _storage_of(dtype):
    if isinstance(dtype, DtaDtype):
        return dtype.storage
    if isinstance(dtype, ExtensionDtype):
        numpy_dtype = getattr(dtype, "numpy_dtype", None)
        if numpy_dtype is None or not dtype._is_numeric and dtype.kind != "b":
            return None
        dtype = numpy_dtype
    try:
        dtype = np.dtype(dtype)
    except TypeError:
        return None
    return _STORAGE_OF_KIND.get(f"{dtype.kind}{dtype.itemsize}")


def _scalar(value):
    """(value, code) of one scalar."""
    if isinstance(value, MissingValue):
        return np.nan, value.code
    if value is None or value is pd.NA or value is pd.NaT:
        return np.nan, 1
    if isinstance(value, (numbers.Real, np.number)) and not isinstance(value, (bool, np.bool_)):
        value = float(value)
        return (np.nan, 1) if value != value else (value, 0)
    if isinstance(value, (bool, np.bool_)):
        return float(value), 0
    raise TypeError(f"a DtaArray holds numbers and missing values, not {value!r}")


def _operand(other, n):
    """The other operand of a comparison or arithmetic as arrays of length
    `n`: values (NaN where missing), codes (0, 1 for `.`, 2 to 27), named
    (True where a `MissingValue` names a letter) and text (True where it is
    text)."""
    zeros = np.zeros(n, dtype=bool)
    if isinstance(other, DtaArray):
        return other._values, other._codes, zeros, zeros
    if not is_list_like(other) or isinstance(other, (str, bytes)):
        if isinstance(other, (str, bytes)):
            return np.full(n, np.nan), np.zeros(n, dtype=np.uint8), zeros, ~zeros
        value, code = _scalar(other)
        named = isinstance(other, MissingValue)
        return (np.full(n, value), np.full(n, code, dtype=np.uint8),
                np.full(n, named), zeros)
    if len(other) != n:
        raise ValueError(f"operands of lengths {n} and {len(other)} cannot be compared or combined")
    if isinstance(other, ExtensionArray) and other.dtype._is_numeric:
        values = other.to_numpy(dtype=np.float64, na_value=np.nan)
        return values, np.isnan(values).astype(np.uint8), zeros, zeros
    if isinstance(other, np.ndarray) and other.dtype.kind in "biuf":
        values = other.astype(np.float64)
        return values, np.isnan(values).astype(np.uint8), zeros, zeros
    # Element by element: np.asarray of a list holding text would make
    # every element text.
    array = other if isinstance(other, (list, tuple)) else np.asarray(other, dtype=object)
    values = np.full(n, np.nan)
    codes = np.zeros(n, dtype=np.uint8)
    named = zeros.copy()
    text = zeros.copy()
    for i, v in enumerate(array):
        if isinstance(v, (str, bytes)):
            text[i] = True
        else:
            values[i], codes[i] = _scalar(v)
            named[i] = isinstance(v, MissingValue)
    return values, codes, named, text


def _from_keys(keys):
    """Values and codes of Stata keys."""
    keys = np.asarray(keys, dtype=np.float64)
    bits = keys.view(np.uint64)
    offset = bits - _MISSING_BITS
    is_missing = (bits >= _MISSING_BITS) & (bits < np.uint64(0x8000000000000000))
    is_missing &= (offset & np.uint64((1 << 40) - 1)) == 0
    step = offset >> _STEP
    is_missing &= step < 27
    codes = np.where(is_missing, step + 1, 0).astype(np.uint8)
    values = np.where(is_missing, np.nan, keys)
    # A NaN key (from outside) is `.`.
    codes[np.isnan(keys) & ~is_missing] = 1
    return values, codes


class DtaArray(ExtensionArray):
    """Numbers with Stata missing codes: `values` (float64) and `codes`
    (uint8: 0 not missing, 1 `.`, 2 to 27 `.a` to `.z`)."""

    __array_priority__ = 1000
    # Above pandas' own arrays (1000), so `Int64 + DtaArray` is left to
    # this array; below Index (2000) and Series (3000).
    __pandas_priority__ = 1500

    def __init__(self, values, codes=None, storage="double", copy=False):
        as_array = np.array if copy else np.asarray
        values = as_array(values, dtype=np.float64)
        if codes is None:
            codes = np.isnan(values).astype(np.uint8)
        else:
            codes = as_array(codes, dtype=np.uint8)
        if values.ndim != 1 or codes.shape != values.shape:
            raise ValueError("values and codes must be 1-dimensional and of one length")
        if codes.size and codes.max() > 27:
            raise ValueError("missing codes run from 0 to 27")
        missing = codes != 0
        if not np.array_equal(np.isnan(values), missing):
            values = np.where(missing, np.nan, values)
            codes = np.where(np.isnan(values) & ~missing, np.uint8(1), codes)
        self._values = values
        self._codes = codes
        self._dtype = DtaDtype(storage)

    @classmethod
    def _simple(cls, values, codes, dtype):
        self = object.__new__(cls)
        self._values = values
        self._codes = codes
        self._dtype = dtype
        return self

    @property
    def dtype(self):
        return self._dtype

    @property
    def codes(self):
        """The missing code of each row."""
        return self._codes

    @property
    def nbytes(self):
        return self._values.nbytes + self._codes.nbytes

    def __len__(self):
        return len(self._values)

    @classmethod
    def _from_sequence(cls, scalars, *, dtype=None, copy=False):
        dtype = pandas_dtype(dtype) if dtype is not None else None
        storage = dtype.storage if isinstance(dtype, DtaDtype) else None
        if isinstance(scalars, DtaArray):
            out = scalars.copy() if copy else scalars
            return out if storage is None else cls._simple(out._values, out._codes, DtaDtype(storage))
        if isinstance(scalars, pd.Series):
            scalars = scalars.array
        if isinstance(scalars, np.ndarray) and scalars.dtype.kind in "biuf":
            values = scalars.astype(np.float64, copy=True)
            return cls(values, None, storage or "double")
        if isinstance(scalars, ExtensionArray) and scalars.dtype._is_numeric:
            values = scalars.to_numpy(dtype=np.float64, na_value=np.nan)
            return cls(values, None, storage or "double")
        pairs = [_scalar(v) for v in scalars]
        values = np.fromiter((p[0] for p in pairs), dtype=np.float64, count=len(pairs))
        codes = np.fromiter((p[1] for p in pairs), dtype=np.uint8, count=len(pairs))
        return cls._simple(values, codes, DtaDtype(storage or "double"))

    @classmethod
    def _from_sequence_of_strings(cls, strings, *, dtype=None, copy=False):
        def parse(s):
            if s in (".", ""):
                return None
            if re.fullmatch(r"\.[a-z]", s):
                return from_code(ord(s[1]) - ord("a") + 2)
            return float(s)

        return cls._from_sequence([parse(s) for s in strings], dtype=dtype)

    @classmethod
    def _from_factorized(cls, values, original):
        v, c = _from_keys(values)
        return cls._simple(v, c, original.dtype)

    def _box(self, i):
        code = self._codes[i]
        return self._values[i] if code == 0 else from_code(code)

    def __getitem__(self, item):
        if is_integer(item):
            return self._box(item)
        if isinstance(item, tuple):
            if len(item) == 1:
                item = item[0]
            elif len(item) == 2 and item[0] is Ellipsis:
                item = item[1]
            elif len(item) == 2 and item[1] is Ellipsis:
                item = item[0]
            if is_integer(item):
                return self._box(item)
        if not isinstance(item, slice):
            item = check_array_indexer(self, item)
        return self._simple(self._values[item], self._codes[item], self._dtype)

    def __setitem__(self, key, value):
        if not is_integer(key) and not isinstance(key, slice):
            key = check_array_indexer(self, key)
        if is_list_like(value) and not isinstance(value, (str, bytes, MissingValue)):
            other = value if isinstance(value, DtaArray) else DtaArray._from_sequence(value)
            v, c = other._values, other._codes
        else:
            v, c = _scalar(value)
        self._values[key] = v
        self._codes[key] = c

    def __iter__(self):
        for value, code in zip(self._values.tolist(), self._codes.tolist()):
            yield value if code == 0 else from_code(code)

    def isna(self):
        return self._codes != 0

    @property
    def _hasna(self):
        return bool(self._codes.any())

    def take(self, indices, allow_fill=False, fill_value=None):
        if allow_fill:
            fill = (np.nan, 1) if fill_value is None or fill_value is self.dtype.na_value else _scalar(fill_value)
        else:
            fill = (None, None)
        values = _take(self._values, indices, allow_fill=allow_fill, fill_value=fill[0])
        codes = _take(self._codes, indices, allow_fill=allow_fill, fill_value=fill[1])
        return self._simple(values, codes.astype(np.uint8, copy=False), self._dtype)

    def copy(self):
        return self._simple(self._values.copy(), self._codes.copy(), self._dtype)

    @classmethod
    def _concat_same_type(cls, to_concat):
        to_concat = list(to_concat)
        storage = functools.reduce(_wider, (a.dtype.storage for a in to_concat), to_concat[0].dtype.storage)
        values = np.concatenate([a._values for a in to_concat])
        codes = np.concatenate([a._codes for a in to_concat])
        return cls._simple(values, codes, DtaDtype(storage))

    def keys(self):
        """The Stata key of each row (see `dta_parser.dta_keys`)."""
        keys = self._values.copy()
        missing = self._codes != 0
        if missing.any():
            keys[missing] = _KEYS[self._codes[missing].astype(np.intp) - 1]
        return keys

    def _values_for_factorize(self):
        return self.keys(), np.nan

    def _values_for_argsort(self):
        return self.keys()

    def argsort(self, *, ascending=True, kind="quicksort", na_position="last", **kwargs):
        # Numbers, then `.` < `.a` < ... < `.z`; descending reverses both.
        # na_position moves the missing rows as a block.
        keys = self.keys()
        order = np.argsort(keys if ascending else -keys, kind="stable")
        if na_position == "first":
            missing = self._codes[order] != 0
            order = np.concatenate([order[missing], order[~missing]])
        elif ascending is False:
            missing = self._codes[order] != 0
            order = np.concatenate([order[~missing], order[missing]])
        return order

    def unique(self):
        v, c = _from_keys(pd.unique(self.keys()))
        return self._simple(v, c, self._dtype)

    def value_counts(self, dropna=True):
        keep = ~self.isna() if dropna else slice(None)
        keys, counts = np.unique(self.keys()[keep], return_counts=True)
        v, c = _from_keys(keys)
        index = pd.Index(self._simple(v, c, self._dtype))
        return pd.Series(counts, index=index, name="count")

    def equals(self, other):
        if not isinstance(other, DtaArray) or self.dtype != other.dtype or len(self) != len(other):
            return False
        if not np.array_equal(self._codes, other._codes):
            return False
        return bool(np.array_equal(self._values, other._values, equal_nan=True))

    def __array__(self, dtype=None, copy=None):
        if dtype is not None and np.dtype(dtype) == object:
            out = self._values.astype(object)
            letters = self._codes > 1
            if letters.any():
                out[letters] = [from_code(c) for c in self._codes[letters]]
            return out
        if dtype is None or np.dtype(dtype) == np.float64:
            return self._values.copy() if copy else self._values
        return self._values.astype(dtype)

    def to_numpy(self, dtype=None, copy=False, na_value=pd.api.extensions.no_default):
        out = np.asarray(self, dtype=dtype)
        if na_value is not pd.api.extensions.no_default and self._hasna:
            out = out.copy() if out is self._values else out
            out[self.isna()] = na_value
        elif copy and out is self._values:
            out = out.copy()
        return out

    def astype(self, dtype, copy=True):
        dtype = pandas_dtype(dtype)
        if isinstance(dtype, DtaDtype):
            out = self.copy() if copy else self
            return self._simple(out._values, out._codes, dtype)
        if isinstance(dtype, ExtensionDtype):
            return super().astype(dtype, copy=copy)
        return np.array(self, dtype=dtype) if copy else np.asarray(self, dtype=dtype)

    def _formatter(self, boxed=False):
        return lambda x: x.name if isinstance(x, MissingValue) else ("." if x != x else repr(x))

    def _reduce(self, name, *, skipna=True, keepdims=False, **kwargs):
        values = self._values[self._codes == 0] if skipna else self._values
        ops = {
            "sum": np.sum, "prod": np.prod, "min": np.min, "max": np.max, "mean": np.mean,
            "median": np.median, "any": np.any, "all": np.all,
        }
        if name in ("std", "var", "sem"):
            ddof = kwargs.get("ddof", 1)
            if len(values) <= ddof:
                result = np.nan
            else:
                result = np.var(values, ddof=ddof) if name == "var" else np.std(values, ddof=ddof)
                if name == "sem":
                    result = result / np.sqrt(len(values))
        elif name in ("sum", "prod") and np.count_nonzero(self._codes == 0) < kwargs.get("min_count", 0):
            result = np.nan
        elif name in ops:
            if len(values) == 0 and name in ("min", "max", "mean", "median"):
                result = np.nan
            else:
                result = ops[name](values)
        else:
            raise TypeError(f"DtaArray does not support {name}")
        return np.array([result]) if keepdims else result

    def _compare(self, other, op):
        """A BooleanArray: where the other side names a letter (a
        `MissingValue`), `==` and `!=` compare letters and an ordering is
        <NA>; else <NA> where either side is missing; else the numbers.
        Text: `==` false and `!=` true on the numbers, an ordering an
        error."""
        if isinstance(other, (pd.Series, pd.Index, pd.DataFrame)):
            return NotImplemented
        n = len(self)
        values, codes, named, text = _operand(other, n)
        equality = op in (operator.eq, operator.ne)
        if text.any() and not equality:
            raise TypeError(f"cannot compare a DtaArray with text using {op.__name__}")
        result = np.zeros(n, dtype=bool)
        known = (self._codes == 0) & (codes == 0) & ~text
        with np.errstate(invalid="ignore"):
            result[known] = op(self._values[known], values[known])
        result[text] = op is operator.ne
        mask = ~known & ~named & ~text
        mask |= text & (self._codes != 0)
        if named.any():
            if equality:
                same = self._codes[named] == codes[named]
                result[named] = same if op is operator.eq else ~same
            else:
                mask |= named
        return pd.arrays.BooleanArray(result, mask)

    def _arith(self, other, op, reflected=False):
        """A DtaArray (double): a row missing on the left keeps its code,
        else one missing on the right keeps the right's, whatever the
        numbers give; a NaN the operation makes is `.`."""
        if isinstance(other, (pd.Series, pd.Index, pd.DataFrame)):
            return NotImplemented
        n = len(self)
        values, codes, _, text = _operand(other, n)
        if text.any():
            raise TypeError(f"unsupported operand: a DtaArray and text with {op.__name__}")
        left, right = (values, self._values) if reflected else (self._values, values)
        left_codes, right_codes = (codes, self._codes) if reflected else (self._codes, codes)
        with np.errstate(all="ignore"):
            out = np.asarray(op(left, right), dtype=np.float64)
        out_codes = np.where(left_codes != 0, left_codes, right_codes)
        out_codes = np.where((out_codes == 0) & np.isnan(out), np.uint8(1), out_codes).astype(np.uint8)
        out = np.where(out_codes != 0, np.nan, out)
        return self._simple(out, out_codes, DtaDtype("double"))

    def _unary(self, values):
        values = np.where(self._codes != 0, np.nan, values)
        return self._simple(values, self._codes.copy(), DtaDtype("double"))

    def __neg__(self):
        return self._unary(-self._values)

    def __pos__(self):
        return self._unary(self._values.copy())

    def __abs__(self):
        return self._unary(np.abs(self._values))

    def round(self, decimals=0, *args, **kwargs):
        values = np.round(self._values, decimals)
        return self._simple(np.where(self._codes != 0, np.nan, values), self._codes.copy(), self._dtype)

    def _accumulate(self, name, *, skipna=True, **kwargs):
        """cumsum, cumprod, cummin, cummax. With skipna, missing rows keep
        their codes and are passed over; without, every row from the first
        missing one on has that row's code."""
        funcs = {"cumsum": (np.add, 0.0), "cumprod": (np.multiply, 1.0),
                 "cummin": (np.minimum, np.inf), "cummax": (np.maximum, -np.inf)}
        if name not in funcs:
            raise TypeError(f"DtaArray does not support {name}")
        ufunc, identity = funcs[name]
        missing = self._codes != 0
        with np.errstate(all="ignore"):
            out = ufunc.accumulate(np.where(missing, identity, self._values))
        codes = self._codes.copy()
        if not skipna and missing.any():
            first = int(np.argmax(missing))
            codes[first:] = codes[first]
        codes[(codes == 0) & np.isnan(out)] = 1  # a NaN the accumulation makes is `.`
        out = np.where(codes != 0, np.nan, out)
        storage = self._dtype if name in ("cummin", "cummax") else DtaDtype("double")
        return self._simple(out, codes, storage)

    def isin(self, values):
        """True where the row's value is among `values`, by Stata key: a
        `MissingValue` matches its letter, NaN or None matches `.`."""
        if isinstance(values, (pd.Series, pd.Index)):
            values = values.array
        if isinstance(values, DtaArray):
            wanted = values.keys()
        else:
            # Text is never a number, so it matches nothing.
            wanted = np.fromiter((dta_key(v) for v in values if not isinstance(v, (str, bytes))), dtype=np.float64)
        return np.isin(self.keys(), wanted)


for _name, _op in [("eq", operator.eq), ("ne", operator.ne), ("lt", operator.lt),
                   ("le", operator.le), ("gt", operator.gt), ("ge", operator.ge)]:
    setattr(DtaArray, f"__{_name}__", lambda self, other, op=_op: self._compare(other, op))

for _name, _op in [("add", operator.add), ("sub", operator.sub), ("mul", operator.mul),
                   ("truediv", operator.truediv), ("floordiv", operator.floordiv),
                   ("mod", operator.mod), ("pow", operator.pow)]:
    setattr(DtaArray, f"__{_name}__", lambda self, other, op=_op: self._arith(other, op))
    setattr(DtaArray, f"__r{_name}__", lambda self, other, op=_op: self._arith(other, op, reflected=True))


def dta_key(value):
    """A float that sorts and compares as Stata does: a number is itself, and
    `.` (NaN, None, pd.NA) < `missing.a` < ... < `missing.z` come after every
    number. Use it to sort, group or compare with missing values in Stata's
    order: `sorted(values, key=dta_key)`."""
    if isinstance(value, MissingValue):
        return float(_KEYS[value.code - 1])
    if value is None or value is pd.NA or value is pd.NaT:
        return float(_KEYS[0])
    value = float(value)
    return float(_KEYS[0]) if value != value else value


def dta_keys(values):
    """`dta_key` of every value of a numeric column (a Series, DtaArray,
    numpy array or nullable array), as a float64 numpy array. Other columns
    (text, dates) come back unchanged, so `df.sort_values(by, key=dta_keys)`
    sorts by several columns in Stata's order."""
    original = values
    if isinstance(values, (pd.Series, pd.Index)):
        values = values.array
    if isinstance(values, DtaArray):
        return values.keys()
    if isinstance(values, ExtensionArray):
        if not values.dtype._is_numeric or values.dtype.kind not in "biuf":
            return original
        values = values.to_numpy(dtype=np.float64, na_value=np.nan)
    values = np.asarray(values)
    if values.dtype.kind in "biuf":
        keys = values.astype(np.float64)
        keys[np.isnan(keys)] = _KEYS[0]
        return keys
    if values.dtype == object:
        try:
            return np.fromiter((dta_key(v) for v in values), dtype=np.float64, count=len(values))
        except (TypeError, ValueError):
            pass
    return original


def missing_codes(values):
    """The missing code of every value of a column, as uint8: 0 not missing,
    1 `.` (NaN, NaT, None, pd.NA), 2 to 27 `.a` to `.z`."""
    if isinstance(values, (pd.Series, pd.Index)):
        values = values.array
    if isinstance(values, DtaArray):
        return values.codes.copy()
    if isinstance(values, np.ndarray) and values.dtype == object:
        return np.fromiter(
            (v.code if isinstance(v, MissingValue) else int(bool(pd.isna(v))) for v in values),
            dtype=np.uint8, count=len(values))
    return np.asarray(pd.isna(values), dtype=np.uint8)
