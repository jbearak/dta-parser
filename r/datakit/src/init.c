// datakit reads fixed-width files through dtaparser (ADR 0032): the
// routine here forwards to the C function dtaparser registers with
// R_RegisterCCallable. dta_link fetches it; .onLoad calls it once
// dtaparser's namespace, and so its library, is loaded.

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

typedef int (*abi_fn)(void);
typedef SEXP (*sexp5_fn)(SEXP, SEXP, SEXP, SEXP, SEXP);

static sexp5_fn fixed_width_fn;

// dtaparser's ABI number, after fetching its callable. R_GetCCallable
// raises an R error for one that is missing.
static SEXP link(void) {
  abi_fn abi = (abi_fn) R_GetCCallable("dtaparser", "dtaparser_abi");
  fixed_width_fn = (sexp5_fn) R_GetCCallable("dtaparser", "dtaparser_fixed_width");
  return Rf_ScalarInteger(abi());
}

static SEXP fixed_width(SEXP data, SEXP setup, SEXP out, SEXP recodes, SEXP commented_formats) {
  if (!fixed_width_fn) Rf_error("datakit: dtaparser is not linked; reload datakit");
  return fixed_width_fn(data, setup, out, recodes, commented_formats);
}

static const R_CallMethodDef routines[] = {
  {"dta_link", (DL_FUNC) &link, 0},
  {"dta_fixed_width", (DL_FUNC) &fixed_width, 5},
  {NULL, NULL, 0}
};

void R_init_datakit(DllInfo *dll) {
  R_registerRoutines(dll, NULL, routines, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
