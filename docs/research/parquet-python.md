# Parquet in Python: what existing readers and writers do

We plan a Parquet reader and writer for R, with matching libraries for
Python, Julia and TypeScript. This note covers the Python side. It
records how the established Python libraries read and write Parquet (and
Arrow IPC, which pyarrow and polars call Feather or IPC), so our design
can keep what works and avoid what users complain about.

Measured November 2026 on macOS (Apple silicon), Python 3.14.7, in a
fresh virtual environment. Every behaviour marked "measured" came from a
script run against the versions below. Facts not measured link to their
source. Timings were taken with a warm page cache on a shared machine
(load average around 10), so treat them as rough. The memory numbers
are more reliable.

| library | version | role |
|---|---|---|
| pandas | 3.1.1 | `read_parquet`, `to_parquet`, `read_feather`; the frame we return |
| pyarrow | 26.0.1 | `pyarrow.parquet`, `pyarrow.feather`; the engine under pandas |
| polars | 2.1.0 | its own Rust Parquet and IPC reader and writer |
| fastparquet | 2026.9.0 | pure-Python/numba Parquet library; being retired |
| duckdb | 2.0.0 | SQL engine with its own Parquet reader and writer |
| pyreadstat | 1.3.7 | `.dta` reader and writer on ReadStat; label handling only |

Licenses are in the table at the end.

## What our Python package must carry through Parquet

`dta_parser.read_dta` (`docs/python.md`, removed with the package: ADR 0042) returns numpy
numeric columns, or a `StataArray` (float values plus a `uint8` code per
row: 0 number, 1 `.`, 2 to 27 `.a` to `.z`) where `.a` to `.z` occur;
`%td` as `datetime64[s]` and `%tc` as `datetime64[ms]`; pandas' default
string dtype; and everything else (labels, value labels keyed by codes
and by `missing.a` objects, formats, storage types, notes) in
`df.attrs["dta"]`, a `DtaInfo` dict whose `__deepcopy__` returns itself
so pandas does not copy it per column.

Measured with today's `StataArray` (copied from `python/dta_parser` into
a scratch package) and the libraries above:

- `df.to_parquet(...)` on a frame with a `StataArray` column fails with
  `ArrowTypeError: ('Did not pass numpy.dtype object', 'Conversion
  failed for column income with type stata[double]')`. `StataArray` has
  no `__arrow_array__`, so pyarrow cannot convert it.
- `df.attrs["dta"]` cannot be written by pandas at all once it holds a
  `MissingValue` key (the value labels of missing codes). See
  [attrs](#dfattrs-in-parquet).
- Even when attrs are plain JSON, integer keys come back as strings:
  `{"r": {1: "North"}}` reads back as `{"r": {"1": "North"}}`.

So `df.to_parquet` cannot be the path for our frames. We need our own
writer, or at least our own conversion to Arrow before handing over.

## pyarrow.parquet

The reference implementation for Python. pandas calls it; polars and
duckdb do not.

### Read

```text
pq.read_table(source, *, columns=None, use_threads=True, schema=None,
    use_pandas_metadata=False, read_dictionary=None, binary_type=None,
    list_type=None, memory_map=False, buffer_size=0, partitioning='hive',
    filesystem=None, filters=None, ignore_prefixes=None, pre_buffer=True,
    coerce_int96_timestamp_unit=None, decryption_properties=None,
    thrift_string_size_limit=None, thrift_container_size_limit=None,
    schema_depth_limit=None, page_checksum_verification=False,
    arrow_extensions_enabled=True)

pq.ParquetFile(source, *, metadata=None, common_metadata=None,
    read_dictionary=None, binary_type=None, list_type=None,
    memory_map=False, buffer_size=0, pre_buffer=True, ...)
  .read(columns=None, use_threads=True, use_pandas_metadata=False)
  .read_row_group(i, columns=None, ...)
  .read_row_groups(row_groups, columns=None, use_threads=True,
      use_pandas_metadata=False)
  .iter_batches(batch_size=65536, row_groups=None, columns=None,
      use_threads=True, use_pandas_metadata=False)
  .metadata, .schema (Parquet), .schema_arrow, .num_row_groups

pq.read_metadata(where, memory_map=False, decryption_properties=None,
    filesystem=None, arrow_extensions_enabled=True)
pq.read_schema(where, memory_map=False, ...)
```

- **Columns.** `columns` takes names, returned in the order asked;
  a name twice returns it twice (measured). A dotted name such as
  `"st.a"` reads one field of a struct. `read_table(columns=[0])`
  raises `TypeError: expected bytes, int found`, but
  `ParquetFile.read(columns=[0])` silently returns a table with no
  columns (measured). That silent empty result is a trap.
- **Rows.** There is no `skip`/`n_max`. You read whole row groups
  (`read_row_groups`), stream batches (`iter_batches`), or read and
  `slice`. `filters` (a DNF list of tuples or a `pyarrow.compute`
  expression) prunes row groups by statistics and then filters rows.
- **Return type.** An Arrow `Table`. `Table.to_pandas(...)` makes the
  frame; its defaults that matter here are `date_as_object=True,
  split_blocks=False, self_destruct=False, types_mapper=None,
  ignore_metadata=False, use_threads=True`.
- **Types on the way to pandas** (measured, file without pandas
  metadata). int64 with nulls becomes `float64`; strings become pandas'
  `str` dtype; dictionary columns become `Categorical`; `DATE` becomes
  `object` holding `datetime.date` (`date_as_object=True`), or
  `datetime64[ms]` with `date_as_object=False`; timestamps keep their
  unit and time zone (`datetime64[us, America/New_York]`); decimals,
  lists and structs become `object` columns of `Decimal`, numpy arrays
  and dicts. `read_dictionary=["s"]` returns a string column as a
  dictionary array.
- **Metadata without data.** `read_metadata` gives row count, row
  groups, per-column-chunk codec, encodings, sizes and statistics, and
  the file key-value metadata. `read_schema` gives the Arrow schema
  including schema and field metadata. Both read only the footer
  (0.011 s and 0.017 s for a 5,000-column file, measured).

### Write

```text
pq.write_table(table, where, row_group_size=None, version='2.6',
    use_dictionary=True, compression='snappy', write_statistics=True,
    use_deprecated_int96_timestamps=None, coerce_timestamps=None,
    allow_truncated_timestamps=False, data_page_size=None, flavor=None,
    filesystem=None, compression_level=None, use_byte_stream_split=False,
    column_encoding=None, data_page_version='1.0',
    use_compliant_nested_type=True, encryption_properties=None,
    write_batch_size=None, dictionary_pagesize_limit=None,
    store_schema=True, write_page_index=False, write_page_checksum=False,
    sorting_columns=None, store_decimal_as_integer=False,
    write_time_adjusted_to_utc=False, max_rows_per_page=None,
    bloom_filter_options=None, use_content_defined_chunking=False)

pq.ParquetWriter(where, schema, ...same options...)
  .write_table(t, row_group_size=None), .write_batch(b), .close()
```

- Defaults (measured): Snappy, dictionary encoding tried for every
  column with fallback to PLAIN when the dictionary page passes 1 MiB,
  data page v1, statistics on, at most 1,048,576 rows per row group,
  `created_by = "parquet-cpp-arrow version 26.0.1"`.
- `version` picks which logical types may be used. With `"1.0"`,
  `uint32` is stored as int64 and nanosecond timestamps become
  microseconds; with `"2.6"` both are kept (measured).
- Parquet has no seconds unit. `timestamp[s]` is written as
  `TIMESTAMP(MILLIS)` and reads back as `timestamp[ms]` (measured).
  `coerce_timestamps="us"` on data that would lose precision raises
  `ArrowInvalid: Casting from timestamp[ns] to timestamp[us] would lose
  data` unless `allow_truncated_timestamps=True`.
- `store_schema=True` writes the whole Arrow schema, base64-encoded IPC,
  under the key `ARROW:schema`. That is how Arrow-only facts survive:
  extension types, field metadata, `large_string`, time zones, the
  ordering flag of dictionaries.
- `column_encoding={"col": "DELTA_BINARY_PACKED"}` (with
  `use_dictionary=False`) and `use_byte_stream_split` pick encodings.
- `ParquetWriter` streams: each `write_table` call adds row groups.

### Metadata

- File key-value metadata: put bytes in the Arrow schema metadata
  (`table.replace_schema_metadata({...})`); `write_table` copies it into
  the footer's key-value list and into `ARROW:schema`.
- Field-level metadata: `pa.field(name, type, metadata={...})`. It
  lives only in `ARROW:schema`; Parquet's own schema has no place for
  it, so duckdb never sees it. It is lost through
  `to_pandas`/`from_pandas` and through polars (measured).
- Extension types: a `pa.ExtensionType` subclass with
  `__arrow_ext_serialize__` / `__arrow_ext_deserialize__`, registered
  with `pa.register_extension_type`. Unregistered readers fall back to
  the storage type ([Arrow docs](https://arrow.apache.org/docs/python/extending_types.html)).

### Performance

- `use_threads=True` decodes columns in parallel. `pre_buffer=True`
  (default) coalesces and prefetches column chunk reads, which helps on
  network filesystems but holds the compressed bytes in memory: reading
  a 397 MB file of 12 float columns peaked at 971 MB with the default
  and 689 MB with `pre_buffer=False` (measured, 147 MB after imports).
- `memory_map=True` maps the file instead of reading it. It cannot avoid
  decoding, so the gain is small (1,236 MB versus 1,330 MB peak for
  `to_pandas`, measured).
- `to_pandas` is where memory doubles. The Arrow docs say plainly that
  without `split_blocks` and `self_destruct` "to_pandas will always
  double memory", and that `self_destruct=True` makes the Table unsafe
  to use afterwards ([Pandas integration](https://arrow.apache.org/docs/python/pandas.html)).
  Measured on the 384 MB float table: `read_table().to_pandas()` 1,330
  MB peak; `to_pandas(split_blocks=True, self_destruct=True)` 1,035 MB;
  that plus `pre_buffer=False` 854 MB. Zero copy is only possible for
  numeric columns with no nulls in one chunk.
- Known problems with these options: [apache/arrow#25913](https://github.com/apache/arrow/issues/25913)
  (`self_destruct` does not prevent doubling in some cases; resolved by
  documenting it), [apache/arrow#50698](https://github.com/apache/arrow/issues/50698)
  (reading table metadata after a `self_destruct` conversion segfaults),
  [pandas#66509](https://github.com/pandas-dev/pandas/issues/66509)
  (`read_parquet(to_pandas_kwargs={"self_destruct": True})` segfaults,
  July 2026). Spark's settings are a good reference: `split_blocks`,
  `self_destruct`, `use_threads=False` and
  `pa.jemalloc_set_decay_ms(0)` ([gist by an Arrow developer](https://gist.github.com/lidavidm/289229caa022358432f7deebe26a9bd3)).

### Errors

See [the comparison](#error-behaviour-compared-measured). Messages name
the file and the column; a damaged footer gives only "Couldn't
deserialize thrift", with no offset. Writing an `object` column that
mixes ints and strings raises `ArrowInvalid: ("Could not convert 'x'
with type str: tried to convert to int64", 'Conversion failed for
column a with type object')`.

## pandas: read_parquet and to_parquet

```text
pd.read_parquet(path, engine=<no_default>, columns=None,
    storage_options=None, dtype_backend=<no_default>, filesystem=None,
    filters=None, to_pandas_kwargs=None, **kwargs)

DataFrame.to_parquet(path=None, *, engine=<no_default>,
    compression='snappy', index=None, partition_cols=None,
    storage_options=None, filesystem=None, **kwargs)
```

- pyarrow is now a required dependency of pandas 3. The `"fastparquet"`
  and `"auto"` engines are deprecated since 3.1.0 and warn with
  `Pandas4Warning` (measured; [docs](https://pandas.pydata.org/docs/reference/api/pandas.read_parquet.html)).
- `**kwargs` go to `pq.read_table` / `pq.write_table`;
  `to_pandas_kwargs` (new in 3.0) to `Table.to_pandas`. `path=None` in
  `to_parquet` returns bytes.
- `filters` work row by row with pyarrow; `columns` selects. There is
  no row limit or offset.
- `index=None` stores a `RangeIndex` as metadata only and any other
  index as a column named `__index_level_0__` (measured), which other
  readers then show as a data column.
- `dtype_backend` (measured on a pandas-written file):

| file column | default | `"numpy_nullable"` | `"pyarrow"` |
|---|---|---|---|
| int8 | `int8` | `Int8` | `int8[pyarrow]` |
| int64 with nulls, from pandas `Int64` | `Int64` | `Int64` | `int64[pyarrow]` |
| int64 with nulls, written by others | `float64` | `Int64` | `int64[pyarrow]` |
| double | `float64` | `Float64` | `double[pyarrow]` |
| string | `str` | `string` | `large_string[pyarrow]` |
| dictionary (from Categorical) | `category` | `category` | `dictionary<...>[pyarrow]` |
| datetime64[s] written | `datetime64[ms]` | same | `timestamp[ms][pyarrow]` |
| tz-aware | `datetime64[us, tz]` | same | `timestamp[us, tz=...][pyarrow]` |
| DATE | `object` (`datetime.date`) | same | `date32[day][pyarrow]` |
| decimal, list, struct | `object` | `object` | Arrow types |

### The "pandas" metadata key

pyarrow's `Table.from_pandas` adds a JSON document under the schema key
`pandas` (measured):

```json
{"index_columns": [{"kind": "range", "name": null, "start": 0, "stop": 3, "step": 1}],
 "columns": [{"name": "Int64", "field_name": "Int64", "pandas_type": "int64",
              "numpy_type": "Int64", "metadata": null},
             {"name": "cat", "pandas_type": "categorical", "numpy_type": "int8",
              "metadata": {"num_categories": 3, "ordered": true}}, ...],
 "attributes": {...df.attrs...}, "pandas_version": "3.1.1", ...}
```

On read, `numpy_type` is looked up with `pandas_dtype()`. If that names
a registered extension dtype with `__from_arrow__`, pyarrow calls it.
This is how `Int64`, `boolean` and `category` round trip, and how ours
could.

### df.attrs in Parquet

Two layers write attrs, and both use JSON:

- pandas (since 2.1, [pandas#54321](https://github.com/pandas-dev/pandas/issues/54321),
  [PR #54346](https://github.com/pandas-dev/pandas/pull/54346)) writes
  `json.dumps(df.attrs)` under the key `PANDAS_ATTRS` and restores it
  in `read_parquet`. Non-string keys come back as strings.
- pyarrow (since 22, [apache/arrow#45382](https://github.com/apache/arrow/issues/45382))
  copies attrs into `"attributes"` of the `pandas` key and restores
  them in `Table.to_pandas`. That is why Feather files keep attrs too
  (measured). If attrs are not JSON-serialisable it warns and writes
  `{}` ([apache/arrow#47966](https://github.com/apache/arrow/issues/47966)
  was the crash before that fix).

Measured results for `to_parquet` with attrs that JSON cannot take
(a `MissingValue` key, a numpy integer): pyarrow warns "Could not
serialize pd.DataFrame.attrs ... defaulting to empty attributes", then
pandas' own `json.dumps` raises `TypeError`, so the write fails. A
tuple comes back as a list. Column-level attrs (`df[c].attrs`) are not
stored by either layer ([pandas#64711](https://github.com/pandas-dev/pandas/issues/64711)).
DuckDB and polars do not read `PANDAS_ATTRS`, and pandas ignores other
keys, so attrs written by others never appear in `df.attrs`.

Attrs are also stored three times: in `PANDAS_ATTRS`, inside the
`pandas` key, and again inside the base64 `ARROW:schema`. For a
5,000-column frame with one small dictionary per column, the footer
was 4.9 MB (`ARROW:schema` 2.6 MB, `pandas` 1.1 MB, `PANDAS_ATTRS`
0.6 MB) for 30 MB of data (measured).

**Large attrs make pandas slow.** With that 5,000-entry attrs dict,
`to_parquet` took 24 s instead of 0.66 s, and `pl.from_pandas` 38 s
instead of 0.10 s (measured). pandas deep-copies `attrs` into each
intermediate object; `DtaInfo.__deepcopy__` exists in our package for
exactly this reason. Any path that goes through pandas' column access
with a plain-dict attrs pays it.

### Extension arrays

Measured with a prototype: give `StataArray` an `__arrow_array__`
returning a `pa.ExtensionArray` of a registered `ExtensionType`
`"dta_parser.stata"` (storage `struct<value: double, code: uint8>`,
parameter = storage type name), and give `StataDtype` a
`__from_arrow__`. Then:

- `to_parquet` writes the struct; the `pandas` key records
  `"numpy_type": "stata[double]"`.
- `read_parquet` returns `stata[double]` with codes `[0 5 1 19]`
  intact.
- If the extension type is not registered, pyarrow still finds
  `stata[double]` through pandas metadata and calls `__from_arrow__`
  with a plain `StructArray`, so `__from_arrow__` must accept both.
- polars 2.1 shows the column as `Extension('dta_parser.stata',
  Struct(...))`; duckdb as `STRUCT("value" DOUBLE, code UTINYINT)`.
  Neither sees a number, so a struct makes the file awkward everywhere
  except our own reader.

The pandas side of this protocol is documented in
[Extending pandas](https://pandas.pydata.org/docs/development/extending.html);
[pandas#67753](https://github.com/pandas-dev/pandas/issues/67753) shows
the risk of serialising extension parameters as a type string.

## pyarrow.feather and pandas read_feather

```text
pyarrow.feather.write_feather(df, dest, compression=None,
    compression_level=None, chunksize=None, version=2)
pyarrow.feather.read_feather(source, columns=None, use_threads=True,
    memory_map=False, **kwargs)        # returns pandas
pyarrow.feather.read_table(source, columns=None, memory_map=False,
    use_threads=True)                  # returns Arrow
```

Feather v2 is the Arrow IPC file format. `compression=None` means LZ4
when available, else uncompressed; `chunksize` defaults to 64K rows per
record batch; writing v1 is deprecated since pyarrow 25. Because IPC
stores Arrow types directly, `datetime64[s]` comes back as
`datetime64[s]` (Parquet gives `ms`) and attrs come back through the
`pandas` key (measured). Uncompressed Feather can be memory-mapped
without decoding, which Parquet cannot. polars `read_ipc` turned the
`timestamp[s]` column into `Datetime(ms)`, since polars has no seconds
unit (measured). A request to store attrs for Feather on the pandas side
is [pandas#60675](https://github.com/pandas-dev/pandas/issues/60675).

## polars

```text
pl.read_parquet(source, *, columns=None, n_rows=None, row_index_name=None,
    row_index_offset=0, parallel='auto', use_statistics=True,
    hive_partitioning=None, glob=True, schema=None, hive_schema=None,
    try_parse_hive_dates=True, low_memory=False, storage_options=None,
    credential_provider='auto', use_pyarrow=False, pyarrow_options=None,
    memory_map=True, include_file_paths=None, missing_columns='raise',
    decryption=None)
pl.scan_parquet(source, *, n_rows=None, row_index_name=None, ...,
    low_memory=False, cache=True, missing_columns='raise',
    extra_columns='raise', cast_options=None, ...)   # LazyFrame
pl.read_parquet_schema(source) -> dict[str, DataType]
pl.read_parquet_metadata(source, storage_options=None,
    credential_provider='auto') -> dict[str, str]
pl.read_ipc(source, *, columns=None, n_rows=None, use_pyarrow=False,
    storage_options=None, row_index_name=None, row_index_offset=0)

DataFrame.write_parquet(file, *, compression='zstd', compression_level=None,
    statistics=True, row_group_size=None, data_page_size=None,
    use_pyarrow=False, pyarrow_options=None, partition_by=None,
    partition_chunk_size_bytes=4294967296, storage_options=None,
    credential_provider='auto', metadata=None, arrow_schema=None,
    encryption=None, mkdir=False)
LazyFrame.sink_parquet(path, *, ...same, plus maintain_order=True, ...)
DataFrame.to_pandas(*, use_pyarrow_extension_array=False, **kwargs)
```

- **Read.** `columns` takes names or positions (measured: `[1, 0]`
  gives `s, i`); a name twice raises `DuplicateError`. `n_rows` limits
  rows; offsets need `scan_parquet(...).slice(offset, n)`, which pushes
  the slice into the scan. `parallel` is `"auto"`, `"columns"`,
  `"row_groups"`, `"prefiltered"` or `"none"`. Types (measured): int64
  with nulls stays `Int64`; strings `String`; dictionary columns
  `Categorical`; `DATE` is `Date`; decimals, lists and structs keep
  their types; `timestamp[s]` becomes `ms`.
- **Write defaults** (measured on a 200,000-row frame): zstd level 3,
  data page v1, PLAIN for numbers, dictionary encoding only for
  low-cardinality columns (the 3-value string and the date column got
  `RLE_DICTIONARY`; unique strings and floats stayed `PLAIN`),
  statistics on, two row groups of 100,000 rows. The docstring says
  `row_group_size` defaults to 512² rows and `data_page_size` to 1 MiB;
  the format version in the footer is 1. Compression levels: gzip 0-9
  (default 6), brotli 0-11 (1), zstd 1-22 (3). Codecs:
  `uncompressed, snappy, gzip, brotli, lz4, zstd`; `lzo` raises
  `ValueError` naming the allowed set.
- **Categorical and Enum.** polars writes them as Arrow dictionaries
  and adds field metadata `_PL_CATEGORICAL2` or `_PL_ENUM_VALUES2`
  (`'2;lo3;mid2;hi'`, length-prefixed values), so an Enum's unused
  levels survive. pandas reads the Enum as an ordered `Categorical`
  with all three levels (measured).
- **Metadata.** `write_parquet(metadata={"k": "v"})` writes file
  key-value pairs (marked experimental; added in
  [PR #21806](https://github.com/pola-rs/polars/pull/21806) after
  [#18550](https://github.com/pola-rs/polars/issues/18550)).
  `arrow_schema=` (marked unstable) sets schema and field metadata; it
  goes into `ARROW:schema` only, so `read_parquet_metadata` does not
  list those keys (measured). polars drops field and schema metadata
  when a frame passes through it: `pl.from_arrow(t).write_parquet()`
  lost both (measured). `read_parquet_schema` failed on files whose
  key-value metadata holds Parquet bytes ([#23211](https://github.com/pola-rs/polars/issues/23211)).
- **to_pandas.** Int with nulls becomes `float64` unless
  `use_pyarrow_extension_array=True`. It doubles memory on big frames
  ([#24951](https://github.com/pola-rs/polars/issues/24951)): measured
  1,026 MB peak for the 384 MB float table versus 884 MB for polars
  alone; on a string-heavy file 665 MB versus 456 MB.

## fastparquet

```text
fastparquet.ParquetFile(fn, verify=False, open_with=open, root=False,
    sep=None, fs=None, pandas_nulls=True, dtypes=None)
  .to_pandas(columns=None, categories=None, filters=[], index=None,
      row_filter=False, dtypes=None)
  .iter_row_groups(filters=None, **kwargs), .head(nrows), .count()
  .columns, .dtypes, .schema, .key_value_metadata, .statistics
fastparquet.write(filename, data, row_group_offsets=None, compression=None,
    file_scheme='simple', open_with=open, mkdirs=None, has_nulls=True,
    write_index=None, partition_on=[], fixed_text=None, append=False,
    object_encoding='infer', times='int64', custom_metadata=None,
    stats='auto')
```

- Status: its documentation says pandas 3 broke parts of it and that it
  "is being retired", with no further development planned
  ([docs](https://fastparquet.readthedocs.io/en/latest/), March 2026).
  pandas deprecated its engine in 3.1.
- Reads straight into pre-allocated pandas columns, so peak memory is
  about the data itself: 524 MB for the 384 MB float table, the lowest
  of all readers measured. Strings come back as `object`; ints with
  nulls as `Int64` (`pandas_nulls=True`); nested structs are flattened
  to `st.a`, `st.b`; decimals become `float64`; `DATE` becomes
  `datetime64[ns]`. It honours pandas metadata, so `datetime64[s]` came
  back as `[s]` where pyarrow gives `[ms]`.
- Writes uncompressed by default, PLAIN encoding only, no string
  statistics (measured). It cannot write `object` columns of
  `datetime.date` or lists containing `None` (`ValueError: Can't infer
  object conversion type`).
- Cannot read DELTA_LENGTH_BYTE_ARRAY, DELTA_BYTE_ARRAY or
  BYTE_STREAM_SPLIT (`NotImplementedError: Encoding 6/7/9`, measured),
  so it fails on duckdb's `PARQUET_VERSION v2` output.
- Row-wise `filters` (`row_filter=True`) failed on a nullable int column
  with `ValueError: cannot convert to 'bool'-dtype NumPy array with
  missing values` (measured).
- Its errors on bad files are the weakest measured (see the
  comparison below).

## duckdb (Python)

```text
duckdb.read_parquet(path_or_buffer, binary_as_string=False, *,
    connection=None, **kwargs) -> DuckDBPyRelation
DuckDBPyRelation.to_parquet(file_name, *, compression=None, field_ids=None,
    row_group_size_bytes=None, row_group_size=None, overwrite=None,
    per_thread_output=None, use_tmp_file=None, partition_by=None,
    write_partition_columns=None, append=None, filename_pattern=None,
    file_size_bytes=None)
SQL: SELECT ... FROM read_parquet('f.parquet', file_row_number=true, ...)
     COPY t TO 'f.parquet' (FORMAT parquet, COMPRESSION zstd,
         ROW_GROUP_SIZE 100000, KV_METADATA {k: 'v'}, PARQUET_VERSION v2)
     parquet_metadata(f), parquet_schema(f), parquet_kv_metadata(f),
     parquet_file_metadata(f)
```

Columns, row filters and limits are plain SQL (`SELECT a, b ... WHERE
... LIMIT n OFFSET m`), pushed down into the scan. `.df()` makes pandas:
int with nulls `Int64`, strings `str`, dictionary columns `str` (the
categorical is lost), `DATE` and timestamps `datetime64[us]`, decimals
`float64` (measured). Write defaults (measured): Snappy, PLAIN plus
`PLAIN_DICTIONARY` for low-cardinality columns, page v1, 122,880 rows
per row group. `PARQUET_VERSION v2` switches to DELTA_BINARY_PACKED and
DELTA_LENGTH_BYTE_ARRAY but still writes v1 page headers (measured).
`KV_METADATA` writes file key-value pairs; `parquet_kv_metadata` reads
them back (with `"` shown as `\x22`). It does not write `ARROW:schema`
or the `pandas` key, so pandas sees no attrs. `.df()` had the highest
peak of all readers: 1,768 MB for the 384 MB float table (measured).
Its documentation lists every read and write option with defaults on
one page
([Parquet overview](https://duckdb.org/docs/2.0/data/parquet/overview.html)).

## pyreadstat and pandas Stata label options

These do not touch Parquet but show how Python users already receive
labels. Both were run on a `.dta` file written by pyreadstat.

```text
pyreadstat.read_dta(path, metadataonly=False, apply_value_formats=False,
    formats_as_category=True, usecols=None, user_missing=False,
    row_limit=0, row_offset=0, output_format=None, ...) -> (df, meta)
pyreadstat.write_dta(df, dst_path, file_label='', column_labels=None,
    version=15, variable_value_labels=None, missing_user_values=None,
    variable_format=None)
```

pyreadstat returns labels in a separate `meta` object
(`column_names_to_labels`, `variable_value_labels` as column to
`{code: label}`, `value_labels` as set name to mapping,
`variable_to_label`, `missing_user_values`, `original_variable_types`
holding formats). With `user_missing=True`, `.d` comes back as the
string `'d'` in an `object` column, else `NaN`;
`apply_value_formats=True` makes labelled columns `Categorical`.

`pd.read_stata(..., convert_categoricals=True, convert_missing=False,
order_categoricals=True, ...)` makes labelled columns ordered
`Categorical` by default; `convert_missing=True` gives
`StataMissingValue` objects in an `object` column. `StataReader` has
`value_labels()`, `variable_labels()` and `data_label`; `to_stata`
takes `variable_labels`, `value_labels` and `data_label`.

Neither keeps labels anywhere a Parquet writer would see them:
pyreadstat's live in a separate object, pandas turns them into
categories. A pandas Categorical written to Parquet keeps the label
strings and loses the codes.

## Codecs and encodings

Read support, measured by writing each case with pyarrow (and each
library's own writer) and reading it with the others; "ok" means the
values matched.

| file | pyarrow | polars | fastparquet | duckdb |
|---|---|---|---|---|
| uncompressed, snappy, gzip, brotli, zstd, lz4_raw | ok | ok | ok | ok |
| Hadoop LZ4 (written by fastparquet as `LZ4`) | ok | ok | not tested | ok |
| data page v2 | ok | ok | ok | ok |
| DELTA_BINARY_PACKED | ok | ok | ok | ok |
| DELTA_LENGTH_BYTE_ARRAY | ok | ok | fails | ok |
| DELTA_BYTE_ARRAY | ok | ok | fails | ok |
| BYTE_STREAM_SPLIT | ok | ok | fails | ok |
| LZO | pyarrow and polars refuse to write it; reading not tested |

What each writer emits by default (measured, 200,000 rows of int64,
double, a 3-value string, a unique string and a date):

| writer | codec | encodings | page | rows per group | stats | footer version |
|---|---|---|---|---|---|---|
| pandas / pyarrow | snappy | RLE_DICTIONARY, PLAIN fallback | v1 | up to 1,048,576 | all | 2.6 |
| polars | zstd (3) | PLAIN; RLE_DICTIONARY for low cardinality | v1 | 512² nominal | all | 1.0 |
| fastparquet | none | PLAIN | v1 | 50,000,000 | not strings | 1.0 |
| duckdb | snappy | PLAIN; PLAIN_DICTIONARY for low cardinality | v1 | 122,880 | all | 1.0 |

File sizes for that frame: polars 2.15 MB, duckdb 3.6 MB, pyarrow 4.4
MB, fastparquet 8.8 MB (4.4 MB with snappy). Every writer defaults to
v1 data pages and to encodings every reader understands; DELTA and
BYTE_STREAM_SPLIT are opt-in everywhere.

## Memory and speed

Peak resident memory reading one file into a frame, each in a fresh
process; 147 MB is the baseline after imports (measured).

| reader | 384 MB of doubles (12 cols x 4M) | 63 MB file, 2 string cols + 1 double, 4M rows |
|---|---|---|
| `pq.read_table` (Arrow only) | 971 | 446 |
| `pq.read_table(pre_buffer=False)` | 689 | |
| `pd.read_parquet` | 1,332 | 485 |
| `pd.read_parquet(dtype_backend="pyarrow")` | 962 | 461 |
| `to_pandas(split_blocks, self_destruct)` | 1,035 | 450 |
| the same with `pre_buffer=False` | 854 | |
| `iter_batches` then `pd.concat` | 1,403 | |
| `pl.read_parquet` | 884 | 456 |
| `pl.read_parquet().to_pandas()` | 1,026 | 665 |
| `fastparquet.ParquetFile().to_pandas()` | 524 | 359 |
| `duckdb.sql(...).df()` | 1,768 | 1,349 |

Every read took 0.02 to 0.4 s, too fast to rank here. pandas 3 keeps
strings in Arrow buffers, so the doubling now hits numeric data most.
Batches concatenated at the end do not help.

Wide files: 5,000 `int8` columns by 10,000 rows. `pq.read_metadata`
0.011 s; `pd.read_parquet` all columns 0.14 s, three columns 0.04 s;
`pl.read_parquet` 0.022 s and 0.007 s; duckdb three columns 0.026 s
(measured). Column selection pays off even for small files.

Published comparisons, for context. [pythonspeed](https://pythonspeed.com/articles/polars-memory-pandas/)
measured pandas with pyarrow at 909 MB versus fastparquet at 400 MB and
lazy polars at 250 MB for one task. [codecentric](https://www.codecentric.de/en/knowledge-hub/blog/duckdb-vs-polars-performance-and-memory-with-massive-parquet-data)
found duckdb lowest in peak memory on large scans and pandas highest.
The [polars PDS-H results](https://pola.rs/posts/benchmarks/) are query
benchmarks, not plain reads. All three measure whole pipelines, so they
say little about a reader that returns a full frame.

## Error behaviour compared (measured)

| case | pandas (pyarrow) | polars | fastparquet | duckdb |
|---|---|---|---|---|
| unknown column | `ArrowInvalid`, lists schema | `ColumnNotFoundError`, lists valid names | `ValueError`, lists available | `BinderException`, suggests a name |
| not Parquet / truncated | `ArrowInvalid`, "magic bytes not found" | `ComputeError`, "must end with PAR1" | `OSError [Errno 22]` | `InvalidInputException`, "No magic bytes" |
| damaged footer | `OSError`, thrift | `ComputeError`, thrift | stdout spam, `IndexError` | `duckdb.Error`, thrift |
| bad codec name on write | `OSError` (LZO) | `ValueError`, lists allowed | not tested | not tested |

pandas raises pyarrow's exception types; nothing in pandas wraps them.

## Documentation quality for our tasks

| task | pyarrow | pandas | polars | fastparquet | duckdb |
|---|---|---|---|---|---|
| some columns | yes | yes | API only | yes | SQL |
| some rows | scattered | filters only | API only | `head`, row groups | SQL |
| metadata without data | yes | no | API only | API only | yes, one page |
| write custom metadata | API only | attrs undocumented | API, "experimental" | API | yes |
| labels | no | no | no | no | no |
| dates and time zones | pandas page, partly stale | dtype notes | API only | yes | yes |
| missing values | pandas page (nullable) | dtype_backend | no | "nulls" page | no |

All five document install, reading a whole file and writing well.
Every library documents its API reference well; the gaps are in
task-oriented guides. pyarrow's guide ([Parquet](https://arrow.apache.org/docs/python/parquet.html))
covers install, columns, `ParquetFile`, `read_metadata`, compression
and datasets with runnable examples, but reading some rows is spread
over `iter_batches`, `read_row_groups` and `filters`, and custom
metadata appears only in API pages. Its pandas page explains memory and
nullable types well but is partly stale: it still points `read_parquet`
users at `use_nullable_dtypes` (gone in pandas 3), and its conversion
table says every timestamp becomes `datetime64[ns]`, which its own
examples contradict. The pandas reference pages never mention attrs;
`PANDAS_ATTRS` is visible only in release notes and source. polars'
user guide page is three short examples. duckdb puts every option and
default on one page. No library documents labels; the nearest thing is
pandas Categorical, which keeps label text and loses codes.

## Lessons for our design

### API ideas worth adopting

1. **Keep our `read_dta` shape.** `read_parquet(path, columns=None,
   skip=0, n_max=None, ...)` and `read_parquet_meta(path)`. No Python
   library offers skip plus limit in one call (pyarrow has neither,
   polars has `n_rows` only, pandas has neither), and users build it
   from row groups or `scan().slice()`. Row groups make seeking cheap,
   so we can do it well.
2. **Columns by name or position, in the order given.** polars accepts
   both; pyarrow's `ParquetFile.read(columns=[0])` returning an empty
   table shows what happens when positions are half supported. Raise
   on unknown names and list valid ones, as polars and fastparquet do.
3. **Metadata without data, footer only.** pyarrow and duckdb read a
   5,000-column footer in about 10 ms. Return our `attrs["dta"]`
   dictionary plus `nobs` and row groups.
4. **Low peak memory as a design goal.** Decode Parquet pages straight
   into numpy and `StataArray` buffers, as fastparquet does (524 MB
   peak against pyarrow's 1,330 MB for the same 384 MB). Our Rust core
   already fills numpy arrays for `.dta`; doing the same for Parquet
   avoids the Arrow-then-pandas copy without `self_destruct` and its
   segfaults.
5. **Write defaults every reader can open:** v1 data pages, PLAIN plus
   RLE_DICTIONARY, statistics on. Choose zstd or snappy; all four
   readers read both, and polars already defaults to zstd. Do not emit
   DELTA or BYTE_STREAM_SPLIT by default (fastparquet cannot read them,
   and some R and Julia readers may not either; check). Expose
   `compression`, `compression_level` and `row_group_size` with the
   same names pyarrow and polars use.
6. **Write `ARROW:schema` and a valid `pandas` key.** pyarrow and
   pandas restore dtypes from the `pandas` key (`Int64`, Categorical,
   `stata[...]` through `__from_arrow__`); polars and Arrow readers in
   other languages use `ARROW:schema` (time zones, dictionary ordering,
   field metadata). Without the `pandas` key, int with nulls comes back
   as `float64` in pandas.
7. **Our own metadata key, not `PANDAS_ATTRS`.** Write one documented
   key (for example `dta`) holding JSON for labels, formats, notes and
   storage types, with value-label codes as numbers in arrays
   (`[[1, "North"], [".d", "Don't know"]]`) rather than object keys,
   because JSON turns `1` into `"1"` and cannot hold `missing.d`.
   Optionally mirror variable labels into field metadata for Arrow
   readers. The same key must serve R, Julia and TypeScript.
8. **Dates.** `%td` fits Parquet `DATE`, but pandas reads `DATE` as
   `object` of `datetime.date` unless told otherwise, and `datetime64[s]`
   written as a timestamp comes back as `ms`. Our reader should apply
   its own conversion (`DATE` to `datetime64[s]`) rather than rely on
   `to_pandas`.

### How to store `.a` to `.z`

Options, from the prototype above:

- **Extension type over a struct** (`value`, `code`). Round trips
  exactly in pyarrow and pandas, but polars and duckdb see a struct,
  not a number. Poor for the main reason people choose Parquet.
- **Double column with nulls, plus a sibling `uint8` code column**
  (for example `income` and a hidden `income#missing`), recorded in our
  metadata key. Other readers see a normal nullable number and an
  extra small column; RLE makes an all-zero codes column nearly free.
- **Double column plus sparse codes in metadata** (row index and code
  for each `.a` to `.z`). Clean schema for others, but the footer grows
  with the number of extended missing values and must be rewritten
  with any row subset.

The second option keeps the file useful to everyone else and is
simplest to read back in all four languages. Whatever we choose, the
column must read as a plain nullable number in pyarrow, polars and
duckdb.

### User pain points

- Memory doubling in `to_pandas` and the fragile workarounds:
  [apache/arrow#25913](https://github.com/apache/arrow/issues/25913),
  [apache/arrow#50698](https://github.com/apache/arrow/issues/50698),
  [pandas#66509](https://github.com/pandas-dev/pandas/issues/66509),
  [polars#24951](https://github.com/pola-rs/polars/issues/24951).
- attrs: lost before 2.1 ([pandas#54321](https://github.com/pandas-dev/pandas/issues/54321));
  crash on non-serialisable values ([apache/arrow#47966](https://github.com/apache/arrow/issues/47966));
  string keys, write failure with non-JSON keys and the 24 s slowdown
  with large attrs (measured here); column attrs unsupported
  ([pandas#64711](https://github.com/pandas-dev/pandas/issues/64711),
  [ARROW-12823](https://issues.apache.org/jira/browse/ARROW-12823)).
- Mixed-type `object` columns fail to write with "Expected bytes, got
  a 'int' object" ([apache/arrow#43298](https://github.com/apache/arrow/issues/43298));
  our `write_dta` already names the column and row, and the Parquet
  writer should too.
- Writers that differ in what they emit: polars-written files once
  used huge memory in Spark ([polars#4393](https://github.com/pola-rs/polars/issues/4393));
  a polars writer omitted `column_orders`, so others distrusted its
  statistics ([polars#10956](https://github.com/pola-rs/polars/issues/10956)).
  Test our files with pyarrow, polars and duckdb, and with the R, Julia
  and JavaScript readers.
- `read_parquet` of a single column using far more memory than a lazy
  scan ([polars#15098](https://github.com/pola-rs/polars/issues/15098)).
- fastparquet being retired leaves pandas with one engine; users who
  chose it for memory have nothing else that reads straight into
  pandas.

### Licenses

Our package is GPL-3.0-only. Nothing here is incompatible. Apache-2.0
code may be combined into GPL-3.0 work (not into GPL-2.0-only); copying
code from any of these needs its notice kept.

| library | license | GPL-3.0 compatible |
|---|---|---|
| pandas 3.1.1 | BSD-3-Clause | yes |
| pyarrow 26.0.1 | Apache-2.0 | yes (compatible with GPL-3.0, not GPL-2.0) |
| polars 2.1.0 | MIT | yes |
| fastparquet 2026.9.0 | Apache-2.0 | yes |
| cramjam 2.14.0 (fastparquet's codecs) | MIT | yes |
| duckdb 2.0.0 | MIT | yes |
| pyreadstat 1.3.7 | Apache-2.0 (wraps ReadStat, MIT) | yes |
| numpy 2.5.4 | BSD-3-Clause and others (0BSD, MIT, Zlib, CC0) | yes |
