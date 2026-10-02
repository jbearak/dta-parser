#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <limits.h>
enum {NUMERIC_BYTE, NUMERIC_INT, NUMERIC_LONG, NUMERIC_FLOAT};
typedef struct {int kind; int format_version;} numeric_data;
static int byte_missing_offset(int8_t value, int format_version) {
    if (format_version <= 111) return value == 127 ? 0 : -1;
    return value >= 101 && value <= 127 ? value - 101 : -1;
}

static int int_missing_offset(int16_t value, int format_version) {
    if (format_version <= 111) return value == 32767 ? 0 : -1;
    return value >= 32741 && value <= 32767 ? value - 32741 : -1;
}

static int long_missing_offset(int32_t value, int format_version) {
    if (format_version <= 111) return value == INT32_MAX ? 0 : -1;
    return value >= INT32_C(2147483621) && value <= INT32_MAX
        ? (int) (value - INT32_C(2147483621)) : -1;
}

static int float_missing_offset(float value, int format_version) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    if (format_version <= 111) {
        return bits >= UINT32_C(0x7f000000) && bits < UINT32_C(0x80000000)
            ? 0 : -1;
    }
    if (bits < UINT32_C(0x7f000000) || bits > UINT32_C(0x7f00d000)) {
        return -1;
    }
    uint32_t delta = bits - UINT32_C(0x7f000000);
    return delta % UINT32_C(0x00000800) == 0
        ? (int) (delta / UINT32_C(0x00000800)) : -1;
}

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


int main(void) {
    size_t checked = 0;
    for (int version = 111; version <= 119; version += 8) {
        numeric_data data = {NUMERIC_BYTE, version};
        arithmetic_missing_policy policy = arithmetic_missing_policy_for(&data);
        for (int value = -128; value <= 127; value++, checked++)
            if (arithmetic_int8_t_missing((int8_t)value, &policy) != (byte_missing_offset((int8_t)value, version) >= 0)) return 1;
        data.kind = NUMERIC_INT; policy = arithmetic_missing_policy_for(&data);
        for (int value = -32768; value <= 32767; value++, checked++)
            if (arithmetic_int16_t_missing((int16_t)value, &policy) != (int_missing_offset((int16_t)value, version) >= 0)) return 2;
        uint32_t state = 0x12345678;
        data.kind = NUMERIC_LONG; policy = arithmetic_missing_policy_for(&data);
        for (int i = 0; i < 1000000; i++, checked++) {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5;
            int32_t value; memcpy(&value, &state, sizeof(value));
            if (i < 40) value = INT32_MAX - i;
            if (arithmetic_int32_t_missing(value, &policy) != (long_missing_offset(value, version) >= 0)) return 3;
        }
        data.kind = NUMERIC_FLOAT; policy = arithmetic_missing_policy_for(&data);
        for (int i = 0; i < 1000000; i++, checked++) {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5;
            uint32_t bits = i < 0x10000 ? 0x7efffff0u + (uint32_t)i : state;
            float value; memcpy(&value, &bits, sizeof(value));
            int expected = float_missing_offset(value, version) >= 0 || isnan((double)value);
            if (arithmetic_float_missing(value, &policy) != expected) {
                printf("mismatch %d %08x\n", version, bits); return 4;
            }
        }
    }
    printf("%zu classifier comparisons; zero mismatches\n", checked);
    return 0;
}
