#include <R.h>
#include <Rinternals.h>
#include <R_ext/Altrep.h>
#include <R_ext/Rdynload.h>

/* Compiled by a child test process only. Mutate a live helper's bytecode
   constant in place, leaving its closure, body and visible source intact. */
static SEXP constant_pool(SEXP closure, SEXP index) {
    if (TYPEOF(closure) != CLOSXP || TYPEOF(index) != INTSXP ||
        XLENGTH(index) != 1 || INTEGER(index)[0] < 0)
        Rf_error("invalid bytecode probe arguments");
    SEXP code = R_ClosureBody(closure);
    if (TYPEOF(code) != BCODESXP) Rf_error("not a compiled closure");
    SEXP constants = CDR(code);
    if (TYPEOF(constants) != VECSXP || INTEGER(index)[0] >= XLENGTH(constants))
        Rf_error("constant index out of range");
    return constants;
}

SEXP C_probe_constant_pool(SEXP closure) {
    if (TYPEOF(closure) != CLOSXP || TYPEOF(R_ClosureBody(closure)) != BCODESXP)
        Rf_error("compiled closure required");
    return CDR(R_ClosureBody(closure));
}

SEXP C_probe_code_vector(SEXP closure) {
    if (TYPEOF(closure) != CLOSXP || TYPEOF(R_ClosureBody(closure)) != BCODESXP)
        Rf_error("compiled closure required");
    return CAR(R_ClosureBody(closure));
}

SEXP C_probe_replace_constant(SEXP closure, SEXP index, SEXP replacement) {
    SEXP constants = constant_pool(closure, index);
    SEXP original = PROTECT(VECTOR_ELT(constants, INTEGER(index)[0]));
    SET_VECTOR_ELT(constants, INTEGER(index)[0], replacement);
    UNPROTECT(1);
    return original;
}

SEXP C_probe_set_constant_attribute(SEXP closure, SEXP index,
                                    SEXP attribute, SEXP replacement) {
    SEXP constants = constant_pool(closure, index);
    if (TYPEOF(attribute) != STRSXP || XLENGTH(attribute) != 1 ||
        STRING_ELT(attribute, 0) == NA_STRING)
        Rf_error("invalid attribute name");
    SEXP value = VECTOR_ELT(constants, INTEGER(index)[0]);
    SEXP name = Rf_installTrChar(STRING_ELT(attribute, 0));
    SEXP original = PROTECT(Rf_getAttrib(value, name));
    Rf_setAttrib(value, name, replacement);
    UNPROTECT(1);
    return original;
}

static R_altrep_class_t probe_class;
static int probe_hits = 0;
static R_xlen_t probe_length(SEXP x) {
    probe_hits++;
    return XLENGTH(R_altrep_data1(x));
}
static int probe_element(SEXP x, R_xlen_t i) {
    probe_hits++;
    return INTEGER(R_altrep_data1(x))[i];
}
static void *probe_data(SEXP x, Rboolean writeable) {
    (void) writeable;
    probe_hits++;
    return INTEGER(R_altrep_data1(x));
}
static const void *probe_data_or_null(SEXP x) {
    probe_hits++;
    return INTEGER(R_altrep_data1(x));
}

SEXP C_probe_altrep_integer(SEXP value) {
    if (TYPEOF(value) != INTSXP || ALTREP(value)) Rf_error("plain integer required");
    SEXP copy = PROTECT(Rf_duplicate(value));
    SEXP out = PROTECT(R_new_altrep(probe_class, copy, R_NilValue));
    Rf_copyMostAttrib(value, out);
    UNPROTECT(2);
    return out;
}

SEXP C_probe_altrep_hits(SEXP reset) {
    int previous = probe_hits;
    if (TYPEOF(reset) == LGLSXP && XLENGTH(reset) == 1 && LOGICAL(reset)[0] == TRUE)
        probe_hits = 0;
    return Rf_ScalarInteger(previous);
}

void R_init_numeric_bytecode_probe(DllInfo *dll) {
    probe_class = R_make_altinteger_class("callback_integer", "bytecode_probe", dll);
    R_set_altrep_Length_method(probe_class, probe_length);
    R_set_altinteger_Elt_method(probe_class, probe_element);
    R_set_altvec_Dataptr_method(probe_class, probe_data);
    R_set_altvec_Dataptr_or_null_method(probe_class, probe_data_or_null);
}
