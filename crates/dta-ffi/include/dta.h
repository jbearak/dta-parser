/*
 * dta.h: the native C ABI of dta-parser, which reads and writes Stata
 * .dta files. The Julia package DtaParser.jl uses it. Build the library
 * with `cargo build --release -p dta-ffi`: libdta_ffi.so, libdta_ffi.dylib
 * or dta_ffi.dll.
 *
 * Errors. Every call that can fail takes `err` and `err_len`: a buffer
 * of `err_len` bytes the library fills with a NUL-terminated UTF-8
 * message on failure (truncated to fit, at a character boundary) and
 * with "" on success. `err` may be NULL. The library keeps no
 * per-thread state, so a caller may move between threads between calls.
 * A panic inside the library is caught and becomes an error.
 *
 * Handles. A `dta_file` is used by one thread at a time; distinct
 * handles are independent and may be used at once.
 *
 * Strings passed in are NUL-terminated UTF-8. Paths are bytes on Unix
 * and UTF-8 on Windows.
 */

#ifndef DTA_H
#define DTA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The ABI described here. A caller should refuse a library whose
 * dta_abi_version() differs. */
#define DTA_ABI_VERSION 4

/* Storage types (dta_column.storage). */
#define DTA_BYTE 1   /* int8; . is 101, .a-.z 102-127 */
#define DTA_INT 2    /* int16 */
#define DTA_LONG 3   /* int32 */
#define DTA_FLOAT 4  /* float */
#define DTA_DOUBLE 5 /* double */
#define DTA_STR 6    /* strN: fixed width, up to 2045 bytes */
#define DTA_STRL 7   /* strL: long text or binary */

/* Element types of dta_column.values. */
#define DTA_I8 1
#define DTA_I16 2
#define DTA_I32 3
#define DTA_I64 4
#define DTA_F32 5
#define DTA_F64 6
#define DTA_U8 7

/*
 * One column of rows: a chunk being read, or a whole frame being
 * written. Unused pointers are NULL.
 *
 * Numbers (storage DTA_BYTE to DTA_DOUBLE):
 *   values  nrows numbers of type value_type.
 *   codes   nrows missing codes: 0 for a number, 1 for ., 2 to 27 for
 *           .a to .z. NULL when no row is missing. Where a code is not
 *           0 the value is meaningless (0 in an integer type, NaN in a
 *           float type, when read).
 * Strings (DTA_STR, DTA_STRL):
 *   bytes   the rows' bytes, back to back: UTF-8 text, or raw bytes for
 *           a binary strL.
 *   offsets nrows + 1 offsets into bytes; row i is
 *           bytes[offsets[i] .. offsets[i + 1]). offsets[0] is 0.
 *   binary  nrows flags, 1 where the row is a binary strL. NULL when no
 *           row is binary. Only DTA_STRL columns have binary rows.
 */
typedef struct dta_column {
    uint32_t storage;
    uint32_t value_type;
    const void *values;
    const uint8_t *codes;
    const uint8_t *bytes;
    const uint64_t *offsets;
    const uint8_t *binary;
} dta_column;

typedef struct dta_file dta_file;

/* DTA_ABI_VERSION of the library. */
uint32_t dta_abi_version(void);

/*
 * Open the file at `path`, reading its header and descriptors. `encoding`
 * says how to decode text in files before release 118: NULL or "" for
 * Windows-1252, or "windows-1252", "latin1", "utf-8". Returns a handle,
 * or NULL on failure. The file stays open until dta_close.
 */
dta_file *dta_open(const char *path, const char *encoding, char *err, size_t err_len);

/* Close a handle from dta_open. NULL is ignored. */
void dta_close(dta_file *file);

/*
 * Everything but the data, as one JSON object (UTF-8, NUL-terminated):
 *
 *   release, nobs, byteOrder ("little" or "big"), label, timestamp,
 *   encoding, sortedBy (variable indices, from 0),
 *   variables: [{name, type ("byte", "str12", "strL", ...), format,
 *                label, valueLabels (the set's name or "")}],
 *   valueLabels: [{name, labels: [[value, text], ...]}], where value is
 *                a number or a missing value such as ".a",
 *   characteristics: [{variable, name, value}], without notes,
 *   notes: [text, ...].
 *
 * Stores the length, without the NUL, in *len when len is not NULL.
 * The caller owns the result and frees it with dta_string_free. Returns
 * NULL on failure.
 */
char *dta_meta_json(dta_file *file, size_t *len, char *err, size_t err_len);

/* Free a string from dta_meta_json or dta_fixed_width_to_dta. NULL is
 * ignored. */
void dta_string_free(char *s);

/*
 * Called once per chunk of rows read, in row order. `first_row` counts
 * from the read's `start`; `columns` has one entry per selected column,
 * in the order selected, each holding `nrows` rows. Numbers come in
 * their storage type (value_type DTA_I8, DTA_I16, DTA_I32, DTA_F32 or
 * DTA_F64).
 *
 * Everything `columns` points to is borrowed: valid only until the
 * callback returns. Copy what you keep. Return 0 to go on, anything
 * else to stop the read. The callback must not unwind (throw) into the
 * library; catch errors and return nonzero.
 */
typedef int (*dta_chunk_fn)(void *user, uint64_t first_row, uint64_t nrows, const dta_column *columns);

/*
 * Read rows start to start + count - 1 of the `ncols` variables whose
 * indices (from 0) are at `cols`, in any order, once for all of them.
 * The rows must lie in the file. The data is read about 8 MiB of the
 * file at a time, and `callback` gets each chunk with `user`.
 *
 * Returns the number of rows read, -1 on failure, or -2 when the
 * callback stopped the read. With no columns, returns `count` without
 * calling the callback.
 */
int64_t dta_read(dta_file *file, const uint32_t *cols, size_t ncols, uint64_t start, uint64_t count,
                 dta_chunk_fn callback, void *user, char *err, size_t err_len);

/*
 * Write a release 118 file at `path`. `columns` has `ncols` columns of
 * `nrows` rows each, borrowed for the call only and not changed.
 *
 * A numeric column's storage is DTA_BYTE to DTA_DOUBLE; its values may
 * be of any value_type, and must fit the storage type (an error names
 * the column and row otherwise). A NaN whose code is 0 or absent is
 * written as `.`. A DTA_STR column's text is written as strN, sized to
 * its longest value, or strL when that is over 2045 bytes; a DTA_STRL
 * column is always strL, and may mark binary rows. Text must be UTF-8
 * without NULs.
 *
 * `meta_json` (NULL or "" for none) is a JSON object:
 *
 *   label, timestamp: strings,
 *   variables: one {name, format, label, valueLabels} per column,
 *              required when there are columns; format "" means the
 *              storage type's default,
 *   valueLabels: [{name, labels: [[value or ".a"..".z", text], ...]}],
 *   characteristics: [{variable ("_dta" or a variable), name, value}],
 *   notes: [text, ...],
 *   sortedBy: [variable index, ...].
 *
 * The file is written beside `path` and renamed into place, so a failed
 * write leaves an existing file alone. Returns 0, or -1 on failure.
 *
 * The columns' buffers are read in place, by up to three threads on
 * large data (the environment variable DTA_THREADS sets the most), and
 * must not change until dta_write returns. dta_read's callback is called
 * on the calling thread, chunk by chunk in row order, even when the rows
 * are decoded on other threads.
 */
int dta_write(const char *path, uint64_t nrows, const dta_column *columns, size_t ncols, const char *meta_json,
              char *err, size_t err_len);

/*
 * Read the fixed-width text file `data_path` as the SAS setup file
 * describes (docs/plans/0009-fixed-width-sas-setup.md) and write it as
 * release 118 to `out_path`, which must not exist; it is created readable
 * by its owner only. The setup is the `n_setups` files at `setup_paths`
 * (at least one), read in order as one; with several, errors and warnings
 * name a file by its place, from 1. `recodes` says what to do with the
 * setup's missing-value recodes: "setup" (as written; also for NULL),
 * "tagged" (codes recoded to . become .a, .b, ... per variable) or
 * "none" (ignored). With `commented_formats` nonzero, a block comment
 * holding only a PROC FORMAT step or a FORMAT statement is read as code.
 *
 * Returns the warnings, a JSON array of strings (UTF-8, NUL-terminated),
 * with its length in *len when len is not NULL; the caller frees it with
 * dta_string_free. Returns NULL on failure.
 */
char *dta_fixed_width_to_dta(const char *data_path, const char *const *setup_paths, size_t n_setups,
                             const char *out_path, const char *recodes, int commented_formats, size_t *len,
                             char *err, size_t err_len);

/* ---------------------------------------------------------------- Parquet
 *
 * Parquet files with a dta profile (docs/plans/0018-parquet.md,
 * docs/parquet.md). The caller allocates every output and decides from
 * dta_pq_info_json what each column becomes.
 */

typedef struct dta_pq_file dta_pq_file;

/*
 * Open the Parquet file at `path`, or, when `path` is NULL, the `len`
 * bytes at `bytes`, which must stay alive and unchanged until
 * dta_pq_close. Reads only the footer. With `nested_skip` nonzero, a
 * read of every column leaves nested columns (lists, maps, groups) out;
 * otherwise it is an error naming them. Returns NULL on failure.
 */
dta_pq_file *dta_pq_open(const char *path, const uint8_t *bytes, size_t len, int nested_skip, char *err,
                         size_t err_len);

void dta_pq_close(dta_pq_file *file);

/*
 * The footer as a JSON object (free it with dta_string_free): rows,
 * row_groups [{rows, compressed_bytes, uncompressed_bytes}], created_by,
 * compression (the codecs used), warnings (about the dta profile),
 * profile (whether there is one), label, notes, timestamp, sort,
 * characteristics [{variable, name, value}], valueLabels [{name, labels:
 * [[value or ".a"..".z", text], ...]}], and columns, one object per
 * top-level column: name, role ("data" or "nested"), physical_type,
 * logical_type, kind ("int8", "int16", "int32", "int64", "uint8" to
 * "uint64", "float", "double", "bool", "text", "binary", "date",
 * "timestamp" with unit ("ms", "us", "ns") and utc, "time" with unit,
 * "decimal" with precision and scale, "unsupported" with why, or
 * "nested"), zone (a timestamp's: the profile's, "" for an instant
 * without one, else ARROW:schema's), levels ("profile", "rows" or null:
 * whether it is a categorical, and where its levels come from),
 * categories and ordered (levels from the profile), storage and logical
 * (the profile's, on a DOUBLE column written so for .a to .z), label,
 * format, value_labels (the set's name), unit_profile, and nulls (whether
 * any row group's statistics count nulls, or do not say).
 */
char *dta_pq_info_json(dta_pq_file *file, size_t *len, char *err, size_t err_len);

/* dta_pq_output.kind */
enum {
    DTA_PQ_I8 = 1, DTA_PQ_I16 = 2, DTA_PQ_I32 = 3, DTA_PQ_I64 = 4, DTA_PQ_F32 = 5, DTA_PQ_F64 = 6,
    DTA_PQ_U8 = 7, DTA_PQ_U16 = 8, DTA_PQ_U32 = 9, DTA_PQ_U64 = 10,
    DTA_PQ_LEVELS = 11, /* int32 level codes in values: base for the first level, null for missing */
    DTA_PQ_TEXT = 12    /* through the callback */
};

/*
 * Where one selected column goes: `values` holds the window's rows of
 * the kind's type (0, or NaN in floats, for a missing value); `codes`,
 * NULL or one byte per row, receives 0 for a value, 1 for a null, 2 to
 * 27 for .a to .z (tagged NaNs in a DOUBLE column). A column reads into
 * a type that holds its values: DATE, TIMESTAMP and TIME as their counts
 * into DTA_PQ_I64, BOOLEAN into DTA_PQ_U8, a DOUBLE column the profile
 * gives a storage type into that type; a value the type cannot hold is
 * an error naming the column and row.
 */
typedef struct dta_pq_output {
    uint32_t kind;
    int32_t base;
    int32_t null;
    void *values;
    uint8_t *codes;
} dta_pq_output;

/*
 * Called on the calling thread with each column chunk of a text column
 * read as DTA_PQ_TEXT, in row order for each column: `k` is the column's
 * place in the selection, `first` the chunk's first row in the read.
 * Value i is bytes[ends[i-1]..ends[i]] (from 0 for i = 0). With a
 * dictionary, codes[r] is row r's value, or UINT32_MAX for a missing row,
 * and `missing` is NULL; without one, row r is value r, missing where
 * missing[r] is not 0 (`missing` may be NULL when none is). Return
 * nonzero to stop the read.
 */
typedef int (*dta_pq_text_fn)(void *user, size_t k, uint64_t first, uint64_t rows, const uint8_t *bytes,
                              const size_t *ends, size_t nvalues, const uint32_t *codes, const uint8_t *missing);

/*
 * Read rows skip to skip + n (clipped to the file) of the `ncols`
 * columns `cols` (0-based, any order) into `outputs`. Column chunks are
 * decoded on worker threads for large reads (DTA_THREADS sets the
 * count). *report receives a JSON object (free it with dta_string_free):
 * letters, per column whether any .a to .z was read, and levels, per
 * column the levels found in the rows read for a categorical whose
 * levels come from the rows (null otherwise). Returns the rows read, -2
 * when the callback stopped the read, or -1 on failure.
 */
int64_t dta_pq_read(dta_pq_file *file, const uint32_t *cols, size_t ncols, uint64_t skip, uint64_t n,
                    const dta_pq_output *outputs, dta_pq_text_fn callback, void *user, char **report,
                    size_t *report_len, char *err, size_t err_len);

/* dta_pq_column.kind */
enum {
    DTA_PQ_W_INT8 = 1, DTA_PQ_W_INT16 = 2, DTA_PQ_W_INT32 = 3, DTA_PQ_W_INT64 = 4, DTA_PQ_W_FLOAT = 5,
    DTA_PQ_W_DOUBLE = 6,
    DTA_PQ_W_BOOL = 7,        /* uint8_t, 0 or 1 */
    DTA_PQ_W_DATE = 8,        /* int64_t days since 0000-12-31 (Julia's Date) */
    DTA_PQ_W_DATETIME = 9,    /* int64_t milliseconds since 0000-12-31 00:00, without zone */
    DTA_PQ_W_ZONED = 10,      /* the same in UTC; the zone in the metadata */
    DTA_PQ_W_TEXT = 11,       /* UTF-8 bytes and nrows + 1 offsets */
    DTA_PQ_W_BINARY = 12,
    DTA_PQ_W_CATEGORICAL = 13 /* uint32_t level numbers from 1, 0 for missing */
};

/*
 * One column to write: `values` of the kind's type, `codes` NULL or one
 * byte per row (0 a value, 1 missing, 2 to 27 .a to .z; for text and
 * binary, nonzero is missing), `bytes` and `offsets` for text and binary.
 */
typedef struct dta_pq_column {
    uint32_t kind;
    const void *values;
    const uint8_t *codes;
    const uint8_t *bytes;
    const uint64_t *offsets;
} dta_pq_column;

/*
 * Write `ncols` columns of `nrows` rows as Parquet to `path`, beside it
 * and renamed into place; or, when `path` is NULL, to memory returned in
 * *out and *out_len (free it with dta_pq_bytes_free). `meta_json` is an
 * object: label, notes, timestamp, sort (column names), characteristics,
 * valueLabels (as dta_write's) and columns, one {name, label, format,
 * valueLabels, levels, ordered, zone} per column. `compression` is
 * "snappy", "zstd", "gzip", "lz4_raw" or "none"; `level` is used when
 * `has_level` is nonzero; `row_group_rows` 0 for the default;
 * `missing_letters` 0 writes .a to .z as nulls. Returns 0, or -1.
 */
int dta_pq_write(const char *path, uint64_t nrows, const dta_pq_column *columns, size_t ncols,
                 const char *meta_json, const char *compression, int level, int has_level,
                 uint64_t row_group_rows, int missing_letters, uint8_t **out, size_t *out_len, char *err,
                 size_t err_len);

void dta_pq_bytes_free(uint8_t *p, size_t len);

#ifdef __cplusplus
}
#endif

#endif
