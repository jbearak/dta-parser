/* Audited grouped mutate admission for owned dibble columns. */
#define ENABLE_LEGACY_NONAPI_FUNS 1
#include "dtatools-internal.h"
#include <string.h>
#include <stdint.h>
#include <float.h>
#include <R_ext/Memory.h>
#include <Rversion.h>
#include "grouped-public-code-qualify.inc"

/* This profile is pinned to the audited R 4.6.1 build. */
extern int RDEBUG(SEXP);
extern SEXP R_PromiseExpr(SEXP);

static int grouped_probe_enabled = 1;

/* Pins refer to one namespace lifetime. Never reuse them after unload. */
SEXP C_dtatools_grouped_disable(SEXP ignored) {
    (void) ignored;
    grouped_probe_enabled = 0;
    return R_NilValue;
}

static SEXP pointer_guard_operators = NULL;
static SEXP public_guard_roots = NULL;
static SEXP public_guard_states = NULL;
static SEXP public_guard_symbols = NULL;
/* Scratch cost experiment: rooted, private ordinary-list records avoid
   nested R list access during an otherwise unchanged live quick scan. */
#define PUBLIC_RECORD_FIELDS 7
static SEXP public_guard_records = NULL;
static SEXP absent_guard_roots = NULL;
static SEXP absent_guard_symbols = NULL;
static SEXP absent_guard_records = NULL;
static R_xlen_t rebind_public_index[2] = {-1, -1};
/* Scratch-only postappend marker/rebind closure graph. match is qualified
   by the bracket's additional-root profile. All pinned public primitives
   remain checked; the closed character unique lookup is checked separately. */
#define BRACKET_MARKER_CLOSURES 14
static R_xlen_t bracket_marker_index[BRACKET_MARKER_CLOSURES];
static const char *bracket_marker_names[BRACKET_MARKER_CLOSURES] = {
    "new.env", "setdiff", ".set_ops_need_as_vector", "isa", "%in%",
    "unique", "unique.default", "tryCatch", "identical", "parent.frame",
    "environment", "obj_address", "maybe_missing", "is_missing"
};
static SEXP bracket_unique_character_table = NULL;
static SEXP bracket_unique_character_symbol = NULL;
static R_xlen_t early_public_index[4] = {-1, -1, -1, -1};
static SEXP early_method_symbols[16];
static const char *early_method_names[16] = {
    "vec_arith.dta_numeric.numeric", "vec_arith.dta_numeric",
    "vec_cast.dta_numeric.dta_numeric", "vec_proxy_equal.dta_numeric",
    "vec_proxy.dibble", "vec_proxy.dta_numeric",
    "vec_ptype2.dta_numeric.dta_numeric", "vec_restore.dta_numeric",
    "+.vctrs_vctr", "$<-.data.frame", "dim.dibble",
    "names<-.vctrs_vctr", "Ops.dta_numeric",
    "anyDuplicated.default", "Ops.numeric_version", "rev.default"
};
static SEXP active_helper = NULL;
static SEXP active_expected = NULL;
static SEXP active_internal = NULL;
static SEXP active_state = NULL;
static int probe_public_srcref_same(SEXP actual, SEXP frozen, SEXP state);
static int probe_public_bindings_same(int deep);
static int active_base_internal_same(void) {
    if (active_internal == NULL || TYPEOF(active_internal) != SPECIALSXP)
        return 0;
    SEXP symbol = Rf_install(".Internal");
    R_BindingType_t type = R_GetBindingType(symbol, R_BaseEnv);
    return (type == R_BindingTypeValue || type == R_BindingTypeForced) &&
        R_getVar(symbol, R_BaseEnv, FALSE) == active_internal;
}
SEXP C_dtatools_grouped_active_mutate(SEXP ignored) {
    (void) ignored;
    SEXP frame = R_GetCurrentEnv();
    if (TYPEOF(frame) != ENVSXP || RDEBUG(frame) || active_helper == NULL ||
        active_expected == NULL || active_state == NULL ||
        !active_base_internal_same()) return Rf_ScalarLogical(FALSE);
    if (!probe_public_bindings_same(0))
        return Rf_ScalarLogical(FALSE);
    SEXP zero = PROTECT(Rf_ScalarInteger(0));
    SEXP call = PROTECT(Rf_lang2(active_helper, zero));
    SEXP actual = PROTECT(Rf_eval(call, frame));
    int same = TYPEOF(actual) == CLOSXP && active_base_internal_same() &&
        R_ClosureBody(actual) == R_ClosureBody(active_expected) &&
        R_ClosureFormals(actual) == R_ClosureFormals(active_expected) &&
        R_ClosureEnv(actual) == R_ClosureEnv(active_expected);
    UNPROTECT(3);
    return Rf_ScalarLogical(same);
}
SEXP C_dtatools_grouped_pin_operators(SEXP operators) {
    if (pointer_guard_operators != NULL || TYPEOF(operators) != VECSXP ||
        XLENGTH(operators) != 3) return Rf_ScalarLogical(FALSE);
    static const char *names[] = {"+", "abs", "-"};
    for (int i = 0; i < 3; i++) {
        SEXP expected = VECTOR_ELT(operators, i);
        if ((TYPEOF(expected) != BUILTINSXP && TYPEOF(expected) != SPECIALSXP) ||
            !dtatools_execution_lexical_function_same(
                R_BaseEnv, Rf_install(names[i]), expected))
            return Rf_ScalarLogical(FALSE);
    }
    R_PreserveObject(operators);
    pointer_guard_operators = operators;
    return Rf_ScalarLogical(TRUE);
}
/* Freshly check the S3 method names that were absent in the qualified
   ordinary route. Registration can override a default without changing any
   of the previously bound method functions. */
SEXP C_dtatools_grouped_pin_absent(SEXP roots) {
    if (absent_guard_roots != NULL || TYPEOF(roots) != VECSXP ||
        XLENGTH(roots) == 0) return Rf_ScalarLogical(FALSE);
    SEXP symbols = PROTECT(Rf_allocVector(VECSXP, XLENGTH(roots)));
    for (R_xlen_t i = 0; i < XLENGTH(roots); i++) {
        SEXP entry = VECTOR_ELT(roots, i);
        if (TYPEOF(entry) != VECSXP || XLENGTH(entry) != 2 ||
            TYPEOF(VECTOR_ELT(entry, 0)) != ENVSXP ||
            TYPEOF(VECTOR_ELT(entry, 1)) != STRSXP ||
            XLENGTH(VECTOR_ELT(entry, 1)) != 1 ||
            STRING_ELT(VECTOR_ELT(entry, 1), 0) == NA_STRING) {
            UNPROTECT(1); return Rf_ScalarLogical(FALSE);
        }
        SEXP symbol = Rf_installChar(STRING_ELT(VECTOR_ELT(entry, 1), 0));
        if (strcmp(CHAR(STRING_ELT(VECTOR_ELT(entry, 1), 0)),
                   "unique.character") == 0) {
            bracket_unique_character_table = VECTOR_ELT(entry, 0);
            bracket_unique_character_symbol = symbol;
        }
        if (R_GetBindingType(symbol, VECTOR_ELT(entry, 0)) !=
                R_BindingTypeUnbound ||
            R_GetBindingType(symbol, R_GlobalEnv) != R_BindingTypeUnbound) {
            UNPROTECT(1); return Rf_ScalarLogical(FALSE);
        }
        SET_VECTOR_ELT(symbols, i, symbol);
    }
    SEXP records = PROTECT(Rf_allocVector(VECSXP, XLENGTH(roots) * 2));
    for (R_xlen_t i = 0; i < XLENGTH(roots); i++) {
        SET_VECTOR_ELT(records, i * 2, VECTOR_ELT(symbols, i));
        SET_VECTOR_ELT(records, i * 2 + 1,
                       VECTOR_ELT(VECTOR_ELT(roots, i), 0));
    }
    R_PreserveObject(roots);
    R_PreserveObject(symbols);
    R_PreserveObject(records);
    absent_guard_roots = roots;
    absent_guard_symbols = symbols;
    absent_guard_records = records;
    UNPROTECT(2);
    return Rf_ScalarLogical(TRUE);
}
static int probe_absent_bindings_same(void) {
    if (absent_guard_roots == NULL || absent_guard_symbols == NULL ||
        absent_guard_records == NULL) return 0;
    const SEXP *records = VECTOR_PTR_RO(absent_guard_records);
    const R_xlen_t count = XLENGTH(absent_guard_roots);
    for (R_xlen_t i = 0; i < count; i++) {
        SEXP symbol = records[i * 2];
        SEXP table = records[i * 2 + 1];
        if (R_GetBindingType(symbol, table) != R_BindingTypeUnbound ||
            R_GetBindingType(symbol, R_GlobalEnv) != R_BindingTypeUnbound)
            return 0;
    }
    return 1;
}

static int probe_public_debug_or_step(SEXP fn) {
    if (RDEBUG(fn)) return 1;
#if defined(__APPLE__) && defined(__aarch64__) && R_VERSION == R_Version(4,6,1)
    /* R 4.6.1's unexported RSTEP field. Unsupported builds always decline. */
    return ((((const uint32_t *) fn)[0] & UINT32_C(0x08000000)) != 0);
#else
    return 1;
#endif
}

static int probe_public_srcref_same(SEXP actual, SEXP frozen, SEXP state) {
    closure_attrs attrs_a = {.count=0}, attrs_b = {.count=0};
    if (R_mapAttrib(actual, capture_closure_attr, &attrs_a) != NULL ||
        R_mapAttrib(frozen, capture_closure_attr, &attrs_b) != NULL ||
        attrs_a.count != attrs_b.count) return 0;
    if (!attrs_a.count) return 1;
    if (attrs_a.count != 1 || attrs_a.tag[0] != Rf_install("srcref") ||
        attrs_b.tag[0] != Rf_install("srcref")) return 0;
    SEXP a = attrs_a.value[0], b = attrs_b.value[0];
    if (TYPEOF(a) != INTSXP || TYPEOF(b) != INTSXP ||
        ALTREP(a) || ALTREP(b) || XLENGTH(a) != 8 || XLENGTH(b) != 8 ||
        memcmp(INTEGER(a), INTEGER(b), 8 * sizeof(int)) != 0) return 0;
    closure_attrs refs_a = {.count=0}, refs_b = {.count=0};
    if (R_mapAttrib(a, capture_closure_attr, &refs_a) != NULL ||
        R_mapAttrib(b, capture_closure_attr, &refs_b) != NULL ||
        refs_a.count != 2 || refs_b.count != 2) return 0;
    SEXP class_a = R_NilValue, class_b = R_NilValue;
    SEXP source_a = R_NilValue, source_b = R_NilValue;
    for (int i=0; i<2; i++) {
        if (refs_a.tag[i] == R_ClassSymbol) class_a = refs_a.value[i];
        if (refs_b.tag[i] == R_ClassSymbol) class_b = refs_b.value[i];
        if (refs_a.tag[i] == Rf_install("srcfile")) source_a = refs_a.value[i];
        if (refs_b.tag[i] == Rf_install("srcfile")) source_b = refs_b.value[i];
    }
    return source_a == VECTOR_ELT(state, 2) &&
        source_b == VECTOR_ELT(state, 3) &&
        TYPEOF(class_a) == STRSXP && TYPEOF(class_b) == STRSXP &&
        !ALTREP(class_a) && !ALTREP(class_b) &&
        XLENGTH(class_a) == 1 && XLENGTH(class_b) == 1 &&
        STRING_ELT(class_a, 0) == STRING_ELT(class_b, 0);
}

/* Explicit fallback for public closures whose compiled constants the general
   cold walker cannot validate. The approved boundary excludes direct writes
   to bytecode and compilation under replaced dependencies. Such roots compare
   visible source/formals cold and again at both admission barriers. */
static int probe_public_visible_source_same(SEXP actual, SEXP frozen) {
    if (TYPEOF(actual) != CLOSXP || TYPEOF(frozen) != CLOSXP ||
        R_ClosureEnv(actual) != R_ClosureEnv(frozen)) return 0;
    SEXP a = PROTECT(R_ClosureExpr(actual));
    SEXP b = PROTECT(R_ClosureExpr(frozen));
    SEXP sa = body_source_file(a), sb = body_source_file(b);
    int okay = ((TYPEOF(sa) == ENVSXP && TYPEOF(sb) == ENVSXP) ||
                (sa == R_NilValue && sb == R_NilValue));
    int budget = 262144;
    if (okay) okay = exact_source_tree(R_ClosureFormals(actual),
         R_ClosureFormals(frozen), sa, sb, &budget, 0, 0);
    budget = 262144;
    if (okay) okay = exact_source_tree(a, b, sa, sb, &budget, 0, 0);
    UNPROTECT(2);
    return okay;
}
static int probe_public_fresh_state(SEXP actual, SEXP frozen, SEXP state) {
    if (TYPEOF(actual) != CLOSXP || TYPEOF(frozen) != CLOSXP ||
        TYPEOF(state) != VECSXP || XLENGTH(state) != 7 ||
        probe_public_debug_or_step(actual) ||
        R_ClosureBody(actual) != VECTOR_ELT(state, 0) ||
        R_ClosureEnv(actual) != VECTOR_ELT(state, 1)) return 0;
    int budget = 32768;
    if (!exact_source_tree(R_ClosureFormals(actual), R_ClosureFormals(frozen),
            VECTOR_ELT(state, 2), VECTOR_ELT(state, 3), &budget, 0, 0))
        return 0;
    return probe_public_srcref_same(actual, frozen, state) &&
        (!LOGICAL(VECTOR_ELT(state, 5))[0] ||
         probe_public_visible_source_same(actual, frozen));
}

SEXP C_dtatools_grouped_pin_public(SEXP functions) {
    if (public_guard_roots != NULL || TYPEOF(functions) != VECSXP ||
        XLENGTH(functions) < 1) return Rf_ScalarLogical(FALSE);
    SEXP states = PROTECT(Rf_allocVector(VECSXP, XLENGTH(functions) + 1));
    SEXP symbols = PROTECT(Rf_allocVector(VECSXP, XLENGTH(functions)));
    SET_VECTOR_ELT(states, XLENGTH(functions), symbols);
    UNPROTECT(1);
    SEXP found_active = NULL, found_internal = NULL, found_state = NULL;
    for (int j = 0; j < BRACKET_MARKER_CLOSURES; j++)
        bracket_marker_index[j] = -1;
    for (R_xlen_t i = 0; i < XLENGTH(functions); i++) {
        SEXP entry = VECTOR_ELT(functions, i);
        if (TYPEOF(entry) != VECSXP ||
            (XLENGTH(entry) != 3 && XLENGTH(entry) != 4))
            return Rf_ScalarLogical(FALSE);
        SEXP env = VECTOR_ELT(entry, 0);
        SEXP name = VECTOR_ELT(entry, 1);
        SEXP expected = VECTOR_ELT(entry, 2);
        if (TYPEOF(env) != ENVSXP || TYPEOF(name) != STRSXP ||
            XLENGTH(name) != 1 || STRING_ELT(name, 0) == NA_STRING ||
            (TYPEOF(expected) != CLOSXP && TYPEOF(expected) != BUILTINSXP &&
             TYPEOF(expected) != SPECIALSXP) ||
            (TYPEOF(expected) == CLOSXP &&
             (XLENGTH(entry) != 4 || probe_public_debug_or_step(expected)))) {
            UNPROTECT(1); return Rf_ScalarLogical(FALSE);
        }
        SEXP symbol = Rf_installChar(STRING_ELT(name, 0));
        SET_VECTOR_ELT(symbols, i, symbol);
        const char *root_name = CHAR(STRING_ELT(name, 0));
        for (int j = 0; j < BRACKET_MARKER_CLOSURES; j++)
            if (strcmp(root_name, bracket_marker_names[j]) == 0)
                bracket_marker_index[j] = i;
        for (int j = 0; j < 16; j++)
            if (strcmp(root_name, early_method_names[j]) == 0)
                early_method_symbols[j] = symbol;
        if (strcmp(root_name, "identical") == 0)
            rebind_public_index[0] = i;
        if (env == R_BaseEnv) {
            if (strcmp(root_name, "missing") == 0) early_public_index[0] = i;
            if (strcmp(root_name, "list") == 0) early_public_index[1] = i;
            if (strcmp(root_name, "names<-") == 0) early_public_index[2] = i;
        }
        if (strcmp(root_name, "obj_address") == 0 &&
            strcmp(CHAR(STRING_ELT(name, 0)), "obj_address") == 0)
            rebind_public_index[1] = i;
        if (strcmp(root_name, "names<-.vctrs_vctr") == 0)
            early_public_index[3] = i;
        R_BindingType_t type = R_GetBindingType(symbol, env);
        if ((type != R_BindingTypeValue && type != R_BindingTypeForced) ||
            R_getVar(symbol, env, FALSE) != expected) {
            UNPROTECT(1); return Rf_ScalarLogical(FALSE);
        }
        if (XLENGTH(entry) == 4) {
            SEXP flags = PROTECT(grouped_source_qualification(
                expected, VECTOR_ELT(entry, 3)));
            int same = TYPEOF(flags) == LGLSXP && XLENGTH(flags) == 4;
            for (int j = 0; same && j < 4; j++)
                same = LOGICAL(flags)[j] == TRUE;
            int visible_fallback = 0;
            if (!same) {
                same = probe_public_visible_source_same(expected,
                                                        VECTOR_ELT(entry, 3));
                visible_fallback = same;
            }
            if (!same) {
                UNPROTECT(2); return Rf_ScalarLogical(FALSE);
            }
            UNPROTECT(1);
            SEXP frozen = VECTOR_ELT(entry, 3);
            SEXP state = PROTECT(Rf_allocVector(VECSXP, 7));
            SET_VECTOR_ELT(state, 0, R_ClosureBody(expected));
            SET_VECTOR_ELT(state, 1, R_ClosureEnv(expected));
            SET_VECTOR_ELT(state, 2, body_source_file(R_ClosureExpr(expected)));
            SET_VECTOR_ELT(state, 3, body_source_file(R_ClosureExpr(frozen)));
            SET_VECTOR_ELT(state, 4, R_ClosureFormals(expected));
            SET_VECTOR_ELT(state, 5, Rf_ScalarLogical(visible_fallback));
            SET_VECTOR_ELT(state, 6, ATTRIB(expected));
            if (!probe_public_fresh_state(expected, frozen, state)) {
                UNPROTECT(2); return Rf_ScalarLogical(FALSE);
            }
            SET_VECTOR_ELT(states, i, state);
            if (symbol == Rf_install("mutate.dibble")) {
                found_active = expected;
                found_state = state;
            }
            UNPROTECT(1);
        }
        if (symbol == Rf_install(".Internal"))
            found_internal = expected;
    }
    if (found_active == NULL || found_internal == NULL ||
        TYPEOF(found_internal) != SPECIALSXP ||
        R_getVar(Rf_install(".Internal"), R_BaseEnv, FALSE) != found_internal) {
        UNPROTECT(1); return Rf_ScalarLogical(FALSE);
    }
    SEXP helper_env = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, 1));
    Rf_defineVar(Rf_install(".Internal"), found_internal, helper_env);
    R_LockEnvironment(helper_env, TRUE);
    SEXP helper_formals = PROTECT(Rf_cons(R_MissingArg, R_NilValue));
    SET_TAG(helper_formals, Rf_install("which"));
    SEXP helper_query = PROTECT(Rf_lang2(Rf_install("sys.function"),
                                         Rf_install("which")));
    SEXP helper_body = PROTECT(Rf_lang2(Rf_install(".Internal"), helper_query));
    SEXP helper = PROTECT(R_mkClosure(helper_formals, helper_body, helper_env));
    R_PreserveObject(helper);
    active_helper = helper;
    active_expected = found_active;
    active_internal = found_internal;
    active_state = found_state;
    UNPROTECT(5);
    SEXP records = PROTECT(Rf_allocVector(
        VECSXP, XLENGTH(functions) * PUBLIC_RECORD_FIELDS));
    for (R_xlen_t i = 0; i < XLENGTH(functions); i++) {
        SEXP entry = VECTOR_ELT(functions, i);
        SEXP state = VECTOR_ELT(states, i);
        R_xlen_t at = i * PUBLIC_RECORD_FIELDS;
        SET_VECTOR_ELT(records, at, VECTOR_ELT(entry, 0));
        SET_VECTOR_ELT(records, at + 1, VECTOR_ELT(symbols, i));
        SET_VECTOR_ELT(records, at + 2, VECTOR_ELT(entry, 2));
        if (TYPEOF(VECTOR_ELT(entry, 2)) == CLOSXP) {
            if (TYPEOF(state) != VECSXP || XLENGTH(state) != 7) {
                UNPROTECT(2); return Rf_ScalarLogical(FALSE);
            }
            SET_VECTOR_ELT(records, at + 3, VECTOR_ELT(state, 0));
            SET_VECTOR_ELT(records, at + 4, VECTOR_ELT(state, 1));
            SET_VECTOR_ELT(records, at + 5, VECTOR_ELT(state, 4));
            SET_VECTOR_ELT(records, at + 6, VECTOR_ELT(state, 6));
        }
    }
    R_PreserveObject(functions);
    R_PreserveObject(states);
    R_PreserveObject(records);
    public_guard_records = records;
    public_guard_roots = functions;
    public_guard_states = states;
    public_guard_symbols = symbols;
    UNPROTECT(2);
    return Rf_ScalarLogical(TRUE);
}

static int probe_public_bindings_same(int deep) {
    if (!grouped_probe_enabled || public_guard_roots == NULL || public_guard_states == NULL ||
        public_guard_symbols == NULL || !probe_absent_bindings_same()) return 0;
    for (R_xlen_t i = 0; i < XLENGTH(public_guard_roots); i++) {
        SEXP entry = VECTOR_ELT(public_guard_roots, i);
        SEXP env = VECTOR_ELT(entry, 0);
        SEXP symbol = VECTOR_ELT(public_guard_symbols, i);
        R_BindingType_t type = R_GetBindingType(symbol, env);
        if (type != R_BindingTypeValue && type != R_BindingTypeForced)
            return 0;
        SEXP actual = R_getVar(symbol, env, FALSE);
        SEXP state = VECTOR_ELT(public_guard_states, i);
        if (TYPEOF(actual) == CLOSXP && TYPEOF(state) != VECSXP) return 0;
        if (TYPEOF(actual) == CLOSXP &&
            LOGICAL(VECTOR_ELT(state, 5))[0] &&
            (!probe_public_visible_source_same(actual, VECTOR_ELT(entry, 3)) ||
             !probe_public_srcref_same(actual, VECTOR_ELT(entry, 3), state)))
            return 0;
        if (actual != VECTOR_ELT(entry, 2) ||
            (TYPEOF(actual) == CLOSXP &&
             !(deep ? probe_public_fresh_state(actual, VECTOR_ELT(entry, 3),
                                               state) :
                       !probe_public_debug_or_step(actual) &&
                       R_ClosureBody(actual) == VECTOR_ELT(state, 0) &&
                       R_ClosureEnv(actual) == VECTOR_ELT(state, 1) &&
                       R_ClosureFormals(actual) == VECTOR_ELT(state, 4))))
            return 0;
    }
    return 1;
}

/* The deep installed-source certificate has run before step one. Public
   R-level trace and replacement between steps changes a root binding, body,
   formals, environment, or attributes. The approved compatibility boundary
   excludes direct low-level edits inside an existing bytecode object. */
/* Full scans hold one view of a preserved, private ordinary record list.
   Public getters and closure checks remain fresh and in their original order.
   The indexed wrapper below retains its original bounds/error behavior. */
#if defined(__GNUC__) || defined(__clang__)
#define PUBLIC_GUARD_RECORD_INLINE static inline __attribute__((always_inline))
#else
#define PUBLIC_GUARD_RECORD_INLINE static inline
#endif
PUBLIC_GUARD_RECORD_INLINE int probe_public_record_quick(const SEXP *record) {
    SEXP env = record[0], symbol = record[1];
    R_BindingType_t type = R_GetBindingType(symbol, env);
    if (type != R_BindingTypeValue && type != R_BindingTypeForced)
        return 0;
    SEXP actual = R_getVar(symbol, env, FALSE);
    if (actual != record[2]) return 0;
    if (TYPEOF(actual) != CLOSXP) return 1;
    return !probe_public_debug_or_step(actual) &&
        R_ClosureBody(actual) == record[3] &&
        R_ClosureEnv(actual) == record[4] &&
        R_ClosureFormals(actual) == record[5] &&
        ATTRIB(actual) == record[6];
}

static int probe_public_root_quick(R_xlen_t i) {
    if (!grouped_probe_enabled || public_guard_records == NULL ||
        i < 0 || i >= XLENGTH(public_guard_roots)) return 0;
    const SEXP *record = VECTOR_PTR_RO(public_guard_records) +
        i * PUBLIC_RECORD_FIELDS;
    return probe_public_record_quick(record);
}

int dtatools_probe_grouped_guard_quick_plain(void) {
    if (!grouped_probe_enabled || public_guard_roots == NULL || public_guard_states == NULL ||
        public_guard_symbols == NULL || !probe_absent_bindings_same()) return 0;
    if (public_guard_records == NULL) return 0;
    const R_xlen_t count = XLENGTH(public_guard_roots);
    const SEXP *record = VECTOR_PTR_RO(public_guard_records);
    for (R_xlen_t i = 0; i < count; i++, record += PUBLIC_RECORD_FIELDS)
        if (!probe_public_record_quick(record)) return 0;
    return 1;
}

int dtatools_probe_grouped_guard_rebind_plain(void) {
    if (!grouped_probe_enabled || public_guard_roots == NULL || public_guard_states == NULL ||
        public_guard_symbols == NULL) return 0;
    return probe_public_root_quick(rebind_public_index[0]) &&
        probe_public_root_quick(rebind_public_index[1]);
}

int dtatools_probe_grouped_guard_bracket_marker_plain(void) {
    if (!grouped_probe_enabled || public_guard_roots == NULL || public_guard_states == NULL ||
        public_guard_symbols == NULL ||
        bracket_unique_character_table == NULL ||
        bracket_unique_character_symbol == NULL) return 0;
    for (int j = 0; j < BRACKET_MARKER_CLOSURES; j++)
        if (!probe_public_root_quick(bracket_marker_index[j])) return 0;
    const R_xlen_t count = XLENGTH(public_guard_roots);
    const SEXP *record = VECTOR_PTR_RO(public_guard_records);
    for (R_xlen_t i = 0; i < count; i++, record += PUBLIC_RECORD_FIELDS)
        if (TYPEOF(record[2]) != CLOSXP &&
            !probe_public_record_quick(record)) return 0;
    /* unique() is called inside base setdiff: base lexical binding, then
       the base method table and GlobalEnv. Caller-local and attached methods
       are outside that actual R lookup range. The default base closure is
       among the checked roots above. */
    SEXP symbol = bracket_unique_character_symbol;
    return R_GetBindingType(symbol, R_BaseNamespace) == R_BindingTypeUnbound &&
        R_GetBindingType(symbol, R_BaseEnv) == R_BindingTypeUnbound &&
        R_GetBindingType(symbol, bracket_unique_character_table) ==
            R_BindingTypeUnbound &&
        R_GetBindingType(symbol, R_GlobalEnv) == R_BindingTypeUnbound;
}

SEXP C_dtatools_grouped_guard_public(SEXP ignored) {
    (void) ignored;
    return Rf_ScalarLogical(probe_public_bindings_same(1));
}

/* Scratch grouped-bracket certificate: the pinned source was qualified at
   namespace load. Current bindings, body identity, formals, and attrs are
   rechecked before each ordered publication. */
int dtatools_probe_grouped_guard_live_plain(void) {
    return probe_public_bindings_same(0);
}
SEXP C_dtatools_probe_grouped_guard_live(SEXP ignored) {
    (void) ignored;
    return Rf_ScalarLogical(dtatools_probe_grouped_guard_live_plain());
}

/* Early exclusion for callbacks reached before the full grouped guard. */
SEXP C_dtatools_grouped_guard_early(SEXP ignored) {
    (void) ignored;
    if (!grouped_probe_enabled || public_guard_roots == NULL || public_guard_states == NULL ||
        !probe_absent_bindings_same())
        return Rf_ScalarLogical(FALSE);
    for (int j = 0; j < 4; j++) {
        R_xlen_t i = early_public_index[j];
        if (i < 0 || i >= XLENGTH(public_guard_roots))
            return Rf_ScalarLogical(FALSE);
        SEXP entry = VECTOR_ELT(public_guard_roots, i);
        SEXP env = VECTOR_ELT(entry, 0);
        SEXP symbol = Rf_installChar(STRING_ELT(VECTOR_ELT(entry, 1), 0));
        R_BindingType_t type = R_GetBindingType(symbol, env);
        if ((type != R_BindingTypeValue && type != R_BindingTypeForced) ||
            R_getVar(symbol, env, FALSE) != VECTOR_ELT(entry, 2))
            return Rf_ScalarLogical(FALSE);
        if (j == 3) {
            SEXP state = VECTOR_ELT(public_guard_states, i);
            SEXP fn = VECTOR_ELT(entry, 2);
            if (!probe_public_fresh_state(fn, VECTOR_ELT(entry, 3), state))
                return Rf_ScalarLogical(FALSE);
        }
    }
    for (int j = 0; j < 16; j++)
        if (early_method_symbols[j] == NULL ||
            R_GetBindingType(early_method_symbols[j], R_GlobalEnv) !=
                R_BindingTypeUnbound)
            return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(TRUE);
}

static int typed(SEXP col, R_xlen_t n, const char *class_name, const char *storage_name) {
    if (TYPEOF(col) != REALSXP || XLENGTH(col) != n) {
        return 0;
    }
    SEXP storage = Rf_getAttrib(col, Rf_install("stata.storage"));
    SEXP classes = Rf_getAttrib(col, R_ClassSymbol);
    if (TYPEOF(storage) != STRSXP || ALTREP(storage) || XLENGTH(storage) != 1 ||
        strcmp(CHAR(STRING_ELT(storage, 0)), storage_name) ||
        TYPEOF(classes) != STRSXP || ALTREP(classes) || XLENGTH(classes) != 4 ||
        strcmp(CHAR(STRING_ELT(classes, 0)), "dta_numeric") ||
        strcmp(CHAR(STRING_ELT(classes, 1)), class_name) ||
        strcmp(CHAR(STRING_ELT(classes, 2)), "vctrs_vctr") ||
        strcmp(CHAR(STRING_ELT(classes, 3)), "double")) {
        return 0;
    }
    return R_getAttribCount(col) == 2 &&
        R_hasAttrib(col, R_ClassSymbol) &&
        R_hasAttrib(col, Rf_install("stata.storage"));
}

struct probe_attr_search { SEXP symbol, value; };
static SEXP probe_attr_visit(SEXP symbol, SEXP value, void *context) {
    struct probe_attr_search *search = (struct probe_attr_search *) context;
    if (symbol != search->symbol) return NULL;
    search->value = value;
    return value;
}

/* R_mapAttrib walks raw attributes without constructing attributes(). */
static SEXP probe_raw_attribute(SEXP value, SEXP symbol) {
    struct probe_attr_search search = { symbol, R_NilValue };
    R_mapAttrib(value, probe_attr_visit, &search);
    return search.value;
}

typedef struct {
    int count;
    SEXP tags[4], values[4];
} probe_table_attrs;

static SEXP probe_collect_table_attr(SEXP tag, SEXP value, void *context) {
    probe_table_attrs *seen = (probe_table_attrs *) context;
    if (seen->count < 4) {
        seen->tags[seen->count] = tag;
        seen->values[seen->count] = value;
    }
    seen->count++;
    return NULL;
}

/* R_mapAttrib walks the raw pairlist and calls only this C visitor. */
static int probe_table_attrs_read(SEXP data, probe_table_attrs *out) {
    out->count = 0;
    return R_mapAttrib(data, probe_collect_table_attr, out) == NULL &&
        out->count == 4;
}

static int probe_name_prefix_same(SEXP data, SEXP published_names,
                                  R_xlen_t width) {
    SEXP current = probe_raw_attribute(data, R_NamesSymbol);
    if (TYPEOF(current) != STRSXP || ALTREP(current) ||
        XLENGTH(current) != width ||
        TYPEOF(published_names) != STRSXP || ALTREP(published_names) ||
        XLENGTH(published_names) < width) return 0;
    for (R_xlen_t j = 0; j < width; j++)
        if (STRING_ELT(current, j) != STRING_ELT(published_names, j))
            return 0;
    return 1;
}

/* Construct the same shallow column and table metadata context as
   .begin_dibble_result before group planning. */
typedef struct {
    SEXP values;
    SEXP names;
    int count;
} probe_context_attrs;

static SEXP probe_context_attr_visit(SEXP tag, SEXP value, void *context) {
    probe_context_attrs *attrs = (probe_context_attrs *) context;
    if (attrs->count < 32) {
        SET_VECTOR_ELT(attrs->values, attrs->count, value);
        SET_STRING_ELT(attrs->names, attrs->count, PRINTNAME(tag));
    }
    attrs->count++;
    return NULL;
}

SEXP C_dtatools_grouped_begin_context(SEXP data) {
    if (TYPEOF(data) != VECSXP || ALTREP(data) ||
        !Rf_inherits(data, "dibble")) return R_NilValue;
    R_xlen_t width = XLENGTH(data);
    if (width < 2 || width > 256) return R_NilValue;
    SEXP columns = PROTECT(Rf_allocVector(VECSXP, width));
    for (R_xlen_t j = 0; j < width; j++)
        SET_VECTOR_ELT(columns, j, VECTOR_ELT(data, j));
    SEXP column_names = Rf_getAttrib(data, R_NamesSymbol);
    if (TYPEOF(column_names) != STRSXP || XLENGTH(column_names) != width) {
        UNPROTECT(1); return R_NilValue;
    }
    Rf_setAttrib(columns, R_NamesSymbol, column_names);

    SEXP raw_values = PROTECT(Rf_allocVector(VECSXP, 32));
    SEXP raw_names = PROTECT(Rf_allocVector(STRSXP, 32));
    probe_context_attrs attrs = {raw_values, raw_names, 0};
    if (R_mapAttrib(data, probe_context_attr_visit, &attrs) != NULL ||
        attrs.count < 3 || attrs.count > 32) {
        UNPROTECT(3); return R_NilValue;
    }
    int retained = 0, class_index = -1, row_index = -1;
    for (int i = 0; i < attrs.count; i++)
        if (strcmp(CHAR(STRING_ELT(raw_names, i)), ".dtatools_ref_state"))
            retained++;
    SEXP metadata = PROTECT(Rf_allocVector(VECSXP, retained));
    SEXP metadata_names = PROTECT(Rf_allocVector(STRSXP, retained));
    for (int i = 0, j = 0; i < attrs.count; i++) {
        SEXP label = STRING_ELT(raw_names, i);
        if (!strcmp(CHAR(label), ".dtatools_ref_state")) continue;
        SET_STRING_ELT(metadata_names, j, label);
        SET_VECTOR_ELT(metadata, j, VECTOR_ELT(raw_values, i));
        if (!strcmp(CHAR(label), "class")) class_index = j;
        if (!strcmp(CHAR(label), "row.names")) row_index = j;
        j++;
    }
    if (class_index < 0 || row_index < 0) {
        UNPROTECT(5); return R_NilValue;
    }
    Rf_setAttrib(metadata, R_NamesSymbol, metadata_names);
    /* Ordinary begin reads class(data) after attributes(data). */
    SEXP classes = Rf_getAttrib(data, R_ClassSymbol);
    if (TYPEOF(classes) != STRSXP || ALTREP(classes)) {
        UNPROTECT(5); return R_NilValue;
    }
    int base_count = 0;
    for (R_xlen_t i = 0; i < XLENGTH(classes); i++) {
        const char *name = CHAR(STRING_ELT(classes, i));
        if (strcmp(name, "dibble") && strcmp(name, "dtatools_ref_data"))
            base_count++;
    }
    SEXP base_classes = PROTECT(Rf_allocVector(STRSXP, base_count));
    for (R_xlen_t i = 0, j = 0; i < XLENGTH(classes); i++) {
        SEXP label = STRING_ELT(classes, i);
        const char *name = CHAR(label);
        if (strcmp(name, "dibble") && strcmp(name, "dtatools_ref_data"))
            SET_STRING_ELT(base_classes, j++, label);
    }
    SET_VECTOR_ELT(metadata, class_index, base_classes);
    /* The ordinary row-info call requests the compact raw representation. */
    SET_VECTOR_ELT(metadata, row_index,
                   probe_raw_attribute(data, R_RowNamesSymbol));
    SEXP context = PROTECT(Rf_allocVector(VECSXP, 4));
    SEXP context_names = PROTECT(Rf_allocVector(STRSXP, 4));
    SET_STRING_ELT(context_names, 0, Rf_mkChar("columns"));
    SET_STRING_ELT(context_names, 1, Rf_mkChar("metadata"));
    SET_STRING_ELT(context_names, 2, Rf_mkChar("caller"));
    SET_STRING_ELT(context_names, 3, Rf_mkChar("operation"));
    SET_VECTOR_ELT(context, 0, columns);
    SET_VECTOR_ELT(context, 1, metadata);
    SET_VECTOR_ELT(context, 2, Rf_mkString("mutate()"));
    SET_VECTOR_ELT(context, 3, Rf_mkString("computed"));
    Rf_setAttrib(context, R_NamesSymbol, context_names);
    UNPROTECT(8);
    return context;
}

static int probe_canonical_table_values(SEXP data, R_xlen_t n) {
    SEXP classes = probe_raw_attribute(data, R_ClassSymbol);
    SEXP rows = probe_raw_attribute(data, R_RowNamesSymbol);
    static const char *expected[] = {
        "dibble", "dtatools_ref_data", "tbl_df", "tbl", "data.frame"
    };
    if (TYPEOF(classes) != STRSXP || ALTREP(classes) ||
        XLENGTH(classes) != 5 || TYPEOF(rows) != INTSXP ||
        ALTREP(rows) || XLENGTH(rows) != 2 ||
        INTEGER(rows)[0] != NA_INTEGER || INTEGER(rows)[1] != -(int)n)
        return 0;
    for (int i=0;i<5;i++)
        if (strcmp(CHAR(STRING_ELT(classes,i)), expected[i])) return 0;
    return 1;
}

static int probe_frozen_group_snapshot_same(SEXP group, const double *snapshot,
                                            R_xlen_t n) {
    if (!ALTREP(group) ||
        !R_altrep_inherits(group, dtatools_metadata_real_class) ||
        R_altrep_data2(group) != R_NilValue) return 0;
    SEXP source = metadata_proxy_source(group);
    if (!ALTREP(source) ||
        !R_altrep_inherits(source, dtatools_numeric_class)) return 0;
    double block[256];
    for (R_xlen_t row = 0; row < n; row += 256) {
        R_xlen_t count = n - row < 256 ? n - row : 256;
        if (REAL_GET_REGION(group, row, count, block) != count ||
            memcmp(block, snapshot + row, (size_t) count * sizeof(double)))
            return 0;
    }
    return 1;
}

static int probe_reference_valid_noalloc(SEXP data) {
    SEXP state = probe_raw_attribute(data, Rf_install(".dtatools_ref_state"));
    if (TYPEOF(state) != ENVSXP) return 0;
    SEXP symbol = Rf_install("owner");
    R_BindingType_t type = R_GetBindingType(symbol, state);
    if (type != R_BindingTypeValue && type != R_BindingTypeForced) return 0;
    SEXP owner = R_getVar(symbol, state, FALSE);
    return TYPEOF(owner) == EXTPTRSXP && R_ExternalPtrAddr(owner) == data;
}

static SEXP probe_dplyr_early_impl(SEXP data, SEXP mode_arg,
                                    SEXP source_symbol, SEXP group_symbol,
                                    SEXP target_names,
                                    SEXP captured_columns) {
    int mode = Rf_asInteger(mode_arg);
    int shape = mode % 10;
    R_xlen_t width = XLENGTH(data);
    if ((mode != 11 && mode != 15) ||
        TYPEOF(captured_columns) != VECSXP || ALTREP(captured_columns) ||
        XLENGTH(captured_columns) != width ||
        TYPEOF(data) != VECSXP || !Rf_inherits(data, "dibble") ||
        !dtatools_reference_state_valid_noalloc(data) ||
        (width < 2 || width > 256)) return R_NilValue;
    SEXP names = Rf_getAttrib(captured_columns, R_NamesSymbol);
    SEXP classes = Rf_getAttrib(data, R_ClassSymbol);
    R_xlen_t source_index = width, group_index = width;
    if (TYPEOF(names) != STRSXP || ALTREP(names) ||
        XLENGTH(names) != width ||
        TYPEOF(classes) != STRSXP || ALTREP(classes) ||
        XLENGTH(classes) != 5 ||
        strcmp(CHAR(STRING_ELT(classes, 0)), "dibble") ||
        strcmp(CHAR(STRING_ELT(classes, 1)), "dtatools_ref_data") ||
        strcmp(CHAR(STRING_ELT(classes, 2)), "tbl_df") ||
        strcmp(CHAR(STRING_ELT(classes, 3)), "tbl") ||
        strcmp(CHAR(STRING_ELT(classes, 4)), "data.frame")) return R_NilValue;
    if (TYPEOF(source_symbol) != SYMSXP ||
        TYPEOF(group_symbol) != SYMSXP ||
        source_symbol == group_symbol ||
        TYPEOF(target_names) != STRSXP || ALTREP(target_names) ||
        XLENGTH(target_names) != shape) return R_NilValue;
    for (R_xlen_t j = 0; j < width; j++) {
        SEXP item = STRING_ELT(names, j);
        if (!strcmp(CHAR(item), CHAR(PRINTNAME(source_symbol))))
            source_index = j;
        if (!strcmp(CHAR(item), CHAR(PRINTNAME(group_symbol))))
            group_index = j;
    }
    if (source_index == width || group_index == width) return R_NilValue;
    for (R_xlen_t j = 0; j < shape; j++) {
        SEXP item = STRING_ELT(target_names, j);
        if (item == NA_STRING || !CHAR(item)[0]) return R_NilValue;
        for (const unsigned char *p = (const unsigned char *) CHAR(item);
             *p; ++p) if (*p >= 128) return R_NilValue;
        for (R_xlen_t k = 0; k < j; k++)
            if (!strcmp(CHAR(STRING_ELT(target_names, k)), CHAR(item)))
                return R_NilValue;
    }
    SEXP keys = PROTECT(R_getAttribNames(data));
    int attr_valid = TYPEOF(keys) == STRSXP && XLENGTH(keys) == 4;
    int seen[4] = {0};
    static const char *required[] = {
        "names", "row.names", "class", ".dtatools_ref_state"
    };
    for (R_xlen_t i = 0; attr_valid && i < XLENGTH(keys); i++) {
        int found = 0;
        for (int j = 0; j < 4; j++) {
            if (!strcmp(CHAR(STRING_ELT(keys, i)), required[j])) {
                seen[j]++;
                found = 1;
                break;
            }
        }
        if (!found) attr_valid = 0;
    }
    UNPROTECT(1);
    for (int i = 0; i < 4; i++) if (seen[i] != 1) attr_valid = 0;
    if (!attr_valid) return R_NilValue;
    const char *seen_names[512] = {NULL};
    uint64_t seen_hashes[512] = {0};
    for (R_xlen_t j = 0; j < width; j++) {
        SEXP item = STRING_ELT(names, j);
        if (item == NA_STRING || !CHAR(item)[0]) return R_NilValue;
        const char *label = CHAR(item);
        for (R_xlen_t k = 0; k < shape; k++)
            if (!strcmp(label, CHAR(STRING_ELT(target_names, k))))
                return R_NilValue;
        uint64_t hash = UINT64_C(14695981039346656037);
        for (const unsigned char *p = (const unsigned char *) label;
             *p; ++p) {
            if (*p >= 128) return R_NilValue;
            hash = (hash ^ *p) * UINT64_C(1099511628211);
        }
        unsigned int slot = (unsigned int) hash & 511U;
        while (seen_names[slot] != NULL) {
            if (seen_hashes[slot] == hash &&
                strcmp(seen_names[slot], label) == 0)
                return R_NilValue;
            slot = (slot + 1U) & 511U;
        }
        seen_names[slot] = label;
        seen_hashes[slot] = hash;
    }
    SEXP capture_source = captured_columns;
    SEXP x = VECTOR_ELT(capture_source, source_index),
         g = VECTOR_ELT(capture_source, group_index);
    if (!owned_real(x) || !ALTREP(g) ||
        !R_altrep_inherits(g, dtatools_numeric_class) ||
        R_altrep_data2(g) != R_NilValue) {
        return R_NilValue;
    }
    R_xlen_t n = XLENGTH(x);
    if (n > INT_MAX) return R_NilValue;
    if (!typed(x, n, "dta_double", "double")) {
        return R_NilValue;
    }
    if (!typed(g, n, "dta_long", "long")) {
        return R_NilValue;
    }
    for (R_xlen_t j = 0; j < width; j++) {
        if (j == source_index || j == group_index) continue;
        SEXP column = VECTOR_ELT(capture_source, j);
        if (!owned_real(column) ||
            !typed(column, n, "dta_double", "double")) return R_NilValue;
    }
    /* Capture the shallow column and table metadata state before planning
       groups, matching the ordinary begin-result order. */
    R_xlen_t outputs = shape;
    R_xlen_t total = width + outputs;
    SEXP source_columns = PROTECT(captured_columns);
    SEXP source_classes = PROTECT(Rf_allocVector(VECSXP, width));
    SEXP source_storages = PROTECT(Rf_allocVector(VECSXP, width));
    SEXP backings = PROTECT(Rf_allocVector(VECSXP, outputs));
    if (VECTOR_ELT(capture_source, source_index) != x ||
        VECTOR_ELT(capture_source, group_index) != g) {
        UNPROTECT(4); return R_NilValue;
    }
    for (R_xlen_t j = 0; j < width; j++) {
        SEXP column = VECTOR_ELT(capture_source, j);
        if (j != group_index && !owned_real(column)) {
            UNPROTECT(4); return R_NilValue;
        }
        if (!typed(column, n, j == group_index ? "dta_long" : "dta_double",
                   j == group_index ? "long" : "double")) {
            UNPROTECT(4); return R_NilValue;
        }
        SET_VECTOR_ELT(source_classes, j, probe_raw_attribute(column, R_ClassSymbol));
        SET_VECTOR_ELT(source_storages, j,
                       probe_raw_attribute(column, Rf_install("stata.storage")));
    }
    probe_table_attrs saved_table_attrs;
    if (!probe_table_attrs_read(data, &saved_table_attrs)) {
        UNPROTECT(4); return R_NilValue;
    }
    /* Group planning reads physical data after the shallow capture, as the
       ordinary expression-group planner does. No materialization is needed. */
    SEXP group_snapshot = PROTECT(Rf_allocVector(REALSXP, n));
    /* Tidyselect resolves `.by` against the physical names at this phase.
       A rename after the shallow capture can remove or move the key, so
       continue the ordinary planner from the retained context instead. */
    if (!probe_name_prefix_same(data, names, width)) {
        UNPROTECT(5); return R_NilValue;
    }
    /* Ordinary group planning reads the physical table after begin-result
       retained its shallow column shell. That slot may now differ from the
       group's captured output handle. */
    SEXP planning_g = VECTOR_ELT(data, group_index);
    if (!ALTREP(planning_g) ||
                    !R_altrep_inherits(planning_g, dtatools_numeric_class) ||
                    R_altrep_data2(planning_g) != R_NilValue ||
                    !typed(planning_g, n, "dta_long", "long")) {
        UNPROTECT(5); return R_NilValue;
    }
    if (numeric_region(planning_g, 0, n, REAL(group_snapshot)) != n) {
        UNPROTECT(5); return R_NilValue;
    }
    const double *gp = REAL(group_snapshot);
    for (R_xlen_t row = 0; row < n; row++) {
        if ((row & 1023) == 0) R_CheckUserInterrupt();
        double key = gp[row];
        if (!R_FINITE(key) || key < 1 || key > INT_MAX ||
            key != (int) key) { UNPROTECT(5); return R_NilValue; }
    }
    SEXP out = PROTECT(Rf_allocVector(VECSXP, total));
    SEXP out_names = PROTECT(Rf_allocVector(STRSXP, total));
    for (R_xlen_t j = 0; j < width; j++) {
        SEXP fork = PROTECT(C_dtatools_metadata_copy(VECTOR_ELT(source_columns, j)));
        SET_VECTOR_ELT(out, j, fork);
        UNPROTECT(1);
        SET_STRING_ELT(out_names, j, STRING_ELT(names, j));
    }
    /* The output source fork already isolates values before the last GC.
       Read its owned backing, not the physical input handle. */
    const double *xp = (const double *) DATAPTR_RO(VECTOR_ELT(out, source_index));
    for (int output_index = 0; output_index < outputs; output_index++) {
        SEXP backing = PROTECT(Rf_allocVector(REALSXP, n));
        SET_VECTOR_ELT(backings, output_index, backing);
        SEXP col = PROTECT(owned_adopt_real(backing));
        SEXP storage = PROTECT(Rf_mkString("double"));
        Rf_setAttrib(col, Rf_install("stata.storage"), storage);
        SEXP col_classes = PROTECT(Rf_allocVector(STRSXP, 4));
        SET_STRING_ELT(col_classes, 0, Rf_mkChar("dta_numeric"));
        SET_STRING_ELT(col_classes, 1, Rf_mkChar("dta_double"));
        SET_STRING_ELT(col_classes, 2, Rf_mkChar("vctrs_vctr"));
        SET_STRING_ELT(col_classes, 3, Rf_mkChar("double"));
        Rf_setAttrib(col, R_ClassSymbol, col_classes);
        R_xlen_t target = width + output_index;
        SET_VECTOR_ELT(out, target, col);
        SET_STRING_ELT(out_names, target,
                       STRING_ELT(target_names, output_index));
        UNPROTECT(4);
    }
    /* Preserve the table metadata captured before group planning. The
       physical table can acquire new attributes while output forks allocate. */
    SEXP ref_symbol = Rf_install(".dtatools_ref_state");
    for (int i = 0; i < saved_table_attrs.count; i++) {
        SEXP tag = saved_table_attrs.tags[i];
        if (tag == ref_symbol) continue;
        Rf_setAttrib(out, tag,
                     tag == R_NamesSymbol ? out_names : saved_table_attrs.values[i]);
    }
    SEXP capacity = PROTECT(Rf_ScalarReal((double) total + 1024));
    SEXP prepared = PROTECT(C_dtatools_reserve_column_capacity(out, capacity));
    SEXP state = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, 29));
    SEXP base_classes = PROTECT(Rf_allocVector(STRSXP, 3));
    for (int i = 0; i < 3; i++)
        SET_STRING_ELT(base_classes, i, STRING_ELT(classes, i + 2));
    Rf_defineVar(Rf_install("classes"), base_classes, state);
    C_dtatools_mark_reference_data(prepared, state, classes);

    /* Last possible R callback. Everything below only reads existing cells,
       writes private numeric payloads, and returns an already-built result. */
    R_CheckUserInterrupt();
    /* The prepared table owns its column and metadata forks. A finalizer can
       modify the physical input after this capture, just as it can after the
       ordinary mask capture; publication must read only the frozen result. */
    if (!probe_public_bindings_same(0) ||
        !dtatools_reference_state_valid_noalloc(prepared) ||
        !probe_name_prefix_same(prepared, out_names, total) ||
        !probe_canonical_table_values(prepared, n)) {
        UNPROTECT(11); return R_NilValue;
    }
    for (R_xlen_t j = 0; j < width; j++) {
        SEXP column = VECTOR_ELT(prepared, j);
        if (TYPEOF(column) != REALSXP ||
            probe_raw_attribute(column, R_ClassSymbol) != VECTOR_ELT(source_classes, j) ||
            probe_raw_attribute(column, Rf_install("stata.storage")) !=
                VECTOR_ELT(source_storages, j) ||
            !typed(column, n, j == group_index ? "dta_long" : "dta_double",
                   j == group_index ? "long" : "double")) {
            UNPROTECT(11); return R_NilValue;
        }
    }
    if (planning_g == g &&
        !probe_frozen_group_snapshot_same(VECTOR_ELT(prepared, group_index),
                                          REAL(group_snapshot), n)) {
        UNPROTECT(11); return R_NilValue;
    }
    for (int output_index = 0; output_index < outputs; output_index++) {
        SEXP backing = VECTOR_ELT(backings, output_index);
        SEXP col = VECTOR_ELT(prepared, width + output_index);
        double *values = REAL(backing);
        int no_missing = 1;
        for (R_xlen_t row = 0; row < n; row++) {
            double value = xp[row] + 1.0;
            int valid = value >= -DBL_MAX / 2 && value <= DBL_MAX / 2;
            values[row] = valid ? value : NA_REAL;
            no_missing &= valid;
        }
        owned_flags(col)[OWNED_NO_NA] = no_missing;
    }
    UNPROTECT(11);
    return prepared;
}

static int probe_literal(SEXP value, double expected) {
    return TYPEOF(value) == REALSXP && !ALTREP(value) &&
        !ANY_ATTRIB(value) && XLENGTH(value) == 1 &&
        REAL(value)[0] == expected;
}

/* Accept a direct source-column plus one expression. */
static SEXP probe_arithmetic_source(SEXP expression) {
    if (TYPEOF(expression) != LANGSXP || ANY_ATTRIB(expression) ||
        CAR(expression) != Rf_install("+"))
        return R_NilValue;
    SEXP first = CDR(expression);
    if (first == R_NilValue || CDR(first) == R_NilValue ||
        CDR(CDR(first)) != R_NilValue) return R_NilValue;
    if (ANY_ATTRIB(first) || TAG(first) != R_NilValue ||
        ANY_ATTRIB(CDR(first)) || TAG(CDR(first)) != R_NilValue ||
        TYPEOF(CAR(first)) != SYMSXP ||
        !probe_literal(CADR(first), 1.0)) return R_NilValue;
    return CAR(first);
}

static SEXP probe_captured_expression(SEXP quo) {
    if (TYPEOF(quo) != LANGSXP || CAR(quo) != Rf_install("~") ||
        CDR(quo) == R_NilValue || CDR(CDR(quo)) != R_NilValue)
        return R_UnboundValue;
    SEXP classes = Rf_getAttrib(quo, R_ClassSymbol);
    SEXP environment = Rf_getAttrib(quo, Rf_install(".Environment"));
    if (TYPEOF(classes) != STRSXP || XLENGTH(classes) != 2 ||
        strcmp(CHAR(STRING_ELT(classes, 0)), "quosure") ||
        strcmp(CHAR(STRING_ELT(classes, 1)), "formula") ||
        TYPEOF(environment) != ENVSXP) return R_UnboundValue;
    return CADR(quo);
}

static SEXP probe_captured_environment(SEXP quo) {
    if (probe_captured_expression(quo) == R_UnboundValue)
        return R_UnboundValue;
    return Rf_getAttrib(quo, Rf_install(".Environment"));
}

/* Operator lookup must resolve from the captured quosure environment. */
static int probe_captured_operator(SEXP quo) {
    SEXP env = probe_captured_environment(quo);
    if (env == R_UnboundValue || pointer_guard_operators == NULL) return 0;
    static const char *methods[] = {
        "+.dta_numeric", "Ops.dta_numeric", "+.vctrs_vctr",
        "vec_arith.dta_numeric", "vec_arith.dta_numeric.numeric",
        "vec_arith.numeric.dta_numeric"
    };
    for (SEXP frame = env; frame != R_EmptyEnv && frame != R_BaseEnv;
         frame = R_ParentEnv(frame)) {
        if (TYPEOF(frame) != ENVSXP) return 0;
        for (int i = 0; i < 6; i++) {
            if (R_GetBindingType(Rf_install(methods[i]), frame) !=
                R_BindingTypeUnbound) return 0;
        }
    }
    return dtatools_execution_lexical_function_same(
        env, Rf_install("+"), VECTOR_ELT(pointer_guard_operators, 0));
}

SEXP C_dtatools_grouped_entry(SEXP data, SEXP dots, SEXP by,
                                   SEXP captured_dots, SEXP captured_by,
                                   SEXP captured_columns) {
    if (!grouped_probe_enabled) return R_NilValue;
    if (TYPEOF(dots) != LANGSXP || CAR(dots) != Rf_install("list"))
        return R_NilValue;
    if (TYPEOF(captured_dots) != VECSXP ||
        XLENGTH(captured_dots) != Rf_length(CDR(dots))) return R_NilValue;
    SEXP captured_names = Rf_getAttrib(captured_dots, R_NamesSymbol);
    SEXP captured_classes = Rf_getAttrib(captured_dots, R_ClassSymbol);
    if (TYPEOF(captured_names) != STRSXP ||
        XLENGTH(captured_names) != XLENGTH(captured_dots) ||
        TYPEOF(captured_classes) != STRSXP || XLENGTH(captured_classes) != 2 ||
        strcmp(CHAR(STRING_ELT(captured_classes, 0)), "quosures") ||
        strcmp(CHAR(STRING_ELT(captured_classes, 1)), "list")) return R_NilValue;
    SEXP captured_by_expr = probe_captured_expression(captured_by);
    if (captured_by_expr == R_UnboundValue || captured_by_expr != by)
        return R_NilValue;
    if (TYPEOF(by) != SYMSXP ||
        TYPEOF(captured_columns) != VECSXP ||
        ALTREP(captured_columns) ||
        XLENGTH(captured_columns) != XLENGTH(data))
        return R_NilValue;
    SEXP args = CDR(dots);
    int count = 0;
    SEXP arithmetic_source = R_NilValue;
    for (SEXP node = args; node != R_NilValue; node = CDR(node)) {
        SEXP name = TAG(node);
        SEXP original = CAR(node);
        SEXP captured = probe_captured_expression(VECTOR_ELT(captured_dots, count));
        SEXP original_source = probe_arithmetic_source(original);
        SEXP captured_source = probe_arithmetic_source(captured);
        int same_shape = original_source != R_NilValue &&
            original_source == captured_source;
        if (count >= XLENGTH(captured_dots) || TYPEOF(name) != SYMSXP ||
            STRING_ELT(captured_names, count) == NA_STRING ||
            strcmp(CHAR(STRING_ELT(captured_names, count)), CHAR(PRINTNAME(name))) ||
            !same_shape) return R_NilValue;
        if (original_source != R_NilValue) {
            if (arithmetic_source != R_NilValue &&
                arithmetic_source != original_source) return R_NilValue;
            arithmetic_source = original_source;
        }
        count++;
    }
    int mode = -1;
    if (count == 1) {
        if (arithmetic_source != R_NilValue) mode = 11;
    } else if (count == 5) {
        int matching = 1;
        SEXP node = args;
        for (int index = 1; index <= 5; index++, node = CDR(node)) {
            if (TYPEOF(TAG(node)) != SYMSXP ||
                probe_arithmetic_source(CAR(node)) != arithmetic_source) {
                matching = 0;
                break;
            }
        }
        if (matching && arithmetic_source != R_NilValue) mode = 15;
    }
    if (mode < 0) return R_NilValue;
    for (int index = 0; index < count; index++)
        if (!probe_captured_operator(VECTOR_ELT(captured_dots, index)))
            return R_NilValue;
    /* Grouped producer: this producer executes no public
       R callback before its final guard. A finalizer during preparation can
       change a dependency, which that guard checks before publication. */
    SEXP mode_value = PROTECT(Rf_ScalarInteger(mode));
    SEXP result = probe_dplyr_early_impl(data, mode_value, arithmetic_source,
                                          by, captured_names, captured_columns);
    UNPROTECT(1);
    return result;
}
