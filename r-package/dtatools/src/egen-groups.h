#ifndef DTATOOLS_EGEN_GROUPS_H
#define DTATOOLS_EGEN_GROUPS_H

#include "dtatools-internal.h"

/* Stable multicolumn ordering over compact readers. Scratch space contains
 * row positions, cached UTF-8 references and prepared numeric order keys.
 * Source columns stay compact. */
#include <R_ext/Memory.h>

/* Private structural counters keep the preparation bound testable without
   timing assertions. Counters are enabled only by the diagnostic reset. */
static int egen_group_counting = 0;
static double egen_group_scalar_values = 0;
static double egen_group_prepared_values = 0;
static double egen_group_prepared_bytes = 0;

SEXP C_dtatools_egen_group_stats(SEXP reset) {
    if (Rf_asLogical(reset) == TRUE) {
        egen_group_scalar_values = egen_group_prepared_values = 0;
        egen_group_prepared_bytes = 0;
        egen_group_counting = 1;
    }
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 3));
    REAL(result)[0] = egen_group_scalar_values;
    REAL(result)[1] = egen_group_prepared_values;
    REAL(result)[2] = egen_group_prepared_bytes;
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 3));
    SET_STRING_ELT(names, 0, Rf_mkChar("scalar_values"));
    SET_STRING_ELT(names, 1, Rf_mkChar("prepared_values"));
    SET_STRING_ELT(names, 2, Rf_mkChar("prepared_bytes"));
    Rf_setAttrib(result, R_NamesSymbol, names);
    if (Rf_asLogical(reset) != TRUE) egen_group_counting = 0;
    UNPROTECT(2);
    return result;
}

static double egen_group_scalar(const numeric_reader *reader, R_xlen_t index,
                                int *missing, int allow_nan) {
    if (egen_group_counting) egen_group_scalar_values++;
    return egen_numeric_at(reader, index, missing, allow_nan);
}

typedef struct {
    SEXP column;
    const char **strings;
    uint64_t *prepared; /* Eight bytes per row for wholly known numeric keys. */
    numeric_reader numeric;
    int string;
    int allow_nan;
} egen_key_reader;

static int egen_key_compare(egen_key_reader *keys, R_xlen_t count,
                            R_xlen_t left, R_xlen_t right) {
    for (R_xlen_t k = 0; k < count; k++) {
        if (keys[k].string) {
            int comparison = strcmp(keys[k].strings[left], keys[k].strings[right]);
            if (comparison) return comparison < 0 ? -1 : 1;
        } else if (keys[k].prepared != NULL) {
            uint64_t a = keys[k].prepared[left], b = keys[k].prepared[right];
            if (a != b) return a < b ? -1 : 1;
        } else {
            int am, bm;
            double a = egen_group_scalar(&keys[k].numeric, left, &am, keys[k].allow_nan);
            double b = egen_group_scalar(&keys[k].numeric, right, &bm, keys[k].allow_nan);
            if (am != bm) return am < bm ? -1 : 1;
            if (am < 0 && a != b) return a < b ? -1 : 1;
        }
    }
    return 0;
}

/* Validation has already excluded infinities, unsupported NaNs and values
   outside Stata double's observed range. Ordered IEEE bits preserve numeric
   order, with both zero signs sharing one key. The top 27 keys hold . through
   .z and lie above every admitted observed value. No R NaN is reconstructed
   while comparing these private keys. */
static uint64_t egen_group_order_key(double value, int missing) {
    if (missing >= 0) {
        unsigned rank = missing == 0 ? 0 : (unsigned) (missing - 'a' + 1);
        return UINT64_MAX - 26 + rank;
    }
    uint64_t bits = 0;
    if (value != 0) memcpy(&bits, &value, sizeof(bits));
    return bits & UINT64_C(0x8000000000000000)
        ? ~bits : bits ^ UINT64_C(0x8000000000000000);
}

/* A foreign numeric/string provider or class can mutate another key while
   admission or sorting runs. Keep the complete scalar route for those calls,
   including its callback order. Only wholly known numeric inputs prepare
   keys. Their row-major validation remains exactly where it was. */
static int egen_group_can_prepare(SEXP columns, SEXP include_missing, SEXP allow_nan) {
    if (ALTREP(columns) || ALTREP(include_missing) || ALTREP(allow_nan)) return 0;
    for (R_xlen_t k = 0; k < XLENGTH(columns); k++) {
        SEXP value = VECTOR_ELT(columns, k);
        if (TYPEOF(value) != REALSXP && TYPEOF(value) != INTSXP &&
            TYPEOF(value) != LGLSXP) return 0;
        if (ALTREP(value) && !owned_column(value) &&
            unmaterialized_numeric_read_storage(value) == NULL) return 0;
        SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
        if (classes != R_NilValue &&
            (TYPEOF(classes) != STRSXP || ALTREP(classes))) return 0;
    }
    return 1;
}

/* All allocations precede reader preparation. Known ordinary readers borrow
   their captured allocation, and compact readers use the descriptor captured
   with its matching root. No pointer is recovered from a public handle after
   callbacks could have replaced its backing. The region read and validation
   loops allocate nothing and invoke no R callbacks. */
static R_xlen_t egen_group_prepare(
    egen_key_reader *keys, egen_block_reader *readers, SEXP roots,
    R_xlen_t count, R_xlen_t n, int missing, R_xlen_t *order
) {
    if (n != 0 && (size_t) count > SIZE_MAX / sizeof(uint64_t) / (size_t) n)
        Rf_error("Grouping numeric key storage is too large");
    for (R_xlen_t k = 0; k < count; k++) {
        keys[k].prepared = (uint64_t *) R_alloc((size_t) n, sizeof(uint64_t));
        if (egen_group_counting)
            egen_group_prepared_bytes += (double) n * sizeof(uint64_t);
    }
    /* Bound decode scratch to 8,192 values except for wider one-row tiles.
       Only the final eight-byte keys grow with both rows and columns. */
    R_xlen_t rows = count < 8192 ? 8192 / count : 1;
    size_t slots = (size_t) rows * (size_t) count;
    double *values = (double *) R_alloc(slots, sizeof(double));
    int *codes = (int *) R_alloc(slots, sizeof(int));
    for (R_xlen_t k = 0; k < count; k++)
        egen_prepare_reader(readers + k, VECTOR_ELT(roots, k), n);
    R_xlen_t admitted = 0;
    for (R_xlen_t start = 0; start < n;) {
        R_CheckUserInterrupt();
        R_xlen_t length = n - start < rows ? n - start : rows;
        for (R_xlen_t k = 0; k < count; k++) {
            size_t offset = (size_t) k * (size_t) rows;
            numeric_reader_region(&readers[k].reader, start, length,
                                  values + offset, codes + offset);
        }
        /* Decode without validation above; validate in the original row/key
           order so two invalid inputs keep their existing error precedence. */
        for (R_xlen_t row = 0; row < length; row++) {
            int eligible = 1;
            for (R_xlen_t k = 0; k < count; k++) {
                size_t offset = (size_t) k * (size_t) rows + (size_t) row;
                int code = codes[offset];
                double value = egen_block_value(readers + k, start + row,
                    values[offset], &code, keys[k].allow_nan);
                keys[k].prepared[start + row] = egen_group_order_key(value, code);
                if (!missing && code >= 0) eligible = 0;
            }
            if (eligible) order[admitted++] = start + row;
        }
        start += length;
    }
    if (egen_group_counting)
        egen_group_prepared_values += (double) n * (double) count;
    return admitted;
}

SEXP dtatools_egen_group(SEXP columns, SEXP include_missing,
                               SEXP allow_nan) {
    if (TYPEOF(columns) != VECSXP || XLENGTH(columns) == 0)
        Rf_error("Supply at least one grouping column");
    R_xlen_t count = XLENGTH(columns);
    int prepare = egen_group_can_prepare(columns, include_missing, allow_nan);
    egen_block_reader *readers = prepare
        ? (egen_block_reader *) R_alloc((size_t) count, sizeof(egen_block_reader)) : NULL;
    int source_rooted = prepare;
    SEXP sources = prepare ? PROTECT(Rf_allocVector(VECSXP, count)) : columns;
    /* Numeric readers survive callbacks from every other key, including
       foreign string Elt methods during admission and numeric Elt in sort. */
    SEXP read_roots = PROTECT(Rf_allocVector(VECSXP, count));
    if (prepare) {
        for (R_xlen_t k = 0; k < count; k++)
            SET_VECTOR_ELT(sources, k, VECTOR_ELT(columns, k));
        /* Allocation can run finalizers on some R builds. Recheck before
           reading classes, then capture temporal policy without allocation. */
        prepare = egen_group_can_prepare(sources, include_missing, allow_nan);
        if (prepare) for (R_xlen_t k = 0; k < count; k++) {
            readers[k].source = VECTOR_ELT(sources, k);
            egen_prepare_temporal(readers + k);
        }
    }
    for (R_xlen_t k = 0; k < count; k++) {
        SEXP column = VECTOR_ELT(prepare ? sources : columns, k);
        SET_VECTOR_ELT(read_roots, k, prepare
            ? egen_capture_reader(column, readers + k) : numeric_payload_root(column));
    }
    R_xlen_t n = XLENGTH(VECTOR_ELT(prepare ? sources : columns, 0));
    if (n > INT_MAX) Rf_error("Grouping currently supports at most INT_MAX rows");
    egen_key_reader *keys = (egen_key_reader *) R_alloc(count, sizeof(egen_key_reader));
    /* Root every cached CHARSXP, including strings produced by an ALTREP
     * element method that does not itself retain the returned string. The
     * cached CHAR pointers then survive all allocations and GC during sort. */
    SEXP string_roots = PROTECT(Rf_allocVector(VECSXP, count));
    for (R_xlen_t k = 0; k < count; k++) {
        SEXP column = VECTOR_ELT(prepare ? sources : columns, k);
        if (XLENGTH(column) != n) Rf_error("Grouping columns must have equal lengths");
        keys[k].column = column;
        keys[k].prepared = NULL;
        keys[k].string = TYPEOF(column) == STRSXP;
        keys[k].allow_nan = Rf_asLogical(allow_nan) == TRUE;
        if (keys[k].string) {
            keys[k].strings = (const char **) R_alloc(n, sizeof(const char *));
            SEXP cache = PROTECT(Rf_allocVector(STRSXP, n));
            SET_VECTOR_ELT(string_roots, k, cache);
            UNPROTECT(1);
        } else if (!prepare) keys[k].numeric = numeric_reader_create(column, n);
    }
    R_xlen_t *order = (R_xlen_t *) R_alloc(n, sizeof(R_xlen_t));
    R_xlen_t *scratch = (R_xlen_t *) R_alloc(n, sizeof(R_xlen_t));
    int missing = Rf_asLogical(include_missing);
    R_xlen_t admitted = prepare
        ? egen_group_prepare(keys, readers, read_roots, count, n, missing, order) : 0;
    if (!prepare) {
        for (R_xlen_t row = 0; row < n; row++) {
            if ((row & 16383) == 0) R_CheckUserInterrupt();
            int eligible = 1;
            for (R_xlen_t k = 0; k < count; k++) {
                if (keys[k].string) {
                    const void *temporary = vmaxget();
                    SEXP value = PROTECT(STRING_ELT(keys[k].column, row));
                    if (value == NA_STRING) Rf_error("Grouping keys cannot contain NA_character_");
                    if (!missing && LENGTH(value) == 0) eligible = 0;
                    SEXP translated = Rf_mkCharCE(Rf_translateCharUTF8(value), CE_UTF8);
                    SET_STRING_ELT(VECTOR_ELT(string_roots, k), row, translated);
                    keys[k].strings[row] = CHAR(translated);
                    UNPROTECT(1);
                    /* A Latin-1/native translation may allocate a temporary
                     * buffer. The interned, rooted copy above owns the bytes
                     * used by the comparator, so release that buffer now. */
                    vmaxset(temporary);
                } else {
                    int code;
                    egen_group_scalar(&keys[k].numeric, row, &code, keys[k].allow_nan);
                    if (!missing && code >= 0) eligible = 0;
                }
            }
            if (eligible) order[admitted++] = row;
        }
    }
    for (R_xlen_t width = 1; width < admitted; width *= 2) {
        for (R_xlen_t start = 0; start < admitted; start += 2 * width) {
            R_CheckUserInterrupt();
            R_xlen_t middle = start + width < admitted ? start + width : admitted;
            R_xlen_t end = start + 2 * width < admitted ? start + 2 * width : admitted;
            R_xlen_t left = start, right = middle, out = start;
            while (left < middle && right < end) {
                if ((out & 16383) == 0) R_CheckUserInterrupt();
                scratch[out++] = egen_key_compare(keys, count, order[left], order[right]) <= 0
                    ? order[left++] : order[right++];
            }
            while (left < middle) {
                if ((out & 16383) == 0) R_CheckUserInterrupt();
                scratch[out++] = order[left++];
            }
            while (right < end) {
                if ((out & 16383) == 0) R_CheckUserInterrupt();
                scratch[out++] = order[right++];
            }
        }
        R_xlen_t *swap = order; order = scratch; scratch = swap;
    }
    SEXP codes = PROTECT(Rf_allocVector(REALSXP, n));
    for (R_xlen_t row = 0; row < n; row++) {
        if ((row & 16383) == 0) R_CheckUserInterrupt();
        REAL(codes)[row] = NA_REAL;
    }
    R_xlen_t groups = 0;
    for (R_xlen_t i = 0; i < admitted; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        if (!i || egen_key_compare(keys, count, order[i - 1], order[i]))
            scratch[groups++] = order[i];
        REAL(codes)[order[i]] = (double) groups;
    }
    SEXP first = PROTECT(Rf_allocVector(INTSXP, groups));
    for (R_xlen_t i = 0; i < groups; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        INTEGER(first)[i] = (int) scratch[i] + 1;
    }
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 2));
    SEXP owned = PROTECT(owned_adopt_real(codes));
    SET_VECTOR_ELT(result, 0, owned); SET_VECTOR_ELT(result, 1, first);
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 2));
    SET_STRING_ELT(names, 0, Rf_mkChar("codes"));
    SET_STRING_ELT(names, 1, Rf_mkChar("first"));
    Rf_setAttrib(result, R_NamesSymbol, names);
    UNPROTECT(7 + source_rooted);
    return result;
}

#endif /* DTATOOLS_EGEN_GROUPS_H */
