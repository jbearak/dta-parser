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


def tagged(values, letters=None, name=""):
    """A Float64 Series of `values`, with the tagged NaN of each letter of
    `letters` (".a" to ".z", or None) where it has one."""
    import polars as pl

    import datakit as dk

    letters = letters or [None] * len(values)
    return pl.Series(name, [dk.tagged_na(t) if t is not None else v for v, t in zip(values, letters)],
                     dtype=pl.Float64)


def tags(s):
    """The letters of a Series as a list, None where it has none."""
    import datakit as dk

    return dk.na_tag(s).to_list()


def assert_same(a, b):
    """assert_frame_equal, which counts every NaN as equal, and the same
    letter in every Float64 cell."""
    import polars as pl
    from polars.testing import assert_frame_equal

    assert_frame_equal(a, b)
    for name, t in b.schema.items():
        if t == pl.Float64:
            assert tags(a[name]) == tags(b[name]), name
