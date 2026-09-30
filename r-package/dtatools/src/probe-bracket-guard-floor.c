#include <R.h>
#include <Rinternals.h>
#include "probe-bracket-live-cache.h"

extern int C_snap_check_raw(SEXP ext);
extern int C_snap_check_roots_raw(SEXP ext);
extern int C_bracket_s3_guard_raw(SEXP caller, SEXP tables, SEXP live,
                               SEXP namespaces);
extern int bracket_source_unshadowed(SEXP caller);

static SEXP profile_field(SEXP profile, const char *name) {
    SEXP symbol = Rf_install(name);
    R_BindingType_t type = R_GetBindingType(symbol, profile);
    if (type != R_BindingTypeValue && type != R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(symbol, profile, FALSE, R_NilValue);
}

static int table_methods_plain(SEXP caller, SEXP base_table,
                               SEXP expected_length) {
    if (TYPEOF(base_table) != ENVSXP ||
        TYPEOF(expected_length) != CLOSXP) return 0;
    const char *names[] = {
        "names.dibble", "names.dtatools_ref_data", "names.tbl_df",
        "names.tbl", "names.data.frame", "length.dibble",
        "length.dtatools_ref_data", "length.tbl_df", "length.tbl",
        "length.data.frame"
    };
    for (int i = 0; i < 10; i++) {
        SEXP symbol = Rf_install(names[i]);
        SEXP expected = i == 5 ? expected_length : R_NilValue;
        for (SEXP env = caller; env != R_BaseEnv && env != R_EmptyEnv;
             env = R_ParentEnv(env)) {
            if (TYPEOF(env) != ENVSXP || Rf_isObject(env) || Rf_isS4(env))
                return 0;
            R_BindingType_t type = R_GetBindingType(symbol, env);
            if (type == R_BindingTypeUnbound) continue;
            if (expected == R_NilValue ||
                (type != R_BindingTypeValue &&
                 type != R_BindingTypeForced) ||
                R_getVarEx(symbol, env, FALSE, R_NilValue) != expected)
                return 0;
        }
        SEXP locations[] = {R_BaseEnv, base_table};
        for (int j = 0; j < 2; j++) {
            R_BindingType_t type = R_GetBindingType(symbol, locations[j]);
            if (expected == R_NilValue) {
                if (type != R_BindingTypeUnbound) return 0;
            } else if (j == 1) {
                if ((type != R_BindingTypeValue &&
                     type != R_BindingTypeForced) ||
                    R_getVarEx(symbol, locations[j], FALSE,
                               R_NilValue) != expected) return 0;
            } else if (type != R_BindingTypeUnbound &&
                       ((type != R_BindingTypeValue &&
                         type != R_BindingTypeForced) ||
                        R_getVarEx(symbol, locations[j], FALSE,
                                   R_NilValue) != expected)) return 0;
        }
    }
    return 1;
}

int C_dtatools_probe_bracket_public_guard_raw(SEXP profile, SEXP caller) {
    if (TYPEOF(profile) != ENVSXP || TYPEOF(caller) != ENVSXP ||
        !bracket_source_unshadowed(caller))
        return 0;
    SEXP snapshots = profile_field(profile, "snapshots");
    SEXP tables = profile_field(profile, "tables");
    SEXP live = profile_field(profile, "live");
    SEXP namespaces = profile_field(profile, "namespaces");
    SEXP primitives = profile_field(profile, "primitives");
    SEXP length_method = profile_field(profile, "length_method");
    if (TYPEOF(snapshots) != VECSXP || XLENGTH(snapshots) != 4 ||
        TYPEOF(primitives) != VECSXP || XLENGTH(primitives) < 18 ||
        XLENGTH(primitives) > 128)
        return 0;
    for (R_xlen_t i = 0; i < XLENGTH(snapshots); i++)
        if (!C_snap_check_raw(VECTOR_ELT(snapshots, i))) return 0;
    SEXP primitive_names = Rf_getAttrib(primitives, R_NamesSymbol);
    if (TYPEOF(primitive_names) != STRSXP ||
        XLENGTH(primitive_names) != XLENGTH(primitives)) return 0;
    for (R_xlen_t i = 0; i < XLENGTH(primitives); i++) {
        SEXP symbol = Rf_installChar(STRING_ELT(primitive_names, i));
        R_BindingType_t type = R_GetBindingType(symbol, R_BaseEnv);
        if ((type != R_BindingTypeValue && type != R_BindingTypeForced) ||
            R_getVarEx(symbol, R_BaseEnv, FALSE, R_NilValue) !=
                VECTOR_ELT(primitives, i)) return 0;
    }
    return C_bracket_s3_guard_raw(caller, tables, live, namespaces) &&
        table_methods_plain(caller, VECTOR_ELT(tables, 0), length_method);
}

int C_dtatools_probe_bracket_public_live_raw(SEXP profile, SEXP caller) {
    dtatools_bracket_live_cache cache;
    return dtatools_probe_bracket_live_cache_init(profile, &cache) &&
        dtatools_probe_bracket_live_cache_check(&cache, caller);
}

int dtatools_probe_bracket_live_cache_init(SEXP profile,
    dtatools_bracket_live_cache *cache) {
    if (TYPEOF(profile) != ENVSXP || cache == NULL) return 0;
    cache->snapshots = profile_field(profile, "snapshots");
    cache->tables = profile_field(profile, "tables");
    cache->live = profile_field(profile, "live");
    cache->namespaces = profile_field(profile, "namespaces");
    cache->primitives = profile_field(profile, "primitives");
    cache->length_method = profile_field(profile, "length_method");
    return 1;
}

int dtatools_probe_bracket_live_cache_check(
    const dtatools_bracket_live_cache *cache, SEXP caller) {
    if (cache == NULL || TYPEOF(caller) != ENVSXP ||
        !bracket_source_unshadowed(caller)) return 0;
    SEXP snapshots = cache->snapshots;
    SEXP tables = cache->tables;
    SEXP live = cache->live;
    SEXP namespaces = cache->namespaces;
    SEXP primitives = cache->primitives;
    SEXP length_method = cache->length_method;
    if (TYPEOF(snapshots) != VECSXP || XLENGTH(snapshots) != 4 ||
        TYPEOF(primitives) != VECSXP || XLENGTH(primitives) < 18 ||
        XLENGTH(primitives) > 128) return 0;
    for (R_xlen_t i = 0; i < XLENGTH(snapshots); i++)
        if (!C_snap_check_roots_raw(VECTOR_ELT(snapshots, i))) return 0;
    SEXP primitive_names = Rf_getAttrib(primitives, R_NamesSymbol);
    if (TYPEOF(primitive_names) != STRSXP ||
        XLENGTH(primitive_names) != XLENGTH(primitives)) return 0;
    for (R_xlen_t i = 0; i < XLENGTH(primitives); i++) {
        SEXP symbol = Rf_installChar(STRING_ELT(primitive_names, i));
        R_BindingType_t type = R_GetBindingType(symbol, R_BaseEnv);
        if ((type != R_BindingTypeValue && type != R_BindingTypeForced) ||
            R_getVarEx(symbol, R_BaseEnv, FALSE, R_NilValue) !=
                VECTOR_ELT(primitives, i)) return 0;
    }
    return C_bracket_s3_guard_raw(caller, tables, live, namespaces) &&
        table_methods_plain(caller, VECTOR_ELT(tables, 0), length_method);
}

SEXP C_dtatools_probe_bracket_public_live(SEXP profile, SEXP assignments) {
    SEXP first = TYPEOF(assignments) == VECSXP && XLENGTH(assignments) > 0 ?
        VECTOR_ELT(assignments, 0) : R_NilValue;
    SEXP quo = TYPEOF(first) == VECSXP && XLENGTH(first) == 2 ?
        VECTOR_ELT(first, 1) : R_NilValue;
    SEXP caller = TYPEOF(quo) == LANGSXP ?
        Rf_getAttrib(quo, Rf_install(".Environment")) : R_NilValue;
    return Rf_ScalarLogical(C_dtatools_probe_bracket_public_live_raw(
        profile, caller));
}

SEXP C_dtatools_probe_bracket_public_live_caller(SEXP profile, SEXP caller) {
    return Rf_ScalarLogical(C_dtatools_probe_bracket_public_live_raw(
        profile, caller));
}

SEXP C_dtatools_probe_bracket_public_guard(SEXP profile,
                                           SEXP assignments) {
    if (TYPEOF(assignments) != VECSXP || XLENGTH(assignments) != 5)
        return Rf_ScalarLogical(FALSE);
    SEXP assignment = VECTOR_ELT(assignments, 0);
    if (TYPEOF(assignment) != VECSXP || XLENGTH(assignment) != 2)
        return Rf_ScalarLogical(FALSE);
    SEXP quo = VECTOR_ELT(assignment, 1);
    if (TYPEOF(quo) != LANGSXP)
        return Rf_ScalarLogical(FALSE);
    SEXP caller = Rf_getAttrib(quo, Rf_install(".Environment"));
    return Rf_ScalarLogical(C_dtatools_probe_bracket_public_guard_raw(
        profile, caller));
}

/* Cost-only screen; the snapshots still require independent cold source
   qualification before they can authorize skipped public calls. */
