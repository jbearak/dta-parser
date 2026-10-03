/* Exercise the production scalar writer with minimal storage/R boundary mocks.
   The fixtures stay in a range where finite double results are Stata-observed.
   Classifier calls measure actual writer work; no timing threshold is used. */
#include <float.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef ptrdiff_t R_xlen_t;
enum { NUMERIC_FLOAT = 4, NUMERIC_DOUBLE = 5, ARITHMETIC_SOURCE_SCALAR = 0 };
#define NA_REAL NAN
#define R_FINITE isfinite
typedef struct {
    int kind, temporal, format_version;
    size_t missing_count;
    const unsigned char *raw;
} numeric_data;
typedef struct { struct { const numeric_data *storage; } reader; R_xlen_t length; } arithmetic_operand;
typedef struct { const arithmetic_operand *operand; int kind; double scalar; } arithmetic_general_source;
typedef struct { int kind; unsigned char *raw; double *real; size_t missing_count; } arithmetic_general_output;
static size_t classified;
static void R_CheckUserInterrupt(void) {}
static double numeric_float_observed_limit(void) { return 0x1.fffffep126; }
static int scalar_arithmetic_result_valid(double x) { return isfinite(x); }
static const unsigned char *numeric_read_span(const numeric_data *data,
        size_t start, size_t count, size_t *available) {
    *available = count;
    return data->raw + start * sizeof(float);
}
static int arithmetic_scale_float_invalid_modern(uint32_t bits) {
    classified++;
    uint32_t offset = bits - UINT32_C(0x7f000000);
    return (bits & UINT32_C(0x7fffffff)) >= UINT32_C(0x7f800000) ||
        ((offset >> 11) | (offset << 21)) <= 26U;
}
static int arithmetic_scale_float_invalid_legacy(uint32_t bits) {
    classified++;
    return (bits & UINT32_C(0x7fffffff)) >= UINT32_C(0x7f800000) ||
        bits - UINT32_C(0x7f000000) <= UINT32_C(0x00ffffff);
}
#include "numeric-arithmetic-float-scalar.h"

int main(void) {
    const size_t length = 1000000, prefix = 256;
    float *source = malloc(length * sizeof(*source));
    float *result = malloc(length * sizeof(*result));
    if (!source || !result) return 2;
    for (size_t i = 0; i < length; i++) source[i] = i < prefix ? 0x1p127f : 1.5f;
    numeric_data data = {NUMERIC_FLOAT, 0, 118, prefix, (const unsigned char *)source};
    arithmetic_operand operand = {{&data}, (R_xlen_t)length};
    arithmetic_general_source left = {&operand, NUMERIC_FLOAT, 0};
    arithmetic_general_source right = {NULL, ARITHMETIC_SOURCE_SCALAR, 1.01};
    arithmetic_float_scalar_proof proof;
    arithmetic_general_output output = {NUMERIC_FLOAT, (unsigned char *)result, NULL, 0};
    if (!arithmetic_float_scalar_prove(&left, &right, (R_xlen_t)length, '*', NUMERIC_FLOAT, &proof)) return 3;
    if (arithmetic_float_scalar_write(&proof, (R_xlen_t)length, &output) != NUMERIC_FLOAT || output.missing_count != prefix) return 4;
    const float expected = (float)(1.5 * 1.01);
    for (size_t i = 0; i < length; i++) {
        float want = i < prefix ? 0x1p127f : expected;
        if (memcmp(result+i, &want, sizeof(want)) != 0) return 5;
    }
    fprintf(stderr, "Actual scalar writer classified %zu of %zu rows after a %zu-row missing prefix\n", classified, length, prefix);
    free(source); free(result);
    return classified < length / 10 ? 0 : 1;
}
