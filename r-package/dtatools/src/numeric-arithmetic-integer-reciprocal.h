/* Every nonzero physical signed integer has magnitude at least one and is
   exactly representable as binary64. Hence |scalar / value| <= |scalar|.
   A representable scalar inside the destination's observed limit also bounds
   the rounded quotient. Keep storage preflight and binary64 division; this
   proof removes only per-result validity and destination-fit reductions.
   Nonzero missing encodings obey the same bound. Only zero needs a benign
   denominator; the store selects inherited missing results separately. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_INTEGER_RECIPROCAL_H
#define DTATOOLS_NUMERIC_ARITHMETIC_INTEGER_RECIPROCAL_H

static int arithmetic_integer_reciprocal_proved(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, int operation, int kind
) {
    if (operation != '/' || length <= 1 ||
        (kind != NUMERIC_FLOAT && kind != NUMERIC_DOUBLE) ||
        left->kind != ARITHMETIC_SOURCE_SCALAR ||
        right->operand->length != length) return 0;
    const numeric_data *data = right->operand->reader.storage;
    if (data == NULL || data->temporal != 0 ||
        data->kind < NUMERIC_BYTE || data->kind > NUMERIC_LONG ||
        data->missing_count > (size_t) length ||
        !scalar_arithmetic_result_valid(left->scalar)) return 0;
    return kind == NUMERIC_DOUBLE ||
        fabs(left->scalar) <= numeric_float_observed_limit();
}

static void arithmetic_integer_reciprocal_write(
    const arithmetic_general_source *column, double scalar,
    R_xlen_t length, arithmetic_general_output *output
) {
    const numeric_data *data = column->operand->reader.storage;
    const int32_t missing_minimum = (int32_t) column->policy.minimum;
    const int all_observed = data->missing_count == 0;
    const int known_zeros = numeric_zero_count_known(data) &&
        data->length == (size_t) length &&
        data->zero_count <= (size_t) length - data->missing_count;
    /* The existing arithmetic_capture claim protects these bytes and their
       cached missing count through allocation, interrupts and publication.
       Zero is observed in every admitted integer layout: all modern and
       legacy reserved codes are positive. Zero denominators are therefore
       disjoint from inherited missing codes, without another classification. */
    output->missing_count = data->missing_count +
        (known_zeros ? data->zero_count : 0);
    for (size_t start = 0; start < (size_t) length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) length - start;
        if (count > 16384) count = 16384;
        const unsigned char *raw = numeric_read_span(data, start, count, &count);
        unsigned zero_count = 0;
#define INTEGER_RECIPROCAL_LOOP(SOURCE, TARGET, DEST, MISSING, OBSERVED, KNOWN, ZERO_FREE) \
        do {                                                               \
            TARGET *restrict target = (DEST) + start;                      \
            const SOURCE missing_limit = (SOURCE) missing_minimum;         \
            for (size_t i = 0; i < count; i++) {                            \
                SOURCE source;                                             \
                memcpy(&source, raw + i * sizeof(source), sizeof(source));  \
                unsigned observed = (OBSERVED) || source < missing_limit;   \
                unsigned zero = !(ZERO_FREE) && source == 0;              \
                unsigned invalid = (!observed) | zero;                    \
                SOURCE denominator = zero ? (SOURCE) 1 : source;          \
                TARGET result = (TARGET) (scalar / (double) denominator); \
                target[i] = invalid ? (TARGET) (MISSING) : result;        \
                if (!(KNOWN)) zero_count += zero;                         \
            }                                                              \
        } while (0)
#define INTEGER_RECIPROCAL_TARGET(SOURCE, OBSERVED, KNOWN, ZERO_FREE)         \
        if (output->kind == NUMERIC_FLOAT) {                                \
            INTEGER_RECIPROCAL_LOOP(SOURCE, float,                          \
                (float *) (void *) output->raw, 0x1p127f, OBSERVED, KNOWN, ZERO_FREE); \
        } else {                                                           \
            INTEGER_RECIPROCAL_LOOP(SOURCE, double,                         \
                output->real, NA_REAL, OBSERVED, KNOWN, ZERO_FREE);         \
        }
#define INTEGER_RECIPROCAL_WIDTHS(OBSERVED, KNOWN, ZERO_FREE)                \
        switch (data->kind) {                                               \
        case NUMERIC_BYTE: INTEGER_RECIPROCAL_TARGET(int8_t, OBSERVED, KNOWN, ZERO_FREE); break; \
        case NUMERIC_INT: INTEGER_RECIPROCAL_TARGET(int16_t, OBSERVED, KNOWN, ZERO_FREE); break; \
        case NUMERIC_LONG: INTEGER_RECIPROCAL_TARGET(int32_t, OBSERVED, KNOWN, ZERO_FREE); break; \
        }
#define INTEGER_RECIPROCAL_SHAPE(KNOWN, ZERO_FREE)                         \
        if (all_observed) { INTEGER_RECIPROCAL_WIDTHS(1, KNOWN, ZERO_FREE); } \
        else { INTEGER_RECIPROCAL_WIDTHS(0, KNOWN, ZERO_FREE); }
        if (known_zeros) {
            if (data->zero_count == 0) { INTEGER_RECIPROCAL_SHAPE(1, 1); }
            else { INTEGER_RECIPROCAL_SHAPE(1, 0); }
        } else { INTEGER_RECIPROCAL_SHAPE(0, 0); }
#undef INTEGER_RECIPROCAL_SHAPE
#undef INTEGER_RECIPROCAL_WIDTHS
#undef INTEGER_RECIPROCAL_TARGET
#undef INTEGER_RECIPROCAL_LOOP
        if (!known_zeros) output->missing_count += zero_count;
        start += count;
    }
}
#endif
