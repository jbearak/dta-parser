"""`.a` to `.z` through polars operations, Meta's methods and `factors`
(plan 0019, "`.a` to `.z`", "`Meta`", "`save_parquet`" and
"`factors=True`")."""

import datetime as dt
import warnings

import polars as pl
import pytest
from polars.testing import assert_frame_equal

import datakit as dk


def L(*v, name=""):
    return pl.Series(name, list(v), dtype=dk.LETTERS)


def survey():
    """A file with letters in x and y, a labelled column and a sort."""
    df = pl.DataFrame({
        "id": pl.Series([1, 2, 3, 4, 5, 6], dtype=pl.Int32),
        "age": pl.Series([12, 30, 14, 45, 16, 60], dtype=pl.Int8),
        "x": [1.5, None, 2.5, None, None, 4.0],
        "y": pl.Series([10, 20, None, 40, 50, None], dtype=pl.Int16),
        "z": pl.Series([1, 2, 3, 4, 5, 6], dtype=pl.Int8),
        "s": ["a", "b", "c", "d", "e", "f"],
    })
    meta = dk.Meta(
        label="Survey", sort=["id"],
        columns={c: dk.Column() for c in df.columns},
        value_labels={"yn": {1: "Yes", 2: "No", 3: "Yes", ".d": "Don't know"}},
        missing={"x": L(None, ".d", None, ".a", None, None, name="x"), "y": L(None, None, ".z", None, None, None, name="y")},
        rows=6,
    )
    meta.columns["z"].value_labels = "yn"
    meta.columns["x"].label = "Income"
    return dk.read_parquet(dk.save_parquet(df, meta=meta))


def quiet(fn, *a, **k):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return fn(*a, **k)


# ---------------------------------------------------------------- reading

def test_letters_meta_is_the_default():
    df, meta = survey()
    assert df.columns == ["id", "age", "x", "y", "z", "s"]
    assert df["x"].null_count() == 3  # `.` and `.a` to `.z` are all null
    assert meta.missing["x"].to_list() == [None, ".d", None, ".a", None, None]
    assert meta.missing["x"].dtype == dk.LETTERS and meta.missing["x"].name == "x"
    assert meta.letters("y").to_list() == [None, None, ".z", None, None, None]
    assert meta.letters("id").to_list() == [None] * 6
    with pytest.raises(KeyError, match='"nope"'):
        meta.letters("nope")
    assert set(meta._digests) == {"x", "y"}


def test_letters_columns_gives_every_eligible_column_a_companion():
    raw = dk.save_parquet(*survey()[:1], meta=survey()[1])
    df, meta = dk.read_parquet(raw, letters="columns")
    assert df.columns == ["id", "id_letter", "age", "age_letter", "x", "x_letter", "y", "y_letter",
                          "z", "z_letter", "s"]
    assert df["x_letter"].to_list() == [None, ".d", None, ".a", None, None]
    assert df["id_letter"].dtype == dk.LETTERS and df["id_letter"].null_count() == 6
    assert meta.letter_columns == {c: c + "_letter" for c in ("id", "age", "x", "y", "z")}
    assert meta.missing == {} and meta._digests == {}
    with pytest.raises(ValueError, match='letters of column "x" are in the frame\'s column "x_letter"'):
        meta.letters("x")
    # Saved, the companions are not columns of the file.
    back, bm = quiet(dk.read_parquet, quiet(dk.save_parquet, df, meta=meta))
    assert back.columns == ["id", "age", "x", "y", "z", "s"]
    assert bm.missing["x"].to_list() == [None, ".d", None, ".a", None, None]


def test_the_same_expression_on_windows_with_and_without_letters():
    raw = dk.save_parquet(*survey()[:1], meta=survey()[1])
    expr = pl.when(pl.col("x_letter") == ".d").then(pl.lit("dk")).otherwise(pl.lit("other")).alias("why")
    for skip, n in [(0, 6), (4, 2)]:
        df, _ = dk.read_parquet(raw, letters="columns", skip=skip, n_max=n)
        assert df.with_columns(expr).height == n
    df, _ = dk.read_parquet(raw, letters="columns", skip=4, n_max=2)
    assert df["x_letter"].to_list() == [None, None]


def test_partial_companions():
    df0, meta0 = survey()
    raw = dk.save_parquet(df0, meta=meta0)
    df, meta = dk.read_parquet(raw, letters=["x"])
    assert df.columns == ["id", "age", "x", "x_letter", "y", "z", "s"]
    assert list(meta.missing) == ["y"]  # y's letters stay in meta
    with pytest.raises(ValueError, match='"x_letter"'):
        meta.letters("x")
    with pytest.raises(ValueError, match='"s".*cannot hold'):
        dk.read_parquet(raw, letters=["s"])
    with pytest.raises(KeyError, match='"nope"'):
        dk.read_parquet(raw, letters=["nope"])
    back, bm = quiet(dk.read_parquet, quiet(dk.save_parquet, df, meta=meta))
    assert bm.missing["x"].equals(meta0.missing["x"]) and bm.missing["y"].equals(meta0.missing["y"])


def test_a_file_column_named_like_a_companion():
    df = pl.DataFrame({"x": [1.0, None], "x_letter": ["a", "b"]})
    raw = dk.save_parquet(df, meta=dk.Meta(missing={"x": L(None, ".a", name="x")}, rows=2))
    with pytest.raises(ValueError, match='"x_letter", which is already a column; pass another letter_suffix'):
        dk.read_parquet(raw, letters="columns")
    got, _ = dk.read_parquet(raw, letters="columns", letter_suffix="_why")
    assert got.columns == ["x", "x_why", "x_letter"]


def test_letters_none_keeps_none():
    df, meta = dk.read_parquet(dk.save_parquet(*survey()[:1], meta=survey()[1]), letters=None)
    assert meta.missing == {} and meta.letter_columns == {} and df["x"].null_count() == 3


def test_a_column_with_letters_read_with_and_without_columns():
    raw = dk.save_parquet(*survey()[:1], meta=survey()[1])
    _, whole = dk.read_parquet(raw)
    part, pm = dk.read_parquet(raw, columns=["x"])
    assert pm.missing["x"].equals(whole.missing["x"])
    assert pm._digests["x"] == whole._digests["x"]


# ---------------------------------------------------------------- recipes

def test_recipe_set_a_letter():
    df, meta = survey()
    df = dk.letters_to_columns(df, meta)
    cond = pl.col("age") < 15
    df = df.with_columns(
        pl.when(cond).then(None).otherwise(pl.col("x")).alias("x"),
        pl.when(cond).then(pl.lit(".d", dk.LETTERS)).otherwise(pl.col("x_letter")).alias("x_letter"),
    )
    back, bm = quiet(dk.read_parquet, quiet(dk.save_parquet, df, meta=meta))
    assert bm.missing["x"].to_list() == [".d", ".d", ".d", ".a", None, None]


def test_recipe_replace_a_letter_with_a_value():
    df, meta = survey()
    df = dk.letters_to_columns(df, meta, ["x"])
    cond = pl.col("x_letter") == ".a"
    df = df.with_columns(
        pl.when(cond).then(0.0).otherwise(pl.col("x")).alias("x"),
        pl.when(cond).then(None).otherwise(pl.col("x_letter")).alias("x_letter"),
    )
    back, bm = dk.read_parquet(dk.save_parquet(df, meta=meta))
    assert back["x"].to_list() == [1.5, None, 2.5, 0.0, None, 4.0]
    assert bm.missing["x"].to_list() == [None, ".d", None, None, None, None]
    # Setting x without clearing x_letter is an error, never resolved silently.
    bad = df.with_columns(pl.when(pl.col("id") == 2).then(9.0).otherwise(pl.col("x")).alias("x"))
    with pytest.raises(ValueError, match='column "x": row 2 holds a value and the letter .d'):
        dk.save_parquet(bad, meta=meta)


def test_recipe_new_column():
    df, meta = survey()
    df = df.with_columns(pl.lit(None, pl.Float64).alias("n"), pl.lit(".a", dk.LETTERS).alias("n_letter"))
    meta.letter_columns["n"] = "n_letter"
    _, bm = quiet(dk.read_parquet, quiet(dk.save_parquet, df, meta=meta))
    assert bm.missing["n"].to_list() == [".a"] * 6


def test_recipe_join():
    df, meta = survey()
    df = dk.letters_to_columns(df, meta, ["x"])
    right = df.select("id", "x", "x_letter").with_columns(pl.col("id"))
    joined = df.join(right, on="id", how="left")
    assert "x_right" in joined.columns and "x_letter_right" in joined.columns
    meta.columns["x_right"] = meta.columns["x"]
    meta.letter_columns["x_right"] = "x_letter_right"
    _, bm = quiet(dk.read_parquet, quiet(dk.save_parquet, joined, meta=meta))
    assert bm.missing["x_right"].equals(bm.missing["x"].alias("x_right"))
    assert bm.columns["x_right"].label == "Income"


def test_recipe_aggregation():
    df, meta = survey()
    df = dk.letters_to_columns(df, meta, ["x"]).with_columns(k=pl.Series([1, 1, 2, 3, 3, 4]))
    out = df.group_by("k", maintain_order=True).agg(pl.col("x").mean(), pl.col("x_letter").drop_nulls().first())
    # A mean is a new value: a letter stays only where the mean is missing.
    with pytest.raises(ValueError, match="holds a value and the letter"):
        dk.save_parquet(out, meta=meta.select(["x"]))
    out = out.with_columns(pl.when(pl.col("x").is_null()).then(pl.col("x_letter")).alias("x_letter"))
    _, bm = quiet(dk.read_parquet, quiet(dk.save_parquet, out, meta=meta.select(["x"])))
    assert bm.missing["x"].to_list() == [None, None, ".a", None]


def test_filter_sort_and_concat_carry_companions():
    df, meta = survey()
    df = dk.letters_to_columns(df, meta)
    out = pl.concat([df.filter(pl.col("x_letter").is_not_null()), df.reverse()])
    kept = meta.select(out.columns)
    kept.sort = []  # the rows are no longer in id's order
    _, bm = quiet(dk.read_parquet, quiet(dk.save_parquet, out, meta=kept))
    assert bm.missing["x"].to_list() == [".d", ".a", None, None, ".a", None, ".d", None]


def test_the_traps():
    df, meta = survey()
    df = dk.letters_to_columns(df, meta, ["x"])
    # != is null on rows without a letter, so a filter drops every valued row.
    assert df.filter(pl.col("x_letter") != ".d").height == 1
    assert df.filter(pl.col("x_letter").ne_missing(".d")).height == 5
    # polars sorts nulls first; Stata sorts missing values last: values,
    # then `.`, then `.a` to `.z`.
    stata = df.sort(["x", "x_letter"], nulls_last=[True, False], maintain_order=True)
    assert stata["x"].to_list()[:3] == [1.5, 2.5, 4.0]
    assert stata["x_letter"].to_list()[3:] == [None, ".a", ".d"]


# ---------------------------------------------------------------- the save checks

def test_the_digest_catches_a_sort_and_a_reverse():
    df, meta = survey()
    for changed in (df.sort("x", nulls_last=True), df.reverse(), df.with_columns(pl.col("x").fill_null(0)),
                    df.filter(pl.col("id") > 0).with_columns(pl.col("x") * 2)):
        with pytest.raises(ValueError, match=r'column "x" has changed since it was read.*letters_to_columns.*'
                                             r'meta.missing.pop\("x"\)'):
            dk.save_parquet(changed, meta=meta)
    with pytest.raises(ValueError, match='have 6 rows, but the frame has 2'):
        dk.save_parquet(df.head(2), meta=meta)
    with pytest.raises(ValueError, match="has changed since it was read"):
        dk.letters_to_columns(df.reverse(), meta)


def test_what_the_digest_cannot_see():
    # Rows exchanged that hold equal values: an all-null column sorted.
    df = pl.DataFrame({"k": [2, 1], "x": pl.Series([None, None], dtype=pl.Float64)})
    meta = dk.Meta(missing={"x": L(".a", ".b", name="x")}, rows=2)
    df, meta = dk.read_parquet(dk.save_parquet(df, meta=meta))
    moved = df.sort("k")
    _, bm = dk.read_parquet(dk.save_parquet(moved, meta=meta))  # passes, and is wrong
    assert bm.missing["x"].to_list() == [".a", ".b"]


def test_the_digest_across_casts():
    df, meta = survey()
    digest = dk._native.arrow_digest
    assert digest(df["y"].cast(pl.Int64)) == meta._digests["y"]  # Int64 cannot hold letters, but digests alike
    for ok in (pl.col("y").cast(pl.Int32), pl.col("y").cast(pl.Float64), pl.col("x").cast(pl.Float32)):
        dk.save_parquet(df.with_columns(ok), meta=meta.copy())
    assert digest(pl.Series([0.5, None], dtype=pl.Float32)) == digest(pl.Series([0.5, None], dtype=pl.Float64))
    big = pl.DataFrame({"n": pl.Series([2**53 + 1, None], dtype=pl.Int64)})
    meta = dk.Meta(missing={"n": L(None, ".a", name="n")}, rows=2)
    meta._digests["n"] = dk._native.arrow_digest(big["n"])
    with pytest.raises(ValueError, match='column "n" has changed'):
        dk.save_parquet(big.with_columns(pl.col("n").cast(pl.Float64)), meta=meta)
    f = pl.DataFrame({"f": [0.1, None]})
    meta = dk.Meta(missing={"f": L(None, ".a", name="f")}, rows=2, _digests={"f": dk._native.arrow_digest(f["f"])})
    with pytest.raises(ValueError, match='column "f" has changed'):
        dk.save_parquet(f.with_columns(pl.col("f").cast(pl.Float32)), meta=meta)


def test_each_companion_check():
    df, meta = survey()
    df = dk.letters_to_columns(df, meta, ["x"])
    # A companion dropped while its column is kept.
    with pytest.raises(ValueError, match='"x" is in the frame but its letters\' column "x_letter" is not'):
        dk.save_parquet(df.drop("x_letter"), meta=meta)
    quiet(dk.save_parquet, df.drop("x_letter"), meta=meta, missing_letters=False)
    # A stale pair: the column dropped, the companion kept.
    with pytest.raises(ValueError, match='"x_letter" holds the letters of column "x", which is not in the frame'):
        dk.save_parquet(df.drop("x"), meta=meta)
    # A companion that is not LETTERS.
    with pytest.raises(TypeError, match='"x_letter", the letters of "x", is Int32'):
        dk.save_parquet(df.with_columns(pl.lit(1).alias("x_letter")), meta=meta)
    # String holding only .a to .z is fine; anything else is an error.
    quiet(dk.save_parquet, df.with_columns(pl.col("x_letter").cast(pl.String)), meta=meta)
    with pytest.raises(ValueError, match='"x" hold "d" in row 2'):
        dk.save_parquet(df.with_columns(pl.col("x_letter").cast(pl.String).str.strip_chars(".")), meta=meta)
    # Letters in both places.
    both = meta.copy()
    both.missing["x"] = L(*([None] * 6), name="x")
    with pytest.raises(ValueError, match='letters both in column "x_letter" and in meta.missing'):
        dk.save_parquet(df, meta=both)
    # A companion paired twice.
    twice = meta.copy()
    twice.letter_columns["s"] = "x_letter"
    with pytest.raises(ValueError, match='"x_letter" is the companion of both "x" and "s"'):
        dk.save_parquet(df, meta=twice)


def test_a_stray_companion_is_written_with_a_warning():
    df, meta = survey()
    df = dk.letters_to_columns(df, meta, ["x"])
    with pytest.warns(UserWarning, match='"x_letter" is a column of datakit.LETTERS that no pair'):
        raw = dk.save_parquet(df, meta=None)
    back, _ = dk.read_parquet(raw)
    assert back["x_letter"].dtype == dk.LETTERS


def test_an_enum_with_letters_is_written_as_level_numbers():
    df, meta = survey()
    df, meta = dk.read_parquet(dk.save_parquet(df, meta=meta), factors=True, columns=["z"])
    meta.missing["z"] = L(None, None, None, None, None, ".d", name="z")
    df = df.with_columns(pl.when(pl.int_range(6) == 5).then(None).otherwise(pl.col("z")).alias("z"))
    meta._digests.clear()
    back, bm = dk.read_parquet(quiet(dk.save_parquet, df, meta=meta))
    assert back["z"].dtype == df["z"].dtype and back["z"].to_list() == df["z"].to_list()
    assert bm.missing["z"].to_list() == [None, None, None, None, None, ".d"]
    # "yn" does not label 1 to 5 with the levels: a set named after the
    # column is made, and "yn" kept as it was.
    assert bm.columns["z"].value_labels == "z" and bm.value_labels["yn"] == meta.value_labels["yn"]
    assert bm.value_labels["z"] == dict(enumerate(df["z"].dtype.categories.to_list(), start=1))


def test_types_that_cannot_hold_letters():
    for t in (pl.Int64, pl.UInt8, pl.UInt16, pl.UInt32, pl.UInt64, pl.Boolean, pl.String):
        df = pl.DataFrame({"v": pl.Series([None, None], dtype=t)})
        with pytest.raises(ValueError, match='"v" is .* and has .a to .z'):
            dk.save_parquet(df, meta=dk.Meta(missing={"v": L(None, ".a", name="v")}, rows=2))


# ---------------------------------------------------------------- sort

def test_the_sort_check():
    df, meta = survey()
    assert dk.read_parquet(quiet(dk.save_parquet, df, meta=meta))[1].sort == ["id"]
    with pytest.warns(UserWarning, match=r"meta.sort \(id\) does not describe"):
        raw = dk.save_parquet(df.reverse(), meta=meta.select(["id", "s"]))
    assert dk.read_parquet(raw)[1].sort == []
    # The guide's recipe passes; polars' default (nulls first) does not.
    df = dk.letters_to_columns(df, meta)
    meta.sort = ["x"]
    stata = df.sort(["x", "x_letter"], nulls_last=[True, False], maintain_order=True)
    assert dk.read_parquet(quiet(dk.save_parquet, stata, meta=meta))[1].sort == ["x"]
    with pytest.warns(UserWarning, match="does not describe"):
        dk.save_parquet(df.sort("x"), meta=meta)
    # A sort column not in the frame cuts the sort there.
    meta.sort = ["x", "gone", "id"]
    assert dk.read_parquet(quiet(dk.save_parquet, stata, meta=meta))[1].sort == ["x"]


# ---------------------------------------------------------------- letters_to_columns

def test_letters_to_columns():
    df, meta = survey()
    out = dk.letters_to_columns(df, meta, ["x"])
    assert out.columns == ["id", "age", "x", "x_letter", "y", "z", "s"]
    assert meta.letter_columns == {"x": "x_letter"} and list(meta.missing) == ["y"] and list(meta._digests) == ["y"]
    again = dk.letters_to_columns(out, meta, ["x"])  # a column already paired is left as it is
    assert again.columns == out.columns
    with pytest.raises(ValueError, match='"x_letter", which is already a column; pass another suffix'):
        dk.letters_to_columns(out.drop("x_letter").with_columns(pl.lit(1).alias("x_letter")),
                              dk.read_parquet(dk.save_parquet(*survey()[:1], meta=survey()[1]))[1], ["x"])
    with pytest.raises(ValueError, match='"s" is String'):
        dk.letters_to_columns(df, meta, ["s"])
    with pytest.raises(KeyError, match='"nope"'):
        dk.letters_to_columns(df, meta, ["nope"])
    all_, m2 = survey()
    all_ = dk.letters_to_columns(all_, m2)
    assert m2.missing == {} and set(m2.letter_columns) == {"id", "age", "x", "y", "z"}


# ---------------------------------------------------------------- Meta

def test_meta_equality_copy_and_labels():
    _, meta = survey()
    other = meta.copy()
    assert other == meta and other is not meta
    assert other.missing["x"] is not meta.missing["x"]
    other.missing["x"] = L(*([None] * 6), name="x")
    assert other != meta
    assert meta.labels("z") == {1: "Yes", 2: "No", 3: "Yes", ".d": "Don't know"}
    meta.labels("z")[4] = "Four"  # the set itself
    assert meta.value_labels["yn"][4] == "Four"
    assert meta.labels("x") == {}
    with pytest.raises(KeyError, match='"nope"'):
        meta.labels("nope")
    assert dk.Meta() == dk.Meta() and dk.Meta().notes is not dk.Meta().notes
    m = dk.Meta(_digests={"x": 1})
    assert m == dk.Meta()  # digests are not compared


def test_meta_rename():
    df, meta = survey()
    renamed = meta.rename({"x": "income", "id": "key"})
    assert list(renamed.columns)[:3] == ["key", "age", "income"]
    assert renamed.missing["income"].name == "income"
    assert renamed._digests["income"] == meta._digests["x"]
    assert renamed.sort == ["key"]
    assert list(meta.columns)[0] == "id"  # a new Meta
    _, bm = quiet(dk.read_parquet, quiet(dk.save_parquet, df.rename({"x": "income", "id": "key"}), meta=renamed))
    assert bm.missing["income"].equals(meta.missing["x"].alias("income"))
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
    assert list(part.columns) == ["s", "id"] and part.missing == {}
    assert part.characteristics == {"_dta": {"a": "1"}, "s": {"c": "3"}}
    assert part.sort == ["id", "s"]  # up to x, not selected
    assert part.value_labels == meta.value_labels
    assert meta.select(["x", "id"]).sort == ["id"]
    with pytest.raises(KeyError):
        meta.select(["nope"])


def test_read_parquet_info_meta_equals_a_read_but_for_missing():
    df, meta = survey()
    raw = dk.save_parquet(df, meta=meta)
    _, read = dk.read_parquet(raw)
    read.missing = {}
    assert dk.read_parquet_info(raw).meta == read


# ---------------------------------------------------------------- factors

def factors_file():
    df = pl.DataFrame({
        "z": pl.Series([1, 2, 3, None, 5, 2], dtype=pl.Int8),
        "w": [0.5, 2.0, 100000.0, None, 1e-4, 3.0],
    })
    meta = dk.Meta(columns={"z": dk.Column(value_labels="yn"), "w": dk.Column(value_labels="w")},
                   value_labels={"yn": {1: "Yes", 2: "No", 3: "Yes", ".d": "Don't know"}, "w": {3: "three"}},
                   missing={"z": L(None, None, None, ".d", None, None, name="z")}, rows=6)
    return dk.save_parquet(df, meta=meta)


def test_factors_as_r_makes_them():
    df, meta = dk.read_parquet(factors_file(), factors=True)
    # Levels: the values and the labelled codes in order; "Yes" twice is
    # one level; missing codes' labels are not levels.
    assert df["z"].dtype == pl.Enum(["Yes", "No", "5"])
    assert df["z"].to_list() == ["Yes", "No", "Yes", None, "5", "No"]
    assert df["w"].dtype == pl.Enum(["1e-04", "0.5", "2", "three", "1e+05"])
    assert meta.columns["z"].value_labels == "yn" and meta.labels("z")[1] == "Yes"
    assert meta.missing["z"].to_list() == [None, None, None, ".d", None, None]  # not lost
    df, meta = dk.read_parquet(factors_file(), factors=True, letters="columns")
    assert df["z_letter"].to_list() == [None, None, None, ".d", None, None]


def test_what_saving_factors_writes(tmp_path):
    df, meta = dk.read_parquet(factors_file(), factors=True, letters="columns", columns=["z"])
    # Parquet: with letters, level numbers from 1 with a set of the levels
    # ("yn" does not fit them, so it is made under the column's name).
    back, bm = dk.read_parquet(quiet(dk.save_parquet, df, meta=meta))
    assert back["z"].dtype == pl.Enum(["Yes", "No", "5"]) and back["z"].to_list() == df["z"].to_list()
    assert bm.columns["z"].value_labels == "z" and bm.value_labels["z"] == {1: "Yes", 2: "No", 3: "5"}
    assert bm.missing["z"].to_list() == [None, None, None, ".d", None, None]
    assert "yn" in bm.value_labels
    # Without them, a categorical of the levels, as text.
    back, bm = dk.read_parquet(dk.save_parquet(df, meta=meta, missing_letters=False))
    assert back["z"].dtype == pl.Enum(["Yes", "No", "5"]) and bm.columns["z"].value_labels is None
    assert "yn" in bm.value_labels
    # .dta: as Stata's encode makes it, codes 1 to k, letters and the
    # letter labels of "yn" kept, marked so that it reads back an Enum.
    dk.save_dta(df, tmp_path / "f.dta", meta=meta)
    back, bm = dk.read_dta(tmp_path / "f.dta")
    assert back["z"].dtype == pl.Enum(["Yes", "No", "5"]) and back["z"].to_list() == df["z"].to_list()
    assert bm.value_labels[bm.columns["z"].value_labels] == {1: "Yes", 2: "No", 3: "5", ".d": "Don't know"}
    assert bm.missing["z"].to_list() == [None, None, None, ".d", None, None]
    df, meta = dk.read_parquet(factors_file(), factors=True, columns=["z"])
    dk.save_dta(df, tmp_path / "g.dta", meta=meta)
    assert dk.read_dta(tmp_path / "g.dta")[1].missing["z"].to_list() == [None, None, None, ".d", None, None]


def test_r_number():
    from datakit._frame import r_number
    cases = {0.5: "0.5", 2.0: "2", 100000.0: "1e+05", 123456.0: "123456", 1e-4: "1e-04", 0.1: "0.1",
             -1.25: "-1.25", 1 / 3: "0.333333333333333", 1e15: "1e+15", 123456789012: "123456789012",
             0.0: "0", 2.0**1000: "1.07150860718627e+301", 1e-300: "1e-300"}
    for v, want in cases.items():
        assert r_number(v) == want, v


# ---------------------------------------------------------------- dates as letters

def test_dates_and_timestamps_hold_letters():
    df = pl.DataFrame({"d": [dt.date(2024, 1, 1), None, None],
                       "t": pl.Series([dt.datetime(2024, 1, 1, 0, 0, 0, 1), None, None], dtype=pl.Datetime("us", "UTC"))})
    meta = dk.Meta(missing={"d": L(None, ".a", None, name="d"), "t": L(None, None, ".z", name="t")}, rows=3)
    back, bm = quiet(dk.read_parquet, dk.save_parquet(df, meta=meta))
    assert_frame_equal(back, df)
    assert bm.missing["d"].to_list() == [None, ".a", None] and bm.missing["t"].to_list() == [None, None, ".z"]
