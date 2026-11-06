"""dta_parser's native module, which holds the Rust core datakit calls.

datakit is pure Python; the decoding and encoding are in dta_parser's
extension module, behind functions documented there as for datakit
only and versioned by `dta_parser._native.ABI_VERSION`. Importing it
runs dta_parser's `__init__`, which loads its pandas names lazily, so
pandas is not imported.
"""

from importlib import metadata

# The version of dta_parser's native functions this datakit was written
# against.
ABI = 1


def _installed(dist):
    try:
        return metadata.version(dist)
    except metadata.PackageNotFoundError:
        return "(unknown version)"


def _load():
    from . import __version__

    reinstall = ("reinstall both from one checkout of dta-parser: "
                 "pip install --force-reinstall ./python ./python/datakit")
    try:
        from dta_parser import _native as native
    except ImportError as e:
        raise ImportError(f"datakit {__version__} needs dta_parser 0.3, which could not be imported ({e}); "
                          f"{reinstall}") from e
    found = getattr(native, "ABI_VERSION", None)
    if found != ABI:
        have = "none" if found is None else found
        raise ImportError(
            f"datakit {__version__} needs dta_parser's native functions at ABI version {ABI}, but the "
            f"installed dta_parser {_installed('dta-parser')} has ABI version {have}; {reinstall}"
        )
    return native


native = _load()
