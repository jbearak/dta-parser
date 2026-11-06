"""Read and write Stata .dta files with pandas, keeping `.a` to `.z`.

Every name is loaded when first used, so `import dta_parser._native`
(which datakit does) runs no pandas code. The dtype `dta[...]` is
registered with pandas as soon as both are imported, in either order, so
`pd.Series(..., dtype="dta[double]")` works as it did when this module
imported pandas itself.
"""

import importlib
import importlib.abc
import importlib.util
import sys

# Each public name and the submodule it lives in.
_NAMES = {
    "MissingValue": "missing",
    "DtaArray": "_array",
    "DtaDtype": "_array",
    "missing_codes": "_array",
    "read_dta": "_read",
    "read_meta": "_read",
    "dta_key": "_array",
    "dta_keys": "_array",
    "write_dta": "_write",
}

# Moved to datakit in 0.3 (docs/migration.md, "dta_parser 0.2 to 0.3").
_MOVED = {
    "read_parquet": "datakit.read_parquet",
    "write_parquet": "datakit.save_parquet",
    "read_fixed_width": "datakit.read_fixed_width",
    "FixedWidthWarning": "datakit.FixedWidthWarning",
}

__all__ = sorted([*_NAMES, "missing"])


def __getattr__(name):
    if name == "missing":
        return importlib.import_module(".missing", __name__)
    if name in _NAMES:
        value = getattr(importlib.import_module("." + _NAMES[name], __name__), name)
        globals()[name] = value
        return value
    if name in _MOVED:
        raise AttributeError(
            f"dta_parser.{name} moved to {_MOVED[name]} in dta_parser 0.3, with polars frames; "
            "install it with pip install ./python/datakit (docs/migration.md)"
        )
    raise AttributeError(f"module 'dta_parser' has no attribute {name!r}")


def __dir__():
    return __all__


class _AfterPandas(importlib.abc.MetaPathFinder):
    """Registers `dta[...]` with pandas once pandas is imported. It
    wraps the loader of the spec found for pandas, and leaves
    `sys.meta_path` once pandas has run (a `find_spec` alone, as polars
    makes to see whether pandas is installed, imports nothing)."""

    def __init__(self):
        self._busy = False

    def find_spec(self, name, path, target=None):
        if name != "pandas" or self._busy:
            return None
        self._busy = True
        try:
            spec = importlib.util.find_spec(name)
        finally:
            self._busy = False
        if spec is None or spec.loader is None:
            return spec
        spec.loader = _RegisterAfter(spec.loader, self)
        return spec


class _RegisterAfter(importlib.abc.Loader):
    def __init__(self, loader, finder):
        self._loader, self._finder = loader, finder

    def create_module(self, spec):
        return self._loader.create_module(spec)

    def exec_module(self, module):
        self._loader.exec_module(module)
        if self._finder in sys.meta_path:
            sys.meta_path.remove(self._finder)
        importlib.import_module(__name__ + "._array")


if "pandas" in sys.modules:
    from . import _array  # noqa: E402,F401  (registers dta[...] with pandas)
else:
    sys.meta_path.insert(0, _AfterPandas())
