/* The chunks whose types decide a grouped summary's common type. */
#include "dtatools-internal.h"

#define PTYPE_ATTRIBUTES 16
#define PTYPE_KINDS 4

typedef struct {
    SEXP tag[PTYPE_ATTRIBUTES], value[PTYPE_ATTRIBUTES];
    int count;
} ptype_attributes;

/* Collects a chunk's attributes as they are stored. Stops, so the caller
   declines, for more attributes than it holds and for row names and
   dimensions, which `attributes()` reads through getAttrib() rather than
   as stored. */
static SEXP ptype_attribute(SEXP tag, SEXP value, void *context) {
    ptype_attributes *set = (ptype_attributes *) context;
    if (tag == R_RowNamesSymbol || tag == R_DimSymbol || tag == R_DimNamesSymbol ||
        set->count == PTYPE_ATTRIBUTES) return R_NilValue;
    set->tag[set->count] = tag;
    set->value[set->count] = value;
    set->count++;
    return NULL;
}

/* A chunk's attributes in the order `attributes()` lists them, which is
   the stored order for every type it takes. 0 when the R code must read
   them. */
static int ptype_attributes_read(SEXP chunk, ptype_attributes *set) {
    switch (TYPEOF(chunk)) {
    case NILSXP: case LGLSXP: case INTSXP: case REALSXP: case CPLXSXP:
    case STRSXP: case RAWSXP: case VECSXP:
        break;
    default:
        return 0;
    }
    set->count = 0;
    return R_mapAttrib(chunk, ptype_attribute, set) == NULL;
}

/* `identical()` of the two lists `attributes()` would return, with its
   default flags. Like it, this compares the names before any value, so
   values are read only when the names match. */
static int ptype_attributes_same(const ptype_attributes *left, const ptype_attributes *right) {
    if (left->count != right->count) return 0;
    for (int i = 0; i < left->count; i++) if (left->tag[i] != right->tag[i]) return 0;
    for (int i = 0; i < left->count; i++) {
        if (left->value[i] != right->value[i] &&
            !R_compute_identical(left->value[i], right->value[i], IDENT_USE_CLOENV)) return 0;
    }
    return 1;
}

/* `.summary_ptype_kept()` in one call (ADR 0056): the first three chunks
   and the first chunk of each distinct set of attributes, with those firsts
   as an attribute, or NULL past four sets or when checking them would fold
   about as often as the chunks it skips. Like the R code, it never records
   an empty set, since assigning NULL to a list element adds nothing, so
   every chunk without attributes counts as a first. FALSE leaves the scan
   to the R code: for chunks other than a plain list, for a chunk whose
   attributes `attributes()` would not return as stored, and for counts
   whose integer sums overflow in the R code. */
SEXP C_dtatools_summary_ptype_kept(SEXP chunks) {
    if (TYPEOF(chunks) != VECSXP || ALTREP(chunks) || Rf_isObject(chunks) ||
        XLENGTH(chunks) > INT_MAX / 4) return Rf_ScalarLogical(FALSE);
    int count = (int) XLENGTH(chunks);
    ptype_attributes seen[PTYPE_KINDS], current;
    int kinds = 0, first_count = 0;
    int *firsts = (int *) R_alloc((size_t) count + 1, sizeof(int));
    for (int index = 0; index < count; index++) {
        if (!ptype_attributes_read(VECTOR_ELT(chunks, index), &current))
            return Rf_ScalarLogical(FALSE);
        int known = 0;
        for (int kind = 0; kind < kinds && !known; kind++)
            known = ptype_attributes_same(&seen[kind], &current);
        if (known) continue;
        if (kinds == PTYPE_KINDS) return R_NilValue;
        if (current.count) seen[kinds++] = current;
        firsts[first_count++] = index + 1;
    }
    int *kept = (int *) R_alloc((size_t) first_count + 3, sizeof(int));
    int kept_count = 3;
    for (int i = 0; i < 3; i++) kept[i] = i + 1;
    for (int i = 0; i < first_count; i++) if (firsts[i] > 3) kept[kept_count++] = firsts[i];
    if (first_count > 1) {
        /* The check folds the kept chunks and every first seen after each
           kept fold from the third, and vctrs folds the kept chunks again.
           Both lists ascend, so one pass counts the firsts up to each. */
        int64_t checks = 0;
        for (int i = 2, j = 0; i < kept_count; i++) {
            while (j < first_count && firsts[j] <= kept[i]) j++;
            checks += j;
        }
        int64_t total = 2 * (int64_t) (kept_count - 1) + checks + 6;
        if (checks > INT_MAX || total > INT_MAX) return Rf_ScalarLogical(FALSE);
        if (total >= (int64_t) count - 1) return R_NilValue;
    }
    SEXP result = PROTECT(Rf_allocVector(INTSXP, kept_count));
    memcpy(INTEGER(result), kept, sizeof(int) * (size_t) kept_count);
    SEXP first = PROTECT(Rf_allocVector(INTSXP, first_count));
    if (first_count) memcpy(INTEGER(first), firsts, sizeof(int) * (size_t) first_count);
    Rf_setAttrib(result, Rf_install("firsts"), first);
    UNPROTECT(2);
    return result;
}
