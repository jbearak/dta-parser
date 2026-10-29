"""StataArray keeps each row's missing code through the pandas operations
the plan lists, and orders and groups values as Stata does."""

import copy
import pickle

import numpy as np
import pandas as pd
import pytest

from dta_parser import MissingValue, StataArray, StataDtype, missing, missing_codes, stata_key, stata_keys


def frame():
    x = StataArray([3.0, np.nan, 1.0, np.nan, np.nan, 2.0], [0, 27, 0, 1, 2, 0], storage="long")
    return pd.DataFrame({"x": x, "row": [0, 1, 2, 3, 4, 5]})


def codes(series):
    return series.array.codes.tolist()


def test_missing_scalars():
    assert missing.a.code == 2 and missing.z.code == 27
    assert repr(missing.q) == ".q"
    assert MissingValue(5) is missing.d
    assert pickle.loads(pickle.dumps(missing.b)) is missing.b
    assert copy.deepcopy({"k": missing.c})["k"] is missing.c
    assert missing.a == missing.a and missing.a != missing.b
    assert sorted([missing.c, 5, missing.a, -1.0]) == [-1.0, 5, missing.a, missing.c]


def test_stata_key_orders_numbers_then_missing_values():
    values = [missing.z, 3, np.nan, -1e300, missing.a, 8.98e307, 0, None]
    ordered = sorted(values, key=stata_key)
    assert ordered[:4] == [-1e300, 0, 3, 8.98e307]
    assert [stata_key(v) for v in ordered[4:]] == sorted(stata_key(v) for v in [np.nan, None, missing.a, missing.z])
    assert stata_key(missing.a) < stata_key(missing.b)
    assert np.isfinite(stata_key(missing.z))
    # The doubles Stata stores for `.` and `.a`.
    assert np.float64(stata_key(np.nan)).view(np.uint64) == 0x7FE0000000000000
    assert np.float64(stata_key(missing.a)).view(np.uint64) == 0x7FE0000000000000 + (1 << 40)


def test_stata_keys_of_columns():
    df = frame()
    keys = stata_keys(df["x"])
    assert keys[0] == 3.0 and keys[2] == 1.0
    assert keys[3] == stata_key(np.nan) and keys[4] == stata_key(missing.a) and keys[1] == stata_key(missing.z)
    assert stata_keys(pd.Series([1.0, np.nan])).tolist() == [1.0, stata_key(np.nan)]
    assert stata_keys(pd.array([1, None], dtype="Int64")).tolist() == [1.0, stata_key(np.nan)]
    assert missing_codes(df["x"]).tolist() == [0, 27, 0, 1, 2, 0]
    assert missing_codes(pd.Series([1.0, np.nan])).tolist() == [0, 1]


def test_scalar_get_and_set():
    df = frame()
    assert df["x"][1] is missing.z
    assert np.isnan(df["x"][3])
    assert df["x"][0] == 3.0
    df.loc[0, "x"] = missing.q
    df.iloc[2, 0] = np.nan
    df.at[5, "x"] = 7
    df.loc[3, "x"] = missing.b
    assert codes(df["x"]) == [18, 27, 1, 3, 2, 0]
    assert df["x"][5] == 7.0
    s = df["x"].copy()
    s[s.array.codes == 2] = missing.c
    assert codes(s) == [18, 27, 1, 3, 4, 0]
    with pytest.raises(TypeError):
        df.loc[0, "x"] = "text"


def test_selection_keeps_codes():
    df = frame()
    assert codes(df[df["row"] > 2]["x"]) == [1, 2, 0]
    assert codes(df.iloc[[4, 1]]["x"]) == [2, 27]
    assert codes(df.loc[[1, 3], "x"]) == [27, 1]
    assert codes(df.iloc[1:3]["x"]) == [27, 0]
    assert codes(df[df["x"].isna()]["x"]) == [27, 1, 2]
    assert codes(df.loc[df["x"] == missing.a]["x"]) == [2]


def test_sort_values_in_stata_order():
    df = frame()
    out = df.sort_values("x")
    assert out["row"].tolist() == [2, 5, 0, 3, 4, 1]
    assert codes(out["x"]) == [0, 0, 0, 1, 2, 27]
    out = df.sort_values("x", na_position="first")
    assert out["row"].tolist() == [3, 4, 1, 2, 5, 0]
    out = df.sort_values("x", ascending=False)
    assert out["row"].tolist() == [0, 5, 2, 1, 4, 3]
    # Several columns sort through pandas' Categorical, which takes no missing
    # categories; stata_keys as the key sorts them in Stata order.
    out = df.sort_values(["x", "row"], key=stata_keys)
    assert out["row"].tolist() == [2, 5, 0, 3, 4, 1]
    assert df["x"].sort_values().array.codes.tolist() == [0, 0, 0, 1, 2, 27]


def test_concat_and_merge_keep_codes():
    a, b = frame(), frame()
    both = pd.concat([a, b], ignore_index=True)
    assert codes(both["x"]) == [0, 27, 0, 1, 2, 0] * 2
    other = pd.DataFrame({"row": [1, 4, 9], "y": StataArray([np.nan, 5.0, np.nan], [3, 0, 1], storage="byte")})
    merged = a.merge(other, on="row", how="left")
    assert codes(merged["x"]) == [0, 27, 0, 1, 2, 0]
    assert codes(merged["y"]) == [1, 3, 1, 1, 0, 1]
    assert merged["y"].dtype == StataDtype("byte")
    inner = a.merge(other, on="row")
    assert codes(inner["x"]) == [27, 2] and codes(inner["y"]) == [3, 0]
    # Concatenating different storage types widens.
    wide = pd.concat([pd.Series(StataArray([1.0], storage="byte")), pd.Series(StataArray([2.0], storage="long"))])
    assert wide.dtype == StataDtype("long")


def test_merge_on_a_stata_array_column():
    left = pd.DataFrame({"k": StataArray([1.0, np.nan, np.nan], [0, 2, 3]), "a": [1, 2, 3]})
    right = pd.DataFrame({"k": StataArray([np.nan, 1.0], [3, 0]), "b": ["b", "one"]})
    out = left.merge(right, on="k")
    assert out["a"].tolist() == [1, 3]
    assert codes(out["k"]) == [0, 3]


def test_reindex_fills_with_system_missing():
    df = frame()
    out = df.reindex([4, 1, 10])
    assert codes(out["x"]) == [2, 27, 1]
    assert codes(df["x"].reindex([0, 7])) == [0, 1]


def test_copy_keeps_codes_and_is_independent():
    df = frame()
    other = df.copy()
    other.loc[0, "x"] = missing.k
    assert codes(df["x"])[0] == 0
    assert codes(other["x"])[0] == 12
    assert codes(copy.deepcopy(df)["x"]) == codes(df["x"])
    assert codes(pickle.loads(pickle.dumps(df))["x"]) == codes(df["x"])


def test_groupby_keeps_each_missing_value_its_own_group():
    x = StataArray([1.0, np.nan, np.nan, 1.0, np.nan, np.nan], [0, 1, 2, 0, 2, 27])
    df = pd.DataFrame({"x": x, "n": [1, 2, 3, 4, 5, 6]})
    sums = df.groupby("x")["n"].sum()
    assert sums.tolist() == [5, 2, 8, 6]
    assert sums.index.array.codes.tolist() == [0, 1, 2, 27]
    sizes = df.groupby("x", sort=False).size()
    assert sizes.index.array.codes.tolist() == [0, 1, 2, 27]
    assert sizes.tolist() == [2, 1, 2, 1]
    firsts = df.groupby("n")["x"].first()
    assert len(firsts) == 6


def test_construction_and_conversion():
    s = pd.Series([1, None, missing.a, 2.5], dtype="stata[int]")
    assert s.dtype == StataDtype("int")
    assert codes(s) == [0, 1, 2, 0]
    assert s.to_numpy().dtype == np.float64
    assert np.isnan(s.to_numpy()[2])
    assert s.astype(object).tolist()[2] is missing.a
    assert s.astype("float64").isna().tolist() == [False, True, True, False]
    assert s.sum() == 3.5 and s.max() == 2.5 and s.mean() == 1.75
    assert (s + 1).tolist()[0] == 2.0
    assert s.unique().codes.tolist() == [0, 1, 2, 0]
    assert len(s.unique()) == 4
    assert "a" in repr(s)
    assert StataArray([1.0, np.nan]).codes.tolist() == [0, 1]
    with pytest.raises(ValueError):
        StataArray([1.0], [28])
    assert s.array.equals(s.array.copy())
    assert not s.array.equals(StataArray._from_sequence([1, None, missing.b, 2.5], dtype="stata[int]"))
