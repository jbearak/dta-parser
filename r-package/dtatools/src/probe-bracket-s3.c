#include <R.h>
#include <Rinternals.h>
#include <stdio.h>

/* R 4.6.1 method guard. The named S3 table is part of the qualified runtime. */
static SEXP sym[17];
static int symbols_ready = 0;
static int guard_debug_stage = 0;
static int guard_debug_type = 0, guard_debug_equal = 0;
static SEXP guard_debug_expected = NULL, guard_debug_current = NULL;

enum {
    PLUS, PLUS_NUMERIC, OPS_NUMERIC, PLUS_DOUBLE, OPS_DOUBLE,
    PLUS_VCTR, VEC_ARITH, ARITH1, ARITH2_DOUBLE, ARITH2_NUMERIC,
    ARITH2_GENERIC, PROXY_DOUBLE, PROXY_NUMERIC,
    ANY_DUPLICATED_DEFAULT, AS_LIST_DEFAULT, UNIQUE_DEFAULT,
    NAMES_SET_VCTR
};

static void init_symbols(void)
{
    if (symbols_ready) return;
    const char *names[] = {
        "+", "+.dta_numeric", "Ops.dta_numeric", "+.dta_double",
        "Ops.dta_double", "+.vctrs_vctr", "vec_arith",
        "vec_arith.dta_numeric", "vec_arith.dta_numeric.double",
        "vec_arith.dta_numeric.numeric", "vec_arith.dta_numeric",
        "vec_proxy.dta_double", "vec_proxy.dta_numeric",
        "anyDuplicated.default", "as.list.default", "unique.default",
        "names<-.vctrs_vctr"
    };
    for (int i = 0; i < 17; ++i) sym[i] = Rf_install(names[i]);
    symbols_ready = 1;
}

static int absent(SEXP env, SEXP name)
{
    /* Object-table binding inspection can call the database's getter. */
    return TYPEOF(env) == ENVSXP && !Rf_isObject(env) && !Rf_isS4(env) &&
        R_GetBindingType(name, env) == R_BindingTypeUnbound;
}

static int same(SEXP env, SEXP name, SEXP expected)
{
    R_BindingType_t type = R_GetBindingType(name, env);
    if (type != R_BindingTypeValue && type != R_BindingTypeForced)
        return 0;
    return R_getVarEx(name, env, FALSE, R_NilValue) == expected;
}

int C_bracket_s3_guard_raw(SEXP caller, SEXP tables, SEXP live, SEXP namespaces)
{
    guard_debug_stage = 1;
    if (!symbols_ready) return 0;
    if (TYPEOF(caller) != ENVSXP || TYPEOF(tables) != VECSXP ||
        XLENGTH(tables) != 3 || TYPEOF(live) != VECSXP ||
        XLENGTH(live) != 12 || TYPEOF(namespaces) != VECSXP ||
        XLENGTH(namespaces) != 2)
        return 0;
    SEXP base_table = VECTOR_ELT(tables, 0);
    SEXP vctrs_table = VECTOR_ELT(tables, 1);
    SEXP dta_table = VECTOR_ELT(tables, 2);
    SEXP vns = VECTOR_ELT(namespaces, 0);
    SEXP dtans = VECTOR_ELT(namespaces, 1);
    if (TYPEOF(base_table) != ENVSXP || TYPEOF(vctrs_table) != ENVSXP ||
        TYPEOF(dta_table) != ENVSXP || TYPEOF(vns) != ENVSXP ||
        TYPEOF(dtans) != ENVSXP)
        return 0;

    /* Any caller-local binding can be active, delayed, or a replacement. */
    guard_debug_stage = 2;
    SEXP env = caller;
    for (;;) {
        for (int i = PLUS; i <= PLUS_VCTR; ++i)
            if (!absent(env, sym[i])) return 0;
        if (!absent(env, sym[PROXY_DOUBLE]) ||
            !absent(env, sym[PROXY_NUMERIC])) return 0;
        for (int i = ANY_DUPLICATED_DEFAULT; i <= NAMES_SET_VCTR; ++i)
            if (!absent(env, sym[i])) return 0;
        if (env == R_GlobalEnv) break;
        if (env == R_BaseEnv || env == R_EmptyEnv)
            return 0;
        env = R_ParentEnv(env);
    }

    /* Ordinary function-position lookup of `+` continues through attached
       environments, even though R_LookupMethod jumps from global to base. */
    guard_debug_stage = 3;
    env = R_ParentEnv(R_GlobalEnv);
    while (env != R_BaseEnv) {
        if (env == R_EmptyEnv || !absent(env, sym[PLUS]))
            return 0;
        env = R_ParentEnv(env);
    }
    if (!same(R_BaseEnv, sym[PLUS], VECTOR_ELT(live, 6)))
        return 0;

    /* DispatchGroup and NextMethod: first matching signature wins. */
    guard_debug_stage = 4;
    guard_debug_stage = 41;
    if (!absent(base_table, sym[PLUS_NUMERIC])) return 0;
    guard_debug_stage = 42;
    if (!absent(R_BaseEnv, sym[PLUS_NUMERIC])) return 0;
    guard_debug_stage = 43;
    if (!same(base_table, sym[OPS_NUMERIC], VECTOR_ELT(live, 0))) {
        guard_debug_type = (int) R_GetBindingType(sym[OPS_NUMERIC], base_table);
        guard_debug_expected = VECTOR_ELT(live, 0);
        guard_debug_current = R_getVarEx(sym[OPS_NUMERIC], base_table,
                                        FALSE, R_NilValue);
        guard_debug_equal = guard_debug_current == guard_debug_expected;
        return 0;
    }
    guard_debug_stage = 44;
    if (!absent(base_table, sym[PLUS_DOUBLE])) return 0;
    guard_debug_stage = 45;
    if (!absent(R_BaseEnv, sym[PLUS_DOUBLE])) return 0;
    guard_debug_stage = 46;
    if (!absent(base_table, sym[OPS_DOUBLE])) return 0;
    guard_debug_stage = 47;
    if (!absent(R_BaseEnv, sym[OPS_DOUBLE])) return 0;
    guard_debug_stage = 48;
    if (!same(base_table, sym[PLUS_VCTR], VECTOR_ELT(live, 1))) return 0;

    /* Actual public wrappers and generics that establish inner call frames. */
    guard_debug_stage = 5;
    if (!same(dtans, sym[OPS_NUMERIC], VECTOR_ELT(live, 0)) ||
        !same(vns, sym[PLUS_VCTR], VECTOR_ELT(live, 1)) ||
        !same(vns, sym[VEC_ARITH], VECTOR_ELT(live, 2)) ||
        !same(dtans, sym[ARITH1], VECTOR_ELT(live, 3)) ||
        !same(dtans, sym[ARITH2_NUMERIC], VECTOR_ELT(live, 4)) ||
        !same(dtans, sym[ARITH2_GENERIC], VECTOR_ELT(live, 5)))
        return 0;

    /* Two UseMethod stages: first vec_arith.dta_numeric, then bare-double
       before numeric. The table entries are current, not cached values. */
    guard_debug_stage = 6;
    if (!same(vctrs_table, sym[ARITH1], VECTOR_ELT(live, 3)) ||
        !absent(dta_table, sym[ARITH2_DOUBLE]) ||
        !same(dta_table, sym[ARITH2_NUMERIC], VECTOR_ELT(live, 4)))
        return 0;
    if (!absent(vctrs_table, sym[PROXY_DOUBLE]) ||
        !absent(dta_table, sym[PROXY_DOUBLE]) ||
        !same(vctrs_table, sym[PROXY_NUMERIC], VECTOR_ELT(live, 7)) ||
        !same(dtans, sym[PROXY_NUMERIC], VECTOR_ELT(live, 7)) ||
        !same(base_table, sym[ANY_DUPLICATED_DEFAULT], VECTOR_ELT(live, 8)) ||
        !same(base_table, sym[AS_LIST_DEFAULT], VECTOR_ELT(live, 9)) ||
        !same(base_table, sym[UNIQUE_DEFAULT], VECTOR_ELT(live, 10)) ||
        !same(base_table, sym[NAMES_SET_VCTR], VECTOR_ELT(live, 11)))
        return 0;
    guard_debug_stage = 7;
    return 1;
}

SEXP C_bracket_s3_init(SEXP ignored) {
    (void) ignored;
    init_symbols();
    return Rf_ScalarLogical(TRUE);
}

SEXP C_bracket_s3_guard(SEXP caller, SEXP tables, SEXP live, SEXP namespaces) {
    return Rf_ScalarLogical(C_bracket_s3_guard_raw(caller, tables, live, namespaces));
}
