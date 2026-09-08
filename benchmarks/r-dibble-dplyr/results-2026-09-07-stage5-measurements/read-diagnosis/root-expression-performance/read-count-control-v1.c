/* Diagnostic only: public R API scans, no dtatools internals or retained pointers. */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

static R_xlen_t checked_length(SEXP x) {
    if (TYPEOF(x) != LGLSXP && TYPEOF(x) != INTSXP)
        Rf_error("logical or integer input required");
    R_xlen_t n = XLENGTH(x);
    if (n > 1000000) Rf_error("diagnostic input exceeds one million values");
    return n;
}

static SEXP nonmissing_elt(SEXP x) {
    PROTECT(x);
    R_xlen_t n = checked_length(x);
    int count = 0;
    if (TYPEOF(x) == LGLSXP) {
        for (R_xlen_t i = 0; i < n; ++i)
            count += LOGICAL_ELT(x, i) != NA_LOGICAL;
    } else {
        for (R_xlen_t i = 0; i < n; ++i)
            count += INTEGER_ELT(x, i) != NA_INTEGER;
    }
    UNPROTECT(1);
    return Rf_ScalarInteger(count);
}

static SEXP nonmissing_pointer(SEXP x) {
    PROTECT(x);
    R_xlen_t n = checked_length(x);
    const int *values = (const int *) DATAPTR_RO(x);
    int count = 0;
    /* NA_LOGICAL and NA_INTEGER share R's integer NA sentinel. No allocation,
       callbacks or writable pointer access occurs in this bounded loop.
       x roots the allocation. The pointer never escapes this native call. */
    for (R_xlen_t i = 0; i < n; ++i)
        count += values[i] != NA_INTEGER;
    UNPROTECT(1);
    return Rf_ScalarInteger(count);
}

/* This separate untimed loop counts its own visits, not base R's is.na/sum. */
static SEXP count_visits(SEXP x) {
    PROTECT(x);
    R_xlen_t n = checked_length(x), visits = 0;
    int count = 0;
    if (TYPEOF(x) == LGLSXP) {
        for (R_xlen_t i = 0; i < n; ++i) {
            ++visits;
            count += LOGICAL_ELT(x, i) != NA_LOGICAL;
        }
    } else {
        for (R_xlen_t i = 0; i < n; ++i) {
            ++visits;
            count += INTEGER_ELT(x, i) != NA_INTEGER;
        }
    }
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 2));
    REAL(result)[0] = (double) count;
    REAL(result)[1] = (double) visits;
    UNPROTECT(2);
    return result;
}

static const R_CallMethodDef methods[] = {
    {"nonmissing_elt", (DL_FUNC) &nonmissing_elt, 1},
    {"nonmissing_pointer", (DL_FUNC) &nonmissing_pointer, 1},
    {"count_visits", (DL_FUNC) &count_visits, 1},
    {NULL, NULL, 0}
};

void attribute_visible R_init_dta_read_control(DllInfo *dll) {
    R_registerRoutines(dll, NULL, methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
