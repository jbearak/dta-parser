#include <R.h>
#include <Rinternals.h>
#include <string.h>
extern int dtatools_probe_public_debugged(SEXP fn);
/* Decline callback-capable or unsupported nodes before comparing a live
   default expression. The disjoint expected forms are qualified separately. */
static int plain_formal(SEXP x, int *budget, int depth) {
    if (--*budget < 0 || depth > 64 || ALTREP(x) || ANY_ATTRIB(x))
        return 0;
    switch (TYPEOF(x)) {
    case NILSXP: case SYMSXP: case CHARSXP: case BUILTINSXP:
    case SPECIALSXP: case ENVSXP: return 1;
    case LGLSXP: case INTSXP: case REALSXP: case CPLXSXP: case RAWSXP:
        return XLENGTH(x) <= 4096;
    case STRSXP:
        if (XLENGTH(x) > 4096) return 0;
        for (R_xlen_t i=0; i<XLENGTH(x); ++i)
            if (!plain_formal(STRING_ELT(x,i),budget,depth+1)) return 0;
        return 1;
    case LANGSXP: case LISTSXP: case DOTSXP:
        return plain_formal(TAG(x),budget,depth+1) &&
            plain_formal(CAR(x),budget,depth+1) &&
            plain_formal(CDR(x),budget,depth+1);
    case VECSXP: case EXPRSXP:
        if (XLENGTH(x) > 4096) return 0;
        for (R_xlen_t i=0; i<XLENGTH(x); ++i)
            if (!plain_formal(VECTOR_ELT(x,i),budget,depth+1)) return 0;
        return 1;
    default: return 0;
    }
}
typedef struct { int count; SEXP tag[8]; SEXP value[8]; } closure_attrs;
static int plain_attr_tree(SEXP x, int *budget, int depth);
typedef struct { int *budget; int depth; int count; } attr_walk;
static SEXP validate_nested_attr(SEXP tag, SEXP value, void *context) {
    attr_walk *walk = (attr_walk *)context;
    if (++walk->count > 16 || TYPEOF(tag)!=SYMSXP || ANY_ATTRIB(tag) ||
        !plain_attr_tree(value,walk->budget,walk->depth+1)) return R_NilValue;
    return NULL;
}
static int plain_attr_tree(SEXP x, int *budget, int depth) {
    if (--*budget < 0 || depth > 64 || ALTREP(x)) return 0;
    if (TYPEOF(x)==SYMSXP || TYPEOF(x)==CHARSXP) {
        if (ANY_ATTRIB(x)) return 0;
    } else {
        attr_walk walk = {.budget=budget,.depth=depth,.count=0};
        if (R_mapAttrib(x,validate_nested_attr,&walk) != NULL) return 0;
    }
    switch(TYPEOF(x)) {
    case NILSXP: case SYMSXP: case CHARSXP: case BUILTINSXP:
    case SPECIALSXP: case ENVSXP: return 1;
    case LGLSXP: case INTSXP: case REALSXP: case CPLXSXP: case RAWSXP:
        return XLENGTH(x) <= 4096;
    case STRSXP:
        if (XLENGTH(x)>4096) return 0;
        for (R_xlen_t i=0;i<XLENGTH(x);++i)
            if (!plain_attr_tree(STRING_ELT(x,i),budget,depth+1)) return 0;
        return 1;
    case LANGSXP: case LISTSXP: case DOTSXP: case BCODESXP:
        return plain_attr_tree(TAG(x),budget,depth+1) &&
            plain_attr_tree(CAR(x),budget,depth+1) &&
            plain_attr_tree(CDR(x),budget,depth+1);
    case CLOSXP:
        return plain_attr_tree(R_ClosureFormals(x),budget,depth+1) &&
            plain_attr_tree(R_ClosureBody(x),budget,depth+1) &&
            plain_attr_tree(R_ClosureEnv(x),budget,depth+1);
    case VECSXP: case EXPRSXP:
        if (XLENGTH(x)>4096) return 0;
        for (R_xlen_t i=0;i<XLENGTH(x);++i)
            if (!plain_attr_tree(VECTOR_ELT(x,i),budget,depth+1)) return 0;
        return 1;
    default: return 0;
    }
}

SEXP C_probe_wrapper_plain(SEXP fn) {
    int budget=32768;
    return Rf_ScalarLogical(TYPEOF(fn)==CLOSXP &&
                            plain_attr_tree(fn,&budget,0));
}

SEXP C_probe_wrapper_ident_flags(SEXP a, SEXP b) {
    if (TYPEOF(a)!=CLOSXP || TYPEOF(b)!=CLOSXP)
        return R_NilValue;
    SEXP out = PROTECT(Rf_allocMatrix(LGLSXP,4,8));
    SEXP ax[4] = {a,R_ClosureFormals(a),R_ClosureBody(a),R_ClosureExpr(a)};
    SEXP bx[4] = {b,R_ClosureFormals(b),R_ClosureBody(b),R_ClosureExpr(b)};
    for (int j=0;j<8;j++) {
        int flags=(j&1 ? IDENT_USE_BYTECODE : 0) |
            (j&2 ? IDENT_USE_CLOENV : 0) |
            (j&4 ? IDENT_USE_SRCREF : 0);
        for (int i=0;i<4;i++)
            LOGICAL(out)[i+4*j] = R_compute_identical(ax[i],bx[i],flags);
    }
    UNPROTECT(1);
    return out;
}
static SEXP capture_closure_attr(SEXP tag, SEXP value, void *context) {
    closure_attrs *out = (closure_attrs *)context;
    if (out->count >= 8 || TYPEOF(tag) != SYMSXP || ANY_ATTRIB(tag))
        return R_NilValue;
    out->tag[out->count] = tag;
    out->value[out->count++] = value;
    return NULL;
}
static SEXP body_source_file(SEXP expression) {
    closure_attrs a = {.count=0};
    if (R_mapAttrib(expression,capture_closure_attr,&a) != NULL)
        return R_NilValue;
    SEXP tag = Rf_install("srcfile"), value = R_NilValue;
    for (int i=0;i<a.count;++i)
        if (a.tag[i]==tag) {
            if (value!=R_NilValue) return R_NilValue;
            value=a.value[i];
        }
    return value;
}
static int exact_source_tree(SEXP a, SEXP b, SEXP source_a, SEXP source_b,
                             int *budget, int depth) {
    if (--*budget<0 || depth>96 || TYPEOF(a)!=TYPEOF(b) ||
        ALTREP(a) || ALTREP(b) || Rf_isObject(a)!=Rf_isObject(b) ||
        Rf_isS4(a)!=Rf_isS4(b)) return 0;
    if (a==b) return 1;
    closure_attrs aa={.count=0}, ab={.count=0};
    if (TYPEOF(a)!=CHARSXP && TYPEOF(a)!=SYMSXP) {
        if (R_mapAttrib(a,capture_closure_attr,&aa)!=NULL ||
            R_mapAttrib(b,capture_closure_attr,&ab)!=NULL ||
            aa.count!=ab.count) return 0;
        for (int i=0;i<aa.count;++i)
            if (aa.tag[i]!=ab.tag[i] ||
                !exact_source_tree(aa.value[i],ab.value[i],source_a,source_b,
                                   budget,depth+1)) return 0;
    } else if (TYPEOF(a)==SYMSXP && (ANY_ATTRIB(a)||ANY_ATTRIB(b))) return 0;
    switch(TYPEOF(a)) {
    case NILSXP: case SYMSXP: case BUILTINSXP: case SPECIALSXP:
        return a==b;
    case ENVSXP:
        return (a==source_a && b==source_b) || a==b;
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
        for (R_xlen_t i=0;i<XLENGTH(a);++i)
            if (!exact_source_tree(STRING_ELT(a,i),STRING_ELT(b,i),
                                   source_a,source_b,budget,depth+1)) return 0;
        return 1;
    case LANGSXP: case LISTSXP: case DOTSXP: case BCODESXP:
        return exact_source_tree(TAG(a),TAG(b),source_a,source_b,budget,depth+1) &&
            exact_source_tree(CAR(a),CAR(b),source_a,source_b,budget,depth+1) &&
            exact_source_tree(CDR(a),CDR(b),source_a,source_b,budget,depth+1);
    case CLOSXP:
        return exact_source_tree(R_ClosureFormals(a),R_ClosureFormals(b),
                                 source_a,source_b,budget,depth+1) &&
            exact_source_tree(R_ClosureBody(a),R_ClosureBody(b),
                                 source_a,source_b,budget,depth+1) &&
            exact_source_tree(R_ClosureEnv(a),R_ClosureEnv(b),
                                 source_a,source_b,budget,depth+1);
    case VECSXP: case EXPRSXP:
        if (XLENGTH(a)!=XLENGTH(b) || XLENGTH(a)>*budget) return 0;
        for (R_xlen_t i=0;i<XLENGTH(a);++i)
            if (!exact_source_tree(VECTOR_ELT(a,i),VECTOR_ELT(b,i),
                                   source_a,source_b,budget,depth+1)) return 0;
        return 1;
    default: return 0;
    }
}
SEXP C_probe_wrapper_source_qualification(SEXP current, SEXP frozen) {
    if (TYPEOF(current)!=CLOSXP || TYPEOF(frozen)!=CLOSXP)
        return R_NilValue;
    int plain_a=32768,plain_b=32768;
    if (!plain_attr_tree(current,&plain_a,0) ||
        !plain_attr_tree(frozen,&plain_b,0)) return R_NilValue;
    SEXP ca=R_ClosureExpr(current), cb=R_ClosureExpr(frozen);
    SEXP sa=body_source_file(ca), sb=body_source_file(cb);
    if (TYPEOF(sa)!=ENVSXP || TYPEOF(sb)!=ENVSXP ||
        R_ClosureEnv(current)!=R_ClosureEnv(frozen)) return R_NilValue;
    SEXP out=PROTECT(Rf_allocVector(LGLSXP,4));
    int budget=32768;
    LOGICAL(out)[0]=exact_source_tree(R_ClosureFormals(current),
        R_ClosureFormals(frozen),sa,sb,&budget,0);
    budget=32768;
    LOGICAL(out)[1]=exact_source_tree(ca,cb,sa,sb,&budget,0);
    budget=32768;
    LOGICAL(out)[2]=exact_source_tree(R_ClosureBody(current),
        R_ClosureBody(frozen),sa,sb,&budget,0);
    budget=32768;
    LOGICAL(out)[3]=exact_source_tree(current,frozen,sa,sb,&budget,0);
    UNPROTECT(1);
    return out;
}
static int same_closure_attrs(SEXP actual, SEXP expected) {
    closure_attrs a = {.count=0}, b = {.count=0};
    if (R_mapAttrib(actual,capture_closure_attr,&a) != NULL ||
        R_mapAttrib(expected,capture_closure_attr,&b) != NULL ||
        a.count != b.count) return 0;
    for (int i=0; i<a.count; ++i) {
        int budget=4096;
        if (a.tag[i] != b.tag[i] ||
            !plain_attr_tree(a.value[i],&budget,0) ||
            !R_compute_identical(a.value[i],b.value[i],
                                 IDENT_USE_CLOENV|IDENT_USE_SRCREF|
                                     IDENT_USE_BYTECODE)) return 0;
    }
    return 1;
}
static int canonical_base_internal(SEXP expected) {
    SEXP sym = Rf_install(".Internal");
    R_BindingType_t kind = R_GetBindingType(sym,R_BaseEnv);
    return TYPEOF(expected)==SPECIALSXP &&
        (kind==R_BindingTypeValue || kind==R_BindingTypeForced) &&
        R_getVarEx(sym,R_BaseEnv,FALSE,R_NilValue)==expected;
}

SEXP C_probe_current_by_helper_safe(SEXP helper, SEXP expected,
                                    SEXP frozen_formals, SEXP expected_internal) {
    if (TYPEOF(helper)!=CLOSXP || TYPEOF(expected)!=CLOSXP)
        return Rf_ScalarLogical(FALSE);
    if (!canonical_base_internal(expected_internal))
        return Rf_ScalarLogical(FALSE);
    SEXP frame = R_GetCurrentEnv();
    SEXP zero = PROTECT(Rf_ScalarInteger(0));
    SEXP call = PROTECT(Rf_lang2(helper,zero));
    SEXP actual = PROTECT(Rf_eval(call,frame));
    int budget=4096;
    int same = TYPEOF(actual)==CLOSXP &&
        canonical_base_internal(expected_internal) &&
        R_ClosureBody(actual)==R_ClosureBody(expected) &&
        R_ClosureFormals(actual)==R_ClosureFormals(expected) &&
        R_ClosureEnv(actual)==R_ClosureEnv(expected) &&
        same_closure_attrs(actual,expected) &&
        plain_formal(R_ClosureFormals(actual),&budget,0) &&
        R_compute_identical(R_ClosureFormals(actual),frozen_formals,
                            IDENT_USE_CLOENV|IDENT_USE_SRCREF|
                                IDENT_USE_BYTECODE);
    UNPROTECT(3);
    return Rf_ScalarLogical(same);
}
/* Source-owned tiny helper constructed from C symbols, with a locked lexical
   alias to base's canonical .Internal primitive. It has no user R template. */
SEXP C_probe_make_sys_function_helper(SEXP expected_internal) {
    SEXP internal_sym = Rf_install(".Internal");
    SEXP sys_fun_sym = Rf_install("sys.function");
    SEXP which_sym = Rf_install("which");
    if (!canonical_base_internal(expected_internal))
        Rf_error("base .Internal does not match the clean build");
    SEXP internal = expected_internal;
    SEXP env = PROTECT(R_NewEnv(R_EmptyEnv,TRUE,1));
    Rf_defineVar(internal_sym,internal,env);
    R_LockEnvironment(env,TRUE);
    SEXP formals = PROTECT(Rf_cons(R_MissingArg,R_NilValue));
    SET_TAG(formals,which_sym);
    SEXP query = PROTECT(Rf_lang2(sys_fun_sym,which_sym));
    SEXP body = PROTECT(Rf_lang2(internal_sym,query));
    SEXP helper = PROTECT(R_mkClosure(formals,body,env));
    UNPROTECT(5);
    return helper;
}

/* A clean installed build supplies the disjoint serialized closure and base
   primitive. Qualification checks the complete compiled wrapper, including
   source AST and bytecode, after a callback-free tree prewalk. */
static int wrapper_source_equal(SEXP current, SEXP frozen) {
    if (TYPEOF(current)!=CLOSXP || TYPEOF(frozen)!=CLOSXP ||
        TYPEOF(R_ClosureBody(current))!=BCODESXP ||
        TYPEOF(R_ClosureBody(frozen))!=BCODESXP ||
        R_ClosureEnv(current)!=R_ClosureEnv(frozen)) return 0;
    int plain_a=32768, plain_b=32768;
    if (!plain_attr_tree(current,&plain_a,0) ||
        !plain_attr_tree(frozen,&plain_b,0)) return 0;
    SEXP ca=R_ClosureExpr(current), cb=R_ClosureExpr(frozen);
    SEXP sa=body_source_file(ca), sb=body_source_file(cb);
    if (!((TYPEOF(sa)==ENVSXP && TYPEOF(sb)==ENVSXP) ||
          (sa==R_NilValue && sb==R_NilValue))) return 0;
    int budget=32768;
    return exact_source_tree(current,frozen,sa,sb,&budget,0);
}

static SEXP wrapper_state_value(SEXP state, const char *name) {
    SEXP sym=Rf_install(name);
    R_BindingType_t kind=R_GetBindingType(sym,state);
    if (kind!=R_BindingTypeValue && kind!=R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(sym,state,FALSE,R_NilValue);
}

SEXP C_dtatools_probe_wrapper_capture(SEXP state) {
    if (TYPEOF(state)!=ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP frozen=wrapper_state_value(state,"frozen");
    SEXP current=wrapper_state_value(state,"live");
    SEXP repl_current=wrapper_state_value(state,"repl");
    SEXP expected_internal=wrapper_state_value(state,"internal");
    if (!canonical_base_internal(expected_internal) ||
        !wrapper_source_equal(current,frozen) ||
        !wrapper_source_equal(repl_current,frozen) ||
        ANY_ATTRIB(current) || ANY_ATTRIB(repl_current) ||
        ANY_ATTRIB(frozen))
        return Rf_ScalarLogical(FALSE);
    SEXP helper=PROTECT(C_probe_make_sys_function_helper(expected_internal));
    Rf_defineVar(Rf_install("helper"),helper,state);
    Rf_defineVar(Rf_install("body"),R_ClosureBody(current),state);
    Rf_defineVar(Rf_install("repl_body"),R_ClosureBody(repl_current),state);
    Rf_defineVar(Rf_install("formals"),R_ClosureFormals(frozen),state);
    UNPROTECT(1);
    return Rf_ScalarLogical(TRUE);
}

/* Called from the active public wrapper's .Call, including again immediately
   before the callback-free arithmetic and publication. */
int dtatools_probe_wrapper_current(SEXP state) {
    if (TYPEOF(state)!=ENVSXP) return 0;
    SEXP live=wrapper_state_value(state,"live");
    SEXP repl_live=wrapper_state_value(state,"repl");
    SEXP helper=wrapper_state_value(state,"helper");
    SEXP body=wrapper_state_value(state,"body");
    SEXP repl_body=wrapper_state_value(state,"repl_body");
    SEXP frozen_formals=wrapper_state_value(state,"formals");
    SEXP expected_internal=wrapper_state_value(state,"internal");
    if (TYPEOF(live)!=CLOSXP || TYPEOF(repl_live)!=CLOSXP ||
        TYPEOF(helper)!=CLOSXP || TYPEOF(body)!=BCODESXP ||
        TYPEOF(repl_body)!=BCODESXP ||
        !canonical_base_internal(expected_internal) ||
        dtatools_probe_public_debugged(live) != 0 ||
        dtatools_probe_public_debugged(repl_live) != 0) return 0;
    SEXP frame=R_GetCurrentEnv();
    if (dtatools_probe_public_debugged(frame) != 0) return 0;
    SEXP zero=PROTECT(Rf_ScalarInteger(0));
    SEXP call=PROTECT(Rf_lang2(helper,zero));
    SEXP actual=PROTECT(Rf_eval(call,frame));
    if (dtatools_probe_public_debugged(actual) != 0) {
        UNPROTECT(3);
        return 0;
    }
    int budget=4096;
    int primary=TYPEOF(actual)==CLOSXP &&
        !ANY_ATTRIB(live) &&
        R_ClosureBody(actual)==body && R_ClosureBody(live)==body &&
        R_ClosureFormals(actual)==R_ClosureFormals(live) &&
        R_ClosureEnv(actual)==R_ClosureEnv(live);
    int alias=TYPEOF(actual)==CLOSXP &&
        !ANY_ATTRIB(repl_live) &&
        R_ClosureBody(actual)==repl_body &&
        R_ClosureBody(repl_live)==repl_body &&
        R_ClosureFormals(actual)==R_ClosureFormals(repl_live) &&
        R_ClosureEnv(actual)==R_ClosureEnv(repl_live);
    int same=TYPEOF(actual)==CLOSXP &&
        canonical_base_internal(expected_internal) &&
        !ANY_ATTRIB(actual) && (primary || alias) &&
        plain_formal(R_ClosureFormals(actual),&budget,0) &&
        R_compute_identical(R_ClosureFormals(actual),frozen_formals,
                            IDENT_USE_CLOENV|IDENT_USE_SRCREF|
                                IDENT_USE_BYTECODE);
    UNPROTECT(3);
    return same;
}

SEXP C_dtatools_probe_wrapper_guard(SEXP state) {
    return Rf_ScalarLogical(dtatools_probe_wrapper_current(state));
}
