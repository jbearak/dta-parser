"""DtaArray compares as missing and keeps codes through arithmetic and the
pandas operations a numeric column meets (plan 0024, stage 3)."""

import numpy as np
import pandas as pd
import pytest

import dta_parser as dp
from conftest import FIXTURES
from dta_parser import DtaArray, DtaDtype, missing, read_dta

NA = pd.NA


def x():
    # 1, 5000, .a, .b, .
    return DtaArray([1.0, 5000.0, np.nan, np.nan, np.nan], [0, 0, 2, 3, 1], storage="double")


def result(r):
    """A comparison's result as a list with pd.NA."""
    return [NA if v is NA else bool(v) for v in pd.array(r, dtype="boolean")]


def codes(a):
    return (a.array if isinstance(a, pd.Series) else a).codes.tolist()


# -------------------------------------------------------------- comparisons


@pytest.mark.parametrize("wrap", [lambda a: a, pd.Series])
def test_numbers_compare_as_missing_in_both_orders(wrap):
    a = wrap(x())
    assert result(a == 1) == [True, False, NA, NA, NA]
    assert result(a != 1) == [False, True, NA, NA, NA]
    assert result(a > 3000) == [False, True, NA, NA, NA]
    assert result(1 == a) == [True, False, NA, NA, NA]
    assert result(3000 < a) == [False, True, NA, NA, NA]
    assert isinstance(x() == 1, pd.arrays.BooleanArray)


@pytest.mark.parametrize("value", [np.nan, None, pd.NA])
def test_a_missing_operand_gives_na(value):
    assert result(x() == value) == [NA] * 5
    assert result(x() != value) == [NA] * 5


def test_a_missing_value_names_its_letter():
    s = pd.Series(x())
    assert result(s == missing.a) == [False, False, True, False, False]
    assert result(s != missing.a) == [True, True, False, True, True]
    assert result(missing.a == s) == [False, False, True, False, False]
    assert result(missing.a != s) == [True, True, False, True, True]
    assert result(s < missing.a) == [NA] * 5
    assert result(missing.a < s) == [NA] * 5
    assert result(missing.a == x()) == [False, False, True, False, False]
    assert missing.a == missing.a and not (missing.a == 1.0)


def test_lists_and_arrays_compare_element_by_element():
    a = x()
    assert result(a == [1, 1, missing.a, missing.a, None]) == [True, False, True, False, NA]
    assert result(a == np.array([1.0, 2.0, 3.0, np.nan, 5.0])) == [True, False, NA, NA, NA]
    nullable = pd.array([1, 5000, 1, 1, None], dtype="Int64")
    assert result(a == nullable) == [True, True, NA, NA, NA]
    with pytest.raises(ValueError, match="lengths 5 and 2"):
        a == [1, 2]


def test_two_dta_arrays_holding_one_letter_compare_na():
    assert result(x() == x()) == [True, True, NA, NA, NA]


def test_text_is_never_equal_and_cannot_be_ordered():
    a = x()
    assert result(a == "a") == [False, False, NA, NA, NA]
    assert result(a != "a") == [True, True, NA, NA, NA]
    assert result(a == [1, "b", 1, 1, 1]) == [True, False, NA, NA, NA]
    with pytest.raises(TypeError):
        a < "a"


def test_filters_drop_missing_rows():
    df = pd.DataFrame({"x": x(), "row": range(5)})
    assert df[df["x"] != 1]["row"].tolist() == [1]
    assert df.loc[df["x"] > 3000, "row"].tolist() == [1]
    assert df.query("x != 1")["row"].tolist() == [1]
    assert df[df["x"] == missing.b]["row"].tolist() == [3]


def test_na_cannot_be_used_as_a_truth_value():
    mask = pd.Series(x()) != 1
    with pytest.raises(TypeError):
        np.where(mask, "y", "n")
    with pytest.raises(TypeError):
        bool(mask[2])


# --------------------------------------------------------------- arithmetic


def test_arithmetic_keeps_a_missing_operands_code():
    a = x()
    assert codes(a * 2) == [0, 0, 2, 3, 1]
    assert (a * 2).dtype == DtaDtype("double")
    assert np.asarray(a * 2)[:2].tolist() == [2.0, 10000.0]
    other = DtaArray([np.nan, np.nan, np.nan, 1.0, np.nan], [26, 1, 4, 0, 5])
    assert codes(a + other) == [26, 1, 2, 3, 1]   # the left's code first
    assert codes(other + a) == [26, 1, 4, 3, 5]   # then the right's
    assert codes(2 - a) == [0, 0, 2, 3, 1]
    assert np.asarray(2 - a)[:2].tolist() == [1.0, -4998.0]
    assert codes(a ** 0) == [0, 0, 2, 3, 1]       # missing stays missing
    zero = DtaArray([0.0, 1.0])
    assert codes(zero / zero) == [1, 0]            # a NaN the operation makes is `.`
    assert codes(-a) == codes(+a) == codes(abs(a)) == [0, 0, 2, 3, 1]
    assert np.asarray(-a)[:2].tolist() == [-1.0, -5000.0]
    with pytest.raises(TypeError):
        a + "a"


def test_series_arithmetic_and_operator_ufuncs_keep_codes():
    s = pd.Series(x())
    assert codes(s * 2) == [0, 0, 2, 3, 1]
    assert codes(s + pd.Series([1.0] * 5)) == [0, 0, 2, 3, 1]
    assert codes(pd.Series(np.add(x(), 1))) == [0, 0, 2, 3, 1]
    assert codes(pd.Series(np.abs(x()))) == [0, 0, 2, 3, 1]
    assert codes(np.negative(s)) == [0, 0, 2, 3, 1]


def test_other_ufuncs_map_and_apply_see_plain_values():
    s = pd.Series(x())
    logged = np.log(s)
    assert logged.dtype == np.float64
    assert logged.isna().tolist() == [False, False, True, True, True]
    seen = s.map(lambda v: v).tolist()
    assert seen[2] is missing.a and seen[3] is missing.b and seen[4] != seen[4]


# ------------------------------------------------------- pandas operations


@pytest.mark.parametrize("dtype, storage", [
    (np.bool_, "byte"), (np.int8, "int"), (np.uint8, "int"), (np.int16, "long"), (np.uint16, "long"),
    (np.int32, "double"), (np.uint32, "double"), (np.float32, "float"), (np.float64, "double"),
    ("Int8", "int"), ("Int16", "long"), ("Int32", "double"), ("Float64", "double"), ("boolean", "byte"),
])
def test_concat_with_numpy_and_nullable_types_gives_a_dta_array(dtype, storage):
    # Joined to a byte column, each type gives the narrowest storage that
    # holds its whole range.
    byte = pd.Series(DtaArray([1.0, np.nan, np.nan], [0, 2, 1], storage="byte"))
    other = pd.Series(np.array([1, 0]).astype(dtype if not isinstance(dtype, str) else "int8"))
    if isinstance(dtype, str):
        other = other.astype(dtype)
    both = pd.concat([byte, other], ignore_index=True)
    assert isinstance(both.array, DtaArray)
    assert both.dtype == DtaDtype(storage)
    assert codes(both) == [0, 2, 1, 0, 0]


def test_concat_keeps_the_narrowest_storage():
    byte = pd.Series(DtaArray([1.0, np.nan], [0, 1], storage="byte"))
    assert pd.concat([byte, pd.Series(np.array([3], dtype=np.int8))]).dtype == DtaDtype("int")
    assert pd.concat([byte, pd.Series(np.array([3], dtype=np.float32))]).dtype == DtaDtype("float")
    assert pd.concat([byte, pd.Series([True])]).dtype == DtaDtype("byte")


@pytest.mark.parametrize("dtype", [np.int64, np.uint64, "Int64", "UInt64"])
def test_concat_with_64_bit_integers_does_not_round(dtype):
    big = pd.Series(np.array([2**53, 2**53 + 1], dtype=np.int64 if dtype in (np.int64, "Int64") else np.uint64))
    big = big.astype(dtype)
    both = pd.concat([pd.Series(x()), big], ignore_index=True)
    assert both.dtype == object
    assert both.iloc[5] != both.iloc[6]


def test_to_numpy_and_astype_give_floats():
    a = x()
    assert np.isnan(a.to_numpy()[2:]).all()
    assert pd.Series(a).astype(float).dtype == np.float64
    df = pd.DataFrame({"x": a, "y": np.arange(5)})
    assert df.to_numpy(dtype=float).dtype == np.float64


def test_cumulative_functions():
    s = pd.Series(DtaArray([1.0, np.nan, 2.0, np.nan, 3.0], [0, 2, 0, 1, 0], storage="byte"))
    out = s.cumsum()
    assert codes(out) == [0, 2, 0, 1, 0]
    assert np.asarray(out.array)[[0, 2, 4]].tolist() == [1.0, 3.0, 6.0]
    assert out.dtype == DtaDtype("double")
    kept = s.cumsum(skipna=False)
    assert codes(kept) == [0, 2, 2, 2, 2]
    assert np.asarray(s.cummax().array)[[0, 2, 4]].tolist() == [1.0, 2.0, 3.0]
    assert s.cummin().dtype == DtaDtype("byte")
    assert np.asarray(s.cumprod().array)[[0, 2, 4]].tolist() == [1.0, 2.0, 6.0]


def test_windows_and_summaries_use_the_numbers():
    s = pd.Series(DtaArray([1.0, 2.0, np.nan, 4.0, 5.0], [0, 0, 2, 0, 0]))
    rolled = s.rolling(2).sum()
    assert rolled.tolist()[:2] == [pytest.approx(np.nan, nan_ok=True), 3.0]
    assert rolled.tolist()[4] == 9.0
    assert s.expanding().sum().tolist()[-1] == 12.0
    assert s.ewm(alpha=0.5).mean().notna().all()
    assert s.quantile(0.5) == 3.0
    assert s.describe()["count"] == 4
    df = pd.DataFrame({"a": s, "b": [2.0, 4.0, 6.0, 8.0, 10.0]})
    assert df.corr().loc["a", "b"] == pytest.approx(1.0)
    assert df.cov().loc["a", "a"] == pytest.approx(np.var([1, 2, 4, 5], ddof=1))


def test_fillna_where_mask_clip_round_isin():
    s = pd.Series(x())
    assert codes(s.fillna(0)) == [0, 0, 0, 0, 0]
    assert codes(s.fillna(missing.c)) == [0, 0, 4, 4, 4]  # every missing row, as pandas fills any NA
    assert codes(s.where(s.array.codes == 0, missing.r)) == [0, 0, 19, 19, 19]
    # pandas' where and mask treat a <NA> condition as "replace", so the
    # missing rows are replaced too; fillna(False) or loc keeps them.
    assert codes(s.mask(s == 1, missing.q)) == [18, 0, 18, 18, 18]
    assert codes(s.mask((s == 1).fillna(False), missing.q)) == [18, 0, 2, 3, 1]
    df = pd.DataFrame({"x": x()})
    df.loc[df["x"] == 1, "x"] = missing.q
    assert codes(df["x"]) == [18, 0, 2, 3, 1]
    clipped = s.clip(0, 10)
    assert codes(clipped) == [0, 0, 2, 3, 1]
    assert np.asarray(clipped.array)[:2].tolist() == [1.0, 10.0]
    rounded = pd.Series(DtaArray([1.26, np.nan], [0, 2])).round(1)
    assert codes(rounded) == [0, 2] and np.asarray(rounded.array)[0] == pytest.approx(1.3)
    assert s.isin([1, missing.b]).tolist() == [True, False, False, True, False]
    assert s.isin([np.nan]).tolist() == [False, False, False, False, True]


def test_merge_of_two_dta_array_keys_matches_letter_to_letter():
    left = pd.DataFrame({"k": x(), "row": range(5)})
    right = pd.DataFrame({"k": DtaArray([np.nan, np.nan, 5000.0, 7.0], [2, 1, 0, 0]), "lab": ["A", "dot", "big", "x"]})
    m = left.merge(right, on="k", how="left").sort_values("row")
    assert m["lab"].tolist() == [np.nan, "big", "A", np.nan, "dot"]


def test_groupby_keeps_dot_and_each_letter_apart():
    s = pd.Series(DtaArray([1.0, np.nan, np.nan, np.nan, 1.0], [0, 2, 3, 1, 0]))
    counts = pd.DataFrame({"x": s, "n": 1}).groupby("x")["n"].sum()
    assert len(counts) == 4


# ------------------------------------------------------------------ reading


def test_a_window_without_missing_values_keeps_its_numpy_type():
    whole = read_dta(FIXTURES / "readstat_111.dta")
    assert whole["i"].array.codes.tolist() == [0, 0, 1, 0, 0]
    first = read_dta(FIXTURES / "readstat_111.dta", n_max=2)
    assert first["i"].dtype == np.int16
    rest = read_dta(FIXTURES / "readstat_111.dta", skip=2)
    assert rest["i"].dtype == DtaDtype("int")
    both = pd.concat([first, rest], ignore_index=True)
    assert both["i"].dtype == DtaDtype("long")
    assert both["i"].array.codes.tolist() == [0, 0, 1, 0, 0]
    assert result(both["i"] != 1000) == [False, True, NA, True, True]


def test_a_frame_read_filtered_sorted_merged_and_written_keeps_its_codes(tmp_path):
    df = read_dta(FIXTURES / "haven_118.dta")
    num = df["num"]
    kept = df[(num > 0) | num.isna()].sort_values("num")
    path = tmp_path / "out.dta"
    dp.write_dta(kept, path)
    back = read_dta(path)
    assert sorted(back["num"].array.codes.tolist()) == sorted(kept["num"].array.codes.tolist())
