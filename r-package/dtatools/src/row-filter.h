/* TRUE-only filter reduction adapts dplyr 1.2.1 src/filter.cpp at 95740975.
   See installed NOTICE. R retains predicate evaluation, validation and warning
   order. This private call-local buffer only reduces payloads and emits rows.
   Group planning supplies a validated complete partition of the input rows. */
static SEXP filter_storage(SEXP state) {
    if (TYPEOF(state) != EXTPTRSXP ||
        R_ExternalPtrTag(state) != Rf_install("dtatools_filter_state")) {
        Rf_error("invalid filter reduction state");
    }
    SEXP storage = R_ExternalPtrProtected(state);
    if (TYPEOF(storage) != RAWSXP || ALTREP(storage)) {
        Rf_error("expired filter reduction state");
    }
    return storage;
}

SEXP C_dtatools_filter_start(SEXP size) {
    if ((TYPEOF(size) != INTSXP && TYPEOF(size) != REALSXP) || XLENGTH(size) != 1) {
        Rf_error("invalid filter row count");
    }
    double count = Rf_asReal(size);
    if (!R_FINITE(count) || count < 0 || count != trunc(count) || count > INT_MAX) {
        Rf_error("invalid filter row count");
    }
    SEXP storage = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) count));
    memset(RAW(storage), 1, (size_t) count);
    /* The pointer owns no C allocation. Its protected slot roots the exact
       R-managed byte vector; no finalizer or global retained state is needed. */
    SEXP state = R_MakeExternalPtr(NULL, Rf_install("dtatools_filter_state"), storage);
    UNPROTECT(1);
    return state;
}

SEXP C_dtatools_filter_reduce(SEXP state, SEXP rows, SEXP value) {
    SEXP storage = PROTECT(filter_storage(state));
    if (TYPEOF(rows) != INTSXP || TYPEOF(value) != LGLSXP ||
        (XLENGTH(value) != 1 && XLENGTH(value) != XLENGTH(rows))) {
        Rf_error("invalid filter reduction input");
    }
    /* A foreign ALTREP element reader can allocate or run R. Root the exact
       backing records before taking owned pointers, since a callback can
       replace a handle's current record. Ordinary values remain R arguments. */
    SEXP row_record = PROTECT(owned_column(rows) ? R_altrep_data1(rows) : R_NilValue);
    SEXP value_record = PROTECT(owned_column(value) ? R_altrep_data1(value) : R_NilValue);
    const int *row_data = row_record != R_NilValue
        ? (const int *) R_ExternalPtrAddr(row_record)
        : (const int *) DATAPTR_RO(rows);
    const int *value_data = value_record != R_NilValue
        ? (const int *) R_ExternalPtrAddr(value_record)
        : ALTREP(value) ? NULL : (const int *) DATAPTR_RO(value);
    R_xlen_t count = XLENGTH(storage);
    R_xlen_t length = XLENGTH(rows);
    int scalar = XLENGTH(value) == 1;
    int scalar_value = scalar ? (value_data ? value_data[0] : LOGICAL_ELT(value, 0)) : 0;
    Rbyte *keep = RAW(storage);
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        int row = row_data[i];
        if (row == NA_INTEGER || row < 1 || (R_xlen_t) row > count) {
            Rf_error("invalid filter group row");
        }
        /* Read every element even after a prior predicate discarded this row.
           R likewise still evaluates every later predicate and every group. */
        int current = scalar ? scalar_value : value_data ? value_data[i] : LOGICAL_ELT(value, i);
        keep[row - 1] = keep[row - 1] && current == 1;
    }
    UNPROTECT(3);
    return R_NilValue;
}

SEXP C_dtatools_filter_finish(SEXP state, SEXP inverse) {
    SEXP storage = PROTECT(filter_storage(state));
    if (TYPEOF(inverse) != LGLSXP || XLENGTH(inverse) != 1 ||
        LOGICAL_ELT(inverse, 0) == NA_LOGICAL) {
        Rf_error("invalid filter inversion");
    }
    int invert = LOGICAL_ELT(inverse, 0) == 1;
    R_xlen_t count = XLENGTH(storage);
    const Rbyte *keep = RAW(storage);
    R_xlen_t selected = 0;
    for (R_xlen_t i = 0; i < count; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        if ((keep[i] != 0) != invert) selected++;
    }
    SEXP result = PROTECT(Rf_allocVector(INTSXP, selected));
    R_xlen_t output = 0;
    for (R_xlen_t i = 0; i < count; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        if ((keep[i] != 0) != invert) INTEGER(result)[output++] = (int) i + 1;
    }
    R_SetExternalPtrProtected(state, R_NilValue);
    UNPROTECT(2);
    return result;
}
