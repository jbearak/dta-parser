#include <stdint.h>
#include <stdio.h>
#include <inttypes.h>
typedef struct { double minimum; uint32_t maximum; uint32_t alignment; } arithmetic_missing_policy;
static int arithmetic_scale_float_invalid(uint32_t bits,
                                          arithmetic_missing_policy policy) {
    return ((bits >= UINT32_C(0x7f000000)) & (bits <= policy.maximum) &
            ((bits & policy.alignment) == 0)) |
        ((bits & UINT32_C(0x7fffffff)) >= UINT32_C(0x7f800000));
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
static uint64_t checked = 0;
static int check(uint32_t bits) {
    arithmetic_missing_policy policies[] = {{0, UINT32_C(0x7f00d000), UINT32_C(0x7ff)}, {0, UINT32_C(0x7fffffff), 0}};
    for (int is_legacy = 0; is_legacy < 2; is_legacy++) {
        int expected = arithmetic_scale_float_invalid(bits, policies[is_legacy]);
        int actual = is_legacy ? arithmetic_scale_float_invalid_legacy(bits) : arithmetic_scale_float_invalid_modern(bits);
        if (actual != expected) {
            fprintf(stderr, "Mismatch bits=%08" PRIx32 " legacy=%d expected=%d actual=%d\n", bits, is_legacy, expected, actual);
            return 1;
        }
        checked++;
    }
    return 0;
}
int main(void) {
    const uint32_t boundaries[] = {0, UINT32_C(0x80000000), UINT32_C(0x7effffff), UINT32_C(0x7f000000), UINT32_C(0x7f00d000), UINT32_C(0x7f00d800), UINT32_C(0x7f7fffff), UINT32_C(0x7f800000), UINT32_C(0x7fc00000), UINT32_C(0x7fffffff), UINT32_C(0xfeffffff), UINT32_C(0xff000000), UINT32_C(0xff7fffff), UINT32_C(0xff800000), UINT32_C(0xffc00000), UINT32_MAX};
    for (unsigned i=0; i<sizeof(boundaries)/sizeof(boundaries[0]); i++)
        for (int offset=-4096; offset<=4096; offset++)
            if (check(boundaries[i] + (uint32_t) offset)) return 1;
    for (uint32_t bits=UINT32_C(0x7eff0000); bits<=UINT32_C(0x7f020000); bits++)
        if (check(bits)) return 1;
    uint32_t state=UINT32_C(0x9e3779b9);
    for (unsigned i=0; i<1000000; i++) {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5;
        if (check(state)) return 1;
    }
    printf("PASS: %" PRIu64 " policy comparisons; 1000000 deterministic random raw32 inputs plus reserved/IEEE boundaries; modern and legacy\n", checked);
    return 0;
}
