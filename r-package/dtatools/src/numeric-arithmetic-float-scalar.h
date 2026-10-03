/* A scalar operation is monotone over finite binary32 inputs. Prove its
   binary64 range once, then express float fit in the input's storage width. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_FLOAT_SCALAR_H
#define DTATOOLS_NUMERIC_ARITHMETIC_FLOAT_SCALAR_H

typedef struct {
    const arithmetic_general_source *column;
    double scalar;
    int operation;
    int reverse;
    int increasing;
    int check_fit;
    float lower;
    float upper;
    uint32_t anchor;
} arithmetic_float_scalar_proof;

static double arithmetic_float_scalar_evaluate(
    const arithmetic_float_scalar_proof *proof, float source
) {
    double value = (double) source;
    switch (proof->operation) {
    case '+': return value + proof->scalar;
    case '-': return proof->reverse ? proof->scalar - value : value - proof->scalar;
    case '*': return value * proof->scalar;
    case '/': return value / proof->scalar;
    }
    return NA_REAL;
}

/* These keys place every finite encoding in numeric order, retaining both
   zero encodings. No NaN or infinity lies between the two finite endpoints. */
static float arithmetic_float_scalar_from_key(uint32_t key) {
    uint32_t bits = key & UINT32_C(0x80000000)
        ? key ^ UINT32_C(0x80000000) : ~key;
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static uint32_t arithmetic_float_scalar_bound(
    const arithmetic_float_scalar_proof *proof, int upper
) {
    uint32_t low = UINT32_C(0x00800000), high = UINT32_C(0xff800000);
    const double limit = numeric_float_observed_limit();
    while (low < high) {
        uint32_t middle = low + (high - low) / 2;
        double value = arithmetic_float_scalar_evaluate(
            proof, arithmetic_float_scalar_from_key(middle));
        int before = proof->increasing
            ? (upper ? value <= limit : value < -limit)
            : (upper ? value >= -limit : value > limit);
        if (before) low = middle + 1;
        else high = middle;
    }
    return low;
}

static int arithmetic_float_scalar_prove(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, int operation, int kind, arithmetic_float_scalar_proof *proof
) {
    if ((kind != NUMERIC_FLOAT && kind != NUMERIC_DOUBLE) || length <= 1) return 0;
    if (right->kind == ARITHMETIC_SOURCE_SCALAR) {
        proof->column = left;
        proof->scalar = right->scalar;
        proof->reverse = 0;
    } else if (left->kind == ARITHMETIC_SOURCE_SCALAR && operation != '/') {
        proof->column = right;
        proof->scalar = left->scalar;
        proof->reverse = 1;
    } else return 0;
    const numeric_data *data = proof->column->operand->reader.storage;
    if (data == NULL || data->temporal != 0 || data->kind != NUMERIC_FLOAT ||
        proof->column->operand->length != length || data->missing_count > (size_t) length ||
        !R_FINITE(proof->scalar) || (operation == '/' && proof->scalar == 0)) return 0;
    proof->operation = operation;
    double low = arithmetic_float_scalar_evaluate(proof, -FLT_MAX);
    double high = arithmetic_float_scalar_evaluate(proof, FLT_MAX);
    if (!scalar_arithmetic_result_valid(low) ||
        !scalar_arithmetic_result_valid(high)) return 0;
    proof->check_fit = 0;
    proof->anchor = 0;
    if (kind == NUMERIC_DOUBLE) return 1;
    proof->lower = -FLT_MAX;
    proof->upper = FLT_MAX;
    if (fabs(low) <= numeric_float_observed_limit() &&
        fabs(high) <= numeric_float_observed_limit()) return 1;
    proof->increasing = low <= high;
    uint32_t first = arithmetic_float_scalar_bound(proof, 0);
    uint32_t after = arithmetic_float_scalar_bound(proof, 1);
    /* Empty intervals use the general producer: an all-invalid result may
       still fit float, so absence of finite fit alone cannot promote it. */
    if (first >= after) return 0;
    proof->lower = arithmetic_float_scalar_from_key(first);
    proof->upper = arithmetic_float_scalar_from_key(after - 1);
    float anchor = proof->lower <= 0 && proof->upper >= 0 ? 0 : proof->lower;
    memcpy(&proof->anchor, &anchor, sizeof(anchor));
    proof->check_fit = 1;
    return 1;
}

/* This local proof excludes encoded missings, all IEEE non-finite values
   and conservative high-magnitude imports. Widen the actual maximum and
   existing binary32 fit endpoints exactly; do not round a new cutoff. */
static int arithmetic_float_scalar_ordinary_block(
    const unsigned char *raw, size_t start, size_t count,
    const arithmetic_float_scalar_proof *proof, int check_fit
) {
    uint32_t maximum = 0;
    for (size_t i = start; i < start + count; i++) {
        uint32_t bits;
        memcpy(&bits, raw + i * sizeof(bits), sizeof(bits));
        bits &= UINT32_C(0x7fffffff);
        maximum = bits > maximum ? bits : maximum;
    }
    if (maximum >= UINT32_C(0x7f000000)) return 0;
    if (check_fit) {
        float magnitude;
        memcpy(&magnitude, &maximum, sizeof(magnitude));
        return -(double) magnitude >= (double) proof->lower &&
            (double) magnitude <= (double) proof->upper;
    }
    return 1;
}

static int arithmetic_float_scalar_write(
    const arithmetic_float_scalar_proof *proof, R_xlen_t length,
    arithmetic_general_output *output
) {
    const numeric_data *data = proof->column->operand->reader.storage;
    const int legacy = data->format_version <= 111;
    const int all_observed = data->missing_count == 0;
    const double scalar = proof->scalar;
    /* The proof is immutable during this write. Snapshot its lane constants
       so stores through target cannot look like updates to the proof itself.
       Double destinations do not initialize or use the float-fit bounds. */
    const float lower = proof->check_fit ? proof->lower : 0.0f;
    const float upper = proof->check_fit ? proof->upper : 0.0f;
    const uint32_t anchor = proof->anchor;
    /* arithmetic_capture protects this exact descriptor and its backing.
       Finite inputs were proved valid; only observed IEEE infinities add
       missing results. Legacy +Inf is included in the inherited count. */
    output->missing_count = data->missing_count;
    for (size_t start = 0; start < (size_t) length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) length - start;
        if (count > 16384) count = 16384;
        const unsigned char *raw = numeric_read_span(data, start, count, &count);
        unsigned promote = 0, missing_count = 0;
#define GENERAL_PROVED_FLOAT_LOOP(TYPE, TARGET, EXPR, MISSING, FIT, NARROW, INVALID, OBSERVED, INF_MASK, INF_VALUE) \
        do {                                                               \
            TYPE *restrict target = (TARGET) + start;                      \
            unsigned failed_blocks = 0;                                   \
            for (size_t block = 0; block < count;) {                       \
                size_t take = count - block;                               \
                if (take > 64) take = 64;                                  \
                size_t end = block + take;                                 \
                if (arithmetic_float_scalar_ordinary_block(                \
                        raw, block, take, proof, FIT)) {                  \
                    failed_blocks = 0;                                    \
                    for (size_t i = block; i < end; i++) {                 \
                        float source;                                     \
                        memcpy(&source, raw + i * sizeof(source), sizeof(source)); \
                        double value = (double) source;                    \
                        target[i] = (TYPE) (EXPR);                         \
                    }                                                     \
                    block = end;                                          \
                    continue;                                             \
                }                                                         \
                /* Each captured span is at most 16,384 rows. Bound failed \
                   proofs within it, then retry in the next span. */       \
                if (++failed_blocks == 4) end = count;                     \
                for (size_t i = block; i < end; i++) {                     \
                uint32_t bits;                                             \
                memcpy(&bits, raw + i * sizeof(bits), sizeof(bits));        \
                const uint32_t bits_original = bits;                       \
                int invalid = (OBSERVED)                                   \
                    ? (bits & UINT32_C(0x7fffffff)) >= UINT32_C(0x7f800000) \
                    : INVALID(bits);                                       \
                float source;                                              \
                memcpy(&source, &bits, sizeof(source));                    \
                int fit = !(FIT) ||                                        \
                    (source >= lower && source <= upper);                  \
                promote |= (unsigned) (!invalid && !fit);                 \
                if (NARROW) {                                              \
                    /* Substitute finite, proved-safe input before the     \
                       double operation and narrowing conversion. */      \
                    uint32_t replace = 0U - (uint32_t) (invalid || !fit);  \
                    bits = (bits & ~replace) | (anchor & replace);         \
                    memcpy(&source, &bits, sizeof(source));                \
                }                                                          \
                double value = (double) source;                            \
                TYPE result = (TYPE) (EXPR);                               \
                target[i] = invalid ? (TYPE) (MISSING) : result;           \
                missing_count += (unsigned)                              \
                    ((bits_original & (INF_MASK)) == (INF_VALUE));        \
                }                                                         \
                block = end;                                              \
            }                                                              \
        } while (0)
#define GENERAL_PROVED_FLOAT_TARGETS(EXPR, INVALID, OBSERVED, INF_MASK, INF_VALUE) \
        if (output->kind == NUMERIC_FLOAT) {                                \
            if (proof->check_fit) {                                        \
                GENERAL_PROVED_FLOAT_LOOP(float, (float *) (void *) output->raw, EXPR, 0x1p127f, 1, 1, INVALID, OBSERVED, INF_MASK, INF_VALUE); \
            } else {                                                       \
                GENERAL_PROVED_FLOAT_LOOP(float, (float *) (void *) output->raw, EXPR, 0x1p127f, 0, 1, INVALID, OBSERVED, INF_MASK, INF_VALUE); \
            }                                                              \
        } else {                                                           \
            GENERAL_PROVED_FLOAT_LOOP(double, output->real, EXPR, NA_REAL, 0, 0, INVALID, OBSERVED, INF_MASK, INF_VALUE); \
        }
#define GENERAL_PROVED_FLOAT_OPERATORS(INVALID, OBSERVED, INF_MASK, INF_VALUE) \
        switch (proof->operation) {                                         \
        case '+': GENERAL_PROVED_FLOAT_TARGETS(value + scalar, INVALID, OBSERVED, INF_MASK, INF_VALUE); break; \
        case '-':                                                          \
            if (proof->reverse) {                                           \
                GENERAL_PROVED_FLOAT_TARGETS(scalar - value, INVALID, OBSERVED, INF_MASK, INF_VALUE); \
            } else {                                                       \
                GENERAL_PROVED_FLOAT_TARGETS(value - scalar, INVALID, OBSERVED, INF_MASK, INF_VALUE); \
            }                                                              \
            break;                                                         \
        case '*': GENERAL_PROVED_FLOAT_TARGETS(value * scalar, INVALID, OBSERVED, INF_MASK, INF_VALUE); break; \
        case '/': GENERAL_PROVED_FLOAT_TARGETS(value / scalar, INVALID, OBSERVED, INF_MASK, INF_VALUE); break; \
        }
#define GENERAL_PROVED_FLOAT_MISSING(INVALID, INF_MASK, INF_VALUE)          \
        if (all_observed) {                                                 \
            GENERAL_PROVED_FLOAT_OPERATORS(INVALID, 1, INF_MASK, INF_VALUE); \
        } else {                                                           \
            GENERAL_PROVED_FLOAT_OPERATORS(INVALID, 0, INF_MASK, INF_VALUE); \
        }
        if (legacy) {
            GENERAL_PROVED_FLOAT_MISSING(arithmetic_scale_float_invalid_legacy,
                UINT32_MAX, UINT32_C(0xff800000));
        } else {
            GENERAL_PROVED_FLOAT_MISSING(arithmetic_scale_float_invalid_modern,
                UINT32_C(0x7fffffff), UINT32_C(0x7f800000));
        }
#undef GENERAL_PROVED_FLOAT_MISSING
#undef GENERAL_PROVED_FLOAT_OPERATORS
#undef GENERAL_PROVED_FLOAT_TARGETS
#undef GENERAL_PROVED_FLOAT_LOOP
        output->missing_count += missing_count;
        if (promote) return NUMERIC_DOUBLE;
        start += count;
    }
    return output->kind;
}
#endif
