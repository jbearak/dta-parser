# datakit for Python

Data preparation in polars that keeps Stata's labels and missing values
`.a` to `.z`. datakit reads Parquet files, Stata `.dta` files, and
fixed-width text with a SAS setup file into a polars `DataFrame`, with a
`Meta` beside it that holds what polars cannot: variable labels, value
labels, display formats, notes, and which of `.a` to `.z` each missing
value was. It saves both back as Parquet or `.dta`. Its Parquet files
carry the same `dta` profile R's and Julia's datakits write, so data
goes between the three languages with its labels and letters; other
tools read them as plain Parquet.

```python
import polars as pl
import datakit as dk

df = pl.DataFrame({"id": [1, 2, 3], "income": [2100.0, None, None]})
meta = dk.Meta(
    columns={"income": dk.Column(label="Monthly income", value_labels="why")},
    value_labels={"why": {".d": "Don't know", ".r": "Refused"}},
    missing={"income": pl.Series("income", [None, ".d", ".r"], dtype=dk.LETTERS)},
    rows=3,
)
dk.save_parquet(df, "survey.parquet", meta=meta)

df, meta = dk.read_parquet("survey.parquet")            # a tuple: the frame and its Meta
print(df["income"].null_count())                        # 2: .d and .r are nulls
print(meta.missing["income"].to_list())                 # [None, '.d', '.r']
print(meta.columns["income"].label)                     # Monthly income

df, meta = dk.read_parquet("survey.parquet", letters="columns")
print(df.columns)                                       # ['id', 'id_letter', 'income', 'income_letter']
```

`letters="columns"` gives each column that can hold a letter a
companion column, `income_letter`, which follows its rows through
`filter`, `sort` and `join`; code that changes rows should use it. The
guide is [docs/python.md](../../docs/python.md#datakit-parquet-dta-and-fixed-width-files-in-polars);
the Parquet file is specified in [docs/parquet.md](../../docs/parquet.md).

## Install from a checkout

datakit is pure Python; the decoding and encoding are in `dta_parser`'s
compiled core, so install both from a checkout of this repository. You
need Python 3.10 or later, a Rust toolchain ([rustup.rs](https://rustup.rs))
and a C compiler:

    git clone https://github.com/jbearak/dta-parser
    pip install ./dta-parser/python ./dta-parser/python/datakit

That also installs polars 2 and, through `dta_parser`, numpy and pandas;
`import datakit` does not load pandas. Neither package is on PyPI.

- **The name.** The distribution is `dta-datakit` and the import name is
  `datakit`. A different project already has `datakit` on PyPI, and the
  two cannot be installed in one environment, since both would be
  imported as `datakit`.
- **Versions.** datakit 0.3 needs `dta_parser` 0.3 from the same
  checkout. If `import datakit` stops with "needs dta_parser's native
  functions at ABI version 1", reinstall both:
  `pip install --force-reinstall ./python ./python/datakit`.

For development, from the repository root:

    pip install maturin pytest pyarrow duckdb
    (cd python && maturin build --release --out dist) && pip install python/dist/*.whl
    pip install -e python/datakit
    python -m pytest python/datakit/tests

Build `dta_parser` as a wheel rather than with `maturin develop`: an
editable `dta_parser` puts `python/` on the import path, where the
directory `python/datakit` hides the installed package.

## What it has

| function | does |
|---|---|
| `read_parquet`, `save_parquet`, `read_parquet_info` | Parquet files, and a file's footer alone |
| `read_dta`, `save_dta` | `.dta` files (releases 104 to 119 read, 118 written), without pandas |
| `read_fixed_width` | fixed-width text through its SAS setup file, such as the NSFG's `.dat` files |
| `letters_to_columns` | `.a` to `.z` from `meta.missing` into companion columns |
| `Meta`, `Column`, `ParquetInfo`, `LETTERS` | what a read returns beside the frame |

There are no Stata-style assignment helpers: polars'
`pl.when().then().otherwise()` with `.over()` is how polars does
`replace ... if` within groups.

The crates compiled into `dta_parser`, which datakit calls, and their
licences are listed in `python/dta_parser/NOTICE`.
