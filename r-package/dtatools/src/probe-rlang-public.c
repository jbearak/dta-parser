/* Scratch public rlang binding qualification for bounded repl(x = x + 1).
 * R 4.6.1: this uses the public environment inspection API and compares
 * source-owned closures at bootstrap; it never forces an active/delayed bind.
 */
#include <R.h>
#include <Rinternals.h>
#include <string.h>

static const char *rlang_names[] = {
    "is_bool", "is_formula", "is_quosure", "quo_get_env",
    "quo_get_expr", "quo_is_missing"
};
#define RLANG_COUNT (sizeof(rlang_names) / sizeof(rlang_names[0]))

static SEXP rlang_value(SEXP ns, const char *name) {
    SEXP symbol = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(symbol, ns);
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(symbol, ns, FALSE, R_NilValue);
}

SEXP C_dtatools_probe_rlang_profile(SEXP ns, SEXP frozen) {
    if (TYPEOF(ns) != ENVSXP || TYPEOF(frozen) != VECSXP ||
        XLENGTH(frozen) != RLANG_COUNT)
        return R_NilValue;
    SEXP labels = Rf_getAttrib(frozen, R_NamesSymbol);
    if (TYPEOF(labels) != STRSXP || XLENGTH(labels) != RLANG_COUNT)
        return R_NilValue;
    SEXP live = PROTECT(Rf_allocVector(VECSXP, RLANG_COUNT));
    for (R_xlen_t i = 0; i < RLANG_COUNT; i++) {
        if (strcmp(CHAR(STRING_ELT(labels, i)), rlang_names[i]) != 0) {
            UNPROTECT(1);
            return R_NilValue;
        }
        SEXP current = rlang_value(ns, rlang_names[i]);
        if (!Rf_isFunction(current) ||
            !R_compute_identical(current, VECTOR_ELT(frozen, i),
                                 IDENT_USE_CLOENV)) {
            UNPROTECT(1);
            return R_NilValue;
        }
        SET_VECTOR_ELT(live, i, current);
    }
    UNPROTECT(1);
    return live;
}

SEXP C_dtatools_probe_rlang_guard(SEXP state) {
    if (TYPEOF(state) != ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP ns = R_getVarEx(Rf_install("namespace"), state, FALSE, R_NilValue);
    if (TYPEOF(ns) != ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP live = R_getVarEx(Rf_install("live"), state, FALSE, R_NilValue);
    if (live == R_NilValue) {
        SEXP frozen = R_getVarEx(Rf_install("frozen"), state, FALSE, R_NilValue);
        live = PROTECT(C_dtatools_probe_rlang_profile(ns, frozen));
        if (live != R_NilValue) Rf_defineVar(Rf_install("live"), live, state);
        UNPROTECT(1);
    }
    if (TYPEOF(live) != VECSXP || XLENGTH(live) != RLANG_COUNT)
        return Rf_ScalarLogical(FALSE);
    for (R_xlen_t i = 0; i < RLANG_COUNT; i++)
        if (rlang_value(ns, rlang_names[i]) != VECTOR_ELT(live, i))
            return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(TRUE);
}
