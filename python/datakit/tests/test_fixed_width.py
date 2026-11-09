"""read_fixed_width reads fixed-width text through a SAS setup file (plan
0009), into polars (plan 0019; moved from dta_parser's tests).

What each value should be follows from the setup text written here; the
converted file is also read with pandas and pyreadstat, which check the
letters, value labels and long labels independently.
"""

import glob
import os
import tempfile
import warnings

import polars as pl
import pytest

import datakit as dk
from conftest import tags
from dta_parser import _native

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


def no_warnings(fn, *args, **kw):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        return fn(*args, **kw)


def test_setup_mode(files):
    df, meta = no_warnings(dk.read_fixed_width, *files())
    assert df.columns == ["ID", "SEX", "KIDS"]
    assert df["ID"].to_list() == [1, 2, 3, 4, 5]
    assert df["ID"].dtype == pl.Int8
    assert df["KIDS"].is_null().to_list() == [False, True, True, True, False]
    assert df["KIDS"].dtype == pl.Int8 and meta._storage == {}
    assert meta.columns["SEX"].label == "R's sex"
    assert meta.columns["KIDS"].label == "k" * 200
    # 98 and 99 can no longer occur, so their labels are gone.
    assert meta.labels("KIDS") == {0: "(0) None"}


def test_tagged_mode(files):
    df, meta = dk.read_fixed_width(*files(), recodes="tagged")
    assert df["KIDS"].dtype == pl.Float64 and meta._storage == {"KIDS": pl.Int8}
    assert tags(df["KIDS"]) == [None, ".a", ".b", ".b", None]
    assert df["KIDS"].fill_nan(None).is_null().to_list() == [False, True, True, True, False]
    assert meta.value_labels["kidsf"] == {0: "(0) None", ".a": "(98) DK", ".b": "(99) Not ascertained"}
    df, _ = dk.read_fixed_width(*files(), recodes="tagged", letters=False)
    assert df["KIDS"].dtype == pl.Int8 and df["KIDS"].is_null().to_list() == [False, True, True, True, False]


def test_none_mode_and_bad_mode(files):
    df, _ = dk.read_fixed_width(*files(), recodes="none")
    assert df["KIDS"].to_list() == [2, 98, 99, 99, 0]
    with pytest.raises(ValueError, match='recodes is "setup", "tagged" or "none"'):
        dk.read_fixed_width(*files(), recodes="letters")


def test_columns_skip_n_max(files):
    df, meta = dk.read_fixed_width(*files(), columns=["KIDS", "ID"], skip=1, n_max=2)
    assert df.columns == ["KIDS", "ID"]
    assert list(meta.columns) == ["KIDS", "ID"]
    assert df["ID"].to_list() == [2, 3]


def test_warnings(files):
    setup = "PROC FORMAT; VALUE f 1-5='low';\nDATA; INPUT X 1;\n" + "\n".join(f"y{i} = x * 2;" for i in range(10))
    with pytest.warns(dk.FixedWidthWarning, match="3 more") as record:
        dk.read_fixed_width(*files(setup, "1\n2\n"))
    assert len(record[0].message.messages) == 11
    assert all(len(line) <= 102 for line in str(record[0].message).splitlines())


def test_errors_leave_no_temporary_files(files):
    before = set(glob.glob(os.path.join(tempfile.gettempdir(), "datakit*")))
    with pytest.raises(ValueError, match="setup line 2: INPUT form not supported"):
        dk.read_fixed_width(*files("DATA;\nINPUT X 1. ;", "1\n"))
    dk.read_fixed_width(*files())
    assert set(glob.glob(os.path.join(tempfile.gettempdir(), "datakit*"))) == before
    with pytest.raises(FileNotFoundError):
        dk.read_fixed_width("no such file.dat", files()[1])


def test_other_readers_read_the_tagged_file(files, tmp_path):
    out = str(tmp_path / "tagged.dta")
    data, setup = files()
    _native.fixed_width(data, [setup], out, "tagged", True)
    pd = pytest.importorskip("pandas")
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


# CDC's setups from 2006-2010 on put the PROC FORMAT step and the FORMAT
# statement each in a block comment; their lines end in CRLF until
# 2011-2013.
COMMENTED = [
    "/*-----------------------------------------------",
    " | PROC FORMAT:  creates user-defined formats; FORMAT: attaches them.",
    " | Sections for PROC FORMAT and FORMAT have been commented out.",
    " |----------------------------------------------*/",
    "* SAS PROC FORMAT;",
    "/*",
    "PROC FORMAT;",
    "VALUE sexf 1 = 'Boy' 2 = 'Girl' ;",
    "VALUE kidsf 0 = 'None' 98 = 'DK' ;",
    "QUIT;",
    "*/",
    "* SAS DATA, INFILE, INPUT STATEMENTS;",
    "DATA;",
    'INFILE "data-filename" LRECL=5;',
    "INPUT ID 1-2 SEX 3 KIDS 4-5 ;",
    "* SAS LABEL STATEMENT;",
    "LABEL ID = 'Case' SEX = 'Sex' KIDS = 'Kids' ;",
    "* SAS FORMAT STATEMENT;",
    "/*",
    "FORMAT",
    "   SEX sexf.",
    "   KIDS kidsf. ;",
    "*/",
    "RUN ;",
]
COMMENTED_DATA = ["01100", "02298"]


def write_crlf(path, lines):
    path.write_bytes("".join(line + "\r\n" for line in lines).encode())
    return str(path)


@pytest.fixture
def crlf(tmp_path):
    def make(setup=COMMENTED):
        return write_crlf(tmp_path / "x.dat", COMMENTED_DATA), write_crlf(tmp_path / "x.sas", setup)
    return make


def kids_labels(result):
    _, meta = result
    name = meta.columns["KIDS"].value_labels
    return meta.value_labels[name] if name else None


def test_commented_formats_are_read_unless_turned_off(crlf):
    df, meta = no_warnings(dk.read_fixed_width, *crlf(), recodes="none")
    assert kids_labels((df, meta)) == {0: "None", 98: "DK"}
    assert meta.value_labels["sexf"] == {1: "Boy", 2: "Girl"}
    off, off_meta = dk.read_fixed_width(*crlf(), recodes="none", commented_formats=False)
    assert kids_labels((off, off_meta)) is None
    assert off_meta.value_labels == {}
    assert off["KIDS"].to_list() == df["KIDS"].to_list() == [0, 98]
    assert off_meta.columns["KIDS"].label == "Kids"
    with pytest.raises(TypeError, match="True or False"):
        dk.read_fixed_width(*crlf(), commented_formats="yes")


def test_a_commented_proc_format_or_format_alone(crlf):
    only_proc = [line for i, line in enumerate(COMMENTED) if i not in (18, 22)]
    only_format = [line for i, line in enumerate(COMMENTED) if i not in (5, 10)]
    for setup in (only_proc, only_format):
        assert kids_labels(dk.read_fixed_width(*crlf(setup), recodes="none")) == {0: "None", 98: "DK"}
        assert kids_labels(dk.read_fixed_width(*crlf(setup), recodes="none", commented_formats=False)) is None


def test_a_comment_that_mentions_proc_format_stays_a_comment(crlf):
    # Read as code, each would end the DATA step before LABEL, or fail.
    for comment in ["/* PROC FORMAT: see the codebook; */", "/* PROC FORMAT; VALUE labels are below */",
                    "/* FORMAT statements: below; */"]:
        setup = COMMENTED[:15] + [comment] + COMMENTED[16:]
        _, meta = no_warnings(dk.read_fixed_width, *crlf(setup), recodes="none")
        assert meta.columns["KIDS"].label == "Kids"


def test_a_setup_in_several_files_reads_as_the_files_joined(tmp_path):
    # CDC's 2002 setups: the DATA step, LABEL, then PROC FORMAT and FORMAT.
    parts = [
        ["FILENAME datafile 'x.dat' ;", "DATA &dataset ;", "INFILE datafile LRECL=5;",
         "INPUT ID $ 1-2 SEX 3 KIDS 4-5 ;", "RUN;"],
        ["LABEL", " /* SECTION A */", '  ID = "RESPONDENT ID"', '  KIDS = "NUMBER OF KIDS"', "  ;"],
        ["PROC FORMAT;", 'VALUE SEXF 1 = "BOY" 2 = "GIRL" ;', 'VALUE KIDSF 98 = "DK" ;', "RUN;",
         "FORMAT SEX SEXF. KIDS KIDSF. ;", "RUN;"],
    ]
    paths = [write_crlf(tmp_path / f"{i}.sas", part) for i, part in enumerate(parts)]
    joined = write_crlf(tmp_path / "all.sas", parts[0] + parts[1] + parts[2])
    data = write_crlf(tmp_path / "x.dat", COMMENTED_DATA)
    files, files_meta = no_warnings(dk.read_fixed_width, data, paths, recodes="none")
    one, one_meta = dk.read_fixed_width(data, joined, recodes="none")
    assert files.equals(one) and files.schema == one.schema
    files_meta.timestamp = one_meta.timestamp
    assert files_meta == one_meta
    assert files_meta.value_labels["SEXF"] == {1: "BOY", 2: "GIRL"}
    assert files_meta.columns["KIDS"].label == "NUMBER OF KIDS"
    write_crlf(tmp_path / "1.sas", ["LABEL KIDS 3;"])
    with pytest.raises(ValueError, match="setup file 2 line 1: LABEL KIDS"):
        dk.read_fixed_width(data, paths)
    with pytest.raises(ValueError, match="one or more paths"):
        dk.read_fixed_width(data, [])


def test_quit_ends_a_proc_step_like_run(files):
    setup = "DATA; INPUT X 1;\nPROC FORMAT; VALUE f 1='one'; QUIT;\nFORMAT X f.;"
    _, meta = no_warnings(dk.read_fixed_width, *files(setup, "1\n2\n"), recodes="none")
    assert meta.value_labels["f"] == {1: "one"}
    assert meta.columns["X"].value_labels == "f"


def test_a_label_with_stray_quotes(tmp_path):
    setup = [
        "DATA; INPUT SALMX1 1 RING 2 C 3;",
        "LABEL",
        '  SALMX1 = "FLAG INDICATING WHETHER " SAME AS LAST MONTH" WAS ORIGINAL ANSWER"',
        '  RING = "EVER USED RING OR "NUVARING"?"',
        "  C 'no equals' ;",
    ]
    sas = write_crlf(tmp_path / "x.sas", setup)
    dat = write_crlf(tmp_path / "x.dat", ["123"])
    _, meta = no_warnings(dk.read_fixed_width, dat, sas)
    assert meta.columns["SALMX1"].label == 'FLAG INDICATING WHETHER " SAME AS LAST MONTH" WAS ORIGINAL ANSWER'
    assert meta.columns["RING"].label == 'EVER USED RING OR "NUVARING"?'
    assert meta.columns["C"].label == "no equals"
