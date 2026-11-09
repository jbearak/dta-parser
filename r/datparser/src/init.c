// The C side of datparser's bridge to Rust (src/rust/lib.rs). Rust reads
// the file into a table and never calls R; this file makes the R vectors
// and asks Rust for their values. The table lives in an external pointer
// whose finalizer frees it, so an R error here (out of memory, Ctrl-C)
// cannot leak it.

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

typedef struct Setup Setup;
typedef struct Table Table;

int datparser_setup(const char *const *setups, size_t nsetups, int commented_formats, Setup **out, char *err,
                    size_t err_len);
int datparser_read(Setup *setup, const char *data, const char *recodes, const int *cols, size_t ncols, Table **out,
                   char *err, size_t err_len);
void datparser_free_setup(Setup *s);
void datparser_free_table(Table *t);
size_t datparser_setup_ncols(const Setup *s);
void datparser_setup_name(const Setup *s, size_t i, const char **ptr, size_t *len);
size_t datparser_nrows(const Table *t);
size_t datparser_nwarnings(const Table *t);
void datparser_warning(const Table *t, size_t i, const char **ptr, size_t *len);
void datparser_label(const Table *t, size_t k, const char **ptr, size_t *len);
int datparser_kind(const Table *t, size_t k, size_t first, size_t n);
int datparser_fill(const Table *t, size_t m, const size_t *ks, const int *kinds, void *const *outs, size_t first,
                   size_t n);
void datparser_string(const Table *t, size_t k, size_t row, const char **ptr, size_t *len);
size_t datparser_nlabels(const Table *t, size_t k);
void datparser_value_label(const Table *t, size_t k, size_t i, double *code, const char **ptr, size_t *len);

// Rows filled between checks for Ctrl-C.
#define CHUNK 65536

// Whether the doubles x hold a tagged NA for .a to .z: R's NA (low word
// 1954) with a lower-case letter in bits 32 to 39.
static int has_letters(SEXP x) {
  if (TYPEOF(x) != REALSXP) return 0;
  const double *v = REAL(x);
  for (R_xlen_t i = 0; i < XLENGTH(x); i++) {
    uint64_t bits;
    memcpy(&bits, v + i, sizeof bits);
    unsigned tag = (unsigned) ((bits >> 32) & 0xff);
    if ((uint32_t) bits == 1954 && tag >= 'a' && tag <= 'z' && ISNAN(v[i])) return 1;
  }
  return 0;
}

static SEXP utf8(const char *p, size_t n) {
  if (n > INT_MAX) Rf_error("a string is too long for R");
  return Rf_mkCharLenCE(p, (int) n, CE_UTF8);
}

static const char **paths_arg(SEXP setup) {
  if (!Rf_isString(setup) || XLENGTH(setup) < 1) Rf_error("setup must be one or more paths");
  R_xlen_t n = XLENGTH(setup);
  const char **s = (const char **) R_alloc(n, sizeof(char *));
  for (R_xlen_t i = 0; i < n; i++) {
    if (STRING_ELT(setup, i) == NA_STRING) Rf_error("setup must not be NA");
    s[i] = Rf_translateCharUTF8(STRING_ELT(setup, i));
  }
  return s;
}

static const char *string_arg(SEXP x, const char *what) {
  if (!Rf_isString(x) || XLENGTH(x) != 1 || STRING_ELT(x, 0) == NA_STRING) Rf_error("%s must be a string", what);
  return Rf_translateCharUTF8(STRING_ELT(x, 0));
}

static int flag_arg(SEXP x, const char *what) {
  int c = Rf_asLogical(x);
  if (c == NA_LOGICAL) Rf_error("%s must be TRUE or FALSE", what);
  return c;
}

static void free_setup(SEXP p) {
  datparser_free_setup((Setup *) R_ExternalPtrAddr(p));
  R_ClearExternalPtr(p);
}

static void free_table(SEXP p) {
  datparser_free_table((Table *) R_ExternalPtrAddr(p));
  R_ClearExternalPtr(p);
}

// The setup files, parsed, as an external pointer for fw_names and
// fw_read.
static SEXP fw_setup(SEXP setup, SEXP commented_formats) {
  const char **s = paths_arg(setup);
  int c = flag_arg(commented_formats, "commented_formats");
  // The pointer and its finalizer exist before Rust makes the setup, so
  // no R allocation can fail while Rust's object has no owner.
  SEXP out = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
  R_RegisterCFinalizerEx(out, free_setup, TRUE);
  char err[1024] = "";
  Setup *parsed = NULL;
  if (datparser_setup(s, (size_t) XLENGTH(setup), c, &parsed, err, sizeof err)) Rf_error("%s", err);
  R_SetExternalPtrAddr(out, parsed);
  UNPROTECT(1);
  return out;
}

static Setup *setup_arg(SEXP p) {
  if (TYPEOF(p) != EXTPTRSXP || !R_ExternalPtrAddr(p)) Rf_error("internal: the setup was used already");
  return (Setup *) R_ExternalPtrAddr(p);
}

// The names of the variables a parsed setup defines.
static SEXP fw_names(SEXP p) {
  Setup *s = setup_arg(p);
  size_t n = datparser_setup_ncols(s);
  SEXP out = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) n));
  for (size_t i = 0; i < n; i++) {
    const char *ptr;
    size_t len;
    datparser_setup_name(s, i, &ptr, &len);
    SET_STRING_ELT(out, (R_xlen_t) i, utf8(ptr, len));
  }
  UNPROTECT(1);
  return out;
}

// One column of kind `kind` (0 integers, 1 doubles, 2 strings): rows
// first..first + n of variable k, with its attributes `label` and
// `labels` (the codes, .a to .z tagged, named by their text). A string
// column is filled here, a numeric one by fw_read.
static SEXP column(const Table *t, size_t k, size_t first, size_t n, int kind) {
  const char *p;
  size_t len;
  SEXP x;
  if (kind == 2) {
    x = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) n));
    for (size_t i = 0; i < n; i++) {
      if (i % CHUNK == 0) R_CheckUserInterrupt();
      datparser_string(t, k, first + i, &p, &len);
      SET_STRING_ELT(x, (R_xlen_t) i, utf8(p, len));
    }
  } else {
    // Filled with the other numeric columns, by fw_read.
    x = PROTECT(Rf_allocVector(kind == 0 ? INTSXP : REALSXP, (R_xlen_t) n));
  }
  datparser_label(t, k, &p, &len);
  if (len) {
    SEXP label = PROTECT(Rf_ScalarString(utf8(p, len)));
    Rf_setAttrib(x, Rf_install("label"), label);
    UNPROTECT(1);
  }
  size_t nl = datparser_nlabels(t, k);
  if (nl) {
    SEXP codes = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) nl));
    SEXP texts = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) nl));
    for (size_t i = 0; i < nl; i++) {
      datparser_value_label(t, k, i, REAL(codes) + i, &p, &len);
      SET_STRING_ELT(texts, (R_xlen_t) i, utf8(p, len));
    }
    Rf_setAttrib(codes, R_NamesSymbol, texts);
    Rf_setAttrib(x, Rf_install("labels"), codes);
    UNPROTECT(2);
  }
  UNPROTECT(1);
  return x;
}

// Read `data` through the parsed setup `setup`, which this uses up: the
// variables at the 0-based `cols`, from row `skip` (0-based), at most
// `n_max` rows. Returns list(columns, nrow, letters, warnings): `letters`
// says which columns hold .a to .z in the rows read.
static SEXP fw_read(SEXP setup, SEXP data, SEXP recodes, SEXP cols, SEXP skip, SEXP n_max) {
  const char *d = string_arg(data, "file");
  const char *r = string_arg(recodes, "recodes");
  if (TYPEOF(cols) != INTSXP) Rf_error("cols must be integers");
  double sk = Rf_asReal(skip), nm = Rf_asReal(n_max);
  if (ISNAN(sk) || sk < 0 || ISNAN(nm) || nm < 0) Rf_error("skip and n_max must be numbers >= 0");
  Setup *s = setup_arg(setup);
  R_xlen_t ncols = XLENGTH(cols);
  SEXP holder = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
  R_RegisterCFinalizerEx(holder, free_table, TRUE);
  R_ClearExternalPtr(setup);  // datparser_read takes it
  char err[1024] = "";
  Table *t = NULL;
  if (datparser_read(s, d, r, INTEGER(cols), (size_t) ncols, &t, err, sizeof err)) Rf_error("%s", err);
  R_SetExternalPtrAddr(holder, t);
  size_t nrows = datparser_nrows(t);
  size_t first = sk >= (double) nrows ? nrows : (size_t) sk;
  size_t n = nrows - first;
  if (nm < (double) n) n = (size_t) nm;

  const char *names[] = {"columns", "nrow", "letters", "warnings", ""};
  SEXP out = PROTECT(Rf_mkNamed(VECSXP, names));
  SEXP columns = Rf_allocVector(VECSXP, ncols);
  SET_VECTOR_ELT(out, 0, columns);
  SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double) n));
  size_t *ks = (size_t *) R_alloc(ncols ? ncols : 1, sizeof(size_t));
  int *kinds = (int *) R_alloc(ncols ? ncols : 1, sizeof(int));
  void **outs = (void **) R_alloc(ncols ? ncols : 1, sizeof(void *));
  size_t m = 0;
  for (R_xlen_t j = 0; j < ncols; j++) {
    size_t k = (size_t) INTEGER(cols)[j];
    int kind = datparser_kind(t, k, first, n);
    SEXP x = column(t, k, first, n, kind);
    SET_VECTOR_ELT(columns, j, x);
    if (kind != 2) {
      ks[m] = k;
      kinds[m] = kind;
      outs[m] = kind == 0 ? (void *) INTEGER(x) : (void *) REAL(x);
      m++;
    }
  }
  R_CheckUserInterrupt();
  if (datparser_fill(t, m, ks, kinds, outs, first, n)) Rf_error("internal error in datparser's Rust code");
  SEXP letters = Rf_allocVector(LGLSXP, ncols);
  SET_VECTOR_ELT(out, 2, letters);
  for (R_xlen_t j = 0; j < ncols; j++) LOGICAL(letters)[j] = has_letters(VECTOR_ELT(columns, j));
  size_t nw = datparser_nwarnings(t);
  SEXP warnings = Rf_allocVector(STRSXP, (R_xlen_t) nw);
  SET_VECTOR_ELT(out, 3, warnings);
  for (size_t i = 0; i < nw; i++) {
    const char *p;
    size_t len;
    datparser_warning(t, i, &p, &len);
    SET_STRING_ELT(warnings, (R_xlen_t) i, utf8(p, len));
  }
  free_table(holder);
  UNPROTECT(2);
  return out;
}

static const R_CallMethodDef routines[] = {
  {"fw_setup", (DL_FUNC) &fw_setup, 2},
  {"fw_names", (DL_FUNC) &fw_names, 1},
  {"fw_read", (DL_FUNC) &fw_read, 6},
  {NULL, NULL, 0}
};

void R_init_datparser(DllInfo *dll) {
  R_registerRoutines(dll, NULL, routines, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
