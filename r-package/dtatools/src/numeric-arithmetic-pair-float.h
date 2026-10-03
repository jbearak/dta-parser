/* A finite binary32 product has at most 48 significand bits and magnitude
   between 2^-298 and 2^256. The established binary64 product is therefore
   exact. For byte/int16/float operands, direct binary32 multiplication has
   exactly the same final rounding as that exact product followed by one
   float conversion. Long operands are excluded: conversion can lose bits.

   Storage selection still follows the exact binary64 product. A rounded
   magnitude strictly below/above the representable observed limit proves
   float fit/double promotion respectively. Equality is ambiguous and reruns
   the existing binary64 producer, including whole-column recomputation on
   promotion. No rounded float result is widened into a promoted output. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_PAIR_FLOAT_H
#define DTATOOLS_NUMERIC_ARITHMETIC_PAIR_FLOAT_H

static int arithmetic_pair_float_multiply_admitted(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, int operation, int kind
) {
    if (operation != '*' || kind != NUMERIC_FLOAT ||
        !arithmetic_pair_admitted(left, right, length, operation, kind)) return 0;
    int x_kind = left->operand->reader.storage->kind;
    int y_kind = right->operand->reader.storage->kind;
    return x_kind != NUMERIC_LONG && y_kind != NUMERIC_LONG &&
        (x_kind == NUMERIC_FLOAT || y_kind == NUMERIC_FLOAT);
}

#define ARITHMETIC_PAIR_FLOAT_LOOP(X, Y)                                  \
    do {                                                                 \
        float *restrict target = (float *) (void *) output->raw + start;  \
        unsigned missing_count = 0;                                     \
        for (size_t i = 0; i < count; i++) {                             \
            arithmetic_pair_value x = arithmetic_pair_load_##X(x_raw, i, &x_policy); \
            arithmetic_pair_value y = arithmetic_pair_load_##Y(y_raw, i, &y_policy); \
            unsigned invalid = x.missing | y.missing | x.infinite | y.infinite; \
            float a = invalid ? 0.0f : x.float_value;                    \
            float b = invalid ? 0.0f : y.float_value;                    \
            float value = a * b;                                        \
            uint32_t bits;                                               \
            memcpy(&bits, &value, sizeof(bits));                         \
            bits &= UINT32_C(0x7fffffff);                               \
            maximum = bits > maximum ? bits : maximum;                  \
            missing_count += invalid;                                   \
            target[i] = invalid ? 0x1p127f : value;                      \
        }                                                                \
        output->missing_count += missing_count;                         \
    } while (0)

#define ARITHMETIC_PAIR_FLOAT_RIGHT(X)                                   \
    switch (y_policy.kind) {                                             \
    case NUMERIC_BYTE: ARITHMETIC_PAIR_FLOAT_LOOP(X, byte); break;        \
    case NUMERIC_INT: ARITHMETIC_PAIR_FLOAT_LOOP(X, int); break;          \
    case NUMERIC_FLOAT: ARITHMETIC_PAIR_FLOAT_LOOP(X, float); break;      \
    case ARITHMETIC_SOURCE_OBSERVED_FLOAT: ARITHMETIC_PAIR_FLOAT_LOOP(X, observed_float); break; \
    case ARITHMETIC_PAIR_LEGACY_FLOAT: ARITHMETIC_PAIR_FLOAT_LOOP(X, legacy_float); break; \
    }

static int arithmetic_pair_float_multiply_write(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, arithmetic_general_output *output
) {
    const arithmetic_pair_policy x_policy = arithmetic_pair_policy_for(left);
    const arithmetic_pair_policy y_policy = arithmetic_pair_policy_for(right);
    uint32_t maximum = 0;
    for (size_t start = 0; start < (size_t) length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) length - start;
        if (count > 16384) count = 16384;
        const unsigned char *x_raw = arithmetic_general_span(left, start, &count);
        const unsigned char *y_raw = arithmetic_general_span(right, start, &count);
        switch (x_policy.kind) {
        case NUMERIC_BYTE: ARITHMETIC_PAIR_FLOAT_RIGHT(byte); break;
        case NUMERIC_INT: ARITHMETIC_PAIR_FLOAT_RIGHT(int); break;
        case NUMERIC_FLOAT: ARITHMETIC_PAIR_FLOAT_RIGHT(float); break;
        case ARITHMETIC_SOURCE_OBSERVED_FLOAT: ARITHMETIC_PAIR_FLOAT_RIGHT(observed_float); break;
        case ARITHMETIC_PAIR_LEGACY_FLOAT: ARITHMETIC_PAIR_FLOAT_RIGHT(legacy_float); break;
        }
        start += count;
    }
    if (maximum > UINT32_C(0x7effffff)) return NUMERIC_DOUBLE;
    if (maximum == UINT32_C(0x7effffff)) {
        /* The float backing remains private. Discard provisional reductions
           before the exact producer overwrites every lane and decides fit. */
        output->missing_count = 0;
        output->magnitude = 0;
        return arithmetic_pair_write(left, right, length, '*', output);
    }
    return NUMERIC_FLOAT;
}

#undef ARITHMETIC_PAIR_FLOAT_RIGHT
#undef ARITHMETIC_PAIR_FLOAT_LOOP
#endif
