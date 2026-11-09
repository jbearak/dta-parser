"""read_dta and the `dtaparser_categorical` mark (plan 0023), which
datakit's save_dta and TypeScript's saveDta put on a categorical that may
hold .a to .z: a category when the rows read hold no letters, else the
numbers with their letters, unless the file has changed since."""

import re
import warnings

import numpy as np
import pandas as pd
import pytest

import dta_parser as dp
from dta_parser import DtaArray, missing, read_dta, read_meta, write_dta
from dta_parser._read import _marked_categorical

STALE = "written as categoricals, but the file has changed since"
WARNING = (STALE + ": their value label set changed, a value has no label, two codes share a text, a code is not a "
           "whole number, `.` is labelled, a date format was given, or a column has both markers; read as unmarked "
           "columns")


def quiet(fn, *a, **k):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return fn(*a, **k)


def written(path, columns, marks, value_labels=None, formats=None):
    """A file of `columns` with characteristics `marks` ({column: {name:
    value}}), which write_dta does not copy: written under another name of
    the same length and renamed in the file."""
    frame = pd.DataFrame(columns)
    frame.attrs["dta"] = {
        "columns": {n: {"value_labels": n if n in (value_labels or {}) else "", "format": (formats or {}).get(n, "")}
                    for n in frame.columns},
        "value_labels": value_labels or {},
        "characteristics": {c: {k.replace("dtaparser_", "zzzzzzzzz_"): v for k, v in m.items()}
                            for c, m in marks.items()},
    }
    write_dta(frame, path)
    path.write_bytes(path.read_bytes().replace(b"zzzzzzzzz_", b"dtaparser_"))
    return path


LEVELS = {10: "low", 20: "mid", 30: "high", 40: "unused", missing.r: "Refused"}


def grade(tmp_path, mark="ordered grade"):
    """grade: low, .a, high, ., .z, mid, as codes 10, 20, 30 of a set with an
    unused level and a label on .r."""
    values = DtaArray([10, 0, 30, 0, 0, 20], [0, 2, 0, 1, 27, 0], storage="long")
    return written(tmp_path / "g.dta", {"id": np.arange(1, 7, dtype=np.int8), "grade": values},
                   {"grade": {"dtaparser_categorical": mark}}, {"grade": LEVELS})


def test_without_letters_in_the_rows_read_a_category(tmp_path):
    path = grade(tmp_path)
    want = pd.CategoricalDtype(["low", "mid", "high", "unused"], ordered=True)
    for skip, n_max in ((0, 1), (2, 1), (5, 1), (6, None)):
        back = quiet(read_dta, path, skip=skip, n_max=n_max)
        assert back["grade"].dtype == want
        assert back["grade"].tolist() == ["low", np.nan, "high", np.nan, np.nan, "mid"][skip:skip + (n_max or 6)]
    unordered = quiet(read_dta, grade(tmp_path, "unordered grade"), n_max=1)
    assert unordered["grade"].dtype == pd.CategoricalDtype(["low", "mid", "high", "unused"], ordered=False)


def test_with_letters_the_numbers_and_letters_without_a_warning(tmp_path):
    path = grade(tmp_path)
    for skip, n_max in ((0, None), (1, 1), (3, 2)):
        back = quiet(read_dta, path, skip=skip, n_max=n_max)
        assert isinstance(back["grade"].dtype, dp.DtaDtype)
        assert dp.missing_codes(back["grade"]).tolist() == [0, 2, 0, 1, 27, 0][skip:skip + (n_max or 6)]
    back = quiet(read_dta, path)
    assert back["grade"].tolist()[:3] == [10.0, missing.a, 30.0]
    info = back.attrs["dta"]
    assert info["columns"]["grade"]["value_labels"] == "grade" and info["value_labels"]["grade"] == LEVELS
    assert info["characteristics"]["grade"] == {"dtaparser_categorical": "ordered grade"}


def test_write_dta_drops_both_marks_and_marks_its_categories(tmp_path):
    path = grade(tmp_path)
    back = quiet(read_dta, path)
    back.attrs["dta"]["characteristics"]["id"] = {"dtaparser_factor": "unordered x", "dtaparser_categorical": "x",
                                                  "unit": "person"}
    back["cat"] = pd.Categorical(["a", "b", "a", "b", "a", "b"])
    again = tmp_path / "again.dta"
    write_dta(back, again)
    assert read_meta(again)["characteristics"] == {"id": {"unit": "person"},
                                                   "cat": {"dtaparser_factor": "unordered cat"}}


def int_column():
    return {"v": np.array([1, 2, 1], dtype=np.int32)}


GOOD = {"v": {1: "a", 2: "b", 777: "x"}}
MARK = {"v": {"dtaparser_categorical": "unordered v"}}


def long_bytes(v):
    return int(v).to_bytes(4, "little", signed=True)


def relabel(path, old, new):
    data = path.read_bytes()
    at = data.index(long_bytes(old), data.index(b"<value_labels>"))
    path.write_bytes(data[:at] + long_bytes(new) + data[at + 4:])
    return path


@pytest.mark.parametrize("why", ["renamed set", "unlabelled value", "shared text", "long's range", "labelled dot",
                                 "%td", "%d", "both marks"])
def test_a_failing_check_reads_unmarked_with_a_warning(tmp_path, why):
    path, unmarked = tmp_path / "s.dta", tmp_path / "u.dta"
    columns, sets, formats = int_column(), GOOD, None
    marks = MARK
    if why == "renamed set":
        marks = {"v": {"dtaparser_categorical": "unordered w"}}
    elif why == "unlabelled value":
        columns = {"v": np.array([1, 3, 1], dtype=np.int32)}
    elif why == "shared text":
        sets = {"v": {1: "a", 2: "b", 777: "a"}}
    elif why.startswith("%"):
        formats = {"v": why}
    elif why == "both marks":
        marks = {"v": {"dtaparser_categorical": "unordered v", "dtaparser_factor": "unordered v"}}
    written(path, columns, marks, sets, formats)
    written(unmarked, columns, {}, sets, formats)
    if why in ("long's range", "labelled dot"):
        new = -2147483648 if why == "long's range" else 2147483621
        relabel(path, 777, new)
        relabel(unmarked, 777, new)
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        back = read_dta(path)
    assert [str(w.message) for w in caught] == ["v was " + WARNING]
    want = quiet(read_dta, unmarked)
    assert back["v"].dtype == want["v"].dtype and back["v"].tolist() == want["v"].tolist()
    if why.startswith("%"):
        # Without date conversion the format does not matter.
        assert quiet(read_dta, path, dates=False)["v"].tolist() == ["a", "b", "a"]


def test_a_marked_string_column_warns_and_reads_as_text(tmp_path):
    path = written(tmp_path / "s.dta", {"v": ["", "", "x"], "w": ["a", "b", "c"]},
                   {"v": {"dtaparser_categorical": "unordered v"}, "w": {"dtaparser_factor": "unordered w"}})
    for n_max in (None, 2, 0):
        with pytest.warns(UserWarning, match="^v was " + re.escape(WARNING) + "$") as caught:
            back = read_dta(path, n_max=n_max)
        assert len(caught) == 1
        assert back["v"].tolist() == ["", "", "x"][:n_max] and back["w"].tolist() == ["a", "b", "c"][:n_max]


def test_one_warning_for_every_stale_categorical_and_its_own_for_factors(tmp_path):
    path = written(tmp_path / "s.dta", {"a": np.array([1, 9], dtype=np.int32), "b": np.array([1, 9], dtype=np.int32),
                                        "c": ["x", "y"]},
                   {"a": {"dtaparser_categorical": "unordered a"}, "b": {"dtaparser_factor": "unordered b"},
                    "c": {"dtaparser_categorical": "unordered c"}},
                   {"a": {1: "one"}, "b": {1: "one"}})
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        read_dta(path)
    messages = sorted(str(w.message) for w in caught)
    assert len(messages) == 2
    assert messages[0] == "a, c were " + WARNING
    assert messages[1].startswith("write_dta wrote b as categories")


def test_a_label_on_a_letter_no_row_holds_passes(tmp_path):
    path = written(tmp_path / "t.dta", int_column(), MARK, {"v": {1: "a", 2: "b", missing.r: "Refused"}})
    back = quiet(read_dta, path)
    assert back["v"].dtype == pd.CategoricalDtype(["a", "b"]) and back["v"].tolist() == ["a", "b", "a"]


def test_a_set_without_labels_and_no_values(tmp_path):
    path = written(tmp_path / "t.dta", {"v": pd.array([None, None], dtype="Float64")}, MARK,
                   {"v": {missing.a: "A"}})
    back = quiet(read_dta, path)
    assert back["v"].dtype == pd.CategoricalDtype([]) and back["v"].isna().all()


@pytest.mark.parametrize("code", [1.5, 3e9, -2147483648, float("inf")])
def test_codes_that_are_not_whole_longs_fail(code):
    """No .dta file holds a code of 1.5; the check is made all the same."""
    values, codes = np.array([1, 2], dtype=np.int32), np.zeros(2, dtype=np.uint8)
    sets = {"v": {1: "a", 2: "b", code: "c"}}
    assert _marked_categorical("unordered v", "v", sets, values, codes, 0, "", True) is None
    sets = {"v": {1: "a", 2: "b", 2147483620: "c"}}
    got = _marked_categorical("unordered v", "v", sets, values, codes, 0, "", True)
    assert list(got.categories) == ["a", "b", "c"]
