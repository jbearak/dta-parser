"""dta_parser 0.3: Parquet and fixed-width text moved to datakit (plan
0019), and the pandas names load when first used."""

import io
import subprocess
import sys

import pytest

import dta_parser as dp


@pytest.mark.parametrize("name, home", [("read_parquet", "datakit.read_parquet"),
                                        ("write_parquet", "datakit.save_parquet"),
                                        ("read_fixed_width", "datakit.read_fixed_width"),
                                        ("FixedWidthWarning", "datakit.FixedWidthWarning")])
def test_moved_names_say_where_they_went(name, home):
    with pytest.raises(AttributeError, match=f"dta_parser.{name} moved to {home} in dta_parser 0.3"):
        getattr(dp, name)
    assert name not in dp.__all__


def test_read_meta_of_a_parquet_file_says_to_use_datakit():
    with pytest.raises(ValueError, match="Parquet file; .*datakit.read_parquet_info"):
        dp.read_meta(io.BytesIO(b"PAR1" + bytes(20) + b"PAR1"))


def test_the_exports():
    assert dp.__all__ == ["DtaArray", "DtaDtype", "MissingValue", "dta_key", "dta_keys", "missing", "missing_codes",
                          "read_dta", "read_meta", "write_dta"]
    for name in dp.__all__:
        assert getattr(dp, name) is not None
    with pytest.raises(AttributeError, match="no attribute 'nope'"):
        dp.nope


def test_the_native_module_imports_without_pandas():
    r = subprocess.run([sys.executable, "-c", "import sys, dta_parser._native; print('pandas' in sys.modules)"],
                       capture_output=True, text=True)
    assert r.stdout.strip() == "False", r.stderr


@pytest.mark.parametrize("first", ["import pandas as pd, dta_parser as dp",
                                   "import dta_parser as dp, pandas as pd",
                                   "import dta_parser._native; import pandas as pd; import dta_parser as dp",
                                   # polars looks for pandas without importing it
                                   "import dta_parser as dp, importlib.util; importlib.util.find_spec('pandas'); "
                                   "import pandas as pd"])
def test_the_dtype_is_registered_whichever_comes_first(first):
    code = (f"{first}\n"
            "s = pd.Series([1.0, None], dtype='dta[double]')\n"
            "print(s.dtype)")
    r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
    assert r.stdout.strip() == "dta[double]", r.stderr


@pytest.mark.parametrize("old", ["StataArray", "StataDtype", "stata_key", "stata_keys"])
def test_the_old_names_are_gone(old):
    assert not hasattr(dp, old)
    assert old not in dp.__all__


def test_the_old_dtype_strings_are_not_registered():
    pd = pytest.importorskip("pandas")
    assert str(pd.Series([1.0, None], dtype="dta[byte]").dtype) == "dta[byte]"
    assert pd.api.types.pandas_dtype("dta") == dp.DtaDtype("double")
    for old in ("stata", "stata[byte]", "stata[int]", "stata[long]", "stata[float]", "stata[double]"):
        with pytest.raises(TypeError):
            pd.api.types.pandas_dtype(old)
