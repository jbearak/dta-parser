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

// A jump that does not save or restore the signal mask: setjmp does on
// macOS, a system call each time, and the shims below run thousands of
// times in one read of a wide file.
#ifdef _WIN32
typedef jmp_buf shim_jmp_buf;
#define SHIM_SETJMP(jb) setjmp(jb)
#define SHIM_LONGJMP(jb) longjmp(jb, 1)
#else
typedef sigjmp_buf shim_jmp_buf;
#define SHIM_SETJMP(jb) sigsetjmp(jb, 0)
#define SHIM_LONGJMP(jb) siglongjmp(jb, 1)
#endif

static void on_jump(void *jb, Rboolean jump) {
  if (jump) SHIM_LONGJMP(*(shim_jmp_buf *) jb);
}

// Run fn(data); 0 if it returned, 1 if it raised an R error.
static int try_r(SEXP (*fn)(void *), void *data, SEXP *out) {
  shim_jmp_buf jb;
  if (SHIM_SETJMP(jb)) return 1;
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

// Make room in R's vector heap for about `bytes` of vectors about to be
// allocated. R grows the heap a step at a time, with a full collection
// at each step: allocating the output of a 600 MB read in a new session
// took 13 collections. Allocating one vector of that size, never
// written (so never resident) and dropped at once, grows the heap in
// one; a cold read of long.dta's Parquet file then took 5.
static SEXP do_reserve(void *p) {
  return Rf_allocVector(RAWSXP, *(R_xlen_t *) p);
}

int dtaparser_reserve(R_xlen_t bytes) {
  return try_r(do_reserve, &bytes, NULL);
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

// Set attribute `name` of x to value, which is already reachable (an
// attribute of another column), so that columns share it.
struct set_attr { SEXP x; const char *name; SEXP value; };

static SEXP do_set_attr(void *p) {
  struct set_attr *a = p;
  Rf_setAttrib(a->x, Rf_install(a->name), a->value);
  return R_NilValue;
}

int dtaparser_set_attr(SEXP x, const char *name, SEXP value) {
  struct set_attr a = {x, name, value};
  return try_r(do_set_attr, &a, NULL);
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
int dtaparser_parquet_info_rs(const char *path, const unsigned char *raw, size_t raw_len, SEXP holder, char *err,
                              size_t err_len);
int dtaparser_parquet_read_rs(const char *path, const unsigned char *raw, size_t raw_len, SEXP names,
                              const char *prefer, double skip, double n_max, int int64, int timestamps, int nested,
                              int decimal, int threads, SEXP holder, char *err, size_t err_len);
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
// dtatools' callables; their errors leave by R's jumps through C frames.
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

// options: an integer vector c(int64, timestamps, nested, decimal), as
// parquet_r.rs's dtaparser_parquet_read_rs takes them; cols NULL or
// column names. When cols has a "prefer" attribute (the name of the
// variable that held them), a column of that name, if the file has one,
// is read instead, as tidyselect would pick it.
static SEXP parquet_read(SEXP file, SEXP cols, SEXP skip, SEXP n_max, SEXP options) {
  const char *path;
  const unsigned char *raw;
  size_t raw_len;
  file_arg(file, &path, &raw, &raw_len);
  if (!Rf_isNull(cols) && TYPEOF(cols) != STRSXP) Rf_error("columns must be names");
  if (TYPEOF(cols) == STRSXP)
    for (R_xlen_t i = 0; i < XLENGTH(cols); i++)
      if (STRING_ELT(cols, i) == NA_STRING) Rf_error("column names must not be NA");
  if (TYPEOF(options) != INTSXP || XLENGTH(options) != 4) Rf_error("internal: read options must be 4 integers");
  double s = Rf_asReal(skip), n = Rf_asReal(n_max);
  if (ISNAN(s) || s < 0 || ISNAN(n) || n < 0) Rf_error("skip and n_max must be numbers >= 0");
  const int *o = INTEGER(options);
  const char *prefer = NULL;
  if (TYPEOF(cols) == STRSXP) {
    SEXP p = Rf_getAttrib(cols, Rf_install("prefer"));
    if (Rf_isString(p) && XLENGTH(p) == 1 && STRING_ELT(p, 0) != NA_STRING) prefer = Rf_translateCharUTF8(STRING_ELT(p, 0));
  }
  SEXP holder = PROTECT(Rf_allocVector(VECSXP, 1));
  char err[4096] = "";
  return finish(dtaparser_parquet_read_rs(path, raw, raw_len, cols, prefer, s, n, o[0], o[1], o[2], o[3],
                                          threads_option(), holder, err, sizeof err),
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

// Each element's place in Stata's missing-value order, as a plain
// integer vector: 0 for a number, 1 for `.` (NA or any other NaN), 2 to
// 27 for .a to .z. The letter is read before the NaN test, as a tagged
// NA is a NaN. An integer or logical vector holds no letter.
static SEXP missing_rank(SEXP x) {
  R_xlen_t n = XLENGTH(x);
  SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
  int *o = INTEGER(out);
  switch (TYPEOF(x)) {
  case REALSXP: {
    const double *p = REAL_RO(x);
    for (R_xlen_t i = 0; i < n; i++) {
      char c = letter_of(p[i]);
      o[i] = c ? c - 'a' + 2 : ISNAN(p[i]);
    }
    break;
  }
  case INTSXP: {
    const int *p = INTEGER_RO(x);
    for (R_xlen_t i = 0; i < n; i++) o[i] = p[i] == NA_INTEGER;
    break;
  }
  case LGLSXP: {
    const int *p = LOGICAL_RO(x);
    for (R_xlen_t i = 0; i < n; i++) o[i] = p[i] == NA_LOGICAL;
    break;
  }
  default:
    Rf_error("missing_rank: x must be a double, integer or logical vector");
  }
  UNPROTECT(1);
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
  {"dta_missing_rank", (DL_FUNC) &missing_rank, 1},
  {NULL, NULL, 0}
};

// dtatools and datakit refuse to run against a dtaparser whose number
// differs from the one they were built for. Bump it when a callable
// changes. 2: dtaparser_write went (dtatools calls save_dta) and
// dtaparser_fixed_width came (datakit's read_fixed_width). 3:
// dtaparser_parquet_read, dtaparser_parquet_write and
// dtaparser_parquet_info came (datakit's Parquet functions), and packed
// columns may hold NA. dtaparser_fixed_width went in 3.2.0 without a new
// number (datparser reads fixed-width files, ADR 0039): no package of
// 3.2.0 fetches it, and a datakit 3.1.0 that does fails to link and
// reports the mismatch as if the number differed.
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
  R_RegisterCCallable("dtaparser", "dtaparser_dictionary", (DL_FUNC) &dtaparser_dictionary);
  R_RegisterCCallable("dtaparser", "dtaparser_parquet_info", (DL_FUNC) &parquet_info);
  R_RegisterCCallable("dtaparser", "dtaparser_parquet_read", (DL_FUNC) &parquet_read);
  R_RegisterCCallable("dtaparser", "dtaparser_parquet_write", (DL_FUNC) &parquet_write);
  R_registerRoutines(dll, NULL, routines, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
