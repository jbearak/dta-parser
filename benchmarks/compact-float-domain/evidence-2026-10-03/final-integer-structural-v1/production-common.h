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


static inline int numeric_strict_modern_float(const numeric_data *data) {
    return data != NULL && data->kind == NUMERIC_FLOAT && data->temporal == 0 &&
        data->format_version > 111 &&
        (data->domain_flags & NUMERIC_DOMAIN_STRICT_MODERN_FLOAT) != 0;
}
static double numeric_float_observed_limit(void) {
    uint32_t maximum_bits = UINT32_C(0x7effffff);
    float maximum;
    memcpy(&maximum, &maximum_bits, sizeof(maximum));
    return (double) maximum;
}
static int uncounted_result_valid(double result) {
#if defined(__APPLE__) && defined(__aarch64__) && defined(__SIZEOF_DOUBLE__) && \
    __SIZEOF_DOUBLE__ == 8 && FLT_RADIX == 2 && DBL_MANT_DIG == 53 && \
    DBL_MAX_EXP == 1024 && UINT64_MAX == UINT64_C(0xffffffffffffffff)
    uint64_t result_bits;
    memcpy(&result_bits, &result, sizeof result_bits);
    return (result_bits & UINT64_C(0x7fffffffffffffff)) <=
        UINT64_C(0x7fdfffffffffffff);
#else
    return isfinite(result) && fabs(result) <= DBL_MAX / 2;
#endif
}
static int scalar_arithmetic_result_valid(double value) {
  result_checks[phase]++; return uncounted_result_valid(value);
}

static int32_t arithmetic_integer_missing(const numeric_data *data) {
    if (data == NULL) return 0;
    int legacy = data->format_version <= 111;
    switch (data->kind) {
    case NUMERIC_BYTE: return legacy ? INT8_MAX : 101;
    case NUMERIC_INT: return legacy ? INT16_MAX : 32741;
    default: return legacy ? INT32_MAX : INT32_C(2147483621);
    }
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