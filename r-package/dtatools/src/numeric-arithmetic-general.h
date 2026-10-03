/* General arithmetic keeps each input in its physical storage until the
   operation. Storage, missing layout, scalar shape, operator and destination
   are dispatched outside the typed loop. No decoded value/code arrays cross
   the producer boundary. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_GENERAL_H
#define DTATOOLS_NUMERIC_ARITHMETIC_GENERAL_H

enum {
    ARITHMETIC_SOURCE_R_INTEGER = 5,
    ARITHMETIC_SOURCE_OBSERVED_FLOAT = 6,
    ARITHMETIC_SOURCE_SCALAR = 7,
    ARITHMETIC_PREFLIGHT = 5
};

typedef struct {
    const arithmetic_operand *operand;
    arithmetic_missing_policy policy;
    int kind;
    double scalar;
} arithmetic_general_source;

typedef struct {
    int kind;
    unsigned char *raw;
    double *real;
    double minimum;
    double maximum;
    uint64_t magnitude;
    unsigned fractional;
    size_t missing_count;
} arithmetic_general_output;

static int arithmetic_general_source_create(
    const arithmetic_operand *operand, arithmetic_general_source *source
) {
    source->operand = operand;
    source->policy = arithmetic_missing_policy_for(operand->reader.storage);
    source->scalar = 0;
    if (operand->length == 1) {
        int code;
        numeric_reader_region(&operand->reader, 0, 1, &source->scalar, &code);
        if (code >= 0) source->scalar = NA_REAL;
        source->kind = ARITHMETIC_SOURCE_SCALAR;
    } else if (operand->reader.storage != NULL) {
        const numeric_data *data = operand->reader.storage;
        source->kind = data->kind;
        if (data->kind == NUMERIC_FLOAT && data->missing_count == 0)
            source->kind = ARITHMETIC_SOURCE_OBSERVED_FLOAT;
    } else if (operand->reader.real_values != NULL) {
        source->kind = NUMERIC_DOUBLE;
    } else if (operand->reader.integer_values != NULL) {
        source->kind = ARITHMETIC_SOURCE_R_INTEGER;
    } else {
        return 0;
    }
    return 1;
}

static const unsigned char *arithmetic_general_span(
    const arithmetic_general_source *source, size_t start, size_t *count
) {
    const numeric_reader *reader = &source->operand->reader;
    if (source->kind == ARITHMETIC_SOURCE_SCALAR) return NULL;
    if (reader->storage != NULL)
        return numeric_read_span(reader->storage, start, *count, count);
    if (reader->real_values != NULL)
        return (const unsigned char *) (reader->real_values + start);
    return (const unsigned char *) (reader->integer_values + start);
}

#define GENERAL_INTEGER_LOAD(NAME, TYPE)                                  \
    static inline double arithmetic_general_load_##NAME(                  \
        const unsigned char *raw, size_t index,                           \
        const arithmetic_general_source *source                           \
    ) {                                                                   \
        TYPE value;                                                       \
        memcpy(&value, raw + index * sizeof(value), sizeof(value));         \
        return (double) value >= source->policy.minimum                   \
            ? NA_REAL : (double) value;                                   \
    }
GENERAL_INTEGER_LOAD(byte, int8_t)
GENERAL_INTEGER_LOAD(int, int16_t)
GENERAL_INTEGER_LOAD(long, int32_t)
#undef GENERAL_INTEGER_LOAD

static inline double arithmetic_general_load_float(
    const unsigned char *raw, size_t index,
    const arithmetic_general_source *source
) {
    float value;
    memcpy(&value, raw + index * sizeof(value), sizeof(value));
    /* Arithmetic discards input missing tags. Set a quiet-NaN exponent in
       each missing 32-bit lane before widening; observed bits are unchanged.
       Bitwise normalization keeps this mask in the source storage width. */
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    uint32_t missing = 0U - (uint32_t) arithmetic_float_missing(value, &source->policy);
    bits |= missing & UINT32_C(0x7fc00000);
    memcpy(&value, &bits, sizeof(value));
    return (double) value;
}

static inline double arithmetic_general_load_observed_float(
    const unsigned char *raw, size_t index,
    const arithmetic_general_source *source
) {
    (void) source;
    float value;
    memcpy(&value, raw + index * sizeof(value), sizeof(value));
    return (double) value;
}

static inline double arithmetic_general_load_double(
    const unsigned char *raw, size_t index,
    const arithmetic_general_source *source
) {
    (void) source;
    double value;
    memcpy(&value, raw + index * sizeof(value), sizeof(value));
    return value;
}

static inline double arithmetic_general_load_r_integer(
    const unsigned char *raw, size_t index,
    const arithmetic_general_source *source
) {
    (void) source;
    int value;
    memcpy(&value, raw + index * sizeof(value), sizeof(value));
    return value == NA_INTEGER ? NA_REAL : (double) value;
}

static inline double arithmetic_general_load_scalar(
    const unsigned char *raw, size_t index,
    const arithmetic_general_source *source
) {
    (void) raw;
    (void) index;
    return source->scalar;
}

static int arithmetic_general_result_kind(
    const arithmetic_general_output *output, int minimum
) {
    if (!output->fractional) {
        if (minimum <= NUMERIC_BYTE && output->minimum >= -127 &&
            output->maximum <= 100) return NUMERIC_BYTE;
        if (minimum <= NUMERIC_INT && output->minimum >= -32767 &&
            output->maximum <= 32740) return NUMERIC_INT;
        if (minimum <= NUMERIC_LONG && output->minimum >= -2147483647.0 &&
            output->maximum <= 2147483620.0) return NUMERIC_LONG;
    }
    if (minimum != NUMERIC_LONG &&
        output->minimum >= -numeric_float_observed_limit() &&
        output->maximum <= numeric_float_observed_limit()) return NUMERIC_FLOAT;
    return NUMERIC_DOUBLE;
}

/* Floating output combines calculation, invalid-result normalization, missing
   count and range proof. Integer destinations have already been proved safe;
   select zero before conversion so missing values never invoke an invalid
   floating-to-integer conversion. Float values outside the proved storage range
   write a private zero placeholder, avoiding an out-of-range C conversion.
   A float promotion discards all provisional
   rounding and recalculates the complete result from the captured inputs. */
#define GENERAL_PAIR_LOOP(X, Y, OP, TYPE, MODE, MISSING)                    \
    do {                                                                  \
        TYPE *restrict target = (MODE) == ARITHMETIC_PREFLIGHT ? NULL :     \
            (TYPE *) (void *) ((MODE) == NUMERIC_DOUBLE                    \
                ? (unsigned char *) output->real : output->raw);          \
        double minimum_value = output->minimum;                           \
        double maximum_value = output->maximum;                           \
        uint64_t maximum_magnitude = output->magnitude;                   \
        unsigned fractional = output->fractional;                        \
        unsigned missing_count = 0;                                      \
        double float_limit = numeric_float_observed_limit();              \
        uint64_t float_limit_bits;                                        \
        memcpy(&float_limit_bits, &float_limit, sizeof(float_limit_bits)); \
        for (size_t i = 0; i < count; i++) {                              \
            double xv = arithmetic_general_load_##X(x_raw, i, left);     \
            double yv = arithmetic_general_load_##Y(y_raw, i, right);     \
            double value = xv OP yv;                                     \
            int valid = scalar_arithmetic_result_valid(value);           \
            double observed = valid ? value : 0.0;                       \
            if ((MODE) == ARITHMETIC_PREFLIGHT) {                         \
                minimum_value = observed < minimum_value                 \
                    ? observed : minimum_value;                          \
                maximum_value = observed > maximum_value                 \
                    ? observed : maximum_value;                          \
                fractional |= observed != trunc(observed);              \
            } else {                                                      \
                double storable = observed;                             \
                missing_count += (unsigned) !valid;                      \
                if ((MODE) == NUMERIC_FLOAT) {                           \
                    uint64_t bits;                                       \
                    memcpy(&bits, &observed, sizeof(bits));              \
                    bits &= UINT64_C(0x7fffffffffffffff);                 \
                    maximum_magnitude = bits > maximum_magnitude         \
                        ? bits : maximum_magnitude;                      \
                    storable = bits <= float_limit_bits ? observed : 0;  \
                }                                                         \
                target[start + i] = valid ? (TYPE) storable : (TYPE) (MISSING); \
            }                                                             \
        }                                                                 \
        output->minimum = minimum_value;                                 \
        output->maximum = maximum_value;                                 \
        output->magnitude = maximum_magnitude;                           \
        output->fractional = fractional;                                 \
        output->missing_count += missing_count;                          \
    } while (0)

#define GENERAL_PAIR_TARGETS(X, Y, OP)                                     \
    switch (output->kind) {                                                \
    case NUMERIC_BYTE: GENERAL_PAIR_LOOP(X, Y, OP, int8_t, NUMERIC_BYTE, 101); break; \
    case NUMERIC_INT: GENERAL_PAIR_LOOP(X, Y, OP, int16_t, NUMERIC_INT, 32741); break; \
    case NUMERIC_LONG: GENERAL_PAIR_LOOP(X, Y, OP, int32_t, NUMERIC_LONG, INT32_C(2147483621)); break; \
    case NUMERIC_FLOAT: GENERAL_PAIR_LOOP(X, Y, OP, float, NUMERIC_FLOAT, 0x1p127f); break; \
    case NUMERIC_DOUBLE: GENERAL_PAIR_LOOP(X, Y, OP, double, NUMERIC_DOUBLE, NA_REAL); break; \
    case ARITHMETIC_PREFLIGHT: GENERAL_PAIR_LOOP(X, Y, OP, double, ARITHMETIC_PREFLIGHT, 0); break; \
    }

#define GENERAL_PAIR_OPERATORS(X, Y)                                      \
    switch (operation) {                                                  \
    case '+': GENERAL_PAIR_TARGETS(X, Y, +); break;                       \
    case '-': GENERAL_PAIR_TARGETS(X, Y, -); break;                       \
    case '*': GENERAL_PAIR_TARGETS(X, Y, *); break;                       \
    case '/': GENERAL_PAIR_TARGETS(X, Y, /); break;                       \
    }

#define GENERAL_RIGHT(X)                                                  \
    switch (right->kind) {                                                \
    case NUMERIC_BYTE: GENERAL_PAIR_OPERATORS(X, byte); break;             \
    case NUMERIC_INT: GENERAL_PAIR_OPERATORS(X, int); break;               \
    case NUMERIC_LONG: GENERAL_PAIR_OPERATORS(X, long); break;             \
    case NUMERIC_FLOAT: GENERAL_PAIR_OPERATORS(X, float); break;           \
    case NUMERIC_DOUBLE: GENERAL_PAIR_OPERATORS(X, double); break;         \
    case ARITHMETIC_SOURCE_R_INTEGER: GENERAL_PAIR_OPERATORS(X, r_integer); break; \
    case ARITHMETIC_SOURCE_OBSERVED_FLOAT: GENERAL_PAIR_OPERATORS(X, observed_float); break; \
    case ARITHMETIC_SOURCE_SCALAR: GENERAL_PAIR_OPERATORS(X, scalar); break; \
    }

static int arithmetic_general_run(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, int operation, int minimum, arithmetic_general_output *output
) {
    for (size_t start = 0; start < (size_t) length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) length - start;
        if (count > 16384) count = 16384;
        const unsigned char *x_raw = arithmetic_general_span(left, start, &count);
        const unsigned char *y_raw = arithmetic_general_span(right, start, &count);
        switch (left->kind) {
        case NUMERIC_BYTE: GENERAL_RIGHT(byte); break;
        case NUMERIC_INT: GENERAL_RIGHT(int); break;
        case NUMERIC_LONG: GENERAL_RIGHT(long); break;
        case NUMERIC_FLOAT: GENERAL_RIGHT(float); break;
        case NUMERIC_DOUBLE: GENERAL_RIGHT(double); break;
        case ARITHMETIC_SOURCE_R_INTEGER: GENERAL_RIGHT(r_integer); break;
        case ARITHMETIC_SOURCE_OBSERVED_FLOAT: GENERAL_RIGHT(observed_float); break;
        case ARITHMETIC_SOURCE_SCALAR: GENERAL_RIGHT(scalar); break;
        }
        if (output->kind == ARITHMETIC_PREFLIGHT) {
            int kind = arithmetic_general_result_kind(output, minimum);
            /* Once float or double is necessary no integer output can win.
               The float writer will prove its complete range while writing. */
            if (kind >= NUMERIC_FLOAT) return kind;
        }
        start += count;
    }
    if (output->kind == ARITHMETIC_PREFLIGHT)
        return arithmetic_general_result_kind(output, minimum);
    if (output->kind == NUMERIC_FLOAT) {
        double maximum;
        uint64_t bits = output->magnitude;
        memcpy(&maximum, &bits, sizeof(maximum));
        if (maximum > numeric_float_observed_limit()) return NUMERIC_DOUBLE;
    }
    return output->kind;
}
#undef GENERAL_RIGHT
#undef GENERAL_PAIR_OPERATORS
#undef GENERAL_PAIR_TARGETS
#undef GENERAL_PAIR_LOOP

static SEXP arithmetic_general_result(
    const arithmetic_operand *left, const arithmetic_operand *right,
    R_xlen_t length, int operation, int minimum, int *result_kind
) {
    arithmetic_general_source x, y;
    if (!arithmetic_general_source_create(left, &x) ||
        !arithmetic_general_source_create(right, &y)) return NULL;
    int kind = minimum;
    if (minimum < NUMERIC_FLOAT) {
        arithmetic_general_output preflight = {
            .kind = ARITHMETIC_PREFLIGHT, .minimum = 0, .maximum = 0
        };
        kind = arithmetic_general_run(&x, &y, length, operation, minimum, &preflight);
    }
    PROTECT_INDEX backing_index;
    SEXP backing;
    PROTECT_WITH_INDEX(backing = arithmetic_backing(length, kind), &backing_index);
    arithmetic_general_output output = {
        .kind = kind,
        .raw = kind == NUMERIC_DOUBLE ? NULL : RAW(backing),
        .real = kind == NUMERIC_DOUBLE ? REAL(backing) : NULL
    };
    int promoted = arithmetic_general_run(&x, &y, length, operation, minimum, &output);
    if (promoted != kind) {
        kind = promoted;
        REPROTECT(backing = arithmetic_backing(length, kind), backing_index);
        output = (arithmetic_general_output) {.kind = kind, .real = REAL(backing)};
        arithmetic_general_run(&x, &y, length, operation, minimum, &output);
    }
    SEXP result = PROTECT(arithmetic_adopt_backing(backing, length, kind, output.missing_count));
    *result_kind = kind;
    UNPROTECT(2);
    return result;
}
#endif
