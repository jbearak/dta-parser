/* Integer-domain arithmetic after the ordinary admission and owner capture.
   Preflight chooses the complete result's storage before allocating it. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_INTEGER_H
#define DTATOOLS_NUMERIC_ARITHMETIC_INTEGER_H

typedef struct {
    int source_kind;
    int operation;
    int wide;
    int x_scalar;
    int y_scalar;
    int32_t x_value;
    int32_t y_value;
    double x_double;
    double y_double;
    int32_t x_missing;
    int32_t y_missing;
    int64_t minimum;
    int64_t maximum;
    size_t missing_count;
} arithmetic_integer_plan;

static int32_t arithmetic_integer_missing(const numeric_data *data) {
    if (data == NULL) return 0;
    int legacy = data->format_version <= 111;
    switch (data->kind) {
    case NUMERIC_BYTE: return legacy ? INT8_MAX : 101;
    case NUMERIC_INT: return legacy ? INT16_MAX : 32741;
    default: return legacy ? INT32_MAX : INT32_C(2147483621);
    }
}

static int arithmetic_integer_prepare(
    const arithmetic_operand *left, const arithmetic_operand *right,
    int operation, arithmetic_integer_plan *plan
) {
    if (operation != '+' && operation != '-' && operation != '*') return 0;
    const numeric_data *x = left->reader.storage;
    const numeric_data *y = right->reader.storage;
    int x_scalar = left->length == 1, y_scalar = right->length == 1;
    if ((x_scalar && y_scalar) ||
        (!x_scalar && (x == NULL || x->kind > NUMERIC_LONG)) ||
        (!y_scalar && (y == NULL || y->kind > NUMERIC_LONG))) return 0;
    int kind = !x_scalar ? x->kind : y->kind;
    if (kind < NUMERIC_BYTE || kind > NUMERIC_LONG ||
        (!x_scalar && x->kind != kind) || (!y_scalar && y->kind != kind))
        return 0;
    if ((x_scalar || y_scalar) && operation != '*') return 0;

    *plan = (arithmetic_integer_plan) {0};
    plan->source_kind = kind;
    plan->operation = operation;
    plan->x_scalar = x_scalar;
    plan->y_scalar = y_scalar;
    plan->x_missing = arithmetic_integer_missing(x);
    plan->y_missing = arithmetic_integer_missing(y);
    plan->wide = kind == NUMERIC_LONG;
    if (x_scalar || y_scalar) {
        double value;
        int code;
        numeric_reader_region(x_scalar ? &left->reader : &right->reader,
                              0, 1, &value, &code);
        if (code >= 0 || !R_FINITE(value) || value != trunc(value) ||
            value < (double) INT32_MIN || value > (double) INT32_MAX)
            return 0;
        int32_t scalar = (int32_t) value;
        if (x_scalar) {
            plan->x_value = scalar;
            plan->x_double = value;
        } else {
            plan->y_value = scalar;
            plan->y_double = value;
        }
        /* Use the entire signed source domain, including legacy observed
           minima and missing encodings, to prove every multiply safe. */
        int64_t magnitude = scalar < 0 ? -(int64_t) scalar : scalar;
        int64_t bound = kind == NUMERIC_BYTE ? INT32_MAX / 128
                                             : INT32_MAX / 32768;
        if (magnitude > bound) plan->wide = 1;
    }
    if (!x_scalar && !y_scalar && operation == '+' &&
        arithmetic_same_compact_storage(left, right, left->length)) {
        /* Equal captured spans prove equal values even if allocation
           callbacks changed either public object. Integer x + x is exactly
           x * 2, including the later binary64 rounding on promotion. */
        plan->y_scalar = 1;
        plan->y_value = 2;
        plan->y_double = 2;
        plan->operation = '*';
    }
    if (plan->x_scalar || plan->y_scalar) {
        /* The scalar is observed and every admitted result is valid. Only
           the captured column's existing missing rows can be missing. */
        plan->missing_count = (plan->x_scalar ? y : x)->missing_count;
    }
    /* Byte/int pairs fit int32 for all three operators. Long pairs and a
       bounded int32 scalar fit int64: the largest product is 2^62. */
    return 1;
}

/* An all-bits unsigned mask lets pair scans combine predicates without
   packing booleans into byte lanes. Subtracting it adds one to the bounded
   unsigned block count for each missing row. */
#define ARITHMETIC_INTEGER_LOAD(SOURCE, ACC, XS, YS)                        \
    ACC xv = (ACC) plan->x_value, yv = (ACC) plan->y_value;                 \
    uint32_t missing = 0;                                                  \
    if (!(XS)) {                                                           \
        SOURCE raw;                                                        \
        memcpy(&raw, x_raw + offset * sizeof(SOURCE), sizeof(raw));        \
        xv = (ACC) raw;                                                    \
        missing |= 0U - (uint32_t) (raw >= plan->x_missing);               \
    }                                                                      \
    if (!(YS)) {                                                           \
        SOURCE raw;                                                        \
        memcpy(&raw, y_raw + offset * sizeof(SOURCE), sizeof(raw));        \
        yv = (ACC) raw;                                                    \
        missing |= 0U - (uint32_t) (raw >= plan->y_missing);               \
    }

#define ARITHMETIC_INTEGER_SHAPES(LOOP, SOURCE, ACC, OP)                    \
    if (plan->x_scalar) { LOOP(SOURCE, ACC, OP, 1, 0) }                    \
    else if (plan->y_scalar) { LOOP(SOURCE, ACC, OP, 0, 1) }               \
    else { LOOP(SOURCE, ACC, OP, 0, 0) }

#define ARITHMETIC_INTEGER_OPERATORS(LOOP, SOURCE, ACC)                    \
    switch (operation) {                                                   \
    case '+': ARITHMETIC_INTEGER_SHAPES(LOOP, SOURCE, ACC, +); break;      \
    case '-': ARITHMETIC_INTEGER_SHAPES(LOOP, SOURCE, ACC, -); break;      \
    case '*': ARITHMETIC_INTEGER_SHAPES(LOOP, SOURCE, ACC, *); break;      \
    }

#define ARITHMETIC_INTEGER_SOURCES(LOOP)                                   \
    switch (plan->source_kind) {                                           \
    case NUMERIC_BYTE:                                                     \
        if (plan->wide) { ARITHMETIC_INTEGER_OPERATORS(LOOP, int8_t, int64_t) } \
        else { ARITHMETIC_INTEGER_OPERATORS(LOOP, int8_t, int32_t) }        \
        break;                                                             \
    case NUMERIC_INT:                                                      \
        if (plan->wide) { ARITHMETIC_INTEGER_OPERATORS(LOOP, int16_t, int64_t) } \
        else { ARITHMETIC_INTEGER_OPERATORS(LOOP, int16_t, int32_t) }       \
        break;                                                             \
    case NUMERIC_LONG:                                                     \
        ARITHMETIC_INTEGER_OPERATORS(LOOP, int32_t, int64_t)                \
        break;                                                             \
    }

static void arithmetic_integer_preflight(
    const arithmetic_operand *left, const arithmetic_operand *right,
    R_xlen_t length, int operation, int minimum_kind,
    arithmetic_integer_plan *plan
) {
    for (R_xlen_t start = 0; start < length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) (length - start > 16384 ? 16384 : length - start);
        const unsigned char *x_raw = plan->x_scalar ? NULL :
            numeric_read_span(left->reader.storage, (size_t) start, count, &count);
        const unsigned char *y_raw = plan->y_scalar ? NULL :
            numeric_read_span(right->reader.storage, (size_t) start, count, &count);
#define ARITHMETIC_INTEGER_PREFLIGHT(SOURCE, ACC, OP, XS, YS)               \
        {                                                                  \
            ACC minimum = (ACC) plan->minimum;                             \
            ACC maximum = (ACC) plan->maximum;                             \
            unsigned missing_count = 0;                                    \
            for (size_t offset = 0; offset < count; offset++) {            \
                ARITHMETIC_INTEGER_LOAD(SOURCE, ACC, XS, YS)               \
                ACC value = xv OP yv;                                      \
                value = missing ? 0 : value;                               \
                minimum = value < minimum ? value : minimum;              \
                maximum = value > maximum ? value : maximum;              \
                if (!(XS) && !(YS)) missing_count -= missing;             \
            }                                                              \
            plan->minimum = minimum;                                      \
            plan->maximum = maximum;                                      \
            plan->missing_count += missing_count;                          \
        }
        ARITHMETIC_INTEGER_SOURCES(ARITHMETIC_INTEGER_PREFLIGHT)
#undef ARITHMETIC_INTEGER_PREFLIGHT
        /* Long can promote only to double, which holds every admitted
           result. Floating output obtains its full missing count separately,
           so no remaining preflight reduction is needed after promotion. */
        if (minimum_kind == NUMERIC_LONG &&
            (plan->minimum < -INT64_C(2147483647) ||
             plan->maximum > INT64_C(2147483620))) return;
        start += (R_xlen_t) count;
    }
}

static int arithmetic_integer_destination(
    const arithmetic_integer_plan *plan, int minimum
) {
    if (minimum == NUMERIC_BYTE && plan->minimum >= -127 &&
        plan->maximum <= 100) return NUMERIC_BYTE;
    if (minimum <= NUMERIC_INT && plan->minimum >= -32767 &&
        plan->maximum <= 32740) return NUMERIC_INT;
    if (minimum <= NUMERIC_LONG && plan->minimum >= -INT64_C(2147483647) &&
        plan->maximum <= INT64_C(2147483620)) return NUMERIC_LONG;
    /* Every admitted result is an integer of magnitude at most 2^62, well
       within float's observed range. Long never narrows through float. */
    return minimum == NUMERIC_LONG || minimum == NUMERIC_DOUBLE
        ? NUMERIC_DOUBLE : NUMERIC_FLOAT;
}

static void arithmetic_integer_write(
    const arithmetic_operand *left, const arithmetic_operand *right,
    R_xlen_t length, int operation, const arithmetic_integer_plan *plan,
    arithmetic_output *output
) {
    for (R_xlen_t start = 0; start < length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) (length - start > 16384 ? 16384 : length - start);
        const unsigned char *x_raw = plan->x_scalar ? NULL :
            numeric_read_span(left->reader.storage, (size_t) start, count, &count);
        const unsigned char *y_raw = plan->y_scalar ? NULL :
            numeric_read_span(right->reader.storage, (size_t) start, count, &count);
#define ARITHMETIC_INTEGER_WRITE_AS(SOURCE, ACC, OP, XS, YS, TYPE, NA)      \
        {                                                                  \
            TYPE *restrict target = (TYPE *) (void *) output->raw + start; \
            for (size_t offset = 0; offset < count; offset++) {            \
                ARITHMETIC_INTEGER_LOAD(SOURCE, ACC, XS, YS)               \
                ACC value = xv OP yv;                                      \
                target[offset] = (TYPE) (missing ? (ACC) (NA) : value);    \
            }                                                              \
        }
#define ARITHMETIC_INTEGER_WRITE(SOURCE, ACC, OP, XS, YS)                  \
        switch (output->kind) {                                            \
        case NUMERIC_BYTE:                                                 \
            ARITHMETIC_INTEGER_WRITE_AS(SOURCE, ACC, OP, XS, YS, int8_t, 101) \
            break;                                                         \
        case NUMERIC_INT:                                                  \
            ARITHMETIC_INTEGER_WRITE_AS(SOURCE, ACC, OP, XS, YS, int16_t, 32741) \
            break;                                                         \
        case NUMERIC_LONG:                                                 \
            ARITHMETIC_INTEGER_WRITE_AS(SOURCE, ACC, OP, XS, YS, int32_t, INT32_C(2147483621)) \
            break;                                                         \
        }
        ARITHMETIC_INTEGER_SOURCES(ARITHMETIC_INTEGER_WRITE)
#undef ARITHMETIC_INTEGER_WRITE
#undef ARITHMETIC_INTEGER_WRITE_AS
        start += (R_xlen_t) count;
    }
}

/* Integer-domain bounds also prove the binary64 result finite and inside
   float's observed range. Keep the original double operation for its rounding
   and signed zero, without repeating generic validity or destination checks. */
static void arithmetic_integer_write_floating(
    const arithmetic_operand *left, const arithmetic_operand *right,
    R_xlen_t length, int operation, const arithmetic_integer_plan *plan,
    arithmetic_output *output
) {
    size_t total_missing = plan->x_scalar || plan->y_scalar
        ? plan->missing_count : 0;
    void *destination = output->kind == NUMERIC_DOUBLE
        ? (void *) output->real : (void *) output->raw;
    for (R_xlen_t start = 0; start < length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) (length - start > 16384 ? 16384 : length - start);
        const unsigned char *x_raw = plan->x_scalar ? NULL :
            numeric_read_span(left->reader.storage, (size_t) start, count, &count);
        const unsigned char *y_raw = plan->y_scalar ? NULL :
            numeric_read_span(right->reader.storage, (size_t) start, count, &count);
#define ARITHMETIC_INTEGER_FLOAT_AS(SOURCE, ACC, OP, XS, YS, TYPE, NA)      \
        {                                                                  \
            TYPE *restrict target = (TYPE *) destination + start;         \
            unsigned missing_count = 0;                                    \
            for (size_t offset = 0; offset < count; offset++) {            \
                ARITHMETIC_INTEGER_LOAD(SOURCE, ACC, XS, YS)               \
                double dx = (XS) ? plan->x_double : (double) xv;           \
                double dy = (YS) ? plan->y_double : (double) yv;           \
                double value = dx OP dy;                                  \
                target[offset] = missing ? (TYPE) (NA) : (TYPE) value;     \
                if (!(XS) && !(YS)) missing_count -= missing;             \
            }                                                              \
            total_missing += missing_count;                               \
        }
#define ARITHMETIC_INTEGER_FLOAT(SOURCE, ACC, OP, XS, YS)                  \
        if (output->kind == NUMERIC_FLOAT) {                               \
            ARITHMETIC_INTEGER_FLOAT_AS(SOURCE, ACC, OP, XS, YS, float, 0x1p127f) \
        } else {                                                           \
            ARITHMETIC_INTEGER_FLOAT_AS(SOURCE, ACC, OP, XS, YS, double, NA_REAL) \
        }
        switch (plan->source_kind) {
        case NUMERIC_BYTE:
            ARITHMETIC_INTEGER_OPERATORS(ARITHMETIC_INTEGER_FLOAT, int8_t, int64_t)
            break;
        case NUMERIC_INT:
            ARITHMETIC_INTEGER_OPERATORS(ARITHMETIC_INTEGER_FLOAT, int16_t, int64_t)
            break;
        case NUMERIC_LONG:
            ARITHMETIC_INTEGER_OPERATORS(ARITHMETIC_INTEGER_FLOAT, int32_t, int64_t)
            break;
        }
#undef ARITHMETIC_INTEGER_FLOAT
#undef ARITHMETIC_INTEGER_FLOAT_AS
        start += (R_xlen_t) count;
    }
    output->missing_count = total_missing;
}

#undef ARITHMETIC_INTEGER_SOURCES
#undef ARITHMETIC_INTEGER_OPERATORS
#undef ARITHMETIC_INTEGER_SHAPES
#undef ARITHMETIC_INTEGER_LOAD

static SEXP arithmetic_integer_result(
    const arithmetic_operand *left, const arithmetic_operand *right,
    R_xlen_t length, int operation, int minimum, int *result_kind
) {
    arithmetic_integer_plan plan;
    if (!arithmetic_integer_prepare(left, right, operation, &plan))
        return NULL;
    operation = plan.operation;
    int kind = minimum;
    if (minimum < NUMERIC_FLOAT) {
        arithmetic_integer_preflight(left, right, length, operation,
                                     minimum, &plan);
        kind = arithmetic_integer_destination(&plan, minimum);
    }
    SEXP backing = PROTECT(arithmetic_backing(length, kind));
    arithmetic_output output = arithmetic_output_create(backing, kind);
    if (kind <= NUMERIC_LONG) {
        arithmetic_integer_write(left, right, length, operation, &plan, &output);
        output.missing_count = plan.missing_count;
    } else {
        arithmetic_integer_write_floating(left, right, length, operation,
                                           &plan, &output);
    }
    SEXP result = PROTECT(arithmetic_adopt_backing(
        backing, length, kind, output.missing_count
    ));
    *result_kind = kind;
    UNPROTECT(2);
    return result;
}

#endif
