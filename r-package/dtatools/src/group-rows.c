/* Facts about a grouping's `.rows` read in one pass, for metadata checks. */
#include "dtatools-internal.h"

static SEXP group_rows_attribute(SEXP tag, SEXP value, void *context) {
    (void) value;
    int *count = context;
    if (tag != R_ClassSymbol && tag != Rf_install("ptype")) return R_NilValue;
    (*count)++;
    return NULL;
}

/* vctrs's `[[`, `as.list()` and `unlist()` hand back a list_of's elements
   unchanged, so a plain list and an exact list_of without names read the
   same. Only one of those, holding ordinary integer vectors, has facts:
   list(rows, sizes, sorted), which are unlist(x, use.names = FALSE),
   lengths(x), and whether no group is.unsorted(strictly = TRUE). Any other
   value, including an empty list, whose unlist() is NULL, returns NULL so
   the caller keeps its R expressions. Setting a long list's attributes can
   wrap it in ALTREP, so elements are read through VECTOR_ELT(), as
   unlist() and lengths() read them. */
SEXP C_dtatools_group_rows_facts(SEXP x) {
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
        if (R_mapAttrib(x, group_rows_attribute, &count) != NULL || count != 2)
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
