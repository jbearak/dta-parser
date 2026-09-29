/* Only known plain and private owned double storage can skip key decoding. */
#include "dtatools-internal.h"
static SEXP double_key_attr(SEXP tag, SEXP value, void *context) {
    (void)value;
    int *count = context;
    if (tag != R_ClassSymbol && tag != Rf_install("stata.storage")) return R_NilValue;
    (*count)++;
    return NULL;
}
SEXP dtatools_grouped_double_values(SEXP value, R_xlen_t n) {
    if (TYPEOF(value) != REALSXP || Rf_isS4(value))
        return R_NilValue;
    SEXP backing = dtatools_probe_double_input_values(value);
    if (backing == R_NilValue || TYPEOF(backing) != REALSXP ||
        ALTREP(backing) || XLENGTH(backing) != n || XLENGTH(value) != n) return R_NilValue;
    SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
    SEXP storage = Rf_getAttrib(value, Rf_install("stata.storage"));
    static const char *wanted[] = {"dta_numeric", "dta_double", "vctrs_vctr", "double"};
    if (TYPEOF(classes) != STRSXP || ALTREP(classes) || ANY_ATTRIB(classes) ||
        Rf_isS4(classes) || XLENGTH(classes) != 4 || TYPEOF(storage) != STRSXP ||
        ALTREP(storage) || ANY_ATTRIB(storage) || Rf_isS4(storage) ||
        XLENGTH(storage) != 1 || strcmp(CHAR(STRING_ELT(storage, 0)), "double"))
        return R_NilValue;
    for (int i = 0; i < 4; ++i)
        if (strcmp(CHAR(STRING_ELT(classes, i)), wanted[i])) return R_NilValue;
    int count = 0;
    if (R_mapAttrib(value, double_key_attr, &count) != NULL || count != 2)
        return R_NilValue;
    return backing;
}
