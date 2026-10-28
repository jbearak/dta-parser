// Registers dtatools' native routines. Each wrapper calls into Rust and
// raises the R error, if any, only after Rust has returned.

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

SEXP dtatools_meta(SEXP path, SEXP encoding, char *err, size_t err_len);
SEXP dtatools_read(SEXP path, SEXP cols, SEXP encoding, char *err, size_t err_len);

static SEXP check(SEXP result, const char *err) {
  if (err[0]) Rf_error("%s", err);
  return result;
}

static SEXP meta(SEXP path, SEXP encoding) {
  char err[1024] = "";
  return check(dtatools_meta(path, encoding, err, sizeof err), err);
}

static SEXP read(SEXP path, SEXP cols, SEXP encoding) {
  char err[1024] = "";
  return check(dtatools_read(path, cols, encoding, err, sizeof err), err);
}

static const R_CallMethodDef routines[] = {
  {"dta_meta", (DL_FUNC) &meta, 2},
  {"dta_read", (DL_FUNC) &read, 3},
  {NULL, NULL, 0}
};

void R_init_dtatools(DllInfo *dll) {
  R_registerRoutines(dll, NULL, routines, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
