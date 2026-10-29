"""StataArray: numbers that keep Stata's missing codes (`.`, `.a` to `.z`).

A StataArray holds float64 values and a uint8 missing code per row (see
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
class StataDtype(ExtensionDtype):
    """The dtype of a StataArray: `stata[byte]` ... `stata[double]`, after the
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
        return f"stata[{self.storage}]"

    @classmethod
    def construct_array_type(cls):
        return StataArray

    @classmethod
    def construct_from_string(cls, string):
        if not isinstance(string, str):
            raise TypeError(f"'construct_from_string' expects a string, got {type(string)}")
        if string == "stata":
            return cls()
        m = re.fullmatch(r"stata\[(\w+)\]", string)
        if m and m.group(1) in STORAGE:
            return cls(m.group(1))
        raise TypeError(f"Cannot construct a 'StataDtype' from '{string}'")

    def _get_common_dtype(self, dtypes):
        if all(isinstance(d, StataDtype) for d in dtypes):
            return StataDtype(functools.reduce(_wider, (d.storage for d in dtypes)))
        return None


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
    raise TypeError(f"a StataArray holds numbers and missing values, not {value!r}")


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


class StataArray(ExtensionArray):
    """Numbers with Stata missing codes: `values` (float64) and `codes`
    (uint8: 0 not missing, 1 `.`, 2 to 27 `.a` to `.z`)."""

    __array_priority__ = 1000

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
        self._dtype = StataDtype(storage)

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
        storage = dtype.storage if isinstance(dtype, StataDtype) else None
        if isinstance(scalars, StataArray):
            out = scalars.copy() if copy else scalars
            return out if storage is None else cls._simple(out._values, out._codes, StataDtype(storage))
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
        return cls._simple(values, codes, StataDtype(storage or "double"))

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
            other = value if isinstance(value, StataArray) else StataArray._from_sequence(value)
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
        return cls._simple(values, codes, StataDtype(storage))

    def keys(self):
        """The Stata key of each row (see `dta_parser.stata_keys`)."""
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
        if not isinstance(other, StataArray) or self.dtype != other.dtype or len(self) != len(other):
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
        if isinstance(dtype, StataDtype):
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
            raise TypeError(f"StataArray does not support {name}")
        return np.array([result]) if keepdims else result

    def _compare(self, other, op):
        if isinstance(other, (pd.Series, pd.Index, pd.DataFrame)):
            return NotImplemented
        if isinstance(other, MissingValue):
            hit = self._codes == other.code
            return hit if op is operator.eq else ~hit if op is operator.ne else op(self._values, np.nan)
        if isinstance(other, StataArray):
            other = other._values
        return op(self._values, np.asarray(other) if is_list_like(other) else other)

    def _arith(self, other, op):
        if isinstance(other, (pd.Series, pd.Index, pd.DataFrame)):
            return NotImplemented
        if isinstance(other, StataArray):
            other = other._values
        elif isinstance(other, MissingValue):
            other = np.nan
        return op(self._values, np.asarray(other) if is_list_like(other) else other)

    def __neg__(self):
        return -self._values

    def __pos__(self):
        return self._values.copy()

    def __abs__(self):
        return np.abs(self._values)


def _reflected(op):
    return lambda a, b: op(b, a)


for _name, _op in [("eq", operator.eq), ("ne", operator.ne), ("lt", operator.lt),
                   ("le", operator.le), ("gt", operator.gt), ("ge", operator.ge)]:
    setattr(StataArray, f"__{_name}__", lambda self, other, op=_op: self._compare(other, op))

for _name, _op in [("add", operator.add), ("sub", operator.sub), ("mul", operator.mul),
                   ("truediv", operator.truediv), ("floordiv", operator.floordiv),
                   ("mod", operator.mod), ("pow", operator.pow)]:
    setattr(StataArray, f"__{_name}__", lambda self, other, op=_op: self._arith(other, op))
    setattr(StataArray, f"__r{_name}__", lambda self, other, op=_reflected(_op): self._arith(other, op))


def stata_key(value):
    """A float that sorts and compares as Stata does: a number is itself, and
    `.` (NaN, None, pd.NA) < `missing.a` < ... < `missing.z` come after every
    number. Use it to sort, group or compare with missing values in Stata's
    order: `sorted(values, key=stata_key)`."""
    if isinstance(value, MissingValue):
        return float(_KEYS[value.code - 1])
    if value is None or value is pd.NA or value is pd.NaT:
        return float(_KEYS[0])
    value = float(value)
    return float(_KEYS[0]) if value != value else value


def stata_keys(values):
    """`stata_key` of every value of a numeric column (a Series, StataArray,
    numpy array or nullable array), as a float64 numpy array. Other columns
    (text, dates) come back unchanged, so `df.sort_values(by, key=stata_keys)`
    sorts by several columns in Stata's order."""
    original = values
    if isinstance(values, (pd.Series, pd.Index)):
        values = values.array
    if isinstance(values, StataArray):
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
            return np.fromiter((stata_key(v) for v in values), dtype=np.float64, count=len(values))
        except (TypeError, ValueError):
            pass
    return original


def missing_codes(values):
    """The missing code of every value of a column, as uint8: 0 not missing,
    1 `.` (NaN, NaT, None, pd.NA), 2 to 27 `.a` to `.z`."""
    if isinstance(values, (pd.Series, pd.Index)):
        values = values.array
    if isinstance(values, StataArray):
        return values.codes.copy()
    if isinstance(values, np.ndarray) and values.dtype == object:
        return np.fromiter(
            (v.code if isinstance(v, MissingValue) else int(bool(pd.isna(v))) for v in values),
            dtype=np.uint8, count=len(values))
    return np.asarray(pd.isna(values), dtype=np.uint8)
