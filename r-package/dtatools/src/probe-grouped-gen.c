/* Guarded native route for grouped source-plus-constant generation. */
#include "dtatools-internal.h"
#include <float.h>
#include <string.h>

extern int dtatools_probe_gen_public_guard_plain(SEXP frame, SEXP base,
    SEXP public_state, SEXP extra_state, SEXP wrapper_state,
    SEXP rlang_state, SEXP s3_state, int grouped);
extern int dtatools_probe_gen_parse_caller(SEXP frame, SEXP *source_symbol,
    SEXP *target_name, SEXP *caller, double *increment);
extern int dtatools_probe_gen_extra_guard_plain(SEXP state);
extern SEXP C_dtatools_append_mark_reference(SEXP data, SEXP name,
    SEXP column, SEXP state, SEXP classes);

static int grouped_mode = 1;
static int attempts = 0, produced = 0, published = 0;
static SEXP grouped_stage_hook = NULL;

static SEXP plain_value(SEXP env, SEXP name) {
    if (TYPEOF(env) != ENVSXP) return R_NilValue;
    R_BindingType_t kind = R_GetBindingType(name, env);
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(name, env, FALSE, R_NilValue);
}

static int no_grouped_method(SEXP caller, SEXP s3_state) {
    SEXP method = Rf_install("vec_proxy_equal.data.frame");
    for (SEXP env = caller;; env = R_ParentEnv(env)) {
        if (TYPEOF(env) != ENVSXP || Rf_isObject(env) || Rf_isS4(env))
            return 0;
        if (env == R_BaseEnv || env == R_EmptyEnv ||
            R_GetBindingType(method, env) != R_BindingTypeUnbound)
            return 0;
        if (env == R_GlobalEnv) break;
    }
    for (SEXP env = R_ParentEnv(R_GlobalEnv); env != R_BaseEnv;
         env = R_ParentEnv(env)) {
        if (TYPEOF(env) != ENVSXP || Rf_isObject(env) || Rf_isS4(env) ||
            env == R_EmptyEnv ||
            R_GetBindingType(method, env) != R_BindingTypeUnbound)
            return 0;
    }
    SEXP tables = plain_value(s3_state, Rf_install("tables"));
    SEXP namespaces = plain_value(s3_state, Rf_install("namespaces"));
    if (TYPEOF(tables) != VECSXP || XLENGTH(tables) != 3 ||
        TYPEOF(namespaces) != VECSXP || XLENGTH(namespaces) != 2)
        return 0;
    SEXP envs[] = { R_BaseEnv, VECTOR_ELT(tables, 0),
        VECTOR_ELT(tables, 1), VECTOR_ELT(tables, 2),
        VECTOR_ELT(namespaces, 0), VECTOR_ELT(namespaces, 1) };
    for (int i = 0; i < 6; ++i)
        if (TYPEOF(envs[i]) != ENVSXP ||
            R_GetBindingType(method, envs[i]) != R_BindingTypeUnbound)
            return 0;
    return 1;
}

static int grouped_public_guard(SEXP caller, SEXP grouped_state,
                                SEXP s3_state) {
    static const char *bindings[] = {
        "as.integer", "as.character", "is.symbol", "is.atomic",
        "names", "seq_len"
    };
    static const char *fields[] = {
        "primitive_as_integer", "primitive_as_character",
        "primitive_is_symbol", "primitive_is_atomic",
        "primitive_names", "primitive_seq_len"
    };
    for (int i = 0; i < 6; ++i) {
        SEXP expected = plain_value(grouped_state, Rf_install(fields[i]));
        if (TYPEOF(expected) != BUILTINSXP ||
            plain_value(R_BaseEnv, Rf_install(bindings[i])) != expected)
            return 0;
    }
    if (!dtatools_probe_gen_extra_guard_plain(grouped_state) ||
        !no_grouped_method(caller, s3_state))
        return 0;
    return 1;
}

SEXP C_dtatools_probe_grouped_gen_after_stage(SEXP callback) {
    if (callback != R_NilValue && !Rf_isFunction(callback))
        Rf_error("grouped gen stage hook must be a function or NULL");
    if (grouped_stage_hook != NULL) R_ReleaseObject(grouped_stage_hook);
    grouped_stage_hook = callback == R_NilValue ? NULL : callback;
    if (grouped_stage_hook != NULL) R_PreserveObject(grouped_stage_hook);
    return Rf_ScalarLogical(TRUE);
}

static void run_grouped_stage_hook(void) {
    if (grouped_stage_hook == NULL) return;
    SEXP callback = PROTECT(grouped_stage_hook);
    grouped_stage_hook = NULL;
    R_ReleaseObject(callback);
    SEXP call = PROTECT(Rf_lang1(callback));
    Rf_eval(call, R_GlobalEnv);
    UNPROTECT(2);
}

SEXP C_dtatools_probe_grouped_gen_mode(SEXP value) {
    int next = Rf_asLogical(value);
    if (next == NA_LOGICAL) Rf_error("grouped gen mode must be TRUE or FALSE");
    int prior = grouped_mode;
    grouped_mode = next;
    return Rf_ScalarLogical(prior);
}

SEXP C_dtatools_probe_grouped_gen_stats(SEXP reset) {
    SEXP out = PROTECT(Rf_allocVector(INTSXP, 3));
    INTEGER(out)[0] = attempts;
    INTEGER(out)[1] = produced;
    INTEGER(out)[2] = published;
    if (Rf_asLogical(reset)) attempts = produced = published = 0;
    UNPROTECT(1);
    return out;
}

static int omitted(SEXP frame, const char *name) {
    SEXP sym = Rf_install(name);
    return R_GetBindingType(sym, frame) == R_BindingTypeDelayed &&
        R_DelayedBindingExpression(sym, frame) == R_NilValue &&
        R_DelayedBindingEnvironment(sym, frame) == frame;
}

static int ascii(SEXP name) {
    if (name == NA_STRING || Rf_getCharCE(name) == CE_BYTES) return 0;
    const unsigned char *p = (const unsigned char *) CHAR(name);
    for (; *p; ++p) if (*p > 127) return 0;
    return 1;
}

static int locations(SEXP names, SEXP source, SEXP key, SEXP target,
                     R_xlen_t *source_at, R_xlen_t *key_at) {
    if (!ascii(source) || !ascii(key) || !ascii(target)) return 0;
    *source_at = *key_at = -1;
    for (R_xlen_t i = 0; i < XLENGTH(names); ++i) {
        SEXP current = STRING_ELT(names, i);
        if (!ascii(current)) return 0;
        const char *name = CHAR(current);
        if (strcmp(name, CHAR(target)) == 0) return 0;
        if (strcmp(name, CHAR(source)) == 0) {
            if (*source_at >= 0) return 0;
            *source_at = i;
        }
        if (strcmp(name, CHAR(key)) == 0) {
            if (*key_at >= 0) return 0;
            *key_at = i;
        }
        for (R_xlen_t j = 0; j < i; ++j)
            if (strcmp(name, CHAR(STRING_ELT(names, j))) == 0) return 0;
    }
    return *source_at >= 0 && *key_at >= 0;
}

typedef struct { int n, class_seen, storage_seen; } attr_count;
static SEXP canonical_attr(SEXP tag, SEXP value, void *context) {
    attr_count *count = context;
    count->n++;
    if (tag == R_ClassSymbol) count->class_seen++;
    else if (tag == Rf_install("stata.storage")) count->storage_seen++;
    else return R_NilValue;
    return NULL;
}

static int canonical_column(SEXP column, R_xlen_t n, const char *kind,
                            int group_key) {
    if (TYPEOF(column) != REALSXP || Rf_isS4(column) || XLENGTH(column) != n ||
        (group_key ? !(R_altrep_inherits(column, dtatools_numeric_class) ||
                       R_altrep_inherits(column, dtatools_metadata_real_class))
                   : (!owned_real(column) ||
                      R_altrep_data2(column) != R_NilValue)))
        return 0;
    if (!group_key) {
        SEXP backing = owned_values(column);
        if (TYPEOF(backing) != REALSXP || ALTREP(backing) ||
            XLENGTH(backing) != n) return 0;
    }
    SEXP class = Rf_getAttrib(column, R_ClassSymbol);
    SEXP storage = Rf_getAttrib(column, Rf_install("stata.storage"));
    if (TYPEOF(class) != STRSXP || XLENGTH(class) != 4 ||
        strcmp(CHAR(STRING_ELT(class, 0)), "dta_numeric") ||
        strcmp(CHAR(STRING_ELT(class, 1)), kind) ||
        strcmp(CHAR(STRING_ELT(class, 2)), "vctrs_vctr") ||
        strcmp(CHAR(STRING_ELT(class, 3)), "double") ||
        TYPEOF(storage) != STRSXP || XLENGTH(storage) != 1 ||
        strcmp(CHAR(STRING_ELT(storage, 0)),
               strcmp(kind, "dta_long") == 0 ? "long" : "double"))
        return 0;
    attr_count count = {0, 0, 0};
    return R_mapAttrib(column, canonical_attr, &count) == NULL &&
        count.n == 2 && count.class_seen == 1 && count.storage_seen == 1;
}

typedef struct { int n; SEXP tags[16], values[16], roots; } table_attrs;
static SEXP collect_table_attr(SEXP tag, SEXP value, void *context) {
    table_attrs *attrs = context;
    if (attrs->n == 16) return R_NilValue;
    attrs->tags[attrs->n] = tag;
    attrs->values[attrs->n] = value;
    if (attrs->roots != R_NilValue)
        SET_VECTOR_ELT(attrs->roots, attrs->n, value);
    attrs->n++;
    return NULL;
}
static int snapshot_table_attrs(SEXP data, table_attrs *attrs, SEXP roots) {
    attrs->n = 0;
    attrs->roots = roots;
    return R_mapAttrib(data, collect_table_attr, attrs) == NULL;
}
static int same_table_attrs(SEXP data, const table_attrs *expected) {
    table_attrs current;
    if (!snapshot_table_attrs(data, &current, R_NilValue) ||
        current.n != expected->n)
        return 0;
    for (int i = 0; i < current.n; ++i)
        if (current.tags[i] != expected->tags[i] ||
            current.values[i] != expected->values[i]) return 0;
    return 1;
}

static int source_frame(SEXP frame, SEXP data, SEXP *source_symbol,
                        SEXP *target_name, SEXP *caller, double *increment,
                        SEXP *group_symbol) {
    if (R_getVarEx(Rf_install("data"), frame, FALSE, R_NilValue) != data ||
        !omitted(frame, "where") || !omitted(frame, "bysort"))
        return 0;
    SEXP by = Rf_install("by");
    if (R_GetBindingType(by, frame) != R_BindingTypeDelayed ||
        TYPEOF(R_DelayedBindingExpression(by, frame)) != SYMSXP)
        return 0;
    if (!dtatools_probe_gen_parse_caller(frame, source_symbol, target_name,
                                         caller, increment)) return 0;
    *group_symbol = R_DelayedBindingExpression(by, frame);
    return R_DelayedBindingEnvironment(by, frame) == *caller &&
        strncmp(CHAR(PRINTNAME(*group_symbol)), "..", 2) != 0 &&
        *group_symbol != Rf_install(".data") &&
        *group_symbol != Rf_install(".env") &&
        *group_symbol != Rf_install(".n") &&
        *group_symbol != Rf_install(".N");
}

SEXP C_dtatools_probe_grouped_gen(SEXP data, SEXP base_state,
    SEXP public_state, SEXP extra_state, SEXP wrapper_state,
    SEXP rlang_state, SEXP s3_state, SEXP grouped_state) {
    if (!grouped_mode) return Rf_ScalarLogical(FALSE);
    attempts++;
    SEXP frame = R_GetCurrentEnv();
    SEXP source, target, caller, group;
    double increment;
    if (!source_frame(frame, data, &source, &target, &caller, &increment,
                      &group) ||
        R_getVarEx(Rf_install("placement"), frame, FALSE, R_NilValue) != R_NilValue) {
        return Rf_ScalarLogical(FALSE);
    }
    SEXP type = Rf_GetOption1(Rf_install("dtatools.generate_type"));
    if (TYPEOF(type) != STRSXP || XLENGTH(type) != 1 ||
        strcmp(CHAR(STRING_ELT(type, 0)), "double")) {
        return Rf_ScalarLogical(FALSE);
    }
    if (TYPEOF(data) != VECSXP || !Rf_inherits(data, "dibble") ||
        Rf_inherits(data, "grouped_df") ||
        !dtatools_reference_state_valid_noalloc(data)) {
        return Rf_ScalarLogical(FALSE);
    }
    R_xlen_t width = XLENGTH(data);
    if (width < 2 || width > 2048) return Rf_ScalarLogical(FALSE);
    SEXP names = PROTECT(Rf_getAttrib(data, R_NamesSymbol));
    if (TYPEOF(names) != STRSXP || ALTREP(names) || XLENGTH(names) != width)
        { UNPROTECT(1); return Rf_ScalarLogical(FALSE); }
    R_xlen_t source_at, group_at;
    if (!locations(names, PRINTNAME(source), PRINTNAME(group), target,
                   &source_at, &group_at)) {
        UNPROTECT(1);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP x = PROTECT(VECTOR_ELT(data, source_at));
    SEXP g = PROTECT(VECTOR_ELT(data, group_at));
    R_xlen_t n = XLENGTH(x);
    if (n == 0 || n > 1000000 ||
        dtatools_grouped_double_values(x, n) == R_NilValue ||
        (!canonical_column(g, n, "dta_long", 1) &&
         dtatools_grouped_double_values(g, n) == R_NilValue)) {
        UNPROTECT(3);
        return Rf_ScalarLogical(FALSE);
    }
    int double_key = dtatools_grouped_double_values(g, n) != R_NilValue;
    int extra_public = double_key || !ALTREP(x);
    if (extra_public && !dtatools_probe_plain_public_guard()) {
        UNPROTECT(3); return Rf_ScalarLogical(FALSE);
    }
    SEXP xb = dtatools_grouped_double_values(x, n);
    SEXP slot_roots = PROTECT(Rf_allocVector(VECSXP, width));
    SEXP attr_roots = PROTECT(Rf_allocVector(VECSXP, 16));
    /* A private read snapshot must not expose or materialize the key. */
    SEXP key_roots = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(key_roots, 2, Rf_allocVector(REALSXP, n));
    SEXP g_source = double_key ? dtatools_grouped_double_values(g, n) : numeric_base_source(g);
    if (g_source == R_NilValue) {
        UNPROTECT(6); return Rf_ScalarLogical(FALSE);
    }
    SET_VECTOR_ELT(key_roots, 0, g_source);
    SET_VECTOR_ELT(key_roots, 1, double_key ? g_source : R_altrep_data1(g_source));
    SEXP group_snapshot = VECTOR_ELT(key_roots, 2);
    if (double_key) memcpy(REAL(group_snapshot), REAL(g_source), (size_t)n * sizeof(double));
    else if (numeric_region(g_source, 0, n, REAL(group_snapshot)) != n) {
        UNPROTECT(6); return Rf_ScalarLogical(FALSE);
    }
    for (R_xlen_t i = 0; i < width; ++i)
        SET_VECTOR_ELT(slot_roots, i, VECTOR_ELT(data, i));
    table_attrs attrs;
    if (!snapshot_table_attrs(data, &attrs, attr_roots)) {
        UNPROTECT(6);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP needed = PROTECT(Rf_ScalarReal((double) width + 1.0));
    int ready = Rf_asLogical(C_dtatools_can_select_data_columns(data, needed));
    UNPROTECT(1);
    if (!ready || !dtatools_probe_gen_public_guard_plain(frame, base_state,
            public_state, extra_state, wrapper_state, rlang_state, s3_state, 1) ||
        !grouped_public_guard(caller, grouped_state, s3_state) ||
        (extra_public && !dtatools_probe_plain_public_guard())) {
        UNPROTECT(6);
        return Rf_ScalarLogical(FALSE);
    }

    SEXP backing = PROTECT(Rf_allocVector(REALSXP, n));
    SEXP column = PROTECT(owned_adopt_real(backing));
    SEXP storage = PROTECT(Rf_mkString("double"));
    Rf_setAttrib(column, Rf_install("stata.storage"), storage);
    SEXP column_classes = PROTECT(Rf_allocVector(STRSXP, 4));
    SET_STRING_ELT(column_classes, 0, Rf_mkChar("dta_numeric"));
    SET_STRING_ELT(column_classes, 1, Rf_mkChar("dta_double"));
    SET_STRING_ELT(column_classes, 2, Rf_mkChar("vctrs_vctr"));
    SET_STRING_ELT(column_classes, 3, Rf_mkChar("double"));
    Rf_setAttrib(column, R_ClassSymbol, column_classes);
    produced++;
    SEXP classes = PROTECT(Rf_getAttrib(data, R_ClassSymbol));
    if (TYPEOF(classes) != STRSXP || XLENGTH(classes) != 5 ||
        strcmp(CHAR(STRING_ELT(classes, 0)), "dibble") ||
        strcmp(CHAR(STRING_ELT(classes, 1)), "dtatools_ref_data") ||
        strcmp(CHAR(STRING_ELT(classes, 2)), "tbl_df") ||
        strcmp(CHAR(STRING_ELT(classes, 3)), "tbl") ||
        strcmp(CHAR(STRING_ELT(classes, 4)), "data.frame")) {
        UNPROTECT(11); return Rf_ScalarLogical(FALSE);
    }
    SEXP base_classes = PROTECT(Rf_allocVector(STRSXP, 3));
    for (int j = 0; j < 3; ++j)
        SET_STRING_ELT(base_classes, j, STRING_ELT(classes, j + 2));
    SEXP state = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, 29));
    Rf_defineVar(Rf_install("classes"), base_classes, state);
    SEXP name = PROTECT(Rf_ScalarString(target));
    for (R_xlen_t i = 0; i < n; i += 8192) R_CheckUserInterrupt();
    run_grouped_stage_hook();
    /* All allocation and polling precede the final source/frame check. */
    SEXP source2, target2, caller2, group2;
    double increment2;
    R_xlen_t source_at2, group_at2;
    if (!dtatools_reference_state_valid_noalloc(data) ||
        !dtatools_probe_gen_public_guard_plain(frame, base_state,
            public_state, extra_state, wrapper_state, rlang_state, s3_state, 1) ||
        !grouped_public_guard(caller, grouped_state, s3_state) ||
        (extra_public && !dtatools_probe_plain_public_guard())) {
        UNPROTECT(14); return Rf_ScalarLogical(FALSE);
    }
    SEXP type2 = Rf_GetOption1(Rf_install("dtatools.generate_type"));
    if (TYPEOF(type2) != STRSXP || ALTREP(type2) ||
        XLENGTH(type2) != 1 ||
        strcmp(CHAR(STRING_ELT(type2, 0)), "double") ||
        !source_frame(frame, data, &source2, &target2, &caller2,
                      &increment2, &group2) ||
        source2 != source || target2 != target || caller2 != caller ||
        group2 != group || increment2 != increment ||
        XLENGTH(data) != width ||
        !same_table_attrs(data, &attrs) ||
        Rf_getAttrib(data, R_NamesSymbol) != names ||
        Rf_getAttrib(data, R_ClassSymbol) != classes ||
        !locations(names, PRINTNAME(source), PRINTNAME(group), target,
                   &source_at2, &group_at2) ||
        source_at2 != source_at || group_at2 != group_at ||
        VECTOR_ELT(data, source_at) != x || VECTOR_ELT(data, group_at) != g ||
        (double_key ? dtatools_grouped_double_values(g, n) != g_source :
         (numeric_base_source(g) != g_source ||
          R_altrep_data1(g_source) != VECTOR_ELT(key_roots, 1))) ||
        dtatools_grouped_double_values(x, n) != xb ||
        dtatools_grouped_double_values(x, n) == R_NilValue ||
        (!canonical_column(g, n, "dta_long", 1) &&
         dtatools_grouped_double_values(g, n) == R_NilValue)) {
        UNPROTECT(14); return Rf_ScalarLogical(FALSE);
    }
    for (R_xlen_t i = 0; i < width; ++i)
        if (VECTOR_ELT(data, i) != VECTOR_ELT(slot_roots, i)) {
            UNPROTECT(14); return Rf_ScalarLogical(FALSE);
        }
    const double *gp = REAL(group_snapshot);
    /* A supported in-place write may keep the descriptor identity. */
    double key_block[256];
    for (R_xlen_t row = 0; row < n; row += 256) {
        R_xlen_t count = n - row < 256 ? n - row : 256;
        if (double_key) memcpy(key_block, REAL(g_source) + row, (size_t)count * sizeof(double));
        else if (numeric_region(g_source, row, count, key_block) != count) {
            UNPROTECT(14); return Rf_ScalarLogical(FALSE);
        }
        if (memcmp(key_block, gp + row, (size_t) count * sizeof(double))) {
            UNPROTECT(14); return Rf_ScalarLogical(FALSE);
        }
    }
    const double *xp = REAL(xb);
    double *out = REAL(backing);
    int bad = 0;
    for (R_xlen_t i = 0; i < n; ++i) {
        double value = xp[i] + increment;
        out[i] = value;
        bad |= !R_FINITE(gp[i]) ||
               gp[i] < -2147483647.0 || gp[i] > 2147483647.0 ||
               gp[i] != (double) ((int) gp[i]) ||
               !R_FINITE(xp[i]) ||
               !(value >= -DBL_MAX / 2.0 && value <= DBL_MAX / 2.0);
    }
    if (bad) { UNPROTECT(14); return Rf_ScalarLogical(FALSE); }
    SEXP appended = PROTECT(C_dtatools_append_mark_reference(
        data, name, column, state, classes));
    if (!Rf_asLogical(appended)) {
        UNPROTECT(15); return Rf_ScalarLogical(FALSE);
    }
    published++;
    UNPROTECT(15);
    return Rf_ScalarLogical(TRUE);
}
