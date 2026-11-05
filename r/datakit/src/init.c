// datakit reads fixed-width and Parquet files through dtaparser (ADR
// 0032, plan 0018): the routines here forward to the C functions
// dtaparser registers with R_RegisterCCallable. dta_link fetches them;
// .onLoad calls it once dtaparser's namespace, and so its library, is
// loaded.

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

typedef int (*abi_fn)(void);
typedef SEXP (*sexp1_fn)(SEXP);
typedef SEXP (*sexp3_fn)(SEXP, SEXP, SEXP);
typedef SEXP (*sexp5_fn)(SEXP, SEXP, SEXP, SEXP, SEXP);

static sexp5_fn fixed_width_fn;
static sexp1_fn parquet_info_fn;
static sexp5_fn parquet_read_fn;
static sexp3_fn parquet_write_fn;

// dtaparser's ABI number, after fetching its callable. R_GetCCallable
// raises an R error for one that is missing.
static SEXP link(void) {
  abi_fn abi = (abi_fn) R_GetCCallable("dtaparser", "dtaparser_abi");
  int found = abi();
  // An older dtaparser has no Parquet callables; .onLoad then refuses it
  // by its ABI number rather than fail here.
  if (found != 3) return Rf_ScalarInteger(found);
  fixed_width_fn = (sexp5_fn) R_GetCCallable("dtaparser", "dtaparser_fixed_width");
  parquet_info_fn = (sexp1_fn) R_GetCCallable("dtaparser", "dtaparser_parquet_info");
  parquet_read_fn = (sexp5_fn) R_GetCCallable("dtaparser", "dtaparser_parquet_read");
  parquet_write_fn = (sexp3_fn) R_GetCCallable("dtaparser", "dtaparser_parquet_write");
  return Rf_ScalarInteger(found);
}

static SEXP fixed_width(SEXP data, SEXP setup, SEXP out, SEXP recodes, SEXP commented_formats) {
  if (!fixed_width_fn) Rf_error("datakit: dtaparser is not linked; reload datakit");
  return fixed_width_fn(data, setup, out, recodes, commented_formats);
}

static void linked(void *fn) {
  if (!fn) Rf_error("datakit: dtaparser is not linked; reload datakit");
}

static SEXP parquet_info(SEXP file) {
  linked(parquet_info_fn);
  return parquet_info_fn(file);
}

static SEXP parquet_read(SEXP file, SEXP cols, SEXP skip, SEXP n_max, SEXP options) {
  linked(parquet_read_fn);
  return parquet_read_fn(file, cols, skip, n_max, options);
}

static SEXP parquet_write(SEXP file, SEXP spec, SEXP options) {
  linked(parquet_write_fn);
  return parquet_write_fn(file, spec, options);
}

static const R_CallMethodDef routines[] = {
  {"dta_link", (DL_FUNC) &link, 0},
  {"dta_fixed_width", (DL_FUNC) &fixed_width, 5},
  {"dta_parquet_info", (DL_FUNC) &parquet_info, 1},
  {"dta_parquet_read", (DL_FUNC) &parquet_read, 5},
  {"dta_parquet_write", (DL_FUNC) &parquet_write, 3},
  {NULL, NULL, 0}
};

void R_init_datakit(DllInfo *dll) {
  R_registerRoutines(dll, NULL, routines, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
