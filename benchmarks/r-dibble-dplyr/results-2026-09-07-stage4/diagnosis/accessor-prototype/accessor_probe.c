/* Development-only read dispatch experiment. No package code is replaced.
   Writable pointer access is deliberately unsupported. */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Altrep.h>
#include <R_ext/Rdynload.h>
static R_altrep_class_t classes[5][3];
static SEXP record(SEXP x) { return VECTOR_ELT(R_altrep_data1(x), 0); }
static SEXP direct(SEXP x) { return R_altrep_data1(x); }
#define METHODS(prefix, payload) \
static R_xlen_t prefix##_length(SEXP x) { return XLENGTH(payload(x)); } \
static const void *prefix##_ptr(SEXP x) { return DATAPTR_RO(payload(x)); } \
static int prefix##_integer(SEXP x, R_xlen_t i) { return INTEGER_ELT(payload(x), i); } \
static int prefix##_logical(SEXP x, R_xlen_t i) { return LOGICAL_ELT(payload(x), i); } \
static SEXP prefix##_string(SEXP x, R_xlen_t i) { return STRING_ELT(payload(x), i); } \
static int prefix##_integer_ptr(SEXP x, R_xlen_t i) { return ((const int *) DATAPTR_RO(payload(x)))[i]; } \
static int prefix##_logical_ptr(SEXP x, R_xlen_t i) { return ((const int *) DATAPTR_RO(payload(x)))[i]; } \
static SEXP prefix##_string_ptr(SEXP x, R_xlen_t i) { return STRING_PTR_RO(payload(x))[i]; }
METHODS(record, record)
METHODS(direct, direct)
static R_xlen_t external_length(SEXP x) { return XLENGTH(R_ExternalPtrProtected(R_altrep_data1(x))); }
static const void *external_ptr(SEXP x) { return R_ExternalPtrAddr(R_altrep_data1(x)); }
static int external_integer(SEXP x, R_xlen_t i) { return ((const int *) external_ptr(x))[i]; }
static SEXP external_string(SEXP x, R_xlen_t i) { return ((const SEXP *) external_ptr(x))[i]; }
static SEXP make_probe(SEXP x, SEXP mode_arg) {
    int type = TYPEOF(x), mode = Rf_asInteger(mode_arg);
    if (ALTREP(x) || (type != INTSXP && type != LGLSXP && type != STRSXP) || mode < 0 || mode > 4)
        Rf_error("ordinary input and mode 0 through 4 required");
    SEXP payload = PROTECT(Rf_duplicate(x));
    CLEAR_ATTRIB(payload);
    SEXP state = PROTECT(mode < 2 ? Rf_allocVector(VECSXP, 2) : mode == 4 ? R_MakeExternalPtr((void *) DATAPTR_RO(payload), R_NilValue, payload) : payload);
    if (mode < 2) {
        SET_VECTOR_ELT(state, 0, payload);
        SET_VECTOR_ELT(state, 1, Rf_allocVector(INTSXP, 5));
    }
    SEXP result = PROTECT(R_new_altrep(classes[mode][type == INTSXP ? 0 : type == LGLSXP ? 1 : 2], state, R_NilValue));
    SHALLOW_DUPLICATE_ATTRIB(result, x);
    UNPROTECT(3);
    return result;
}
static const R_CallMethodDef calls[] = {{"make_probe", (DL_FUNC)&make_probe, 2}, {NULL, NULL, 0}};
void R_init_accessor_probe(DllInfo *dll) {
    for (int mode = 0; mode < 5; mode++) {
        char name[40];
        snprintf(name, sizeof(name), "probe_integer_%d", mode);
        classes[mode][0] = R_make_altinteger_class(name, "accessor_probe", dll);
        snprintf(name, sizeof(name), "probe_logical_%d", mode);
        classes[mode][1] = R_make_altlogical_class(name, "accessor_probe", dll);
        snprintf(name, sizeof(name), "probe_string_%d", mode);
        classes[mode][2] = R_make_altstring_class(name, "accessor_probe", dll);
        for (int type = 0; type < 3; type++) {
            R_set_altrep_Length_method(classes[mode][type], mode < 2 ? record_length : mode == 4 ? external_length : direct_length);
            R_set_altvec_Dataptr_or_null_method(classes[mode][type], mode < 2 ? record_ptr : mode == 4 ? external_ptr : direct_ptr);
        }
        R_set_altinteger_Elt_method(classes[mode][0], mode == 0 ? record_integer : mode == 1 ? record_integer_ptr : mode == 2 ? direct_integer : mode == 4 ? external_integer : direct_integer_ptr);
        R_set_altlogical_Elt_method(classes[mode][1], mode == 0 ? record_logical : mode == 1 ? record_logical_ptr : mode == 2 ? direct_logical : mode == 4 ? external_integer : direct_logical_ptr);
        R_set_altstring_Elt_method(classes[mode][2], mode == 0 ? record_string : mode == 1 ? record_string_ptr : mode == 2 ? direct_string : mode == 4 ? external_string : direct_string_ptr);
    }
    R_registerRoutines(dll, NULL, calls, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
