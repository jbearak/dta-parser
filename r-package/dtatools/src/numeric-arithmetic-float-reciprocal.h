/* A finite scalar divided by a nonzero float has two monotone safe intervals.
   Prove both denominator signs with the original binary64 division. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_FLOAT_RECIPROCAL_H
#define DTATOOLS_NUMERIC_ARITHMETIC_FLOAT_RECIPROCAL_H

typedef struct {
    const arithmetic_general_source *column;
    double scalar;
    uint32_t minimum_magnitude;
    int all_missing;
    int whole_domain;
    size_t result_missing_count;
} arithmetic_float_reciprocal_proof;

static int arithmetic_float_reciprocal_safe(
    double scalar, uint32_t magnitude, int kind
) {
    float source;
    memcpy(&source, &magnitude, sizeof(source));
    double positive = scalar / (double) source;
    double negative = scalar / -(double) source;
    if (!scalar_arithmetic_result_valid(positive) ||
        !scalar_arithmetic_result_valid(negative)) return 0;
    return kind == NUMERIC_DOUBLE ||
        (fabs(positive) <= numeric_float_observed_limit() &&
         fabs(negative) <= numeric_float_observed_limit());
}

static int arithmetic_float_reciprocal_prove(
    const arithmetic_general_source *left, const arithmetic_general_source *right,
    R_xlen_t length, int operation, int kind, arithmetic_float_reciprocal_proof *proof
) {
    if (operation != '/' || left->kind != ARITHMETIC_SOURCE_SCALAR ||
        (kind != NUMERIC_FLOAT && kind != NUMERIC_DOUBLE) || length <= 1 ||
        !R_FINITE(left->scalar)) return 0;
    const numeric_data *data = right->operand->reader.storage;
    if (data == NULL || data->kind != NUMERIC_FLOAT || data->temporal != 0 ||
        right->operand->length != length || data->missing_count > (size_t) length)
        return 0;
    proof->column = right;
    proof->scalar = left->scalar;
    proof->minimum_magnitude = 0;
    proof->all_missing = data->missing_count == (size_t) length;
    proof->whole_domain = 0;
    proof->result_missing_count = 0;
    /* Only complete captured extents can use an exact zero count. Bounds may
       be conservative subset facts, but zeros and inherited missing rows
       must be disjoint exact counts for this result's complete length. */
    const int cached = numeric_float_bounds_known(data) &&
        numeric_zero_count_known(data) && data->length == (size_t) length &&
        data->zero_count <= (size_t) length - data->missing_count;
    if (cached) {
        proof->result_missing_count = data->missing_count + data->zero_count;
        if (proof->result_missing_count == (size_t) length) {
            proof->all_missing = 1;
            return 1;
        }
    }
    /* Captured exact input counts prove every result missing independently
       of its denominator encoding. No threshold or input read is needed. */
    if (proof->all_missing) return 1;
    /* Encodings below 0x7f000000 are finite and observed in both formats.
       Search this conservative domain only; exceptional spans stay exact.
       Both signs matter under directed rounding. */
    uint32_t low = 1, high = UINT32_C(0x7effffff);
    if (!arithmetic_float_reciprocal_safe(left->scalar, high, kind)) return 0;
    while (low < high) {
        uint32_t middle = low + (high - low) / 2;
        if (arithmetic_float_reciprocal_safe(left->scalar, middle, kind)) high = middle;
        else low = middle + 1;
    }
    proof->minimum_magnitude = low;
    /* The existing search proves both denominator signs using binary64
       division under the active rounding mode. Every nonzero observed lane
       lies above this captured lower bound; tags are larger than the safe
       search endpoint, and zero lanes will use that endpoint as an anchor. */
    proof->whole_domain = cached &&
        data->float_min_nonzero_magnitude_bound >= low;
    return 1;
}

static int arithmetic_float_reciprocal_ordinary_block(
    const unsigned char *raw, size_t start, size_t count, uint32_t threshold
) {
    uint32_t minimum = UINT32_MAX, maximum = 0;
    for (size_t i = start; i < start + count; i++) {
        uint32_t bits;
        memcpy(&bits, raw + i * sizeof(bits), sizeof(bits));
        bits &= UINT32_C(0x7fffffff);
        minimum = bits < minimum ? bits : minimum;
        maximum = bits > maximum ? bits : maximum;
    }
    /* Zero is deliberately retained in the minimum, including negative zero. */
    return minimum >= threshold && maximum < UINT32_C(0x7f000000);
}

/* Exact input policy allows a mixed block to reuse the same quotient bound.
   Invalid lanes use an anchor already proved for both signs and output kind. */
static int arithmetic_float_reciprocal_prepare_block(
    const unsigned char *raw, size_t start, size_t count,
    const arithmetic_general_source *column, uint32_t threshold,
    float *prepared, unsigned char *missing, unsigned *missing_count
) {
    uint32_t minimum = UINT32_MAX;
    unsigned invalid_count = 0;
    for (size_t offset = 0; offset < count; offset++) {
        uint32_t bits;
        memcpy(&bits, raw + (start + offset) * sizeof(bits), sizeof(bits));
        float source;
        memcpy(&source, &bits, sizeof(source));
        uint32_t magnitude = bits & UINT32_C(0x7fffffff);
        unsigned invalid = (unsigned) arithmetic_float_missing(source, &column->policy) |
            (unsigned) (magnitude == 0);
        missing[offset] = (unsigned char) invalid;
        invalid_count += invalid;
        bits = invalid ? UINT32_C(0x7effffff) : bits;
        prepared[offset] = invalid ? 0x1.fffffep126f : source;
        magnitude = bits & UINT32_C(0x7fffffff);
        minimum = magnitude < minimum ? magnitude : minimum;
    }
    *missing_count = invalid_count;
    return minimum >= threshold;
}

/* Four failing ordinary blocks select this writer only for captured strict
   modern bytes. Their domain proves finite observed inputs and exact missing
   tags, so one magnitude comparison replaces the imported-value classifier.
   Tags lie above the proved anchor and can keep their original denominator;
   only below-threshold lanes need substitution, including both zero signs.
   Keep the quotient in binary64, then narrow once. Too-small observed inputs
   use a safe anchor in this private provisional pass; the caller overwrites
   the entire attempted range with the exact producer before publishing it. */
#define RECIPROCAL_CANONICAL_WRITE(NAME, TYPE, TARGET, MISSING)              \
    static int arithmetic_float_reciprocal_canonical_##NAME(                \
        const unsigned char *raw, size_t offset, size_t count,             \
        size_t destination, double scalar, uint32_t threshold,             \
        arithmetic_general_output *output, unsigned *missing_count        \
    ) {                                                                    \
        TYPE *restrict target = (TARGET) + destination;                    \
        unsigned invalid_count = 0, too_small = 0;                         \
        for (size_t i = 0; i < count; i++) {                               \
            uint32_t bits;                                                 \
            memcpy(&bits, raw + (offset + i) * sizeof(bits), sizeof(bits)); \
            uint32_t magnitude = bits & UINT32_C(0x7fffffff);              \
            unsigned invalid = (unsigned) (magnitude >= UINT32_C(0x7f000000)) | \
                (unsigned) (magnitude == 0);                               \
            unsigned small = (unsigned) (magnitude < threshold);           \
            unsigned unsafe = small & (unsigned) (magnitude != 0);         \
            too_small |= unsafe;                                           \
            bits = small ? UINT32_C(0x7effffff) : bits;         \
            float denominator;                                             \
            memcpy(&denominator, &bits, sizeof(denominator));              \
            double quotient = scalar / (double) denominator;              \
            target[i] = invalid ? (TYPE) (MISSING) : (TYPE) quotient;       \
            invalid_count += invalid;                                     \
        }                                                                  \
        if (too_small) return 0;                                          \
        *missing_count = invalid_count;                                   \
        return 1;                                                          \
    }
RECIPROCAL_CANONICAL_WRITE(float, float, (float *) (void *) output->raw, 0x1p127f)
RECIPROCAL_CANONICAL_WRITE(double, double, output->real, NA_REAL)
#undef RECIPROCAL_CANONICAL_WRITE

/* The caller supplies fresh output with a zero missing count. */
static int arithmetic_float_reciprocal_fill_missing(
    R_xlen_t length, arithmetic_general_output *output
) {
    for (size_t start = 0; start < (size_t) length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) length - start;
        if (count > 16384) count = 16384;
        if (output->kind == NUMERIC_FLOAT) {
            float *target = (float *) (void *) output->raw + start;
            for (size_t i = 0; i < count; i++) target[i] = 0x1p127f;
        } else {
            double *target = output->real + start;
            for (size_t i = 0; i < count; i++) target[i] = NA_REAL;
        }
        output->missing_count += count;
        start += count;
    }
    return output->kind;
}

/* Immutable complete-column facts remove both range and count reductions.
   Missing-tag and zero presence are dispatched before the typed row loop.
   A missing tag itself is a safe finite denominator; only zero needs an
   anchor. Observed lanes retain their original binary64 division and single
   narrowing, including signed zeros produced by underflow or a zero scalar. */
static int arithmetic_float_reciprocal_whole_write(
    const arithmetic_float_reciprocal_proof *proof, R_xlen_t length,
    arithmetic_general_output *output
) {
    const numeric_data *data = proof->column->operand->reader.storage;
    const double scalar = proof->scalar;
    const int tagged = data->missing_count != 0;
    const int zeros = data->zero_count != 0;
    output->missing_count = proof->result_missing_count;
#define RECIPROCAL_WHOLE_LOOP(TYPE, TARGET, MISSING, TAGGED, ZEROS)         \
    do {                                                                  \
        for (size_t start = 0; start < (size_t) length;) {                 \
            R_CheckUserInterrupt();                                       \
            size_t count = (size_t) length - start;                       \
            if (count > 16384) count = 16384;                             \
            const unsigned char *raw = numeric_read_span(data, start, count, &count); \
            TYPE *restrict target = (TARGET) + start;                     \
            for (size_t i = 0; i < count; i++) {                          \
                uint32_t bits;                                            \
                memcpy(&bits, raw + i * sizeof(bits), sizeof(bits));      \
                uint32_t magnitude = bits & UINT32_C(0x7fffffff);         \
                unsigned zero = (ZEROS) && magnitude == 0;               \
                unsigned invalid = ((TAGGED) &&                          \
                    magnitude >= UINT32_C(0x7f000000)) | zero;           \
                bits = zero ? UINT32_C(0x7effffff) : bits;               \
                float denominator;                                        \
                memcpy(&denominator, &bits, sizeof(denominator));         \
                double quotient = scalar / (double) denominator;         \
                target[i] = invalid ? (TYPE) (MISSING) : (TYPE) quotient; \
            }                                                             \
            start += count;                                               \
        }                                                                 \
    } while (0)
#define RECIPROCAL_WHOLE_SHAPE(TYPE, TARGET, MISSING)                      \
    if (tagged) {                                                         \
        if (zeros) { RECIPROCAL_WHOLE_LOOP(TYPE, TARGET, MISSING, 1, 1); } \
        else { RECIPROCAL_WHOLE_LOOP(TYPE, TARGET, MISSING, 1, 0); }       \
    } else {                                                              \
        if (zeros) { RECIPROCAL_WHOLE_LOOP(TYPE, TARGET, MISSING, 0, 1); } \
        else { RECIPROCAL_WHOLE_LOOP(TYPE, TARGET, MISSING, 0, 0); }       \
    }
    if (output->kind == NUMERIC_FLOAT) {
        RECIPROCAL_WHOLE_SHAPE(float, (float *) (void *) output->raw, 0x1p127f);
    } else {
        RECIPROCAL_WHOLE_SHAPE(double, output->real, NA_REAL);
    }
#undef RECIPROCAL_WHOLE_SHAPE
#undef RECIPROCAL_WHOLE_LOOP
    return output->kind;
}

static int arithmetic_float_reciprocal_write(
    const arithmetic_float_reciprocal_proof *proof, R_xlen_t length,
    arithmetic_general_output *output
) {
    if (proof->all_missing)
        return arithmetic_float_reciprocal_fill_missing(length, output);
    if (proof->whole_domain)
        return arithmetic_float_reciprocal_whole_write(proof, length, output);
    const arithmetic_general_source *column = proof->column;
    const numeric_data *data = column->operand->reader.storage;
    const double scalar = proof->scalar;
    const uint32_t threshold = proof->minimum_magnitude;
    const int all_observed = data->missing_count == 0;
    const int canonical = numeric_strict_modern_float(data);
    const double float_limit = numeric_float_observed_limit();
    uint64_t float_limit_bits;
    memcpy(&float_limit_bits, &float_limit, sizeof(float_limit_bits));
    for (size_t start = 0; start < (size_t) length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) length - start;
        if (count > 16384) count = 16384;
        const unsigned char *raw = numeric_read_span(data, start, count, &count);
        uint64_t maximum_magnitude = 0;
        unsigned missing_count = 0;
#define RECIPROCAL_FLOAT_LOOP(TYPE, TARGET, LOAD, NARROW, MISSING, PREPARED)            \
        do {                                                               \
            TYPE *restrict target = (TARGET) + start;                      \
            unsigned failed_blocks = 0;                                   \
            unsigned ordinary_failures = 0;                               \
            for (size_t block = 0; block < count;) {                       \
                size_t take = count - block;                               \
                if (take > 64) take = 64;                                  \
                size_t end = block + take;                                 \
                int dense = PREPARED && canonical && ordinary_failures == 4; \
                if (dense) {                                               \
                    unsigned dense_missing = 0;                            \
                    end = count;                                           \
                    int proved_dense = output->kind == NUMERIC_FLOAT       \
                        ? arithmetic_float_reciprocal_canonical_float(raw, block, \
                            end - block, start + block, scalar, threshold, output, &dense_missing) \
                        : arithmetic_float_reciprocal_canonical_double(raw, block, \
                            end - block, start + block, scalar, threshold, output, &dense_missing); \
                    if (proved_dense) {                                    \
                        missing_count += dense_missing;                    \
                        block = end;                                       \
                        continue;                                          \
                    }                                                      \
                }                                                          \
                float prepared[64];                                       \
                unsigned char missing[64];                                \
                unsigned block_missing = 0;                               \
                /* Retry the ordinary proof at each captured span. */     \
                int ordinary = !dense && !(PREPARED && ordinary_failures == 4) &&   \
                    arithmetic_float_reciprocal_ordinary_block(            \
                        raw, block, take, threshold);                      \
                int prepared_block = PREPARED && !ordinary;               \
                int proved = ordinary;                                    \
                if (PREPARED && !dense) {                                 \
                    if (ordinary) ordinary_failures = 0;                  \
                    else {                                                \
                        if (ordinary_failures < 4) ordinary_failures++;    \
                        proved = arithmetic_float_reciprocal_prepare_block( \
                            raw, block, take, column, threshold,            \
                            prepared, missing, &block_missing);            \
                    }                                                     \
                }                                                         \
                if (proved) {                                             \
                    failed_blocks = 0;                                    \
                    if (!prepared_block) {                                  \
                        for (size_t i = block; i < end; i++) {              \
                            float source;                                   \
                            memcpy(&source, raw + i * sizeof(source), sizeof(source));\
                            target[i] = (TYPE) (scalar / (double) source);  \
                        }                                                   \
                    } else if (block_missing == take) {                     \
                        for (size_t i = block; i < end; i++)                \
                            target[i] = (TYPE) (MISSING);                   \
                    } else {                                                \
                        for (size_t i = block; i < end; i++) {              \
                            double quotient = scalar / (double) prepared[i - block];\
                            target[i] = missing[i - block]                  \
                                ? (TYPE) (MISSING) : (TYPE) quotient;       \
                        }                                                   \
                    }                                                       \
                    missing_count += block_missing;                       \
                    block = end;                                          \
                    continue;                                             \
                }                                                         \
                /* Retry after at most this bounded 16,384-row span. */    \
                if (++failed_blocks == 4) end = count;                     \
                for (size_t i = block; i < end; i++) {                     \
                    double source = LOAD(raw, i, column);                 \
                    double value = scalar / source;                       \
                    int valid = scalar_arithmetic_result_valid(value);    \
                    double observed = valid ? value : 0.0;                \
                    double storable = observed;                           \
                    missing_count += (unsigned) !valid;                   \
                    if (NARROW) {                                         \
                        uint64_t bits;                                    \
                        memcpy(&bits, &observed, sizeof(bits));            \
                        bits &= UINT64_C(0x7fffffffffffffff);              \
                        maximum_magnitude = bits > maximum_magnitude      \
                            ? bits : maximum_magnitude;                   \
                        storable = bits <= float_limit_bits ? observed : 0; \
                    }                                                     \
                    target[i] = valid ? (TYPE) storable : (TYPE) (MISSING); \
                }                                                         \
                block = end;                                              \
            }                                                              \
        } while (0)
#define RECIPROCAL_FLOAT_TARGETS(LOAD, PREPARED)                                      \
        if (output->kind == NUMERIC_FLOAT) {                                \
            RECIPROCAL_FLOAT_LOOP(float, (float *) (void *) output->raw,    \
                LOAD, 1, 0x1p127f, PREPARED);                                       \
        } else {                                                           \
            RECIPROCAL_FLOAT_LOOP(double, output->real, LOAD, 0, NA_REAL, PREPARED);  \
        }
        if (all_observed) {
            RECIPROCAL_FLOAT_TARGETS(arithmetic_general_load_observed_float, 0);
        } else {
            RECIPROCAL_FLOAT_TARGETS(arithmetic_general_load_float, 1);
        }
#undef RECIPROCAL_FLOAT_TARGETS
#undef RECIPROCAL_FLOAT_LOOP
        output->missing_count += missing_count;
        /* Only valid non-fitting results promote. Recompute the complete
           column from the same captured inputs through the existing caller. */
        if (output->kind == NUMERIC_FLOAT && maximum_magnitude > float_limit_bits)
            return NUMERIC_DOUBLE;
        start += count;
    }
    return output->kind;
}
#endif
