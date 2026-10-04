/* Two compact physical domains prove the binary64 result range. Finite
   operands have magnitude below 2^128 and nonzero magnitude at least 2^-149:
   sums, products and nonzero quotients stay below 2^277, far inside Stata's
   observed double range. Keep exact input missing/IEEE facts in source width
   instead of encoding them into NaNs and reclassifying the computed double. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_PAIR_H
#define DTATOOLS_NUMERIC_ARITHMETIC_PAIR_H

enum { ARITHMETIC_PAIR_LEGACY_FLOAT = 8 };

typedef struct {
    int kind;
    int32_t missing_minimum;
} arithmetic_pair_policy;

typedef struct {
    double value;
    unsigned missing;
    unsigned infinite;
    unsigned zero;
    float float_value;
} arithmetic_pair_value;

static int arithmetic_pair_admitted(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, int operation, int kind
) {
    if (length <= 1 || (kind != NUMERIC_FLOAT && kind != NUMERIC_DOUBLE) ||
        (operation != '+' && operation != '-' && operation != '*' && operation != '/'))
        return 0;
    const arithmetic_general_source *sources[] = {left, right};
    for (int i = 0; i < 2; i++) {
        const arithmetic_operand *operand = sources[i]->operand;
        const numeric_data *data = operand->reader.storage;
        if (data == NULL || operand->length != length || data->temporal != 0 ||
            data->kind < NUMERIC_BYTE || data->kind > NUMERIC_FLOAT)
            return 0;
    }
    return 1;
}

static arithmetic_pair_policy arithmetic_pair_policy_for(
    const arithmetic_general_source *source
) {
    const numeric_data *data = source->operand->reader.storage;
    arithmetic_pair_policy policy = {
        .kind = source->kind,
        .missing_minimum = data->kind <= NUMERIC_LONG
            ? arithmetic_integer_missing(data) : 0
    };
    if (data->kind == NUMERIC_FLOAT && data->missing_count != 0 &&
        data->format_version <= 111) policy.kind = ARITHMETIC_PAIR_LEGACY_FLOAT;
    return policy;
}

#define ARITHMETIC_PAIR_INTEGER_LOAD(NAME, TYPE)                            \
    static inline arithmetic_pair_value arithmetic_pair_load_##NAME(        \
        const unsigned char *raw, size_t index,                             \
        const arithmetic_pair_policy *policy                               \
    ) {                                                                     \
        exact_integer_rows++;                                      \
        TYPE value;                                                         \
        memcpy(&value, raw + index * sizeof(value), sizeof(value));          \
        TYPE missing_minimum = (TYPE) policy->missing_minimum;              \
        return (arithmetic_pair_value) {                                    \
            (double) value, (unsigned) (value >= missing_minimum),           \
            0, (unsigned) (value == 0), (float) value                        \
        };                                                                  \
    }
ARITHMETIC_PAIR_INTEGER_LOAD(byte, int8_t)
ARITHMETIC_PAIR_INTEGER_LOAD(int, int16_t)
ARITHMETIC_PAIR_INTEGER_LOAD(long, int32_t)
#undef ARITHMETIC_PAIR_INTEGER_LOAD

#define ARITHMETIC_PAIR_FLOAT_LOAD(NAME, ENCODED_MISSING)                   \
    static inline arithmetic_pair_value arithmetic_pair_load_##NAME(       \
        const unsigned char *raw, size_t index,                            \
        const arithmetic_pair_policy *policy                              \
    ) {                                                                    \
        exact_float_rows++;                                       \
        (void) policy;                                                     \
        uint32_t bits;                                                     \
        memcpy(&bits, raw + index * sizeof(bits), sizeof(bits));           \
        uint32_t magnitude = bits & UINT32_C(0x7fffffff);                  \
        uint32_t offset = bits - UINT32_C(0x7f000000);                     \
        (void) offset;                                                     \
        float value;                                                       \
        memcpy(&value, &bits, sizeof(value));                              \
        return (arithmetic_pair_value) {                                  \
            (double) value, (unsigned) ((ENCODED_MISSING) |                \
                (magnitude > UINT32_C(0x7f800000))),                       \
            (unsigned) (magnitude == UINT32_C(0x7f800000)),                \
            (unsigned) (magnitude == 0), value                            \
        };                                                                 \
    }
ARITHMETIC_PAIR_FLOAT_LOAD(float, ((offset >> 11) | (offset << 21)) <= 26U)
ARITHMETIC_PAIR_FLOAT_LOAD(legacy_float, offset <= UINT32_C(0x00ffffff))
ARITHMETIC_PAIR_FLOAT_LOAD(observed_float, 0)
#undef ARITHMETIC_PAIR_FLOAT_LOAD

/* Division preserves observed denominator infinities: finite / +/-Inf is
   a valid signed zero. A numerator infinity is always invalid, and legacy
   +Inf remains inherited missing even when it is the denominator. NaNs and
   all encoded missings propagate for every operator. Float fit still uses
   the exact binary64 expression, with a finite placeholder before narrowing. */
#define ARITHMETIC_PAIR_LOOP(X, Y, OP, DIVIDE, TYPE, KIND, MISSING)         \
    do {                                                                   \
        TYPE *restrict target = (TYPE *) (void *) ((KIND) == NUMERIC_DOUBLE \
            ? (unsigned char *) output->real : output->raw) + start;       \
        uint64_t maximum_magnitude = output->magnitude;                    \
        unsigned missing_count = 0;                                       \
        double float_limit = numeric_float_observed_limit();               \
        uint64_t float_limit_bits;                                        \
        memcpy(&float_limit_bits, &float_limit, sizeof(float_limit_bits)); \
        for (size_t i = 0; i < count; i++) {                               \
            arithmetic_pair_value x = arithmetic_pair_load_##X(x_raw, i, &x_policy); \
            arithmetic_pair_value y = arithmetic_pair_load_##Y(y_raw, i, &y_policy); \
            unsigned invalid = x.missing | y.missing | x.infinite |       \
                ((DIVIDE) ? y.zero : y.infinite);                         \
            double value = x.value OP y.value;                            \
            double observed = invalid ? 0.0 : value;                      \
            double storable = observed;                                  \
            missing_count += invalid;                                    \
            if ((KIND) == NUMERIC_FLOAT) {                                \
                uint64_t bits;                                            \
                memcpy(&bits, &observed, sizeof(bits));                   \
                bits &= UINT64_C(0x7fffffffffffffff);                     \
                maximum_magnitude = bits > maximum_magnitude             \
                    ? bits : maximum_magnitude;                          \
                storable = bits <= float_limit_bits ? observed : 0;      \
            }                                                              \
            target[i] = invalid ? (TYPE) (MISSING) : (TYPE) storable;      \
        }                                                                  \
        output->magnitude = maximum_magnitude;                            \
        output->missing_count += missing_count;                          \
    } while (0)

#define ARITHMETIC_PAIR_TARGETS(X, Y, OP, DIVIDE)                          \
    if (output->kind == NUMERIC_FLOAT) {                                  \
        ARITHMETIC_PAIR_LOOP(X, Y, OP, DIVIDE, float, NUMERIC_FLOAT, 0x1p127f); \
    } else {                                                               \
        ARITHMETIC_PAIR_LOOP(X, Y, OP, DIVIDE, double, NUMERIC_DOUBLE, NA_REAL); \
    }
#define ARITHMETIC_PAIR_OPERATORS(X, Y)                                   \
    switch (operation) {                                                  \
    case '+': ARITHMETIC_PAIR_TARGETS(X, Y, +, 0); break;                  \
    case '-': ARITHMETIC_PAIR_TARGETS(X, Y, -, 0); break;                  \
    case '*': ARITHMETIC_PAIR_TARGETS(X, Y, *, 0); break;                  \
    case '/': ARITHMETIC_PAIR_TARGETS(X, Y, /, 1); break;                  \
    }
#define ARITHMETIC_PAIR_RIGHT(X)                                         \
    switch (y_policy.kind) {                                              \
    case NUMERIC_BYTE: ARITHMETIC_PAIR_OPERATORS(X, byte); break;          \
    case NUMERIC_INT: ARITHMETIC_PAIR_OPERATORS(X, int); break;            \
    case NUMERIC_LONG: ARITHMETIC_PAIR_OPERATORS(X, long); break;          \
    case NUMERIC_FLOAT: ARITHMETIC_PAIR_OPERATORS(X, float); break;        \
    case ARITHMETIC_SOURCE_OBSERVED_FLOAT: ARITHMETIC_PAIR_OPERATORS(X, observed_float); break; \
    case ARITHMETIC_PAIR_LEGACY_FLOAT: ARITHMETIC_PAIR_OPERATORS(X, legacy_float); break; \
    }

static int arithmetic_pair_write(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, int operation, arithmetic_general_output *output
) {
    const arithmetic_pair_policy x_policy = arithmetic_pair_policy_for(left);
    const arithmetic_pair_policy y_policy = arithmetic_pair_policy_for(right);
    for (size_t start = 0; start < (size_t) length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) length - start;
        if (count > 16384) count = 16384;
        const unsigned char *x_raw = arithmetic_general_span(left, start, &count);
        const unsigned char *y_raw = arithmetic_general_span(right, start, &count);
        switch (x_policy.kind) {
        case NUMERIC_BYTE: ARITHMETIC_PAIR_RIGHT(byte); break;
        case NUMERIC_INT: ARITHMETIC_PAIR_RIGHT(int); break;
        case NUMERIC_LONG: ARITHMETIC_PAIR_RIGHT(long); break;
        case NUMERIC_FLOAT: ARITHMETIC_PAIR_RIGHT(float); break;
        case ARITHMETIC_SOURCE_OBSERVED_FLOAT: ARITHMETIC_PAIR_RIGHT(observed_float); break;
        case ARITHMETIC_PAIR_LEGACY_FLOAT: ARITHMETIC_PAIR_RIGHT(legacy_float); break;
        }
        start += count;
    }
    if (output->kind == NUMERIC_FLOAT) {
        double maximum;
        memcpy(&maximum, &output->magnitude, sizeof(maximum));
        if (maximum > numeric_float_observed_limit()) return NUMERIC_DOUBLE;
    }
    return output->kind;
}
#include "numeric-arithmetic-pair-long-float.h"

#undef ARITHMETIC_PAIR_RIGHT
#undef ARITHMETIC_PAIR_OPERATORS
#undef ARITHMETIC_PAIR_TARGETS
#undef ARITHMETIC_PAIR_LOOP
#endif
