// dtatools reads and writes files through dtaparser (ADR 0016): the
// routines here forward to C functions dtaparser registers with
// R_RegisterCCallable. dta_link fetches them; .onLoad calls it once
// dtaparser's namespace, and so its library, is loaded.

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

typedef int (*abi_fn)(void);
typedef SEXP (*sexp1_fn)(SEXP);
typedef SEXP (*sexp2_fn)(SEXP, SEXP);
typedef SEXP (*sexp6_fn)(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);

static sexp2_fn meta_fn, write_fn;
static sexp6_fn read_fn;
static sexp1_fn dictionary_fn;

// dtaparser's ABI number, after fetching its callables. R_GetCCallable
// raises an R error for one that is missing.
static SEXP link(void) {
  abi_fn abi = (abi_fn) R_GetCCallable("dtaparser", "dtaparser_abi");
  meta_fn = (sexp2_fn) R_GetCCallable("dtaparser", "dtaparser_meta");
  read_fn = (sexp6_fn) R_GetCCallable("dtaparser", "dtaparser_read");
  write_fn = (sexp2_fn) R_GetCCallable("dtaparser", "dtaparser_write");
  dictionary_fn = (sexp1_fn) R_GetCCallable("dtaparser", "dtaparser_dictionary");
  return Rf_ScalarInteger(abi());
}

static void check_linked(void) {
  if (!read_fn) Rf_error("dtatools: dtaparser is not linked; reload dtatools");
}

static SEXP meta(SEXP path, SEXP encoding) {
  check_linked();
  return meta_fn(path, encoding);
}

// Mode 1: dtatools' dta_num columns.
static SEXP read(SEXP path, SEXP cols, SEXP skip, SEXP n_max, SEXP encoding) {
  check_linked();
  SEXP mode = PROTECT(Rf_ScalarInteger(1));
  SEXP out = read_fn(path, cols, skip, n_max, encoding, mode);
  UNPROTECT(1);
  return out;
}

static SEXP write(SEXP path, SEXP spec) {
  check_linked();
  return write_fn(path, spec);
}

static SEXP dictionary(SEXP x) {
  check_linked();
  return dictionary_fn(x);
}

SEXP dtatools_codes(SEXP x);
SEXP dtatools_keys(SEXP x, SEXP keep_na);
SEXP dtatools_missing(SEXP codes);

static const R_CallMethodDef routines[] = {
  {"dta_codes", (DL_FUNC) &dtatools_codes, 1},
  {"dta_keys", (DL_FUNC) &dtatools_keys, 2},
  {"dta_missing", (DL_FUNC) &dtatools_missing, 1},
  {"dta_link", (DL_FUNC) &link, 0},
  {"dta_dictionary", (DL_FUNC) &dictionary, 1},
  {"dta_meta", (DL_FUNC) &meta, 2},
  {"dta_read", (DL_FUNC) &read, 5},
  {"dta_write", (DL_FUNC) &write, 2},
  {NULL, NULL, 0}
};

void R_init_dtatools(DllInfo *dll) {
  R_registerRoutines(dll, NULL, routines, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
