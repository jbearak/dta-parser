/* Guarded grouped bracket execution with frozen selection, ordered append,
   and ordinary continuation for a pending RHS or uncommitted suffix. */
#define ENABLE_LEGACY_NONAPI_FUNS 1
#include "dtatools-internal.h"
#include <time.h>
#include <float.h>

extern SEXP C_dtatools_probe_grouped_bracket_selection(SEXP key, SEXP name);
extern SEXP C_dtatools_append_mark_reference(SEXP data, SEXP name,
                                             SEXP column, SEXP state,
                                             SEXP classes);
extern SEXP C_dtatools_probe_bracket_append_mark_reference(
    SEXP data, SEXP name, SEXP column, SEXP state, SEXP classes);
extern int dtatools_probe_grouped_guard_live_plain(void);
extern int dtatools_probe_grouped_guard_quick_plain(void);
extern int dtatools_probe_grouped_guard_rebind_plain(void);
extern int dtatools_probe_grouped_guard_bracket_marker_plain(void);
extern int dtatools_fast_s3_guard_env(SEXP caller, SEXP tables,
                                      SEXP live, SEXP namespaces);
extern void dtatools_probe_grouped_fire_output_hook(void);
static SEXP state_value(SEXP state, const char *name);

#define BRACKET_EXTRA_ROOTS 19

static SEXP extra_pinned = NULL;
static SEXP extra_bodies = NULL, extra_formals = NULL;
static SEXP extra_environments = NULL, extra_attributes = NULL;
static R_xlen_t extra_marker_index[2] = {-1, -1};
static SEXP bracket_function_symbol = NULL;
static SEXP bracket_function_primitive = NULL;
/* Immutable ASCII labels only. Every table's current class/dim/extent is
   still checked at each existing pre-RHS barrier. */
static SEXP bracket_numeric_class_labels = NULL;
#define BRACKET_NUMERIC_BASE_CLASSES 12
#define BRACKET_NUMERIC_CLASSES 16
static const char *bracket_numeric_class_names[BRACKET_NUMERIC_CLASSES] = {
    "dta_numeric", "dta_double", "vctrs_vctr", "double",
    "dta_temporal", "dta_date", "dta_datetime", "Date", "POSIXct",
    "POSIXt", "haven_labelled", "dtatools_dta_metadata_vector",
    "dta_byte", "dta_int", "dta_long", "dta_float"
};

SEXP C_dtatools_probe_grouped_bracket_pin(SEXP state) {
    if (extra_pinned != NULL || TYPEOF(state) != ENVSXP)
        return Rf_ScalarLogical(FALSE);
    SEXP labels = state_value(state, "labels");
    SEXP envs = state_value(state, "envs");
    SEXP live = state_value(state, "live");
    SEXP function_primitive = state_value(state, "function_primitive");
    if (TYPEOF(function_primitive) != SPECIALSXP) return Rf_ScalarLogical(FALSE);
    SEXP function_symbol = Rf_install("function");
    R_BindingType_t function_kind = R_GetBindingType(function_symbol, R_BaseEnv);
    if ((function_kind != R_BindingTypeValue &&
         function_kind != R_BindingTypeForced) ||
        R_getVarEx(function_symbol, R_BaseEnv, FALSE, R_NilValue) !=
            function_primitive) return Rf_ScalarLogical(FALSE);
    if (TYPEOF(labels) != STRSXP || XLENGTH(labels) != BRACKET_EXTRA_ROOTS ||
        TYPEOF(envs) != VECSXP || XLENGTH(envs) != BRACKET_EXTRA_ROOTS ||
        TYPEOF(live) != VECSXP || XLENGTH(live) != BRACKET_EXTRA_ROOTS)
        return Rf_ScalarLogical(FALSE);
    SEXP bodies = PROTECT(Rf_allocVector(VECSXP, BRACKET_EXTRA_ROOTS));
    SEXP formals = PROTECT(Rf_allocVector(VECSXP, BRACKET_EXTRA_ROOTS));
    SEXP environments = PROTECT(Rf_allocVector(VECSXP, BRACKET_EXTRA_ROOTS));
    SEXP attributes = PROTECT(Rf_allocVector(VECSXP, BRACKET_EXTRA_ROOTS));
    for (int i = 0; i < BRACKET_EXTRA_ROOTS; i++) {
        SEXP env = VECTOR_ELT(envs, i), fn = VECTOR_ELT(live, i);
        if (TYPEOF(env) != ENVSXP || TYPEOF(fn) != CLOSXP) {
            UNPROTECT(4); return Rf_ScalarLogical(FALSE);
        }
        SEXP symbol = Rf_installChar(STRING_ELT(labels, i));
        const char *name = CHAR(STRING_ELT(labels, i));
        if (strcmp(name, "match") == 0) extra_marker_index[0] = i;
        if (strcmp(name, "identity") == 0) extra_marker_index[1] = i;
        R_BindingType_t kind = R_GetBindingType(symbol, env);
        if ((kind != R_BindingTypeValue && kind != R_BindingTypeForced) ||
            R_getVarEx(symbol, env, FALSE, R_NilValue) != fn) {
            UNPROTECT(4); return Rf_ScalarLogical(FALSE);
        }
        SET_VECTOR_ELT(bodies, i, R_ClosureBody(fn));
        SET_VECTOR_ELT(formals, i, R_ClosureFormals(fn));
        SET_VECTOR_ELT(environments, i, R_ClosureEnv(fn));
        SET_VECTOR_ELT(attributes, i, ATTRIB(fn));
    }
    SEXP class_labels = PROTECT(Rf_allocVector(STRSXP,
                                             BRACKET_NUMERIC_CLASSES));
    for (int i = 0; i < BRACKET_NUMERIC_CLASSES; i++)
        SET_STRING_ELT(class_labels, i, Rf_mkChar(bracket_numeric_class_names[i]));
    R_PreserveObject(class_labels);
    bracket_numeric_class_labels = class_labels;
    R_PreserveObject(state);
    R_PreserveObject(bodies);
    R_PreserveObject(formals);
    R_PreserveObject(environments);
    R_PreserveObject(attributes);
    extra_pinned = state;
    extra_bodies = bodies;
    extra_formals = formals;
    extra_environments = environments;
    extra_attributes = attributes;
    bracket_function_symbol = function_symbol;
    bracket_function_primitive = function_primitive;
    UNPROTECT(5);
    return Rf_ScalarLogical(TRUE);
}

static int bracket_extra_guard(SEXP state) {
    if (state != extra_pinned || extra_pinned == NULL) return 0;
    R_BindingType_t function_kind = R_GetBindingType(
        bracket_function_symbol, R_BaseEnv);
    if ((function_kind != R_BindingTypeValue &&
         function_kind != R_BindingTypeForced) ||
        R_getVarEx(bracket_function_symbol, R_BaseEnv, FALSE, R_NilValue) !=
            bracket_function_primitive) return 0;
    SEXP labels = state_value(state, "labels");
    SEXP envs = state_value(state, "envs");
    SEXP live = state_value(state, "live");
    if (TYPEOF(labels) != STRSXP || XLENGTH(labels) != BRACKET_EXTRA_ROOTS ||
        TYPEOF(envs) != VECSXP || XLENGTH(envs) != BRACKET_EXTRA_ROOTS ||
        TYPEOF(live) != VECSXP || XLENGTH(live) != BRACKET_EXTRA_ROOTS)
        return 0;
    for (int i = 0; i < BRACKET_EXTRA_ROOTS; i++) {
        SEXP env = VECTOR_ELT(envs, i), fn = VECTOR_ELT(live, i);
        if (TYPEOF(env) != ENVSXP || TYPEOF(fn) != CLOSXP)
            return 0;
        SEXP symbol = Rf_installChar(STRING_ELT(labels, i));
        R_BindingType_t kind = R_GetBindingType(symbol, env);
        if ((kind != R_BindingTypeValue && kind != R_BindingTypeForced) ||
            R_getVarEx(symbol, env, FALSE, R_NilValue) != fn ||
            R_ClosureBody(fn) != VECTOR_ELT(extra_bodies, i) ||
            R_ClosureFormals(fn) != VECTOR_ELT(extra_formals, i) ||
            R_ClosureEnv(fn) != VECTOR_ELT(extra_environments, i) ||
            ATTRIB(fn) != VECTOR_ELT(extra_attributes, i))
            return 0;
    }
    return 1;
}

/* No R allocation or evaluation. Cold public qualification ran before this
   batch. Ordinary trace/body/binding changes invalidate the live identities. */
int dtatools_probe_grouped_bracket_marker_admitted(void) {
    if (extra_pinned == NULL || bracket_function_symbol == NULL ||
        !dtatools_probe_grouped_guard_bracket_marker_plain()) return 0;
    R_BindingType_t function_kind = R_GetBindingType(
        bracket_function_symbol, R_BaseEnv);
    if ((function_kind != R_BindingTypeValue &&
         function_kind != R_BindingTypeForced) ||
        R_getVarEx(bracket_function_symbol, R_BaseEnv, FALSE, R_NilValue) !=
            bracket_function_primitive) return 0;
    SEXP labels = state_value(extra_pinned, "labels");
    SEXP envs = state_value(extra_pinned, "envs");
    SEXP live = state_value(extra_pinned, "live");
    for (int j = 0; j < 2; j++) {
        R_xlen_t i = extra_marker_index[j];
        if (i < 0 || i >= BRACKET_EXTRA_ROOTS) return 0;
        SEXP env = VECTOR_ELT(envs, i), fn = VECTOR_ELT(live, i);
        SEXP symbol = Rf_installChar(STRING_ELT(labels, i));
        R_BindingType_t kind = R_GetBindingType(symbol, env);
        if ((kind != R_BindingTypeValue && kind != R_BindingTypeForced) ||
            R_getVarEx(symbol, env, FALSE, R_NilValue) != fn ||
            R_ClosureBody(fn) != VECTOR_ELT(extra_bodies, i) ||
            R_ClosureFormals(fn) != VECTOR_ELT(extra_formals, i) ||
            R_ClosureEnv(fn) != VECTOR_ELT(extra_environments, i) ||
            ATTRIB(fn) != VECTOR_ELT(extra_attributes, i)) return 0;
    }
    return 1;
}

static int bracket_reference_valid(SEXP data) {
    if (!Rf_inherits(data, "dtatools_ref_data")) return 0;
    SEXP state = R_NilValue;
    SEXP state_tag = Rf_install(".dtatools_ref_state");
    for (SEXP node = ATTRIB(data); node != R_NilValue; node = CDR(node))
        if (TAG(node) == state_tag) { state = CAR(node); break; }
    if (TYPEOF(state) != ENVSXP) return 0;
    SEXP owner_tag = Rf_install("owner");
    R_BindingType_t kind = R_GetBindingType(owner_tag, state);
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
        return 0;
    SEXP owner = R_getVarEx(owner_tag, state, FALSE, R_NilValue);
    return TYPEOF(owner) == EXTPTRSXP && R_ExternalPtrAddr(owner) == data;
}

static int attempts, plans, publications;
/* Scratch profiling only: 0 physical, 1 entry guard, 2 per-step guard with
   the package append transaction, 3 per-step guard with staged append,
   4 entry guard with staged append, 5 entry plus cheap per-step public guard
   and exact post-append rebind guard. */
static const int benchmark_mode = 5;
static int profile_on = 0;
static double profile_ns[4];
static int profile_count[4];
static double profile_clock(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double) t.tv_sec * 1e9 + (double) t.tv_nsec;
}
static void profile_add(int kind, double since) {
    if (profile_on) {
        profile_ns[kind] += profile_clock() - since;
        profile_count[kind]++;
    }
}
SEXP C_dtatools_probe_grouped_bracket_profile(SEXP on) {
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 4));
    for (int i = 0; i < 4; i++) {
        REAL(result)[i] = profile_count[i] ?
            profile_ns[i] / profile_count[i] / 1000.0 : NA_REAL;
        profile_ns[i] = 0;
        profile_count[i] = 0;
    }
    profile_on = Rf_asLogical(on) == TRUE;
    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_probe_grouped_bracket_mode(SEXP requested) {
    int next = Rf_asInteger(requested);
    if (next != 5)
        Rf_error("only the qualified grouped bracket mode is available");
    return Rf_ScalarInteger(benchmark_mode);
}

/* The R adapter uses this final rebind check at its existing return boundary.
   The current postappend marker certificate also checks rebind roots before
   deciding whether to return a deferred current marker. */
SEXP C_dtatools_probe_grouped_bracket_rebind_live(SEXP ignored) {
    (void) ignored;
    return Rf_ScalarLogical(dtatools_probe_grouped_guard_rebind_plain());
}

static SEXP state_value(SEXP state, const char *name) {
    if (TYPEOF(state) != ENVSXP) return R_NilValue;
    SEXP symbol = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(symbol, state);
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(symbol, state, FALSE, R_NilValue);
}

static int no_grouped_method(SEXP caller) {
    (void) caller;
    SEXP symbol = Rf_install("vec_proxy_equal.data.frame");
    /* vctrs' equality proxy resolver consults only GlobalEnv and its method
       table. The full/quick public guards retain the table-absence check;
       a caller or attached binding cannot affect this C resolver. */
    return R_GetBindingType(symbol, R_GlobalEnv) == R_BindingTypeUnbound;
}

/* A late caller binding for the source changes ordinary mask evaluation.
   Conservatively return to R even when the binding is a function or the
   shadow-check option is disabled; no promise or active binding is forced. */
static int source_unshadowed(SEXP caller, SEXP source_symbol) {
    if (TYPEOF(caller) != ENVSXP || TYPEOF(source_symbol) != SYMSXP)
        return 0;
    for (SEXP env = caller; env != R_EmptyEnv;
         env = R_ParentEnv(env)) {
        if (env == R_BaseEnv || R_IsNamespaceEnv(env)) return 1;
        if (R_GetBindingType(source_symbol, env) != R_BindingTypeUnbound)
            return 0;
        if (env == R_GlobalEnv) return 1;
    }
    return 1;
}

typedef struct {
    int count, seen;
    SEXP classes, rows;
} bracket_table_attrs;

static SEXP bracket_table_attr(SEXP tag, SEXP value, void *raw) {
    bracket_table_attrs *attrs = (bracket_table_attrs *) raw;
    attrs->count++;
    if (tag == R_NamesSymbol) attrs->seen |= 1;
    else if (tag == R_ClassSymbol) {
        attrs->seen |= 2; attrs->classes = value;
    } else if (tag == R_RowNamesSymbol) {
        attrs->seen |= 4; attrs->rows = value;
    } else if (tag == Rf_install(".dtatools_ref_state"))
        attrs->seen |= 8;
    else return R_NilValue;
    return NULL;
}

static int canonical_table(SEXP data, R_xlen_t n, R_xlen_t width) {
    if (TYPEOF(data) != VECSXP || ALTREP(data) ||
        XLENGTH(data) != width || n < 1 || n > INT_MAX ||
        !bracket_reference_valid(data)) return 0;
    bracket_table_attrs attrs = {0, 0, R_NilValue, R_NilValue};
    if (R_mapAttrib(data, bracket_table_attr, &attrs) != NULL ||
        attrs.count != 4 || attrs.seen != 15) return 0;
    static const char *wanted[] = {
        "dibble", "dtatools_ref_data", "tbl_df", "tbl", "data.frame"
    };
    if (TYPEOF(attrs.classes) != STRSXP || ALTREP(attrs.classes) ||
        XLENGTH(attrs.classes) != 5 ||
        TYPEOF(attrs.rows) != INTSXP || ALTREP(attrs.rows) ||
        XLENGTH(attrs.rows) != 2 ||
        INTEGER(attrs.rows)[0] != NA_INTEGER ||
        INTEGER(attrs.rows)[1] != -(int) n) return 0;
    for (int i = 0; i < 5; i++)
        if (strcmp(CHAR(STRING_ELT(attrs.classes, i)), wanted[i]))
            return 0;
    for (R_xlen_t i = 0; i < width; i++) {
        SEXP column = VECTOR_ELT(data, i);
        if (!ALTREP(column)) {
            if (XLENGTH(column) != n) return 0;
        } else if (owned_real(column) &&
                   R_altrep_data2(column) == R_NilValue &&
                   TYPEOF(owned_values(column)) == REALSXP &&
                   !ALTREP(owned_values(column))) {
            if (XLENGTH(owned_values(column)) != n) return 0;
        } else {
            numeric_data *compact = unmaterialized_numeric_read_storage(column);
            if (compact == NULL || compact->length != (size_t) n) return 0;
        }
    }
    return 1;
}

/* Same accepted class-name set as known_numeric_classes(). The current
   dimension, class-vector type, class-vector attributes and every class name
   are freshly read. Pointer misses use the unchanged byte-string predicate,
   preserving byte-marked/equivalent ASCII names and all unusual encodings.
   No label construction, allocation or interning happens in this check. */
static int bracket_numeric_classes(SEXP value, int compact) {
    if (bracket_numeric_class_labels == NULL)
        return known_numeric_classes(value, compact);
    if (TYPEOF(value) != REALSXP ||
        Rf_getAttrib(value, R_DimSymbol) != R_NilValue) return 0;
    SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
    if (classes == R_NilValue) return 1;
    if (TYPEOF(classes) != STRSXP || ALTREP(classes) || ANY_ATTRIB(classes))
        return 0;
    int count = compact ? BRACKET_NUMERIC_CLASSES :
                          BRACKET_NUMERIC_BASE_CLASSES;
    const SEXP *labels = STRING_PTR_RO(bracket_numeric_class_labels);
    const SEXP *current = STRING_PTR_RO(classes);
    for (R_xlen_t i = 0; i < XLENGTH(classes); i++) {
        SEXP name = current[i];
        int known = 0;
        for (int j = 0; j < count; j++)
            if (name == labels[j]) {
                known = 1; break;
            }
        if (!known) return known_numeric_classes(value, compact);
    }
    return 1;
}

/* Ordinary .as_mutation_data validates every sibling before the RHS. Known
   private views supply their length without NROW dispatch; unknown views may
   call public dim/NROW methods. Decline those shapes before their length is
   queried. This is a pre-RHS premise, not a post-RHS publication condition. */
static int pre_rhs_column_shapes(SEXP data, R_xlen_t n) {
    for (R_xlen_t i = 0; i < XLENGTH(data); i++) {
        SEXP column = VECTOR_ELT(data, i);
        if (Rf_getAttrib(column, R_DimSymbol) != R_NilValue) return 0;
        if (owned_column(column)) {
            if (TYPEOF(column) == REALSXP
                ? !bracket_numeric_classes(column, 0)
                : !owned_supported(column)) return 0;
            SEXP record = R_altrep_data1(column);
            if (TYPEOF(record) != EXTPTRSXP) return 0;
            SEXP values = R_ExternalPtrProtected(record);
            if (TYPEOF(values) != TYPEOF(column) || ALTREP(values) ||
                XLENGTH(values) != n) return 0;
        } else if (ALTREP(column)) {
            if (!bracket_numeric_classes(column, 1)) return 0;
            numeric_data *compact = unmaterialized_numeric_read_storage(column);
            if (compact == NULL || compact->length != (size_t) n) return 0;
        } else {
            int type = TYPEOF(column);
            if ((Rf_isObject(column) && dtatools_grouped_double_values(column, n) == R_NilValue) || IS_S4_OBJECT(column) ||
                (type != REALSXP && type != INTSXP && type != LGLSXP &&
                 type != STRSXP && type != CPLXSXP && type != RAWSXP &&
                 type != VECSXP) || XLENGTH(column) != n) return 0;
        }
    }
    return 1;
}

static int public_admitted(SEXP caller, SEXP extra_state,
                           SEXP s3_state) {
    return dtatools_probe_grouped_guard_live_plain() &&
        bracket_extra_guard(extra_state) &&
        no_grouped_method(caller) &&
        dtatools_fast_s3_guard_env(
            caller, state_value(s3_state, "tables"),
            state_value(s3_state, "live"),
            state_value(s3_state, "namespaces"));
}

static int public_admitted_quick(SEXP caller, SEXP extra_state,
                                 SEXP s3_state) {
    return dtatools_probe_grouped_guard_quick_plain() &&
        bracket_extra_guard(extra_state) &&
        no_grouped_method(caller) &&
        dtatools_fast_s3_guard_env(
            caller, state_value(s3_state, "tables"),
            state_value(s3_state, "live"),
            state_value(s3_state, "namespaces"));
}

static int double_generation_option(void) {
    SEXP value = Rf_GetOption1(Rf_install("dtatools.generate_type"));
    return TYPEOF(value) == STRSXP && !ALTREP(value) &&
        XLENGTH(value) == 1 &&
        strcmp(CHAR(STRING_ELT(value, 0)), "double") == 0;
}

static int valid_growth_option(void) {
    SEXP value = Rf_GetOption1(Rf_install("dtatools.auto_grow"));
    return value == R_NilValue ||
        (TYPEOF(value) == LGLSXP && !ALTREP(value) &&
         XLENGTH(value) == 1 && LOGICAL(value)[0] != NA_LOGICAL);
}

SEXP C_dtatools_probe_grouped_owned_write_first(SEXP column, SEXP number) {
    if (!owned_real(column) || XLENGTH(column) < 1 ||
        TYPEOF(owned_values(column)) != REALSXP || XLENGTH(number) != 1)
        Rf_error("invalid scratch direct source write");
    REAL(owned_values(column))[0] = Rf_asReal(number);
    return R_NilValue;
}

SEXP C_dtatools_probe_grouped_set_column_label(SEXP column, SEXP label) {
    if (TYPEOF(column) != REALSXP || TYPEOF(label) != STRSXP ||
        XLENGTH(label) != 1)
        Rf_error("invalid scratch column metadata write");
    Rf_setAttrib(column, Rf_install("label"), label);
    return R_NilValue;
}

SEXP C_dtatools_probe_grouped_set_column_attr(SEXP column, SEXP name,
                                              SEXP value) {
    if (TYPEOF(column) != REALSXP || TYPEOF(name) != STRSXP ||
        XLENGTH(name) != 1 || STRING_ELT(name, 0) == NA_STRING)
        Rf_error("invalid scratch column attribute write");
    Rf_setAttrib(column, Rf_installChar(STRING_ELT(name, 0)), value);
    return R_NilValue;
}

SEXP C_dtatools_probe_grouped_set_table_attr(SEXP data, SEXP name,
                                              SEXP value) {
    if (TYPEOF(data) != VECSXP || TYPEOF(name) != STRSXP ||
        XLENGTH(name) != 1 || STRING_ELT(name, 0) == NA_STRING)
        Rf_error("invalid scratch table metadata write");
    Rf_setAttrib(data, Rf_installChar(STRING_ELT(name, 0)), value);
    return R_NilValue;
}

SEXP C_dtatools_probe_grouped_bracket_stats(SEXP reset) {
    SEXP result = PROTECT(Rf_allocVector(INTSXP, 3));
    INTEGER(result)[0] = attempts;
    INTEGER(result)[1] = plans;
    INTEGER(result)[2] = publications;
    if (Rf_asLogical(reset)) attempts = plans = publications = 0;
    UNPROTECT(1);
    return result;
}

static int same_name(SEXP a, SEXP b) {
    if (a == b) return 1;
    if (TYPEOF(a) != CHARSXP || TYPEOF(b) != CHARSXP ||
        Rf_getCharCE(a) == CE_BYTES || Rf_getCharCE(b) == CE_BYTES)
        return 0;
    return strcmp(Rf_translateCharUTF8(a), Rf_translateCharUTF8(b)) == 0;
}

static int table_slot(SEXP names, SEXP wanted) {
    int found = -1;
    for (R_xlen_t slot = 0; slot < XLENGTH(names); slot++) {
        if (same_name(STRING_ELT(names, slot), wanted)) {
            if (found != -1) return -1;
            found = (int) slot;
        }
    }
    return found;
}

static int canonical_double(SEXP value, R_xlen_t n) {
    return dtatools_grouped_double_values(value, n) != R_NilValue;
}

static int parsed_value(SEXP assignment, SEXP caller, SEXP *source,
                        SEXP *target) {
    if (TYPEOF(assignment) != VECSXP || XLENGTH(assignment) != 2)
        return 0;
    SEXP fields = Rf_getAttrib(assignment, R_NamesSymbol);
    if (TYPEOF(fields) != STRSXP || XLENGTH(fields) != 2 ||
        strcmp(CHAR(STRING_ELT(fields, 0)), "name") ||
        strcmp(CHAR(STRING_ELT(fields, 1)), "values")) return 0;
    SEXP name = VECTOR_ELT(assignment, 0);
    SEXP quo = VECTOR_ELT(assignment, 1);
    if (TYPEOF(name) != STRSXP || XLENGTH(name) != 1 ||
        STRING_ELT(name, 0) == NA_STRING ||
        !CHAR(STRING_ELT(name, 0))[0] ||
        TYPEOF(quo) != LANGSXP || Rf_length(quo) != 2 ||
        CAR(quo) != Rf_install("~") ||
        Rf_getAttrib(quo, Rf_install(".Environment")) != caller)
        return 0;
    SEXP expr = CADR(quo);
    if (TYPEOF(expr) != LANGSXP || Rf_length(expr) != 3 ||
        CAR(expr) != Rf_install("+") || TYPEOF(CADR(expr)) != SYMSXP)
        return 0;
    SEXP literal = CADDR(expr);
    if (TYPEOF(literal) != REALSXP || ALTREP(literal) ||
        XLENGTH(literal) != 1 || REAL(literal)[0] != 1.0)
        return 0;
    if (*source == R_NilValue) *source = CADR(expr);
    if (*source != CADR(expr)) return 0;
    *target = STRING_ELT(name, 0);
    return 1;
}

static SEXP wrap_column(SEXP backing, SEXP classes, SEXP storage) {
    SEXP column = PROTECT(owned_adopt_real(backing));
    /* Generated columns own their metadata. Public by-reference attribute
       setters must not mutate the source or another generated column. */
    SEXP own_storage = PROTECT(Rf_duplicate(storage));
    SEXP own_classes = PROTECT(Rf_duplicate(classes));
    Rf_setAttrib(column, Rf_install("stata.storage"), own_storage);
    Rf_setAttrib(column, R_ClassSymbol, own_classes);
    UNPROTECT(3);
    return column;
}

/* Cost-only experiment on the existing fully guarded exact-R mode.
 * The existing R/dependency artifact admission must succeed before mode5 fill.
 * IEEE binary64 classification matches qualified libR R_finite, including its
 * integer-only exception behavior. Unknown builds and other modes keep it. */
#if defined(__APPLE__) && (defined(__arm64__) || defined(__aarch64__)) && \
    R_VERSION == R_Version(4, 6, 1) && R_SVN_REVISION == 90187 && \
    defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__ && \
    defined(__SIZEOF_DOUBLE__) && __SIZEOF_DOUBLE__ == 8 && \
    CHAR_BIT == 8 && FLT_RADIX == 2 && DBL_MANT_DIG == 53 && DBL_MAX_EXP == 1024
#define BRACKET_INLINE_BINARY64_FINITE 1
static inline int bracket_binary64_finite(double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return (bits & UINT64_C(0x7fffffffffffffff)) <
        UINT64_C(0x7ff0000000000000);
}
#else
#define BRACKET_INLINE_BINARY64_FINITE 0
#endif

static int fill_column(SEXP source, SEXP backing) {
    R_xlen_t n = XLENGTH(source);
    for (R_xlen_t row = 0; row < n; row += 8192)
        R_CheckUserInterrupt();
    SEXP current = dtatools_grouped_double_values(source, n);
    if (current == R_NilValue) return 0;
    const double *input = REAL(current);
    double *output = REAL(backing);
    int okay = 1;
#if BRACKET_INLINE_BINARY64_FINITE
    if (benchmark_mode == 5) {
        for (R_xlen_t row = 0; row < n; row++) {
            double value = input[row] + 1.0;
            output[row] = value;
            okay &= bracket_binary64_finite(input[row]) &&
                bracket_binary64_finite(value) && value >= -DBL_MAX / 2.0 && value <= DBL_MAX / 2.0;
        }
        return okay;
    }
#endif
    for (R_xlen_t row = 0; row < n; row++) {
        double value = input[row] + 1.0;
        output[row] = value;
        okay &= R_FINITE(input[row]) && value >= -DBL_MAX / 2.0 && value <= DBL_MAX / 2.0;
    }
    return okay;
}

typedef struct {
    SEXP data, column;
    SEXP old_names, new_names, old_attrs, new_attrs, attr_snapshot;
    SEXP table_classes, table_state, result;
    R_xlen_t width, n;
    int started, published;
} bracket_append;

static int unchanged_append(bracket_append *ctx) {
    SEXP data = ctx->data;
    if (TYPEOF(data) != VECSXP || ALTREP(data) ||
        XLENGTH(data) != ctx->width ||
        R_maxLength(data) < ctx->width + 1 ||
        ATTRIB(data) != ctx->old_attrs ||
        Rf_getAttrib(data, R_NamesSymbol) != ctx->old_names ||
        Rf_getAttrib(data, R_ClassSymbol) != ctx->table_classes ||
        Rf_getAttrib(data, Rf_install(".dtatools_ref_state")) !=
            ctx->table_state ||
        !bracket_reference_valid(data) ||
        TYPEOF(ctx->old_names) != STRSXP ||
        ALTREP(ctx->old_names) ||
        XLENGTH(ctx->old_names) != ctx->width)
        return 0;
    for (R_xlen_t i = 0; i < ctx->width; i++)
        if (STRING_ELT(ctx->old_names, i) !=
            STRING_ELT(ctx->new_names, i)) return 0;
    SEXP old = ctx->old_attrs, snapshot = ctx->attr_snapshot;
    while (old != R_NilValue && snapshot != R_NilValue) {
        if (TAG(old) != TAG(snapshot) || CAR(old) != CAR(snapshot))
            return 0;
        old = CDR(old);
        snapshot = CDR(snapshot);
    }
    if (old != R_NilValue || snapshot != R_NilValue) return 0;
    return 1;
}

static SEXP commit_bracket_append(void *raw) {
    bracket_append *ctx = (bracket_append *) raw;
    if (!unchanged_append(ctx)) return R_NilValue;
    /* RHS evaluation has already finished. A finalizer during append staging
       may change the source for the next assignment, not this output. */
    ctx->started = 1;
    SET_ATTRIB(ctx->data, R_NilValue);
    R_resizeVector(ctx->data, ctx->width + 1);
    SET_VECTOR_ELT(ctx->data, ctx->width, ctx->column);
    SET_ATTRIB(ctx->data, ctx->new_attrs);
    ctx->published = 1;
    return ctx->result;
}

static void cleanup_bracket_append(void *raw, Rboolean jump) {
    bracket_append *ctx = (bracket_append *) raw;
    if (!jump || !ctx->started || ctx->published) return;
    SET_ATTRIB(ctx->data, R_NilValue);
    R_resizeVector(ctx->data, ctx->width);
    SET_ATTRIB(ctx->data, ctx->old_attrs);
}

static SEXP prepared_append(SEXP data, SEXP column,
                            SEXP target, SEXP state, SEXP classes,
                            R_xlen_t n) {
    R_xlen_t width = XLENGTH(data);
    SEXP old_names = PROTECT(Rf_getAttrib(data, R_NamesSymbol));
    SEXP old_attrs = PROTECT(ATTRIB(data));
    if (TYPEOF(old_names) != STRSXP || ALTREP(old_names) ||
        XLENGTH(old_names) != width ||
        !R_isResizable(data) || R_maxLength(data) < width + 1) {
        UNPROTECT(2); return Rf_ScalarLogical(FALSE);
    }
    SEXP new_names = PROTECT(Rf_allocVector(STRSXP, width + 1));
    for (R_xlen_t i = 0; i < width; i++)
        SET_STRING_ELT(new_names, i, STRING_ELT(old_names, i));
    SET_STRING_ELT(new_names, width, target);
    SEXP owner = PROTECT(R_MakeExternalPtr(data, R_NilValue, R_NilValue));
    Rf_defineVar(Rf_install("owner"), owner, state);
    int count = 0, found_names = 0, found_class = 0, found_state = 0;
    for (SEXP node = old_attrs; node != R_NilValue; node = CDR(node)) {
        if (TYPEOF(node) != LISTSXP || ++count > 64) {
            UNPROTECT(4); return Rf_ScalarLogical(FALSE);
        }
    }
    SEXP new_attrs = PROTECT(Rf_allocList(count));
    SEXP attr_snapshot = PROTECT(Rf_allocList(count));
    SEXP out = new_attrs;
    SEXP saved = attr_snapshot;
    SEXP state_symbol = Rf_install(".dtatools_ref_state");
    for (SEXP node = old_attrs; node != R_NilValue;
         node = CDR(node), out = CDR(out), saved = CDR(saved)) {
        SEXP tag = TAG(node), value = CAR(node);
        SET_TAG(saved, tag);
        SETCAR(saved, value);
        if (tag == R_NamesSymbol) { value = new_names; found_names++; }
        else if (tag == R_ClassSymbol) { value = classes; found_class++; }
        else if (tag == state_symbol) { value = state; found_state++; }
        SET_TAG(out, tag);
        SETCAR(out, value);
    }
    if (found_names != 1 || found_class != 1 || found_state != 1) {
        UNPROTECT(6); return Rf_ScalarLogical(FALSE);
    }
    bracket_append ctx = {
        .data = data, .column = column,
        .old_names = old_names, .new_names = new_names,
        .old_attrs = old_attrs, .new_attrs = new_attrs,
        .attr_snapshot = attr_snapshot,
        .table_classes = Rf_getAttrib(data, R_ClassSymbol),
        .table_state = Rf_getAttrib(data, state_symbol),
        .width = width, .n = n,
        .started = 0, .published = 0
    };
    SEXP hook = Rf_GetOption1(Rf_install(
        "dtatools.probe_grouped_bracket_stage_hook"));
    if (Rf_isFunction(hook)) {
        SEXP call = PROTECT(Rf_lang1(hook));
        Rf_eval(call, R_GlobalEnv);
        UNPROTECT(1);
    }
    /* An interrupt at any preparation boundary precedes the last check. */
    R_CheckUserInterrupt();
    for (R_xlen_t row = 8192; row < n; row += 8192)
        R_CheckUserInterrupt();
    SEXP result_value = PROTECT(Rf_ScalarLogical(TRUE));
    ctx.result = result_value;
    SEXP continuation = PROTECT(R_MakeUnwindCont());
    SEXP result = R_UnwindProtect(commit_bracket_append, &ctx,
                                  cleanup_bracket_append, &ctx,
                                  continuation);
    UNPROTECT(8);
    return result;
}

/* Keep a completed RHS across a late decline. The adapter resumes at the
   recorded generation phase and never re-evaluates grouped arithmetic. */
static void retain_pending(SEXP result, int step, SEXP target, R_xlen_t n,
                           SEXP value, int generated) {
    SEXP pending = PROTECT(Rf_allocVector(VECSXP, 5));
    SEXP labels = PROTECT(Rf_allocVector(STRSXP, 5));
    const char *names[] = {"step", "target", "row_count", "rhs", "generated"};
    for (int i = 0; i < 5; i++) SET_STRING_ELT(labels, i, Rf_mkChar(names[i]));
    Rf_setAttrib(pending, R_NamesSymbol, labels);
    SET_VECTOR_ELT(pending, 0, Rf_ScalarInteger(step));
    SET_VECTOR_ELT(pending, 1, Rf_ScalarString(target));
    SET_VECTOR_ELT(pending, 2, Rf_ScalarReal((double) n));
    SET_VECTOR_ELT(pending, 3, value);
    SET_VECTOR_ELT(pending, 4, Rf_ScalarLogical(generated));
    SET_VECTOR_ELT(result, 4, pending);
    UNPROTECT(2);
}

SEXP C_dtatools_probe_grouped_bracket_batch(SEXP data, SEXP assignments,
                                             SEXP by, SEXP where,
                                             SEXP caller, SEXP extra_state,
                                             SEXP s3_state) {
    attempts++;
    if (TYPEOF(caller) == LANGSXP)
        caller = Rf_getAttrib(caller, Rf_install(".Environment"));
    if (TYPEOF(data) != VECSXP || TYPEOF(assignments) != VECSXP ||
        TYPEOF(caller) != ENVSXP || TYPEOF(by) != LANGSXP ||
        TYPEOF(where) != LANGSXP ||
        !(XLENGTH(assignments) == 1 || XLENGTH(assignments) == 5) ||
        !Rf_inherits(data, "dibble") ||
        Rf_inherits(data, "grouped_df") ||
        !bracket_reference_valid(data))
        return R_NilValue;
    if (Rf_length(where) != 2 || Rf_length(by) != 2)
        return R_NilValue;
    SEXP where_expr = CADR(where);
    SEXP by_expr = CADR(by);
    if (where_expr != R_NilValue || by_expr == R_NilValue ||
        TYPEOF(by_expr) != SYMSXP ||
        Rf_getAttrib(where, Rf_install(".Environment")) != R_EmptyEnv ||
        Rf_getAttrib(by, Rf_install(".Environment")) != caller)
        return R_NilValue;
    R_xlen_t width = XLENGTH(data);
    if (width < 2 || width > INT_MAX - 5) return R_NilValue;
    SEXP names = Rf_getAttrib(data, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || ALTREP(names) || XLENGTH(names) != width)
        return R_NilValue;
    SEXP source_symbol = R_NilValue;
    SEXP targets = PROTECT(Rf_allocVector(STRSXP, XLENGTH(assignments)));
    for (R_xlen_t i = 0; i < XLENGTH(assignments); i++) {
        SEXP target = R_NilValue;
        if (!parsed_value(VECTOR_ELT(assignments, i), caller,
                          &source_symbol, &target) ||
            table_slot(names, target) >= 0) {
            UNPROTECT(1); return R_NilValue;
        }
        for (R_xlen_t prior = 0; prior < i; prior++)
            if (same_name(STRING_ELT(targets, prior), target)) {
                UNPROTECT(1); return R_NilValue;
            }
        SET_STRING_ELT(targets, i, target);
    }
    if (source_symbol == R_NilValue) {
        UNPROTECT(1); return R_NilValue;
    }
    SEXP source_name = PRINTNAME(source_symbol);
    SEXP key_name = PRINTNAME(by_expr);
    int source_slot = table_slot(names, source_name);
    int key_slot = table_slot(names, key_name);
    if (source_slot < 0 || key_slot < 0 || source_slot == key_slot) {
        UNPROTECT(1); return R_NilValue;
    }
    SEXP source = VECTOR_ELT(data, source_slot);
    PROTECT_INDEX source_index;
    PROTECT_WITH_INDEX(source, &source_index);
    SEXP key = PROTECT(VECTOR_ELT(data, key_slot));
    R_xlen_t n = XLENGTH(source);
    if (!canonical_double(source, n) || XLENGTH(key) != n ||
        !canonical_table(data, n, width) ||
        !pre_rhs_column_shapes(data, n) ||
        !source_unshadowed(caller, source_symbol) ||
        !valid_growth_option() || !double_generation_option()) {
        UNPROTECT(3); return R_NilValue;
    }
    double tick = profile_on ? profile_clock() : 0.0;
    int double_inputs = !ALTREP(source) || dtatools_grouped_double_values(key, n) != R_NilValue;
    for (R_xlen_t j = 0; j < width; ++j)
        double_inputs |= !ALTREP(VECTOR_ELT(data, j)) && Rf_isObject(VECTOR_ELT(data, j));
    int initial_public = (benchmark_mode == 0 ||
        public_admitted(caller, extra_state, s3_state)) &&
        (!double_inputs || dtatools_probe_plain_public_guard());
    if (benchmark_mode != 0) profile_add(0, tick);
    if (!initial_public) {
        UNPROTECT(3); return R_NilValue;
    }
    SEXP needed = PROTECT(Rf_ScalarReal((double) width +
                                        XLENGTH(assignments)));
    int ready = Rf_asLogical(C_dtatools_can_select_data_columns(data, needed));
    UNPROTECT(1);
    if (!ready) { UNPROTECT(3); return R_NilValue; }
    SEXP key_name_string = PROTECT(Rf_ScalarString(key_name));
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 5));
    SEXP completed = PROTECT(Rf_ScalarInteger(0));
    SEXP needs_rebind = PROTECT(Rf_ScalarLogical(FALSE));
    SEXP staged = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, 29));
    SET_VECTOR_ELT(result, 0, completed);
    SET_VECTOR_ELT(result, 2, needs_rebind);
    SET_VECTOR_ELT(result, 3, staged);
    tick = profile_on ? profile_clock() : 0.0;
    SEXP selection = PROTECT(C_dtatools_probe_grouped_bracket_selection(
        key, key_name_string));
    profile_add(1, tick);
    if (selection == R_NilValue) {
        UNPROTECT(9); return R_NilValue;
    }
    tick = profile_on ? profile_clock() : 0.0;
    int after_plan_public = benchmark_mode != 5 ||
        (public_admitted_quick(caller, extra_state, s3_state) &&
             (!double_inputs || dtatools_probe_plain_public_guard()));
    if (benchmark_mode == 5) profile_add(0, tick);
    if (VECTOR_ELT(data, key_slot) != key || !after_plan_public) {
        UNPROTECT(9); return R_NilValue;
    }
    plans++;
    SET_VECTOR_ELT(result, 1, selection);
    int limit = (int) XLENGTH(assignments);
    SEXP limit_option = Rf_GetOption1(Rf_install(
        "dtatools.probe_grouped_bracket_limit"));
    if (TYPEOF(limit_option) == INTSXP && XLENGTH(limit_option) == 1 &&
        INTEGER(limit_option)[0] >= 0 && INTEGER(limit_option)[0] < limit)
        limit = INTEGER(limit_option)[0];
    for (R_xlen_t step = 0; step < XLENGTH(assignments); step++) {
        if (step >= limit) break;
        if (!double_generation_option()) break;
        if (step > 0 && (benchmark_mode == 2 || benchmark_mode == 3)) {
            tick = profile_on ? profile_clock() : 0.0;
            int good = public_admitted(caller, extra_state, s3_state);
            profile_add(0, tick);
            if (!good) break;
        }
        if (step > 0 && benchmark_mode == 5) {
            tick = profile_on ? profile_clock() : 0.0;
            int good = (public_admitted_quick(caller, extra_state, s3_state) &&
             (!double_inputs || dtatools_probe_plain_public_guard()));
            profile_add(0, tick);
            if (!good) break;
        }
        if (XLENGTH(data) != width + step ||
            !canonical_table(data, n, width + step) ||
            !pre_rhs_column_shapes(data, n) ||
            !source_unshadowed(caller, source_symbol)) break;
        names = Rf_getAttrib(data, R_NamesSymbol);
        if (TYPEOF(names) != STRSXP || XLENGTH(names) != width + step ||
            table_slot(names, source_name) != source_slot ||
            table_slot(names, key_name) != key_slot ||
            table_slot(names, STRING_ELT(targets, step)) >= 0) break;
        REPROTECT(source = VECTOR_ELT(data, source_slot), source_index);
        if (!canonical_double(source, n)) break;
        tick = profile_on ? profile_clock() : 0.0;
        SEXP backing = PROTECT(Rf_allocVector(REALSXP, n));
        double guard_tick = profile_on ? profile_clock() : 0.0;
        int after_prepare_public = benchmark_mode != 5 ||
            (public_admitted_quick(caller, extra_state, s3_state) &&
             (!double_inputs || dtatools_probe_plain_public_guard()));
        if (benchmark_mode == 5) profile_add(0, guard_tick);
        if ((benchmark_mode == 5 &&
             (!after_prepare_public ||
              VECTOR_ELT(data, source_slot) != source ||
              !canonical_table(data, n, width + step) ||
              !source_unshadowed(caller, source_symbol) ||
              !canonical_double(source, n) ||
              !double_generation_option())) ||
            !fill_column(source, backing)) {
            UNPROTECT(1); break;
        }
        SEXP source_classes = PROTECT(Rf_getAttrib(source, R_ClassSymbol));
        SEXP source_storage = PROTECT(Rf_getAttrib(
            source, Rf_install("stata.storage")));
        SEXP column = PROTECT(wrap_column(
            backing, source_classes, source_storage));
        SEXP pre_generation = Rf_GetOption1(Rf_install(
            "dtatools.probe_grouped_pre_generation_hook"));
        if (Rf_isFunction(pre_generation)) {
            SEXP callback = PROTECT(pre_generation);
            SEXP call = PROTECT(Rf_lang1(callback));
            Rf_eval(call, caller);
            UNPROTECT(2);
        }
        if (benchmark_mode == 5 &&
            (!public_admitted_quick(caller, extra_state, s3_state) ||
             (double_inputs && !dtatools_probe_plain_public_guard()))) {
            retain_pending(result, (int) step + 1, STRING_ELT(targets, step),
                           n, column, 0);
            UNPROTECT(4);
            break;
        }
        /* The ordinary output hook follows its public shaping calls. Changes
           made here affect later RHSs, not the already shaped current value. */
        dtatools_probe_grouped_fire_output_hook();
        profile_add(2, tick);
        SEXP classes = PROTECT(Rf_getAttrib(data, R_ClassSymbol));
        SEXP base_classes = PROTECT(Rf_allocVector(STRSXP, 3));
        if (TYPEOF(classes) != STRSXP || XLENGTH(classes) != 5) {
            retain_pending(result, (int) step + 1, STRING_ELT(targets, step),
                           n, column, 1);
            UNPROTECT(6); break;
        }
        for (int i = 0; i < 3; i++)
            SET_STRING_ELT(base_classes, i, STRING_ELT(classes, i + 2));
        SEXP state = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, 29));
        Rf_defineVar(Rf_install("classes"), base_classes, state);
        SEXP name = PROTECT(Rf_ScalarString(STRING_ELT(targets, step)));
        tick = profile_on ? profile_clock() : 0.0;
        SEXP appended = PROTECT(
            (benchmark_mode == 3 || benchmark_mode == 4) ?
            prepared_append(data, column, STRING_ELT(targets, step),
                            state, classes, n) :
            benchmark_mode == 5 ?
            C_dtatools_probe_bracket_append_mark_reference(
                data, name, column, state, classes) :
            C_dtatools_append_mark_reference(data, name, column,
                                              state, classes));
        profile_add(3, tick);
        if (appended == R_NilValue ||
            (TYPEOF(appended) == LGLSXP &&
             Rf_asLogical(appended) != TRUE)) {
            Rf_error("internal error: prepared table cannot append a column");
        }
        INTEGER(completed)[0] = (int) step + 1;
        publications++;
        if (TYPEOF(appended) == INTSXP &&
            XLENGTH(appended) == 1 && INTEGER(appended)[0] == 2) {
            SET_VECTOR_ELT(result, 2, Rf_ScalarLogical(TRUE));
            UNPROTECT(9);
            break;
        }
        UNPROTECT(9);
        SEXP hook = Rf_GetOption1(Rf_install(
            "dtatools.probe_grouped_bracket_after_step"));
        if (Rf_isFunction(hook)) {
            SEXP at = PROTECT(Rf_ScalarInteger((int) step + 1));
            SEXP call = PROTECT(Rf_lang2(hook, at));
            Rf_eval(call, caller);
            UNPROTECT(2);
        }
    }
    UNPROTECT(9);
    return result;
}
