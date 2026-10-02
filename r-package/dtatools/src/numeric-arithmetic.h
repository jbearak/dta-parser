/* Included after the existing scalar producers. The public admission route
   shares their dependency proof, decoration and result-commit contract. */
#ifndef DTATOOLS_NUMERIC_ARITHMETIC_H
#define DTATOOLS_NUMERIC_ARITHMETIC_H

static int combine_chain_absent(SEXP env, SEXP symbol);
static int combine_frame_absent(SEXP env, SEXP symbol);

static int arithmetic_storage_names_unchanged(SEXP frame, SEXP dependencies) {
    SEXP vctrs = VECTOR_ELT(dependencies, 8);
    SEXP table = computed_peek(Rf_install(".__S3MethodsTable__."), R_BaseNamespace, 16);
    if (TYPEOF(table) != ENVSXP) return 0;
    static const char *methods[] = {
        "names.dta_byte", "names.dta_int", "names.dta_long", "names.dta_float",
        "names<-.dta_byte", "names<-.dta_int", "names<-.dta_long", "names<-.dta_float"
    };
    for (size_t i = 0; i < sizeof(methods) / sizeof(methods[0]); i++) {
        SEXP symbol = Rf_install(methods[i]);
        if (!combine_chain_absent(frame, symbol) ||
            !combine_chain_absent(vctrs, symbol) ||
            !combine_frame_absent(table, symbol)) return 0;
    }
    return 1;
}

static int arithmetic_passive_attribute(SEXP name, SEXP value) {
    const char *label = CHAR(PRINTNAME(name));
    if (strcmp(label, "format.stata") != 0 && strcmp(label, "label") != 0)
        return 0;
    return TYPEOF(value) == STRSXP && !ALTREP(value) && !ANY_ATTRIB(value) &&
        XLENGTH(value) == 1 && STRING_ELT(value, 0) != NA_STRING;
}

static SEXP arithmetic_compact_attribute(SEXP name, SEXP value, void *context) {
    if (arithmetic_passive_attribute(name, value)) return NULL;
    return scalar_compact_attribute(name, value, context);
}

static SEXP arithmetic_double_attribute(SEXP name, SEXP value, void *context) {
    if (arithmetic_passive_attribute(name, value)) return NULL;
    return scalar_double_attribute(name, value, context);
}

static int arithmetic_operand_kind(SEXP value, int *kind) {
    if (TYPEOF(value) == REALSXP && !Rf_isS4(value)) {
        numeric_data *data = unmaterialized_numeric_read_storage(value);
        if (data != NULL && data->temporal == 0 &&
            data->kind >= NUMERIC_BYTE && data->kind <= NUMERIC_FLOAT) {
            scalar_compact_attribute_state state = {data->kind, 0};
            if (R_mapAttrib(value, arithmetic_compact_attribute, &state) == NULL &&
                state.seen == 3U) {
                *kind = data->kind;
                return 1;
            }
        }
        if (!ALTREP(value) || owned_real(value)) {
            unsigned seen = 0;
            if (R_mapAttrib(value, arithmetic_double_attribute, &seen) == NULL &&
                seen == 3U) {
                *kind = NUMERIC_DOUBLE;
                return 1;
            }
        }
    }
    if (ANY_ATTRIB(value) || Rf_isObject(value) || Rf_isS4(value) ||
        (ALTREP(value) && !owned_real(value)) ||
        (TYPEOF(value) != REALSXP && TYPEOF(value) != INTSXP &&
         TYPEOF(value) != LGLSXP)) return 0;
    *kind = -1;
    return 1;
}

static int arithmetic_promoted_kind(int left, int right) {
    if (left < 0) return right;
    if (right < 0) return left;
    if ((left == NUMERIC_LONG && right == NUMERIC_FLOAT) ||
        (right == NUMERIC_LONG && left == NUMERIC_FLOAT)) return NUMERIC_DOUBLE;
    return left > right ? left : right;
}

static int arithmetic_operator_unchanged(SEXP frame, int operation) {
    if (operation == '+' || operation == '-') return 1;
    SEXP dependencies = computed_peek(
        Rf_install(".numeric_binary_dependencies"), frame, 16
    );
    if (TYPEOF(dependencies) != VECSXP || ALTREP(dependencies) ||
        ANY_ATTRIB(dependencies) || XLENGTH(dependencies) != 2) return 0;
    SEXP expected = VECTOR_ELT(dependencies, operation == '*' ? 0 : 1);
    if (TYPEOF(expected) != BUILTINSXP) return 0;
    SEXP actual = computed_dependency_value(
        Rf_install(operation == '*' ? "*" : "/"), R_BaseEnv, 16
    );
    return actual == expected;
}

typedef struct {
    numeric_reader reader;
    numeric_data storage;
    R_xlen_t length;
} arithmetic_operand;

/* The caller protects each returned owner until both scan and encode finish.
   A descriptor captured here survives a finalizer materializing its public
   input during a subsequent output allocation. */
static SEXP arithmetic_capture(SEXP value, arithmetic_operand *operand,
                                SEXP claims, int slot) {
    operand->length = XLENGTH(value);
    SEXP root = PROTECT(numeric_missing_mask_capture(value, &operand->storage));
    if (root != R_NilValue) {
        if (!numeric_payload_retained(&operand->storage)) {
            SEXP external = R_altrep_data1(numeric_base_source(value));
            SEXP previous = R_ExternalPtrTag(external);
            if (previous != claims) {
                /* No allocation separates the plain snapshot from this
                   claim. A reentrant patch must detach before changing the
                   bytes on which promotion preflight will depend. */
                SET_VECTOR_ELT(claims, slot, external);
                SET_VECTOR_ELT(claims, slot + 1, previous);
                compact_payload_claim(external, claims);
            }
        }
        operand->reader = (numeric_reader) {
            value, &operand->storage, NULL, NULL, REALSXP
        };
    } else {
        UNPROTECT(1);
        root = PROTECT(numeric_payload_root(value));
        operand->reader = numeric_reader_create(value, operand->length);
    }
    UNPROTECT(1);
    return root;
}

typedef struct {
    int kind;
    int trusted;
    unsigned fits;
    size_t missing_count;
    unsigned char *raw;
    double *real;
} arithmetic_output;

/* Values that fit the minimum also fit every permitted wider destination.
   Only a value outside that minimum contributes new promotion constraints. */
static unsigned arithmetic_wider_fit(double value, int minimum) {
    unsigned fits = 1U << NUMERIC_DOUBLE;
    if (minimum < NUMERIC_FLOAT && minimum != NUMERIC_LONG &&
        fabs(value) <= numeric_float_observed_limit())
        fits |= 1U << NUMERIC_FLOAT;
    if (minimum < NUMERIC_LONG && value == trunc(value)) {
        if (minimum == NUMERIC_BYTE && value >= -32767 && value <= 32740)
            fits |= 1U << NUMERIC_INT;
        if (value >= -2147483647.0 && value <= 2147483620.0)
            fits |= 1U << NUMERIC_LONG;
    }
    return fits;
}

/* Target type and operator are chosen outside the element loop. The promoted
   second pass writes already-proved values without repeating fit checks. */
#define ARITHMETIC_STORE_RESULT(TYPE, FIT, MISSING, TRUSTED)                \
    TYPE encoded;                                                         \
    if (missing || !scalar_arithmetic_result_valid(value)) {                \
        encoded = (TYPE) (MISSING);                                        \
        missing_count++;                                                  \
    } else if ((TRUSTED) || (FIT)) {                                       \
        encoded = (TYPE) value;                                            \
    } else {                                                              \
        fits &= arithmetic_wider_fit(value, result_kind);                 \
        encoded = 0;                                                      \
    }                                                                     \
    target[index] = encoded;

#define ARITHMETIC_TARGETS(LOOP, SOURCE, OP)                                \
    switch (output->kind) {                                                \
    case NUMERIC_BYTE:                                                     \
        LOOP(SOURCE, OP, int8_t, value >= -127 && value <= 100 &&           \
             (integral || value == trunc(value)), 101); break;            \
    case NUMERIC_INT:                                                      \
        LOOP(SOURCE, OP, int16_t, value >= -32767 && value <= 32740 &&      \
             (integral || value == trunc(value)), 32741); break;          \
    case NUMERIC_LONG:                                                     \
        LOOP(SOURCE, OP, int32_t, value >= -2147483647.0 &&                  \
             value <= 2147483620.0 && (integral || value == trunc(value)), \
             INT32_C(2147483621)); break;                                 \
    case NUMERIC_FLOAT:                                                    \
        LOOP(SOURCE, OP, float, fabs(value) <= float_limit, 0x1p127f); break; \
    case NUMERIC_DOUBLE:                                                   \
        LOOP(SOURCE, OP, double, 1, NA_REAL); break;                       \
    }

#define ARITHMETIC_OPERATORS(LOOP, SOURCE)                                  \
    switch (operation) {                                                   \
    case '+': ARITHMETIC_TARGETS(LOOP, SOURCE, +); break;                  \
    case '-': ARITHMETIC_TARGETS(LOOP, SOURCE, -); break;                  \
    case '*': ARITHMETIC_TARGETS(LOOP, SOURCE, *); break;                  \
    case '/': ARITHMETIC_TARGETS(LOOP, SOURCE, /); break;                  \
    }

/* Ordinary doubles avoid decode buffers and all storage-fit work. */
static void arithmetic_double_run(
    const arithmetic_operand *left, const arithmetic_operand *right,
    R_xlen_t length, int operation, arithmetic_output *output
) {
    const double *x = left->reader.real_values;
    const double *y = right->reader.real_values;
    int x_scalar = left->length == 1, y_scalar = right->length == 1;
    /* Only the fresh output is restricted: the inputs may be the same vector. */
    double *restrict target = output->real;
    const double missing_value = NA_REAL;
    size_t missing_count = output->missing_count;
#define ARITHMETIC_DOUBLE_SHAPE(OP, X_INDEX, Y_INDEX)                      \
    for (R_xlen_t start = 0; start < length;) {                            \
        R_CheckUserInterrupt();                                           \
        R_xlen_t end = length - start > 16384 ? start + 16384 : length;    \
        for (R_xlen_t index = start; index < end; index++) {               \
            double value = x[X_INDEX] OP y[Y_INDEX];                       \
            int valid = scalar_arithmetic_result_valid(value);            \
            target[index] = valid ? value : missing_value;                \
            missing_count += !valid;                                      \
        }                                                                 \
        start = end;                                                      \
    }
#define ARITHMETIC_DOUBLE_LOOP(OP)                                        \
    if (x_scalar) {                                                       \
        if (y_scalar) { ARITHMETIC_DOUBLE_SHAPE(OP, 0, 0) }               \
        else { ARITHMETIC_DOUBLE_SHAPE(OP, 0, index) }                    \
    } else if (y_scalar) { ARITHMETIC_DOUBLE_SHAPE(OP, index, 0) }         \
    else { ARITHMETIC_DOUBLE_SHAPE(OP, index, index) }
    switch (operation) {
    case '+': ARITHMETIC_DOUBLE_LOOP(+); break;
    case '-': ARITHMETIC_DOUBLE_LOOP(-); break;
    case '*': ARITHMETIC_DOUBLE_LOOP(*); break;
    case '/': ARITHMETIC_DOUBLE_LOOP(/); break;
    }
    output->missing_count = missing_count;
#undef ARITHMETIC_DOUBLE_LOOP
#undef ARITHMETIC_DOUBLE_SHAPE
}

/* Known observed compact operands need neither decoded scratch vectors nor
   missing-code arrays. Retained pairs split at either owner's chunk edge. */
static int arithmetic_compact_run(
    const arithmetic_operand *left, const arithmetic_operand *right,
    R_xlen_t length, int operation, arithmetic_output *output
) {
    const numeric_data *x_data = left->reader.storage;
    const numeric_data *y_data = right->reader.storage;
    int x_scalar = left->length == 1, y_scalar = right->length == 1;
    if ((!x_scalar && (x_data == NULL || x_data->missing_count != 0)) ||
        (!y_scalar && (y_data == NULL || y_data->missing_count != 0))) return 0;
    int kind = !x_scalar ? x_data->kind : !y_scalar ? y_data->kind :
        x_data != NULL ? x_data->kind : y_data != NULL ? y_data->kind : -1;
    if (kind < NUMERIC_BYTE || kind > NUMERIC_FLOAT ||
        (!x_scalar && x_data->kind != kind) ||
        (!y_scalar && y_data->kind != kind)) return 0;
    double x_value = 0, y_value = 0;
    int code;
    if (x_scalar) {
        numeric_reader_region(&left->reader, 0, 1, &x_value, &code);
        if (code >= 0 || !R_FINITE(x_value)) return 0;
    }
    if (y_scalar) {
        numeric_reader_region(&right->reader, 0, 1, &y_value, &code);
        if (code >= 0 || !R_FINITE(y_value)) return 0;
    }
    unsigned char *destination = output->kind == NUMERIC_DOUBLE
        ? (unsigned char *) output->real : output->raw;
    const double float_limit = numeric_float_observed_limit();
    const int result_kind = output->kind;
    const int trusted = output->trusted;
    const int integral_result = kind <= NUMERIC_LONG && operation != '/' &&
        (!x_scalar || x_value == trunc(x_value)) &&
        (!y_scalar || y_value == trunc(y_value));
    unsigned fits = output->fits;
    size_t missing_count = output->missing_count;
    for (R_xlen_t start = 0; start < length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) (length - start > 16384 ? 16384 : length - start);
        const unsigned char *x_raw = x_scalar ? NULL :
            numeric_read_span(x_data, (size_t) start, count, &count);
        const unsigned char *y_raw = y_scalar ? NULL :
            numeric_read_span(y_data, (size_t) start, count, &count);
#define ARITHMETIC_SPAN_SHAPE(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED, XS, YS) \
    {                                                                     \
        TYPE *restrict target = (TYPE *) (void *) destination;             \
        for (size_t offset = 0; offset < count; offset++) {                \
            double xv = x_value, yv = y_value;                            \
            if (!(XS)) {                                                  \
                SOURCE source;                                            \
                memcpy(&source, x_raw + offset * sizeof(SOURCE), sizeof(SOURCE)); \
                xv = (double) source;                                     \
            }                                                             \
            if (!(YS)) {                                                  \
                SOURCE source;                                            \
                memcpy(&source, y_raw + offset * sizeof(SOURCE), sizeof(SOURCE)); \
                yv = (double) source;                                     \
            }                                                             \
            double value = xv OP yv;                                      \
            int missing = 0;                                              \
            R_xlen_t index = start + (R_xlen_t) offset;                   \
            ARITHMETIC_STORE_RESULT(TYPE, FIT, MISSING, TRUSTED)           \
        }                                                                 \
    }
#define ARITHMETIC_SPAN_SHAPES(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED)     \
    if (x_scalar) {                                                       \
        if (y_scalar) {                                                   \
            ARITHMETIC_SPAN_SHAPE(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED, 1, 1) \
        } else {                                                          \
            ARITHMETIC_SPAN_SHAPE(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED, 1, 0) \
        }                                                                 \
    } else if (y_scalar) {                                                \
        ARITHMETIC_SPAN_SHAPE(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED, 0, 1) \
    } else {                                                              \
        ARITHMETIC_SPAN_SHAPE(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED, 0, 0) \
    }
#define ARITHMETIC_SPAN_LOOP(SOURCE, OP, TYPE, FIT, MISSING)                \
    if (trusted) {                                                        \
        const int integral = 1;                                          \
        ARITHMETIC_SPAN_SHAPES(SOURCE, OP, TYPE, FIT, MISSING, 1)          \
    } else if (integral_result) {                                         \
        const int integral = 1;                                          \
        ARITHMETIC_SPAN_SHAPES(SOURCE, OP, TYPE, FIT, MISSING, 0)          \
    } else {                                                              \
        const int integral = 0;                                          \
        ARITHMETIC_SPAN_SHAPES(SOURCE, OP, TYPE, FIT, MISSING, 0)          \
    }
        switch (kind) {
        case NUMERIC_BYTE: ARITHMETIC_OPERATORS(ARITHMETIC_SPAN_LOOP, int8_t); break;
        case NUMERIC_INT: ARITHMETIC_OPERATORS(ARITHMETIC_SPAN_LOOP, int16_t); break;
        case NUMERIC_LONG: ARITHMETIC_OPERATORS(ARITHMETIC_SPAN_LOOP, int32_t); break;
        case NUMERIC_FLOAT: ARITHMETIC_OPERATORS(ARITHMETIC_SPAN_LOOP, float); break;
        }
#undef ARITHMETIC_SPAN_LOOP
#undef ARITHMETIC_SPAN_SHAPES
#undef ARITHMETIC_SPAN_SHAPE
        start += (R_xlen_t) count;
    }
    output->fits = fits;
    output->missing_count = missing_count;
    return 1;
}

/* Arithmetic needs only a missing mask, not the missing letter. Hoist each
   operand's encoding policy before intersecting its retained spans. The float
   predicate is float_missing_offset() >= 0 plus IEEE NaNs: modern infinities
   remain observed, while the legacy positive reserved range includes +Inf. */
typedef struct {
    double minimum;
    uint32_t maximum;
    uint32_t alignment;
} arithmetic_missing_policy;

static arithmetic_missing_policy arithmetic_missing_policy_for(const numeric_data *data) {
    arithmetic_missing_policy policy = {0, 0, 0};
    if (data == NULL) return policy;
    int legacy = data->format_version <= 111;
    switch (data->kind) {
    case NUMERIC_BYTE: policy.minimum = legacy ? 127 : 101; break;
    case NUMERIC_INT: policy.minimum = legacy ? 32767 : 32741; break;
    case NUMERIC_LONG: policy.minimum = legacy ? 2147483647.0 : 2147483621.0; break;
    case NUMERIC_FLOAT:
        policy.maximum = legacy ? UINT32_C(0x7fffffff) : UINT32_C(0x7f00d000);
        policy.alignment = legacy ? 0 : UINT32_C(0x000007ff);
        break;
    }
    return policy;
}

#define ARITHMETIC_INTEGER_MISSING(TYPE)                                   \
    static int arithmetic_##TYPE##_missing(                                \
        TYPE value, const arithmetic_missing_policy *policy                \
    ) { return (double) value >= policy->minimum; }
ARITHMETIC_INTEGER_MISSING(int8_t)
ARITHMETIC_INTEGER_MISSING(int16_t)
ARITHMETIC_INTEGER_MISSING(int32_t)
#undef ARITHMETIC_INTEGER_MISSING

static int arithmetic_float_missing(float value, const arithmetic_missing_policy *policy) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return ((bits >= UINT32_C(0x7f000000)) & (bits <= policy->maximum) &
            ((bits & policy->alignment) == 0)) |
        ((bits & UINT32_C(0x7fffffff)) > UINT32_C(0x7f800000));
}

/* Missing-bearing same-width operands use the observed producer's typed
   arithmetic and destination policies without decoded value/code buffers. */
static int arithmetic_compact_missing_run(
    const arithmetic_operand *left, const arithmetic_operand *right,
    R_xlen_t length, int operation, arithmetic_output *output
) {
    const numeric_data *x_data = left->reader.storage;
    const numeric_data *y_data = right->reader.storage;
    int x_scalar = left->length == 1, y_scalar = right->length == 1;
    if ((!x_scalar && x_data == NULL) || (!y_scalar && y_data == NULL)) return 0;
    if ((x_scalar || x_data->missing_count == 0) &&
        (y_scalar || y_data->missing_count == 0)) return 0;
    int kind = !x_scalar ? x_data->kind : !y_scalar ? y_data->kind :
        x_data != NULL ? x_data->kind : y_data != NULL ? y_data->kind : -1;
    if (kind < NUMERIC_BYTE || kind > NUMERIC_FLOAT ||
        (!x_scalar && x_data->kind != kind) ||
        (!y_scalar && y_data->kind != kind)) return 0;
    double x_value = 0, y_value = 0;
    int code;
    if (x_scalar) {
        numeric_reader_region(&left->reader, 0, 1, &x_value, &code);
        if (code >= 0 || !R_FINITE(x_value)) return 0;
    }
    if (y_scalar) {
        numeric_reader_region(&right->reader, 0, 1, &y_value, &code);
        if (code >= 0 || !R_FINITE(y_value)) return 0;
    }
    arithmetic_missing_policy x_policy = arithmetic_missing_policy_for(x_data);
    arithmetic_missing_policy y_policy = arithmetic_missing_policy_for(y_data);
    unsigned char *destination = output->kind == NUMERIC_DOUBLE
        ? (unsigned char *) output->real : output->raw;
    const double float_limit = numeric_float_observed_limit();
    const int result_kind = output->kind;
    const int trusted = output->trusted;
    const int integral_result = kind <= NUMERIC_LONG && operation != '/' &&
        (!x_scalar || x_value == trunc(x_value)) &&
        (!y_scalar || y_value == trunc(y_value));
    unsigned fits = output->fits;
    size_t missing_count = output->missing_count;
    for (R_xlen_t start = 0; start < length;) {
        R_CheckUserInterrupt();
        size_t count = (size_t) (length - start > 16384 ? 16384 : length - start);
        const unsigned char *x_raw = x_scalar ? NULL :
            numeric_read_span(x_data, (size_t) start, count, &count);
        const unsigned char *y_raw = y_scalar ? NULL :
            numeric_read_span(y_data, (size_t) start, count, &count);
#define ARITHMETIC_SPAN_SHAPE(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED, XS, YS) \
    {                                                                     \
        TYPE *restrict target = (TYPE *) (void *) destination;             \
        for (size_t offset = 0; offset < count; offset++) {                \
            double xv = x_value, yv = y_value;                            \
            int missing = 0;                                              \
            if (!(XS)) {                                                  \
                SOURCE source;                                            \
                memcpy(&source, x_raw + offset * sizeof(SOURCE), sizeof(SOURCE)); \
                xv = (double) source;                                     \
                missing |= arithmetic_##SOURCE##_missing(source, &x_policy); \
            }                                                             \
            if (!(YS)) {                                                  \
                SOURCE source;                                            \
                memcpy(&source, y_raw + offset * sizeof(SOURCE), sizeof(SOURCE)); \
                yv = (double) source;                                     \
                missing |= arithmetic_##SOURCE##_missing(source, &y_policy); \
            }                                                             \
            double value = xv OP yv;                                      \
            R_xlen_t index = start + (R_xlen_t) offset;                   \
            ARITHMETIC_STORE_RESULT(TYPE, FIT, MISSING, TRUSTED)           \
        }                                                                 \
    }
#define ARITHMETIC_SPAN_SHAPES(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED)     \
    if (x_scalar) {                                                       \
        if (y_scalar) {                                                   \
            ARITHMETIC_SPAN_SHAPE(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED, 1, 1) \
        } else {                                                          \
            ARITHMETIC_SPAN_SHAPE(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED, 1, 0) \
        }                                                                 \
    } else if (y_scalar) {                                                \
        ARITHMETIC_SPAN_SHAPE(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED, 0, 1) \
    } else {                                                              \
        ARITHMETIC_SPAN_SHAPE(SOURCE, OP, TYPE, FIT, MISSING, TRUSTED, 0, 0) \
    }
#define ARITHMETIC_SPAN_LOOP(SOURCE, OP, TYPE, FIT, MISSING)                \
    if (trusted) {                                                        \
        const int integral = 1;                                          \
        ARITHMETIC_SPAN_SHAPES(SOURCE, OP, TYPE, FIT, MISSING, 1)          \
    } else if (integral_result) {                                         \
        const int integral = 1;                                          \
        ARITHMETIC_SPAN_SHAPES(SOURCE, OP, TYPE, FIT, MISSING, 0)          \
    } else {                                                              \
        const int integral = 0;                                          \
        ARITHMETIC_SPAN_SHAPES(SOURCE, OP, TYPE, FIT, MISSING, 0)          \
    }
        switch (kind) {
        case NUMERIC_BYTE: ARITHMETIC_OPERATORS(ARITHMETIC_SPAN_LOOP, int8_t); break;
        case NUMERIC_INT: ARITHMETIC_OPERATORS(ARITHMETIC_SPAN_LOOP, int16_t); break;
        case NUMERIC_LONG: ARITHMETIC_OPERATORS(ARITHMETIC_SPAN_LOOP, int32_t); break;
        case NUMERIC_FLOAT: ARITHMETIC_OPERATORS(ARITHMETIC_SPAN_LOOP, float); break;
        }
#undef ARITHMETIC_SPAN_LOOP
#undef ARITHMETIC_SPAN_SHAPES
#undef ARITHMETIC_SPAN_SHAPE
        start += (R_xlen_t) count;
    }
    output->fits = fits;
    output->missing_count = missing_count;
    return 1;
}

static void arithmetic_run(
    const arithmetic_operand *left, const arithmetic_operand *right,
    R_xlen_t length, int operation, arithmetic_output *output
) {
    if (output->kind == NUMERIC_DOUBLE &&
        left->reader.real_values != NULL && right->reader.real_values != NULL) {
        arithmetic_double_run(left, right, length, operation, output);
        return;
    }
    if (arithmetic_compact_run(left, right, length, operation, output)) return;
    if (arithmetic_compact_missing_run(left, right, length, operation, output)) return;
    double x[1024], y[1024];
    int x_codes[1024], y_codes[1024];
    int x_scalar = left->length == 1, y_scalar = right->length == 1;
    unsigned char *destination = output->kind == NUMERIC_DOUBLE
        ? (unsigned char *) output->real : output->raw;
    const double float_limit = numeric_float_observed_limit();
    const int integral = 0;
    const int result_kind = output->kind;
    const int trusted = output->trusted;
    unsigned fits = output->fits;
    size_t missing_count = output->missing_count;
    if (x_scalar) numeric_reader_region(&left->reader, 0, 1, x, x_codes);
    if (y_scalar) numeric_reader_region(&right->reader, 0, 1, y, y_codes);
    for (R_xlen_t start = 0; start < length;) {
        R_CheckUserInterrupt();
        R_xlen_t count = length - start > 1024 ? 1024 : length - start;
        if (!x_scalar) numeric_reader_region(&left->reader, start, count, x, x_codes);
        if (!y_scalar) numeric_reader_region(&right->reader, start, count, y, y_codes);
#define ARITHMETIC_BLOCK_LOOP(SOURCE, OP, TYPE, FIT, MISSING)                \
    {                                                                     \
        TYPE *restrict target = (TYPE *) (void *) destination;             \
        for (R_xlen_t offset = 0; offset < count; offset++) {               \
            R_xlen_t xi = x_scalar ? 0 : offset;                          \
            R_xlen_t yi = y_scalar ? 0 : offset;                          \
            int missing = x_codes[xi] >= 0 || y_codes[yi] >= 0;           \
            double value = missing ? NA_REAL : x[xi] OP y[yi];            \
            R_xlen_t index = start + offset;                              \
            ARITHMETIC_STORE_RESULT(TYPE, FIT, MISSING, trusted)           \
        }                                                                 \
    }
        ARITHMETIC_OPERATORS(ARITHMETIC_BLOCK_LOOP, double)
#undef ARITHMETIC_BLOCK_LOOP
        start += count;
    }
    output->fits = fits;
    output->missing_count = missing_count;
}
#undef ARITHMETIC_STORE_RESULT
#undef ARITHMETIC_TARGETS
#undef ARITHMETIC_OPERATORS

/* Private, one-use correctness checkpoint. Ordinary R defers finalizers at
   native allocations; the GC mode exercises immediate-finalizer builds and
   the failure mode checks restoration when production exits nonlocally. */
static int arithmetic_checkpoint = 0;
static SEXP arithmetic_checkpoint_token = NULL;

SEXP C_dtatools_test_arithmetic_checkpoint(SEXP mode, SEXP token) {
    if (TYPEOF(mode) != INTSXP || ALTREP(mode) || ANY_ATTRIB(mode) ||
        XLENGTH(mode) != 1 || INTEGER(mode)[0] < 0 || INTEGER(mode)[0] > 2)
        Rf_error("arithmetic checkpoint mode must be 0, 1, or 2");
    if ((token != R_NilValue && TYPEOF(token) != ENVSXP) ||
        (INTEGER(mode)[0] == 0 && token != R_NilValue))
        Rf_error("arithmetic checkpoint token must be an environment or NULL");
    int previous = arithmetic_checkpoint;
    if (token != R_NilValue) R_PreserveObject(token);
    if (arithmetic_checkpoint_token != NULL)
        R_ReleaseObject(arithmetic_checkpoint_token);
    arithmetic_checkpoint_token = token == R_NilValue ? NULL : token;
    arithmetic_checkpoint = INTEGER(mode)[0];
    return Rf_ScalarInteger(previous);
}

static SEXP arithmetic_backing(R_xlen_t length, int kind) {
    if (arithmetic_checkpoint != 0) {
        int mode = arithmetic_checkpoint;
        arithmetic_checkpoint = 0;
        if (arithmetic_checkpoint_token != NULL) {
            R_ReleaseObject(arithmetic_checkpoint_token);
            arithmetic_checkpoint_token = NULL;
        }
        R_gc();
        if (mode == 2) Rf_error("injected arithmetic checkpoint failure");
    }
    if (kind == NUMERIC_DOUBLE) return Rf_allocVector(REALSXP, length);
    size_t width = numeric_kind_width(kind);
    if ((uint64_t) length > SIZE_MAX / width ||
        (uint64_t) length > (uint64_t) R_XLEN_T_MAX / width)
        Rf_error("computed Stata numeric vector is too long");
    return Rf_allocVector(RAWSXP, length * (R_xlen_t) width);
}

static arithmetic_output arithmetic_output_create(SEXP backing, int kind) {
    return (arithmetic_output) {
        kind, kind == NUMERIC_DOUBLE, (1U << (NUMERIC_DOUBLE + 1)) - 1U, 0,
        kind == NUMERIC_DOUBLE ? NULL : RAW(backing),
        kind == NUMERIC_DOUBLE ? REAL(backing) : NULL
    };
}

static SEXP arithmetic_adopt_backing(SEXP backing, R_xlen_t length,
                                     int kind, size_t missing_count) {
    SEXP result = PROTECT(kind == NUMERIC_DOUBLE
        ? owned_adopt_real(backing)
        : numeric_from_backing_managed(backing, (size_t) length, kind, 0, 119,
                                       missing_count));
    if (kind == NUMERIC_DOUBLE) {
        owned_flags(result)[OWNED_NO_NA] = missing_count == 0;
        owned_flags(result)[OWNED_FINITE_DOUBLE] = missing_count == 0;
    }
    UNPROTECT(1);
    return result;
}

#include "numeric-arithmetic-scale.h"
#include "numeric-arithmetic-integer.h"

typedef struct {
    SEXP x;
    SEXP y;
    SEXP claims;
    R_xlen_t length;
    int operation;
    int minimum;
    int *result_kind;
} arithmetic_result_context;

static void arithmetic_release_claims(void *raw) {
    arithmetic_result_context *context = raw;
    for (int slot = 2; slot >= 0; slot -= 2) {
        SEXP external = VECTOR_ELT(context->claims, slot);
        if (external != R_NilValue &&
            R_ExternalPtrTag(external) == context->claims) {
            /* New aliases replace our claim with the shared marker. Never
               erase their ownership change when restoring the entry tag. */
            R_SetExternalPtrTag(external, VECTOR_ELT(context->claims, slot + 1));
        }
    }
}

static SEXP arithmetic_result_body(void *raw) {
    arithmetic_result_context *context = raw;
    SEXP x = context->x, y = context->y;
    R_xlen_t length = context->length;
    int operation = context->operation, minimum = context->minimum;
    int *result_kind = context->result_kind;
    arithmetic_operand left, right;
    PROTECT(arithmetic_capture(x, &left, context->claims, 0));
    PROTECT(arithmetic_capture(y, &right, context->claims, 2));
    SEXP specialized = arithmetic_scale_result(
        &left, &right, length, operation, minimum, result_kind);
    if (specialized == NULL)
        specialized = arithmetic_integer_result(
            &left, &right, length, operation, minimum, result_kind);
    if (specialized != NULL) {
        UNPROTECT(2);
        return specialized;
    }
    PROTECT_INDEX backing_index;
    SEXP backing;
    PROTECT_WITH_INDEX(backing = arithmetic_backing(length, minimum), &backing_index);
    arithmetic_output output = arithmetic_output_create(backing, minimum);
    arithmetic_run(&left, &right, length, operation, &output);
    int kind = minimum;
    if (!(output.fits & (1U << kind))) {
        for (kind = minimum + 1; kind < NUMERIC_DOUBLE; kind++) {
            if (minimum == NUMERIC_LONG && kind == NUMERIC_FLOAT) continue;
            if (output.fits & (1U << kind)) break;
        }
        REPROTECT(backing = arithmetic_backing(length, kind), backing_index);
        output = arithmetic_output_create(backing, kind);
        output.trusted = 1;
        arithmetic_run(&left, &right, length, operation, &output);
    }
    SEXP result = PROTECT(arithmetic_adopt_backing(
        backing, length, kind, output.missing_count));
    *result_kind = kind;
    UNPROTECT(4);
    return result;
}

static SEXP arithmetic_result(SEXP x, SEXP y, R_xlen_t length,
                              int operation, int minimum, int *result_kind) {
    SEXP claims = PROTECT(Rf_allocVector(VECSXP, 4));
    arithmetic_result_context context = {
        x, y, claims, length, operation, minimum, result_kind
    };
    SEXP result = R_ExecWithCleanup(
        arithmetic_result_body, &context, arithmetic_release_claims, &context
    );
    UNPROTECT(1);
    return result;
}

/* NULL declines without forcing any original promise. A successful extension
   returns the same committed status as the original scalar producer. */
static SEXP numeric_arithmetic_extension(
    SEXP frame, SEXP x, SEXP y, SEXP op, SEXP storage_getter, SEXP dependencies
) {
    if (TYPEOF(op) != STRSXP || ALTREP(op) || ANY_ATTRIB(op) ||
        XLENGTH(op) != 1 || STRING_ELT(op, 0) == NA_STRING) return R_NilValue;
    const char *operator = CHAR(STRING_ELT(op, 0));
    int operation = operator[0];
    if ((operation != '+' && operation != '-' &&
         operation != '*' && operation != '/') ||
        operator[1] != '\0') return R_NilValue;
    double scalar;
    if ((operation == '+' || operation == '-') &&
        (scalar_finite_value(x, &scalar) || scalar_finite_value(y, &scalar)))
        return R_NilValue;
    int x_kind, y_kind;
    if (!arithmetic_operand_kind(x, &x_kind) ||
        !arithmetic_operand_kind(y, &y_kind) ||
        (x_kind < 0 && y_kind < 0)) return R_NilValue;
    R_xlen_t x_length = XLENGTH(x), y_length = XLENGTH(y);
    if (x_length == 0 || y_length == 0 ||
        (x_length != y_length && x_length != 1 && y_length != 1)) return R_NilValue;
    R_xlen_t length = x_length > y_length ? x_length : y_length;
    int minimum = computed_storage_kind(computed_minimum(frame, storage_getter));
    if (minimum < 0 || minimum != arithmetic_promoted_kind(x_kind, y_kind) ||
        !scalar_dependencies_unchanged(frame, dependencies) ||
        !arithmetic_operator_unchanged(frame, operation) ||
        !arithmetic_storage_names_unchanged(frame, dependencies) ||
        !scalar_is_na_primitive(frame) ||
        !dtatools_numeric_helpers_admitted(frame, DTATOOLS_NUMERIC_SCALAR) ||
        !dtatools_numeric_decoration_admitted(frame, DTATOOLS_NUMERIC_SCALAR,
                                              R_NilValue)) return R_NilValue;
    int result_kind;
    SEXP result = PROTECT(arithmetic_result(x, y, length, operation, minimum,
                                            &result_kind));
    static const char *storage_names[] = {"byte", "int", "long", "float", "double"};
    SEXP storage = PROTECT(Rf_mkString(storage_names[result_kind]));
    numeric_decorate_result(result, storage);
    if (!numeric_result_slot_available(frame)) {
        UNPROTECT(2);
        return R_NilValue;
    }
    R_getVar(Rf_install("x"), frame, TRUE);
    R_getVar(Rf_install("y"), frame, TRUE);
    R_getVar(Rf_install("op"), frame, TRUE);
    R_getVar(Rf_install("minimum"), frame, TRUE);
    SEXP status = numeric_result_commit(result, frame);
    if (LOGICAL(status)[0]) numeric_scalar_successes++;
    UNPROTECT(2);
    return status;
}
#endif
