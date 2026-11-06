"""The documentation's examples run, and every export is documented.

Each ```python block of docs/python.md (all of it: its datakit part uses
the example file its first part makes) and of python/datakit/README.md
runs, in order, in one namespace per file, in a fresh temporary
directory. Blocks whose info string says `norun` are skipped. Every
export has a docstring that links to the guide, and the guide names it.
"""

import contextlib
import inspect
import io
import re

import pytest

import datakit as dk
from conftest import ROOT

PAGE = ROOT / "docs" / "python.md"
README = ROOT / "python" / "datakit" / "README.md"
GUIDE = "https://github.com/jbearak/dta-parser/blob/main/docs/python.md#"
pytestmark = pytest.mark.skipif(not PAGE.exists(), reason="docs/python.md is not here")


def code_blocks(path):
    lines = path.read_text(encoding="utf-8").split("\n")
    out, i = [], 0
    while i < len(lines):
        m = re.match(r"^(`{3,})\s*([A-Za-z]*)(.*)$", lines[i])
        if not m:
            i += 1
            continue
        end = i + 1
        while end < len(lines) and not lines[end].startswith(m.group(1)):
            end += 1
        if m.group(2) == "python" and "norun" not in m.group(3):
            out.append((i + 1, "\n".join(lines[i + 1:end])))
        i = end + 1
    return out


@pytest.mark.parametrize("path", [PAGE, README], ids=lambda p: str(p.relative_to(ROOT)))
def test_examples_run(path, tmp_path, monkeypatch):
    pytest.importorskip("pandas")
    monkeypatch.chdir(tmp_path)
    namespace = {"__name__": "__docs__"}
    for line, code in code_blocks(path):
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                exec(compile(code, f"{path.name}:{line}", "exec"), namespace)
        except Exception as e:
            pytest.fail(f"{path.name}:{line}: {type(e).__name__}: {e}")


def anchors(text):
    """GitHub's anchors of a Markdown page's headings."""
    out = set()
    for line in text.split("\n"):
        m = re.match(r"^#+ (.*)$", line)
        if m:
            a = re.sub(r"[^\w\- ]", "", m.group(1).strip().lower()).replace(" ", "-")
            out.add(a)
    return out


def test_every_export_is_documented_and_links_to_the_guide():
    page = PAGE.read_text(encoding="utf-8")
    known = anchors(page)
    for name in dk.__all__:
        obj = getattr(dk, name)
        assert f"`{name}" in page or f".{name}" in page, f"docs/python.md does not mention {name}"
        if name == "LETTERS":
            continue  # a polars dtype; the guide documents it
        doc = inspect.getdoc(obj)
        assert doc, f"{name} has no docstring"
        links = re.findall(re.escape(GUIDE) + r"([\w\-]+)", doc)
        assert links, f"{name}'s docstring does not link to the guide"
        for a in links:
            assert a in known, f"{name}'s docstring links to #{a}, which docs/python.md does not have"
