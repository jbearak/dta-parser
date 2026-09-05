/* Stable multicolumn ordering over compact readers. Scratch space contains
 * row positions only; no numeric or string payload column is materialized. */
typedef struct {
    SEXP column;
    numeric_reader numeric;
    int string;
    int allow_nan;
} egen_key_reader;

static int egen_key_compare(egen_key_reader *keys, R_xlen_t count,
                            R_xlen_t left, R_xlen_t right) {
    for (R_xlen_t k = 0; k < count; k++) {
        if (keys[k].string) {
            const char *a = Rf_translateCharUTF8(STRING_ELT(keys[k].column, left));
            const char *b = Rf_translateCharUTF8(STRING_ELT(keys[k].column, right));
            int comparison = strcmp(a, b);
            if (comparison) return comparison < 0 ? -1 : 1;
        } else {
            int am, bm;
            double a = egen_numeric_at(&keys[k].numeric, left, &am, keys[k].allow_nan);
            double b = egen_numeric_at(&keys[k].numeric, right, &bm, keys[k].allow_nan);
            if (am != bm) return am < bm ? -1 : 1;
            if (am < 0 && a != b) return a < b ? -1 : 1;
        }
    }
    return 0;
}

static SEXP dtatools_egen_group(SEXP columns, SEXP include_missing,
                               SEXP allow_nan) {
    if (TYPEOF(columns) != VECSXP || XLENGTH(columns) == 0)
        Rf_error("Supply at least one grouping column");
    R_xlen_t count = XLENGTH(columns), n = XLENGTH(VECTOR_ELT(columns, 0));
    if (n > INT_MAX) Rf_error("Grouping currently supports at most INT_MAX rows");
    egen_key_reader *keys = (egen_key_reader *) R_alloc(count, sizeof(egen_key_reader));
    for (R_xlen_t k = 0; k < count; k++) {
        SEXP column = VECTOR_ELT(columns, k);
        if (XLENGTH(column) != n) Rf_error("Grouping columns must have equal lengths");
        keys[k].column = column;
        keys[k].string = TYPEOF(column) == STRSXP;
        keys[k].allow_nan = Rf_asLogical(allow_nan) == TRUE;
        if (!keys[k].string) keys[k].numeric = numeric_reader_create(column, n);
    }
    R_xlen_t *order = (R_xlen_t *) R_alloc(n, sizeof(R_xlen_t));
    R_xlen_t *scratch = (R_xlen_t *) R_alloc(n, sizeof(R_xlen_t));
    R_xlen_t admitted = 0;
    int missing = Rf_asLogical(include_missing);
    for (R_xlen_t row = 0; row < n; row++) {
        if ((row & 16383) == 0) R_CheckUserInterrupt();
        int eligible = 1;
        for (R_xlen_t k = 0; k < count; k++) {
            if (keys[k].string) {
                SEXP value = STRING_ELT(keys[k].column, row);
                if (value == NA_STRING) Rf_error("Grouping keys cannot contain NA_character_");
                if (!missing && LENGTH(value) == 0) eligible = 0;
            } else {
                int code;
                egen_numeric_at(&keys[k].numeric, row, &code, keys[k].allow_nan);
                if (!missing && code >= 0) eligible = 0;
            }
        }
        if (eligible) order[admitted++] = row;
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
    SET_VECTOR_ELT(result, 0, codes); SET_VECTOR_ELT(result, 1, first);
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 2));
    SET_STRING_ELT(names, 0, Rf_mkChar("codes"));
    SET_STRING_ELT(names, 1, Rf_mkChar("first"));
    Rf_setAttrib(result, R_NamesSymbol, names);
    UNPROTECT(4);
    return result;
}
