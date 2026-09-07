#include <R.h>
#include <Rinternals.h>
#include <R_ext/Memory.h>

/* Call the package's registered entry directly so its temporary allocation
   marker remains observable before the surrounding .Call restores it. The
   caller supplies getNativeSymbolInfo(..., withRegistrationInfo = FALSE). */
SEXP scan_vmax(SEXP address, SEXP values) {
    if (TYPEOF(address) != EXTPTRSXP || !Rf_inherits(address, "NativeSymbol"))
        Rf_error("expected a native function address");
    SEXP (*width_entry)(SEXP) = (SEXP (*)(SEXP)) R_ExternalPtrAddr(address);
    if (width_entry == NULL) Rf_error("null native function address");
    const void *before = vmaxget();
    SEXP width = PROTECT(width_entry(values));
    int retained = vmaxget() != before;
    vmaxset(before);
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(result, 0, width);
    SET_VECTOR_ELT(result, 1, Rf_ScalarLogical(retained));
    UNPROTECT(2);
    return result;
}
