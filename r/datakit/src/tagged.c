// Whether a `by` column of `:=` holds .a to .z, which vctrs groups with
// plain NA (their bits differ only in the letter). Checked without
// allocating, so grouping a column with no tagged NA costs no more
// than before.

#include <stdint.h>
#include <string.h>
#include <R.h>
#include <Rinternals.h>

// 1 if the double's bits are a tagged NA: a NaN whose low word is
// R's NA (1954), with a letter a to z in bits 32 to 39, as dtaparser's
// letter_of() reads them. Branchless (& and an unsigned range test),
// so the loops below vectorise or at least do not mispredict.
static inline unsigned tagged(const double *x) {
  uint64_t bits;
  memcpy(&bits, x, sizeof bits);
  return (((bits >> 52) & 0x7ff) == 0x7ff) & ((uint32_t) bits == 1954) &
         ((uint32_t) ((bits >> 32) & 0xff) - 'a' < 26u);
}

// R_IsNA(), inlined, since it runs once per group: a NaN whose low
// word is 1954, true for NA and .a to .z, false for NaN.
static inline int is_na(double x) {
  uint64_t bits;
  memcpy(&bits, &x, sizeof bits);
  return ISNAN(x) && (uint32_t) bits == 1954;
}

// Whether the double vector x holds a tagged NA in a group whose key is
// NA. `key` is the group keys of this column and `loc` each group's
// rows (1-based) in x, as vctrs::vec_group_loc() gives them. A tagged NA
// is NA to is_na(), so it is only in such a group; NaN groups are
// skipped. When those groups hold more than a sixteenth of the rows, one
// sequential pass over x is cheaper than reading their rows.
SEXP dta_na_groups_tagged(SEXP x, SEXP key, SEXP loc) {
  const double *p = REAL_RO(x), *k = REAL_RO(key);
  R_xlen_t n = XLENGTH(x), groups = XLENGTH(key), missing = 0;
  for (R_xlen_t g = 0; g < groups; g++) {
    if (is_na(k[g])) missing += XLENGTH(VECTOR_ELT(loc, g));
  }
  if (!missing) return Rf_ScalarLogical(FALSE);
  unsigned found = 0;
  if (missing > n / 16) {
    for (R_xlen_t i = 0; i < n; i++) found |= tagged(p + i);
    return Rf_ScalarLogical(found != 0);
  }
  for (R_xlen_t g = 0; g < groups && !found; g++) {
    if (!is_na(k[g])) continue;
    SEXP rows = VECTOR_ELT(loc, g);
    const int *r = INTEGER_RO(rows);
    for (R_xlen_t i = 0, m = XLENGTH(rows); i < m; i++) found |= tagged(p + r[i] - 1);
  }
  return Rf_ScalarLogical(found != 0);
}
