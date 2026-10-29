"""Build the blinded judging bundles described in rubric.md.

    python docs/judging/bundle.py OTHERS OUT SEED

OTHERS holds the pinned sources of the other libraries (one directory per
library, as named below); OUT receives one prompt file per pair and
`pairs.json` with the coin flips. Needs R (for Rd to text), the
benchmark Python environment (pandas and pyreadstat docstrings) and a
checkout of this repository at the commit being judged.
"""

import ast
import glob
import inspect
import json
import os
import random
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

OURS = {
    "R": ("docs/r.md", "rd:r/dtatools/man/*.Rd"),
    "Python": ("docs/python.md", "pydoc:python/dta_parser"),
    "Julia": ("docs/julia.md", "jldoc:julia/DtaParser/src"),
    "TypeScript": ("docs/typescript.md", "tsdoc:js/src"),
}
OUR_NAMES = ["@jbearak/dta-parser", "jbearak/dta-parser", "DtaParser.jl", "DtaParser", "dta-parser",
             "dta_parser", "dtatools"]

# Rubric's common/ours-only table, as task lists: the table itself names
# the libraries, so the judges get only the list.
COMMON = {"R": range(1, 10), "Python": range(1, 10), "Julia": range(1, 10), "TypeScript": [1, 2, 4, 5, 6, 8, 9]}

PAIRS = [
    ("R", "haven", ["haven"]),
    ("R", "readstata13", ["readstata13"]),
    ("Python", "pandas", []),  # pandas is the table type in both bundles
    ("Python", "pyreadstat", ["pyreadstat"]),
    ("Julia", "ReadStatTables", ["ReadStatTables.jl", "ReadStatTables"]),
    ("TypeScript", "statfmt", ["@irbisadm/statfmt", "irbisadm/statfmt", "statfmt"]),
]


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def rd_text(path):
    out = subprocess.run(["R", "CMD", "Rdconv", "-t", "txt", path], capture_output=True, text=True, check=True)
    return out.stdout


def py_docstrings(package_dir):
    """Docstrings of the public names in `__all__`, from the source."""
    parts = []
    for path in sorted(glob.glob(os.path.join(package_dir, "*.py"))):
        tree = ast.parse(read(path))
        for node in tree.body:
            if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and not node.name.startswith("_"):
                doc = ast.get_docstring(node)
                if doc:
                    parts.append(f"### {node.name}\n\n{doc}\n")
                if isinstance(node, ast.ClassDef):
                    for sub in node.body:
                        if isinstance(sub, ast.FunctionDef) and not sub.name.startswith("_"):
                            doc = ast.get_docstring(sub)
                            if doc:
                                parts.append(f"### {node.name}.{sub.name}\n\n{doc}\n")
    return "\n".join(parts)


def jl_docstrings(src_dir):
    """Every triple-quoted docstring and the line it documents."""
    parts = []
    for path in sorted(glob.glob(os.path.join(src_dir, "*.jl"))):
        for m in re.finditer(r'^"""\n(.*?)\n"""\n([^\n]*)', read(path), re.S | re.M):
            parts.append(f"### {m.group(2).strip()}\n\n{m.group(1)}\n")
    return "\n".join(parts)


def ts_docs(src_dir):
    """Every /** ... */ comment and the declaration after it."""
    parts = []
    for path in sorted(glob.glob(os.path.join(src_dir, "*.ts"))):
        for m in re.finditer(r"/\*\*(.*?)\*/\s*\n([^\n]*)", read(path), re.S):
            body = "\n".join(re.sub(r"^\s*\* ?", "", line) for line in m.group(1).strip().splitlines())
            parts.append(f"### {m.group(2).strip()}\n\n{body}\n")
    return "\n".join(parts)


def reference(spec):
    kind, arg = spec.split(":", 1)
    if kind == "rd":
        return "\n".join(f"===== {os.path.basename(p)} =====\n{rd_text(p)}"
                         for p in sorted(glob.glob(os.path.join(REPO, arg))))
    if kind == "pydoc":
        return py_docstrings(os.path.join(REPO, arg))
    if kind == "jldoc":
        return jl_docstrings(os.path.join(REPO, arg))
    return ts_docs(os.path.join(REPO, arg))


def ours(language):
    page, ref = OURS[language]
    files = ["README.md"] + sorted(os.path.relpath(p, REPO) for p in glob.glob(os.path.join(REPO, "docs/guide/*.md")))
    files.append(page)
    parts = [f"===== {f} =====\n{read(os.path.join(REPO, f))}" for f in files]
    parts.append(f"===== API reference =====\n{reference(ref)}")
    return "\n\n".join(parts)


def py_live_docs(objects):
    import importlib
    parts = []
    for dotted in objects:
        module, attr = dotted.split(":")
        obj = importlib.import_module(module)
        for name in attr.split("."):
            obj = getattr(obj, name)
        parts.append(f"### {dotted.replace(':', '.')}\n\n{inspect.getdoc(obj)}\n")
    return "\n".join(parts)


def other(name, root):
    d = os.path.join(root, name)
    if name == "haven":
        files = ["README.md", "vignettes/semantics.Rmd"]
        rds = ["read_dta", "labelled", "tagged_na", "as_factor", "zap_labels"]
    elif name == "readstata13":
        files = ["README.md", "vignettes/readstata13_basic_manual.Rmd"]
        rds = ["read.dta13", "save.dta13", "get.label", "get.label.name", "get.label.tables", "set.label",
               "varlabel"]
    if name in ("haven", "readstata13"):
        parts = [f"===== {f} =====\n{read(os.path.join(d, f))}" for f in files]
        parts += [f"===== man/{r}.Rd =====\n{rd_text(os.path.join(d, 'man', r + '.Rd'))}" for r in rds]
    elif name == "pandas":
        parts = [f"===== user guide: Stata format =====\n{read(os.path.join(d, 'stata.rst'))}",
                 "===== API reference =====\n" + py_live_docs([
                     "pandas:read_stata", "pandas:DataFrame.to_stata", "pandas.io.stata:StataReader",
                     "pandas.io.stata:StataWriter117"])]
    elif name == "pyreadstat":
        parts = [f"===== README.md =====\n{read(os.path.join(d, 'README.md'))}",
                 "===== API reference =====\n" + py_live_docs([
                     "pyreadstat:read_dta", "pyreadstat:write_dta", "pyreadstat:set_value_labels",
                     "pyreadstat:read_file_in_chunks"])]
    elif name == "ReadStatTables":
        files = ["README.md", "docs/src/index.md"] + sorted(
            os.path.relpath(p, d) for p in glob.glob(os.path.join(d, "docs/src/man/*.md")))
        parts = [f"===== {f} =====\n{read(os.path.join(d, f))}" for f in files]
    elif name == "statfmt":
        pkg = os.path.join(d, "package")
        dts = sorted(glob.glob(os.path.join(pkg, "dist", "*.d.ts")) + glob.glob(os.path.join(pkg, "dist", "stata", "*.d.ts")))
        parts = [f"===== README.md =====\n{read(os.path.join(pkg, 'README.md'))}"]
        parts += [f"===== {os.path.relpath(p, pkg)} =====\n{read(p)}" for p in dts]
    return "\n\n".join(parts)


CODE = re.compile(r"(```.*?```|`[^`\n]*`|^(?: {4}|\t).*$)", re.S | re.M)


def blind(text, names, letter):
    """Replace `names` by `letter` outside code blocks and code spans."""
    pattern = re.compile("|".join(re.escape(n) for n in sorted(names, key=len, reverse=True)), re.I)
    pieces = CODE.split(text)
    for i in range(0, len(pieces), 2):
        pieces[i] = pattern.sub(letter, pieces[i])
    return "".join(pieces)


def section(text, start, stop):
    return text[text.index(start):text.index(stop)]


def main(root, out, seed):
    rubric = read(os.path.join(REPO, "docs/judging/rubric.md"))
    instructions = "\n".join([
        section(rubric, "## The ten tasks", "## Common and ours-only tasks"),
        section(rubric, "## Scores", "## Pass rule"),
    ])
    rng = random.Random(seed)
    os.makedirs(out, exist_ok=True)
    flips = []
    for language, name, names in PAIRS:
        ours_first = rng.random() < 0.5
        our_letter, their_letter = ("Library A", "Library B") if ours_first else ("Library B", "Library A")
        mine = blind(blind(ours(language), OUR_NAMES, our_letter), names, their_letter) if names else \
            blind(ours(language), OUR_NAMES, our_letter)
        theirs = blind(blind(other(name, root), names, their_letter), OUR_NAMES, our_letter) if names else \
            other(name, root)
        a, b = (mine, theirs) if ours_first else (theirs, mine)
        prompt = (
            f"You are judging the documentation of two {language} libraries that read and write Stata .dta "
            "files, called Library A and Library B. Judge only from the text below; do not use outside "
            "knowledge of any library, and do not run code or look anything up.\n\n"
            f"The tasks common to both libraries are {', '.join(map(str, COMMON[language]))}; the others are "
            "scored too but reported separately.\n\n"
            + instructions
            + "\n## What to return\n\nFor each library (A, B) and each of the ten tasks, give the four scores "
            "(findability, correctness, completeness, clarity), each 0 to 3, and one or two sentences of reason "
            "for every score below 3. Then a table of task scores (mean of the four) and each library's total "
            "over the common tasks. Start with a JSON block:\n"
            '```json\n{"A": {"1": [F, Co, Cm, Cl], ...}, "B": {...}}\n```\n\n'
            f"# Bundle: Library A\n\n{a}\n\n# Bundle: Library B\n\n{b}\n"
        )
        path = os.path.join(out, f"{language.lower()}-{name}.md")
        with open(path, "w", encoding="utf-8") as f:
            f.write(prompt)
        flips.append({"language": language, "other": name, "ours": "A" if ours_first else "B",
                      "prompt": os.path.basename(path), "chars": len(prompt)})
    commit = subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    with open(os.path.join(out, "pairs.json"), "w") as f:
        json.dump({"seed": seed, "commit": commit, "pairs": flips}, f, indent=2)
    print(json.dumps(flips, indent=2))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]))
