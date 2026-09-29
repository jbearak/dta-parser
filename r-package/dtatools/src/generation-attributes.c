/* Ordinary generated doubles already have exactly the attributes gen keeps. */
#include "dtatools-internal.h"

static SEXP generation_only_names(SEXP name, SEXP value, void *context) {
    (void) value;
    (void) context;
    return name == R_NamesSymbol ? NULL : R_NilValue;
}

static int generation_plain_strings(SEXP value, R_xlen_t size) {
    /* No foreign length or element callback is needed to decline. */
    return TYPEOF(value) == STRSXP && !ALTREP(value) &&
        !ANY_ATTRIB(value) && !Rf_isObject(value) && !Rf_isS4(value) &&
        XLENGTH(value) == size;
}

static int generation_string_is(SEXP value, R_xlen_t index, const char *expected) {
    SEXP text = STRING_ELT(value, index);
    /* Byte-marked classes can change startsWith() diagnostics in the R path. */
    return text != NA_STRING && Rf_getCharCE(text) != CE_BYTES &&
        strcmp(CHAR(text), expected) == 0;
}

static SEXP canonical_generate_attributes(SEXP source, SEXP frame, SEXP dependencies) {
    if (TYPEOF(source) != VECSXP || ALTREP(source) ||
        Rf_isObject(source) || Rf_isS4(source) || XLENGTH(source) != 2 ||
        R_mapAttrib(source, generation_only_names, NULL) != NULL)
        return Rf_ScalarLogical(FALSE);

    SEXP names = Rf_getAttrib(source, R_NamesSymbol);
    SEXP storage = VECTOR_ELT(source, 0);
    SEXP classes = VECTOR_ELT(source, 1);
    /* Qualify every container before inspecting any character content. */
    if (!generation_plain_strings(names, 2) ||
        !generation_plain_strings(storage, 1) ||
        !generation_plain_strings(classes, 4))
        return Rf_ScalarLogical(FALSE);

    if (TYPEOF(dependencies) == ENVSXP)
        dependencies = dtatools_metadata_profile_from_state(dependencies);
    PROTECT(dependencies);
    int admitted = dtatools_metadata_dependencies_unchanged(frame, dependencies, 1);
    UNPROTECT(1);
    if (!admitted)
        return Rf_ScalarLogical(FALSE);

    return Rf_ScalarLogical(
        generation_string_is(names, 0, "stata.storage") &&
        generation_string_is(names, 1, "class") &&
        generation_string_is(storage, 0, "double") &&
        generation_string_is(classes, 0, "dta_numeric") &&
        generation_string_is(classes, 1, "dta_double") &&
        generation_string_is(classes, 2, "vctrs_vctr") &&
        generation_string_is(classes, 3, "double"));
}

/* Production passes no eager payload. Its original source promise remains
   untouched whenever admission declines. Explicit-frame diagnostics retain
   their supplied payload contract. Root borrowed source attributes throughout
   profile validation, whose supported binding/syntax APIs may allocate. */
SEXP C_dtatools_canonical_generate_attributes(SEXP source, SEXP frame, SEXP dependencies) {
    if (frame == R_NilValue) {
        frame = R_GetCurrentEnv();
        SEXP profile = PROTECT(TYPEOF(dependencies) == ENVSXP ?
            dtatools_metadata_profile_from_state(dependencies) : dependencies);
        int admitted = TYPEOF(profile) == VECSXP && !ALTREP(profile) &&
            XLENGTH(profile) == 29 &&
            dtatools_execution_frame_same(frame, VECTOR_ELT(profile, 13));
        UNPROTECT(1);
        if (!admitted) return Rf_ScalarLogical(FALSE);
        source = dtatools_metadata_source(frame);
    }
    PROTECT(source);
    SEXP result = canonical_generate_attributes(source, frame, dependencies);
    UNPROTECT(1);
    return result;
}
