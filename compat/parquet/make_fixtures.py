"""Write small Parquet fixtures with pyarrow, polars and DuckDB, from data
made here, into compat/parquet/fixtures/.

Run from the repository root (needs pyarrow, polars and duckdb):

    python3 compat/parquet/make_fixtures.py
    Rscript compat/parquet/make_fixtures.R
    python3 compat/parquet/expected.py

Each file covers the types plan 0018's first slice reads, with nulls, and
the encodings, page versions and codecs its writer uses by default; a few
use options (data page v2, gzip, an offset index, no dictionary, small
row groups and pages) to cover the rest.
"""

import datetime as dt
import os

import duckdb
import polars as pl
import pyarrow as pa
import pyarrow.parquet as pq

OUT = os.path.join(os.path.dirname(__file__), "fixtures")
os.makedirs(OUT, exist_ok=True)

N = 600


def nulls(every, offset=3):
    return [i % every == offset for i in range(N)]


def masked(values, every):
    return [None if m else v for v, m in zip(values, nulls(every))]


def table():
    """Every type of the first slice, with nulls; values are simple
    functions of the row."""
    rows = range(N)
    utc = dt.timezone.utc
    base = dt.datetime(2020, 1, 1, tzinfo=utc)
    floats = [i / 7 for i in rows]
    floats[5] = float("nan")
    floats[6] = -0.0
    return pa.table(
        {
            "i8": pa.array(masked([i % 250 - 125 for i in rows], 10), pa.int8()),
            "i16": pa.array(masked([i * 11 - 16000 for i in rows], 11), pa.int16()),
            "i32": pa.array(masked([i * 700_001 - 1_000_000_000 for i in rows], 12), pa.int32()),
            "i64": pa.array(masked([i * 3_000_000_000_017 - 5 for i in rows], 13), pa.int64()),
            "f32": pa.array(masked([i * 0.25 - 50 for i in rows], 14), pa.float32()),
            "f64": pa.array(masked(floats, 15), pa.float64()),
            "flag": pa.array(masked([i % 3 == 0 for i in rows], 16), pa.bool_()),
            "word": pa.array(masked([f"word {i % 40} ü" for i in rows], 17), pa.string()),
            "unique": pa.array(masked([f"row number {i}" for i in rows], 18), pa.string()),
            "blob": pa.array(masked([bytes([i % 256, 7, 0]) for i in rows], 19), pa.binary()),
            "day": pa.array(masked([dt.date(1960, 1, 1) + dt.timedelta(days=i * 9) for i in rows], 20), pa.date32()),
            "ts_ms": pa.array(masked([base + dt.timedelta(seconds=i * 61) for i in rows], 21), pa.timestamp("ms", tz="UTC")),
            "ts_us_ny": pa.array(
                masked([base + dt.timedelta(microseconds=i * 1_000_003) for i in rows], 22),
                pa.timestamp("us", tz="America/New_York"),
            ),
            "ts_ns_local": pa.array(masked([i * 1_000_000_007 for i in rows], 23), pa.timestamp("ns")),
            "cat": pa.array(masked(["low", "mid", "high"] * (N // 3), 24)).dictionary_encode(),
        }
    )


def main():
    t = table()
    pq.write_table(t, os.path.join(OUT, "pyarrow_default.parquet"))
    pq.write_table(t, os.path.join(OUT, "pyarrow_v2_pages.parquet"), data_page_version="2.0")
    pq.write_table(t, os.path.join(OUT, "pyarrow_gzip.parquet"), compression="gzip")
    pq.write_table(
        t,
        os.path.join(OUT, "pyarrow_small_pages.parquet"),
        row_group_size=200,
        data_page_size=1024,
        write_page_index=True,
        compression="zstd",
    )
    pq.write_table(t, os.path.join(OUT, "pyarrow_plain.parquet"), use_dictionary=False, compression="none")

    # polars: its own default (zstd) and explicitly zstd with statistics.
    df = pl.from_arrow(t)
    df.write_parquet(os.path.join(OUT, "polars_default.parquet"))
    df.write_parquet(os.path.join(OUT, "polars_zstd.parquet"), compression="zstd", statistics=True, row_group_size=250)

    # DuckDB, from the same table. DuckDB has no dictionary type to write,
    # so cat is text there.
    con = duckdb.connect()
    con.register("t", t)
    path = os.path.join(OUT, "duckdb_default.parquet").replace("'", "''")
    con.execute(f"COPY (SELECT * FROM t) TO '{path}' (FORMAT parquet)")

    print("wrote", ", ".join(sorted(f for f in os.listdir(OUT) if f.endswith(".parquet"))))
    print(f"pyarrow {pa.__version__}, polars {pl.__version__}, duckdb {duckdb.__version__}")


if __name__ == "__main__":
    main()
