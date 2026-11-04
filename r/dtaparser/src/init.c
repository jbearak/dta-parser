// The C side of dtaparser's bridge to Rust, and the C functions dtatools
// and datakit call through R_GetCCallable (see the end of this file).
//
// R reports errors by jumping (longjmp) up the stack, which must never
// pass through Rust frames. So Rust calls R only through the shims here:
// each runs its R calls under R_UnwindProtect, catches a jump, and
// returns 1 instead, leaving the error in `token`. Rust then returns
// normally, dropping what it holds, and the entry points below resume
// the error with R_ContinueUnwind. Errors of our own come back as a
// message and are raised with Rf_error, also after Rust has returned.

#include <setjmp.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

static SEXP token;

static void on_jump(void *jb, Rboolean jump) {
  if (jump) longjmp(*(jmp_buf *) jb, 1);
}

// Run fn(data); 0 if it returned, 1 if it raised an R error.
static int try_r(SEXP (*fn)(void *), void *data, SEXP *out) {
  jmp_buf jb;
  if (setjmp(jb)) return 1;
  SEXP result = R_UnwindProtect(fn, data, on_jump, &jb, token);
  if (out) *out = result;
  return 0;
}

// Allocate a vector and store it as element i of the list parent.
struct alloc_elt { SEXP parent; R_xlen_t i; SEXPTYPE type; R_xlen_t n; };

static SEXP do_alloc_elt(void *p) {
  struct alloc_elt *a = p;
  return SET_VECTOR_ELT(a->parent, a->i, Rf_allocVector(a->type, a->n));
}

int dtaparser_alloc_elt(SEXP parent, R_xlen_t i, int type, R_xlen_t n, SEXP *out) {
  struct alloc_elt a = {parent, i, (SEXPTYPE) type, n};
  return try_r(do_alloc_elt, &a, out);
}

// Allocate a vector and attach it to x as attribute `name`.
struct alloc_attr { SEXP x; const char *name; SEXPTYPE type; R_xlen_t n; };

static SEXP do_alloc_attr(void *p) {
  struct alloc_attr *a = p;
  SEXP value = PROTECT(Rf_allocVector(a->type, a->n));
  Rf_setAttrib(a->x, Rf_install(a->name), value);
  UNPROTECT(1);
  return value;
}

int dtaparser_alloc_attr(SEXP x, const char *name, int type, R_xlen_t n, SEXP *out) {
  struct alloc_attr a = {x, name, (SEXPTYPE) type, n};
  return try_r(do_alloc_attr, &a, out);
}

// A new packed string column (strings.c), stored as element i of parent.
SEXP dtaparser_new_packed(SEXP parent, R_xlen_t i, R_xlen_t nbytes, R_xlen_t n, R_xlen_t rows, int has_na,
                         SEXP *bytes, SEXP *ends, SEXP *codes);

struct packed { SEXP parent; R_xlen_t i, nbytes, n, rows; int has_na; SEXP *bytes, *ends, *codes; };

static SEXP do_packed(void *p) {
  struct packed *a = p;
  return dtaparser_new_packed(a->parent, a->i, a->nbytes, a->n, a->rows, a->has_na, a->bytes, a->ends, a->codes);
}

int dtaparser_packed_elt(SEXP parent, R_xlen_t i, R_xlen_t nbytes, R_xlen_t n, R_xlen_t rows, int has_na, SEXP *out,
                        SEXP *bytes, SEXP *ends, SEXP *codes) {
  struct packed a = {parent, i, nbytes, n, rows, has_na, bytes, ends, codes};
  return try_r(do_packed, &a, out);
}

// Set x[first + i] to the UTF-8 string bytes[ends[i-1]..ends[i]], for i
// in 0..n. R cannot hold a NUL in a string; one makes this an R error.
struct set_strings { SEXP x; R_xlen_t first; const char *bytes; const size_t *ends; R_xlen_t n; };

static SEXP do_set_strings(void *p) {
  struct set_strings *a = p;
  size_t from = 0;
  for (R_xlen_t i = 0; i < a->n; i++) {
    size_t to = a->ends[i];
    SET_STRING_ELT(a->x, a->first + i, Rf_mkCharLenCE(a->bytes + from, (int) (to - from), CE_UTF8));
    from = to;
  }
  return R_NilValue;
}

int dtaparser_set_strings(SEXP x, R_xlen_t first, const char *bytes, const size_t *ends, R_xlen_t n) {
  struct set_strings a = {x, first, bytes, ends, n};
  return try_r(do_set_strings, &a, NULL);
}

// As set_strings, with NA_STRING where missing[i] is nonzero (the
// value's bytes are then empty).
struct set_strings_na { SEXP x; R_xlen_t first; const char *bytes; const size_t *ends; const unsigned char *missing; R_xlen_t n; };

static SEXP do_set_strings_na(void *p) {
  struct set_strings_na *a = p;
  size_t from = 0;
  for (R_xlen_t i = 0; i < a->n; i++) {
    size_t to = a->ends[i];
    SET_STRING_ELT(a->x, a->first + i,
                   a->missing[i] ? NA_STRING : Rf_mkCharLenCE(a->bytes + from, (int) (to - from), CE_UTF8));
    from = to;
  }
  return R_NilValue;
}

int dtaparser_set_strings_na(SEXP x, R_xlen_t first, const char *bytes, const size_t *ends, const unsigned char *missing,
                             R_xlen_t n) {
  struct set_strings_na a = {x, first, bytes, ends, missing, n};
  return try_r(do_set_strings_na, &a, NULL);
}

// Set elements first..first+n of the list x to raw vectors of
// bytes[ends[i-1]..ends[i]], or NULL where missing[i] is nonzero.
static SEXP do_set_raws(void *p) {
  struct set_strings_na *a = p;
  size_t from = 0;
  for (R_xlen_t i = 0; i < a->n; i++) {
    size_t to = a->ends[i];
    if (!a->missing[i]) {
      SEXP r = SET_VECTOR_ELT(a->x, a->first + i, Rf_allocVector(RAWSXP, (R_xlen_t) (to - from)));
      if (to > from) memcpy(RAW(r), a->bytes + from, to - from);
    }
    from = to;
  }
  return R_NilValue;
}

int dtaparser_set_raws(SEXP x, R_xlen_t first, const char *bytes, const size_t *ends, const unsigned char *missing,
                       R_xlen_t n) {
  struct set_strings_na a = {x, first, bytes, ends, missing, n};
  return try_r(do_set_raws, &a, NULL);
}

// Whether the user has pressed Ctrl-C. R_ToplevelExec stops the
// interrupt's jump at its own frame.
static void check_interrupt(void *unused) {
  (void) unused;
  R_CheckUserInterrupt();
}

int dtaparser_interrupted(void) {
  return R_ToplevelExec(check_interrupt, NULL) == FALSE;
}

// Implemented in Rust: each fills element 0 of `holder` and returns 0,
// 1 with a message in err, or 2 when an R error is waiting in `token`.
int dtaparser_meta(const char *path, const char *encoding, SEXP holder, char *err, size_t err_len);
int dtaparser_read(const char *path, const int *cols, R_xlen_t ncols, double skip, double n_max, const char *encoding,
                   int mode, int threads, SEXP holder, char *err, size_t err_len);
int dtaparser_write(const char *path, SEXP spec, int threads, char *err, size_t err_len);
int dtaparser_fixed_width(const char *data, const char *const *setups, size_t nsetups, const char *out,
                          const char *recodes, int commented_formats, SEXP holder, char *err, size_t err_len);
int dtaparser_parquet_info_rs(const char *path, const unsigned char *raw, size_t raw_len, SEXP holder, char *err,
                              size_t err_len);
int dtaparser_parquet_read_rs(const char *path, const unsigned char *raw, size_t raw_len, SEXP names, double skip,
                              double n_max, int int64, int timestamps, int nested, int threads, SEXP holder, char *err,
                              size_t err_len);
int dtaparser_parquet_write_rs(const char *path, SEXP spec, const char *compression, int level, int has_level,
                               double row_group_size, int missing_letters, int threads, char *err, size_t err_len);

// Threads for a read or write: options(dtaparser.threads) when set to a
// positive number, else 0 (the core's default, or DTA_THREADS). When
// _R_CHECK_LIMIT_CORES_ is set (R CMD check), at most 2.
static int threads_option(void) {
  SEXP opt = Rf_GetOption1(Rf_install("dtaparser.threads"));
  int n = 0;
  if (opt != R_NilValue && (Rf_isInteger(opt) || Rf_isReal(opt)) && XLENGTH(opt) == 1) {
    double v = Rf_asReal(opt);
    if (!ISNAN(v) && v >= 1) n = v > 1024 ? 1024 : (int) v;
  }
  const char *limit = getenv("_R_CHECK_LIMIT_CORES_");
  if (limit && *limit && strcmp(limit, "false") != 0 && strcmp(limit, "FALSE") != 0 && (n == 0 || n > 2)) n = 2;
  return n;
}

static const char *string_arg(SEXP x, const char *what) {
  if (!Rf_isString(x) || XLENGTH(x) < 1 || STRING_ELT(x, 0) == NA_STRING) Rf_error("%s must be a string", what);
  return Rf_translateCharUTF8(STRING_ELT(x, 0));
}

static SEXP finish(int status, SEXP holder, const char *err) {
  if (status == 2) R_ContinueUnwind(token);
  if (status == 1) Rf_error("%s", err);
  SEXP out = VECTOR_ELT(holder, 0);
  UNPROTECT(1);
  return out;
}

// meta, read and dtaparser_dictionary are .Call routines and also
// dtatools' callables, and fixed_width is datakit's callable; their
// errors leave by R's jumps through C frames.
static SEXP meta(SEXP path, SEXP encoding) {
  const char *p = string_arg(path, "file");
  const char *enc = Rf_isNull(encoding) ? NULL : string_arg(encoding, "encoding");
  SEXP holder = PROTECT(Rf_allocVector(VECSXP, 1));
  char err[1024] = "";
  return finish(dtaparser_meta(p, enc, holder, err, sizeof err), holder, err);
}

// mode: 0 plain R types, 1 dtatools' dta_num columns, 2 plain with dates
// converted (Mode in lib.rs).
static SEXP read(SEXP path, SEXP cols, SEXP skip, SEXP n_max, SEXP encoding, SEXP mode) {
  const char *p = string_arg(path, "file");
  const char *enc = Rf_isNull(encoding) ? NULL : string_arg(encoding, "encoding");
  if (TYPEOF(cols) != INTSXP) Rf_error("column indices must be integers");
  double s = Rf_asReal(skip), n = Rf_asReal(n_max);
  if (ISNAN(s) || s < 0 || ISNAN(n) || n < 0) Rf_error("skip and n_max must be numbers >= 0");
  int m = Rf_asInteger(mode);
  SEXP holder = PROTECT(Rf_allocVector(VECSXP, 1));
  char err[1024] = "";
  return finish(dtaparser_read(p, INTEGER(cols), XLENGTH(cols), s, n, enc, m, threads_option(), holder, err, sizeof err), holder, err);
}

// ALTREP vectors (compact sequences, deferred strings) build their data
// when it is first touched, which can allocate and so raise an R error.
// Touch everything here, before Rust borrows it; the data then stays.
static void materialize(SEXP x) {
  switch (TYPEOF(x)) {
  case REALSXP: (void) REAL(x); break;
  case INTSXP: (void) INTEGER(x); break;
  case LGLSXP: (void) LOGICAL(x); break;
  case STRSXP: (void) STRING_PTR_RO(x); break;
  case VECSXP:
    for (R_xlen_t i = 0; i < XLENGTH(x); i++) materialize(VECTOR_ELT(x, i));
    break;
  default: break;
  }
}

int dtaparser_packed_parts(SEXP x, SEXP *bytes, SEXP *ends, SEXP *codes);

static SEXP write(SEXP path, SEXP spec) {
  const char *p = string_arg(path, "file");
  if (TYPEOF(spec) != VECSXP || XLENGTH(spec) < 1 || TYPEOF(VECTOR_ELT(spec, 0)) != VECSXP)
    Rf_error("internal: the write spec must be a list starting with the columns");
  // Data columns that are packed stay packed: Rust reads their text
  // (lib.rs, dtaparser_write). Everything else, including a packed
  // vector anywhere outside spec[[1]], is materialised as before.
  SEXP columns = VECTOR_ELT(spec, 0), unused;
  for (R_xlen_t i = 0; i < XLENGTH(columns); i++) {
    SEXP col = VECTOR_ELT(columns, i);
    if (dtaparser_packed_parts(col, &unused, &unused, &unused) == 0) materialize(col);
  }
  for (R_xlen_t i = 1; i < XLENGTH(spec); i++) materialize(VECTOR_ELT(spec, i));
  char err[1024] = "";
  int status = dtaparser_write(p, spec, threads_option(), err, sizeof err);
  if (status == 2) R_ContinueUnwind(token);
  if (status == 1) Rf_error("%s", err);
  return R_NilValue;
}

// Convert a fixed-width file through its SAS setup file, given as one or
// more files read in order, to the new release 118 file `out`; returns
// the warnings' messages. datakit's read_fixed_width calls it.
static SEXP fixed_width(SEXP data, SEXP setup, SEXP out, SEXP recodes, SEXP commented_formats) {
  const char *d = string_arg(data, "file"), *o = string_arg(out, "out");
  const char *r = string_arg(recodes, "recodes");
  if (!Rf_isString(setup) || XLENGTH(setup) < 1) Rf_error("setup must be one or more paths");
  R_xlen_t n = XLENGTH(setup);
  const char **s = (const char **) R_alloc(n, sizeof(char *));
  for (R_xlen_t i = 0; i < n; i++) {
    if (STRING_ELT(setup, i) == NA_STRING) Rf_error("setup must not be NA");
    s[i] = Rf_translateCharUTF8(STRING_ELT(setup, i));
  }
  int c = Rf_asLogical(commented_formats);
  if (c == NA_LOGICAL) Rf_error("commented_formats must be TRUE or FALSE");
  SEXP holder = PROTECT(Rf_allocVector(VECSXP, 1));
  char err[1024] = "";
  return finish(dtaparser_fixed_width(d, s, (size_t) n, o, r, c, holder, err, sizeof err), holder, err);
}

// Parquet (plan 0018), datakit's read_parquet, read_parquet_info and
// save_parquet. `file` is a path or a raw vector holding a whole file.
static void file_arg(SEXP file, const char **path, const unsigned char **raw, size_t *raw_len) {
  *path = NULL;
  *raw = NULL;
  *raw_len = 0;
  if (TYPEOF(file) == RAWSXP) {
    // A non-NULL pointer even for an empty vector, which says "raw".
    static const unsigned char empty[1] = {0};
    *raw = XLENGTH(file) ? RAW(file) : empty;
    *raw_len = (size_t) XLENGTH(file);
  } else {
    *path = string_arg(file, "file");
  }
}

static SEXP parquet_info(SEXP file) {
  const char *path;
  const unsigned char *raw;
  size_t raw_len;
  file_arg(file, &path, &raw, &raw_len);
  SEXP holder = PROTECT(Rf_allocVector(VECSXP, 1));
  char err[4096] = "";
  return finish(dtaparser_parquet_info_rs(path, raw, raw_len, holder, err, sizeof err), holder, err);
}

// options: an integer vector c(int64, timestamps, nested), as lib.rs's
// dtaparser_parquet_read_rs takes them; cols NULL or column names.
static SEXP parquet_read(SEXP file, SEXP cols, SEXP skip, SEXP n_max, SEXP options) {
  const char *path;
  const unsigned char *raw;
  size_t raw_len;
  file_arg(file, &path, &raw, &raw_len);
  if (!Rf_isNull(cols) && TYPEOF(cols) != STRSXP) Rf_error("columns must be names");
  if (TYPEOF(cols) == STRSXP)
    for (R_xlen_t i = 0; i < XLENGTH(cols); i++)
      if (STRING_ELT(cols, i) == NA_STRING) Rf_error("column names must not be NA");
  if (TYPEOF(options) != INTSXP || XLENGTH(options) != 3) Rf_error("internal: read options must be 3 integers");
  double s = Rf_asReal(skip), n = Rf_asReal(n_max);
  if (ISNAN(s) || s < 0 || ISNAN(n) || n < 0) Rf_error("skip and n_max must be numbers >= 0");
  const int *o = INTEGER(options);
  SEXP holder = PROTECT(Rf_allocVector(VECSXP, 1));
  char err[4096] = "";
  return finish(dtaparser_parquet_read_rs(path, raw, raw_len, cols, s, n, o[0], o[1], o[2], threads_option(), holder,
                                          err, sizeof err),
                holder, err);
}

// options: list(compression, compression_level (NULL or a number),
// row_group_size (NULL or a number), missing_letters).
static SEXP parquet_write(SEXP file, SEXP spec, SEXP options) {
  const char *p = string_arg(file, "file");
  if (TYPEOF(spec) != VECSXP || XLENGTH(spec) < 1 || TYPEOF(VECTOR_ELT(spec, 0)) != VECSXP)
    Rf_error("internal: the write spec must be a list starting with the columns");
  if (TYPEOF(options) != VECSXP || XLENGTH(options) != 4) Rf_error("internal: write options must be a list of 4");
  const char *compression = string_arg(VECTOR_ELT(options, 0), "compression");
  SEXP lv = VECTOR_ELT(options, 1), rg = VECTOR_ELT(options, 2);
  int has_level = !Rf_isNull(lv), level = has_level ? Rf_asInteger(lv) : 0;
  if (has_level && level == NA_INTEGER) Rf_error("compression_level must be a whole number");
  double rows = Rf_isNull(rg) ? R_PosInf : Rf_asReal(rg);
  int letters = Rf_asLogical(VECTOR_ELT(options, 3));
  if (letters == NA_LOGICAL) Rf_error("missing_letters must be TRUE or FALSE");
  // As for save_dta: data columns that are packed stay packed; every
  // other vector, inside lists too, is materialised before Rust borrows
  // it, since the writer's threads read it.
  SEXP columns = VECTOR_ELT(spec, 0), unused;
  for (R_xlen_t i = 0; i < XLENGTH(columns); i++) {
    SEXP col = VECTOR_ELT(columns, i);
    if (dtaparser_packed_parts(col, &unused, &unused, &unused) == 0) materialize(col);
  }
  for (R_xlen_t i = 1; i < XLENGTH(spec); i++) materialize(VECTOR_ELT(spec, i));
  char err[4096] = "";
  int status = dtaparser_parquet_write_rs(p, spec, compression, level, has_level, rows, letters, threads_option(), err,
                                          sizeof err);
  if (status == 2) R_ContinueUnwind(token);
  if (status == 1) Rf_error("%s", err);
  return R_NilValue;
}

// The letter of a tagged NA for .a to .z, or 0: R's NA (low word 1954)
// with a letter in bits 32 to 39, as lib.rs writes them.
static char letter_of(double x) {
  if (!ISNAN(x)) return 0;
  uint64_t bits;
  memcpy(&bits, &x, sizeof bits);
  unsigned tag = (unsigned) ((bits >> 32) & 0xff);
  return (uint32_t) bits == 1954 && tag >= 'a' && tag <= 'z' ? (char) tag : 0;
}

// Whether a double vector holds a tagged NA for .a to .z.
static SEXP has_letters(SEXP x) {
  if (TYPEOF(x) != REALSXP) return Rf_ScalarLogical(FALSE);
  const double *p = REAL_RO(x);
  for (R_xlen_t i = 0, n = XLENGTH(x); i < n; i++) {
    if (letter_of(p[i])) return Rf_ScalarLogical(TRUE);
  }
  return Rf_ScalarLogical(FALSE);
}

// The letter of each element of a double vector ("a" to "z"), NA where
// it is a number or a plain NA. Names are left to the R caller.
static SEXP na_tag(SEXP x) {
  if (TYPEOF(x) != REALSXP) Rf_error("na_tag: x must be a double vector");
  R_xlen_t n = XLENGTH(x);
  const double *p = REAL_RO(x);
  SEXP out = PROTECT(Rf_allocVector(STRSXP, n));
  SEXP letters = PROTECT(Rf_allocVector(STRSXP, 26));
  for (int i = 0; i < 26; i++) {
    char c = (char) ('a' + i);
    SET_STRING_ELT(letters, i, Rf_mkCharLen(&c, 1));
  }
  for (R_xlen_t i = 0; i < n; i++) {
    char c = letter_of(p[i]);
    SET_STRING_ELT(out, i, c ? STRING_ELT(letters, c - 'a') : NA_STRING);
  }
  UNPROTECT(2);
  return out;
}

SEXP dtaparser_packed_state(SEXP x);
SEXP dtaparser_dictionary(SEXP x);
void dtaparser_init_packed(DllInfo *dll);

static const R_CallMethodDef routines[] = {
  {"dta_packed_state", (DL_FUNC) &dtaparser_packed_state, 1},
  {"dta_dictionary", (DL_FUNC) &dtaparser_dictionary, 1},
  {"dta_meta", (DL_FUNC) &meta, 2},
  {"dta_read", (DL_FUNC) &read, 6},
  {"dta_write", (DL_FUNC) &write, 2},
  {"dta_has_letters", (DL_FUNC) &has_letters, 1},
  {"dta_na_tag", (DL_FUNC) &na_tag, 1},
  {"dta_parquet_info", (DL_FUNC) &parquet_info, 1},
  {"dta_parquet_read", (DL_FUNC) &parquet_read, 5},
  {"dta_parquet_write", (DL_FUNC) &parquet_write, 3},
  {NULL, NULL, 0}
};

// dtatools and datakit refuse to run against a dtaparser whose number
// differs from the one they were built for. Bump it when a callable
// changes. 2: dtaparser_write went (dtatools calls save_dta) and
// dtaparser_fixed_width came (datakit's read_fixed_width). 3:
// dtaparser_parquet_read, dtaparser_parquet_write and
// dtaparser_parquet_info came (datakit's Parquet functions), and packed
// columns may hold NA.
static int abi(void) {
  return 3;
}

void R_init_dtaparser(DllInfo *dll) {
  token = R_MakeUnwindCont();
  R_PreserveObject(token);
  dtaparser_init_packed(dll);
  R_RegisterCCallable("dtaparser", "dtaparser_abi", (DL_FUNC) &abi);
  R_RegisterCCallable("dtaparser", "dtaparser_meta", (DL_FUNC) &meta);
  R_RegisterCCallable("dtaparser", "dtaparser_read", (DL_FUNC) &read);
  R_RegisterCCallable("dtaparser", "dtaparser_fixed_width", (DL_FUNC) &fixed_width);
  R_RegisterCCallable("dtaparser", "dtaparser_dictionary", (DL_FUNC) &dtaparser_dictionary);
  R_RegisterCCallable("dtaparser", "dtaparser_parquet_info", (DL_FUNC) &parquet_info);
  R_RegisterCCallable("dtaparser", "dtaparser_parquet_read", (DL_FUNC) &parquet_read);
  R_RegisterCCallable("dtaparser", "dtaparser_parquet_write", (DL_FUNC) &parquet_write);
  R_registerRoutines(dll, NULL, routines, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
