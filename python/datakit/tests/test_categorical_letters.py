"""Parquet categoricals that keep `.a` to `.z` (plan 0022): an Enum with
letters is written as level numbers from 1 (DOUBLE, tagged NaNs) and reads
back as the same Enum, its letters in `meta.missing` or a companion."""

import json
import re
import struct
import warnings

import polars as pl
import pytest

import datakit as dk

LEVELS = ["low", "mid", "high", "unused"]


def L(*v, name="grade"):
    return pl.Series(name, list(v), dtype=dk.LETTERS)


def quiet(fn, *a, **k):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return fn(*a, **k)


def grade(**write):
    """A file whose `grade` is an ordered Enum with an unused level, `.a`,
    `.` and `.z`, and a set with a label on `.r`."""
    df = pl.DataFrame({
        "id": pl.Series([1, 2, 3, 4, 5, 6], dtype=pl.Int32),
        "grade": pl.Series(["low", None, "high", None, None, "mid"], dtype=pl.Enum(LEVELS)),
    })
    meta = dk.Meta(
        columns={"id": dk.Column(), "grade": dk.Column(label="Grade", value_labels="grade", ordered=True)},
        value_labels={"grade": {1: "low", 2: "mid", 3: "high", 4: "unused", ".r": "Refused"}},
        missing={"grade": L(None, ".a", None, None, ".z", None)},
        rows=6,
    )
    return df, meta, quiet(dk.save_parquet, df, meta=meta, **write)


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
    assert "storage" not in entry
    # Other tools see the numbers 1 to k, NaN for .a to .z.
    pa = pytest.importorskip("pyarrow.parquet")
    import io
    t = pa.read_table(io.BytesIO(raw))
    got = t.column("grade").to_pylist()
    assert got[0] == 1.0 and got[1] != got[1] and got[2] == 3.0 and got[3] is None and got[5] == 2.0


def test_a_categorical_with_letters_round_trips_unchanged():
    df, meta, raw = grade()
    for factors in (False, True):
        back, bm = quiet(dk.read_parquet, raw, factors=factors)
        assert back["grade"].dtype == pl.Enum(LEVELS)
        assert back["grade"].to_list() == df["grade"].to_list()
        assert bm.columns["grade"] == dk.Column(label="Grade", value_labels="grade", ordered=True)
        assert bm.value_labels == {"grade": {1: "low", 2: "mid", 3: "high", 4: "unused", ".r": "Refused"}}
        assert bm.missing["grade"].to_list() == [None, ".a", None, None, ".z", None]
        assert bm.labels("grade")[".r"] == "Refused"
    # Again, and again: the same file.
    again = quiet(dk.save_parquet, back, meta=bm)
    assert profile(again) == profile(raw)
    back2, bm2 = quiet(dk.read_parquet, again)
    assert back2.equals(back) and bm2.missing["grade"].equals(bm.missing["grade"])
    assert bm2.value_labels == bm.value_labels and bm2.columns == bm.columns


def test_companion_columns_pair_it():
    df, _, raw = grade()
    back, bm = quiet(dk.read_parquet, raw, letters="columns")
    assert back.columns == ["id", "id_letter", "grade", "grade_letter"]
    assert back["grade"].dtype == pl.Enum(LEVELS)
    assert back["grade_letter"].to_list() == [None, ".a", None, None, ".z", None]
    assert bm.letter_columns["grade"] == "grade_letter" and "grade" not in bm.missing
    # The pair follows its rows, and is written back from the companion.
    shuffled = back.reverse()
    again, am = quiet(dk.read_parquet, quiet(dk.save_parquet, shuffled, meta=bm))
    assert again["grade"].to_list() == df["grade"].reverse().to_list()
    assert am.missing["grade"].to_list() == [None, ".z", None, None, ".a", None]
    # letters_to_columns pairs it too.
    back, bm = quiet(dk.read_parquet, raw)
    paired = dk.letters_to_columns(back, bm, ["grade"])
    assert paired["grade_letter"].to_list() == [None, ".a", None, None, ".z", None]


def test_save_dta_takes_what_read_parquet_gives(tmp_path):
    _, _, raw = grade()
    back, bm = quiet(dk.read_parquet, raw)
    dk.save_dta(back, tmp_path / "g.dta", meta=bm)
    d, dm = dk.read_dta(tmp_path / "g.dta")
    assert d["grade"].to_list() == [1, None, 3, None, None, 2]
    assert dm.missing["grade"].to_list() == [None, ".a", None, None, ".z", None]
    assert dm.value_labels[dm.columns["grade"].value_labels] == {1: "low", 2: "mid", 3: "high", 4: "unused"}


def test_without_letters_it_stays_text():
    df, meta, _ = grade()
    meta.missing.pop("grade")
    raw = quiet(dk.save_parquet, df, meta=meta)
    entry = profile(raw)["columns"]["grade"]
    assert "logical" not in entry and "value_labels" not in entry
    row = dk.read_parquet_info(raw).columns.filter(pl.col("name") == "grade").row(0, named=True)
    assert row["physical_type"] == "BYTE_ARRAY"
    # missing_letters=False writes the letters as nulls, as text.
    _, meta, _ = grade()
    raw = quiet(dk.save_parquet, df, meta=meta, missing_letters=False)
    back, bm = quiet(dk.read_parquet, raw)
    assert back["grade"].to_list() == df["grade"].to_list() and "grade" not in bm.missing
    assert "logical" not in profile(raw)["columns"]["grade"]


def test_what_cannot_be_given_letters():
    df, meta, _ = grade()
    # An Enum that meta gives no set.
    meta.columns["grade"].value_labels = None
    with pytest.raises(ValueError, match='"grade" is an Enum without a value label set and has .a to .z'):
        dk.save_parquet(df, meta=meta)
    del meta.columns["grade"]
    with pytest.raises(ValueError, match='"grade" is an Enum without a value label set'):
        dk.save_parquet(df, meta=meta)
    # A polars Categorical, whatever meta says.
    df, meta, _ = grade()
    cat = df.with_columns(pl.col("grade").cast(pl.String).cast(pl.Categorical))
    meta._digests.clear()
    with pytest.raises(ValueError, match='"grade" is a Categorical and has .a to .z'):
        dk.save_parquet(cat, meta=meta)


def test_a_set_that_does_not_fit_is_left_to_its_column():
    """The caller names a set another column uses that does not label the
    levels: the categorical gets grade_2, and the names stay over rounds."""
    df = pl.DataFrame({
        "score": pl.Series([1, 2, 1], dtype=pl.Int8),
        "grade": pl.Series(["low", None, "high"], dtype=pl.Enum(["low", "mid", "high"])),
    })
    sets = {"grade": {1: "A", 2: "B"}}
    meta = dk.Meta(columns={"score": dk.Column(value_labels="grade"), "grade": dk.Column(value_labels="grade")},
                   value_labels=sets, missing={"grade": L(None, ".b", None)}, rows=3)
    raw = quiet(dk.save_parquet, df, meta=meta)
    first = profile(raw)
    assert first["columns"]["grade"]["value_labels"] == "grade_2"
    assert first["columns"]["score"]["value_labels"] == "grade"
    back, bm = quiet(dk.read_parquet, raw)
    assert bm.columns["grade"].value_labels == "grade_2" and bm.columns["score"].value_labels == "grade"
    assert bm.value_labels == {"grade": {1: "A", 2: "B"}, "grade_2": {1: "low", 2: "mid", 3: "high"}}
    # A read of the categorical alone names the same set.
    one, om = quiet(dk.read_parquet, raw, columns=["grade"])
    assert om.columns["grade"].value_labels == "grade_2" and om.value_labels["grade_2"] == bm.value_labels["grade_2"]
    # Written back twice: the same sets and names.
    raw2 = quiet(dk.save_parquet, back, meta=bm)
    back2, bm2 = quiet(dk.read_parquet, raw2)
    raw3 = quiet(dk.save_parquet, back2, meta=bm2)
    assert profile(raw2) == first and profile(raw3) == first
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
                   value_labels={"grade": {1: "A", 2: "B"}}, missing={"grade": L(None, ".b", None)}, rows=3)
    raw = quiet(dk.save_parquet, df, meta=meta)
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
        assert bm.missing["grade"].to_list() == [None, ".b", None]
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
                   value_labels={"grade": {1: "low", 2: "mid", 3: "high"}},
                   missing={"grade": L(None, ".a", None, None)}, rows=4)
    raw = quiet(dk.save_parquet, df, meta=meta, compression="none", row_group_size=2)
    three, half = struct.pack("<d", 3.0), struct.pack("<d", 1.5)
    assert three in raw
    return raw.replace(three, half)


def test_a_value_that_is_no_level_number_reads_as_dot_with_a_warning():
    raw = bad_value_file()
    enum = pl.Enum(["low", "mid", "high"])
    # A window before it: clean, no warning.
    df, meta = quiet(dk.read_parquet, raw, n_max=2)
    assert df["grade"].dtype == enum and df["grade"].to_list() == ["low", None]
    assert meta.missing["grade"].to_list() == [None, ".a"]
    # A window over it: `.` there, one warning naming the column and row.
    for _ in range(2):  # every read warns
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            df, meta = dk.read_parquet(raw, skip=1, n_max=3)
        assert [str(w.message) for w in caught] == [
            'column "grade": row 3 holds a value that is not one of its 3 level numbers; it is read as .'
        ]
        assert df["grade"].dtype == enum and df["grade"].to_list() == [None, None, "mid"]
        assert meta.missing["grade"].to_list() == [".a", None, None]
    # The whole file: one warning, however many bad rows.
    with pytest.warns(UserWarning, match="row 3 holds a value") as caught:
        df, _ = dk.read_parquet(raw, letters="columns")
    assert len(caught) == 1
    assert df["grade"].dtype == enum and df["grade_letter"].to_list() == [None, ".a", None, None]
    # The info call reads no rows, so it does not warn.
    assert quiet(dk.read_parquet_info, raw).columns["dtype"].to_list() == [str(enum)]


def test_keys_of_every_width():
    """Enums of 3, 300 and 70,000 levels: polars' keys of 8, 16 and 32
    bits, made from the level numbers in place."""
    for n in (3, 300, 70_000):
        levels = [f"v{i}" for i in range(n)]
        values = [None if i % 7 == 3 else levels[(i * 37) % n] for i in range(500)]
        letters = L(*[".c" if i % 7 == 3 else None for i in range(500)])
        df = pl.DataFrame({"grade": pl.Series(values, dtype=pl.Enum(levels))})
        meta = dk.Meta(columns={"grade": dk.Column(value_labels="grade")}, missing={"grade": letters}, rows=500)
        raw = quiet(dk.save_parquet, df, meta=meta, row_group_size=128)
        back, bm = quiet(dk.read_parquet, raw, skip=100, n_max=300)
        assert back["grade"].dtype == pl.Enum(levels), n
        assert back["grade"].to_list() == values[100:400], n
        assert bm.missing["grade"].to_list() == letters.to_list()[100:400], n
