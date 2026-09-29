/* Exact ordinary-REAL roots for the existing generated-column reader.
   No public R evaluation, proxy dispatch or per-call admission cache. */
#include "dtatools-internal.h"
#include <stdio.h>

#if defined(__APPLE__) && defined(__aarch64__) && \
    R_VERSION == R_Version(4, 6, 1) && R_SVN_REVISION == 90187
#include <dlfcn.h>
#define GENERATED_CORE_WRAPPER_PIN 1
#else
#define GENERATED_CORE_WRAPPER_PIN 0
#endif

typedef SEXP (*generated_core_function)(SEXP);
static generated_core_function generated_altrep_class;
static SEXP generated_real_wrapper_class;

#if GENERATED_CORE_WRAPPER_PIN
/* Same cold FNV64 identity read as probe-profile-file-fingerprint.c.
   Build identity only; no assertion of adversarial file integrity. */
static int generated_r_image_matches(const char *path) {
    FILE *stream = path == NULL ? NULL : fopen(path, "rb");
    if (stream == NULL) return 0;
    uint64_t hash = UINT64_C(14695981039346656037);
    unsigned char block[65536];
    size_t length;
    while ((length = fread(block, 1, sizeof(block), stream)) != 0) {
        for (size_t index = 0; index < length; index++) {
            hash ^= block[index];
            hash *= UINT64_C(1099511628211);
        }
    }
    int failed = ferror(stream);
    if (fclose(stream) != 0) failed = 1;
    return !failed && hash == UINT64_C(0x080247de6d9aa85c);
}
#endif

void initialize_generated_real_reader(void) {
    generated_altrep_class = NULL;
    generated_real_wrapper_class = NULL;
#if GENERATED_CORE_WRAPPER_PIN
    if (sizeof(void *) != 8 || sizeof(double) != 8 ||
        DBL_MANT_DIG != 53 || DBL_MAX_EXP != 1024) return;
    void *try_wrap_address = dlsym(RTLD_DEFAULT, "R_tryWrap");
    void *class_address = dlsym(RTLD_DEFAULT, "ALTREP_CLASS");
    Dl_info allocator_image, wrapper_image, class_image;
    if (try_wrap_address == NULL || class_address == NULL ||
        !dladdr((void *) &Rf_allocVector, &allocator_image) ||
        !dladdr(try_wrap_address, &wrapper_image) ||
        !dladdr(class_address, &class_image) ||
        allocator_image.dli_fbase != wrapper_image.dli_fbase ||
        allocator_image.dli_fbase != class_image.dli_fbase ||
        !generated_r_image_matches(allocator_image.dli_fname)) return;

    generated_core_function try_wrap =
        (generated_core_function) try_wrap_address;
    generated_core_function class_of =
        (generated_core_function) class_address;
    /* This internally created plain seed has no callbacks or attributes.
       Both experimental APIs are resolved dynamically from qualified libR. */
    SEXP seed = PROTECT(Rf_allocVector(REALSXP, 0));
    SEXP wrapper = PROTECT(try_wrap(seed));
    if (TYPEOF(wrapper) == REALSXP && ALTREP(wrapper) &&
        R_altrep_data1(wrapper) == seed) {
        SEXP class = PROTECT(class_of(wrapper));
        if (class != R_NilValue) {
            R_PreserveObject(class);
            generated_real_wrapper_class = class;
            generated_altrep_class = class_of;
        }
        UNPROTECT(1);
    }
    UNPROTECT(2);
#endif
}

void release_generated_real_reader(void) {
    if (generated_real_wrapper_class != NULL)
        R_ReleaseObject(generated_real_wrapper_class);
    generated_real_wrapper_class = NULL;
    generated_altrep_class = NULL;
}

/* Return only a callback-free ordinary or package-owned REAL leaf.
   Do not inspect an unknown ALTREP's data1 or infer its class by name. */
SEXP generated_real_reader_leaf(SEXP value) {
    for (int depth = 0; depth < 32; depth++) {
        if (TYPEOF(value) != REALSXP) return R_NilValue;
        if (!ALTREP(value) || owned_real(value)) return value;
        if (generated_real_wrapper_class == NULL ||
            generated_altrep_class == NULL ||
            generated_altrep_class(value) != generated_real_wrapper_class)
            return R_NilValue;
        value = R_altrep_data1(value);
    }
    return R_NilValue;
}
