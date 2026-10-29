"""Stata's extended missing values `.a` to `.z`.

`missing.a` ... `missing.z` are the values a `StataArray` gives back for
them, and what assignment into one accepts. System missing `.` is NaN,
as everywhere else in pandas.

A missing code is 0 for a value that is not missing, 1 for `.` and 2 to
27 for `.a` to `.z`.
"""

import numpy as np

__all__ = ["MissingValue", "from_code"] + [chr(c) for c in range(ord("a"), ord("z") + 1)]


class MissingValue:
    """One of `.a` to `.z`. There is one object per letter: compare with `is`
    or `==`. They sort after every number, in order, as in Stata."""

    __slots__ = ("code",)

    def __new__(cls, code):
        return _BY_CODE[code]

    @classmethod
    def _make(cls, code):
        self = object.__new__(cls)
        self.code = code
        return self

    @property
    def name(self):
        return "." + chr(ord("a") + self.code - 2)

    def __repr__(self):
        return self.name

    __str__ = __repr__

    def __reduce__(self):
        return (MissingValue, (self.code,))

    def __copy__(self):
        return self

    def __deepcopy__(self, memo):
        return self

    def __hash__(self):
        return hash(("dta_parser.missing", self.code))

    def __eq__(self, other):
        return self is other

    def __ne__(self, other):
        return self is not other

    def __float__(self):
        return float("nan")

    def _key(self):
        return _KEYS[self.code - 1]

    def __lt__(self, other):
        return self._key() < _key_of(other)

    def __le__(self, other):
        return self._key() <= _key_of(other)

    def __gt__(self, other):
        return self._key() > _key_of(other)

    def __ge__(self, other):
        return self._key() >= _key_of(other)


# The doubles Stata stores for `.` to `.z`: finite, increasing, and above
# every number Stata stores. Index 0 is `.`.
_KEYS = (np.uint64(0x7FE0000000000000) + (np.arange(27, dtype=np.uint64) << np.uint64(40))).view(np.float64)


def _key_of(value):
    if isinstance(value, MissingValue):
        return value._key()
    value = float(value)
    return _KEYS[0] if value != value else value


_BY_CODE = {code: MissingValue._make(code) for code in range(2, 28)}


def from_code(code):
    """The missing value of a code: NaN for 1 (`.`), `missing.a` for 2, ...
    `missing.z` for 27."""
    if code == 1:
        return float("nan")
    try:
        return _BY_CODE[int(code)]
    except KeyError:
        raise ValueError(f"{code} is not a missing code (1 to 27)") from None


for _code, _value in _BY_CODE.items():
    globals()[_value.name[1:]] = _value
del _code, _value
