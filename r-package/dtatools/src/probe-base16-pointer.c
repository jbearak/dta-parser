/* Scratch, pinned R 4.6.1: fresh public vec_size bytecode admission. */
#include <R.h>
#include <Rinternals.h>
#include <string.h>

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
    case CLOSXP:
        return R_ClosureEnv(a) == R_ClosureEnv(b) &&
            exact_plain(R_ClosureFormals(a), R_ClosureFormals(b),
                        source_a, source_b, budget, depth+1) &&
            exact_plain(R_ClosureBody(a), R_ClosureBody(b),
                        source_a, source_b, budget, depth+1);
    default: return 0;
    }
}
int dtatools_probe_fresh_formals(SEXP live, SEXP frozen) {
    if (TYPEOF(live) != CLOSXP || TYPEOF(frozen) != CLOSXP ||
        R_ClosureEnv(live) != R_ClosureEnv(frozen)) return 0;
    int budget = 8192;
    return exact_plain(R_ClosureFormals(live),R_ClosureFormals(frozen),
                       R_NilValue,R_NilValue,&budget,0);
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
SEXP C_probe_vctrs_size_guard(SEXP state) {
    if (TYPEOF(state) != ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP ns = current_value(state, "namespace");
    SEXP source = current_value(state, "frozen_source");
    SEXP code = current_value(state, "frozen_code");
    if (TYPEOF(ns) != ENVSXP || !code_equal(current_value(ns, "vec_size"),
                                           source, code))
        return Rf_ScalarLogical(FALSE);
    SEXP proxy_ns = current_value(state, "proxy_namespace");
    SEXP table = current_value(state, "proxy_table");
    SEXP proxy_source = current_value(state, "proxy_source");
    SEXP proxy_code = current_value(state, "proxy_code");
    const char *name = "vec_proxy.dta_numeric";
    if (TYPEOF(proxy_ns) != ENVSXP || TYPEOF(table) != ENVSXP ||
        R_GetBindingType(Rf_install(name), R_GlobalEnv) != R_BindingTypeUnbound ||
        !code_equal(current_value(table, name), proxy_source, proxy_code) ||
        current_value(proxy_ns, name) != current_value(table, name))
        return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(TRUE);
}
/* Test-only exposure of the public BCODESXP instruction vector. */
SEXP C_probe_vec_size_instructions(SEXP fn) {
    if (TYPEOF(fn)!=CLOSXP || TYPEOF(R_ClosureBody(fn))!=BCODESXP)
        return R_NilValue;
    return CAR(R_ClosureBody(fn));
}
SEXP C_probe_same_pointer(SEXP a, SEXP b) {
    return Rf_ScalarLogical(a == b);
}

/* Cost-only fresh content screen for the 14 omitted base closures and two
   effective default methods. Does not claim transitive graph coverage. */
SEXP C_probe_base16_content(SEXP sources, SEXP compiled) {
    static const char *names[] = {
        ".row_names_info", "%in%", "all.names", "character", "environment",
        "is.factor", "is.primitive", "isNamespace", "logical", "numeric",
        "parent.env", "paste", "paste0", "setdiff", "unique.default",
        "anyDuplicated.default"
    };
    if (TYPEOF(sources)!=VECSXP || TYPEOF(compiled)!=VECSXP ||
        XLENGTH(sources)!=16 || XLENGTH(compiled)!=16)
        return Rf_ScalarLogical(FALSE);
    for (int i=0;i<16;i++)
        if (!code_equal(current_value(R_BaseEnv,names[i]),
                        VECTOR_ELT(sources,i),VECTOR_ELT(compiled,i))) {
            return Rf_ScalarLogical(FALSE);
        }
    return Rf_ScalarLogical(TRUE);
}
SEXP C_probe_true(void) { return Rf_ScalarLogical(TRUE); }
SEXP C_probe_true2(SEXP a, SEXP b) { (void)a; (void)b; return Rf_ScalarLogical(TRUE); }
SEXP C_probe_true1(SEXP a) { (void)a; return Rf_ScalarLogical(TRUE); }

/* Cost-only route: the compiled expectation is qualified against the clean
   source snapshot once at load. Each call checks the live compiled closure,
   including its source expression in the constant pool and its attributes.
   No R evaluator or callback is called by this path. */
static int code_equal_fast(SEXP live, SEXP expected) {
    if (TYPEOF(live) != CLOSXP || TYPEOF(expected) != CLOSXP ||
        R_ClosureEnv(live) != R_ClosureEnv(expected)) return 0;
    SEXP body_a = R_ClosureBody(live), body_b = R_ClosureBody(expected);
    if (TYPEOF(body_a) != BCODESXP || TYPEOF(body_b) != BCODESXP) return 0;
    SEXP pool_a = CDR(body_a), pool_b = CDR(body_b);
    if (TYPEOF(pool_a) != VECSXP || TYPEOF(pool_b) != VECSXP ||
        ALTREP(pool_a) || ALTREP(pool_b) ||
        XLENGTH(pool_a) < 1 || XLENGTH(pool_b) < 1) return 0;
    SEXP expr_a = VECTOR_ELT(pool_a, 0), expr_b = VECTOR_ELT(pool_b, 0);
    if (TYPEOF(expr_a) != LANGSXP || TYPEOF(expr_b) != LANGSXP) return 0;
    SEXP sf_a = source_file_attr(expr_a), sf_b = source_file_attr(expr_b);
    if (!((TYPEOF(sf_a) == ENVSXP && TYPEOF(sf_b) == ENVSXP) ||
          (sf_a == R_NilValue && sf_b == R_NilValue))) return 0;
    int budget = 8192;
    return exact_plain(live, expected, sf_a, sf_b, &budget, 0);
}
SEXP C_probe_base16_fast(SEXP sources, SEXP compiled) {
    static const char *names[] = {
        ".row_names_info", "%in%", "all.names", "character", "environment",
        "is.factor", "is.primitive", "isNamespace", "logical", "numeric",
        "parent.env", "paste", "paste0", "setdiff", "unique.default",
        "anyDuplicated.default"
    };
    (void)sources;
    if (TYPEOF(compiled) != VECSXP || XLENGTH(compiled) != 16)
        return Rf_ScalarLogical(FALSE);
    for (int i=0; i<16; ++i)
        if (!code_equal_fast(current_value(R_BaseEnv, names[i]),
                             VECTOR_ELT(compiled,i)))
            return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(TRUE);
}

/* Scratch-only mutation controls. Never call the edited function before the
   saved object has been restored. */
SEXP C_probe_base16_source_expr(SEXP fn) {
    if (TYPEOF(fn) != CLOSXP || TYPEOF(R_ClosureBody(fn)) != BCODESXP)
        return R_NilValue;
    SEXP pool = CDR(R_ClosureBody(fn));
    if (TYPEOF(pool) != VECSXP || ALTREP(pool) || XLENGTH(pool) < 1)
        return R_NilValue;
    return VECTOR_ELT(pool, 0);
}
SEXP C_probe_base16_set_car(SEXP pair, SEXP value) {
    if (TYPEOF(pair) != LANGSXP && TYPEOF(pair) != LISTSXP)
        Rf_error("expected language or pairlist");
    SEXP old = CAR(pair);
    SETCAR(pair, value);
    return old;
}
SEXP C_probe_base16_formal_pair(SEXP fn, SEXP index) {
    if (TYPEOF(fn) != CLOSXP) Rf_error("expected closure");
    int i = Rf_asInteger(index);
    SEXP pair = R_ClosureFormals(fn);
    while (i-- > 0 && TYPEOF(pair) == LISTSXP) pair = CDR(pair);
    if (TYPEOF(pair) != LISTSXP) Rf_error("bad formal index");
    return pair;
}
SEXP C_probe_base16_body(SEXP fn) {
    return TYPEOF(fn) == CLOSXP ? R_ClosureBody(fn) : R_NilValue;
}
SEXP C_probe_base16_formals(SEXP fn) {
    return TYPEOF(fn) == CLOSXP ? R_ClosureFormals(fn) : R_NilValue;
}

/* Conditional pointer-only physical screen. Capture first qualifies each
   live closure against an independent clean-process source/code snapshot.
   The returned state holds separate body/formals/environment references so
   replacing those slots on a same-pointer closure still changes the check. */
SEXP C_probe_base16_pointer_capture(SEXP sources, SEXP compiled) {
    static const char *names[] = {
        ".row_names_info", "%in%", "all.names", "character", "environment",
        "is.factor", "is.primitive", "isNamespace", "logical", "numeric",
        "parent.env", "paste", "paste0", "setdiff", "unique.default",
        "anyDuplicated.default"
    };
    if (TYPEOF(sources) != VECSXP || TYPEOF(compiled) != VECSXP ||
        XLENGTH(sources) != 16 || XLENGTH(compiled) != 16) return R_NilValue;
    SEXP state = PROTECT(Rf_allocVector(VECSXP,6));
    for (int j=0; j<5; ++j)
        SET_VECTOR_ELT(state,j,Rf_allocVector(VECSXP,16));
    SET_VECTOR_ELT(state,5,compiled);
    for (int i=0; i<16; ++i) {
        SEXP sym = Rf_install(names[i]);
        SEXP fn = current_value(R_BaseEnv,names[i]);
        if (!code_equal(fn,VECTOR_ELT(sources,i),VECTOR_ELT(compiled,i))) {
            UNPROTECT(1);
            return R_NilValue;
        }
        SET_VECTOR_ELT(VECTOR_ELT(state,0),i,sym);
        SET_VECTOR_ELT(VECTOR_ELT(state,1),i,fn);
        SET_VECTOR_ELT(VECTOR_ELT(state,2),i,R_ClosureBody(fn));
        SET_VECTOR_ELT(VECTOR_ELT(state,3),i,R_ClosureFormals(fn));
        SET_VECTOR_ELT(VECTOR_ELT(state,4),i,R_ClosureEnv(fn));
    }
    UNPROTECT(1);
    return state;
}
static SEXP base16_pointer_guard_common(SEXP state, int check_source) {
    if (TYPEOF(state) != VECSXP || XLENGTH(state) != 6)
        return Rf_ScalarLogical(FALSE);
    for (int i=0; i<16; ++i) {
        SEXP sym = VECTOR_ELT(VECTOR_ELT(state,0),i);
        R_BindingType_t kind = R_GetBindingType(sym,R_BaseEnv);
        if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
            return Rf_ScalarLogical(FALSE);
        SEXP fn = R_getVarEx(sym,R_BaseEnv,FALSE,R_NilValue);
        if (TYPEOF(fn) != CLOSXP ||
            fn != VECTOR_ELT(VECTOR_ELT(state,1),i) ||
            R_ClosureBody(fn) != VECTOR_ELT(VECTOR_ELT(state,2),i) ||
            R_ClosureFormals(fn) != VECTOR_ELT(VECTOR_ELT(state,3),i) ||
            R_ClosureEnv(fn) != VECTOR_ELT(VECTOR_ELT(state,4),i) ||
            ANY_ATTRIB(fn))
            return Rf_ScalarLogical(FALSE);
        SEXP expected = VECTOR_ELT(VECTOR_ELT(state,5),i);
        int budget = 8192;
        if (!exact_plain(R_ClosureFormals(fn),R_ClosureFormals(expected),
                         R_NilValue,R_NilValue,&budget,0))
            return Rf_ScalarLogical(FALSE);
        if (!check_source) continue;
        SEXP pool_a = CDR(R_ClosureBody(fn));
        SEXP pool_b = CDR(R_ClosureBody(expected));
        if (TYPEOF(pool_a) != VECSXP || TYPEOF(pool_b) != VECSXP ||
            ALTREP(pool_a) || ALTREP(pool_b) ||
            XLENGTH(pool_a) < 1 || XLENGTH(pool_b) < 1)
            return Rf_ScalarLogical(FALSE);
        SEXP expr_a = VECTOR_ELT(pool_a,0), expr_b = VECTOR_ELT(pool_b,0);
        if (TYPEOF(expr_a) != LANGSXP || TYPEOF(expr_b) != LANGSXP)
            return Rf_ScalarLogical(FALSE);
        SEXP sf_a = source_file_attr(expr_a), sf_b = source_file_attr(expr_b);
        if (!((TYPEOF(sf_a) == ENVSXP && TYPEOF(sf_b) == ENVSXP) ||
              (sf_a == R_NilValue && sf_b == R_NilValue)) ||
            !exact_plain(expr_a,expr_b,sf_a,sf_b,&budget,0))
            return Rf_ScalarLogical(FALSE);
    }
    return Rf_ScalarLogical(TRUE);
}
SEXP C_probe_base16_pointer_guard(SEXP state) {
    return base16_pointer_guard_common(state,1);
}
static int base16_check_source = 1;
SEXP C_dtatools_probe_base16_mode(SEXP mode) {
    if (TYPEOF(mode) != INTSXP || XLENGTH(mode) != 1 ||
        (INTEGER(mode)[0] != 0 && INTEGER(mode)[0] != 1))
        Rf_error("base16 source mode must be 0 or 1");
    int previous = base16_check_source;
    base16_check_source = INTEGER(mode)[0];
    return Rf_ScalarInteger(previous);
}
SEXP C_dtatools_probe_base16_formals_only(SEXP state) {
    if (TYPEOF(state) != ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP live = R_getVarEx(Rf_install("live"),state,FALSE,R_NilValue);
    return base16_pointer_guard_common(live,0);
}

SEXP C_dtatools_probe_base16_guard(SEXP state) {
    if (TYPEOF(state) != ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP live = R_getVarEx(Rf_install("live"),state,FALSE,R_NilValue);
    if (live == R_NilValue) {
        SEXP sources = R_getVarEx(Rf_install("source"),state,FALSE,R_NilValue);
        SEXP compiled = R_getVarEx(Rf_install("compiled"),state,FALSE,R_NilValue);
        live = PROTECT(C_probe_base16_pointer_capture(sources,compiled));
        if (live != R_NilValue)
            Rf_defineVar(Rf_install("live"),live,state);
        UNPROTECT(1);
    }
    return base16_pointer_guard_common(live,base16_check_source);
}
SEXP C_probe_base16_set_constant(SEXP fn, SEXP index, SEXP value) {
    if (TYPEOF(fn) != CLOSXP || TYPEOF(R_ClosureBody(fn)) != BCODESXP)
        Rf_error("expected compiled closure");
    SEXP pool = CDR(R_ClosureBody(fn));
    int i = Rf_asInteger(index);
    if (TYPEOF(pool) != VECSXP || ALTREP(pool) || i < 0 || i >= XLENGTH(pool))
        Rf_error("bad constant index");
    SEXP old = VECTOR_ELT(pool, i);
    SET_VECTOR_ELT(pool, i, value);
    return old;
}
