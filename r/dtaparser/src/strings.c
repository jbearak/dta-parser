// Packed string columns: read_dta's character vectors keep their text as
// the UTF-8 bytes read from the file and make R strings only when R asks
// for them. Making 10M distinct R strings costs seconds (each is hashed
// into R's global string cache and traced by its collector); a column
// most code only filters, slices or looks at the head of need not pay
// that at read time.
//
// A column is an ALTREP character vector in one of two states:
//
// - packed: data1 is list(bytes, ends, codes). bytes is a raw vector of
//   text and ends a double vector of each value's end offset. With codes
//   R_NilValue they hold every row's value; with codes an integer vector
//   (0-based, one per row) they hold a dictionary of the distinct values,
//   so R makes one string per distinct value, not per row. data2 is
//   R_NilValue or a cache, a character vector with a slot per value in
//   bytes holding the strings made so far, and NA_STRING where none is
//   made yet. A row whose code is NA_INTEGER is NA (Parquet's nulls;
//   Stata strings are never NA), and data1's fourth element, a logical,
//   says whether any code is.
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
#define CODES(x) VECTOR_ELT(R_altrep_data1(x), 2)
#define HAS_NA(x) (LOGICAL(VECTOR_ELT(R_altrep_data1(x), 3))[0])

static R_xlen_t packed_length(SEXP x) {
  if (!PACKED(x)) return XLENGTH(R_altrep_data2(x));
  return CODES(x) != R_NilValue ? XLENGTH(CODES(x)) : XLENGTH(ENDS(x));
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

// The string in slot i of a packed column, made and cached if need be.
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

// Called once per element by code that walks a vector (nchar, is.na,
// paste), so each R API call saved here counts: the usual case, a string
// already made, reads data1, the codes and the cache once each.
static SEXP packed_elt(SEXP x, R_xlen_t i) {
  SEXP data = R_altrep_data1(x);
  SEXP cache = R_altrep_data2(x);
  if (data == R_NilValue) return STRING_ELT(cache, i);
  SEXP codes = VECTOR_ELT(data, 2);
  R_xlen_t slot = codes == R_NilValue ? i : ((const int *) DATAPTR_RO(codes))[i];
  if (slot == NA_INTEGER) return NA_STRING;
  if (cache != R_NilValue) {
    SEXP s = STRING_ELT(cache, slot);
    if (s != NA_STRING) return s;
  }
  return packed_make(x, cache_of(x), slot);
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
    SEXP codes = CODES(x);
    if (codes != R_NilValue) {
      // Every row's string is one of the dictionary's, already made.
      R_xlen_t rows = XLENGTH(codes);
      SEXP full = PROTECT(Rf_allocVector(STRSXP, rows));
      const int *code = INTEGER(codes);
      for (R_xlen_t i = 0; i < rows; i++)
        SET_STRING_ELT(full, i, code[i] == NA_INTEGER ? NA_STRING : STRING_ELT(cache, code[i]));
      R_set_altrep_data2(x, full);
      UNPROTECT(1);
    }
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

// A packed column holds NA only where a code is NA_INTEGER; once made, a
// NA may have been written through the data pointer, so make no promise.
static int packed_no_na(SEXP x) {
  return PACKED(x) && !HAS_NA(x);
}

// A packed copy shares the packed text, which is never modified; R copies
// the attributes. A made column is copied as a plain vector.
static SEXP packed_duplicate(SEXP x, Rboolean deep) {
  (void) deep;
  if (!PACKED(x)) return NULL;
  return R_new_altrep(packed_class, R_altrep_data1(x), R_NilValue);
}

// A new packed column of n values and nbytes bytes of text, stored as
// element i of parent; *bytes and *ends receive its vectors to fill. With
// rows >= 0 the values are a dictionary and *codes receives an integer
// vector of rows codes to fill, NA_INTEGER for NA when has_na; with
// rows < 0, *codes is R_NilValue.
SEXP dtaparser_new_packed(SEXP parent, R_xlen_t i, R_xlen_t nbytes, R_xlen_t n, R_xlen_t rows, int has_na,
                         SEXP *bytes, SEXP *ends, SEXP *codes) {
  SEXP data = PROTECT(Rf_allocVector(VECSXP, 4));
  *bytes = SET_VECTOR_ELT(data, 0, Rf_allocVector(RAWSXP, nbytes));
  *ends = SET_VECTOR_ELT(data, 1, Rf_allocVector(REALSXP, n));
  *codes = rows < 0 ? R_NilValue : SET_VECTOR_ELT(data, 2, Rf_allocVector(INTSXP, rows));
  SET_VECTOR_ELT(data, 3, Rf_ScalarLogical(rows >= 0 && has_na));
  SEXP x = SET_VECTOR_ELT(parent, i, R_new_altrep(packed_class, data, R_NilValue));
  UNPROTECT(1);
  return x;
}

// For a packed column with a dictionary and no NA, list(values, codes):
// its distinct values as a character vector and each row's 0-based code
// (shared with the column, so not to be modified). NULL for anything else.
SEXP dtaparser_dictionary(SEXP x) {
  if (!ALTREP(x) || !R_altrep_inherits(x, packed_class) || !PACKED(x) || CODES(x) == R_NilValue || HAS_NA(x))
    return R_NilValue;
  SEXP cache = cache_of(x);
  for (R_xlen_t i = 0; i < XLENGTH(cache); i++) packed_make(x, cache, i);
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, Rf_duplicate(cache));
  SEXP codes = CODES(x);
  MARK_NOT_MUTABLE(codes);
  SET_VECTOR_ELT(out, 1, codes);
  UNPROTECT(1);
  return out;
}

// The parts of a column the writer can read without making R strings:
// 1 for a packed column, with *bytes, *ends and *codes as in data1 (the
// codes R_NilValue without a dictionary, NA_INTEGER for NA); 2 for a made one, with its
// ordinary character vector in *bytes; 0 for any other vector. Calls no
// R function that allocates or raises an error.
int dtaparser_packed_parts(SEXP x, SEXP *bytes, SEXP *ends, SEXP *codes) {
  if (!ALTREP(x) || !R_altrep_inherits(x, packed_class)) return 0;
  if (!PACKED(x)) {
    *bytes = R_altrep_data2(x);
    return 2;
  }
  *bytes = BYTES(x);
  *ends = ENDS(x);
  *codes = CODES(x);
  return 1;
}

// For the tests: c(state, dictionary). state is -2 for a vector that is
// not a packed column, -1 for a made one, and for a packed one the number
// of cache slots made so far; dictionary is 1 for a packed column with a
// dictionary, else 0.
SEXP dtaparser_packed_state(SEXP x) {
  SEXP out = PROTECT(Rf_allocVector(REALSXP, 2));
  double *o = REAL(out);
  o[0] = -2;
  o[1] = 0;
  if (ALTREP(x) && R_altrep_inherits(x, packed_class)) {
    o[0] = -1;
    if (PACKED(x)) {
      SEXP cache = R_altrep_data2(x);
      o[0] = 0;
      if (cache != R_NilValue)
        for (R_xlen_t i = 0; i < XLENGTH(cache); i++) o[0] += STRING_ELT(cache, i) != NA_STRING;
      o[1] = CODES(x) != R_NilValue;
    }
  }
  UNPROTECT(1);
  return out;
}

void dtaparser_init_packed(DllInfo *dll) {
  packed_class = R_make_altstring_class("packed_strings", "dtaparser", dll);
  R_set_altrep_Length_method(packed_class, packed_length);
  R_set_altrep_Duplicate_method(packed_class, packed_duplicate);
  R_set_altvec_Dataptr_method(packed_class, packed_dataptr);
  R_set_altvec_Dataptr_or_null_method(packed_class, packed_dataptr_or_null);
  R_set_altstring_Elt_method(packed_class, packed_elt);
  R_set_altstring_Set_elt_method(packed_class, packed_set_elt);
  R_set_altstring_No_NA_method(packed_class, packed_no_na);
}
