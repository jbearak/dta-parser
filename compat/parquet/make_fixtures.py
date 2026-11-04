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

The second slice's files (``python3 compat/parquet/make_fixtures.py
breadth`` writes only these) cover the DELTA and BYTE_STREAM_SPLIT
encodings, brotli, INT96, TIME, DECIMAL, unsigned integers,
FIXED_LEN_BYTE_ARRAY, UUID, JSON and a dictionary of integers, from
pyarrow and fastparquet.
"""

import datetime as dt
import decimal
import os
import sys

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


def breadth_table():
    """The second slice's types, with nulls; values are simple functions
    of the row, and some decimals have more than 15 significant digits."""
    rows = range(N)
    D = decimal.Decimal
    return pa.table(
        {
            "u8": pa.array(masked([i % 256 for i in rows], 10), pa.uint8()),
            "u16": pa.array(masked([(i * 109) % 65536 for i in rows], 11), pa.uint16()),
            "u32": pa.array(masked([(i * 7_158_271) % 4_294_967_296 for i in rows], 12), pa.uint32()),
            "u64": pa.array(masked([(i * 30_740_755_617_891_237) % 2**64 for i in rows], 13), pa.uint64()),
            "t_ms": pa.array(masked([(i * 143_999) % 86_400_000 for i in rows], 14), pa.time32("ms")),
            "t_us": pa.array(masked([(i * 143_999_999) % 86_400_000_000 for i in rows], 15), pa.time64("us")),
            "t_ns": pa.array(masked([(i * 143_999_999_999) % 86_400_000_000_000 for i in rows], 16), pa.time64("ns")),
            "dec9": pa.array(masked([D(i * 1237 - 300_000).scaleb(-2) for i in rows], 17), pa.decimal128(9, 2)),
            "dec18": pa.array(masked([D(i * 98_765_432_101 - 9 * 10**13).scaleb(-4) for i in rows], 18), pa.decimal128(18, 4)),
            "dec38": pa.array(
                masked([D((i - 300) * 12_345_678_901_234_567_890_123_457).scaleb(-10) for i in rows], 19),
                pa.decimal128(38, 10),
            ),
            "dec50": pa.array(
                masked([D((i - 300) * 10**44 + i * 7).scaleb(-5) for i in rows], 20),
                pa.decimal256(50, 5),
            ),
            "fixed": pa.array(masked([bytes([i % 256, (i * 7) % 256, 255]) for i in rows], 21), pa.binary(3)),
            "uid": pa.array(masked([bytes(range(i % 200, i % 200 + 16)) for i in rows], 22), pa.uuid()),
            "js": pa.array(masked([f'{{"row": {i}, "even": {str(i % 2 == 0).lower()}}}' for i in rows], 23), pa.json_()),
            "icat": pa.array(masked([i % 7 * 1000 for i in rows], 24), pa.int64()).dictionary_encode(),
            "stamp": pa.array(masked([i * 1_000_000_007 - 10**11 for i in rows], 25), pa.timestamp("ns")),
        }
    )


def delta_table():
    """Columns for the DELTA and BYTE_STREAM_SPLIT encodings."""
    rows = range(N)
    D = decimal.Decimal
    return pa.table(
        {
            "i32": pa.array(masked([(i * 2_654_435_761) % 2**32 - 2**31 for i in rows], 10), pa.int32()),
            "i32_steps": pa.array(masked([i * 3 for i in rows], 11), pa.int32()),
            "i64": pa.array(masked([i * 3_000_000_000_017 - 2**62 for i in rows], 12), pa.int64()),
            "word": pa.array(masked([f"word {i % 40} ü" for i in rows], 13), pa.string()),
            "unique": pa.array(masked([f"row number {i}" for i in rows], 14), pa.string()),
            "blob": pa.array(masked([bytes([i % 256]) * (i % 9) for i in rows], 15), pa.binary()),
            "f32": pa.array(masked([i * 0.25 - 50 for i in rows], 16), pa.float32()),
            "f64": pa.array(masked([i / 7 for i in rows], 17), pa.float64()),
            "i32_split": pa.array(masked([i * 1001 - 300_000 for i in rows], 18), pa.int32()),
            "i64_split": pa.array(masked([i * 10**12 + 5 for i in rows], 19), pa.int64()),
            "fixed_split": pa.array(masked([bytes([i % 256, 1, (i * 3) % 256, 9]) for i in rows], 20), pa.binary(4)),
            "fixed_prefix": pa.array(masked([b"key-" + bytes([48 + i % 10, 48 + i % 7]) for i in rows], 21), pa.binary(6)),
            "dec_int": pa.array(masked([D(i * 1237 - 300_000).scaleb(-2) for i in rows], 22), pa.decimal128(9, 2)),
            "dec_long": pa.array(masked([D(i * 98_765_432_101 - 9 * 10**13).scaleb(-4) for i in rows], 23), pa.decimal128(18, 4)),
        }
    )


DELTA_ENCODINGS = {
    "i32": "DELTA_BINARY_PACKED",
    "i32_steps": "DELTA_BINARY_PACKED",
    "i64": "DELTA_BINARY_PACKED",
    "word": "DELTA_BYTE_ARRAY",
    "unique": "DELTA_LENGTH_BYTE_ARRAY",
    "blob": "DELTA_LENGTH_BYTE_ARRAY",
    "f32": "BYTE_STREAM_SPLIT",
    "f64": "BYTE_STREAM_SPLIT",
    "i32_split": "BYTE_STREAM_SPLIT",
    "i64_split": "BYTE_STREAM_SPLIT",
    "fixed_split": "BYTE_STREAM_SPLIT",
    "fixed_prefix": "DELTA_BYTE_ARRAY",
    "dec_int": "DELTA_BINARY_PACKED",
    "dec_long": "DELTA_BINARY_PACKED",
}


def breadth():
    """The second slice's fixtures, from pyarrow and fastparquet."""
    import fastparquet
    import pandas as pd

    t = table()
    pq.write_table(t, os.path.join(OUT, "pyarrow_brotli.parquet"), compression="brotli")

    d = delta_table()
    common = dict(use_dictionary=False, column_encoding=DELTA_ENCODINGS, store_decimal_as_integer=True)
    pq.write_table(d, os.path.join(OUT, "pyarrow_delta.parquet"), compression="none", data_page_size=1024, **common)
    pq.write_table(
        d,
        os.path.join(OUT, "pyarrow_delta_v2.parquet"),
        compression="snappy",
        data_page_version="2.0",
        row_group_size=250,
        write_page_index=True,
        **common,
    )

    b = breadth_table()
    pq.write_table(b, os.path.join(OUT, "pyarrow_types.parquet"), use_deprecated_int96_timestamps=True)
    pq.write_table(
        b,
        os.path.join(OUT, "pyarrow_types_v2.parquet"),
        store_decimal_as_integer=True,
        data_page_version="2.0",
        compression="zstd",
        row_group_size=200,
        data_page_size=512,
        write_page_index=True,
    )

    # fastparquet: pandas types, its own encodings; unsigned integers,
    # a categorical, INT96 times and brotli.
    rows = range(N)
    df = pd.DataFrame(
        {
            "u8": pd.array([i % 256 for i in rows], "uint8"),
            "u16": pd.array([(i * 109) % 65536 for i in rows], "uint16"),
            "u32": pd.array([(i * 7_158_271) % 4_294_967_296 for i in rows], "uint32"),
            "u64": pd.array([(i * 30_740_755_617_891_237) % 2**64 for i in rows], "uint64"),
            "i16": pd.array(masked([i * 11 - 3000 for i in rows], 11), "Int16"),
            "f64": [None if m else i / 7 for i, m in zip(rows, nulls(12))],
            "flag": pd.array(masked([i % 3 == 0 for i in rows], 13), "boolean"),
            "word": pd.Series(masked([f"word {i % 40} ü" for i in rows], 14), dtype=object),
            "cat": pd.Categorical(masked(["low", "mid", "high"] * (N // 3), 15)),
            "when": pd.to_datetime([1_600_000_000_000_000_000 + i * 1_000_000_007 for i in rows]),
        }
    )
    fastparquet.write(os.path.join(OUT, "fastparquet_default.parquet"), df, row_group_offsets=250)
    fastparquet.write(os.path.join(OUT, "fastparquet_int96_brotli.parquet"), df, times="int96", compression="BROTLI")
    print(f"pyarrow {pa.__version__}, fastparquet {fastparquet.__version__}, pandas {pd.__version__}")


def main():
    if sys.argv[1:] == ["breadth"]:
        breadth()
        return
    import duckdb
    import polars as pl

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

    # Nested columns between flat ones: a list, a struct and a map, which
    # are not read; the flat columns around them are.
    nested = pa.table(
        {
            "id": pa.array(range(N), pa.int32()),
            "tags": pa.array([[i, i + 1] if i % 5 else None for i in range(N)], pa.list_(pa.int64())),
            "point": pa.array([{"x": i, "y": float(i) / 2} for i in range(N)]),
            "props": pa.array([[("k", i)] for i in range(N)], pa.map_(pa.string(), pa.int64())),
            "name": pa.array(masked([f"n{i}" for i in range(N)], 7), pa.string()),
        }
    )
    pq.write_table(nested, os.path.join(OUT, "pyarrow_nested.parquet"))

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
    breadth()


if __name__ == "__main__":
    main()
