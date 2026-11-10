// datakit reads Parquet files through dtaparser (plan 0018), and polars
// frames through its Arrow streams (plan 0025): the routines here
// forward to the C functions dtaparser registers with
// R_RegisterCCallable. dta_link fetches them;
// .onLoad calls it once dtaparser's namespace, and so its library, is
// loaded.

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

typedef int (*abi_fn)(void);
typedef SEXP (*sexp1_fn)(SEXP);
typedef SEXP (*sexp3_fn)(SEXP, SEXP, SEXP);
typedef SEXP (*sexp4_fn)(SEXP, SEXP, SEXP, SEXP);
typedef SEXP (*sexp5_fn)(SEXP, SEXP, SEXP, SEXP, SEXP);
typedef SEXP (*sexp7_fn)(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
typedef SEXP (*sexp8_fn)(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);

static sexp1_fn parquet_info_fn;
static sexp5_fn parquet_read_fn;
static sexp3_fn parquet_write_fn;
static sexp7_fn parquet_read_arrow_fn;
static sexp8_fn dta_read_arrow_fn;
static sexp4_fn parquet_write_arrow_fn;
static sexp4_fn dta_write_arrow_fn;
static sexp5_fn fixed_width_dta_fn;

// dtaparser's ABI number, after fetching its callable. R_GetCCallable
// raises an R error for one that is missing.
static SEXP link(void) {
  abi_fn abi = (abi_fn) R_GetCCallable("dtaparser", "dtaparser_abi");
  int found = abi();
  // An older dtaparser lacks some of these callables; .onLoad then
  // refuses it by its ABI number rather than fail here.
  if (found != 4) return Rf_ScalarInteger(found);
  parquet_info_fn = (sexp1_fn) R_GetCCallable("dtaparser", "dtaparser_parquet_info");
  parquet_read_fn = (sexp5_fn) R_GetCCallable("dtaparser", "dtaparser_parquet_read");
  parquet_write_fn = (sexp3_fn) R_GetCCallable("dtaparser", "dtaparser_parquet_write");
  parquet_read_arrow_fn = (sexp7_fn) R_GetCCallable("dtaparser", "dtaparser_parquet_read_arrow");
  dta_read_arrow_fn = (sexp8_fn) R_GetCCallable("dtaparser", "dtaparser_dta_read_arrow");
  parquet_write_arrow_fn = (sexp4_fn) R_GetCCallable("dtaparser", "dtaparser_parquet_write_arrow");
  dta_write_arrow_fn = (sexp4_fn) R_GetCCallable("dtaparser", "dtaparser_dta_write_arrow");
  fixed_width_dta_fn = (sexp5_fn) R_GetCCallable("dtaparser", "dtaparser_fixed_width_dta");
  return Rf_ScalarInteger(found);
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

static SEXP parquet_read_arrow(SEXP file, SEXP cols, SEXP skip, SEXP n_max, SEXP options, SEXP data, SEXP letters) {
  linked(parquet_read_arrow_fn);
  return parquet_read_arrow_fn(file, cols, skip, n_max, options, data, letters);
}

static SEXP dta_read_arrow(SEXP file, SEXP cols, SEXP skip, SEXP n_max, SEXP encoding, SEXP timestamps, SEXP data,
                           SEXP letters) {
  linked(dta_read_arrow_fn);
  return dta_read_arrow_fn(file, cols, skip, n_max, encoding, timestamps, data, letters);
}

static SEXP parquet_write_arrow(SEXP stream, SEXP file, SEXP meta, SEXP options) {
  linked(parquet_write_arrow_fn);
  return parquet_write_arrow_fn(stream, file, meta, options);
}

static SEXP dta_write_arrow(SEXP stream, SEXP file, SEXP meta, SEXP options) {
  linked(dta_write_arrow_fn);
  return dta_write_arrow_fn(stream, file, meta, options);
}

static SEXP fixed_width_dta(SEXP data, SEXP setup, SEXP out, SEXP recodes, SEXP commented_formats) {
  linked(fixed_width_dta_fn);
  return fixed_width_dta_fn(data, setup, out, recodes, commented_formats);
}

SEXP dta_na_groups_tagged(SEXP x, SEXP key, SEXP loc);
SEXP dta_meta_columns(SEXP names, SEXP label, SEXP format, SEXP value_labels, SEXP ordered);

static const R_CallMethodDef routines[] = {
  {"dta_link", (DL_FUNC) &link, 0},
  {"dta_parquet_info", (DL_FUNC) &parquet_info, 1},
  {"dta_parquet_read", (DL_FUNC) &parquet_read, 5},
  {"dta_parquet_write", (DL_FUNC) &parquet_write, 3},
  {"dta_parquet_read_arrow", (DL_FUNC) &parquet_read_arrow, 7},
  {"dta_dta_read_arrow", (DL_FUNC) &dta_read_arrow, 8},
  {"dta_parquet_write_arrow", (DL_FUNC) &parquet_write_arrow, 4},
  {"dta_dta_write_arrow", (DL_FUNC) &dta_write_arrow, 4},
  {"dta_fixed_width_dta", (DL_FUNC) &fixed_width_dta, 5},
  {"dta_na_groups_tagged", (DL_FUNC) &dta_na_groups_tagged, 3},
  {"dta_meta_columns", (DL_FUNC) &dta_meta_columns, 5},
  {NULL, NULL, 0}
};

void R_init_datakit(DllInfo *dll) {
  R_registerRoutines(dll, NULL, routines, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
