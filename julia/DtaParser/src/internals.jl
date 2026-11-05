"""
    DtaParser.Internals

What Datakit uses of DtaParser beyond its exports, and nothing else:

- the version of the library's C interface, `ABI_VERSION`, which Datakit
  checks when it loads;
- the native call wrappers for Parquet and fixed-width text (`pq_open`,
  `pq_close`, `pq_info_json`, `pq_read`, `pq_write`,
  `fixed_width_to_dta`) and the C structures and constants they take
  (`PqOutput`, `PqColumn`, `PQ_*`, `W_*`);
- the column builders `read_dta` and `write_dta` use (`split_missing`,
  `missing_codes`, `all_text_or_bytes`, `STORAGE_OF`, `date_kind`,
  `label_set`, `label_sets_json`);
- the JSON reader and writer (`parse_json`, `json`);
- the error types (`DtaError`, `WriteError`).

For Datakit only. None of this is DtaParser's API: it may change in any
release, and changes with `ABI_VERSION`. Use Datakit's `read_parquet`,
`read_parquet_info`, `save_parquet` and `read_fixed_width` instead.
"""
module Internals

using ..DtaParser: ABI_VERSION, PqOutput, PqColumn, PQ_I8, PQ_I16, PQ_I32, PQ_I64, PQ_F32, PQ_F64, PQ_U8, PQ_U16,
                   PQ_U32, PQ_U64, PQ_LEVELS, PQ_TEXT, W_INT8, W_INT16, W_INT32, W_INT64, W_FLOAT, W_DOUBLE, W_BOOL,
                   W_DATE, W_DATETIME, W_ZONED, W_TEXT, W_BINARY, W_CATEGORICAL, pq_open, pq_close, pq_info_json,
                   pq_read, pq_write, fixed_width_to_dta, split_missing, missing_codes, all_text_or_bytes, STORAGE_OF,
                   date_kind, label_set, label_sets_json, parse_json, json, DtaError, WriteError

export ABI_VERSION, PqOutput, PqColumn, PQ_I8, PQ_I16, PQ_I32, PQ_I64, PQ_F32, PQ_F64, PQ_U8, PQ_U16, PQ_U32, PQ_U64,
       PQ_LEVELS, PQ_TEXT, W_INT8, W_INT16, W_INT32, W_INT64, W_FLOAT, W_DOUBLE, W_BOOL, W_DATE, W_DATETIME, W_ZONED,
       W_TEXT, W_BINARY, W_CATEGORICAL, pq_open, pq_close, pq_info_json, pq_read, pq_write, fixed_width_to_dta,
       split_missing, missing_codes, all_text_or_bytes, STORAGE_OF, date_kind, label_set, label_sets_json, parse_json,
       json, DtaError, WriteError

end
