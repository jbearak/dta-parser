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

SEXP C_dtatools_egen_summary(SEXP input, SEXP operation, SEXP missing,
                           SEXP allow_nan) {
    int op = Rf_asInteger(operation), include = Rf_asLogical(missing);
    R_xlen_t size = XLENGTH(input), observed = 0;
    numeric_reader reader = numeric_reader_create(input, size);
    /* Stata accumulates in input order at double precision. In particular,
       1e16 + 1 - 1e16 is zero. Extended precision varies by architecture. */
    double total = 0.0;
    double extreme = 0.0;
    int extreme_missing = -1, any_missing = 0;
    for (R_xlen_t row = 0; row < size; row++) {
        if ((row & 16383) == 0) R_CheckUserInterrupt();
        int code;
        double value = egen_numeric_at(&reader, row, &code, Rf_asLogical(allow_nan));
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
    double result;
    if (op == 0) result = observed ? total / observed : NA_REAL;
    else if (op == 3) result = !observed && include ? NA_REAL : total;
    else if (include && any_missing && (op == 2 || !observed)) {
        result = egen_missing_result(extreme_missing);
    } else result = observed ? extreme : NA_REAL;
    if (!ISNAN(result) && !R_FINITE(result)) result = NA_REAL;
    return Rf_ScalarReal(result);
}

SEXP C_dtatools_egen_rows(SEXP columns, SEXP operation, SEXP missing,
                        SEXP allow_nan) {
    R_xlen_t count = XLENGTH(columns);
    if (TYPEOF(columns) != VECSXP || count == 0) {
        Rf_error("At least one numeric column is required");
    }
    R_xlen_t size = XLENGTH(VECTOR_ELT(columns, 0));
    int op = Rf_asInteger(operation), include = Rf_asLogical(missing);
    numeric_reader *readers = (numeric_reader *) R_alloc(count, sizeof(numeric_reader));
    for (R_xlen_t column = 0; column < count; column++) {
        SEXP value = VECTOR_ELT(columns, column);
        if (XLENGTH(value) != size) Rf_error("Columns must have equal lengths");
        readers[column] = numeric_reader_create(value, size);
    }
    SEXP result = PROTECT(Rf_allocVector(REALSXP, size));
    for (R_xlen_t row = 0; row < size; row++) {
        if ((row & 16383) == 0) R_CheckUserInterrupt();
        double total = 0.0;
        double extreme = 0.0;
        int observed = 0;
        for (R_xlen_t column = 0; column < count; column++) {
            int code;
            double value = egen_numeric_at(&readers[column], row, &code,
                                          Rf_asLogical(allow_nan));
            if (code >= 0) continue;
            total += value;
            if (!observed || value > extreme) extreme = value;
            observed = 1;
        }
        double value = op == 2 ? (observed ? extreme : NA_REAL)
            : (!observed && include ? NA_REAL : total);
        if (!ISNAN(value) && !R_FINITE(value)) value = NA_REAL;
        REAL(result)[row] = value;
    }
    UNPROTECT(1);
    return result;
}
