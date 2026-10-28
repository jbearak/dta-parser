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
#define DTA_ABI_VERSION 1

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

/* Free a string from dta_meta_json. NULL is ignored. */
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
 */
int dta_write(const char *path, uint64_t nrows, const dta_column *columns, size_t ncols, const char *meta_json,
              char *err, size_t err_len);

#ifdef __cplusplus
}
#endif

#endif
