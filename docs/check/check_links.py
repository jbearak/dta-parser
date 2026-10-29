"""Check the relative links and anchors in the Markdown documentation.

    python3 docs/check/check_links.py

Looks at README.md, CONTRIBUTING.md and every .md file under docs/ and
in the package directories (js/, python/, r/dtatools/). A link to a
file must name one that exists; a link with #anchor must name a heading
of the target (or of the same file), using GitHub's anchor rules.
Links to http(s) and mailto are not fetched. Exits 1 on any broken
link, listing each.
"""

import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LINK = re.compile(r"(?<!!)\[(?:[^\]\[]|\[[^\]]*\])*\]\(([^()\s]+)(?:\s+\"[^\"]*\")?\)|!\[[^\]]*\]\(([^()\s]+)\)")
FENCE = re.compile(r"^(`{3,}|~{3,})")


def files():
    out = [ROOT / "README.md", ROOT / "CONTRIBUTING.md"]
    out += sorted((ROOT / "docs").rglob("*.md"))
    for sub in ("js", "python", "r/dtatools"):
        out += sorted(p for p in (ROOT / sub).glob("*.md"))
    return [p for p in out if p.exists()]


def prose(text):
    """The lines of `text` outside fenced code blocks, with inline code removed."""
    out = []
    fence = None
    for line in text.split("\n"):
        m = FENCE.match(line)
        if fence is None and m:
            fence = m.group(1)
            out.append("")
            continue
        if fence is not None:
            if line.startswith(fence):
                fence = None
            out.append("")
            continue
        out.append(re.sub(r"`[^`]*`", "", line))
    return out


def slug(heading):
    """GitHub's anchor for a heading."""
    text = re.sub(r"`([^`]*)`", r"\1", heading.strip().lower())
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    kept = []
    for ch in text:
        cat = unicodedata.category(ch)
        if ch in " -_" or cat[0] in "LN":
            kept.append(ch)
    return "".join(kept).replace(" ", "-")


def anchors(path, cache={}):
    if path not in cache:
        seen = {}
        names = set()
        text = path.read_text(encoding="utf-8")
        fence = None
        for line in text.split("\n"):
            m = FENCE.match(line)
            if fence is None and m:
                fence = m.group(1)
                continue
            if fence is not None:
                if line.startswith(fence):
                    fence = None
                continue
            h = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
            if h:
                base = slug(h.group(1))
                n = seen.get(base, 0)
                seen[base] = n + 1
                names.add(base if n == 0 else f"{base}-{n}")
        for m in re.finditer(r'<a\s+(?:name|id)="([^"]+)"', text):
            names.add(m.group(1))
        cache[path] = names
    return cache[path]


def main():
    broken = []
    for path in files():
        for number, line in enumerate(prose(path.read_text(encoding="utf-8")), 1):
            for m in LINK.finditer(line):
                target = m.group(1) or m.group(2)
                if re.match(r"^(https?:|mailto:)", target):
                    continue
                file_part, _, anchor = target.partition("#")
                dest = path if not file_part else (path.parent / file_part).resolve()
                where = f"{path.relative_to(ROOT)}:{number}: {target}"
                if not dest.exists():
                    broken.append(f"{where} (no such file)")
                elif anchor and dest.suffix == ".md" and anchor not in anchors(dest):
                    broken.append(f"{where} (no such heading)")
    for b in broken:
        print(b)
    print(f"{len(files())} files checked, {len(broken)} broken links")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
