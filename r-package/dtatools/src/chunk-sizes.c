/* Sizes of the results a grouped verb's expressions return for each group. */
#include "dtatools-internal.h"

static int chunk_class_is(SEXP classes, R_xlen_t i, const char *expected) {
    SEXP name = STRING_ELT(classes, i);
    return name != NA_STRING && strcmp(CHAR(name), expected) == 0;
}

/* The classes the package's Stata numeric constructors give, whose
   vec_proxy() method is vec_proxy.dta_numeric(). */
static int chunk_stata_numeric(SEXP value) {
    static const char *storages[] = {
        "dta_byte", "dta_int", "dta_long", "dta_float", "dta_double"
    };
    SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
    if (TYPEOF(value) != REALSXP || TYPEOF(classes) != STRSXP || ALTREP(classes) ||
        XLENGTH(classes) != 4 || !chunk_class_is(classes, 0, "dta_numeric") ||
        !chunk_class_is(classes, 2, "vctrs_vctr") ||
        !chunk_class_is(classes, 3, "double")) return 0;
    for (int i = 0; i < 5; i++) if (chunk_class_is(classes, 1, storages[i])) return 1;
    return 0;
}

/* A grouped summarise() or mutate() checks each group's result with
   vctrs::obj_is_vector() and vctrs::vec_size(). Both call the result's
   vec_proxy() method, and for a Stata numeric that is
   vec_proxy.dta_numeric(), whose R code costs more than a small group's
   summary. A bare vector, or a Stata numeric of the package's classes, is
   a vector whose size is its length, so this returns the length without
   the method (ADR 0052). It returns NULL, and the caller asks vctrs, for
   other classes, S4 objects, arrays, long vectors, and ALTREP vectors the
   package does not own, whose length can run R code. */
SEXP C_dtatools_chunk_size(SEXP value) {
    if (Rf_isS4(value) || (ALTREP(value) && !owned_column(value) &&
        unmaterialized_numeric_read_storage(value) == NULL)) return R_NilValue;
    switch (TYPEOF(value)) {
    case LGLSXP: case INTSXP: case REALSXP: case CPLXSXP: case STRSXP:
    case RAWSXP: case VECSXP:
        break;
    default:
        return R_NilValue;
    }
    if ((Rf_isObject(value) && !chunk_stata_numeric(value)) ||
        Rf_getAttrib(value, R_DimSymbol) != R_NilValue) return R_NilValue;
    R_xlen_t size = XLENGTH(value);
    if (size > INT_MAX) return R_NilValue;
    return Rf_ScalarInteger((int) size);
}
