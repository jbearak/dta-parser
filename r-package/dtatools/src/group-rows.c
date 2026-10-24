/* Facts about a grouping's `.rows` read in one pass, for metadata checks. */
#include "dtatools-internal.h"

static SEXP group_rows_attribute(SEXP tag, SEXP value, void *context) {
    (void) value;
    int *count = context;
    if (tag != R_ClassSymbol && tag != Rf_install("ptype")) return R_NilValue;
    (*count)++;
    return NULL;
}

/* The R expressions dispatch on a list_of from base closures: vapply() calls
   as.list(), lengths() calls length() on the list and `[[` on each element,
   and unlist() and lengths() are generics themselves. From base, dispatch
   looks in base's namespace, then base's S3 methods table, then the global
   environment and the search path down to the base environment. No binding
   may be active, since reading one would run its code. */
static int group_rows_no_method(SEXP table, const char *name) {
    SEXP symbol = Rf_install(name);
    if (R_GetBindingType(symbol, R_BaseNamespace) != R_BindingTypeUnbound ||
        R_GetBindingType(symbol, table) != R_BindingTypeUnbound) return 0;
    for (SEXP env = R_GlobalEnv;; env = R_ParentEnv(env)) {
        if (TYPEOF(env) != ENVSXP || env == R_EmptyEnv ||
            R_GetBindingType(symbol, env) != R_BindingTypeUnbound) return 0;
        if (env == R_BaseEnv) return 1;
    }
}

/* The table's method comes before the global environment, so it is the one
   dispatch finds. It must be the method vctrs defined when dtatools was
   built. Namespace loading registers each method as a promise, which the
   first dispatch forces; reading an unforced one would run code, so it
   declines until the R expressions have dispatched. */
static int group_rows_original_method(SEXP table, const char *name, SEXP original) {
    SEXP symbol = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(symbol, table);
    if (R_GetBindingType(symbol, R_BaseNamespace) != R_BindingTypeUnbound ||
        (kind != R_BindingTypeValue && kind != R_BindingTypeForced)) return 0;
    SEXP method = R_getVarEx(symbol, table, FALSE, R_NilValue);
    return TYPEOF(method) == CLOSXP && TYPEOF(original) == CLOSXP &&
        R_compute_identical(method, original, IDENT_USE_CLOENV);
}

static int group_rows_methods_original(SEXP originals) {
    static const char *absent[] = {
        "unlist.vctrs_list_of", "unlist.vctrs_vctr", "unlist.list", "unlist.default",
        "lengths.vctrs_list_of", "lengths.vctrs_vctr", "lengths.list", "lengths.default",
        "length.vctrs_list_of", "length.vctrs_vctr", "length.list", "length.default"
    };
    SEXP name = Rf_install(".__S3MethodsTable__.");
    R_BindingType_t kind = R_GetBindingType(name, R_BaseNamespace);
    if (TYPEOF(originals) != VECSXP || XLENGTH(originals) != 2 ||
        (kind != R_BindingTypeValue && kind != R_BindingTypeForced)) return 0;
    SEXP table = R_getVarEx(name, R_BaseNamespace, FALSE, R_NilValue);
    if (TYPEOF(table) != ENVSXP ||
        !group_rows_original_method(table, "as.list.vctrs_list_of", VECTOR_ELT(originals, 0)) ||
        !group_rows_original_method(table, "[[.vctrs_list_of", VECTOR_ELT(originals, 1)))
        return 0;
    for (size_t i = 0; i < sizeof(absent) / sizeof(absent[0]); i++)
        if (!group_rows_no_method(table, absent[i])) return 0;
    return 1;
}

/* vctrs's `[[` and `as.list()` hand back a list_of's elements unchanged, and
   unlist(), lengths() and length() have no list_of method, so a plain list
   and an exact list_of without names read the same while that holds.
   `originals` holds vctrs's as.list() and `[[` methods for a list_of. Only
   such a list, holding ordinary integer vectors, has facts: list(rows,
   sizes, sorted), which are unlist(x, use.names = FALSE), lengths(x), and
   whether no group is.unsorted(strictly = TRUE). Any other value, including
   an empty list, whose unlist() is NULL, returns NULL so the caller keeps
   its R expressions. Setting a long list's attributes can wrap it in
   ALTREP, so elements are read through VECTOR_ELT(), as unlist() and
   lengths() read them. */
SEXP C_dtatools_group_rows_facts(SEXP x, SEXP originals) {
    if (TYPEOF(x) != VECSXP || Rf_isS4(x)) return R_NilValue;
    R_xlen_t groups = XLENGTH(x);
    if (groups == 0 || groups > INT_MAX) return R_NilValue;
    if (ANY_ATTRIB(x)) {
        static const char *wanted[] = {"vctrs_list_of", "vctrs_vctr", "list"};
        SEXP classes = Rf_getAttrib(x, R_ClassSymbol);
        if (TYPEOF(classes) != STRSXP || ALTREP(classes) || ANY_ATTRIB(classes) ||
            XLENGTH(classes) != 3) return R_NilValue;
        for (int i = 0; i < 3; i++)
            if (strcmp(CHAR(STRING_ELT(classes, i)), wanted[i])) return R_NilValue;
        int count = 0;
        if (R_mapAttrib(x, group_rows_attribute, &count) != NULL || count != 2 ||
            !group_rows_methods_original(originals))
            return R_NilValue;
    }
    R_xlen_t total = 0;
    for (R_xlen_t group = 0; group < groups; group++) {
        SEXP rows = VECTOR_ELT(x, group);
        if (TYPEOF(rows) != INTSXP || ALTREP(rows) || ANY_ATTRIB(rows) ||
            XLENGTH(rows) > INT_MAX || XLENGTH(rows) > R_XLEN_T_MAX - total)
            return R_NilValue;
        total += XLENGTH(rows);
    }
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 3));
    SEXP flat = PROTECT(Rf_allocVector(INTSXP, total));
    SET_VECTOR_ELT(result, 0, flat);
    SEXP sizes = PROTECT(Rf_allocVector(INTSXP, groups));
    SET_VECTOR_ELT(result, 1, sizes);
    int *output = INTEGER(flat), *size = INTEGER(sizes);
    /* As any() over is.unsorted(): a group of two or more rows holding NA is
       NA, and any unsorted group outweighs an NA. */
    int unsorted = 0, missing = 0;
    R_xlen_t offset = 0;
    for (R_xlen_t group = 0; group < groups; group++) {
        if ((group & 16383) == 0) R_CheckUserInterrupt();
        SEXP rows = VECTOR_ELT(x, group);
        R_xlen_t length = XLENGTH(rows);
        const int *values = INTEGER(rows);
        int has_na = 0, decreases = 0;
        for (R_xlen_t i = 0; i < length; i++) {
            if (values[i] == NA_INTEGER) has_na = 1;
            else if (i > 0 && values[i - 1] != NA_INTEGER &&
                     values[i] <= values[i - 1]) decreases = 1;
            output[offset + i] = values[i];
        }
        if (length > 1) {
            if (has_na) missing = 1;
            else if (decreases) unsorted = 1;
        }
        size[group] = (int) length;
        offset += length;
    }
    SET_VECTOR_ELT(result, 2, Rf_ScalarLogical(
        unsorted ? FALSE : missing ? NA_LOGICAL : TRUE));
    UNPROTECT(3);
    return result;
}

/* Whether reading `x` runs no R code: it is ordinary, owned, or compact, or
   a chain of metadata views that ends at one of those. A view reads its
   materialized copy when it has one, and its source otherwise. */
static int group_key_readable(SEXP x) {
    for (int depth = 0; depth < 64; depth++) {
        if (!ALTREP(x) || owned_column(x)) return 1;
        if (TYPEOF(x) == STRSXP) {
            /* A compact string column reads its dictionary. */
            if (R_altrep_inherits(x, dtatools_dictstring_class)) return 1;
            if (!R_altrep_inherits(x, dtatools_metadata_string_class)) return 0;
        } else {
            if (TYPEOF(x) != REALSXP) return 0;
            if (R_altrep_inherits(x, dtatools_numeric_class)) return 1;
            if (!R_altrep_inherits(x, dtatools_metadata_real_class)) return 0;
        }
        SEXP materialized = R_altrep_data2(x);
        x = materialized != R_NilValue ? materialized : metadata_proxy_source(x);
    }
    return 0;
}

/* A bare logical, integer, double or character column whose values are read
   without running R code. */
static int group_key_column(SEXP x) {
    int type = TYPEOF(x);
    if ((type != LGLSXP && type != INTSXP && type != REALSXP && type != STRSXP) ||
        ANY_ATTRIB(x))
        return 0;
    return group_key_readable(x);
}

typedef struct {
    int count;
    SEXP row_names;
} group_key_frame;

static SEXP group_key_frame_attribute(SEXP tag, SEXP value, void *context) {
    group_key_frame *frame = context;
    if (tag == R_NamesSymbol) {
        frame->count++;
        return NULL;
    }
    if (tag == R_RowNamesSymbol) {
        frame->row_names = value;
        frame->count++;
        return NULL;
    }
    if (tag == R_ClassSymbol && TYPEOF(value) == STRSXP && !ALTREP(value) &&
        !ANY_ATTRIB(value) && XLENGTH(value) == 1 &&
        strcmp(CHAR(STRING_ELT(value, 0)), "data.frame") == 0) {
        frame->count++;
        return NULL;
    }
    return R_NilValue;
}

/* The number of rows a data frame's row names give, as .row_names_info(x, 2)
   does, reading R's compact c(NA, n) form without expanding it. */
static R_xlen_t group_key_frame_rows(SEXP row_names) {
    if (TYPEOF(row_names) == INTSXP && XLENGTH(row_names) == 2 &&
        INTEGER_ELT(row_names, 0) == NA_INTEGER) {
        int n = INTEGER_ELT(row_names, 1);
        return n == NA_INTEGER ? -1 : n < 0 ? -(R_xlen_t) n : n;
    }
    return XLENGTH(row_names);
}

/* The columns of an equality proxy that is a bare column, or a bare data
   frame of them with exactly names, a "data.frame" class and row names.
   NULL for anything else. */
static SEXP group_key_columns(SEXP x) {
    if (TYPEOF(x) != VECSXP) {
        if (!group_key_column(x)) return R_NilValue;
        SEXP columns = Rf_allocVector(VECSXP, 1);
        SET_VECTOR_ELT(columns, 0, x);
        return columns;
    }
    group_key_frame frame = {0, R_NilValue};
    if (ALTREP(x) || Rf_isS4(x) ||
        R_mapAttrib(x, group_key_frame_attribute, &frame) != NULL || frame.count != 3 ||
        ALTREP(frame.row_names))
        return R_NilValue;
    R_xlen_t rows = group_key_frame_rows(frame.row_names);
    for (R_xlen_t i = 0; i < XLENGTH(x); i++) {
        SEXP column = VECTOR_ELT(x, i);
        if (!group_key_column(column) || XLENGTH(column) != rows) return R_NilValue;
    }
    return x;
}

static int group_key_double_equal(double x, double y) {
    /* vctrs's na_equal comparison: numbers by value, and NA and NaN each
       equal only to themselves. */
    if (!ISNAN(x)) return !ISNAN(y) && x == y;
    return ISNAN(y) && R_IsNA(x) == R_IsNA(y);
}

#define GROUP_KEY_BLOCK 4096

/* Whether row i of `actual` equals the key of the group holding it, where
   the groups hold sizes[0], sizes[1], ... consecutive rows. */
static int group_key_column_matches(SEXP actual, SEXP key, const int *sizes,
                                    R_xlen_t groups) {
    int type = TYPEOF(actual);
    R_xlen_t total = XLENGTH(actual), group = 0, left = groups ? sizes[0] : 0;
    if (type == STRSXP) {
        /* vctrs translates strings to UTF-8 before it compares them, which
           leaves NA and ASCII strings as they are, and R keeps one copy of
           each ASCII string, so two of those are equal exactly when they are
           the same element. A translation can fail, so any other string
           declines, even after a mismatch. The keys are held in a vector,
           since reading a compact string can collect an unreferenced one. */
        SEXP keys = PROTECT(Rf_allocVector(STRSXP, groups));
        for (R_xlen_t i = 0; i < groups; i++) {
            SEXP value = STRING_ELT(key, i);
            if (value != NA_STRING && !Rf_charIsASCII(value)) {
                UNPROTECT(1);
                return -1;
            }
            SET_STRING_ELT(keys, i, value);
        }
        int matched = 1;
        for (R_xlen_t i = 0; i < total; i++) {
            if (i % GROUP_KEY_BLOCK == 0) R_CheckUserInterrupt();
            while (left == 0) left = sizes[++group];
            SEXP value = STRING_ELT(actual, i);
            if (value != NA_STRING && !Rf_charIsASCII(value)) {
                UNPROTECT(1);
                return -1;
            }
            if (value != STRING_ELT(keys, group)) matched = 0;
            left--;
        }
        UNPROTECT(1);
        return matched;
    }
    if (type == REALSXP) {
        double *keys = (double *) R_alloc(groups ? groups : 1, sizeof(double));
        double buffer[GROUP_KEY_BLOCK];
        if (REAL_GET_REGION(key, 0, groups, keys) != groups) return -1;
        for (R_xlen_t start = 0; start < total; start += GROUP_KEY_BLOCK) {
            R_CheckUserInterrupt();
            R_xlen_t n = total - start < GROUP_KEY_BLOCK ? total - start : GROUP_KEY_BLOCK;
            if (REAL_GET_REGION(actual, start, n, buffer) != n) return -1;
            for (R_xlen_t i = 0; i < n; i++) {
                while (left == 0) left = sizes[++group];
                if (!group_key_double_equal(buffer[i], keys[group])) return 0;
                left--;
            }
        }
        return 1;
    }
    int *keys = (int *) R_alloc(groups ? groups : 1, sizeof(int));
    int buffer[GROUP_KEY_BLOCK];
    if ((type == INTSXP ? INTEGER_GET_REGION(key, 0, groups, keys) :
         LOGICAL_GET_REGION(key, 0, groups, keys)) != groups) return -1;
    for (R_xlen_t start = 0; start < total; start += GROUP_KEY_BLOCK) {
        R_CheckUserInterrupt();
        R_xlen_t n = total - start < GROUP_KEY_BLOCK ? total - start : GROUP_KEY_BLOCK;
        if ((type == INTSXP ? INTEGER_GET_REGION(actual, start, n, buffer) :
             LOGICAL_GET_REGION(actual, start, n, buffer)) != n) return -1;
        for (R_xlen_t i = 0; i < n; i++) {
            while (left == 0) left = sizes[++group];
            if (buffer[i] != keys[group]) return 0;
            left--;
        }
    }
    return 1;
}

/* all(vctrs::vec_equal(actual, expected, na_equal = TRUE)), where expected
   repeats the i-th value of `key` sizes[i] times, without building expected.
   `actual` and `key` are equality proxies: bare logical, integer, double or
   character columns, or bare data frames of them with the same names and
   column types, which vctrs compares column by column without dispatch. NULL
   declines any other proxy, sizes that do not cover `actual`, and strings
   the comparison above declines, so the caller builds expected and asks
   vctrs. */
SEXP C_dtatools_group_keys_match(SEXP actual, SEXP key, SEXP sizes) {
    SEXP actual_columns = PROTECT(group_key_columns(actual));
    SEXP key_columns = PROTECT(group_key_columns(key));
    R_xlen_t groups = XLENGTH(sizes), count;
    if (actual_columns == R_NilValue || key_columns == R_NilValue ||
        TYPEOF(actual) != TYPEOF(key) || TYPEOF(sizes) != INTSXP || ALTREP(sizes) || ANY_ATTRIB(sizes) ||
        (count = XLENGTH(actual_columns)) != XLENGTH(key_columns) || count == 0) {
        UNPROTECT(2);
        return R_NilValue;
    }
    if (TYPEOF(actual) == VECSXP) {
        SEXP actual_names = Rf_getAttrib(actual, R_NamesSymbol);
        SEXP key_names = Rf_getAttrib(key, R_NamesSymbol);
        int same = TYPEOF(actual_names) == STRSXP && TYPEOF(key_names) == STRSXP &&
            XLENGTH(actual_names) == count && XLENGTH(key_names) == count;
        for (R_xlen_t i = 0; same && i < count; i++)
            same = STRING_ELT(actual_names, i) == STRING_ELT(key_names, i);
        if (!same) {
            UNPROTECT(2);
            return R_NilValue;
        }
    }
    const int *size = INTEGER_RO(sizes);
    R_xlen_t total = 0;
    for (R_xlen_t i = 0; i < groups; i++) {
        if (size[i] == NA_INTEGER || size[i] < 0) {
            UNPROTECT(2);
            return R_NilValue;
        }
        total += size[i];
    }
    for (R_xlen_t i = 0; i < count; i++) {
        SEXP a = VECTOR_ELT(actual_columns, i), k = VECTOR_ELT(key_columns, i);
        if (TYPEOF(a) != TYPEOF(k) || XLENGTH(a) != total || XLENGTH(k) != groups) {
            UNPROTECT(2);
            return R_NilValue;
        }
    }
    /* vctrs translates every string column before it compares any column,
       so a mismatch in one column still reads the others. */
    int matched = 1;
    for (R_xlen_t i = 0; matched >= 0 && i < count; i++) {
        int column = group_key_column_matches(VECTOR_ELT(actual_columns, i),
                                              VECTOR_ELT(key_columns, i), size, groups);
        if (column <= 0) matched = column;
        if (matched == 0) {
            /* Only string columns can still decline. */
            int strings = 0;
            for (R_xlen_t j = i + 1; j < count; j++)
                strings |= TYPEOF(VECTOR_ELT(actual_columns, j)) == STRSXP;
            if (!strings) break;
        }
    }
    UNPROTECT(2);
    return matched < 0 ? R_NilValue : Rf_ScalarLogical(matched);
}
