#include <R.h>
#include <Rversion.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Altrep.h>
#include <R_ext/Utils.h>
#include <R_ext/Visibility.h>
#include <float.h>
#include <stdint.h>
#include <string.h>

extern SEXP dtaparser_metadata_rust(
    const char *, uint32_t, uint32_t, const char *, char **
);
extern SEXP dtaparser_read_rust(
    const char *, const int *, size_t, int, double, double, int, int,
    const char *, char **
);
extern void dtaparser_free_error(char *);
extern void dtaparser_numeric_free(void *);
extern void dtaparser_dictstring_free(void *);
extern int dtaparser_dictstring_bytes(
    void *, uint32_t, const char **, int *
);

typedef struct {
    uint32_t *value_ids;
    size_t length;
} dictstring_data;

static R_altrep_class_t dtaparser_dictstring_class;
static R_altrep_class_t dtaparser_numeric_class;

typedef struct {
    void *values;
    size_t length;
    int kind;
    int temporal;
    int format_version;
    int no_na;
} numeric_data;

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
        dtaparser_numeric_free(data);
    }
    R_SetExternalPtrProtected(external, R_NilValue);
}

static numeric_data *numeric_storage(SEXP value) {
    numeric_data *data = (numeric_data *) R_ExternalPtrAddr(
        R_altrep_data1(value)
    );
    if (data == NULL) Rf_error("dtaparser numeric data are no longer available");
    return data;
}

static R_xlen_t numeric_length(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return XLENGTH(materialized);
    size_t length = numeric_storage(value)->length;
    if (length > (size_t) R_XLEN_T_MAX) {
        Rf_error("dtaparser numeric vector is too long");
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

static int double_missing_offset(double value, int format_version) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    if (format_version == 105) {
        return bits == UINT64_C(0x54c0000000000000) ||
               (bits >= UINT64_C(0x7fe0000000000000) &&
                bits < UINT64_C(0x8000000000000000)) ? 0 : -1;
    }
    if (format_version <= 111) {
        return bits >= UINT64_C(0x7fe0000000000000) &&
               bits < UINT64_C(0x8000000000000000) ? 0 : -1;
    }
    if (bits < UINT64_C(0x7fe0000000000000) ||
        bits > UINT64_C(0x7fe01a0000000000)) {
        return -1;
    }
    uint64_t delta = bits - UINT64_C(0x7fe0000000000000);
    return delta % UINT64_C(0x0000010000000000) == 0
        ? (int) (delta / UINT64_C(0x0000010000000000)) : -1;
}

static double numeric_missing_value(int offset) {
    if (offset == 0) return NA_REAL;
    uint64_t letter = (uint64_t) ('a' + offset - 1);
    uint64_t bits = UINT64_C(0x7ff00000000007a2) | (letter << 32);
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static double numeric_observed_value(double value, int temporal) {
    if (temporal == 1) return value - 3653.0;
    if (temporal == 2) return value / 1000.0 - 315619200.0;
    return value;
}

static double numeric_value_at(numeric_data *data, size_t index) {
    double value;
    int missing;
    switch (data->kind) {
    case NUMERIC_BYTE: {
        int8_t raw;
        memcpy(&raw, (const char *) data->values + index, sizeof(raw));
        value = (double) raw;
        missing = byte_missing_offset(raw, data->format_version);
        break;
    }
    case NUMERIC_INT: {
        int16_t raw;
        memcpy(&raw, (const char *) data->values + index * sizeof(raw),
               sizeof(raw));
        value = (double) raw;
        missing = int_missing_offset(raw, data->format_version);
        break;
    }
    case NUMERIC_LONG: {
        int32_t raw;
        memcpy(&raw, (const char *) data->values + index * sizeof(raw),
               sizeof(raw));
        value = (double) raw;
        missing = long_missing_offset(raw, data->format_version);
        break;
    }
    case NUMERIC_FLOAT: {
        float raw;
        memcpy(&raw, (const char *) data->values + index * sizeof(raw),
               sizeof(raw));
        value = (double) raw;
        missing = float_missing_offset(raw, data->format_version);
        break;
    }
    case NUMERIC_DOUBLE: {
        double raw;
        memcpy(&raw, (const char *) data->values + index * sizeof(raw),
               sizeof(raw));
        value = raw;
        missing = double_missing_offset(raw, data->format_version);
        break;
    }
    default:
        Rf_error("invalid dtaparser numeric storage kind");
    }
    return missing >= 0
        ? numeric_missing_value(missing)
        : numeric_observed_value(value, data->temporal);
}

static double numeric_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return REAL_ELT(materialized, index);
    numeric_data *data = numeric_storage(value);
    if (index < 0 || (size_t) index >= data->length) {
        Rf_error("invalid dtaparser numeric-vector index");
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
    for (size_t offset = 0; offset < length; offset++) {
        if ((offset & 16383) == 0) R_CheckUserInterrupt();
        output[offset] = numeric_value_at(data, (size_t) index + offset);
    }
    return (R_xlen_t) length;
}

static SEXP numeric_materialize(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return materialized;
    numeric_data *data = numeric_storage(value);
    materialized = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) data->length));
    double *output = REAL(materialized);
    for (size_t index = 0; index < data->length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        output[index] = numeric_value_at(data, index);
    }
    R_set_altrep_data2(value, materialized);
    numeric_finalize(R_altrep_data1(value));
    UNPROTECT(1);
    return materialized;
}

static void *numeric_dataptr(SEXP value, Rboolean writeable) {
    SEXP materialized = numeric_materialize(value);
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
    return numeric_storage(value)->no_na;
}

static SEXP numeric_sum(SEXP value, Rboolean na_rm) {
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    numeric_data *data = numeric_storage(value);
    long double sum = 0.0;
    for (size_t index = 0; index < data->length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        double element = numeric_value_at(data, index);
        if (!na_rm || !ISNAN(element)) sum += element;
    }
    if (sum > DBL_MAX) return Rf_ScalarReal(R_PosInf);
    if (sum < -DBL_MAX) return Rf_ScalarReal(R_NegInf);
    return Rf_ScalarReal((double) sum);
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
        dtaparser_numeric_class, external, R_NilValue
    ));
    R_PreserveObject(result);
    context->result = result;
    UNPROTECT(2);
}

int dtaparser_make_numeric(
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

static void dictstring_finalize(SEXP external) {
    void *data = R_ExternalPtrAddr(external);
    if (data != NULL) {
        R_ClearExternalPtr(external);
        dtaparser_dictstring_free(data);
    }
    R_SetExternalPtrProtected(external, R_NilValue);
}

static dictstring_data *dictstring_storage(SEXP value) {
    SEXP external = R_altrep_data1(value);
    dictstring_data *data = (dictstring_data *) R_ExternalPtrAddr(external);
    if (data == NULL) Rf_error("dtaparser string indices are no longer available");
    return data;
}

static SEXP dictstring_cache(SEXP value) {
    SEXP cache = R_ExternalPtrProtected(R_altrep_data1(value));
    if (TYPEOF(cache) != VECSXP) {
        Rf_error("dtaparser string cache is no longer available");
    }
    return cache;
}

static SEXP dictstring_cached_value(
    dictstring_data *data, SEXP cache, uint32_t id
) {
    if ((R_xlen_t) id >= XLENGTH(cache)) {
        Rf_error("invalid dtaparser string-dictionary index");
    }
    SEXP cached = VECTOR_ELT(cache, (R_xlen_t) id);
    if (cached != R_NilValue) return cached;

    const char *bytes = NULL;
    int length = 0;
    if (!dtaparser_dictstring_bytes(data, id, &bytes, &length) ||
        bytes == NULL || length < 0) {
        Rf_error("invalid dtaparser string-dictionary value");
    }
    cached = Rf_mkCharLenCE(bytes, length, CE_UTF8);
    SET_VECTOR_ELT(cache, (R_xlen_t) id, cached);
    return cached;
}

static R_xlen_t dictstring_length(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return XLENGTH(materialized);
    size_t length = dictstring_storage(value)->length;
    if (length > (size_t) R_XLEN_T_MAX) {
        Rf_error("dtaparser string vector is too long");
    }
    return (R_xlen_t) length;
}

static SEXP dictstring_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return STRING_ELT(materialized, index);
    dictstring_data *data = dictstring_storage(value);
    if (index < 0 || (size_t) index >= data->length) {
        Rf_error("invalid dtaparser string-vector index");
    }
    SEXP cache = dictstring_cache(value);
    uint32_t id = data->value_ids[index];
    return dictstring_cached_value(data, cache, id);
}

static SEXP dictstring_materialize(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return materialized;

    dictstring_data *data = dictstring_storage(value);
    SEXP cache = dictstring_cache(value);
    R_xlen_t dictionary_length = XLENGTH(cache);
    SEXP *dictionary_values = (SEXP *) R_alloc(
        (R_SIZE_T) dictionary_length, (int) sizeof(SEXP)
    );
    for (R_xlen_t id = 0; id < dictionary_length; id++) {
        if ((id & 16383) == 0) R_CheckUserInterrupt();
        dictionary_values[id] = dictstring_cached_value(
            data, cache, (uint32_t) id
        );
    }
    materialized = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t) data->length));
    for (size_t index = 0; index < data->length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        uint32_t id = data->value_ids[index];
        if ((R_xlen_t) id >= dictionary_length) {
            Rf_error("invalid dtaparser string-dictionary index");
        }
        SET_STRING_ELT(
            materialized, (R_xlen_t) index,
            dictionary_values[id]
        );
    }
    R_set_altrep_data2(value, materialized);
    dictstring_finalize(R_altrep_data1(value));
    UNPROTECT(1);
    return materialized;
}

static void *dictstring_dataptr(SEXP value, Rboolean writeable) {
    (void) writeable;
    SEXP materialized = dictstring_materialize(value);
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
    SET_STRING_ELT(dictstring_materialize(value), index, replacement);
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
        dtaparser_dictstring_class, external, R_NilValue
    ));
    R_PreserveObject(result);
    context->result = result;
    UNPROTECT(3);
}

int dtaparser_make_dictstring(
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

int dtaparser_alloc_vector(int type, R_xlen_t length, SEXP *result) {
    alloc_vector_context context = {type, length, NULL};
    int ok = R_ToplevelExec(alloc_vector_call, &context);
    if (ok && result != NULL) *result = context.result;
    return ok;
}

void dtaparser_release_object(SEXP object) {
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

int dtaparser_make_char(
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

int dtaparser_install(const char *name, SEXP *result) {
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

int dtaparser_set_attrib(SEXP object, SEXP name, SEXP value) {
    set_attrib_context context = {object, name, value};
    return R_ToplevelExec(set_attrib_call, &context);
}

static void check_interrupt(void *unused) {
    (void) unused;
    R_CheckUserInterrupt();
}

int dtaparser_check_interrupt(void) {
    return R_ToplevelExec(check_interrupt, NULL) ? 0 : 1;
}

static void fail_from_rust(char *message) {
    char local[4096];
    if (message == NULL) {
        Rf_error("native dtaparser call failed");
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
    dtaparser_free_error(message);
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

SEXP C_dtaparser_metadata(
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
    SEXP result = dtaparser_metadata_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)),
        (uint32_t) INTEGER(column_start)[0],
        (uint32_t) INTEGER(column_count)[0],
        optional_encoding(encoding), &error
    );
    if (result == NULL) fail_from_rust(error);
    return result;
}

SEXP C_dtaparser_read(
    SEXP path, SEXP columns, SEXP skip, SEXP n_max, SEXP direct_to_r,
    SEXP threads, SEXP encoding
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
    char *error = NULL;
    SEXP result = dtaparser_read_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)),
        all_columns ? NULL : INTEGER(columns),
        all_columns ? 0 : (size_t) XLENGTH(columns),
        all_columns,
        REAL(skip)[0],
        REAL(n_max)[0],
        LOGICAL(direct_to_r)[0],
        INTEGER(threads)[0],
        optional_encoding(encoding),
        &error
    );
    if (result == NULL) fail_from_rust(error);
    return result;
}

SEXP C_dtaparser_is_numeric_altrep(SEXP value) {
    return Rf_ScalarLogical(R_altrep_inherits(value, dtaparser_numeric_class));
}

static const R_CallMethodDef CallEntries[] = {
    {"C_dtaparser_metadata", (DL_FUNC) &C_dtaparser_metadata, 4},
    {"C_dtaparser_read", (DL_FUNC) &C_dtaparser_read, 7},
    {"C_dtaparser_is_numeric_altrep",
     (DL_FUNC) &C_dtaparser_is_numeric_altrep, 1},
    {NULL, NULL, 0}
};

void attribute_visible R_init_dtaparser(DllInfo *dll) {
    dtaparser_numeric_class = R_make_altreal_class(
        "dtaparser_numeric", "dtaparser", dll
    );
    R_set_altrep_Length_method(dtaparser_numeric_class, numeric_length);
    R_set_altvec_Dataptr_method(dtaparser_numeric_class, numeric_dataptr);
    R_set_altvec_Dataptr_or_null_method(
        dtaparser_numeric_class, numeric_dataptr_or_null
    );
    R_set_altreal_Elt_method(dtaparser_numeric_class, numeric_value);
    R_set_altreal_Get_region_method(dtaparser_numeric_class, numeric_region);
    R_set_altreal_No_NA_method(dtaparser_numeric_class, numeric_no_na);
    R_set_altreal_Sum_method(dtaparser_numeric_class, numeric_sum);
    dtaparser_dictstring_class = R_make_altstring_class(
        "dtaparser_dictstring", "dtaparser", dll
    );
    R_set_altrep_Length_method(dtaparser_dictstring_class, dictstring_length);
    R_set_altvec_Dataptr_method(dtaparser_dictstring_class, dictstring_dataptr);
    R_set_altvec_Dataptr_or_null_method(
        dtaparser_dictstring_class, dictstring_dataptr_or_null
    );
    R_set_altstring_Elt_method(dtaparser_dictstring_class, dictstring_value);
    R_set_altstring_Set_elt_method(dtaparser_dictstring_class, dictstring_set_elt);
    R_set_altstring_No_NA_method(dtaparser_dictstring_class, dictstring_no_na);
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
