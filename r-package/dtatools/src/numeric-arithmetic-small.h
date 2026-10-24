/* `.dta_arith_base()` for operands under the size gate (ADR 0059). It takes
   the four base operators while base still binds the primitives in
   `.numeric_binary_dependencies`. One operand must be a compact Stata
   numeric, value labels allowed, or a canonical double. The other must be
   another or a bare double, integer or logical vector without attributes.
   It reads the values as `.dta_data()` does, recycles an operand of length
   one as `vctrs::vec_recycle_common()` does, applies the operator, makes
   each position where either operand is missing system missing, as
   `.collapse_missing()` does, and builds the result as `.dta_computed()`
   builds a small one. It peeks at the operands and the operator in the
   caller's frame, declines while any of them is a promise that would
   evaluate a call, and forces them in the R code's order before computing.
   It forces `minimum` after computing, as the R code does. Where it cannot
   build the result for that `minimum`, it calls `.dta_computed()` with the
   values, and where R code run by `minimum` has bound `native` in the
   frame, it returns the result from the frame, so the R code never
   computes it again. It does not prove the helpers it skips. Like the
   routes above, it binds the result to `native` in the caller's frame and
   returns TRUE, or returns FALSE, so the R code runs. */
static int arithmetic_class_is(SEXP classes, R_xlen_t i, const char *expected) {
    SEXP name = STRING_ELT(classes, i);
    return name != NA_STRING && strcmp(CHAR(name), expected) == 0;
}

/* A compact Stata numeric with the classes the package gives one, with
   haven_labelled when it carries value labels. `.dta_data()` drops every
   attribute but names, so labels and formats do not change the values the
   R code computes with. A names attribute would carry to the result. */
static int arithmetic_small_compact(SEXP value, int *kind) {
    static const char *storages[] = {"dta_byte", "dta_int", "dta_long", "dta_float"};
    if (TYPEOF(value) != REALSXP || Rf_isS4(value)) return 0;
    numeric_data *data = unmaterialized_numeric_read_storage(value);
    if (data == NULL || data->temporal != 0 || data->kind < NUMERIC_BYTE ||
        data->kind > NUMERIC_FLOAT || Rf_getAttrib(value, R_NamesSymbol) != R_NilValue)
        return 0;
    SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
    R_xlen_t count = TYPEOF(classes) == STRSXP && !ALTREP(classes) ? XLENGTH(classes) : 0;
    if ((count != 4 && count != 5) || !arithmetic_class_is(classes, 0, "dta_numeric") ||
        (count == 5 && !arithmetic_class_is(classes, 2, "haven_labelled")) ||
        !arithmetic_class_is(classes, count - 2, "vctrs_vctr") ||
        !arithmetic_class_is(classes, count - 1, "double")) return 0;
    for (int i = 0; i < 4; i++) if (arithmetic_class_is(classes, 1, storages[i])) {
        *kind = data->kind;
        return 1;
    }
    return 0;
}

SEXP C_dtatools_arithmetic_small(void) {
    SEXP frame = R_GetCurrentEnv();
    if (numeric_size_minimum == 0 || !numeric_result_slot_available(frame))
        return Rf_ScalarLogical(FALSE);
    static SEXP op_symbol = NULL, x_symbol = NULL, y_symbol = NULL;
    if (op_symbol == NULL) {
        op_symbol = Rf_install("op");
        x_symbol = Rf_install("x");
        y_symbol = Rf_install("y");
    }
    SEXP op = PROTECT(computed_peek(op_symbol, frame, 16));
    int operation = 0;
    if (TYPEOF(op) == STRSXP && !ALTREP(op) && !ANY_ATTRIB(op) && XLENGTH(op) == 1 &&
        STRING_ELT(op, 0) != NA_STRING) {
        const char *name = CHAR(STRING_ELT(op, 0));
        if (name[0] != '\0' && name[1] == '\0' && strchr("+-*/", name[0]) != NULL)
            operation = name[0];
    }
    SEXP x = PROTECT(computed_peek(x_symbol, frame, 16));
    SEXP y = PROTECT(computed_peek(y_symbol, frame, 16));
    int x_kind = -1, y_kind = -1;
    if (operation == 0 ||
        !(arithmetic_small_compact(x, &x_kind) || arithmetic_operand_kind(x, &x_kind)) ||
        !(arithmetic_small_compact(y, &y_kind) || arithmetic_operand_kind(y, &y_kind)) ||
        (x_kind < 0 && y_kind < 0) ||
        !arithmetic_operator_unchanged(frame, operation)) {
        UNPROTECT(3);
        return Rf_ScalarLogical(FALSE);
    }
    /* vctrs recycles an operand of length one and rejects other unequal
       lengths, which the R code reports. */
    R_xlen_t x_length = XLENGTH(x), y_length = XLENGTH(y);
    R_xlen_t length = x_length == y_length ? x_length :
        x_length == 1 ? y_length : y_length == 1 ? x_length : -1;
    if (length <= 0 || length >= numeric_size_minimum) {
        UNPROTECT(3);
        return Rf_ScalarLogical(FALSE);
    }
    /* Settle the operands and then the operator, in the R code's order,
       before R code run by `minimum` could rebind what their promises
       forward to. Each peek followed only values and symbols, so forcing
       runs no R code and finds the values peeked. */
    if (R_getVar(x_symbol, frame, TRUE) != x || R_getVar(y_symbol, frame, TRUE) != y ||
        R_getVar(op_symbol, frame, TRUE) != op) {
        UNPROTECT(3);
        return Rf_ScalarLogical(FALSE);
    }
    PROTECT(numeric_payload_root(x));
    PROTECT(numeric_payload_root(y));
    numeric_reader x_reader = numeric_reader_create(x, x_length);
    numeric_reader y_reader = numeric_reader_create(y, y_length);
    double *x_values = (double *) R_alloc((size_t) x_length, sizeof(double));
    double *y_values = (double *) R_alloc((size_t) y_length, sizeof(double));
    int *x_codes = (int *) R_alloc((size_t) x_length, sizeof(int));
    int *y_codes = (int *) R_alloc((size_t) y_length, sizeof(int));
    numeric_reader_region(&x_reader, 0, x_length, x_values, x_codes);
    numeric_reader_region(&y_reader, 0, y_length, y_values, y_codes);
    SEXP result = PROTECT(Rf_allocVector(REALSXP, length));
    double *output = REAL(result);
    for (R_xlen_t i = 0; i < length; i++) {
        R_xlen_t left = x_length == 1 ? 0 : i, right = y_length == 1 ? 0 : i;
        /* A missing code marks every value `is.na()` reports. */
        if (x_codes[left] >= 0 || y_codes[right] >= 0) {
            output[i] = NA_REAL;
            continue;
        }
        double a = x_values[left], b = y_values[right];
        output[i] = operation == '+' ? a + b : operation == '-' ? a - b :
            operation == '*' ? a * b : a / b;
    }
    SEXP minimum = PROTECT(R_getVar(numeric_minimum_symbol, frame, TRUE));
    SEXP built = PROTECT(numeric_computed_small(result, minimum));
    if (built == R_NilValue) {
        /* Forcing `minimum` can run R code, which could change an operand
           or rebind `minimum`, so finish as the R code does, from the
           values computed before and the value `minimum` gave. */
        static SEXP computed_symbol = NULL, quote_symbol = NULL;
        if (computed_symbol == NULL) computed_symbol = Rf_install(".dta_computed");
        if (quote_symbol == NULL) quote_symbol = Rf_install("quote");
        SEXP argument = minimum;
        switch (TYPEOF(minimum)) {
        case SYMSXP: case LANGSXP: case PROMSXP: case DOTSXP: case BCODESXP:
            /* Base's `quote()` keeps a value `eval()` would evaluate. */
            argument = Rf_lang2(R_getVar(quote_symbol, R_BaseEnv, FALSE), minimum);
            break;
        default:
            break;
        }
        PROTECT(argument);
        SEXP call = PROTECT(Rf_lang3(computed_symbol, result, argument));
        built = Rf_eval(call, frame);
        UNPROTECT(3);
        PROTECT(built);
    }
    if (!numeric_result_slot_available(frame)) {
        /* R code run by `minimum` bound `native` in the frame. Return the
           result from the frame, as `.native_admission_return()` does in
           the R code, instead of letting the R code compute it again. */
        static SEXP return_symbol = NULL;
        if (return_symbol == NULL) return_symbol = Rf_install(".native_admission_return");
        SEXP jump = computed_peek(return_symbol, frame, 16);
        if (TYPEOF(jump) == SPECIALSXP) {
            SEXP call = PROTECT(Rf_lang2(jump, built));
            Rf_eval(call, frame);
            UNPROTECT(1);
        }
    }
    SEXP status = numeric_result_commit(built, frame);
    UNPROTECT(8);
    return status;
}
