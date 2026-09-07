#include <R.h>
#include <Rinternals.h>
#include <R_ext/Memory.h>
#include <string.h>
static int owned_string_width(SEXP value) {
    return Rf_getCharCE(value) == CE_BYTES ? LENGTH(value) :
        (int) strlen(Rf_translateCharUTF8(value));
}
SEXP width_probe(SEXP values) {
    const void *start = vmaxget(), *previous = start;
    int changes = 0, maximum = 0;
    for (R_xlen_t i = 0; i < XLENGTH(values); i++) {
        int width = owned_string_width(STRING_ELT(values, i));
        if (width > maximum) maximum = width;
        const void *current = vmaxget();
        changes += current != previous;
        previous = current;
    }
    int retained = vmaxget() != start;
    vmaxset(start);
    SEXP result = PROTECT(Rf_allocVector(INTSXP, 3));
    INTEGER(result)[0] = changes; INTEGER(result)[1] = retained; INTEGER(result)[2] = maximum;
    UNPROTECT(1); return result;
}
