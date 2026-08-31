#include <R.h>
#include <Rversion.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Altrep.h>
#include <R_ext/GraphicsEngine.h>
#include <R_ext/Utils.h>
#include <R_ext/Visibility.h>
#include <float.h>
#include <limits.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern SEXP dtatools_metadata_rust(
    const char *, uint32_t, uint32_t, const char *, char **
);
extern SEXP dtatools_read_rust(
    const char *, const int *, size_t, int, double, double, int, int, int,
    const char *, char **
);
extern int dtatools_write_rust(
    const char *, const char *, SEXP, const void *,
    size_t, double *, size_t, const char *, char **
);
extern int dtatools_write_path_kind(const char *, char **);
extern void dtatools_free_error(char *);
extern void dtatools_numeric_free(void *);
extern void *dtatools_numeric_alloc(void *, size_t, int, int, size_t);
extern int dtatools_gather_numeric_columns(
    const void *, size_t, const int *, const int *, size_t
);
extern void dtatools_dictstring_free(void *);
extern int dtatools_dictstring_bytes(
    void *, uint32_t, const char **, int *
);
extern void *dtatools_dictstring_clone(const void *);

typedef struct {
    const char *name;
    int kind;
    const char *label;
    const char *format;
    int storage;
    int string_storage;
    int ordered;
    const char *tz;
    const char *units;
    const void *values;
    SEXP strings;
    size_t string_count;
    const void *compact_values;
    int compact_kind;
    int compact_format_version;
    int compact_temporal;
    const double *label_values;
    SEXP label_texts;
    size_t label_count;
    SEXP stata_metadata;
    int has_value_labels;
    int haven_labelled;
    /* Unmaterialized dictionary-string payload, or NULL for eager columns. */
    const void *dictstring;
} dtatools_arrow_column;

extern SEXP dtatools_save_arrow_rust(
    const char *, const char *, SEXP, const dtatools_arrow_column *,
    size_t, size_t, const char *, int, int, int *, char **
);
extern SEXP dtatools_datasig_rust(
    const char *, SEXP, const dtatools_arrow_column *, size_t, size_t,
    int, int *, char **
);
extern void *dtatools_open_arrow_rust(const char *, char **);
extern void dtatools_close_arrow_rust(void *);
extern SEXP dtatools_read_arrow_rust(
    const void *, const int *, size_t, int, double, double, int, int, int,
    int, int, int *, char **
);
extern SEXP dtatools_arrow_metadata_rust(
    const void *, int, int, double, double, int *, char **
);
extern SEXP dtatools_arrow_datasig_rust(const char *, char **);

typedef struct {
    uint32_t *value_ids;
    size_t length;
} dictstring_data;

static R_altrep_class_t dtatools_dictstring_class;
static R_altrep_class_t dtatools_numeric_class;
static R_altrep_class_t dtatools_metadata_real_class;
static R_altrep_class_t dtatools_metadata_string_class;
static R_altrep_class_t dtatools_ephemeral_string_class;
static SEXP write_callback_condition_classes;
static int metadata_real_aggregate_mask_enabled;
static int metadata_real_aggregate_mask;

static dictstring_data *dictstring_storage(SEXP value);
static SEXP dictstring_cache(SEXP value);
static SEXP unmaterialized_dictstring_source(SEXP value);
static SEXP metadata_proxy_source(SEXP value);
static SEXP metadata_proxy_owner(SEXP value);
static void metadata_proxy_set_state(SEXP value, SEXP source, SEXP owner);
static SEXP dictstring_compact_copy(SEXP value);
static size_t numeric_kind_width(int kind);
static int string_declared_width(SEXP declared, const char *message);
static size_t reference_string_width(SEXP value, const char *operation);
static void write_numeric_missing(
    unsigned char *output, R_xlen_t index, int kind, int offset
);

enum {
    METADATA_AGGREGATE_NO_NA = 1,
    METADATA_AGGREGATE_SUM = 2,
    METADATA_AGGREGATE_MIN = 4,
    METADATA_AGGREGATE_MAX = 8
};

typedef struct {
    void *values;
    size_t length;
    int kind;
    int temporal;
    int format_version;
    size_t missing_count;
} numeric_data;

static SEXP numeric_compact_copy(const numeric_data *data);

/* Compact ALTREP payload ownership lives in the external-pointer tag. A NULL
   tag is directly writable. A non-NULL tag means an alias exists and ordinary
   writes must detach. Metadata proxies use a private token as both the tag and
   their owner claim; R_BaseEnv is the anonymous shared marker. Keep those
   states behind these helpers rather than spreading tag policy across ALTREP
   materialization and reference mutation. */
static int compact_payload_is_shared(SEXP external) {
    return R_ExternalPtrTag(external) != R_NilValue;
}

static void compact_payload_mark_shared(SEXP external) {
    R_SetExternalPtrTag(external, R_BaseEnv);
}

static int compact_payload_is_owned_by(SEXP external, SEXP owner) {
    return owner != R_NilValue && R_ExternalPtrTag(external) == owner;
}

static void compact_payload_claim(SEXP external, SEXP owner) {
    R_SetExternalPtrTag(external, owner);
}

static void compact_payload_revoke_claim(SEXP external) {
    R_SetExternalPtrTag(external, R_NilValue);
}

static SEXP detach_shared_materialized_payload(SEXP value) {
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
} numeric_gather_column;

enum {
    NUMERIC_BYTE = 0,
    NUMERIC_INT = 1,
    NUMERIC_LONG = 2,
    NUMERIC_FLOAT = 3,
    NUMERIC_DOUBLE = 4
};

static void numeric_finalize(SEXP external) {
    void *data = R_ExternalPtrAddr(external);
    if (data != NULL) {
        R_ClearExternalPtr(external);
        dtatools_numeric_free(data);
    }
    R_SetExternalPtrProtected(external, R_NilValue);
}

static numeric_data *numeric_storage(SEXP value) {
    numeric_data *data = (numeric_data *) R_ExternalPtrAddr(
        R_altrep_data1(value)
    );
    if (data == NULL) Rf_error("dtatools numeric data are no longer available");
    return data;
}

static R_xlen_t numeric_length(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return XLENGTH(materialized);
    size_t length = numeric_storage(value)->length;
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

static double numeric_missing_value(int offset) {
    if (offset == 0) return NA_REAL;
    uint64_t letter = (uint64_t) ('a' + offset - 1);
    uint64_t bits = UINT64_C(0x7ff00000000007a2) | (letter << 32);
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static int tagged_na_tag_value(double value) {
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

static int is_tagged_na_value(double value) {
    return tagged_na_tag_value(value) != 0;
}

static int stata_expression_string_is_missing(SEXP value) {
    return value == NA_STRING || LENGTH(value) == 0;
}

static int stata_missing_tag_value(double value) {
    int tag = tagged_na_tag_value(value);
    return tag >= 'a' && tag <= 'z' ? tag : 0;
}

static int normalized_stata_missing_tag(SEXP value, const char *argument) {
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

static void copy_shape_attributes(SEXP target, SEXP source) {
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

static numeric_data *unmaterialized_numeric_storage(SEXP value) {
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

static double numeric_observed_value(double value, int temporal) {
    if (temporal == 1) return value - 3653.0;
    if (temporal == 2) return value / 1000.0 - 315619200.0;
    return value;
}

#define DEFINE_NUMERIC_KERNELS(NAME, TYPE, MISSING_OFFSET)                    \
    static TYPE numeric_##NAME##_raw_at(                                     \
        const numeric_data *data, size_t index                               \
    ) {                                                                       \
        TYPE raw;                                                             \
        memcpy(&raw, (const char *) data->values + index * sizeof(raw),       \
               sizeof(raw));                                                  \
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
    static long double numeric_##NAME##_sum(                                  \
        const numeric_data *data, Rboolean na_rm                              \
    ) {                                                                       \
        long double sum = 0.0;                                                \
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
        return sum;                                                           \
    }                                                                         \
                                                                              \
    static int numeric_##NAME##_extreme(                                      \
        const numeric_data *data, Rboolean na_rm, int minimum, double *result \
    ) {                                                                       \
        double current = 0.0;                                                 \
        int updated = 0;                                                      \
        if (data->missing_count == 0) {                                       \
            if (data->length == 0) return 0;                                  \
            TYPE raw = numeric_##NAME##_raw_at(data, 0);                     \
            current = numeric_observed_value(                                \
                (double) raw, data->temporal                                  \
            );                                                                \
            updated = 1;                                                      \
            for (size_t index = 1; index < data->length; index++) {           \
                if ((index & 16383) == 0) R_CheckUserInterrupt();             \
                raw = numeric_##NAME##_raw_at(data, index);                   \
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

static int numeric_missing_offset_at(
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

static int numeric_value_is_missing_at(
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

typedef struct {
    SEXP value;
    numeric_data *storage;
    const double *real_values;
    const int *integer_values;
    int type;
} numeric_reader;

enum {
    WRITE_NUMERIC_CALLBACK = 0,
    WRITE_NUMERIC_INTEGER = 1,
    WRITE_NUMERIC_DOUBLE = 2,
    WRITE_NUMERIC_BYTE = 3,
    WRITE_NUMERIC_INT = 4,
    WRITE_NUMERIC_LONG = 5,
    WRITE_NUMERIC_FLOAT = 6
};

static numeric_reader numeric_reader_create(
    SEXP value, R_xlen_t expected_length
) {
    numeric_reader reader = {
        value, NULL, NULL, NULL, TYPEOF(value)
    };
    if (reader.type == REALSXP) {
        reader.storage = unmaterialized_numeric_storage(value);
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

static double numeric_reader_at(
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
/* Test control. It disarms itself before raising SIGINT after native writes. */
static int reference_write_interrupt_enabled = 0;

static void record_reference_row_read(void) {
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

static void maybe_inject_reference_write_interrupt(void) {
    if (!reference_write_interrupt_enabled) return;
    reference_write_interrupt_enabled = 0;
    raise(SIGINT);
    R_CheckUserInterrupt();
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

typedef struct {
    const char *name;
    int dta_type;
    const char *format;
    const char *label;
    void *numeric_values;
    SEXP string_values;
    void *label_values;
    SEXP label_texts;
    size_t label_count;
    SEXP stata_metadata;
    int has_value_labels;
    double numeric_shift;
    double numeric_scale;
    const void *direct_numeric_values;
    int direct_numeric_kind;
    int direct_numeric_format_version;
    int direct_numeric_temporal;
    int direct_numeric_no_na;
    void *direct_string_data;
} dtatools_write_column;

static int write_string_utf8_status(SEXP value) {
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
    R_xlen_t length = XLENGTH(value);
    int materialize_altstring = ALTREP(value);
    if (materialize_altstring) {
        normalized = PROTECT(Rf_allocVector(STRSXP, length));
    }
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        SEXP element = STRING_ELT(value, index);
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
                    SET_STRING_ELT(normalized, prior, STRING_ELT(value, prior));
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

static double numeric_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return REAL_ELT(materialized, index);
    numeric_data *data = numeric_storage(value);
    if (index < 0 || (size_t) index >= data->length) {
        Rf_error("invalid dtatools numeric-vector index");
    }
    return numeric_value_at(data, (size_t) index);
}

static R_xlen_t numeric_region(
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
    numeric_data *data = numeric_storage(value);
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
    numeric_data *data = numeric_storage(value);
    if (compact_payload_is_shared(R_altrep_data1(value))) {
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

static void *numeric_dataptr(SEXP value, Rboolean writeable) {
    SEXP materialized = numeric_materialize(value, writeable);
#if R_VERSION >= R_Version(4, 6, 0)
    return writeable ? DATAPTR_RW(materialized) : (void *) DATAPTR_RO(materialized);
#else
    (void) writeable;
    return DATAPTR(materialized);
#endif
}

static const void *numeric_dataptr_or_null(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? NULL : DATAPTR_OR_NULL(materialized);
}

static int numeric_no_na(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) {
        R_xlen_t length = XLENGTH(materialized);
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            if (ISNAN(REAL_ELT(materialized, index))) return 0;
        }
        return 1;
    }
    return numeric_storage(value)->missing_count == 0;
}

static SEXP numeric_sum(SEXP value, Rboolean na_rm) {
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    numeric_data *data = numeric_storage(value);
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
            numeric_storage(value), na_rm, minimum, &result
        )) {
        return NULL;
    }
    return Rf_ScalarReal(result);
}

static SEXP numeric_min(SEXP value, Rboolean na_rm) {
    return numeric_extreme(value, na_rm, 1);
}

static SEXP numeric_max(SEXP value, Rboolean na_rm) {
    return numeric_extreme(value, na_rm, 0);
}

static SEXP numeric_from_backing(
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

static SEXP numeric_compact_copy(const numeric_data *data) {
    size_t width = numeric_kind_width(data->kind);
    if (data->length > SIZE_MAX / width ||
        data->length * width > (size_t) R_XLEN_T_MAX) {
        Rf_error("compact Stata numeric vector is too long");
    }
    R_xlen_t byte_length = (R_xlen_t) (data->length * width);
    SEXP backing = PROTECT(Rf_allocVector(RAWSXP, byte_length));
    memcpy(RAW(backing), data->values, (size_t) byte_length);
    SEXP result = numeric_from_backing(
        backing, data->length, data->kind, data->temporal,
        data->format_version, data->missing_count
    );
    UNPROTECT(1);
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

static SEXP numeric_serialized_state(SEXP value) {
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    numeric_data *data = numeric_storage(value);
    SEXP backing = PROTECT(Rf_allocVector(
        RAWSXP, (R_xlen_t) (data->length * numeric_kind_width(data->kind))
    ));
    memcpy(RAW(backing), data->values, (size_t) XLENGTH(backing));
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

static SEXP numeric_unserialize(SEXP class, SEXP state) {
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

static SEXP numeric_duplicate(SEXP value, Rboolean deep) {
    (void) deep;
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    return numeric_compact_copy(numeric_storage(value));
}

static void write_numeric_system_missing_raw(
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

static SEXP numeric_extract_subset(SEXP value, SEXP index, SEXP call) {
    (void) call;
    if (R_altrep_data2(value) != R_NilValue ||
        (TYPEOF(index) != INTSXP && TYPEOF(index) != REALSXP)) {
        return NULL;
    }
    numeric_data *data = numeric_storage(value);
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
            memcpy(output + (size_t) i * width,
                   (unsigned char *) data->values + (size_t) source * width,
                   width);
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
    UNPROTECT(1);
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
    numeric_data *x_data = unmaterialized_numeric_storage(x);
    if (x_data == NULL) {
        Rf_error("internal numeric gather requires compact `x` storage");
    }
    numeric_data *y_data = NULL;
    if (y != R_NilValue) {
        y_data = unmaterialized_numeric_storage(y);
        if (y_data == NULL) {
            Rf_error("internal numeric gather requires compact `y` storage");
        }
        if (x_data->kind != y_data->kind ||
            x_data->temporal != y_data->temporal) {
            Rf_error("internal numeric gather requires matching storage");
        }
        if ((x_data->format_version <= 111) !=
            (y_data->format_version <= 111)) {
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
    UNPROTECT(gathered_names == R_NilValue ? 2 : 3);
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
    numeric_data *compact = unmaterialized_numeric_storage(value);
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
    if (column_count == 0) {
        UNPROTECT(1);
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
        numeric_gather_source x_source = numeric_gather_source_create(
            x_value, "x"
        );
        numeric_gather_source y_source;
        if (y != R_NilValue) {
            y_source = numeric_gather_source_create(y_value, "y");
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
    UNPROTECT(1);
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
    if (TYPEOF(backing) != RAWSXP) return 0;
    make_numeric_context context = {data, backing, 0, NULL};
    int ok = R_ToplevelExec(make_numeric_call, &context);
    *transferred = context.transferred;
    if (ok) *result = context.result;
    return ok;
}

static size_t numeric_kind_width(int kind) {
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

static void write_numeric_missing(
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

static void write_numeric_observed(
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
                "use `stata_%s()`", wider
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
                "use `stata_%s()`", wider
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
                "use `stata_double()`"
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
                "use `stata_double()`"
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
            "Stata %s storage cannot represent `x`; use `stata_%s(x)`",
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

static void dictstring_finalize(SEXP external) {
    void *data = R_ExternalPtrAddr(external);
    if (data != NULL) {
        R_ClearExternalPtr(external);
        dtatools_dictstring_free(data);
    }
    R_SetExternalPtrProtected(external, R_NilValue);
}

static dictstring_data *dictstring_storage(SEXP value) {
    SEXP external = R_altrep_data1(value);
    dictstring_data *data = (dictstring_data *) R_ExternalPtrAddr(external);
    if (data == NULL) Rf_error("dtatools string indices are no longer available");
    return data;
}

static SEXP dictstring_cache(SEXP value) {
    SEXP cache = R_ExternalPtrProtected(R_altrep_data1(value));
    if (TYPEOF(cache) != VECSXP) {
        Rf_error("dtatools string cache is no longer available");
    }
    return cache;
}

static SEXP unmaterialized_dictstring_source(SEXP value) {
    while (ALTREP(value) &&
           R_altrep_inherits(value, dtatools_metadata_string_class) &&
           R_altrep_data2(value) == R_NilValue) {
        value = metadata_proxy_source(value);
    }
    return ALTREP(value) &&
            R_altrep_inherits(value, dtatools_dictstring_class) &&
            R_altrep_data2(value) == R_NilValue
        ? value : R_NilValue;
}

static SEXP dictstring_cached_value(
    dictstring_data *data, SEXP cache, uint32_t id
) {
    if ((R_xlen_t) id >= XLENGTH(cache)) {
        Rf_error("invalid dtatools string-dictionary index");
    }
    SEXP cached = VECTOR_ELT(cache, (R_xlen_t) id);
    if (cached != R_NilValue) return cached;

    const char *bytes = NULL;
    int length = 0;
    if (!dtatools_dictstring_bytes(data, id, &bytes, &length) ||
        bytes == NULL || length < 0) {
        Rf_error("invalid dtatools string-dictionary value");
    }
    cached = Rf_mkCharLenCE(bytes, length, CE_UTF8);
    SET_VECTOR_ELT(cache, (R_xlen_t) id, cached);
    return cached;
}

typedef struct {
    SEXP values;
    SEXP source;
    SEXP cache;
    SEXP private_cache;
    SEXP scalar;
    dictstring_data *data;
} reference_string_reader;

static SEXP reference_string_reader_private_cache(
    SEXP values, R_xlen_t read_count
) {
    SEXP source = unmaterialized_dictstring_source(values);
    if (source == R_NilValue) return R_NilValue;
    R_xlen_t cardinality = XLENGTH(dictstring_cache(source));
    return cardinality > 0 && cardinality <= read_count / 4
        ? Rf_allocVector(VECSXP, cardinality) : R_NilValue;
}

static reference_string_reader reference_string_reader_create(
    SEXP values, SEXP private_cache
) {
    reference_string_reader reader = {
        .values = values,
        .source = unmaterialized_dictstring_source(values),
        .cache = R_NilValue,
        .private_cache = private_cache,
        .scalar = R_NilValue,
        .data = NULL
    };
    if (reader.source != R_NilValue) {
        reader.cache = dictstring_cache(reader.source);
        reader.data = dictstring_storage(reader.source);
    }
    return reader;
}

static SEXP reference_string_reader_at(
    const reference_string_reader *reader, R_xlen_t index
) {
    if (reader->scalar != R_NilValue) return reader->scalar;
    if (reader->source == R_NilValue) {
        return STRING_ELT(reader->values, index);
    }
    if (index < 0 || (size_t) index >= reader->data->length) {
        Rf_error("invalid reference string plan");
    }
    uint32_t id = reader->data->value_ids[index];
    if ((R_xlen_t) id >= XLENGTH(reader->cache)) {
        Rf_error("invalid dtatools string-dictionary index");
    }
    SEXP cached = VECTOR_ELT(reader->cache, (R_xlen_t) id);
    if (cached != R_NilValue) return cached;
    if (reader->private_cache != R_NilValue) {
        cached = VECTOR_ELT(reader->private_cache, (R_xlen_t) id);
        if (cached != R_NilValue) return cached;
    }

    const char *bytes = NULL;
    int length = 0;
    if (!dtatools_dictstring_bytes(reader->data, id, &bytes, &length) ||
        bytes == NULL || length < 0) {
        Rf_error("invalid dtatools string-dictionary value");
    }
    cached = Rf_mkCharLenCE(bytes, length, CE_UTF8);
    if (reader->private_cache != R_NilValue) {
        SET_VECTOR_ELT(reader->private_cache, (R_xlen_t) id, cached);
    }
    return cached;
}

static int reference_string_reader_is_missing_at(
    const reference_string_reader *reader, R_xlen_t index
) {
    if (reader->scalar != R_NilValue) {
        return stata_expression_string_is_missing(reader->scalar);
    }
    if (reader->source == R_NilValue) {
        return stata_expression_string_is_missing(
            STRING_ELT(reader->values, index)
        );
    }
    if (index < 0 || (size_t) index >= reader->data->length) {
        Rf_error("invalid reference string plan");
    }
    uint32_t id = reader->data->value_ids[index];
    if ((R_xlen_t) id >= XLENGTH(reader->cache)) {
        Rf_error("invalid dtatools string-dictionary index");
    }

    const char *bytes = NULL;
    int length = 0;
    if (!dtatools_dictstring_bytes(reader->data, id, &bytes, &length) ||
        bytes == NULL || length < 0) {
        Rf_error("invalid dtatools string-dictionary value");
    }
    return length == 0;
}

static R_xlen_t dictstring_length(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return XLENGTH(materialized);
    size_t length = dictstring_storage(value)->length;
    if (length > (size_t) R_XLEN_T_MAX) {
        Rf_error("dtatools string vector is too long");
    }
    return (R_xlen_t) length;
}

static SEXP dictstring_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return STRING_ELT(materialized, index);
    dictstring_data *data = dictstring_storage(value);
    if (index < 0 || (size_t) index >= data->length) {
        Rf_error("invalid dtatools string-vector index");
    }
    SEXP cache = dictstring_cache(value);
    uint32_t id = data->value_ids[index];
    return dictstring_cached_value(data, cache, id);
}

static SEXP dictstring_materialized_values(SEXP value, SEXP cache) {
    dictstring_data *data = dictstring_storage(value);
    R_xlen_t dictionary_length = XLENGTH(cache);
    for (R_xlen_t id = 0; id < dictionary_length; id++) {
        if ((id & 16383) == 0) R_CheckUserInterrupt();
        (void) dictstring_cached_value(data, cache, (uint32_t) id);
    }
    SEXP materialized = PROTECT(Rf_allocVector(
        STRSXP, (R_xlen_t) data->length
    ));
    for (size_t index = 0; index < data->length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        uint32_t id = data->value_ids[index];
        if ((R_xlen_t) id >= dictionary_length) {
            Rf_error("invalid dtatools string-dictionary index");
        }
        SET_STRING_ELT(
            materialized, (R_xlen_t) index,
            VECTOR_ELT(cache, (R_xlen_t) id)
        );
    }
    UNPROTECT(1);
    return materialized;
}

static SEXP dictstring_patch_values(SEXP value, SEXP private_cache) {
    reference_string_reader reader = reference_string_reader_create(
        value, private_cache
    );
    R_xlen_t length = dictstring_length(value);
    SEXP materialized = PROTECT(Rf_allocVector(STRSXP, length));
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        SET_STRING_ELT(
            materialized, index,
            reference_string_reader_at(&reader, index)
        );
    }
    UNPROTECT(1);
    return materialized;
}

static SEXP dictstring_materialize(SEXP value, Rboolean writeable) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) {
        return writeable
            ? detach_shared_materialized_payload(value) : materialized;
    }

    if (compact_payload_is_shared(R_altrep_data1(value))) {
        SEXP detached = PROTECT(dictstring_compact_copy(value));
        R_set_altrep_data1(value, R_altrep_data1(detached));
        UNPROTECT(1);
    }
    SEXP cache = dictstring_cache(value);
    materialized = PROTECT(dictstring_materialized_values(value, cache));
    R_set_altrep_data2(value, materialized);
    dictstring_finalize(R_altrep_data1(value));
    UNPROTECT(1);
    return materialized;
}

static SEXP dictstring_materialize_for_patch(SEXP value, SEXP private_cache) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) {
        return detach_shared_materialized_payload(value);
    }
    materialized = PROTECT(dictstring_patch_values(value, private_cache));
    R_set_altrep_data2(value, materialized);
    UNPROTECT(1);
    return materialized;
}

static void *dictstring_dataptr(SEXP value, Rboolean writeable) {
    SEXP materialized = dictstring_materialize(value, writeable);
#if R_VERSION >= R_Version(4, 6, 0)
    return DATAPTR_RW(materialized);
#else
    return DATAPTR(materialized);
#endif
}

static const void *dictstring_dataptr_or_null(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? NULL : DATAPTR_OR_NULL(materialized);
}

static void dictstring_set_elt(SEXP value, R_xlen_t index, SEXP replacement) {
    SET_STRING_ELT(
        dictstring_materialize(value, TRUE), index, replacement
    );
}

static int dictstring_no_na(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized == R_NilValue) return 1;
    R_xlen_t length = XLENGTH(materialized);
    for (R_xlen_t index = 0; index < length; index++) {
        if (STRING_ELT(materialized, index) == NA_STRING) return 0;
    }
    return 1;
}

typedef struct {
    void *data;
    size_t value_count;
    int transferred;
    SEXP result;
} make_dictstring_context;

static void make_dictstring_call(void *payload) {
    make_dictstring_context *context = (make_dictstring_context *) payload;
    SEXP cache = PROTECT(Rf_allocVector(
        VECSXP, (R_xlen_t) context->value_count
    ));
    SEXP external = PROTECT(R_MakeExternalPtr(
        context->data, R_NilValue, cache
    ));
    R_RegisterCFinalizerEx(external, dictstring_finalize, TRUE);
    context->transferred = 1;
    SEXP result = PROTECT(R_new_altrep(
        dtatools_dictstring_class, external, R_NilValue
    ));
    R_PreserveObject(result);
    context->result = result;
    UNPROTECT(3);
}

int dtatools_make_dictstring(
    void *data, size_t value_count, int *transferred, SEXP *result
) {
    if (data == NULL || transferred == NULL || result == NULL ||
        value_count > (size_t) R_XLEN_T_MAX) {
        return 0;
    }
    make_dictstring_context context = {
        data, value_count, 0, NULL
    };
    int ok = R_ToplevelExec(make_dictstring_call, &context);
    *transferred = context.transferred;
    if (ok) *result = context.result;
    return ok;
}

typedef struct {
    int type;
    R_xlen_t length;
    SEXP result;
} alloc_vector_context;

static void alloc_vector_call(void *data) {
    alloc_vector_context *context = (alloc_vector_context *) data;
    SEXP result = PROTECT(Rf_allocVector(context->type, context->length));
    R_PreserveObject(result);
    context->result = result;
    UNPROTECT(1);
}

int dtatools_alloc_vector(int type, R_xlen_t length, SEXP *result) {
    alloc_vector_context context = {type, length, NULL};
    int ok = R_ToplevelExec(alloc_vector_call, &context);
    if (ok && result != NULL) *result = context.result;
    return ok;
}

size_t dtatools_xlength(SEXP value) {
    return (size_t) XLENGTH(value);
}

void dtatools_release_object(SEXP object) {
    if (object != NULL) R_ReleaseObject(object);
}

typedef struct {
    const char *value;
    int length;
    cetype_t encoding;
    SEXP result;
} make_char_context;

static void make_char_call(void *data) {
    make_char_context *context = (make_char_context *) data;
    context->result = Rf_mkCharLenCE(
        context->value, context->length, context->encoding
    );
}

int dtatools_make_char(
    const char *value, int length, int encoding, SEXP *result
) {
    make_char_context context = {
        value, length, (cetype_t) encoding, NULL
    };
    int ok = R_ToplevelExec(make_char_call, &context);
    if (ok && result != NULL) *result = context.result;
    return ok;
}

typedef struct {
    const char *name;
    SEXP result;
} install_context;

static void install_call(void *data) {
    install_context *context = (install_context *) data;
    context->result = Rf_install(context->name);
}

int dtatools_install(const char *name, SEXP *result) {
    install_context context = {name, NULL};
    int ok = R_ToplevelExec(install_call, &context);
    if (ok && result != NULL) *result = context.result;
    return ok;
}

typedef struct {
    SEXP object;
    SEXP name;
    SEXP value;
} set_attrib_context;

static void set_attrib_call(void *data) {
    set_attrib_context *context = (set_attrib_context *) data;
    Rf_setAttrib(context->object, context->name, context->value);
}

int dtatools_set_attrib(SEXP object, SEXP name, SEXP value) {
    set_attrib_context context = {object, name, value};
    return R_ToplevelExec(set_attrib_call, &context);
}

static void check_interrupt(void *unused) {
    (void) unused;
    R_CheckUserInterrupt();
}

int dtatools_check_interrupt(void) {
    return R_ToplevelExec(check_interrupt, NULL) ? 0 : 1;
}

static void fail_from_rust(char *message) {
    char local[4096];
    if (message == NULL) {
        Rf_error("native dtatools call failed");
    }
    size_t copy_length = strlen(message);
    if (copy_length >= sizeof(local)) {
        copy_length = sizeof(local) - 1;
        while (copy_length > 0 &&
               (((unsigned char) message[copy_length]) & 0xc0) == 0x80) {
            copy_length--;
        }
    }
    memcpy(local, message, copy_length);
    local[copy_length] = '\0';
    dtatools_free_error(message);
    Rf_error("%s", local);
}

static const char *optional_encoding(SEXP encoding) {
    if (Rf_isNull(encoding)) return NULL;
    if (TYPEOF(encoding) != STRSXP || XLENGTH(encoding) != 1 ||
        STRING_ELT(encoding, 0) == NA_STRING) {
        Rf_error("`encoding` must be NULL or one non-missing character string");
    }
    return Rf_translateCharUTF8(STRING_ELT(encoding, 0));
}

SEXP C_dtatools_metadata(
    SEXP path, SEXP encoding, SEXP column_start, SEXP column_count
) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING) {
        Rf_error("`file` must be one non-missing path");
    }
    if (TYPEOF(column_start) != INTSXP || XLENGTH(column_start) != 1 ||
        INTEGER(column_start)[0] < 0 || TYPEOF(column_count) != INTSXP ||
        XLENGTH(column_count) != 1 || INTEGER(column_count)[0] < 0) {
        Rf_error("internal metadata column bounds must be non-negative integers");
    }
    char *error = NULL;
    SEXP result = dtatools_metadata_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)),
        (uint32_t) INTEGER(column_start)[0],
        (uint32_t) INTEGER(column_count)[0],
        optional_encoding(encoding), &error
    );
    if (result == NULL) fail_from_rust(error);
    return result;
}

SEXP C_dtatools_read(
    SEXP path, SEXP columns, SEXP skip, SEXP n_max, SEXP direct_to_r,
    SEXP threads, SEXP numeric_altrep, SEXP encoding
) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING) {
        Rf_error("`file` must be one non-missing path");
    }
    int all_columns = Rf_isNull(columns);
    if (!all_columns && TYPEOF(columns) != INTSXP) {
        Rf_error("internal column selection must be integer");
    }
    if (TYPEOF(skip) != REALSXP || XLENGTH(skip) != 1 ||
        TYPEOF(n_max) != REALSXP || XLENGTH(n_max) != 1) {
        Rf_error("internal row bounds must be numeric scalars");
    }
    if (TYPEOF(direct_to_r) != LGLSXP || XLENGTH(direct_to_r) != 1 ||
        LOGICAL(direct_to_r)[0] == NA_LOGICAL) {
        Rf_error("internal materialization selector must be logical");
    }
    if (TYPEOF(threads) != INTSXP || XLENGTH(threads) != 1 ||
        INTEGER(threads)[0] < 0) {
        Rf_error("internal thread count must be one non-negative integer");
    }
    if (TYPEOF(numeric_altrep) != LGLSXP || XLENGTH(numeric_altrep) != 1 ||
        LOGICAL(numeric_altrep)[0] == NA_LOGICAL) {
        Rf_error("internal numeric ALTREP selector must be logical");
    }
    char *error = NULL;
    SEXP result = dtatools_read_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)),
        all_columns ? NULL : INTEGER(columns),
        all_columns ? 0 : (size_t) XLENGTH(columns),
        all_columns,
        REAL(skip)[0],
        REAL(n_max)[0],
        LOGICAL(direct_to_r)[0],
        INTEGER(threads)[0],
        LOGICAL(numeric_altrep)[0],
        optional_encoding(encoding),
        &error
    );
    if (result == NULL) fail_from_rust(error);
    return result;
}

static const char *write_scalar_string(SEXP value, const char *name) {
    if (TYPEOF(value) != STRSXP || XLENGTH(value) != 1 ||
        STRING_ELT(value, 0) == NA_STRING) {
        Rf_error("internal `%s` must be one non-missing string", name);
    }
    return Rf_translateCharUTF8(STRING_ELT(value, 0));
}

static SEXP write_utf8_strings(
    SEXP values, const char *name, int allow_missing
) {
    if (TYPEOF(values) != STRSXP) {
        Rf_error("internal `%s` must be character", name);
    }
    R_xlen_t length = XLENGTH(values);
    SEXP normalized = PROTECT(Rf_allocVector(STRSXP, length));
    for (R_xlen_t index = 0; index < length; index++) {
        SEXP element = PROTECT(STRING_ELT(values, index));
        if (element == NA_STRING) {
            if (allow_missing) {
                SET_STRING_ELT(normalized, index, NA_STRING);
                UNPROTECT(1);
                continue;
            }
            UNPROTECT(2);
            Rf_error("internal `%s` contains a missing string", name);
        }
        SEXP utf8 = PROTECT(Rf_mkCharCE(
            Rf_translateCharUTF8(element), CE_UTF8
        ));
        SET_STRING_ELT(normalized, index, utf8);
        UNPROTECT(2);
    }
    UNPROTECT(1);
    return normalized;
}

static SEXP write_rooted_strings(
    SEXP roots, R_xlen_t index, SEXP values, const char *name
) {
    SEXP normalized = PROTECT(write_utf8_strings(values, name, 0));
    SET_VECTOR_ELT(roots, index, normalized);
    UNPROTECT(1);
    return normalized;
}

const char *dtatools_string_elt_utf8(SEXP values, size_t index) {
    if (TYPEOF(values) != STRSXP || index >= (size_t) XLENGTH(values) ||
        STRING_ELT(values, (R_xlen_t) index) == NA_STRING) {
        return NULL;
    }
    return CHAR(STRING_ELT(values, (R_xlen_t) index));
}

static SEXP write_rooted_optional_strings(
    SEXP roots, R_xlen_t index, SEXP values, const char *name
) {
    SEXP normalized = PROTECT(write_utf8_strings(values, name, 1));
    SET_VECTOR_ELT(roots, index, normalized);
    UNPROTECT(1);
    return normalized;
}

static const char *write_rooted_scalar_string(
    SEXP roots, R_xlen_t index, SEXP value, const char *name
) {
    if (TYPEOF(value) != STRSXP || XLENGTH(value) != 1) {
        Rf_error("internal `%s` must be one non-missing string", name);
    }
    SEXP normalized = write_rooted_strings(roots, index, value, name);
    return CHAR(STRING_ELT(normalized, 0));
}

static const char *write_rooted_nullable_scalar_string(
    SEXP roots, R_xlen_t index, SEXP value, const char *name
) {
    if (Rf_isNull(value)) {
        SET_VECTOR_ELT(roots, index, R_NilValue);
        return NULL;
    }
    return write_rooted_scalar_string(roots, index, value, name);
}

SEXP C_dtatools_write_path_kind(SEXP path) {
    const char *output_path = write_scalar_string(path, "path");
    char *rust_error = NULL;
    int kind = dtatools_write_path_kind(output_path, &rust_error);
    if (kind < 0) fail_from_rust(rust_error);
    return Rf_ScalarInteger(kind);
}

static int write_column_type(SEXP column) {
    if (TYPEOF(column) != VECSXP || XLENGTH(column) != 11) {
        Rf_error("internal write column must be an eleven-element list");
    }
    SEXP dta_type = VECTOR_ELT(column, 1);
    if (TYPEOF(dta_type) != INTSXP || XLENGTH(dta_type) != 1 ||
        INTEGER(dta_type)[0] < 0 || INTEGER(dta_type)[0] > 2050) {
        Rf_error("invalid internal write column metadata");
    }
    return INTEGER(dta_type)[0];
}

SEXP C_dtatools_write(SEXP specification, SEXP path) {
    if (TYPEOF(specification) != VECSXP || XLENGTH(specification) != 4) {
        Rf_error("internal write specification must be a four-element list");
    }
    SEXP dataset_metadata = VECTOR_ELT(specification, 1);
    SEXP columns = VECTOR_ELT(specification, 2);
    if (TYPEOF(dataset_metadata) != STRSXP || TYPEOF(columns) != VECSXP) {
        Rf_error("invalid internal write specification");
    }

    size_t column_count = (size_t) XLENGTH(columns);
    if (column_count > ((size_t) R_XLEN_T_MAX - 4) / 5) {
        Rf_error("too many internal write columns");
    }
    SEXP string_roots = PROTECT(Rf_allocVector(
        VECSXP, (R_xlen_t) (4 + 5 * column_count)
    ));
    R_xlen_t root_index = 0;
    const char *output_path = write_rooted_scalar_string(
        string_roots, root_index++, path, "path"
    );
    const char *dataset_label = write_rooted_scalar_string(
        string_roots, root_index++, VECTOR_ELT(specification, 0),
        "dataset label"
    );
    SEXP rooted_dataset_metadata = write_rooted_strings(
        string_roots, root_index++, dataset_metadata, "dataset Stata metadata"
    );
    const char *timestamp = write_rooted_scalar_string(
        string_roots, root_index++, VECTOR_ELT(specification, 3), "timestamp"
    );

    size_t numeric_column_count = 0;
    size_t labelled_column_count = 0;
    for (size_t index = 0; index < column_count; index++) {
        SEXP column = VECTOR_ELT(columns, (R_xlen_t) index);
        if (write_column_type(column) <= 4) numeric_column_count++;
        if (XLENGTH(VECTOR_ELT(column, 4)) > 0) labelled_column_count++;
    }

    SEXP numeric_replacements = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) column_count));
    dtatools_write_column *descriptors = (dtatools_write_column *) R_alloc(
        (R_SIZE_T) column_count, (int) sizeof(dtatools_write_column)
    );
    numeric_reader *value_readers = numeric_column_count == 0 ? NULL :
        (numeric_reader *) R_alloc(
            (R_SIZE_T) numeric_column_count, (int) sizeof(numeric_reader)
        );
    numeric_reader *label_readers = labelled_column_count == 0 ? NULL :
        (numeric_reader *) R_alloc(
            (R_SIZE_T) labelled_column_count, (int) sizeof(numeric_reader)
        );
    size_t value_reader_index = 0;
    size_t label_reader_index = 0;
    size_t row_count = 0;
    for (size_t index = 0; index < column_count; index++) {
        SEXP column = VECTOR_ELT(columns, (R_xlen_t) index);
        int dta_type = write_column_type(column);
        SEXP label_values = VECTOR_ELT(column, 4);
        SEXP label_texts = VECTOR_ELT(column, 5);
        SEXP stata_metadata = VECTOR_ELT(column, 10);
        SEXP values = VECTOR_ELT(column, 6);
        SEXP has_value_labels = VECTOR_ELT(column, 7);
        SEXP numeric_shift = VECTOR_ELT(column, 8);
        SEXP numeric_scale = VECTOR_ELT(column, 9);
        if (TYPEOF(label_texts) != STRSXP ||
            XLENGTH(label_values) != XLENGTH(label_texts) ||
            TYPEOF(stata_metadata) != STRSXP ||
            TYPEOF(has_value_labels) != LGLSXP ||
            XLENGTH(has_value_labels) != 1 ||
            LOGICAL(has_value_labels)[0] == NA_LOGICAL ||
            TYPEOF(numeric_shift) != REALSXP || XLENGTH(numeric_shift) != 1 ||
            TYPEOF(numeric_scale) != REALSXP || XLENGTH(numeric_scale) != 1 ||
            !R_FINITE(REAL(numeric_shift)[0]) ||
            !R_FINITE(REAL(numeric_scale)[0])) {
            Rf_error("invalid internal write column metadata");
        }
        size_t length = (size_t) XLENGTH(values);
        if (index == 0) row_count = length;
        if (length != row_count) {
            Rf_error("internal write columns have different lengths");
        }

        const char *name = write_rooted_scalar_string(
            string_roots, root_index++, VECTOR_ELT(column, 0), "name"
        );
        const char *format = write_rooted_scalar_string(
            string_roots, root_index++, VECTOR_ELT(column, 2), "format"
        );
        const char *label = write_rooted_scalar_string(
            string_roots, root_index++, VECTOR_ELT(column, 3), "variable label"
        );
        label_texts = write_rooted_strings(
            string_roots, root_index++, label_texts, "value-label text"
        );
        stata_metadata = write_rooted_strings(
            string_roots, root_index++, stata_metadata, "variable Stata metadata"
        );
        dtatools_write_column *descriptor = &descriptors[index];
        *descriptor = (dtatools_write_column) {
            .name = name,
            .dta_type = dta_type,
            .format = format,
            .label = label,
            .string_values = R_NilValue,
            .label_texts = label_texts,
            .label_count = (size_t) XLENGTH(label_values),
            .stata_metadata = stata_metadata,
            .has_value_labels = LOGICAL(has_value_labels)[0],
            .numeric_shift = REAL(numeric_shift)[0],
            .numeric_scale = REAL(numeric_scale)[0],
            .direct_numeric_kind = WRITE_NUMERIC_CALLBACK
        };
        if (descriptor->dta_type <= 4) {
            numeric_reader *reader = &value_readers[value_reader_index++];
            *reader = numeric_reader_create(values, (R_xlen_t) row_count);
            descriptor->numeric_values = reader;
            if (reader->storage != NULL) {
                descriptor->direct_numeric_values = reader->storage->values;
                descriptor->direct_numeric_kind =
                    WRITE_NUMERIC_BYTE + reader->storage->kind;
                descriptor->direct_numeric_format_version =
                    reader->storage->format_version;
                descriptor->direct_numeric_temporal = reader->storage->temporal;
                descriptor->direct_numeric_no_na =
                    reader->storage->missing_count == 0;
            } else if (reader->integer_values != NULL) {
                descriptor->direct_numeric_values = reader->integer_values;
                descriptor->direct_numeric_kind = WRITE_NUMERIC_INTEGER;
            } else if (reader->real_values != NULL) {
                descriptor->direct_numeric_values = reader->real_values;
                descriptor->direct_numeric_kind = WRITE_NUMERIC_DOUBLE;
            }
        } else {
            if (TYPEOF(values) != STRSXP) {
                Rf_error("internal string write column must be character");
            }
            descriptor->string_values = values;
            SEXP dictionary_source = unmaterialized_dictstring_source(values);
            if (dictionary_source != R_NilValue) {
                descriptor->direct_string_data = dictstring_storage(dictionary_source);
            }
        }
        if (descriptor->label_count > 0) {
            numeric_reader *reader = &label_readers[label_reader_index++];
            *reader = numeric_reader_create(
                label_values, (R_xlen_t) descriptor->label_count
            );
            descriptor->label_values = reader;
        }
    }

    char *rust_error = NULL;
    int ok = dtatools_write_rust(
        output_path, dataset_label, rooted_dataset_metadata, descriptors,
        column_count, REAL(numeric_replacements), row_count, timestamp,
        &rust_error
    );
    if (ok < 0) {
        UNPROTECT(2);
        Rf_onintr();
        Rf_error("write interrupted");
    }
    if (!ok) fail_from_rust(rust_error);
    UNPROTECT(2);
    return numeric_replacements;
}

/* One Arrow write column: a sixteen-element list built by
 * .prepare_arrow_write(): name, kind, values, levels, ordered, label, format,
 * storage, tz, units, label_values, label_texts, has_value_labels,
 * haven_labelled, string_storage, stata_metadata. Character data must already
 * be UTF-8; the R layer normalizes with enc2utf8(). */
static void arrow_write_column_descriptor(
    SEXP column, size_t index, size_t row_count, SEXP string_roots,
    R_xlen_t *root_index, dtatools_arrow_column *descriptor
) {
    if (TYPEOF(column) != VECSXP || XLENGTH(column) != 16) {
        Rf_error("internal Arrow column must be a sixteen-element list");
    }
    SEXP kind_value = VECTOR_ELT(column, 1);
    SEXP values = VECTOR_ELT(column, 2);
    SEXP levels = VECTOR_ELT(column, 3);
    SEXP ordered = VECTOR_ELT(column, 4);
    SEXP storage = VECTOR_ELT(column, 7);
    SEXP label_values = VECTOR_ELT(column, 10);
    SEXP label_texts = VECTOR_ELT(column, 11);
    SEXP has_value_labels = VECTOR_ELT(column, 12);
    SEXP haven_labelled = VECTOR_ELT(column, 13);
    SEXP string_storage = VECTOR_ELT(column, 14);
    SEXP stata_metadata = VECTOR_ELT(column, 15);
    if (TYPEOF(kind_value) != INTSXP || XLENGTH(kind_value) != 1 ||
        TYPEOF(ordered) != LGLSXP || XLENGTH(ordered) != 1 ||
        TYPEOF(storage) != INTSXP || XLENGTH(storage) != 1 ||
        TYPEOF(label_values) != REALSXP || TYPEOF(label_texts) != STRSXP ||
        XLENGTH(label_values) != XLENGTH(label_texts) ||
        TYPEOF(stata_metadata) != STRSXP ||
        TYPEOF(has_value_labels) != LGLSXP ||
        XLENGTH(has_value_labels) != 1 ||
        LOGICAL(has_value_labels)[0] == NA_LOGICAL ||
        TYPEOF(haven_labelled) != LGLSXP || XLENGTH(haven_labelled) != 1 ||
        LOGICAL(haven_labelled)[0] == NA_LOGICAL ||
        TYPEOF(string_storage) != INTSXP || XLENGTH(string_storage) != 1) {
        Rf_error("invalid internal Arrow column metadata");
    }
    if ((size_t) XLENGTH(values) != row_count) {
        Rf_error("internal Arrow columns have different lengths");
    }

    memset(descriptor, 0, sizeof(*descriptor));
    descriptor->kind = INTEGER(kind_value)[0];
    descriptor->storage = INTEGER(storage)[0];
    descriptor->string_storage = INTEGER(string_storage)[0];
    descriptor->ordered = LOGICAL(ordered)[0] == 1;
    descriptor->strings = R_NilValue;
    descriptor->name = write_rooted_scalar_string(
        string_roots, (*root_index)++, VECTOR_ELT(column, 0), "name"
    );
    descriptor->label = write_rooted_scalar_string(
        string_roots, (*root_index)++, VECTOR_ELT(column, 5), "variable label"
    );
    descriptor->format = write_rooted_scalar_string(
        string_roots, (*root_index)++, VECTOR_ELT(column, 6), "format"
    );
    descriptor->tz = write_rooted_nullable_scalar_string(
        string_roots, (*root_index)++, VECTOR_ELT(column, 8), "time zone"
    );
    descriptor->units = write_rooted_scalar_string(
        string_roots, (*root_index)++, VECTOR_ELT(column, 9), "units"
    );
    descriptor->label_texts = write_rooted_strings(
        string_roots, (*root_index)++, label_texts, "value-label text"
    );
    descriptor->label_count = (size_t) XLENGTH(label_values);
    descriptor->stata_metadata = write_rooted_strings(
        string_roots, (*root_index)++, stata_metadata, "variable Stata metadata"
    );
    descriptor->has_value_labels = LOGICAL(has_value_labels)[0];
    descriptor->haven_labelled = LOGICAL(haven_labelled)[0];
    descriptor->label_values =
        descriptor->label_count > 0 ? REAL(label_values) : NULL;

    switch (descriptor->kind) {
    case 0: /* logical */
        if (TYPEOF(values) != LGLSXP) {
            Rf_error("internal Arrow logical column has the wrong type");
        }
        descriptor->values = LOGICAL(values);
        break;
    case 1: /* integer */
        if (TYPEOF(values) != INTSXP) {
            Rf_error("internal Arrow integer column has the wrong type");
        }
        descriptor->values = INTEGER(values);
        break;
    case 2: /* double */
    case 6: /* date */
    case 7: /* datetime */
    case 8: /* difftime */
        if (TYPEOF(values) != REALSXP) {
            Rf_error("internal Arrow double column has the wrong type");
        }
        descriptor->values = REAL(values);
        break;
    case 3: { /* character */
        if (TYPEOF(values) != STRSXP) {
            Rf_error("internal Arrow character column has the wrong type");
        }
        descriptor->strings = values;
        descriptor->string_count = row_count;
        SEXP dictionary_source = unmaterialized_dictstring_source(values);
        if (dictionary_source != R_NilValue) {
            descriptor->dictstring = dictstring_storage(dictionary_source);
        }
        break;
    }
    case 4: /* raw */
        if (TYPEOF(values) != RAWSXP) {
            Rf_error("internal Arrow raw column has the wrong type");
        }
        descriptor->values = RAW(values);
        break;
    case 5: /* factor */
        if (TYPEOF(values) != INTSXP || TYPEOF(levels) != STRSXP) {
            Rf_error("internal Arrow factor column has the wrong type");
        }
        descriptor->values = INTEGER(values);
        descriptor->strings = write_rooted_optional_strings(
            string_roots, (*root_index)++, levels, "factor levels"
        );
        descriptor->string_count = (size_t) XLENGTH(levels);
        break;
    case 9: { /* profiled Stata numeric */
        numeric_data *compact = unmaterialized_numeric_storage(values);
        if (compact != NULL) {
            descriptor->compact_values = compact->values;
            descriptor->compact_kind = compact->kind;
            descriptor->compact_format_version = compact->format_version;
            descriptor->compact_temporal = compact->temporal;
        } else {
            if (TYPEOF(values) != REALSXP) {
                Rf_error("internal Arrow Stata column has the wrong type");
            }
            descriptor->values = REAL(values);
        }
        break;
    }
    default:
        Rf_error("invalid internal Arrow column kind");
    }
    (void) index;
}

SEXP C_dtatools_save_arrow(
    SEXP specification, SEXP path, SEXP compression, SEXP threads,
    SEXP checksums
) {
    if (TYPEOF(specification) != VECSXP || XLENGTH(specification) != 3) {
        Rf_error("internal Arrow specification must be a three-element list");
    }
    if (TYPEOF(threads) != INTSXP || XLENGTH(threads) != 1 ||
        INTEGER(threads)[0] < 0) {
        Rf_error("internal thread count must be one non-negative integer");
    }
    if (TYPEOF(checksums) != LGLSXP || XLENGTH(checksums) != 1 ||
        LOGICAL(checksums)[0] == NA_LOGICAL) {
        Rf_error("internal checksums flag must be TRUE or FALSE");
    }
    SEXP dataset_metadata = VECTOR_ELT(specification, 1);
    SEXP columns = VECTOR_ELT(specification, 2);
    if (TYPEOF(dataset_metadata) != STRSXP || TYPEOF(columns) != VECSXP) {
        Rf_error("invalid internal Arrow specification");
    }

    size_t column_count = (size_t) XLENGTH(columns);
    if (column_count > ((size_t) R_XLEN_T_MAX - 4) / 9) {
        Rf_error("too many internal Arrow columns");
    }
    SEXP string_roots = PROTECT(Rf_allocVector(
        VECSXP, (R_xlen_t) (4 + 9 * column_count)
    ));
    R_xlen_t root_index = 0;
    const char *output_path = write_rooted_scalar_string(
        string_roots, root_index++, path, "path"
    );
    const char *compression_label = write_rooted_scalar_string(
        string_roots, root_index++, compression, "compression"
    );
    const char *dataset_label = write_rooted_scalar_string(
        string_roots, root_index++, VECTOR_ELT(specification, 0),
        "dataset label"
    );
    SEXP rooted_dataset_metadata = write_rooted_strings(
        string_roots, root_index++, dataset_metadata, "dataset Stata metadata"
    );

    size_t row_count = 0;
    if (column_count > 0) {
        SEXP first = VECTOR_ELT(columns, 0);
        if (TYPEOF(first) != VECSXP || XLENGTH(first) != 16) {
            Rf_error("internal Arrow column must be a sixteen-element list");
        }
        row_count = (size_t) XLENGTH(VECTOR_ELT(first, 2));
    }
    dtatools_arrow_column *descriptors = (dtatools_arrow_column *) R_alloc(
        (R_SIZE_T) column_count, (int) sizeof(dtatools_arrow_column)
    );
    for (size_t index = 0; index < column_count; index++) {
        arrow_write_column_descriptor(
            VECTOR_ELT(columns, (R_xlen_t) index), index, row_count,
            string_roots, &root_index, &descriptors[index]
        );
    }

    int interrupted = 0;
    char *rust_error = NULL;
    SEXP result = dtatools_save_arrow_rust(
        output_path, dataset_label, rooted_dataset_metadata,
        descriptors, column_count, row_count,
        compression_label, INTEGER(threads)[0], LOGICAL(checksums)[0],
        &interrupted,
        &rust_error
    );
    if (result == NULL) {
        UNPROTECT(1);
        if (interrupted) {
            Rf_onintr();
            Rf_error("Arrow write interrupted");
        }
        fail_from_rust(rust_error);
    }
    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_datasig(SEXP specification, SEXP threads) {
    if (TYPEOF(specification) != VECSXP || XLENGTH(specification) != 3) {
        Rf_error("internal Arrow specification must be a three-element list");
    }
    if (TYPEOF(threads) != INTSXP || XLENGTH(threads) != 1 ||
        INTEGER(threads)[0] < 0) {
        Rf_error("internal thread count must be one non-negative integer");
    }
    SEXP dataset_metadata = VECTOR_ELT(specification, 1);
    SEXP columns = VECTOR_ELT(specification, 2);
    if (TYPEOF(dataset_metadata) != STRSXP || TYPEOF(columns) != VECSXP) {
        Rf_error("invalid internal Arrow specification");
    }

    size_t column_count = (size_t) XLENGTH(columns);
    if (column_count > ((size_t) R_XLEN_T_MAX - 2) / 9) {
        Rf_error("too many internal Arrow columns");
    }
    SEXP string_roots = PROTECT(Rf_allocVector(
        VECSXP, (R_xlen_t) (2 + 9 * column_count)
    ));
    R_xlen_t root_index = 0;
    const char *dataset_label = write_rooted_scalar_string(
        string_roots, root_index++, VECTOR_ELT(specification, 0),
        "dataset label"
    );
    SEXP rooted_dataset_metadata = write_rooted_strings(
        string_roots, root_index++, dataset_metadata, "dataset Stata metadata"
    );

    size_t row_count = 0;
    if (column_count > 0) {
        SEXP first = VECTOR_ELT(columns, 0);
        if (TYPEOF(first) != VECSXP || XLENGTH(first) != 16) {
            Rf_error("internal Arrow column must be a sixteen-element list");
        }
        row_count = (size_t) XLENGTH(VECTOR_ELT(first, 2));
    }
    dtatools_arrow_column *descriptors = (dtatools_arrow_column *) R_alloc(
        (R_SIZE_T) column_count, (int) sizeof(dtatools_arrow_column)
    );
    for (size_t index = 0; index < column_count; index++) {
        arrow_write_column_descriptor(
            VECTOR_ELT(columns, (R_xlen_t) index), index, row_count,
            string_roots, &root_index, &descriptors[index]
        );
    }

    int interrupted = 0;
    char *rust_error = NULL;
    SEXP result = dtatools_datasig_rust(
        dataset_label, rooted_dataset_metadata,
        descriptors, column_count, row_count, INTEGER(threads)[0],
        &interrupted,
        &rust_error
    );
    if (result == NULL) {
        UNPROTECT(1);
        if (interrupted) {
            Rf_onintr();
            Rf_error("Arrow signature interrupted");
        }
        fail_from_rust(rust_error);
    }
    UNPROTECT(1);
    return result;
}

static SEXP dtatools_arrow_snapshot_tag = NULL;

static void arrow_snapshot_finalize(SEXP external) {
    void *snapshot = R_ExternalPtrAddr(external);
    if (snapshot != NULL) {
        dtatools_close_arrow_rust(snapshot);
        R_ClearExternalPtr(external);
    }
}

static void *arrow_snapshot_pointer(SEXP external) {
    if (TYPEOF(external) != EXTPTRSXP ||
        dtatools_arrow_snapshot_tag == NULL ||
        R_ExternalPtrTag(external) != dtatools_arrow_snapshot_tag) {
        Rf_error("internal Arrow file snapshot is invalid");
    }
    void *snapshot = R_ExternalPtrAddr(external);
    if (snapshot == NULL) {
        Rf_error("internal Arrow file snapshot is closed");
    }
    return snapshot;
}

SEXP C_dtatools_open_arrow(SEXP path) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 ||
        STRING_ELT(path, 0) == NA_STRING) {
        Rf_error("`file` must be one non-missing path");
    }
    char *rust_error = NULL;
    void *snapshot = dtatools_open_arrow_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)), &rust_error
    );
    if (snapshot == NULL) fail_from_rust(rust_error);
    if (dtatools_arrow_snapshot_tag == NULL) {
        dtatools_arrow_snapshot_tag = Rf_install("dtatools_arrow_snapshot");
    }
    SEXP external = PROTECT(R_MakeExternalPtr(
        snapshot, dtatools_arrow_snapshot_tag, R_NilValue
    ));
    R_RegisterCFinalizerEx(external, arrow_snapshot_finalize, TRUE);
    UNPROTECT(1);
    return external;
}

SEXP C_dtatools_close_arrow(SEXP snapshot) {
    (void) arrow_snapshot_pointer(snapshot);
    arrow_snapshot_finalize(snapshot);
    return R_NilValue;
}

SEXP C_dtatools_read_arrow(
    SEXP snapshot, SEXP columns, SEXP skip, SEXP n_max, SEXP verify, SEXP profile,
    SEXP numeric_altrep, SEXP threads, SEXP datasig
) {
    void *snapshot_pointer = arrow_snapshot_pointer(snapshot);
    int all_columns = Rf_isNull(columns);
    if (!all_columns && TYPEOF(columns) != INTSXP) {
        Rf_error("internal column selection must be integer");
    }
    if (TYPEOF(skip) != REALSXP || XLENGTH(skip) != 1 ||
        TYPEOF(n_max) != REALSXP || XLENGTH(n_max) != 1) {
        Rf_error("internal row bounds must be numeric scalars");
    }
    if (TYPEOF(verify) != LGLSXP || XLENGTH(verify) != 1 ||
        LOGICAL(verify)[0] == NA_LOGICAL ||
        TYPEOF(profile) != LGLSXP || XLENGTH(profile) != 1 ||
        LOGICAL(profile)[0] == NA_LOGICAL) {
        Rf_error("internal Arrow read flags must be logical");
    }
    if (TYPEOF(numeric_altrep) != LGLSXP || XLENGTH(numeric_altrep) != 1 ||
        LOGICAL(numeric_altrep)[0] == NA_LOGICAL) {
        Rf_error("internal numeric ALTREP selector must be logical");
    }
    if (TYPEOF(datasig) != LGLSXP || XLENGTH(datasig) != 1 ||
        LOGICAL(datasig)[0] == NA_LOGICAL) {
        Rf_error("internal data signature selector must be logical");
    }
    if (TYPEOF(threads) != INTSXP || XLENGTH(threads) != 1 ||
        INTEGER(threads)[0] < 0) {
        Rf_error("internal thread count must be one non-negative integer");
    }
    int interrupted = 0;
    char *rust_error = NULL;
    SEXP result = dtatools_read_arrow_rust(
        snapshot_pointer,
        all_columns ? NULL : INTEGER(columns),
        all_columns ? 0 : (size_t) XLENGTH(columns),
        all_columns,
        REAL(skip)[0],
        REAL(n_max)[0],
        LOGICAL(verify)[0],
        LOGICAL(profile)[0],
        LOGICAL(numeric_altrep)[0],
        INTEGER(threads)[0],
        LOGICAL(datasig)[0],
        &interrupted,
        &rust_error
    );
    if (result == NULL) {
        if (interrupted) {
            Rf_onintr();
            Rf_error("Arrow read interrupted");
        }
        fail_from_rust(rust_error);
    }
    return result;
}

SEXP C_dtatools_arrow_metadata(
    SEXP snapshot, SEXP profile, SEXP scan_ambiguous_int32,
    SEXP skip, SEXP n_max
) {
    void *snapshot_pointer = arrow_snapshot_pointer(snapshot);
    if (TYPEOF(profile) != LGLSXP || XLENGTH(profile) != 1 ||
        LOGICAL(profile)[0] == NA_LOGICAL ||
        TYPEOF(scan_ambiguous_int32) != LGLSXP ||
        XLENGTH(scan_ambiguous_int32) != 1 ||
        LOGICAL(scan_ambiguous_int32)[0] == NA_LOGICAL) {
        Rf_error("internal Arrow metadata selectors must be logical");
    }
    if (TYPEOF(skip) != REALSXP || XLENGTH(skip) != 1 ||
        TYPEOF(n_max) != REALSXP || XLENGTH(n_max) != 1) {
        Rf_error("internal Arrow metadata row bounds must be numeric scalars");
    }
    int interrupted = 0;
    char *rust_error = NULL;
    SEXP result = dtatools_arrow_metadata_rust(
        snapshot_pointer, LOGICAL(profile)[0],
        LOGICAL(scan_ambiguous_int32)[0],
        REAL(skip)[0], REAL(n_max)[0],
        &interrupted, &rust_error
    );
    if (result == NULL) {
        if (interrupted) {
            Rf_onintr();
            Rf_error("Arrow read interrupted");
        }
        fail_from_rust(rust_error);
    }
    return result;
}

SEXP C_dtatools_arrow_datasig(SEXP path) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 ||
        STRING_ELT(path, 0) == NA_STRING) {
        Rf_error("`file` must be one non-missing path");
    }
    char *error = NULL;
    SEXP result = dtatools_arrow_datasig_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)), &error
    );
    if (result == NULL) fail_from_rust(error);
    return result;
}

static R_xlen_t ephemeral_string_length(SEXP value) {
    return XLENGTH(R_altrep_data1(value));
}

static SEXP ephemeral_string_value(SEXP value, R_xlen_t index) {
    SEXP source = STRING_ELT(R_altrep_data1(value), index);
    if (source == NA_STRING) return NA_STRING;
    return Rf_mkCharLenCE(CHAR(source), LENGTH(source), Rf_getCharCE(source));
}

SEXP C_dtatools_ephemeral_altstring(SEXP value) {
    if (TYPEOF(value) != STRSXP) {
        Rf_error("ephemeral ALTSTRING source must be character");
    }
    return R_new_altrep(
        dtatools_ephemeral_string_class, value, R_NilValue
    );
}

SEXP C_dtatools_is_numeric_altrep(SEXP value) {
    return Rf_ScalarLogical(R_altrep_inherits(value, dtatools_numeric_class));
}

SEXP C_dtatools_is_altrep(SEXP value) {
    return Rf_ScalarLogical(ALTREP(value));
}

static SEXP metadata_proxy_state(SEXP value) {
    SEXP state = R_altrep_data1(value);
    return TYPEOF(state) == VECSXP && XLENGTH(state) == 2
        ? state : R_NilValue;
}

static SEXP metadata_proxy_source(SEXP value) {
    SEXP state = metadata_proxy_state(value);
    return state == R_NilValue
        ? R_altrep_data1(value) : VECTOR_ELT(state, 0);
}

static SEXP metadata_proxy_owner(SEXP value) {
    SEXP state = metadata_proxy_state(value);
    return state == R_NilValue ? R_NilValue : VECTOR_ELT(state, 1);
}

static void metadata_proxy_set_state(
    SEXP value, SEXP source, SEXP owner
) {
    SEXP state = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(state, 0, source);
    SET_VECTOR_ELT(state, 1, owner);
    R_set_altrep_data1(value, state);
    UNPROTECT(1);
}

static R_xlen_t metadata_proxy_length(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue
        ? XLENGTH(metadata_proxy_source(value)) : XLENGTH(materialized);
}

static double metadata_real_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    return REAL_ELT(
        materialized == R_NilValue ? metadata_proxy_source(value) : materialized,
        index
    );
}

static R_xlen_t metadata_real_region(
    SEXP value, R_xlen_t index, R_xlen_t count, double *output
) {
    SEXP materialized = R_altrep_data2(value);
    return REAL_GET_REGION(
        materialized == R_NilValue ? metadata_proxy_source(value) : materialized,
        index, count, output
    );
}

static SEXP metadata_real_materialize(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return materialized;

    SEXP source = metadata_proxy_source(value);
    R_xlen_t length = XLENGTH(source);
    materialized = PROTECT(Rf_allocVector(REALSXP, length));
    R_xlen_t copied = REAL_GET_REGION(source, 0, length, REAL(materialized));
    if (copied != length) {
        UNPROTECT(1);
        Rf_error("failed to materialize dtatools metadata proxy");
    }
    R_set_altrep_data2(value, materialized);
    R_set_altrep_data1(value, R_NilValue);
    UNPROTECT(1);
    return materialized;
}

static void *metadata_real_dataptr(SEXP value, Rboolean writeable) {
    SEXP materialized = metadata_real_materialize(value);
#if R_VERSION >= R_Version(4, 6, 0)
    return writeable ? DATAPTR_RW(materialized) : (void *) DATAPTR_RO(materialized);
#else
    (void) writeable;
    return DATAPTR(materialized);
#endif
}

static const void *metadata_real_dataptr_or_null(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? NULL : DATAPTR_OR_NULL(materialized);
}

static SEXP metadata_real_extract_subset(
    SEXP value, SEXP index, SEXP call
) {
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    SEXP source = metadata_proxy_source(value);
    if (!ALTREP(source) ||
        !R_altrep_inherits(source, dtatools_numeric_class)) {
        return NULL;
    }
    return numeric_extract_subset(source, index, call);
}

static int metadata_real_no_na(SEXP value) {
    if (metadata_real_aggregate_mask_enabled) {
        metadata_real_aggregate_mask |= METADATA_AGGREGATE_NO_NA;
    }
    if (R_altrep_data2(value) != R_NilValue) return 0;
    SEXP source = metadata_proxy_source(value);
    return ALTREP(source) &&
        R_altrep_inherits(source, dtatools_numeric_class)
        ? numeric_no_na(source) : 0;
}

static SEXP metadata_real_sum(SEXP value, Rboolean na_rm) {
    if (metadata_real_aggregate_mask_enabled) {
        metadata_real_aggregate_mask |= METADATA_AGGREGATE_SUM;
    }
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    SEXP source = metadata_proxy_source(value);
    return ALTREP(source) &&
        R_altrep_inherits(source, dtatools_numeric_class)
        ? numeric_sum(source, na_rm) : NULL;
}

static SEXP metadata_real_min(SEXP value, Rboolean na_rm) {
    if (metadata_real_aggregate_mask_enabled) {
        metadata_real_aggregate_mask |= METADATA_AGGREGATE_MIN;
    }
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    SEXP source = metadata_proxy_source(value);
    return ALTREP(source) &&
        R_altrep_inherits(source, dtatools_numeric_class)
        ? numeric_min(source, na_rm) : NULL;
}

static SEXP metadata_real_max(SEXP value, Rboolean na_rm) {
    if (metadata_real_aggregate_mask_enabled) {
        metadata_real_aggregate_mask |= METADATA_AGGREGATE_MAX;
    }
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    SEXP source = metadata_proxy_source(value);
    return ALTREP(source) &&
        R_altrep_inherits(source, dtatools_numeric_class)
        ? numeric_max(source, na_rm) : NULL;
}

static SEXP metadata_string_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    return STRING_ELT(
        materialized == R_NilValue ? metadata_proxy_source(value) : materialized,
        index
    );
}

static SEXP metadata_string_materialize(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return materialized;

    SEXP source = metadata_proxy_source(value);
    R_xlen_t length = XLENGTH(source);
    materialized = PROTECT(Rf_allocVector(STRSXP, length));
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        SET_STRING_ELT(materialized, index, STRING_ELT(source, index));
    }
    R_set_altrep_data2(value, materialized);
    R_set_altrep_data1(value, R_NilValue);
    UNPROTECT(1);
    return materialized;
}

static SEXP metadata_string_materialize_for_patch(
    SEXP value, SEXP dictionary, SEXP private_cache
) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) {
        return detach_shared_materialized_payload(value);
    }
    materialized = PROTECT(dictstring_patch_values(
        dictionary, private_cache
    ));
    R_set_altrep_data2(value, materialized);
    R_set_altrep_data1(value, R_NilValue);
    UNPROTECT(1);
    return materialized;
}

static void *metadata_string_dataptr(SEXP value, Rboolean writeable) {
    (void) writeable;
    SEXP materialized = metadata_string_materialize(value);
#if R_VERSION >= R_Version(4, 6, 0)
    return DATAPTR_RW(materialized);
#else
    return DATAPTR(materialized);
#endif
}

static const void *metadata_string_dataptr_or_null(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? NULL : DATAPTR_OR_NULL(materialized);
}

static void metadata_string_set_elt(
    SEXP value, R_xlen_t index, SEXP replacement
) {
    SET_STRING_ELT(metadata_string_materialize(value), index, replacement);
}

static SEXP metadata_proxy(
    SEXP value, R_altrep_class_t proxy_class, int isolate
) {
    SEXP source = value;
    while (ALTREP(source) && R_altrep_inherits(source, proxy_class) &&
           R_altrep_data2(source) == R_NilValue) {
        SEXP owner = metadata_proxy_owner(source);
        SEXP next = metadata_proxy_source(source);
        if (isolate && owner != R_NilValue && ALTREP(next) &&
            R_altrep_inherits(next, dtatools_numeric_class) &&
            R_altrep_data2(next) == R_NilValue &&
            compact_payload_is_owned_by(R_altrep_data1(next), owner)) {
            /* A second proxy now shares this payload. Revoke the first
               proxy's exclusive-write claim so its next patch detaches. */
            compact_payload_revoke_claim(R_altrep_data1(next));
        }
        source = next;
    }
    SEXP materialized_snapshot = R_NilValue;
    if (isolate && ALTREP(source) &&
        R_altrep_inherits(source, proxy_class) &&
        R_altrep_data2(source) != R_NilValue) {
        materialized_snapshot = PROTECT(Rf_duplicate(
            R_altrep_data2(source)
        ));
        source = materialized_snapshot;
    }
    SEXP alias = R_NilValue;
    if (isolate && ALTREP(source) &&
        R_altrep_inherits(source, dtatools_numeric_class)) {
        SEXP external = R_altrep_data1(source);
        alias = PROTECT(R_new_altrep(
            dtatools_numeric_class, external, R_altrep_data2(source)
        ));
        compact_payload_mark_shared(external);
        source = alias;
    } else if (isolate && ALTREP(source) &&
               R_altrep_inherits(source, dtatools_dictstring_class)) {
        SEXP external = R_altrep_data1(source);
        alias = PROTECT(R_new_altrep(
            dtatools_dictstring_class, external, R_altrep_data2(source)
        ));
        compact_payload_mark_shared(external);
        source = alias;
    }
    SEXP state = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(state, 0, source);
    SET_VECTOR_ELT(state, 1, R_NilValue);
    SEXP result = PROTECT(R_new_altrep(proxy_class, state, R_NilValue));
    SHALLOW_DUPLICATE_ATTRIB(result, value);
    UNPROTECT(
        2 + (alias != R_NilValue) +
        (materialized_snapshot != R_NilValue)
    );
    return result;
}

SEXP C_dtatools_metadata_copy(SEXP value) {
    if (!ALTREP(value)) return Rf_shallow_duplicate(value);
    if (R_altrep_inherits(value, dtatools_numeric_class) ||
        R_altrep_inherits(value, dtatools_metadata_real_class)) {
        return metadata_proxy(value, dtatools_metadata_real_class, 1);
    }
    if (R_altrep_inherits(value, dtatools_dictstring_class) ||
        R_altrep_inherits(value, dtatools_metadata_string_class)) {
        return metadata_proxy(value, dtatools_metadata_string_class, 1);
    }
    return Rf_shallow_duplicate(value);
}

SEXP C_dtatools_metadata_view(SEXP value) {
    if (!ALTREP(value)) return Rf_shallow_duplicate(value);
    if (R_altrep_inherits(value, dtatools_numeric_class) ||
        R_altrep_inherits(value, dtatools_metadata_real_class)) {
        return metadata_proxy(value, dtatools_metadata_real_class, 0);
    }
    if (R_altrep_inherits(value, dtatools_dictstring_class) ||
        R_altrep_inherits(value, dtatools_metadata_string_class)) {
        return metadata_proxy(value, dtatools_metadata_string_class, 0);
    }
    return Rf_shallow_duplicate(value);
}

SEXP C_dtatools_mark_reference_data(
    SEXP data, SEXP state, SEXP classes
) {
    if (TYPEOF(data) != VECSXP || TYPEOF(state) != ENVSXP ||
        TYPEOF(classes) != STRSXP || XLENGTH(classes) == 0) {
        Rf_error("invalid reference-data state");
    }
    Rf_setAttrib(data, Rf_install(".dtatools_ref_state"), state);
    Rf_setAttrib(data, R_ClassSymbol, classes);
    return data;
}

static SEXP dictstring_compact_copy(SEXP value) {
    SEXP source = unmaterialized_dictstring_source(value);
    if (source == R_NilValue) return R_NilValue;
    dictstring_data *source_data = dictstring_storage(source);
    SEXP source_cache = dictstring_cache(source);
    SEXP cache = PROTECT(Rf_allocVector(VECSXP, XLENGTH(source_cache)));
    SEXP external = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, cache));
    R_RegisterCFinalizerEx(external, dictstring_finalize, TRUE);
    void *copy = dtatools_dictstring_clone(source_data);
    if (copy == NULL) {
        Rf_error("could not copy compact dictionary-string storage");
    }
    R_SetExternalPtrAddr(external, copy);
    SEXP result = PROTECT(R_new_altrep(
        dtatools_dictstring_class, external, R_NilValue
    ));
    DUPLICATE_ATTRIB(result, value);
    UNPROTECT(3);
    return result;
}

SEXP C_dtatools_deep_copy_value(SEXP value) {
    numeric_data *numeric = unmaterialized_numeric_storage(value);
    if (numeric != NULL) {
        SEXP result = PROTECT(numeric_compact_copy(numeric));
        DUPLICATE_ATTRIB(result, value);
        UNPROTECT(1);
        return result;
    }
    SEXP dictionary = dictstring_compact_copy(value);
    if (dictionary != R_NilValue) return dictionary;
    return Rf_duplicate(value);
}

SEXP C_dtatools_reference_contents(SEXP value) {
    int type = TYPEOF(value);
    if (type != VECSXP && type != EXPRSXP &&
        type != LISTSXP && type != LANGSXP) {
        Rf_error("invalid reference-object container");
    }
    R_xlen_t length = 0;
    if (type == VECSXP || type == EXPRSXP) {
        length = XLENGTH(value);
    } else {
        for (SEXP node = value; node != R_NilValue; node = CDR(node)) {
            if ((length & 16383) == 0) R_CheckUserInterrupt();
            int node_type = TYPEOF(node);
            if (node_type != LISTSXP && node_type != LANGSXP &&
                node_type != DOTSXP) {
                Rf_error("invalid reference-object pairlist");
            }
            if (length == R_XLEN_T_MAX) {
                Rf_error("reference-object container is too long");
            }
            length++;
        }
    }
    SEXP result = PROTECT(Rf_allocVector(VECSXP, length));
    if (type == VECSXP || type == EXPRSXP) {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            SET_VECTOR_ELT(result, index, VECTOR_ELT(value, index));
        }
    } else {
        SEXP node = value;
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            SET_VECTOR_ELT(result, index, CAR(node));
            node = CDR(node);
        }
    }
    UNPROTECT(1);
    return result;
}

static int reference_mutable_altrep(SEXP value) {
    return ALTREP(value) &&
        (R_altrep_inherits(value, dtatools_numeric_class) ||
         R_altrep_inherits(value, dtatools_dictstring_class) ||
         R_altrep_inherits(value, dtatools_metadata_real_class) ||
         R_altrep_inherits(value, dtatools_metadata_string_class));
}

static SEXP plain_column(SEXP value, int copy_values) {
    int type = TYPEOF(value);
    if (type != REALSXP && type != INTSXP &&
        type != LGLSXP && type != STRSXP) {
        Rf_error("unsupported generic ALTREP replacement storage");
    }
    R_xlen_t length = XLENGTH(value);
    SEXP result = PROTECT(Rf_allocVector(type, length));
    if (copy_values) {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            switch (type) {
            case REALSXP:
                REAL(result)[index] = REAL_ELT(value, index);
                break;
            case INTSXP:
                INTEGER(result)[index] = INTEGER_ELT(value, index);
                break;
            case LGLSXP:
                LOGICAL(result)[index] = LOGICAL_ELT(value, index);
                break;
            case STRSXP:
                SET_STRING_ELT(result, index, STRING_ELT(value, index));
                break;
            }
        }
    }
    DUPLICATE_ATTRIB(result, value);
    UNPROTECT(1);
    return result;
}

static double compact_patch_encoded_value(double value, int temporal) {
    if (temporal == 1) return value + 3653.0;
    if (temporal == 2) {
        double source = (value + 315619200.0) * 1000.0;
        double rounded = round(source);
        double decoded = rounded / 1000.0 - 315619200.0;
        return R_FINITE(source) && decoded == value ? rounded : source;
    }
    return value;
}

static void validate_compact_patch_value(
    const numeric_data *target, double value, int missing_code
) {
    if (missing_code >= 0) {
        if (missing_code == 256 ||
            (missing_code != 0 &&
             (missing_code < 'a' || missing_code > 'z'))) {
            Rf_error(
                "replacement values cannot contain `NaN` or unsupported missing tags"
            );
        }
        if (target->format_version <= 111 && missing_code != 0) {
            Rf_error(
                "this legacy compact column cannot store extended missing values"
            );
        }
        return;
    }
    unsigned char encoded[4] = {0};
    write_numeric_observed(
        encoded, 0, target->kind,
        compact_patch_encoded_value(value, target->temporal)
    );
}

static void write_compact_patch_value(
    numeric_data *target, size_t row, double value, int missing_code
) {
    unsigned char *output = (unsigned char *) target->values;
    if (missing_code >= 0) {
        int offset = missing_code == 0 ? 0 : missing_code - 'a' + 1;
        if (target->format_version <= 111) {
            write_numeric_system_missing_raw(
                output, (R_xlen_t) row, target->kind,
                target->format_version
            );
        } else {
            write_numeric_missing(
                output, (R_xlen_t) row, target->kind, offset
            );
        }
        return;
    }
    write_numeric_observed(
        output, (R_xlen_t) row, target->kind,
        compact_patch_encoded_value(value, target->temporal)
    );
}

static void encode_compact_patch_value(
    const numeric_data *target, double value, int missing_code,
    unsigned char encoded[4]
) {
    numeric_data encoder = *target;
    encoder.values = encoded;
    encoder.length = 1;
    write_compact_patch_value(&encoder, 0, value, missing_code);
}

static void write_encoded_compact_patch_value(
    numeric_data *target, size_t row, const unsigned char encoded[4],
    size_t width
) {
    memcpy(
        (unsigned char *) target->values + row * width,
        encoded, width
    );
}

static void fill_encoded_compact_patch_value(
    numeric_data *target, const unsigned char encoded[4], size_t width
) {
    if (width == 1) {
        memset(target->values, encoded[0], target->length);
        return;
    }
    for (size_t row = 0; row < target->length; row++) {
        if ((row & 16383) == 0) R_CheckUserInterrupt();
        write_encoded_compact_patch_value(target, row, encoded, width);
    }
}

static numeric_data *detach_compact_patch_target(SEXP value) {
    if (ALTREP(value) &&
        R_altrep_inherits(value, dtatools_numeric_class) &&
        R_altrep_data2(value) == R_NilValue) {
        SEXP external = R_altrep_data1(value);
        numeric_data *source = numeric_storage(value);
        if (!compact_payload_is_shared(external)) return source;
        SEXP detached = PROTECT(numeric_compact_copy(source));
        R_set_altrep_data1(value, R_altrep_data1(detached));
        numeric_data *result = numeric_storage(value);
        UNPROTECT(1);
        return result;
    }
    if (!ALTREP(value) ||
        !R_altrep_inherits(value, dtatools_metadata_real_class) ||
        R_altrep_data2(value) != R_NilValue) {
        return NULL;
    }
    SEXP owned = metadata_proxy_source(value);
    SEXP owner = metadata_proxy_owner(value);
    if (ALTREP(owned) &&
        R_altrep_inherits(owned, dtatools_numeric_class) &&
        R_altrep_data2(owned) == R_NilValue &&
        compact_payload_is_owned_by(R_altrep_data1(owned), owner)) {
        return numeric_storage(owned);
    }
    numeric_data *source = unmaterialized_numeric_storage(value);
    if (source == NULL) return NULL;
    SEXP detached = PROTECT(numeric_compact_copy(source));
    SEXP token = PROTECT(R_MakeExternalPtr(
        NULL, R_NilValue, R_NilValue
    ));
    compact_payload_claim(R_altrep_data1(detached), token);
    metadata_proxy_set_state(value, detached, token);
    R_set_altrep_data2(value, R_NilValue);
    numeric_data *result = numeric_storage(detached);
    UNPROTECT(2);
    return result;
}

static void detach_materialized_patch_target(SEXP value) {
    if (ALTREP(value) &&
        (R_altrep_inherits(value, dtatools_numeric_class) ||
         R_altrep_inherits(value, dtatools_dictstring_class))) {
        (void) detach_shared_materialized_payload(value);
    }
}

typedef struct {
    SEXP value;
    const int *integer_values;
    numeric_reader real_reader;
    R_xlen_t *snapshot;
    int real;
    int snapshot_required;
} reference_rows;

static R_xlen_t reference_live_row_at(
    const reference_rows *rows, R_xlen_t index
) {
    record_reference_row_read();
    if (rows->real) {
        int missing_code;
        double value = numeric_reader_at(
            &rows->real_reader, index, &missing_code
        );
        if (missing_code >= 0 || !R_FINITE(value) ||
            value != trunc(value) || value <= 0 ||
            value > (double) R_XLEN_T_MAX) {
            Rf_error("invalid reference mutation row");
        }
        return (R_xlen_t) value;
    }
    int value = rows->integer_values == NULL
        ? INTEGER_ELT(rows->value, index) : rows->integer_values[index];
    if (value == NA_INTEGER || value <= 0) {
        Rf_error("invalid reference mutation row");
    }
    return (R_xlen_t) value;
}

static R_xlen_t reference_row_at(
    const reference_rows *rows, R_xlen_t index
) {
    return rows->snapshot == NULL
        ? reference_live_row_at(rows, index) : rows->snapshot[index];
}

static reference_rows reference_rows_create(
    SEXP value, R_xlen_t limit
) {
    reference_rows rows;
    memset(&rows, 0, sizeof(rows));
    rows.value = value;
    if (value == R_NilValue) return rows;
    if (TYPEOF(value) == INTSXP) {
        rows.integer_values = (const int *) DATAPTR_OR_NULL(value);
    } else if (TYPEOF(value) == REALSXP) {
        rows.real_reader = numeric_reader_create(value, XLENGTH(value));
        rows.real = 1;
    } else {
        Rf_error("invalid reference mutation row plan");
    }
    R_xlen_t length = XLENGTH(value);
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t row = reference_row_at(&rows, index);
        if (row > limit) Rf_error("invalid reference mutation row");
    }
    return rows;
}

static int reference_rows_alias_target(SEXP rows, SEXP target) {
    if (rows == R_NilValue) return 0;
    if (rows == target) return 1;

    numeric_data *row_storage = unmaterialized_numeric_storage(rows);
    numeric_data *target_storage = unmaterialized_numeric_storage(target);
    if (row_storage != NULL && row_storage == target_storage) return 1;

    const void *row_values = DATAPTR_OR_NULL(rows);
    const void *target_values = DATAPTR_OR_NULL(target);
    return row_values != NULL && row_values == target_values;
}

static reference_rows reference_patch_rows_create(
    SEXP value, SEXP target, R_xlen_t limit
) {
    reference_rows rows = reference_rows_create(value, limit);
    rows.snapshot_required = reference_rows_alias_target(value, target);
    return rows;
}

static void snapshot_reference_rows(reference_rows *rows) {
    if (!rows->snapshot_required || rows->snapshot != NULL ||
        rows->value == R_NilValue) {
        return;
    }
    R_xlen_t length = XLENGTH(rows->value);
    if ((size_t) length > SIZE_MAX / sizeof(R_xlen_t)) {
        Rf_error("reference mutation row plan is too large");
    }
    rows->snapshot = (R_xlen_t *) malloc(
        length == 0 ? 1 : (size_t) length * sizeof(R_xlen_t)
    );
    if (rows->snapshot == NULL) {
        Rf_error("could not snapshot the reference mutation row plan");
    }
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        rows->snapshot[index] = reference_live_row_at(rows, index);
    }
}

static void release_reference_rows(reference_rows *rows) {
    free(rows->snapshot);
    rows->snapshot = NULL;
}

static R_xlen_t reference_patch_row(
    const reference_rows *rows, R_xlen_t index
) {
    if (rows->value == R_NilValue) return index;
    return reference_row_at(rows, index) - 1;
}

typedef enum {
    REFERENCE_VALUES_SCALAR,
    REFERENCE_VALUES_SELECTED,
    REFERENCE_VALUES_BY_ROW
} reference_value_mode;

typedef struct {
    R_xlen_t count;
    R_xlen_t value_count;
    reference_value_mode mode;
} reference_value_plan;

static reference_value_plan reference_value_plan_create(
    SEXP values, const reference_rows *rows, R_xlen_t count,
    R_xlen_t row_count, int allow_by_row, const char *error_message
) {
    reference_value_plan plan = {
        count, XLENGTH(values), REFERENCE_VALUES_SELECTED
    };
    if (plan.value_count == 1) {
        plan.mode = REFERENCE_VALUES_SCALAR;
    } else if (allow_by_row && rows->value != R_NilValue &&
               plan.value_count == row_count) {
        plan.mode = REFERENCE_VALUES_BY_ROW;
    } else if (plan.value_count != count &&
               !(count == 0 && plan.value_count == 0)) {
        Rf_error("%s", error_message);
    }
    return plan;
}

static R_xlen_t reference_value_index(
    const reference_value_plan *plan, R_xlen_t index, R_xlen_t row
) {
    if (plan->mode == REFERENCE_VALUES_SCALAR) return 0;
    if (plan->mode == REFERENCE_VALUES_BY_ROW) return row;
    return index;
}

typedef struct {
    numeric_reader reader;
    reference_value_plan values;
    unsigned char scalar_encoded[4];
    int scalar_missing_code;
    int validate_on_apply;
} compact_replacement_plan;

static compact_replacement_plan compact_replacement_plan_create(
    const numeric_data *target, SEXP values, const reference_rows *rows,
    reference_value_plan value_plan, int prevalidate
) {
    compact_replacement_plan plan;
    memset(&plan, 0, sizeof(plan));
    plan.values = value_plan;
    plan.scalar_missing_code = -1;
    plan.validate_on_apply = !prevalidate;
    plan.reader = numeric_reader_create(values, value_plan.value_count);
    if (value_plan.mode == REFERENCE_VALUES_SCALAR) {
        double value = numeric_reader_at(
            &plan.reader, 0, &plan.scalar_missing_code
        );
        validate_compact_patch_value(
            target, value, plan.scalar_missing_code
        );
        encode_compact_patch_value(
            target, value, plan.scalar_missing_code,
            plan.scalar_encoded
        );
    } else if (prevalidate) {
        for (R_xlen_t index = 0; index < value_plan.count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            int missing_code;
            R_xlen_t value_index = value_plan.mode == REFERENCE_VALUES_BY_ROW
                ? reference_patch_row(rows, index) : index;
            double value = numeric_reader_at(
                &plan.reader, value_index, &missing_code
            );
            validate_compact_patch_value(target, value, missing_code);
        }
    }
    return plan;
}

static void apply_compact_replacement(
    numeric_data *target, const reference_rows *rows,
    const compact_replacement_plan *replacement
) {
    size_t width = numeric_kind_width(target->kind);
    if (replacement->values.mode == REFERENCE_VALUES_SCALAR) {
        int new_missing = replacement->scalar_missing_code >= 0;
        if (rows->value == R_NilValue) {
            fill_encoded_compact_patch_value(
                target, replacement->scalar_encoded, width
            );
            target->missing_count = new_missing ? target->length : 0;
            return;
        }
        for (R_xlen_t index = 0;
             index < replacement->values.count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            size_t row = (size_t) reference_patch_row(rows, index);
            int old_missing = numeric_value_is_missing_at(target, row);
            if (old_missing && !new_missing) target->missing_count--;
            if (!old_missing && new_missing) target->missing_count++;
            write_encoded_compact_patch_value(
                target, row, replacement->scalar_encoded, width
            );
        }
        return;
    }
    for (R_xlen_t index = 0;
         index < replacement->values.count; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        int missing_code;
        R_xlen_t row = reference_patch_row(rows, index);
        R_xlen_t value_index = reference_value_index(
            &replacement->values, index, row
        );
        double value = numeric_reader_at(
            &replacement->reader, value_index, &missing_code
        );
        if (replacement->validate_on_apply) {
            validate_compact_patch_value(target, value, missing_code);
        }
        size_t row_offset = (size_t) row;
        int old_missing = numeric_value_is_missing_at(target, row_offset);
        int new_missing = missing_code >= 0;
        if (old_missing && !new_missing) target->missing_count--;
        if (!old_missing && new_missing) target->missing_count++;
        write_compact_patch_value(
            target, row_offset, value, missing_code
        );
    }
}

typedef struct {
    SEXP target;
    SEXP saved_data1;
    SEXP saved_data2;
    reference_rows *rows;
    const compact_replacement_plan *replacement;
    numeric_data *compact;
    unsigned char *undo;
    size_t undo_bytes;
    size_t width;
    size_t saved_missing_count;
    int journal_complete;
} compact_patch_transaction;

static void restore_compact_patch(compact_patch_transaction *transaction) {
    if (R_altrep_data1(transaction->target) != transaction->saved_data1 ||
        R_altrep_data2(transaction->target) != transaction->saved_data2) {
        R_set_altrep_data1(transaction->target, transaction->saved_data1);
        R_set_altrep_data2(transaction->target, transaction->saved_data2);
        return;
    }
    if (transaction->compact == NULL || transaction->undo == NULL) return;
    if (transaction->rows->value == R_NilValue) {
        if (transaction->undo_bytes > 0) {
            memcpy(
                transaction->compact->values,
                transaction->undo,
                transaction->undo_bytes
            );
        }
    } else {
        R_xlen_t count = transaction->replacement->values.count;
        for (R_xlen_t index = 0; index < count; index++) {
            size_t row = (size_t) reference_patch_row(
                transaction->rows, index
            );
            memcpy(
                (unsigned char *) transaction->compact->values +
                    row * transaction->width,
                transaction->undo + (size_t) index * transaction->width,
                transaction->width
            );
        }
    }
    transaction->compact->missing_count = transaction->saved_missing_count;
}

static SEXP apply_compact_patch_transaction(void *data) {
    compact_patch_transaction *transaction =
        (compact_patch_transaction *) data;
    snapshot_reference_rows(transaction->rows);
    R_xlen_t count = transaction->replacement->values.count;
    if (transaction->rows->value == R_NilValue) {
        if (transaction->undo_bytes > 0) {
            memcpy(
                transaction->undo,
                transaction->compact->values,
                transaction->undo_bytes
            );
        }
    } else {
        for (R_xlen_t index = 0; index < count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            size_t row = (size_t) reference_patch_row(
                transaction->rows, index
            );
            memcpy(
                transaction->undo + (size_t) index * transaction->width,
                (unsigned char *) transaction->compact->values +
                    row * transaction->width,
                transaction->width
            );
        }
    }
    transaction->journal_complete = 1;

    transaction->compact = detach_compact_patch_target(transaction->target);
    if (transaction->compact == NULL) {
        Rf_error("compact replacement target became unavailable");
    }
    transaction->saved_missing_count = transaction->compact->missing_count;
    apply_compact_replacement(
        transaction->compact,
        transaction->rows,
        transaction->replacement
    );
    if (count > 0) maybe_inject_reference_write_interrupt();
    R_CheckUserInterrupt();
    return Rf_ScalarLogical(1);
}

static void cleanup_compact_patch_transaction(
    void *data, Rboolean jump
) {
    compact_patch_transaction *transaction =
        (compact_patch_transaction *) data;
    if (jump && transaction->journal_complete) {
        restore_compact_patch(transaction);
    }
    release_reference_rows(transaction->rows);
    free(transaction->undo);
    transaction->undo = NULL;
}

typedef struct {
    SEXP target;
    SEXP replacement;
    reference_string_reader replacement_reader;
    SEXP saved_data1;
    SEXP saved_data2;
    SEXP string_undo;
    SEXP dictstring_private_cache;
    SEXP dictstring_source;
    SEXP replacement_empty;
    reference_rows *rows;
    unsigned char *undo;
    size_t width;
    reference_value_plan values;
    R_xlen_t writes_completed;
    int type;
    int journal_complete;
    int delayed_dictstring_finalize;
    int rollback_required;
    int replacement_string_width;
} vector_patch_transaction;

static SEXP vector_patch_replacement_string(
    const vector_patch_transaction *transaction, R_xlen_t index
) {
    SEXP value = reference_string_reader_at(
        &transaction->replacement_reader, index
    );
    return value == NA_STRING ? transaction->replacement_empty : value;
}

static void validate_reference_replacement_string(
    SEXP value, int declared_width
) {
    size_t width = reference_string_width(value, "replacement");
    if (declared_width > 0 && width > (size_t) declared_width) {
        Rf_error(
            "Replacement values do not fit their declared Stata string storage"
        );
    }
}

static void validate_vector_patch_replacement_strings(
    const vector_patch_transaction *transaction
) {
    if (transaction->type != STRSXP || transaction->values.count == 0) {
        return;
    }
    if (transaction->values.mode == REFERENCE_VALUES_SCALAR) {
        validate_reference_replacement_string(
            vector_patch_replacement_string(transaction, 0),
            transaction->replacement_string_width
        );
        return;
    }
    for (R_xlen_t index = 0;
         index < transaction->values.count; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t row = reference_patch_row(transaction->rows, index);
        R_xlen_t replacement_index = reference_value_index(
            &transaction->values, index, row
        );
        validate_reference_replacement_string(
            vector_patch_replacement_string(transaction, replacement_index),
            transaction->replacement_string_width
        );
    }
}

static int vector_patch_state_changed(
    const vector_patch_transaction *transaction
) {
    return ALTREP(transaction->target) &&
        (R_altrep_data1(transaction->target) != transaction->saved_data1 ||
         R_altrep_data2(transaction->target) != transaction->saved_data2);
}

static void restore_vector_patch(vector_patch_transaction *transaction) {
    if (vector_patch_state_changed(transaction)) {
        SEXP current_data1 = R_altrep_data1(transaction->target);
        if (transaction->delayed_dictstring_finalize &&
            current_data1 != transaction->saved_data1) {
            dictstring_finalize(current_data1);
        }
        R_set_altrep_data1(transaction->target, transaction->saved_data1);
        R_set_altrep_data2(transaction->target, transaction->saved_data2);
        return;
    }
    double *real_output = transaction->type == REALSXP
        ? REAL(transaction->target) : NULL;
    int *integer_output = transaction->type == INTSXP
        ? INTEGER(transaction->target) : NULL;
    int *logical_output = transaction->type == LGLSXP
        ? LOGICAL(transaction->target) : NULL;
    for (R_xlen_t index = 0;
         index < transaction->writes_completed; index++) {
        R_xlen_t row = reference_patch_row(transaction->rows, index);
        switch (transaction->type) {
        case REALSXP:
            memcpy(
                real_output + row,
                transaction->undo + (size_t) index * transaction->width,
                transaction->width
            );
            break;
        case INTSXP:
            memcpy(
                integer_output + row,
                transaction->undo + (size_t) index * transaction->width,
                transaction->width
            );
            break;
        case LGLSXP:
            memcpy(
                logical_output + row,
                transaction->undo + (size_t) index * transaction->width,
                transaction->width
            );
            break;
        case STRSXP:
            SET_STRING_ELT(
                transaction->target, row,
                STRING_ELT(transaction->string_undo, index)
            );
            break;
        }
    }
}

static SEXP apply_vector_patch_transaction(void *data) {
    vector_patch_transaction *transaction =
        (vector_patch_transaction *) data;
    snapshot_reference_rows(transaction->rows);
    int full_dictionary_overwrite =
        transaction->dictstring_source != R_NilValue &&
        transaction->rows->value == R_NilValue;
    if (!full_dictionary_overwrite) {
        validate_vector_patch_replacement_strings(transaction);
    } else if (transaction->values.count > 0 &&
               transaction->values.mode == REFERENCE_VALUES_SCALAR) {
        validate_reference_replacement_string(
            vector_patch_replacement_string(transaction, 0),
            transaction->replacement_string_width
        );
    }
    if (transaction->rollback_required &&
        (transaction->type != STRSXP ||
         transaction->dictstring_source == R_NilValue)) {
        for (R_xlen_t index = 0;
             index < transaction->values.count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            R_xlen_t row = reference_patch_row(transaction->rows, index);
            switch (transaction->type) {
            case REALSXP: {
                double value = REAL_ELT(transaction->target, row);
                memcpy(
                    transaction->undo + (size_t) index * transaction->width,
                    &value, transaction->width
                );
                break;
            }
            case INTSXP: {
                int value = INTEGER_ELT(transaction->target, row);
                memcpy(
                    transaction->undo + (size_t) index * transaction->width,
                    &value, transaction->width
                );
                break;
            }
            case LGLSXP: {
                int value = LOGICAL_ELT(transaction->target, row);
                memcpy(
                    transaction->undo + (size_t) index * transaction->width,
                    &value, transaction->width
                );
                break;
            }
            case STRSXP:
                SET_STRING_ELT(
                    transaction->string_undo, index,
                    STRING_ELT(transaction->target, row)
                );
                break;
            }
        }
    }
    transaction->journal_complete = transaction->rollback_required;

    if (full_dictionary_overwrite) {
        SEXP materialized = PROTECT(Rf_allocVector(
            STRSXP, transaction->values.count
        ));
        for (R_xlen_t index = 0;
             index < transaction->values.count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            R_xlen_t replacement_index = reference_value_index(
                &transaction->values, index, index
            );
            SEXP value = vector_patch_replacement_string(
                transaction, replacement_index
            );
            if (transaction->values.mode != REFERENCE_VALUES_SCALAR) {
                validate_reference_replacement_string(
                    value, transaction->replacement_string_width
                );
            }
            SET_STRING_ELT(materialized, index, value);
        }
        R_CheckUserInterrupt();
        R_set_altrep_data2(transaction->target, materialized);
        if (!transaction->delayed_dictstring_finalize) {
            R_set_altrep_data1(transaction->target, R_NilValue);
        }
        transaction->writes_completed = transaction->values.count;
        UNPROTECT(1);
    } else if (transaction->delayed_dictstring_finalize) {
        (void) dictstring_materialize_for_patch(
            transaction->target, transaction->dictstring_private_cache
        );
    } else if (transaction->dictstring_source != R_NilValue) {
        (void) metadata_string_materialize_for_patch(
            transaction->target, transaction->dictstring_source,
            transaction->dictstring_private_cache
        );
    } else {
        detach_materialized_patch_target(transaction->target);
    }
    double *real_output = NULL;
    int *integer_output = NULL;
    int *logical_output = NULL;
    SEXP string_output = R_NilValue;
    if (transaction->type == REALSXP) {
#if R_VERSION >= R_Version(4, 6, 0)
        real_output = (double *) DATAPTR_RW(transaction->target);
#else
        real_output = REAL(transaction->target);
#endif
    } else if (transaction->type == INTSXP) {
        integer_output = INTEGER(transaction->target);
    } else if (transaction->type == LGLSXP) {
        logical_output = LOGICAL(transaction->target);
    } else if (transaction->type == STRSXP) {
        string_output = ALTREP(transaction->target)
            ? R_altrep_data2(transaction->target) : transaction->target;
    }
    for (R_xlen_t index = transaction->writes_completed;
         index < transaction->values.count; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t row = reference_patch_row(transaction->rows, index);
        R_xlen_t replacement_index = reference_value_index(
            &transaction->values, index, row
        );
        switch (transaction->type) {
        case REALSXP:
            real_output[row] = REAL_ELT(
                transaction->replacement, replacement_index
            );
            break;
        case INTSXP:
            integer_output[row] = INTEGER_ELT(
                transaction->replacement, replacement_index
            );
            break;
        case LGLSXP:
            logical_output[row] = LOGICAL_ELT(
                transaction->replacement, replacement_index
            );
            break;
        case STRSXP:
            SET_STRING_ELT(
                string_output, row,
                vector_patch_replacement_string(
                    transaction, replacement_index
                )
            );
            break;
        }
        transaction->writes_completed = index + 1;
    }
    if (transaction->values.count > 0) {
        maybe_inject_reference_write_interrupt();
    }
    R_CheckUserInterrupt();
    return Rf_ScalarLogical(0);
}

static void cleanup_vector_patch_transaction(
    void *data, Rboolean jump
) {
    vector_patch_transaction *transaction =
        (vector_patch_transaction *) data;
    if (jump && transaction->journal_complete &&
        (vector_patch_state_changed(transaction) ||
         transaction->writes_completed > 0)) {
        restore_vector_patch(transaction);
    }
    release_reference_rows(transaction->rows);
    free(transaction->undo);
    transaction->undo = NULL;
}

static void commit_vector_patch_transaction(
    vector_patch_transaction *transaction
) {
    if (!transaction->delayed_dictstring_finalize) return;
    SEXP external = R_altrep_data1(transaction->target);
    if (!compact_payload_is_shared(external)) {
        dictstring_finalize(external);
    }
    R_set_altrep_data1(transaction->target, R_NilValue);
}

static SEXP patch_vector(
    SEXP target, SEXP rows, SEXP replacement, int rollback_required
) {
    if (rows != R_NilValue &&
        TYPEOF(rows) != INTSXP && TYPEOF(rows) != REALSXP) {
        Rf_error("invalid reference replacement plan");
    }
    R_xlen_t target_length = XLENGTH(target);
    R_xlen_t count = rows == R_NilValue ? target_length : XLENGTH(rows);
    reference_rows row_plan = reference_patch_rows_create(
        rows, target, target_length
    );

    numeric_data *compact = unmaterialized_numeric_storage(target);
    int native_by_row = compact != NULL ||
        unmaterialized_dictstring_source(replacement) != R_NilValue;
    reference_value_plan value_plan = reference_value_plan_create(
        replacement, &row_plan, count, target_length, native_by_row,
        "invalid reference replacement plan"
    );
    if (compact != NULL) {
        compact_replacement_plan replacement_plan =
            compact_replacement_plan_create(
                compact, replacement, &row_plan, value_plan, 1
            );
        if (count == 0) {
            release_reference_rows(&row_plan);
            return Rf_ScalarLogical(0);
        }
        size_t width = numeric_kind_width(compact->kind);
        if ((size_t) count > SIZE_MAX / width) {
            Rf_error("reference replacement plan is too large");
        }
        size_t undo_bytes = (size_t) count * width;
        SEXP saved_state = PROTECT(Rf_allocVector(VECSXP, 2));
        SET_VECTOR_ELT(saved_state, 0, R_altrep_data1(target));
        SET_VECTOR_ELT(saved_state, 1, R_altrep_data2(target));
        SEXP continuation = PROTECT(R_MakeUnwindCont());
        unsigned char *undo = (unsigned char *) malloc(
            undo_bytes == 0 ? 1 : undo_bytes
        );
        if (undo == NULL) {
            UNPROTECT(2);
            Rf_error("could not allocate reference replacement rollback data");
        }
        compact_patch_transaction transaction = {
            target,
            VECTOR_ELT(saved_state, 0),
            VECTOR_ELT(saved_state, 1),
            &row_plan,
            &replacement_plan,
            compact,
            undo,
            undo_bytes,
            width,
            compact->missing_count,
            0
        };
        SEXP result = R_UnwindProtect(
            apply_compact_patch_transaction, &transaction,
            cleanup_compact_patch_transaction, &transaction,
            continuation
        );
        UNPROTECT(2);
        return result;
    }

    if (TYPEOF(target) != TYPEOF(replacement)) {
        Rf_error("replacement storage does not match its target");
    }
    int type = TYPEOF(target);
    if (type != REALSXP && type != INTSXP &&
        type != LGLSXP && type != STRSXP) {
        Rf_error("unsupported reference replacement storage");
    }
    if (count == 0) {
        if (type == STRSXP &&
            value_plan.mode == REFERENCE_VALUES_SCALAR) {
            reference_string_reader reader =
                reference_string_reader_create(replacement, R_NilValue);
            int declared_width = string_declared_width(
                Rf_getAttrib(
                    target, Rf_install("stata.string.storage")
                ),
                "Replacement values do not fit their declared Stata string storage"
            );
            validate_reference_replacement_string(
                reference_string_reader_at(&reader, 0), declared_width
            );
        }
        release_reference_rows(&row_plan);
        return Rf_ScalarLogical(0);
    }
    if (ALTREP(target) && !reference_mutable_altrep(target)) {
        Rf_error("generic ALTREP targets must be detached before replacement");
    }
    size_t width = type == REALSXP ? sizeof(double) : sizeof(int);
    SEXP dictstring_source = type == STRSXP
        ? unmaterialized_dictstring_source(target) : R_NilValue;
    SEXP replacement_dictstring_source = type == STRSXP
        ? unmaterialized_dictstring_source(replacement) : R_NilValue;
    if (rows == R_NilValue &&
        ((target == replacement &&
          (type != STRSXP || dictstring_source != R_NilValue)) ||
         (dictstring_source == target &&
          replacement_dictstring_source == target))) {
        release_reference_rows(&row_plan);
        return Rf_ScalarLogical(0);
    }
    int delayed_dictstring_finalize = dictstring_source == target;
    SEXP saved_state = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(
        saved_state, 0,
        ALTREP(target) ? R_altrep_data1(target) : R_NilValue
    );
    SET_VECTOR_ELT(
        saved_state, 1,
        ALTREP(target) ? R_altrep_data2(target) : R_NilValue
    );
    SEXP string_undo = PROTECT(
        rollback_required && type == STRSXP &&
            dictstring_source == R_NilValue
            ? Rf_allocVector(STRSXP, count) : R_NilValue
    );
    SEXP private_cache = PROTECT(
        dictstring_source != R_NilValue && rows != R_NilValue
            ? reference_string_reader_private_cache(
                dictstring_source, count
            )
            : R_NilValue
    );
    SEXP replacement_reader_cache = PROTECT(
        type == STRSXP
            ? reference_string_reader_private_cache(
                replacement,
                value_plan.mode == REFERENCE_VALUES_SCALAR ? 1 : count
            )
            : R_NilValue
    );
    reference_string_reader replacement_reader =
        reference_string_reader_create(
            replacement, replacement_reader_cache
        );
    SEXP replacement_scalar = PROTECT(
        type == STRSXP &&
            value_plan.mode == REFERENCE_VALUES_SCALAR
            ? reference_string_reader_at(&replacement_reader, 0)
            : R_NilValue
    );
    replacement_reader.scalar = replacement_scalar;
    SEXP replacement_empty = PROTECT(
        type == STRSXP ? Rf_mkChar("") : R_NilValue
    );
    SEXP continuation = PROTECT(R_MakeUnwindCont());
    unsigned char *undo = NULL;
    if (rollback_required && type != STRSXP) {
        if ((size_t) count > SIZE_MAX / width) {
            UNPROTECT(7);
            Rf_error("reference replacement plan is too large");
        }
        size_t bytes = (size_t) count * width;
        undo = (unsigned char *) malloc(bytes == 0 ? 1 : bytes);
        if (undo == NULL) {
            UNPROTECT(7);
            Rf_error("could not allocate reference replacement rollback data");
        }
    }
    vector_patch_transaction transaction = {
        .target = target,
        .replacement = replacement,
        .replacement_reader = replacement_reader,
        .saved_data1 = VECTOR_ELT(saved_state, 0),
        .saved_data2 = VECTOR_ELT(saved_state, 1),
        .string_undo = string_undo,
        .dictstring_private_cache = private_cache,
        .dictstring_source = dictstring_source,
        .replacement_empty = replacement_empty,
        .rows = &row_plan,
        .undo = undo,
        .width = width,
        .values = value_plan,
        .writes_completed = 0,
        .type = type,
        .journal_complete = 0,
        .delayed_dictstring_finalize = delayed_dictstring_finalize,
        .rollback_required = rollback_required,
        .replacement_string_width = type == STRSXP
            ? string_declared_width(
                Rf_getAttrib(
                    target, Rf_install("stata.string.storage")
                ),
                "Replacement values do not fit their declared Stata string storage"
            )
            : -1
    };
    SEXP result = R_UnwindProtect(
        apply_vector_patch_transaction, &transaction,
        cleanup_vector_patch_transaction, &transaction,
        continuation
    );
    commit_vector_patch_transaction(&transaction);
    UNPROTECT(7);
    return result;
}

SEXP C_dtatools_patch_vector(
    SEXP target, SEXP rows, SEXP replacement
) {
    return patch_vector(target, rows, replacement, 1);
}

SEXP C_dtatools_patch_data_column(
    SEXP data, SEXP location, SEXP target, SEXP rows, SEXP replacement
) {
    if (TYPEOF(data) != VECSXP || TYPEOF(location) != INTSXP ||
        XLENGTH(location) != 1) {
        Rf_error("invalid generic ALTREP replacement target");
    }
    int index = INTEGER_ELT(location, 0);
    if (index == NA_INTEGER || index < 1) {
        Rf_error("invalid generic ALTREP replacement target");
    }

    int detached = ALTREP(target) && !reference_mutable_altrep(target);
    if ((R_xlen_t) index > XLENGTH(data)) {
        if (!detached || XLENGTH(target) == 0 ||
            (rows != R_NilValue && XLENGTH(rows) == 0)) {
            PROTECT(patch_vector(target, rows, replacement, 1));
            UNPROTECT(1);
            return target;
        }
        SEXP column = PROTECT(plain_column(target, rows != R_NilValue));
        PROTECT(patch_vector(column, rows, replacement, 0));
        UNPROTECT(2);
        return column;
    }
    if (target != VECTOR_ELT(data, (R_xlen_t) index - 1)) {
        Rf_error("invalid generic ALTREP replacement target");
    }
    if (XLENGTH(target) == 0 ||
        (rows != R_NilValue && XLENGTH(rows) == 0)) {
        PROTECT(patch_vector(target, rows, replacement, 1));
        UNPROTECT(1);
        return target;
    }
    if (!detached) {
        PROTECT(patch_vector(target, rows, replacement, 1));
        UNPROTECT(1);
        return target;
    }

    SEXP column = PROTECT(plain_column(target, rows != R_NilValue));
    PROTECT(patch_vector(column, rows, replacement, 0));
    SET_VECTOR_ELT(data, (R_xlen_t) index - 1, column);
    UNPROTECT(2);
    return column;
}

SEXP C_dtatools_set_data_column(SEXP data, SEXP location, SEXP column) {
    if (TYPEOF(data) != VECSXP) {
        Rf_error("`data` must be a list");
    }
    if (TYPEOF(location) != INTSXP || XLENGTH(location) != 1) {
        Rf_error("`location` must be one integer value");
    }
    int index = INTEGER(location)[0];
    if (index == NA_INTEGER || index < 1 ||
        (R_xlen_t) index > XLENGTH(data)) {
        Rf_error("`location` is out of range");
    }
    SET_VECTOR_ELT(data, (R_xlen_t) index - 1, column);
    return column;
}

static void resize_reference_vector(SEXP value, R_xlen_t length) {
#if R_VERSION >= R_Version(4, 6, 0)
    R_resizeVector(value, length);
#else
    SETLENGTH(value, length);
#endif
}

static int can_resize_reference_columns(
    SEXP data, SEXP current_names, R_xlen_t new_length
) {
    R_xlen_t old_length = XLENGTH(data);
    int is_data_table = Rf_inherits(data, "data.table");
#if R_VERSION >= R_Version(4, 6, 0)
    return new_length == old_length ||
        (!ALTREP(data) &&
         R_isResizable(data) &&
         new_length <= R_maxLength(data) &&
         (!is_data_table ||
          (R_isResizable(current_names) &&
           new_length <= R_maxLength(current_names))));
#else
    return new_length == old_length ||
        (!ALTREP(data) &&
         TRUELENGTH(data) > 0 &&
         (R_xlen_t) TRUELENGTH(data) >= new_length &&
         (!is_data_table ||
          (TRUELENGTH(current_names) > 0 &&
           (R_xlen_t) TRUELENGTH(current_names) >= new_length)));
#endif
}

SEXP C_dtatools_can_select_data_columns(SEXP data, SEXP length) {
    if (TYPEOF(data) != VECSXP || XLENGTH(length) != 1) {
        Rf_error("invalid reference column selection capacity query");
    }
    double requested = Rf_asReal(length);
    if (!R_FINITE(requested) || requested < 0 ||
        requested > (double) R_XLEN_T_MAX || requested != floor(requested)) {
        Rf_error("invalid reference column selection capacity query");
    }
    SEXP current_names = Rf_getAttrib(data, R_NamesSymbol);
    if (TYPEOF(current_names) != STRSXP ||
        XLENGTH(current_names) != XLENGTH(data)) {
        Rf_error("invalid reference column selection names");
    }
    int can_resize = can_resize_reference_columns(
        data, current_names, (R_xlen_t) requested
    );
    if (!can_resize && Rf_inherits(data, "data.table")) {
        Rf_error(
            "`data` is a non-resizable data.table; call "
            "`data.table::setalloccol()` after restoring it"
        );
    }
    return Rf_ScalarLogical(can_resize);
}

SEXP C_dtatools_select_data_columns(
    SEXP data, SEXP columns, SEXP names, SEXP state,
    SEXP base_classes, SEXP reference_classes
) {
    if (TYPEOF(data) != VECSXP ||
        TYPEOF(columns) != VECSXP || TYPEOF(names) != STRSXP ||
        XLENGTH(columns) != XLENGTH(names)) {
        Rf_error("invalid reference column selection plan");
    }
    if (state != R_NilValue && TYPEOF(state) != ENVSXP) {
        Rf_error("invalid reference column selection state");
    }
    if (TYPEOF(base_classes) != STRSXP || XLENGTH(base_classes) == 0 ||
        TYPEOF(reference_classes) != STRSXP ||
        XLENGTH(reference_classes) == 0) {
        Rf_error("invalid reference column selection classes");
    }
    SEXP current_names = PROTECT(Rf_getAttrib(data, R_NamesSymbol));
    if (TYPEOF(current_names) != STRSXP ||
        XLENGTH(current_names) != XLENGTH(data)) {
        Rf_error("invalid reference column selection names");
    }
    for (R_xlen_t index = 0; index < XLENGTH(names); index++) {
        SEXP name = STRING_ELT(names, index);
        if (name == NA_STRING || LENGTH(name) == 0) {
            Rf_error("invalid reference column selection name");
        }
    }
    if (Rf_any_duplicated(names, FALSE) != 0) {
        Rf_error("invalid duplicate reference column selection name");
    }
    SEXP planned_names = PROTECT(Rf_duplicate(names));

    R_xlen_t old_length = XLENGTH(data);
    R_xlen_t new_length = XLENGTH(columns);
    int is_data_table = Rf_inherits(data, "data.table");
    int can_resize = can_resize_reference_columns(
        data, current_names, new_length
    );
    if ((!can_resize && TYPEOF(state) != ENVSXP) ||
        (can_resize && state != R_NilValue)) {
        Rf_error("invalid reference column selection state");
    }
    int keep_state = !can_resize;
    R_xlen_t installed_length = can_resize
        ? new_length
        : (new_length < old_length ? new_length : old_length);
    int protect_count = 2;
    SEXP committed_names = current_names;
    if (!is_data_table) {
        committed_names = PROTECT(Rf_allocVector(
            STRSXP, can_resize ? new_length : old_length
        ));
        protect_count++;
        for (R_xlen_t index = 0; index < installed_length; index++) {
            SET_STRING_ELT(
                committed_names, index, STRING_ELT(planned_names, index)
            );
        }
        for (R_xlen_t index = installed_length;
             index < XLENGTH(committed_names); index++) {
            SET_STRING_ELT(committed_names, index, R_BlankString);
        }
    }

    /* Materialize an ALTREP list wrapper before any visible commit. Once this
       succeeds, installing its already validated elements cannot allocate. */
    if (ALTREP(data)) (void) DATAPTR_RO(data);

    /* R-level selection and state construction are complete. The remaining
       writes commit one already validated plan. */
    SEXP reference_state_symbol = Rf_install(".dtatools_ref_state");
    SEXP sorted_symbol = Rf_install("sorted");
    SEXP index_symbol = Rf_install("index");
    Rf_setAttrib(
        data, reference_state_symbol,
        keep_state ? state : R_NilValue
    );
    Rf_setAttrib(
        data, R_ClassSymbol,
        keep_state ? reference_classes : base_classes
    );
    if (is_data_table) {
        Rf_setAttrib(data, sorted_symbol, R_NilValue);
        Rf_setAttrib(data, index_symbol, R_NilValue);
    }

    if (can_resize && new_length != old_length) {
        resize_reference_vector(data, new_length);
        if (is_data_table) {
            resize_reference_vector(current_names, new_length);
        }
    }
    for (R_xlen_t index = 0; index < installed_length; index++) {
        SET_VECTOR_ELT(data, index, VECTOR_ELT(columns, index));
    }
    if (!can_resize) {
        for (R_xlen_t index = installed_length; index < old_length; index++) {
            SET_VECTOR_ELT(data, index, R_NilValue);
        }
    }
    if (is_data_table) {
        for (R_xlen_t index = 0; index < installed_length; index++) {
            SET_STRING_ELT(
                current_names, index, STRING_ELT(planned_names, index)
            );
        }
        if (!can_resize) {
            for (R_xlen_t index = installed_length;
                 index < old_length; index++) {
                SET_STRING_ELT(current_names, index, R_BlankString);
            }
        }
    }
    Rf_setAttrib(data, R_NamesSymbol, committed_names);
    UNPROTECT(protect_count);
    return data;
}

static double generated_double_value(
    const numeric_reader *reader, R_xlen_t index, int temporal
) {
    int missing_code;
    double value = numeric_reader_at(reader, index, &missing_code);
    if (missing_code >= 0) {
        if (missing_code == 0) return NA_REAL;
        if (missing_code >= 'a' && missing_code <= 'z') {
            return numeric_missing_value(missing_code - 'a' + 1);
        }
        Rf_error(
            "generated values cannot contain `NaN` or unsupported missing tags"
        );
    }
    double encoded = compact_patch_encoded_value(value, temporal);
    if (!R_FINITE(encoded) || fabs(encoded) > DBL_MAX / 2.0) {
        Rf_error("No Stata double storage can represent the generated value");
    }
    return value;
}

static SEXP generate_double_numeric(
    SEXP values, const reference_rows *rows, size_t row_count,
    const reference_value_plan *value_plan, int temporal
) {
    numeric_reader reader = numeric_reader_create(
        values, value_plan->value_count
    );
    SEXP result = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) row_count));
    double *output = REAL(result);
    if (rows->value != R_NilValue) {
        for (size_t index = 0; index < row_count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            output[index] = NA_REAL;
        }
    }

    if (value_plan->mode == REFERENCE_VALUES_SCALAR) {
        double value = generated_double_value(&reader, 0, temporal);
        if (rows->value == R_NilValue) {
            for (size_t index = 0; index < row_count; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                output[index] = value;
            }
        } else {
            for (R_xlen_t index = 0; index < value_plan->count; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                output[reference_patch_row(rows, index)] = value;
            }
        }
    } else {
        for (R_xlen_t index = 0; index < value_plan->count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            R_xlen_t row = rows->value == R_NilValue
                ? index : reference_patch_row(rows, index);
            R_xlen_t value_index = reference_value_index(
                value_plan, index, row
            );
            output[row] = generated_double_value(
                &reader, value_index, temporal
            );
        }
    }
    UNPROTECT(1);
    return result;
}

static void set_generated_attributes(SEXP value, SEXP attributes) {
    if (TYPEOF(attributes) != VECSXP) {
        Rf_error("invalid generated-column attributes");
    }
    SEXP names = Rf_getAttrib(attributes, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || XLENGTH(names) != XLENGTH(attributes)) {
        Rf_error("invalid generated-column attributes");
    }
    for (R_xlen_t index = 0; index < XLENGTH(attributes); index++) {
        SEXP name = STRING_ELT(names, index);
        if (name == NA_STRING || LENGTH(name) == 0) {
            Rf_error("invalid generated-column attribute name");
        }
        Rf_setAttrib(
            value, Rf_installChar(name), VECTOR_ELT(attributes, index)
        );
    }
}

static int string_declared_width(SEXP declared, const char *message) {
    if (declared == R_NilValue) return -1;
    if (TYPEOF(declared) != STRSXP || XLENGTH(declared) != 1 ||
        STRING_ELT(declared, 0) == NA_STRING) {
        Rf_error("%s", message);
    }
    const char *storage = Rf_translateCharUTF8(STRING_ELT(declared, 0));
    if (strcmp(storage, "strL") == 0) return 0;
    if (strncmp(storage, "str", 3) != 0 || storage[3] == '\0') {
        Rf_error("%s", message);
    }
    int width = 0;
    for (const char *digit = storage + 3; *digit != '\0'; digit++) {
        if (*digit < '0' || *digit > '9' || width > 2045) {
            Rf_error("%s", message);
        }
        width = width * 10 + (*digit - '0');
    }
    if (width < 1 || width > 2045) {
        Rf_error("%s", message);
    }
    return width;
}

static int generated_string_declared_width(SEXP declared) {
    return string_declared_width(
        declared,
        "Generated values do not fit their declared Stata string storage"
    );
}

static size_t reference_string_width(SEXP value, const char *operation) {
    if (value == NA_STRING) return 0;
    const char *bytes = Rf_translateCharUTF8(value);
    size_t width = strlen(bytes);
    if (width > (size_t) 2000000000) {
        Rf_error(
            "A %s string exceeds Stata's 2,000,000,000-byte limit",
            operation
        );
    }
    return width;
}

static size_t generated_string_width(SEXP value) {
    return reference_string_width(value, "generated");
}

SEXP C_dtatools_generate_character(
    SEXP values, SEXP rows, SEXP row_count_value,
    SEXP declared, SEXP attributes
) {
    if (TYPEOF(values) != STRSXP ||
        (rows != R_NilValue &&
         TYPEOF(rows) != INTSXP && TYPEOF(rows) != REALSXP)) {
        Rf_error("invalid reference string generation plan");
    }
    double row_count_double = Rf_asReal(row_count_value);
    if (!R_FINITE(row_count_double) || row_count_double < 0 ||
        row_count_double != trunc(row_count_double) ||
        row_count_double > (double) R_XLEN_T_MAX) {
        Rf_error("invalid reference generation row count");
    }
    R_xlen_t row_count = (R_xlen_t) row_count_double;
    R_xlen_t count = rows == R_NilValue ? row_count : XLENGTH(rows);
    reference_rows row_plan = reference_rows_create(rows, row_count);
    reference_value_plan value_plan = reference_value_plan_create(
        values, &row_plan, count, row_count, 1,
        "invalid reference string generation plan"
    );
    int declared_width = generated_string_declared_width(declared);
    SEXP reader_cache = PROTECT(
        reference_string_reader_private_cache(
            values,
            value_plan.mode == REFERENCE_VALUES_SCALAR && count > 0
                ? 1 : count
        )
    );
    reference_string_reader reader = reference_string_reader_create(
        values, reader_cache
    );

    SEXP scalar_value = PROTECT(
        count > 0 && value_plan.mode == REFERENCE_VALUES_SCALAR
            ? reference_string_reader_at(&reader, 0) : R_NilValue
    );
    SEXP result = PROTECT(Rf_allocVector(STRSXP, row_count));
    SEXP empty = PROTECT(Rf_mkChar(""));
    size_t maximum = scalar_value == R_NilValue
        ? 0 : generated_string_width(scalar_value);
    if (rows != R_NilValue &&
        value_plan.mode != REFERENCE_VALUES_SCALAR) {
        int needs_normalization = 0;
        /* R initializes string vectors with blank strings. Visit selected rows
           in reverse so each final, last-write-wins value is decoded once.
           NA_STRING marks a selected blank, distinguishing it from an
           untouched row until the final normalization pass. */
        for (R_xlen_t remaining = count; remaining > 0; remaining--) {
            R_xlen_t index = remaining - 1;
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            R_xlen_t row = reference_patch_row(&row_plan, index);
            if (STRING_ELT(result, row) != empty) continue;
            R_xlen_t value_index = reference_value_index(
                &value_plan, index, row
            );
            SEXP value = reference_string_reader_at(&reader, value_index);
            SEXP normalized = value == NA_STRING ? empty : value;
            if (normalized == empty) needs_normalization = 1;
            SET_STRING_ELT(
                result, row, normalized == empty ? NA_STRING : normalized
            );
            size_t width = generated_string_width(normalized);
            if (width > maximum) maximum = width;
        }
        if (needs_normalization) {
            for (R_xlen_t index = 0; index < row_count; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                if (STRING_ELT(result, index) == NA_STRING) {
                    SET_STRING_ELT(result, index, empty);
                }
            }
        }
    } else {
        for (R_xlen_t index = 0; index < count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            R_xlen_t row = rows == R_NilValue
                ? index : reference_patch_row(&row_plan, index);
            R_xlen_t value_index = reference_value_index(
                &value_plan, index, row
            );
            SEXP value = value_plan.mode == REFERENCE_VALUES_SCALAR
                ? scalar_value
                : reference_string_reader_at(&reader, value_index);
            SEXP normalized = value == NA_STRING ? empty : value;
            SET_STRING_ELT(result, row, normalized);
            if (value_plan.mode != REFERENCE_VALUES_SCALAR) {
                size_t width = generated_string_width(normalized);
                if (width > maximum) maximum = width;
            }
        }
    }
    if (declared_width > 0 && maximum > (size_t) declared_width) {
        Rf_error("Generated values do not fit their declared Stata string storage");
    }

    char inferred[16];
    const char *storage;
    if (declared_width == 0) {
        storage = "strL";
    } else if (declared_width > 0) {
        storage = Rf_translateCharUTF8(STRING_ELT(declared, 0));
    } else if (maximum > 2045) {
        storage = "strL";
    } else {
        snprintf(
            inferred, sizeof(inferred), "str%zu",
            maximum > 0 ? maximum : 1
        );
        storage = inferred;
    }
    SEXP storage_value = PROTECT(Rf_mkString(storage));
    set_generated_attributes(result, attributes);
    Rf_setAttrib(
        result, Rf_install("stata.string.storage"), storage_value
    );
    UNPROTECT(5);
    return result;
}

SEXP C_dtatools_generate_numeric(
    SEXP values, SEXP rows, SEXP row_count_value,
    SEXP kind_value, SEXP temporal_value, SEXP attributes
) {
    if (rows != R_NilValue &&
        TYPEOF(rows) != INTSXP && TYPEOF(rows) != REALSXP) {
        Rf_error("invalid reference generation plan");
    }
    double row_count_double = Rf_asReal(row_count_value);
    if (!R_FINITE(row_count_double) || row_count_double < 0 ||
        row_count_double != trunc(row_count_double) ||
        row_count_double > (double) R_XLEN_T_MAX ||
        row_count_double > (double) SIZE_MAX) {
        Rf_error("invalid reference generation row count");
    }
    size_t row_count = (size_t) row_count_double;
    int kind = Rf_asInteger(kind_value);
    int temporal = Rf_asInteger(temporal_value);
    if (kind < NUMERIC_BYTE || kind > NUMERIC_DOUBLE ||
        temporal < 0 || temporal > 2) {
        Rf_error("invalid reference generation storage");
    }

    R_xlen_t count = rows == R_NilValue
        ? (R_xlen_t) row_count : XLENGTH(rows);
    reference_rows row_plan = reference_rows_create(
        rows, (R_xlen_t) row_count
    );
    reference_value_plan value_plan = reference_value_plan_create(
        values, &row_plan, count, (R_xlen_t) row_count, 1,
        "invalid reference generation plan"
    );

    if (kind == NUMERIC_DOUBLE) {
        SEXP result = PROTECT(generate_double_numeric(
            values, &row_plan, row_count, &value_plan, temporal
        ));
        set_generated_attributes(result, attributes);
        UNPROTECT(1);
        return result;
    }

    numeric_data plan = {
        NULL, row_count, kind, temporal, 119,
        rows == R_NilValue ? 0 : row_count
    };
    compact_replacement_plan replacement_plan =
        compact_replacement_plan_create(
            &plan, values, &row_plan, value_plan, 0
        );

    size_t width = numeric_kind_width(kind);
    if (row_count > SIZE_MAX / width ||
        row_count * width > (size_t) R_XLEN_T_MAX) {
        Rf_error("generated compact Stata numeric vector is too long");
    }
    SEXP backing = PROTECT(Rf_allocVector(
        RAWSXP, (R_xlen_t) (row_count * width)
    ));
    plan.values = RAW(backing);
    if (rows != R_NilValue) {
        for (size_t index = 0; index < row_count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            write_numeric_missing(plan.values, (R_xlen_t) index, kind, 0);
        }
    }
    apply_compact_replacement(&plan, &row_plan, &replacement_plan);

    SEXP result = PROTECT(numeric_from_backing(
        backing, row_count, kind, temporal, 119, plan.missing_count
    ));
    set_generated_attributes(result, attributes);
    UNPROTECT(2);
    return result;
}

SEXP C_dtatools_is_unmaterialized_numeric_altrep(SEXP value) {
    while (ALTREP(value)) {
        if (R_altrep_inherits(value, dtatools_numeric_class)) {
            return Rf_ScalarLogical(R_altrep_data2(value) == R_NilValue);
        }
        if (!R_altrep_inherits(value, dtatools_metadata_real_class)) break;
        if (R_altrep_data2(value) != R_NilValue) return Rf_ScalarLogical(0);
        value = metadata_proxy_source(value);
    }
    return Rf_ScalarLogical(0);
}

SEXP C_dtatools_is_unmaterialized_dictstring(SEXP value) {
    return Rf_ScalarLogical(
        unmaterialized_dictstring_source(value) != R_NilValue
    );
}

SEXP C_dtatools_dictstring_cached_count(SEXP value) {
    SEXP source = unmaterialized_dictstring_source(value);
    if (source == R_NilValue) {
        Rf_error("value is not an unmaterialized dictionary string");
    }
    SEXP cache = dictstring_cache(source);
    R_xlen_t count = 0;
    for (R_xlen_t index = 0; index < XLENGTH(cache); index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        if (VECTOR_ELT(cache, index) != R_NilValue) count++;
    }
    return Rf_ScalarReal((double) count);
}

SEXP C_dtatools_numeric_storage_matches(
    SEXP value, SEXP kind_value, SEXP temporal_value
) {
    if (TYPEOF(kind_value) != INTSXP || XLENGTH(kind_value) != 1 ||
        INTEGER(kind_value)[0] < 0 || INTEGER(kind_value)[0] > 4 ||
        TYPEOF(temporal_value) != INTSXP || XLENGTH(temporal_value) != 1 ||
        INTEGER(temporal_value)[0] < 0 || INTEGER(temporal_value)[0] > 2) {
        Rf_error("invalid compact Stata storage probe");
    }
    numeric_data *storage = unmaterialized_numeric_storage(value);
    return Rf_ScalarLogical(
        storage != NULL && storage->kind == INTEGER(kind_value)[0] &&
        storage->temporal == INTEGER(temporal_value)[0]
    );
}

SEXP C_dtatools_force_altrep_materialization(SEXP value) {
    if (!ALTREP(value) ||
        !(TYPEOF(value) == REALSXP || TYPEOF(value) == STRSXP)) {
        Rf_error("internal materialization probe requires an ALTREP vector");
    }
#if R_VERSION >= R_Version(4, 6, 0)
    (void) DATAPTR_RO(value);
#else
    (void) DATAPTR(value);
#endif
    return value;
}

SEXP C_dtatools_mutate_first_numeric_altrep(SEXP value, SEXP replacement) {
    if (!ALTREP(value) || TYPEOF(value) != REALSXP || XLENGTH(value) == 0 ||
        TYPEOF(replacement) != REALSXP || XLENGTH(replacement) != 1) {
        Rf_error("internal writable ALTREP probe requires a nonempty numeric ALTREP vector");
    }
#if R_VERSION >= R_Version(4, 6, 0)
    double *data = (double *) DATAPTR_RW(value);
#else
    double *data = REAL(value);
#endif
    data[0] = REAL(replacement)[0];
    return value;
}

SEXP C_dtatools_mutate_first_dictstring_altrep(
    SEXP value, SEXP replacement
) {
    if (!ALTREP(value) || TYPEOF(value) != STRSXP || XLENGTH(value) == 0 ||
        TYPEOF(replacement) != STRSXP || XLENGTH(replacement) != 1) {
        Rf_error(
            "internal writable ALTSTRING probe requires a nonempty "
            "string ALTREP vector"
        );
    }
    SET_STRING_ELT(value, 0, STRING_ELT(replacement, 0));
    return value;
}

SEXP C_dtatools_metadata_proxy_depth(SEXP value) {
    int depth = 0;
    while (ALTREP(value)) {
        if (!(R_altrep_inherits(value, dtatools_metadata_real_class) ||
              R_altrep_inherits(value, dtatools_metadata_string_class))) {
            break;
        }
        if (depth == INT_MAX) Rf_error("metadata proxy depth exceeds R limits");
        depth++;
        value = metadata_proxy_source(value);
    }
    return Rf_ScalarInteger(depth);
}

SEXP C_dtatools_metadata_proxy_aggregate_mask(SEXP enabled) {
    if (TYPEOF(enabled) != LGLSXP || XLENGTH(enabled) != 1 ||
        LOGICAL(enabled)[0] == NA_LOGICAL) {
        Rf_error("internal aggregate-mask state must be logical");
    }
    if (LOGICAL(enabled)[0]) {
        metadata_real_aggregate_mask = 0;
        metadata_real_aggregate_mask_enabled = 1;
    } else {
        metadata_real_aggregate_mask_enabled = 0;
    }
    return Rf_ScalarInteger(metadata_real_aggregate_mask);
}

SEXP C_dtatools_has_tagged_na(SEXP value) {
    if (TYPEOF(value) != REALSXP) return Rf_ScalarLogical(0);
    R_xlen_t length = XLENGTH(value);
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        if (is_tagged_na_value(REAL_ELT(value, index))) {
            return Rf_ScalarLogical(1);
        }
    }
    return Rf_ScalarLogical(0);
}

SEXP C_dtatools_tagged_missing(SEXP tag) {
    if (TYPEOF(tag) != STRSXP) {
        Rf_error("`tag` must be a character vector");
    }

    R_xlen_t length = XLENGTH(tag);
    SEXP result = PROTECT(Rf_allocVector(REALSXP, length));
    double *output = REAL(result);
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        int normalized = normalized_stata_missing_tag(
            STRING_ELT(tag, index), "tag"
        );
        output[index] = numeric_missing_value(normalized - 'a' + 1);
    }
    copy_shape_attributes(result, tag);
    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_is_tagged_missing(SEXP value, SEXP tag) {
    if ((TYPEOF(value) != REALSXP && TYPEOF(value) != INTSXP) ||
        Rf_inherits(value, "factor")) {
        Rf_error("`x` must be a numeric vector");
    }

    int match_any = tag == R_NilValue;
    int selected[26] = {0};
    if (!match_any) {
        if (TYPEOF(tag) != STRSXP) {
            Rf_error("`tag` must be a character vector or NULL");
        }
        R_xlen_t tag_count = XLENGTH(tag);
        for (R_xlen_t index = 0; index < tag_count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            int normalized = normalized_stata_missing_tag(
                STRING_ELT(tag, index), "tag"
            );
            selected[normalized - 'a'] = 1;
        }
    }

    R_xlen_t length = XLENGTH(value);
    SEXP result = PROTECT(Rf_allocVector(LGLSXP, length));
    int *output = LOGICAL(result);
    if (TYPEOF(value) == REALSXP) {
        numeric_data *storage = unmaterialized_numeric_storage(value);
        const double *input = storage == NULL
            ? (const double *) DATAPTR_OR_NULL(value) : NULL;
        if (storage != NULL) {
            if ((R_xlen_t) storage->length != length) {
                Rf_error(
                    "dtatools numeric storage length does not match vector length"
                );
            }
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int offset = numeric_missing_offset_at(
                    storage, (size_t) index
                );
                output[index] = offset >= 1 && offset <= 26 &&
                    (match_any || selected[offset - 1]);
            }
        } else if (input != NULL) {
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int actual = stata_missing_tag_value(input[index]);
                output[index] = actual != 0 &&
                    (match_any || selected[actual - 'a']);
            }
        } else {
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int actual = stata_missing_tag_value(REAL_ELT(value, index));
                output[index] = actual != 0 &&
                    (match_any || selected[actual - 'a']);
            }
        }
    } else {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            output[index] = 0;
        }
    }
    copy_shape_attributes(result, value);
    UNPROTECT(1);
    return result;
}

static int is_missing_supported_class(SEXP value) {
    if (!Rf_isObject(value)) return 1;
    if (Rf_inherits(value, "factor")) return 0;

    switch (TYPEOF(value)) {
    case LGLSXP:
    case INTSXP:
    case REALSXP:
        return Rf_inherits(value, "stata_numeric") ||
            Rf_inherits(value, "stata_temporal") ||
            Rf_inherits(value, "Date") ||
            Rf_inherits(value, "POSIXct") ||
            Rf_inherits(value, "haven_labelled");
    case STRSXP:
        return Rf_inherits(value, "haven_labelled");
    default:
        return 0;
    }
}

static int is_missing_supported_type(SEXP value) {
    int type = TYPEOF(value);
    return type == LGLSXP || type == INTSXP || type == REALSXP ||
        type == STRSXP;
}

static void validate_is_missing_argument(SEXP value, R_xlen_t argument) {
    if (Rf_getAttrib(value, R_DimSymbol) != R_NilValue) {
        Rf_error(
            "Argument %lld to `is_missing()` must be a vector, not a matrix or array",
            (long long) argument
        );
    }
    if (!is_missing_supported_type(value)) {
        Rf_error(
            "Argument %lld to `is_missing()` must be a logical, numeric, or character vector",
            (long long) argument
        );
    }
    if (!is_missing_supported_class(value)) {
        Rf_error(
            "Argument %lld to `is_missing()` has an unsupported class",
            (long long) argument
        );
    }
}

static int numeric_reader_is_missing_at(
    const numeric_reader *reader, R_xlen_t index
) {
    if (reader->storage != NULL) {
        numeric_data *data = reader->storage;
        return numeric_value_is_missing_at(data, (size_t) index);
    }

    if (reader->type == INTSXP || reader->type == LGLSXP) {
        int value = reader->integer_values == NULL
            ? (reader->type == LGLSXP
                ? LOGICAL_ELT(reader->value, index)
                : INTEGER_ELT(reader->value, index))
            : reader->integer_values[index];
        return value == NA_INTEGER;
    }

    double value = reader->real_values == NULL
        ? REAL_ELT(reader->value, index)
        : reader->real_values[index];
    return ISNAN(value);
}

static int is_missing_value_at(
    SEXP value, const numeric_reader *numeric,
    const reference_string_reader *string, R_xlen_t index
) {
    if (TYPEOF(value) == STRSXP) {
        return reference_string_reader_is_missing_at(string, index);
    }
    return numeric_reader_is_missing_at(numeric, index);
}

SEXP C_dtatools_is_missing(SEXP values) {
    if (TYPEOF(values) != VECSXP) {
        Rf_error("internal `is_missing()` arguments must be a list");
    }
    R_xlen_t argument_count = XLENGTH(values);
    if (argument_count == 0) {
        Rf_error("`is_missing()` requires at least one argument");
    }

    R_xlen_t common_size = 1;
    R_xlen_t common_argument = 0;
    for (R_xlen_t argument = 0; argument < argument_count; argument++) {
        SEXP value = VECTOR_ELT(values, argument);
        validate_is_missing_argument(value, argument + 1);
        R_xlen_t size = XLENGTH(value);
        if (size == 1) continue;
        if (common_argument == 0) {
            common_size = size;
            common_argument = argument + 1;
        } else if (size != common_size) {
            Rf_error(
                "Argument %lld to `is_missing()` has size %lld, which is incompatible with argument %lld of size %lld; only size-one recycling is allowed",
                (long long) (argument + 1), (long long) size,
                (long long) common_argument, (long long) common_size
            );
        }
    }

    SEXP result = PROTECT(Rf_allocVector(LGLSXP, common_size));
    int *output = LOGICAL(result);
    memset(output, 0, (size_t) common_size * sizeof(int));
    R_xlen_t unresolved = common_size;

    for (R_xlen_t argument = 0;
         argument < argument_count && unresolved > 0;
         argument++) {
        SEXP value = VECTOR_ELT(values, argument);
        if (XLENGTH(value) != 1) continue;
        R_CheckUserInterrupt();

        numeric_reader reader = {0};
        numeric_reader *reader_pointer = NULL;
        reference_string_reader string_reader = {0};
        reference_string_reader *string_reader_pointer = NULL;
        if (TYPEOF(value) == STRSXP) {
            string_reader = reference_string_reader_create(value, R_NilValue);
            string_reader_pointer = &string_reader;
        } else {
            reader = numeric_reader_create(value, 1);
            reader_pointer = &reader;
        }
        if (!is_missing_value_at(
                value, reader_pointer, string_reader_pointer, 0
            )) continue;

        for (R_xlen_t index = 0; index < common_size; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            output[index] = 1;
        }
        unresolved = 0;
    }

    for (R_xlen_t argument = 0;
         argument < argument_count && unresolved > 0;
         argument++) {
        SEXP value = VECTOR_ELT(values, argument);
        R_xlen_t size = XLENGTH(value);
        if (size <= 1) continue;

        numeric_reader reader = {0};
        numeric_reader *reader_pointer = NULL;
        reference_string_reader string_reader = {0};
        reference_string_reader *string_reader_pointer = NULL;
        if (TYPEOF(value) == STRSXP) {
            string_reader = reference_string_reader_create(value, R_NilValue);
            string_reader_pointer = &string_reader;
        } else {
            reader = numeric_reader_create(value, size);
            reader_pointer = &reader;
        }

        for (R_xlen_t index = 0;
             index < common_size && unresolved > 0;
             index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            if (output[index]) continue;
            int missing = is_missing_value_at(
                value, reader_pointer, string_reader_pointer, index
            );
            output[index] = missing;
            if (missing) unresolved--;
        }
    }

    for (R_xlen_t argument = 0; argument < argument_count; argument++) {
        SEXP value = VECTOR_ELT(values, argument);
        if (XLENGTH(value) != common_size) continue;
        SEXP names = Rf_getAttrib(value, R_NamesSymbol);
        if (names != R_NilValue) {
            Rf_setAttrib(result, R_NamesSymbol, names);
            break;
        }
    }

    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_missing_tag(SEXP value) {
    if ((TYPEOF(value) != REALSXP && TYPEOF(value) != INTSXP) ||
        Rf_inherits(value, "factor")) {
        Rf_error("`x` must be a numeric vector");
    }

    R_xlen_t length = XLENGTH(value);
    SEXP result = PROTECT(Rf_allocVector(STRSXP, length));
    if (TYPEOF(value) == REALSXP) {
        SEXP tag_names = PROTECT(Rf_allocVector(STRSXP, 26));
        for (int index = 0; index < 26; index++) {
            char text = (char) ('a' + index);
            SET_STRING_ELT(tag_names, index, Rf_mkCharLen(&text, 1));
        }

        numeric_data *storage = unmaterialized_numeric_storage(value);
        const double *input = storage == NULL
            ? (const double *) DATAPTR_OR_NULL(value) : NULL;
        if (storage != NULL) {
            if ((R_xlen_t) storage->length != length) {
                Rf_error(
                    "dtatools numeric storage length does not match vector length"
                );
            }
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int offset = numeric_missing_offset_at(
                    storage, (size_t) index
                );
                SET_STRING_ELT(
                    result, index,
                    offset >= 1 && offset <= 26
                        ? STRING_ELT(tag_names, offset - 1) : NA_STRING
                );
            }
        } else if (input != NULL) {
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int tag = stata_missing_tag_value(input[index]);
                SET_STRING_ELT(
                    result, index,
                    tag == 0 ? NA_STRING : STRING_ELT(tag_names, tag - 'a')
                );
            }
        } else {
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int tag = stata_missing_tag_value(REAL_ELT(value, index));
                SET_STRING_ELT(
                    result, index,
                    tag == 0 ? NA_STRING : STRING_ELT(tag_names, tag - 'a')
                );
            }
        }
        UNPROTECT(1);
    } else {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            SET_STRING_ELT(result, index, NA_STRING);
        }
    }
    copy_shape_attributes(result, value);
    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_missing_codes(SEXP value) {
    /* NA means observed, zero is system missing, 1--255 is the tagged-NA
       payload byte, and 256 is an ordinary R NaN. */
    R_xlen_t length = XLENGTH(value);
    SEXP result = PROTECT(Rf_allocVector(INTSXP, length));
    int *output = INTEGER(result);

    if (TYPEOF(value) == REALSXP) {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            double element = REAL_ELT(value, index);
            int tag = tagged_na_tag_value(element);
            if (tag != 0) {
                output[index] = tag;
            } else if (ISNA(element)) {
                output[index] = 0;
            } else if (ISNAN(element)) {
                output[index] = 256;
            } else {
                output[index] = NA_INTEGER;
            }
        }
    } else if (TYPEOF(value) == INTSXP) {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            output[index] = INTEGER_ELT(value, index) == NA_INTEGER
                ? 0 : NA_INTEGER;
        }
    } else {
        Rf_error("missing-code classification requires a numeric vector");
    }

    UNPROTECT(1);
    return result;
}

static const R_CallMethodDef CallEntries[] = {
    {"C_dtatools_metadata", (DL_FUNC) &C_dtatools_metadata, 4},
    {"C_dtatools_read", (DL_FUNC) &C_dtatools_read, 8},
    {"C_dtatools_write", (DL_FUNC) &C_dtatools_write, 2},
    {"C_dtatools_save_arrow", (DL_FUNC) &C_dtatools_save_arrow, 5},
    {"C_dtatools_datasig", (DL_FUNC) &C_dtatools_datasig, 2},
    {"C_dtatools_open_arrow", (DL_FUNC) &C_dtatools_open_arrow, 1},
    {"C_dtatools_close_arrow", (DL_FUNC) &C_dtatools_close_arrow, 1},
    {"C_dtatools_read_arrow", (DL_FUNC) &C_dtatools_read_arrow, 9},
    {"C_dtatools_arrow_metadata",
     (DL_FUNC) &C_dtatools_arrow_metadata, 5},
    {"C_dtatools_arrow_datasig",
     (DL_FUNC) &C_dtatools_arrow_datasig, 1},
    {"C_dtatools_write_path_kind",
     (DL_FUNC) &C_dtatools_write_path_kind, 1},
    {"C_dtatools_write_string_plan",
     (DL_FUNC) &C_dtatools_write_string_plan, 1},
    {"C_dtatools_ephemeral_altstring",
     (DL_FUNC) &C_dtatools_ephemeral_altstring, 1},
    {"C_dtatools_construct_numeric",
     (DL_FUNC) &C_dtatools_construct_numeric, 3},
    {"C_dtatools_gather_numeric",
     (DL_FUNC) &C_dtatools_gather_numeric, 4},
    {"C_dtatools_gather_numeric_columns",
     (DL_FUNC) &C_dtatools_gather_numeric_columns, 4},
    {"C_dtatools_is_numeric_altrep",
     (DL_FUNC) &C_dtatools_is_numeric_altrep, 1},
    {"C_dtatools_is_altrep", (DL_FUNC) &C_dtatools_is_altrep, 1},
    {"C_dtatools_metadata_copy", (DL_FUNC) &C_dtatools_metadata_copy, 1},
    {"C_dtatools_metadata_view", (DL_FUNC) &C_dtatools_metadata_view, 1},
    {"C_dtatools_mark_reference_data",
     (DL_FUNC) &C_dtatools_mark_reference_data, 3},
    {"C_dtatools_deep_copy_value",
     (DL_FUNC) &C_dtatools_deep_copy_value, 1},
    {"C_dtatools_reference_contents",
     (DL_FUNC) &C_dtatools_reference_contents, 1},
    {"C_dtatools_reference_row_reads",
     (DL_FUNC) &C_dtatools_reference_row_reads, 1},
    {"C_dtatools_inject_reference_write_interrupt",
     (DL_FUNC) &C_dtatools_inject_reference_write_interrupt, 1},
    {"C_dtatools_mutation_rows",
     (DL_FUNC) &C_dtatools_mutation_rows, 2},
    {"C_dtatools_patch_vector",
     (DL_FUNC) &C_dtatools_patch_vector, 3},
    {"C_dtatools_patch_data_column",
     (DL_FUNC) &C_dtatools_patch_data_column, 5},
    {"C_dtatools_set_data_column",
     (DL_FUNC) &C_dtatools_set_data_column, 3},
    {"C_dtatools_can_select_data_columns",
     (DL_FUNC) &C_dtatools_can_select_data_columns, 2},
    {"C_dtatools_select_data_columns",
     (DL_FUNC) &C_dtatools_select_data_columns, 6},
    {"C_dtatools_generate_numeric",
     (DL_FUNC) &C_dtatools_generate_numeric, 6},
    {"C_dtatools_generate_character",
     (DL_FUNC) &C_dtatools_generate_character, 5},
    {"C_dtatools_is_unmaterialized_numeric_altrep",
     (DL_FUNC) &C_dtatools_is_unmaterialized_numeric_altrep, 1},
    {"C_dtatools_is_unmaterialized_dictstring",
     (DL_FUNC) &C_dtatools_is_unmaterialized_dictstring, 1},
    {"C_dtatools_dictstring_cached_count",
     (DL_FUNC) &C_dtatools_dictstring_cached_count, 1},
    {"C_dtatools_numeric_storage_matches",
     (DL_FUNC) &C_dtatools_numeric_storage_matches, 3},
    {"C_dtatools_force_altrep_materialization",
     (DL_FUNC) &C_dtatools_force_altrep_materialization, 1},
    {"C_dtatools_mutate_first_numeric_altrep",
     (DL_FUNC) &C_dtatools_mutate_first_numeric_altrep, 2},
    {"C_dtatools_mutate_first_dictstring_altrep",
     (DL_FUNC) &C_dtatools_mutate_first_dictstring_altrep, 2},
    {"C_dtatools_metadata_proxy_depth",
     (DL_FUNC) &C_dtatools_metadata_proxy_depth, 1},
    {"C_dtatools_metadata_proxy_aggregate_mask",
     (DL_FUNC) &C_dtatools_metadata_proxy_aggregate_mask, 1},
    {"C_dtatools_has_tagged_na", (DL_FUNC) &C_dtatools_has_tagged_na, 1},
    {"C_dtatools_tagged_missing",
     (DL_FUNC) &C_dtatools_tagged_missing, 1},
    {"C_dtatools_missing_tag", (DL_FUNC) &C_dtatools_missing_tag, 1},
    {"C_dtatools_is_tagged_missing",
     (DL_FUNC) &C_dtatools_is_tagged_missing, 2},
    {"C_dtatools_is_missing", (DL_FUNC) &C_dtatools_is_missing, 1},
    {"C_dtatools_factorize_numeric",
     (DL_FUNC) &C_dtatools_factorize_numeric, 3},
    {"C_dtatools_missing_codes",
     (DL_FUNC) &C_dtatools_missing_codes, 1},
    {NULL, NULL, 0}
};

void attribute_visible R_init_dtatools(DllInfo *dll) {
    write_callback_condition_classes = PROTECT(Rf_allocVector(STRSXP, 2));
    SET_STRING_ELT(
        write_callback_condition_classes, 0, Rf_mkChar("interrupt")
    );
    SET_STRING_ELT(write_callback_condition_classes, 1, Rf_mkChar("error"));
    R_PreserveObject(write_callback_condition_classes);
    UNPROTECT(1);

    dtatools_numeric_class = R_make_altreal_class(
        "dtatools_numeric", "dtatools", dll
    );
    R_set_altrep_Unserialize_method(
        dtatools_numeric_class, numeric_unserialize
    );
    R_set_altrep_Serialized_state_method(
        dtatools_numeric_class, numeric_serialized_state
    );
    R_set_altrep_Duplicate_method(
        dtatools_numeric_class, numeric_duplicate
    );
    R_set_altrep_Length_method(dtatools_numeric_class, numeric_length);
    R_set_altvec_Extract_subset_method(
        dtatools_numeric_class, numeric_extract_subset
    );
    R_set_altvec_Dataptr_method(dtatools_numeric_class, numeric_dataptr);
    R_set_altvec_Dataptr_or_null_method(
        dtatools_numeric_class, numeric_dataptr_or_null
    );
    R_set_altreal_Elt_method(dtatools_numeric_class, numeric_value);
    R_set_altreal_Get_region_method(dtatools_numeric_class, numeric_region);
    R_set_altreal_No_NA_method(dtatools_numeric_class, numeric_no_na);
    R_set_altreal_Sum_method(dtatools_numeric_class, numeric_sum);
    R_set_altreal_Min_method(dtatools_numeric_class, numeric_min);
    R_set_altreal_Max_method(dtatools_numeric_class, numeric_max);
    dtatools_dictstring_class = R_make_altstring_class(
        "dtatools_dictstring", "dtatools", dll
    );
    R_set_altrep_Length_method(dtatools_dictstring_class, dictstring_length);
    R_set_altvec_Dataptr_method(dtatools_dictstring_class, dictstring_dataptr);
    R_set_altvec_Dataptr_or_null_method(
        dtatools_dictstring_class, dictstring_dataptr_or_null
    );
    R_set_altstring_Elt_method(dtatools_dictstring_class, dictstring_value);
    R_set_altstring_Set_elt_method(dtatools_dictstring_class, dictstring_set_elt);
    R_set_altstring_No_NA_method(dtatools_dictstring_class, dictstring_no_na);
    dtatools_ephemeral_string_class = R_make_altstring_class(
        "dtatools_ephemeral_string", "dtatools", dll
    );
    R_set_altrep_Length_method(
        dtatools_ephemeral_string_class, ephemeral_string_length
    );
    R_set_altstring_Elt_method(
        dtatools_ephemeral_string_class, ephemeral_string_value
    );
    dtatools_metadata_real_class = R_make_altreal_class(
        "dtatools_metadata_real", "dtatools", dll
    );
    R_set_altrep_Length_method(
        dtatools_metadata_real_class, metadata_proxy_length
    );
    R_set_altvec_Dataptr_method(
        dtatools_metadata_real_class, metadata_real_dataptr
    );
    R_set_altvec_Dataptr_or_null_method(
        dtatools_metadata_real_class, metadata_real_dataptr_or_null
    );
    R_set_altvec_Extract_subset_method(
        dtatools_metadata_real_class, metadata_real_extract_subset
    );
    R_set_altreal_Elt_method(
        dtatools_metadata_real_class, metadata_real_value
    );
    R_set_altreal_Get_region_method(
        dtatools_metadata_real_class, metadata_real_region
    );
    R_set_altreal_No_NA_method(
        dtatools_metadata_real_class, metadata_real_no_na
    );
    R_set_altreal_Sum_method(
        dtatools_metadata_real_class, metadata_real_sum
    );
    R_set_altreal_Min_method(
        dtatools_metadata_real_class, metadata_real_min
    );
    R_set_altreal_Max_method(
        dtatools_metadata_real_class, metadata_real_max
    );
    dtatools_metadata_string_class = R_make_altstring_class(
        "dtatools_metadata_string", "dtatools", dll
    );
    R_set_altrep_Length_method(
        dtatools_metadata_string_class, metadata_proxy_length
    );
    R_set_altvec_Dataptr_method(
        dtatools_metadata_string_class, metadata_string_dataptr
    );
    R_set_altvec_Dataptr_or_null_method(
        dtatools_metadata_string_class, metadata_string_dataptr_or_null
    );
    R_set_altstring_Elt_method(
        dtatools_metadata_string_class, metadata_string_value
    );
    R_set_altstring_Set_elt_method(
        dtatools_metadata_string_class, metadata_string_set_elt
    );
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
