"""read_fixed_width reads fixed-width text through a SAS setup file (plan 0009).

What each value should be follows from the setup text written here; the
converted file is also read with pandas and pyreadstat, which check the
letters, value labels and long labels independently.
"""

import glob
import os
import tempfile

import pandas as pd
import pytest

import dta_parser as dp
from dta_parser import _native, missing

SETUP = "\n".join([
    "/* A setup in CDC's style */",
    'libname "data-file-path";',
    "PROC FORMAT;",
    "  VALUE sexf  1='(1) Boy' 2='(2) Girl' ;",
    "  VALUE kidsf 0='(0) None' 98='(98) DK' 99='(99) Not ascertained' ;",
    "DATA ;",
    'INFILE "c:\\temp\\x.dat" LRECL=6;',
    "INPUT ID 1-3 SEX 4 KIDS 5-6 ;",
    "LABEL ID = 'Case number' SEX = \"R's sex\"",
    "  KIDS = '" + "k" * 200 + "' ;",
    "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
    "FORMAT SEX sexf. KIDS kidsf. ;",
    "RUN ;",
])
DATA = "0011 2\n002298\n003199\n004199\n0052 0\n"


@pytest.fixture
def files(tmp_path):
    def make(setup=SETUP, data=DATA):
        (tmp_path / "x.sas").write_text(setup)
        (tmp_path / "x.dat").write_text(data)
        return str(tmp_path / "x.dat"), str(tmp_path / "x.sas")
    return make


def test_setup_mode(files):
    df = dp.read_fixed_width(*files())
    assert list(df.columns) == ["ID", "SEX", "KIDS"]
    assert df["ID"].tolist() == [1, 2, 3, 4, 5]
    assert df["ID"].dtype == "int8"
    kids = df["KIDS"]
    assert kids.isna().tolist() == [False, True, True, True, False]
    assert dp.missing_codes(kids).tolist() == [0, 1, 1, 1, 0]
    info = df.attrs["dta"]
    assert info["columns"]["SEX"]["label"] == "R's sex"
    assert info["columns"]["KIDS"]["label"] == "k" * 200
    # 98 and 99 can no longer occur, so their labels are gone.
    assert info["value_labels"][info["columns"]["KIDS"]["value_labels"]] == {0: "(0) None"}
    assert "warnings" not in df.attrs


def test_tagged_mode(files):
    df = dp.read_fixed_width(*files(), recodes="tagged")
    kids = df["KIDS"]
    assert kids[1] is missing.a and kids[2] is missing.b and kids[3] is missing.b
    assert dp.missing_codes(kids).tolist() == [0, 2, 3, 3, 0]
    info = df.attrs["dta"]
    assert info["value_labels"]["kidsf"] == {0: "(0) None", missing.a: "(98) DK", missing.b: "(99) Not ascertained"}


def test_none_mode_and_bad_mode(files):
    df = dp.read_fixed_width(*files(), recodes="none")
    assert df["KIDS"].tolist() == [2, 98, 99, 99, 0]
    with pytest.raises(ValueError, match="recodes must be"):
        dp.read_fixed_width(*files(), recodes="letters")


def test_columns_skip_n_max(files):
    df = dp.read_fixed_width(*files(), columns=["KIDS", "ID"], skip=1, n_max=2)
    assert list(df.columns) == ["KIDS", "ID"]
    assert df["ID"].tolist() == [2, 3]


def test_warnings(files):
    setup = "PROC FORMAT; VALUE f 1-5='low';\nDATA; INPUT X 1;\n" + "\n".join(f"y{i} = x * 2;" for i in range(10))
    with pytest.warns(dp.FixedWidthWarning, match="3 more") as record:
        df = dp.read_fixed_width(*files(setup, "1\n2\n"))
    assert len(df.attrs["warnings"]) == 11
    assert all(len(line) <= 102 for line in str(record[0].message).splitlines())


def test_errors_leave_no_temporary_files(files):
    before = set(glob.glob(os.path.join(tempfile.gettempdir(), "dta_parser*")))
    with pytest.raises(ValueError, match="setup line 2: INPUT form not supported"):
        dp.read_fixed_width(*files("DATA;\nINPUT X 1. ;", "1\n"))
    dp.read_fixed_width(*files())
    assert set(glob.glob(os.path.join(tempfile.gettempdir(), "dta_parser*"))) == before
    with pytest.raises(FileNotFoundError):
        dp.read_fixed_width("no such file.dat", files()[1])


def test_other_readers_read_the_tagged_file(files, tmp_path):
    out = str(tmp_path / "tagged.dta")
    _native.fixed_width(*files(), out, "tagged")
    theirs = pd.read_stata(out, convert_missing=True, convert_categoricals=False)
    assert [str(v) for v in theirs["KIDS"]] == ["2", ".a", ".b", ".b", "0"]
    with pd.io.stata.StataReader(out) as reader:
        reader.read()
        assert reader.variable_labels()["KIDS"] == "k" * 200
        labels = reader.value_labels()["kidsf"]
    assert labels[0] == "(0) None" and len(labels) == 3
    pyreadstat = pytest.importorskip("pyreadstat")
    df, meta = pyreadstat.read_dta(out, user_missing=True)
    assert df["KIDS"].tolist()[1:4] == ["a", "b", "b"]
    assert meta.variable_value_labels["KIDS"] == {0: "(0) None", "a": "(98) DK", "b": "(99) Not ascertained"}
