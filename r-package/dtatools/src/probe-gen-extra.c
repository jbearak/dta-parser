/* Gen-only public closures. The existing 58-root repl guard remains intact. */
#include <R.h>
#include <Rinternals.h>

extern int dtatools_probe_fresh_formals(SEXP live, SEXP frozen);
extern int dtatools_probe_public_debugged(SEXP fn);

static SEXP field(SEXP state, const char *name) {
    if (TYPEOF(state) != ENVSXP) return R_NilValue;
    SEXP symbol = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(symbol, state);
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(symbol, state, FALSE, R_NilValue);
}

typedef struct { int n; SEXP tags[4], values[4]; } gen_attrs;
static SEXP collect_gen_attr(SEXP tag, SEXP value, void *context) {
    gen_attrs *out = context;
    if (out->n >= 4 || TYPEOF(tag) != SYMSXP || ANY_ATTRIB(tag))
        return R_NilValue;
    out->tags[out->n] = tag;
    out->values[out->n++] = value;
    return NULL;
}
static SEXP capture_gen_attrs(SEXP fn) {
    gen_attrs attrs = {.n = 0};
    if (R_mapAttrib(fn, collect_gen_attr, &attrs) != NULL)
        return R_NilValue;
    SEXP out = PROTECT(Rf_allocVector(VECSXP, attrs.n * 2));
    for (int i = 0; i < attrs.n; ++i) {
        SET_VECTOR_ELT(out, i * 2, attrs.tags[i]);
        SET_VECTOR_ELT(out, i * 2 + 1, attrs.values[i]);
    }
    UNPROTECT(1);
    return out;
}
static int same_gen_attrs(SEXP fn, SEXP captured) {
    gen_attrs attrs = {.n = 0};
    if (TYPEOF(captured) != VECSXP ||
        R_mapAttrib(fn, collect_gen_attr, &attrs) != NULL ||
        XLENGTH(captured) != attrs.n * 2) return 0;
    for (int i = 0; i < attrs.n; ++i)
        if (VECTOR_ELT(captured, i * 2) != attrs.tags[i] ||
            VECTOR_ELT(captured, i * 2 + 1) != attrs.values[i])
            return 0;
    return 1;
}

static int fields(SEXP state, SEXP *envs, SEXP *labels, SEXP *frozen,
                  SEXP *live, SEXP *bodies, SEXP *environments,
                  SEXP *attributes) {
    *envs = field(state, "envs");
    *labels = field(state, "labels");
    *frozen = field(state, "frozen");
    *live = field(state, "live");
    *bodies = field(state, "bodies");
    *environments = field(state, "environments");
    *attributes = field(state, "attributes");
    R_xlen_t n = TYPEOF(*envs) == VECSXP ? XLENGTH(*envs) : 0;
    return n > 0 && n <= 128 && TYPEOF(*labels) == STRSXP &&
        TYPEOF(*frozen) == VECSXP && TYPEOF(*live) == VECSXP &&
        XLENGTH(*labels) == n &&
        XLENGTH(*frozen) == n && XLENGTH(*live) == n &&
        (*bodies == R_NilValue ||
         (TYPEOF(*bodies) == VECSXP && XLENGTH(*bodies) == n)) &&
        (*environments == R_NilValue ||
         (TYPEOF(*environments) == VECSXP && XLENGTH(*environments) == n)) &&
        (*attributes == R_NilValue ||
         (TYPEOF(*attributes) == VECSXP && XLENGTH(*attributes) == n));
}

SEXP C_dtatools_probe_gen_extra_capture(SEXP state) {
    SEXP envs, labels, frozen, live, prior_bodies, prior_envs, prior_attrs;
    if (!fields(state, &envs, &labels, &frozen, &live,
                &prior_bodies, &prior_envs, &prior_attrs) ||
        prior_bodies != R_NilValue || prior_envs != R_NilValue ||
        prior_attrs != R_NilValue)
        return Rf_ScalarLogical(FALSE);
    R_xlen_t n = XLENGTH(envs);
    SEXP bodies = PROTECT(Rf_allocVector(VECSXP, n));
    SEXP environments = PROTECT(Rf_allocVector(VECSXP, n));
    SEXP attributes = PROTECT(Rf_allocVector(VECSXP, n));
    for (R_xlen_t i = 0; i < n; ++i) {
        SEXP env = VECTOR_ELT(envs, i), fn = VECTOR_ELT(live, i);
        SEXP expected = VECTOR_ELT(frozen, i);
        if (TYPEOF(env) != ENVSXP || TYPEOF(fn) != CLOSXP ||
            TYPEOF(expected) != CLOSXP ||
            dtatools_probe_public_debugged(fn) != 0 ||
            !dtatools_probe_fresh_formals(fn, expected)) {
            UNPROTECT(3);
            return Rf_ScalarLogical(FALSE);
        }
        SEXP symbol = Rf_installChar(STRING_ELT(labels, i));
        R_BindingType_t kind = R_GetBindingType(symbol, env);
        if ((kind != R_BindingTypeValue && kind != R_BindingTypeForced) ||
            R_getVarEx(symbol, env, FALSE, R_NilValue) != fn) {
            UNPROTECT(3);
            return Rf_ScalarLogical(FALSE);
        }
        SET_VECTOR_ELT(bodies, i, R_ClosureBody(fn));
        SET_VECTOR_ELT(environments, i, R_ClosureEnv(fn));
        SEXP captured = capture_gen_attrs(fn);
        if (captured == R_NilValue) {
            UNPROTECT(3);
            return Rf_ScalarLogical(FALSE);
        }
        SET_VECTOR_ELT(attributes, i, captured);
    }
    Rf_defineVar(Rf_install("bodies"), bodies, state);
    Rf_defineVar(Rf_install("environments"), environments, state);
    Rf_defineVar(Rf_install("attributes"), attributes, state);
    UNPROTECT(3);
    return Rf_ScalarLogical(TRUE);
}

int dtatools_probe_gen_extra_guard_plain(SEXP state) {
    SEXP envs, labels, frozen, live, bodies, environments, attributes;
    if (!fields(state, &envs, &labels, &frozen, &live,
                &bodies, &environments, &attributes) ||
        bodies == R_NilValue || environments == R_NilValue ||
        attributes == R_NilValue)
        return 0;
    for (R_xlen_t i = 0; i < XLENGTH(envs); ++i) {
        SEXP env = VECTOR_ELT(envs, i);
        if (TYPEOF(env) != ENVSXP) return 0;
        SEXP symbol = Rf_installChar(STRING_ELT(labels, i));
        R_BindingType_t kind = R_GetBindingType(symbol, env);
        if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
            return 0;
        SEXP fn = R_getVarEx(symbol, env, FALSE, R_NilValue);
        if (TYPEOF(fn) != CLOSXP || fn != VECTOR_ELT(live, i) ||
            R_ClosureBody(fn) != VECTOR_ELT(bodies, i) ||
            R_ClosureEnv(fn) != VECTOR_ELT(environments, i) ||
            !same_gen_attrs(fn, VECTOR_ELT(attributes, i)) ||
            dtatools_probe_public_debugged(fn) != 0 ||
            !dtatools_probe_fresh_formals(fn, VECTOR_ELT(frozen, i)))
            return 0;
    }
    return 1;
}
