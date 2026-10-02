#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <string.h>

/* Compile once and load the exact same binary with both package builds. This
   deliberately uses R's ordinary ALTREP dispatch/GC guard, rather than either
   package's internal materialization test entry point. Every list element is
   a fresh, independently constructed compact handle. */
static SEXP force_batch(SEXP columns) {
    if (TYPEOF(columns) != VECSXP) Rf_error("expected a list of numeric columns");
    for (R_xlen_t i = 0; i < XLENGTH(columns); ++i) {
        SEXP value = VECTOR_ELT(columns, i);
        if (TYPEOF(value) != REALSXP) Rf_error("expected a double column");
        const void *pointer = DATAPTR_RO(value);
        if (XLENGTH(value) != 0 && pointer == NULL)
            Rf_error("materialization returned a null pointer");
    }
    return R_NilValue;
}

/* Full bitwise value checks must not acquire a pointer to the compact source:
   an as.double()/metadata alias can itself change its sharing state before a
   measurement. Region reads preserve that state and all 27 missing payloads. */
static SEXP matches_batch(SEXP columns, SEXP expected) {
    if (TYPEOF(columns) != VECSXP || TYPEOF(expected) != REALSXP || ALTREP(expected))
        Rf_error("expected a column list and ordinary double oracle");
    const double *oracle = REAL(expected);
    R_xlen_t n = XLENGTH(expected);
    double values[8192];
    for (R_xlen_t i = 0; i < XLENGTH(columns); ++i) {
        SEXP value = VECTOR_ELT(columns, i);
        if (TYPEOF(value) != REALSXP || XLENGTH(value) != n) return Rf_ScalarLogical(FALSE);
        for (R_xlen_t start = 0; start < n;) {
            R_xlen_t count = n - start < 8192 ? n - start : 8192;
            R_xlen_t got = REAL_GET_REGION(value, start, count, values);
            if (got <= 0 || got > count ||
                memcmp(values, oracle + start, (size_t) got * sizeof(double)) != 0)
                return Rf_ScalarLogical(FALSE);
            start += got;
        }
    }
    return Rf_ScalarLogical(TRUE);
}

static const R_CallMethodDef methods[] = {
    {"force_batch", (DL_FUNC) &force_batch, 1},
    {"matches_batch", (DL_FUNC) &matches_batch, 2},
    {NULL, NULL, 0}
};

void R_init_materialization_probe(DllInfo *info) {
    R_registerRoutines(info, NULL, methods, NULL, NULL);
    R_useDynamicSymbols(info, FALSE);
    R_forceSymbols(info, TRUE);
}
