// Missing codes and Stata order keys for R vectors.
//
// dtatools stores `.` as NA_real_ and `.a` to `.z` as NA_real_ with the
// letter in bits 32 to 39 (haven's tagged_na layout). These functions
// read that payload from any double vector, classed or not.

#include <stdint.h>
#include <string.h>
#include <R.h>
#include <Rinternals.h>

// 0 for a number, 1 for `.` (NA, or any other NaN), 2 to 27 for `.a` to `.z`.
static int code_of(double x) {
  if (!ISNAN(x)) return 0;
  uint64_t bits;
  memcpy(&bits, &x, sizeof bits);
  unsigned tag = (unsigned) ((bits >> 32) & 0xff);
  if ((uint32_t) bits == 1954 && tag >= 'a' && tag <= 'z') return (int) (tag - 'a') + 2;
  return 1;
}

// The code of element i of a numeric, integer or logical vector.
static int code_at(SEXP x, R_xlen_t i) {
  switch (TYPEOF(x)) {
  case REALSXP: return code_of(REAL(x)[i]);
  case INTSXP: return INTEGER(x)[i] == NA_INTEGER;
  case LGLSXP: return LOGICAL(x)[i] == NA_LOGICAL;
  default: return 0;
  }
}

static double value_at(SEXP x, R_xlen_t i) {
  switch (TYPEOF(x)) {
  case REALSXP: return REAL(x)[i];
  case INTSXP: return INTEGER(x)[i];
  case LGLSXP: return LOGICAL(x)[i];
  default: return 0;
  }
}

static void check_numeric(SEXP x) {
  int t = TYPEOF(x);
  if (t != REALSXP && t != INTSXP && t != LGLSXP && t != NILSXP)
    Rf_error("expected a numeric vector, not %s", Rf_type2char(t));
}

SEXP dtatools_codes(SEXP x) {
  check_numeric(x);
  R_xlen_t n = XLENGTH(x);
  SEXP out = PROTECT(Rf_allocVector(INTSXP, n));
  int *o = INTEGER(out);
  for (R_xlen_t i = 0; i < n; i++) o[i] = code_at(x, i);
  UNPROTECT(1);
  return out;
}

// Keys that sort and compare as Stata does: numbers as themselves, and
// `.` to `.z` as the doubles Stata itself stores for them, which are
// finite, increasing, and above every number Stata stores. With
// keep_na, `.` stays NA (for match(): `x %in% NA` finds `.`).
SEXP dtatools_keys(SEXP x, SEXP keep_na) {
  check_numeric(x);
  int na = Rf_asLogical(keep_na) == TRUE;
  R_xlen_t n = XLENGTH(x);
  SEXP out = PROTECT(Rf_allocVector(REALSXP, n));
  double *o = REAL(out);
  for (R_xlen_t i = 0; i < n; i++) {
    int code = code_at(x, i);
    if (code == 0) {
      o[i] = value_at(x, i);
    } else if (code == 1 && na) {
      o[i] = NA_REAL;
    } else {
      uint64_t bits = 0x7fe0000000000000ULL + ((uint64_t) (code - 1) << 40);
      memcpy(&o[i], &bits, sizeof bits);
    }
  }
  UNPROTECT(1);
  return out;
}

// The doubles for missing codes (1 to 27), as dtatools stores them.
SEXP dtatools_missing(SEXP codes) {
  R_xlen_t n = XLENGTH(codes);
  SEXP out = PROTECT(Rf_allocVector(REALSXP, n));
  double *o = REAL(out);
  const int *c = INTEGER(codes);
  for (R_xlen_t i = 0; i < n; i++) {
    uint64_t bits = 0x7ff00000000007a2ULL;  // NA_real_
    if (c[i] >= 2 && c[i] <= 27) bits |= (uint64_t) ('a' + c[i] - 2) << 32;
    memcpy(&o[i], &bits, sizeof bits);
  }
  UNPROTECT(1);
  return out;
}
