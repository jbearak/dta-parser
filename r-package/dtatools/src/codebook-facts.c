#include "dtatools-internal.h"

/* A codebook summarizes a variable's observed values with unique(), sort(),
   diff(), min(), max() and quantile(type = 2). When those values are finite
   integers below 2^53 in magnitude whose range is at most their count plus
   CODEBOOK_SPAN_SLACK, one tally per value gives every one of those results.
   A -0 declines, since unique() keeps whichever zero comes first. */
#define CODEBOOK_SPAN_SLACK 65536

typedef struct {
    R_xlen_t rank;
    int slot;
} codebook_rank;

/* The ordinary R calls give each result below. NULL means the input was
   not admitted and the caller makes those calls. Otherwise the result is a
   list of the distinct values in order of first appearance, as unique()
   returns them, and c(min, max, smallest gap, five quantiles). */
SEXP C_dtatools_codebook_facts(SEXP x) {
    if (TYPEOF(x) != REALSXP || ANY_ATTRIB(x)) return R_NilValue;
    R_xlen_t n = XLENGTH(x);
    if (n == 0 || n > INT_MAX) return R_NilValue;
    const double *value = (const double *) DATAPTR_OR_NULL(x);
    if (value == NULL) return R_NilValue;
    double low = value[0], high = value[0];
    for (R_xlen_t i = 0; i < n; i++) {
        if ((i & 1048575) == 0) R_CheckUserInterrupt();
        double v = value[i];
        /* The negated comparison also declines NaN. */
        if (!(fabs(v) < 9007199254740992.0) || v != floor(v) ||
            (v == 0 && signbit(v))) return R_NilValue;
        if (v < low) low = v;
        if (v > high) high = v;
    }
    if (high - low > (double) n + CODEBOOK_SPAN_SLACK) return R_NilValue;
    R_xlen_t bins = (R_xlen_t) (high - low) + 1;
    SEXP counts = PROTECT(Rf_allocVector(INTSXP, bins));
    int *count = INTEGER(counts);
    memset(count, 0, (size_t) bins * sizeof(int));
    SEXP seen = PROTECT(Rf_allocVector(REALSXP, bins < n ? bins : n));
    double *first = REAL(seen);
    value = (const double *) DATAPTR_OR_NULL(x);
    if (value == NULL) {
        UNPROTECT(2);
        return R_NilValue;
    }
    R_xlen_t distinct = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        if ((i & 1048575) == 0) R_CheckUserInterrupt();
        R_xlen_t bin = (R_xlen_t) (value[i] - low);
        if (count[bin]++ == 0) first[distinct++] = value[i];
    }

    /* quantile.default(type = 2) with its default fuzz reads order
       statistics j and j + 1, clamped to 1 and n, and averages them when
       n * p is a whole number and they differ. */
    static const double probs[5] = {.1, .25, .5, .75, .9};
    const double fuzz = 4 * DBL_EPSILON;
    double h[5], order[10];
    codebook_rank ranks[10];
    for (int p = 0; p < 5; p++) {
        double nppm = (double) n * probs[p];
        double j = floor(nppm * (1 + fuzz));
        h[p] = ((nppm > j) + 1) / 2.0;
        R_xlen_t lower = (R_xlen_t) j;
        ranks[2 * p] = (codebook_rank) {lower < 1 ? 1 : lower, 2 * p};
        ranks[2 * p + 1] = (codebook_rank) {lower + 1 > n ? n : lower + 1, 2 * p + 1};
    }
    for (int i = 1; i < 10; i++) {
        codebook_rank next = ranks[i];
        int k = i;
        for (; k > 0 && ranks[k - 1].rank > next.rank; k--) ranks[k] = ranks[k - 1];
        ranks[k] = next;
    }
    /* Consecutive occupied bins hold consecutive sorted distinct values.
       Each is an integer below 2^53, so diff() of two is exact. */
    R_xlen_t cumulative = 0, previous = -1;
    double gap = NA_REAL;
    int next = 0;
    for (R_xlen_t bin = 0; bin < bins; bin++) {
        if ((bin & 1048575) == 0) R_CheckUserInterrupt();
        if (count[bin] == 0) continue;
        double here = low + (double) bin;
        if (previous >= 0) {
            double step = here - (low + (double) previous);
            if (ISNAN(gap) || step < gap) gap = step;
        }
        previous = bin;
        cumulative += count[bin];
        while (next < 10 && ranks[next].rank <= cumulative) {
            order[ranks[next].slot] = here;
            next++;
        }
    }

    SEXP result = PROTECT(Rf_allocVector(VECSXP, 2));
    SEXP values = Rf_allocVector(REALSXP, distinct);
    SET_VECTOR_ELT(result, 0, values);
    if (distinct) memcpy(REAL(values), first, (size_t) distinct * sizeof(double));
    SEXP facts = Rf_allocVector(REALSXP, 8);
    SET_VECTOR_ELT(result, 1, facts);
    double *fact = REAL(facts);
    fact[0] = low;
    fact[1] = high;
    fact[2] = gap;
    for (int p = 0; p < 5; p++) {
        double a = order[2 * p], b = order[2 * p + 1], q = a;
        if (h[p] == 1) q = b;
        /* h is one half here. Halving an integer is exact, so a fused
           multiply-add cannot round this sum differently from R. */
        if (h[p] > 0 && h[p] < 1 && a != b) q = (1 - h[p]) * a + h[p] * b;
        fact[3 + p] = q;
    }
    UNPROTECT(3);
    return result;
}
