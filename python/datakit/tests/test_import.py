"""Importing datakit: no pandas, and the ABI check (plan 0019,
"Native code stays in the format package")."""

import subprocess
import sys
import textwrap


def run(code):
    return subprocess.run([sys.executable, "-c", textwrap.dedent(code)], capture_output=True, text=True)


def test_import_datakit_does_not_import_pandas_or_pyarrow():
    r = run("""
        import sys, time
        t = time.perf_counter()
        import datakit
        print(time.perf_counter() - t)
        print("pandas" in sys.modules, "pyarrow" in sys.modules, "numpy" in sys.modules)
    """)
    assert r.returncode == 0, r.stderr
    seconds, loaded = r.stdout.splitlines()
    assert loaded.split()[:2] == ["False", "False"]
    print(f"import datakit: {float(seconds) * 1000:.0f} ms")


def test_dta_parser_loads_its_pandas_names_when_used():
    r = run("""
        import sys
        import dta_parser
        before = "pandas" in sys.modules
        dta_parser.read_dta
        print(before, "pandas" in sys.modules)
    """)
    assert r.stdout.split() == ["False", "True"], r.stderr


def test_a_mismatched_abi_stops_with_the_versions_and_the_reinstall():
    r = run("""
        import dta_parser._native as n
        n.ABI_VERSION = 99
        import datakit
    """)
    assert r.returncode != 0
    assert "ImportError: datakit 0.3.0 needs dta_parser's native functions at ABI version 1" in r.stderr
    assert "has ABI version 99" in r.stderr
    assert "pip install --force-reinstall ./python ./python/datakit" in r.stderr
    r = run("""
        import dta_parser._native as n
        del n.ABI_VERSION
        import datakit
    """)
    assert "has ABI version none" in r.stderr
