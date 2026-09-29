/* Scratch, pinned R 4.6.1: one public closure/primitive steady admission.
   Full source/code qualification is performed once by .probe_public48_init.
   This is a physical compatibility slice, not a complete graph proof. */
#include <R.h>
#include <Rinternals.h>
extern SEXP C_dtatools_probe_base_guard(SEXP state, SEXP quosure);
extern int dtatools_probe_public48_guard_plain(SEXP state);
extern int dtatools_probe_scalar_public_dependencies_after50(
    SEXP dependencies, SEXP public_state);

static SEXP value(SEXP env, const char *name) {
    if (TYPEOF(env) != ENVSXP) return R_NilValue;
    SEXP sym=Rf_install(name);
    R_BindingType_t kind=R_GetBindingType(sym,env);
    if (kind!=R_BindingTypeValue && kind!=R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(sym,env,FALSE,R_NilValue);
}
static int table_has(SEXP table, const char *name, SEXP expected) {
    SEXP sym=Rf_install(name);
    R_BindingType_t kind=R_GetBindingType(sym,table);
    return (kind==R_BindingTypeValue || kind==R_BindingTypeForced) &&
        R_getVarEx(sym,table,FALSE,R_NilValue)==expected;
}
static int no_method(SEXP caller, SEXP table, const char *name) {
    SEXP sym=Rf_install(name);
    if (TYPEOF(caller)!=ENVSXP ||
        R_GetBindingType(sym,table)!=R_BindingTypeUnbound) return 0;
    for (SEXP env=caller;;env=R_ParentEnv(env)) {
        if (R_GetBindingType(sym,env)!=R_BindingTypeUnbound) return 0;
        if (env==R_GlobalEnv) break;
        if (env==R_BaseEnv || env==R_EmptyEnv) return 0;
    }
    for (SEXP env=R_ParentEnv(R_GlobalEnv);env!=R_BaseEnv;
         env=R_ParentEnv(env)) {
        if (env==R_EmptyEnv ||
            R_GetBindingType(sym,env)!=R_BindingTypeUnbound) return 0;
    }
    return R_GetBindingType(sym,R_BaseEnv)==R_BindingTypeUnbound;
}
SEXP C_dtatools_probe_public_fused_guard(SEXP base, SEXP public48,
                                          SEXP vctrs, SEXP quosure,
                                          SEXP dependencies) {
    if (TYPEOF(base)!=ENVSXP || TYPEOF(public48)!=ENVSXP ||
        TYPEOF(vctrs)!=ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP base_live=value(base,"live");
    if (base_live==R_NilValue) {
        if (Rf_asLogical(C_dtatools_probe_base_guard(base,quosure))!=TRUE)
            return Rf_ScalarLogical(FALSE);
        base_live=value(base,"live");
    }
    if (TYPEOF(base_live)!=VECSXP || XLENGTH(base_live)!=29)
        return Rf_ScalarLogical(FALSE);
    /* Keep the full live public-root check and the six-source-elision
       continuation adjacent in C. There is no R dispatch, callback, or
       explicit allocation between these two successful checks. */
    if (!dtatools_probe_public48_guard_plain(public48) ||
        !dtatools_probe_scalar_public_dependencies_after50(
            dependencies, public48))
        return Rf_ScalarLogical(FALSE);
    static const char *primitive_names[]={"c","$","missing","&&","if",
        "return","!","is.null",".Call","attr<-","attributes<-"};
    for (int i=0;i<11;++i)
        if (value(R_BaseEnv,primitive_names[i])!=VECTOR_ELT(base_live,18+i))
            return Rf_ScalarLogical(FALSE);
    SEXP table=value(R_BaseEnv,".__S3MethodsTable__.");
    SEXP public_live=value(public48,"live");
    if (TYPEOF(table)!=ENVSXP ||
        TYPEOF(public_live)!=VECSXP || XLENGTH(public_live)!=58 ||
        !table_has(table,"names<-.vctrs_vctr",VECTOR_ELT(public_live,50)) ||
        !table_has(table,"unique.default",VECTOR_ELT(base_live,15)) ||
        !table_has(table,"anyDuplicated.default",VECTOR_ELT(base_live,16)) ||
        !table_has(table,"as.list.default",VECTOR_ELT(base_live,17)))
        return Rf_ScalarLogical(FALSE);
    SEXP caller=Rf_getAttrib(quosure,Rf_install(".Environment"));
    if (!no_method(caller,table,"unique.character") ||
        !no_method(caller,table,"anyDuplicated.character") ||
        !no_method(caller,table,"as.list.list") ||
        !no_method(caller,table,"dim.dta_double") ||
        !no_method(caller,table,"dim.dta_numeric") ||
        !no_method(caller,table,"dim.vctrs_vctr") ||
        !no_method(caller,table,"dim.double") ||
        !no_method(caller,table,"dim.default") ||
        !no_method(caller,table,"names.dta_double") ||
        !no_method(caller,table,"names.dta_numeric") ||
        !no_method(caller,table,"names.default") ||
        !no_method(caller,table,"names.vctrs_vctr") ||
        !no_method(caller,table,"names.double") ||
        !no_method(caller,table,"names<-.dta_numeric") ||
        !no_method(caller,table,"names<-.dta_double") ||
        !no_method(caller,table,"names<-.double") ||
        !no_method(caller,table,"names<-.default"))
        return Rf_ScalarLogical(FALSE);
    SEXP proxy_ns=value(vctrs,"proxy_namespace");
    SEXP proxy_table=value(vctrs,"proxy_table");
    SEXP dta_table=value(proxy_ns,".__S3MethodsTable__.");
    if (TYPEOF(proxy_ns)!=ENVSXP || TYPEOF(proxy_table)!=ENVSXP ||
        TYPEOF(dta_table)!=ENVSXP ||
        !no_method(caller,dta_table,"vec_arith.dta_numeric.double") ||
        R_GetBindingType(Rf_install("vec_proxy.dta_numeric"),R_GlobalEnv)!=
            R_BindingTypeUnbound ||
        value(proxy_ns,"vec_proxy.dta_numeric")!=
            value(proxy_table,"vec_proxy.dta_numeric"))
        return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(TRUE);
}
