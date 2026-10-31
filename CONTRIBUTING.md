# Contributing

This repository holds one implementation of the `.dta` format, in Rust,
and four packages built on it. This page says how to build and test
each part, how the documentation is checked, and the rules every change
follows.

## Rules that come first

These come from [AGENTS.md](AGENTS.md) and apply to every change, by
people and by coding agents alike:

- Stata is not used: not run, not installed, and none of its files
  (ado files, help files, example datasets) are read or copied.
- Expected values in tests come only from open-source readers (haven,
  ReadStat, pandas, pyreadstat, readstata13, ReadStatTables) and never
  from output Stata produced. [ADR 0005](docs/adr/0005-oracles.md) and
  [ADR 0006](docs/adr/0006-fixture-sources.md) explain this.
- Test files are made with this library's writer, or with haven, pandas
  or ReadStat from data you create. A few old releases come from
  open-source projects' test suites, with their licences and credit
  (`compat/fixtures/`). No sample `.dta` file is added for the docs.
- Facts about the format come from general knowledge and open-source
  projects' code and documentation, written in your own words; never
  from official Stata documentation.
- Nothing is published to npm, PyPI, CRAN or the Julia registry without
  the maintainer's say-so.

## Layout

| path | what | language |
|---|---|---|
| `crates/dta` | the format: reader (releases 104 to 119) and release 118 writer | Rust |
| `crates/dta-ffi` | the WebAssembly interface for the npm package, and the C interface (`include/dta.h`) for Julia | Rust |
| `r/dtaparser` | the R package for standard R types; the bridge to the core is in its `src/rust` | R, Rust, C |
| `r/dtatools` | the R package with Stata's rules; reads and writes through dtaparser ([ADR 0016](docs/adr/0016-dtaparser-under-dtatools.md)) | R, C |
| `python` | the Python package, a PyO3 extension | Python, Rust |
| `julia/DtaParser` | the Julia package, over the C interface | Julia |
| `js` | the npm package, over the WebAssembly module | TypeScript |
| `compat` | fixtures and what other readers make of them | |
| `bench` | benchmarks | |
| `docs` | user documentation, [decisions](docs/adr/) and [plans](docs/plans/) | Markdown |

Decisions that shape the code are recorded as ADRs in `docs/adr/`;
read the ones for the part you change. Larger work starts as a plan in
`docs/plans/`.

## Build and test

You need stable Rust (from [rustup.rs](https://rustup.rs)). Each part
also needs its language. The commands match what CI runs
(`.github/workflows/ci.yml`), from the repository root.

**Rust core.**

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

**npm package** (Node 24 or later, and the WebAssembly target:
`rustup target add wasm32-unknown-unknown`):

```sh
scripts/build-wasm.sh
cd js && npm ci && npm run build && npm test
```

**R packages** (R 4.2 or later, with testthat, haven, readstata13 and
dplyr for the tests). dtatools imports dtaparser, so install dtaparser
first:

```sh
R CMD INSTALL r/dtaparser
R CMD INSTALL r/dtatools
Rscript -e 'testthat::test_dir("r/dtaparser/tests/testthat", package = "dtaparser", load_package = "installed")'
Rscript -e 'testthat::test_dir("r/dtatools/tests/testthat", package = "dtatools", load_package = "installed")'
```

`scripts/build-r-package.sh` makes the source tarballs that CI
installs; dtaparser's carries its own copy of the Rust core.

**Python package** (Python 3.10 or later):

```sh
pip install maturin pytest pyreadstat
pip install ./python
python -m pytest python/tests
```

Run pytest from the repository root, not from `python/`, or Python
imports the source directory instead of the installed package.

**Julia package** (Julia 1.10 or later):

```sh
julia --project=julia/DtaParser -e 'using Pkg; Pkg.instantiate(); Pkg.build(); Pkg.test()'
```

`Pkg.build` runs cargo to build `crates/dta-ffi` and copies the library
into `julia/DtaParser/deps/usr/lib`.

## Documentation

User documentation lives in `README.md`, `docs/guide/` (concepts, for
every language) and one page per language (`docs/r.md`,
`docs/python.md`, `docs/julia.md`, `docs/typescript.md`). The API
reference is in the code: roxygen comments (R), docstrings (Python and
Julia) and TSDoc (TypeScript).

### Every example runs

Each language's test suite runs that language's code blocks from
`README.md`, `docs/guide/*.md` and its own page:

| language | test | blocks |
|---|---|---|
| R | `r/dtatools/tests/testthat/test-docs.R` | ` ```r ` |
| Python | `python/tests/test_docs.py` | ` ```python ` |
| Julia | `julia/DtaParser/test/docs.jl` | ` ```julia ` |
| TypeScript | `js/test/docs.test.mjs` | ` ```ts ` and ` ```js ` |

The blocks of one file run in order in a fresh temporary directory, so
a later block can read a file an earlier one wrote. In R, Python and
Julia they share one session per file; in TypeScript each block has its
own scope, and the import lines of all blocks are merged at the top.
Every page starts with a block that writes the file the rest read; no
`.dta` file is committed for the docs.

Write the output a reader should expect as a comment
(`# "Monthly income"`), and check it by running the block yourself; the
tests check that blocks run, not what they print.

A block that cannot run in a test (installation) gets `norun` after its
language: ` ```r norun `. Use it only for installation, and use ` ```sh `
for shell commands, which never run.

### Every export is documented

The same tests fail when an exported function has no help page (R),
docstring (Python, Julia) or TSDoc comment (TypeScript), or is not
mentioned on its language page. When you add an export, document it in
both places.

### R help pages

Each package's `man/` is generated from the roxygen comments in its
`R/`; do not edit it by hand. After changing a comment, install the
package and regenerate the pages (roxygen2 8 or later):

```sh
R CMD INSTALL r/dtatools
Rscript -e 'roxygen2::roxygenise("r/dtatools", roclets = "rd", load_code = roxygen2::load_installed)'
```

The same commands with `r/dtaparser` regenerate dtaparser's.

`roclets = "rd"` leaves `NAMESPACE` alone; it is written by hand.

### Links

```sh
python3 docs/check/check_links.py
```

checks every relative link and `#anchor` in `README.md`,
`CONTRIBUTING.md` and the Markdown under `docs/`. CI runs it.

### Writing style

Plain, specific sentences. Say what a call does and what it returns, with
the exact names; prefer a short example over a paragraph. Use the terms
in [CONTEXT.md](CONTEXT.md) (release, storage type, missing code, value
label set, display format). Sentence-case headings.

### Judging

The documentation is compared with that of other Stata readers on a
rubric fixed in advance: [docs/judging/rubric.md](docs/judging/rubric.md).
Rounds and their transcripts go in `docs/judging/`.

## Commits and pull requests

Small commits, each one logical change, with a message that says what
changed and why. A pull request says what it changes and how it was
tested; CI must pass. Do not commit build output (`target/`,
`js/dist/`, `julia/DtaParser/deps/usr/`) or data files.
