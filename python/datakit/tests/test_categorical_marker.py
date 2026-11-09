"""`.dta` categoricals marked `dtaparser_categorical` (plan 0023): save_dta
marks each Enum and Categorical, letters or not, and read_dta gives the
Enum back with its levels, order, letters and letter labels, unless the
file has changed since."""

import re
import warnings

import numpy as np
import polars as pl
import pytest

import datakit as dk
from datakit._frame import restore_categoricals

dp = pytest.importorskip("dta_parser")
pd = pytest.importorskip("pandas")

LEVELS = ["low", "mid", "high", "unused"]
STALE = "written as categoricals, but the file has changed since"


def L(*v, name="grade"):
    return pl.Series(name, list(v), dtype=dk.LETTERS)


def quiet(fn, *a, **k):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return fn(*a, **k)


def grade(path, **save):
    """An ordered Enum with an unused level, `.a`, `.` and `.z`, its set
    named "gl" (not the column's name) with a label on `.r`."""
    df = pl.DataFrame({
        "id": pl.Series([1, 2, 3, 4, 5, 6], dtype=pl.Int32),
        "grade": pl.Series(["low", None, "high", None, None, "mid"], dtype=pl.Enum(LEVELS)),
    })
    meta = dk.Meta(
        columns={"id": dk.Column(), "grade": dk.Column(label="Grade", value_labels="gl", ordered=True)},
        value_labels={"gl": {1: "low", 2: "mid", 3: "high", 4: "unused", ".r": "Refused"}},
        missing={"grade": L(None, ".a", None, None, ".z", None)},
        rows=6,
    )
    quiet(dk.save_dta, df, path, meta, **save)
    return df, meta


def chars(path):
    return dp.read_meta(path)["characteristics"]


def test_an_enum_with_letters_round_trips(tmp_path):
    path = tmp_path / "g.dta"
    df, _ = grade(path)
    assert chars(path) == {"grade": {"dtaparser_categorical": "ordered grade"}}
    sets = dp.read_meta(path)["value_labels"]
    assert sets["grade"] == {1: "low", 2: "mid", 3: "high", 4: "unused", dp.missing.r: "Refused"}
    for letters in ("meta", "columns", None):
        back, bm = quiet(dk.read_dta, path, letters=letters)
        assert back["grade"].dtype == pl.Enum(LEVELS)
        assert back["grade"].to_list() == df["grade"].to_list()
        assert bm.columns["grade"] == dk.Column(label="Grade", format="%12.0g", value_labels="grade", ordered=True)
        assert bm.labels("grade")[".r"] == "Refused"
        assert "grade" not in bm.characteristics
        want = [None, ".a", None, None, ".z", None]
        if letters == "meta":
            assert bm.missing["grade"].to_list() == want
        elif letters == "columns":
            assert back["grade_letter"].to_list() == want and "grade" not in bm.missing
        else:
            assert bm.missing == {} and "grade_letter" not in back.columns
    # Written again from what was read: the same file, as far as it says.
    back, bm = quiet(dk.read_dta, path)
    again = tmp_path / "again.dta"
    quiet(dk.save_dta, back, again, bm)
    assert chars(again) == chars(path)
    back2, bm2 = quiet(dk.read_dta, again)
    assert back2.equals(back) and bm2.missing["grade"].equals(bm.missing["grade"])
    assert bm2.value_labels["grade"] == bm.value_labels["grade"] and bm2.columns == bm.columns


def test_dta_parser_reads_the_letters_as_numbers_and_the_rest_as_a_category(tmp_path):
    path = tmp_path / "g.dta"
    grade(path)
    back = quiet(dp.read_dta, path)
    assert dp.missing_codes(back["grade"]).tolist() == [0, 2, 0, 1, 27, 0]
    window = quiet(dp.read_dta, path, n_max=1)
    assert window["grade"].dtype == pd.CategoricalDtype(LEVELS, ordered=True)


def test_ordered_and_unordered(tmp_path):
    for ordered, word in ((True, "ordered"), (False, "unordered"), (None, "unordered")):
        df = pl.DataFrame({"e": pl.Series(["b", "a"], dtype=pl.Enum(["b", "a", "c"]))})
        quiet(dk.save_dta, df, tmp_path / "o.dta", dk.Meta(columns={"e": dk.Column(ordered=ordered)}))
        assert chars(tmp_path / "o.dta") == {"e": {"dtaparser_categorical": f"{word} e"}}
        back, bm = quiet(dk.read_dta, tmp_path / "o.dta")
        assert back["e"].dtype == pl.Enum(["b", "a", "c"]) and back["e"].to_list() == ["b", "a"]
        assert bm.columns["e"].ordered is (word == "ordered")


def test_a_categorical_comes_back_an_enum(tmp_path):
    df = pl.DataFrame({"c": pl.Series(["x", None, "y", "x"], dtype=pl.Categorical)})
    quiet(dk.save_dta, df, tmp_path / "c.dta")
    assert chars(tmp_path / "c.dta") == {"c": {"dtaparser_categorical": "unordered c"}}
    back, _ = quiet(dk.read_dta, tmp_path / "c.dta")
    assert isinstance(back["c"].dtype, pl.Enum)
    assert back["c"].cast(pl.String).to_list() == ["x", None, "y", "x"]


def test_missing_letters_false_writes_dot_and_the_mark(tmp_path):
    path = tmp_path / "g.dta"
    df, _ = grade(path, missing_letters=False)
    assert chars(path) == {"grade": {"dtaparser_categorical": "ordered grade"}}
    assert dp.read_meta(path)["value_labels"]["grade"] == {1: "low", 2: "mid", 3: "high", 4: "unused"}
    assert dp.missing_codes(dp.read_dta(path)["grade"]).tolist() == [0, 1, 0, 1, 1, 0]
    back, bm = quiet(dk.read_dta, path)
    assert back["grade"].dtype == pl.Enum(LEVELS) and back["grade"].to_list() == df["grade"].to_list()
    assert bm.missing == {}


def written(path, columns, marks, value_labels=None, formats=None):
    """A file of pandas `columns` written by dta_parser, with characteristics
    `marks` ({column: {name: value}}), which no writer copies: written under
    another name of the same length and renamed in the file."""
    frame = pd.DataFrame(columns)
    frame.attrs["dta"] = {
        "columns": {n: {"value_labels": n if n in (value_labels or {}) else "", "format": (formats or {}).get(n, "")}
                    for n in frame.columns},
        "value_labels": value_labels or {},
        "characteristics": {c: {k.replace("dtaparser_", "zzzzzzzzz_"): v for k, v in m.items()}
                            for c, m in marks.items()},
    }
    dp.write_dta(frame, path)
    path.write_bytes(path.read_bytes().replace(b"zzzzzzzzz_", b"dtaparser_"))
    return path


def test_codes_are_renumbered_from_one(tmp_path):
    path = written(tmp_path / "t.dta", {"v": np.array([10, 30, 20, 10], dtype=np.int32)},
                   {"v": {"dtaparser_categorical": "unordered v"}}, {"v": {10: "a", 20: "b", 30: "c"}})
    back, bm = quiet(dk.read_dta, path)
    assert back["v"].dtype == pl.Enum(["a", "b", "c"]) and back["v"].to_list() == ["a", "c", "b", "a"]
    assert bm.value_labels["v"] == {10: "a", 20: "b", 30: "c"}
    quiet(dk.save_dta, back, tmp_path / "again.dta", bm)
    assert dp.read_meta(tmp_path / "again.dta")["value_labels"]["v"] == {1: "a", 2: "b", 3: "c"}
    assert dp.read_dta(tmp_path / "again.dta")["v"].tolist() == ["a", "c", "b", "a"]
    assert quiet(dk.read_dta, tmp_path / "again.dta")[0]["v"].to_list() == ["a", "c", "b", "a"]


def test_save_dta_drops_marks_meta_still_holds(tmp_path):
    path = tmp_path / "g.dta"
    grade(path)
    back, bm = quiet(dk.read_dta, path)
    # The column is integers now; a mark left in meta must not follow it.
    ints = back.with_columns(pl.col("grade").to_physical().cast(pl.Int32))
    im = bm.copy()
    im.missing.pop("grade")
    im.characteristics["grade"] = {"dtaparser_categorical": "ordered grade", "dtaparser_factor": "ordered grade",
                                   "note": "kept"}
    im.characteristics["id"] = {"dtaparser_factor": "unordered gl"}
    quiet(dk.save_dta, ints, tmp_path / "ints.dta", im)
    assert chars(tmp_path / "ints.dta") == {"grade": {"note": "kept"}}
    assert quiet(dk.read_dta, tmp_path / "ints.dta")[0]["grade"].dtype == pl.Int32
    # An Enum gets its own mark, whatever meta says.
    bm.characteristics["grade"] = {"dtaparser_factor": "unordered x", "dtaparser_categorical": "unordered x"}
    quiet(dk.save_dta, back, tmp_path / "enum.dta", bm)
    assert chars(tmp_path / "enum.dta") == {"grade": {"dtaparser_categorical": "ordered grade"}}


def test_factors_true(tmp_path):
    path = tmp_path / "g.dta"
    df, _ = grade(path)
    back, bm = quiet(dk.read_dta, path, factors=True)
    assert back["grade"].dtype == pl.Enum(LEVELS) and back["grade"].to_list() == df["grade"].to_list()
    assert bm.missing["grade"].to_list() == [None, ".a", None, None, ".z", None]
    # A stale one is any labelled column to to_factors: the values read and
    # the labelled codes.
    stale = written(tmp_path / "s.dta", {"v": np.array([1, 2, 5], dtype=np.int32)},
                    {"v": {"dtaparser_categorical": "unordered v"}}, {"v": {1: "a", 2: "b"}})
    with pytest.warns(UserWarning, match=STALE):
        back, bm = dk.read_dta(stale, factors=True)
    assert back["v"].dtype == pl.Enum(["a", "b", "5"]) and bm.characteristics["v"] == {
        "dtaparser_categorical": "unordered v"}


def test_a_window_without_letters_is_an_enum(tmp_path):
    path = tmp_path / "g.dta"
    df, _ = grade(path)
    for skip, n_max in ((0, 1), (2, 1), (5, 1), (1, 4)):
        back, bm = quiet(dk.read_dta, path, skip=skip, n_max=n_max)
        assert back["grade"].dtype == pl.Enum(LEVELS)
        assert back["grade"].to_list() == df["grade"].to_list()[skip:skip + n_max]
    back, bm = quiet(dk.read_dta, path, columns=["grade"], skip=6)
    assert back["grade"].dtype == pl.Enum(LEVELS) and back.height == 0


def long_bytes(v):
    return int(v).to_bytes(4, "little", signed=True)


def relabel(path, old, new):
    """The file with the value label code `old` made `new`."""
    data = path.read_bytes()
    at = data.index(long_bytes(old), data.index(b"<value_labels>"))
    path.write_bytes(data[:at] + long_bytes(new) + data[at + 4:])
    return path


GOOD = {"v": {1: "a", 2: "b", 777: "x"}}
MARK = {"v": {"dtaparser_categorical": "unordered v"}}


def int_column():
    return {"v": np.array([1, 2, 1], dtype=np.int32)}


@pytest.mark.parametrize("why", ["renamed set", "unlabelled value", "shared text", "long's range", "labelled dot",
                                 "%td", "%d", "string", "both marks"])
def test_a_failing_check_reads_unmarked_with_a_warning(tmp_path, why):
    path = tmp_path / "s.dta"
    if why == "renamed set":
        written(path, int_column(), {"v": {"dtaparser_categorical": "unordered w"}}, GOOD)
    elif why == "unlabelled value":
        written(path, {"v": np.array([1, 3, 1], dtype=np.int32)}, MARK, GOOD)
    elif why == "shared text":
        written(path, int_column(), MARK, {"v": {1: "a", 2: "b", 777: "a"}})
    elif why == "long's range":
        relabel(written(path, int_column(), MARK, GOOD), 777, -2147483648)
    elif why == "labelled dot":
        relabel(written(path, int_column(), MARK, GOOD), 777, 2147483621)
    elif why in ("%td", "%d"):
        written(path, int_column(), MARK, GOOD, formats={"v": why})
    elif why == "string":
        written(path, {"v": ["a", "b", ""]}, MARK)
    else:
        written(path, int_column(), {"v": {"dtaparser_categorical": "unordered v",
                                           "dtaparser_factor": "unordered v"}}, GOOD)
    unmarked = tmp_path / "u.dta"
    written(unmarked, *{
        "renamed set": (int_column(), {}, GOOD),
        "unlabelled value": ({"v": np.array([1, 3, 1], dtype=np.int32)}, {}, GOOD),
        "shared text": (int_column(), {}, {"v": {1: "a", 2: "b", 777: "a"}}),
        "string": ({"v": ["a", "b", ""]}, {}),
    }.get(why, (int_column(), {}, GOOD)), formats={"v": why} if why.startswith("%") else None)
    if why in ("long's range", "labelled dot"):
        relabel(unmarked, 777, -2147483648 if why == "long's range" else 2147483621)
    for factors in (False, True):
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            back, bm = dk.read_dta(path, factors=factors)
        assert [str(w.message) for w in caught if STALE in str(w.message)] == [
            f'column "v" was {STALE}: their value label set changed, a value has no label, two codes share a text, '
            "a code is not a whole number, `.` is labelled, a date format was given, or a column has both markers; "
            "read as unmarked columns"]
        want, wm = quiet(dk.read_dta, unmarked, factors=factors)
        assert back.equals(want), (why, factors)
        assert bm.columns == wm.columns and bm.value_labels == wm.value_labels
        assert "dtaparser_categorical" in bm.characteristics["v"]


def test_one_warning_names_every_stale_column(tmp_path):
    path = written(tmp_path / "s.dta", {"a": np.array([1, 9], dtype=np.int32), "b": ["x", "y"],
                                        "c": np.array([1, 2], dtype=np.int32)},
                   {"a": {"dtaparser_categorical": "unordered a"}, "b": {"dtaparser_categorical": "unordered b"},
                    "c": {"dtaparser_categorical": "unordered c"}},
                   {"a": {1: "one"}, "c": {1: "one", 2: "two"}})
    with pytest.warns(UserWarning, match=re.escape('columns "a", "b" were ' + STALE)) as caught:
        back, _ = dk.read_dta(path)
    assert len([w for w in caught if STALE in str(w.message)]) == 1
    assert back["c"].dtype == pl.Enum(["one", "two"]) and back["a"].dtype == pl.Int8


def test_a_label_on_a_letter_no_row_holds_passes(tmp_path):
    path = written(tmp_path / "t.dta", int_column(), MARK, {"v": {1: "a", 2: "b", dp.missing.r: "Refused"}})
    back, bm = quiet(dk.read_dta, path)
    assert back["v"].dtype == pl.Enum(["a", "b"]) and bm.missing == {}
    assert bm.labels("v") == {1: "a", 2: "b", ".r": "Refused"}


def test_a_factor_mark_alone_is_left_as_it_is(tmp_path):
    path = written(tmp_path / "f.dta", int_column(), {"v": {"dtaparser_factor": "unordered v"}}, GOOD)
    back, bm = quiet(dk.read_dta, path)
    assert back["v"].dtype == pl.Int8 and bm.characteristics["v"] == {"dtaparser_factor": "unordered v"}


@pytest.mark.parametrize("code", [1.5, 3e9, -2147483648, float("inf")])
def test_codes_that_are_not_whole_longs_fail(code):
    """No .dta file holds a code of 1.5; the check is made all the same."""
    df = pl.DataFrame({"v": pl.Series([1, 2], dtype=pl.Int32)})
    meta = dk.Meta(columns={"v": dk.Column(value_labels="v")}, value_labels={"v": {1: "a", 2: "b", code: "c"}},
                   characteristics={"v": {"dtaparser_categorical": "unordered v"}})
    out, stale = restore_categoricals(df, meta)
    assert stale == ["v"] and out.equals(df)
    meta.value_labels["v"] = {1: "a", 2: "b", 2147483620: "c"}
    out, stale = restore_categoricals(df, meta)
    assert stale == [] and out["v"].dtype == pl.Enum(["a", "b", "c"])


def test_an_enum_without_levels_holding_only_letters(tmp_path):
    df = pl.DataFrame({"e": pl.Series([None, None], dtype=pl.Enum([]))})
    meta = dk.Meta(columns={"e": dk.Column(value_labels="s")}, value_labels={"s": {".a": "A"}},
                   missing={"e": L(None, ".a", name="e")}, rows=2)
    quiet(dk.save_dta, df, tmp_path / "e.dta", meta)
    back, bm = quiet(dk.read_dta, tmp_path / "e.dta")
    assert back["e"].dtype == pl.Enum([]) and back["e"].to_list() == [None, None]
    assert bm.missing["e"].to_list() == [None, ".a"] and bm.labels("e") == {".a": "A"}
