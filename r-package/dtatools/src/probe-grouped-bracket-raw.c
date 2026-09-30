/* Scratch early grouped bracket capture. This bypasses ordinary parser and
   rlang captures only for literal one/five assignment syntax and bare `by`.
   It has no public callback certificate and is not production admission. */
#include "dtatools-internal.h"

static int raw_quosure(SEXP quo, SEXP *caller, SEXP *expression) {
    if (TYPEOF(quo) != LANGSXP || Rf_length(quo) != 2 ||
        CAR(quo) != Rf_install("~")) return 0;
    SEXP classes = Rf_getAttrib(quo, R_ClassSymbol);
    if (TYPEOF(classes) != STRSXP || ALTREP(classes) ||
        XLENGTH(classes) != 2 ||
        strcmp(CHAR(STRING_ELT(classes, 0)), "quosure") ||
        strcmp(CHAR(STRING_ELT(classes, 1)), "formula")) return 0;
    *caller = Rf_getAttrib(quo, Rf_install(".Environment"));
    *expression = CADR(quo);
    return TYPEOF(*caller) == ENVSXP;
}

static int value_expression(SEXP expr, SEXP *source) {
    if (TYPEOF(expr) != LANGSXP || Rf_length(expr) != 3 ||
        CAR(expr) != Rf_install("+") || TYPEOF(CADR(expr)) != SYMSXP)
        return 0;
    SEXP literal = CADDR(expr);
    if (TYPEOF(literal) != REALSXP || ALTREP(literal) ||
        Rf_isS4(literal) || ANY_ATTRIB(literal) ||
        XLENGTH(literal) != 1 || REAL(literal)[0] != 1.0)
        return 0;
    if (*source == R_NilValue) *source = CADR(expr);
    return *source == CADR(expr);
}

static SEXP make_quosure(SEXP expression, SEXP environment) {
    SEXP quo = PROTECT(Rf_lang2(Rf_install("~"), expression));
    SEXP classes = PROTECT(Rf_allocVector(STRSXP, 2));
    SET_STRING_ELT(classes, 0, Rf_mkChar("quosure"));
    SET_STRING_ELT(classes, 1, Rf_mkChar("formula"));
    Rf_setAttrib(quo, Rf_install(".Environment"), environment);
    Rf_setAttrib(quo, R_ClassSymbol, classes);
    UNPROTECT(2);
    return quo;
}

SEXP C_dtatools_probe_grouped_bracket_raw(SEXP raw_j) {
    SEXP frame = R_GetCurrentEnv();
    SEXP caller = R_NilValue, expression = R_NilValue;
    SEXP enabled = Rf_GetOption1(Rf_install(
        "dtatools.probe_grouped_bracket_raw"));
    if (enabled != R_NilValue &&
        (TYPEOF(enabled) != LGLSXP || ALTREP(enabled) ||
         XLENGTH(enabled) != 1 || LOGICAL(enabled)[0] != TRUE))
        return R_NilValue;
    if (TYPEOF(frame) != ENVSXP ||
        !raw_quosure(raw_j, &caller, &expression) ||
        TYPEOF(expression) != LANGSXP ||
        CAR(expression) != Rf_install(":=")) return R_NilValue;
    if (R_GetBindingType(Rf_install("i"), frame) !=
            R_BindingTypeMissing ||
        R_GetBindingType(Rf_install("drop"), frame) !=
            R_BindingTypeMissing)
        return R_NilValue;
    SEXP bysort_symbol = Rf_install("bysort");
    R_BindingType_t bysort_kind = R_GetBindingType(bysort_symbol, frame);
    if (bysort_kind != R_BindingTypeMissing &&
        (bysort_kind != R_BindingTypeDelayed ||
         R_DelayedBindingExpression(bysort_symbol, frame) != R_NilValue ||
         R_DelayedBindingEnvironment(bysort_symbol, frame) != frame))
        return R_NilValue;
    if (R_GetBindingType(R_DotsSymbol, frame) != R_BindingTypeMissing)
        return R_NilValue;
    SEXP by_symbol = Rf_install("by");
    if (R_GetBindingType(by_symbol, frame) != R_BindingTypeDelayed ||
        R_DelayedBindingEnvironment(by_symbol, frame) != caller)
        return R_NilValue;
    SEXP by_expression = R_DelayedBindingExpression(by_symbol, frame);
    if (TYPEOF(by_expression) != SYMSXP) return R_NilValue;

    R_xlen_t count = Rf_length(expression) - 1;
    int tagged = count == 5;
    if (!tagged && count != 2) return R_NilValue;
    SEXP argument = CDR(expression);
    SEXP source = R_NilValue;
    if (!tagged) {
        if (TYPEOF(argument) != LISTSXP ||
            TAG(argument) != R_NilValue ||
            TYPEOF(CAR(argument)) != SYMSXP ||
            CAR(argument) == R_DotsSymbol ||
            TYPEOF(CDR(argument)) != LISTSXP ||
            TAG(CDR(argument)) != R_NilValue ||
            !value_expression(CADDR(expression), &source))
            return R_NilValue;
    } else {
        for (SEXP node = argument; node != R_NilValue; node = CDR(node)) {
            if (TYPEOF(node) != LISTSXP || TAG(node) == R_NilValue ||
                TAG(node) == R_DotsSymbol ||
                !CHAR(PRINTNAME(TAG(node)))[0] ||
                !value_expression(CAR(node), &source))
                return R_NilValue;
            for (SEXP prior = argument; prior != node; prior = CDR(prior))
                if (TAG(prior) == TAG(node)) return R_NilValue;
        }
    }
    SEXP assignments = PROTECT(Rf_allocVector(VECSXP, tagged ? 5 : 1));
    SEXP node = argument;
    for (int i = 0; i < (tagged ? 5 : 1); i++) {
        SEXP target = tagged ? PRINTNAME(TAG(node)) : PRINTNAME(CAR(node));
        /* Match enquo() capture even if later callbacks force a partial
           native result back through the ordinary evaluator. */
        SEXP value = PROTECT(Rf_duplicate(tagged ? CAR(node) : CADR(node)));
        SEXP assignment = PROTECT(Rf_allocVector(VECSXP, 2));
        SEXP name = PROTECT(Rf_ScalarString(target));
        SEXP quo = PROTECT(make_quosure(value, caller));
        SEXP field_names = PROTECT(Rf_allocVector(STRSXP, 2));
        SET_STRING_ELT(field_names, 0, Rf_mkChar("name"));
        SET_STRING_ELT(field_names, 1, Rf_mkChar("values"));
        SET_VECTOR_ELT(assignment, 0, name);
        SET_VECTOR_ELT(assignment, 1, quo);
        Rf_setAttrib(assignment, R_NamesSymbol, field_names);
        SET_VECTOR_ELT(assignments, i, assignment);
        UNPROTECT(5);
        node = CDR(node);
    }
    SEXP by = PROTECT(make_quosure(by_expression, caller));
    SEXP where = PROTECT(make_quosure(R_NilValue, R_EmptyEnv));
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(result, 0, assignments);
    SET_VECTOR_ELT(result, 1, by);
    SET_VECTOR_ELT(result, 2, where);
    UNPROTECT(4);
    return result;
}
