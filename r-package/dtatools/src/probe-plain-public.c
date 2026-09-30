/* Additional public dependencies reached by canonical ordinary doubles. */
#include "dtatools-internal.h"
#include <float.h>
extern int dtatools_probe_gen_extra_guard_plain(SEXP state);
extern int dtatools_probe_public_debugged(SEXP fn);
static SEXP plain_public_state = NULL;
typedef struct {
    SEXP env, symbol, function, body, formals, closure_env, attributes;
} plain_public_entry;
static plain_public_entry *plain_entries = NULL;
static R_xlen_t plain_entry_count = 0;
typedef struct { SEXP symbol, value; } plain_primitive_entry;
static plain_primitive_entry *plain_primitives = NULL;
static R_xlen_t plain_primitive_count = 0;

void dtatools_probe_plain_public_release(void) {
    if (plain_public_state != NULL) R_ReleaseObject(plain_public_state);
    if (plain_entries != NULL) R_Free(plain_entries);
    if (plain_primitives != NULL) R_Free(plain_primitives);
    plain_public_state = NULL;
    plain_entries = NULL;
    plain_primitives = NULL;
    plain_entry_count = plain_primitive_count = 0;
}

typedef struct { SEXP expected; R_xlen_t index; } plain_attribute_cursor;
static SEXP plain_attribute_same(SEXP tag, SEXP value, void *context) {
    plain_attribute_cursor *cursor = context;
    if (cursor->index + 1 >= XLENGTH(cursor->expected) ||
        VECTOR_ELT(cursor->expected, cursor->index) != tag ||
        VECTOR_ELT(cursor->expected, cursor->index + 1) != value)
        return R_NilValue;
    cursor->index += 2;
    return NULL;
}

static int plain_double_limit_current(void) {
    SEXP symbol = Rf_install(".Machine");
    R_BindingType_t type = R_GetBindingType(symbol, R_BaseEnv);
    if (type != R_BindingTypeValue && type != R_BindingTypeForced) return 0;
    SEXP machine = R_getVar(symbol, R_BaseEnv, FALSE);
    if (TYPEOF(machine) != VECSXP || ALTREP(machine) || Rf_isObject(machine) ||
        Rf_isS4(machine) || XLENGTH(machine) > 128) return 0;
    SEXP names = Rf_getAttrib(machine, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || ALTREP(names) || XLENGTH(names) != XLENGTH(machine)) return 0;
    for (R_xlen_t i = 0; i < XLENGTH(names); ++i) {
        if (strcmp(CHAR(STRING_ELT(names, i)), "double.xmax")) continue;
        SEXP value = VECTOR_ELT(machine, i);
        return TYPEOF(value) == REALSXP && !ALTREP(value) && !ANY_ATTRIB(value) &&
            XLENGTH(value) == 1 && REAL(value)[0] == DBL_MAX;
    }
    return 0;
}

int dtatools_probe_plain_public_guard(void) {
    if (plain_public_state == NULL || plain_entries == NULL ||
        !plain_double_limit_current()) return 0;
    for (R_xlen_t i = 0; i < plain_entry_count; ++i) {
        const plain_public_entry *entry = plain_entries + i;
        R_BindingType_t type = R_GetBindingType(entry->symbol, entry->env);
        if (type != R_BindingTypeValue && type != R_BindingTypeForced) return 0;
        SEXP current = R_getVar(entry->symbol, entry->env, FALSE);
        if (current != entry->function || R_ClosureBody(current) != entry->body ||
            R_ClosureFormals(current) != entry->formals ||
            R_ClosureEnv(current) != entry->closure_env ||
            dtatools_probe_public_debugged(current) != 0) return 0;
        plain_attribute_cursor cursor = {entry->attributes, 0};
        if (R_mapAttrib(current, plain_attribute_same, &cursor) != NULL ||
            cursor.index != XLENGTH(entry->attributes)) return 0;
    }
    for (R_xlen_t i = 0; i < plain_primitive_count; ++i) {
        const plain_primitive_entry *entry = plain_primitives + i;
        R_BindingType_t type = R_GetBindingType(entry->symbol, R_BaseEnv);
        if ((type != R_BindingTypeValue && type != R_BindingTypeForced) ||
            R_getVar(entry->symbol, R_BaseEnv, FALSE) != entry->value) return 0;
    }
    return 1;
}

SEXP C_dtatools_probe_plain_public_pin(SEXP state) {
    if (plain_public_state != NULL || TYPEOF(state) != ENVSXP ||
        !dtatools_probe_gen_extra_guard_plain(state)) return Rf_ScalarLogical(FALSE);
    SEXP envs = R_getVar(Rf_install("envs"), state, FALSE);
    SEXP labels = R_getVar(Rf_install("labels"), state, FALSE);
    SEXP live = R_getVar(Rf_install("live"), state, FALSE);
    SEXP bodies = R_getVar(Rf_install("bodies"), state, FALSE);
    SEXP environments = R_getVar(Rf_install("environments"), state, FALSE);
    SEXP attributes = R_getVar(Rf_install("attributes"), state, FALSE);
    SEXP names = R_getVarEx(Rf_install("primitive_names"), state, FALSE, R_NilValue);
    SEXP values = R_getVarEx(Rf_install("primitive_values"), state, FALSE, R_NilValue);
    if (TYPEOF(names) != STRSXP || TYPEOF(values) != VECSXP ||
        XLENGTH(names) != XLENGTH(values)) return Rf_ScalarLogical(FALSE);
    R_xlen_t count = XLENGTH(live);
    SEXP formals = PROTECT(Rf_allocVector(VECSXP, count));
    for (R_xlen_t i = 0; i < count; ++i)
        SET_VECTOR_ELT(formals, i, R_ClosureFormals(VECTOR_ELT(live, i)));
    Rf_defineVar(Rf_install("formals"), formals, state);
    if (!dtatools_probe_gen_extra_guard_plain(state)) {
        UNPROTECT(1); return Rf_ScalarLogical(FALSE);
    }
    plain_entries = R_Calloc(count, plain_public_entry);
    plain_primitives = R_Calloc(XLENGTH(names), plain_primitive_entry);
    for (R_xlen_t i = 0; i < count; ++i) {
        plain_public_entry *entry = plain_entries + i;
        entry->env = VECTOR_ELT(envs, i);
        entry->symbol = Rf_installChar(STRING_ELT(labels, i));
        entry->function = VECTOR_ELT(live, i);
        entry->body = VECTOR_ELT(bodies, i);
        entry->formals = VECTOR_ELT(formals, i);
        entry->closure_env = VECTOR_ELT(environments, i);
        entry->attributes = VECTOR_ELT(attributes, i);
    }
    for (R_xlen_t i = 0; i < XLENGTH(names); ++i) {
        plain_primitives[i].symbol = Rf_installChar(STRING_ELT(names, i));
        plain_primitives[i].value = VECTOR_ELT(values, i);
    }
    R_PreserveObject(state);
    plain_public_state = state;
    plain_entry_count = count;
    plain_primitive_count = XLENGTH(names);
    UNPROTECT(1);
    return Rf_ScalarLogical(dtatools_probe_plain_public_guard());
}
