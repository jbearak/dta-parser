"""`.a` to `.z` in the frame (ADR 0040): tagged_na, na_tag and
is_tagged_na; letters through pandas operations and the guide's recipes;
Meta's methods; and `factors`."""

import struct
import warnings

import numpy as np
import pandas as pd
import pytest

import datakit as dk
from conftest import assert_same, lettered, tags
from dta_parser import DtaArray, missing


def survey():
    """A file with letters in x (double) and y (int), a labelled column
    and a sort."""
    df = pd.DataFrame({
        "id": np.arange(1, 7, dtype=np.int32),
        "age": np.array([12, 30, 14, 45, 16, 60], dtype=np.int8),
        "x": lettered([1.5, None, 2.5, None, None, 4.0], [None, ".d", None, ".a", None, None]),
        "y": lettered([10, 20, None, 40, 50, None], [None, None, ".z", None, None, None], storage="int"),
        "z": np.array([1, 2, 3, 4, 5, 6], dtype=np.int8),
        "s": ["a", "b", "c", "d", "e", "f"],
    })
    meta = dk.Meta(
        label="Survey", sort=["id"],
        columns={c: dk.Column() for c in df.columns},
        value_labels={"yn": {1: "Yes", 2: "No", 3: "Yes", ".d": "Don't know"}},
        rows=6,
    )
    meta.columns["z"].value_labels = "yn"
    meta.columns["x"].label = "Income"
    return dk.read_parquet(dk.save_parquet(df, meta=meta))


def quiet(fn, *a, **k):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return fn(*a, **k)


def bits(v):
    return struct.unpack("<Q", struct.pack("<d", v))[0]


def tagged_float(letter):
    return struct.unpack("<d", struct.pack("<Q", 0x7FF0_0000_0000_07A2 | (ord(letter[-1]) << 32)))[0]


# ---------------------------------------------------------------- the functions

def test_tagged_na_is_a_missing_value():
    assert dk.tagged_na(".a") is missing.a
    assert dk.tagged_na("z") is missing.z
    for bad in ("", ".", "A", ".A", "ab", "..a", "1"):
        with pytest.raises(ValueError, match='a letter is ".a" to ".z"'):
            dk.tagged_na(bad)
    with pytest.raises(TypeError):
        dk.tagged_na(1)


def test_na_tag_reads_every_letter_and_nothing_else():
    letters = [f".{chr(c)}" for c in range(ord("a"), ord("z") + 1)]
    s = lettered([None] * 26, letters, name="x")
    t = dk.na_tag(s)
    assert tags(s) == letters and t.dtype == dk.LETTERS and t.name == "x"
    assert isinstance(dk.LETTERS, pd.CategoricalDtype) and list(dk.LETTERS.categories) == letters
    # A plain float column's tagged NaNs are letters too (R's layout).
    floats = pd.Series([tagged_float(".a"), 1.0, np.nan, tagged_float(".q")])
    assert tags(floats) == [".a", None, None, ".q"]
    others = pd.Series([1.0, float("nan"), None, float("inf"),
                        struct.unpack("<d", struct.pack("<Q", 0x7FF0_0000_0000_07A2))[0],
                        struct.unpack("<d", struct.pack("<Q", 0x7FF0_0041_0000_07A2))[0],
                        struct.unpack("<d", struct.pack("<Q", 0x7FF0_0061_0000_07A3))[0]])
    assert tags(others) == [None] * 7
    # Arithmetic on a plain float may quiet the NaN or flip its sign; the
    # letter stays. On a DtaArray the code stays.
    a = pd.Series([tagged_float(".q")])
    for changed in (a * 2, a + 1, -a, a / 3, (a * 2).abs()):
        assert tags(changed) == [".q"]
    d = lettered([None], [".q"])
    for changed in (d * 2, d + 1, -d, d / 3, (d * 2).abs()):
        assert tags(changed) == [".q"]
    # Other dtypes hold no letter.
    for s in (pd.Series([1, None], dtype="Int64"), pd.Series(["a", None]), pd.Series([1, 2], dtype=np.int8),
              pd.Series(pd.to_datetime(["2020-01-01", None])), pd.Series(pd.Categorical(["x", None]))):
        assert tags(s) == [None, None], s.dtype
        assert dk.is_tagged_na(s).tolist() == [False, False]


def test_the_functions_take_a_series_or_an_array():
    s = lettered([1.0, None, None], [None, ".b", None], name="x")
    assert tags(s) == [None, ".b", None]
    assert tags(s.array) == [None, ".b", None]
    assert tags(s * 2) == [None, ".b", None]
    assert dk.is_tagged_na(s).tolist() == [False, True, False]
    assert isinstance(dk.is_tagged_na(s), np.ndarray) and dk.is_tagged_na(s).dtype == bool
    assert dk.is_tagged_na(s, ".b").tolist() == [False, True, False]
    assert dk.is_tagged_na(s, "c").tolist() == [False, False, False]
    assert dk.is_tagged_na(s.array, "b").tolist() == [False, True, False]
    s.index = [10, 20, 30]
    assert dk.na_tag(s).index.tolist() == [10, 20, 30]
    with pytest.raises(TypeError):
        dk.na_tag(1.0)
    with pytest.raises(ValueError):
        dk.is_tagged_na(s, "ab")


def test_a_letter_made_with_these_functions_is_saved_and_read_back(tmp_path):
    df = pd.DataFrame({"x": pd.Series([1.0, 2.0, 3.0], dtype="dta[double]")})
    df.loc[df["x"] > 1.5, "x"] = dk.tagged_na(".a")
    assert tags(df["x"]) == [None, ".a", ".a"]
    for save, read, target in ((dk.save_parquet, dk.read_parquet, tmp_path / "a.parquet"),
                               (dk.save_dta, dk.read_dta, tmp_path / "a.dta")):
        save(df, target)
        back, _ = read(target)
        assert tags(back["x"]) == [None, ".a", ".a"] and dk.is_tagged_na(back["x"], ".a").tolist() == [False, True, True]


# ---------------------------------------------------------------- reading

def test_a_read_puts_the_letters_in_the_column():
    df, meta = survey()
    assert list(df.columns) == ["id", "age", "x", "y", "z", "s"]
    assert df["x"].dtype == "dta[double]" and df["y"].dtype == "dta[int]" and df["age"].dtype == np.int8
    assert tags(df["x"]) == [None, ".d", None, ".a", None, None]
    assert tags(df["y"]) == [None, None, ".z", None, None, None]
    # Every missing value is missing to pandas.
    assert df["x"].isna().sum() == 3 and df["x"].count() == 3
    assert df["x"].mean() == pytest.approx((1.5 + 2.5 + 4.0) / 3)


def test_the_same_expression_on_windows_with_and_without_letters():
    df, meta = survey()
    raw = dk.save_parquet(df, meta=meta)
    with_, _ = dk.read_parquet(raw, n_max=3)
    without, _ = dk.read_parquet(raw, skip=3)
    assert with_["y"].dtype == "dta[int]" and without["y"].dtype == "dta[int]"
    assert (with_["y"] * 2).tolist()[:2] == [20.0, 40.0]
    # Filters agree: a missing row is dropped in either.
    assert with_[with_["y"] != 20]["id"].tolist() == [1]
    assert without[without["y"] != 40]["id"].tolist() == [5]
    # A window with no missing value keeps the numpy type, and concat
    # with one that has gives a DtaArray (long: int16's whole range does
    # not fit Stata's int).
    first, _ = dk.read_parquet(raw, n_max=2)
    assert first["y"].dtype == np.int16
    both = pd.concat([first, without], ignore_index=True)
    assert both["y"].dtype == "dta[long]" and both["y"].array.codes.tolist() == [0, 0, 0, 0, 1]


def test_letters_false_keeps_none():
    df, meta = survey()
    df, meta = dk.read_parquet(dk.save_parquet(df, meta=meta), letters=False)
    assert df["x"].isna().sum() == 3 and tags(df["x"]) == [None] * 6
    assert df["y"].dtype == "dta[int]" and df["y"].array.codes.tolist() == [0, 0, 1, 0, 0, 1]


# ---------------------------------------------------------------- through pandas

def test_filter_sort_merge_and_concat_carry_the_letters():
    df, meta = survey()
    out = df[df["id"] > 1].sort_values("id", ascending=False)
    assert tags(out["x"]) == [None, None, ".a", None, ".d"]
    joined = df.merge(df[["id", "x"]].rename(columns={"x": "x2"}), on="id", how="left")
    assert tags(joined["x2"]) == tags(df["x"])
    assert tags(pd.concat([df, df])["x"]) == tags(df["x"]) * 2
    back, _ = quiet(dk.read_parquet, quiet(dk.save_parquet, out))
    assert tags(back["x"]) == tags(out["x"])


def test_comparisons_treat_letters_as_missing():
    # As R's doubles: a comparison with a missing row is <NA>, which a
    # filter drops; `== tagged_na(".d")` names a letter.
    df, _ = survey()
    assert (df["x"] > 3).tolist() == [False, pd.NA, False, pd.NA, pd.NA, True]
    assert df[df["x"] != 2.5]["id"].tolist() == [1, 6]
    assert df[df["x"] == dk.tagged_na(".d")]["id"].tolist() == [2]
    assert df[~dk.is_tagged_na(df["x"], ".d")]["id"].tolist() == [1, 3, 4, 5, 6]
    assert df.query("x > 1")["id"].tolist() == [1, 3, 6]


def test_groupby_keeps_dot_and_each_letter_apart():
    df = pd.DataFrame({"x": lettered([1.0, None, None, None, 1.0, None], [None, ".a", ".b", None, None, ".a"]),
                       "n": 1})
    counts = df.groupby("x", dropna=False)["n"].sum()
    assert [str(k) for k in counts.index] == ["1.0", "nan", ".a", ".b"]
    assert counts.tolist() == [2, 1, 2, 1]


def test_recipe_set_a_letter():
    df, meta = survey()
    out = df.copy()
    out.loc[out["age"] > 40, "x"] = dk.tagged_na(".r")
    assert tags(out["x"]) == [None, ".d", None, ".r", None, ".r"]
    # mask with a condition that may be <NA>: fillna(False) first, since
    # mask replaces where the condition is <NA> too.
    cond = out["x"] > 2
    assert tags(out["x"].mask(cond.fillna(False), dk.tagged_na(".s"))) == [None, ".d", ".s", ".r", None, ".r"]
    assert tags(out["x"].mask(cond, dk.tagged_na(".s"))) == [None, ".s", ".s", ".s", ".s", ".s"]
    # A numpy column must become a DtaArray first.
    out["z"] = out["z"].astype("dta[byte]")
    out.loc[out["age"] > 40, "z"] = dk.tagged_na(".r")
    assert out["z"].dtype == "dta[byte]" and tags(out["z"]) == [None, None, None, ".r", None, ".r"]
    back, _ = quiet(dk.read_parquet, quiet(dk.save_parquet, out, meta=meta))
    assert_same(back, out)


def test_a_missing_value_into_a_numpy_column(tmp_path):
    s = pd.Series([1.0, 2.0])
    if int(pd.__version__.split(".")[0]) >= 3:
        with pytest.raises(TypeError):
            s.loc[0] = dk.tagged_na(".a")
    else:
        with pytest.warns(FutureWarning):
            s.loc[0] = dk.tagged_na(".a")
        assert s.dtype == object
        with pytest.raises(TypeError, match=r'astype\("dta\[double\]"\)'):
            dk.save_parquet(pd.DataFrame({"x": s}))
        with pytest.raises(TypeError, match=r'astype\("dta\[double\]"\)'):
            dk.save_dta(pd.DataFrame({"x": s}), tmp_path / "x.dta")
    obj = pd.DataFrame({"x": pd.Series([missing.a, 1.0], dtype=object)})
    with pytest.raises(TypeError, match=r'df\["x"\] = df\["x"\].astype\("dta\[double\]"\)'):
        dk.save_parquet(obj)


def test_recipe_replace_a_letter_with_a_value():
    df, meta = survey()
    x = df["x"].copy()
    x[dk.is_tagged_na(x, ".d")] = 0.0
    assert tags(x) == [None, None, None, ".a", None, None] and x[1] == 0.0
    # fillna fills every missing row, letters included.
    assert df["x"].fillna(0.0).isna().sum() == 0


def test_recipe_new_column():
    df, meta = survey()
    out = df.assign(y2=pd.Series([dk.tagged_na(".a")] * len(df), dtype="dta[double]"))
    assert out["y2"].dtype == "dta[double]" and tags(out["y2"]) == [".a"] * 6
    back, _ = quiet(dk.read_parquet, quiet(dk.save_parquet, out, meta=meta))
    assert tags(back["y2"]) == [".a"] * 6


def test_recipe_aggregation():
    df, _ = survey()
    out = df.groupby(df["age"] > 20)["x"].agg(["mean", "count"])
    assert out["mean"].tolist() == [2.0, 4.0] and out["count"].tolist() == [2, 1]


def test_the_stata_sort_and_the_sort_check():
    df, meta = survey()
    assert dk.read_parquet(quiet(dk.save_parquet, df, meta=meta))[1].sort == ["id"]
    with pytest.warns(UserWarning, match=r"meta.sort \(id\) does not describe"):
        raw = dk.save_parquet(df.iloc[::-1], meta=meta.select(["id", "s"]))
    assert dk.read_parquet(raw)[1].sort == []
    # Stata's order: values, then `.`, then .a to .z; a DtaArray sorts so.
    meta.sort = ["x"]
    stata = df.sort_values("x", kind="stable")
    assert tags(stata["x"]) == [None, None, None, None, ".a", ".d"] and stata["x"].isna().tolist()[3]
    assert dk.read_parquet(quiet(dk.save_parquet, stata, meta=meta))[1].sort == ["x"]
    with pytest.warns(UserWarning, match="does not describe"):
        dk.save_parquet(df, meta=meta)
    # A sort column not in the frame cuts the sort there.
    meta.sort = ["x", "gone", "id"]
    assert dk.read_parquet(quiet(dk.save_parquet, stata, meta=meta))[1].sort == ["x"]


def test_a_nan_is_dot():
    # pandas' nullable types do not keep a NaN apart from a null, and .dta
    # has no NaN: a NaN is written and read as `.`.
    df = pd.DataFrame({"x": [1.0, float("nan"), None]})
    back, _ = quiet(dk.read_parquet, dk.save_parquet(df))
    assert back["x"].dtype == "dta[double]" and back["x"].array.codes.tolist() == [0, 1, 1]


# ---------------------------------------------------------------- Meta

def test_meta_equality_copy_and_labels():
    _, meta = survey()
    other = meta.copy()
    assert other == meta and other is not meta
    other.label = "Other"
    assert other != meta
    assert meta.labels("z") == {1: "Yes", 2: "No", 3: "Yes", ".d": "Don't know"}
    meta.labels("z")[4] = "Four"  # the set itself
    assert meta.value_labels["yn"][4] == "Four"
    assert meta.labels("x") == {}
    with pytest.raises(KeyError, match='"nope"'):
        meta.labels("nope")
    assert dk.Meta() == dk.Meta() and dk.Meta().notes is not dk.Meta().notes
    assert not hasattr(dk.Meta(), "_storage")


def test_meta_compares_and_copies_pandas_values():
    a = dk.Meta(characteristics={"x": {"s": pd.Series([1, 2])}})
    b = a.copy()
    assert a == b and b.characteristics["x"]["s"] is not a.characteristics["x"]["s"]
    b.characteristics["x"]["s"].iloc[0] = 5
    assert a != b and a.characteristics["x"]["s"].iloc[0] == 1
    assert dk.Meta(characteristics={"x": {"s": pd.Series([1, 2], dtype="int8")}}) != a
    f = dk.Meta(characteristics={"x": {"f": pd.DataFrame({"a": [1]})}})
    assert f == f.copy()


def test_meta_rename():
    df, meta = survey()
    renamed = meta.rename({"y": "count", "id": "key"})
    assert list(renamed.columns)[:4] == ["key", "age", "x", "count"]
    assert renamed.sort == ["key"]
    assert list(meta.columns)[0] == "id"  # a new Meta
    raw = quiet(dk.save_parquet, df.rename(columns={"y": "count", "id": "key"}), meta=renamed)
    info = dk.read_parquet_info(raw).columns
    assert info.loc[info["name"] == "count", "storage"].tolist() == ["int"]
    with pytest.raises(KeyError):
        meta.rename({"nope": "a"})
    with pytest.raises(ValueError, match='already has a column "y"'):
        meta.rename({"x": "y"})
    assert meta.rename({"x": "y", "y": "x"}).columns["y"].label == "Income"


def test_meta_select():
    _, meta = survey()
    meta.characteristics = {"_dta": {"a": "1"}, "x": {"b": "2"}, "s": {"c": "3"}}
    meta.sort = ["id", "s", "x"]
    part = meta.select(["s", "id"])
    assert list(part.columns) == ["s", "id"]
    assert part.characteristics == {"_dta": {"a": "1"}, "s": {"c": "3"}}
    assert part.sort == ["id", "s"]  # up to x, not selected
    assert part.value_labels == meta.value_labels
    assert meta.select(["x", "id"]).sort == ["id"]
    with pytest.raises(KeyError):
        meta.select(["nope"])


def test_read_parquet_info_meta_equals_a_read():
    df, meta = survey()
    raw = dk.save_parquet(df, meta=meta)
    _, read = dk.read_parquet(raw)
    assert dk.read_parquet_info(raw).meta == read


# ---------------------------------------------------------------- factors

def factors_file():
    df = pd.DataFrame({
        "z": lettered([1, 2, 3, None, 5, 2], [None, None, None, ".d", None, None], storage="byte"),
        "w": [0.5, 2.0, 100000.0, None, 1e-4, 3.0],
        "v": pd.Series([1, 2, 3, None, 5, 2], dtype="dta[byte]"),
    })
    meta = dk.Meta(columns={"z": dk.Column(value_labels="yn"), "w": dk.Column(value_labels="w"),
                            "v": dk.Column(value_labels="yn")},
                   value_labels={"yn": {1: "Yes", 2: "No", 3: "Yes", ".d": "Don't know"}, "w": {3: "three"}}, rows=6)
    return dk.save_parquet(df, meta=meta)


def categories(s):
    return list(s.dtype.categories)


def values(s):
    return [None if v != v else v for v in s.tolist()]


def test_factors_as_r_makes_them():
    with pytest.warns(UserWarning, match=r'\.a to \.z in "z" are NaN in its category; read with factors=False'):
        df, meta = dk.read_parquet(factors_file(), factors=True)
    # Levels: the values and the labelled codes in order; "Yes" twice is
    # one level; missing codes' labels are not levels.
    assert categories(df["v"]) == ["Yes", "No", "5"]
    assert values(df["v"]) == ["Yes", "No", "Yes", None, "5", "No"]
    assert categories(df["w"]) == ["1e-04", "0.5", "2", "three", "1e+05"]
    assert meta.columns["v"].value_labels == "yn" and meta.labels("v")[1] == "Yes"
    # A column holding letters is a category too, its letters NaN, as in R.
    assert categories(df["z"]) == ["Yes", "No", "5"] and values(df["z"]) == ["Yes", "No", "Yes", None, "5", "No"]
    # letters=False: the same, without the warning.
    df2, _ = quiet(dk.read_parquet, factors_file(), factors=True, letters=False)
    pd.testing.assert_frame_equal(df2, df)
    # factors=False keeps them.
    df, _ = dk.read_parquet(factors_file())
    assert df["z"].dtype == "dta[byte]" and tags(df["z"]) == [None, None, None, ".d", None, None]


def test_what_saving_factors_writes(tmp_path):
    df, meta = dk.read_parquet(factors_file(), factors=True, columns=["v"])
    # Parquet: a categorical of the levels, as text.
    back, bm = dk.read_parquet(quiet(dk.save_parquet, df, meta=meta))
    assert categories(back["v"]) == ["Yes", "No", "5"] and bm.columns["v"].value_labels is None
    assert "yn" in bm.value_labels
    # .dta: as Stata's encode makes it, codes 1 to k, the letter labels of
    # "yn" kept, marked so that it reads back a category.
    dk.save_dta(df, tmp_path / "f.dta", meta=meta)
    back, bm = dk.read_dta(tmp_path / "f.dta")
    assert categories(back["v"]) == ["Yes", "No", "5"] and values(back["v"]) == values(df["v"])
    assert bm.value_labels[bm.columns["v"].value_labels] == {1: "Yes", 2: "No", 3: "5", ".d": "Don't know"}


def test_r_number():
    from datakit._frame import r_number
    cases = {0.5: "0.5", 2.0: "2", 100000.0: "1e+05", 123456.0: "123456", 1e-4: "1e-04", 0.1: "0.1",
             -1.25: "-1.25", 1 / 3: "0.333333333333333", 1e15: "1e+15", 123456789012: "123456789012",
             0.0: "0", 2.0**1000: "1.07150860718627e+301", 1e-300: "1e-300"}
    for v, want in cases.items():
        assert r_number(v) == want, v


def test_dtaarray_is_what_reads_give():
    df, _ = survey()
    assert isinstance(df["x"].array, DtaArray)
