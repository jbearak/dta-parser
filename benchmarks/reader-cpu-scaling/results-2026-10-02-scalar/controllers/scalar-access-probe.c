/* Private diagnostics. All element reads use the public R scalar API. */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Altrep.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Utils.h>
#include <math.h>
#include <string.h>

static R_xlen_t gcd_length(R_xlen_t x, R_xlen_t y) {
    while (y != 0) {
        R_xlen_t remainder = x % y;
        x = y;
        y = remainder;
    }
    return x;
}

static int named(SEXP value, const char *expected) {
    if (TYPEOF(value) == SYMSXP) return strcmp(CHAR(PRINTNAME(value)), expected) == 0;
    if (TYPEOF(value) == CHARSXP) return value != NA_STRING && strcmp(CHAR(value), expected) == 0;
    return TYPEOF(value) == STRSXP && XLENGTH(value) == 1 &&
        STRING_ELT(value, 0) != NA_STRING &&
        strcmp(CHAR(STRING_ELT(value, 0)), expected) == 0;
}

static int known_class(SEXP value, const char *class_name) {
    return ALTREP(value) &&
        named(R_altrep_class_package(value), "dtatools") &&
        named(R_altrep_class_name(value), class_name);
}

/* Returns a rooted R object, never a cached pointer into its descriptor.
   No source or payload is changed. Unknown ALTREP implementations are opaque. */
SEXP scalar_access_unwrap(SEXP value) {
    if (TYPEOF(value) != REALSXP) Rf_error("unwrap requires a double vector");
    SEXP source = value;
    int depth = 0;
    while (known_class(source, "dtatools_metadata_real")) {
        if (++depth > 1024) Rf_error("metadata proxy chain is too deep");
        SEXP materialized = R_altrep_data2(source);
        if (materialized != R_NilValue) {
            source = materialized;
            break;
        }
        SEXP state = R_altrep_data1(source);
        if (TYPEOF(state) == VECSXP && !ALTREP(state) &&
            (XLENGTH(state) == 2 || XLENGTH(state) == 3)) {
            source = VECTOR_ELT(state, 0);
        } else {
            source = state;
        }
        if (TYPEOF(source) != REALSXP) Rf_error("unexpected numeric proxy source");
    }
    if (ALTREP(source) && !known_class(source, "dtatools_numeric"))
        Rf_error("unwrap stopped at an unknown ALTREP implementation");
    return source;
}

/* order: sequential, reverse, or permuted. The latter visits every position
   once using a deterministic stride coprime to the vector length. Selected
   positions are optional one-based integers/doubles, independent of order.
   checksum sums finite values; NA count includes all NaN payloads. */
SEXP scalar_access_scan(SEXP value, SEXP order, SEXP selected) {
    if (TYPEOF(value) != REALSXP) Rf_error("scan requires a double vector");
    if (TYPEOF(order) != STRSXP || XLENGTH(order) != 1 || STRING_ELT(order, 0) == NA_STRING)
        Rf_error("order must be one non-missing string");
    const char *label = CHAR(STRING_ELT(order, 0));
    int mode = strcmp(label, "sequential") == 0 ? 0 :
        (strcmp(label, "reverse") == 0 ? 1 :
         (strcmp(label, "permuted") == 0 ? 2 : -1));
    if (mode < 0) Rf_error("unsupported scan order");
    if (selected != R_NilValue && TYPEOF(selected) != INTSXP && TYPEOF(selected) != REALSXP)
        Rf_error("selected positions must be numeric or NULL");
    R_xlen_t length = XLENGTH(value);
    R_xlen_t selected_length = selected == R_NilValue ? 0 : XLENGTH(selected);
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 5));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 5));
    const char *labels[] = {"checksum", "na_count", "positive_infinity_count", "negative_infinity_count", "values"};
    for (int i = 0; i < 5; ++i) SET_STRING_ELT(names, i, Rf_mkChar(labels[i]));
    Rf_setAttrib(result, R_NamesSymbol, names);
    SEXP values = PROTECT(Rf_allocVector(REALSXP, selected_length));
    SET_VECTOR_ELT(result, 4, values);

    double checksum = 0.0, na_count = 0.0, positive_infinity = 0.0, negative_infinity = 0.0;
    R_xlen_t step = length > 1 ? length / 3 + 1 : 0;
    if (mode == 2 && length > 1) {
        while (gcd_length(step, length) != 1) ++step;
    }
    R_xlen_t permuted = 0;
    for (R_xlen_t i = 0; i < length; ++i) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t index = mode == 0 ? i : (mode == 1 ? length - i - 1 : permuted);
        double element = REAL_ELT(value, index);
        if (ISNAN(element)) ++na_count;
        else if (!R_FINITE(element)) {
            if (element > 0) ++positive_infinity;
            else ++negative_infinity;
        } else checksum += element;
        if (mode == 2 && length > 1) {
            /* Modular addition without overflowing the index type. */
            permuted = permuted >= length - step ?
                permuted - (length - step) : permuted + step;
        }
    }
    for (R_xlen_t i = 0; i < selected_length; ++i) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        double position = TYPEOF(selected) == INTSXP ?
            (double) INTEGER_ELT(selected, i) : REAL_ELT(selected, i);
        if (!R_FINITE(position) || position < 1 || position > (double) length || position != floor(position))
            Rf_error("selected position is outside the vector");
        double element = REAL_ELT(value, (R_xlen_t) position - 1);
        memcpy(REAL(values) + i, &element, sizeof(element));
    }
    SET_VECTOR_ELT(result, 0, Rf_ScalarReal(checksum));
    SET_VECTOR_ELT(result, 1, Rf_ScalarReal(na_count));
    SET_VECTOR_ELT(result, 2, Rf_ScalarReal(positive_infinity));
    SET_VECTOR_ELT(result, 3, Rf_ScalarReal(negative_infinity));
    UNPROTECT(3);
    return result;
}

static const R_CallMethodDef calls[] = {
    {"scalar_access_scan", (DL_FUNC) &scalar_access_scan, 3},
    {"scalar_access_unwrap", (DL_FUNC) &scalar_access_unwrap, 1},
    {NULL, NULL, 0}
};

void R_init_scalar_access_probe(DllInfo *dll) {
    R_registerRoutines(dll, NULL, calls, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
