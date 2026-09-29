/* Deterministic callback controls for bracket continuation regressions. */
#include "dtatools-internal.h"

SEXP C_dtatools_probe_bracket_generation_hook(SEXP ignored) {
    (void) ignored;
    SEXP hook = Rf_GetOption1(Rf_install("dtatools.probe_bracket_generation_hook"));
    if (!Rf_isFunction(hook)) return R_NilValue;
    SEXP callback = PROTECT(hook);
    SEXP call = PROTECT(Rf_lang1(callback));
    Rf_eval(call, R_GlobalEnv);
    UNPROTECT(2);
    return R_NilValue;
}

SEXP C_dtatools_probe_bracket_pre_generation_hook(SEXP resolved) {
    SEXP hook = Rf_GetOption1(Rf_install("dtatools.probe_grouped_pre_generation_hook"));
    if (!Rf_isFunction(hook)) return R_NilValue;
    SEXP callback = PROTECT(hook);
    SEXP call = PROTECT(Rf_lang2(callback, resolved));
    Rf_eval(call, R_GlobalEnv);
    UNPROTECT(2);
    return R_NilValue;
}
