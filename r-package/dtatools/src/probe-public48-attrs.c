/* Scratch pinned-R public closure attribute/debug check.  In particular,
   do not link RDEBUG: it is absent from R's installed API declaration. */
#include <R.h>
#include <Rinternals.h>
#if defined(__APPLE__) && defined(__aarch64__)
#include <dlfcn.h>
#endif
#include <stdint.h>
#include <string.h>

typedef int (*debug_fn_t)(SEXP);
static debug_fn_t debug_fn;
static int debug_initialized;

/* R 4.6.1 r90187 aarch64/Darwin: Defn.h puts RSTEP in sxpinfo.spare,
   bit 27 of the first word. This is a pinned private-layout read. */
static int step_bit(SEXP fn) {
#if defined(__APPLE__) && defined(__aarch64__)
    if (sizeof(void*) != 8) return -1;
    uint32_t bits=0;
    memcpy(&bits,fn,sizeof(bits));
    return (bits & UINT32_C(0x08000000)) != 0;
#else
    (void)fn;
    return -1;
#endif
}
static int step_supported(void) {
#if defined(__APPLE__) && defined(__aarch64__)
    return sizeof(void*) == 8;
#else
    return 0;
#endif
}

int dtatools_probe_public_debugged(SEXP fn) {
    if (!debug_initialized) {
#if defined(__APPLE__) && defined(__aarch64__)
        debug_fn = (debug_fn_t)dlsym(RTLD_DEFAULT, "RDEBUG");
#endif
        debug_initialized = 1;
    }
    if (!debug_fn || !step_supported() ||
        (TYPEOF(fn) != CLOSXP && TYPEOF(fn) != ENVSXP)) return -1;
    int step=TYPEOF(fn)==CLOSXP ? step_bit(fn) : 0;
    return step<0 ? -1 : (debug_fn(fn) || step ? 1 : 0);
}

SEXP C_probe_public48_debug_state(SEXP fn) {
    int state = dtatools_probe_public_debugged(fn);
    return Rf_ScalarInteger(state);
}

SEXP C_probe_public48_same_pointer(SEXP a, SEXP b) {
    return Rf_ScalarLogical(a == b);
}

SEXP C_probe_public48_debug_available(SEXP unused) {
    (void)unused;
    if (!debug_initialized) {
#if defined(__APPLE__) && defined(__aarch64__)
        debug_fn = (debug_fn_t)dlsym(RTLD_DEFAULT, "RDEBUG");
#endif
        debug_initialized = 1;
    }
    return Rf_ScalarLogical(debug_fn != NULL && step_supported());
}

typedef struct { int n; SEXP tag[3], value[3]; } attrs_t;
static SEXP collect(SEXP tag, SEXP value, void *ptr) {
    attrs_t *out = ptr;
    if (out->n >= 3 || TYPEOF(tag) != SYMSXP || ANY_ATTRIB(tag))
        return R_NilValue;
    out->tag[out->n] = tag;
    out->value[out->n++] = value;
    return NULL;
}
static SEXP state_value(SEXP state, const char *name) {
    SEXP sym = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(sym, state);
    if (kind != R_BindingTypeValue && kind != R_BindingTypeForced)
        return R_NilValue;
    return R_getVarEx(sym, state, FALSE, R_NilValue);
}
static int attr_same(SEXP fn, SEXP expected, SEXP saved_sourcefile) {
    attrs_t live = {.n=0}, frozen = {.n=0};
    if (R_mapAttrib(fn, collect, &live) != NULL ||
        R_mapAttrib(expected, collect, &frozen) != NULL ||
        live.n != frozen.n) return 0;
    if (live.n == 0) return saved_sourcefile == R_NilValue;
    SEXP srcref = Rf_install("srcref");
    if (live.n != 1 || live.tag[0] != srcref ||
        frozen.tag[0] != srcref) return 0;
    SEXP x = live.value[0], y = frozen.value[0];
    if (TYPEOF(x) != INTSXP || TYPEOF(y) != INTSXP ||
        ALTREP(x) || ALTREP(y) || XLENGTH(x) != 8 || XLENGTH(y) != 8 ||
        memcmp(INTEGER(x), INTEGER(y), 8*sizeof(int))) return 0;
    attrs_t a = {.n=0}, b = {.n=0};
    if (R_mapAttrib(x, collect, &a) != NULL ||
        R_mapAttrib(y, collect, &b) != NULL ||
        a.n != 2 || b.n != 2) return 0;
    SEXP clsx=R_NilValue, clsy=R_NilValue, sfx=R_NilValue, sfy=R_NilValue;
    SEXP srcfile = Rf_install("srcfile");
    for (int i=0; i<2; ++i) {
        if (a.tag[i] == R_ClassSymbol) clsx = a.value[i];
        if (b.tag[i] == R_ClassSymbol) clsy = b.value[i];
        if (a.tag[i] == srcfile) sfx = a.value[i];
        if (b.tag[i] == srcfile) sfy = b.value[i];
    }
    if (TYPEOF(sfx) != ENVSXP || TYPEOF(sfy) != ENVSXP ||
        sfx != saved_sourcefile ||
        TYPEOF(clsx) != STRSXP || TYPEOF(clsy) != STRSXP ||
        ALTREP(clsx) || ALTREP(clsy) ||
        XLENGTH(clsx) != 1 || XLENGTH(clsy) != 1 ||
        STRING_ELT(clsx,0) != STRING_ELT(clsy,0)) return 0;
    return 1;
}
int dtatools_probe_public48_attrs_debug(SEXP state) {
    if (TYPEOF(state) != ENVSXP || !debug_fn || !step_supported())
        return 0;
    SEXP debug_supported=state_value(state,"debug_supported");
    if (TYPEOF(debug_supported)!=LGLSXP || XLENGTH(debug_supported)!=1 ||
        LOGICAL(debug_supported)[0]!=TRUE) return 0;
    SEXP live=state_value(state,"live");
    SEXP expected=state_value(state,"compiled");
    SEXP sourcefiles=state_value(state,"sourcefiles");
    if (TYPEOF(live)!=VECSXP || TYPEOF(expected)!=VECSXP ||
        TYPEOF(sourcefiles)!=VECSXP || XLENGTH(live)!=58 ||
        XLENGTH(expected)!=58 || XLENGTH(sourcefiles)!=58)
        return 0;
    for (int i=0; i<58; ++i) {
        SEXP fn=VECTOR_ELT(live,i);
        if (TYPEOF(fn)!=CLOSXP || debug_fn(fn) || step_bit(fn)!=0 ||
            !attr_same(fn,VECTOR_ELT(expected,i),VECTOR_ELT(sourcefiles,i)))
            return 0;
    }
    return 1;
}
