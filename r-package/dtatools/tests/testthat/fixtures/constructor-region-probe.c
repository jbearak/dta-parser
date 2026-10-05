#include <R.h>
#include <Rinternals.h>
#include <R_ext/Altrep.h>
#include <R_ext/Rdynload.h>
#include <string.h>

/* Test-only class, compiled once in an isolated test process. All read
   counters and optional second-pass values belong to the individual object. */
static R_altrep_class_t constructor_probe_class;
enum { MODE, LIMIT, REGIONS, SCALARS, POINTERS, PASSES, MAX_REQUEST, FORCED, CONTROL_SIZE };
enum { DIRECT, FULL_REGION, PARTIAL_REGION, ZERO_REGION, NEGATIVE_REGION, OVERSIZED_REGION };

static int *control(SEXP value) {
    return INTEGER(VECTOR_ELT(R_altrep_data1(value), 2));
}

static SEXP active_values(SEXP value) {
    SEXP state = R_altrep_data1(value);
    if (control(value)[PASSES] >= 2) {
        SEXP callback = VECTOR_ELT(state, 3);
        if (callback != R_NilValue) {
            PROTECT(callback);
            SET_VECTOR_ELT(state, 3, R_NilValue);
            SEXP call = PROTECT(Rf_lang1(callback));
            Rf_eval(call, R_GlobalEnv);
            UNPROTECT(2);
        }
        if (VECTOR_ELT(state, 1) != R_NilValue) return VECTOR_ELT(state, 1);
    }
    return VECTOR_ELT(state, 0);
}

static R_xlen_t probe_length(SEXP value) {
    return XLENGTH(VECTOR_ELT(R_altrep_data1(value), 0));
}

static const void *probe_pointer(SEXP value) {
    int *counts = control(value);
    counts[POINTERS]++;
    if (counts[MODE] != DIRECT) return NULL;
    R_xlen_t chunks = (probe_length(value) + 16383) / 16384;
    if (counts[POINTERS] == 1 || (R_xlen_t)counts[POINTERS] == chunks + 1)
        counts[PASSES]++;
    return REAL(active_values(value));
}

static void *probe_forced_pointer(SEXP value, Rboolean writable) {
    (void)writable;
    control(value)[FORCED]++;
    Rf_error("constructor unexpectedly forced foreign input materialization");
    return NULL;
}

static double probe_scalar(SEXP value, R_xlen_t index) {
    control(value)[SCALARS]++;
    return REAL(active_values(value))[index];
}

static R_xlen_t probe_region(SEXP value, R_xlen_t start, R_xlen_t count, double *output) {
    int *counts = control(value);
    counts[REGIONS]++;
    if (start == 0) counts[PASSES]++;
    if (count > counts[MAX_REQUEST]) counts[MAX_REQUEST] = (int)count;
    switch (counts[MODE]) {
    case ZERO_REGION: return 0;
    case NEGATIVE_REGION: return -1;
    case OVERSIZED_REGION: return count + 1;
    }
    SEXP source = active_values(value);
    R_xlen_t available = XLENGTH(source) - start;
    if (count > available) count = available;
    if (counts[MODE] == PARTIAL_REGION && count > counts[LIMIT]) count = counts[LIMIT];
    memcpy(output, REAL(source) + start, (size_t)count * sizeof(double));
    return count;
}

SEXP C_constructor_probe(SEXP values, SEXP second, SEXP mode, SEXP limit, SEXP callback) {
    if (TYPEOF(values) != REALSXP || ALTREP(values) ||
        (second != R_NilValue && (TYPEOF(second) != REALSXP || ALTREP(second) ||
                                 XLENGTH(second) != XLENGTH(values))) ||
        TYPEOF(mode) != INTSXP || XLENGTH(mode) != 1 ||
        INTEGER(mode)[0] < DIRECT || INTEGER(mode)[0] > OVERSIZED_REGION ||
        TYPEOF(limit) != INTSXP || XLENGTH(limit) != 1 || INTEGER(limit)[0] < 1 ||
        (callback != R_NilValue && !Rf_isFunction(callback)))
        Rf_error("invalid constructor region probe arguments");
    SEXP state = PROTECT(Rf_allocVector(VECSXP, 4));
    SET_VECTOR_ELT(state, 0, values);
    SET_VECTOR_ELT(state, 1, second);
    SET_VECTOR_ELT(state, 3, callback);
    SEXP counts = PROTECT(Rf_allocVector(INTSXP, CONTROL_SIZE));
    memset(INTEGER(counts), 0, CONTROL_SIZE * sizeof(int));
    INTEGER(counts)[MODE] = INTEGER(mode)[0];
    INTEGER(counts)[LIMIT] = INTEGER(limit)[0];
    SET_VECTOR_ELT(state, 2, counts);
    SEXP result = R_new_altrep(constructor_probe_class, state, R_NilValue);
    UNPROTECT(2);
    return result;
}

SEXP C_constructor_probe_info(SEXP value) {
    if (!ALTREP(value) || !R_altrep_inherits(value, constructor_probe_class))
        Rf_error("constructor probe required");
    SEXP result = PROTECT(Rf_allocVector(INTSXP, 6));
    const int indices[] = {REGIONS, SCALARS, POINTERS, PASSES, MAX_REQUEST, FORCED};
    for (int i = 0; i < 6; i++) INTEGER(result)[i] = control(value)[indices[i]];
    const char *names[] = {"regions", "scalars", "pointers", "passes", "max_request", "forced"};
    SEXP labels = PROTECT(Rf_allocVector(STRSXP, 6));
    for (int i = 0; i < 6; i++) SET_STRING_ELT(labels, i, Rf_mkChar(names[i]));
    Rf_setAttrib(result, R_NamesSymbol, labels);
    UNPROTECT(2);
    return result;
}

void R_init_constructor_region_probe(DllInfo *dll) {
    constructor_probe_class = R_make_altreal_class("constructor_input", "constructor_region_probe", dll);
    R_set_altrep_Length_method(constructor_probe_class, probe_length);
    R_set_altreal_Elt_method(constructor_probe_class, probe_scalar);
    R_set_altreal_Get_region_method(constructor_probe_class, probe_region);
    R_set_altvec_Dataptr_method(constructor_probe_class, probe_forced_pointer);
    R_set_altvec_Dataptr_or_null_method(constructor_probe_class, probe_pointer);
    static const R_CallMethodDef methods[] = {
        {"C_constructor_probe", (DL_FUNC)&C_constructor_probe, 5},
        {"C_constructor_probe_info", (DL_FUNC)&C_constructor_probe_info, 1},
        {NULL, NULL, 0}
    };
    R_registerRoutines(dll, NULL, methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
