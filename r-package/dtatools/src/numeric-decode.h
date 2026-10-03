/* Decode a contiguous compact span under the caller's existing source
   lifetime contract. Materialization holds its read claim and roots the bytes
   across the bounded interrupt polls; ordinary regions retain their borrowed
   reader contract.
   No R callback, owner lookup, temporal dispatch, or format dispatch occurs
   inside a typed tile. memcpy keeps unaligned retained/raw spans valid. */
#ifndef DTATOOLS_NUMERIC_DECODE_H
#define DTATOOLS_NUMERIC_DECODE_H

typedef void (*numeric_decode_tile)(
    const unsigned char *source, size_t length, double *output
);

#define NUMERIC_DECODE_UNCHANGED(value) (value)
#define NUMERIC_DECODE_DATE(value) ((value) - 3653.0)
#define NUMERIC_DECODE_DATETIME(value) ((value) / 1000.0 - 315619200.0)

#define DEFINE_NUMERIC_DECODE_TILE(NAME, TYPE, SUFFIX, MISSING, FORMAT, TRANSFORM) \
    static void numeric_decode_##NAME##_##SUFFIX(                              \
        const unsigned char *source, size_t length, double *output             \
    ) {                                                                        \
        for (size_t index = 0; index < length; index++) {                       \
            TYPE raw;                                                          \
            memcpy(&raw, source + index * sizeof(raw), sizeof(raw));           \
            int missing = MISSING ? NAME##_missing_offset(raw, FORMAT) : -1;   \
            output[index] = missing >= 0 ? numeric_missing_value(missing)      \
                : TRANSFORM((double) raw);                                     \
        }                                                                      \
    }

#define DEFINE_NUMERIC_DECODE_TEMPORAL(NAME, TYPE, SUFFIX, TRANSFORM)          \
    DEFINE_NUMERIC_DECODE_TILE(NAME, TYPE, SUFFIX##_plain, 0, 119, TRANSFORM)  \
    DEFINE_NUMERIC_DECODE_TILE(NAME, TYPE, SUFFIX##_legacy, 1, 111, TRANSFORM) \
    DEFINE_NUMERIC_DECODE_TILE(NAME, TYPE, SUFFIX##_modern, 1, 119, TRANSFORM)

#define DEFINE_NUMERIC_DECODE_TYPE(NAME, TYPE)                                \
    DEFINE_NUMERIC_DECODE_TEMPORAL(NAME, TYPE, number, NUMERIC_DECODE_UNCHANGED) \
    DEFINE_NUMERIC_DECODE_TEMPORAL(NAME, TYPE, date, NUMERIC_DECODE_DATE)       \
    DEFINE_NUMERIC_DECODE_TEMPORAL(NAME, TYPE, datetime, NUMERIC_DECODE_DATETIME)

DEFINE_NUMERIC_DECODE_TYPE(byte, int8_t)
DEFINE_NUMERIC_DECODE_TYPE(int, int16_t)
DEFINE_NUMERIC_DECODE_TYPE(long, int32_t)
DEFINE_NUMERIC_DECODE_TYPE(float, float)

#undef DEFINE_NUMERIC_DECODE_TYPE
#undef DEFINE_NUMERIC_DECODE_TEMPORAL
#undef DEFINE_NUMERIC_DECODE_TILE
#undef NUMERIC_DECODE_DATETIME
#undef NUMERIC_DECODE_DATE
#undef NUMERIC_DECODE_UNCHANGED

#define NUMERIC_DECODE_TEMPORAL_TABLE(NAME, TEMPORAL)                          \
    {numeric_decode_##NAME##_##TEMPORAL##_plain,                               \
     numeric_decode_##NAME##_##TEMPORAL##_legacy,                              \
     numeric_decode_##NAME##_##TEMPORAL##_modern}
#define NUMERIC_DECODE_TYPE_TABLE(NAME)                                      \
    {NUMERIC_DECODE_TEMPORAL_TABLE(NAME, number),                             \
     NUMERIC_DECODE_TEMPORAL_TABLE(NAME, date),                               \
     NUMERIC_DECODE_TEMPORAL_TABLE(NAME, datetime)}

static void numeric_decode_plain_span(const numeric_data *span, double *output) {
    static const numeric_decode_tile kernels[4][3][3] = {
        NUMERIC_DECODE_TYPE_TABLE(byte), NUMERIC_DECODE_TYPE_TABLE(int),
        NUMERIC_DECODE_TYPE_TABLE(long), NUMERIC_DECODE_TYPE_TABLE(float)
    };
    if (span->kind < NUMERIC_BYTE || span->kind > NUMERIC_FLOAT ||
        numeric_payload_retained(span))
        Rf_error("invalid compact numeric decode span");
    int temporal = span->temporal == 1 ? 1 : span->temporal == 2 ? 2 : 0;
    int format = span->missing_count == 0 ? 0 : span->format_version <= 111 ? 1 : 2;
    numeric_decode_tile decode = kernels[span->kind][temporal][format];
    size_t width = numeric_kind_width(span->kind);
    const unsigned char *source = span->values;
    for (size_t start = 0; start < span->length;) {
        size_t count = span->length - start;
        if (count > 16384) count = 16384;
        R_CheckUserInterrupt();
        decode(source + start * width, count, output + start);
        start += count;
    }
}

#undef NUMERIC_DECODE_TYPE_TABLE
#undef NUMERIC_DECODE_TEMPORAL_TABLE
#endif
