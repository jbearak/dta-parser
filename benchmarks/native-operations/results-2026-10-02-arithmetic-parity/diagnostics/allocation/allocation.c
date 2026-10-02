#include <R.h>
#include <Rinternals.h>
#include <time.h>
#include <string.h>
static double allocation_cpu = 0;
static double overwrite_cpu = 0;
static double finalizers = 0;
static double cpu_time(void) {
    struct timespec t;
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}
static void finalize(SEXP p) {
    R_ClearExternalPtr(p);
    R_SetExternalPtrProtected(p, R_NilValue);
    finalizers++;
}
SEXP probe_alloc(SEXP raw, SEXP byte_count, SEXP fill, SEXP finalizable) {
    R_xlen_t bytes = (R_xlen_t)Rf_asReal(byte_count);
    int use_raw = Rf_asLogical(raw);
    double start = cpu_time();
    SEXP v = PROTECT(Rf_allocVector(use_raw ? RAWSXP : REALSXP,
                                  use_raw ? bytes : bytes / sizeof(double)));
    double after_allocation = cpu_time();
    if (Rf_asLogical(fill)) memset(use_raw ? (void *)RAW(v) : (void *)REAL(v), 0, (size_t)bytes);
    double after_overwrite = cpu_time();
    allocation_cpu += after_allocation - start;
    overwrite_cpu += after_overwrite - after_allocation;
    SEXP p = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, v));
    if (Rf_asLogical(finalizable)) R_RegisterCFinalizerEx(p, finalize, TRUE);
    UNPROTECT(2);
    return p;
}
SEXP probe_stats(SEXP reset) {
    if (Rf_asLogical(reset)) {
        allocation_cpu = overwrite_cpu = finalizers = 0;
        return R_NilValue;
    }
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 3));
    REAL(result)[0] = allocation_cpu;
    REAL(result)[1] = overwrite_cpu;
    REAL(result)[2] = finalizers;
    UNPROTECT(1);
    return result;
}
