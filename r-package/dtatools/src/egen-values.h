#ifndef DTATOOLS_EGEN_VALUES_H
#define DTATOOLS_EGEN_VALUES_H

#include "dtatools-internal.h"

/* Numeric egen calculations share the compact reader with mutation. Readers
   use element access for foreign ALTREP inputs and never request DATAPTR. */
static double egen_numeric_at(const numeric_reader *reader, R_xlen_t index,
                              int *missing, int allow_nan) {
    double value = numeric_reader_at(reader, index, missing);
    if (*missing == 256 && allow_nan && reader->type == REALSXP &&
        tagged_na_tag_value(REAL_ELT(reader->value, index)) == 0) {
        *missing = 0;
    }
    if (*missing == 256 || !R_FINITE(value)) {
        Rf_error("Calculation inputs cannot contain NaN, unsupported missing tags, or infinities");
    }
    if (*missing < 0) {
        if (Rf_inherits(reader->value, "Date")) value += 3653.0;
        else if (Rf_inherits(reader->value, "POSIXct")) {
            value = (value + 315619200.0) * 1000.0;
        }
        if (!R_FINITE(value) || fabs(value) > DBL_MAX / 2.0) {
            Rf_error("Calculation input cannot be represented by Stata double storage");
        }
    }
    return value;
}

static double egen_missing_result(int code) {
    return code == 0 ? NA_REAL : numeric_missing_value(code - 'a' + 1);
}

typedef struct {
    SEXP source;
    numeric_reader reader;
    numeric_data storage;
    int compact;
    int temporal;
} egen_block_reader;

/* Capture each allocation before allocating decode buffers or entering another
   operand's methods. A retained capture owns a private descriptor as well as
   the bytes, so materializing the public handle cannot invalidate the reader. */
static SEXP egen_capture_reader(SEXP value, egen_block_reader *reader) {
    reader->source = value;
    SEXP root = numeric_missing_mask_capture(value, &reader->storage);
    reader->compact = root != R_NilValue;
    return reader->compact ? root : numeric_payload_root(value);
}

static void egen_prepare_reader(egen_block_reader *reader, SEXP root,
                                R_xlen_t size) {
    SEXP value = reader->source;
    if (reader->compact) {
        if ((R_xlen_t) reader->storage.length != size) {
            Rf_error("dtatools numeric storage length does not match vector length");
        }
        reader->reader = (numeric_reader) {
            value, &reader->storage, NULL, NULL, REALSXP
        };
    } else {
        /* Known ordinary allocation roots give the pointer its own lifetime.
           Unknown ALTREP values retain their original element-method path. */
        int known = !ALTREP(value) || owned_column(value) ||
            R_altrep_inherits(value, dtatools_numeric_class) ||
            R_altrep_inherits(value, dtatools_metadata_real_class);
        SEXP input = known && !ALTREP(root) && TYPEOF(root) == TYPEOF(value)
            ? root : value;
        reader->reader = numeric_reader_create(input, size);
    }
}

static int egen_block_readable(const egen_block_reader *reader) {
    const numeric_reader *input = &reader->reader;
    if (input->storage == NULL && input->real_values == NULL &&
        input->integer_values == NULL) return 0;
    if (input->storage == NULL && ALTREP(input->value)) return 0;
    SEXP classes = Rf_getAttrib(reader->source, R_ClassSymbol);
    return classes == R_NilValue || (TYPEOF(classes) == STRSXP && !ALTREP(classes));
}

static void egen_prepare_temporal(egen_block_reader *reader) {
    SEXP value = reader->source;
    reader->temporal = Rf_inherits(value, "Date") ? 1
        : (Rf_inherits(value, "POSIXct") ? 2 : 0);
}

static double egen_scalar_value(const egen_block_reader *reader, R_xlen_t index,
                                 int *missing, int allow_nan) {
    numeric_reader scalar = reader->reader;
    scalar.value = reader->source;
    return egen_numeric_at(&scalar, index, missing, allow_nan);
}

static double egen_block_value(const egen_block_reader *reader, R_xlen_t index,
                                double value, int *code, int allow_nan) {
    if (*code == 256 && allow_nan && reader->reader.type == REALSXP) {
        /* Compact IEEE float NaNs cannot encode the double payload used for
           unsupported tags. Ordinary doubles still need that exact check. */
        if (reader->reader.storage != NULL ||
            tagged_na_tag_value(reader->reader.real_values[index]) == 0) {
            *code = 0;
        }
    }
    if (*code == 256 || !R_FINITE(value)) {
        Rf_error("Calculation inputs cannot contain NaN, unsupported missing tags, or infinities");
    }
    if (*code < 0) {
        if (reader->temporal == 1) value += 3653.0;
        else if (reader->temporal == 2) value = (value + 315619200.0) * 1000.0;
        if (!R_FINITE(value) || fabs(value) > DBL_MAX / 2.0) {
            Rf_error("Calculation input cannot be represented by Stata double storage");
        }
    }
    return value;
}

SEXP C_dtatools_egen_summary(SEXP input, SEXP operation, SEXP missing,
                           SEXP allow_nan) {
    int op = Rf_asInteger(operation), include = Rf_asLogical(missing);
    R_xlen_t size = XLENGTH(input), observed = 0;
    egen_block_reader reader = {0};
    SEXP root = PROTECT(egen_capture_reader(input, &reader));
    egen_prepare_reader(&reader, root, size);
    /* Stata accumulates in input order at double precision. In particular,
       1e16 + 1 - 1e16 is zero. Extended precision varies by architecture. */
    double total = 0.0;
    double extreme = 0.0;
    int extreme_missing = -1, any_missing = 0;
    if (egen_block_readable(&reader) && !ALTREP(allow_nan)) {
        const R_xlen_t capacity = 2048;
        double *values = (double *) R_alloc((size_t) capacity, sizeof(double));
        int *codes = (int *) R_alloc((size_t) capacity, sizeof(int));
        int permit_nan = Rf_asLogical(allow_nan);
        egen_prepare_temporal(&reader);
        for (R_xlen_t start = 0; start < size;) {
            R_CheckUserInterrupt();
            R_xlen_t length = size - start < capacity ? size - start : capacity;
            numeric_reader_region(&reader.reader, start, length, values, codes);
            for (R_xlen_t offset = 0; offset < length; offset++) {
                int code = codes[offset];
                double value = egen_block_value(&reader, start + offset,
                                                values[offset], &code, permit_nan);
                if (code >= 0) {
                    if (!any_missing || (op == 1 ? code < extreme_missing
                                                : code > extreme_missing)) {
                        extreme_missing = code;
                    }
                    any_missing = 1;
                    continue;
                }
                if (!observed || (op == 1 ? value < extreme : value > extreme)) {
                    extreme = value;
                }
                total += value;
                observed++;
            }
            start += length;
        }
    } else {
        for (R_xlen_t row = 0; row < size; row++) {
            if ((row & 16383) == 0) R_CheckUserInterrupt();
            int code;
            double value = egen_scalar_value(&reader, row, &code,
                                            Rf_asLogical(allow_nan));
            if (code >= 0) {
                if (!any_missing || (op == 1 ? code < extreme_missing
                                            : code > extreme_missing)) {
                    extreme_missing = code;
                }
                any_missing = 1;
                continue;
            }
            if (!observed || (op == 1 ? value < extreme : value > extreme)) {
                extreme = value;
            }
            total += value;
            observed++;
        }
    }
    double result;
    if (op == 0) result = observed ? total / observed : NA_REAL;
    else if (op == 3) result = !observed && include ? NA_REAL : total;
    else if (include && any_missing && (op == 2 || !observed)) {
        result = egen_missing_result(extreme_missing);
    } else result = observed ? extreme : NA_REAL;
    if (!ISNAN(result) && !R_FINITE(result)) result = NA_REAL;
    SEXP scalar = PROTECT(Rf_ScalarReal(result));
    UNPROTECT(2);
    return scalar;
}

SEXP C_dtatools_egen_rows(SEXP columns, SEXP operation, SEXP missing,
                        SEXP allow_nan) {
    R_xlen_t count = XLENGTH(columns);
    if (TYPEOF(columns) != VECSXP || count == 0) {
        Rf_error("At least one numeric column is required");
    }
    /* Later Length/Dataptr_or_null/Elt methods can materialize an earlier
       public handle. Keep each allocation alive independently of that handle;
       the protection stack releases these roots on errors and interrupts. */
    SEXP read_roots = PROTECT(Rf_allocVector(VECSXP, count));
    egen_block_reader *readers = (egen_block_reader *) R_alloc(
        (size_t) count, sizeof(egen_block_reader)
    );
    memset(readers, 0, (size_t) count * sizeof(egen_block_reader));
    for (R_xlen_t column = 0; column < count; column++) {
        SET_VECTOR_ELT(read_roots, column,
                       egen_capture_reader(VECTOR_ELT(columns, column), &readers[column]));
    }
    R_xlen_t size = XLENGTH(VECTOR_ELT(columns, 0));
    int op = Rf_asInteger(operation), include = Rf_asLogical(missing);
    int block = !ALTREP(allow_nan);
    for (R_xlen_t column = 0; column < count; column++) {
        SEXP value = VECTOR_ELT(columns, column);
        if (XLENGTH(value) != size) Rf_error("Columns must have equal lengths");
        egen_prepare_reader(&readers[column], VECTOR_ELT(read_roots, column), size);
        if (!egen_block_readable(&readers[column])) block = 0;
    }
    SEXP result = PROTECT(Rf_allocVector(REALSXP, size));
    /* This ordinary result stays private until all input callbacks finish. */
    double *output = REAL(result);
    if (block) {
        /* Bound the complete column-by-row tile, then validate and fold in
           row-major order. This keeps both error precedence and column order. */
        R_xlen_t rows = count < 8192 ? 8192 / count : 1;
        size_t slots = (size_t) rows * (size_t) count;
        double *values = (double *) R_alloc(slots, sizeof(double));
        int *codes = (int *) R_alloc(slots, sizeof(int));
        int permit_nan = Rf_asLogical(allow_nan);
        for (R_xlen_t column = 0; column < count; column++) {
            egen_prepare_temporal(&readers[column]);
        }
        for (R_xlen_t start = 0; start < size;) {
            R_CheckUserInterrupt();
            R_xlen_t length = size - start < rows ? size - start : rows;
            for (R_xlen_t column = 0; column < count; column++) {
                size_t offset = (size_t) column * (size_t) rows;
                numeric_reader_region(&readers[column].reader, start, length,
                                      values + offset, codes + offset);
            }
            for (R_xlen_t row = 0; row < length; row++) {
                double total = 0.0, extreme = 0.0;
                int observed = 0;
                for (R_xlen_t column = 0; column < count; column++) {
                    size_t offset = (size_t) column * (size_t) rows + (size_t) row;
                    int code = codes[offset];
                    double value = egen_block_value(&readers[column], start + row,
                                                    values[offset], &code, permit_nan);
                    if (code >= 0) continue;
                    total += value;
                    if (!observed || value > extreme) extreme = value;
                    observed = 1;
                }
                double value = op == 2 ? (observed ? extreme : NA_REAL)
                    : (!observed && include ? NA_REAL : total);
                if (!ISNAN(value) && !R_FINITE(value)) value = NA_REAL;
                output[start + row] = value;
            }
            start += length;
        }
    } else {
        for (R_xlen_t row = 0; row < size; row++) {
            if ((row & 16383) == 0) R_CheckUserInterrupt();
            double total = 0.0;
            double extreme = 0.0;
            int observed = 0;
            for (R_xlen_t column = 0; column < count; column++) {
                int code;
                double value = egen_scalar_value(&readers[column], row, &code,
                                                Rf_asLogical(allow_nan));
                if (code >= 0) continue;
                total += value;
                if (!observed || value > extreme) extreme = value;
                observed = 1;
            }
            double value = op == 2 ? (observed ? extreme : NA_REAL)
                : (!observed && include ? NA_REAL : total);
            if (!ISNAN(value) && !R_FINITE(value)) value = NA_REAL;
            output[row] = value;
        }
    }
    SEXP owned = PROTECT(owned_adopt_real(result));
    UNPROTECT(3);
    return owned;
}

#endif /* DTATOOLS_EGEN_VALUES_H */
