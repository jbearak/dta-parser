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
