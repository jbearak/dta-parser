#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <dlfcn.h>
#include <stdint.h>
/* Look up documented dyld image queries without its legacy TRUE/FALSE enum. */
SEXP preflight_loaded_images(void) {
    uint32_t (*image_count)(void) = dlsym(RTLD_DEFAULT, "_dyld_image_count");
    const char *(*image_name)(uint32_t) = dlsym(RTLD_DEFAULT, "_dyld_get_image_name");
    if (!image_count || !image_name) Rf_error("dyld image query unavailable");
    uint32_t count = image_count();
    SEXP result = PROTECT(Rf_allocVector(STRSXP, count));
    for (uint32_t i = 0; i < count; ++i)
        SET_STRING_ELT(result, i, Rf_mkChar(image_name(i)));
    UNPROTECT(1);
    return result;
}
