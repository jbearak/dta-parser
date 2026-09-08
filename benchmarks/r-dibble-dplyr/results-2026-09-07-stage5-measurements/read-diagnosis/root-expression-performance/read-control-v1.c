/* Diagnostic only: public R API scans, no dtatools internals or retained pointers. */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

static R_xlen_t checked_length(SEXP x) {
    if (TYPEOF(x) != STRSXP) Rf_error("character input required");
    R_xlen_t n = XLENGTH(x);
    if (n > 1000000) Rf_error("diagnostic input exceeds one million values");
    return n;
}

static SEXP any_na_elt(SEXP x) {
    PROTECT(x);
    R_xlen_t n = checked_length(x);
    int missing = 0;
    for (R_xlen_t i = 0; i < n; ++i) {
        if (STRING_ELT(x, i) == NA_STRING) { missing = 1; break; }
    }
    UNPROTECT(1);
    return Rf_ScalarLogical(missing);
}

static SEXP any_na_pointer(SEXP x) {
    PROTECT(x);
    R_xlen_t n = checked_length(x);
    const SEXP *values = (const SEXP *) DATAPTR_RO(x);
    int missing = 0;
    /* No allocation, callbacks or writable pointer access in this bounded loop.
       x roots the allocation. The pointer never escapes this native call. */
    for (R_xlen_t i = 0; i < n; ++i) {
        if (values[i] == NA_STRING) { missing = 1; break; }
    }
    UNPROTECT(1);
    return Rf_ScalarLogical(missing);
}

/* Separate untimed control. Counts this loop, not base R's anyNA implementation. */
static SEXP elt_visits(SEXP x) {
    PROTECT(x);
    R_xlen_t n = checked_length(x), visits = 0;
    for (R_xlen_t i = 0; i < n; ++i) {
        ++visits;
        if (STRING_ELT(x, i) == NA_STRING) break;
    }
    UNPROTECT(1);
    return Rf_ScalarReal((double) visits);
}

static const R_CallMethodDef methods[] = {
    {"any_na_elt", (DL_FUNC) &any_na_elt, 1},
    {"any_na_pointer", (DL_FUNC) &any_na_pointer, 1},
    {"elt_visits", (DL_FUNC) &elt_visits, 1},
    {NULL, NULL, 0}
};

void attribute_visible R_init_dta_read_control(DllInfo *dll) {
    R_registerRoutines(dll, NULL, methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
