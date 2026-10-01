#include <R.h>
#include <Rinternals.h>
#include <math.h>

/* Compensated accumulation is needed even on platforms where long double
   has double precision. In particular, 1e16 + 1 - 1e16 must retain the 1. */
SEXP C_dtatools_summarize_sum(SEXP x) {
    if (TYPEOF(x) != REALSXP) Rf_error("Expected a double summary vector");
    double sum = 0.0, correction = 0.0;
    R_xlen_t n = XLENGTH(x);
    for (R_xlen_t i = 0; i < n; ++i) {
        if (i % 65536 == 0) R_CheckUserInterrupt();
        double value = REAL_ELT(x, i);
        double next = sum + value;
        if (!R_FINITE(next)) return Rf_ScalarReal(next);
        correction += fabs(sum) >= fabs(value)
            ? (sum - next) + value : (value - next) + sum;
        sum = next;
    }
    return Rf_ScalarReal(sum + correction);
}
