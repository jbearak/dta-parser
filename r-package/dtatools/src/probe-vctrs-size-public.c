/* Scratch, pinned R 4.6.1: fresh public vec_size bytecode admission. */
#include <R.h>
#include <Rinternals.h>
#include <string.h>
extern int dtatools_probe_fresh_formals(SEXP live, SEXP frozen);

typedef struct { SEXP tag[16], value[16]; int count; } attrs_t;
static SEXP collect_attr(SEXP tag, SEXP value, void *ptr) {
    attrs_t *a = ptr;
    if (a->count >= 16 || TYPEOF(tag) != SYMSXP || ANY_ATTRIB(tag) ||
        tag == R_RowNamesSymbol) return R_NilValue;
    a->tag[a->count] = tag;
    a->value[a->count++] = value;
    return NULL;
}
static SEXP source_file_attr(SEXP expression) {
    attrs_t attrs = {.count = 0};
    if (R_mapAttrib(expression, collect_attr, &attrs) != NULL)
        return R_NilValue;
    SEXP sym = Rf_install("srcfile"), result = R_NilValue;
    for (int i=0; i<attrs.count; ++i) {
        if (attrs.tag[i] == sym) {
            if (result != R_NilValue) return R_NilValue;
            result = attrs.value[i];
        }
    }
    return result;
}
static int plain_walk(SEXP x, SEXP source_env, SEXP closure_env,
                      int *budget, int depth) {
    if (--*budget < 0 || depth > 96 || ALTREP(x)) return 0;
    attrs_t a = {.count = 0};
    if (TYPEOF(x) != CHARSXP && TYPEOF(x) != SYMSXP) {
        if (R_mapAttrib(x, collect_attr, &a) != NULL) return 0;
        for (int i=0; i<a.count; ++i)
            if (!plain_walk(a.value[i],source_env,closure_env,budget,depth+1))
                return 0;
    } else if (TYPEOF(x) == SYMSXP && ANY_ATTRIB(x)) return 0;
    switch(TYPEOF(x)) {
    case NILSXP: case SYMSXP: case CHARSXP: case BUILTINSXP:
    case SPECIALSXP: case LGLSXP: case INTSXP: case REALSXP:
    case CPLXSXP: case RAWSXP: case STRSXP: return 1;
    case ENVSXP:
        /* Environment identity is checked in the later exact comparison.
           Visiting an environment does not evaluate its bindings. */
        return 1;
    case LANGSXP: case LISTSXP: case DOTSXP: case BCODESXP:
        return plain_walk(TAG(x),source_env,closure_env,budget,depth+1) &&
               plain_walk(CAR(x),source_env,closure_env,budget,depth+1) &&
               plain_walk(CDR(x),source_env,closure_env,budget,depth+1);
    case CLOSXP:
        return R_ClosureEnv(x) == closure_env &&
               plain_walk(R_ClosureFormals(x),source_env,closure_env,budget,depth+1) &&
               plain_walk(R_ClosureBody(x),source_env,closure_env,budget,depth+1);
    case VECSXP: case EXPRSXP:
        if (XLENGTH(x) > *budget) return 0;
        for (R_xlen_t i=0;i<XLENGTH(x);++i)
            if (!plain_walk(VECTOR_ELT(x,i),source_env,closure_env,budget,depth+1))
                return 0;
        return 1;
    default: return 0;
    }
}
static int exact_plain(SEXP a, SEXP b, SEXP source_a, SEXP source_b,
                       int *budget, int depth) {
    if (--*budget < 0 || depth > 96 || TYPEOF(a) != TYPEOF(b) ||
        ALTREP(a) || ALTREP(b) || Rf_isObject(a) != Rf_isObject(b) ||
        Rf_isS4(a) != Rf_isS4(b)) return 0;
    if (a == b) return 1;
    attrs_t aa = {.count = 0}, ab = {.count = 0};
    if (TYPEOF(a) != CHARSXP && TYPEOF(a) != SYMSXP) {
        if (R_mapAttrib(a, collect_attr, &aa) != NULL ||
            R_mapAttrib(b, collect_attr, &ab) != NULL || aa.count != ab.count)
            return 0;
        for (int i = 0; i < aa.count; ++i) {
            if (aa.tag[i] != ab.tag[i] ||
                !exact_plain(aa.value[i], ab.value[i], source_a, source_b,
                             budget, depth + 1)) return 0;
        }
    } else if (TYPEOF(a) == SYMSXP && (ANY_ATTRIB(a) || ANY_ATTRIB(b)))
        return 0;
    switch (TYPEOF(a)) {
    case NILSXP: case SYMSXP: case BUILTINSXP: case SPECIALSXP:
        return a == b;
    case ENVSXP:
        return (a == source_a && b == source_b) || a == b;
    case CHARSXP:
        return R_compute_identical(a,b,IDENT_USE_BYTECODE|
                                     IDENT_USE_CLOENV|IDENT_USE_SRCREF);
    case LGLSXP:
        return XLENGTH(a)==XLENGTH(b) &&
            memcmp(LOGICAL(a),LOGICAL(b),(size_t)XLENGTH(a)*sizeof(int))==0;
    case INTSXP:
        return XLENGTH(a)==XLENGTH(b) &&
            memcmp(INTEGER(a),INTEGER(b),(size_t)XLENGTH(a)*sizeof(int))==0;
    case REALSXP:
        return XLENGTH(a)==XLENGTH(b) &&
            memcmp(REAL(a),REAL(b),(size_t)XLENGTH(a)*sizeof(double))==0;
    case CPLXSXP:
        return XLENGTH(a)==XLENGTH(b) &&
            memcmp(COMPLEX(a),COMPLEX(b),(size_t)XLENGTH(a)*sizeof(Rcomplex))==0;
    case RAWSXP:
        return XLENGTH(a)==XLENGTH(b) &&
            memcmp(RAW(a),RAW(b),(size_t)XLENGTH(a))==0;
    case STRSXP:
        if (XLENGTH(a)!=XLENGTH(b)) return 0;
        for (R_xlen_t i=0; i<XLENGTH(a); ++i)
            if (!R_compute_identical(STRING_ELT(a,i),STRING_ELT(b,i),
                 IDENT_USE_BYTECODE|IDENT_USE_CLOENV|IDENT_USE_SRCREF)) return 0;
        return 1;
    case LANGSXP: case LISTSXP: case DOTSXP: case BCODESXP:
        return exact_plain(TAG(a), TAG(b), source_a, source_b, budget, depth+1) &&
               exact_plain(CAR(a), CAR(b), source_a, source_b, budget, depth+1) &&
               exact_plain(CDR(a), CDR(b), source_a, source_b, budget, depth+1);
    case VECSXP: case EXPRSXP:
        if (XLENGTH(a) != XLENGTH(b) || XLENGTH(a) > *budget) return 0;
        for (R_xlen_t i=0; i<XLENGTH(a); ++i)
            if (!exact_plain(VECTOR_ELT(a,i), VECTOR_ELT(b,i),
                             source_a, source_b, budget, depth+1)) return 0;
        return 1;
    default: return 0;
    }
}
static SEXP current_value(SEXP env, const char *name) {
    SEXP sym = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(sym, env);
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(sym, env, FALSE, R_NilValue);
}
static int code_equal(SEXP current, SEXP frozen_source, SEXP frozen_code) {
    if (TYPEOF(current) != CLOSXP || TYPEOF(frozen_source) != CLOSXP ||
        TYPEOF(frozen_code) != CLOSXP ||
        R_ClosureEnv(current) != R_ClosureEnv(frozen_source) ||
        R_ClosureEnv(current) != R_ClosureEnv(frozen_code) ||
        TYPEOF(R_ClosureBody(current)) != BCODESXP ||
        TYPEOF(R_ClosureBody(frozen_code)) != BCODESXP)
        return 0;
    /* R 4.6.1 R_ClosureExpr reads constant zero through LENGTH/VECTOR_ELT.
       Qualify the entire closure and the ordinary constant pool first. */
    SEXP live_pool = CDR(R_ClosureBody(current));
    SEXP frozen_pool = CDR(R_ClosureBody(frozen_code));
    int walk_budget = 8192;
    if (TYPEOF(live_pool) != VECSXP || ALTREP(live_pool) ||
        TYPEOF(frozen_pool) != VECSXP || ALTREP(frozen_pool) ||
        XLENGTH(live_pool) < 1 || XLENGTH(frozen_pool) < 1 ||
        !plain_walk(current,R_NilValue,R_ClosureEnv(current),&walk_budget,0))
        return 0;
    SEXP expr_a = R_ClosureExpr(current), expr_b = R_ClosureExpr(frozen_code);
    if (TYPEOF(expr_a) != LANGSXP || TYPEOF(expr_b) != LANGSXP)
        return 0;
    SEXP sf_a = source_file_attr(expr_a);
    SEXP sf_b = source_file_attr(expr_b);
    if (!((TYPEOF(sf_a) == ENVSXP && TYPEOF(sf_b) == ENVSXP) ||
          (sf_a == R_NilValue && sf_b == R_NilValue)))
        return 0;
    if (!R_compute_identical(current,frozen_source,IDENT_USE_CLOENV)) return 0;
    int budget = 8192;
    return exact_plain(R_ClosureFormals(current), R_ClosureFormals(frozen_code),
                       sf_a, sf_b, &budget, 0) &&
           exact_plain(R_ClosureBody(current), R_ClosureBody(frozen_code),
                       sf_a, sf_b, &budget, 0);
}
static SEXP vctrs_size_guard_core(SEXP state, int deep) {
    if (TYPEOF(state) != ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP ns = current_value(state, "namespace");
    SEXP source = current_value(state, "frozen_source");
    SEXP code = current_value(state, "frozen_code");
    if (TYPEOF(ns) != ENVSXP)
        return Rf_ScalarLogical(FALSE);
    SEXP proxy_ns = current_value(state, "proxy_namespace");
    SEXP table = current_value(state, "proxy_table");
    SEXP proxy_source = current_value(state, "proxy_source");
    SEXP proxy_code = current_value(state, "proxy_code");
    const char *name = "vec_proxy.dta_numeric";
    if (TYPEOF(proxy_ns) != ENVSXP || TYPEOF(table) != ENVSXP ||
        R_GetBindingType(Rf_install(name), R_GlobalEnv) != R_BindingTypeUnbound)
        return Rf_ScalarLogical(FALSE);
    SEXP size_live = current_value(ns,"vec_size");
    SEXP proxy_live = current_value(table,name);
    if (current_value(proxy_ns,name) != proxy_live)
        return Rf_ScalarLogical(FALSE);
    if (deep) {
        if (!code_equal(size_live,source,code) ||
            !code_equal(proxy_live,proxy_source,proxy_code))
            return Rf_ScalarLogical(FALSE);
    } else {
        SEXP size_saved = current_value(state,"size_live");
        if (size_saved == R_NilValue) {
            if (!code_equal(size_live,source,code) ||
                !code_equal(proxy_live,proxy_source,proxy_code))
                return Rf_ScalarLogical(FALSE);
            Rf_defineVar(Rf_install("size_live"),size_live,state);
            Rf_defineVar(Rf_install("size_body"),R_ClosureBody(size_live),state);
            Rf_defineVar(Rf_install("proxy_live"),proxy_live,state);
            Rf_defineVar(Rf_install("proxy_body"),R_ClosureBody(proxy_live),state);
        } else {
            if (size_live != size_saved ||
                R_ClosureBody(size_live) != current_value(state,"size_body") ||
                proxy_live != current_value(state,"proxy_live") ||
                R_ClosureBody(proxy_live) != current_value(state,"proxy_body") ||
                !dtatools_probe_fresh_formals(size_live,code) ||
                !dtatools_probe_fresh_formals(proxy_live,proxy_code))
                return Rf_ScalarLogical(FALSE);
        }
    }
    return Rf_ScalarLogical(TRUE);
}
SEXP C_dtatools_probe_vctrs_size_guard(SEXP state) {
    return vctrs_size_guard_core(state,0);
}
SEXP C_dtatools_probe_vctrs_size_guard_deep(SEXP state) {
    return vctrs_size_guard_core(state,1);
}
