#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <mach-o/dyld.h>
SEXP preflight_loaded_images(void) {
    uint32_t count = _dyld_image_count();
    SEXP result = PROTECT(Rf_allocVector(STRSXP, count));
    for (uint32_t i = 0; i < count; ++i)
        SET_STRING_ELT(result, i, Rf_mkChar(_dyld_get_image_name(i)));
    UNPROTECT(1);
    return result;
}
