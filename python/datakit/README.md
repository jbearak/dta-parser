# datakit for Python

Data preparation in pandas that keeps Stata's labels and missing values
`.a` to `.z`. datakit reads Parquet files, Stata `.dta` files, and
fixed-width text with a SAS setup file into a pandas `DataFrame`, and
keeps a `Meta` beside it that holds what a pandas frame does not:
variable labels, value labels, display formats and notes. Every numeric
column with a missing value is a `DtaArray` (from `dta_parser`), which
keeps `.` and `.a` to `.z` in a code per row and compares them as
missing, as R's `NA` does. datakit saves both back as Parquet or `.dta`.
Its Parquet files carry the same `dta` profile R's and Julia's datakits
write, so data goes between the three languages with its labels and
letters; other tools read them as plain Parquet.

```python
import pandas as pd
import datakit as dk

df = pd.DataFrame({
    "id": [1, 2, 3],
    "income": pd.Series([2100.0, dk.tagged_na(".d"), dk.tagged_na(".r")], dtype="dta[double]"),
})
meta = dk.Meta(
    columns={"income": dk.Column(label="Monthly income", value_labels="why")},
    value_labels={"why": {".d": "Don't know", ".r": "Refused"}},
    rows=3,
)
dk.save_parquet(df, "survey.parquet", meta=meta)

df, meta = dk.read_parquet("survey.parquet")            # a tuple: the frame and its Meta
print(dk.na_tag(df["income"]).tolist())                 # [nan, '.d', '.r']
print(df[df["income"] == dk.tagged_na(".r")]["id"].tolist())   # [3]
print(df[df["income"] != 2100]["id"].tolist())          # []: a missing row is <NA>, and dropped
print(df["income"].mean())                              # 2100.0
print(meta.columns["income"].label)                     # Monthly income
```

Each letter is in its row's code, so it follows the row through
filtering, sorting, `merge`, `concat` and arithmetic, and `groupby`
keeps `.`, `.a` and `.b` apart. A comparison with a missing row is
`<NA>`, which `df[cond]` drops. The guide is
[docs/python.md](../../docs/python.md#datakit-parquet-dta-and-fixed-width-files-in-pandas);
the Parquet file is specified in [docs/parquet.md](../../docs/parquet.md).

## Install from a checkout

datakit is pure Python; the decoding and encoding are in `dta_parser`'s
compiled core, so install both from a checkout of this repository. You
need Python 3.10 or later, a Rust toolchain ([rustup.rs](https://rustup.rs))
and a C compiler:

    git clone https://github.com/jbearak/dta-parser
    pip install ./dta-parser/python ./dta-parser/python/datakit

That also installs pandas (2.2 or later) and numpy. Neither pyarrow nor
polars is needed. Neither package is on PyPI.

- **The name.** The distribution is `dta-datakit` and the import name is
  `datakit`. A different project already has `datakit` on PyPI, and the
  two cannot be installed in one environment, since both would be
  imported as `datakit`.
- **Versions.** datakit 0.4 needs `dta_parser` 0.4 from the same
  checkout. If `import datakit` stops with "needs dta_parser's native
  functions at ABI version 2", reinstall both:
  `pip install --force-reinstall ./python ./python/datakit`.

For development, from the repository root:

    pip install maturin pytest pyarrow duckdb
    (cd python && maturin build --release --out dist) && pip install python/dist/*.whl
    pip install -e python/datakit
    python -m pytest python/datakit/tests

Build `dta_parser` as a wheel rather than with `maturin develop`: an
editable `dta_parser` puts `python/` on the import path, where the
directory `python/datakit` hides the installed package. (With an
editable `dta_parser`, put `python/datakit` first on `PYTHONPATH`.)

## What it has

| function | does |
|---|---|
| `read_parquet`, `save_parquet`, `read_parquet_info` | Parquet files, and a file's footer alone |
| `read_dta`, `save_dta` | `.dta` files (releases 104 to 119 read, 118 written), the columns `dta_parser.read_dta` gives |
| `read_fixed_width` | fixed-width text through its SAS setup file, such as the NSFG's `.dat` files |
| `tagged_na`, `na_tag`, `is_tagged_na` | make `.a` to `.z`, and read them from a column |
| `Meta`, `Column`, `ParquetInfo`, `LETTERS` | what a read returns beside the frame |

There are no Stata-style assignment helpers:
`df.loc[cond, "x"] = value` (with `groupby().transform()` for values
within groups) is how pandas does `replace ... if`.

The crates compiled into `dta_parser`, which datakit calls, and their
licences are listed in `python/dta_parser/NOTICE`.

The open-source projects studied for the Parquet code, and the codec
crates it uses, are listed with their licenses in
[docs/acknowledgements.md](../../docs/acknowledgements.md).
