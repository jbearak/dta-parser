#include <Rinternals.h>

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

/* Build identity, not an adversarial integrity check.  This runs only while
   qualifying an installed source profile at package load. */
SEXP C_dtatools_profile_file_fingerprints(SEXP paths) {
    if (TYPEOF(paths) != STRSXP) return R_NilValue;
    R_xlen_t count = XLENGTH(paths);
    SEXP result = PROTECT(allocVector(STRSXP, count));
    for (R_xlen_t i = 0; i < count; ++i) {
        SEXP name = STRING_ELT(paths, i);
        if (name == NA_STRING) {
            SET_STRING_ELT(result, i, NA_STRING);
            continue;
        }
        FILE *stream = fopen(CHAR(name), "rb");
        if (stream == NULL) {
            SET_STRING_ELT(result, i, NA_STRING);
            continue;
        }
        uint64_t hash = UINT64_C(14695981039346656037);
        unsigned char block[65536];
        size_t length;
        while ((length = fread(block, 1, sizeof(block), stream)) != 0) {
            for (size_t j = 0; j < length; ++j) {
                hash ^= block[j];
                hash *= UINT64_C(1099511628211);
            }
        }
        int failed = ferror(stream);
        if (fclose(stream) != 0) failed = 1;
        if (failed) {
            SET_STRING_ELT(result, i, NA_STRING);
            continue;
        }
        char hex[17];
        snprintf(hex, sizeof(hex), "%016" PRIx64, hash);
        SET_STRING_ELT(result, i, mkChar(hex));
    }
    UNPROTECT(1);
    return result;
}
