/* Integer match codes for two compact dictionary strings, so dta_merge()
   can match string keys without making an R string for each value. */
#include "dtatools-internal.h"

/* Returns list(x_codes, y_codes), or NULL when either value is not an
   unmaterialized dictionary string or a row's value holds a NUL byte, which
   an R string cannot. Rows share a code exactly when their values have equal
   UTF-8 bytes. Both payloads stay pinned while the codes are read, so no
   callback can release a dictionary in use. */
SEXP C_dtatools_dictstring_match_codes(SEXP x, SEXP y) {
    SEXP x_root = PROTECT(dictstring_read_root(x));
    SEXP y_root = PROTECT(dictstring_read_root(y));
    if (x_root == R_NilValue || y_root == R_NilValue) {
        UNPROTECT(2);
        return R_NilValue;
    }
    dictstring_data *x_data = (dictstring_data *) R_ExternalPtrAddr(x_root);
    dictstring_data *y_data = (dictstring_data *) R_ExternalPtrAddr(y_root);
    if (x_data->length > (size_t) R_XLEN_T_MAX ||
        y_data->length > (size_t) R_XLEN_T_MAX) {
        Rf_error("compact string key is too long");
    }
    SEXP x_codes = PROTECT(Rf_allocVector(INTSXP, (R_xlen_t) x_data->length));
    SEXP y_codes = PROTECT(Rf_allocVector(INTSXP, (R_xlen_t) y_data->length));
    int status = dtatools_dictstring_match_codes(
        x_data, (size_t) XLENGTH(R_ExternalPtrProtected(x_root)),
        x_data->value_ids, x_data->length, INTEGER(x_codes),
        y_data, (size_t) XLENGTH(R_ExternalPtrProtected(y_root)),
        y_data->value_ids, y_data->length, INTEGER(y_codes));
    if (status == 2) {
        UNPROTECT(4);
        return R_NilValue;
    }
    if (status != 1) Rf_error("could not code dtatools string-dictionary keys");
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(result, 0, x_codes);
    SET_VECTOR_ELT(result, 1, y_codes);
    UNPROTECT(5);
    return result;
}
