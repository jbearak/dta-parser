#include <R.h>
#include <Rinternals.h>
#include <R_ext/Memory.h>
#include <string.h>
static int owned_string_width(SEXP value) {
    if (Rf_getCharCE(value) == CE_BYTES) return LENGTH(value);
    /* Translation can allocate R temporary storage for each encoded element.
       Only the byte count escapes, so release that storage before the next
       element instead of retaining every conversion until .Call returns. */
    const void *marker = vmaxget();
    int width = (int) strlen(Rf_translateCharUTF8(value));
    vmaxset(marker);
    return width;
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
