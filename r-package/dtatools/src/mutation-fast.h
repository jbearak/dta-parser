#ifndef DTATOOLS_MUTATION_FAST_H
#define DTATOOLS_MUTATION_FAST_H

/* Callback-free adapters to the same transaction used by the general path.
   NULL means decline before writing. Policy, expression evaluation, promotion
   and diagnostics outside this domain stay with the existing R adapters. */
static int mutation_plain_numeric(SEXP value) {
    return !ALTREP(value) && !ANY_ATTRIB(value) &&
        (TYPEOF(value) == REALSXP || TYPEOF(value) == INTSXP || TYPEOF(value) == LGLSXP);
}

static int mutation_plain_positions(SEXP rows, R_xlen_t count) {
    if (rows == R_NilValue) return 1;
    if (!mutation_plain_numeric(rows) || TYPEOF(rows) == LGLSXP || count > INT_MAX) return 0;
    for (R_xlen_t i = 0; i < XLENGTH(rows); i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        double row = TYPEOF(rows) == REALSXP ? REAL(rows)[i] : INTEGER(rows)[i];
        if (!R_FINITE(row) || row < 1 || row > (double) count || row != trunc(row)) return 0;
    }
    return 1;
}

static R_xlen_t mutation_scalar_location(SEXP data, SEXP variable) {
    if ((TYPEOF(variable) != STRSXP && TYPEOF(variable) != INTSXP && TYPEOF(variable) != REALSXP) ||
        ALTREP(variable) || ANY_ATTRIB(variable) || XLENGTH(variable) != 1) return -1;
    if (TYPEOF(variable) == STRSXP) {
        SEXP location = C_dtatools_mutation_name_location(data, variable);
        if (location == R_NilValue || INTEGER(location)[0] == NA_INTEGER) return -1;
        return INTEGER(location)[0] - 1;
    }
    if (TYPEOF(variable) == INTSXP || TYPEOF(variable) == REALSXP) {
        double index = Rf_asReal(variable);
        if (R_FINITE(index) && index >= 1 && index <= (double) XLENGTH(data) && index == trunc(index))
            return (R_xlen_t) index - 1;
    }
    return -1;
}

static SEXP mutation_patch_scalar(SEXP data, SEXP variable, SEXP rows,
                                  SEXP value, int promote, R_xlen_t count) {
    if (!mutation_plain_numeric(value) || XLENGTH(value) != 1) return R_NilValue;
    R_xlen_t slot = mutation_scalar_location(data, variable);
    if (slot < 0 || !mutation_plain_positions(rows, count)) return R_NilValue;
    SEXP target = VECTOR_ELT(data, slot);
    if (!known_numeric_classes(target, 1) || !Rf_inherits(target, "dta_numeric") ||
        Rf_inherits(target, "dta_temporal")) return R_NilValue;
    numeric_data *compact = unmaterialized_numeric_storage(target);
    numeric_data materialized;
    int kind;
    if (compact != NULL) kind = compact->kind;
    else if (rows == R_NilValue && materialized_numeric_storage(target, &materialized)) kind = materialized.kind;
    else if (owned_real(target) && owned_real_supported(target)) kind = NUMERIC_DOUBLE;
    else return R_NilValue;
    if (promote) {
        if ((rows == R_NilValue ? count : XLENGTH(rows)) == 0) return data;
        SEXP storage = PROTECT(Rf_ScalarInteger(kind));
        SEXP row_mode = PROTECT(Rf_ScalarLogical(0));
        SEXP fits = C_dtatools_replacement_fits(value, R_NilValue, row_mode, storage);
        int accepted = Rf_asLogical(fits) == TRUE;
        UNPROTECT(2);
        if (!accepted) return R_NilValue;
    }
    /* No R-visible target view or list of columns has raised its reference
       count. The transaction also checks backing ownership and pointer exposure. */
    return patch_numeric_slot(data, slot, rows, value, MAYBE_SHARED(target));
}

SEXP C_dtatools_patch_scalar(SEXP data, SEXP name, SEXP rows, SEXP value, SEXP promote) {
    R_xlen_t count;
    if (!mutation_fast_shape(data, &count) || TYPEOF(promote) != LGLSXP ||
        ALTREP(promote) || ANY_ATTRIB(promote) || XLENGTH(promote) != 1 ||
        LOGICAL(promote)[0] == NA_LOGICAL) return R_NilValue;
    return mutation_patch_scalar(data, name, rows, value, LOGICAL(promote)[0], count);
}

/* Reading a delayed argument's expression is not evaluating it. Resolve only
   a literal or a symbol already bound to a value; active and delayed caller
   bindings decline. In particular, never evaluate an expression speculatively
   and then repeat it on fallback. These are public APIs in our minimum R 4.6. */
static SEXP mutation_bound_value(SEXP expression, SEXP environment) {
    if (TYPEOF(expression) != SYMSXP) return expression;
    while (environment != R_EmptyEnv && TYPEOF(environment) == ENVSXP) {
        R_BindingType_t type = R_GetBindingType(expression, environment);
        if (type == R_BindingTypeValue || type == R_BindingTypeForced)
            return R_getVar(expression, environment, FALSE);
        if (type != R_BindingTypeUnbound) return R_UnboundValue;
        environment = R_ParentEnv(environment);
    }
    return R_UnboundValue;
}

static SEXP mutation_argument(SEXP frame, const char *name) {
    SEXP symbol = Rf_install(name);
    R_BindingType_t type = R_GetBindingType(symbol, frame);
    if (type == R_BindingTypeValue || type == R_BindingTypeForced)
        return R_getVar(symbol, frame, FALSE);
    if (type != R_BindingTypeDelayed) return R_UnboundValue;
    return mutation_bound_value(R_DelayedBindingExpression(symbol, frame),
                                R_DelayedBindingEnvironment(symbol, frame));
}

/* The promoting adapter may fall back after its fit check. Its speculative
   work must not force a policy expression that could change row/value
   bindings before that fallback evaluates them. */
SEXP C_dtatools_peek_promote(SEXP frame) {
    if (TYPEOF(frame) != ENVSXP) return R_NilValue;
    SEXP value = mutation_argument(frame, "promote");
    if (TYPEOF(value) != LGLSXP || ALTREP(value) || ANY_ATTRIB(value) ||
        XLENGTH(value) != 1 || LOGICAL(value)[0] == NA_LOGICAL) return R_NilValue;
    return value;
}

SEXP C_dtatools_set_values_fast(SEXP data, SEXP frame) {
    R_xlen_t count;
    if (TYPEOF(frame) != ENVSXP || !mutation_fast_shape(data, &count)) return R_NilValue;
    SEXP variable = PROTECT(mutation_argument(frame, "variable"));
    SEXP create = PROTECT(mutation_argument(frame, "create"));
    SEXP rows = PROTECT(mutation_argument(frame, "rows"));
    SEXP value = PROTECT(mutation_argument(frame, "value"));
    SEXP result = R_NilValue;
    if (variable != R_UnboundValue && rows != R_UnboundValue && value != R_UnboundValue &&
        TYPEOF(create) == LGLSXP && !ALTREP(create) && !ANY_ATTRIB(create) &&
        XLENGTH(create) == 1 && LOGICAL(create)[0] == FALSE) {
        result = mutation_patch_scalar(data, variable, rows, value, 0, count);
    }
    UNPROTECT(4);
    return result;
}

/* Bare numeric scalars have a fixed attribute plan. Reuse native generation
   (including its interrupt checkpoint) instead of building the plan in R. */
SEXP C_dtatools_generate_scalar(SEXP value, SEXP rows, SEXP count, SEXP storage) {
    if (!mutation_plain_numeric(value) || TYPEOF(value) == LGLSXP || XLENGTH(value) != 1 ||
        TYPEOF(storage) != STRSXP || ALTREP(storage) || ANY_ATTRIB(storage) ||
        XLENGTH(storage) != 1) return R_NilValue;
    const char *name = CHAR(STRING_ELT(storage, 0));
    int kind = strcmp(name, "long") == 0 ? NUMERIC_LONG :
        strcmp(name, "float") == 0 ? NUMERIC_FLOAT : strcmp(name, "double") == 0 ? NUMERIC_DOUBLE : -1;
    if (kind < 0 || (TYPEOF(value) == REALSXP && kind == NUMERIC_LONG)) return R_NilValue;
    SEXP attributes = PROTECT(Rf_allocVector(VECSXP, 2));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 2));
    SET_STRING_ELT(names, 0, Rf_mkChar("stata.storage"));
    SET_STRING_ELT(names, 1, Rf_mkChar("class"));
    Rf_setAttrib(attributes, R_NamesSymbol, names);
    SET_VECTOR_ELT(attributes, 0, storage);
    SEXP classes = PROTECT(Rf_allocVector(STRSXP, 4));
    SET_STRING_ELT(classes, 0, Rf_mkChar("dta_numeric"));
    SET_STRING_ELT(classes, 1, Rf_mkChar(kind == NUMERIC_LONG ? "dta_long" :
                                      kind == NUMERIC_FLOAT ? "dta_float" : "dta_double"));
    SET_STRING_ELT(classes, 2, Rf_mkChar("vctrs_vctr"));
    SET_STRING_ELT(classes, 3, Rf_mkChar("double"));
    SET_VECTOR_ELT(attributes, 1, classes);
    SEXP kind_value = PROTECT(Rf_ScalarInteger(kind));
    SEXP temporal = PROTECT(Rf_ScalarInteger(0));
    SEXP result = C_dtatools_generate_numeric(value, rows, count, kind_value, temporal, attributes);
    UNPROTECT(5);
    return result;
}

#endif
