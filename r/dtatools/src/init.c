// The C side of dtatools' bridge to Rust.
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

int dtatools_alloc_elt(SEXP parent, R_xlen_t i, int type, R_xlen_t n, SEXP *out) {
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

int dtatools_alloc_attr(SEXP x, const char *name, int type, R_xlen_t n, SEXP *out) {
  struct alloc_attr a = {x, name, (SEXPTYPE) type, n};
  return try_r(do_alloc_attr, &a, out);
}

// A new packed string column (strings.c), stored as element i of parent.
SEXP dtatools_new_packed(SEXP parent, R_xlen_t i, R_xlen_t nbytes, R_xlen_t n, R_xlen_t rows, SEXP *bytes,
                         SEXP *ends, SEXP *codes);

struct packed { SEXP parent; R_xlen_t i, nbytes, n, rows; SEXP *bytes, *ends, *codes; };

static SEXP do_packed(void *p) {
  struct packed *a = p;
  return dtatools_new_packed(a->parent, a->i, a->nbytes, a->n, a->rows, a->bytes, a->ends, a->codes);
}

int dtatools_packed_elt(SEXP parent, R_xlen_t i, R_xlen_t nbytes, R_xlen_t n, R_xlen_t rows, SEXP *out, SEXP *bytes,
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

int dtatools_set_strings(SEXP x, R_xlen_t first, const char *bytes, const size_t *ends, R_xlen_t n) {
  struct set_strings a = {x, first, bytes, ends, n};
  return try_r(do_set_strings, &a, NULL);
}

// Whether the user has pressed Ctrl-C. R_ToplevelExec stops the
// interrupt's jump at its own frame.
static void check_interrupt(void *unused) {
  (void) unused;
  R_CheckUserInterrupt();
}

int dtatools_interrupted(void) {
  return R_ToplevelExec(check_interrupt, NULL) == FALSE;
}

// Implemented in Rust: each fills element 0 of `holder` and returns 0,
// 1 with a message in err, or 2 when an R error is waiting in `token`.
int dtatools_meta(const char *path, const char *encoding, SEXP holder, char *err, size_t err_len);
int dtatools_read(const char *path, const int *cols, R_xlen_t ncols, const char *encoding, SEXP holder,
                  char *err, size_t err_len);
int dtatools_write(const char *path, SEXP spec, char *err, size_t err_len);

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

static SEXP meta(SEXP path, SEXP encoding) {
  const char *p = string_arg(path, "file");
  const char *enc = Rf_isNull(encoding) ? NULL : string_arg(encoding, "encoding");
  SEXP holder = PROTECT(Rf_allocVector(VECSXP, 1));
  char err[1024] = "";
  return finish(dtatools_meta(p, enc, holder, err, sizeof err), holder, err);
}

static SEXP read(SEXP path, SEXP cols, SEXP encoding) {
  const char *p = string_arg(path, "file");
  const char *enc = Rf_isNull(encoding) ? NULL : string_arg(encoding, "encoding");
  if (TYPEOF(cols) != INTSXP) Rf_error("column indices must be integers");
  SEXP holder = PROTECT(Rf_allocVector(VECSXP, 1));
  char err[1024] = "";
  return finish(dtatools_read(p, INTEGER(cols), XLENGTH(cols), enc, holder, err, sizeof err), holder, err);
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

static SEXP write(SEXP path, SEXP spec) {
  const char *p = string_arg(path, "file");
  if (TYPEOF(spec) != VECSXP) Rf_error("internal: the write spec must be a list");
  materialize(spec);
  char err[1024] = "";
  int status = dtatools_write(p, spec, err, sizeof err);
  if (status == 2) R_ContinueUnwind(token);
  if (status == 1) Rf_error("%s", err);
  return R_NilValue;
}

SEXP dtatools_codes(SEXP x);
SEXP dtatools_keys(SEXP x, SEXP keep_na);
SEXP dtatools_missing(SEXP codes);
SEXP dtatools_packed_state(SEXP x);
SEXP dtatools_dictionary(SEXP x);
void dtatools_init_packed(DllInfo *dll);

static const R_CallMethodDef routines[] = {
  {"dta_codes", (DL_FUNC) &dtatools_codes, 1},
  {"dta_keys", (DL_FUNC) &dtatools_keys, 2},
  {"dta_missing", (DL_FUNC) &dtatools_missing, 1},
  {"dta_packed_state", (DL_FUNC) &dtatools_packed_state, 1},
  {"dta_dictionary", (DL_FUNC) &dtatools_dictionary, 1},
  {"dta_meta", (DL_FUNC) &meta, 2},
  {"dta_read", (DL_FUNC) &read, 3},
  {"dta_write", (DL_FUNC) &write, 2},
  {NULL, NULL, 0}
};

void R_init_dtatools(DllInfo *dll) {
  token = R_MakeUnwindCont();
  R_PreserveObject(token);
  dtatools_init_packed(dll);
  R_registerRoutines(dll, NULL, routines, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
