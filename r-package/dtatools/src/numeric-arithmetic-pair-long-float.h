/* Long/float addition retains its binary64 result. A bounded local proof can
   exclude missing and nonfinite inputs without classifying every ordinary
   output lane. Other operations and destinations keep their existing path. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_PAIR_LONG_FLOAT_H
#define DTATOOLS_NUMERIC_ARITHMETIC_PAIR_LONG_FLOAT_H

static int arithmetic_long_float_add_admitted(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, int operation, int kind
) {
    if (operation != '+' || kind != NUMERIC_DOUBLE ||
        !arithmetic_pair_admitted(left, right, length, operation, kind)) return 0;
    int x_kind = left->operand->reader.storage->kind;
    int y_kind = right->operand->reader.storage->kind;
    return (x_kind == NUMERIC_LONG && y_kind == NUMERIC_FLOAT) ||
        (x_kind == NUMERIC_FLOAT && y_kind == NUMERIC_LONG);
}

static int arithmetic_long_float_add_ordinary(
    const unsigned char *integer_raw, const unsigned char *float_raw,
    size_t count, int32_t missing_minimum
) {
    int32_t integer_maximum = INT32_MIN;
    uint32_t float_maximum = 0;
    for (size_t i = 0; i < count; i++) {
        int32_t integer;
        uint32_t bits;
        memcpy(&integer, integer_raw + 4 * i, sizeof(integer));
        memcpy(&bits, float_raw + 4 * i, sizeof(bits));
        bits &= UINT32_C(0x7fffffff);
        integer_maximum = integer > integer_maximum ? integer : integer_maximum;
        float_maximum = bits > float_maximum ? bits : float_maximum;
    }
    /* A signed maximum admits INT32_MIN. The conservative float magnitude
       bound excludes both missing layouts, all NaNs and infinities. High
       finite imports outside the proof remain valid in the exact fallback. */
    return integer_maximum < missing_minimum && float_maximum < UINT32_C(0x7f000000);
}

static void arithmetic_long_float_add_observed(
    const unsigned char *integer_raw, const unsigned char *float_raw,
    size_t start, size_t count, int reverse, arithmetic_general_output *output
) {
    double *restrict target = output->real + start;
    if (reverse) {
        for (size_t i = 0; i < count; i++) {
            int32_t integer;
            float value;
            memcpy(&integer, integer_raw + 4 * i, sizeof(integer));
            memcpy(&value, float_raw + 4 * i, sizeof(value));
            target[i] = (double) value + (double) integer;
        }
    } else {
        for (size_t i = 0; i < count; i++) {
            int32_t integer;
            float value;
            memcpy(&integer, integer_raw + 4 * i, sizeof(integer));
            memcpy(&value, float_raw + 4 * i, sizeof(value));
            target[i] = (double) integer + (double) value;
        }
    }
    /* Every admitted lane is finite and observed, so this block contributes
       zero missing outputs. Summing inherited counts would be wrong when
       missing input positions overlap; exception blocks keep the exact union. */
}

static void arithmetic_long_float_add_exact(
    const unsigned char *x_raw, const unsigned char *y_raw,
    arithmetic_pair_policy x_policy, arithmetic_pair_policy y_policy,
    size_t start, size_t count, arithmetic_general_output *output
) {
    /* Instantiate the existing exact writer, including modern/legacy imports,
       missing union and the established binary64 expression. */
    if (x_policy.kind == NUMERIC_LONG) {
        switch (y_policy.kind) {
        case NUMERIC_FLOAT:
            ARITHMETIC_PAIR_LOOP(long, float, +, 0, double, NUMERIC_DOUBLE, NA_REAL); break;
        case ARITHMETIC_SOURCE_OBSERVED_FLOAT:
            ARITHMETIC_PAIR_LOOP(long, observed_float, +, 0, double, NUMERIC_DOUBLE, NA_REAL); break;
        case ARITHMETIC_PAIR_LEGACY_FLOAT:
            ARITHMETIC_PAIR_LOOP(long, legacy_float, +, 0, double, NUMERIC_DOUBLE, NA_REAL); break;
        }
    } else {
        switch (x_policy.kind) {
        case NUMERIC_FLOAT:
            ARITHMETIC_PAIR_LOOP(float, long, +, 0, double, NUMERIC_DOUBLE, NA_REAL); break;
        case ARITHMETIC_SOURCE_OBSERVED_FLOAT:
            ARITHMETIC_PAIR_LOOP(observed_float, long, +, 0, double, NUMERIC_DOUBLE, NA_REAL); break;
        case ARITHMETIC_PAIR_LEGACY_FLOAT:
            ARITHMETIC_PAIR_LOOP(legacy_float, long, +, 0, double, NUMERIC_DOUBLE, NA_REAL); break;
        }
    }
}

/* This loader is selected only from a captured strict-domain descriptor.
   Every stored value is finite; positive high values are exactly the 27 tags. */
#define LONG_FLOAT_CANONICAL_LOAD(NAME, MISSING)                            \
    static inline arithmetic_pair_value arithmetic_pair_load_##NAME(       \
        const unsigned char *raw, size_t index,                            \
        const arithmetic_pair_policy *policy                              \
    ) {                                                                    \
        (void) policy;                                                     \
        float value;                                                       \
        memcpy(&value, raw + index * sizeof(value), sizeof(value));         \
        return (arithmetic_pair_value) {                                  \
            (double) value, (unsigned) (MISSING), 0,                        \
            (unsigned) (value == 0), value                                 \
        };                                                                 \
    }
LONG_FLOAT_CANONICAL_LOAD(canonical_float, value >= 0x1p127f)
LONG_FLOAT_CANONICAL_LOAD(canonical_observed_float, 0)
#undef LONG_FLOAT_CANONICAL_LOAD

static void arithmetic_long_float_add_canonical(
    const unsigned char *x_raw, const unsigned char *y_raw,
    arithmetic_pair_policy x_policy, arithmetic_pair_policy y_policy,
    size_t start, size_t count, int observed, arithmetic_general_output *output
) {
    if (x_policy.kind == NUMERIC_LONG) {
        if (observed) {
            ARITHMETIC_PAIR_LOOP(long, canonical_observed_float, +, 0, double, NUMERIC_DOUBLE, NA_REAL);
        } else {
            ARITHMETIC_PAIR_LOOP(long, canonical_float, +, 0, double, NUMERIC_DOUBLE, NA_REAL);
        }
    } else {
        if (observed) {
            ARITHMETIC_PAIR_LOOP(canonical_observed_float, long, +, 0, double, NUMERIC_DOUBLE, NA_REAL);
        } else {
            ARITHMETIC_PAIR_LOOP(canonical_float, long, +, 0, double, NUMERIC_DOUBLE, NA_REAL);
        }
    }
}

static int arithmetic_long_float_add_write(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, arithmetic_general_output *output
) {
    /* Capture rooted both native descriptors and claimed mutable compact
       backing before output allocation. These exact counts stay valid even
       if a callback patches or materializes the public inputs. */
    if (left->operand->reader.storage->missing_count == (size_t) length ||
        right->operand->reader.storage->missing_count == (size_t) length) {
        arithmetic_general_fill_missing_double(length, output);
        return NUMERIC_DOUBLE;
    }
    const arithmetic_pair_policy x_policy = arithmetic_pair_policy_for(left);
    const arithmetic_pair_policy y_policy = arithmetic_pair_policy_for(right);
    const int reverse = x_policy.kind != NUMERIC_LONG;
    const numeric_data *float_data = reverse ? left->operand->reader.storage : right->operand->reader.storage;
    const int canonical = numeric_strict_modern_float(float_data);
    const int observed = float_data->missing_count == 0;
    const int32_t missing_minimum = reverse ? y_policy.missing_minimum : x_policy.missing_minimum;
    for (size_t start = 0; start < (size_t) length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) length - start;
        if (count > 16384) count = 16384;
        const unsigned char *x_raw = arithmetic_general_span(left, start, &count);
        const unsigned char *y_raw = arithmetic_general_span(right, start, &count);
        if (canonical) {
            arithmetic_long_float_add_canonical(x_raw, y_raw, x_policy, y_policy,
                start, count, observed, output);
        } else {
            unsigned failures = 0;
            for (size_t offset = 0; offset < count;) {
                size_t block = count - offset;
                if (block > 64) block = 64;
                const unsigned char *x = x_raw + 4 * offset;
                const unsigned char *y = y_raw + 4 * offset;
                const unsigned char *integer_raw = reverse ? y : x;
                const unsigned char *float_raw = reverse ? x : y;
                if (arithmetic_long_float_add_ordinary(integer_raw, float_raw, block, missing_minimum)) {
                    arithmetic_long_float_add_observed(integer_raw, float_raw,
                        start + offset, block, reverse, output);
                    failures = 0;
                } else {
                    arithmetic_long_float_add_exact(x, y, x_policy, y_policy,
                        start + offset, block, output);
                    failures++;
                }
                offset += block;
                if (failures == 4 && offset < count) {
                    arithmetic_long_float_add_exact(x_raw + 4 * offset, y_raw + 4 * offset,
                        x_policy, y_policy, start + offset, count - offset, output);
                    break;
                }
            }
        }
        /* The exact fallback is bounded by this captured span. A dense prefix
           cannot suppress proofs in the rest of a whole contiguous column. */
        start += count;
    }
    return NUMERIC_DOUBLE;
}
#endif
