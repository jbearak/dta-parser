#include "dtatools-internal.h"

/* dta_append() writes each source's rows of a numeric column into one
   preallocated buffer. Copy `values` into `buffer` at the zero-based
   `offset` through the region getter, so a compact column is decoded in
   blocks instead of read one element at a time as `[<-` reads it. Return
   FALSE without writing anything when the caller must use `[<-`: the
   buffer is shared, or the arguments do not describe exactly `rows`
   doubles inside it. */
SEXP C_dtatools_append_write_doubles(
    SEXP buffer, SEXP offset, SEXP rows, SEXP values
) {
    if (TYPEOF(buffer) != REALSXP || ALTREP(buffer) || MAYBE_SHARED(buffer) ||
        TYPEOF(values) != REALSXP ||
        TYPEOF(offset) != INTSXP || XLENGTH(offset) != 1 ||
        TYPEOF(rows) != INTSXP || XLENGTH(rows) != 1) {
        return Rf_ScalarLogical(FALSE);
    }
    int start = INTEGER(offset)[0], count = INTEGER(rows)[0];
    if (start == NA_INTEGER || count == NA_INTEGER || start < 0 || count < 0 ||
        XLENGTH(values) != count || count > XLENGTH(buffer) - start) {
        return Rf_ScalarLogical(FALSE);
    }
    double *target = REAL(buffer) + start;
    R_xlen_t copied = 0;
    while (copied < count) {
        R_xlen_t region = REAL_GET_REGION(
            values, copied, count - copied, target + copied
        );
        if (region <= 0) break;
        copied += region;
    }
    for (; copied < count; copied++) target[copied] = REAL_ELT(values, copied);
    return Rf_ScalarLogical(TRUE);
}
