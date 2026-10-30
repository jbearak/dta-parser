// The C side of dtaparser's bridge to Rust, and the C functions dtatools
// calls through R_GetCCallable (see the end of this file).
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
SEXP dtaparser_new_packed(SEXP parent, R_xlen_t i, R_xlen_t nbytes, R_xlen_t n, R_xlen_t rows, SEXP *bytes,
                         SEXP *ends, SEXP *codes);

struct packed { SEXP parent; R_xlen_t i, nbytes, n, rows; SEXP *bytes, *ends, *codes; };

static SEXP do_packed(void *p) {
  struct packed *a = p;
  return dtaparser_new_packed(a->parent, a->i, a->nbytes, a->n, a->rows, a->bytes, a->ends, a->codes);
}

int dtaparser_packed_elt(SEXP parent, R_xlen_t i, R_xlen_t nbytes, R_xlen_t n, R_xlen_t rows, SEXP *out, SEXP *bytes,
                        SEXP *ends, SEXP *codes) {
  struct packed a = {parent, i, nbytes, n, rows, bytes, ends, codes};
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

// meta, read, write and dtaparser_dictionary are .Call routines and also
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

// Whether a double vector holds a tagged NA for .a to .z: R's NA (low
// word 1954) with a letter in bits 32 to 39, as lib.rs writes them.
static SEXP has_letters(SEXP x) {
  if (TYPEOF(x) != REALSXP) return Rf_ScalarLogical(FALSE);
  const double *p = REAL_RO(x);
  for (R_xlen_t i = 0, n = XLENGTH(x); i < n; i++) {
    if (!ISNAN(p[i])) continue;
    uint64_t bits;
    memcpy(&bits, &p[i], sizeof bits);
    unsigned tag = (unsigned) ((bits >> 32) & 0xff);
    if ((uint32_t) bits == 1954 && tag >= 'a' && tag <= 'z') return Rf_ScalarLogical(TRUE);
  }
  return Rf_ScalarLogical(FALSE);
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
  {NULL, NULL, 0}
};

// dtatools refuses to run against a dtaparser whose number differs from
// the one it was built for. Bump it when a callable changes.
static int abi(void) {
  return 1;
}

void R_init_dtaparser(DllInfo *dll) {
  token = R_MakeUnwindCont();
  R_PreserveObject(token);
  dtaparser_init_packed(dll);
  R_RegisterCCallable("dtaparser", "dtaparser_abi", (DL_FUNC) &abi);
  R_RegisterCCallable("dtaparser", "dtaparser_meta", (DL_FUNC) &meta);
  R_RegisterCCallable("dtaparser", "dtaparser_read", (DL_FUNC) &read);
  R_RegisterCCallable("dtaparser", "dtaparser_write", (DL_FUNC) &write);
  R_RegisterCCallable("dtaparser", "dtaparser_dictionary", (DL_FUNC) &dtaparser_dictionary);
  R_registerRoutines(dll, NULL, routines, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
