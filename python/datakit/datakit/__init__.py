"""datakit: data preparation in polars that keeps Stata's labels and
`.a` to `.z`.

Reads Parquet files, Stata .dta files and fixed-width text with a SAS
setup file into a polars DataFrame, with the missing values `.a` to `.z`
as tagged NaNs in its Float64 columns, and a Meta beside it (labels,
formats and notes), and saves them back as Parquet or .dta. The Parquet files carry a "dta" profile that R's and
Julia's datakits read too.

    import datakit as dk
    df, meta = dk.read_parquet("survey.parquet")
    dk.save_parquet(df, "out.parquet", meta=meta)

Guide: https://github.com/jbearak/dta-parser/blob/main/docs/python.md
"""

__version__ = "0.3.0"

from ._native import native as _native  # noqa: E402,F401  (checks dta_parser's ABI first)
from ._dta import FixedWidthWarning, read_dta, read_fixed_width, save_dta  # noqa: E402
from ._meta import LETTERS, Column, Meta, ParquetInfo  # noqa: E402
from ._parquet import read_parquet, read_parquet_info, save_parquet  # noqa: E402
from ._tagged import is_tagged_na, na_tag, tagged_na  # noqa: E402

__all__ = [
    "LETTERS",
    "Column",
    "FixedWidthWarning",
    "Meta",
    "ParquetInfo",
    "is_tagged_na",
    "na_tag",
    "read_dta",
    "read_fixed_width",
    "read_parquet",
    "read_parquet_info",
    "save_dta",
    "save_parquet",
    "tagged_na",
]
