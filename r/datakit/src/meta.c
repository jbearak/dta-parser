// meta's `columns` for a polars read: one entry per column, each
// list(label, format, value_labels, ordered) with NULL where the read
// gave NA. Built here because an R call per column took 7 ms on a file
// of 5,160 columns, most of read_parquet_pl()'s time beyond the read.

#include <R.h>
#include <Rinternals.h>

// names, label, format and value_labels: character vectors of one
// length; ordered: a logical vector of that length.
SEXP dta_meta_columns(SEXP names, SEXP label, SEXP format, SEXP value_labels, SEXP ordered) {
  R_xlen_t n = XLENGTH(names);
  if (TYPEOF(names) != STRSXP || TYPEOF(label) != STRSXP || TYPEOF(format) != STRSXP ||
      TYPEOF(value_labels) != STRSXP || TYPEOF(ordered) != LGLSXP || XLENGTH(label) != n || XLENGTH(format) != n ||
      XLENGTH(value_labels) != n || XLENGTH(ordered) != n)
    Rf_error("internal: a read's columns must be four character vectors and a logical vector of one length");
  SEXP out = PROTECT(Rf_allocVector(VECSXP, n));
  // Every entry shares one names vector.
  SEXP fields = PROTECT(Rf_allocVector(STRSXP, 4));
  SET_STRING_ELT(fields, 0, Rf_mkChar("label"));
  SET_STRING_ELT(fields, 1, Rf_mkChar("format"));
  SET_STRING_ELT(fields, 2, Rf_mkChar("value_labels"));
  SET_STRING_ELT(fields, 3, Rf_mkChar("ordered"));
  SEXP text[3] = {label, format, value_labels};
  const int *ord = LOGICAL(ordered);
  for (R_xlen_t k = 0; k < n; k++) {
    SEXP entry = Rf_allocVector(VECSXP, 4);
    SET_VECTOR_ELT(out, k, entry);
    Rf_setAttrib(entry, R_NamesSymbol, fields);
    for (int f = 0; f < 3; f++) {
      SEXP s = STRING_ELT(text[f], k);
      if (s != NA_STRING) SET_VECTOR_ELT(entry, f, Rf_ScalarString(s));
    }
    if (ord[k] != NA_LOGICAL) SET_VECTOR_ELT(entry, 3, Rf_ScalarLogical(ord[k]));
  }
  Rf_setAttrib(out, R_NamesSymbol, names);
  UNPROTECT(2);
  return out;
}
