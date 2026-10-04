/* Binary scaling preserves a float's significand until its final binary32
   rounding. Integer division by a power of two needs only a divisibility
   reduction to choose storage; float fit checks share the output scan. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_SCALE_H
#define DTATOOLS_NUMERIC_ARITHMETIC_SCALE_H

static int arithmetic_scale_fractional(const numeric_data *data,
                                       R_xlen_t length, unsigned shift) {
    uint32_t remainder = 0;
    const uint32_t mask = (UINT32_C(1) << shift) - 1U;
    const int32_t missing_minimum = (int32_t)
        arithmetic_missing_policy_for(data).minimum;
    for (R_xlen_t start = 0; start < length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) (length - start > 16384 ? 16384 : length - start);
        const unsigned char *raw = numeric_read_span(data, (size_t) start, count, &count);
#define SCALE_REMAINDER(TYPE)                                              \
        for (size_t i = 0; i < count; i++) {                               \
            TYPE value;                                                   \
            memcpy(&value, raw + i * sizeof(TYPE), sizeof(TYPE));          \
            remainder |= value >= missing_minimum ? 0U : (uint32_t) value; \
        }
        switch (data->kind) {
        case NUMERIC_BYTE: SCALE_REMAINDER(int8_t); break;
        case NUMERIC_INT: SCALE_REMAINDER(int16_t); break;
        case NUMERIC_LONG: SCALE_REMAINDER(int32_t); break;
        }
#undef SCALE_REMAINDER
        /* Contraction proves the range. One fractional result settles the
           only remaining storage constraint for the entire column. */
        if (remainder & mask) return 1;
        start += (R_xlen_t) count;
    }
    return 0;
}

static int arithmetic_scale_float_invalid_modern(uint32_t bits) {
    /* Rotating the offset admits exactly 0x7f000000 + tag * 0x800 for
       tag 0..26. Unaligned bits rotate above that range, and unsigned
       subtraction also excludes every encoding below the first code. */
    uint32_t offset = bits - UINT32_C(0x7f000000);
    uint32_t tag = (offset >> 11) | (offset << 21);
    return (tag <= 26U) |
        ((bits & UINT32_C(0x7fffffff)) >= UINT32_C(0x7f800000));
}

static int arithmetic_scale_float_invalid_legacy(uint32_t bits) {
    return (bits - UINT32_C(0x7f000000) <= UINT32_C(0x00ffffff)) |
        ((bits & UINT32_C(0x7fffffff)) >= UINT32_C(0x7f800000));
}

/* shift is at least one, so the unsigned magnitude after shifting fits in
   int32 even for the legacy-observed INT32_MIN. No negative signed shift or
   negation of INT32_MIN is used. */
static int32_t arithmetic_scale_quotient(int32_t value, unsigned shift,
                                        int negative) {
    const uint32_t sign = 0U - (uint32_t) (value < 0);
    uint32_t magnitude = (((uint32_t) value ^ sign) - sign) >> shift;
    int32_t result = (int32_t) magnitude;
    return ((value < 0) != negative) ? -result : result;
}

static void arithmetic_scale_integer_write(const numeric_data *data,
                                            R_xlen_t length, unsigned shift,
                                            double factor,
                                            arithmetic_output *output) {
    /* Here 2^-30 <= |factor| <= 1/2. Nonzero integer quotients therefore
       remain normal binary32 values. Rounding the integer to float before
       this exact exponent shift gives the same final float as binary64
       scaling followed by conversion, with the zero sign preserved. */
    const int32_t missing_minimum = (int32_t)
        arithmetic_missing_policy_for(data).minimum;
    const int negative = factor < 0;
    unsigned char *destination = output->kind == NUMERIC_DOUBLE
        ? (unsigned char *) output->real : output->raw;
    for (R_xlen_t start = 0; start < length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) (length - start > 16384 ? 16384 : length - start);
        const unsigned char *raw = numeric_read_span(data, (size_t) start, count, &count);
#define SCALE_INTEGER_WRITE(SOURCE, TYPE, VALUE, MISSING)                  \
        {                                                                 \
            TYPE *restrict target = (TYPE *) (void *) destination + start; \
            for (size_t i = 0; i < count; i++) {                           \
                SOURCE source;                                            \
                memcpy(&source, raw + i * sizeof(SOURCE), sizeof(SOURCE)); \
                int missing = source >= missing_minimum;                  \
                TYPE value = (TYPE) (VALUE);                               \
                target[i] = missing ? (TYPE) (MISSING) : value;            \
            }                                                             \
        }
#define SCALE_INTEGER_TARGETS(SOURCE)                                      \
        switch (output->kind) {                                            \
        case NUMERIC_BYTE:                                                \
            SCALE_INTEGER_WRITE(SOURCE, int8_t,                            \
                arithmetic_scale_quotient(source, shift, negative), 101); break; \
        case NUMERIC_INT:                                                 \
            SCALE_INTEGER_WRITE(SOURCE, int16_t,                           \
                arithmetic_scale_quotient(source, shift, negative), 32741); break; \
        case NUMERIC_LONG:                                                \
            SCALE_INTEGER_WRITE(SOURCE, int32_t,                           \
                arithmetic_scale_quotient(source, shift, negative), INT32_C(2147483621)); break; \
        case NUMERIC_FLOAT:                                               \
            SCALE_INTEGER_WRITE(SOURCE, float,                            \
                (float) source * (float) factor, 0x1p127f); break;         \
        case NUMERIC_DOUBLE:                                              \
            SCALE_INTEGER_WRITE(SOURCE, double,                           \
                (double) source * factor, NA_REAL); break;                \
        }
        switch (data->kind) {
        case NUMERIC_BYTE: SCALE_INTEGER_TARGETS(int8_t); break;
        case NUMERIC_INT: SCALE_INTEGER_TARGETS(int16_t); break;
        case NUMERIC_LONG: SCALE_INTEGER_TARGETS(int32_t); break;
        }
#undef SCALE_INTEGER_TARGETS
#undef SCALE_INTEGER_WRITE
        start += (R_xlen_t) count;
    }
}

/* A binary shift gives an exact binary32 input cutoff. Fit detection can
   therefore share the narrow producer without converting each value to
   double. Stop at the first chunk proving double is required; no further
   storage decisions remain, and that writer recomputes every original value. */
static int arithmetic_scale_float_write(const numeric_data *data,
                                         R_xlen_t length, double factor,
                                         arithmetic_output *output) {
    const int legacy = data->format_version <= 111;
    /* Cached missing counts include every reserved code and IEEE NaN.
       Binary scaling invalidates only the remaining observed infinities.
       Legacy +Inf is reserved already; legacy -Inf and modern +/-Inf are not. */
    output->missing_count = data->missing_count;
    double input_limit = numeric_float_observed_limit() / fabs(factor);
    float limit = input_limit >= FLT_MAX ? FLT_MAX : (float) input_limit;
    uint32_t cutoff;
    memcpy(&cutoff, &limit, sizeof(cutoff));
    for (R_xlen_t start = 0; start < length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) (length - start > 16384 ? 16384 : length - start);
        const unsigned char *raw = numeric_read_span(data, (size_t) start, count, &count);
        uint32_t maximum = 0;
        unsigned missing_count = 0;
#define SCALE_FLOAT_WRITE(TYPE, TARGET, FACTOR, MISSING, CHECK_FIT, INVALID, INF_MASK, INF_VALUE) \
        {                                                                 \
            TYPE *restrict target = (TARGET) + start;                     \
            const TYPE multiplier = (TYPE) (FACTOR);                       \
            for (size_t i = 0; i < count; i++) {                           \
                uint32_t bits;                                            \
                memcpy(&bits, raw + i * sizeof(bits), sizeof(bits));        \
                int missing = INVALID(bits);                             \
                uint32_t observed = missing ? 0 : bits;                    \
                uint32_t magnitude = observed & UINT32_C(0x7fffffff);     \
                if (CHECK_FIT)                                            \
                    maximum = magnitude > maximum ? magnitude : maximum; \
                float source;                                             \
                memcpy(&source, &observed, sizeof(source));                \
                TYPE value = (TYPE) source * multiplier;                   \
                target[i] = missing ? (TYPE) (MISSING) : value;            \
                missing_count +=                                          \
                    (unsigned) ((bits & (INF_MASK)) == (INF_VALUE));       \
            }                                                             \
        }
#define SCALE_FLOAT_TARGETS(INVALID, INF_MASK, INF_VALUE)                  \
        if (output->kind == NUMERIC_FLOAT) {                               \
            if (fabs(factor) <= 0.5) {                                    \
                SCALE_FLOAT_WRITE(float, (float *) (void *) output->raw, factor, 0x1p127f, 0, INVALID, INF_MASK, INF_VALUE); \
            } else {                                                      \
                SCALE_FLOAT_WRITE(float, (float *) (void *) output->raw, factor, 0x1p127f, 1, INVALID, INF_MASK, INF_VALUE); \
            }                                                             \
        } else {                                                          \
            SCALE_FLOAT_WRITE(double, output->real, factor, NA_REAL, 0, INVALID, INF_MASK, INF_VALUE); \
        }
        /* Half of the largest finite binary32 value is exactly the largest
           observed Stata float. Contraction needs no fit scan. Encoding
           dispatch stays outside the typed loop, including infinity counts. */
        if (legacy) {
            SCALE_FLOAT_TARGETS(arithmetic_scale_float_invalid_legacy,
                                UINT32_MAX, UINT32_C(0xff800000));
        } else {
            SCALE_FLOAT_TARGETS(arithmetic_scale_float_invalid_modern,
                                UINT32_C(0x7fffffff), UINT32_C(0x7f800000));
        }
#undef SCALE_FLOAT_TARGETS
#undef SCALE_FLOAT_WRITE
        output->missing_count += missing_count;
        /* A too-large provisional product can be infinity. It is never
           exposed or counted as missing: this backing is discarded and the
           double writer starts again from the original captured values. */
        if (maximum > cutoff) return 1;
        start += (R_xlen_t) count;
    }
    return 0;
}

/* Public object identity is insufficient: either capture may allocate. Compare
   the already captured byte spans instead, including both encoding policies. */
static int arithmetic_same_compact_storage(const arithmetic_operand *left,
                                           const arithmetic_operand *right,
                                           R_xlen_t length) {
    const numeric_data *x = left->reader.storage, *y = right->reader.storage;
    if (x == NULL || y == NULL || x->kind != y->kind ||
        x->kind < NUMERIC_BYTE || x->kind > NUMERIC_FLOAT ||
        x->format_version != y->format_version ||
        left->length != length || right->length != length) return 0;
    for (R_xlen_t start = 0; start < length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) (length - start > 16384 ? 16384 : length - start);
        const unsigned char *xp = numeric_read_span(x, (size_t) start, count, &count);
        const unsigned char *yp = numeric_read_span(y, (size_t) start, count, &count);
        if (xp != yp) return 0;
        start += (R_xlen_t) count;
    }
    return 1;
}

static SEXP arithmetic_scale_result(const arithmetic_operand *left,
                                     const arithmetic_operand *right,
                                     R_xlen_t length, int operation,
                                     int minimum, int *result_kind) {
    if (length <= 1) return NULL;
    const arithmetic_operand *column = NULL, *scalar = NULL;
    int exponent = 1;
    double factor = 2;
    if (operation == '+') {
        if (left->reader.storage == NULL ||
            left->reader.storage->kind != NUMERIC_FLOAT ||
            !arithmetic_same_compact_storage(left, right, length)) return NULL;
        column = left;
    } else {
        if (operation != '*' && operation != '/') return NULL;
        if (right->length == 1) {
            column = left;
            scalar = right;
        } else if (left->length == 1 && operation == '*') {
            column = right;
            scalar = left;
        } else return NULL;
        double value;
        int code;
        numeric_reader_region(&scalar->reader, 0, 1, &value, &code);
        if (code >= 0 || !R_FINITE(value) || value == 0 ||
            frexp(fabs(value), &exponent) != 0.5) return NULL;
        exponent--;
        if (exponent < -30 || exponent > 30) return NULL;
        factor = ldexp(value < 0 ? -1.0 : 1.0,
                       operation == '*' ? exponent : -exponent);
    }
    const numeric_data *data = column->reader.storage;
    if (data == NULL || data->kind > NUMERIC_FLOAT) return NULL;
    if (data->kind <= NUMERIC_LONG &&
        (operation != '/' || exponent < 1)) return NULL;
    int kind = minimum;
    size_t missing_count = data->missing_count;
    if (data->kind < NUMERIC_FLOAT && kind < NUMERIC_FLOAT &&
               arithmetic_scale_fractional(data, length, (unsigned) exponent)) {
        kind = kind == NUMERIC_LONG ? NUMERIC_DOUBLE : NUMERIC_FLOAT;
    }
    PROTECT_INDEX backing_index;
    SEXP backing;
    PROTECT_WITH_INDEX(backing = arithmetic_backing(length, kind), &backing_index);
    arithmetic_output output = arithmetic_output_create(backing, kind);
    if (data->kind == NUMERIC_FLOAT) {
        if (arithmetic_scale_float_write(data, length, factor, &output)) {
            kind = NUMERIC_DOUBLE;
            REPROTECT(backing = arithmetic_backing(length, kind), backing_index);
            output = arithmetic_output_create(backing, kind);
            arithmetic_scale_float_write(data, length, factor, &output);
        }
        missing_count = output.missing_count;
    } else {
        arithmetic_scale_integer_write(data, length, (unsigned) exponent, factor, &output);
    }
    SEXP result = PROTECT(arithmetic_adopt_backing(backing, length, kind, missing_count));
    *result_kind = kind;
    UNPROTECT(2);
    return result;
}
#endif
