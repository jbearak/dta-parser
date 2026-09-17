/* Calls the Rust reader makes back into R. Each one runs inside
   R_ToplevelExec so a long jump from R stays on the C side of the bridge. */
#include "dtatools-internal.h"

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

int dtatools_is_null(SEXP value) {
    return Rf_isNull(value);
}

typedef struct {
    SEXP object;
} preserve_object_context;

static void preserve_object_call(void *data) {
    preserve_object_context *context = (preserve_object_context *) data;
    R_PreserveObject(context->object);
}

int dtatools_preserve_object(SEXP object) {
    if (object == NULL) return 0;
    preserve_object_context context = {object};
    return R_ToplevelExec(preserve_object_call, &context);
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

void fail_from_rust(char *message) {
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
