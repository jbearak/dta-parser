/* Compact numeric payloads: the numeric_data descriptor, its ALTREP class
   methods, the per-element read and write kernels, the reader shared with
   mutation and egen, and the Rust bridge that hands finished payloads to R.
   Per-element helpers that hot loops call stay in this unit. */
#include "dtatools-internal.h"

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
    if (data->native_owner != NULL) {
        SEXP detached = PROTECT(numeric_compact_copy(data));
        owned_numeric_compatibility_bytes +=
            (double) data->length * (double) numeric_kind_width(data->kind);
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
    if (data->native_owner == NULL) {
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

void numeric_copy_region(
    const numeric_data *data, size_t start, size_t length, void *output
) {
    size_t width = numeric_kind_width(data->kind);
    if (start > data->length || length > data->length - start) {
        Rf_error("invalid compact numeric copy range");
    }
    if (data->native_owner == NULL) {
        if (length != 0) memcpy(output, (const unsigned char *) data->values + start * width, length * width);
        return;
    }
    size_t copied = 0;
    while (copied < length) {
        if (length >= 16384) R_CheckUserInterrupt();
        size_t count = 0;
        size_t wanted = length - copied < 65536 ? length - copied : 65536;
        const void *values = numeric_read_span(data, start + copied, wanted, &count);
        memcpy((unsigned char *) output + copied * width, values, count * width);
        copied += count;
    }
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

#define DEFINE_NUMERIC_KERNELS(NAME, TYPE, MISSING_OFFSET)                    \
    static TYPE numeric_##NAME##_raw_at(                                     \
        const numeric_data *data, size_t index                               \
    ) {                                                                       \
        TYPE raw;                                                             \
        if (data->native_owner == NULL) {                                     \
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
    static double numeric_##NAME##_value_at(                                  \
        const numeric_data *data, size_t index                                \
    ) {                                                                       \
        TYPE raw = numeric_##NAME##_raw_at(data, index);                      \
        int missing = MISSING_OFFSET(raw, data->format_version);              \
        return missing >= 0                                                   \
            ? numeric_missing_value(missing)                                  \
            : numeric_observed_value((double) raw, data->temporal);           \
    }                                                                         \
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
    static void numeric_##NAME##_sum_accumulate(                              \
        const numeric_data *data, Rboolean na_rm, long double *accumulator    \
    ) {                                                                       \
        long double sum = *accumulator;                                       \
        if (data->missing_count == 0) {                                       \
            for (size_t index = 0; index < data->length; index++) {           \
                if ((index & 16383) == 0) R_CheckUserInterrupt();             \
                TYPE raw = numeric_##NAME##_raw_at(data, index);              \
                sum += numeric_observed_value((double) raw, data->temporal);  \
            }                                                                 \
        } else {                                                              \
            for (size_t index = 0; index < data->length; index++) {           \
                if ((index & 16383) == 0) R_CheckUserInterrupt();             \
                double element = numeric_##NAME##_value_at(data, index);      \
                if (!na_rm || !ISNAN(element)) sum += element;                \
            }                                                                 \
        }                                                                     \
        *accumulator = sum;                                                   \
    }                                                                         \
                                                                              \
    static long double numeric_##NAME##_sum(                                  \
        const numeric_data *data, Rboolean na_rm                              \
    ) {                                                                       \
        long double sum = 0.0;                                                \
        numeric_##NAME##_sum_accumulate(data, na_rm, &sum);                   \
        return sum;                                                           \
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
        if (numeric_read_storage(source)->native_owner != NULL)
            return numeric_handle_copy(source);
        return R_ExternalPtrProtected(R_altrep_data1(source));
    }
    if (ALTREP(value) && R_altrep_data2(value) != R_NilValue) return R_altrep_data2(value);
    return value;
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

double numeric_reader_at(
    const numeric_reader *reader, R_xlen_t index, int *missing_code
) {
    if (reader->storage != NULL) {
        numeric_data *data = reader->storage;
        int offset = numeric_missing_offset_at(data, (size_t) index);
        if (offset >= 0) {
            *missing_code = offset == 0 ? 0 : 'a' + offset - 1;
            return 0.0;
        }
        double value = numeric_value_at(data, (size_t) index);
        if (ISNAN(value)) {
            *missing_code = 256;
            return 0.0;
        }
        *missing_code = -1;
        return value;
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
DTATOOLS_LAYOUT_ASSERT(numeric_size, sizeof(numeric_data) == 48);
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

static void numeric_fill_region(
    const numeric_data *data, size_t index, size_t length, double *output
) {
    if (data->native_owner != NULL) {
        size_t copied = 0;
        while (copied < length) {
            size_t count = 0;
            const void *values = numeric_read_span(data, index + copied, length - copied, &count);
            numeric_data region = *data;
            region.values = (void *) values;
            region.length = count;
            region.native_owner = NULL;
            numeric_fill_region(&region, 0, count, output + copied);
            copied += count;
        }
        return;
    }
    switch (data->kind) {
    case NUMERIC_BYTE:
        numeric_byte_region(data, index, length, output);
        return;
    case NUMERIC_INT:
        numeric_int_region(data, index, length, output);
        return;
    case NUMERIC_LONG:
        numeric_long_region(data, index, length, output);
        return;
    case NUMERIC_FLOAT:
        numeric_float_region(data, index, length, output);
        return;
    default:
        Rf_error("invalid dtatools numeric storage kind");
    }
}

static long double numeric_sum_storage(
    const numeric_data *data, Rboolean na_rm
) {
    if (data->native_owner != NULL) {
        long double sum = 0.0;
        for (size_t start = 0; start < data->length;) {
            R_CheckUserInterrupt();
            size_t count = 0;
            numeric_data region = *data;
            region.values = (void *) numeric_read_span(data, start, data->length - start, &count);
            region.length = count;
            region.native_owner = NULL;
            /* Carry one accumulator through every row. Summing independent
               chunks and combining their totals changes floating rounding. */
            switch (data->kind) {
            case NUMERIC_BYTE: numeric_byte_sum_accumulate(&region, na_rm, &sum); break;
            case NUMERIC_INT: numeric_int_sum_accumulate(&region, na_rm, &sum); break;
            case NUMERIC_LONG: numeric_long_sum_accumulate(&region, na_rm, &sum); break;
            case NUMERIC_FLOAT: numeric_float_sum_accumulate(&region, na_rm, &sum); break;
            default: Rf_error("invalid dtatools numeric storage kind");
            }
            start += count;
        }
        return sum;
    }
    switch (data->kind) {
    case NUMERIC_BYTE:
        return numeric_byte_sum(data, na_rm);
    case NUMERIC_INT:
        return numeric_int_sum(data, na_rm);
    case NUMERIC_LONG:
        return numeric_long_sum(data, na_rm);
    case NUMERIC_FLOAT:
        return numeric_float_sum(data, na_rm);
    default:
        Rf_error("invalid dtatools numeric storage kind");
    }
}

static int numeric_extreme_storage(
    const numeric_data *data, Rboolean na_rm, int minimum, double *result
) {
    if (data->native_owner != NULL) {
        double current = 0.0;
        int updated = 0;
        for (size_t start = 0; start < data->length;) {
            R_CheckUserInterrupt();
            size_t count = 0;
            numeric_data region = *data;
            region.values = (void *) numeric_read_span(data, start, data->length - start, &count);
            region.length = count;
            region.native_owner = NULL;
            switch (data->kind) {
            case NUMERIC_BYTE: numeric_byte_extreme_accumulate(&region, na_rm, minimum, &current, &updated); break;
            case NUMERIC_INT: numeric_int_extreme_accumulate(&region, na_rm, minimum, &current, &updated); break;
            case NUMERIC_LONG: numeric_long_extreme_accumulate(&region, na_rm, minimum, &current, &updated); break;
            case NUMERIC_FLOAT: numeric_float_extreme_accumulate(&region, na_rm, minimum, &current, &updated); break;
            default: Rf_error("invalid dtatools numeric storage kind");
            }
            start += count;
        }
        if (updated) *result = current;
        return updated;
    }
    switch (data->kind) {
    case NUMERIC_BYTE:
        return numeric_byte_extreme(data, na_rm, minimum, result);
    case NUMERIC_INT:
        return numeric_int_extreme(data, na_rm, minimum, result);
    case NUMERIC_LONG:
        return numeric_long_extreme(data, na_rm, minimum, result);
    case NUMERIC_FLOAT:
        return numeric_float_extreme(data, na_rm, minimum, result);
    default:
        Rf_error("invalid dtatools numeric storage kind");
    }
}

double numeric_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return REAL_ELT(materialized, index);
    numeric_data *data = numeric_read_storage(value);
    if (index < 0 || (size_t) index >= data->length) {
        Rf_error("invalid dtatools numeric-vector index");
    }
    return numeric_value_at(data, (size_t) index);
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
    if (data->native_owner != NULL) {
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
    UNPROTECT(2);
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

/* Share only immutable bytes. Every returned vector has its own descriptor,
   external pointer and materialization state, plus the original R roots. */
SEXP numeric_handle_copy(SEXP source) {
    numeric_data *data = numeric_read_storage(source);
    if (data->native_owner == NULL) return numeric_compact_copy(data);
    SEXP external = PROTECT(R_MakeExternalPtr(
        NULL, R_NilValue, R_ExternalPtrProtected(R_altrep_data1(source))
    ));
    R_RegisterCFinalizerEx(external, numeric_finalize, TRUE);
    void *copy = dtatools_owned_numeric_clone(data);
    if (copy == NULL) Rf_error("could not retain an owned numeric column");
    R_SetExternalPtrAddr(external, copy);
    SEXP result = PROTECT(R_new_altrep(dtatools_numeric_class, external, R_NilValue));
    UNPROTECT(2);
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
    SEXP read_handle = PROTECT(numeric_read_storage(value)->native_owner != NULL
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
    if (source->native_owner != NULL) {
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
        !(backing == R_NilValue && ((numeric_data *) data)->native_owner != NULL)) return 0;
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
        uint32_t maximum_bits = UINT32_C(0x7effffff);
        float maximum;
        memcpy(&maximum, &maximum_bits, sizeof(maximum));
        if (!R_FINITE(value) || value < -(double) maximum ||
            value > (double) maximum) {
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
    uint32_t float_maximum_bits = UINT32_C(0x7effffff);
    float float_maximum;
    memcpy(&float_maximum, &float_maximum_bits, sizeof(float_maximum));
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
            fabs(element) <= (double) float_maximum;
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
