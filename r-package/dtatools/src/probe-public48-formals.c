#include <R.h>
#include <Rinternals.h>
extern int dtatools_probe_public48_attrs_debug(SEXP state);

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

SEXP C_probe_48_expected_plain(SEXP expected) {
    if (TYPEOF(expected) != VECSXP || XLENGTH(expected) != 58)
        return Rf_ScalarLogical(FALSE);
    for (R_xlen_t i=0; i<58; ++i) {
        int budget = 4096;
        if (!plain_formal(VECTOR_ELT(expected,i),&budget,0))
            return Rf_ScalarLogical(FALSE);
    }
    return Rf_ScalarLogical(TRUE);
}

static SEXP probe_formals(SEXP envs, SEXP labels, SEXP expected, int safe) {
    R_xlen_t count = XLENGTH(envs);
    if (TYPEOF(envs) != VECSXP || TYPEOF(labels) != STRSXP ||
        TYPEOF(expected) != VECSXP || count < 1 || count > 58 ||
        XLENGTH(labels) != count || XLENGTH(expected) != count)
        return Rf_ScalarLogical(FALSE);
    for (R_xlen_t i = 0; i < count; ++i) {
        SEXP env = VECTOR_ELT(envs, i);
        if (TYPEOF(env) != ENVSXP) return Rf_ScalarLogical(FALSE);
        SEXP symbol = Rf_installChar(STRING_ELT(labels, i));
        R_BindingType_t kind = R_GetBindingType(symbol, env);
        if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
            return Rf_ScalarLogical(FALSE);
        SEXP fn = R_getVarEx(symbol, env, FALSE, R_NilValue);
        if (TYPEOF(fn) != CLOSXP) return Rf_ScalarLogical(FALSE);
        SEXP forms = R_ClosureFormals(fn);
        int budget = 4096;
        if ((safe && !plain_formal(forms,&budget,0)) ||
            !R_compute_identical(forms, VECTOR_ELT(expected, i),
                                 IDENT_USE_CLOENV | IDENT_USE_SRCREF |
                                     IDENT_USE_BYTECODE))
            return Rf_ScalarLogical(FALSE);
    }
    return Rf_ScalarLogical(TRUE);
}

SEXP C_probe_48_formals(SEXP envs, SEXP labels, SEXP expected) {
    return probe_formals(envs,labels,expected,0);
}

SEXP C_probe_48_formals_safe(SEXP envs, SEXP labels, SEXP expected) {
    return probe_formals(envs,labels,expected,1);
}

SEXP C_probe_48_noop(SEXP envs, SEXP labels, SEXP expected) {
    (void)envs; (void)labels; (void)expected;
    return Rf_ScalarLogical(TRUE);
}


/* Integrated scratch admission. The independent source snapshots are checked
   by the package-load R initializer before this capture. */
static SEXP state_value(SEXP state, const char *name) {
    SEXP sym = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(sym,state);
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(sym,state,FALSE,R_NilValue);
}

SEXP C_dtatools_probe_public48_capture(SEXP state) {
    if (TYPEOF(state)!=ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP envs=state_value(state,"envs"), labels=state_value(state,"labels");
    SEXP expected=state_value(state,"expected"), live=state_value(state,"live");
    if (TYPEOF(envs)!=VECSXP || TYPEOF(labels)!=STRSXP ||
        TYPEOF(expected)!=VECSXP || TYPEOF(live)!=VECSXP ||
        XLENGTH(envs)!=58 || XLENGTH(labels)!=58 ||
        XLENGTH(expected)!=58 || XLENGTH(live)!=58 ||
        Rf_asLogical(C_probe_48_expected_plain(expected))!=TRUE)
        return Rf_ScalarLogical(FALSE);
    SEXP bodies=PROTECT(Rf_allocVector(VECSXP,58));
    SEXP closure_envs=PROTECT(Rf_allocVector(VECSXP,58));
    for (R_xlen_t i=0;i<58;++i) {
        SEXP env=VECTOR_ELT(envs,i), fn=VECTOR_ELT(live,i);
        if (TYPEOF(env)!=ENVSXP || TYPEOF(fn)!=CLOSXP) {
            UNPROTECT(2); return Rf_ScalarLogical(FALSE);
        }
        SEXP sym=Rf_installChar(STRING_ELT(labels,i));
        R_BindingType_t kind=R_GetBindingType(sym,env);
        if ((kind!=R_BindingTypeValue && kind!=R_BindingTypeForced) ||
            R_getVarEx(sym,env,FALSE,R_NilValue)!=fn) {
            UNPROTECT(2); return Rf_ScalarLogical(FALSE);
        }
        SET_VECTOR_ELT(bodies,i,R_ClosureBody(fn));
        SET_VECTOR_ELT(closure_envs,i,R_ClosureEnv(fn));
    }
    Rf_defineVar(Rf_install("bodies"),bodies,state);
    Rf_defineVar(Rf_install("closure_envs"),closure_envs,state);
    UNPROTECT(2);
    return Rf_ScalarLogical(TRUE);
}

int dtatools_probe_public48_guard_plain(SEXP state) {
    if (TYPEOF(state)!=ENVSXP) return 0;
    SEXP envs=state_value(state,"envs"), labels=state_value(state,"labels");
    SEXP expected=state_value(state,"expected"), live=state_value(state,"live");
    SEXP bodies=state_value(state,"bodies");
    SEXP closure_envs=state_value(state,"closure_envs");
    if (TYPEOF(envs)!=VECSXP || TYPEOF(labels)!=STRSXP ||
        TYPEOF(expected)!=VECSXP || TYPEOF(live)!=VECSXP ||
        TYPEOF(bodies)!=VECSXP || TYPEOF(closure_envs)!=VECSXP ||
        XLENGTH(envs)!=58 || XLENGTH(labels)!=58 ||
        XLENGTH(expected)!=58 || XLENGTH(live)!=58 ||
        XLENGTH(bodies)!=58 || XLENGTH(closure_envs)!=58)
        return 0;
    for (R_xlen_t i=0;i<58;++i) {
        SEXP env=VECTOR_ELT(envs,i);
        if (TYPEOF(env)!=ENVSXP) return 0;
        SEXP sym=Rf_installChar(STRING_ELT(labels,i));
        R_BindingType_t kind=R_GetBindingType(sym,env);
        if (kind!=R_BindingTypeValue && kind!=R_BindingTypeForced)
            return 0;
        SEXP fn=R_getVarEx(sym,env,FALSE,R_NilValue);
        if (TYPEOF(fn)!=CLOSXP || fn!=VECTOR_ELT(live,i) ||
            R_ClosureBody(fn)!=VECTOR_ELT(bodies,i) ||
            R_ClosureEnv(fn)!=VECTOR_ELT(closure_envs,i))
            return 0;
        SEXP forms=R_ClosureFormals(fn);
        int budget=4096;
        if (!plain_formal(forms,&budget,0) ||
            !R_compute_identical(forms,VECTOR_ELT(expected,i),
                                 IDENT_USE_CLOENV|IDENT_USE_SRCREF|
                                     IDENT_USE_BYTECODE))
            return 0;
    }
    return dtatools_probe_public48_attrs_debug(state);
}

SEXP C_dtatools_probe_public48_guard(SEXP state) {
    return Rf_ScalarLogical(dtatools_probe_public48_guard_plain(state));
}
