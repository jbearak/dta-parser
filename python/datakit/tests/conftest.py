from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "compat" / "fixtures"
PARQUET = ROOT / "compat" / "parquet"


def fixture_paths():
    return sorted(FIXTURES.glob("*.dta"))


@pytest.fixture(params=fixture_paths(), ids=lambda p: p.stem)
def dta(request):
    return request.param


def lettered(values, letters=None, name=None, storage="double"):
    """A Series of `values` (a DtaArray of `storage`), with each letter of
    `letters` (".a" to ".z", or None) where it has one."""
    import pandas as pd

    import datakit as dk

    letters = letters or [None] * len(values)
    return pd.Series(pd.array([dk.tagged_na(t) if t is not None else v for v, t in zip(values, letters)],
                              dtype=f"dta[{storage}]"), name=name)


def tags(s):
    """The letters of a Series as a list, None where it has none."""
    import datakit as dk

    return [None if v != v else v for v in dk.na_tag(s).tolist()]


def is_text(dtype):
    """pandas' default text dtype: `str` from pandas 3, object before."""
    import pandas as pd

    return dtype == object or isinstance(dtype, pd.StringDtype)


def assert_same(a, b):
    """assert_frame_equal, and the same code (`.`, `.a` ...) in every
    missing cell of a DtaArray or float column."""
    import numpy as np
    import pandas as pd

    from dta_parser import DtaArray

    pd.testing.assert_frame_equal(a, b)
    for name in b.columns:
        if isinstance(b[name].array, DtaArray):
            assert np.array_equal(a[name].array.codes, b[name].array.codes), name
        elif b[name].dtype.kind == "f":
            assert tags(a[name]) == tags(b[name]), name
