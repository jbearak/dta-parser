#include <R.h>
#include <Rversion.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Altrep.h>
#include <R_ext/Utils.h>
#include <R_ext/Visibility.h>
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
extern void dtaparser_dictstring_free(void *);
extern int dtaparser_dictstring_bytes(
    void *, uint32_t, const char **, int *
);

typedef struct {
    uint32_t *value_ids;
    size_t length;
} dictstring_data;

static R_altrep_class_t dtaparser_dictstring_class;

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
    for (R_xlen_t id = 0; id < dictionary_length; id++) {
        if ((id & 16383) == 0) R_CheckUserInterrupt();
        (void) dictstring_cached_value(data, cache, (uint32_t) id);
    }
    const SEXP *dictionary_values = VECTOR_PTR_RO(cache);
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

static const R_CallMethodDef CallEntries[] = {
    {"C_dtaparser_metadata", (DL_FUNC) &C_dtaparser_metadata, 4},
    {"C_dtaparser_read", (DL_FUNC) &C_dtaparser_read, 7},
    {NULL, NULL, 0}
};

void attribute_visible R_init_dtaparser(DllInfo *dll) {
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
