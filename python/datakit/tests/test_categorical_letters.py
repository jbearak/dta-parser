"""Parquet categoricals that keep `.a` to `.z` (plan 0022), as
TypeScript's saveParquet writes them: level numbers from 1 (DOUBLE,
tagged NaNs). A polars Enum cannot hold a tagged NaN (ADR 0036), so
read_parquet gives such a column as R and Julia do: Float64 level
numbers, its letters tagged NaNs, its value label set labelling the
numbers. Without letters in the rows read, it is the Enum."""

import json
import re
import struct
import warnings

import polars as pl
import pytest

import datakit as dk
from conftest import tags
from datakit import _frame
from datakit._native import native

LEVELS = ["low", "mid", "high", "unused"]


def L(*v, name="grade"):
    return pl.Series(name, list(v), dtype=dk.LETTERS)


def quiet(fn, *a, **k):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return fn(*a, **k)


def save_with_letters(df, meta, letters, compression="snappy", row_group_size=None):
    """The file the native writer makes of an Enum with letters, as
    TypeScript's saveParquet makes one."""
    out, profile = _frame.prepare(df, meta, True, "test")
    profile["missing"].update(letters)
    return native.parquet_write_arrow(out, None, profile, compression, None, row_group_size, True, "error")


def grade():
    """A file whose `grade` is an ordered Enum with an unused level, `.a`,
    `.` and `.z`, and a set with a label on `.r`."""
    df = pl.DataFrame({
        "id": pl.Series([1, 2, 3, 4, 5, 6], dtype=pl.Int32),
        "grade": pl.Series(["low", None, "high", None, None, "mid"], dtype=pl.Enum(LEVELS)),
    })
    meta = dk.Meta(
        columns={"id": dk.Column(), "grade": dk.Column(label="Grade", value_labels="grade", ordered=True)},
        value_labels={"grade": {1: "low", 2: "mid", 3: "high", 4: "unused", ".r": "Refused"}},
        rows=6,
    )
    return df, meta, save_with_letters(df, meta, {"grade": L(None, ".a", None, None, ".z", None)})


def profile(raw):
    return json.loads(dk.read_parquet_info(raw).key_value["dta"])


def test_the_file_holds_level_numbers_and_the_set():
    _, _, raw = grade()
    info = quiet(dk.read_parquet_info, raw)
    row = info.columns.filter(pl.col("name") == "grade").row(0, named=True)
    assert row["physical_type"] == "DOUBLE" and row["storage"] is None
    assert row["dtype"] == str(pl.Enum(LEVELS)) and row["value_labels"] == "grade"
    entry = profile(raw)["columns"]["grade"]
    assert entry["logical"] == "categorical" and entry["value_labels"] == "grade"
    assert entry["categorical"] == {"levels": LEVELS, "ordered": True}


def test_it_reads_as_labelled_level_numbers_with_its_letters():
    _, _, raw = grade()
    for factors in (False, True):
        back, bm = quiet(dk.read_parquet, raw, factors=factors)
        assert back["grade"].dtype == pl.Float64
        assert back["grade"].fill_nan(None).to_list() == [1.0, None, 3.0, None, None, 2.0]
        assert tags(back["grade"]) == [None, ".a", None, None, ".z", None]
        assert bm.columns["grade"] == dk.Column(label="Grade", value_labels="grade")
        assert bm.value_labels == {"grade": {1: "low", 2: "mid", 3: "high", 4: "unused", ".r": "Refused"}}
    # Written back, it is a labelled double: the same numbers, letters and set.
    again = quiet(dk.save_parquet, back, meta=bm)
    assert profile(again)["columns"]["grade"].get("logical") is None
    back2, bm2 = quiet(dk.read_parquet, again)
    assert back2["grade"].fill_nan(None).equals(back["grade"].fill_nan(None)) and tags(back2["grade"]) == tags(back["grade"])
    assert bm2.value_labels == bm.value_labels and bm2.columns == bm.columns
    # letters=False reads the Enum, its letters nulls.
    plain, pm = quiet(dk.read_parquet, raw, letters=False)
    assert plain["grade"].dtype == pl.Enum(LEVELS) and pm.columns["grade"].ordered is True
    assert plain["grade"].to_list() == ["low", None, "high", None, None, "mid"]


def test_save_dta_takes_what_read_parquet_gives(tmp_path):
    _, _, raw = grade()
    back, bm = quiet(dk.read_parquet, raw)
    dk.save_dta(back, tmp_path / "g.dta", meta=bm)
    d, dm = quiet(dk.read_dta, tmp_path / "g.dta")
    assert d["grade"].dtype == pl.Float64 and tags(d["grade"]) == [None, ".a", None, None, ".z", None]
    assert d["grade"].fill_nan(None).to_list() == [1.0, None, 3.0, None, None, 2.0]
    assert dm.value_labels[dm.columns["grade"].value_labels] == {1: "low", 2: "mid", 3: "high", 4: "unused",
                                                                 ".r": "Refused"}


def test_without_letters_it_stays_text():
    df, meta, _ = grade()
    raw = quiet(dk.save_parquet, df, meta=meta)
    entry = profile(raw)["columns"]["grade"]
    assert "logical" not in entry and "value_labels" not in entry
    row = dk.read_parquet_info(raw).columns.filter(pl.col("name") == "grade").row(0, named=True)
    assert row["physical_type"] == "BYTE_ARRAY"


def test_a_set_that_does_not_fit_is_left_to_its_column():
    """The writer was given a set another column uses that does not label
    the levels: the categorical has grade_2, in every read."""
    df = pl.DataFrame({
        "score": pl.Series([1, 2, 1], dtype=pl.Int8),
        "grade": pl.Series(["low", None, "high"], dtype=pl.Enum(["low", "mid", "high"])),
    })
    meta = dk.Meta(columns={"score": dk.Column(value_labels="grade"), "grade": dk.Column(value_labels="grade")},
                   value_labels={"grade": {1: "A", 2: "B"}}, rows=3)
    raw = save_with_letters(df, meta, {"grade": L(None, ".b", None)})
    first = profile(raw)
    assert first["columns"]["grade"]["value_labels"] == "grade_2"
    assert first["columns"]["score"]["value_labels"] == "grade"
    back, bm = quiet(dk.read_parquet, raw)
    assert bm.columns["grade"].value_labels == "grade_2" and bm.columns["score"].value_labels == "grade"
    assert bm.value_labels == {"grade": {1: "A", 2: "B"}, "grade_2": {1: "low", 2: "mid", 3: "high"}}
    assert tags(back["grade"]) == [None, ".b", None]
    one, om = quiet(dk.read_parquet, raw, columns=["grade"])
    assert om.columns["grade"].value_labels == "grade_2" and om.value_labels["grade_2"] == bm.value_labels["grade_2"]
    # Written back twice: the same sets and names.
    raw2 = quiet(dk.save_parquet, back, meta=bm)
    back2, bm2 = quiet(dk.read_parquet, raw2)
    raw3 = quiet(dk.save_parquet, back2, meta=bm2)
    assert profile(raw2) == profile(raw3)
    assert dk.read_parquet(raw3)[1].value_labels == bm.value_labels


def blank(raw, pattern):
    """`raw` with the profile text matching `pattern` made spaces: the
    same length, so the footer stays valid."""
    text = raw.decode("latin-1")
    found = re.search(pattern, text)
    assert found, pattern
    return raw[:found.start()] + b" " * (found.end() - found.start()) + raw[found.end():]


def test_a_set_made_on_read_has_one_name_in_every_read():
    """A categorical recording no set, while a set named after it labels
    another column: every read, also of the categorical alone, makes
    grade_2."""
    df = pl.DataFrame({
        "score": pl.Series([1, 2, 1], dtype=pl.Int8),
        "grade": pl.Series(["low", None, "high"], dtype=pl.Enum(["low", "mid", "high"])),
    })
    meta = dk.Meta(columns={"score": dk.Column(value_labels="grade"), "grade": dk.Column(value_labels="grade")},
                   value_labels={"grade": {1: "A", 2: "B"}}, rows=3)
    raw = save_with_letters(df, meta, {"grade": L(None, ".b", None)})
    # Take out the categorical's set and its name from the profile.
    raw = blank(raw, r'"value_labels":"grade_2",?')
    raw = blank(raw, r',?"grade_2":\[\[1,"low"\],\[2,"mid"\],\[3,"high"\]\]')
    p = profile(raw)
    assert "value_labels" not in p["columns"]["grade"] and set(p["value_labels"]) == {"grade"}
    made = {1: "low", 2: "mid", 3: "high"}
    for cols in (None, ["grade"], ["grade", "score"]):
        back, bm = quiet(dk.read_parquet, raw, columns=cols)
        assert bm.columns["grade"].value_labels == "grade_2", cols
        assert bm.value_labels["grade_2"] == made
        assert tags(back["grade"]) == [None, ".b", None]
    assert dk.read_parquet_info(raw).columns.filter(pl.col("name") == "grade")["value_labels"].to_list() == ["grade_2"]
    # Written back, the made set is recorded under its name.
    back, bm = quiet(dk.read_parquet, raw, columns=["grade"])
    again = profile(quiet(dk.save_parquet, back, meta=bm))
    assert again["columns"]["grade"]["value_labels"] == "grade_2"
    assert again["value_labels"]["grade_2"] == [[1, "low"], [2, "mid"], [3, "high"]]


def bad_value_file():
    """Rows low, .a | high, mid in row groups of 2, with every 3.0 (high)
    made 1.5, which is no level number."""
    df = pl.DataFrame({"grade": pl.Series(["low", None, "high", "mid"], dtype=pl.Enum(["low", "mid", "high"]))})
    meta = dk.Meta(columns={"grade": dk.Column(value_labels="grade")},
                   value_labels={"grade": {1: "low", 2: "mid", 3: "high"}}, rows=4)
    raw = save_with_letters(df, meta, {"grade": L(None, ".a", None, None)}, compression="none", row_group_size=2)
    three, half = struct.pack("<d", 3.0), struct.pack("<d", 1.5)
    assert three in raw
    return raw.replace(three, half)


def test_a_value_that_is_no_level_number_reads_as_dot_with_a_warning():
    raw = bad_value_file()
    enum = pl.Enum(["low", "mid", "high"])
    # A window before it: clean, no warning.
    df, _ = quiet(dk.read_parquet, raw, n_max=2)
    assert tags(df["grade"]) == [None, ".a"] and df["grade"].fill_nan(None).to_list() == [1.0, None]
    # A window over it: `.` there, one warning naming the column and row.
    for _ in range(2):  # every read warns
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            df, _ = dk.read_parquet(raw, skip=1, n_max=3)
        assert [str(w.message) for w in caught] == [
            'column "grade": row 3 holds a value that is not one of its 3 level numbers; it is read as .'
        ]
        assert df["grade"].fill_nan(None).to_list() == [None, None, 2.0] and tags(df["grade"]) == [".a", None, None]
    # Rows without letters: the Enum.
    with pytest.warns(UserWarning, match="row 3 holds a value"):
        df, _ = dk.read_parquet(raw, skip=2)
    assert df["grade"].dtype == enum and df["grade"].to_list() == [None, "mid"]
    # The info call reads no rows, so it does not warn.
    assert quiet(dk.read_parquet_info, raw).columns["dtype"].to_list() == [str(enum)]


def test_keys_of_every_width():
    """Enums of 3, 300 and 70,000 levels: polars' keys of 8, 16 and 32
    bits, made from the level numbers in place (letters=False), and the
    level numbers themselves (with letters)."""
    for n in (3, 300, 70_000):
        levels = [f"v{i}" for i in range(n)]
        codes = [None if i % 7 == 3 else (i * 37) % n for i in range(500)]
        values = [None if c is None else levels[c] for c in codes]
        letters = L(*[".c" if i % 7 == 3 else None for i in range(500)])
        df = pl.DataFrame({"grade": pl.Series(values, dtype=pl.Enum(levels))})
        meta = dk.Meta(columns={"grade": dk.Column(value_labels="grade")}, rows=500)
        raw = save_with_letters(df, meta, {"grade": letters}, row_group_size=128)
        plain, _ = quiet(dk.read_parquet, raw, skip=100, n_max=300, letters=False)
        assert plain["grade"].dtype == pl.Enum(levels), n
        assert plain["grade"].to_list() == values[100:400], n
        back, _ = quiet(dk.read_parquet, raw, skip=100, n_max=300)
        assert back["grade"].fill_nan(None).to_list() == [None if c is None else c + 1.0 for c in codes[100:400]], n
        assert tags(back["grade"]) == letters.to_list()[100:400], n
