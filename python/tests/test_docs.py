"""The documentation's Python examples run, and every export is documented.

Each ```python block of README.md, docs/guide/*.md and docs/python.md
runs, in order, in one namespace per file, in a fresh temporary
directory. Blocks whose info string says `norun` are skipped. The docs
live in the repository; outside a checkout these tests skip.
"""

import contextlib
import inspect
import io
import re
from pathlib import Path

import pytest

import dta_parser

ROOT = Path(__file__).resolve().parents[2]
PAGE = ROOT / "docs" / "python.md"
pytestmark = pytest.mark.skipif(not PAGE.exists(), reason="docs/python.md is not here")


def doc_files():
    if not PAGE.exists():
        return []
    return [ROOT / "README.md", *sorted((ROOT / "docs" / "guide").glob("*.md")), PAGE]


def code_blocks(path, lang):
    """(line, code) of each block of `lang` in a Markdown file."""
    lines = path.read_text(encoding="utf-8").split("\n")
    out = []
    i = 0
    while i < len(lines):
        m = re.match(r"^(`{3,})\s*([A-Za-z]*)(.*)$", lines[i])
        if not m:
            i += 1
            continue
        end = i + 1
        while end < len(lines) and not lines[end].startswith(m.group(1)):
            end += 1
        if m.group(2) == lang and "norun" not in m.group(3):
            out.append((i + 1, "\n".join(lines[i + 1:end])))
        i = end + 1
    return out


@pytest.mark.parametrize("path", doc_files(), ids=lambda p: str(p.relative_to(ROOT)))
def test_examples_run(path, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    namespace = {"__name__": "__docs__"}
    for line, code in code_blocks(path, "python"):
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                exec(compile(code, f"{path.name}:{line}", "exec"), namespace)
        except Exception as e:
            pytest.fail(f"{path.name}:{line}: {type(e).__name__}: {e}")


def test_every_export_is_documented():
    page = PAGE.read_text(encoding="utf-8")
    for name in dta_parser.__all__:
        obj = getattr(dta_parser, name)
        assert inspect.getdoc(obj), f"{name} has no docstring"
        assert f"`{name}" in page or f".{name}" in page, f"docs/python.md does not mention {name}"
