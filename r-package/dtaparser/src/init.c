#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Altrep.h>
#include <R_ext/Utils.h>
#include <R_ext/Visibility.h>
#include <stdint.h>
#include <limits.h>
#include <string.h>

extern SEXP dtaparser_metadata_rust(
    const char *, uint32_t, uint32_t, const char *, char **
);
extern SEXP dtaparser_read_rust(
    const char *, const int *, size_t, int, double, double, int, const char *,
    char **
);
extern void dtaparser_free_error(char *);
extern void dtaparser_altstring_free(void *);
extern size_t dtaparser_altstring_length(const void *);
extern int dtaparser_altstring_value(
    const void *, size_t, const char **, int *
);
extern int dtaparser_altstring_view(
    const void *, const unsigned char **, const void **, int *, size_t *
);

static R_altrep_class_t dtaparser_altstring_class;

static void altstring_finalize(SEXP external) {
    void *data = R_ExternalPtrAddr(external);
    if (data == NULL) return;
    R_ClearExternalPtr(external);
    dtaparser_altstring_free(data);
}

static void *altstring_data(SEXP value) {
    SEXP external = R_altrep_data1(value);
    void *data = R_ExternalPtrAddr(external);
    if (data == NULL) Rf_error("dtaparser string data are no longer available");
    return data;
}

static R_xlen_t altstring_length(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return XLENGTH(materialized);
    size_t length = dtaparser_altstring_length(altstring_data(value));
    if (length > (size_t) R_XLEN_T_MAX) {
        Rf_error("dtaparser string vector is too long");
    }
    return (R_xlen_t) length;
}

static SEXP altstring_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return STRING_ELT(materialized, index);
    const char *bytes = NULL;
    int length = 0;
    if (index < 0 || !dtaparser_altstring_value(
        altstring_data(value), (size_t) index, &bytes, &length
    )) {
        Rf_error("invalid dtaparser string-vector index");
    }
    return Rf_mkCharLenCE(bytes, length, CE_UTF8);
}

static SEXP altstring_materialize(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return materialized;

    R_xlen_t length = altstring_length(value);
    materialized = PROTECT(Rf_allocVector(STRSXP, length));
    const unsigned char *bytes = NULL;
    const void *ends = NULL;
    int end_width = 0;
    size_t view_length = 0;
    if (!dtaparser_altstring_view(
        altstring_data(value), &bytes, &ends, &end_width, &view_length
    ) || view_length != (size_t) length) {
        Rf_error("invalid dtaparser string storage");
    }
    uint64_t start = 0;
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        uint64_t end = end_width == 4
            ? (uint64_t) ((const uint32_t *) ends)[index]
            : ((const uint64_t *) ends)[index];
        if (end < start || end - start > INT_MAX) {
            Rf_error("invalid dtaparser string offsets");
        }
        SET_STRING_ELT(materialized, index, Rf_mkCharLenCE(
            (const char *) (bytes + start), (int) (end - start), CE_UTF8
        ));
        start = end;
    }
    R_set_altrep_data2(value, materialized);
    altstring_finalize(R_altrep_data1(value));
    UNPROTECT(1);
    return materialized;
}

static void *altstring_dataptr(SEXP value, Rboolean writeable) {
    (void) writeable;
    return DATAPTR_RW(altstring_materialize(value));
}

static const void *altstring_dataptr_or_null(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? NULL : DATAPTR_OR_NULL(materialized);
}

static void altstring_set_elt(SEXP value, R_xlen_t index, SEXP replacement) {
    SET_STRING_ELT(altstring_materialize(value), index, replacement);
}

static int altstring_no_na(SEXP value) {
    (void) value;
    return 1;
}

typedef struct {
    void *data;
    SEXP external;
    SEXP result;
} make_altstring_context;

static void make_altstring_call(void *payload) {
    make_altstring_context *context = (make_altstring_context *) payload;
    SEXP external = PROTECT(R_MakeExternalPtr(
        context->data, R_NilValue, R_NilValue
    ));
    context->external = external;
    SEXP result = PROTECT(R_new_altrep(
        dtaparser_altstring_class, external, R_NilValue
    ));
    R_RegisterCFinalizerEx(external, altstring_finalize, TRUE);
    R_PreserveObject(result);
    context->result = result;
    UNPROTECT(2);
}

int dtaparser_make_altstring(void *data, SEXP *result) {
    make_altstring_context context = {data, NULL, NULL};
    int ok = R_ToplevelExec(make_altstring_call, &context);
    if (!ok && context.external != NULL) R_ClearExternalPtr(context.external);
    if (ok && result != NULL) *result = context.result;
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
    SEXP encoding
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
    char *error = NULL;
    SEXP result = dtaparser_read_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)),
        all_columns ? NULL : INTEGER(columns),
        all_columns ? 0 : (size_t) XLENGTH(columns),
        all_columns,
        REAL(skip)[0],
        REAL(n_max)[0],
        LOGICAL(direct_to_r)[0],
        optional_encoding(encoding),
        &error
    );
    if (result == NULL) fail_from_rust(error);
    return result;
}

static const R_CallMethodDef CallEntries[] = {
    {"C_dtaparser_metadata", (DL_FUNC) &C_dtaparser_metadata, 4},
    {"C_dtaparser_read", (DL_FUNC) &C_dtaparser_read, 6},
    {NULL, NULL, 0}
};

void attribute_visible R_init_dtaparser(DllInfo *dll) {
    dtaparser_altstring_class = R_make_altstring_class(
        "dtaparser_altstring", "dtaparser", dll
    );
    R_set_altrep_Length_method(dtaparser_altstring_class, altstring_length);
    R_set_altvec_Dataptr_method(dtaparser_altstring_class, altstring_dataptr);
    R_set_altvec_Dataptr_or_null_method(
        dtaparser_altstring_class, altstring_dataptr_or_null
    );
    R_set_altstring_Elt_method(dtaparser_altstring_class, altstring_value);
    R_set_altstring_Set_elt_method(dtaparser_altstring_class, altstring_set_elt);
    R_set_altstring_No_NA_method(dtaparser_altstring_class, altstring_no_na);
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
