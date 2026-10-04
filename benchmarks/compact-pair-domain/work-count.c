/* Reuse the established mock boundaries, not its LONG/FLOAT oracle/matrix. */
#include <stddef.h>
static size_t pair_range_proved_rows, pair_maximum_rows;
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

static void mixed_bits(size_t i, size_t n, const char *pattern, int kind,
        uint32_t *left, uint32_t *right) {
    int16_t integer;
    mixed_fixture(i, n, pattern, &integer, right);
    if (i + 1 == n && !strcmp(pattern, "physical_min"))
        integer = kind == NUMERIC_BYTE ? -128 : -32768;
    if (i + 1 == n && !strcmp(pattern, "endpoint")) {
        integer = 1;
        *right = UINT32_C(0x7effffff);
    }
    if (kind == NUMERIC_FLOAT) {
        if (integer >= 32741) *left = UINT32_C(0x7f000000) +
            (uint32_t)(integer - 32741) * 2048U;
        else {
            float value = (float)integer;
            memcpy(left, &value, sizeof value);
        }
        if (i + 1 == n && !strcmp(pattern, "sum_inside")) {
            *left = UINT32_C(0x7efffffe); *right = UINT32_C(0x72800000);
        } else if (i + 1 == n && !strcmp(pattern, "product_inside")) {
            *left = UINT32_C(0x5f7ffffe); *right = UINT32_C(0x5f000000);
        } else if (i + 1 == n && !strcmp(pattern, "product_endpoint")) {
            *left = UINT32_C(0x5f7fffff); *right = UINT32_C(0x5f000000);
        } else if (i + 1 == n && !strcmp(pattern, "product_outside")) {
            *left = UINT32_C(0x5f800000); *right = UINT32_C(0x5f000000);
        }
    } else {
        if (kind == NUMERIC_BYTE && integer >= 32741) integer -= 32640;
        *left = kind == NUMERIC_BYTE ? (uint8_t)(int8_t)integer : (uint16_t)integer;
    }
}

static void store_left(unsigned char *output, int kind, uint32_t bits) {
    if (kind == NUMERIC_BYTE) {
        uint8_t value = (uint8_t)bits;
        memcpy(output, &value, 1);
    } else if (kind == NUMERIC_INT) {
        uint16_t value = (uint16_t)bits;
        memcpy(output, &value, 2);
    } else memcpy(output, &bits, 4);
}

static double left_value(uint32_t bits, int kind, unsigned *missing) {
    if (kind == NUMERIC_FLOAT) {
        float value; memcpy(&value, &bits, sizeof value);
        *missing = float_missing(bits, 0);
        return (double)value;
    }
    if (kind == NUMERIC_BYTE) {
        uint8_t encoded = (uint8_t)bits;
        int8_t value; memcpy(&value, &encoded, 1);
        *missing = value >= 101;
        return (double)value;
    }
    uint16_t encoded = (uint16_t)bits;
    int16_t value; memcpy(&value, &encoded, 2);
    *missing = value >= 32741;
    return (double)value;
}

static void observe_float_facts(numeric_data *data, uint32_t bits) {
    uint32_t magnitude = bits & UINT32_C(0x7fffffff);
    if (magnitude > UINT32_C(0x7effffff)) return;
    if (magnitude > data->float_max_magnitude_bound)
        data->float_max_magnitude_bound = magnitude;
    if (magnitude == 0) data->zero_count++;
    else if (magnitude < data->float_min_nonzero_magnitude_bound)
        data->float_min_nonzero_magnitude_bound = magnitude;
}

static void finish_float_facts(numeric_data *data, int strict, const char *facts) {
    if (data->kind != NUMERIC_FLOAT) return;
    data->domain_flags = strict ? NUMERIC_DOMAIN_STRICT_MODERN_FLOAT : 0;
    if (!strcmp(facts, "known") || !strcmp(facts, "conservative") ||
            !strcmp(facts, "subset") || !strcmp(facts, "outside")) {
        data->domain_flags |= NUMERIC_DOMAIN_FLOAT_BOUNDS_KNOWN |
            NUMERIC_DOMAIN_ZERO_COUNT_KNOWN;
        if (!strcmp(facts, "conservative") || !strcmp(facts, "subset")) {
            uint32_t maximum = data->float_max_magnitude_bound;
            data->float_max_magnitude_bound = maximum <= UINT32_C(0x7efffff7)
                ? maximum + 8 : UINT32_C(0x7effffff);
            if (data->float_min_nonzero_magnitude_bound != UINT32_MAX)
                data->float_min_nonzero_magnitude_bound = 1;
        }
        if (!strcmp(facts, "subset")) {
            data->domain_flags &= ~NUMERIC_DOMAIN_ZERO_COUNT_KNOWN;
            data->zero_count = 999; /* Parent count cannot be used for a subset. */
        }
        if (!strcmp(facts, "outside"))
            data->float_max_magnitude_bound = UINT32_C(0x7f000000);
    }
}

/* An independent wider arithmetic bound predicts admission. The fixtures
   leave more than one binary64 ulp of room whenever the exact sum is below
   the endpoint, so directed long-double rounding cannot change this decision. */
static int independent_bound(const numeric_data *data, long double *bound) {
    if (data->kind == NUMERIC_BYTE) { *bound = 128; return 1; }
    if (data->kind == NUMERIC_INT) { *bound = 32768; return 1; }
    if (data->kind != NUMERIC_FLOAT || data->temporal || data->format_version <= 111 ||
            (data->domain_flags & 3U) != 3U ||
            data->float_max_magnitude_bound > UINT32_C(0x7effffff)) return 0;
    float value;
    memcpy(&value, &data->float_max_magnitude_bound, sizeof value);
    *bound = (long double)value;
    return 1;
}
static int independent_range(const numeric_data *x, const numeric_data *y, char op) {
    long double a, b;
    if (!independent_bound(x, &a) || !independent_bound(y, &b)) return 0;
    long double bound = op == '*' ? a * b : a + b;
    return bound < 0x1.fffffep126L;
}

static unsigned mixed_case(int mode, const char *pattern, int strict,
        int chunked, int reverse, char op, int left_kind, const char *facts) {
    size_t n = !strcmp(pattern, "ordinary") || !strcmp(pattern, "sparse") ? 4097 : 259;
    unsigned char *x = malloc(n * width(left_kind));
    uint32_t *y = malloc(n * sizeof *y);
    double *expected = malloc(n * sizeof *expected);
    if (!x || !y || !expected) abort();
    numeric_data xd = {.kind = left_kind, .format_version = 118, .raw = x,
        .chunk_size = chunked ? 7U : 0U, .length = n,
        .float_min_nonzero_magnitude_bound = UINT32_MAX};
    numeric_data yd = {.kind = NUMERIC_FLOAT, .format_version = 118,
        .raw = (const unsigned char *)y, .chunk_size = chunked ? 11U : 0U,
        .length = n, .float_min_nonzero_magnitude_bound = UINT32_MAX};
    size_t missing = 0;
    int expected_kind = NUMERIC_FLOAT;
    double limit = (double)0x1.fffffep126f;
    for (size_t i = 0; i < n; i++) {
        uint32_t left_bits;
        mixed_bits(i, n, pattern, left_kind, &left_bits, y + i);
        store_left(x + i * width(left_kind), left_kind, left_bits);
        unsigned xm;
        double a = left_value(left_bits, left_kind, &xm);
        unsigned ym = float_missing(y[i], 0);
        xd.missing_count += xm; yd.missing_count += ym;
        if (left_kind == NUMERIC_FLOAT) observe_float_facts(&xd, left_bits);
        observe_float_facts(&yd, y[i]);
        float f; memcpy(&f, y + i, sizeof f);
        unsigned invalid = xm || ym || (y[i] & UINT32_C(0x7fffffff)) == UINT32_C(0x7f800000);
        double result = invalid ? NA_REAL : independent_operation(
            reverse ? (double)f : a, reverse ? a : (double)f, op);
        expected[i] = result;
        missing += invalid;
        if (!invalid && fabs(result) > limit) expected_kind = NUMERIC_DOUBLE;
    }
    finish_float_facts(&xd, strict, facts);
    finish_float_facts(&yd, strict, facts);
    int expected_proved = independent_range(&xd, &yd, op);
    phase = 0; allocations = exact_integer_rows = exact_float_rows = canonical_rows = 0;
    pair_range_proved_rows = pair_maximum_rows = 0;
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
        uint32_t original_x, original_y;
        unsigned char encoded[4];
        mixed_bits(i, n, pattern, left_kind, &original_x, &original_y);
        store_left(encoded, left_kind, original_x);
        errors += memcmp(x + i * width(left_kind), encoded, width(left_kind)) != 0 ||
            y[i] != original_y;
        if (expected_kind == NUMERIC_FLOAT) {
            float value = isnan(expected[i]) ? 0x1p127f : (float)expected[i];
            errors += memcmp(result->raw + i * 4, &value, 4) != 0;
        } else errors += memcmp(result->raw + i * 8, expected + i, 8) != 0;
    }
    /* A strict fast producer may legitimately run the broad exact fallback
       when rounded limit equality or whole-column promotion requires it. */
    int gate = !strcmp(pattern, "ordinary") || !strcmp(pattern, "sparse") ||
        !strcmp(pattern, "tags") || !strcmp(pattern, "cancel");
    size_t float_columns = left_kind == NUMERIC_FLOAT ? 2 : 1;
    int work = (strict && gate && (exact_float_rows != 0 || canonical_rows != n * float_columns)) ||
        (!strict && canonical_rows != 0) ||
        pair_range_proved_rows != (expected_proved ? n : 0) ||
        pair_maximum_rows != (expected_proved ? 0 : n);
    printf("%d,%s,%d,%d,%d,%c,%zu,%d,%zu,%zu,%zu,%u,%d,%d,%s,%zu,%zu\n",
        mode, pattern, strict, chunked, reverse, op, n, selected, missing,
        exact_float_rows, canonical_rows, errors, work, left_kind, facts,
        pair_range_proved_rows, pair_maximum_rows);
    for (size_t i = 0; i < allocations; i++) { free(allocated[i]->raw); free(allocated[i]); }
    free(x); free(y); free(expected);
    return errors;
}

int main(void) {
    const int modes[] = {FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO};
    const char *patterns[] = {"ordinary", "sparse", "tags", "edges", "limit_above", "limit_below", "cancel"};
    const char operations[] = "+-*";
    unsigned errors = 0;
    printf("mode,pattern,strict,chunked,reverse,op,length,output,missing,broad_rows,canonical_rows,semantic_failures,work_failure,left_kind,facts,range_proved_rows,maximum_rows\n");
    for (int mode = 0; mode < 4; mode++) {
        if (fesetround(modes[mode]) || fegetround() != modes[mode]) abort();
        for (size_t p = 0; p < sizeof patterns / sizeof *patterns; p++)
            for (int strict = 0; strict < 2; strict++) {
                if (!strcmp(patterns[p], "edges") && strict) continue;
                for (int chunked = 0; chunked < 2; chunked++)
                    for (int reverse = 0; reverse < 2; reverse++)
                        for (size_t op = 0; op < sizeof operations - 1; op++)
                            errors += mixed_case(mode, patterns[p], strict, chunked, reverse,
                                operations[op], NUMERIC_INT, "legacy");
            }
    }
    for (int mode = 0; mode < 4; mode++) {
        if (fesetround(modes[mode]) || fegetround() != modes[mode]) abort();
        const int kinds[] = {NUMERIC_BYTE, NUMERIC_INT, NUMERIC_FLOAT};
        const char *ordinary[] = {"ordinary", "sparse", "tags", "cancel"};
        const char *facts[] = {"known", "conservative", "subset", "unknown", "outside"};
        for (size_t kind = 0; kind < sizeof kinds / sizeof *kinds; kind++)
            for (size_t pattern = 0; pattern < sizeof ordinary / sizeof *ordinary; pattern++)
                for (size_t fact = 0; fact < sizeof facts / sizeof *facts; fact++) {
                    if (pattern != 0 && pattern != 2 && fact != 0) continue;
                    for (int chunked = 0; chunked < 2; chunked++)
                        for (int reverse = 0; reverse < 2; reverse++)
                            for (size_t op = 0; op < sizeof operations - 1; op++)
                                errors += mixed_case(mode, ordinary[pattern], 1, chunked,
                                    reverse, operations[op], kinds[kind], facts[fact]);
                }
        const char *integer_edges[] = {"limit_above", "limit_below", "physical_min", "endpoint"};
        const char *float_edges[] = {"sum_inside", "product_inside", "product_endpoint", "product_outside", "endpoint"};
        for (int floats = 0; floats < 2; floats++) {
            const char **edges = floats ? float_edges : integer_edges;
            size_t edge_count = floats ? sizeof float_edges / sizeof *float_edges
                : sizeof integer_edges / sizeof *integer_edges;
            for (size_t pattern = 0; pattern < edge_count; pattern++)
                for (int unknown = 0; unknown < 2; unknown++)
                    for (int chunked = 0; chunked < 2; chunked++)
                        for (int reverse = 0; reverse < 2; reverse++)
                            for (size_t op = 0; op < sizeof operations - 1; op++)
                                errors += mixed_case(mode, edges[pattern], 1, chunked,
                                    reverse, operations[op], floats ? NUMERIC_FLOAT : NUMERIC_INT,
                                    unknown ? "unknown" : "known");
        }
    }
    fesetround(FE_TONEAREST);
    fprintf(stderr, "%u semantic failures\n", errors);
    return errors != 0;
}
