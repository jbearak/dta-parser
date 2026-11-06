"""Build the blinded Parquet judging prompts described in parquet-rubric.md.

    python docs/judging/parquet_bundle.py OTHERS OUT SEED

OTHERS holds the pinned sources of the other libraries, one directory
per entry of SOURCES below; OUT receives one prompt file per pair and
`pairs.json` with the coin flips and the commits. Run it with a Python
that has pyarrow 26.0.1, pandas 3.1.1 and polars 2.1.0 installed (their
docstrings are read from the installed packages), with R on the path
(for Rd to text), from a checkout of this repository at the commit
being judged.
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bundle import jl_docstrings, py_live_docs, rd_text, read, section, ts_docs  # noqa: E402

# Fenced blocks, code spans and indented code lines. bundle.py's CODE lets
# an indented line run to the end of the text under re.S, which leaves
# everything after the first indented line unblinded; here an indented
# line ends at its newline.
CODE = re.compile(r"(```.*?```|`[^`\n]*`|^(?: {4}|\t)[^\n]*$)", re.S | re.M)

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# The sections of each language page that hold the Parquet material: the
# page's opening and contents, its Install section, the datakit section
# (Python, Julia), the Parquet section with all its subsections, and the
# Troubleshooting, Errors and API reference sections.
PAGE_SECTIONS = {
    "R": ["## Install", "## Plain R types: dtaparser", "## Parquet files", "## Troubleshooting",
          "## API reference"],
    "Python": ["## Install", "## datakit: Parquet, .dta and fixed-width files in polars", "## Parquet files",
               "## Troubleshooting", "## API reference"],
    "Julia": ["## Install", "## Datakit: Parquet and fixed-width text into DataFrames", "## Parquet files",
              "## Troubleshooting", "## API reference"],
    "TypeScript": ["## Install", "## Parquet files", "## Errors", "## Troubleshooting", "## API reference"],
}
PAGES = {"R": "docs/r.md", "Python": "docs/python.md", "Julia": "docs/julia.md", "TypeScript": "docs/typescript.md"}

OUR_NAMES = ["@jbearak/dta-parser", "jbearak/dta-parser", "dta-parser", "dta_parser", "DtaParser.jl", "DtaParser",
             "dtaparser", "dtatools", "Datakit.jl", "Datakit", "datakit"]

# (language, short name, names blinded in prose). polars is not blinded
# in its pair: it is the table type in both bundles, as pandas was in
# round 1 of rubric.md.
PAIRS = [
    ("R", "arrow", ["arrow"]),
    ("R", "nanoparquet", ["nanoparquet"]),
    ("Python", "pyarrow", ["PyArrow", "pyarrow"]),
    ("Python", "pandas", ["pandas"]),
    ("Python", "polars", []),
    ("Julia", "Parquet2", ["Parquet2.jl", "Parquet2"]),
    ("TypeScript", "hyparquet", ["hyparquet-writer", "hyparquet", "Hyperparam"]),
    ("TypeScript", "parquet-wasm", ["parquet-wasm", "parquet_wasm"]),
]

# Names matched case-sensitively, so that "arrow" (the R package) is
# blinded but "Arrow" (the format and project) is not.
CASE_SENSITIVE = {"arrow"}

# The rubric's supported-task table, as the tasks each library cannot do.
UNSUPPORTED = {
    "arrow": [10],
    "nanoparquet": [4, 10],
    "pyarrow": [10],
    "pandas": [4, 5, 10],
    "polars": [10],
    "Parquet2": [10],
    "hyparquet": [10],
    "parquet-wasm": [10],
}

# Where each library's pinned source lives under OTHERS, and the tag it
# was taken from (recorded with the round).
SOURCES = {
    "arrow": "arrow-r",
    "nanoparquet": "nanoparquet",
    "pyarrow": "arrow-py",
    "pandas": "pandas",
    "polars": "polars",
    "Parquet2": "Parquet2",
    "hyparquet": ["npm-hyparquet", "npm-hyparquet-writer"],
    "parquet-wasm": "npm-parquet-wasm",
}


def md_sections(text, headings):
    """The text before the first `## ` heading, then each named `## `
    section with its subsections, in page order."""
    lines = text.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.startswith("## ")]
    out = ["".join(lines[:starts[0]])]
    for k, i in enumerate(starts):
        if lines[i].rstrip("\n") in headings:
            end = starts[k + 1] if k + 1 < len(starts) else len(lines)
            out.append("".join(lines[i:end]))
    found = {lines[i].rstrip("\n") for i in starts}
    missing = [h for h in headings if h not in found]
    if missing:
        raise SystemExit(f"headings not found: {missing}")
    return "".join(out)


def py_public_docstrings(package_dir):
    """Docstrings of the names in the package's `__all__`, read from the
    source: the module docstring, then each function and class with its
    public methods and properties."""
    init = read(os.path.join(package_dir, "__init__.py"))
    tree = ast.parse(init)
    public = set()
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", None) == "__all__" for t in node.targets):
            public = set(ast.literal_eval(node.value))
    parts = [f"### module\n\n{ast.get_docstring(tree)}\n"]
    for path in sorted(glob.glob(os.path.join(package_dir, "*.py"))):
        for node in ast.parse(read(path)).body:
            if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in public:
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


def our_reference(language):
    if language == "R":
        pages = [f"r/datakit/man/{n}.Rd" for n in ("read_parquet", "read_parquet_info", "save_parquet")]
        pages += [f"r/dtaparser/man/{n}.Rd" for n in ("val_labels", "with_labels", "na_tag", "drop_labels",
                                                       "missing_rank")]
        return "\n".join(f"===== {p} =====\n{rd_text(os.path.join(REPO, p))}" for p in pages)
    if language == "Python":
        return py_public_docstrings(os.path.join(REPO, "python/datakit/datakit"))
    if language == "Julia":
        return jl_docstrings(os.path.join(REPO, "julia/Datakit/src"))
    return ts_docs(os.path.join(REPO, "js/src"))


def ours(language):
    parts = [f"===== README.md =====\n{read(os.path.join(REPO, 'README.md'))}",
             f"===== docs/parquet.md =====\n{read(os.path.join(REPO, 'docs/parquet.md'))}"]
    page = PAGES[language]
    parts.append(f"===== {page} (its Parquet sections) =====\n"
                 + md_sections(read(os.path.join(REPO, page)), PAGE_SECTIONS[language]))
    parts.append(f"===== API reference =====\n{our_reference(language)}")
    return "\n\n".join(parts)


def files(d, names):
    return [f"===== {n} =====\n{read(os.path.join(d, n))}" for n in names]


def rds(d, names):
    return [f"===== man/{n}.Rd =====\n{rd_text(os.path.join(d, 'man', n + '.Rd'))}" for n in names]


def py_class_docs(dotted):
    """A class's docstring and those of its public methods and properties."""
    import importlib
    module, attr = dotted.split(":")
    cls = getattr(importlib.import_module(module), attr)
    parts = [f"### {module}.{attr}\n\n{inspect.getdoc(cls)}\n"]
    for name, member in vars(cls).items():
        if name.startswith("_"):
            continue
        doc = inspect.getdoc(member.fget if isinstance(member, property) else member)
        if doc:
            parts.append(f"### {module}.{attr}.{name}\n\n{doc}\n")
    return "\n".join(parts)


def polars_page(d, rel):
    """A polars user guide page with its `{{code_block(...)}}` snippets
    filled in from `docs/source/src/python/`."""
    text = read(os.path.join(d, "docs/source", rel))

    def fill(m):
        path, name = m.group(1), m.group(2)
        src = read(os.path.join(d, "docs/source/src/python", path + ".py"))
        body = re.search(rf"# --8<-- \[start:{name}\]\n(.*?)# --8<-- \[end:{name}\]", src, re.S).group(1)
        return f"```python\n{body}```"

    return re.sub(r"\{\{code_block\('([^']+)','([^']+)',\[[^\]]*\]\)\}\}", fill, text)


def other(name, root):
    src = SOURCES[name]
    if name == "arrow":
        d = os.path.join(root, src, "r")
        parts = files(d, ["README.md", "vignettes/install.Rmd", "vignettes/read_write.Rmd", "vignettes/metadata.Rmd"])
        parts += rds(d, ["read_parquet", "write_parquet", "ParquetFileReader", "open_dataset", "schema"])
    elif name == "nanoparquet":
        d = os.path.join(root, src)
        parts = files(d, ["README.md", "vignettes/articles/list-columns.qmd", "vignettes/articles/benchmarks.qmd",
                          "vignettes/2025-06-03/_nanoparquet.qmd"])
        parts += rds(d, ["read_parquet", "write_parquet", "read_parquet_schema", "read_parquet_info",
                         "read_parquet_metadata", "parquet_options"])
    elif name == "pyarrow":
        d = os.path.join(root, src, "docs/source/python")
        parts = files(d, ["index.rst", "install.rst", "parquet/index.rst", "parquet/parquet.rst",
                          "parquet/parquet_type_handling.rst", "parquet/parquet_datasets.rst",
                          "parquet/parquet_encryption.rst"])
        parts.append("===== API reference =====\n"
                     + py_live_docs(["pyarrow.parquet:read_table", "pyarrow.parquet:write_table"])
                     + "\n" + py_class_docs("pyarrow.parquet:ParquetFile")
                     + "\n" + py_live_docs(["pyarrow.parquet:read_metadata", "pyarrow.parquet:read_schema"]))
    elif name == "pandas":
        d = os.path.join(root, src, "doc/source")
        io = read(os.path.join(d, "user_guide/io.rst"))
        start = io.index(".. _io.parquet:")
        stop = io.index(".. _io.orc:")
        parts = files(d, ["index.rst.template", "getting_started/install.rst"])
        parts.append(f"===== user_guide/io.rst: Parquet =====\n{io[start:stop]}")
        parts.append("===== API reference =====\n"
                     + py_live_docs(["pandas:read_parquet", "pandas:DataFrame.to_parquet"]))
    elif name == "polars":
        d = os.path.join(root, src)
        parts = [f"===== docs/source/{p} =====\n{polars_page(d, p)}"
                 for p in ["index.md", "user-guide/installation.md", "user-guide/io/parquet.md"]]
        parts.append("===== API reference =====\n" + py_live_docs([
            "polars:read_parquet", "polars:scan_parquet", "polars:read_parquet_schema",
            "polars:read_parquet_metadata", "polars:DataFrame.write_parquet"]))
    elif name == "Parquet2":
        d = os.path.join(root, src)
        parts = files(d, ["README.md"] + sorted(os.path.relpath(p, d) for p in glob.glob(os.path.join(d, "docs/src/*.md"))))
    elif name == "hyparquet":
        parts = []
        for pkg, modules in [
            ("npm-hyparquet", ["index", "read", "query", "scan", "metadata", "indexes", "utils", "node"]),
            ("npm-hyparquet-writer", ["index", "write", "write-rows", "parquet-writer", "schema", "bytewriter",
                                      "node"]),
        ]:
            d = os.path.join(root, pkg, "package")
            label = pkg[len("npm-"):]
            parts.append(f"===== {label}: README.md =====\n{read(os.path.join(d, 'README.md'))}")
            parts += [f"===== {label}: types/{m}.d.ts =====\n{read(os.path.join(d, 'types', m + '.d.ts'))}"
                      for m in modules]
            parts.append(f"===== {label}: src/types.d.ts =====\n{read(os.path.join(d, 'src/types.d.ts'))}")
    elif name == "parquet-wasm":
        d = os.path.join(root, src, "package")
        # The documentation site is TypeDoc built from these declarations.
        parts = files(d, ["README.md", "esm/parquet_wasm.d.ts"])
    else:
        raise ValueError(name)
    return "\n\n".join(parts)


def blind(text, names, letter):
    """Replace `names` (and their plurals) by `letter` outside code blocks
    and code spans, where no letter or digit adjoins them: in compounds
    such as `pyarrow-core` and in link anchors too."""
    if not names:
        return text
    alts = [re.escape(n) if n in CASE_SENSITIVE else f"(?i:{re.escape(n)})"
            for n in sorted(names, key=len, reverse=True)]
    pattern = re.compile(r"(?<![A-Za-z0-9])(?:" + "|".join(alts) + r")s?(?![A-Za-z0-9])")
    pieces = CODE.split(text)
    for i in range(0, len(pieces), 2):
        pieces[i] = pattern.sub(letter, pieces[i])
    return "".join(pieces)


def supported_text(name, letter_theirs, letter_ours):
    no = UNSUPPORTED[name]
    yes = [t for t in range(1, 12) if t not in no]
    return (f"{letter_ours} supports all eleven tasks. {letter_theirs} supports tasks "
            f"{', '.join(map(str, yes))}; it cannot do task{'s' if len(no) > 1 else ''} "
            f"{', '.join(map(str, no))}. Score every task for both libraries anyway; a task a library cannot "
            "do is scored on what its documentation says about it.\n\n")


def instructions():
    rubric = read(os.path.join(REPO, "docs/judging/parquet-rubric.md"))
    scores = read(os.path.join(REPO, "docs/judging/rubric.md"))
    defs = section(scores, "For each library and task, a judge gives four scores", "A library's **task score**")
    tasks = section(rubric, "## The eleven tasks", "## What each library supports")
    return (tasks + "\n## Scores\n\n"
            + defs.replace("For each library and task, a judge gives four scores from 0 to 3.",
                           "For each library and task, give four scores from 0 to 3. \"What the judge looks for\" "
                           "is the column of the task table above. Install (task 1) is scored on the install "
                           "documentation like every other task, not on whether the package is on a registry.")
            + "A library's **task score** is the mean of its four scores (0 to 3). Its **total** is the sum of "
            "its task scores over all eleven tasks.\n")


def main(root, out, seed):
    rng = random.Random(seed)
    os.makedirs(out, exist_ok=True)
    text = instructions()
    flips = []
    for language, name, names in PAIRS:
        ours_first = rng.random() < 0.5
        our_letter, their_letter = ("Library A", "Library B") if ours_first else ("Library B", "Library A")
        mine = blind(blind(ours(language), OUR_NAMES, our_letter), names, their_letter)
        theirs = blind(blind(other(name, root), names, their_letter), OUR_NAMES, our_letter)
        a, b = (mine, theirs) if ours_first else (theirs, mine)
        prompt = (
            f"You are judging the Parquet documentation of two {language} libraries that read and write "
            "Parquet files, called Library A and Library B. Judge only from the text below; do not use outside "
            "knowledge of any library, and do not run code or look anything up. One library's documentation "
            "discusses Stata's value labels and missing values; score the tasks, and do not try to guess which "
            "library is which.\n\n"
            + supported_text(name, their_letter, our_letter)
            + text
            + "\n## What to return\n\nFor each library (A, B) and each of the eleven tasks, give the four scores "
            "(findability, correctness, completeness, clarity), each 0 to 3, and one or two sentences of reason "
            "for every score below 3. Then a table of task scores (mean of the four) and each library's total "
            "over all eleven tasks. Start your reply with this JSON block, filled in, with all eleven tasks for "
            "both libraries:\n"
            '```json\n{"A": {"1": [F, Co, Cm, Cl], "2": [...], ..., "11": [...]}, "B": {...}}\n```\n\n'
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
        f.write("\n")
    print(json.dumps(flips, indent=2))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]))
