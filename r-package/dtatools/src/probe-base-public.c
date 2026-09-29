/* Scratch public base-call qualification for the bounded repl producer. */
#include "dtatools-internal.h"
#include <string.h>
extern int dtatools_probe_fresh_formals(SEXP live, SEXP frozen);

static const char *names[] = {
    "is.data.frame", "anyDuplicated", "isTRUE", "identical", "eval",
    "getOption", "unique", "exists", "vapply", "lapply", "new.env",
    "as.list", "parent.frame", "suppressWarnings", "getExportedValue",
    "unique.default", "anyDuplicated.default", "as.list.default", "c",
    "$", "missing", "&&", "if", "return", "!", "is.null", ".Call",
    "attr<-", "attributes<-"
};
#define BASE_COUNT (sizeof(names) / sizeof(names[0]))
#define BASE_UNIQUE_DEFAULT 15
#define BASE_ANY_DUPLICATED_DEFAULT 16
#define BASE_AS_LIST_DEFAULT 17

static SEXP base_value(const char *name) {
    SEXP symbol = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(symbol, R_BaseEnv);
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(symbol, R_BaseEnv, FALSE, R_NilValue);
}

static int table_has(SEXP table, const char *name, SEXP expected) {
    SEXP symbol = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(symbol, table);
    if (expected == R_NilValue) return kind == R_BindingTypeUnbound;
    return (kind == R_BindingTypeValue || kind == R_BindingTypeForced) &&
        R_getVarEx(symbol, table, FALSE, R_NilValue) == expected;
}

SEXP C_dtatools_probe_base_profile(SEXP frozen) {
    if (TYPEOF(frozen) != VECSXP || XLENGTH(frozen) != BASE_COUNT)
        return R_NilValue;
    SEXP labels = Rf_getAttrib(frozen, R_NamesSymbol);
    if (TYPEOF(labels) != STRSXP || XLENGTH(labels) != BASE_COUNT)
        return R_NilValue;
    SEXP live = PROTECT(Rf_allocVector(VECSXP, BASE_COUNT));
    for (R_xlen_t i = 0; i < BASE_COUNT; i++) {
        if (strcmp(CHAR(STRING_ELT(labels, i)), names[i]) != 0) {
            UNPROTECT(1);
            return R_NilValue;
        }
        SEXP current = base_value(names[i]);
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

static int no_effective_method(SEXP caller, SEXP table, const char *name) {
    SEXP method = Rf_install(name);
    if (TYPEOF(caller) != ENVSXP ||
        R_GetBindingType(method, table) != R_BindingTypeUnbound)
        return 0;
    SEXP env = caller;
    for (;;) {
        if (R_GetBindingType(method, env) != R_BindingTypeUnbound) return 0;
        if (env == R_GlobalEnv) break;
        if (env == R_BaseEnv || env == R_EmptyEnv) return 0;
        env = R_ParentEnv(env);
    }
    env = R_ParentEnv(R_GlobalEnv);
    while (env != R_BaseEnv) {
        if (env == R_EmptyEnv ||
            R_GetBindingType(method, env) != R_BindingTypeUnbound) return 0;
        env = R_ParentEnv(env);
    }
    return R_GetBindingType(method, R_BaseEnv) == R_BindingTypeUnbound;
}

static SEXP base_guard_core(SEXP state, SEXP quosure, int deep) {
    if (TYPEOF(state) != ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP live = R_getVarEx(Rf_install("live"), state, FALSE, R_NilValue);
    if (live == R_NilValue) {
        SEXP frozen = R_getVarEx(Rf_install("frozen"), state, FALSE, R_NilValue);
        live = PROTECT(C_dtatools_probe_base_profile(frozen));
        if (live != R_NilValue) {
            Rf_defineVar(Rf_install("live"), live, state);
            Rf_defineVar(Rf_install("as_list_body"),
                R_ClosureBody(VECTOR_ELT(live,BASE_AS_LIST_DEFAULT)),state);
        }
        UNPROTECT(1);
    }
    if (TYPEOF(live) != VECSXP || XLENGTH(live) != BASE_COUNT)
        return Rf_ScalarLogical(FALSE);
    SEXP caller = Rf_getAttrib(quosure, Rf_install(".Environment"));
    if (TYPEOF(caller) != ENVSXP) return Rf_ScalarLogical(FALSE);
    for (R_xlen_t i = 0; i < BASE_COUNT; i++)
        if (base_value(names[i]) != VECTOR_ELT(live, i))
            return Rf_ScalarLogical(FALSE);
    SEXP frozen = R_getVarEx(Rf_install("frozen"), state, FALSE, R_NilValue);
    if (TYPEOF(frozen) != VECSXP || XLENGTH(frozen) != BASE_COUNT)
        return Rf_ScalarLogical(FALSE);
    SEXP as_list = VECTOR_ELT(live,BASE_AS_LIST_DEFAULT);
    if (deep) {
        if (!dtatools_execution_function_same(as_list,
                                              VECTOR_ELT(frozen,BASE_AS_LIST_DEFAULT)))
            return Rf_ScalarLogical(FALSE);
    } else {
        SEXP saved_body = R_getVarEx(Rf_install("as_list_body"),state,FALSE,R_NilValue);
        if (TYPEOF(as_list) != CLOSXP ||
            R_ClosureBody(as_list) != saved_body ||
            !dtatools_probe_fresh_formals(as_list,
                                          VECTOR_ELT(frozen,BASE_AS_LIST_DEFAULT)))
            return Rf_ScalarLogical(FALSE);
    }
    SEXP table = base_value(".__S3MethodsTable__.");
    if (TYPEOF(table) != ENVSXP ||
        !table_has(table, "unique.default", VECTOR_ELT(live, BASE_UNIQUE_DEFAULT)) ||
        !table_has(table, "anyDuplicated.default", VECTOR_ELT(live, BASE_ANY_DUPLICATED_DEFAULT)) ||
        !table_has(table, "as.list.default", VECTOR_ELT(live, BASE_AS_LIST_DEFAULT)) ||
        !no_effective_method(caller, table, "unique.character") ||
        !no_effective_method(caller, table, "anyDuplicated.character") ||
        !no_effective_method(caller, table, "as.list.list"))
        return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(TRUE);
}
SEXP C_dtatools_probe_base_guard(SEXP state, SEXP quosure) {
    return base_guard_core(state,quosure,0);
}
SEXP C_dtatools_probe_base_guard_deep(SEXP state, SEXP quosure) {
    return base_guard_core(state,quosure,1);
}
