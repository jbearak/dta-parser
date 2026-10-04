/* Reuse the established mock boundaries, not its LONG/FLOAT oracle/matrix. */
#define main historical_long_float_main
#include "../compact-float-domain/work-count.c"
#undef main
#include <fenv.h>

static double independent_operation(double a, double b, char op) {
    volatile double x = a, y = b;
    switch (op) {
    case '+': return x + y;
    case '-': return x - y;
    default: return x * y;
    }
}

static void mixed_fixture(size_t i, size_t n, const char *pattern,
        int16_t *x, uint32_t *bits) {
    const int16_t ints[] = {-3, -1, 0, 1, 7, 19};
    const uint32_t floats[] = {0, UINT32_C(0x80000000), 1,
        UINT32_C(0x80000001), UINT32_C(0x3e800000), UINT32_C(0xbe800000),
        UINT32_C(0x3f800001)};
    *x = ints[i % (sizeof ints / sizeof *ints)];
    *bits = floats[i % (sizeof floats / sizeof *floats)];
    if (!strcmp(pattern, "sparse")) {
        if (i >= 12 && (i - 12) % 997 == 0) *x = (int16_t)(32741 + i % 27);
        if (i >= 18 && (i - 18) % 991 == 0) *bits = UINT32_C(0x7f000000) + (uint32_t)(i % 27) * 2048U;
    } else if (!strcmp(pattern, "tags")) {
        if (i % 5 == 0) *x = (int16_t)(32741 + (i / 5) % 27);
        if (i % 3 == 0) *bits = UINT32_C(0x7f000000) + (uint32_t)((i / 3) % 27) * 2048U;
    } else if (!strcmp(pattern, "edges")) {
        const uint32_t edges[] = {UINT32_C(0x7f000001), UINT32_C(0xff000001),
            UINT32_C(0x7f0007ff), UINT32_C(0x7f00d001), UINT32_C(0x7f7fffff),
            UINT32_C(0xff7fffff), UINT32_C(0x7f800000), UINT32_C(0xff800000),
            UINT32_C(0x7fc00001), UINT32_C(0xff800001)};
        *bits = edges[i % (sizeof edges / sizeof *edges)];
    } else if (i + 1 == n && !strcmp(pattern, "limit_above")) {
        *x = 11; *bits = UINT32_C(0x7d3a2e8b);
    } else if (i + 1 == n && !strcmp(pattern, "limit_below")) {
        *x = 19; *bits = UINT32_C(0x7cd79435);
    } else if (!strcmp(pattern, "cancel")) {
        *x = (i & 1U) ? -1 : 1;
        float value = (float)-*x;
        memcpy(bits, &value, sizeof value);
    }
}

static unsigned mixed_case(int mode, const char *pattern, int strict,
        int chunked, int reverse, char op) {
    size_t n = !strcmp(pattern, "ordinary") || !strcmp(pattern, "sparse") ? 4097 : 259;
    int16_t *x = malloc(n * sizeof *x);
    uint32_t *y = malloc(n * sizeof *y);
    double *expected = malloc(n * sizeof *expected);
    if (!x || !y || !expected) abort();
    numeric_data xd = {NUMERIC_INT, 0, 118, 0, chunked ? 7U : 0U, (unsigned char *)x, 0};
    numeric_data yd = {NUMERIC_FLOAT, 0, 118, 0, chunked ? 11U : 0U, (unsigned char *)y,
        strict ? NUMERIC_DOMAIN_STRICT_MODERN_FLOAT : 0};
    size_t missing = 0;
    int expected_kind = NUMERIC_FLOAT;
    double limit = (double)0x1.fffffep126f;
    for (size_t i = 0; i < n; i++) {
        mixed_fixture(i, n, pattern, x + i, y + i);
        unsigned xm = x[i] >= 32741;
        unsigned ym = float_missing(y[i], 0);
        xd.missing_count += xm; yd.missing_count += ym;
        float f; memcpy(&f, y + i, sizeof f);
        unsigned invalid = xm || ym || (y[i] & UINT32_C(0x7fffffff)) == UINT32_C(0x7f800000);
        double result = invalid ? NA_REAL : independent_operation(
            reverse ? (double)f : (double)x[i], reverse ? (double)x[i] : (double)f, op);
        expected[i] = result;
        missing += invalid;
        if (!invalid && fabs(result) > limit) expected_kind = NUMERIC_DOUBLE;
    }
    phase = 0; allocations = exact_integer_rows = exact_float_rows = canonical_rows = 0;
    memset(general_rows, 0, sizeof general_rows);
    memset(result_checks, 0, sizeof result_checks);
    memset(span_rows, 0, sizeof span_rows);
    arithmetic_operand xo = {{&xd, NULL, NULL}, (R_xlen_t)n};
    arithmetic_operand yo = {{&yd, NULL, NULL}, (R_xlen_t)n};
    int selected = -1;
    SEXP result = arithmetic_general_result(reverse ? &yo : &xo, reverse ? &xo : &yo,
        (R_xlen_t)n, op, NUMERIC_FLOAT, &selected);
    unsigned errors = selected != expected_kind || result->kind != expected_kind ||
        result->missing_count != missing;
    for (size_t i = 0; i < n; i++) {
        int16_t original_x; uint32_t original_y;
        mixed_fixture(i, n, pattern, &original_x, &original_y);
        errors += x[i] != original_x || y[i] != original_y;
        if (expected_kind == NUMERIC_FLOAT) {
            float value = isnan(expected[i]) ? 0x1p127f : (float)expected[i];
            errors += memcmp(result->raw + i * 4, &value, 4) != 0;
        } else errors += memcmp(result->raw + i * 8, expected + i, 8) != 0;
    }
    /* A strict fast producer may legitimately run the broad exact fallback
       when rounded limit equality or whole-column promotion requires it. */
    int gate = !strcmp(pattern, "ordinary") || !strcmp(pattern, "sparse") ||
        !strcmp(pattern, "tags") || !strcmp(pattern, "cancel");
    int work = (strict && gate && (exact_float_rows != 0 || canonical_rows != n)) ||
        (!strict && canonical_rows != 0);
    printf("%d,%s,%d,%d,%d,%c,%zu,%d,%zu,%zu,%zu,%u,%d\n",
        mode, pattern, strict, chunked, reverse, op, n, selected, missing,
        exact_float_rows, canonical_rows, errors, work);
    for (size_t i = 0; i < allocations; i++) { free(allocated[i]->raw); free(allocated[i]); }
    free(x); free(y); free(expected);
    return errors;
}

int main(void) {
    const int modes[] = {FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO};
    const char *patterns[] = {"ordinary", "sparse", "tags", "edges", "limit_above", "limit_below", "cancel"};
    const char operations[] = "+-*";
    unsigned errors = 0;
    printf("mode,pattern,strict,chunked,reverse,op,length,output,missing,broad_rows,canonical_rows,semantic_failures,work_failure\n");
    for (int mode = 0; mode < 4; mode++) {
        if (fesetround(modes[mode]) || fegetround() != modes[mode]) abort();
        for (size_t p = 0; p < sizeof patterns / sizeof *patterns; p++)
            for (int strict = 0; strict < 2; strict++) {
                if (!strcmp(patterns[p], "edges") && strict) continue;
                for (int chunked = 0; chunked < 2; chunked++)
                    for (int reverse = 0; reverse < 2; reverse++)
                        for (size_t op = 0; op < sizeof operations - 1; op++)
                            errors += mixed_case(mode, patterns[p], strict, chunked, reverse, operations[op]);
            }
    }
    fesetround(FE_TONEAREST);
    fprintf(stderr, "%u semantic failures\n", errors);
    return errors != 0;
}
