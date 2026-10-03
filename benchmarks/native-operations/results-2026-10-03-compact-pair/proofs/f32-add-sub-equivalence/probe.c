/* Standalone semantic experiment only. This file is not included by the
   package and changes no production path. Compare the established binary64
   addition/subtraction storage contract with proposed binary32 operations plus exact
   boundary fallback, including imported physical encodings. No timings. */
#include <fenv.h>
#include <float.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "extracted-classifiers.h"
#pragma STDC FENV_ACCESS ON

enum { BYTE, INT, FLOAT };
typedef struct { int kind, legacy; int integer; uint32_t bits; } input;
typedef struct { int kind, missing; uint64_t bits; } result;
static uint64_t checked, equal_boundary, strict_promotion, checksum;
static uint64_t ambiguous_above, ambiguous_below, exact_boundary;
static uint64_t column_checks;
typedef struct { input x, y; uint64_t exact_bits; uint32_t rounded_bits; int present; } witness;
static witness boundary_witness[4];
typedef struct { int mode; uint64_t checked, counts[4], columns; uint32_t positive, negative; witness witnesses[4]; } mode_result;
static mode_result mode_results[8];
static char operation;
typedef struct { input x, y; uint64_t binary64_bits; uint32_t binary32_bits; result encoded; } oracle_witness;
static oracle_witness oracle_witnesses[8][256];
static size_t oracle_counts[8];
static char record_operations[8];
static float from_bits(uint32_t bits) { float value; memcpy(&value, &bits, 4); return value; }
static uint32_t to_bits(float value) { uint32_t bits; memcpy(&bits, &value, 4); return bits; }
static result missing_result(void) { return (result) {FLOAT, 1, UINT32_C(0x7f000000)}; }

static double reference_value(input x, int *invalid) {
    int code;
    if (x.kind == BYTE) { code = byte_missing_offset((int8_t) x.integer, x.legacy ? 111 : 119); }
    else if (x.kind == INT) { code = int_missing_offset((int16_t) x.integer, x.legacy ? 111 : 119); }
    else {
        float value = from_bits(x.bits);
        code = float_missing_offset(value, x.legacy ? 111 : 119);
        *invalid |= code >= 0 || !isfinite(value);
        return (double) value;
    }
    *invalid |= code >= 0;
    return (double) x.integer;
}

static float candidate_value(input x, int *invalid) {
    if (x.kind != FLOAT) {
        int minimum = x.kind == BYTE ? (x.legacy ? 127 : 101) : (x.legacy ? 32767 : 32741);
        *invalid |= x.integer >= minimum;
        return (float) x.integer;
    }
    uint32_t magnitude = x.bits & UINT32_C(0x7fffffff);
    uint32_t offset = x.bits - UINT32_C(0x7f000000);
    unsigned missing = x.legacy ? offset <= UINT32_C(0x00ffffff)
        : ((offset >> 11) | (offset << 21)) <= 26U;
    *invalid |= missing | (magnitude >= UINT32_C(0x7f800000));
    return from_bits(x.bits);
}

static result encode_double(double value) {
    const double limit = (double) from_bits(UINT32_C(0x7effffff));
    if (fabs(value) > limit) {
        uint64_t bits; memcpy(&bits, &value, 8);
        return (result) {3, 0, bits};
    }
    return (result) {FLOAT, 0, to_bits((float) value)};
}

__attribute__((noinline)) static result reference(input x, input y) {
    int invalid = 0;
    double a = reference_value(x, &invalid), b = reference_value(y, &invalid);
    if (invalid) return missing_result();
    /* Keep an actual binary64 evaluation observable to the compiler. */
    volatile double product = operation == '+' ? a + b : a - b;
    return encode_double(product);
}

__attribute__((noinline)) static result candidate(input x, input y) {
    int invalid = 0;
    float a = candidate_value(x, &invalid), b = candidate_value(y, &invalid);
    a = invalid ? 0.0f : a;
    b = invalid ? 0.0f : b;
    volatile float product = operation == '+' ? a + b : a - b;
    uint32_t bits = to_bits(product);
    if (invalid) return missing_result();
    uint32_t magnitude = bits & UINT32_C(0x7fffffff);
    if (magnitude < UINT32_C(0x7effffff)) return (result) {FLOAT, 0, bits};
    if (magnitude > UINT32_C(0x7effffff)) {
        strict_promotion++;
        result exact = reference(x, y);
        if (exact.kind != 3 || exact.missing) {
            fputs("Rounded strict promotion was not justified by exact binary64 result\n", stderr);
            exit(1);
        }
        if (!boundary_witness[3].present)
            boundary_witness[3] = (witness) {x, y, exact.bits, bits, 1};
    }
    else {
        equal_boundary++;
        double exact = operation == '+' ? (double) a + (double) b : (double) a - (double) b;
        double limit = (double) from_bits(UINT32_C(0x7effffff));
        int category;
        if (fabs(exact) > limit) { ambiguous_above++; category = 0; }
        else if (fabs(exact) < limit) { ambiguous_below++; category = 1; }
        else { exact_boundary++; category = 2; }
        if (!boundary_witness[category].present) {
            uint64_t exact_bits; memcpy(&exact_bits, &exact, 8);
            boundary_witness[category] = (witness) {x, y, exact_bits, bits, 1};
        }
    }
    /* Stand in for the proposed whole-column binary64 recomputation. */
    return reference(x, y);
}

static void check(input x, input y) {
    result expected = reference(x, y), actual = candidate(x, y);
    checked++;
    if (expected.kind != actual.kind || expected.missing != actual.missing || expected.bits != actual.bits) {
        fprintf(stderr, "Mismatch #%" PRIu64 " x(kind=%d,int=%d,bits=%08" PRIx32 ",legacy=%d) y(kind=%d,int=%d,bits=%08" PRIx32 ",legacy=%d) expected=%d/%d/%016" PRIx64 " actual=%d/%d/%016" PRIx64 "\n",
            checked, x.kind, x.integer, x.bits, x.legacy, y.kind, y.integer, y.bits, y.legacy,
            expected.kind, expected.missing, expected.bits, actual.kind, actual.missing, actual.bits);
        exit(1);
    }
    checksum = (checksum ^ actual.bits ^ (uint64_t) actual.kind ^ (uint64_t) actual.missing) * UINT64_C(1099511628211);
}

/* A standalone whole-column model, not a package integration test. A late
   ambiguous or strict boundary forces complete recomputation; prior rounded
   floats must never be widened into the promoted double output. */
static void check_column(witness edge) {
    enum { LENGTH = 19 };
    input x[LENGTH], y[LENGTH];
    result actual[LENGTH], expected[LENGTH];
    const input ordinary = {FLOAT, 0, 0, UINT32_C(0x3f800001)};
    const input multiplier = {INT, 0, 7, 0};
    for (int i = 0; i < LENGTH; i++) { x[i] = ordinary; y[i] = multiplier; }
    x[1] = (input) {FLOAT, 0, 0, UINT32_C(0x7f000800)};
    y[1] = (input) {INT, 0, 32742, 0}; /* one missing union, not two */
    y[2] = (input) {FLOAT, 0, 0, UINT32_C(0xff800000)};
    x[LENGTH - 1] = edge.x; y[LENGTH - 1] = edge.y;
    uint32_t maximum = 0;
    unsigned first_count = 0, final_count = 0, expected_count = 0;
    int expected_kind = FLOAT;
    for (int start = 0; start < LENGTH;) {
        int end_x = ((start / 3) + 1) * 3, end_y = ((start / 4) + 1) * 4;
        int end = end_x < end_y ? end_x : end_y;
        if (end > LENGTH) end = LENGTH;
        for (int i = start; i < end; i++) {
            int invalid = 0;
            float a = candidate_value(x[i], &invalid), b = candidate_value(y[i], &invalid);
            a = invalid ? 0.0f : a;
            b = invalid ? 0.0f : b;
            volatile float value = operation == '+' ? a + b : a - b;
            uint32_t bits = to_bits(value), magnitude = invalid ? 0 : bits & UINT32_C(0x7fffffff);
            if (magnitude > maximum) maximum = magnitude;
            first_count += (unsigned) invalid;
            actual[i] = invalid ? missing_result() : (result) {FLOAT, 0, bits};
            expected[i] = reference(x[i], y[i]);
            if (expected[i].kind == 3) expected_kind = 3;
            expected_count += (unsigned) expected[i].missing;
        }
        start = end;
    }
    int actual_kind = FLOAT;
    if (maximum >= UINT32_C(0x7effffff)) {
        /* Equal is unresolved: exact binary64 preflight, then full promotion. */
        for (int i = 0; i < LENGTH; i++) if (reference(x[i], y[i]).kind == 3) actual_kind = 3;
        if (maximum > UINT32_C(0x7effffff) && actual_kind != 3) {
            fputs("Whole-column strict promotion failed\n", stderr); exit(1);
        }
        first_count = 0; /* reset provisional reductions before recomputation */
        for (int i = 0; i < LENGTH; i++) {
            int invalid = 0;
            double a = reference_value(x[i], &invalid), b = reference_value(y[i], &invalid);
            volatile double value = operation == '+' ? a + b : a - b;
            first_count += (unsigned) invalid;
            if (actual_kind == 3) {
                uint64_t bits; memcpy(&bits, (const void *) &value, 8);
                actual[i] = (result) {3, invalid, invalid ? UINT64_C(0x7ff00000000007a2) : bits};
            } else actual[i] = invalid ? missing_result() : encode_double(value);
        }
    }
    for (int i = 0; i < LENGTH; i++) {
        if (expected_kind == 3) {
            int invalid = 0;
            double a = reference_value(x[i], &invalid), b = reference_value(y[i], &invalid);
            volatile double value = operation == '+' ? a + b : a - b;
            uint64_t bits; memcpy(&bits, (const void *) &value, 8);
            expected[i] = (result) {3, invalid, invalid ? UINT64_C(0x7ff00000000007a2) : bits};
        }
        final_count += (unsigned) actual[i].missing;
        if (actual[i].kind != expected[i].kind || actual[i].missing != expected[i].missing || actual[i].bits != expected[i].bits) {
            fputs("Whole-column result mismatch\n", stderr); exit(1);
        }
        checksum = (checksum ^ actual[i].bits) * UINT64_C(1099511628211);
    }
    if (actual_kind != expected_kind || first_count != expected_count || final_count != expected_count) {
        fputs("Whole-column promotion or missing-union mismatch\n", stderr); exit(1);
    }
    column_checks++;
}

static uint64_t random_state = UINT64_C(0x917fa259d286c34b);
static uint32_t next_bits(void) {
    random_state ^= random_state << 13;
    random_state ^= random_state >> 7;
    random_state ^= random_state << 17;
    return (uint32_t) (random_state >> 16);
}

static void add_oracle(int index, input x, input y) {
    check(x, y);
    int invalid = 0;
    double a = reference_value(x, &invalid), b = reference_value(y, &invalid);
    if (invalid || oracle_counts[index] >= 256) { fputs("Invalid oracle witness fixture\n", stderr); exit(1); }
    volatile double d = operation == '+' ? a + b : a - b;
    volatile float fa = (float) a, fb = (float) b;
    volatile float f = operation == '+' ? fa + fb : fa - fb;
    uint64_t bits; memcpy(&bits, (const void *) &d, 8);
    oracle_witnesses[index][oracle_counts[index]++] = (oracle_witness) {x, y, bits, to_bits(f), reference(x,y)};
}

static void run_mode(int mode, int index) {
    if (fesetround(mode) != 0) { fputs("Unable to set rounding mode\n", stderr); exit(1); }
    if (fegetround() != mode) { fputs("Rounding mode did not persist\n", stderr); exit(1); }
    volatile float one = 1.0f, half = 0x1p-24f;
    volatile float positive = operation == '+' ? one + half : one - (-half);
    volatile float negative = operation == '+' ? -one + (-half) : -one - half;
    uint32_t positive_bits = to_bits(positive), negative_bits = to_bits(negative);
    uint32_t positive_expected = mode == FE_UPWARD ? UINT32_C(0x3f800001) : UINT32_C(0x3f800000);
    uint32_t negative_expected = mode == FE_DOWNWARD ? UINT32_C(0xbf800001) : UINT32_C(0xbf800000);
    if (positive_bits != positive_expected || negative_bits != negative_expected) {
        fputs("Generated addition/subtraction does not honor rounding mode\n", stderr); exit(1);
    }
    record_operations[index] = operation;
    uint64_t before_checked = checked, before_columns = column_checks;
    uint64_t before_counts[] = {ambiguous_above, ambiguous_below, exact_boundary, strict_promotion};
    memset(boundary_witness, 0, sizeof(boundary_witness));
    uint32_t floats[128]; size_t count = 0;
    const uint32_t endpoints[] = {0, 1, 0x007fffff, 0x00800000, 0x3f000000, 0x3f800000,
        0x7efffffe, 0x7effffff, 0x7f000000, 0x7f000001, 0x7f00d001, 0x7f7fffff,
        0x7f800000, 0x7f800001, 0x7fc00000, 0x7fffffff};
    for (size_t i = 0; i < sizeof(endpoints) / sizeof(*endpoints); i++) {
        floats[count++] = endpoints[i]; floats[count++] = endpoints[i] | UINT32_C(0x80000000);
    }
    for (uint32_t tag = 0; tag <= 26; tag++) {
        uint32_t bits = UINT32_C(0x7f000000) + (tag << 11);
        floats[count++] = bits - 1; floats[count++] = bits; floats[count++] = bits + 1;
    }
    for (int legacy_x = 0; legacy_x <= 1; legacy_x++) for (int legacy_y = 0; legacy_y <= 1; legacy_y++) {
        for (size_t i = 0; i < count; i++) for (size_t j = 0; j < count; j++)
            check((input) {FLOAT, legacy_x, 0, floats[i]}, (input) {FLOAT, legacy_y, 0, floats[j]});
        for (int value = -32768; value <= 32767; value++) {
            const int selected[] = {0, 5, 12, 13, 20, 21, 22, 23, 24, 25, 26, 27};
            for (size_t i = 0; i < sizeof(selected) / sizeof(*selected); i++) {
                input integer = {INT, legacy_x, value, 0};
                input floating = {FLOAT, legacy_y, 0, floats[selected[i]]};
                check(integer, floating); check(floating, integer);
            }
        }
        for (int value = -128; value <= 127; value++) for (size_t i = 0; i < count; i++) {
            input integer = {BYTE, legacy_x, value, 0};
            input floating = {FLOAT, legacy_y, 0, floats[i]};
            check(integer, floating); check(floating, integer);
        }
    }
    /* Gaps around the exact-binary64 bound and both sides of binades. */
    const int gaps[] = {28, 29, 30, 31, 52, 53, 54, 100};
    const uint32_t mantissas[] = {0, 1, 0x7ffffe, 0x7fffff};
    for (int e = -126; e <= 127; e++) for (size_t g = 0; g < sizeof(gaps)/sizeof(*gaps); g++) {
        int smaller = e - gaps[g];
        if (smaller < -149) continue;
        uint32_t small = smaller >= -126 ? (uint32_t) (smaller + 127) << 23 : 1U << (smaller + 149);
        for (size_t i = 0; i < 4; i++) for (int delta = -1; delta <= 1; delta++) {
            uint32_t large = ((uint32_t) (e + 127) << 23) | mantissas[i];
            uint32_t lower = small + (uint32_t) delta;
            for (uint32_t sx = 0; sx <= 1; sx++) for (uint32_t sy = 0; sy <= 1; sy++) {
                input x = {FLOAT, 0, 0, large | (sx << 31)};
                input y = {FLOAT, 0, 0, lower | (sy << 31)};
                check(x, y); check(y, x);
            }
        }
    }
    /* Independent rational oracle records: zero signs, cancellation, gaps,
       subnormal boundaries, and rounded-f64 storage at L +/- 1. */
    for (uint32_t sx = 0; sx <= 1; sx++) for (uint32_t sy = 0; sy <= 1; sy++)
        add_oracle(index, (input) {FLOAT,0,0,sx << 31}, (input) {FLOAT,0,0,sy << 31});
    const uint32_t cancel[] = {1, 0x007fffff, 0x00800000, 0x3f7fffff, 0x3f800000, 0x3f800001, 0x7effffff};
    for (size_t c = 0; c < sizeof(cancel)/sizeof(*cancel); c++) for (uint32_t sx = 0; sx <= 1; sx++) {
        uint32_t x = cancel[c] | (sx << 31);
        uint32_t y = x ^ (operation == '+' ? UINT32_C(0x80000000) : 0);
        add_oracle(index, (input) {FLOAT,0,0,x}, (input) {FLOAT,0,0,y});
    }
    const int oracle_exponents[] = {-119, -1, 0, 126};
    for (size_t e = 0; e < 4; e++) for (size_t g = 0; g < 4; g++) {
        int exponent = oracle_exponents[e], smaller = exponent - gaps[g];
        if (smaller < -149) continue;
        uint32_t a = (uint32_t) (exponent + 127) << 23;
        uint32_t b = smaller >= -126 ? ((uint32_t) (smaller + 127) << 23) | UINT32_C(0x7fffff) : 1U << (smaller + 149);
        for (uint32_t sx = 0; sx <= 1; sx++) for (uint32_t sy = 0; sy <= 1; sy++)
            add_oracle(index, (input) {FLOAT,0,0,a | (sx << 31)}, (input) {FLOAT,0,0,b | (sy << 31)});
    }
    const uint32_t near_limit[] = {0x3f800000, 0x72000000, 0x72800000, 0x73000000, 0x7effffff};
    for (size_t b = 0; b < 5; b++) for (uint32_t sx = 0; sx <= 1; sx++) for (uint32_t sy = 0; sy <= 1; sy++)
        add_oracle(index, (input) {FLOAT,0,0,0x7effffff | (sx << 31)}, (input) {FLOAT,0,0,near_limit[b] | (sy << 31)});
    for (size_t i = 0; i < 1000000; i++) {
        input x = {FLOAT, (int) (next_bits() & 1), 0, next_bits()};
        input y = {FLOAT, (int) (next_bits() & 1), 0, next_bits()};
        check(x, y);
        x = (input) {INT, (int) (next_bits() & 1), (int) (next_bits() & 65535) - 32768, 0};
        check(x, y);
    }
    for (int i = 0; i < 4; i++) {
        if (boundary_witness[i].present) check_column(boundary_witness[i]);
    }
    check_column((witness) {{FLOAT, 0, 0, 0x3f800001}, {INT, 0, 7, 0}, 0, 0, 1});
    mode_result *record = &mode_results[index];
    record->mode = mode; record->checked = checked - before_checked;
    record->columns = column_checks - before_columns;
    uint64_t after_counts[] = {ambiguous_above, ambiguous_below, exact_boundary, strict_promotion};
    for (int i = 0; i < 4; i++) {
        record->counts[i] = after_counts[i] - before_counts[i];
        record->witnesses[i] = boundary_witness[i];
    }
    record->positive = positive_bits; record->negative = negative_bits;
}

int main(void) {
    if (sizeof(float) != 4 || sizeof(double) != 8 || FLT_RADIX != 2 || FLT_MANT_DIG != 24 || DBL_MANT_DIG != 53) {
        fputs("This diagnostic requires binary32/binary64\n", stderr); return 1;
    }
    for (int op = 0; op < 2; op++) {
        operation = op == 0 ? '+' : '-';
        run_mode(FE_TONEAREST, op*4); run_mode(FE_DOWNWARD, op*4+1);
        run_mode(FE_UPWARD, op*4+2); run_mode(FE_TOWARDZERO, op*4+3);
    }
    if (!ambiguous_above || !ambiguous_below || !exact_boundary || !strict_promotion) {
        fputs("Boundary coverage incomplete\n", stderr); return 1;
    }
    printf("{\"checked\":%" PRIu64 ",\"equal_boundary\":%" PRIu64 ",\"ambiguous_above\":%" PRIu64 ",\"ambiguous_below\":%" PRIu64 ",\"exact_boundary\":%" PRIu64 ",\"strict_promotion\":%" PRIu64 ",\"checksum\":\"%016" PRIx64 "\",\"mismatches\":0,\"rounding_modes\":4,\"operations\":2,\"column_checks\":%" PRIu64 ",\"modes\":[",
        checked, equal_boundary, ambiguous_above, ambiguous_below, exact_boundary, strict_promotion, checksum, column_checks);
    for (int m = 0; m < 8; m++) {
        mode_result r = mode_results[m];
        printf("%s{\"operation\":\"%c\",\"mode\":%d,\"checked\":%" PRIu64 ",\"counts\":[%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 "],\"columns\":%" PRIu64 ",\"rounding_positive\":\"%08" PRIx32 "\",\"rounding_negative\":\"%08" PRIx32 "\",\"witnesses\":[",
            m ? "," : "", record_operations[m], r.mode, r.checked, r.counts[0], r.counts[1], r.counts[2], r.counts[3], r.columns, r.positive, r.negative);
        for (int i = 0; i < 4; i++) {
            witness w = r.witnesses[i];
            printf("%s{\"category\":%d,\"present\":%d,\"x\":{\"kind\":%d,\"integer\":%d,\"bits\":\"%08" PRIx32 "\",\"legacy\":%d},\"y\":{\"kind\":%d,\"integer\":%d,\"bits\":\"%08" PRIx32 "\",\"legacy\":%d},\"binary64_result\":\"%016" PRIx64 "\",\"binary32_result\":\"%08" PRIx32 "\"}",
                i ? "," : "", i, w.present, w.x.kind, w.x.integer, w.x.bits, w.x.legacy,
                w.y.kind, w.y.integer, w.y.bits, w.y.legacy, w.exact_bits, w.rounded_bits);
        }
        printf("],\"oracle_witnesses\":[");
        for (size_t i = 0; i < oracle_counts[m]; i++) {
            oracle_witness w = oracle_witnesses[m][i];
            printf("%s{\"x\":{\"kind\":%d,\"integer\":%d,\"bits\":\"%08" PRIx32 "\",\"legacy\":%d},\"y\":{\"kind\":%d,\"integer\":%d,\"bits\":\"%08" PRIx32 "\",\"legacy\":%d},\"binary64_result\":\"%016" PRIx64 "\",\"binary32_result\":\"%08" PRIx32 "\",\"kind\":%d,\"missing\":%d,\"encoded_bits\":\"%016" PRIx64 "\"}",
                   i ? "," : "", w.x.kind, w.x.integer, w.x.bits, w.x.legacy,
                   w.y.kind, w.y.integer, w.y.bits, w.y.legacy, w.binary64_bits, w.binary32_bits,
                   w.encoded.kind, w.encoded.missing, w.encoded.bits);
        }
        printf("]}");
    }
    puts("]}");
    return 0;
}
