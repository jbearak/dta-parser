#include <R.h>
#include <Rinternals.h>

/* R 4.6.1-only scratch guard. The named S3 table is an implementation detail. */
static SEXP sym[11];
static int symbols_ready = 0;

enum {
    PLUS, PLUS_NUMERIC, OPS_NUMERIC, PLUS_DOUBLE, OPS_DOUBLE,
    PLUS_VCTR, VEC_ARITH, ARITH1, ARITH2_DOUBLE, ARITH2_NUMERIC,
    ARITH2_GENERIC
};

static void init_symbols(void)
{
    if (symbols_ready) return;
    const char *names[] = {
        "+", "+.dta_numeric", "Ops.dta_numeric", "+.dta_double",
        "Ops.dta_double", "+.vctrs_vctr", "vec_arith",
        "vec_arith.dta_numeric", "vec_arith.dta_numeric.double",
        "vec_arith.dta_numeric.numeric", "vec_arith.dta_numeric"
    };
    for (int i = 0; i < 11; ++i) sym[i] = Rf_install(names[i]);
    symbols_ready = 1;
}

static int absent(SEXP env, SEXP name)
{
    return R_GetBindingType(name, env) == R_BindingTypeUnbound;
}

static int same(SEXP env, SEXP name, SEXP expected)
{
    R_BindingType_t type = R_GetBindingType(name, env);
    if (type != R_BindingTypeValue && type != R_BindingTypeForced)
        return 0;
    return R_getVarEx(name, env, FALSE, R_NilValue) == expected;
}

SEXP C_fast_s3_guard(SEXP quosure, SEXP tables, SEXP live, SEXP namespaces)
{
    /* The exact abs(-3) branch feeds abs a bare numeric scalar. No Ops or
       vec_arith method can run there; the caller's abs/- bindings are checked
       separately, and the exact syntax is certified by the transaction. */
    SEXP expression = TYPEOF(quosure) == LANGSXP ? CADR(quosure) : R_NilValue;
    if (TYPEOF(expression) == LANGSXP && CAR(expression) == Rf_install("abs"))
        return Rf_ScalarLogical(TRUE);
    init_symbols();
    SEXP caller = Rf_getAttrib(quosure, Rf_install(".Environment"));
    if (TYPEOF(caller) != ENVSXP || TYPEOF(tables) != VECSXP ||
        XLENGTH(tables) != 3 || TYPEOF(live) != VECSXP ||
        XLENGTH(live) != 7 || TYPEOF(namespaces) != VECSXP ||
        XLENGTH(namespaces) != 2)
        Rf_error("bad scratch guard arguments");
    SEXP base_table = VECTOR_ELT(tables, 0);
    SEXP vctrs_table = VECTOR_ELT(tables, 1);
    SEXP dta_table = VECTOR_ELT(tables, 2);
    SEXP vns = VECTOR_ELT(namespaces, 0);
    SEXP dtans = VECTOR_ELT(namespaces, 1);
    if (TYPEOF(base_table) != ENVSXP || TYPEOF(vctrs_table) != ENVSXP ||
        TYPEOF(dta_table) != ENVSXP || TYPEOF(vns) != ENVSXP ||
        TYPEOF(dtans) != ENVSXP)
        Rf_error("bad scratch guard environments");

    /* Any caller-local binding can be active, delayed, or a replacement. */
    SEXP env = caller;
    for (;;) {
        for (int i = PLUS; i <= PLUS_VCTR; ++i)
            if (!absent(env, sym[i])) return Rf_ScalarLogical(FALSE);
        if (env == R_GlobalEnv) break;
        if (env == R_BaseEnv || env == R_EmptyEnv)
            return Rf_ScalarLogical(FALSE);
        env = R_ParentEnv(env);
    }

    /* Ordinary function-position lookup of `+` continues through attached
       environments, even though R_LookupMethod jumps from global to base. */
    env = R_ParentEnv(R_GlobalEnv);
    while (env != R_BaseEnv) {
        if (env == R_EmptyEnv || !absent(env, sym[PLUS]))
            return Rf_ScalarLogical(FALSE);
        env = R_ParentEnv(env);
    }
    if (!same(R_BaseEnv, sym[PLUS], VECTOR_ELT(live, 6)))
        return Rf_ScalarLogical(FALSE);

    /* DispatchGroup and NextMethod: first matching signature wins. */
    if (!absent(base_table, sym[PLUS_NUMERIC]) ||
        !absent(R_BaseEnv, sym[PLUS_NUMERIC]) ||
        !same(base_table, sym[OPS_NUMERIC], VECTOR_ELT(live, 0)) ||
        !absent(base_table, sym[PLUS_DOUBLE]) ||
        !absent(R_BaseEnv, sym[PLUS_DOUBLE]) ||
        !absent(base_table, sym[OPS_DOUBLE]) ||
        !absent(R_BaseEnv, sym[OPS_DOUBLE]) ||
        !same(base_table, sym[PLUS_VCTR], VECTOR_ELT(live, 1)))
        return Rf_ScalarLogical(FALSE);

    /* Actual public wrappers and generics that establish inner call frames. */
    if (!same(dtans, sym[OPS_NUMERIC], VECTOR_ELT(live, 0)) ||
        !same(vns, sym[PLUS_VCTR], VECTOR_ELT(live, 1)) ||
        !same(vns, sym[VEC_ARITH], VECTOR_ELT(live, 2)) ||
        !same(dtans, sym[ARITH1], VECTOR_ELT(live, 3)) ||
        !same(dtans, sym[ARITH2_NUMERIC], VECTOR_ELT(live, 4)) ||
        !same(dtans, sym[ARITH2_GENERIC], VECTOR_ELT(live, 5)))
        return Rf_ScalarLogical(FALSE);

    /* Two UseMethod stages: first vec_arith.dta_numeric, then bare-double
       before numeric. The table entries are current, not cached values. */
    if (!same(vctrs_table, sym[ARITH1], VECTOR_ELT(live, 3)) ||
        !absent(dta_table, sym[ARITH2_DOUBLE]) ||
        !same(dta_table, sym[ARITH2_NUMERIC], VECTOR_ELT(live, 4)))
        return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(TRUE);
}
