/* Compact numeric payloads: the numeric_data descriptor, its ALTREP class
   methods, the per-element read and write kernels, the reader shared with
   mutation and egen, and the Rust bridge that hands finished payloads to R.
   Per-element helpers that hot loops call stay in this unit. */
#include "dtatools-internal.h"


/* Capture the compiler-created argument promises without forcing them. The
   capture closure has returned before the selector evaluates any callback. */
SEXP C_dtatools_capture_branch_frame(void) {
    return R_GetCurrentEnv();
}

/* Evaluating symbols through the captured primitive keeps R's exact condition
   rules and forces the original promises in their original environments. A
   primitive alias over raw branch expressions would lose their bytecode.
   Use only where the selected value is assigned or discarded: .Call does not
   preserve an invisible branch's visibility when used as a tail expression. */
SEXP C_dtatools_select_branch(SEXP frame, SEXP primitive_if) {
    if (TYPEOF(frame) != ENVSXP || TYPEOF(primitive_if) != SPECIALSXP) {
        Rf_error("invalid native admission branch frame");
    }
    PROTECT(frame);
    PROTECT(primitive_if);
    SEXP call = PROTECT(Rf_lang4(
        primitive_if, Rf_install("condition"), Rf_install("yes"), Rf_install("no")
    ));
    SEXP result = Rf_eval(call, frame);
    UNPROTECT(3);
    return result;
}

static double numeric_construct_successes = 0;
static double numeric_computed_successes = 0;
static double numeric_scalar_successes = 0;
static double numeric_holds_successes = 0;

/* Scratch policy control: zero restores the original admission path. This
   stores only a size policy, never a live function or successful proof. */
static int numeric_size_minimum = 2048;
static SEXP numeric_size_symbols[4];
static double numeric_size_counts[4][3];

void initialize_numeric_size_gate(void) {
    static const char *names[] = {"x", "y", "result", "doubles"};
    for (int i = 0; i < 4; i++) numeric_size_symbols[i] = Rf_install(names[i]);
}

SEXP C_dtatools_test_numeric_size_minimum(SEXP value) {
    int prior = numeric_size_minimum;
    if (value != R_NilValue) {
        if (TYPEOF(value) != INTSXP || ALTREP(value) || ANY_ATTRIB(value) ||
            XLENGTH(value) != 1 || INTEGER(value)[0] == NA_INTEGER ||
            INTEGER(value)[0] < 0) Rf_error("size minimum must be a nonnegative integer");
        numeric_size_minimum = INTEGER(value)[0];
    }
    return Rf_ScalarInteger(prior);
}

SEXP C_dtatools_numeric_size_stats(SEXP reset) {
    static const char *names[] = {
        "scalar.small", "scalar.unknown", "scalar.continue",
        "computed.small", "computed.unknown", "computed.continue",
        "construct.small", "construct.unknown", "construct.continue",
        "holds.small", "holds.unknown", "holds.continue"
    };
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 12));
    SEXP labels = PROTECT(Rf_allocVector(STRSXP, 12));
    for (int i = 0; i < 12; i++) {
        REAL(result)[i] = numeric_size_counts[i / 3][i % 3];
        SET_STRING_ELT(labels, i, Rf_mkChar(names[i]));
    }
    Rf_setAttrib(result, R_NamesSymbol, labels);
    if (Rf_asLogical(reset) == TRUE) memset(numeric_size_counts, 0, sizeof(numeric_size_counts));
    UNPROTECT(2);
    return result;
}

SEXP C_dtatools_numeric_entry_stats(SEXP reset) {
    static const char *fields[] = {"construct", "computed", "scalar", "holds"};
    double values[] = {numeric_construct_successes, numeric_computed_successes,
                       numeric_scalar_successes, numeric_holds_successes};
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 4));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 4));
    for (int i = 0; i < 4; i++) {
        SET_STRING_ELT(names, i, Rf_mkChar(fields[i]));
        REAL(result)[i] = values[i];
    }
    Rf_setAttrib(result, R_NamesSymbol, names);
    if (Rf_asLogical(reset) == TRUE) {
        numeric_construct_successes = numeric_computed_successes = 0;
        numeric_scalar_successes = numeric_holds_successes = 0;
    }
    UNPROTECT(2);
    return result;
}

/* Compact ALTREP payload ownership lives in the external-pointer tag. A NULL
   tag is directly writable. A non-NULL tag means an alias exists and ordinary
   writes must detach. Metadata proxies use a private token as both the tag and
   their owner claim; R_BaseEnv is the anonymous shared marker. Keep those
   states behind these helpers rather than spreading tag policy across ALTREP
   materialization and reference mutation. */
int compact_payload_is_shared(SEXP external) {
    return R_ExternalPtrTag(external) != R_NilValue;
}

void compact_payload_mark_shared(SEXP external) {
    R_SetExternalPtrTag(external, R_BaseEnv);
}

int compact_payload_is_owned_by(SEXP external, SEXP owner) {
    return owner != R_NilValue && R_ExternalPtrTag(external) == owner;
}

void compact_payload_claim(SEXP external, SEXP owner) {
    R_SetExternalPtrTag(external, owner);
}

void compact_payload_revoke_claim(SEXP external) {
    R_SetExternalPtrTag(external, R_NilValue);
}

SEXP detach_shared_materialized_payload(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    SEXP external = R_altrep_data1(value);
    if (materialized == R_NilValue || TYPEOF(external) != EXTPTRSXP ||
        !compact_payload_is_shared(external)) {
        return materialized;
    }

    SEXP detached = PROTECT(Rf_duplicate(materialized));
    SEXP private_external = PROTECT(R_MakeExternalPtr(
        NULL, R_NilValue, R_NilValue
    ));
    R_set_altrep_data1(value, private_external);
    R_set_altrep_data2(value, detached);
    UNPROTECT(2);
    return detached;
}

typedef struct {
    uintptr_t x_values;
    uintptr_t y_values;
    uintptr_t output;
    size_t width;
    unsigned char missing[8];
    uintptr_t missing_count;
    int kind;
    int format_version;
    int source_has_missing;
    uintptr_t x_owner;
    uintptr_t y_owner;
    size_t x_length;
    size_t y_length;
} numeric_gather_column;


void numeric_finalize(SEXP external) {
    void *data = R_ExternalPtrAddr(external);
    if (data != NULL) {
        R_ClearExternalPtr(external);
        dtatools_numeric_free(data);
    }
    R_SetExternalPtrProtected(external, R_NilValue);
}

numeric_data *numeric_read_storage(SEXP value) {
    numeric_data *data = (numeric_data *) R_ExternalPtrAddr(
        R_altrep_data1(value)
    );
    if (data == NULL) Rf_error("dtatools numeric data are no longer available");
    return data;
}

/* Conservative adapter for legacy consumers which require contiguous,
   writable bytes. No immutable owner ever enters those pointer interfaces. */
numeric_data *numeric_storage(SEXP value) {
    numeric_data *data = numeric_read_storage(value);
    if (numeric_payload_retained(data)) {
        double compatibility_bytes =
            (double) data->length * (double) numeric_kind_width(data->kind);
        SEXP detached = PROTECT(numeric_compact_copy(data));
        owned_numeric_compatibility_bytes += compatibility_bytes;
        R_set_altrep_data1(value, R_altrep_data1(detached));
        data = numeric_read_storage(value);
        UNPROTECT(1);
    }
    return data;
}

R_xlen_t numeric_length(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return XLENGTH(materialized);
    size_t length = numeric_read_storage(value)->length;
    if (length > (size_t) R_XLEN_T_MAX) {
        Rf_error("dtatools numeric vector is too long");
    }
    return (R_xlen_t) length;
}

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

double numeric_missing_value(int offset) {
    if (offset == 0) return NA_REAL;
    uint64_t letter = (uint64_t) ('a' + offset - 1);
    uint64_t bits = UINT64_C(0x7ff00000000007a2) | (letter << 32);
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

int tagged_na_tag_value(double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    const uint64_t sign_bit = UINT64_C(0x8000000000000000);
    const uint64_t quiet_nan_bit = UINT64_C(0x0008000000000000);
    const uint64_t tag_bits = UINT64_C(0x000000ff00000000);
    const uint64_t ignored_bits = sign_bit | quiet_nan_bit | tag_bits;
    const uint64_t tagged_na_layout = UINT64_C(0x7ff00000000007a2);
    /* Arithmetic may quiet a NaN and unary minus may set its sign; haven
       treats both layouts as the same tagged missing value. */
    uint64_t tag = (bits & tag_bits) >> 32;
    return tag != 0 &&
        (bits & ~ignored_bits) == (tagged_na_layout & ~ignored_bits)
        ? (int) tag : 0;
}

int is_tagged_na_value(double value) {
    return tagged_na_tag_value(value) != 0;
}

int dta_expression_string_is_missing(SEXP value) {
    return value == NA_STRING || LENGTH(value) == 0;
}

int dta_missing_tag_value(double value) {
    int tag = tagged_na_tag_value(value);
    return tag >= 'a' && tag <= 'z' ? tag : 0;
}

int normalized_dta_missing_tag(SEXP value, const char *argument) {
    if (value == NA_STRING) {
        Rf_error("`%s` must contain only letters `a` through `z`", argument);
    }
    const char *text = Rf_translateCharUTF8(value);
    if (text[0] == '\0' || text[1] != '\0' ||
        !((text[0] >= 'a' && text[0] <= 'z') ||
          (text[0] >= 'A' && text[0] <= 'Z'))) {
        Rf_error("`%s` must contain only letters `a` through `z`", argument);
    }
    return text[0] >= 'A' && text[0] <= 'Z'
        ? text[0] - 'A' + 'a' : text[0];
}

void copy_shape_attributes(SEXP target, SEXP source) {
    SEXP dimensions = Rf_getAttrib(source, R_DimSymbol);
    if (dimensions != R_NilValue) {
        Rf_setAttrib(target, R_DimSymbol, dimensions);
        SEXP dimension_names = Rf_getAttrib(source, R_DimNamesSymbol);
        if (dimension_names != R_NilValue) {
            Rf_setAttrib(target, R_DimNamesSymbol, dimension_names);
        }
    }

    SEXP names = Rf_getAttrib(source, R_NamesSymbol);
    if (names != R_NilValue) Rf_setAttrib(target, R_NamesSymbol, names);
}

numeric_data *unmaterialized_numeric_storage(SEXP value) {
    while (ALTREP(value) &&
           R_altrep_inherits(value, dtatools_metadata_real_class)) {
        if (R_altrep_data2(value) != R_NilValue) return NULL;
        value = metadata_proxy_source(value);
    }
    if (!ALTREP(value) ||
        !R_altrep_inherits(value, dtatools_numeric_class) ||
        R_altrep_data2(value) != R_NilValue) {
        return NULL;
    }
    return numeric_storage(value);
}

SEXP numeric_base_source(SEXP value) {
    while (ALTREP(value) &&
           R_altrep_inherits(value, dtatools_metadata_real_class)) {
        if (R_altrep_data2(value) != R_NilValue) return R_NilValue;
        value = metadata_proxy_source(value);
    }
    return ALTREP(value) && R_altrep_inherits(value, dtatools_numeric_class) &&
        R_altrep_data2(value) == R_NilValue ? value : R_NilValue;
}

numeric_data *unmaterialized_numeric_read_storage(SEXP value) {
    SEXP source = numeric_base_source(value);
    return source == R_NilValue ? NULL : numeric_read_storage(source);
}

/* Immutable span access, with a contiguous R-backed adapter. The source
   descriptor and its owning handle must remain rooted across the call. */
static const void *numeric_read_span(
    const numeric_data *data, size_t start, size_t requested, size_t *count
) {
    if (start > data->length) Rf_error("invalid compact numeric region");
    if (!numeric_payload_retained(data)) {
        *count = requested < data->length - start ? requested : data->length - start;
        return (const unsigned char *) data->values + start * numeric_kind_width(data->kind);
    }
    const void *values = NULL;
    if (!dtatools_owned_numeric_region(data, start, requested, &values, count) ||
        (*count == 0 && requested != 0 && start != data->length)) {
        Rf_error("invalid owned compact numeric region");
    }
    return values;
}

/* Visit [start, start + length) as contiguous plain spans. A plain payload is
   one span; a retained payload yields the owner's chunks in order, cut to
   blocks of at most 65536 rows so a visitor that does not poll on its own
   still leaves the loop interruptible. Kernels written for plain bytes run
   unchanged on each span. */
void numeric_for_each_span(
    const numeric_data *data, size_t start, size_t length,
    numeric_span_visitor visit, void *context
) {
    if (start > data->length || length > data->length - start) {
        Rf_error("invalid compact numeric region");
    }
    if (!numeric_payload_retained(data)) {
        numeric_data span = *data;
        span.values = (unsigned char *) data->values +
            start * numeric_kind_width(data->kind);
        span.length = length;
        visit(&span, 0, context);
        return;
    }
    size_t visited = 0;
    while (visited < length) {
        if (length >= 16384) R_CheckUserInterrupt();
        size_t count = 0;
        size_t wanted = length - visited < 65536 ? length - visited : 65536;
        numeric_data span = *data;
        span.values = (void *) numeric_read_span(
            data, start + visited, wanted, &count
        );
        span.length = count;
        span.native_owner = NULL;
        visit(&span, visited, context);
        visited += count;
    }
}

static void copy_span_bytes(const numeric_data *span, size_t offset, void *context) {
    size_t width = numeric_kind_width(span->kind);
    if (span->length != 0) {
        memcpy((unsigned char *) context + offset * width, span->values,
               span->length * width);
    }
}

void numeric_copy_region(
    const numeric_data *data, size_t start, size_t length, void *output
) {
    if (start > data->length || length > data->length - start) {
        Rf_error("invalid compact numeric copy range");
    }
    numeric_for_each_span(data, start, length, copy_span_bytes, output);
}

int materialized_numeric_storage(
    SEXP value, numeric_data *storage
) {
    if (!ALTREP(value) || R_altrep_data2(value) == R_NilValue ||
        (!R_altrep_inherits(value, dtatools_numeric_class) &&
         !R_altrep_inherits(value, dtatools_metadata_real_class))) {
        return 0;
    }
    SEXP declared = Rf_getAttrib(value, Rf_install("stata.storage"));
    if (TYPEOF(declared) != STRSXP || XLENGTH(declared) != 1) return 0;
    const char *name = CHAR(STRING_ELT(declared, 0));
    int kind = strcmp(name, "byte") == 0 ? NUMERIC_BYTE :
        strcmp(name, "int") == 0 ? NUMERIC_INT :
        strcmp(name, "long") == 0 ? NUMERIC_LONG :
        strcmp(name, "float") == 0 ? NUMERIC_FLOAT : -1;
    if (kind < 0) return 0;
    memset(storage, 0, sizeof(*storage));
    storage->length = (size_t) XLENGTH(value);
    storage->kind = kind;
    storage->temporal = Rf_inherits(value, "dta_date") ? 1 :
        (Rf_inherits(value, "dta_datetime") ? 2 : 0);
    storage->format_version = 119;
    return 1;
}

double numeric_observed_value(double value, int temporal) {
    if (temporal == 1) return value - 3653.0;
    if (temporal == 2) return value / 1000.0 - 315619200.0;
    return value;
}

/* Only the scalar ALTREP getter calls this cache. Its descriptor roots the
   immutable owner, and this helper neither allocates nor invokes R callbacks.
   Cache the complete chunk so reverse reads reuse it as well as forward reads.
   Region and native reader kernels keep their existing read-only paths. */
static const void *numeric_scalar_span(
    numeric_data *data, size_t index, size_t width
) {
    if (index < data->scalar_start || index >= data->scalar_end) {
        const void *values = NULL;
        size_t start = 0, end = 0;
        if (!dtatools_owned_numeric_scalar_span(data, index, &values, &start, &end) ||
            values == NULL || index < start || index >= end) {
            Rf_error("invalid owned compact scalar span");
        }
        data->scalar_values = values;
        data->scalar_start = start;
        data->scalar_end = end;
    }
    return (const unsigned char *) data->scalar_values +
        (index - data->scalar_start) * width;
}

#define DEFINE_NUMERIC_KERNELS(NAME, TYPE, MISSING_OFFSET)                    \
    static TYPE numeric_##NAME##_raw_at(                                     \
        const numeric_data *data, size_t index                               \
    ) {                                                                       \
        TYPE raw;                                                             \
        if (!numeric_payload_retained(data)) {                                \
            memcpy(&raw, (const char *) data->values + index * sizeof(raw),   \
                   sizeof(raw));                                              \
        } else {                                                              \
            size_t available = 0;                                            \
            const void *source = numeric_read_span(data, index, 1, &available);\
            if (available != 1) Rf_error("invalid compact numeric index");    \
            memcpy(&raw, source, sizeof(raw));                                \
        }                                                                     \
        return raw;                                                           \
    }                                                                         \
                                                                              \
    static double numeric_##NAME##_decode(                                   \
        TYPE raw, const numeric_data *data                                   \
    ) {                                                                      \
        int missing = MISSING_OFFSET(raw, data->format_version);             \
        return missing >= 0                                                  \
            ? numeric_missing_value(missing)                                 \
            : numeric_observed_value((double) raw, data->temporal);          \
    }                                                                        \
                                                                             \
    static double numeric_##NAME##_value_at(                                 \
        const numeric_data *data, size_t index                               \
    ) {                                                                      \
        return numeric_##NAME##_decode(                                      \
            numeric_##NAME##_raw_at(data, index), data                       \
        );                                                                   \
    }                                                                        \
                                                                             \
    static double numeric_##NAME##_scalar_value_at(                          \
        numeric_data *data, size_t index                                     \
    ) {                                                                      \
        TYPE raw;                                                            \
        if (!numeric_payload_retained(data)) {                               \
            memcpy(&raw, (const char *) data->values + index * sizeof(raw),  \
                   sizeof(raw));                                             \
        } else {                                                             \
            const void *source = numeric_scalar_span(                        \
                data, index, sizeof(raw)                                     \
            );                                                               \
            memcpy(&raw, source, sizeof(raw));                               \
        }                                                                    \
        return numeric_##NAME##_decode(raw, data);                           \
    }                                                                        \
                                                                             \
    static void numeric_##NAME##_region(                                      \
        const numeric_data *data, size_t index, size_t length, double *output \
    ) {                                                                       \
        if (data->missing_count == 0) {                                       \
            for (size_t offset = 0; offset < length; offset++) {              \
                if ((offset & 16383) == 0) R_CheckUserInterrupt();            \
                TYPE raw = numeric_##NAME##_raw_at(data, index + offset);     \
                output[offset] = numeric_observed_value(                      \
                    (double) raw, data->temporal                              \
                );                                                            \
            }                                                                 \
        } else {                                                              \
            for (size_t offset = 0; offset < length; offset++) {              \
                if ((offset & 16383) == 0) R_CheckUserInterrupt();            \
                output[offset] = numeric_##NAME##_value_at(                   \
                    data, index + offset                                      \
                );                                                            \
            }                                                                 \
        }                                                                     \
    }                                                                         \
                                                                              \
    static void numeric_##NAME##_extreme_accumulate(                          \
        const numeric_data *data, Rboolean na_rm, int minimum,               \
        double *accumulator, int *initialized                                \
    ) {                                                                       \
        double current = *accumulator;                                       \
        int updated = *initialized;                                          \
        if (data->missing_count == 0) {                                       \
            size_t first = 0;                                                 \
            if (!updated && data->length != 0) {                             \
                TYPE raw = numeric_##NAME##_raw_at(data, 0);                 \
                current = numeric_observed_value((double) raw, data->temporal);\
                updated = 1;                                                  \
                first = 1;                                                    \
            }                                                                 \
            for (size_t index = first; index < data->length; index++) {       \
                if ((index & 16383) == 0) R_CheckUserInterrupt();             \
                TYPE raw = numeric_##NAME##_raw_at(data, index);              \
                double element = numeric_observed_value(                     \
                    (double) raw, data->temporal                              \
                );                                                            \
                if (minimum ? element < current : element > current) {        \
                    current = element;                                        \
                }                                                             \
            }                                                                 \
        } else {                                                              \
            for (size_t index = 0; index < data->length; index++) {           \
                if ((index & 16383) == 0) R_CheckUserInterrupt();             \
                double element = numeric_##NAME##_value_at(data, index);      \
                if (ISNAN(element)) {                                         \
                    if (!na_rm) {                                             \
                        if (!ISNA(current)) current = element;                \
                        updated = 1;                                          \
                    }                                                         \
                } else if (!updated ||                                        \
                           (minimum ? element < current : element > current)) {\
                    current = element;                                        \
                    updated = 1;                                              \
                }                                                             \
            }                                                                 \
        }                                                                     \
        *accumulator = current;                                               \
        *initialized = updated;                                               \
    }                                                                         \
                                                                              \
    static int numeric_##NAME##_extreme(                                      \
        const numeric_data *data, Rboolean na_rm, int minimum, double *result \
    ) {                                                                       \
        double current = 0.0;                                                 \
        int updated = 0;                                                      \
        numeric_##NAME##_extreme_accumulate(data, na_rm, minimum, &current, &updated);\
        if (updated) *result = current;                                       \
        return updated;                                                       \
    }

DEFINE_NUMERIC_KERNELS(byte, int8_t, byte_missing_offset)
DEFINE_NUMERIC_KERNELS(int, int16_t, int_missing_offset)
DEFINE_NUMERIC_KERNELS(long, int32_t, long_missing_offset)
DEFINE_NUMERIC_KERNELS(float, float, float_missing_offset)

#undef DEFINE_NUMERIC_KERNELS


/* A sum keeps one ordered accumulator across every block and span. Direct
   typed loads avoid scalar decode dispatch; invariant missingness and temporal
   policies select the loop before it starts. Independent partial sums would
   change rounding, so these loops deliberately do not reassociate addition. */
#define NUMERIC_SUM_ROWS(TYPE, PREPARE, VALUE)                               \
    do {                                                                    \
        for (size_t start = 0; start < data->length; ) {                      \
            size_t count = data->length - start;                             \
            if (count > 65536) count = 65536;                                \
            if (data->length >= 16384) R_CheckUserInterrupt();               \
            for (size_t i = start; i < start + count; i++) {                 \
                TYPE raw;                                                   \
                memcpy(&raw, bytes + i * sizeof(raw), sizeof(raw));         \
                PREPARE                                                     \
                double element = (VALUE);                                   \
                sum += element;                                             \
            }                                                               \
            start += count;                                                 \
        }                                                                   \
    } while (0)

#define NUMERIC_SUM_OBSERVED(VALUE) (VALUE)
#define NUMERIC_SUM_DECODED(VALUE)                                           \
    (missing >= 0 ? numeric_missing_value(missing) : (VALUE))

#define NUMERIC_SUM_TEMPORAL(TYPE, PREPARE, DECODE)                           \
    do {                                                                    \
        if (temporal == 1) {                                                 \
            NUMERIC_SUM_ROWS(TYPE, PREPARE, DECODE((double) raw - 3653.0));   \
        } else if (temporal == 2) {                                          \
            NUMERIC_SUM_ROWS(TYPE, PREPARE,                                  \
                             DECODE((double) raw / 1000.0 - 315619200.0));   \
        } else {                                                            \
            NUMERIC_SUM_ROWS(TYPE, PREPARE, DECODE((double) raw));           \
        }                                                                   \
    } while (0)

#define DEFINE_NUMERIC_SUM(NAME, TYPE, MISSING_OFFSET, FAST_OBSERVED)        \
    static void numeric_##NAME##_sum_accumulate(                             \
        const numeric_data *data, Rboolean na_rm, long double *accumulator   \
    ) {                                                                     \
        const unsigned char *bytes = data->values;                           \
        int temporal = data->temporal;                                      \
        long double sum = *accumulator;                                      \
        if (data->missing_count == 0) {                                      \
            NUMERIC_SUM_TEMPORAL(TYPE, (void) 0;, NUMERIC_SUM_OBSERVED);     \
        } else if (na_rm) {                                                 \
            if (data->format_version <= 111) {                               \
                NUMERIC_SUM_TEMPORAL(TYPE,                                  \
                    if (!(FAST_OBSERVED) &&                                 \
                        (MISSING_OFFSET(raw, 111) >= 0 ||                    \
                         isnan((double) raw))) continue;,                   \
                    NUMERIC_SUM_OBSERVED);                                  \
            } else {                                                        \
                NUMERIC_SUM_TEMPORAL(TYPE,                                  \
                    if (!(FAST_OBSERVED) &&                                 \
                        (MISSING_OFFSET(raw, 119) >= 0 ||                    \
                         isnan((double) raw))) continue;,                   \
                    NUMERIC_SUM_OBSERVED);                                  \
            }                                                               \
        } else if (data->format_version <= 111) {                            \
            NUMERIC_SUM_TEMPORAL(TYPE,                                      \
                int missing = MISSING_OFFSET(raw, 111);, NUMERIC_SUM_DECODED);\
        } else {                                                            \
            NUMERIC_SUM_TEMPORAL(TYPE,                                      \
                int missing = MISSING_OFFSET(raw, 119);, NUMERIC_SUM_DECODED);\
        }                                                                   \
        *accumulator = sum;                                                  \
    }

DEFINE_NUMERIC_SUM(byte, int8_t, byte_missing_offset, 0)
DEFINE_NUMERIC_SUM(int, int16_t, int_missing_offset, 0)
DEFINE_NUMERIC_SUM(long, int32_t, long_missing_offset, 0)
/* Every Stata float missing code is at least 2^127. An ordered comparison
   excludes either NaN sign; ordinary values and negative infinity need no
   further predicate. Large positive values retain the full format check. */
DEFINE_NUMERIC_SUM(float, float, float_missing_offset, raw < 0x1p127f)

#undef DEFINE_NUMERIC_SUM
#undef NUMERIC_SUM_TEMPORAL
#undef NUMERIC_SUM_DECODED
#undef NUMERIC_SUM_OBSERVED
#undef NUMERIC_SUM_ROWS

static double numeric_value_at(const numeric_data *data, size_t index) {
    switch (data->kind) {
    case NUMERIC_BYTE:
        return numeric_byte_value_at(data, index);
    case NUMERIC_INT:
        return numeric_int_value_at(data, index);
    case NUMERIC_LONG:
        return numeric_long_value_at(data, index);
    case NUMERIC_FLOAT:
        return numeric_float_value_at(data, index);
    default:
        Rf_error("invalid dtatools numeric storage kind");
    }
}

int numeric_missing_offset_at(
    const numeric_data *data, size_t index
) {
    switch (data->kind) {
    case NUMERIC_BYTE:
        return byte_missing_offset(
            numeric_byte_raw_at(data, index), data->format_version
        );
    case NUMERIC_INT:
        return int_missing_offset(
            numeric_int_raw_at(data, index), data->format_version
        );
    case NUMERIC_LONG:
        return long_missing_offset(
            numeric_long_raw_at(data, index), data->format_version
        );
    case NUMERIC_FLOAT:
        return float_missing_offset(
            numeric_float_raw_at(data, index), data->format_version
        );
    default:
        Rf_error("invalid dtatools numeric storage kind");
    }
}

int numeric_value_is_missing_at(
    const numeric_data *data, size_t index
) {
    if (numeric_missing_offset_at(data, index) >= 0) return 1;
    return data->kind == NUMERIC_FLOAT &&
        isnan(numeric_float_raw_at(data, index));
}

/* Missingness needs only storage codes, never decoded doubles. Select the
   representation once per contiguous span; keep R dispatch and interrupt
   checks outside the vectorizable byte loops. The caller roots a descriptor
   snapshot and its backing before allocating the output. */
typedef struct {
    int *output;
    int combine;
    size_t added;
} numeric_missing_mask_context;

#define NUMERIC_MISSING_MASK_LOOP(TYPE, MISSING)                             \
    do {                                                                    \
        const unsigned char *restrict bytes = span->values;                 \
        int *restrict output = context->output + offset;                    \
        for (size_t start = 0; start < span->length; ) {                      \
            size_t count = span->length - start;                             \
            if (count > 65536) count = 65536;                                \
            if (span->length >= 16384) R_CheckUserInterrupt();               \
            if (context->combine) {                                         \
                size_t added = 0;                                           \
                for (size_t i = start; i < start + count; i++) {             \
                    TYPE raw;                                               \
                    memcpy(&raw, bytes + i * sizeof(raw), sizeof(raw));     \
                    int missing = (MISSING);                                \
                    int previous = output[i];                               \
                    output[i] = previous | missing;                         \
                    added += (size_t) (missing & !previous);                \
                }                                                           \
                context->added += added;                                    \
            } else {                                                        \
                for (size_t i = start; i < start + count; i++) {             \
                    TYPE raw;                                               \
                    memcpy(&raw, bytes + i * sizeof(raw), sizeof(raw));     \
                    output[i] = (MISSING);                                  \
                }                                                           \
            }                                                               \
            start += count;                                                 \
        }                                                                   \
    } while (0)

static void numeric_missing_mask_span(
    const numeric_data *span, size_t offset, void *raw_context
) {
    numeric_missing_mask_context *context = raw_context;
    int legacy = span->format_version <= 111;
    switch (span->kind) {
    case NUMERIC_BYTE:
        if (legacy) NUMERIC_MISSING_MASK_LOOP(int8_t, raw == INT8_C(127));
        else NUMERIC_MISSING_MASK_LOOP(int8_t, raw >= INT8_C(101));
        break;
    case NUMERIC_INT:
        if (legacy) NUMERIC_MISSING_MASK_LOOP(int16_t, raw == INT16_C(32767));
        else NUMERIC_MISSING_MASK_LOOP(int16_t, raw >= INT16_C(32741));
        break;
    case NUMERIC_LONG:
        if (legacy) NUMERIC_MISSING_MASK_LOOP(int32_t, raw == INT32_MAX);
        else NUMERIC_MISSING_MASK_LOOP(int32_t, raw >= INT32_C(2147483621));
        break;
    case NUMERIC_FLOAT:
        if (legacy) {
            NUMERIC_MISSING_MASK_LOOP(uint32_t,
                (raw >= UINT32_C(0x7f000000) && raw < UINT32_C(0x80000000)) |
                ((raw & UINT32_C(0x7fffffff)) > UINT32_C(0x7f800000)));
        } else {
            NUMERIC_MISSING_MASK_LOOP(uint32_t,
                (raw >= UINT32_C(0x7f000000) && raw <= UINT32_C(0x7f00d000) &&
                 (raw & UINT32_C(0x000007ff)) == 0) |
                ((raw & UINT32_C(0x7fffffff)) > UINT32_C(0x7f800000)));
        }
        break;
    default:
        Rf_error("invalid dtatools numeric storage kind");
    }
}
#undef NUMERIC_MISSING_MASK_LOOP

/* combine=0 writes a fresh mask; combine=1 ORs into an existing 0/1 mask and
   returns the number of newly missing rows for argument-level short circuit. */
size_t numeric_missing_mask(const numeric_data *data, int *output, int combine) {
    numeric_missing_mask_context context = {output, combine, 0};
    numeric_for_each_span(data, 0, data->length, numeric_missing_mask_span, &context);
    return context.added;
}

static size_t numeric_count_missing(const numeric_data *data) {
    size_t count = 0;
    for (size_t index = 0; index < data->length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        if (numeric_value_is_missing_at(data, index)) count++;
    }
    return count;
}



/* Retain the allocation behind a native read pointer across later R callbacks.
   Retaining only an ALTREP handle is insufficient if the callback changes its
   data1/data2 state. This function neither copies nor marks backing shared. */
SEXP numeric_payload_root(SEXP value) {
    if (owned_column(value)) return owned_values(value);
    if (unmaterialized_numeric_read_storage(value) != NULL) {
        SEXP source = numeric_base_source(value);
        /* A private handle cannot be materialized or cleared by a callback
           that holds the public vector. It also retains frozen R raw roots. */
        if (numeric_payload_retained(numeric_read_storage(source)))
            return numeric_handle_copy(source);
        return R_ExternalPtrProtected(R_altrep_data1(source));
    }
    if (ALTREP(value) && R_altrep_data2(value) != R_NilValue) return R_altrep_data2(value);
    return value;
}

/* Retaining an immutable owner's bytes creates a distinct native owner.
   Derive its descriptor only after the private handle has captured it: an
   allocation callback may materialize the public handle during capture. For
   plain backing, the raw allocation root keeps the entry descriptor valid. */
SEXP numeric_missing_mask_capture(SEXP value, numeric_data *storage) {
    SEXP source = numeric_base_source(value);
    if (source == R_NilValue) return R_NilValue;
    numeric_data entry = *numeric_read_storage(source);
    SEXP root = numeric_payload_root(source);
    *storage = numeric_payload_retained(&entry)
        ? *numeric_read_storage(root) : entry;
    return root;
}

numeric_reader numeric_reader_create(
    SEXP value, R_xlen_t expected_length
) {
    /* Callers that keep this reader across callbacks must also protect
       numeric_payload_root(value). Snapshot the descriptor because public
       handle materialization can free it even while its backing is rooted. */
    numeric_reader reader = {
        value, NULL, NULL, NULL, TYPEOF(value)
    };
    if (reader.type == REALSXP) {
        reader.storage = unmaterialized_numeric_read_storage(value);
        if (reader.storage != NULL) {
            numeric_data encoding = *reader.storage;
            reader.storage = (numeric_data *) R_alloc(1, sizeof(numeric_data));
            *reader.storage = encoding;
        }
        if (reader.storage != NULL &&
            (R_xlen_t) reader.storage->length != expected_length) {
            Rf_error(
                "dtatools numeric storage length does not match vector length"
            );
        } else if (reader.storage == NULL) {
            reader.real_values = (const double *) DATAPTR_OR_NULL(value);
        }
    } else if (reader.type == INTSXP || reader.type == LGLSXP) {
        reader.integer_values = (const int *) DATAPTR_OR_NULL(value);
    } else {
        Rf_error(
            "internal numeric grouping requires doubles, integers, or logicals"
        );
    }
    return reader;
}

static double numeric_integer_value(int value, int *missing_code) {
    if (value == NA_INTEGER) {
        *missing_code = 0;
        return 0.0;
    }
    *missing_code = -1;
    return (double) value;
}

static double numeric_real_value(double value, int *missing_code) {
    if (!ISNAN(value)) {
        *missing_code = -1;
        return value;
    }
    int payload_tag = tagged_na_tag_value(value);
    int tag = payload_tag >= 'a' && payload_tag <= 'z' ? payload_tag : 0;
    *missing_code = tag != 0
        ? tag : (payload_tag != 0 ? 256 : (ISNA(value) ? 0 : 256));
    return 0.0;
}

typedef struct {
    double *values;
    int *codes;
} numeric_reader_region_context;

/* Dispatch storage, historical missing encoding, and temporal conversion
   outside the loop. The same contiguous loop serves plain and retained
   backing; retained owners are consulted once per span, never per row. */
#define NUMERIC_READER_ROWS(TYPE, MISSING, VALUE, STORE)                      \
    do {                                                                    \
        for (size_t begin = 0; begin < span->length; ) {                     \
            size_t count = span->length - begin;                            \
            if (count > 65536) count = 65536;                               \
            if (span->length >= 16384) R_CheckUserInterrupt();              \
            for (size_t i = begin; i < begin + count; i++) {                \
                TYPE raw;                                                   \
                memcpy(&raw, bytes + i * sizeof(raw), sizeof(raw));        \
                int missing = (MISSING);                                   \
                int code = missing >= 0                                   \
                    ? (missing == 0 ? 0 : 'a' + missing - 1)               \
                    : (ISNAN((double) raw) ? 256 : -1);                    \
                codes[i] = code;                                           \
                STORE                                                       \
            }                                                               \
            begin += count;                                                 \
        }                                                                   \
    } while (0)

/* VALUE is substituted at this macro level before entering the row macro. */
#define NUMERIC_READER_VALUES(TYPE, MISSING, VALUE)                          \
    NUMERIC_READER_ROWS(TYPE, MISSING, VALUE,                                \
                       values[i] = code < 0 ? (VALUE) : 0.0;)

#define NUMERIC_READER_TEMPORAL(TYPE, MISSING)                               \
    do {                                                                    \
        if (values == NULL) {                                               \
            NUMERIC_READER_ROWS(TYPE, MISSING, 0, (void) 0;);               \
        } else if (span->temporal == 1) {                                   \
            NUMERIC_READER_VALUES(TYPE, MISSING, (double) raw - 3653.0);   \
        } else if (span->temporal == 2) {                                   \
            NUMERIC_READER_VALUES(TYPE, MISSING,                            \
                (double) raw / 1000.0 - 315619200.0);                       \
        } else {                                                            \
            NUMERIC_READER_VALUES(TYPE, MISSING, (double) raw);            \
        }                                                                   \
    } while (0)

static void numeric_reader_decode_span(
    const numeric_data *span, size_t offset, void *raw_context
) {
    numeric_reader_region_context *context = raw_context;
    double *values = context->values == NULL ? NULL : context->values + offset;
    int *codes = context->codes + offset;
    const unsigned char *bytes = span->values;
    int legacy = span->format_version <= 111;
    switch (span->kind) {
    case NUMERIC_BYTE:
        if (legacy) NUMERIC_READER_TEMPORAL(int8_t, byte_missing_offset(raw, 111));
        else NUMERIC_READER_TEMPORAL(int8_t, byte_missing_offset(raw, 119));
        break;
    case NUMERIC_INT:
        if (legacy) NUMERIC_READER_TEMPORAL(int16_t, int_missing_offset(raw, 111));
        else NUMERIC_READER_TEMPORAL(int16_t, int_missing_offset(raw, 119));
        break;
    case NUMERIC_LONG:
        if (legacy) NUMERIC_READER_TEMPORAL(int32_t, long_missing_offset(raw, 111));
        else NUMERIC_READER_TEMPORAL(int32_t, long_missing_offset(raw, 119));
        break;
    case NUMERIC_FLOAT:
        if (legacy) NUMERIC_READER_TEMPORAL(float, float_missing_offset(raw, 111));
        else NUMERIC_READER_TEMPORAL(float, float_missing_offset(raw, 119));
        break;
    default:
        Rf_error("invalid dtatools numeric storage kind");
    }
}
#undef NUMERIC_READER_TEMPORAL
#undef NUMERIC_READER_VALUES
#undef NUMERIC_READER_ROWS

void numeric_reader_region(
    const numeric_reader *reader, R_xlen_t start, R_xlen_t length,
    double *values, int *missing_codes
) {
    R_xlen_t total = reader->storage != NULL
        ? (R_xlen_t) reader->storage->length : XLENGTH(reader->value);
    if (start < 0 || length < 0 || start > total || length > total - start)
        Rf_error("invalid numeric reader region");
    if (reader->storage != NULL) {
        numeric_reader_region_context context = {values, missing_codes};
        numeric_for_each_span(reader->storage, (size_t) start, (size_t) length,
                              numeric_reader_decode_span, &context);
        return;
    }
    if (reader->real_values != NULL) {
        const double *input = reader->real_values + start;
        for (R_xlen_t i = 0; i < length; i++) {
            if ((i & 16383) == 0 && length >= 16384) R_CheckUserInterrupt();
            double value = numeric_real_value(input[i], missing_codes + i);
            if (values != NULL) values[i] = value;
        }
        return;
    }
    if (reader->integer_values != NULL) {
        const int *input = reader->integer_values + start;
        for (R_xlen_t i = 0; i < length; i++) {
            if ((i & 16383) == 0 && length >= 16384) R_CheckUserInterrupt();
            double value = numeric_integer_value(input[i], missing_codes + i);
            if (values != NULL) values[i] = value;
        }
        return;
    }
    /* Unknown ALTREP providers keep their scalar callback order. */
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0 && length >= 16384) R_CheckUserInterrupt();
        double value = numeric_reader_at(reader, start + i, missing_codes + i);
        if (values != NULL) values[i] = value;
    }
}

double numeric_reader_at(
    const numeric_reader *reader, R_xlen_t index, int *missing_code
) {
    if (reader->storage != NULL) {
        /* Decode once. Separate missing/value probes would each find and
           fetch the same retained span for every observed scalar. */
        return numeric_real_value(
            numeric_value_at(reader->storage, (size_t) index), missing_code
        );
    }

    if (reader->type == INTSXP || reader->type == LGLSXP) {
        int value = reader->integer_values == NULL
            ? (reader->type == LGLSXP
                ? LOGICAL_ELT(reader->value, index)
                : INTEGER_ELT(reader->value, index))
            : reader->integer_values[index];
        return numeric_integer_value(value, missing_code);
    }

    double value = reader->real_values == NULL
        ? REAL_ELT(reader->value, index)
        : reader->real_values[index];
    return numeric_real_value(value, missing_code);
}

static double reference_row_reads = 0.0;
static int reference_row_reads_enabled = 0;
/* Test control. Disarm before entering R's native interrupt handler. CRT
   SIGINT delivery can terminate Windows R instead of unwinding its contexts. */
static int reference_write_interrupt_enabled = 0;

void record_reference_row_read(void) {
    if (reference_row_reads_enabled) reference_row_reads += 1.0;
}

SEXP C_dtatools_reference_row_reads(SEXP enabled) {
    int value = Rf_asLogical(enabled);
    if (value == NA_LOGICAL) {
        Rf_error("invalid reference row-read counter state");
    }
    if (value) {
        reference_row_reads = 0.0;
        reference_row_reads_enabled = 1;
        return Rf_ScalarReal(0.0);
    }
    reference_row_reads_enabled = 0;
    return Rf_ScalarReal(reference_row_reads);
}

SEXP C_dtatools_inject_reference_write_interrupt(SEXP enabled) {
    int value = Rf_asLogical(enabled);
    if (value == NA_LOGICAL) {
        Rf_error("invalid reference write-interrupt state");
    }
    int previous = reference_write_interrupt_enabled;
    reference_write_interrupt_enabled = value;
    return Rf_ScalarLogical(previous);
}

void maybe_inject_reference_write_interrupt(void) {
    if (!reference_write_interrupt_enabled) return;
    reference_write_interrupt_enabled = 0;
    Rf_onintr();
    Rf_error("failed to inject reference write interrupt");
}

SEXP C_dtatools_mutation_rows(SEXP value, SEXP row_count_value) {
    double row_count_double = Rf_asReal(row_count_value);
    if (!R_FINITE(row_count_double) || row_count_double < 0 ||
        row_count_double != trunc(row_count_double) ||
        row_count_double > (double) INT_MAX) {
        Rf_error("invalid reference mutation row count");
    }
    R_xlen_t row_count = (R_xlen_t) row_count_double;
    R_xlen_t length = XLENGTH(value);

    if (TYPEOF(value) == LGLSXP) {
        if (length == 1) {
            return LOGICAL_ELT(value, 0) == 1
                ? R_NilValue : Rf_allocVector(INTSXP, 0);
        }
        if (length != row_count) {
            Rf_error(
                "`where` has size %lld; expected size 1 or %lld",
                (long long) length, (long long) row_count
            );
        }
        R_xlen_t selected = 0;
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            if (LOGICAL_ELT(value, index) == 1) selected++;
        }
        if (selected == row_count) return R_NilValue;
        if (selected == 0) return Rf_allocVector(INTSXP, 0);
        SEXP result = PROTECT(Rf_allocVector(INTSXP, selected));
        R_xlen_t output = 0;
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            if (LOGICAL_ELT(value, index) == 1) {
                INTEGER(result)[output++] = (int) index + 1;
            }
        }
        UNPROTECT(1);
        return result;
    }

    if (TYPEOF(value) != INTSXP && TYPEOF(value) != REALSXP) {
        Rf_error("invalid reference mutation row selector");
    }
    if (TYPEOF(value) == INTSXP) {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            record_reference_row_read();
            int row = INTEGER_ELT(value, index);
            if (row == NA_INTEGER || row <= 0 ||
                (R_xlen_t) row > row_count) {
                Rf_error(
                    "`where` row positions must be positive, finite, whole, "
                    "and no greater than the row count"
                );
            }
        }
        return value;
    }

    numeric_reader reader = numeric_reader_create(value, length);
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        record_reference_row_read();
        int missing_code;
        double row = numeric_reader_at(&reader, index, &missing_code);
        if (missing_code >= 0 || !R_FINITE(row) || row != trunc(row) ||
            row <= 0 || row > row_count || row > (double) INT_MAX) {
            Rf_error(
                "`where` row positions must be positive, finite, whole, "
                "and no greater than the row count"
            );
        }
    }
    return value;
}



#define DTATOOLS_LAYOUT_ASSERT(name, condition) \
    typedef char dtatools_layout_assert_##name[(condition) ? 1 : -1]

#if UINTPTR_MAX == UINT64_MAX
DTATOOLS_LAYOUT_ASSERT(compare_owner, offsetof(dtatools_compare_operand, native_owner) == 24);
DTATOOLS_LAYOUT_ASSERT(compare_size, sizeof(dtatools_compare_operand) == 32);
DTATOOLS_LAYOUT_ASSERT(gather_x_owner, offsetof(numeric_gather_column, x_owner) == 64);
DTATOOLS_LAYOUT_ASSERT(gather_y_owner, offsetof(numeric_gather_column, y_owner) == 72);
DTATOOLS_LAYOUT_ASSERT(gather_x_length, offsetof(numeric_gather_column, x_length) == 80);
DTATOOLS_LAYOUT_ASSERT(gather_size, sizeof(numeric_gather_column) == 96);
DTATOOLS_LAYOUT_ASSERT(numeric_owner, offsetof(numeric_data, native_owner) == 40);
DTATOOLS_LAYOUT_ASSERT(numeric_scalar_values, offsetof(numeric_data, scalar_values) == 48);
DTATOOLS_LAYOUT_ASSERT(numeric_scalar_start, offsetof(numeric_data, scalar_start) == 56);
DTATOOLS_LAYOUT_ASSERT(numeric_scalar_end, offsetof(numeric_data, scalar_end) == 64);
DTATOOLS_LAYOUT_ASSERT(numeric_size, sizeof(numeric_data) == 72);
DTATOOLS_LAYOUT_ASSERT(write_column_name, offsetof(dtatools_write_column, name) == 0);
DTATOOLS_LAYOUT_ASSERT(write_column_dta_type, offsetof(dtatools_write_column, dta_type) == 8);
DTATOOLS_LAYOUT_ASSERT(write_column_format, offsetof(dtatools_write_column, format) == 16);
DTATOOLS_LAYOUT_ASSERT(write_column_label, offsetof(dtatools_write_column, label) == 24);
DTATOOLS_LAYOUT_ASSERT(write_column_numeric_values, offsetof(dtatools_write_column, numeric_values) == 32);
DTATOOLS_LAYOUT_ASSERT(write_column_string_values, offsetof(dtatools_write_column, string_values) == 40);
DTATOOLS_LAYOUT_ASSERT(write_column_value_label_index, offsetof(dtatools_write_column, value_label_index) == 48);
DTATOOLS_LAYOUT_ASSERT(write_column_dta_metadata, offsetof(dtatools_write_column, dta_metadata) == 56);
DTATOOLS_LAYOUT_ASSERT(write_column_numeric_shift, offsetof(dtatools_write_column, numeric_shift) == 64);
DTATOOLS_LAYOUT_ASSERT(write_column_numeric_scale, offsetof(dtatools_write_column, numeric_scale) == 72);
DTATOOLS_LAYOUT_ASSERT(write_column_direct_values, offsetof(dtatools_write_column, direct_numeric_values) == 80);
DTATOOLS_LAYOUT_ASSERT(write_column_direct_kind, offsetof(dtatools_write_column, direct_numeric_kind) == 88);
DTATOOLS_LAYOUT_ASSERT(write_column_direct_version, offsetof(dtatools_write_column, direct_numeric_format_version) == 92);
DTATOOLS_LAYOUT_ASSERT(write_column_direct_temporal, offsetof(dtatools_write_column, direct_numeric_temporal) == 96);
DTATOOLS_LAYOUT_ASSERT(write_column_direct_no_na, offsetof(dtatools_write_column, direct_numeric_no_na) == 100);
DTATOOLS_LAYOUT_ASSERT(write_column_direct_string, offsetof(dtatools_write_column, direct_string_data) == 104);
DTATOOLS_LAYOUT_ASSERT(write_column_direct_owner, offsetof(dtatools_write_column, direct_numeric_owner) == 112);
DTATOOLS_LAYOUT_ASSERT(write_column_size, sizeof(dtatools_write_column) == 120);
DTATOOLS_LAYOUT_ASSERT(write_table_name, offsetof(dtatools_write_value_label_table, name) == 0);
DTATOOLS_LAYOUT_ASSERT(write_table_values, offsetof(dtatools_write_value_label_table, label_values) == 8);
DTATOOLS_LAYOUT_ASSERT(write_table_texts, offsetof(dtatools_write_value_label_table, label_texts) == 16);
DTATOOLS_LAYOUT_ASSERT(write_table_count, offsetof(dtatools_write_value_label_table, label_count) == 24);
DTATOOLS_LAYOUT_ASSERT(write_table_size, sizeof(dtatools_write_value_label_table) == 32);
DTATOOLS_LAYOUT_ASSERT(arrow_column_name, offsetof(dtatools_arrow_column, name) == 0);
DTATOOLS_LAYOUT_ASSERT(arrow_column_kind, offsetof(dtatools_arrow_column, kind) == 8);
DTATOOLS_LAYOUT_ASSERT(arrow_column_label, offsetof(dtatools_arrow_column, label) == 16);
DTATOOLS_LAYOUT_ASSERT(arrow_column_format, offsetof(dtatools_arrow_column, format) == 24);
DTATOOLS_LAYOUT_ASSERT(arrow_column_storage, offsetof(dtatools_arrow_column, storage) == 32);
DTATOOLS_LAYOUT_ASSERT(arrow_column_string_storage, offsetof(dtatools_arrow_column, string_storage) == 36);
DTATOOLS_LAYOUT_ASSERT(arrow_column_ordered, offsetof(dtatools_arrow_column, ordered) == 40);
DTATOOLS_LAYOUT_ASSERT(arrow_column_tz, offsetof(dtatools_arrow_column, tz) == 48);
DTATOOLS_LAYOUT_ASSERT(arrow_column_units, offsetof(dtatools_arrow_column, units) == 56);
DTATOOLS_LAYOUT_ASSERT(arrow_column_values, offsetof(dtatools_arrow_column, values) == 64);
DTATOOLS_LAYOUT_ASSERT(arrow_column_strings, offsetof(dtatools_arrow_column, strings) == 72);
DTATOOLS_LAYOUT_ASSERT(arrow_column_string_count, offsetof(dtatools_arrow_column, string_count) == 80);
DTATOOLS_LAYOUT_ASSERT(arrow_column_compact_values, offsetof(dtatools_arrow_column, compact_values) == 88);
DTATOOLS_LAYOUT_ASSERT(arrow_column_compact_kind, offsetof(dtatools_arrow_column, compact_kind) == 96);
DTATOOLS_LAYOUT_ASSERT(arrow_column_compact_version, offsetof(dtatools_arrow_column, compact_format_version) == 100);
DTATOOLS_LAYOUT_ASSERT(arrow_column_compact_temporal, offsetof(dtatools_arrow_column, compact_temporal) == 104);
DTATOOLS_LAYOUT_ASSERT(arrow_column_value_label_index, offsetof(dtatools_arrow_column, value_label_index) == 108);
DTATOOLS_LAYOUT_ASSERT(arrow_column_dta_metadata, offsetof(dtatools_arrow_column, dta_metadata) == 112);
DTATOOLS_LAYOUT_ASSERT(arrow_column_haven_labelled, offsetof(dtatools_arrow_column, haven_labelled) == 120);
DTATOOLS_LAYOUT_ASSERT(arrow_column_dictstring, offsetof(dtatools_arrow_column, dictstring) == 128);
DTATOOLS_LAYOUT_ASSERT(arrow_column_compact_owner, offsetof(dtatools_arrow_column, compact_owner) == 136);
DTATOOLS_LAYOUT_ASSERT(arrow_column_size, sizeof(dtatools_arrow_column) == 144);
DTATOOLS_LAYOUT_ASSERT(arrow_table_name, offsetof(dtatools_arrow_value_label_table, name) == 0);
DTATOOLS_LAYOUT_ASSERT(arrow_table_values, offsetof(dtatools_arrow_value_label_table, label_values) == 8);
DTATOOLS_LAYOUT_ASSERT(arrow_table_texts, offsetof(dtatools_arrow_value_label_table, label_texts) == 16);
DTATOOLS_LAYOUT_ASSERT(arrow_table_count, offsetof(dtatools_arrow_value_label_table, label_count) == 24);
DTATOOLS_LAYOUT_ASSERT(arrow_table_size, sizeof(dtatools_arrow_value_label_table) == 32);
#endif

int write_string_utf8_status(SEXP value) {
    int utf8 = Rf_getCharCE(value) == CE_UTF8;
    int ascii = 1;
    const unsigned char *bytes = (const unsigned char *) CHAR(value);
    int length = LENGTH(value);
    for (int index = 0; index < length; index++) {
        if (bytes[index] == 0) return -1;
        if (bytes[index] > 0x7f) ascii = 0;
    }
    return utf8 || ascii;
}

typedef struct {
    void (*function)(void *);
    void *data;
    int status;
    char *error_message;
    size_t error_capacity;
} write_callback_exec_context;

static SEXP write_callback_body(void *data) {
    write_callback_exec_context *context = (
        write_callback_exec_context *
    ) data;
    context->function(context->data);
    context->status = 1;
    return R_NilValue;
}

static void write_callback_copy_condition(
    write_callback_exec_context *context, SEXP condition
) {
    if (context->error_message == NULL || context->error_capacity == 0) return;
    context->error_message[0] = '\0';

    SEXP call = PROTECT(Rf_lang2(Rf_install("conditionMessage"), condition));
    int failed = 0;
    SEXP result = R_tryEval(call, R_BaseEnv, &failed);
    if (!failed) {
        PROTECT(result);
        if (TYPEOF(result) == STRSXP && XLENGTH(result) >= 1 &&
            STRING_ELT(result, 0) != NA_STRING) {
            const char *message = Rf_translateCharUTF8(
                STRING_ELT(result, 0)
            );
            size_t length = strlen(message);
            if (length >= context->error_capacity) {
                length = context->error_capacity - 1;
            }
            memcpy(context->error_message, message, length);
            context->error_message[length] = '\0';
        }
        UNPROTECT(1);
    }
    UNPROTECT(1);
}

static SEXP write_callback_handler(SEXP condition, void *data) {
    write_callback_exec_context *context = (
        write_callback_exec_context *
    ) data;
    int interrupted = Rf_inherits(condition, "interrupt");
    context->status = interrupted ? -1 : 0;
    if (!interrupted) write_callback_copy_condition(context, condition);
    return R_NilValue;
}

static void write_callback_try_catch(void *data) {
    write_callback_exec_context *context = (
        write_callback_exec_context *
    ) data;
    R_tryCatch(
        write_callback_body, context, write_callback_condition_classes,
        write_callback_handler, context, NULL, NULL
    );
}

static int write_callback_exec(
    void (*function)(void *), void *data,
    char *error_message, size_t error_capacity
) {
    if (error_message != NULL && error_capacity > 0) error_message[0] = '\0';
    write_callback_exec_context context = {
        function, data, 0, error_message, error_capacity
    };
    return R_ToplevelExec(write_callback_try_catch, &context)
        ? context.status : 0;
}

typedef struct {
    const numeric_reader *reader;
    size_t start;
    size_t length;
    double *values;
    int *missing_codes;
    int success;
} write_numeric_region_context;

static void write_numeric_region_call(void *data) {
    write_numeric_region_context *context = (
        write_numeric_region_context *
    ) data;
    const numeric_reader *reader = context->reader;
    size_t available = (size_t) XLENGTH(reader->value);
    if (context->start > available ||
        context->length > available - context->start) {
        return;
    }
    if (reader->storage != NULL || reader->integer_values != NULL ||
        reader->real_values != NULL) {
        for (size_t offset = 0; offset < context->length; offset++) {
            context->values[offset] = numeric_reader_at(
                reader,
                (R_xlen_t) (context->start + offset),
                &context->missing_codes[offset]
            );
        }
        context->success = 1;
        return;
    }

    size_t total = 0;
    while (total < context->length) {
        R_xlen_t requested = (R_xlen_t) (context->length - total);
        R_xlen_t copied;
        if (reader->type == INTSXP) {
            copied = INTEGER_GET_REGION(
                reader->value,
                (R_xlen_t) (context->start + total),
                requested,
                context->missing_codes + total
            );
        } else if (reader->type == LGLSXP) {
            copied = LOGICAL_GET_REGION(
                reader->value,
                (R_xlen_t) (context->start + total),
                requested,
                context->missing_codes + total
            );
        } else {
            copied = REAL_GET_REGION(
                reader->value,
                (R_xlen_t) (context->start + total),
                requested,
                context->values + total
            );
        }
        if (copied <= 0 || copied > requested) return;
        total += (size_t) copied;
    }

    if (reader->type == INTSXP || reader->type == LGLSXP) {
        for (size_t offset = 0; offset < context->length; offset++) {
            context->values[offset] = numeric_integer_value(
                context->missing_codes[offset], &context->missing_codes[offset]
            );
        }
    } else {
        for (size_t offset = 0; offset < context->length; offset++) {
            context->values[offset] = numeric_real_value(
                context->values[offset], &context->missing_codes[offset]
            );
        }
    }
    context->success = 1;
}

int dtatools_write_numeric_region(
    const void *reader_pointer, size_t start, size_t length,
    double *values, int *missing_codes,
    char *error_message, size_t error_capacity
) {
    if (reader_pointer == NULL || values == NULL || missing_codes == NULL) {
        return 0;
    }
    const numeric_reader *reader = (const numeric_reader *) reader_pointer;
    write_numeric_region_context context = {
        reader, start, length, values, missing_codes, 0
    };
    int status = write_callback_exec(
        write_numeric_region_call, &context, error_message, error_capacity
    );
    return status == 1 ? context.success : status;
}

typedef struct {
    SEXP values;
    size_t start;
    size_t length;
    uint64_t *ids;
    const char **strings;
    size_t *string_lengths;
    int success;
} write_string_region_context;

static void write_string_region_call(void *data) {
    write_string_region_context *context =
        (write_string_region_context *) data;
    size_t available = (size_t) XLENGTH(context->values);
    if (context->start > available ||
        context->length > available - context->start) {
        return;
    }
    for (size_t offset = 0; offset < context->length; offset++) {
        SEXP element = STRING_ELT(
            context->values, (R_xlen_t) (context->start + offset)
        );
        if (context->ids != NULL) {
            context->ids[offset] = (uint64_t) (uintptr_t) element;
        }
        if (element == NA_STRING) {
            context->strings[offset] = NULL;
            context->string_lengths[offset] = 0;
        } else {
            context->strings[offset] = CHAR(element);
            context->string_lengths[offset] = (size_t) LENGTH(element);
        }
    }
    context->success = 1;
}

int dtatools_write_string_region(
    SEXP values, size_t start, size_t length, uint64_t *ids,
    const char **strings, size_t *string_lengths,
    char *error_message, size_t error_capacity
) {
    if (TYPEOF(values) != STRSXP || strings == NULL ||
        string_lengths == NULL) {
        return 0;
    }
    write_string_region_context context = {
        values, start, length, ids, strings, string_lengths, 0
    };
    int status = write_callback_exec(
        write_string_region_call, &context, error_message, error_capacity
    );
    return status == 1 ? context.success : status;
}

static SEXP write_string_plan_result(
    size_t maximum, double missing, SEXP values
) {
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 3));
    SEXP maximum_value = PROTECT(Rf_ScalarReal((double) maximum));
    SEXP missing_value = PROTECT(Rf_ScalarReal(missing));
    SET_VECTOR_ELT(result, 0, maximum_value);
    SET_VECTOR_ELT(result, 1, missing_value);
    SET_VECTOR_ELT(result, 2, values);
    UNPROTECT(3);
    return result;
}

/* Explicit string construction replaces the incoming class. Capture borrowed
   values even when that removable class is outside generic owned qualification.
   Existing compact dictionaries retain their separate copy-on-write contract. */
SEXP C_dtatools_capture_string(SEXP value) {
    if (TYPEOF(value) != STRSXP) Rf_error("string construction requires character values");
    if (unmaterialized_dictstring_source(value) != R_NilValue) return value;
    return owned_fork(value);
}

/* Complete callback-free, unnamed construction on one unpublished handle.
   Borrowed values are captured before metadata is removed; existing owned
   inputs still fork, retaining their real aliases. NULL declines cases whose
   names dispatch, prototype restoration or foreign readers belong to R's
   existing constructor path. Foreign reads could also change metadata after
   qualification. Never clear sharing on a published record. */
SEXP C_dtatools_construct_string(SEXP value, SEXP storage) {
    if (TYPEOF(value) != STRSXP || Rf_isS4(value) ||
        (ALTREP(value) && !owned_column(value)) ||
        Rf_getAttrib(value, R_NamesSymbol) != R_NilValue ||
        TYPEOF(storage) != STRSXP || ALTREP(storage) || ANY_ATTRIB(storage) ||
        XLENGTH(storage) != 1 || STRING_ELT(storage, 0) == NA_STRING ||
        unmaterialized_dictstring_source(value) != R_NilValue) return R_NilValue;
    SEXP result = PROTECT(owned_fork(value));
    Rf_setAttrib(result, R_ClassSymbol, R_NilValue);
    CLEAR_ATTRIB(result);
    Rf_setAttrib(result, Rf_install("stata.string.storage"), storage);
    SEXP classes = PROTECT(Rf_allocVector(STRSXP, 3));
    SET_STRING_ELT(classes, 0, Rf_mkChar("dta_string"));
    SET_STRING_ELT(classes, 1, Rf_mkChar("vctrs_vctr"));
    SET_STRING_ELT(classes, 2, Rf_mkChar("character"));
    Rf_setAttrib(result, R_ClassSymbol, classes);
    if (owned_flags(result)[OWNED_MAX_WIDTH] < 0 ||
        owned_flags(result)[OWNED_NO_NA] < 0) owned_scan_strings(result);
    UNPROTECT(2);
    return result;
}

SEXP C_dtatools_write_string_plan(SEXP value) {
    if (TYPEOF(value) != STRSXP) {
        Rf_error("internal string planning requires a character vector");
    }
    size_t maximum = 0;
    double missing = 0;
    SEXP normalized = R_NilValue;
    SEXP dictionary_source = unmaterialized_dictstring_source(value);
    if (dictionary_source != R_NilValue) {
        dictstring_data *data = dictstring_storage(dictionary_source);
        SEXP cache = dictstring_cache(dictionary_source);
        R_xlen_t value_count = XLENGTH(cache);
        for (R_xlen_t id = 0; id < value_count; id++) {
            if ((id & 16383) == 0) R_CheckUserInterrupt();
            const char *bytes = NULL;
            int length = 0;
            if (!dtatools_dictstring_bytes(
                    data, (uint32_t) id, &bytes, &length
                ) || bytes == NULL || length < 0) {
                Rf_error("invalid dtatools string-dictionary value");
            }
            if (memchr(bytes, 0, (size_t) length) != NULL) {
                Rf_error("character values cannot contain NUL bytes");
            }
            if ((uint64_t) length > UINT64_C(2000000000)) {
                Rf_error("a strL value exceeds Stata's 2,000,000,000-byte limit");
            }
            if ((size_t) length > maximum) maximum = (size_t) length;
        }
        return write_string_plan_result(maximum, 0, value);
    }
    /* Owned strings have stable ordinary storage. Read that allocation here,
       but return the tracked handle when no normalization is needed. Foreign
       ALTSTRING values still need the established materialization boundary. */
    SEXP source = PROTECT(owned_column(value) ? owned_values(value) : value);
    R_xlen_t length = XLENGTH(source);
    int materialize_altstring = ALTREP(source);
    if (materialize_altstring) {
        normalized = PROTECT(Rf_allocVector(STRSXP, length));
    }
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        SEXP element = STRING_ELT(source, index);
        if (materialize_altstring) PROTECT(element);
        if (element == NA_STRING) {
            missing += 1;
            if (normalized != R_NilValue) {
                SET_STRING_ELT(normalized, index, NA_STRING);
            }
            if (materialize_altstring) UNPROTECT(1);
            continue;
        }
        int utf8_status = write_string_utf8_status(element);
        if (utf8_status < 0) {
            Rf_error("character values cannot contain NUL bytes");
        }
        size_t bytes;
        if (utf8_status) {
            bytes = (size_t) LENGTH(element);
            if (normalized != R_NilValue) {
                SET_STRING_ELT(normalized, index, element);
            }
        } else {
            if (normalized == R_NilValue) {
                normalized = PROTECT(Rf_allocVector(STRSXP, length));
                for (R_xlen_t prior = 0; prior < index; prior++) {
                    SET_STRING_ELT(normalized, prior, STRING_ELT(source, prior));
                }
            }
            const char *translated = Rf_translateCharUTF8(element);
            bytes = strlen(translated);
            SET_STRING_ELT(normalized, index, Rf_mkCharCE(translated, CE_UTF8));
        }
        if (bytes > maximum) maximum = bytes;
        if (materialize_altstring) UNPROTECT(1);
    }
    if (maximum > UINT64_C(2000000000)) {
        Rf_error("a strL value exceeds Stata's 2,000,000,000-byte limit");
    }

    SEXP result = write_string_plan_result(
        maximum, missing, normalized == R_NilValue ? value : normalized
    );
    if (normalized != R_NilValue) UNPROTECT(1);
    UNPROTECT(1);
    return result;
}

typedef struct {
    uint64_t key;
    int id_plus_one;
} numeric_hash_entry;

typedef struct {
    double value;
    int old_id;
} numeric_level_entry;

typedef struct {
    SEXP value;
    SEXP seeds;
    int missing_mode;
    numeric_hash_entry *entries;
    size_t entry_capacity;
    uint64_t *keys;
    size_t key_capacity;
    size_t key_count;
    numeric_level_entry *levels;
} numeric_factor_context;

static uint64_t normalized_numeric_key(double value) {
    if (value == 0.0) return 0;
    uint64_t key;
    memcpy(&key, &value, sizeof(key));
    return key;
}

static uint64_t numeric_key_hash(uint64_t key) {
    key ^= key >> 33;
    key *= UINT64_C(0xff51afd7ed558ccd);
    key ^= key >> 33;
    key *= UINT64_C(0xc4ceb9fe1a85ec53);
    return key ^ (key >> 33);
}

static void numeric_hash_resize(
    numeric_factor_context *context, size_t capacity
) {
    if (capacity > SIZE_MAX / sizeof(numeric_hash_entry)) {
        Rf_error("too many distinct numeric factor levels");
    }
    numeric_hash_entry *entries = (numeric_hash_entry *) calloc(
        capacity, sizeof(numeric_hash_entry)
    );
    if (entries == NULL) Rf_error("failed to allocate numeric level index");

    free(context->entries);
    context->entries = entries;
    context->entry_capacity = capacity;
    for (size_t id = 0; id < context->key_count; id++) {
        if ((id & 16383) == 0) R_CheckUserInterrupt();
        uint64_t key = context->keys[id];
        size_t slot = (size_t) numeric_key_hash(key) & (capacity - 1);
        while (context->entries[slot].id_plus_one != 0) {
            slot = (slot + 1) & (capacity - 1);
        }
        context->entries[slot].key = key;
        context->entries[slot].id_plus_one = (int) id + 1;
    }
}

static void numeric_keys_grow(numeric_factor_context *context) {
    if (context->key_capacity > SIZE_MAX / 2) {
        Rf_error("too many distinct numeric factor levels");
    }
    size_t capacity = context->key_capacity == 0
        ? 16 : context->key_capacity * 2;
    if (capacity > SIZE_MAX / sizeof(uint64_t)) {
        Rf_error("too many distinct numeric factor levels");
    }
    uint64_t *keys = (uint64_t *) realloc(
        context->keys, capacity * sizeof(uint64_t)
    );
    if (keys == NULL) Rf_error("failed to allocate numeric factor levels");
    context->keys = keys;
    context->key_capacity = capacity;
}

static int numeric_level_id(
    numeric_factor_context *context, double value
) {
    if (context->entry_capacity == 0) numeric_hash_resize(context, 16);
    if (context->key_count >=
        context->entry_capacity - context->entry_capacity / 4) {
        if (context->entry_capacity > SIZE_MAX / 2) {
            Rf_error("too many distinct numeric factor levels");
        }
        numeric_hash_resize(context, context->entry_capacity * 2);
    }

    uint64_t key = normalized_numeric_key(value);
    size_t slot = (size_t) numeric_key_hash(key) &
        (context->entry_capacity - 1);
    while (context->entries[slot].id_plus_one != 0) {
        if (context->entries[slot].key == key) {
            return context->entries[slot].id_plus_one - 1;
        }
        slot = (slot + 1) & (context->entry_capacity - 1);
    }

    if (context->key_count >= (size_t) INT_MAX) {
        Rf_error("a factor cannot have more than INT_MAX levels");
    }
    if (context->key_count == context->key_capacity) {
        numeric_keys_grow(context);
    }
    int id = (int) context->key_count;
    context->keys[context->key_count++] = key;
    context->entries[slot].key = key;
    context->entries[slot].id_plus_one = id + 1;
    return id;
}

static int numeric_level_after(
    const numeric_level_entry *left, const numeric_level_entry *right
) {
    return left->value > right->value;
}

static void numeric_level_sift_down(
    numeric_level_entry *levels, size_t root, size_t count
) {
    if (count < 2) return;
    while (root <= (count - 2) / 2) {
        size_t child = root * 2 + 1;
        if (child + 1 < count &&
            numeric_level_after(&levels[child + 1], &levels[child])) {
            child++;
        }
        if (!numeric_level_after(&levels[child], &levels[root])) return;
        numeric_level_entry temporary = levels[root];
        levels[root] = levels[child];
        levels[child] = temporary;
        root = child;
    }
}

static void numeric_level_sort(numeric_level_entry *levels, size_t count) {
    if (count < 2) return;
    for (size_t start = count / 2; start > 0; start--) {
        if ((start & 16383) == 0) R_CheckUserInterrupt();
        numeric_level_sift_down(levels, start - 1, count);
    }
    for (size_t end = count; end > 1; end--) {
        if ((end & 16383) == 0) R_CheckUserInterrupt();
        numeric_level_entry temporary = levels[0];
        levels[0] = levels[end - 1];
        levels[end - 1] = temporary;
        numeric_level_sift_down(levels, 0, end - 1);
    }
}

static void numeric_factor_cleanup(void *data) {
    numeric_factor_context *context = (numeric_factor_context *) data;
    free(context->entries);
    free(context->keys);
    free(context->levels);
}

static SEXP numeric_factor_body(void *data) {
    numeric_factor_context *context = (numeric_factor_context *) data;
    R_xlen_t length = XLENGTH(context->value);
    SEXP codes = PROTECT(Rf_allocVector(INTSXP, length));
    int *code_values = INTEGER(codes);
    int missing_seen[257] = {0};
    numeric_reader reader = numeric_reader_create(context->value, length);

    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        int missing_code;
        double value = numeric_reader_at(&reader, index, &missing_code);
        if (missing_code < 0) {
            code_values[index] = numeric_level_id(context, value) + 1;
        } else if (context->missing_mode == 1) {
            missing_seen[missing_code] = 1;
            code_values[index] = -(missing_code + 1);
        } else {
            code_values[index] = NA_INTEGER;
        }
    }

    if (context->seeds != R_NilValue) {
        R_xlen_t seed_count = XLENGTH(context->seeds);
        numeric_reader seed_reader = numeric_reader_create(
            context->seeds, seed_count
        );
        for (R_xlen_t index = 0; index < seed_count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            int missing_code;
            double value = numeric_reader_at(
                &seed_reader, index, &missing_code
            );
            if (missing_code < 0) {
                (void) numeric_level_id(context, value);
            } else if (context->missing_mode == 1) {
                missing_seen[missing_code] = 1;
            }
        }
    }

    size_t level_count = context->key_count;
    if (level_count > 0) {
        if (level_count > SIZE_MAX / sizeof(numeric_level_entry)) {
            Rf_error("too many distinct numeric factor levels");
        }
        context->levels = (numeric_level_entry *) malloc(
            level_count * sizeof(numeric_level_entry)
        );
        if (context->levels == NULL) {
            Rf_error("failed to allocate sorted numeric factor levels");
        }
    }
    for (size_t index = 0; index < level_count; index++) {
        double value;
        memcpy(&value, &context->keys[index], sizeof(value));
        context->levels[index].value = value;
        context->levels[index].old_id = (int) index;
    }
    numeric_level_sort(context->levels, level_count);

    SEXP values = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) level_count));
    int *remap = level_count == 0 ? NULL :
        (int *) R_alloc(level_count, sizeof(int));
    for (size_t index = 0; index < level_count; index++) {
        REAL(values)[index] = context->levels[index].value;
        remap[context->levels[index].old_id] = (int) index + 1;
    }

    int missing_positions[257] = {0};
    int missing_count = 0;
    for (int code = 0; code <= 256; code++) {
        if (missing_seen[code]) missing_positions[code] = ++missing_count;
    }
    if (level_count > (size_t) (INT_MAX - missing_count)) {
        Rf_error("a factor cannot have more than INT_MAX levels");
    }
    SEXP missing_codes = PROTECT(Rf_allocVector(INTSXP, missing_count));
    for (int code = 0; code <= 256; code++) {
        if (missing_positions[code] != 0) {
            INTEGER(missing_codes)[missing_positions[code] - 1] = code;
        }
    }

    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        int code = code_values[index];
        if (code > 0) {
            code_values[index] = remap[code - 1];
        } else if (code != NA_INTEGER) {
            int missing_code = -code - 1;
            code_values[index] = (int) level_count +
                missing_positions[missing_code];
        }
    }

    SEXP result = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(result, 0, codes);
    SET_VECTOR_ELT(result, 1, values);
    SET_VECTOR_ELT(result, 2, missing_codes);
    SEXP result_names = PROTECT(Rf_allocVector(STRSXP, 3));
    SET_STRING_ELT(result_names, 0, Rf_mkChar("codes"));
    SET_STRING_ELT(result_names, 1, Rf_mkChar("values"));
    SET_STRING_ELT(result_names, 2, Rf_mkChar("missing_codes"));
    Rf_setAttrib(result, R_NamesSymbol, result_names);
    UNPROTECT(5);
    return result;
}

SEXP C_dtatools_factorize_numeric(
    SEXP value, SEXP seeds, SEXP missing_mode
) {
    if ((TYPEOF(value) != REALSXP && TYPEOF(value) != INTSXP) ||
        (seeds != R_NilValue &&
         TYPEOF(seeds) != REALSXP && TYPEOF(seeds) != INTSXP)) {
        Rf_error("internal numeric grouping requires doubles or integers");
    }
    if (TYPEOF(missing_mode) != INTSXP || XLENGTH(missing_mode) != 1 ||
        INTEGER(missing_mode)[0] < 0 || INTEGER(missing_mode)[0] > 2) {
        Rf_error("internal missing mode is invalid");
    }
    numeric_factor_context context = {
        value,
        seeds,
        INTEGER(missing_mode)[0],
        NULL,
        0,
        NULL,
        0,
        0,
        NULL
    };
    return R_ExecWithCleanup(
        numeric_factor_body, &context, numeric_factor_cleanup, &context
    );
}

static void fill_span_doubles(const numeric_data *span, size_t offset, void *context) {
    double *output = (double *) context + offset;
    switch (span->kind) {
    case NUMERIC_BYTE:
        numeric_byte_region(span, 0, span->length, output);
        return;
    case NUMERIC_INT:
        numeric_int_region(span, 0, span->length, output);
        return;
    case NUMERIC_LONG:
        numeric_long_region(span, 0, span->length, output);
        return;
    case NUMERIC_FLOAT:
        numeric_float_region(span, 0, span->length, output);
        return;
    default:
        Rf_error("invalid dtatools numeric storage kind");
    }
}

static void numeric_fill_region(
    const numeric_data *data, size_t index, size_t length, double *output
) {
    numeric_for_each_span(data, index, length, fill_span_doubles, output);
}

typedef struct {
    Rboolean na_rm;
    long double sum;
} numeric_sum_context;

static void sum_span(const numeric_data *span, size_t offset, void *context) {
    (void) offset;
    numeric_sum_context *state = (numeric_sum_context *) context;
    /* Carry one accumulator through every row. Summing independent
       chunks and combining their totals changes floating rounding. */
    switch (span->kind) {
    case NUMERIC_BYTE: numeric_byte_sum_accumulate(span, state->na_rm, &state->sum); break;
    case NUMERIC_INT: numeric_int_sum_accumulate(span, state->na_rm, &state->sum); break;
    case NUMERIC_LONG: numeric_long_sum_accumulate(span, state->na_rm, &state->sum); break;
    case NUMERIC_FLOAT: numeric_float_sum_accumulate(span, state->na_rm, &state->sum); break;
    default: Rf_error("invalid dtatools numeric storage kind");
    }
}

static long double numeric_sum_storage(
    const numeric_data *data, Rboolean na_rm
) {
    numeric_sum_context state = {na_rm, 0.0};
    numeric_for_each_span(data, 0, data->length, sum_span, &state);
    return state.sum;
}

typedef struct {
    Rboolean na_rm;
    int minimum;
    double current;
    int updated;
} numeric_extreme_context;

static void extreme_span(const numeric_data *span, size_t offset, void *context) {
    (void) offset;
    numeric_extreme_context *state = (numeric_extreme_context *) context;
    switch (span->kind) {
    case NUMERIC_BYTE: numeric_byte_extreme_accumulate(span, state->na_rm, state->minimum, &state->current, &state->updated); break;
    case NUMERIC_INT: numeric_int_extreme_accumulate(span, state->na_rm, state->minimum, &state->current, &state->updated); break;
    case NUMERIC_LONG: numeric_long_extreme_accumulate(span, state->na_rm, state->minimum, &state->current, &state->updated); break;
    case NUMERIC_FLOAT: numeric_float_extreme_accumulate(span, state->na_rm, state->minimum, &state->current, &state->updated); break;
    default: Rf_error("invalid dtatools numeric storage kind");
    }
}

static int numeric_extreme_storage(
    const numeric_data *data, Rboolean na_rm, int minimum, double *result
) {
    numeric_extreme_context state = {na_rm, minimum, 0.0, 0};
    numeric_for_each_span(data, 0, data->length, extreme_span, &state);
    if (state.updated) *result = state.current;
    return state.updated;
}

double numeric_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return REAL_ELT(materialized, index);
    numeric_data *data = numeric_read_storage(value);
    if (index < 0 || (size_t) index >= data->length) {
        Rf_error("invalid dtatools numeric-vector index");
    }
    switch (data->kind) {
    case NUMERIC_BYTE:
        return numeric_byte_scalar_value_at(data, (size_t) index);
    case NUMERIC_INT:
        return numeric_int_scalar_value_at(data, (size_t) index);
    case NUMERIC_LONG:
        return numeric_long_scalar_value_at(data, (size_t) index);
    case NUMERIC_FLOAT:
        return numeric_float_scalar_value_at(data, (size_t) index);
    default:
        Rf_error("invalid dtatools numeric storage kind");
    }
}

R_xlen_t numeric_region(
    SEXP value, R_xlen_t index, R_xlen_t count, double *output
) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) {
        R_xlen_t length = XLENGTH(materialized);
        if (index < 0 || count < 0 || index >= length) return 0;
        R_xlen_t available = length - index;
        R_xlen_t copied = count < available ? count : available;
        memcpy(output, REAL(materialized) + index,
               (size_t) copied * sizeof(double));
        return copied;
    }
    numeric_data *data = numeric_read_storage(value);
    if (index < 0 || count < 0 || (size_t) index >= data->length) return 0;
    size_t available = data->length - (size_t) index;
    size_t requested = (size_t) count;
    size_t length = requested < available ? requested : available;
    numeric_fill_region(data, (size_t) index, length, output);
    return (R_xlen_t) length;
}

static SEXP numeric_materialize(SEXP value, Rboolean writeable) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) {
        return writeable
            ? detach_shared_materialized_payload(value) : materialized;
    }
    numeric_data *data = numeric_read_storage(value);
    if (numeric_payload_retained(data)) {
        SEXP detached = PROTECT(numeric_handle_copy(value));
        R_set_altrep_data1(value, R_altrep_data1(detached));
        data = numeric_read_storage(value);
        UNPROTECT(1);
    } else if (compact_payload_is_shared(R_altrep_data1(value))) {
        SEXP detached = PROTECT(numeric_compact_copy(data));
        R_set_altrep_data1(value, R_altrep_data1(detached));
        data = numeric_storage(value);
        UNPROTECT(1);
    }
    materialized = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) data->length));
    double *output = REAL(materialized);
    numeric_fill_region(data, 0, data->length, output);
    R_set_altrep_data2(value, materialized);
    numeric_finalize(R_altrep_data1(value));
    UNPROTECT(1);
    return materialized;
}

void *numeric_dataptr(SEXP value, Rboolean writeable) {
    SEXP materialized = numeric_materialize(value, writeable);
    return writeable ? DATAPTR_RW(materialized) : (void *) DATAPTR_RO(materialized);

}

const void *numeric_dataptr_or_null(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? NULL : DATAPTR_OR_NULL(materialized);
}

int numeric_no_na(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) {
        R_xlen_t length = XLENGTH(materialized);
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            if (ISNAN(REAL_ELT(materialized, index))) return 0;
        }
        return 1;
    }
    return numeric_read_storage(value)->missing_count == 0;
}

SEXP numeric_sum(SEXP value, Rboolean na_rm) {
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    numeric_data *data = numeric_read_storage(value);
    long double sum = numeric_sum_storage(data, na_rm);
    if (sum > DBL_MAX) return Rf_ScalarReal(R_PosInf);
    if (sum < -DBL_MAX) return Rf_ScalarReal(R_NegInf);
    return Rf_ScalarReal((double) sum);
}

static SEXP numeric_extreme(
    SEXP value, Rboolean na_rm, int minimum
) {
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    double result;
    if (!numeric_extreme_storage(
            numeric_read_storage(value), na_rm, minimum, &result
        )) {
        return NULL;
    }
    return Rf_ScalarReal(result);
}

SEXP numeric_min(SEXP value, Rboolean na_rm) {
    return numeric_extreme(value, na_rm, 1);
}

SEXP numeric_max(SEXP value, Rboolean na_rm) {
    return numeric_extreme(value, na_rm, 0);
}

SEXP numeric_from_backing(
    SEXP backing, size_t length, int kind, int temporal,
    int format_version, size_t missing_count
) {
    /* backing may be rooted only by a public handle whose finalizer or
       materialization clears that root during external-pointer allocation. */
    PROTECT(backing);
    SEXP external = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, backing));
    R_RegisterCFinalizerEx(external, numeric_finalize, TRUE);
    void *data = dtatools_numeric_alloc(
        RAW(backing), length, kind, temporal, missing_count
    );
    if (data == NULL) {
        Rf_error("could not allocate compact Stata numeric storage");
    }
    R_SetExternalPtrAddr(external, data);
    numeric_data *numeric = (numeric_data *) data;
    numeric->format_version = format_version;
    if (missing_count == SIZE_MAX) {
        numeric->missing_count = numeric_count_missing(numeric);
    }
    SEXP result = PROTECT(R_new_altrep(
        dtatools_numeric_class, external, R_NilValue
    ));
    UNPROTECT(3);
    return result;
}

SEXP numeric_compact_copy(const numeric_data *data) {
    size_t width = numeric_kind_width(data->kind);
    if (data->length > SIZE_MAX / width ||
        data->length * width > (size_t) R_XLEN_T_MAX) {
        Rf_error("compact Stata numeric vector is too long");
    }
    R_xlen_t byte_length = (R_xlen_t) (data->length * width);
    SEXP backing = PROTECT(Rf_allocVector(RAWSXP, byte_length));
    numeric_copy_region(data, 0, data->length, RAW(backing));
    compact_copy_bytes += (double) byte_length;
    SEXP result = numeric_from_backing(
        backing, data->length, data->kind, data->temporal,
        data->format_version, data->missing_count
    );
    UNPROTECT(1);
    return result;
}

typedef struct {
    const numeric_data *entry;
    SEXP roots;
    void *copy;
} numeric_capture_context;

static void numeric_capture_cleanup(void *raw) {
    numeric_capture_context *context = (numeric_capture_context *) raw;
    if (context->copy != NULL) {
        dtatools_numeric_free(context->copy);
        context->copy = NULL;
    }
}

static SEXP numeric_capture_body(void *raw) {
    numeric_capture_context *context = (numeric_capture_context *) raw;
    /* Rust clones scalar metadata and retains the immutable owner. It calls
       no R API. Do not dereference the public descriptor after this call. */
    context->copy = dtatools_owned_numeric_clone(context->entry);
    context->entry = NULL;
    if (context->copy == NULL) Rf_error("could not retain an owned numeric column");
    SEXP external = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(external, numeric_finalize, TRUE);
    /* Registered finalizer takes ownership in one allocation-free segment. */
    R_SetExternalPtrProtected(external, context->roots);
    R_SetExternalPtrAddr(external, context->copy);
    context->copy = NULL;
    SEXP result = PROTECT(R_new_altrep(dtatools_numeric_class, external, R_NilValue));
    UNPROTECT(2);
    return result;
}

/* Share only immutable bytes. Every returned vector has its own descriptor,
   external pointer and materialization state, plus the entry R roots. */
SEXP numeric_handle_copy(SEXP source) {
    numeric_data *data = numeric_read_storage(source);
    if (!numeric_payload_retained(data)) return numeric_compact_copy(data);
    PROTECT(source);
    SEXP entry_external = PROTECT(R_altrep_data1(source));
    SEXP entry_roots = PROTECT(R_ExternalPtrProtected(entry_external));
    numeric_capture_context context = {data, entry_roots, NULL};
    SEXP result = R_ExecWithCleanup(
        numeric_capture_body, &context, numeric_capture_cleanup, &context
    );
    UNPROTECT(3);
    return result;
}

static int host_is_little_endian(void) {
    uint16_t value = UINT16_C(1);
    return *((unsigned char *) &value) == 1;
}

static void swap_compact_numeric_bytes(
    unsigned char *bytes, size_t length, size_t width
) {
    if (width == 1) return;
    for (size_t index = 0; index < length; index++) {
        unsigned char *element = bytes + index * width;
        for (size_t left = 0; left < width / 2; left++) {
            size_t right = width - left - 1;
            unsigned char temporary = element[left];
            element[left] = element[right];
            element[right] = temporary;
        }
    }
}

SEXP numeric_serialized_state(SEXP value) {
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    numeric_data *data = numeric_read_storage(value);
    SEXP backing = PROTECT(Rf_allocVector(
        RAWSXP, (R_xlen_t) (data->length * numeric_kind_width(data->kind))
    ));
    numeric_copy_region(data, 0, data->length, RAW(backing));
    if (!host_is_little_endian()) {
        swap_compact_numeric_bytes(
            RAW(backing), data->length, numeric_kind_width(data->kind)
        );
    }
    SEXP metadata = PROTECT(Rf_allocVector(INTSXP, 5));
    INTEGER(metadata)[0] = data->kind;
    INTEGER(metadata)[1] = data->temporal;
    INTEGER(metadata)[2] = data->format_version;
    INTEGER(metadata)[3] = data->missing_count == 0;
    INTEGER(metadata)[4] = 2;
    SEXP state = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(state, 0, backing);
    SET_VECTOR_ELT(state, 1, metadata);
    UNPROTECT(3);
    return state;
}

SEXP numeric_unserialize(SEXP class, SEXP state) {
    (void) class;
    if (TYPEOF(state) != VECSXP || XLENGTH(state) != 2) {
        Rf_error("invalid serialized dtatools numeric state");
    }
    SEXP backing = VECTOR_ELT(state, 0);
    SEXP metadata = VECTOR_ELT(state, 1);
    if (TYPEOF(backing) != RAWSXP || TYPEOF(metadata) != INTSXP ||
        XLENGTH(metadata) != 5 || INTEGER(metadata)[4] != 2) {
        Rf_error("invalid serialized dtatools numeric state");
    }
    int kind = INTEGER(metadata)[0];
    size_t width = numeric_kind_width(kind);
    size_t byte_length = (size_t) XLENGTH(backing);
    if (byte_length % width != 0) {
        Rf_error("invalid serialized dtatools numeric state");
    }
    int protected_backing = 0;
    if (!host_is_little_endian()) {
        backing = PROTECT(Rf_duplicate(backing));
        protected_backing = 1;
        swap_compact_numeric_bytes(RAW(backing), byte_length / width, width);
    }
    SEXP result = numeric_from_backing(
        backing, byte_length / width, kind, INTEGER(metadata)[1],
        INTEGER(metadata)[2], INTEGER(metadata)[3] ? 0 : SIZE_MAX
    );
    if (protected_backing) UNPROTECT(1);
    return result;
}

SEXP numeric_duplicate(SEXP value, Rboolean deep) {
    (void) deep;
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    return numeric_handle_copy(value);
}

void write_numeric_system_missing_raw(
    unsigned char *output, R_xlen_t index, int kind, int format_version
) {
    if (format_version > 111) {
        write_numeric_missing(output, index, kind, 0);
        return;
    }
    switch (kind) {
    case NUMERIC_BYTE: {
        int8_t encoded = INT8_MAX;
        memcpy(output + (size_t) index, &encoded, sizeof(encoded));
        return;
    }
    case NUMERIC_INT: {
        int16_t encoded = INT16_MAX;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_LONG: {
        int32_t encoded = INT32_MAX;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_FLOAT: {
        uint32_t bits = UINT32_C(0x7f000000);
        memcpy(output + (size_t) index * sizeof(bits), &bits, sizeof(bits));
        return;
    }
    default:
        Rf_error("invalid compact Stata numeric storage type");
    }
}

SEXP numeric_extract_subset(SEXP value, SEXP index, SEXP call) {
    (void) call;
    if (R_altrep_data2(value) != R_NilValue ||
        (TYPEOF(index) != INTSXP && TYPEOF(index) != REALSXP)) {
        return NULL;
    }
    /* Index callbacks can materialize value and free its native descriptor.
       Freeze the descriptor and retain its raw payload for this read loop. */
    /* The independent immutable handle keeps the owner alive even when an
       index callback materializes or mutates the original value. */
    SEXP read_handle = PROTECT(numeric_payload_retained(numeric_read_storage(value))
        ? numeric_handle_copy(value) : value);
    numeric_data snapshot = *numeric_read_storage(read_handle);
    const numeric_data *data = &snapshot;
    SEXP source_backing = PROTECT(R_ExternalPtrProtected(R_altrep_data1(read_handle)));
    (void) source_backing;
    R_xlen_t length = XLENGTH(index);
    size_t width = numeric_kind_width(data->kind);
    if ((size_t) length > SIZE_MAX / width) {
        Rf_error("compact Stata numeric subset is too long");
    }
    SEXP backing = PROTECT(Rf_allocVector(
        RAWSXP, (R_xlen_t) ((size_t) length * width)
    ));
    unsigned char *output = RAW(backing);
    size_t missing_count = 0;
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t source = -1;
        if (TYPEOF(index) == INTSXP) {
            int candidate = INTEGER_ELT(index, i);
            if (candidate != NA_INTEGER && candidate > 0 &&
                (size_t) candidate <= data->length) source = candidate - 1;
        } else {
            double candidate = REAL_ELT(index, i);
            if (R_FINITE(candidate) && candidate >= 1 &&
                candidate <= (double) data->length) {
                source = (R_xlen_t) candidate - 1;
            }
        }
        if (source >= 0) {
            numeric_copy_region(data, (size_t) source, 1,
                                output + (size_t) i * width);
            if (numeric_value_is_missing_at(data, (size_t) source)) {
                missing_count++;
            }
        } else {
            write_numeric_system_missing_raw(
                output, i, data->kind, data->format_version
            );
            missing_count++;
        }
    }
    SEXP result = numeric_from_backing(
        backing, (size_t) length, data->kind, data->temporal,
        data->format_version, missing_count
    );
    UNPROTECT(3);
    return result;
}

typedef struct {
    SEXP value;
    const int *integer_values;
    const double *real_values;
    int type;
} numeric_gather_indices;

static numeric_gather_indices numeric_gather_indices_create(
    SEXP value, const char *argument
) {
    numeric_gather_indices indices = {
        value, NULL, NULL, TYPEOF(value)
    };
    if (indices.type == INTSXP) {
        indices.integer_values = (const int *) DATAPTR_OR_NULL(value);
    } else if (indices.type == REALSXP) {
        indices.real_values = (const double *) DATAPTR_OR_NULL(value);
    } else {
        Rf_error("`%s` must be an integer or double vector", argument);
    }
    return indices;
}

static R_xlen_t numeric_gather_index(
    const numeric_gather_indices *indices, R_xlen_t position,
    size_t source_length, const char *argument
) {
    if (indices->type == INTSXP) {
        int candidate = indices->integer_values == NULL
            ? INTEGER_ELT(indices->value, position)
            : indices->integer_values[position];
        if (candidate == NA_INTEGER) return -1;
        if (candidate <= 0 || (size_t) candidate > source_length) {
            Rf_error("`%s` contains an invalid row index", argument);
        }
        return (R_xlen_t) candidate - 1;
    }

    double candidate = indices->real_values == NULL
        ? REAL_ELT(indices->value, position)
        : indices->real_values[position];
    if (ISNAN(candidate)) return -1;
    if (!R_FINITE(candidate) || candidate != trunc(candidate) ||
        candidate <= 0 || candidate > (double) source_length) {
        Rf_error("`%s` contains an invalid row index", argument);
    }
    return (R_xlen_t) candidate - 1;
}

static void numeric_gather_element(
    unsigned char *output, R_xlen_t output_index,
    const numeric_data *source, R_xlen_t source_index, size_t width
) {
    if (numeric_payload_retained(source)) {
        size_t available;
        const void *input = numeric_read_span(source, (size_t) source_index, 1, &available);
        memcpy(output + (size_t) output_index * width, input, width);
        return;
    }
    const unsigned char *input = (const unsigned char *) source->values;
    if (width == 1) {
        output[output_index] = input[source_index];
    } else if (width == 2) {
        uint16_t element;
        memcpy(&element, input + (size_t) source_index * 2, 2);
        memcpy(output + (size_t) output_index * 2, &element, 2);
    } else {
        uint32_t element;
        memcpy(&element, input + (size_t) source_index * 4, 4);
        memcpy(output + (size_t) output_index * 4, &element, 4);
    }
}

SEXP C_dtatools_gather_numeric(
    SEXP x, SEXP y, SEXP x_rows, SEXP y_rows
) {
    SEXP x_root = PROTECT(numeric_payload_root(x));
    SEXP y_root = PROTECT(y == R_NilValue ? R_NilValue : numeric_payload_root(y));
    numeric_data *x_data = unmaterialized_numeric_read_storage(x_root);
    if (x_data == NULL) x_data = unmaterialized_numeric_read_storage(x);
    if (x_data == NULL) {
        Rf_error("internal numeric gather requires compact `x` storage");
    }
    numeric_data x_encoding = *x_data;
    x_data = &x_encoding;
    numeric_data *y_data = NULL;
    numeric_data y_encoding;
    if (y != R_NilValue) {
        y_data = unmaterialized_numeric_read_storage(y_root);
        if (y_data == NULL) y_data = unmaterialized_numeric_read_storage(y);
        if (y_data == NULL) {
            Rf_error("internal numeric gather requires compact `y` storage");
        }
        y_encoding = *y_data;
        y_data = &y_encoding;
        if (x_data->kind != y_data->kind ||
            x_data->temporal != y_data->temporal) {
            Rf_error("internal numeric gather requires matching storage");
        }
        if ((x_data->format_version <= 111) !=
            (y_data->format_version <= 111)) {
            UNPROTECT(2);
            return R_NilValue;
        }
        if (XLENGTH(y_rows) != XLENGTH(x_rows)) {
            Rf_error("internal numeric gather row vectors differ in length");
        }
    } else if (y_rows != R_NilValue) {
        Rf_error("internal numeric gather received `y_rows` without `y`");
    }

    R_xlen_t length = XLENGTH(x_rows);
    size_t width = numeric_kind_width(x_data->kind);
    if ((size_t) length > SIZE_MAX / width ||
        (size_t) length * width > (size_t) R_XLEN_T_MAX) {
        Rf_error("compact Stata numeric gather is too long");
    }
    SEXP backing = PROTECT(Rf_allocVector(
        RAWSXP, (R_xlen_t) ((size_t) length * width)
    ));
    numeric_gather_indices x_indices = numeric_gather_indices_create(
        x_rows, "x_rows"
    );
    numeric_gather_indices y_indices;
    if (y_data != NULL) {
        y_indices = numeric_gather_indices_create(y_rows, "y_rows");
    }
    unsigned char *output = RAW(backing);
    SEXP x_names = Rf_getAttrib(x, R_NamesSymbol);
    SEXP gathered_names = R_NilValue;
    if (x_names != R_NilValue) {
        gathered_names = PROTECT(Rf_allocVector(STRSXP, length));
    }
    size_t missing_count = 0;

    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t source_index = numeric_gather_index(
            &x_indices, index, x_data->length, "x_rows"
        );
        const numeric_data *source = x_data;
        if (source_index < 0 && y_data != NULL) {
            source_index = numeric_gather_index(
                &y_indices, index, y_data->length, "y_rows"
            );
            source = y_data;
        }
        if (source_index < 0) {
            write_numeric_system_missing_raw(
                output, index, x_data->kind, x_data->format_version
            );
            missing_count++;
        } else {
            numeric_gather_element(
                output, index, source, source_index, width
            );
            if (numeric_value_is_missing_at(
                    source, (size_t) source_index
                )) {
                missing_count++;
            }
        }
        if (gathered_names != R_NilValue) {
            SET_STRING_ELT(
                gathered_names, index,
                source == x_data && source_index >= 0
                    ? STRING_ELT(x_names, source_index) : R_BlankString
            );
        }
    }

    SEXP result = PROTECT(numeric_from_backing(
        backing, (size_t) length, x_data->kind, x_data->temporal,
        x_data->format_version, missing_count
    ));
    if (gathered_names != R_NilValue) {
        Rf_setAttrib(result, R_NamesSymbol, gathered_names);
    }
    UNPROTECT(gathered_names == R_NilValue ? 4 : 5);
    return result;
}

static int *numeric_gather_plan(
    SEXP rows, size_t source_length, const char *argument
) {
    if (source_length > (size_t) INT_MAX) {
        Rf_error("compact numeric gather source is too long");
    }
    R_xlen_t length = XLENGTH(rows);
    if ((size_t) length > SIZE_MAX / sizeof(int)) {
        Rf_error("compact numeric gather plan is too long");
    }
    int *plan = (int *) R_alloc((size_t) length, sizeof(int));
    numeric_gather_indices indices = numeric_gather_indices_create(
        rows, argument
    );
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t source = numeric_gather_index(
            &indices, index, source_length, argument
        );
        plan[index] = (int) source;
    }
    return plan;
}

typedef struct {
    const unsigned char *values;
    size_t length;
    size_t width;
    numeric_data *compact;
} numeric_gather_source;

static numeric_gather_source numeric_gather_source_create(
    SEXP value, const char *argument
) {
    numeric_data *compact = unmaterialized_numeric_read_storage(value);
    if (compact != NULL) {
        numeric_gather_source source = {
            (const unsigned char *) compact->values,
            compact->length,
            numeric_kind_width(compact->kind),
            compact
        };
        return source;
    }
    if (TYPEOF(value) != REALSXP) {
        Rf_error(
            "internal column gather requires compact or double `%s` storage",
            argument
        );
    }
    R_xlen_t length = XLENGTH(value);
    if ((uint64_t) length > (uint64_t) SIZE_MAX) {
        Rf_error("internal column gather `%s` is too long", argument);
    }
    numeric_gather_source source = {
        (const unsigned char *) DATAPTR_RO(value),
        (size_t) length,
        sizeof(double),
        NULL
    };
    return source;
}

SEXP C_dtatools_gather_numeric_columns(
    SEXP x, SEXP y, SEXP x_rows, SEXP y_rows
) {
    if (TYPEOF(x) != VECSXP ||
        (y != R_NilValue &&
         (TYPEOF(y) != VECSXP || XLENGTH(y) != XLENGTH(x)))) {
        Rf_error("internal column gather requires matching lists");
    }
    R_xlen_t column_count = XLENGTH(x);
    SEXP result = PROTECT(Rf_allocVector(VECSXP, column_count));
    SEXP read_roots = PROTECT(Rf_allocVector(VECSXP, 2 * column_count));
    for (R_xlen_t index = 0; index < column_count; index++) {
        SET_VECTOR_ELT(read_roots, 2 * index, numeric_payload_root(VECTOR_ELT(x, index)));
        if (y != R_NilValue)
            SET_VECTOR_ELT(read_roots, 2 * index + 1, numeric_payload_root(VECTOR_ELT(y, index)));
    }
    if (column_count == 0) {
        UNPROTECT(2);
        return result;
    }

    numeric_gather_source first_x = numeric_gather_source_create(
        VECTOR_ELT(x, 0), "x"
    );
    numeric_gather_source first_y;
    if (y != R_NilValue) {
        first_y = numeric_gather_source_create(VECTOR_ELT(y, 0), "y");
        if (XLENGTH(y_rows) != XLENGTH(x_rows)) {
            Rf_error("internal column gather row vectors differ in length");
        }
    } else if (y_rows != R_NilValue) {
        Rf_error("internal column gather received `y_rows` without `y`");
    }

    int *x_plan = numeric_gather_plan(
        x_rows, first_x.length, "x_rows"
    );
    int *y_plan = y == R_NilValue ? NULL : numeric_gather_plan(
        y_rows, first_y.length, "y_rows"
    );
    if ((size_t) column_count > SIZE_MAX / sizeof(numeric_gather_column)) {
        Rf_error("compact numeric column gather is too wide");
    }
    numeric_gather_column *columns = (numeric_gather_column *) R_alloc(
        (size_t) column_count, sizeof(numeric_gather_column)
    );
    size_t active = 0;

    for (R_xlen_t index = 0; index < column_count; index++) {
        SEXP x_value = VECTOR_ELT(x, index);
        SEXP y_value = y == R_NilValue
            ? R_NilValue : VECTOR_ELT(y, index);
        SEXP x_read = VECTOR_ELT(read_roots, 2 * index);
        SEXP y_read = VECTOR_ELT(read_roots, 2 * index + 1);
        numeric_gather_source x_source = numeric_gather_source_create(
            unmaterialized_numeric_read_storage(x_read) != NULL ? x_read : x_value, "x"
        );
        numeric_gather_source y_source;
        if (y != R_NilValue) {
            y_source = numeric_gather_source_create(
                unmaterialized_numeric_read_storage(y_read) != NULL ? y_read : y_value, "y");
        }
        if (x_source.length != first_x.length ||
            (y != R_NilValue && y_source.length != first_y.length)) {
            Rf_error("internal column gather received inconsistent storage");
        }
        if (y != R_NilValue) {
            int x_is_compact = x_source.compact != NULL;
            int y_is_compact = y_source.compact != NULL;
            if (x_is_compact != y_is_compact ||
                (x_is_compact &&
                 (x_source.compact->kind != y_source.compact->kind ||
                  x_source.compact->temporal !=
                      y_source.compact->temporal))) {
                Rf_error("internal column gather requires matching storage");
            }
        }
        if (Rf_getAttrib(x_value, R_NamesSymbol) != R_NilValue ||
            Rf_getAttrib(x_value, R_DimSymbol) != R_NilValue ||
            (y != R_NilValue &&
             (Rf_getAttrib(y_value, R_NamesSymbol) != R_NilValue ||
              Rf_getAttrib(y_value, R_DimSymbol) != R_NilValue)) ||
            (y != R_NilValue && x_source.compact != NULL &&
             ((x_source.compact->format_version <= 111) !=
              (y_source.compact->format_version <= 111)))) {
            SET_VECTOR_ELT(result, index, R_NilValue);
            continue;
        }

        size_t width = x_source.width;
        R_xlen_t row_count = XLENGTH(x_rows);
        if ((size_t) row_count > SIZE_MAX / width ||
            (size_t) row_count * width > (size_t) R_XLEN_T_MAX) {
            Rf_error("Stata numeric gather is too long");
        }
        SEXP gathered;
        SEXP backing = R_NilValue;
        if (x_source.compact != NULL) {
            backing = PROTECT(Rf_allocVector(
                RAWSXP, (R_xlen_t) ((size_t) row_count * width)
            ));
            gathered = PROTECT(numeric_from_backing(
                backing, (size_t) row_count,
                x_source.compact->kind, x_source.compact->temporal,
                x_source.compact->format_version, 0
            ));
        } else {
            gathered = PROTECT(Rf_allocVector(REALSXP, row_count));
        }
        numeric_gather_column *column = &columns[active++];
        column->x_values = (uintptr_t) x_source.values;
        column->y_values = y == R_NilValue
            ? (uintptr_t) 0 : (uintptr_t) y_source.values;
        column->x_owner = x_source.compact == NULL ? 0 : (uintptr_t) x_source.compact->native_owner;
        column->y_owner = y == R_NilValue || y_source.compact == NULL
            ? 0 : (uintptr_t) y_source.compact->native_owner;
        column->x_length = x_source.length;
        column->y_length = y == R_NilValue ? 0 : y_source.length;
        column->output = x_source.compact == NULL
            ? (uintptr_t) REAL(gathered) : (uintptr_t) RAW(backing);
        column->width = width;
        memset(column->missing, 0, sizeof(column->missing));
        if (x_source.compact != NULL) {
            write_numeric_system_missing_raw(
                column->missing, 0,
                x_source.compact->kind, x_source.compact->format_version
            );
            column->missing_count = (uintptr_t)
                &numeric_storage(gathered)->missing_count;
            column->kind = x_source.compact->kind;
            column->format_version = x_source.compact->format_version;
            column->source_has_missing =
                x_source.compact->missing_count != 0 ||
                (y != R_NilValue && y_source.compact != NULL &&
                 y_source.compact->missing_count != 0);
        } else {
            double missing = NA_REAL;
            memcpy(column->missing, &missing, sizeof(missing));
            column->missing_count = (uintptr_t) 0;
            column->kind = 0;
            column->format_version = 0;
            column->source_has_missing = 0;
        }
        SHALLOW_DUPLICATE_ATTRIB(gathered, x_value);
        SET_VECTOR_ELT(result, index, gathered);
        UNPROTECT(x_source.compact == NULL ? 1 : 2);
    }

    R_CheckUserInterrupt();
    if (active > 0 && !dtatools_gather_numeric_columns(
            columns, active, x_plan, y_plan,
            (size_t) XLENGTH(x_rows)
        )) {
        Rf_error("parallel compact numeric gather failed");
    }
    R_CheckUserInterrupt();
    /* All worker writes have completed. These ordinary output buffers have
       never escaped native gathering, so ownership needs no second copy. */
    for (R_xlen_t index = 0; index < XLENGTH(result); index++) {
        SEXP gathered = VECTOR_ELT(result, index);
        if (TYPEOF(gathered) == REALSXP && !ALTREP(gathered)) {
            SEXP owned = PROTECT(owned_adopt_real(gathered));
            SET_VECTOR_ELT(result, index, owned);
            UNPROTECT(1);
        }
    }
    UNPROTECT(2);
    return result;
}

typedef struct {
    void *data;
    SEXP backing;
    int transferred;
    SEXP result;
} make_numeric_context;

static void make_numeric_call(void *payload) {
    make_numeric_context *context = (make_numeric_context *) payload;
    SEXP external = PROTECT(R_MakeExternalPtr(
        context->data, R_NilValue, context->backing
    ));
    R_RegisterCFinalizerEx(external, numeric_finalize, TRUE);
    context->transferred = 1;
    SEXP result = PROTECT(R_new_altrep(
        dtatools_numeric_class, external, R_NilValue
    ));
    R_PreserveObject(result);
    context->result = result;
    UNPROTECT(2);
}

int dtatools_make_numeric(
    void *data, SEXP backing, int *transferred, SEXP *result
) {
    if (data == NULL || transferred == NULL || result == NULL) return 0;
    if (TYPEOF(backing) != RAWSXP &&
        !(backing == R_NilValue && numeric_payload_retained((numeric_data *) data))) return 0;
    make_numeric_context context = {data, backing, 0, NULL};
    int ok = R_ToplevelExec(make_numeric_call, &context);
    *transferred = context.transferred;
    if (ok) *result = context.result;
    return ok;
}

size_t numeric_kind_width(int kind) {
    switch (kind) {
    case NUMERIC_BYTE:
        return sizeof(int8_t);
    case NUMERIC_INT:
        return sizeof(int16_t);
    case NUMERIC_LONG:
        return sizeof(int32_t);
    case NUMERIC_FLOAT:
        return sizeof(float);
    default:
        Rf_error("invalid compact Stata numeric storage type");
    }
}

void write_numeric_missing(
    unsigned char *output, R_xlen_t index, int kind, int offset
) {
    switch (kind) {
    case NUMERIC_BYTE: {
        int8_t encoded = (int8_t) (101 + offset);
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_INT: {
        int16_t encoded = (int16_t) (32741 + offset);
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_LONG: {
        int32_t encoded = INT32_C(2147483621) + offset;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_FLOAT: {
        uint32_t bits = UINT32_C(0x7f000000) +
            (uint32_t) offset * UINT32_C(0x00000800);
        float encoded;
        memcpy(&encoded, &bits, sizeof(encoded));
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    default:
        Rf_error("invalid compact Stata numeric storage type");
    }
}

static double numeric_float_observed_limit(void) {
    uint32_t maximum_bits = UINT32_C(0x7effffff);
    float maximum;
    memcpy(&maximum, &maximum_bits, sizeof(maximum));
    return (double) maximum;
}

void write_numeric_observed(
    unsigned char *output, R_xlen_t index, int kind, double value
) {
    switch (kind) {
    case NUMERIC_BYTE: {
        if (!R_FINITE(value) || value != trunc(value) ||
            value < -127.0 || value > 100.0) {
            const char *wider = R_FINITE(value) && value == trunc(value) &&
                value >= -32767.0 && value <= 32740.0 ? "int" :
                (R_FINITE(value) && value == trunc(value) &&
                 value >= -2147483647.0 && value <= 2147483620.0
                    ? "long" : "double");
            Rf_error(
                "Stata byte storage cannot represent the value; "
                "use `dta_%s()`", wider
            );
        }
        int8_t encoded = (int8_t) value;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_INT: {
        if (!R_FINITE(value) || value != trunc(value) ||
            value < -32767.0 || value > 32740.0) {
            const char *wider = R_FINITE(value) && value == trunc(value) &&
                value >= -2147483647.0 && value <= 2147483620.0
                    ? "long" : "double";
            Rf_error(
                "Stata int storage cannot represent the value; "
                "use `dta_%s()`", wider
            );
        }
        int16_t encoded = (int16_t) value;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_LONG: {
        if (!R_FINITE(value) || value != trunc(value) ||
            value < -2147483647.0 || value > 2147483620.0) {
            Rf_error(
                "Stata long storage cannot represent the value; "
                "use `dta_double()`"
            );
        }
        int32_t encoded = (int32_t) value;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_FLOAT: {
        double maximum = numeric_float_observed_limit();
        if (!R_FINITE(value) || value < -maximum || value > maximum) {
            Rf_error(
                "Stata float storage cannot represent the value; "
                "use `dta_double()`"
            );
        }
        float encoded = (float) value;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    default:
        Rf_error("invalid compact Stata numeric storage type");
    }
}

static void write_numeric_observed_trusted(
    unsigned char *output, R_xlen_t index, int kind, double value
) {
    switch (kind) {
    case NUMERIC_BYTE: {
        int8_t encoded = (int8_t) value;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_INT: {
        int16_t encoded = (int16_t) value;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_LONG: {
        int32_t encoded = (int32_t) value;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    case NUMERIC_FLOAT: {
        float encoded = (float) value;
        memcpy(output + (size_t) index * sizeof(encoded), &encoded,
               sizeof(encoded));
        return;
    }
    default:
        Rf_error("invalid compact Stata numeric storage type");
    }
}

/* Computed-result policies remain lazy. Follow only settled values, literals,
   and symbol forwarding, never active bindings or arbitrary expressions. The
   bounded walk also declines recursive promises without changing their error. */
static SEXP computed_peek(SEXP expression, SEXP environment, int depth) {
    PROTECT_INDEX expression_root, environment_root;
    PROTECT_WITH_INDEX(expression, &expression_root);
    PROTECT_WITH_INDEX(environment, &environment_root);
    SEXP value = R_UnboundValue;
    while (depth > 0) {
        if (TYPEOF(expression) != SYMSXP) {
            if (TYPEOF(expression) != LANGSXP) value = expression;
            break;
        }
        /* Dots references use the evaluator's argument lookup, not a
           same-named ordinary binding, even through a forwarded promise. */
        if (strncmp(CHAR(PRINTNAME(expression)), "..", 2) == 0) break;
        /* Binding-type queries themselves call a user database's getter.
           Secondary arguments have not passed the primary size preflight. */
        if (TYPEOF(environment) != ENVSXP || environment == R_EmptyEnv ||
            Rf_isObject(environment) || Rf_isS4(environment)) break;
        R_BindingType_t type = R_GetBindingType(expression, environment);
        if (type == R_BindingTypeValue || type == R_BindingTypeForced) {
            value = R_getVar(expression, environment, FALSE);
            break;
        }
        if (type == R_BindingTypeDelayed) {
            SEXP next_expression = R_DelayedBindingExpression(expression, environment);
            SEXP next_environment = R_DelayedBindingEnvironment(expression, environment);
            REPROTECT(expression = next_expression, expression_root);
            REPROTECT(environment = next_environment, environment_root);
            depth--;
        } else if (type == R_BindingTypeUnbound) {
            REPROTECT(environment = R_ParentEnv(environment), environment_root);
        } else break;
    }
    PROTECT(value);
    UNPROTECT(3);
    return value;
}

/* This preflight runs before the executing closure is qualified. Reject
   custom environments before even querying binding type: a user database's
   lookup may execute code. Forced getters can process ordinary pending
   finalizers; keep both walk inputs rooted and retain no admission verdict.
   No delayed operand expression is evaluated. */
static SEXP numeric_size_peek(SEXP expression, SEXP environment) {
    PROTECT_INDEX expression_index, environment_index;
    PROTECT_WITH_INDEX(expression, &expression_index);
    PROTECT_WITH_INDEX(environment, &environment_index);
    SEXP value = R_UnboundValue;
    for (int visits = 0; visits < 64; visits++) {
        if (expression == R_UnboundValue || expression == R_MissingArg) break;
        if (TYPEOF(expression) != SYMSXP) {
            if (TYPEOF(expression) != LANGSXP) value = expression;
            break;
        }
        if (strncmp(CHAR(PRINTNAME(expression)), "..", 2) == 0) break;
        if (TYPEOF(environment) != ENVSXP || environment == R_EmptyEnv ||
            Rf_isObject(environment) || Rf_isS4(environment)) break;
        R_BindingType_t type = R_GetBindingType(expression, environment);
        if (type == R_BindingTypeValue || type == R_BindingTypeForced) {
            value = R_getVar(expression, environment, FALSE);
            break;
        }
        if (type == R_BindingTypeDelayed) {
            SEXP next_expression = R_DelayedBindingExpression(expression, environment);
            SEXP next_environment = R_DelayedBindingEnvironment(expression, environment);
            REPROTECT(expression = next_expression, expression_index);
            REPROTECT(environment = next_environment, environment_index);
        } else if (type == R_BindingTypeUnbound) {
            REPROTECT(environment = R_ParentEnv(environment), environment_index);
        } else break;
    }
    PROTECT(value);
    UNPROTECT(3);
    return value;
}

/* Length comes from an ordinary vector header or from package-owned compact
   metadata. Recognized owned reals expose their already-rooted ordinary
   backing; compact Stata ALTREPs expose the descriptor length without
   invoking an ALTREP Length or data method. Attribute values and numeric
   elements stay unread. Foreign ALTREP classes remain unknown. */
static int numeric_size_known_length(SEXP value, int scalar, R_xlen_t *length) {
    if (TYPEOF(value) != REALSXP &&
        (!scalar || (TYPEOF(value) != INTSXP && TYPEOF(value) != LGLSXP))) return 0;
    if (ALTREP(value)) {
        numeric_data *compact = unmaterialized_numeric_read_storage(value);
        if (compact != NULL) {
            if (compact->length > (size_t) R_XLEN_T_MAX) return 0;
            *length = (R_xlen_t) compact->length;
            return 1;
        }
        if (!owned_real(value)) return 0;
        SEXP record = R_altrep_data1(value);
        if (TYPEOF(record) != EXTPTRSXP) return 0;
        value = R_ExternalPtrProtected(record);
        if (TYPEOF(value) != REALSXP || ALTREP(value)) return 0;
    }
    *length = XLENGTH(value);
    return 1;
}

static int numeric_size_admitted(SEXP frame, unsigned route) {
    if (numeric_size_minimum == 0) return 1;
    int index = route == DTATOOLS_NUMERIC_SCALAR ? 0 :
                route == DTATOOLS_NUMERIC_COMPUTED ? 1 :
                route == DTATOOLS_NUMERIC_CONSTRUCT ? 2 :
                route == DTATOOLS_NUMERIC_HOLDS ? 3 : -1;
    if (index < 0) return 0;
    int argument = index == 1 ? 2 : index == 3 ? 3 : 0;
    SEXP value = PROTECT(numeric_size_peek(numeric_size_symbols[argument], frame));
    R_xlen_t length = 0;
    int known = numeric_size_known_length(value, index == 0, &length);
    UNPROTECT(1);
    if (index == 0 && known && length < numeric_size_minimum) {
        value = PROTECT(numeric_size_peek(numeric_size_symbols[1], frame));
        known = numeric_size_known_length(value, 1, &length);
        UNPROTECT(1);
    }
    int outcome = !known ? 1 : length < numeric_size_minimum ? 0 : 2;
    numeric_size_counts[index][outcome]++;
    return outcome == 2;
}

/* Diagnostic seam for checking preflight reads without invoking fallback. */
SEXP C_dtatools_test_numeric_size_gate(SEXP route) {
    if (TYPEOF(route) != INTSXP || ALTREP(route) || XLENGTH(route) != 1)
        return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(numeric_size_admitted(
        R_GetCurrentEnv(), (unsigned) INTEGER(route)[0]));
}

/* Dependency lookup must not follow an unforced promise, even a symbol that
   currently names the expected function. Skipping the original call would
   leave that binding delayed, allowing later rebinding to change its value.
   Operand forwarding above is separate: successful entries settle those
   original arguments before publishing a result. */
static SEXP computed_dependency_value(SEXP symbol, SEXP environment, int depth) {
    PROTECT(symbol);
    PROTECT_INDEX environment_root;
    PROTECT_WITH_INDEX(environment, &environment_root);
    SEXP value = R_UnboundValue;
    for (; depth > 0; depth--) {
        if (TYPEOF(environment) != ENVSXP || environment == R_EmptyEnv ||
            Rf_isObject(environment) || Rf_isS4(environment)) break;
        R_BindingType_t type = R_GetBindingType(symbol, environment);
        if (type == R_BindingTypeValue || type == R_BindingTypeForced) {
            value = R_getVar(symbol, environment, FALSE);
            break;
        }
        if (type != R_BindingTypeUnbound) break;
        REPROTECT(environment = R_ParentEnv(environment), environment_root);
    }
    PROTECT(value);
    UNPROTECT(3);
    return value;
}

static SEXP computed_attribute(SEXP name, SEXP value, void *context) {
    (void) context;
    if (name != R_NamesSymbol || TYPEOF(value) != STRSXP ||
        ALTREP(value) || ANY_ATTRIB(value) ||
        Rf_isObject(value) || Rf_isS4(value)) return R_NilValue;
    return NULL;
}

/* The R checks read .Machine$double.xmax. Admit its current ordinary value
   without invoking a binding, a $ method, or a foreign names/field reader.
   Other fields do not participate in the range check and remain unread. */
static int computed_double_limit_unchanged(SEXP frame) {
    SEXP machine = computed_dependency_value(Rf_install(".Machine"), frame, 16);
    if (TYPEOF(machine) != VECSXP || ALTREP(machine) ||
        Rf_isObject(machine) || Rf_isS4(machine) ||
        R_mapAttrib(machine, computed_attribute, NULL) != NULL) return 0;
    if (XLENGTH(machine) > 128) return 0;
    SEXP names = Rf_getAttrib(machine, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || XLENGTH(names) != XLENGTH(machine)) return 0;
    for (R_xlen_t i = 0; i < XLENGTH(machine); i++) {
        SEXP name = STRING_ELT(names, i);
        if (name == NA_STRING || strcmp(CHAR(name), "double.xmax") != 0) continue;
        SEXP limit = VECTOR_ELT(machine, i);
        return TYPEOF(limit) == REALSXP && !ALTREP(limit) &&
            !ANY_ATTRIB(limit) && !Rf_isObject(limit) && !Rf_isS4(limit) &&
            XLENGTH(limit) == 1 && REAL(limit)[0] == DBL_MAX;
    }
    return 0;
}

static int computed_dependencies_unchanged(SEXP frame, SEXP dependencies) {
    static const char *names[] = {
        "is.na", "is.infinite", "is.finite", "any", "abs", "floor",
        "!", "|", "&", "==", ">", "<", ">=", "<=", "[", "[<-",
        "attr", "names", "names<-", "[[", "length"
    };
    static SEXP symbols[sizeof(names) / sizeof(names[0])];
    if (TYPEOF(frame) != ENVSXP || TYPEOF(dependencies) != VECSXP ||
        ALTREP(dependencies) ||
        XLENGTH(dependencies) != (R_xlen_t) (sizeof(names) / sizeof(names[0]))) return 0;
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        if (symbols[i] == NULL) symbols[i] = Rf_install(names[i]);
        SEXP expected = VECTOR_ELT(dependencies, i);
        if ((TYPEOF(expected) != BUILTINSXP && TYPEOF(expected) != SPECIALSXP) ||
            computed_dependency_value(symbols[i], frame, 16) != expected) return 0;
    }
    return computed_double_limit_unchanged(frame);
}

static int computed_storage_kind(SEXP storage) {
    if (TYPEOF(storage) != STRSXP || ALTREP(storage) || ANY_ATTRIB(storage) ||
        Rf_isObject(storage) || Rf_isS4(storage) ||
        XLENGTH(storage) != 1 || STRING_ELT(storage, 0) == NA_STRING) return -1;
    const char *name = CHAR(STRING_ELT(storage, 0));
    static const char *names[] = {"byte", "int", "long", "float", "double"};
    for (int kind = 0; kind <= NUMERIC_DOUBLE; kind++)
        if (strcmp(name, names[kind]) == 0) return kind;
    return -1;
}

/* Keep valid missing payload bits, including signed/quiet NA variants. Unknown
   tag bytes decline instead of being reclassified as computational NaN. */
static double computed_normalize(double value, int *missing, int *unsupported) {
    if (ISNAN(value)) {
        int tag = tagged_na_tag_value(value);
        if (tag != 0 && (tag < 'a' || tag > 'z')) *unsupported = 1;
        *missing = tag == 0 ? 0 : tag - 'a' + 1;
        return tag != 0 || ISNA(value) ? value : NA_REAL;
    }
    if (!R_FINITE(value) || fabs(value) > DBL_MAX / 2) {
        *missing = 0;
        return NA_REAL;
    }
    *missing = -1;
    return value;
}

static unsigned computed_fit(double value) {
    unsigned fits = 1U << NUMERIC_DOUBLE;
    if (fabs(value) <= numeric_float_observed_limit()) fits |= 1U << NUMERIC_FLOAT;
    if (value == trunc(value)) {
        if (value >= -127 && value <= 100) fits |= 1U << NUMERIC_BYTE;
        if (value >= -32767 && value <= 32740) fits |= 1U << NUMERIC_INT;
        if (value >= -2147483647.0 && value <= 2147483620.0) fits |= 1U << NUMERIC_LONG;
    }
    return fits;
}

/* Return an undecorated independent payload and storage. R retains metadata
   construction, including its observable attribute/name evaluation. */
static SEXP computed_result(SEXP payload, int kind) {
    static const char *names[] = {"byte", "int", "long", "float", "double"};
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(result, 0, payload);
    SET_VECTOR_ELT(result, 1, Rf_mkString(names[kind]));
    UNPROTECT(1);
    return result;
}

/* Decorate only a fresh, unnamed payload after the complete entry proof.
   No R helper or S3 method runs after omitted local state would be observable. */
static SEXP numeric_decorate_result(SEXP payload, SEXP storage) {
    int kind = computed_storage_kind(storage);
    if (payload == R_NilValue || kind < 0) return R_NilValue;
    static const char *storage_classes[] = {
        "dta_byte", "dta_int", "dta_long", "dta_float", "dta_double"
    };
    PROTECT(payload);
    PROTECT(storage);
    SEXP classes = PROTECT(Rf_allocVector(STRSXP, 4));
    SET_STRING_ELT(classes, 0, Rf_mkChar("dta_numeric"));
    SET_STRING_ELT(classes, 1, Rf_mkChar(storage_classes[kind]));
    SET_STRING_ELT(classes, 2, Rf_mkChar("vctrs_vctr"));
    SET_STRING_ELT(classes, 3, Rf_mkChar("double"));
    Rf_setAttrib(payload, Rf_install("stata.storage"), storage);
    Rf_setAttrib(payload, R_ClassSymbol, classes);
    UNPROTECT(3);
    return payload;
}

/* Minimum admission follows the actual argument and its evaluation
   environment. Only the canonical attribute getter
   on a settled symbol can be substituted without evaluating arbitrary R code. */
static SEXP computed_minimum_expression(
    SEXP expression, SEXP environment, SEXP storage_getter,
    SEXP getter_symbol, SEXP argument_symbol, SEXP storage_symbol, int depth
) {
    PROTECT_INDEX expression_root, environment_root;
    PROTECT_WITH_INDEX(expression, &expression_root);
    PROTECT_WITH_INDEX(environment, &environment_root);
    SEXP value = R_UnboundValue;
    while (depth > 0 && expression != R_MissingArg) {
        if (TYPEOF(expression) == SYMSXP) {
            if (strncmp(CHAR(PRINTNAME(expression)), "..", 2) == 0) break;
            if (TYPEOF(environment) != ENVSXP || environment == R_EmptyEnv ||
                Rf_isObject(environment) || Rf_isS4(environment)) break;
            R_BindingType_t type = R_GetBindingType(expression, environment);
            if (type == R_BindingTypeValue || type == R_BindingTypeForced) {
                value = R_getVar(expression, environment, FALSE);
                break;
            }
            if (type == R_BindingTypeDelayed) {
                SEXP next_expression = R_DelayedBindingExpression(expression, environment);
                SEXP next_environment = R_DelayedBindingEnvironment(expression, environment);
                REPROTECT(expression = next_expression, expression_root);
                REPROTECT(environment = next_environment, environment_root);
                depth--;
            } else if (type == R_BindingTypeUnbound) {
                REPROTECT(environment = R_ParentEnv(environment), environment_root);
            } else break;
            continue;
        }
        if (TYPEOF(expression) != LANGSXP) {
            value = expression;
            break;
        }
        if (ANY_ATTRIB(expression) || TAG(expression) != R_NilValue ||
            CAR(expression) != getter_symbol) break;
        SEXP argument = CDR(expression);
        if (TYPEOF(argument) != LISTSXP || ANY_ATTRIB(argument) ||
            CDR(argument) != R_NilValue || TYPEOF(CAR(argument)) != SYMSXP ||
            CAR(argument) == R_MissingArg ||
            (TAG(argument) != R_NilValue && TAG(argument) != argument_symbol)) break;
        SEXP getter = PROTECT(computed_dependency_value(getter_symbol, environment, 16));
        int same = dtatools_execution_function_same(getter, storage_getter);
        UNPROTECT(1);
        if (!same) break;
        SEXP source = PROTECT(computed_peek(CAR(argument), environment, 16));
        if (TYPEOF(source) == REALSXP) value = Rf_getAttrib(source, storage_symbol);
        UNPROTECT(1);
        break;
    }
    PROTECT(value);
    UNPROTECT(3);
    return value;
}

static SEXP computed_minimum(SEXP frame, SEXP storage_getter) {
    /* Intern names before borrowing any value from a delayed binding. */
    SEXP minimum_symbol = Rf_install("minimum");
    SEXP getter_symbol = Rf_install(".declared_dta_storage");
    SEXP argument_symbol = Rf_install("x");
    SEXP storage_symbol = Rf_install("stata.storage");
    return computed_minimum_expression(minimum_symbol, frame, storage_getter,
        getter_symbol, argument_symbol, storage_symbol, 16);
}

/* Source references are not executable. Do not inspect their values, which
   can contain arbitrary environments or foreign vectors. Every other syntax
   attribute declines. Compare only bounded ordinary syntax and literals. */
static SEXP scalar_source_attribute(SEXP name, SEXP value, void *context) {
    (void) value; (void) context;
    const char *text = CHAR(PRINTNAME(name));
    return strcmp(text, "srcref") == 0 || strcmp(text, "srcfile") == 0 ||
        strcmp(text, "wholeSrcref") == 0 ? NULL : R_NilValue;
}

static int scalar_same_expression(SEXP left, SEXP right, int *remaining) {
    if (--*remaining < 0 || TYPEOF(left) != TYPEOF(right) ||
        ALTREP(left) || ALTREP(right)) return 0;
    if (TYPEOF(left) == LANGSXP || TYPEOF(left) == LISTSXP) {
        if (R_mapAttrib(left, scalar_source_attribute, NULL) != NULL ||
            R_mapAttrib(right, scalar_source_attribute, NULL) != NULL) return 0;
        return TAG(left) == TAG(right) &&
            scalar_same_expression(CAR(left), CAR(right), remaining) &&
            scalar_same_expression(CDR(left), CDR(right), remaining);
    }
    if (ANY_ATTRIB(left) || ANY_ATTRIB(right)) return 0;
    switch (TYPEOF(left)) {
    case NILSXP: case SYMSXP: return left == right;
    case LGLSXP: case INTSXP: case REALSXP: case STRSXP: case CHARSXP:
        return R_compute_identical(left, right, IDENT_NUM_AS_BITS | IDENT_NA_AS_BITS);
    default: return 0;
    }
}

static int scalar_same_function_bounded(SEXP actual, SEXP expected, int remaining) {
    if (TYPEOF(actual) != TYPEOF(expected)) return 0;
    if (TYPEOF(actual) == BUILTINSXP || TYPEOF(actual) == SPECIALSXP)
        return actual == expected;
    if (TYPEOF(actual) != CLOSXP ||
        R_ClosureEnv(actual) != R_ClosureEnv(expected) ||
        R_mapAttrib(actual, scalar_source_attribute, NULL) != NULL ||
        R_mapAttrib(expected, scalar_source_attribute, NULL) != NULL) return 0;
    return scalar_same_expression(R_ClosureFormals(actual), R_ClosureFormals(expected),
                                  &remaining) &&
        scalar_same_expression(R_ClosureExpr(actual), R_ClosureExpr(expected), &remaining);
}

static int scalar_same_function(SEXP actual, SEXP expected) {
    return scalar_same_function_bounded(actual, expected, 512);
}

/* A descriptor contains only trusted expected data, never a successful
   verdict about a live function. Shipped expectations were deep-copied at
   build time. This native copy additionally owns independent literal vectors.
   All SEXP fields are rooted through the external pointer's protected pair:
   the expected profile and the literal-root list. No actual SEXP is retained. */
typedef struct {
    SEXPTYPE type;
    int car, cdr;
    SEXP tag, literal;
    R_xlen_t length;
} numeric_expected_node;

typedef struct {
    SEXPTYPE type;
    SEXP function, environment, body;
    numeric_expected_node *nodes;
    int node_count, used, formals, expression;
} numeric_expected_function;

typedef struct {
    int count;
    numeric_expected_function *functions;
} numeric_expected_profile;

static SEXP numeric_expected_tag = NULL;
static double numeric_expected_successes = 0;
static double numeric_expected_closure_successes = 0;

SEXP C_dtatools_numeric_proof_stats(SEXP reset) {
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 2));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 2));
    REAL(result)[0] = numeric_expected_successes;
    REAL(result)[1] = numeric_expected_closure_successes;
    SET_STRING_ELT(names, 0, Rf_mkChar("functions"));
    SET_STRING_ELT(names, 1, Rf_mkChar("closures"));
    Rf_setAttrib(result, R_NamesSymbol, names);
    if (Rf_asLogical(reset) == TRUE)
        numeric_expected_successes = numeric_expected_closure_successes = 0;
    UNPROTECT(2);
    return result;
}

static void numeric_expected_finalize(SEXP external) {
    numeric_expected_profile *profile = R_ExternalPtrAddr(external);
    if (profile == NULL) return;
    R_ClearExternalPtr(external);
    for (int i = 0; i < profile->count; i++) free(profile->functions[i].nodes);
    free(profile->functions);
    free(profile);
}

static numeric_expected_profile *numeric_expected_profile_get(SEXP value) {
    if (TYPEOF(value) != EXTPTRSXP || numeric_expected_tag == NULL ||
        R_ExternalPtrTag(value) != numeric_expected_tag) return NULL;
    return R_ExternalPtrAddr(value);
}

/* Count only the ordinary syntax already certified by the old exact proof.
   Its joint 4096-node formals/source bound precedes this trusted traversal. */
static int numeric_expected_node_count(SEXP value) {
    if (TYPEOF(value) != LANGSXP && TYPEOF(value) != LISTSXP) return 1;
    return 1 + numeric_expected_node_count(CAR(value)) +
        numeric_expected_node_count(CDR(value));
}

static int numeric_expected_compile_node(
    SEXP value, numeric_expected_function *function, SEXP roots, int *root_index
) {
    int index = function->used++;
    numeric_expected_node *node = &function->nodes[index];
    node->type = TYPEOF(value);
    if (node->type == LANGSXP || node->type == LISTSXP) {
        node->tag = TAG(value);
        node->car = numeric_expected_compile_node(CAR(value), function, roots, root_index);
        node->cdr = numeric_expected_compile_node(CDR(value), function, roots, root_index);
    } else if (node->type == NILSXP || node->type == SYMSXP) {
        node->literal = value;
    } else {
        SEXP literal = PROTECT(Rf_duplicate(value));
        SET_VECTOR_ELT(roots, (*root_index)++, literal);
        node->literal = literal;
        node->length = node->type == CHARSXP ? 0 : XLENGTH(literal);
        UNPROTECT(1);
    }
    return index;
}

SEXP C_dtatools_expected_numeric_profile(SEXP profile, SEXP count_value) {
    if (TYPEOF(profile) != VECSXP || ALTREP(profile) ||
        TYPEOF(count_value) != INTSXP || ALTREP(count_value) || ANY_ATTRIB(count_value) ||
        XLENGTH(count_value) != 1 || INTEGER(count_value)[0] < 1 ||
        INTEGER(count_value)[0] > 128 || XLENGTH(profile) < INTEGER(count_value)[0])
        return R_NilValue;
    int count = INTEGER(count_value)[0], total_nodes = 0;
    for (int i = 0; i < count; i++) {
        SEXP expected = VECTOR_ELT(profile, i);
        if (!scalar_same_function_bounded(expected, expected, 4096)) return R_NilValue;
        if (TYPEOF(expected) == CLOSXP) {
            if (TYPEOF(R_ClosureBody(expected)) != BCODESXP) return R_NilValue;
            total_nodes += numeric_expected_node_count(R_ClosureFormals(expected)) +
                numeric_expected_node_count(R_ClosureExpr(expected));
        }
    }
    if (numeric_expected_tag == NULL)
        numeric_expected_tag = Rf_install("dtatools.expected.numeric.profile");
    SEXP roots = PROTECT(Rf_allocVector(VECSXP, total_nodes));
    SEXP anchor = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(anchor, 0, profile);
    SET_VECTOR_ELT(anchor, 1, roots);
    SEXP external = PROTECT(R_MakeExternalPtr(NULL, numeric_expected_tag, anchor));
    R_RegisterCFinalizerEx(external, numeric_expected_finalize, TRUE);
    numeric_expected_profile *prepared = calloc(1, sizeof(*prepared));
    if (prepared == NULL) { UNPROTECT(3); return R_NilValue; }
    R_SetExternalPtrAddr(external, prepared);
    prepared->functions = calloc((size_t) count, sizeof(*prepared->functions));
    if (prepared->functions == NULL) {
        numeric_expected_finalize(external);
        UNPROTECT(3);
        return R_NilValue;
    }
    prepared->count = count;
    int root_index = 0;
    for (int i = 0; i < count; i++) {
        SEXP expected = VECTOR_ELT(profile, i);
        numeric_expected_function *function = &prepared->functions[i];
        function->type = TYPEOF(expected);
        function->function = expected;
        if (function->type != CLOSXP) continue;
        function->environment = R_ClosureEnv(expected);
        function->body = R_ClosureBody(expected);
        function->node_count = numeric_expected_node_count(R_ClosureFormals(expected)) +
            numeric_expected_node_count(R_ClosureExpr(expected));
        function->nodes = calloc((size_t) function->node_count, sizeof(*function->nodes));
        if (function->nodes == NULL) {
            numeric_expected_finalize(external);
            UNPROTECT(3);
            return R_NilValue;
        }
        function->formals = numeric_expected_compile_node(
            R_ClosureFormals(expected), function, roots, &root_index);
        function->expression = numeric_expected_compile_node(
            R_ClosureExpr(expected), function, roots, &root_index);
    }
    UNPROTECT(3);
    return external;
}

/* Exact live syntax qualification remains before the fresh bytecode proof.
   The descriptor fixes the traversal bound; cycles or a different tree shape
   necessarily mismatch before walking beyond the trusted expected structure. */
static int numeric_expected_expression_same(
    SEXP actual, const numeric_expected_function *function, int index
) {
    const numeric_expected_node *node = &function->nodes[index];
    if (TYPEOF(actual) != node->type || ALTREP(actual)) return 0;
    if (node->type == LANGSXP || node->type == LISTSXP) {
        if (ANY_ATTRIB(actual) &&
            R_mapAttrib(actual, scalar_source_attribute, NULL) != NULL) return 0;
        return TAG(actual) == node->tag &&
            numeric_expected_expression_same(CAR(actual), function, node->car) &&
            numeric_expected_expression_same(CDR(actual), function, node->cdr);
    }
    if (ANY_ATTRIB(actual)) return 0;
    switch (node->type) {
    case NILSXP: case SYMSXP: return actual == node->literal;
    case LGLSXP:
        return XLENGTH(actual) == node->length &&
            memcmp(LOGICAL(actual), LOGICAL(node->literal), (size_t) node->length * sizeof(int)) == 0;
    case INTSXP:
        return XLENGTH(actual) == node->length &&
            memcmp(INTEGER(actual), INTEGER(node->literal), (size_t) node->length * sizeof(int)) == 0;
    case REALSXP:
        return XLENGTH(actual) == node->length &&
            memcmp(REAL(actual), REAL(node->literal), (size_t) node->length * sizeof(double)) == 0;
    case STRSXP: case CHARSXP:
        return R_compute_identical(actual, node->literal, IDENT_NUM_AS_BITS | IDENT_NA_AS_BITS);
    default: return 0;
    }
}

/* R_compute_identical can read ALTREP values nested in bytecode constants,
   including their attributes. Check both graphs without invoking getters;
   unfamiliar or cyclic graphs retain the ordinary R path. */
static int numeric_bytecode_plain(SEXP value, int *remaining, int depth);

typedef struct {
    int *remaining;
    int depth;
} numeric_bytecode_attribute_context;

static SEXP numeric_bytecode_plain_attribute(SEXP name, SEXP value, void *data) {
    numeric_bytecode_attribute_context *ctx = data;
    /* Decline malformed tags and row names before identical inspects them. */
    if (TYPEOF(name) != SYMSXP || ANY_ATTRIB(name) ||
        name == R_RowNamesSymbol) return R_NilValue;
    return numeric_bytecode_plain(value, ctx->remaining, ctx->depth + 1)
        ? NULL : R_NilValue;
}

static int numeric_bytecode_plain(SEXP value, int *remaining, int depth) {
    if (--*remaining < 0 || depth > 256 || ALTREP(value)) return 0;
    /* identical.c skips CHARSXP cache attributes; symbol attributes can be
       compared, but cannot safely be walked with R_mapAttrib here. Decline
       those symbols. R_mapAttrib visits raw ATTRIB pairs, so it cannot expand
       row names; nevertheless row.names is declined because identical.c may. */
    if (TYPEOF(value) == SYMSXP && ANY_ATTRIB(value)) return 0;
    if (TYPEOF(value) != CHARSXP && TYPEOF(value) != SYMSXP &&
        ANY_ATTRIB(value)) {
        numeric_bytecode_attribute_context ctx = {remaining, depth};
        if (R_mapAttrib(value, numeric_bytecode_plain_attribute, &ctx) != NULL)
            return 0;
    }
    switch (TYPEOF(value)) {
    case NILSXP: case SYMSXP: case CHARSXP: case ENVSXP:
    case BUILTINSXP: case SPECIALSXP:
    case LGLSXP: case INTSXP: case REALSXP: case CPLXSXP: case RAWSXP:
    case STRSXP:
        return 1;
    case LANGSXP: case LISTSXP: case DOTSXP:
    case BCODESXP:
        return numeric_bytecode_plain(CAR(value), remaining, depth + 1) &&
            numeric_bytecode_plain(TAG(value), remaining, depth + 1) &&
            numeric_bytecode_plain(CDR(value), remaining, depth + 1);
    case CLOSXP:
        return numeric_bytecode_plain(R_ClosureFormals(value), remaining, depth + 1) &&
            numeric_bytecode_plain(R_ClosureBody(value), remaining, depth + 1);
    case VECSXP: case EXPRSXP: {
        R_xlen_t n = XLENGTH(value);
        if (n > *remaining) return 0;
        for (R_xlen_t i = 0; i < n; i++)
            if (!numeric_bytecode_plain(VECTOR_ELT(value, i), remaining, depth + 1))
                return 0;
        return 1;
    }
    default: return 0;
    }
}

/* Compare both graphs in one traversal. Recursive nodes with attributes or
   unfamiliar types decline; canonical bytecode attributes occur only on
   integer metadata. Attribute values are checked before R compares that
   leaf, so neither path can invoke an ALTREP getter during admission. */
static int numeric_bytecode_equal_plain(SEXP left, SEXP right, int *remaining, int depth) {
    if (--*remaining < 0 || depth > 256 || TYPEOF(left) != TYPEOF(right) ||
        ALTREP(left) || ALTREP(right) || Rf_isObject(left) != Rf_isObject(right) ||
        Rf_isS4(left) != Rf_isS4(right)) return 0;
    int type = TYPEOF(left);
    if (type == SYMSXP && (ANY_ATTRIB(left) || ANY_ATTRIB(right))) return 0;
    if (type != CHARSXP && type != SYMSXP &&
        (ANY_ATTRIB(left) || ANY_ATTRIB(right))) {
        if (type != INTSXP || !ANY_ATTRIB(left) || !ANY_ATTRIB(right) ||
            !numeric_bytecode_plain(left, remaining, depth) ||
            !numeric_bytecode_plain(right, remaining, depth)) return 0;
        return R_compute_identical(left, right, IDENT_USE_BYTECODE);
    }
    switch (type) {
    case NILSXP: case SYMSXP: case ENVSXP:
        return left == right;
    case CHARSXP: case BUILTINSXP: case SPECIALSXP:
    case LGLSXP: case INTSXP: case REALSXP: case CPLXSXP:
    case RAWSXP: case STRSXP:
        return left == right || R_compute_identical(left, right, IDENT_USE_BYTECODE);
    case LANGSXP: case LISTSXP: case DOTSXP:
        if (TAG(left) != TAG(right) ||
            (TAG(left) != R_NilValue &&
             (TYPEOF(TAG(left)) != SYMSXP || ANY_ATTRIB(TAG(left))))) return 0;
        return numeric_bytecode_equal_plain(CAR(left), CAR(right), remaining, depth + 1) &&
            numeric_bytecode_equal_plain(CDR(left), CDR(right), remaining, depth + 1);
    case BCODESXP:
        return numeric_bytecode_equal_plain(CAR(left), CAR(right), remaining, depth + 1) &&
            numeric_bytecode_equal_plain(TAG(left), TAG(right), remaining, depth + 1) &&
            numeric_bytecode_equal_plain(CDR(left), CDR(right), remaining, depth + 1);
    case CLOSXP:
        return R_ClosureEnv(left) == R_ClosureEnv(right) &&
            numeric_bytecode_equal_plain(R_ClosureFormals(left), R_ClosureFormals(right),
                                         remaining, depth + 1) &&
            numeric_bytecode_equal_plain(R_ClosureBody(left), R_ClosureBody(right),
                                         remaining, depth + 1);
    case VECSXP: case EXPRSXP: {
        R_xlen_t n = XLENGTH(left);
        if (n != XLENGTH(right) || n > *remaining) return 0;
        for (R_xlen_t i = 0; i < n; i++)
            if (!numeric_bytecode_equal_plain(VECTOR_ELT(left, i), VECTOR_ELT(right, i),
                                              remaining, depth + 1)) return 0;
        return 1;
    }
    default: return 0;
    }
}

/* A fresh local table remembers only pairs completely checked by this
   callback-free strict comparator. Unfamiliar graphs retain the original
   guarded comparison. No entry survives a comparison call. */
typedef struct {
    SEXP left[2048], right[2048];
    unsigned char occupied[2048];
    int remaining;
} scalar_strict_memo;
static int scalar_strict_equal(SEXP left, SEXP right, scalar_strict_memo *memo, int depth);
typedef struct { SEXP tags[64], values[64]; int count; } scalar_strict_attrs;
static SEXP scalar_strict_collect_attribute(SEXP tag, SEXP value, void *data) {
    scalar_strict_attrs *attrs = data;
    if (attrs->count >= 64 || TYPEOF(tag) != SYMSXP || ANY_ATTRIB(tag) ||
        tag == R_RowNamesSymbol) return R_NilValue;
    attrs->tags[attrs->count] = tag;
    attrs->values[attrs->count++] = value;
    return NULL;
}
static int scalar_strict_attributes(SEXP left, SEXP right,
                                    scalar_strict_memo *memo, int depth) {
    scalar_strict_attrs a = {.count = 0}, b = {.count = 0};
    if (R_mapAttrib(left, scalar_strict_collect_attribute, &a) != NULL ||
        R_mapAttrib(right, scalar_strict_collect_attribute, &b) != NULL ||
        a.count != b.count) return 0;
    for (int i = 0; i < a.count; i++) {
        if (--memo->remaining < 0 || a.tags[i] != b.tags[i] ||
            TYPEOF(a.values[i]) == CLOSXP || TYPEOF(b.values[i]) == CLOSXP ||
            !scalar_strict_equal(a.values[i], b.values[i], memo, depth + 1)) return 0;
    }
    return 1;
}
static int scalar_strict_equal(SEXP left, SEXP right, scalar_strict_memo *memo, int depth) {
    if (--memo->remaining < 0 || depth > 256 || TYPEOF(left) != TYPEOF(right) ||
        ALTREP(left) || ALTREP(right) || Rf_isObject(left) != Rf_isObject(right) ||
        Rf_isS4(left) != Rf_isS4(right)) return 0;
    int type = TYPEOF(left);
    if (type == SYMSXP && (ANY_ATTRIB(left) || ANY_ATTRIB(right))) return 0;
    if (type != CHARSXP && type != SYMSXP &&
        (ANY_ATTRIB(left) || ANY_ATTRIB(right))) {
        if (type != INTSXP || !ANY_ATTRIB(left) || !ANY_ATTRIB(right) ||
            !scalar_strict_attributes(left, right, memo, depth + 1)) return 0;
    }
    switch (type) {
    case NILSXP: case SYMSXP: case ENVSXP:
    case CHARSXP: case BUILTINSXP: case SPECIALSXP:
        return left == right;
    case LGLSXP: case INTSXP:
        if (XLENGTH(left) != XLENGTH(right) ||
            (uint64_t)XLENGTH(left) > SIZE_MAX / sizeof(int)) return 0;
        return memcmp(type == LGLSXP ? (const void *)LOGICAL(left) : (const void *)INTEGER(left),
                   type == LGLSXP ? (const void *)LOGICAL(right) : (const void *)INTEGER(right),
                   (size_t)XLENGTH(left) * sizeof(int)) == 0;
    case REALSXP:
        if (XLENGTH(left) != XLENGTH(right) ||
            (uint64_t)XLENGTH(left) > SIZE_MAX / sizeof(double)) return 0;
        return memcmp(REAL(left), REAL(right), (size_t)XLENGTH(left) * sizeof(double)) == 0;
    case CPLXSXP:
        if (XLENGTH(left) != XLENGTH(right) ||
            (uint64_t)XLENGTH(left) > SIZE_MAX / sizeof(Rcomplex)) return 0;
        return memcmp(COMPLEX(left), COMPLEX(right), (size_t)XLENGTH(left) * sizeof(Rcomplex)) == 0;
    case RAWSXP:
        if (XLENGTH(left) != XLENGTH(right) ||
            (uint64_t)XLENGTH(left) > SIZE_MAX) return 0;
        return memcmp(RAW(left), RAW(right), (size_t)XLENGTH(left)) == 0;
    case STRSXP:
        if (XLENGTH(left) != XLENGTH(right)) return 0;
        for (R_xlen_t i = 0; i < XLENGTH(left); i++)
            if (STRING_ELT(left, i) != STRING_ELT(right, i)) return 0;
        return 1;
    case LANGSXP: case LISTSXP: case DOTSXP: case BCODESXP:
    case CLOSXP: case VECSXP: case EXPRSXP: break;
    default: return 0;
    }
    uintptr_t l = (uintptr_t)left, r = (uintptr_t)right;
    size_t slot = ((l >> 4) ^ (r >> 7) ^ (l >> 19) ^ (r >> 29)) & 2047U;
    size_t empty = 2048;
    for (size_t n = 0; n < 2048; n++, slot = (slot + 1) & 2047U) {
        if (!memo->occupied[slot]) { empty = slot; break; }
        if (memo->left[slot] == left && memo->right[slot] == right) {
            return 1;
        }
    }
    if (empty == 2048) return 0;
    int same = 0;
    if (type == LANGSXP || type == LISTSXP || type == DOTSXP) {
        same = TAG(left) == TAG(right) &&
            (TAG(left) == R_NilValue ||
             (TYPEOF(TAG(left)) == SYMSXP && !ANY_ATTRIB(TAG(left)))) &&
            scalar_strict_equal(CAR(left), CAR(right), memo, depth + 1) &&
            scalar_strict_equal(CDR(left), CDR(right), memo, depth + 1);
    } else if (type == BCODESXP) {
        same = scalar_strict_equal(CAR(left), CAR(right), memo, depth + 1) &&
            scalar_strict_equal(TAG(left), TAG(right), memo, depth + 1) &&
            scalar_strict_equal(CDR(left), CDR(right), memo, depth + 1);
    } else if (type == CLOSXP) {
        same = R_ClosureEnv(left) == R_ClosureEnv(right) &&
            scalar_strict_equal(R_ClosureFormals(left), R_ClosureFormals(right), memo, depth + 1) &&
            scalar_strict_equal(R_ClosureBody(left), R_ClosureBody(right), memo, depth + 1);
    } else {
        R_xlen_t n = XLENGTH(left);
        if (n == XLENGTH(right) && n <= memo->remaining) {
            same = 1;
            for (R_xlen_t i = 0; i < n; i++)
                if (!scalar_strict_equal(VECTOR_ELT(left, i), VECTOR_ELT(right, i),
                                         memo, depth + 1)) { same = 0; break; }
        }
    }
    if (same) {
        /* Descendants can fill the first empty slot; find a fresh slot. */
        slot = ((l >> 4) ^ (r >> 7) ^ (l >> 19) ^ (r >> 29)) & 2047U;
        for (size_t n = 0; n < 2048; n++, slot = (slot + 1) & 2047U) {
            if (!memo->occupied[slot]) {
                memo->occupied[slot] = 1;
                memo->left[slot] = left;
                memo->right[slot] = right;
                break;
            }
        }
    }
    return same;
}

static int numeric_bytecode_identical_safe(SEXP left, SEXP right) {
    if (TYPEOF(left) != BCODESXP || TYPEOF(right) != BCODESXP) return 0;
    scalar_strict_memo memo = {.occupied = {0}, .remaining = 131072};
    if (scalar_strict_equal(left, right, &memo, 0)) return 1;
    int remaining = 131072;
    return numeric_bytecode_equal_plain(left, right, &remaining, 0);
}

static int numeric_expected_function_same(
    SEXP actual, const numeric_expected_function *expected
) {
    if (TYPEOF(actual) != expected->type) return 0;
    if (expected->type == BUILTINSXP || expected->type == SPECIALSXP) {
        int same = actual == expected->function;
        if (same) numeric_expected_successes++;
        return same;
    }
    if (expected->type != CLOSXP || R_ClosureEnv(actual) != expected->environment ||
        (ANY_ATTRIB(actual) && R_mapAttrib(actual, scalar_source_attribute, NULL) != NULL)) return 0;
    /* On the pinned R build, R_ClosureExpr() is bytecode constant zero.
       The full body comparison below already checks that constant, so a
       second walk of the same source expression adds work without proof. */
    if (!numeric_expected_expression_same(R_ClosureFormals(actual), expected, expected->formals))
        return 0;
    int same = numeric_bytecode_identical_safe(R_ClosureBody(actual), expected->body);
    if (same) {
        numeric_expected_successes++;
        numeric_expected_closure_successes++;
    }
    return same;
}

static int numeric_expected_lexical_same(
    SEXP env, SEXP symbol, const numeric_expected_function *expected
) {
    /* Same ordinary-environment and settled-binding rules as the original
       numeric helper profile; do not coalesce either lexical lookup. */
    for (int depth = 0; depth < 16 && env != R_EmptyEnv; depth++) {
        if (TYPEOF(env) != ENVSXP || Rf_isObject(env) || Rf_isS4(env)) return 0;
        R_BindingType_t type = R_GetBindingType(symbol, env);
        if (type == R_BindingTypeValue || type == R_BindingTypeForced) {
            SEXP actual = PROTECT(R_getVar(symbol, env, FALSE));
            int same = numeric_expected_function_same(actual, expected);
            UNPROTECT(1);
            return same;
        }
        if (type != R_BindingTypeUnbound) return 0;
        env = R_ParentEnv(env);
    }
    return 0;
}

/* Scratch diagnostic seam uses the production comparator, without retaining
   its verdict. The caller creates an independent trusted expected fixture. */
SEXP C_dtatools_test_numeric_proof(SEXP actual, SEXP external, SEXP index_value) {
    numeric_expected_profile *profile = numeric_expected_profile_get(external);
    if (profile == NULL || TYPEOF(index_value) != INTSXP || ALTREP(index_value) ||
        XLENGTH(index_value) != 1 || INTEGER(index_value)[0] < 1 ||
        INTEGER(index_value)[0] > profile->count) return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(numeric_expected_function_same(
        actual, &profile->functions[INTEGER(index_value)[0] - 1]));
}

SEXP C_dtatools_test_numeric_old_proof(SEXP actual, SEXP expected) {
    return Rf_ScalarLogical(dtatools_execution_function_same(actual, expected));
}

/* Package helpers have larger ordinary bodies than the small wrapper profile.
   The source proof bounds every ordinary syntax/literal visit before comparing
   standard compiler output. Private AST-inconsistent bytecode is outside this
   compatibility contract. */
int dtatools_execution_function_same(SEXP actual, SEXP expected) {
    if (!scalar_same_function_bounded(actual, expected, 4096)) return 0;
    if (TYPEOF(actual) != CLOSXP) return 1;
    return TYPEOF(R_ClosureBody(actual)) == BCODESXP &&
        TYPEOF(R_ClosureBody(expected)) == BCODESXP &&
        numeric_bytecode_identical_safe(R_ClosureBody(actual), R_ClosureBody(expected));
}

/* The audited vctrs/rlang wrappers have source-reference-sensitive bytecode,
   but their complete reached R graph on these bare operands is only braces,
   .External2 and imported list2. Check all lexical function bindings so source
   equivalence remains sufficient after ordinary compiler transformations. */
static int scalar_wrapper_bindings_unchanged(SEXP wrapper, SEXP dependencies) {
    static const char *names[] = {"{", ".External2"};
    if (TYPEOF(wrapper) != CLOSXP) return 0;
    for (int i = 0; i < 2; i++) {
        SEXP expected = VECTOR_ELT(dependencies, i + 14);
        if ((TYPEOF(expected) != BUILTINSXP && TYPEOF(expected) != SPECIALSXP) ||
            computed_dependency_value(Rf_install(names[i]), R_ClosureEnv(wrapper), 16) != expected)
            return 0;
    }
    return 1;
}

/* The scalar and grouped paths both omit a vctrs namespace export lookup. */
static SEXP vctrs_exported_function(
    SEXP frame, SEXP ns, const char *name, SEXP expected_colon
);

static int scalar_dependencies_unchanged(SEXP frame, SEXP dependencies) {
    if (TYPEOF(dependencies) != VECSXP || ALTREP(dependencies) ||
        XLENGTH(dependencies) != 16) return 0;
    SEXP ns = VECTOR_ELT(dependencies, 8);
    if (TYPEOF(ns) != ENVSXP) return 0;
    SEXP recycle = vctrs_exported_function(
        frame, ns, "vec_recycle_common", VECTOR_ELT(dependencies, 5));
    if (!scalar_same_function(recycle, VECTOR_ELT(dependencies, 0)) ||
        !scalar_wrapper_bindings_unchanged(recycle, dependencies)) return 0;
    SEXP list2 = computed_dependency_value(Rf_install("list2"), ns, 16);
    if (!scalar_wrapper_bindings_unchanged(list2, dependencies)) return 0;
    if (!scalar_same_function(list2,
                              VECTOR_ELT(dependencies, 9)) ||
        !dtatools_execution_function_same(computed_dependency_value(Rf_install("withCallingHandlers"), R_BaseEnv, 16),
                              VECTOR_ELT(dependencies, 10)) ||
        !dtatools_execution_function_same(computed_dependency_value(Rf_install("parent.frame"), R_BaseEnv, 16),
                              VECTOR_ELT(dependencies, 11)) ||
        !scalar_same_function(computed_dependency_value(Rf_install("list"), R_BaseEnv, 16),
                              VECTOR_ELT(dependencies, 13))) return 0;
    static const char *names[] = {
        "getExportedValue", "suppressWarnings", "+", "-", "::", "is.numeric", "as.double"
    };
    for (int i = 0; i < 7; i++) {
        SEXP actual = computed_dependency_value(Rf_install(names[i]), frame, 16);
        if (!dtatools_execution_function_same(actual, VECTOR_ELT(dependencies, i + 1))) return 0;
    }
    return computed_dependencies_unchanged(frame, VECTOR_ELT(dependencies, 12));
}

/* Scratch cost screen: the existing build-owned external scalar profile,
   without the 53-entry package-private helper profile. */
SEXP C_dtatools_probe_scalar_public_dependencies(SEXP dependencies) {
    return Rf_ScalarLogical(scalar_dependencies_unchanged(
        R_GetCurrentEnv(), dependencies));
}

/* Scratch-only fast continuation after C_dtatools_probe_public_fused_guard()
   has just qualified the 50 public roots on this same operation. Keep the
   scalar profile's lexical/export, primitive, and numeric-dependency checks;
   replace six duplicate source/bytecode walks with fresh value-identity
   checks against the independently qualified public-root capture. */
int dtatools_probe_scalar_public_dependencies_after50(
    SEXP dependencies, SEXP public_state
) {
    if (TYPEOF(dependencies) != VECSXP || ALTREP(dependencies) ||
        XLENGTH(dependencies) != 16 || TYPEOF(public_state) != ENVSXP)
        return 0;
    SEXP live_sym = Rf_install("live");
    R_BindingType_t live_kind = R_GetBindingType(live_sym, public_state);
    if (live_kind != R_BindingTypeValue && live_kind != R_BindingTypeForced)
        return 0;
    SEXP live = R_getVarEx(live_sym, public_state, FALSE, R_NilValue);
    if (TYPEOF(live) != VECSXP || ALTREP(live) || XLENGTH(live) != 58)
        return 0;
    SEXP frame = R_GetCurrentEnv();
    SEXP ns = VECTOR_ELT(dependencies, 8);
    if (TYPEOF(ns) != ENVSXP) return 0;
    SEXP recycle = vctrs_exported_function(
        frame, ns, "vec_recycle_common", VECTOR_ELT(dependencies, 5));
    if (recycle != VECTOR_ELT(live, 40) ||
        !scalar_wrapper_bindings_unchanged(recycle, dependencies))
        return 0;
    SEXP list2 = computed_dependency_value(Rf_install("list2"), ns, 16);
    if (list2 != VECTOR_ELT(live, 39) ||
        !scalar_wrapper_bindings_unchanged(list2, dependencies))
        return 0;
    if (computed_dependency_value(Rf_install("withCallingHandlers"),
                                  R_BaseEnv, 16) != VECTOR_ELT(live, 32) ||
        computed_dependency_value(Rf_install("parent.frame"),
                                  R_BaseEnv, 16) != VECTOR_ELT(live, 12) ||
        !scalar_same_function(computed_dependency_value(Rf_install("list"),
                                                        R_BaseEnv, 16),
                              VECTOR_ELT(dependencies, 13)))
        return 0;
    static const char *names[] = {
        "getExportedValue", "suppressWarnings", "+", "-", "::",
        "is.numeric", "as.double"
    };
    for (int i = 0; i < 7; i++) {
        SEXP actual = computed_dependency_value(Rf_install(names[i]), frame, 16);
        if (i == 0 || i == 1) {
            if (actual != VECTOR_ELT(live, i == 0 ? 14 : 13))
                return 0;
        } else if (!dtatools_execution_function_same(
                       actual, VECTOR_ELT(dependencies, i + 1)))
            return 0;
    }
    return computed_dependencies_unchanged(
        frame, VECTOR_ELT(dependencies, 12));
}

/* Scratch caller-operator check for a captured quosure. */
SEXP C_dtatools_probe_caller_plus(SEXP quosure, SEXP dependencies) {
    if (TYPEOF(quosure) != LANGSXP || TYPEOF(dependencies) != VECSXP ||
        XLENGTH(dependencies) != 16) return Rf_ScalarLogical(FALSE);
    SEXP environment = Rf_getAttrib(quosure, Rf_install(".Environment"));
    if (TYPEOF(environment) != ENVSXP) return Rf_ScalarLogical(FALSE);
    SEXP expression = CADR(quosure);
    if (TYPEOF(expression) != LANGSXP) return Rf_ScalarLogical(FALSE);
    if (CAR(expression) == Rf_install("+"))
        return Rf_ScalarLogical(
            computed_dependency_value(Rf_install("+"), environment, 16) ==
            VECTOR_ELT(dependencies, 3));
    if (CAR(expression) == Rf_install("abs")) {
        SEXP numeric = VECTOR_ELT(dependencies, 12);
        if (TYPEOF(numeric) != VECSXP || XLENGTH(numeric) != 21)
            return Rf_ScalarLogical(FALSE);
        SEXP expected_abs = VECTOR_ELT(numeric, 4);
        return Rf_ScalarLogical(TYPEOF(expected_abs) == BUILTINSXP &&
            computed_dependency_value(Rf_install("abs"), environment, 16) ==
                expected_abs &&
            computed_dependency_value(Rf_install("-"), environment, 16) ==
                VECTOR_ELT(dependencies, 4));
    }
    return Rf_ScalarLogical(FALSE);
}

/* .dta_read_is_na uses the primitive branch for the native fallback. If base
   is.na is traced or replaced, preserve that executable callback by declining
   the compact producer before it bypasses the branch. */
static int scalar_is_na_primitive(SEXP frame) {
    SEXP actual = computed_dependency_value(Rf_install("is.na"), frame, 16);
    return TYPEOF(actual) == BUILTINSXP || TYPEOF(actual) == SPECIALSXP;
}

static SEXP scalar_double_attribute(SEXP name, SEXP value, void *context) {
    unsigned *seen = context;
    if (name == R_ClassSymbol) {
        static const char *classes[] = {"dta_numeric", "dta_double", "vctrs_vctr", "double"};
        if (TYPEOF(value) != STRSXP || ALTREP(value) || ANY_ATTRIB(value) ||
            XLENGTH(value) != 4) return R_NilValue;
        for (int i = 0; i < 4; i++)
            if (STRING_ELT(value, i) == NA_STRING ||
                strcmp(CHAR(STRING_ELT(value, i)), classes[i]) != 0) return R_NilValue;
        *seen |= 1U;
    } else if (strcmp(CHAR(PRINTNAME(name)), "stata.storage") == 0) {
        if (computed_storage_kind(value) != NUMERIC_DOUBLE) return R_NilValue;
        *seen |= 2U;
    } else return R_NilValue;
    return NULL;
}

typedef struct {
    int kind;
    unsigned seen;
} scalar_compact_attribute_state;

static SEXP scalar_compact_attribute(SEXP name, SEXP value, void *context) {
    scalar_compact_attribute_state *state = context;
    if (name == R_ClassSymbol) {
        static const char *prefix[] = {
            "dta_numeric", NULL, "vctrs_vctr", "double"
        };
        static const char *storage_classes[] = {
            "dta_byte", "dta_int", "dta_long", "dta_float"
        };
        if (TYPEOF(value) != STRSXP || ALTREP(value) || ANY_ATTRIB(value) ||
            XLENGTH(value) != 4) return R_NilValue;
        for (int i = 0; i < 4; i++) {
            if (STRING_ELT(value, i) == NA_STRING) return R_NilValue;
            const char *expected = prefix[i];
            if (i == 1) {
                if (state->kind < NUMERIC_BYTE || state->kind > NUMERIC_FLOAT ||
                    strcmp(CHAR(STRING_ELT(value, i)),
                           storage_classes[state->kind]) != 0) return R_NilValue;
                expected = storage_classes[state->kind];
            }
            if (strcmp(CHAR(STRING_ELT(value, i)), expected) != 0)
                return R_NilValue;
        }
        state->seen |= 1U;
    } else if (strcmp(CHAR(PRINTNAME(name)), "stata.storage") == 0) {
        if (computed_storage_kind(value) != state->kind) return R_NilValue;
        state->seen |= 2U;
    } else return R_NilValue;
    return NULL;
}

static int scalar_compact_numeric(SEXP value, int *kind) {
    if (TYPEOF(value) != REALSXP || Rf_isS4(value) || !ALTREP(value)) return 0;
    numeric_data *data = unmaterialized_numeric_read_storage(value);
    if (data == NULL || data->temporal != 0 || data->kind < NUMERIC_BYTE ||
        data->kind > NUMERIC_FLOAT) return 0;
    scalar_compact_attribute_state state = {data->kind, 0};
    if (R_mapAttrib(value, scalar_compact_attribute, &state) != NULL ||
        state.seen != 3U) return 0;
    *kind = data->kind;
    return 1;
}

static int scalar_canonical_double(SEXP value) {
    if (TYPEOF(value) != REALSXP || Rf_isS4(value) ||
        (ALTREP(value) && !owned_real(value))) return 0;
    unsigned seen = 0;
    return R_mapAttrib(value, scalar_double_attribute, &seen) == NULL && seen == 3U;
}

static int scalar_finite_value(SEXP value, double *number) {
    if (ALTREP(value) || ANY_ATTRIB(value) || Rf_isObject(value) || Rf_isS4(value) ||
        (TYPEOF(value) != REALSXP && TYPEOF(value) != INTSXP && TYPEOF(value) != LGLSXP) ||
        XLENGTH(value) != 1) return 0;
    if (TYPEOF(value) == REALSXP) *number = REAL(value)[0];
    else {
        int integer = TYPEOF(value) == INTSXP ? INTEGER(value)[0] : LOGICAL(value)[0];
        if (integer == NA_INTEGER) return 0;
        *number = integer;
    }
    return R_FINITE(*number);
}

/* Production calls use a logical status and a fresh local result binding.
   This keeps admission from calling new R predicates even when the enclosing
   helper is interpreted. R_GetCurrentEnv is public experimental API on the
   audited R build and is used only at these direct closure .Call sites. */
static int numeric_result_slot_available(SEXP frame) {
    return TYPEOF(frame) == ENVSXP && !R_EnvironmentIsLocked(frame) &&
        R_GetBindingType(Rf_install("native"), frame) == R_BindingTypeUnbound;
}

/* Early production admission reads only payloads whose original coercion,
   dimensions and names cannot execute an input method or foreign reader. */
static int numeric_entry_bare_double(SEXP value) {
    return TYPEOF(value) == REALSXP && !ANY_ATTRIB(value) &&
        !Rf_isObject(value) && !Rf_isS4(value) &&
        (!ALTREP(value) || owned_real(value));
}

static SEXP numeric_result_commit(SEXP value, SEXP frame) {
    if (value == R_NilValue) return Rf_ScalarLogical(FALSE);
    PROTECT(value);
    /* A finalizer may have installed a binding while the result allocated.
       Never enter an active setter or replace any newly installed value. */
    if (!numeric_result_slot_available(frame)) {
        UNPROTECT(1);
        return Rf_ScalarLogical(FALSE);
    }
    Rf_defineVar(Rf_install("native"), value, frame);
    UNPROTECT(1);
    return Rf_ScalarLogical(TRUE);
}

/* The scalar arithmetic route collapses both Stata missing payloads and
   computational non-finite results to system missing. Keep this predicate in
   one place so the ordinary-double and compact-payload producers cannot
   drift apart. The guarded bit comparison is the same Apple arm64/binary64
   kernel used by the ordinary route; other hosts retain the portable test. */
static int scalar_arithmetic_result_valid(double result) {
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

typedef struct {
    double scalar;
    int reverse;
    int addition;
    unsigned fits;
    size_t missing_count;
} scalar_compact_scan_context;

/* Scan compact storage in bounded scratch blocks. numeric_for_each_span()
   preserves foreign/Rust owners as separate spans, while numeric_fill_region()
   decodes each span without asking the public ALTREP for a data pointer. */
static void scalar_compact_scan_span(
    const numeric_data *span, size_t offset, void *context
) {
    scalar_compact_scan_context *state = context;
    (void) offset;
    for (size_t start = 0; start < span->length; ) {
        size_t count = span->length - start < 16384
            ? span->length - start : 16384;
        double scratch[16384];
        numeric_fill_region(span, start, count, scratch);
        for (size_t i = 0; i < count; i++) {
            double value = scratch[i];
            double result = state->addition
                ? (state->reverse ? state->scalar + value : value + state->scalar)
                : (state->reverse ? state->scalar - value : value - state->scalar);
            if (!scalar_arithmetic_result_valid(result)) {
                state->missing_count++;
            } else {
                state->fits &= computed_fit(result);
            }
        }
        start += count;
    }
}

typedef struct {
    double scalar;
    int reverse;
    int addition;
    int kind;
    unsigned char *raw;
    double *real;
    int fits;
    size_t missing_count;
} scalar_compact_write_context;

/* Integer storage and a bounded integer scalar produce exact binary64 results.
   Check the Stata lattice in integer arithmetic, then write the compact bytes
   directly. Other scalars retain the floating-point path below. */
static int scalar_compact_integer_span(
    const numeric_data *span, size_t offset, scalar_compact_write_context *state
) {
    if (state->kind != span->kind || span->missing_count != 0 ||
        span->kind < NUMERIC_BYTE || span->kind > NUMERIC_LONG ||
        !R_FINITE(state->scalar) ||
        state->scalar < -2147483648.0 || state->scalar > 2147483647.0 ||
        state->scalar != trunc(state->scalar)) return 0;
    int64_t scalar = (int64_t) state->scalar;
#define SCALAR_COMPACT_INTEGER_LOOP(TYPE, LOWER, UPPER)                    \
    for (size_t start = 0; start < span->length; ) {                       \
        R_CheckUserInterrupt();                                             \
        size_t end = span->length - start > 16384                           \
            ? start + 16384 : span->length;                                 \
        for (size_t i = start; i < end; i++) {                              \
            TYPE source;                                                    \
            memcpy(&source, (const unsigned char *) span->values +         \
                   i * sizeof(TYPE), sizeof(TYPE));                        \
            int64_t value = (int64_t) source;                               \
            int64_t result = state->addition ? value + scalar :            \
                (state->reverse ? scalar - value : value - scalar);         \
            int valid = result >= (LOWER) && result <= (UPPER);             \
            state->fits &= valid;                                           \
            TYPE encoded = valid ? (TYPE) result : (TYPE) 0;               \
            memcpy(state->raw + (offset + i) * sizeof(TYPE), &encoded,      \
                   sizeof(TYPE));                                           \
        }                                                                   \
        start = end;                                                        \
    }
    switch (span->kind) {
    case NUMERIC_BYTE: {
        SCALAR_COMPACT_INTEGER_LOOP(int8_t, -127, 100); break;
    }
    case NUMERIC_INT: {
        SCALAR_COMPACT_INTEGER_LOOP(int16_t, -32767, 32740); break;
    }
    case NUMERIC_LONG: {
        SCALAR_COMPACT_INTEGER_LOOP(int32_t, -2147483647LL, 2147483620LL); break;
    }
    default: break;
    }
#undef SCALAR_COMPACT_INTEGER_LOOP
    return 1;
}

static int scalar_compact_float_span(
    const numeric_data *span, size_t offset, scalar_compact_write_context *state
) {
    const double limit = numeric_float_observed_limit();
    if (state->kind != NUMERIC_FLOAT || span->kind != NUMERIC_FLOAT ||
        span->missing_count != 0 || !R_FINITE(state->scalar) ||
        fabs(state->scalar) > limit) return 0;
    for (size_t start = 0; start < span->length; ) {
        R_CheckUserInterrupt();
        size_t end = span->length - start > 16384
            ? start + 16384 : span->length;
        for (size_t i = start; i < end; i++) {
            float source;
            memcpy(&source, (const unsigned char *) span->values +
                   i * sizeof(float), sizeof(float));
            double value = (double) source;
            double result = state->addition ? value + state->scalar :
                (state->reverse ? state->scalar - value : value - state->scalar);
            int valid = fabs(result) <= limit;
            state->fits &= valid;
            float encoded = valid ? (float) result : 0.0f;
            memcpy(state->raw + (offset + i) * sizeof(float), &encoded,
                   sizeof(float));
        }
        start = end;
    }
    return 1;
}

static void scalar_compact_write_span(
    const numeric_data *span, size_t offset, void *context
) {
    scalar_compact_write_context *state = context;
    if (!state->fits) return;
    if (scalar_compact_integer_span(span, offset, state)) return;
    if (scalar_compact_float_span(span, offset, state)) return;
    double float_limit = numeric_float_observed_limit();
#define SCALAR_COMPACT_SAME_LOOP(TYPE, LOWER, UPPER, FLOAT_LIMIT)             \
    for (size_t i = 0; i < span->length; i++) {                              \
        if ((i & 16383) == 0) R_CheckUserInterrupt();                        \
        TYPE source;                                                          \
        memcpy(&source, (const unsigned char *) span->values +               \
               i * sizeof(TYPE), sizeof(TYPE));                              \
        double value = (double) source;                                       \
        double result = state->addition                                      \
            ? (state->reverse ? state->scalar + value : value + state->scalar)\
            : (state->reverse ? state->scalar - value : value - state->scalar);\
        size_t index = offset + i;                                            \
        int valid_result = scalar_arithmetic_result_valid(result);           \
        int valid = valid_result &&                                          \
            (FLOAT_LIMIT ? fabs(result) <= (double) (UPPER) :                \
             result == trunc(result) && result >= (LOWER) && result <= (UPPER));\
        if (!valid_result) {                                                  \
            state->missing_count++;                                          \
            write_numeric_missing(state->raw, (R_xlen_t) index,              \
                                  state->kind, 0);                           \
        } else if (!valid) {                                                  \
            state->fits = 0;                                                  \
        } else {                                                              \
            TYPE encoded = (TYPE) result;                                     \
            memcpy(state->raw + index * sizeof(TYPE), &encoded, sizeof(TYPE));\
        }                                                                     \
    }
    if (state->kind == span->kind && span->missing_count == 0) {
        switch (span->kind) {
        case NUMERIC_BYTE:
            SCALAR_COMPACT_SAME_LOOP(int8_t, -127, 100, 0); break;
        case NUMERIC_INT:
            SCALAR_COMPACT_SAME_LOOP(int16_t, -32767, 32740, 0); break;
        case NUMERIC_LONG:
            SCALAR_COMPACT_SAME_LOOP(int32_t, -2147483647.0, 2147483620.0, 0); break;
        case NUMERIC_FLOAT:
            SCALAR_COMPACT_SAME_LOOP(float, 0.0, float_limit, 1); break;
        default: break;
        }
        if (state->kind == span->kind) return;
    }
#undef SCALAR_COMPACT_SAME_LOOP
    double scratch[16384];
    for (size_t start = 0; start < span->length; ) {
        size_t count = span->length - start < 16384
            ? span->length - start : 16384;
        numeric_fill_region(span, start, count, scratch);
        for (size_t i = 0; i < count; i++) {
            double value = scratch[i];
            double result = state->addition
                ? (state->reverse ? state->scalar + value : value + state->scalar)
                : (state->reverse ? state->scalar - value : value - state->scalar);
            size_t index = offset + start + i;
            if (!scalar_arithmetic_result_valid(result)) {
                state->missing_count++;
                if (state->kind != NUMERIC_DOUBLE)
                    write_numeric_missing(state->raw, (R_xlen_t) index,
                                          state->kind, 0);
                else state->real[index] = NA_REAL;
            } else {
                state->fits = state->fits &&
                    (computed_fit(result) & (1U << state->kind)) != 0;
                if (state->kind == NUMERIC_DOUBLE) {
                    state->real[index] = result;
                } else {
                    write_numeric_observed_trusted(
                        state->raw, (R_xlen_t) index, state->kind, result
                    );
                }
            }
        }
        start += count;
    }
}

/* Produce a typed result directly from the package-owned compact ALTREP.
   This is deliberately limited to unmaterialized dtatools payloads: foreign
   ALTREP classes retain the conservative fallback, including their callbacks,
   custom methods and mutation/ownership semantics. */
static SEXP scalar_arithmetic_compact_result(
    SEXP vector, double scalar, int reverse, int addition, int minimum,
    int *result_kind
) {
    numeric_data *data = unmaterialized_numeric_read_storage(vector);
    if (data == NULL || data->temporal != 0 || data->length == 0 ||
        minimum < NUMERIC_BYTE || minimum > NUMERIC_DOUBLE) return R_NilValue;

    /* Most scalar operations preserve the declared storage kind. Try that
       common case in one pass; only a value outside the kind's lattice range
       needs the existing scan-then-rewrite promotion path. */
    int kind = minimum;
    SEXP backing;
    if (kind == NUMERIC_DOUBLE) {
        if (data->length > (size_t) R_XLEN_T_MAX) return R_NilValue;
        backing = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) data->length));
    } else {
        size_t width = numeric_kind_width(kind);
        if (data->length > SIZE_MAX / width ||
            data->length * width > (size_t) R_XLEN_T_MAX) return R_NilValue;
        backing = PROTECT(Rf_allocVector(
            RAWSXP, (R_xlen_t) (data->length * width)
        ));
    }

    scalar_compact_write_context write = {
        scalar, reverse, addition, kind,
        kind == NUMERIC_DOUBLE ? NULL : RAW(backing),
        kind == NUMERIC_DOUBLE ? REAL(backing) : NULL,
        1,
        0
    };
    numeric_for_each_span(data, 0, data->length,
                          scalar_compact_write_span, &write);

    if (write.fits) {
        SEXP result = PROTECT(kind == NUMERIC_DOUBLE
            ? owned_adopt_real(backing)
            : numeric_from_backing(backing, data->length, kind, 0, 119,
                                   write.missing_count));
        if (kind == NUMERIC_DOUBLE)
            owned_flags(result)[OWNED_NO_NA] = write.missing_count == 0;
        *result_kind = kind;
        UNPROTECT(2);
        return result;
    }
    UNPROTECT(1);

    scalar_compact_scan_context scan = {
        scalar, reverse, addition,
        (1U << (NUMERIC_DOUBLE + 1)) - 1U, 0
    };
    numeric_for_each_span(data, 0, data->length,
                          scalar_compact_scan_span, &scan);

    for (kind = minimum + 1; kind < NUMERIC_DOUBLE; kind++) {
        if (minimum == NUMERIC_LONG && kind == NUMERIC_FLOAT) continue;
        if (scan.fits & (1U << kind)) break;
    }
    if (kind > NUMERIC_DOUBLE) return R_NilValue;
    *result_kind = kind;

    if (kind == NUMERIC_DOUBLE) {
        if (data->length > (size_t) R_XLEN_T_MAX) return R_NilValue;
        backing = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) data->length));
    } else {
        size_t width = numeric_kind_width(kind);
        if (data->length > SIZE_MAX / width ||
            data->length * width > (size_t) R_XLEN_T_MAX) return R_NilValue;
        backing = PROTECT(Rf_allocVector(
            RAWSXP, (R_xlen_t) (data->length * width)
        ));
    }
    write = (scalar_compact_write_context) {
        scalar, reverse, addition, kind,
        kind == NUMERIC_DOUBLE ? NULL : RAW(backing),
        kind == NUMERIC_DOUBLE ? REAL(backing) : NULL,
        1,
        0
    };
    numeric_for_each_span(data, 0, data->length,
                          scalar_compact_write_span, &write);

    SEXP result = PROTECT(kind == NUMERIC_DOUBLE
        ? owned_adopt_real(backing)
        : numeric_from_backing(backing, data->length, kind, 0, 119,
                               write.missing_count));
    if (kind == NUMERIC_DOUBLE)
        owned_flags(result)[OWNED_NO_NA] = write.missing_count == 0;
    UNPROTECT(2);
    return result;
}

/* The explicit-frame kernel and early entry share only numeric execution. */
static SEXP scalar_arithmetic_result(SEXP vector, double scalar, int reverse, int addition) {
    SEXP source = PROTECT(owned_real(vector) ? owned_values(vector) : vector);
    if (TYPEOF(source) != REALSXP || ALTREP(source) || XLENGTH(source) == 0) {
        UNPROTECT(1);
        return R_NilValue;
    }
    R_xlen_t length = XLENGTH(source);
    const double *values = REAL(source);
    SEXP backing = PROTECT(Rf_allocVector(REALSXP, length));
    double *output = REAL(backing);
    int no_missing = 1;
    for (R_xlen_t start = 0; start < length; ) {
        R_CheckUserInterrupt();
        R_xlen_t end = length - start > 16384 ? start + 16384 : length;
        for (R_xlen_t i = start; i < end; i++) {
            double value = values[i];
            double result = addition ? (reverse ? scalar + value : value + scalar) :
                (reverse ? scalar - value : value - scalar);
            /* For + and -, any missing operand is still non-finite here.
               Collapse its payload and computational overflow in the same pass. */
            int valid = scalar_arithmetic_result_valid(result);
            output[i] = valid ? result : NA_REAL;
            no_missing &= valid;
        }
        start = end;
    }
    SEXP result = PROTECT(owned_adopt_real(backing));
    owned_flags(result)[OWNED_NO_NA] = no_missing;
    owned_flags(result)[OWNED_FINITE_DOUBLE] = no_missing;
    UNPROTECT(3);
    return result;
}

static SEXP C_dtatools_scalar_arithmetic_impl(
    SEXP left, SEXP right, SEXP frame, SEXP storage_getter, SEXP dependencies
) {
    if (TYPEOF(frame) != ENVSXP) return R_NilValue;
    /* op remains lazy until recycling on the fallback. In particular, an
       unresolved op expression must not replace an incompatible-size error. */
    SEXP op = PROTECT(computed_peek(Rf_install("op"), frame, 16));
    if (TYPEOF(op) != STRSXP || ALTREP(op) || ANY_ATTRIB(op) || XLENGTH(op) != 1 ||
        STRING_ELT(op, 0) == NA_STRING) { UNPROTECT(1); return R_NilValue; }
    const char *operator = CHAR(STRING_ELT(op, 0));
    if (strcmp(operator, "+") != 0 && strcmp(operator, "-") != 0) {
        UNPROTECT(1); return R_NilValue;
    }
    SEXP x = PROTECT(computed_peek(Rf_install("x"), frame, 16));
    SEXP y = PROTECT(computed_peek(Rf_install("y"), frame, 16));
    double scalar;
    int reverse = 0;
    SEXP vector;
    int compact_kind = -1;
    /* Original classes determine admission; use the actual settled operands
       produced by .dta_data(), including a scalar captured before a callback
       changed its caller binding. */
    double original_scalar;
    if ((scalar_canonical_double(x) || scalar_compact_numeric(x, &compact_kind)) &&
        scalar_finite_value(y, &original_scalar) &&
        scalar_finite_value(right, &scalar)) vector = left;
    else if ((scalar_canonical_double(y) || scalar_compact_numeric(y, &compact_kind)) &&
             scalar_finite_value(x, &original_scalar) &&
             scalar_finite_value(left, &scalar)) {
        vector = right;
        reverse = 1;
    } else { UNPROTECT(3); return R_NilValue; }
    int minimum = computed_storage_kind(computed_minimum(frame, storage_getter));
    numeric_data *compact = unmaterialized_numeric_read_storage(vector);
    if (TYPEOF(vector) != REALSXP ||
        (compact == NULL && (ANY_ATTRIB(vector) || Rf_isObject(vector))) ||
        Rf_isS4(vector) ||
        (ALTREP(vector) && !owned_real(vector) && compact == NULL) ||
        minimum < 0 || (compact == NULL && minimum != NUMERIC_DOUBLE) ||
        (compact != NULL && minimum != compact_kind)) {
        UNPROTECT(3); return R_NilValue;
    }
    if (!scalar_dependencies_unchanged(frame, dependencies) ||
        !scalar_is_na_primitive(frame) ||
        !dtatools_numeric_helpers_admitted(frame, DTATOOLS_NUMERIC_SCALAR)) {
        UNPROTECT(3); return R_NilValue;
    }
    int result_kind = NUMERIC_DOUBLE;
    SEXP result = PROTECT(compact != NULL
        ? scalar_arithmetic_compact_result(
            vector, scalar, reverse, *operator == '+', minimum, &result_kind
        )
        : scalar_arithmetic_result(vector, scalar, reverse, *operator == '+'));
    if (result != R_NilValue) {
        R_getVar(Rf_install("op"), frame, TRUE);
        R_getVar(Rf_install("minimum"), frame, TRUE);
    }
    UNPROTECT(4);
    return result;
}

#include "numeric-arithmetic.h"

SEXP C_dtatools_scalar_arithmetic(SEXP left, SEXP right, SEXP frame, SEXP storage_getter, SEXP dependencies) {
    /* Explicit-frame diagnostics retain their settled left/right contract. */
    if (frame != R_NilValue)
        return C_dtatools_scalar_arithmetic_impl(left, right, frame, storage_getter, dependencies);
    frame = R_GetCurrentEnv();
    if (!numeric_size_admitted(frame, DTATOOLS_NUMERIC_SCALAR)) return Rf_ScalarLogical(FALSE);
    if (!dtatools_numeric_entry_frame_admitted(frame, DTATOOLS_NUMERIC_SCALAR) ||
        !numeric_result_slot_available(frame)) return Rf_ScalarLogical(FALSE);
    SEXP x = PROTECT(computed_peek(Rf_install("x"), frame, 16));
    SEXP y = PROTECT(computed_peek(Rf_install("y"), frame, 16));
    SEXP op = PROTECT(computed_peek(Rf_install("op"), frame, 16));
    SEXP extended = PROTECT(numeric_arithmetic_extension(
        frame, x, y, op, storage_getter, dependencies
    ));
    if (extended != R_NilValue) {
        UNPROTECT(4);
        return extended;
    }
    UNPROTECT(1);
    SEXP vector = R_NilValue;
    int compact_kind = -1;
    double scalar = 0;
    int reverse = 0;
    if ((scalar_canonical_double(x) || scalar_compact_numeric(x, &compact_kind)) &&
        scalar_finite_value(y, &scalar)) vector = x;
    else if ((scalar_canonical_double(y) || scalar_compact_numeric(y, &compact_kind)) &&
             scalar_finite_value(x, &scalar)) {
        vector = y;
        reverse = 1;
    }
    /* Compact backing does not override the helper's minimum argument.
       Other or unresolved policies retain the ordinary R evaluation. */
    int minimum = computed_storage_kind(computed_minimum(frame, storage_getter));
    numeric_data *compact = vector == R_NilValue
        ? NULL : unmaterialized_numeric_read_storage(vector);
    if (vector == R_NilValue || TYPEOF(op) != STRSXP || ALTREP(op) || ANY_ATTRIB(op) ||
        XLENGTH(op) != 1 || STRING_ELT(op, 0) == NA_STRING ||
        (strcmp(CHAR(STRING_ELT(op, 0)), "+") != 0 &&
         strcmp(CHAR(STRING_ELT(op, 0)), "-") != 0) ||
        minimum < 0 || (compact == NULL && minimum != NUMERIC_DOUBLE) ||
        (compact != NULL && minimum != compact_kind) ||
        (ALTREP(vector) && !owned_real(vector) && compact == NULL) ||
        !scalar_dependencies_unchanged(frame, dependencies) ||
        !arithmetic_storage_names_unchanged(frame, dependencies) ||
        !scalar_is_na_primitive(frame) ||
        !dtatools_numeric_helpers_admitted(frame, DTATOOLS_NUMERIC_SCALAR) ||
        !dtatools_numeric_decoration_admitted(frame, DTATOOLS_NUMERIC_SCALAR, R_NilValue)) {
        UNPROTECT(3);
        return Rf_ScalarLogical(FALSE);
    }
    int result_kind = NUMERIC_DOUBLE;
    SEXP result = PROTECT(compact != NULL
        ? scalar_arithmetic_compact_result(
            vector, scalar, reverse, CHAR(STRING_ELT(op, 0))[0] == '+',
            minimum, &result_kind
        )
        : scalar_arithmetic_result(
            vector, scalar, reverse, CHAR(STRING_ELT(op, 0))[0] == '+'
        ));
    if (result == R_NilValue) {
        UNPROTECT(4);
        return Rf_ScalarLogical(FALSE);
    }
    static const char *storage_names[] = {"byte", "int", "long", "float", "double"};
    SEXP storage = PROTECT(Rf_mkString(storage_names[result_kind]));
    numeric_decorate_result(result, storage);
    if (!numeric_result_slot_available(frame)) {
        UNPROTECT(5);
        return Rf_ScalarLogical(FALSE);
    }
    /* No original argument is forced until the complete successful block is
       qualified. Preserve the original ancestor promise values and order. */
    R_getVar(Rf_install("x"), frame, TRUE);
    R_getVar(Rf_install("y"), frame, TRUE);
    R_getVar(Rf_install("op"), frame, TRUE);
    R_getVar(Rf_install("minimum"), frame, TRUE);
    SEXP status = numeric_result_commit(result, frame);
    if (LOGICAL(status)[0]) numeric_scalar_successes++;
    UNPROTECT(5);
    return status;
}

static SEXP C_dtatools_computed_numeric_impl(
    SEXP value, SEXP frame, SEXP storage_getter, SEXP dependencies,
    int settle_arguments
) {
    if (TYPEOF(frame) != ENVSXP || TYPEOF(value) != REALSXP ||
        (ALTREP(value) && !owned_real(value))) return R_NilValue;
    if (R_mapAttrib(value, computed_attribute, NULL) != NULL) return R_NilValue;
    if (!computed_dependencies_unchanged(frame, dependencies) ||
        !dtatools_numeric_helpers_admitted(frame, DTATOOLS_NUMERIC_COMPUTED))
        return R_NilValue;
    SEXP temporal = computed_peek(Rf_install("temporal"), frame, 16);
    if (TYPEOF(temporal) != INTSXP || ALTREP(temporal) || ANY_ATTRIB(temporal) ||
        Rf_isObject(temporal) || Rf_isS4(temporal) ||
        XLENGTH(temporal) != 1 || INTEGER(temporal)[0] != 0) return R_NilValue;
    SEXP storage = computed_minimum(frame, storage_getter);
    int minimum = computed_storage_kind(storage);
    if (minimum < 0) return R_NilValue;
    SEXP source = PROTECT(owned_real(value) ? owned_values(value) : value);
    if (ALTREP(source) || TYPEOF(source) != REALSXP) {
        UNPROTECT(1);
        return R_NilValue;
    }
    R_xlen_t length = XLENGTH(source);
    const double *values = REAL(source);
    int unsupported = 0;
    size_t missing_count = 0;
    int kind = minimum;
    SEXP backing;
    SEXP payload;
    if (minimum == NUMERIC_DOUBLE) {
        backing = PROTECT(Rf_allocVector(REALSXP, length));
        double *output = REAL(backing);
        for (R_xlen_t i = 0; i < length; i++) {
            if ((i & 16383) == 0) R_CheckUserInterrupt();
            int missing;
            output[i] = computed_normalize(values[i], &missing, &unsupported);
            missing_count += missing >= 0;
        }
        if (unsupported) { UNPROTECT(2); return R_NilValue; }
        payload = PROTECT(owned_adopt_real(backing));
        owned_flags(payload)[OWNED_NO_NA] = missing_count == 0;
    } else {
        unsigned fits = (1U << (NUMERIC_DOUBLE + 1)) - 1;
        for (R_xlen_t i = 0; i < length; i++) {
            if ((i & 16383) == 0) R_CheckUserInterrupt();
            int missing;
            double element = computed_normalize(values[i], &missing, &unsupported);
            if (missing >= 0) missing_count++;
            else fits &= computed_fit(element);
        }
        if (unsupported) { UNPROTECT(1); return R_NilValue; }
        for (; kind < NUMERIC_DOUBLE; kind++) {
            if (minimum == NUMERIC_LONG && kind == NUMERIC_FLOAT) continue;
            if (fits & (1U << kind)) break;
        }
        unsigned constants = kind == NUMERIC_DOUBLE ? 0U :
            DTATOOLS_NUMERIC_ENCODED_STORAGE;
        if (missing_count < (size_t) length &&
            minimum != NUMERIC_LONG && kind >= NUMERIC_FLOAT)
            constants |= DTATOOLS_NUMERIC_FLOAT_LIMIT;
        if (constants && !dtatools_numeric_helpers_admitted(frame, constants)) {
            UNPROTECT(1);
            return R_NilValue;
        }
        size_t width = kind == NUMERIC_DOUBLE ? sizeof(double) : numeric_kind_width(kind);
        if ((size_t) length > SIZE_MAX / width ||
            (size_t) length * width > (size_t) R_XLEN_T_MAX)
            Rf_error("computed Stata numeric vector is too long");
        backing = PROTECT(Rf_allocVector(kind == NUMERIC_DOUBLE ? REALSXP : RAWSXP,
            kind == NUMERIC_DOUBLE ? length : (R_xlen_t) ((size_t) length * width)));
        for (R_xlen_t i = 0; i < length; i++) {
            if ((i & 16383) == 0) R_CheckUserInterrupt();
            int missing;
            double element = computed_normalize(values[i], &missing, &unsupported);
            if (kind == NUMERIC_DOUBLE) REAL(backing)[i] = element;
            else if (missing >= 0) write_numeric_missing(RAW(backing), i, kind, missing);
            else write_numeric_observed_trusted(RAW(backing), i, kind, element);
        }
        payload = PROTECT(kind == NUMERIC_DOUBLE ? owned_adopt_real(backing) :
            numeric_from_backing(backing, (size_t) length, kind, 0, 119, missing_count));
        if (kind == NUMERIC_DOUBLE) owned_flags(payload)[OWNED_NO_NA] = missing_count == 0;
    }
    SEXP result = PROTECT(computed_result(payload, kind));
    /* Explicit-frame callers retain their original settlement contract.
       Early production instead settles result first in its caller below. */
    if (settle_arguments) {
        R_getVar(Rf_install("temporal"), frame, TRUE);
        R_getVar(Rf_install("minimum"), frame, TRUE);
    }
    UNPROTECT(4);
    return result;
}

SEXP C_dtatools_computed_numeric(SEXP value, SEXP frame, SEXP storage_getter, SEXP dependencies) {
    /* Explicit-frame callers retain the payload-or-NULL native test contract. */
    if (frame != R_NilValue)
        return C_dtatools_computed_numeric_impl(value, frame, storage_getter,
                                               dependencies, 1);
    frame = R_GetCurrentEnv();
    if (!numeric_size_admitted(frame, DTATOOLS_NUMERIC_COMPUTED)) return Rf_ScalarLogical(FALSE);
    if (!dtatools_numeric_entry_frame_admitted(frame, DTATOOLS_NUMERIC_COMPUTED) ||
        !numeric_result_slot_available(frame)) return Rf_ScalarLogical(FALSE);
    value = PROTECT(computed_peek(Rf_install("result"), frame, 16));
    if (!numeric_entry_bare_double(value) ||
        !dtatools_numeric_decoration_admitted(frame, DTATOOLS_NUMERIC_COMPUTED,
                                               R_NilValue)) {
        UNPROTECT(1);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP prepared = PROTECT(C_dtatools_computed_numeric_impl(
        value, frame, storage_getter, dependencies, 0));
    if (prepared == R_NilValue) {
        UNPROTECT(2);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP result = PROTECT(numeric_decorate_result(
        VECTOR_ELT(prepared, 0), VECTOR_ELT(prepared, 1)));
    if (result == R_NilValue || !numeric_result_slot_available(frame)) {
        UNPROTECT(3);
        return Rf_ScalarLogical(FALSE);
    }
    /* All declining checks finish before original promise chains settle.
       Keep the result formal's input and its expression, including forwarded
       caller promises, while matching the original policy forcing order. */
    R_getVar(Rf_install("result"), frame, TRUE);
    R_getVar(Rf_install("temporal"), frame, TRUE);
    R_getVar(Rf_install("minimum"), frame, TRUE);
    SEXP status = numeric_result_commit(result, frame);
    if (LOGICAL(status)[0]) numeric_computed_successes++;
    UNPROTECT(3);
    return status;
}

SEXP C_dtatools_construct_numeric(
    SEXP value, SEXP kind_value, SEXP temporal_value
) {
    if (TYPEOF(value) != REALSXP) {
        Rf_error("compact Stata numeric construction requires doubles");
    }
    if (TYPEOF(kind_value) != INTSXP || XLENGTH(kind_value) != 1) {
        Rf_error("invalid compact Stata numeric storage type");
    }
    int kind = INTEGER(kind_value)[0];
    if (TYPEOF(temporal_value) != INTSXP ||
        XLENGTH(temporal_value) != 1 ||
        INTEGER(temporal_value)[0] < 0 || INTEGER(temporal_value)[0] > 2) {
        Rf_error("invalid compact Stata temporal storage type");
    }
    int temporal = INTEGER(temporal_value)[0];
    size_t width = numeric_kind_width(kind);
    R_xlen_t length = XLENGTH(value);
    if ((size_t) length > SIZE_MAX / width ||
        (size_t) length * width > (size_t) R_XLEN_T_MAX) {
        Rf_error("compact Stata numeric vector is too long");
    }

    int fits_requested = 1;
    int fits_int = 1;
    int fits_long = 1;
    int fits_float = 1;
    int fits_double = 1;
    int has_nonfinite = 0;
    double float_maximum = numeric_float_observed_limit();
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        double element = REAL_ELT(value, index);
        int payload_tag = tagged_na_tag_value(element);
        int valid_missing = ISNA(element) ||
            (payload_tag >= 'a' && payload_tag <= 'z');
        if (valid_missing) continue;
        if (ISNAN(element)) {
            if (payload_tag == 0) {
                Rf_error(
                    "No Stata numeric storage can represent `x`; use `NA_real_` for system missing or `tagged_missing()` for `.a` through `.z`"
                );
            }
            Rf_error(
                "compact Stata numerics accept only system missing and `.a` through `.z`"
            );
        }
        if (!R_FINITE(element)) has_nonfinite = 1;
        int integral = R_FINITE(element) && element == trunc(element);
        int element_fits_int = integral &&
            element >= -32767.0 && element <= 32740.0;
        int element_fits_long = integral &&
            element >= -2147483647.0 && element <= 2147483620.0;
        int element_fits_float = R_FINITE(element) &&
            fabs(element) <= float_maximum;
        int element_fits_double = R_FINITE(element) &&
            fabs(element) <= DBL_MAX / 2.0;
        fits_int = fits_int && element_fits_int;
        fits_long = fits_long && element_fits_long;
        fits_float = fits_float && element_fits_float;
        fits_double = fits_double && element_fits_double;
        switch (kind) {
        case NUMERIC_BYTE:
            fits_requested = fits_requested && integral &&
                element >= -127.0 && element <= 100.0;
            break;
        case NUMERIC_INT:
            fits_requested = fits_requested && element_fits_int;
            break;
        case NUMERIC_LONG:
            fits_requested = fits_requested && element_fits_long;
            break;
        case NUMERIC_FLOAT:
            fits_requested = fits_requested && element_fits_float;
            break;
        default:
            Rf_error("invalid compact Stata numeric storage type");
        }
    }
    if (!fits_requested) {
        if (has_nonfinite) {
            Rf_error(
                "No Stata numeric storage can represent `x`; use `NA_real_` for system missing or `tagged_missing()` for `.a` through `.z`"
            );
        }
        const char *storage_name = kind == NUMERIC_BYTE ? "byte" :
            kind == NUMERIC_INT ? "int" :
            kind == NUMERIC_LONG ? "long" : "float";
        const char *recommendation = NULL;
        if (kind == NUMERIC_BYTE && fits_int) recommendation = "int";
        else if ((kind == NUMERIC_BYTE || kind == NUMERIC_INT) && fits_long)
            recommendation = "long";
        else if ((kind == NUMERIC_BYTE || kind == NUMERIC_INT) && fits_float)
            recommendation = "float";
        else if (fits_double) recommendation = "double";
        if (recommendation == NULL) {
            Rf_error("No Stata numeric storage can represent `x`");
        }
        Rf_error(
            "Stata %s storage cannot represent `x`; use `dta_%s(x)`",
            storage_name, recommendation
        );
    }
    R_xlen_t byte_length = (R_xlen_t) ((size_t) length * width);
    SEXP backing = PROTECT(Rf_allocVector(RAWSXP, byte_length));
    unsigned char *output = RAW(backing);
    size_t missing_count = 0;

    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        double element = REAL_ELT(value, index);
        int payload_tag = tagged_na_tag_value(element);
        int offset = payload_tag >= 'a' && payload_tag <= 'z'
            ? payload_tag - 'a' + 1 : -1;
        if (payload_tag == 0 && ISNA(element)) offset = 0;
        if (offset >= 0) {
            missing_count++;
            write_numeric_missing(output, index, kind, offset);
        } else if (ISNAN(element)) {
            Rf_error(
                "compact Stata numerics accept only system missing and `.a` through `.z`"
            );
        } else {
            write_numeric_observed(output, index, kind, element);
        }
    }

    void *data = dtatools_numeric_alloc(
        output, (size_t) length, kind, temporal, missing_count
    );
    if (data == NULL) {
        UNPROTECT(1);
        Rf_error("could not allocate compact Stata numeric storage");
    }
    SEXP external = PROTECT(R_MakeExternalPtr(data, R_NilValue, backing));
    R_RegisterCFinalizerEx(external, numeric_finalize, TRUE);
    SEXP result = PROTECT(R_new_altrep(
        dtatools_numeric_class, external, R_NilValue
    ));
    UNPROTECT(3);
    return result;
}

/* A successful strict-double check can replace the R masks only while their
   predicates retain the installed definitions. Inspect bindings and syntax
   without forcing a policy promise or reading a foreign literal. */
static const char *strict_double_predicate_names[] = {
    "is.na", "is.finite", "any", "abs", "floor", "!", "|", "&",
    "==", ">", "<", ">=", "<=", "[", "[<-", "rep", "length",
    "utf8ToInt", "identical", "/", "$"
};

static int strict_double_admitted(SEXP value, SEXP frame, SEXP dependencies) {
    if (TYPEOF(frame) != ENVSXP || TYPEOF(value) != REALSXP ||
        Rf_isObject(value) || Rf_isS4(value) || ANY_ATTRIB(value) ||
        (ALTREP(value) && !owned_real(value)) ||
        TYPEOF(dependencies) != VECSXP || ALTREP(dependencies) ||
        XLENGTH(dependencies) != (R_xlen_t) (sizeof(strict_double_predicate_names) /
                                          sizeof(strict_double_predicate_names[0]))) return 0;
    for (size_t i = 0; i < sizeof(strict_double_predicate_names) /
                            sizeof(strict_double_predicate_names[0]); i++) {
        SEXP actual = computed_dependency_value(Rf_install(strict_double_predicate_names[i]), frame, 16);
        if (!dtatools_execution_function_same(actual, VECTOR_ELT(dependencies, i))) return 0;
    }
    return computed_double_limit_unchanged(frame);
}

static int strict_double_valid(double value, int *no_missing) {
    if (!ISNAN(value)) return R_FINITE(value) && fabs(value) <= DBL_MAX / 2;
    *no_missing = 0;
    int tag = tagged_na_tag_value(value);
    return tag == 0 ? ISNA(value) : tag >= 'a' && tag <= 'z';
}

/* This profile covers vctrs 0.7.3's dispatch for unnamed canonical doubles.
   Unknown bindings decline without invoking methods or forcing promises. */
static int combine_plain_list(SEXP value) {
    return TYPEOF(value) == VECSXP && !ALTREP(value) && !ANY_ATTRIB(value) &&
        !Rf_isObject(value) && !Rf_isS4(value);
}

static int combine_plain_environment(SEXP value) {
    return TYPEOF(value) == ENVSXP && !Rf_isObject(value) && !Rf_isS4(value);
}

enum combine_binding { COMBINE_UNKNOWN = -1, COMBINE_ABSENT = 0,
                       COMBINE_VALUE = 1 };

static enum combine_binding combine_peek_frame(SEXP env, SEXP symbol, SEXP *out) {
    if (!combine_plain_environment(env)) return COMBINE_UNKNOWN;
    switch (R_GetBindingType(symbol, env)) {
    case R_BindingTypeUnbound:
        return COMBINE_ABSENT;
    case R_BindingTypeValue:
    case R_BindingTypeForced:
        *out = R_getVar(symbol, env, FALSE);
        return COMBINE_VALUE;
    default:
        return COMBINE_UNKNOWN;
    }
}

/* Construct ordinary active bindings; read and lifetime policy stays in R. */
static SEXP mask_bindings_current_attribute(SEXP name, SEXP value, void *context) {
    (void) value; (void) context;
    return name == R_NamesSymbol ? NULL : R_NilValue;
}

/* Keep encoded-name conversion and its diagnostics on the original R path.
   ASCII names need no locale translation when interned as symbols. */
static int mask_bindings_ascii_name(SEXP name) {
    if (name == NA_STRING || LENGTH(name) == 0 || LENGTH(name) > 1024 ||
        Rf_getCharCE(name) == CE_BYTES)
        return 0;
    const unsigned char *bytes = (const unsigned char *) CHAR(name);
    for (int i = 0; i < LENGTH(name); i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        if (bytes[i] >= 128) return 0;
    }
    return 1;
}

/* Check every skipped binding at its actual lexical root. The small base
   wrapper graph and the local factory must retain their compiled bodies as
   well as their source. Standard decompilation/recompilation can expose new
   callbacks without changing that source. No candidate function is called. */
static int mask_bindings_factory_same(SEXP frame, SEXP reader_env, SEXP expected) {
    SEXP symbol = Rf_install("binding"), actual = R_NilValue;
    if (R_GetBindingType(symbol, frame) != R_BindingTypeUnbound ||
        combine_peek_frame(reader_env, symbol, &actual) != COMBINE_VALUE ||
        TYPEOF(actual) != CLOSXP || TYPEOF(expected) != CLOSXP ||
        R_ClosureEnv(actual) != reader_env ||
        R_mapAttrib(actual, scalar_source_attribute, NULL) != NULL ||
        R_mapAttrib(expected, scalar_source_attribute, NULL) != NULL)
        return 0;
    int remaining = 512;
    if (!scalar_same_expression(R_ClosureFormals(actual), R_ClosureFormals(expected),
                                &remaining) ||
        !scalar_same_expression(R_ClosureExpr(actual), R_ClosureExpr(expected),
                                &remaining)) return 0;
    /* Source proof precedes comparison of standard public compiler output.
       This does not admit hand-built source-inconsistent private bytecode. */
    return TYPEOF(R_ClosureBody(actual)) == BCODESXP &&
        TYPEOF(R_ClosureBody(expected)) == BCODESXP &&
        numeric_bytecode_identical_safe(R_ClosureBody(actual), R_ClosureBody(expected));
}

static int mask_bindings_dependencies_same(
    SEXP frame, SEXP reader_env, SEXP dependencies
) {
    static const char *names[] = {
        "new.env", "makeActiveBinding", "$", "names", "as.name", "force",
        "emptyenv", "is.character", ".Internal", "[[", "for", "{", "<-", "function"
    };
    size_t count = sizeof(names) / sizeof(names[0]);
    SEXP profile = computed_peek(Rf_install(".metadata_state"), reader_env, 16);
    SEXP enabled = R_NilValue;
    if (combine_peek_frame(profile, Rf_install("dependencies"), &enabled) != COMBINE_VALUE ||
        enabled == R_NilValue ||
        !combine_plain_environment(frame) || !combine_plain_environment(reader_env) ||
        !combine_plain_list(dependencies) || XLENGTH(dependencies) != count + 1)
        return 0;
    for (size_t i = 0; i < count; i++) {
        /* as.name and is.character are called by base makeActiveBinding;
           .Internal is reached by its base wrappers. The factory's force
           calls resolve in the reader frame, with no make_mask local scope. */
        SEXP env = i == 4 || i == 7 || i == 8 ? R_BaseNamespace :
                   i == 5 ? reader_env : frame;
        if (!dtatools_execution_lexical_function_same(
                env, Rf_install(names[i]), VECTOR_ELT(dependencies, i))) return 0;
    }
    return mask_bindings_factory_same(frame, reader_env, VECTOR_ELT(dependencies, count));
}

/* The only unevaluated expression admitted is this private factory's exact
   default state$id in its own frame. Inspect through public binding APIs;
   even a declined foreign name list must leave the group promise untouched. */
static int mask_bindings_inputs(SEXP frame, SEXP reader_env, SEXP *current, SEXP *id) {
    if (!combine_plain_environment(frame) || !combine_plain_environment(reader_env) ||
        R_ParentEnv(frame) != reader_env) return 0;
    SEXP state_symbol = Rf_install("state"), id_symbol = Rf_install("id");
    SEXP current_symbol = Rf_install("current"), dollar_symbol = Rf_install("$");
    SEXP state = R_NilValue;
    if (R_GetBindingType(state_symbol, frame) != R_BindingTypeUnbound ||
        combine_peek_frame(reader_env, state_symbol, &state) != COMBINE_VALUE ||
        !combine_plain_environment(state) ||
        combine_peek_frame(state, current_symbol, current) != COMBINE_VALUE) return 0;
    if (R_GetBindingType(id_symbol, frame) != R_BindingTypeDelayed)
        return combine_peek_frame(frame, id_symbol, id) == COMBINE_VALUE;
    if (R_DelayedBindingEnvironment(id_symbol, frame) != frame) return 0;
    SEXP expression = R_DelayedBindingExpression(id_symbol, frame);
    if (TYPEOF(expression) != LANGSXP || ANY_ATTRIB(expression) ||
        TAG(expression) != R_NilValue || CAR(expression) != dollar_symbol) return 0;
    SEXP rest = CDR(expression);
    if (TYPEOF(rest) != LISTSXP || ANY_ATTRIB(rest) || TAG(rest) != R_NilValue ||
        CAR(rest) != state_symbol) return 0;
    rest = CDR(rest);
    if (TYPEOF(rest) != LISTSXP || ANY_ATTRIB(rest) || TAG(rest) != R_NilValue ||
        CAR(rest) != id_symbol || CDR(rest) != R_NilValue) return 0;
    return combine_peek_frame(state, id_symbol, id) == COMBINE_VALUE;
}

static SEXP mask_bindings_construct(
    SEXP frame, SEXP reader_env, SEXP dependencies, SEXP *last_name
) {
    SEXP current = R_NilValue, id = R_NilValue;
    if (!mask_bindings_dependencies_same(frame, reader_env, dependencies) ||
        !mask_bindings_inputs(frame, reader_env, &current, &id)) return R_NilValue;
    /* These exact objects are borrowed from mutable state, not .Call inputs.
       Root them across allocation even if a finalizer replaces state fields. */
    PROTECT(current);
    PROTECT(id);
    if (TYPEOF(current) != VECSXP || ALTREP(current) ||
        Rf_isObject(current) || Rf_isS4(current) ||
        R_mapAttrib(current, mask_bindings_current_attribute, NULL) != NULL ||
        TYPEOF(id) != INTSXP || ALTREP(id) || ANY_ATTRIB(id) ||
        Rf_isObject(id) || Rf_isS4(id) || XLENGTH(id) != 1 ||
        INTEGER(id)[0] == NA_INTEGER || INTEGER(id)[0] < 0) {
        UNPROTECT(2);
        return R_NilValue;
    }
    R_xlen_t width = XLENGTH(current);
    if (width > INT_MAX) {
        UNPROTECT(2);
        return R_NilValue;
    }
    SEXP names = PROTECT(Rf_getAttrib(current, R_NamesSymbol));
    if (TYPEOF(names) != STRSXP || ALTREP(names) || ANY_ATTRIB(names) ||
        Rf_isObject(names) || Rf_isS4(names) || XLENGTH(names) != width) {
        UNPROTECT(3);
        return R_NilValue;
    }
    /* Finish all ordinary-shape checks before creating the result environment.
       No generation fields or column payloads are read. */
    for (R_xlen_t i = 0; i < width; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        SEXP name = STRING_ELT(names, i);
        if (!mask_bindings_ascii_name(name) ||
            !combine_plain_environment(VECTOR_ELT(current, i))) {
            UNPROTECT(3);
            return R_NilValue;
        }
    }
    SEXP bindings = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, width < 29 ? 29 : (int) width));
    SEXP fixed_id = PROTECT(Rf_ScalarInteger(INTEGER(id)[0]));
    SEXP read_symbol = Rf_install("read");
    SEXP generation_symbol = Rf_install("generation"), name_symbol = Rf_install("name");
    SEXP id_symbol = Rf_install("id");
    /* Retain the original factory's call and capture frame. A changed reader
       can inspect its argument expressions, including after construction.
       Forced bindings preserve both fixed values and substitute(..., frame)
       without evaluating the original state access or any R constructor. */
    SEXP body = PROTECT(Rf_lang4(read_symbol, generation_symbol, name_symbol, id_symbol));
    SEXP current_expression = PROTECT(Rf_lang3(
        Rf_install("$"), Rf_install("state"), Rf_install("current")));
    SEXP generation_expression = PROTECT(Rf_lang3(
        Rf_install("[["), current_expression, name_symbol));
    for (R_xlen_t i = 0; i < width; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        SEXP symbol = Rf_installTrChar(STRING_ELT(names, i));
        /* This is our fresh ordinary environment. Existence inspection does
           not run previously installed active bindings. Never expose a partial
           result, including when two encodings resolve to the same symbol. */
        if (R_existsVarInFrame(bindings, symbol)) {
            UNPROTECT(8);
            return R_NilValue;
        }
        SEXP name = PROTECT(Rf_ScalarString(STRING_ELT(names, i)));
        SEXP capture = PROTECT(R_NewEnv(reader_env, FALSE, 0));
        /* Insert in reverse formal order, as in the original call frame. */
        R_MakeForcedBinding(id_symbol, id_symbol, fixed_id, capture);
        R_MakeForcedBinding(name_symbol, name_symbol, name, capture);
        R_MakeForcedBinding(generation_symbol, generation_expression,
                            VECTOR_ELT(current, i), capture);
        SEXP getter = PROTECT(R_mkClosure(R_NilValue, body, capture));
        R_MakeActiveBinding(symbol, getter, bindings);
        /* The result roots the same scalar retained by the last capture. */
        *last_name = name;
        UNPROTECT(3);
    }
    UNPROTECT(8);
    return bindings;
}

static int mask_bindings_result_slot_available(SEXP frame, SEXP symbol) {
    return combine_plain_environment(frame) && !R_EnvironmentIsLocked(frame) &&
        R_GetBindingType(symbol, frame) == R_BindingTypeUnbound;
}

static int mask_bindings_name_slot_available(SEXP frame, SEXP symbol) {
    if (!combine_plain_environment(frame) || R_EnvironmentIsLocked(frame)) return 0;
    R_BindingType_t type = R_GetBindingType(symbol, frame);
    return type == R_BindingTypeUnbound ||
        ((type == R_BindingTypeValue || type == R_BindingTypeForced) &&
         !R_BindingIsLocked(symbol, frame));
}

SEXP C_dtatools_try_mask_bindings(
    SEXP frame, SEXP reader_env, SEXP dependencies
) {
    int publish = frame == R_NilValue && reader_env == R_NilValue;
    /* Production calls .Call directly in make_mask. On the audited R build,
       experimental public R_GetCurrentEnv therefore finds its evaluation frame;
       the lexical parent owns the reader. An R wrapper/eval frame needs a new
       proof. Explicit-frame calls retain their environment-or-NULL contract. */
    if (frame == R_NilValue) frame = R_GetCurrentEnv();
    if (!combine_plain_environment(frame))
        return publish ? Rf_ScalarLogical(FALSE) : R_NilValue;
    if (reader_env == R_NilValue) reader_env = R_ParentEnv(frame);
    SEXP symbol = Rf_install("bindings"), id_symbol = Rf_install("id");
    SEXP name_symbol = Rf_install("name");
    if (!mask_bindings_name_slot_available(frame, name_symbol))
        return publish ? Rf_ScalarLogical(FALSE) : R_NilValue;
    if (publish && !mask_bindings_result_slot_available(frame, symbol))
        return Rf_ScalarLogical(FALSE);
    SEXP current = R_NilValue, id = R_NilValue;
    if (!mask_bindings_inputs(frame, reader_env, &current, &id))
        return publish ? Rf_ScalarLogical(FALSE) : R_NilValue;
    PROTECT(current);
    PROTECT(id);
    R_BindingType_t id_type = R_GetBindingType(id_symbol, frame);
    SEXP expression = PROTECT(id_type == R_BindingTypeDelayed ?
        R_DelayedBindingExpression(id_symbol, frame) :
        id_type == R_BindingTypeForced ? R_ForcedBindingExpression(id_symbol, frame) : R_NilValue);
    int settle = id_type == R_BindingTypeDelayed &&
        TYPEOF(current) == VECSXP && !ALTREP(current) && XLENGTH(current) != 0;
    if (settle && (R_EnvironmentIsLocked(frame) || R_BindingIsLocked(id_symbol, frame))) {
        UNPROTECT(3);
        return publish ? Rf_ScalarLogical(FALSE) : R_NilValue;
    }
    SEXP name = R_NilValue;
    SEXP result = PROTECT(mask_bindings_construct(frame, reader_env, dependencies, &name));
    /* A declined partial construction need not retain its last capture. */
    if (result == R_NilValue) name = R_NilValue;
    PROTECT(name);
    SEXP now_current = R_NilValue, now_id = R_NilValue;
    /* Construction allocates. Recheck the exact default and its settled state
       without evaluating any promise, entering an active binding or replacing
       a locked binding installed in the meantime. */
    int unchanged = result != R_NilValue &&
        mask_bindings_inputs(frame, reader_env, &now_current, &now_id) &&
        now_current == current && now_id == id &&
        R_GetBindingType(id_symbol, frame) == id_type &&
        (id_type != R_BindingTypeDelayed ||
            R_DelayedBindingExpression(id_symbol, frame) == expression) &&
        (id_type != R_BindingTypeForced ||
            R_ForcedBindingExpression(id_symbol, frame) == expression) &&
        (!settle || (!R_EnvironmentIsLocked(frame) && !R_BindingIsLocked(id_symbol, frame))) &&
        mask_bindings_name_slot_available(frame, name_symbol) &&
        (!publish || mask_bindings_result_slot_available(frame, symbol));
    if (!unchanged) {
        UNPROTECT(5);
        return publish ? Rf_ScalarLogical(FALSE) : R_NilValue;
    }
    /* The original nonempty loop forces make_mask's default id through the
       first factory call. Settle that same expression and captured value only
       after every declining check. R_MakeForcedBinding allocates its promise;
       expression, value and completed result stay rooted across that commit. */
    if (settle) R_MakeForcedBinding(id_symbol, expression, id, frame);
    /* R's for loop leaves its final scalar in the caller, or NULL for an
       empty sequence. The following new_data_mask callback can inspect it. */
    Rf_defineVar(name_symbol, name, frame);
    if (publish) Rf_defineVar(symbol, result, frame);
    UNPROTECT(5);
    return publish ? Rf_ScalarLogical(TRUE) : result;
}

static int combine_frame_absent(SEXP env, SEXP symbol) {
    return combine_plain_environment(env) &&
        R_GetBindingType(symbol, env) == R_BindingTypeUnbound;
}

static int combine_frame_same(SEXP env, SEXP symbol, SEXP expected) {
    SEXP actual;
    return combine_peek_frame(env, symbol, &actual) == COMBINE_VALUE &&
        scalar_same_function(actual, expected);
}

/* R's S3 lookup skips the attached search path after the global frame. */
static int combine_chain_absent(SEXP env, SEXP symbol) {
    for (int depth = 0; depth < 16; depth++) {
        if (env == R_EmptyEnv) return 1;
        if (!combine_frame_absent(env, symbol)) return 0;
        env = env == R_GlobalEnv ? R_BaseEnv : R_ParentEnv(env);
    }
    return env == R_EmptyEnv;
}

static int combine_lexical_function_same(SEXP env, SEXP symbol, SEXP expected) {
    for (int depth = 0; depth < 16 && env != R_EmptyEnv; depth++) {
        SEXP actual;
        enum combine_binding binding = combine_peek_frame(env, symbol, &actual);
        if (binding == COMBINE_VALUE) return scalar_same_function(actual, expected);
        if (binding != COMBINE_ABSENT) return 0;
        env = R_ParentEnv(env);
    }
    return 0;
}

/* The argument is our build-time, optimize=3 probe, never a user expression.
   Give a copy a private sentinel binding while retaining its compiled body.
   The VM's direct vector opcode returns list(NULL); interpreted execution
   reaches the private closure and returns FALSE. No process flags or user
   bindings are read or changed. R_mkClosure preserves bytecode; environment<-
   would discard it. */
SEXP C_dtatools_metadata_execution_profile(SEXP original) {
    if (TYPEOF(original) != CLOSXP || Rf_isObject(original) || Rf_isS4(original) ||
        R_ClosureFormals(original) != R_NilValue ||
        TYPEOF(R_ClosureBody(original)) != BCODESXP)
        return Rf_ScalarLogical(FALSE);
    SEXP expression = R_ClosureExpr(original);
    if (TYPEOF(expression) != LANGSXP || ANY_ATTRIB(expression) ||
        CAR(expression) != Rf_install("vector")) return Rf_ScalarLogical(FALSE);
    SEXP args = CDR(expression);
    if (TYPEOF(args) != LISTSXP || TAG(args) != R_NilValue ||
        TYPEOF(CAR(args)) != STRSXP || ALTREP(CAR(args)) || ANY_ATTRIB(CAR(args)) ||
        XLENGTH(CAR(args)) != 1 || STRING_ELT(CAR(args), 0) != Rf_mkChar("list"))
        return Rf_ScalarLogical(FALSE);
    args = CDR(args);
    if (TYPEOF(args) != LISTSXP || TAG(args) != R_NilValue || CDR(args) != R_NilValue ||
        TYPEOF(CAR(args)) != INTSXP || ALTREP(CAR(args)) || ANY_ATTRIB(CAR(args)) ||
        XLENGTH(CAR(args)) != 1 || INTEGER(CAR(args))[0] != 1)
        return Rf_ScalarLogical(FALSE);
    SEXP env = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, 1));
    SEXP formals = PROTECT(Rf_cons(R_MissingArg, R_NilValue));
    SET_TAG(formals, R_DotsSymbol);
    SEXP sentinel_body = PROTECT(Rf_ScalarLogical(FALSE));
    SEXP sentinel = PROTECT(R_mkClosure(formals, sentinel_body, R_EmptyEnv));
    Rf_defineVar(Rf_install("vector"), sentinel, env);
    SEXP probe = PROTECT(R_mkClosure(R_NilValue, R_ClosureBody(original), env));
    SEXP call = PROTECT(Rf_lang1(probe));
    SEXP result = PROTECT(Rf_eval(call, R_EmptyEnv));
    int enabled = TYPEOF(result) == VECSXP && !ALTREP(result) && !ANY_ATTRIB(result) &&
        !Rf_isObject(result) && !Rf_isS4(result) && XLENGTH(result) == 1 &&
        VECTOR_ELT(result, 0) == R_NilValue;
    UNPROTECT(7);
    return Rf_ScalarLogical(enabled);
}

int dtatools_execution_lexical_function_same(SEXP env, SEXP symbol, SEXP expected) {
    for (int depth = 0; depth < 16 && env != R_EmptyEnv; depth++) {
        SEXP actual;
        enum combine_binding binding = combine_peek_frame(env, symbol, &actual);
        if (binding == COMBINE_VALUE)
            return dtatools_execution_function_same(actual, expected);
        if (binding != COMBINE_ABSENT) return 0;
        env = R_ParentEnv(env);
    }
    return 0;
}

/* These helpers are omitted by the admitted numeric routes. Keep the named
   layout and route membership in sync with z-numeric-helper-profile.R.
   Zero-mask base names execute as internal/builtin or control opcodes in
   the qualified compiled bodies; their lazy namespace functions are unused.
   is.factor, %in% and attributes<- retain live function lookup checks.
   Constructor dim and constructor/computed as.double also settle their
   bindings, even when their compiled calls bypass executable tracers. */
int dtatools_numeric_helpers_unchanged(SEXP frame, SEXP profile, unsigned route, SEXP proof) {
    static const char *names[] = {
        ".dta_arith_base", ".dta_read_is_na", ".collapse_missing", ".dta_computed",
        ".tab_missing_codes", ".encode_dta_temporal", ".dta_storage_candidates", ".invalid_dta_observed",
        ".construct_dta_numeric_trusted", ".metadata_copy", ".repair_data_table_container", ".construct_dta_numeric",
        ".dta_storage_holds", ".dta_storage_class", ".declared_dta_storage", ".dta_data",
        ".metadata_view", "is.primitive", "rep", "identical",
        "inherits", "utf8ToInt", "/", "$",
        ".Call", "::", "isTRUE", "attr<-",
        "paste0", "names<-", "names", "c",
        "{", "return", "<-", "if",
        "[[", "list", ".Internal", "is.null",
        "typeof", "is.factor", "%in%", "dim",
        "as.double", "&&", "||", "match",
        "switch", "attributes<-", ".dta_temporal_none", ".dta_float_max",
        ".dta_storage"
    };
    static const unsigned routes[] = {
        1, 1, 1, 3, 31, 23, 3, 31, 3, 23, 23, 20,
        8, 23, 19, 1, 1, 1, 31, 31, 0, 20, 31, 31,
        31, 1, 144, 23, 23, 23, 23, 23, 23, 23, 23, 23,
        23, 23, 23, 0, 0, 4, 4, 4, 7, 0, 0, 0,
        0, 1, 23, 64, 48
    };
    const R_xlen_t count = sizeof(names) / sizeof(names[0]);
    if (!combine_plain_environment(frame) || TYPEOF(profile) != VECSXP ||
        ALTREP(profile) || Rf_isObject(profile) || Rf_isS4(profile) ||
        R_mapAttrib(profile, mask_bindings_current_attribute, NULL) != NULL ||
        XLENGTH(profile) != count || route == 0 || (route & ~255U)) return 0;
    SEXP labels = Rf_getAttrib(profile, R_NamesSymbol);
    if (TYPEOF(labels) != STRSXP || ALTREP(labels) || ANY_ATTRIB(labels) ||
        XLENGTH(labels) != count) return 0;
    numeric_expected_profile *prepared = numeric_expected_profile_get(proof);
    if (prepared != NULL && (R_ExternalPtrProtected(proof) == R_NilValue ||
        VECTOR_ELT(R_ExternalPtrProtected(proof), 0) != profile || prepared->count != 50))
        prepared = NULL;
    for (R_xlen_t i = 0; i < count; i++) {
        SEXP label = STRING_ELT(labels, i);
        if (!mask_bindings_ascii_name(label) || strcmp(CHAR(label), names[i]) != 0)
            return 0;
        if (!(routes[i] & route)) continue;
        SEXP symbol = Rf_installTrChar(label), expected = VECTOR_ELT(profile, i);
        if (i < 50) {
            if (!(prepared ? numeric_expected_lexical_same(frame, symbol, &prepared->functions[i]) :
                  dtatools_execution_lexical_function_same(frame, symbol, expected)) ||
                (i >= 17 && !(prepared ? numeric_expected_lexical_same(R_BaseNamespace, symbol, &prepared->functions[i]) :
                  dtatools_execution_lexical_function_same(R_BaseNamespace, symbol, expected)))) return 0;
        } else {
            SEXP actual = computed_peek(symbol, frame, 16);
            int remaining = 64;
            if (!scalar_same_expression(actual, expected, &remaining)) return 0;
        }
    }
    return 1;
}

/* Native entry points inspect runtime state without introducing an R `$`,
   environment(), or helper invocation on the successful path. */
int dtatools_numeric_helpers_admitted(SEXP frame, unsigned route) {
    SEXP state = computed_peek(Rf_install(".numeric_helper_state"), frame, 16);
    SEXP profile = R_NilValue;
    if (combine_peek_frame(state, Rf_install("dependencies"), &profile) != COMBINE_VALUE)
        return 0;
    PROTECT(profile);
    SEXP proof = R_NilValue;
    (void) combine_peek_frame(state, Rf_install("proof"), &proof);
    PROTECT(proof);
    int admitted = dtatools_numeric_helpers_unchanged(frame, profile, route, proof);
    UNPROTECT(2);
    return admitted;
}

/* Query the public sys.function() helper through a private lexical binding.
   Its template is captured at build, never from a live runtime base binding. */
static int numeric_entry_template_valid(SEXP expected) {
    if (!combine_plain_list(expected) || XLENGTH(expected) != 2) return 0;
    SEXP function = VECTOR_ELT(expected, 0), internal = VECTOR_ELT(expected, 1);
    if (TYPEOF(function) != CLOSXP || TYPEOF(internal) != SPECIALSXP ||
        R_mapAttrib(function, scalar_source_attribute, NULL) != NULL ||
        TYPEOF(R_ClosureBody(function)) != BCODESXP) return 0;
    SEXP which = Rf_install("which"), internal_symbol = Rf_install(".Internal");
    SEXP function_symbol = Rf_install("sys.function");
    SEXP formals = R_ClosureFormals(function);
    if (TYPEOF(formals) != LISTSXP || ANY_ATTRIB(formals) ||
        TAG(formals) != which || CDR(formals) != R_NilValue) return 0;
    SEXP zero = CAR(formals);
    if (TYPEOF(zero) != INTSXP || ALTREP(zero) || ANY_ATTRIB(zero) ||
        XLENGTH(zero) != 1 || INTEGER(zero)[0] != 0) return 0;
    SEXP expression = R_ClosureExpr(function);
    if (TYPEOF(expression) != LANGSXP || ANY_ATTRIB(expression) ||
        TAG(expression) != R_NilValue || CAR(expression) != internal_symbol) return 0;
    SEXP rest = CDR(expression);
    if (TYPEOF(rest) != LISTSXP || ANY_ATTRIB(rest) || TAG(rest) != R_NilValue ||
        CDR(rest) != R_NilValue) return 0;
    expression = CAR(rest);
    if (TYPEOF(expression) != LANGSXP || ANY_ATTRIB(expression) ||
        TAG(expression) != R_NilValue || CAR(expression) != function_symbol) return 0;
    rest = CDR(expression);
    return TYPEOF(rest) == LISTSXP && !ANY_ATTRIB(rest) &&
        TAG(rest) == R_NilValue && CDR(rest) == R_NilValue && CAR(rest) == which;
}

SEXP C_dtatools_numeric_entry_state(SEXP expected) {
    if (!numeric_entry_template_valid(expected)) return R_NilValue;
    SEXP template = VECTOR_ELT(expected, 0), internal = VECTOR_ELT(expected, 1);
    SEXP environment = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, 1));
    Rf_defineVar(Rf_install(".Internal"), internal, environment);
    R_LockEnvironment(environment, TRUE);
    SEXP helper = PROTECT(R_mkClosure(R_ClosureFormals(template),
                                     R_ClosureBody(template), environment));
    SEXP record = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(record, 0, helper);
    SET_VECTOR_ELT(record, 1, expected);
    UNPROTECT(3);
    return record;
}

static int numeric_entry_helper_valid(SEXP record) {
    if (!combine_plain_list(record) || XLENGTH(record) != 2) return 0;
    SEXP helper = VECTOR_ELT(record, 0), expected = VECTOR_ELT(record, 1);
    if (!numeric_entry_template_valid(expected) || TYPEOF(helper) != CLOSXP ||
        R_mapAttrib(helper, scalar_source_attribute, NULL) != NULL) return 0;
    SEXP template = VECTOR_ELT(expected, 0), environment = R_ClosureEnv(helper);
    SEXP actual = R_NilValue, symbol = Rf_install(".Internal");
    if (!combine_plain_environment(environment) || R_ParentEnv(environment) != R_EmptyEnv ||
        !R_EnvironmentIsLocked(environment) ||
        combine_peek_frame(environment, symbol, &actual) != COMBINE_VALUE ||
        actual != VECTOR_ELT(expected, 1) || !R_BindingIsLocked(symbol, environment)) return 0;
    int remaining = 64;
    return scalar_same_expression(R_ClosureFormals(helper), R_ClosureFormals(template), &remaining) &&
        scalar_same_expression(R_ClosureExpr(helper), R_ClosureExpr(template), &remaining) &&
        TYPEOF(R_ClosureBody(helper)) == BCODESXP &&
        numeric_bytecode_identical_safe(R_ClosureBody(helper), R_ClosureBody(template));
}

/* Call only from the direct .Call at the original helper's first expression.
   This proof reads no operand, forces no caller promise, and writes no local.
   Live dependency qualification remains a separate required check. */
int dtatools_execution_frame_same(SEXP frame, SEXP expected) {
    if (!combine_plain_environment(frame) || frame != R_GetCurrentEnv()) return 0;
    PROTECT(expected);
    SEXP state = PROTECT(computed_peek(Rf_install(".numeric_helper_state"), frame, 16));
    SEXP record = R_NilValue;
    if (combine_peek_frame(state, Rf_install("entry"), &record) != COMBINE_VALUE) {
        UNPROTECT(2);
        return 0;
    }
    PROTECT(record);
    if (!numeric_entry_helper_valid(record)) {
        UNPROTECT(3);
        return 0;
    }
    SEXP zero = PROTECT(Rf_ScalarInteger(0));
    SEXP call = PROTECT(Rf_lang2(VECTOR_ELT(record, 0), zero));
    SEXP actual = PROTECT(Rf_eval(call, frame));
    int admitted = dtatools_execution_function_same(actual, expected);
    UNPROTECT(6);
    return admitted;
}

int dtatools_numeric_entry_frame_admitted(SEXP frame, unsigned route) {
    int index = route == DTATOOLS_NUMERIC_SCALAR ? 0 :
                route == DTATOOLS_NUMERIC_COMPUTED ? 3 :
                route == DTATOOLS_NUMERIC_CONSTRUCT ? 11 :
                route == DTATOOLS_NUMERIC_HOLDS ? 12 : -1;
    if (index < 0 || !combine_plain_environment(frame) || frame != R_GetCurrentEnv()) return 0;
    SEXP state = PROTECT(computed_peek(Rf_install(".numeric_helper_state"), frame, 16));
    SEXP profile = R_NilValue;
    if (combine_peek_frame(state, Rf_install("dependencies"), &profile) != COMBINE_VALUE) {
        UNPROTECT(1);
        return 0;
    }
    PROTECT(profile);
    int admitted = TYPEOF(profile) == VECSXP && !ALTREP(profile) && XLENGTH(profile) > index &&
        dtatools_execution_frame_same(frame, VECTOR_ELT(profile, index));
    UNPROTECT(2);
    return admitted;
}

/* Attribute shortcuts skip the same base set operations, including their
   character-vector dispatch. Share one nonforcing admission check with the
   combiner, which would otherwise bypass those calls through restoration. */
int dtatools_metadata_dependencies_unchanged(SEXP frame, SEXP dependencies, int generation) {
    static const char *function_names[] = {
        "intersect", "setdiff", "startsWith", ".set_ops_need_as_vector",
        "unique", "unique.default", "isa", "tryCatch", "parent.frame",
        "%in%", "names<-", "list", "identity",
        ".generate_attributes", ".dta_attribute_plan", "environment",
        "==", "all", "c", "dim", "isS4", "length", "missing", "names", "UseMethod",
        "!", ">", "any", "class"
    };
    /* 1 = attribute planning, 2 = generation. Compiled operations may settle
       a binding even when they bypass its executable tracer. Only generation
       reaches the final four names on these canonical metadata inputs. */
    static const unsigned routes[] = {
        3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 1, 3,
        3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2
    };
    if (!combine_plain_environment(frame) || TYPEOF(dependencies) != VECSXP ||
        ALTREP(dependencies) || Rf_isObject(dependencies) || Rf_isS4(dependencies) ||
        R_mapAttrib(dependencies, mask_bindings_current_attribute, NULL) != NULL)
        return 0;
    R_xlen_t count = XLENGTH(dependencies);
    SEXP names = Rf_getAttrib(dependencies, R_NamesSymbol);
    if (count != (R_xlen_t) (sizeof(function_names) / sizeof(function_names[0])) ||
        TYPEOF(names) != STRSXP || ALTREP(names) ||
        ANY_ATTRIB(names) || Rf_isObject(names) || Rf_isS4(names) ||
        XLENGTH(names) != count) return 0;
    for (R_xlen_t i = 0; i < count; i++) {
        SEXP name = STRING_ELT(names, i);
        if (!mask_bindings_ascii_name(name) ||
            strcmp(CHAR(name), function_names[i]) != 0) return 0;
        SEXP symbol = Rf_installTrChar(name), expected = VECTOR_ELT(dependencies, i);
        int base_dependency = i != 13 && i != 14;
        if ((routes[i] & (generation ? 2U : 1U)) &&
            (!dtatools_execution_lexical_function_same(frame, symbol, expected) ||
             (base_dependency && !dtatools_execution_lexical_function_same(R_BaseNamespace, symbol, expected))))
            return 0;
    }
    SEXP method = Rf_install("unique.character"), table = R_NilValue;
    if (!combine_chain_absent(frame, method) ||
        !combine_chain_absent(R_BaseNamespace, method) ||
        combine_peek_frame(R_BaseNamespace, Rf_install(".__S3MethodsTable__."),
                           &table) != COMBINE_VALUE ||
        !combine_frame_absent(table, method)) return 0;
    return 1;
}

SEXP C_dtatools_metadata_dependencies_unchanged(SEXP frame, SEXP dependencies) {
    return Rf_ScalarLogical(dtatools_metadata_dependencies_unchanged(frame, dependencies, 0));
}

SEXP dtatools_metadata_profile_from_state(SEXP state) {
    SEXP dependencies;
    return combine_peek_frame(state, Rf_install("dependencies"), &dependencies) == COMBINE_VALUE ?
        dependencies : R_NilValue;
}

/* Production metadata calls pass no source payload. Follow settled values
   and safe symbol promises from the actual enclosing frame without forcing a
   source expression or invoking an active local binding on a declined attempt. */
SEXP dtatools_metadata_source(SEXP frame) {
    return computed_peek(Rf_install("source"), frame, 16);
}

static int canonical_attribute_plan_admitted(SEXP source, SEXP frame, SEXP state) {
    if (TYPEOF(source) != VECSXP || ALTREP(source) ||
        Rf_isObject(source) || Rf_isS4(source) || XLENGTH(source) != 2 ||
        R_mapAttrib(source, mask_bindings_current_attribute, NULL) != NULL)
        return 0;
    SEXP names = Rf_getAttrib(source, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || ALTREP(names) || ANY_ATTRIB(names) ||
        Rf_isObject(names) || Rf_isS4(names) || XLENGTH(names) != 2 ||
        !mask_bindings_ascii_name(STRING_ELT(names, 0)) ||
        !mask_bindings_ascii_name(STRING_ELT(names, 1)) ||
        strcmp(CHAR(STRING_ELT(names, 0)), "stata.storage") != 0 ||
        strcmp(CHAR(STRING_ELT(names, 1)), "class") != 0)
        return 0;
    SEXP dependencies = dtatools_metadata_profile_from_state(state);
    if (dependencies == R_NilValue) return 0;
    PROTECT(dependencies);
    int admitted = dtatools_metadata_dependencies_unchanged(frame, dependencies, 0);
    UNPROTECT(1);
    return admitted;
}

static int metadata_unknown_slot_available(SEXP frame, SEXP symbol) {
    return combine_plain_environment(frame) && !R_EnvironmentIsLocked(frame) &&
        R_GetBindingType(symbol, frame) == R_BindingTypeUnbound;
}

static double attribute_plan_successes = 0;

SEXP C_dtatools_attribute_plan_stats(SEXP reset) {
    double successes = attribute_plan_successes;
    if (Rf_asLogical(reset) == TRUE) attribute_plan_successes = 0;
    return Rf_ScalarReal(successes);
}

/* R_GetCurrentEnv identifies this direct closure call's frame. Explicit
   diagnostic payloads still require the original settled source identity;
   production NULL calls inspect it without adding an R argument read. */
SEXP C_dtatools_canonical_attribute_plan(SEXP source, SEXP state) {
    SEXP frame = R_GetCurrentEnv(), actual;
    int publish = source == R_NilValue;
    SEXP unknown_symbol = Rf_install("unknown");
    if (publish) {
        /* A self-removing tracer restores the namespace binding while its
           interpreted closure is still executing. Qualify that closure too. */
        SEXP profile = PROTECT(dtatools_metadata_profile_from_state(state));
        int admitted = TYPEOF(profile) == VECSXP && !ALTREP(profile) &&
            XLENGTH(profile) == 29 &&
            dtatools_execution_frame_same(frame, VECTOR_ELT(profile, 14));
        UNPROTECT(1);
        if (!admitted) return Rf_ScalarLogical(FALSE);
        source = dtatools_metadata_source(frame);
    }
    else if (combine_peek_frame(frame, Rf_install("source"), &actual) != COMBINE_VALUE ||
             actual != source) return Rf_ScalarLogical(FALSE);
    PROTECT(source);
    int admitted = canonical_attribute_plan_admitted(source, frame, state);
    if (admitted && publish) {
        /* The omitted setdiff assigns this ordinary empty character vector.
           Later R callbacks still see the original local in their caller.
           Existing or protected bindings retain the original R assignment. */
        admitted = metadata_unknown_slot_available(frame, unknown_symbol);
        if (admitted) {
            SEXP unknown = PROTECT(Rf_allocVector(STRSXP, 0));
            admitted = metadata_unknown_slot_available(frame, unknown_symbol);
            if (admitted) {
                Rf_defineVar(unknown_symbol, unknown, frame);
                attribute_plan_successes++;
            }
            UNPROTECT(1);
        }
    }
    UNPROTECT(1);
    return Rf_ScalarLogical(admitted);
}

/* Expected record: namespaces, eight functions, six primitives, class,
   storage, profile, strict predicates and skipped helper graph. Runtime records
   insert the live vctrs and base method tables before the strict predicates. */
static int combine_dependencies_valid(SEXP record, R_xlen_t length) {
    if (!combine_plain_list(record) || XLENGTH(record) != length ||
        !combine_plain_environment(VECTOR_ELT(record, 0)) ||
        !combine_plain_environment(VECTOR_ELT(record, 1))) return 0;
    SEXP functions = VECTOR_ELT(record, 2), primitives = VECTOR_ELT(record, 3);
    if (!combine_plain_list(functions) || XLENGTH(functions) != 8 ||
        !combine_plain_list(primitives) || XLENGTH(primitives) != 6) return 0;
    for (int i = 0; i < 8; i++) {
        SEXP expected = VECTOR_ELT(functions, i);
        SEXP ns = VECTOR_ELT(record, i == 0 || i >= 6 ? 0 : 1);
        if (TYPEOF(expected) != CLOSXP || R_ClosureEnv(expected) != ns) return 0;
    }
    for (int i = 0; i < 6; i++) {
        SEXP expected = VECTOR_ELT(primitives, i);
        if (TYPEOF(expected) != BUILTINSXP && TYPEOF(expected) != SPECIALSXP) return 0;
    }
    SEXP classes = VECTOR_ELT(record, 4), storage = VECTOR_ELT(record, 5);
    unsigned seen = 0;
    if (Rf_isObject(classes) || Rf_isS4(classes) ||
        Rf_isObject(storage) || Rf_isS4(storage) ||
        scalar_double_attribute(R_ClassSymbol, classes, &seen) != NULL ||
        scalar_double_attribute(Rf_install("stata.storage"), storage, &seen) != NULL)
        return 0;
    SEXP profile = VECTOR_ELT(record, 6);
    if (TYPEOF(profile) != STRSXP || ALTREP(profile) || ANY_ATTRIB(profile) ||
        Rf_isObject(profile) || Rf_isS4(profile) || XLENGTH(profile) != 1 ||
        STRING_ELT(profile, 0) == NA_STRING ||
        strcmp(CHAR(STRING_ELT(profile, 0)), "vctrs-0.7.3") != 0) return 0;
    SEXP strict = VECTOR_ELT(record, length == 9 ? 7 : 9);
    if (!combine_plain_list(strict) || XLENGTH(strict) !=
        (R_xlen_t) (sizeof(strict_double_predicate_names) /
                    sizeof(strict_double_predicate_names[0]))) return 0;
    SEXP graph = VECTOR_ELT(record, length == 9 ? 8 : 10);
    if (!combine_plain_list(graph) || XLENGTH(graph) != 5) return 0;
    return length == 9 ||
        (combine_plain_environment(VECTOR_ELT(record, 7)) &&
         combine_plain_environment(VECTOR_ELT(record, 8)));
}

SEXP C_dtatools_double_combine_dependencies(SEXP expected) {
    if (!combine_dependencies_valid(expected, 9)) return R_NilValue;
    SEXP vctrs_table, base_table;
    SEXP symbol = Rf_install(".__S3MethodsTable__.");
    if (combine_peek_frame(VECTOR_ELT(expected, 0), symbol, &vctrs_table) != COMBINE_VALUE ||
        !combine_plain_environment(vctrs_table) ||
        combine_peek_frame(R_BaseNamespace, symbol, &base_table) != COMBINE_VALUE ||
        !combine_plain_environment(base_table)) return R_NilValue;
    /* Capture live tables at load, never serialized copies or current methods
       as replacement expectations. Entries are checked on every operation. */
    PROTECT(vctrs_table);
    PROTECT(base_table);
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 11));
    for (int i = 0; i < 7; i++) SET_VECTOR_ELT(result, i, VECTOR_ELT(expected, i));
    SET_VECTOR_ELT(result, 7, vctrs_table);
    SET_VECTOR_ELT(result, 8, base_table);
    SET_VECTOR_ELT(result, 9, VECTOR_ELT(expected, 7));
    SET_VECTOR_ELT(result, 10, VECTOR_ELT(expected, 8));
    UNPROTECT(3);
    return result;
}

/* Native numeric decoration bypasses the original R names setter. A custom
   method can inspect the caller frame even when it delegates to NextMethod.
   Qualify only the canonical NULL-names branch and its reached helper graph;
   named results and unknown dispatch retain the original decoration path. */
static int numeric_decoration_dependencies_unchanged(
    SEXP frame, unsigned route, SEXP dependencies
) {
    if (!combine_dependencies_valid(dependencies, 11)) return 0;
    SEXP vctrs = VECTOR_ELT(dependencies, 0);
    SEXP expected = VECTOR_ELT(dependencies, 2);
    SEXP graph = VECTOR_ELT(dependencies, 10);
    SEXP base = VECTOR_ELT(graph, 1), external = VECTOR_ELT(graph, 2);
    SEXP primitive = VECTOR_ELT(graph, 3), table = R_NilValue;
    if (!combine_plain_list(base) || XLENGTH(base) != 8 ||
        !combine_plain_list(external) || XLENGTH(external) != 3 ||
        !combine_plain_list(primitive) || XLENGTH(primitive) != 18 ||
        combine_peek_frame(R_BaseNamespace, Rf_install(".__S3MethodsTable__."),
                           &table) != COMBINE_VALUE ||
        table != VECTOR_ELT(dependencies, 8)) return 0;

    static const char *methods[] = {
        "names<-.dta_numeric", "names<-.dta_double", "names<-.double",
        "names<-.default", "names<-.dta_byte", "names<-.dta_int",
        "names<-.dta_long", "names<-.dta_float"
    };
    size_t count = route == DTATOOLS_NUMERIC_COMPUTED ? 8 : 4;
    for (size_t i = 0; i < count; i++) {
        SEXP symbol = Rf_install(methods[i]);
        if (!combine_chain_absent(frame, symbol) ||
            !combine_chain_absent(vctrs, symbol) ||
            !combine_frame_absent(table, symbol)) return 0;
    }
    if (route == DTATOOLS_NUMERIC_SCALAR) {
        static const char *getters[] = {
            "names.dta_numeric", "names.dta_double", "names.vctrs_vctr",
            "names.double", "names.default"
        };
        for (size_t i = 0; i < sizeof(getters) / sizeof(getters[0]); i++) {
            SEXP symbol = Rf_install(getters[i]);
            if (!combine_chain_absent(frame, symbol) ||
                !combine_chain_absent(vctrs, symbol) ||
                !combine_frame_absent(table, symbol)) return 0;
        }
    }
    SEXP setter = Rf_install("names<-.vctrs_vctr");
    if (!combine_chain_absent(frame, setter) ||
        !combine_frame_same(table, setter, VECTOR_ELT(expected, 7)) ||
        !combine_lexical_function_same(vctrs, setter, VECTOR_ELT(expected, 7)))
        return 0;

    if (!combine_lexical_function_same(vctrs, Rf_install("names_repair_missing"),
                                        VECTOR_ELT(external, 0)) ||
        !dtatools_execution_lexical_function_same(vctrs, Rf_install("NextMethod"),
                                                  VECTOR_ELT(base, 4)) ||
        !dtatools_execution_lexical_function_same(R_BaseNamespace, Rf_install("NextMethod"),
                                                  VECTOR_ELT(base, 4))) return 0;

    /* The source-only setter and repair helper may be interpreted or compiled
       at any ordinary optimization level. For NULL names, length short-circuits
       validation and is.null returns directly; no missing-name repair runs.
       Include their control lookups and NextMethod's nested .Internal binding. */
    static const char *names[] = {
        "is.null", "length", "!=", "&&", "if", "{", "return", "<-", ".Internal"
    };
    static const int indices[] = {3, 5, 6, 7, 8, 9, 10, 11, 13};
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        SEXP symbol = Rf_install(names[i]), function = VECTOR_ELT(primitive, indices[i]);
        if ((TYPEOF(function) != BUILTINSXP && TYPEOF(function) != SPECIALSXP) ||
            !combine_lexical_function_same(vctrs, symbol, function) ||
            !combine_lexical_function_same(R_BaseNamespace, symbol, function)) return 0;
    }
    return 1;
}

int dtatools_numeric_decoration_admitted(SEXP frame, unsigned route, SEXP names) {
    if (names != R_NilValue || !combine_plain_environment(frame) ||
        (route != DTATOOLS_NUMERIC_SCALAR && route != DTATOOLS_NUMERIC_COMPUTED &&
         route != DTATOOLS_NUMERIC_CONSTRUCT)) return 0;
    SEXP state = computed_peek(Rf_install(".double_combine_state"), frame, 16);
    SEXP dependencies = R_NilValue;
    if (combine_peek_frame(state, Rf_install("dependencies"), &dependencies) != COMBINE_VALUE)
        return 0;
    PROTECT(dependencies);
    int admitted = numeric_decoration_dependencies_unchanged(frame, route, dependencies);
    UNPROTECT(1);
    return admitted;
}

/* Successful unnamed-double assembly skips these helper calls. Package and
   base closures use the shared standard-compiled proof. The three external
   helpers have small reached branches whose entire lexical graph is checked,
   so their source-reference-bearing compiler output need not be normalized. */
static int combine_graph_unchanged(SEXP dependencies) {
    static const char *package_names[] = {
        ".dta_promote", ".dta_common_ptype", ".dta_ptype",
        ".reconcile_dta_metadata", ".restore_dta_metadata",
        ".dta_classes_from", ".dta_combine_value_labels",
        ".reconcile_dta_metadata_attributes", ".apply_haven_labelled_class",
        ".dta_snapshot", ".cast_to_dta", ".compact_dta_storage_matches"
    };
    static const char *base_names[] = {
        "double", "is.factor", "paste0", "identical",
        "NextMethod", "environment", "parent.frame", "sys.frame"
    };
    static const char *external_names[] = {
        "names_repair_missing", "check_dots_empty0", "current_env"
    };
    static const char *primitive_names[] = {
        "list", "c", ".Call", "is.null", "nargs", "length", "!=", "&&",
        "if", "{", "return", "<-", "UseMethod", ".Internal", "attributes<-", "-",
        ".subset", "attr"
    };
    SEXP graph = VECTOR_ELT(dependencies, 10);
    SEXP dtatools = VECTOR_ELT(dependencies, 1), vctrs = VECTOR_ELT(dependencies, 0);
    if (!combine_plain_list(graph) || XLENGTH(graph) != 5) return 0;
    SEXP package = VECTOR_ELT(graph, 0), base = VECTOR_ELT(graph, 1);
    SEXP external = VECTOR_ELT(graph, 2), primitive = VECTOR_ELT(graph, 3);
    SEXP rlang = VECTOR_ELT(graph, 4);
    if (!combine_plain_list(package) || XLENGTH(package) != 12 ||
        !combine_plain_list(base) || XLENGTH(base) != 8 ||
        !combine_plain_list(external) || XLENGTH(external) != 3 ||
        !combine_plain_list(primitive) || XLENGTH(primitive) != 18 ||
        !combine_plain_environment(rlang) ||
        !dtatools_numeric_helpers_admitted(dtatools, DTATOOLS_NUMERIC_COMBINE)) return 0;
    for (int i = 0; i < 12; i++)
        if (!dtatools_execution_lexical_function_same(dtatools,
                Rf_install(package_names[i]), VECTOR_ELT(package, i))) return 0;
    /* double/is.factor/paste0 are called by package helpers; NextMethod and
       environment by vctrs; parent.frame by current_env in rlang. vctrs native
       dispatch calls r_peek_frame's interpreted sys.frame(-1) closure.
       Checking all three lookup chains also rejects new lexical masks without evaluating
       them. Base bytecode comparison closes their reached nested graph.
       match() and inherits() are direct internal opcodes in these qualified
       package/base bodies. Do not require their unused lazy base bindings to
       settle; body replacement or a compiler mode that exposes those lookups
       changes the compiled-body proof and declines. The three external
       source-only success branches below call neither function. */
    for (int i = 0; i < 8; i++) {
        SEXP symbol = Rf_install(base_names[i]), expected = VECTOR_ELT(base, i);
        if (!dtatools_execution_lexical_function_same(dtatools, symbol, expected) ||
            !dtatools_execution_lexical_function_same(vctrs, symbol, expected) ||
            !dtatools_execution_lexical_function_same(rlang, symbol, expected) ||
            !dtatools_execution_lexical_function_same(R_BaseNamespace, symbol, expected))
            return 0;
    }
    for (int i = 0; i < 3; i++) {
        SEXP expected = VECTOR_ELT(external, i);
        SEXP origin = i == 0 ? vctrs : rlang;
        if (TYPEOF(expected) != CLOSXP || R_ClosureEnv(expected) != origin ||
            !combine_lexical_function_same(vctrs, Rf_install(external_names[i]), expected) ||
            !combine_lexical_function_same(origin, Rf_install(external_names[i]), expected))
            return 0;
    }
    /* Snapshot proxy conversion calls attributes<- even for canonical pieces.
       Native vctrs dispatch also evaluates unary - in sys.frame(-1).
       .subset and attr must already be settled even when compiled package
       helpers bypass their executable tracers.
       list_unchop supplies no dots; check_dots_empty0 exits on nargs()==0.
       Every names setter receives NULL; names_repair_missing exits at is.null.
       current_env only calls the validated parent.frame. In interpreted or
       optimize=0 forms their control primitives become lexical lookups, so
       qualify those too instead of assuming the ordinary compiler opcodes. */
    for (int i = 0; i < 18; i++) {
        SEXP symbol = Rf_install(primitive_names[i]), expected = VECTOR_ELT(primitive, i);
        if ((TYPEOF(expected) != BUILTINSXP && TYPEOF(expected) != SPECIALSXP) ||
            !combine_lexical_function_same(dtatools, symbol, expected) ||
            !combine_lexical_function_same(vctrs, symbol, expected) ||
            !combine_lexical_function_same(rlang, symbol, expected) ||
            !combine_lexical_function_same(R_BaseNamespace, symbol, expected)) return 0;
    }
    return 1;
}

static int combine_dispatch_unchanged(SEXP dependencies, SEXP combine) {
    static const char *function_names[] = {
        "list_unchop", "vec_ptype2.dta_numeric.dta_numeric",
        "vec_cast.dta_numeric.dta_numeric", "vec_proxy.dta_numeric",
        "vec_restore.dta_numeric", "as.double.dta_numeric",
        "vec_ptype_finalise.default", "names<-.vctrs_vctr"
    };
    static const char *primitive_names[] = {"names", "dim", "as.double", "names<-"};
    static const char *class_methods[5][5] = {
        {"vec_ptype.dta_numeric", "vec_ptype.dta_double",
         "vec_ptype.vctrs_vctr", "vec_ptype.double", NULL},
        {"vec_ptype_finalise.dta_numeric", "vec_ptype_finalise.dta_double",
         "vec_ptype_finalise.vctrs_vctr", "vec_ptype_finalise.double", NULL},
        {"names.dta_numeric", "names.dta_double", "names.vctrs_vctr",
         "names.double", "names.default"},
        {"dim.dta_numeric", "dim.dta_double", "dim.vctrs_vctr",
         "dim.double", "dim.default"},
        {"names<-.dta_numeric", "names<-.dta_double", "names<-.vctrs_vctr",
         "names<-.double", "names<-.default"}
    };
    static SEXP functions[8], primitives[4], methods[5][5], table_symbol, option_symbol;
    if (table_symbol == NULL) {
        option_symbol = Rf_install("vctrs.no_guessing");
        for (int i = 0; i < 8; i++) functions[i] = Rf_install(function_names[i]);
        for (int i = 0; i < 4; i++) primitives[i] = Rf_install(primitive_names[i]);
        for (int row = 0; row < 5; row++)
            for (int col = 0; col < 5; col++)
                if (class_methods[row][col] != NULL)
                    methods[row][col] = Rf_install(class_methods[row][col]);
        table_symbol = Rf_install(".__S3MethodsTable__.");
    }
    SEXP vctrs = VECTOR_ELT(dependencies, 0), dtatools = VECTOR_ELT(dependencies, 1);
    SEXP expected = VECTOR_ELT(dependencies, 2), primitive = VECTOR_ELT(dependencies, 3);
    SEXP vctrs_table = VECTOR_ELT(dependencies, 7), base_table = VECTOR_ELT(dependencies, 8);
    SEXP actual;
    if (!combine_graph_unchanged(dependencies) ||
        !scalar_same_function(combine, VECTOR_ELT(expected, 0)) ||
        combine_peek_frame(vctrs, table_symbol, &actual) != COMBINE_VALUE ||
        actual != vctrs_table ||
        combine_peek_frame(R_BaseNamespace, table_symbol, &actual) != COMBINE_VALUE ||
        actual != base_table) return 0;

    for (int i = 1; i <= 3; i++) {
        SEXP actual_method;
        enum combine_binding binding = combine_peek_frame(R_GlobalEnv, functions[i], &actual_method);
        if (binding == COMBINE_ABSENT)
            binding = combine_peek_frame(vctrs_table, functions[i], &actual_method);
        if (binding != COMBINE_VALUE ||
            !dtatools_execution_function_same(actual_method, VECTOR_ELT(expected, i))) return 0;
    }
    if (!combine_frame_absent(vctrs, functions[4]) ||
        !dtatools_execution_lexical_function_same(vctrs_table, functions[4], VECTOR_ELT(expected, 4)) ||
        !dtatools_execution_lexical_function_same(dtatools, functions[5], VECTOR_ELT(expected, 5)) ||
        !combine_frame_same(vctrs, functions[6], VECTOR_ELT(expected, 6))) return 0;
    for (int i = 0; i < 4; i++) {
        if (!combine_frame_absent(R_GlobalEnv, methods[0][i]) ||
            !combine_frame_absent(vctrs_table, methods[0][i]) ||
            !combine_chain_absent(vctrs, methods[1][i]) ||
            !combine_frame_absent(vctrs_table, methods[1][i])) return 0;
    }
    for (int i = 0; i < 5; i++) {
        if (!combine_chain_absent(dtatools, methods[2][i]) ||
            !combine_chain_absent(vctrs, methods[2][i]) ||
            !combine_frame_absent(base_table, methods[2][i]) ||
            !combine_chain_absent(dtatools, methods[3][i]) ||
            !combine_frame_absent(base_table, methods[3][i])) return 0;
    }
    for (int i = 0; i < 2; i++) {
        if (!combine_chain_absent(dtatools, methods[4][i]) ||
            !combine_frame_absent(base_table, methods[4][i])) return 0;
    }
    if (!combine_frame_absent(dtatools, functions[7]) ||
        !combine_frame_absent(R_GlobalEnv, functions[7]) ||
        !combine_frame_same(base_table, functions[7], VECTOR_ELT(expected, 7))) return 0;
    /* The canonical names setter calls NextMethod(), even for NULL names. */
    for (int i = 3; i < 5; i++) {
        if (!combine_chain_absent(dtatools, methods[4][i]) ||
            !combine_chain_absent(vctrs, methods[4][i]) ||
            !combine_frame_absent(base_table, methods[4][i])) return 0;
    }
    for (int i = 0; i < 4; i++)
        if (!combine_lexical_function_same(dtatools, primitives[i], VECTOR_ELT(primitive, i)))
            return 0;
    if (!combine_lexical_function_same(vctrs, primitives[0], VECTOR_ELT(primitive, 0))) return 0;
    /* Assembly bypasses strict construction, so retain its existing predicate
       and trace callbacks. Use settled lexical lookup here; never force a
       delayed predicate or inspect an arbitrary environment implementation. */
    SEXP strict = VECTOR_ELT(dependencies, 9);
    for (size_t i = 0; i < sizeof(strict_double_predicate_names) /
                            sizeof(strict_double_predicate_names[0]); i++) {
        if (!combine_lexical_function_same(dtatools,
                Rf_install(strict_double_predicate_names[i]), VECTOR_ELT(strict, i))) return 0;
    }
    SEXP option = Rf_GetOption1(option_symbol);
    if (option != R_NilValue &&
        (TYPEOF(option) != LGLSXP || ALTREP(option) || ANY_ATTRIB(option) ||
         Rf_isObject(option) || Rf_isS4(option) || XLENGTH(option) != 1 ||
         LOGICAL(option)[0] != FALSE)) return 0;
    /* The shared validator requires a settled public .Machine binding. */
    return computed_double_limit_unchanged(dtatools);
}

static int combine_double_plain_indices(SEXP value) {
    return TYPEOF(value) == INTSXP && !ALTREP(value) && !ANY_ATTRIB(value) &&
        !Rf_isObject(value) && !Rf_isS4(value);
}

static int combine_double_canonical_piece(SEXP value) {
    if (!Rf_isObject(value) || !scalar_canonical_double(value)) return 0;
    /* scalar_canonical_double checks exact values and ordinary attributes.
       Also reject malformed object/S4 flags on the attribute vectors. */
    SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
    SEXP storage = Rf_getAttrib(value, Rf_install("stata.storage"));
    return !Rf_isObject(classes) && !Rf_isS4(classes) &&
        !Rf_isObject(storage) && !Rf_isS4(storage);
}

SEXP C_dtatools_try_combine_double(
    SEXP pieces, SEXP indices, SEXP combine, SEXP dependencies, SEXP metadata
) {
    if (!combine_dependencies_valid(dependencies, 11)) return R_NilValue;
    if (!dtatools_metadata_dependencies_unchanged(VECTOR_ELT(dependencies, 1), metadata, 0))
        return R_NilValue;
    if (!combine_plain_list(pieces)) return R_NilValue;
    R_xlen_t count = XLENGTH(pieces);
    int indexed = indices != R_NilValue;
    if (count == 0 || (uint64_t) count > (uint64_t) SIZE_MAX / sizeof(SEXP) ||
        (indexed && (!combine_plain_list(indices) ||
                     XLENGTH(indices) != count))) return R_NilValue;

    /* Complete representation admission precedes every numeric payload read.
       Length is callback-free for ordinary vectors and the recognized owned
       class. In particular, do not ask a foreign piece or index its length. */
    R_xlen_t total = 0;
    for (R_xlen_t group = 0; group < count; group++) {
        if ((group & 16383) == 0) R_CheckUserInterrupt();
        SEXP piece = VECTOR_ELT(pieces, group);
        if (!combine_double_canonical_piece(piece)) return R_NilValue;
        SEXP source = owned_real(piece) ? owned_values(piece) : piece;
        if (TYPEOF(source) != REALSXP || ALTREP(source)) return R_NilValue;
        R_xlen_t length = XLENGTH(source);
        if (length > R_XLEN_T_MAX - total) return R_NilValue;
        total += length;
        if (indexed) {
            SEXP positions = VECTOR_ELT(indices, group);
            if (!combine_double_plain_indices(positions) ||
                XLENGTH(positions) != length) return R_NilValue;
        }
    }
    if ((uint64_t) total > (uint64_t) SIZE_MAX / sizeof(double) ||
        total > INT_MAX) return R_NilValue;
    if (!combine_dispatch_unchanged(dependencies, combine)) return R_NilValue;

    /* Root the exact source allocations, not only owned handles whose backing
       records could later change. This list has no borrowed native pointers.
       These roots survive all scratch/output allocations and interrupts. */
    SEXP roots = PROTECT(Rf_allocVector(VECSXP, count));
    combine_root_r_bytes += (double) count * sizeof(SEXP);
    R_xlen_t rooted_total = 0;
    for (R_xlen_t group = 0; group < count; group++) {
        if ((group & 16383) == 0) R_CheckUserInterrupt();
        SEXP piece = VECTOR_ELT(pieces, group);
        SEXP source = owned_real(piece) ? owned_values(piece) : piece;
        SET_VECTOR_ELT(roots, group, source);
        if (TYPEOF(source) != REALSXP || ALTREP(source)) {
            UNPROTECT(1);
            return R_NilValue;
        }
        R_xlen_t length = XLENGTH(source);
        if (length != XLENGTH(piece) || length > R_XLEN_T_MAX - rooted_total ||
            (indexed && length != XLENGTH(VECTOR_ELT(indices, group)))) {
            UNPROTECT(1);
            return R_NilValue;
        }
        rooted_total += length;
    }
    if (rooted_total != total) {
        UNPROTECT(1);
        return R_NilValue;
    }

    /* A valid index list is a partition of 1:total. Equal index/piece lengths,
       in-range positions and uniqueness imply complete coverage; no second
       bitmap scan, integer gather plan or output initialization is needed. */
    if (indexed && total != 0) {
        size_t bit_bytes = (size_t) total / CHAR_BIT +
            ((size_t) total % CHAR_BIT != 0);
        const void *marker = vmaxget();
        unsigned char *seen = (unsigned char *) R_alloc(bit_bytes, 1);
        combine_partition_r_bytes += (double) bit_bytes;
        for (size_t start = 0; start < bit_bytes; ) {
            R_CheckUserInterrupt();
            size_t amount = bit_bytes - start > 16384 ? 16384 : bit_bytes - start;
            memset(seen + start, 0, amount);
            start += amount;
        }
        for (R_xlen_t group = 0; group < count; group++) {
            if ((group & 16383) == 0) R_CheckUserInterrupt();
            SEXP positions = VECTOR_ELT(indices, group);
            const int *locations = INTEGER(positions);
            R_xlen_t length = XLENGTH(positions);
            for (R_xlen_t i = 0; i < length; i++) {
                if ((i & 16383) == 0) R_CheckUserInterrupt();
                int position = locations[i];
                if (position == NA_INTEGER || position < 1 ||
                    (R_xlen_t) position > total) {
                    vmaxset(marker);
                    UNPROTECT(1);
                    return R_NilValue;
                }
                size_t offset = (size_t) position - 1;
                unsigned char mask = (unsigned char) (1U << (offset % CHAR_BIT));
                unsigned char *byte = seen + offset / CHAR_BIT;
                if (*byte & mask) {
                    vmaxset(marker);
                    UNPROTECT(1);
                    return R_NilValue;
                }
                *byte |= mask;
            }
        }
        /* No native scratch pointer escapes. R also reclaims R_alloc storage
           if an interrupt unwinds before this explicit early release. */
        vmaxset(marker);
    }

    /* Validate all values before allocating the destination. The strict
       predicate distinguishes valid system/tagged missing from NaN, infinity,
       invalid tags and values outside Stata's strict double range. */
    int no_missing = 1;
    for (R_xlen_t group = 0; group < count; group++) {
        if ((group & 16383) == 0) R_CheckUserInterrupt();
        SEXP source = VECTOR_ELT(roots, group);
        const double *values = REAL(source);
        R_xlen_t length = XLENGTH(source);
        for (R_xlen_t i = 0; i < length; i++) {
            if ((i & 16383) == 0) R_CheckUserInterrupt();
            if (!strict_double_valid(values[i], &no_missing)) {
                UNPROTECT(1);
                return R_NilValue;
            }
        }
    }

    /* Only this fresh allocation is adopted. Byte copies preserve signed zero
       and every admitted missing payload even if validation loaded a NaN into
       a floating-point register. No input record/fact/share flag is changed. */
    SEXP backing = PROTECT(Rf_allocVector(REALSXP, total));
    double *output = REAL(backing);
    R_xlen_t offset = 0;
    for (R_xlen_t group = 0; group < count; group++) {
        if ((group & 16383) == 0) R_CheckUserInterrupt();
        SEXP source = VECTOR_ELT(roots, group);
        const double *values = REAL(source);
        R_xlen_t length = XLENGTH(source);
        const int *locations = indexed ? INTEGER(VECTOR_ELT(indices, group)) : NULL;
        for (R_xlen_t start = 0; start < length; ) {
            R_CheckUserInterrupt();
            R_xlen_t amount = length - start > 16384 ? 16384 : length - start;
            if (indexed) {
                for (R_xlen_t i = start; i < start + amount; i++) {
                    R_xlen_t destination = (R_xlen_t) locations[i] - 1;
                    memcpy(output + destination, values + i, sizeof(double));
                }
            } else {
                memcpy(output + offset + start, values + start,
                       (size_t) amount * sizeof(double));
            }
            /* Count actual copied bytes even if a later interrupt aborts. */
            combine_copied_payload_bytes += (double) amount * sizeof(double);
            start += amount;
        }
        offset += length;
    }
    SEXP result = PROTECT(owned_adopt_real(backing));
    owned_flags(result)[OWNED_NO_NA] = no_missing;
    /* The original combiner gives each result fresh class and storage vectors.
       Public by-reference edits must not reach another result or the profile. */
    SEXP classes = PROTECT(Rf_duplicate(VECTOR_ELT(dependencies, 4)));
    SEXP storage = PROTECT(Rf_duplicate(VECTOR_ELT(dependencies, 5)));
    Rf_setAttrib(result, Rf_install("stata.storage"), storage);
    Rf_setAttrib(result, R_ClassSymbol, classes);
    UNPROTECT(5);
    return result;
}

/* The indexed adapter keeps the original mask$rows expression on fallback.
   Borrow only the exact field of an ordinary list; never invoke $, inspect a
   foreign names vector, or force a mask promise to decide admission. */
static SEXP combine_settled_mask_rows(SEXP mask) {
    if (TYPEOF(mask) != VECSXP || ALTREP(mask) ||
        Rf_isObject(mask) || Rf_isS4(mask) ||
        R_mapAttrib(mask, mask_bindings_current_attribute, NULL) != NULL)
        return R_UnboundValue;
    SEXP names = Rf_getAttrib(mask, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || ALTREP(names) || ANY_ATTRIB(names) ||
        Rf_isObject(names) || Rf_isS4(names) || XLENGTH(names) != XLENGTH(mask) ||
        XLENGTH(mask) > 128) return R_UnboundValue;
    for (R_xlen_t i = 0; i < XLENGTH(mask); i++) {
        SEXP name = STRING_ELT(names, i);
        if (name != NA_STRING && strcmp(CHAR(name), "rows") == 0)
            return VECTOR_ELT(mask, i);
    }
    return R_UnboundValue;
}

/* On the audited loaded-namespace path, :: is the only R function called by
   lookup. Its C implementation reads this namespace info/export mapping and
   then the mapped binding. All of those reads must be settled and ordinary.
   dtatools Imports vctrs, so supported unloadNamespace() cannot unregister it
   while dtatools is loaded. Direct private namespace-registry mutation is not
   covered; its only callback-free C handle is explicitly non-API. */
static SEXP vctrs_exported_function(
    SEXP frame, SEXP ns, const char *name, SEXP expected_colon
) {
    SEXP colon = Rf_install("::");
    SEXP spec_symbol = Rf_install("spec"), exports_symbol = Rf_install("exports");
    SEXP function_symbol = Rf_install(name);
    if (!dtatools_execution_lexical_function_same(frame, colon, expected_colon))
        return R_UnboundValue;
    SEXP info, spec, exports, alias, function;
    if (R_GetBindingType(R_NamespaceEnvSymbol, ns) != R_BindingTypeValue ||
        combine_peek_frame(ns, R_NamespaceEnvSymbol, &info) != COMBINE_VALUE ||
        !combine_plain_environment(info) ||
        R_GetBindingType(spec_symbol, info) != R_BindingTypeValue ||
        combine_peek_frame(info, spec_symbol, &spec) != COMBINE_VALUE ||
        TYPEOF(spec) != STRSXP || ALTREP(spec) ||
        R_mapAttrib(spec, computed_attribute, NULL) != NULL ||
        XLENGTH(spec) < 1 || XLENGTH(spec) > 8 || STRING_ELT(spec, 0) == NA_STRING ||
        strcmp(CHAR(STRING_ELT(spec, 0)), "vctrs") != 0 ||
        combine_peek_frame(info, exports_symbol, &exports) != COMBINE_VALUE ||
        combine_peek_frame(exports, function_symbol, &alias) != COMBINE_VALUE ||
        TYPEOF(alias) != STRSXP || ALTREP(alias) || ANY_ATTRIB(alias) ||
        XLENGTH(alias) != 1 || STRING_ELT(alias, 0) == NA_STRING ||
        strcmp(CHAR(STRING_ELT(alias, 0)), name) != 0 ||
        combine_peek_frame(ns, function_symbol, &function) != COMBINE_VALUE)
        return R_UnboundValue;
    return function;
}

static SEXP combine_exported_function(SEXP frame, SEXP dependencies) {
    SEXP primitives = VECTOR_ELT(dependencies, 3);
    if (!dtatools_execution_lexical_function_same(
            frame, Rf_install("<-"), VECTOR_ELT(primitives, 5)))
        return R_UnboundValue;
    return vctrs_exported_function(frame, VECTOR_ELT(dependencies, 0),
                                    "list_unchop", VECTOR_ELT(primitives, 4));
}

/* The original R assignment follows the native status call. Only an absent
   or ordinary unlocked target can be published without invoking a setter or
   forcing a promise. Reusing an ordinary value slot supports later expressions
   in the same run frame. Active, delayed and locked targets retain R fallback. */
static int combine_assignment_available(SEXP frame, SEXP symbol) {
    if (!combine_plain_environment(frame) || R_EnvironmentIsLocked(frame)) return 0;
    R_BindingType_t type = R_GetBindingType(symbol, frame);
    return type == R_BindingTypeUnbound ||
        ((type == R_BindingTypeValue || type == R_BindingTypeForced) &&
         !R_BindingIsLocked(symbol, frame));
}

/* Production calls stay at their original assignment sites. This native
   attempt receives no operands and never forces one: unsupported promises or
   namespace lookups reach the untouched original R call, in the original
   evaluation frame, before any argument promise is evaluated. */
SEXP C_dtatools_combine_double_into_current(
    SEXP indexed, SEXP state, SEXP metadata_state
) {
    SEXP frame = R_GetCurrentEnv(), dependencies, metadata;
    if (TYPEOF(indexed) != LGLSXP || ALTREP(indexed) || ANY_ATTRIB(indexed) ||
        XLENGTH(indexed) != 1 || LOGICAL(indexed)[0] == NA_LOGICAL)
        return Rf_ScalarLogical(FALSE);
    int use_indices = LOGICAL(indexed)[0];
    if (use_indices) {
        /* R_GetCurrentEnv in the original indexed block reports tryCatch's
           closure frame. The admission-only helper supplies exact unforced
           symbol promises whose shared environment is the original run frame.
           No R environment()/parent.frame() callback or arbitrary expression
           evaluation is required to recover it. */
        SEXP chunks_symbol = Rf_install("chunks"), mask_symbol = Rf_install("mask");
        if (!combine_plain_environment(frame) ||
            R_GetBindingType(chunks_symbol, frame) != R_BindingTypeDelayed ||
            R_GetBindingType(mask_symbol, frame) != R_BindingTypeDelayed ||
            R_DelayedBindingExpression(chunks_symbol, frame) != chunks_symbol ||
            R_DelayedBindingExpression(mask_symbol, frame) != mask_symbol)
            return Rf_ScalarLogical(FALSE);
        SEXP caller = R_DelayedBindingEnvironment(chunks_symbol, frame);
        if (caller != R_DelayedBindingEnvironment(mask_symbol, frame))
            return Rf_ScalarLogical(FALSE);
        frame = caller;
    }
    SEXP target = Rf_install(use_indices ? "value" : "result");
    if (!combine_assignment_available(frame, target) ||
        combine_peek_frame(state, Rf_install("dependencies"), &dependencies) != COMBINE_VALUE ||
        combine_peek_frame(metadata_state, Rf_install("dependencies"), &metadata) != COMBINE_VALUE)
        return Rf_ScalarLogical(FALSE);
    PROTECT(dependencies);
    PROTECT(metadata);
    if (!combine_dependencies_valid(dependencies, 11)) {
        UNPROTECT(2);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP combine = PROTECT(combine_exported_function(frame, dependencies));
    SEXP pieces = PROTECT(computed_peek(Rf_install(use_indices ? "chunks" : "pieces"), frame, 16));
    SEXP mask = PROTECT(use_indices ? computed_peek(Rf_install("mask"), frame, 16) : R_NilValue);
    SEXP indices = R_NilValue;
    if (use_indices) {
        SEXP strict = VECTOR_ELT(dependencies, 9);
        if (!dtatools_execution_lexical_function_same(frame, Rf_install("$"),
                                                     VECTOR_ELT(strict, 20))) {
            UNPROTECT(5);
            return Rf_ScalarLogical(FALSE);
        }
        indices = combine_settled_mask_rows(mask);
    }
    PROTECT(indices);
    SEXP result = PROTECT(combine == R_UnboundValue || pieces == R_UnboundValue ||
        indices == R_UnboundValue ? R_NilValue :
        C_dtatools_try_combine_double(pieces, indices, combine, dependencies, metadata));
    /* Allocation may run finalizers that alter the local assignment target. */
    int admitted = result != R_NilValue && combine_assignment_available(frame, target);
    if (admitted) {
        /* The original combiner forces these qualified argument chains before
           later caller callbacks can rebind their sources. Keep the result
           rooted while settling those same promises in the same order. */
        R_getVar(Rf_install(use_indices ? "chunks" : "pieces"), frame, TRUE);
        if (use_indices) R_getVar(Rf_install("mask"), frame, TRUE);
        admitted = combine_assignment_available(frame, target);
        if (admitted) Rf_defineVar(target, result, frame);
    }
    UNPROTECT(7);
    return Rf_ScalarLogical(admitted);
}

static SEXP C_dtatools_construct_double_impl(SEXP value, SEXP frame, SEXP dependencies) {
    /* Only owned bare values reach the old isTRUE(replacement_fits()) call.
       Plain inputs must not wait for that otherwise-unused lazy base binding. */
    unsigned route = DTATOOLS_NUMERIC_CONSTRUCT |
        (owned_real(value) ? DTATOOLS_NUMERIC_OWNED_CONSTRUCT : 0U);
    if (!strict_double_admitted(value, frame, dependencies) ||
        !dtatools_numeric_helpers_admitted(frame, route)) return R_NilValue;
    SEXP source = PROTECT(owned_real(value) ? owned_values(value) : value);
    if (TYPEOF(source) != REALSXP || ALTREP(source)) {
        UNPROTECT(1);
        return R_NilValue;
    }
    R_xlen_t length = XLENGTH(source);
    const double *values = REAL(source);
    int no_missing = 1;
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        if (!strict_double_valid(values[i], &no_missing)) {
            UNPROTECT(1);
            return R_NilValue;
        }
    }
    /* Reuse capture/fork ownership and its copy-byte accounting. Invalid
       ordinary inputs reach fallback without allocating another payload. */
    SEXP result = PROTECT(owned_fork(value));
    owned_flags(result)[OWNED_NO_NA] = no_missing;
    UNPROTECT(2);
    return result;
}

SEXP C_dtatools_construct_double(SEXP value, SEXP frame, SEXP dependencies) {
    /* Explicit-frame callers retain the payload-or-NULL native test contract. */
    if (frame != R_NilValue) return C_dtatools_construct_double_impl(value, frame, dependencies);
    frame = R_GetCurrentEnv();
    if (!numeric_size_admitted(frame, DTATOOLS_NUMERIC_CONSTRUCT)) return Rf_ScalarLogical(FALSE);
    if (!dtatools_numeric_entry_frame_admitted(frame, DTATOOLS_NUMERIC_CONSTRUCT) ||
        !numeric_result_slot_available(frame)) return Rf_ScalarLogical(FALSE);
    value = PROTECT(computed_peek(Rf_install("x"), frame, 16));
    SEXP size = PROTECT(computed_peek(Rf_install(".size"), frame, 16));
    SEXP storage = PROTECT(computed_peek(Rf_install("storage"), frame, 16));
    SEXP temporal = PROTECT(computed_peek(Rf_install("temporal"), frame, 16));
    if (!numeric_entry_bare_double(value) || size != R_NilValue ||
        computed_storage_kind(storage) != NUMERIC_DOUBLE ||
        TYPEOF(temporal) != INTSXP || ALTREP(temporal) || ANY_ATTRIB(temporal) ||
        Rf_isObject(temporal) || Rf_isS4(temporal) ||
        XLENGTH(temporal) != 1 || INTEGER(temporal)[0] != 0 ||
        !dtatools_numeric_decoration_admitted(frame, DTATOOLS_NUMERIC_CONSTRUCT,
                                               R_NilValue)) {
        UNPROTECT(4);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP payload = PROTECT(C_dtatools_construct_double_impl(value, frame, dependencies));
    if (payload == R_NilValue) {
        UNPROTECT(5);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP result = PROTECT(numeric_decorate_result(payload, storage));
    if (result == R_NilValue || !numeric_result_slot_available(frame)) {
        UNPROTECT(6);
        return Rf_ScalarLogical(FALSE);
    }
    /* A bare non-NULL input forces x and .size in the first validation test.
       The double storage branch next forces storage, then valid_owned forces
       temporal. Preserve those original expressions and ancestor promises. */
    R_getVar(Rf_install("x"), frame, TRUE);
    R_getVar(Rf_install(".size"), frame, TRUE);
    R_getVar(Rf_install("storage"), frame, TRUE);
    R_getVar(Rf_install("temporal"), frame, TRUE);
    SEXP status = numeric_result_commit(result, frame);
    if (LOGICAL(status)[0]) numeric_construct_successes++;
    UNPROTECT(6);
    return status;
}

/* Only success bypasses the legacy fit helper. Its unusual-tag behavior and
   all diagnostics remain on fallback; a delayed storage expression is not
   forced before missing classification would have reached it in R. */
static SEXP C_dtatools_double_fits_impl(SEXP value, SEXP frame, SEXP dependencies) {
    if (TYPEOF(frame) != ENVSXP ||
        computed_storage_kind(computed_peek(Rf_install("storage"), frame, 16)) != NUMERIC_DOUBLE ||
        !strict_double_admitted(value, frame, dependencies) ||
        !dtatools_numeric_helpers_admitted(frame, DTATOOLS_NUMERIC_HOLDS)) return R_NilValue;
    SEXP source = PROTECT(owned_real(value) ? owned_values(value) : value);
    if (TYPEOF(source) != REALSXP || ALTREP(source)) {
        UNPROTECT(1);
        return R_NilValue;
    }
    const double *values = REAL(source);
    R_xlen_t length = XLENGTH(source);
    int no_missing = 1;
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        if (!strict_double_valid(values[i], &no_missing)) {
            UNPROTECT(1);
            return R_NilValue;
        }
    }
    UNPROTECT(1);
    return Rf_ScalarLogical(TRUE);
}

SEXP C_dtatools_double_fits(SEXP value, SEXP frame, SEXP dependencies) {
    if (frame != R_NilValue) return C_dtatools_double_fits_impl(value, frame, dependencies);
    frame = R_GetCurrentEnv();
    if (!numeric_size_admitted(frame, DTATOOLS_NUMERIC_HOLDS)) return Rf_ScalarLogical(FALSE);
    if (!dtatools_numeric_entry_frame_admitted(frame, DTATOOLS_NUMERIC_HOLDS))
        return Rf_ScalarLogical(FALSE);
    /* The production caller passes NULL so .Call cannot force doubles before
       .tab_missing_codes and its callbacks. Follow settled values, literals,
       and symbol forwarding only; leave every other promise to the R path. */
    value = computed_peek(Rf_install("doubles"), frame, 16);
    if (value == R_UnboundValue) return Rf_ScalarLogical(FALSE);
    PROTECT(value);
    SEXP result = PROTECT(C_dtatools_double_fits_impl(value, frame, dependencies));
    if (result != R_NilValue) {
        /* Success replaces R checks that force both original argument chains.
           A retained caller must keep their values after outer rebindings. */
        R_getVar(Rf_install("doubles"), frame, TRUE);
        R_getVar(Rf_install("storage"), frame, TRUE);
        numeric_holds_successes++;
    }
    UNPROTECT(2);
    return result == R_NilValue ? Rf_ScalarLogical(FALSE) : result;
}

SEXP C_dtatools_construct_numeric_trusted(
    SEXP value, SEXP missing_codes, SEXP kind_value, SEXP temporal_value
) {
    if (TYPEOF(value) != REALSXP || TYPEOF(missing_codes) != INTSXP ||
        XLENGTH(value) != XLENGTH(missing_codes)) {
        Rf_error("invalid trusted Stata numeric construction buffers");
    }
    if (TYPEOF(kind_value) != INTSXP || XLENGTH(kind_value) != 1) {
        Rf_error("invalid compact Stata numeric storage type");
    }
    int kind = INTEGER(kind_value)[0];
    if (TYPEOF(temporal_value) != INTSXP ||
        XLENGTH(temporal_value) != 1 ||
        INTEGER(temporal_value)[0] < 0 || INTEGER(temporal_value)[0] > 2) {
        Rf_error("invalid compact Stata temporal storage type");
    }
    int temporal = INTEGER(temporal_value)[0];
    size_t width = numeric_kind_width(kind);
    R_xlen_t length = XLENGTH(value);
    if ((size_t) length > SIZE_MAX / width ||
        (size_t) length * width > (size_t) R_XLEN_T_MAX) {
        Rf_error("compact Stata numeric vector is too long");
    }

    R_xlen_t byte_length = (R_xlen_t) ((size_t) length * width);
    SEXP backing = PROTECT(Rf_allocVector(RAWSXP, byte_length));
    unsigned char *output = RAW(backing);
    size_t missing_count = 0;
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        int code = INTEGER_ELT(missing_codes, index);
        if (code == NA_INTEGER) {
            write_numeric_observed_trusted(
                output, index, kind, REAL_ELT(value, index)
            );
            continue;
        }
        int offset = code == 0 ? 0 : code >= 'a' && code <= 'z'
            ? code - 'a' + 1 : -1;
        if (offset < 0) {
            UNPROTECT(1);
            Rf_error("invalid trusted Stata numeric missing code");
        }
        missing_count++;
        write_numeric_missing(output, index, kind, offset);
    }

    void *data = dtatools_numeric_alloc(
        output, (size_t) length, kind, temporal, missing_count
    );
    if (data == NULL) {
        UNPROTECT(1);
        Rf_error("could not allocate compact Stata numeric storage");
    }
    SEXP external = PROTECT(R_MakeExternalPtr(data, R_NilValue, backing));
    R_RegisterCFinalizerEx(external, numeric_finalize, TRUE);
    SEXP result = PROTECT(R_new_altrep(
        dtatools_numeric_class, external, R_NilValue
    ));
    UNPROTECT(3);
    return result;
}

#include "initial-capture.inc"
