// Packed string columns: read_dta's character vectors keep their text as
// the UTF-8 bytes read from the file and make R strings only when R asks
// for them. Making 10M distinct R strings costs seconds (each is hashed
// into R's global string cache and traced by its collector); a column
// most code only filters, slices or looks at the head of need not pay
// that at read time.
//
// A column is an ALTREP character vector in one of two states:
//
// - packed: data1 is list(bytes, ends), a raw vector of the text and a
//   double vector of each value's end offset; data2 is R_NilValue or a
//   cache, a character vector holding the strings made so far and
//   NA_STRING where none is made yet (Stata strings are never NA).
// - made: data1 is R_NilValue and data2 holds every string; the column is
//   an ordinary character vector behind one indirection. It may hold NAs
//   assigned since.
//
// Written from R's R_ext/Altrep.h; R's deferred strings, vroom and arrow
// informed the design.

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Altrep.h>
#include <R_ext/Rdynload.h>

static R_altrep_class_t packed_class;

#define PACKED(x) (R_altrep_data1(x) != R_NilValue)
#define BYTES(x) VECTOR_ELT(R_altrep_data1(x), 0)
#define ENDS(x) VECTOR_ELT(R_altrep_data1(x), 1)

static R_xlen_t packed_length(SEXP x) {
  return PACKED(x) ? XLENGTH(ENDS(x)) : XLENGTH(R_altrep_data2(x));
}

// The cache, allocated and attached on first use.
static SEXP cache_of(SEXP x) {
  SEXP cache = R_altrep_data2(x);
  if (cache != R_NilValue) return cache;
  R_xlen_t n = XLENGTH(ENDS(x));
  cache = PROTECT(Rf_allocVector(STRSXP, n));
  for (R_xlen_t i = 0; i < n; i++) SET_STRING_ELT(cache, i, NA_STRING);
  R_set_altrep_data2(x, cache);
  UNPROTECT(1);
  return cache;
}

// The string at i of a packed column, made and cached if need be.
static SEXP packed_make(SEXP x, SEXP cache, R_xlen_t i) {
  SEXP s = STRING_ELT(cache, i);
  if (s != NA_STRING) return s;
  const double *ends = REAL(ENDS(x));
  R_xlen_t from = i == 0 ? 0 : (R_xlen_t) ends[i - 1];
  const char *bytes = (const char *) RAW(BYTES(x));
  // read_dta checked that each value fits an R string and holds no NUL.
  s = Rf_mkCharLenCE(bytes + from, (int) ((R_xlen_t) ends[i] - from), CE_UTF8);
  SET_STRING_ELT(cache, i, s);
  return s;
}

static SEXP packed_elt(SEXP x, R_xlen_t i) {
  if (!PACKED(x)) return STRING_ELT(R_altrep_data2(x), i);
  return packed_make(x, cache_of(x), i);
}

// Make every string, then drop the packed text.
static void *packed_dataptr(SEXP x, Rboolean writeable) {
  (void) writeable;
  if (PACKED(x)) {
    // In row order: the strings then lie in memory in the order R's
    // collector visits them, which keeps every later collection cheap.
    SEXP cache = cache_of(x);
    R_xlen_t n = XLENGTH(cache);
    for (R_xlen_t i = 0; i < n; i++) packed_make(x, cache, i);
    R_set_altrep_data1(x, R_NilValue);
  }
  return (void *) STRING_PTR_RO(R_altrep_data2(x));
}

static const void *packed_dataptr_or_null(SEXP x) {
  return PACKED(x) ? NULL : STRING_PTR_RO(R_altrep_data2(x));
}

static void packed_set_elt(SEXP x, R_xlen_t i, SEXP v) {
  packed_dataptr(x, TRUE);
  SET_STRING_ELT(R_altrep_data2(x), i, v);
}

// Packed columns cannot hold NA; once made, a NA may have been written
// through the data pointer, so make no promise.
static int packed_no_na(SEXP x) {
  return PACKED(x);
}

// A packed copy shares the packed text, which is never modified; R copies
// the attributes. A made column is copied as a plain vector.
static SEXP packed_duplicate(SEXP x, Rboolean deep) {
  (void) deep;
  if (!PACKED(x)) return NULL;
  return R_new_altrep(packed_class, R_altrep_data1(x), R_NilValue);
}

// A new packed column of n values and nbytes bytes of text, stored as
// element i of parent; *bytes and *ends receive its vectors to fill.
SEXP dtatools_new_packed(SEXP parent, R_xlen_t i, R_xlen_t nbytes, R_xlen_t n, SEXP *bytes, SEXP *ends) {
  SEXP data = PROTECT(Rf_allocVector(VECSXP, 2));
  *bytes = SET_VECTOR_ELT(data, 0, Rf_allocVector(RAWSXP, nbytes));
  *ends = SET_VECTOR_ELT(data, 1, Rf_allocVector(REALSXP, n));
  SEXP x = SET_VECTOR_ELT(parent, i, R_new_altrep(packed_class, data, R_NilValue));
  UNPROTECT(1);
  return x;
}

// For the tests: -2 for a vector that is not a packed column, -1 for a
// made one, and for a packed one the number of strings made so far.
SEXP dtatools_packed_state(SEXP x) {
  if (!ALTREP(x) || !R_altrep_inherits(x, packed_class)) return Rf_ScalarReal(-2);
  if (!PACKED(x)) return Rf_ScalarReal(-1);
  SEXP cache = R_altrep_data2(x);
  double made = 0;
  if (cache != R_NilValue)
    for (R_xlen_t i = 0; i < XLENGTH(cache); i++) made += STRING_ELT(cache, i) != NA_STRING;
  return Rf_ScalarReal(made);
}

void dtatools_init_packed(DllInfo *dll) {
  packed_class = R_make_altstring_class("packed_strings", "dtatools", dll);
  R_set_altrep_Length_method(packed_class, packed_length);
  R_set_altrep_Duplicate_method(packed_class, packed_duplicate);
  R_set_altvec_Dataptr_method(packed_class, packed_dataptr);
  R_set_altvec_Dataptr_or_null_method(packed_class, packed_dataptr_or_null);
  R_set_altstring_Elt_method(packed_class, packed_elt);
  R_set_altstring_Set_elt_method(packed_class, packed_set_elt);
  R_set_altstring_No_NA_method(packed_class, packed_no_na);
}
