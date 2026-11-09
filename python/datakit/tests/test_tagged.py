"""`.a` to `.z` as tagged NaNs in the frame (ADR 0036): tagged_na,
na_tag and is_tagged_na; letters through polars operations and the
guide's recipes; Meta's methods; and `factors`."""

import struct
import warnings

import polars as pl
import pytest

import datakit as dk
from conftest import assert_same, tagged, tags


def survey():
    """A file with letters in x (double) and y (int), a labelled column
    and a sort."""
    df = pl.DataFrame({
        "id": pl.Series([1, 2, 3, 4, 5, 6], dtype=pl.Int32),
        "age": pl.Series([12, 30, 14, 45, 16, 60], dtype=pl.Int8),
        "x": tagged([1.5, None, 2.5, None, None, 4.0], [None, ".d", None, ".a", None, None]),
        "y": tagged([10, 20, None, 40, 50, None], [None, None, ".z", None, None, None]),
        "z": pl.Series([1, 2, 3, 4, 5, 6], dtype=pl.Int8),
        "s": ["a", "b", "c", "d", "e", "f"],
    })
    meta = dk.Meta(
        label="Survey", sort=["id"],
        columns={c: dk.Column() for c in df.columns},
        value_labels={"yn": {1: "Yes", 2: "No", 3: "Yes", ".d": "Don't know"}},
        rows=6,
    )
    meta._storage = {"y": pl.Int16}
    meta.columns["z"].value_labels = "yn"
    meta.columns["x"].label = "Income"
    return dk.read_parquet(dk.save_parquet(df, meta=meta))


def quiet(fn, *a, **k):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return fn(*a, **k)


def bits(v):
    return struct.unpack("<Q", struct.pack("<d", v))[0]


# ---------------------------------------------------------------- the functions

def test_tagged_na_is_rs_bits():
    # R's NA_real_ (low word 1954) with the letter in byte 4, as haven's
    # tagged_na() and the Parquet files hold it.
    assert bits(dk.tagged_na(".a")) == 0x7FF0_0061_0000_07A2
    assert bits(dk.tagged_na("z")) == 0x7FF0_007A_0000_07A2
    for bad in ("", ".", "A", ".A", "ab", "..a", "1"):
        with pytest.raises(ValueError, match='a letter is ".a" to ".z"'):
            dk.tagged_na(bad)
    with pytest.raises(TypeError):
        dk.tagged_na(1)


def test_na_tag_reads_every_letter_and_nothing_else():
    letters = [f".{chr(c)}" for c in range(ord("a"), ord("z") + 1)]
    s = tagged([None] * 26, letters)
    assert tags(s) == letters and dk.na_tag(s).dtype == dk.LETTERS
    others = pl.Series([1.0, float("nan"), None, float("inf"), struct.unpack("<d", struct.pack("<Q", 0x7FF0_0000_0000_07A2))[0],
                        struct.unpack("<d", struct.pack("<Q", 0x7FF0_0041_0000_07A2))[0],
                        struct.unpack("<d", struct.pack("<Q", 0x7FF0_0061_0000_07A3))[0]])
    assert tags(others) == [None] * 7
    # Arithmetic may quiet the NaN or flip its sign; the letter stays.
    a = tagged([None], [".q"])
    for changed in (a * 2, a + 1, -a, a / 3, (a * 2).abs()):
        assert tags(changed) == [".q"]
    # Only Float64 holds letters.
    assert tags(a.cast(pl.Float32).cast(pl.Float64)) == [None]
    assert tags(pl.Series([1, None], dtype=pl.Int8)) == [None, None]
    assert tags(pl.Series(["a"])) == [None]


def test_the_functions_take_a_name_an_expr_or_a_series():
    df = pl.DataFrame({"x": tagged([1.0, None, None], [None, ".b", None])})
    assert df.select(dk.na_tag("x"))["x"].to_list() == [None, ".b", None]
    assert df.select(dk.na_tag(pl.col("x") * 2).alias("t"))["t"].to_list() == [None, ".b", None]
    assert df.select(dk.is_tagged_na("x"))["x"].to_list() == [False, True, False]
    assert df.select(dk.is_tagged_na("x", ".b"))["x"].to_list() == [False, True, False]
    assert df.select(dk.is_tagged_na("x", "c"))["x"].to_list() == [False, False, False]
    assert dk.is_tagged_na(df["x"], "b").to_list() == [False, True, False]
    assert dk.na_tag(df["x"]).name == "x"
    with pytest.raises(TypeError):
        dk.na_tag(1.0)
    with pytest.raises(ValueError):
        dk.is_tagged_na("x", "ab")


# ---------------------------------------------------------------- reading

def test_a_read_puts_the_letters_in_the_column():
    df, meta = survey()
    assert df.columns == ["id", "age", "x", "y", "z", "s"]
    assert df.schema["x"] == pl.Float64 and df.schema["y"] == pl.Float64 and df.schema["age"] == pl.Int8
    assert tags(df["x"]) == [None, ".d", None, ".a", None, None]
    assert tags(df["y"]) == [None, None, ".z", None, None, None]
    assert meta._storage == {"y": pl.Int16}
    # `.` is null; the letters are NaN, which polars counts as values.
    assert df["x"].null_count() == 1 and df["x"].is_nan().sum() == 2
    assert df["x"].fill_nan(None).null_count() == 3
    assert df["x"].fill_nan(None).mean() == pytest.approx((1.5 + 2.5 + 4.0) / 3)


def test_the_same_expression_on_windows_with_and_without_letters():
    df, meta = survey()
    raw = dk.save_parquet(df, meta=meta)
    expr = pl.col("y").fill_nan(None) * 2
    with_, _ = dk.read_parquet(raw, n_max=3)
    without, _ = dk.read_parquet(raw, skip=3)
    assert with_["y"].dtype == pl.Float64 and without["y"].dtype == pl.Int16
    assert with_.select(expr)["y"].to_list() == [20.0, 40.0, None]
    assert without.select(expr)["y"].to_list() == [80, 100, None]


def test_letters_false_keeps_none():
    df, meta = survey()
    df, meta = dk.read_parquet(dk.save_parquet(df, meta=meta), letters=False)
    assert df["x"].null_count() == 3 and df["x"].is_nan().sum() == 0
    assert df["y"].dtype == pl.Int16 and meta._storage == {}


# ---------------------------------------------------------------- through polars

def test_filter_sort_join_and_concat_carry_the_letters():
    df, meta = survey()
    out = df.filter(pl.col("id") > 1).sort("id", descending=True)
    assert tags(out["x"]) == [None, None, ".a", None, ".d"]
    joined = df.join(df.select("id", pl.col("x").alias("x2")), on="id", maintain_order="left")
    assert tags(joined["x2"]) == tags(df["x"])
    assert tags(pl.concat([df, df])["x"]) == tags(df["x"]) * 2
    back, _ = quiet(dk.read_parquet, quiet(dk.save_parquet, out))
    assert tags(back["x"]) == tags(out["x"])


def test_comparisons_treat_letters_as_stata_does():
    # Stata's missing values are greater than every number; so is NaN in
    # polars. `.` is null, so a comparison is null there: use ne_missing,
    # or fill_null, to keep it.
    df, _ = survey()
    assert df.select(pl.col("x") > 3)["x"].to_list() == [False, True, False, True, None, True]
    assert df.filter(pl.col("x") != 2.5)["id"].to_list() == [1, 2, 4, 6]
    assert df.filter(pl.col("x").ne_missing(2.5))["id"].to_list() == [1, 2, 4, 5, 6]
    assert df.filter(dk.is_tagged_na("x", ".d").not_())["id"].to_list() == [1, 3, 4, 5, 6]


def test_recipe_set_a_letter():
    df, meta = survey()
    out = df.with_columns(pl.when(pl.col("age") > 40).then(dk.tagged_na(".r")).otherwise(pl.col("x")).alias("x"))
    assert tags(out["x"]) == [None, ".d", None, ".r", None, ".r"]
    # In an integer column, polars makes the result Float64, the letter kept.
    out = out.with_columns(pl.when(pl.col("age") > 40).then(dk.tagged_na(".r")).otherwise(pl.col("z")).alias("z"))
    assert out["z"].dtype == pl.Float64 and tags(out["z"]) == [None, None, None, ".r", None, ".r"]
    back, _ = quiet(dk.read_parquet, quiet(dk.save_parquet, out, meta=meta))
    assert_same(back, out)


def test_recipe_replace_a_letter_with_a_value():
    df, meta = survey()
    out = df.with_columns(pl.when(dk.is_tagged_na("x", ".d")).then(0.0).otherwise(pl.col("x")).alias("x"))
    assert tags(out["x"]) == [None, None, None, ".a", None, None] and out["x"][1] == 0.0
    # fill_nan(None) makes every letter `.`.
    assert out["x"].fill_nan(None).null_count() == 2


def test_recipe_new_column():
    df, meta = survey()
    out = df.with_columns(y2=pl.lit(dk.tagged_na(".a")))
    assert out["y2"].dtype == pl.Float64 and tags(out["y2"]) == [".a"] * 6
    back, _ = quiet(dk.read_parquet, quiet(dk.save_parquet, out, meta=meta))
    assert tags(back["y2"]) == [".a"] * 6


def test_recipe_aggregation():
    df, _ = survey()
    out = df.group_by(pl.col("age") > 20, maintain_order=True).agg(
        pl.col("x").fill_nan(None).mean().alias("mean"), pl.col("x").fill_nan(None).count().alias("n"))
    assert out["mean"].to_list() == [2.0, 4.0] and out["n"].to_list() == [2, 1]


def test_the_stata_sort_and_the_sort_check():
    df, meta = survey()
    assert dk.read_parquet(quiet(dk.save_parquet, df, meta=meta))[1].sort == ["id"]
    with pytest.warns(UserWarning, match=r"meta.sort \(id\) does not describe"):
        raw = dk.save_parquet(df.reverse(), meta=meta.select(["id", "s"]))
    assert dk.read_parquet(raw)[1].sort == []
    # Stata's order: values, then `.`, then .a to .z.
    meta.sort = ["x"]
    stata = df.sort(pl.col("x").fill_nan(None), dk.na_tag("x"), nulls_last=[True, False], maintain_order=True)
    assert tags(stata["x"]) == [None, None, None, None, ".a", ".d"] and stata["x"][3] is None
    assert dk.read_parquet(quiet(dk.save_parquet, stata, meta=meta))[1].sort == ["x"]
    with pytest.warns(UserWarning, match="does not describe"):
        dk.save_parquet(df.sort("x"), meta=meta)
    # A sort column not in the frame cuts the sort there.
    meta.sort = ["x", "gone", "id"]
    assert dk.read_parquet(quiet(dk.save_parquet, stata, meta=meta))[1].sort == ["x"]


def test_a_nan_that_is_no_letter_is_a_value():
    df = pl.DataFrame({"x": [1.0, float("nan"), None]})
    back, _ = quiet(dk.read_parquet, dk.save_parquet(df))
    assert back["x"].is_nan().to_list() == [False, True, None] and tags(back["x"]) == [None, None, None]


# ---------------------------------------------------------------- Meta

def test_meta_equality_copy_and_labels():
    _, meta = survey()
    other = meta.copy()
    assert other == meta and other is not meta
    assert other._storage == meta._storage and other._storage is not meta._storage
    other.label = "Other"
    assert other != meta
    assert meta.labels("z") == {1: "Yes", 2: "No", 3: "Yes", ".d": "Don't know"}
    meta.labels("z")[4] = "Four"  # the set itself
    assert meta.value_labels["yn"][4] == "Four"
    assert meta.labels("x") == {}
    with pytest.raises(KeyError, match='"nope"'):
        meta.labels("nope")
    assert dk.Meta() == dk.Meta() and dk.Meta().notes is not dk.Meta().notes
    m = dk.Meta(_storage={"x": pl.Int8})
    assert m == dk.Meta()  # storage types are not compared


def test_meta_rename():
    df, meta = survey()
    renamed = meta.rename({"y": "count", "id": "key"})
    assert list(renamed.columns)[:4] == ["key", "age", "x", "count"]
    assert renamed._storage == {"count": pl.Int16}
    assert renamed.sort == ["key"]
    assert list(meta.columns)[0] == "id"  # a new Meta
    raw = quiet(dk.save_parquet, df.rename({"y": "count", "id": "key"}), meta=renamed)
    assert dk.read_parquet_info(raw).columns.filter(pl.col("name") == "count")["storage"].to_list() == ["int"]
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
    assert list(part.columns) == ["s", "id"] and part._storage == {}
    assert part.characteristics == {"_dta": {"a": "1"}, "s": {"c": "3"}}
    assert part.sort == ["id", "s"]  # up to x, not selected
    assert part.value_labels == meta.value_labels
    assert meta.select(["x", "id"]).sort == ["id"]
    assert meta.select(["y"])._storage == {"y": pl.Int16}
    with pytest.raises(KeyError):
        meta.select(["nope"])


def test_read_parquet_info_meta_equals_a_read():
    df, meta = survey()
    raw = dk.save_parquet(df, meta=meta)
    _, read = dk.read_parquet(raw)
    assert dk.read_parquet_info(raw).meta == read


# ---------------------------------------------------------------- factors

def factors_file():
    df = pl.DataFrame({
        "z": tagged([1, 2, 3, None, 5, 2], [None, None, None, ".d", None, None]),
        "w": [0.5, 2.0, 100000.0, None, 1e-4, 3.0],
        "v": pl.Series([1, 2, 3, None, 5, 2], dtype=pl.Int8),
    })
    meta = dk.Meta(columns={"z": dk.Column(value_labels="yn"), "w": dk.Column(value_labels="w"),
                            "v": dk.Column(value_labels="yn")},
                   value_labels={"yn": {1: "Yes", 2: "No", 3: "Yes", ".d": "Don't know"}, "w": {3: "three"}}, rows=6)
    meta._storage = {"z": pl.Int8}
    return dk.save_parquet(df, meta=meta)


def test_factors_as_r_makes_them():
    with pytest.warns(UserWarning, match=r'\.a to \.z in "z" are nulls in its Enum; read with factors=False'):
        df, meta = dk.read_parquet(factors_file(), factors=True)
    # Levels: the values and the labelled codes in order; "Yes" twice is
    # one level; missing codes' labels are not levels.
    assert df["v"].dtype == pl.Enum(["Yes", "No", "5"])
    assert df["v"].to_list() == ["Yes", "No", "Yes", None, "5", "No"]
    assert df["w"].dtype == pl.Enum(["1e-04", "0.5", "2", "three", "1e+05"])
    assert meta.columns["v"].value_labels == "yn" and meta.labels("v")[1] == "Yes"
    # A column holding letters is an Enum too, its letters nulls, as in R.
    assert df["z"].dtype == pl.Enum(["Yes", "No", "5"]) and df["z"].to_list() == ["Yes", "No", "Yes", None, "5", "No"]
    # letters=False: the same, without the warning.
    df2, _ = quiet(dk.read_parquet, factors_file(), factors=True, letters=False)
    assert df2.equals(df)
    # factors=False keeps them.
    df, _ = dk.read_parquet(factors_file())
    assert df["z"].dtype == pl.Float64 and tags(df["z"]) == [None, None, None, ".d", None, None]


def test_what_saving_factors_writes(tmp_path):
    df, meta = dk.read_parquet(factors_file(), factors=True, columns=["v"])
    # Parquet: a categorical of the levels, as text.
    back, bm = dk.read_parquet(quiet(dk.save_parquet, df, meta=meta))
    assert back["v"].dtype == pl.Enum(["Yes", "No", "5"]) and bm.columns["v"].value_labels is None
    assert "yn" in bm.value_labels
    # .dta: as Stata's encode makes it, codes 1 to k, the letter labels of
    # "yn" kept, marked so that it reads back an Enum.
    dk.save_dta(df, tmp_path / "f.dta", meta=meta)
    back, bm = dk.read_dta(tmp_path / "f.dta")
    assert back["v"].dtype == pl.Enum(["Yes", "No", "5"]) and back["v"].to_list() == df["v"].to_list()
    assert bm.value_labels[bm.columns["v"].value_labels] == {1: "Yes", 2: "No", 3: "5", ".d": "Don't know"}


def test_r_number():
    from datakit._frame import r_number
    cases = {0.5: "0.5", 2.0: "2", 100000.0: "1e+05", 123456.0: "123456", 1e-4: "1e-04", 0.1: "0.1",
             -1.25: "-1.25", 1 / 3: "0.333333333333333", 1e15: "1e+15", 123456789012: "123456789012",
             0.0: "0", 2.0**1000: "1.07150860718627e+301", 1e-300: "1e-300"}
    for v, want in cases.items():
        assert r_number(v) == want, v
