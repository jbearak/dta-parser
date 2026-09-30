/* Ungrouped typed-double gen admission. Gen-only roots are qualified from
   installed source alongside the existing public-root profile at load. */
#include "dtatools-internal.h"
#include <string.h>

extern int dtatools_probe_public48_guard_plain(SEXP state);
extern int dtatools_probe_gen_extra_guard_plain(SEXP state);
extern int dtatools_probe_wrapper_current(SEXP state);
extern int dtatools_fast_s3_guard_env(SEXP caller, SEXP tables,
                                      SEXP live, SEXP namespaces);

static SEXP frozen_colon2 = NULL;
void dtatools_probe_gen_primitive_init(void) {
    SEXP symbol = Rf_install("::");
    R_BindingType_t kind = R_GetBindingType(symbol, R_BaseEnv);
    if (kind == R_BindingTypeValue || kind == R_BindingTypeForced) {
        SEXP current = R_getVarEx(symbol, R_BaseEnv, FALSE, R_NilValue);
        if (TYPEOF(current) != SPECIALSXP) return;
        frozen_colon2 = current;
        R_PreserveObject(frozen_colon2);
    }
}

static SEXP value(SEXP env, const char *name) {
    if (TYPEOF(env) != ENVSXP) return R_NilValue;
    SEXP sym = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(sym, env);
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(sym, env, FALSE, R_NilValue);
}

static int no_caller_method(SEXP caller, const char *name) {
    SEXP symbol = Rf_install(name);
    for (SEXP env = caller; env != R_EmptyEnv; env = R_ParentEnv(env))
        if (R_GetBindingType(symbol, env) != R_BindingTypeUnbound) return 0;
    return 1;
}

static int no_method(SEXP caller, SEXP table, const char *name) {
    return TYPEOF(table) == ENVSXP &&
        R_GetBindingType(Rf_install(name), table) == R_BindingTypeUnbound &&
        no_caller_method(caller, name);
}

static int source_methods_canonical(SEXP caller, SEXP base_table,
                                    SEXP dta_table) {
    /* The ordinary arithmetic and result construction dispatch these even
       when the source has exactly the canonical dta_double classes. */
    static const char *base_absent[] = {
        "dim.dta_numeric", "dim.dta_double", "dim.vctrs_vctr",
        "dim.double", "dim.default", "names.dta_numeric",
        "names.dta_double", "names.vctrs_vctr", "names.double",
        "names.default", "names<-.dta_numeric", "names<-.dta_double",
        "names<-.double", "names<-.default"
    };
    for (size_t i = 0; i < sizeof(base_absent) / sizeof(base_absent[0]); ++i)
        if (!no_method(caller, base_table, base_absent[i])) return 0;
    return no_method(caller, dta_table, "vec_arith.dta_numeric.double") &&
        no_caller_method(caller, "vec_proxy.dta_numeric");
}

typedef struct { int count; unsigned seen; } q_attrs;
static SEXP visit_q_attr(SEXP tag, SEXP val, void *context) {
    q_attrs *a = (q_attrs *)context;
    a->count++;
    if (tag == R_ClassSymbol) {
        if (TYPEOF(val) != STRSXP || ALTREP(val) || XLENGTH(val) != 2 ||
            strcmp(CHAR(STRING_ELT(val,0)),"quosure") ||
            strcmp(CHAR(STRING_ELT(val,1)),"formula")) return R_NilValue;
        a->seen |= 1U;
    } else if (tag == Rf_install(".Environment")) {
        if (TYPEOF(val) != ENVSXP) return R_NilValue;
        a->seen |= 2U;
    } else return R_NilValue;
    return NULL;
}
static int canonical_q(SEXP q) {
    if (TYPEOF(q) != LANGSXP || CAR(q) != Rf_install("~") ||
        CDDR(q) != R_NilValue) return 0;
    q_attrs attrs = {.count=0,.seen=0};
    return R_mapAttrib(q,visit_q_attr,&attrs) == NULL &&
        attrs.count == 2 && attrs.seen == 3U;
}
static SEXP visit_arguments_attr(SEXP tag, SEXP val, void *context) {
    int *seen = (int *)context;
    if (tag != R_NamesSymbol || TYPEOF(val) != STRSXP || ALTREP(val) ||
        XLENGTH(val) != 3 || ++*seen != 1) return R_NilValue;
    return NULL;
}

typedef struct {
    SEXP caller;
    SEXP source_symbol;
    SEXP target_name;
    double increment;
} gen_capture;

static int canonical_caller(SEXP frame, gen_capture *capture) {
    SEXP arguments = value(frame, "arguments");
    if (TYPEOF(arguments) != VECSXP || ALTREP(arguments) ||
        XLENGTH(arguments) != 3) return 0;
    int names_seen = 0;
    if (R_mapAttrib(arguments,visit_arguments_attr,&names_seen) != NULL ||
        names_seen != 1) return 0;
    SEXP names = Rf_getAttrib(arguments, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || XLENGTH(names) != 3 ||
        strcmp(CHAR(STRING_ELT(names, 0)), "variable") ||
        strcmp(CHAR(STRING_ELT(names, 1)), "values") ||
        strcmp(CHAR(STRING_ELT(names, 2)), "where")) return 0;
    SEXP target = VECTOR_ELT(arguments, 0);
    SEXP rhs = VECTOR_ELT(arguments, 1);
    SEXP where = VECTOR_ELT(arguments, 2);
    if (!canonical_q(target) || !canonical_q(rhs) ||
        !canonical_q(where) ||
        TYPEOF(CADR(target)) != STRSXP ||
        ALTREP(CADR(target)) || ANY_ATTRIB(CADR(target)) ||
        XLENGTH(CADR(target)) != 1 ||
        STRING_ELT(CADR(target), 0) == NA_STRING ||
        CADR(where) != R_NilValue ||
        Rf_getAttrib(target,Rf_install(".Environment")) != R_EmptyEnv ||
        Rf_getAttrib(where,Rf_install(".Environment")) != R_EmptyEnv)
        return 0;
    SEXP expr = CADR(rhs);
    if (TYPEOF(expr) != LANGSXP || ANY_ATTRIB(expr) ||
        CAR(expr) != Rf_install("+") ||
        TYPEOF(CADR(expr)) != SYMSXP ||
        TYPEOF(CADDR(expr)) != REALSXP ||
        ALTREP(CADDR(expr)) || ANY_ATTRIB(CADDR(expr)) ||
        XLENGTH(CADDR(expr)) != 1 ||
        !R_FINITE(REAL(CADDR(expr))[0]) ||
        CDDDR(expr) != R_NilValue) return 0;
    capture->caller = Rf_getAttrib(rhs, Rf_install(".Environment"));
    capture->source_symbol = CADR(expr);
    if (capture->source_symbol == Rf_install(".data") ||
        capture->source_symbol == Rf_install(".env") ||
        capture->source_symbol == Rf_install(".") ||
        capture->source_symbol == Rf_install(".n") ||
        capture->source_symbol == Rf_install(".N") ||
        strncmp(CHAR(PRINTNAME(capture->source_symbol)), "..", 2) == 0) return 0;
    capture->target_name = STRING_ELT(CADR(target), 0);
    capture->increment = REAL(CADDR(expr))[0];
    return TYPEOF(capture->caller) == ENVSXP;
}

int dtatools_probe_gen_parse_caller(SEXP frame, SEXP *source_symbol,
                                    SEXP *target_name, SEXP *caller,
                                    double *increment) {
    gen_capture capture;
    if (!canonical_caller(frame, &capture)) return 0;
    *source_symbol = capture.source_symbol;
    *target_name = capture.target_name;
    *caller = capture.caller;
    *increment = capture.increment;
    return 1;
}

int dtatools_probe_gen_public_guard_plain(SEXP frame, SEXP base,
                                           SEXP public_state,
                                           SEXP extra_state,
                                           SEXP wrapper_state,
                                           SEXP rlang_state, SEXP s3_state,
                                           int grouped) {
    /* Wrapper reconstruction can allocate. Check the other public roots
       after it, as close as possible to the native decision. */
    if (frozen_colon2 == NULL ||
        value(R_BaseEnv, "::") != frozen_colon2 ||
        !dtatools_probe_wrapper_current(wrapper_state) ||
        !dtatools_probe_public48_guard_plain(public_state) ||
        !dtatools_probe_gen_extra_guard_plain(extra_state)) return 0;
    SEXP frozen = value(base, "frozen");
    if (TYPEOF(frozen) != VECSXP || XLENGTH(frozen) != 29)
        return 0;
    static const char *names[] = {
        "c", "$", "missing", "&&", "if", "return", "!",
        "is.null", ".Call", "attr<-", "attributes<-"
    };
    for (int i = 0; i < 11; ++i)
        if (value(R_BaseEnv, names[i]) != VECTOR_ELT(frozen, 18 + i))
            return 0;
    /* rlang exports the same primitive under a second public binding. */
    SEXP rns = value(rlang_state, "namespace");
    if (TYPEOF(rns) != ENVSXP ||
        value(rns, "is_null") != value(R_BaseEnv, "is.null"))
        return 0;
    SEXP frozen_length = value(extra_state, "primitive_length");
    if (TYPEOF(frozen_length) != BUILTINSXP ||
        value(R_BaseEnv, "length") != frozen_length)
        return 0;
    SEXP frozen_bracket = value(extra_state, "primitive_bracket2");
    SEXP frozen_minus = value(extra_state, "primitive_minus");
    if (TYPEOF(frozen_bracket) != SPECIALSXP ||
        TYPEOF(frozen_minus) != BUILTINSXP ||
        value(R_BaseEnv, "[[") != frozen_bracket ||
        value(R_BaseEnv, "-") != frozen_minus)
        return 0;
    SEXP frozen_names_set = value(extra_state, "primitive_names_set");
    SEXP frozen_list = value(extra_state, "primitive_list");
    if (TYPEOF(frozen_names_set) != BUILTINSXP ||
        TYPEOF(frozen_list) != BUILTINSXP ||
        value(R_BaseEnv, "names<-") != frozen_names_set ||
        value(R_BaseEnv, "list") != frozen_list)
        return 0;
    SEXP by = Rf_install("by");
    if (R_GetBindingType(by, frame) != R_BindingTypeDelayed ||
        (!grouped && R_DelayedBindingExpression(by, frame) != R_NilValue) ||
        (grouped && TYPEOF(R_DelayedBindingExpression(by, frame)) != SYMSXP))
        return 0;
    gen_capture capture;
    if (!canonical_caller(frame, &capture)) return 0;
    for (SEXP env=capture.caller;;env=R_ParentEnv(env)) {
        if (env==R_BaseEnv || env==R_EmptyEnv ||
            R_GetBindingType(capture.source_symbol,env)!=R_BindingTypeUnbound)
            return 0;
        if (env==R_GlobalEnv) break;
    }
    if (!dtatools_fast_s3_guard_env(capture.caller,
        value(s3_state, "tables"), value(s3_state, "live"),
        value(s3_state, "namespaces"))) return 0;
    SEXP tables = value(s3_state, "tables");
    SEXP namespaces = value(s3_state, "namespaces");
    if (TYPEOF(tables) != VECSXP || XLENGTH(tables) != 3 ||
        TYPEOF(namespaces) != VECSXP || XLENGTH(namespaces) != 2)
        return 0;
    SEXP vctrs_table = VECTOR_ELT(tables, 1);
    SEXP base_table = VECTOR_ELT(tables, 0);
    SEXP dta_table = VECTOR_ELT(tables, 2);
    SEXP vns = VECTOR_ELT(namespaces, 0);
    SEXP dtans = VECTOR_ELT(namespaces, 1);
    if (!source_methods_canonical(capture.caller, base_table, dta_table) ||
        value(vctrs_table, "vec_proxy_equal.dta_numeric") !=
            value(dtans, "vec_proxy_equal.dta_numeric") ||
        value(vctrs_table, "vec_proxy.dta_numeric") !=
            value(dtans, "vec_proxy.dta_numeric") ||
        value(base_table, "names<-.vctrs_vctr") !=
            value(vns, "names<-.vctrs_vctr")) return 0;
    return 1;
}

SEXP C_dtatools_probe_gen_public_guard(SEXP base, SEXP public_state,
                                       SEXP extra_state,
                                       SEXP wrapper_state, SEXP rlang_state,
                                       SEXP s3_state) {
    return Rf_ScalarLogical(dtatools_probe_gen_public_guard_plain(
        R_GetCurrentEnv(), base, public_state, extra_state, wrapper_state,
        rlang_state, s3_state, 0));
}
