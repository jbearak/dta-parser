/* Source-qualified native ungrouped mutate for canonical owned dibbles. */
#include "dtatools-internal.h"
#include <string.h>
#include <stdint.h>
#include <float.h>
#include <math.h>
#include <R_ext/Memory.h>
#include <Rversion.h>
#if defined(__aarch64__)
#include <arm_neon.h>
#endif
#define grouped_source_qualification ungrouped_source_qualification
#include "grouped-public-code-qualify.inc"
extern int RDEBUG(SEXP);
extern SEXP R_PromiseExpr(SEXP);
extern SEXP PRENV(SEXP);

static int attempts = 0, admitted = 0, published = 0;
/* A failed optional load-time qualification leaves this route disabled. */
static int mutate_probe_enabled = 0;
static SEXP pointer_guard_operators = NULL;
static SEXP public_guard_roots = NULL;
static SEXP public_guard_states = NULL;
static SEXP public_guard_symbols = NULL;
static SEXP absent_guard_roots = NULL;
static SEXP absent_guard_symbols = NULL;
static SEXP active_expected = NULL;
static SEXP publication_gc_root = NULL;
static int publication_gc_after_fork = -1;
typedef struct {
    SEXP env, symbol, expected, frozen, state;
    SEXP body, closure_env, formals;
    int visible_source;
} probe_public_root_entry;
static probe_public_root_entry *public_guard_cache = NULL;
void dtatools_probe_release_public_cache(void) {
    if (public_guard_cache != NULL) {
        R_Free(public_guard_cache);
        public_guard_cache = NULL;
    }
    if (public_guard_roots != NULL) R_ReleaseObject(public_guard_roots);
    if (public_guard_states != NULL) R_ReleaseObject(public_guard_states);
    if (absent_guard_roots != NULL) R_ReleaseObject(absent_guard_roots);
    if (absent_guard_symbols != NULL) R_ReleaseObject(absent_guard_symbols);
    if (pointer_guard_operators != NULL) R_ReleaseObject(pointer_guard_operators);
    if (publication_gc_root != NULL) R_ReleaseObject(publication_gc_root);
}
SEXP C_dtatools_probe_mutate_mode(SEXP enabled) {
    int old = mutate_probe_enabled;
    if (enabled != R_NilValue) {
        if (TYPEOF(enabled) != LGLSXP || XLENGTH(enabled) != 1 ||
            LOGICAL(enabled)[0] == NA_LOGICAL)
            Rf_error("invalid mutate probe mode");
        mutate_probe_enabled = LOGICAL(enabled)[0];
    }
    return Rf_ScalarLogical(old);
}

SEXP C_dtatools_probe_arm_publication_gc(SEXP value) {
    if (publication_gc_root != NULL || TYPEOF(value) != ENVSXP)
        return Rf_ScalarLogical(FALSE);
    R_PreserveObject(value);
    publication_gc_root = value;
    return Rf_ScalarLogical(TRUE);
}
SEXP C_dtatools_probe_fork_gc_index(SEXP value) {
    int old = publication_gc_after_fork;
    if (value != R_NilValue) {
        if (TYPEOF(value) != INTSXP || XLENGTH(value) != 1 ||
            INTEGER(value)[0] < -1 || INTEGER(value)[0] > 256)
            Rf_error("invalid fork GC index");
        publication_gc_after_fork = INTEGER(value)[0];
    }
    return Rf_ScalarInteger(old);
}

SEXP C_dtatools_probe_pin_operators(SEXP operators) {
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
SEXP C_dtatools_probe_pin_absent(SEXP roots) {
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
        if (R_GetBindingType(symbol, VECTOR_ELT(entry, 0)) !=
                R_BindingTypeUnbound ||
            R_GetBindingType(symbol, R_GlobalEnv) != R_BindingTypeUnbound) {
            UNPROTECT(1); return Rf_ScalarLogical(FALSE);
        }
        SET_VECTOR_ELT(symbols, i, symbol);
    }
    R_PreserveObject(roots);
    R_PreserveObject(symbols);
    absent_guard_roots = roots;
    absent_guard_symbols = symbols;
    UNPROTECT(1);
    return Rf_ScalarLogical(TRUE);
}
static int probe_absent_bindings_same(void) {
    if (absent_guard_roots == NULL || absent_guard_symbols == NULL)
        return 0;
    for (R_xlen_t i = 0; i < XLENGTH(absent_guard_roots); i++) {
        SEXP symbol = VECTOR_ELT(absent_guard_symbols, i);
        SEXP table = VECTOR_ELT(VECTOR_ELT(absent_guard_roots, i), 0);
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
        TYPEOF(state) != VECSXP || XLENGTH(state) != 6 ||
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


SEXP C_dtatools_probe_pin_public(SEXP functions) {
    if (public_guard_roots != NULL || TYPEOF(functions) != VECSXP ||
        XLENGTH(functions) < 1) return Rf_ScalarLogical(FALSE);
    SEXP states = PROTECT(Rf_allocVector(VECSXP, XLENGTH(functions) + 1));
    SEXP symbols = PROTECT(Rf_allocVector(VECSXP, XLENGTH(functions)));
    SET_VECTOR_ELT(states, XLENGTH(functions), symbols);
    UNPROTECT(1);
    SEXP found_active = NULL;
    for (R_xlen_t i = 0; i < XLENGTH(functions); i++) {
        SEXP entry = VECTOR_ELT(functions, i);
        if (TYPEOF(entry) != VECSXP ||
            (XLENGTH(entry) != 3 && XLENGTH(entry) != 4)) {
            UNPROTECT(1);
            return Rf_ScalarLogical(FALSE);
        }
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
        R_BindingType_t type = R_GetBindingType(symbol, env);
        if ((type != R_BindingTypeValue && type != R_BindingTypeForced) ||
            R_getVar(symbol, env, FALSE) != expected) {
            UNPROTECT(1); return Rf_ScalarLogical(FALSE);
        }
        if (XLENGTH(entry) == 4) {
            SEXP flags = PROTECT(ungrouped_source_qualification(
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
                UNPROTECT(2);
                return Rf_ScalarLogical(FALSE);
            }
            UNPROTECT(1);
            SEXP frozen = VECTOR_ELT(entry, 3);
            SEXP state = PROTECT(Rf_allocVector(VECSXP, 6));
            SET_VECTOR_ELT(state, 0, R_ClosureBody(expected));
            SET_VECTOR_ELT(state, 1, R_ClosureEnv(expected));
            SET_VECTOR_ELT(state, 2, body_source_file(R_ClosureExpr(expected)));
            SET_VECTOR_ELT(state, 3, body_source_file(R_ClosureExpr(frozen)));
            SET_VECTOR_ELT(state, 4, R_ClosureFormals(expected));
            SET_VECTOR_ELT(state, 5, Rf_ScalarLogical(visible_fallback));
            if (!probe_public_fresh_state(expected, frozen, state)) {
                UNPROTECT(2); return Rf_ScalarLogical(FALSE);
            }
            SET_VECTOR_ELT(states, i, state);
            if (symbol == Rf_install("mutate.dibble")) {
                found_active = expected;
            }
            UNPROTECT(1);
        }
    }
    if (found_active == NULL) {
        UNPROTECT(1);
        return Rf_ScalarLogical(FALSE);
    }
    active_expected = found_active;
    R_PreserveObject(functions);
    R_PreserveObject(states);
    probe_public_root_entry *cache = R_Calloc(XLENGTH(functions),
                                             probe_public_root_entry);
    for (R_xlen_t i = 0; i < XLENGTH(functions); i++) {
        SEXP entry = VECTOR_ELT(functions, i);
        SEXP state = VECTOR_ELT(states, i);
        cache[i].env = VECTOR_ELT(entry, 0);
        cache[i].symbol = VECTOR_ELT(symbols, i);
        cache[i].expected = VECTOR_ELT(entry, 2);
        cache[i].frozen = XLENGTH(entry) == 4 ? VECTOR_ELT(entry, 3) : R_NilValue;
        cache[i].state = state;
        if (TYPEOF(state) == VECSXP) {
            cache[i].body = VECTOR_ELT(state, 0);
            cache[i].closure_env = VECTOR_ELT(state, 1);
            cache[i].formals = VECTOR_ELT(state, 4);
            cache[i].visible_source = LOGICAL(VECTOR_ELT(state, 5))[0];
        }
    }
    public_guard_roots = functions;
    public_guard_states = states;
    public_guard_symbols = symbols;
    public_guard_cache = cache;
    UNPROTECT(1);
    return Rf_ScalarLogical(TRUE);
}

static int probe_public_bindings_same(void) {
    if (public_guard_roots == NULL || public_guard_states == NULL ||
        public_guard_symbols == NULL || public_guard_cache == NULL ||
        !probe_absent_bindings_same()) return 0;
    for (R_xlen_t i = 0; i < XLENGTH(public_guard_roots); i++) {
        probe_public_root_entry *entry = &public_guard_cache[i];
        R_BindingType_t type = R_GetBindingType(entry->symbol, entry->env);
        if (type != R_BindingTypeValue && type != R_BindingTypeForced)
            return 0;
        SEXP actual = R_getVar(entry->symbol, entry->env, FALSE);
        if (actual != entry->expected) return 0;
        if (TYPEOF(actual) == CLOSXP) {
            if (TYPEOF(entry->state) != VECSXP ||
                probe_public_debug_or_step(actual) ||
                R_ClosureBody(actual) != entry->body ||
                R_ClosureEnv(actual) != entry->closure_env ||
                R_ClosureFormals(actual) != entry->formals)
                return 0;
            if (entry->visible_source &&
                (!probe_public_visible_source_same(actual, entry->frozen) ||
                 !probe_public_srcref_same(actual, entry->frozen,
                                           entry->state))) return 0;
        }
    }
    return 1;
}
SEXP C_dtatools_probe_guard_public(SEXP ignored) {
    (void) ignored;
    return Rf_ScalarLogical(probe_public_bindings_same());
}

SEXP C_dtatools_probe_dplyr_early_stats(SEXP reset) {
    SEXP out = PROTECT(Rf_allocVector(INTSXP, 3));
    INTEGER(out)[0] = attempts;
    INTEGER(out)[1] = admitted;
    INTEGER(out)[2] = published;
    if (Rf_asLogical(reset)) attempts = admitted = published = 0;
    UNPROTECT(1);
    return out;
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

static int ungrouped_column(SEXP col, R_xlen_t n) {
    return (owned_real(col) && typed(col, n, "dta_double", "double")) ||
        (TYPEOF(col) == REALSXP && ALTREP(col) &&
         R_altrep_inherits(col, dtatools_numeric_class) &&
         R_altrep_data2(col) == R_NilValue &&
         typed(col, n, "dta_long", "long"));
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

static int probe_table_attrs_same(SEXP data, const probe_table_attrs *saved) {
    probe_table_attrs now;
    if (!probe_table_attrs_read(data, &now)) return 0;
    for (int i = 0; i < 4; i++)
        if (now.tags[i] != saved->tags[i] ||
            now.values[i] != saved->values[i]) return 0;
    return 1;
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

/* The ordinary result constructor uses this option as spare capacity. A
   different or malformed value belongs to its R validation path. */
static int probe_default_alloccol_option(void) {
    SEXP option = Rf_GetOption1(Rf_install("dtatools.alloccol"));
    if (option == R_NilValue) return 1;
    if ((TYPEOF(option) != INTSXP && TYPEOF(option) != REALSXP) ||
        ALTREP(option) || ANY_ATTRIB(option) || XLENGTH(option) != 1)
        return 0;
    if (TYPEOF(option) == INTSXP) return INTEGER(option)[0] == 1024;
    if (TYPEOF(option) == REALSXP) return REAL(option)[0] == 1024.0;
    return 0;
}

static SEXP probe_dplyr_early_config(SEXP data, int mode,
                                      SEXP source_symbol, SEXP target_symbol,
                                      double offset, int general_create) {
    attempts++;
    int shape = mode;
    int constant = shape == 6 || shape == 7;
    R_xlen_t width = XLENGTH(data);
    if ((mode != 0 && mode != 1 && mode != 5 && mode != 6 && mode != 7) ||
        general_create != (mode == 1 || mode == 5) ||
        TYPEOF(data) != VECSXP || !Rf_inherits(data, "dibble") ||
        !dtatools_reference_state_valid_noalloc(data) ||
        !probe_default_alloccol_option() ||
        (width < 2 || width > 256)) return R_NilValue;
    SEXP names = Rf_getAttrib(data, R_NamesSymbol);
    SEXP classes = Rf_getAttrib(data, R_ClassSymbol);
    if (TYPEOF(names) != STRSXP || ALTREP(names) ||
        XLENGTH(names) != width ||
        TYPEOF(classes) != STRSXP || ALTREP(classes) ||
        XLENGTH(classes) != 5 ||
        strcmp(CHAR(STRING_ELT(classes, 0)), "dibble") ||
        strcmp(CHAR(STRING_ELT(classes, 1)), "dtatools_ref_data") ||
        strcmp(CHAR(STRING_ELT(classes, 2)), "tbl_df") ||
        strcmp(CHAR(STRING_ELT(classes, 3)), "tbl") ||
        strcmp(CHAR(STRING_ELT(classes, 4)), "data.frame")) return R_NilValue;
    R_xlen_t source_index = 0;
    R_xlen_t target_index = width;
    SEXP target_char = R_NilValue;
    if (general_create) {
        if ((mode != 1 && mode != 5) || TYPEOF(source_symbol) != SYMSXP ||
            !R_FINITE(offset) || offset < -1000000 || offset > 1000000)
            return R_NilValue;
        if (mode == 1) {
            if (TYPEOF(target_symbol) != SYMSXP) return R_NilValue;
            target_char = PRINTNAME(target_symbol);
            if (target_char == NA_STRING || !CHAR(target_char)[0]) return R_NilValue;
            for (const unsigned char *p =
                     (const unsigned char *) CHAR(target_char); *p; ++p)
                if (*p >= 128) return R_NilValue;
        } else {
            if (TYPEOF(target_symbol) != DOTSXP ||
                Rf_length(target_symbol) != 5) return R_NilValue;
            for (SEXP node = target_symbol; node != R_NilValue;
                 node = CDR(node)) {
                if (TYPEOF(TAG(node)) != SYMSXP) return R_NilValue;
                SEXP label = PRINTNAME(TAG(node));
                if (label == NA_STRING || !CHAR(label)[0]) return R_NilValue;
                for (const unsigned char *p =
                         (const unsigned char *) CHAR(label); *p; ++p)
                    if (*p >= 128) return R_NilValue;
                for (SEXP next = CDR(node); next != R_NilValue;
                     next = CDR(next))
                    if (TAG(next) == TAG(node)) return R_NilValue;
            }
        }
        source_index = width;
        for (R_xlen_t j = 0; j < width; j++)
            if (!strcmp(CHAR(STRING_ELT(names, j)),
                        CHAR(PRINTNAME(source_symbol)))) source_index = j;
        if (source_index == width)
            return R_NilValue;
    } else if (mode == 0 || mode == 6 || mode == 7) {
        if (TYPEOF(target_symbol) != SYMSXP ||
            (mode == 0 && source_symbol != target_symbol)) return R_NilValue;
        target_char = PRINTNAME(target_symbol);
        for (R_xlen_t j = 0; j < width; j++)
            if (STRING_ELT(names, j) == target_char ||
                !strcmp(CHAR(STRING_ELT(names, j)), CHAR(target_char)))
                target_index = j;
        if (target_index == width) return R_NilValue;
        source_index = target_index;
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
        if (shape == 1 && strcmp(label, CHAR(target_char)) == 0)
            return R_NilValue;
        if (shape == 5)
            for (SEXP node = target_symbol; node != R_NilValue;
                 node = CDR(node))
                if (!strcmp(label, CHAR(PRINTNAME(TAG(node)))))
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
    SEXP x = VECTOR_ELT(data, source_index);
    if (!owned_real(x)) return R_NilValue;
    R_xlen_t n = XLENGTH(x);
    if (n < 1 || n > 1000000) return R_NilValue;
    if (!typed(x, n, "dta_double", "double")) {
        return R_NilValue;
    }
    for (R_xlen_t j = 0; j < width; j++) {
        if (j == source_index) continue;
        SEXP column = VECTOR_ELT(data, j);
        if (!ungrouped_column(column, n)) return R_NilValue;
    }
    /* Read-only pointers keep owned input handles unexposed. */
    const double *xp = constant ? NULL : (const double *) DATAPTR_RO(x);
    /* Every allocation and output publication precedes the final input and
       dependency check. The snapshots detect reference writes before fill. */
    R_xlen_t outputs = shape == 0 || constant ? 0 : shape;
    R_xlen_t total = width + outputs;
    int fork_outputs = shape == 5;
    SEXP source_columns = PROTECT(Rf_allocVector(VECSXP, width));
    SEXP source_classes = PROTECT(Rf_allocVector(VECSXP, width));
    SEXP source_storages = PROTECT(Rf_allocVector(VECSXP, width));
    SEXP input_attrs = PROTECT(Rf_allocVector(VECSXP, 4));
    SEXP backings = PROTECT(Rf_allocVector(VECSXP,
        outputs == 0 ? 2 : (fork_outputs ? 1 : outputs)));
    if (VECTOR_ELT(data, source_index) != x) {
        UNPROTECT(5); return R_NilValue;
    }
    for (R_xlen_t j = 0; j < width; j++) {
        SEXP column = VECTOR_ELT(data, j);
        if (!ungrouped_column(column, n)) {
            UNPROTECT(5); return R_NilValue;
        }
        SET_VECTOR_ELT(source_columns, j, column);
        SET_VECTOR_ELT(source_classes, j, probe_raw_attribute(column, R_ClassSymbol));
        SET_VECTOR_ELT(source_storages, j,
                       probe_raw_attribute(column, Rf_install("stata.storage")));
    }
    static const char *input_keys[] = {
        "names", "row.names", "class", ".dtatools_ref_state"
    };
    for (int i = 0; i < 4; i++)
        SET_VECTOR_ELT(input_attrs, i,
            probe_raw_attribute(data, Rf_install(input_keys[i])));
    probe_table_attrs saved_table_attrs;
    if (!probe_table_attrs_read(data, &saved_table_attrs)) {
        UNPROTECT(5); return R_NilValue;
    }
    xp = constant ? NULL : (const double *) DATAPTR_RO(x);
    SEXP out = PROTECT(Rf_allocVector(VECSXP, total));
    SEXP out_names = PROTECT(Rf_allocVector(STRSXP, total));
    for (R_xlen_t j = 0; j < width; j++) {
        SEXP fork = PROTECT(C_dtatools_metadata_copy(VECTOR_ELT(data, j)));
        if (outputs == 0 && j == target_index)
            SET_VECTOR_ELT(backings, 1, fork);
        else SET_VECTOR_ELT(out, j, fork);
        UNPROTECT(1);
        SET_STRING_ELT(out_names, j, STRING_ELT(names, j));
        if (publication_gc_root != NULL &&
            publication_gc_after_fork == j + 1) {
            SEXP pending = publication_gc_root;
            publication_gc_root = NULL;
            R_ReleaseObject(pending);
            R_gc();
        }
    }
    for (int output_index = 0; output_index < (outputs == 0 ? 1 : outputs); output_index++) {
        int protected = 0;
        SEXP col;
        if (fork_outputs && output_index > 0) {
            col = PROTECT(owned_fork(VECTOR_ELT(out, width)));
            protected = 1;
            /* Generated siblings share immutable values, not mutable metadata. */
            DUPLICATE_ATTRIB(col, VECTOR_ELT(out, width));
        } else {
            SEXP backing = PROTECT(Rf_allocVector(REALSXP, n));
            protected++;
            SET_VECTOR_ELT(backings, output_index, backing);
            col = PROTECT(owned_adopt_real(backing));
            protected++;
            SEXP storage = PROTECT(Rf_mkString("double"));
            protected++;
            Rf_setAttrib(col, Rf_install("stata.storage"), storage);
            SEXP col_classes = PROTECT(Rf_allocVector(STRSXP, 4));
            protected++;
            SET_STRING_ELT(col_classes, 0, Rf_mkChar("dta_numeric"));
            SET_STRING_ELT(col_classes, 1, Rf_mkChar("dta_double"));
            SET_STRING_ELT(col_classes, 2, Rf_mkChar("vctrs_vctr"));
            SET_STRING_ELT(col_classes, 3, Rf_mkChar("double"));
            Rf_setAttrib(col, R_ClassSymbol, col_classes);
        }
        if (outputs == 0) SET_VECTOR_ELT(out, target_index, col);
        else {
            R_xlen_t target = width + output_index;
            SET_VECTOR_ELT(out, target, col);
            if (shape == 5) {
                SEXP node = target_symbol;
                for (int k = 0; k < output_index; k++) node = CDR(node);
                SET_STRING_ELT(out_names, target, PRINTNAME(TAG(node)));
            } else SET_STRING_ELT(out_names, target, target_char);
        }
        UNPROTECT(protected);
    }
    SHALLOW_DUPLICATE_ATTRIB(out, data);
    Rf_setAttrib(out, R_NamesSymbol, out_names);
    Rf_setAttrib(out, Rf_install(".dtatools_ref_state"), R_NilValue);
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
    if (publication_gc_root != NULL) {
        SEXP pending = publication_gc_root;
        publication_gc_root = NULL;
        R_ReleaseObject(pending);
        R_gc();
    }
    R_CheckUserInterrupt();
    int public_ok = probe_public_bindings_same();
    int final_ok[] = {
        public_ok,
        probe_default_alloccol_option(),
        probe_raw_attribute(data, R_NamesSymbol) == VECTOR_ELT(input_attrs, 0),
        probe_raw_attribute(data, R_RowNamesSymbol) == VECTOR_ELT(input_attrs, 1),
        probe_raw_attribute(data, R_ClassSymbol) == VECTOR_ELT(input_attrs, 2),
        probe_raw_attribute(data, Rf_install(".dtatools_ref_state")) == VECTOR_ELT(input_attrs, 3),
        dtatools_reference_state_valid_noalloc(data),
        probe_table_attrs_same(data, &saved_table_attrs),
        probe_name_prefix_same(data, out_names, width),
        probe_canonical_table_values(data, n)
    };
    int all_final_ok = 1;
    for (int i = 0; i < 10; i++) if (!final_ok[i]) {
        all_final_ok = 0;
    }
    if (!all_final_ok) {
        UNPROTECT(11); return R_NilValue;
    }
    for (R_xlen_t j = 0; j < width; j++) {
        SEXP column = VECTOR_ELT(data, j);
        /* Every ungrouped input column has an ordered isolated fork. A COW
           value write after its fork may detach the physical input's record,
           while ordinary mask evaluation continues to use the frozen one. */
        if (column != VECTOR_ELT(source_columns, j) ||
            probe_raw_attribute(column, R_ClassSymbol) != VECTOR_ELT(source_classes, j) ||
            probe_raw_attribute(column, Rf_install("stata.storage")) !=
                VECTOR_ELT(source_storages, j) ||
            TYPEOF(column) != REALSXP || XLENGTH(column) != n) {
            UNPROTECT(11); return R_NilValue;
        }
    }
    /* Read the frozen source fork. The original handle may now point at a
       newer record after a finalizer's supported COW value write. */
    if (!constant)
        xp = (const double *) R_ExternalPtrAddr(
            R_altrep_data1(outputs == 0 ? VECTOR_ELT(backings, 1) :
                           VECTOR_ELT(prepared, source_index)));
    admitted++;
    for (int output_index = 0; output_index <
         (fork_outputs ? 1 : (outputs == 0 ? 1 : outputs)); output_index++) {
        SEXP backing = VECTOR_ELT(backings, output_index);
        SEXP col = VECTOR_ELT(prepared,
                              outputs == 0 ? target_index : width + output_index);
        double *values = REAL(backing);
        int no_missing = 1;
#if defined(__aarch64__)
        R_xlen_t row = 0;
        if (!constant) {
            const float64x2_t offset_pair = vdupq_n_f64(offset);
            const float64x2_t lower = vdupq_n_f64(-DBL_MAX / 2);
            const float64x2_t upper = vdupq_n_f64(DBL_MAX / 2);
            double missing = NA_REAL;
            uint64_t missing_bits;
            memcpy(&missing_bits, &missing, sizeof(missing_bits));
            const uint64x2_t missing_pair = vdupq_n_u64(missing_bits);
            uint64_t all_valid = UINT64_MAX;
            for (; row + 1 < n; row += 2) {
                float64x2_t computed = vaddq_f64(vld1q_f64(xp + row),
                                                   offset_pair);
                uint64x2_t valid = vandq_u64(vcgeq_f64(computed, lower),
                                             vcleq_f64(computed, upper));
                uint64x2_t selected = vbslq_u64(
                    valid, vreinterpretq_u64_f64(computed), missing_pair);
                vst1q_f64(values + row, vreinterpretq_f64_u64(selected));
                all_valid &= vgetq_lane_u64(valid, 0) &
                             vgetq_lane_u64(valid, 1);
            }
            no_missing = all_valid == UINT64_MAX;
        }
#else
        R_xlen_t row = 0;
#endif
        for (; row < n; row++) {
            double source = constant ? 0.0 : xp[row];
            double value = constant ? offset : source + offset;
            int valid = value >= -DBL_MAX / 2 && value <= DBL_MAX / 2;
            values[row] = valid ? value : NA_REAL;
            no_missing &= valid;
        }
        owned_flags(col)[OWNED_NO_NA] = no_missing;
        if (fork_outputs)
            for (R_xlen_t output = 1; output < outputs; output++)
                owned_flags(VECTOR_ELT(prepared, width + output))[OWNED_NO_NA] =
                    no_missing;
    }
    published++;
    UNPROTECT(11);
    return prepared;
}


static int probe_general_arithmetic(SEXP expression, SEXP *source,
                                    double *offset) {
    if (TYPEOF(expression) != LANGSXP || ANY_ATTRIB(expression) ||
        CAR(expression) != Rf_install("+")) return 0;
    SEXP args = CDR(expression);
    if (args == R_NilValue || CDR(args) == R_NilValue ||
        CDR(CDR(args)) != R_NilValue || ANY_ATTRIB(args) ||
        ANY_ATTRIB(CDR(args)) || TAG(args) != R_NilValue ||
        TAG(CDR(args)) != R_NilValue || TYPEOF(CAR(args)) != SYMSXP)
        return 0;
    SEXP scalar = CADR(args);
    if (TYPEOF(scalar) != REALSXP || ALTREP(scalar) ||
        ANY_ATTRIB(scalar) || XLENGTH(scalar) != 1 ||
        !R_FINITE(REAL(scalar)[0]) || REAL(scalar)[0] < -1000000 ||
        REAL(scalar)[0] > 1000000) return 0;
    *source = CAR(args);
    *offset = REAL(scalar)[0];
    return 1;
}

static int probe_finite_literal(SEXP value, double *number) {
    if (TYPEOF(value) != REALSXP || ALTREP(value) || ANY_ATTRIB(value) ||
        XLENGTH(value) != 1 || !R_FINITE(REAL(value)[0]) ||
        REAL(value)[0] < -1000000 || REAL(value)[0] > 1000000)
        return 0;
    *number = REAL(value)[0];
    return 1;
}

static int probe_abs_minus_literal(SEXP expression, double *number) {
    if (TYPEOF(expression) != LANGSXP || ANY_ATTRIB(expression) ||
        CAR(expression) != Rf_install("abs")) return 0;
    SEXP arg = CDR(expression);
    if (arg == R_NilValue || CDR(arg) != R_NilValue ||
        ANY_ATTRIB(arg) || TAG(arg) != R_NilValue) return 0;
    SEXP negated = CAR(arg);
    if (TYPEOF(negated) != LANGSXP || ANY_ATTRIB(negated) ||
        CAR(negated) != Rf_install("-")) return 0;
    SEXP inner = CDR(negated);
    if (inner == R_NilValue || CDR(inner) != R_NilValue ||
        ANY_ATTRIB(inner) || TAG(inner) != R_NilValue ||
        !probe_finite_literal(CAR(inner), number)) return 0;
    *number = fabs(*number);
    return 1;
}


static SEXP probe_dplyr_precapture_attempt(SEXP method_frame) {
    if (!mutate_probe_enabled || TYPEOF(method_frame) != ENVSXP ||
        Rf_isObject(method_frame) || Rf_isS4(method_frame) ||
        active_expected == NULL ||
        pointer_guard_operators == NULL || public_guard_cache == NULL)
        return R_NilValue;
    SEXP data_name = Rf_install(".data");
    R_BindingType_t data_type = R_GetBindingType(data_name, method_frame);
    if (data_type != R_BindingTypeValue &&
        data_type != R_BindingTypeForced) return R_NilValue;
    SEXP data = R_getVar(data_name, method_frame, FALSE);
    if (TYPEOF(data) != VECSXP ||
        !dtatools_reference_state_valid_noalloc(data)) return R_NilValue;
    static const char *defaults[] = {".by", ".keep", ".before", ".after"};
    SEXP formals = CDR(CDR(R_ClosureFormals(active_expected)));
    for (int i = 0; i < 4; i++, formals = CDR(formals)) {
        SEXP name = Rf_install(defaults[i]);
        if (formals == R_NilValue ||
            R_GetBindingType(name, method_frame) != R_BindingTypeDelayed ||
            R_DelayedBindingExpression(name, method_frame) != CAR(formals) ||
            R_DelayedBindingEnvironment(name, method_frame) != method_frame)
            return R_NilValue;
    }
    SEXP dots = R_getVar(R_DotsSymbol, method_frame, FALSE);
    if (TYPEOF(dots) != DOTSXP ||
        (Rf_length(dots) != 1 && Rf_length(dots) != 5) ||
        TYPEOF(TAG(dots)) != SYMSXP || TYPEOF(CAR(dots)) != PROMSXP)
        return R_NilValue;
    SEXP promise = CAR(dots);
    SEXP expr = R_PromiseExpr(promise);
    SEXP caller = PRENV(promise);
    if (TYPEOF(caller) != ENVSXP) return R_NilValue;
    int mode = -1, general_create = 0;
    SEXP target = TAG(dots), source = target;
    double number = 1.0;
    if (probe_finite_literal(expr, &number)) mode = 6;
    else if (probe_abs_minus_literal(expr, &number)) mode = 7;
    else if (probe_general_arithmetic(expr, &source, &number)) {
        if (source == target) mode = 0;
        else { mode = 1; general_create = 1; }
    }
    if (Rf_length(dots) == 5) {
        SEXP common_source = R_NilValue;
        double common_offset = 0.0;
        for (SEXP node = dots; node != R_NilValue; node = CDR(node)) {
            SEXP next_source = R_NilValue;
            double next_offset = 0.0;
            if (TYPEOF(TAG(node)) != SYMSXP ||
                TYPEOF(CAR(node)) != PROMSXP ||
                PRENV(CAR(node)) != caller ||
                !probe_general_arithmetic(R_PromiseExpr(CAR(node)),
                                          &next_source, &next_offset))
                return R_NilValue;
            if (common_source == R_NilValue) {
                common_source = next_source;
                common_offset = next_offset;
            } else if (next_source != common_source ||
                       memcmp(&next_offset, &common_offset,
                              sizeof(double)) != 0) return R_NilValue;
        }
        source = common_source;
        number = common_offset;
        target = dots;
        mode = 5;
        general_create = 1;
    }
    if (mode < 0) return R_NilValue;
    if (mode == 0 || mode == 1 || mode == 5 || mode == 7) {
        static const char *local_methods[] = {
            "+.dta_numeric", "+.dta_double", "Ops.dta_numeric",
            "Ops.dta_double", "+.vctrs_vctr",
            "vec_arith.dta_numeric", "vec_arith.dta_numeric.numeric",
            "vec_arith.dta_numeric.double", "vec_arith.numeric.dta_numeric"
        };
        if (mode == 0 || mode == 1 || mode == 5) {
            for (SEXP env = caller; env != R_EmptyEnv && env != R_BaseEnv;
                 env = R_ParentEnv(env)) {
                if (TYPEOF(env) != ENVSXP || Rf_isObject(env) ||
                    Rf_isS4(env)) return R_NilValue;
                for (int j = 0; j < 9; j++)
                    if (R_GetBindingType(Rf_install(local_methods[j]), env) !=
                        R_BindingTypeUnbound) return R_NilValue;
            }
            if (!dtatools_execution_lexical_function_same(
                    caller, Rf_install("+"),
                    VECTOR_ELT(pointer_guard_operators, 0))) return R_NilValue;
        } else if (!dtatools_execution_lexical_function_same(
                       caller, Rf_install("abs"),
                       VECTOR_ELT(pointer_guard_operators, 1)) ||
                   !dtatools_execution_lexical_function_same(
                       caller, Rf_install("-"),
                       VECTOR_ELT(pointer_guard_operators, 2)))
            return R_NilValue;
    }
    if (!probe_public_bindings_same()) return R_NilValue;
    return probe_dplyr_early_config(data, mode, source, target,
                                    number, general_create);
}

SEXP C_dtatools_probe_mutate_selector(SEXP branch_frame) {
    if (TYPEOF(branch_frame) != ENVSXP) Rf_error("invalid branch frame");
    PROTECT(branch_frame);
    SEXP method_frame = R_DelayedBindingEnvironment(Rf_install("no"),
                                                     branch_frame);
    SEXP result = PROTECT(probe_dplyr_precapture_attempt(method_frame));
    if (result == R_NilValue)
        result = Rf_eval(Rf_install("no"), branch_frame);
    UNPROTECT(2);
    return result;
}
