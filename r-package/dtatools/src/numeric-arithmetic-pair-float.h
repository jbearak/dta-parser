/* For byte/int16/float operands, binary32 +, - and * have the same final
   rounding as the established binary64 expression then one float conversion.
   A nonzero finite product has at most 48 significand bits and magnitude
   between 2^-298 and 2^256, so its binary64 evaluation is exact. For sums and
   differences, an exponent gap <= 29 also fits exactly in binary64. At larger
   gaps the smaller operand plus binary64 rounding error is below the nearest
   binary32 midpoint margin, including the smaller lower-binade spacing.
   Directed rounding composes across the nested binary32/binary64 grids.
   Long operands are excluded because their float conversion can lose bits.

   Storage selection still follows the rounded binary64 expression, which
   need not equal the exact rational sum at a large exponent gap. A rounded
   magnitude strictly below/above the representable observed limit proves
   float fit/double promotion respectively. Equality is ambiguous and reruns
   the existing binary64 producer, including whole-column recomputation on
   promotion. No rounded float result is widened into a promoted output. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_PAIR_FLOAT_H
#define DTATOOLS_NUMERIC_ARITHMETIC_PAIR_FLOAT_H

enum {
    ARITHMETIC_PAIR_CANONICAL_FLOAT = 9,
    ARITHMETIC_PAIR_CANONICAL_OBSERVED_FLOAT = 10
};

static arithmetic_pair_policy arithmetic_pair_float_policy_for(
    const arithmetic_general_source *source
) {
    arithmetic_pair_policy policy = arithmetic_pair_policy_for(source);
    const numeric_data *data = source->operand->reader.storage;
    /* The operand's captured read claim protects the descriptor and bytes.
       Unknown imports retain the general missing/infinity classification. */
    if (numeric_strict_modern_float(data)) {
        policy.kind = data->missing_count == 0
            ? ARITHMETIC_PAIR_CANONICAL_OBSERVED_FLOAT
            : ARITHMETIC_PAIR_CANONICAL_FLOAT;
    }
    return policy;
}

static int arithmetic_pair_float_admitted(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, int operation, int kind
) {
    if ((operation != '+' && operation != '-' && operation != '*') ||
        kind != NUMERIC_FLOAT ||
        !arithmetic_pair_admitted(left, right, length, operation, kind)) return 0;
    int x_kind = left->operand->reader.storage->kind;
    int y_kind = right->operand->reader.storage->kind;
    return x_kind != NUMERIC_LONG && y_kind != NUMERIC_LONG &&
        (x_kind == NUMERIC_FLOAT || y_kind == NUMERIC_FLOAT);
}

/* Integer physical limits and protected FLOAT magnitude bounds can prove
   storage fit once for the entire captured input. Bounds may be conservative
   for a subset; no exact count is consumed by this proof. */
static int arithmetic_pair_float_magnitude_bound(
    const arithmetic_general_source *source, double *bound
) {
    const numeric_data *data = source->operand->reader.storage;
    if (data->kind == NUMERIC_BYTE) { *bound = 128.0; return 1; }
    if (data->kind == NUMERIC_INT) { *bound = 32768.0; return 1; }
    if (!numeric_float_bounds_known(data) ||
        data->float_max_magnitude_bound > UINT32_C(0x7effffff)) return 0;
    float maximum;
    memcpy(&maximum, &data->float_max_magnitude_bound, sizeof(maximum));
    *bound = (double) maximum;
    return 1;
}

static int arithmetic_pair_float_range_proved(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    int operation
) {
    double x, y;
    if (!arithmetic_pair_float_magnitude_bound(left, &x) ||
        !arithmetic_pair_float_magnitude_bound(right, &y)) return 0;
    double bound = operation == '*' ? x * y : x + y;
    /* All finite compact products fit binary64 exactly. A sum at a large
       exponent gap may round down in the current mode. Advance its positive
       binary64 representation by one ulp to bound the exact sum in all four
       modes, without an extra floating-point operation or exception flag. */
    if (operation != '*') {
        uint64_t bits;
        memcpy(&bits, &bound, sizeof(bits));
        bits++;
        memcpy(&bound, &bits, sizeof(bound));
    }
    /* Strict inequality leaves the representable observed endpoint inside
       the proof even when the producer rounds upward to binary32. */
    return bound < numeric_float_observed_limit();
}

#define ARITHMETIC_PAIR_FLOAT_ROWS(X, Y, OP, RANGE_PROVED)                 \
    do {                                                                 \
        for (size_t i = 0; i < count; i++) {                             \
            arithmetic_pair_value x = arithmetic_pair_load_##X(x_raw, i, &x_policy); \
            arithmetic_pair_value y = arithmetic_pair_load_##Y(y_raw, i, &y_policy); \
            unsigned invalid = x.missing | y.missing | x.infinite | y.infinite; \
            float a = invalid ? 0.0f : x.float_value;                    \
            float b = invalid ? 0.0f : y.float_value;                    \
            float value = a OP b;                                       \
            if (!(RANGE_PROVED)) {                                      \
                uint32_t bits;                                           \
                memcpy(&bits, &value, sizeof(bits));                     \
                bits &= UINT32_C(0x7fffffff);                           \
                maximum = bits > maximum ? bits : maximum;              \
            }                                                            \
            missing_count += invalid;                                   \
            target[i] = invalid ? 0x1p127f : value;                      \
        }                                                                \
    } while (0)

#define ARITHMETIC_PAIR_FLOAT_LOOP(X, Y, OP)                              \
    do {                                                                 \
        float *restrict target = (float *) (void *) output->raw + start;  \
        unsigned missing_count = 0;                                     \
        if (range_proved) {                                              \
            ARITHMETIC_PAIR_FLOAT_ROWS(X, Y, OP, 1);                     \
        } else {                                                         \
            ARITHMETIC_PAIR_FLOAT_ROWS(X, Y, OP, 0);                     \
        }                                                                \
        output->missing_count += missing_count;                         \
    } while (0)

#define ARITHMETIC_PAIR_FLOAT_RIGHT(X, OP)                               \
    switch (y_policy.kind) {                                             \
    case NUMERIC_BYTE: ARITHMETIC_PAIR_FLOAT_LOOP(X, byte, OP); break;    \
    case NUMERIC_INT: ARITHMETIC_PAIR_FLOAT_LOOP(X, int, OP); break;      \
    case NUMERIC_FLOAT: ARITHMETIC_PAIR_FLOAT_LOOP(X, float, OP); break;  \
    case ARITHMETIC_SOURCE_OBSERVED_FLOAT: ARITHMETIC_PAIR_FLOAT_LOOP(X, observed_float, OP); break; \
    case ARITHMETIC_PAIR_LEGACY_FLOAT: ARITHMETIC_PAIR_FLOAT_LOOP(X, legacy_float, OP); break; \
    case ARITHMETIC_PAIR_CANONICAL_FLOAT: ARITHMETIC_PAIR_FLOAT_LOOP(X, canonical_float, OP); break; \
    case ARITHMETIC_PAIR_CANONICAL_OBSERVED_FLOAT: ARITHMETIC_PAIR_FLOAT_LOOP(X, canonical_observed_float, OP); break; \
    }

#define ARITHMETIC_PAIR_FLOAT_LEFT(OP)                                  \
    switch (x_policy.kind) {                                             \
    case NUMERIC_BYTE: ARITHMETIC_PAIR_FLOAT_RIGHT(byte, OP); break;     \
    case NUMERIC_INT: ARITHMETIC_PAIR_FLOAT_RIGHT(int, OP); break;       \
    case NUMERIC_FLOAT: ARITHMETIC_PAIR_FLOAT_RIGHT(float, OP); break;   \
    case ARITHMETIC_SOURCE_OBSERVED_FLOAT: ARITHMETIC_PAIR_FLOAT_RIGHT(observed_float, OP); break; \
    case ARITHMETIC_PAIR_LEGACY_FLOAT: ARITHMETIC_PAIR_FLOAT_RIGHT(legacy_float, OP); break; \
    case ARITHMETIC_PAIR_CANONICAL_FLOAT: ARITHMETIC_PAIR_FLOAT_RIGHT(canonical_float, OP); break; \
    case ARITHMETIC_PAIR_CANONICAL_OBSERVED_FLOAT: ARITHMETIC_PAIR_FLOAT_RIGHT(canonical_observed_float, OP); break; \
    }

static int arithmetic_pair_float_write(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, int operation, arithmetic_general_output *output
) {
    const arithmetic_pair_policy x_policy = arithmetic_pair_float_policy_for(left);
    const arithmetic_pair_policy y_policy = arithmetic_pair_float_policy_for(right);
    const int range_proved = arithmetic_pair_float_range_proved(left, right, operation);
    uint32_t maximum = 0;
    for (size_t start = 0; start < (size_t) length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) length - start;
        if (count > 16384) count = 16384;
        const unsigned char *x_raw = arithmetic_general_span(left, start, &count);
        const unsigned char *y_raw = arithmetic_general_span(right, start, &count);
        /* Instantiate each operation outside the row loop. Source layout,
           missing semantics and whole-column promotion stay shared. */
        switch (operation) {
        case '+': ARITHMETIC_PAIR_FLOAT_LEFT(+); break;
        case '-': ARITHMETIC_PAIR_FLOAT_LEFT(-); break;
        case '*': ARITHMETIC_PAIR_FLOAT_LEFT(*); break;
        }
        start += count;
    }
    if (range_proved) return NUMERIC_FLOAT;
    if (maximum > UINT32_C(0x7effffff)) return NUMERIC_DOUBLE;
    if (maximum == UINT32_C(0x7effffff)) {
        /* The float backing remains private. Discard provisional reductions
           before the exact producer overwrites every lane and decides fit. */
        output->missing_count = 0;
        output->magnitude = 0;
        return arithmetic_pair_write(left, right, length, operation, output);
    }
    return NUMERIC_FLOAT;
}

#undef ARITHMETIC_PAIR_FLOAT_LEFT
#undef ARITHMETIC_PAIR_FLOAT_RIGHT
#undef ARITHMETIC_PAIR_FLOAT_LOOP
#undef ARITHMETIC_PAIR_FLOAT_ROWS
#endif
