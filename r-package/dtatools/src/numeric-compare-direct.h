/* `Ops.dta_numeric()` for the six comparisons, in one call (ADR 0060). The R
   code passes the operands through `.dta_compare()`, `.dta_compare_native()`
   and `.dta_compare_scalar()` to `C_dtatools_dta_compare()`. For operands
   whose checks and conversions there run no R code with effects, this call
   makes the same kernel calls in the same order and returns the first
   result, or declines so the R code runs. */

static int compare_class_is(SEXP classes, R_xlen_t i, const char *expected) {
    SEXP name = STRING_ELT(classes, i);
    return name != NA_STRING && strcmp(CHAR(name), expected) == 0;
}

/* A bare double, integer or logical vector, or a Stata numeric with the
   classes the package gives one, with haven_labelled when it carries value
   labels, without names and not temporal. `length()`, `inherits()` and
   `as.double()` run no other code on these. */
static int compare_direct_operand(SEXP value) {
    static const char *storages[] = {
        "dta_byte", "dta_int", "dta_long", "dta_float", "dta_double"
    };
    int type = TYPEOF(value);
    if ((type != REALSXP && type != INTSXP && type != LGLSXP) || Rf_isS4(value))
        return 0;
    if (!ANY_ATTRIB(value)) return !ALTREP(value) || owned_real(value);
    if (type != REALSXP || Rf_getAttrib(value, R_NamesSymbol) != R_NilValue) return 0;
    numeric_data *data = unmaterialized_numeric_read_storage(value);
    if (data == NULL ? ALTREP(value) && !owned_real(value) : data->temporal != 0)
        return 0;
    SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
    R_xlen_t count = TYPEOF(classes) == STRSXP && !ALTREP(classes) ? XLENGTH(classes) : 0;
    if ((count != 4 && count != 5) || !compare_class_is(classes, 0, "dta_numeric") ||
        (count == 5 && !compare_class_is(classes, 2, "haven_labelled")) ||
        !compare_class_is(classes, count - 2, "vctrs_vctr") ||
        !compare_class_is(classes, count - 1, "double")) return 0;
    for (int i = 0; i < 5; i++) if (compare_class_is(classes, 1, storages[i])) return 1;
    return 0;
}

/* `.dta_compare_scalar()` of a length-one operand: its value and rank, where
   rank 0 is observed, 1 is `.` and 2 through 27 are `.a` through `.z`. It
   returns 0 where that function returns NULL, for NaN and for other tagged
   payloads. */
static int compare_direct_scalar(SEXP value, double *plan) {
    int code = -1;
    double decoded = 0;
    PROTECT(numeric_payload_root(value));
    numeric_reader reader = numeric_reader_create(value, 1);
    numeric_reader_region(&reader, 0, 1, &decoded, &code);
    UNPROTECT(1);
    if (code < 0) {
        plan[0] = decoded;
        plan[1] = 0;
    } else if (code == 0) {
        plan[0] = 0;
        plan[1] = 1;
    } else if (code >= 'a' && code <= 'z') {
        plan[0] = 0;
        plan[1] = code - 'a' + 2;
    } else return 0;
    return 1;
}

/* `getOption("dtatools.threads", 0L)` as `.dta_compare_native()` settles it,
   or -1 for an option whose checks would run R code. */
static int compare_direct_threads(void) {
    SEXP option = Rf_GetOption1(Rf_install("dtatools.threads"));
    if (option == R_NilValue) return 0;
    if (ANY_ATTRIB(option) || ALTREP(option)) return -1;
    if (TYPEOF(option) == INTSXP) {
        if (XLENGTH(option) != 1 || INTEGER(option)[0] == NA_INTEGER ||
            INTEGER(option)[0] < 0) return 0;
        return INTEGER(option)[0];
    }
    if (TYPEOF(option) == REALSXP) {
        if (XLENGTH(option) != 1 || ISNAN(REAL(option)[0]) || REAL(option)[0] < 0)
            return 0;
        /* `as.integer()` warns above the integer range. */
        if (REAL(option)[0] >= 2147483648.0) return -1;
        return (int) REAL(option)[0];
    }
    return 0;
}

SEXP C_dtatools_compare_direct(void) {
    static const char *operators[] = {"==", "!=", "<", "<=", ">", ">="};
    static const int flipped[] = {0, 1, 4, 5, 2, 3};
    static SEXP generic_symbol = NULL, e1_symbol = NULL, e2_symbol = NULL;
    if (generic_symbol == NULL) {
        generic_symbol = Rf_install(".Generic");
        e1_symbol = Rf_install("e1");
        e2_symbol = Rf_install("e2");
    }
    SEXP frame = R_GetCurrentEnv();
    if (!numeric_result_slot_available(frame) ||
        R_GetBindingType(generic_symbol, frame) != R_BindingTypeValue)
        return Rf_ScalarLogical(FALSE);
    SEXP generic = R_getVar(generic_symbol, frame, FALSE);
    int op = -1;
    if (TYPEOF(generic) == STRSXP && !ALTREP(generic) && XLENGTH(generic) == 1 &&
        STRING_ELT(generic, 0) != NA_STRING)
        for (int i = 0; i < 6; i++)
            if (strcmp(CHAR(STRING_ELT(generic, 0)), operators[i]) == 0) op = i;
    if (op < 0) return Rf_ScalarLogical(FALSE);
    SEXP x = PROTECT(computed_peek(e1_symbol, frame, 16));
    SEXP y = PROTECT(computed_peek(e2_symbol, frame, 16));
    if (!compare_direct_operand(x) || !compare_direct_operand(y)) {
        UNPROTECT(2);
        return Rf_ScalarLogical(FALSE);
    }
    R_xlen_t x_length = XLENGTH(x), y_length = XLENGTH(y);
    int threads = compare_direct_threads();
    if (x_length == 0 || y_length == 0 || threads < 0 ||
        (x_length != y_length && x_length != 1 && y_length != 1)) {
        UNPROTECT(2);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP threads_value = PROTECT(Rf_ScalarInteger(threads));
    SEXP plan = PROTECT(Rf_allocVector(REALSXP, 2));
    SEXP result = R_NilValue;
    if (y_length == 1 && compare_direct_scalar(y, REAL(plan))) {
        SEXP code = PROTECT(Rf_ScalarInteger(op));
        result = C_dtatools_dta_compare(code, x, R_NilValue, plan, threads_value);
        UNPROTECT(1);
    }
    if (result == R_NilValue && x_length == 1 &&
        compare_direct_scalar(x, REAL(plan))) {
        /* Flip the operator so the vector stays on the left. */
        SEXP code = PROTECT(Rf_ScalarInteger(flipped[op]));
        result = C_dtatools_dta_compare(code, y, R_NilValue, plan, threads_value);
        UNPROTECT(1);
    }
    if (result == R_NilValue && x_length == y_length) {
        SEXP code = PROTECT(Rf_ScalarInteger(op));
        result = C_dtatools_dta_compare(code, x, y, R_NilValue, threads_value);
        UNPROTECT(1);
    }
    SEXP status = numeric_result_commit(result, frame);
    UNPROTECT(4);
    return status;
}
