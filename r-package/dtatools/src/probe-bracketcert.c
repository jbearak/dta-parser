#include <R.h>
#include <Rinternals.h>
#include <Rversion.h>
#include <R_ext/Altrep.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
extern int dtatools_probe_public_debugged(SEXP fn);

/* Scratch-only exact same-pointer graph snapshot. A changed pointer declines. */
#define SNAP_MAX_NODES 131072
#define SNAP_TABLE_SIZE 262144
#define SNAP_MAX_BYTES ((size_t) 100000000)

typedef struct { SEXP tag, value; } snap_attr;
typedef struct {
    SEXP value, a, b, c;
    SEXPTYPE type;
    int object, s4, attr_count;
    R_xlen_t length;
    snap_attr *attrs;
    SEXP *elements;
    void *bytes;
    size_t byte_count;
} snap_node;
typedef struct {
    SEXP env;
    int function_count, node_count, shallow_bracket;
    SEXP *functions, *symbols, *bodies, *formals, *closure_envs;
    snap_node *nodes;
    int *table;
} snap_profile;

static void snap_free(SEXP ext) {
    snap_profile *p = R_ExternalPtrAddr(ext);
    if (p == NULL) return;
    R_ClearExternalPtr(ext);
    for (int i = 0; i < p->node_count; i++) {
        free(p->nodes[i].attrs);
        free(p->nodes[i].elements);
        free(p->nodes[i].bytes);
    }
    free(p->functions);
    free(p->symbols);
    free(p->bodies);
    free(p->formals);
    free(p->closure_envs);
    free(p->nodes);
    free(p->table);
    free(p);
}

static size_t snap_hash(SEXP value) {
    uintptr_t x = (uintptr_t) value;
    x ^= x >> 33;
    x *= UINT64_C(0xff51afd7ed558ccd);
    x ^= x >> 33;
    return (size_t) x & (SNAP_TABLE_SIZE - 1);
}

static int snap_visit(snap_profile *p, SEXP value, int depth);
typedef struct { snap_profile *p; snap_node *node; int ok, depth, index; } snap_attr_context;

static SEXP snap_count_attr(SEXP tag, SEXP value, void *context) {
    (void) tag; (void) value;
    (*(int *) context)++;
    return NULL;
}

static SEXP snap_build_attr(SEXP tag, SEXP value, void *context) {
    snap_attr_context *ctx = context;
    if (!ctx->ok || ctx->index >= ctx->node->attr_count || TYPEOF(tag) != SYMSXP) {
        ctx->ok = 0;
        return R_NilValue;
    }
    ctx->node->attrs[ctx->index].tag = tag;
    ctx->node->attrs[ctx->index].value = value;
    ctx->index++;
    if (!snap_visit(ctx->p, value, ctx->depth + 1)) ctx->ok = 0;
    return ctx->ok ? NULL : R_NilValue;
}

static int snap_save_bytes(snap_node *node, const void *source, size_t count) {
    if (count > SNAP_MAX_BYTES) return 0;
    node->bytes = malloc(count ? count : 1);
    if (node->bytes == NULL) return 0;
    memcpy(node->bytes, source, count);
    node->byte_count = count;
    return 1;
}

static int snap_visit(snap_profile *p, SEXP value, int depth) {
    if (depth > 256 || ALTREP(value)) return 0;
    size_t slot = snap_hash(value);
    for (size_t i = 0; i < SNAP_TABLE_SIZE; i++, slot = (slot + 1) & (SNAP_TABLE_SIZE - 1)) {
        int record = p->table[slot];
        if (record != 0) {
            if (p->nodes[record - 1].value == value) return 1;
            continue;
        }
        if (p->node_count >= SNAP_MAX_NODES) return 0;
        int index = p->node_count++;
        p->table[slot] = index + 1;
        snap_node *node = &p->nodes[index];
        node->value = value;
        node->type = TYPEOF(value);
        node->object = Rf_isObject(value);
        node->s4 = Rf_isS4(value);
        if (node->type == SYMSXP && ANY_ATTRIB(value)) return 0;
        if (node->type != CHARSXP && ANY_ATTRIB(value)) {
            int count = 0;
            R_mapAttrib(value, snap_count_attr, &count);
            if (count < 0 || count > 256) return 0;
            node->attr_count = count;
            node->attrs = calloc((size_t) count ? (size_t) count : 1, sizeof(snap_attr));
            if (node->attrs == NULL) return 0;
            snap_attr_context ctx = {p, node, 1, depth, 0};
            if (R_mapAttrib(value, snap_build_attr, &ctx) != NULL ||
                !ctx.ok || ctx.index != count) return 0;
        }
        switch (node->type) {
        case NILSXP: case SYMSXP: case ENVSXP: case CHARSXP:
        case BUILTINSXP: case SPECIALSXP: return 1;
        case LANGSXP: case LISTSXP: case DOTSXP:
            node->a = CAR(value); node->b = TAG(value); node->c = CDR(value);
            return snap_visit(p, node->a, depth + 1) &&
                   snap_visit(p, node->b, depth + 1) &&
                   snap_visit(p, node->c, depth + 1);
        case BCODESXP:
            node->a = CAR(value); node->b = TAG(value); node->c = CDR(value);
            return snap_visit(p, node->a, depth + 1) &&
                   snap_visit(p, node->b, depth + 1) &&
                   snap_visit(p, node->c, depth + 1);
        case CLOSXP:
            node->a = R_ClosureEnv(value);
            node->b = R_ClosureFormals(value);
            node->c = R_ClosureBody(value);
            return snap_visit(p, node->b, depth + 1) &&
                   (p->shallow_bracket == 2 ||
                    (p->shallow_bracket == 1 && value == p->functions[0]) ? 1 :
                    snap_visit(p, node->c, depth + 1));
        case LGLSXP: case INTSXP: {
            node->length = XLENGTH(value);
            if ((uint64_t) node->length > SIZE_MAX / sizeof(int)) return 0;
            return snap_save_bytes(node,
                node->type == LGLSXP ? (const void *) LOGICAL(value) : (const void *) INTEGER(value),
                (size_t) node->length * sizeof(int));
        }
        case REALSXP: {
            node->length = XLENGTH(value);
            if ((uint64_t) node->length > SIZE_MAX / sizeof(double)) return 0;
            return snap_save_bytes(node, REAL(value), (size_t) node->length * sizeof(double));
        }
        case CPLXSXP: {
            node->length = XLENGTH(value);
            if ((uint64_t) node->length > SIZE_MAX / sizeof(Rcomplex)) return 0;
            return snap_save_bytes(node, COMPLEX(value), (size_t) node->length * sizeof(Rcomplex));
        }
        case RAWSXP:
            node->length = XLENGTH(value);
            return snap_save_bytes(node, RAW(value), (size_t) node->length);
        case STRSXP: case VECSXP: case EXPRSXP:
            node->length = XLENGTH(value);
            if (node->length < 0 || node->length > SNAP_MAX_NODES) return 0;
            node->elements = calloc((size_t) node->length ? (size_t) node->length : 1,
                                    sizeof(SEXP));
            if (node->elements == NULL) return 0;
            for (R_xlen_t j = 0; j < node->length; j++) {
                SEXP child = node->type == STRSXP ? STRING_ELT(value, j) : VECTOR_ELT(value, j);
                node->elements[j] = child;
                if (!snap_visit(p, child, depth + 1)) return 0;
            }
            return 1;
        default: return 0;
        }
    }
    return 0;
}

static SEXP snap_new(SEXP functions, SEXP env, int shallow_bracket) {
    if (TYPEOF(functions) != VECSXP || ALTREP(functions) || TYPEOF(env) != ENVSXP ||
        XLENGTH(functions) == 0 || XLENGTH(functions) > 128) return R_NilValue;
    SEXP names = Rf_getAttrib(functions, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || XLENGTH(names) != XLENGTH(functions)) return R_NilValue;
    snap_profile *p = calloc(1, sizeof(*p));
    if (p == NULL) Rf_error("snapshot allocation failed");
    p->function_count = (int) XLENGTH(functions);
    p->shallow_bracket = shallow_bracket;
    p->env = env;
    SEXP ext = PROTECT(R_MakeExternalPtr(p, R_NilValue, functions));
    R_RegisterCFinalizerEx(ext, snap_free, TRUE);
    p->functions = calloc((size_t) p->function_count, sizeof(SEXP));
    p->symbols = calloc((size_t) p->function_count, sizeof(SEXP));
    p->bodies = calloc((size_t) p->function_count, sizeof(SEXP));
    p->formals = calloc((size_t) p->function_count, sizeof(SEXP));
    p->closure_envs = calloc((size_t) p->function_count, sizeof(SEXP));
    p->nodes = calloc(SNAP_MAX_NODES, sizeof(snap_node));
    p->table = calloc(SNAP_TABLE_SIZE, sizeof(int));
    if (p->functions == NULL || p->symbols == NULL || p->bodies == NULL ||
        p->formals == NULL || p->closure_envs == NULL ||
        p->nodes == NULL || p->table == NULL) {
        snap_free(ext); UNPROTECT(1); return R_NilValue;
    }
    int ok = 1;
    for (int i = 0; i < p->function_count; i++) {
        SEXP label = STRING_ELT(names, i);
        SEXP function = VECTOR_ELT(functions, i);
        if (label == NA_STRING || TYPEOF(function) != CLOSXP) { ok = 0; break; }
        p->functions[i] = function;
        p->symbols[i] = Rf_installTrChar(label);
        p->bodies[i] = R_ClosureBody(function);
        p->formals[i] = R_ClosureFormals(function);
        p->closure_envs[i] = R_ClosureEnv(function);
        if (!snap_visit(p, function, 0)) { ok = 0; break; }
    }
    if (!ok) { snap_free(ext); UNPROTECT(1); return R_NilValue; }
    SEXP roots = PROTECT(Rf_allocVector(VECSXP, p->node_count));
    for (int i = 0; i < p->node_count; i++) SET_VECTOR_ELT(roots, i, p->nodes[i].value);
    R_SetExternalPtrProtected(ext, roots);
    UNPROTECT(2);
    return ext;
}

SEXP C_snap_new(SEXP functions, SEXP env) {
    return snap_new(functions, env, 0);
}

SEXP C_snap_new_bracket(SEXP functions, SEXP env) {
    if (TYPEOF(functions) != VECSXP || XLENGTH(functions) != 1)
        return R_NilValue;
    return snap_new(functions, env, 1);
}

SEXP C_snap_new_shallow_all(SEXP functions, SEXP env) {
    return snap_new(functions, env, 2);
}

typedef struct { const snap_node *node; int index, ok; } snap_check_attr_context;
static SEXP snap_check_attr(SEXP tag, SEXP value, void *context) {
    snap_check_attr_context *ctx = context;
    if (ctx->index >= ctx->node->attr_count ||
        tag != ctx->node->attrs[ctx->index].tag ||
        value != ctx->node->attrs[ctx->index].value) ctx->ok = 0;
    ctx->index++;
    return ctx->ok ? NULL : R_NilValue;
}

static int snap_node_same(const snap_node *node) {
    SEXP value = node->value;
    if (TYPEOF(value) != node->type || ALTREP(value) ||
        Rf_isObject(value) != node->object || Rf_isS4(value) != node->s4) return 0;
    if (node->attr_count == 0) {
        if (node->type != CHARSXP && ANY_ATTRIB(value)) return 0;
    } else {
        if (!ANY_ATTRIB(value)) return 0;
        snap_check_attr_context ctx = {node, 0, 1};
        if (R_mapAttrib(value, snap_check_attr, &ctx) != NULL ||
            !ctx.ok || ctx.index != node->attr_count) return 0;
    }
    switch (node->type) {
    case NILSXP: case SYMSXP: case ENVSXP: case CHARSXP:
    case BUILTINSXP: case SPECIALSXP: return 1;
    case LANGSXP: case LISTSXP: case DOTSXP: case BCODESXP:
        return CAR(value) == node->a && TAG(value) == node->b && CDR(value) == node->c;
    case CLOSXP:
        return dtatools_probe_public_debugged(value) == 0 &&
               R_ClosureEnv(value) == node->a &&
               R_ClosureFormals(value) == node->b &&
               R_ClosureBody(value) == node->c;
    case LGLSXP: case INTSXP:
        return XLENGTH(value) == node->length &&
            memcmp(node->type == LGLSXP ? (const void *) LOGICAL(value) : (const void *) INTEGER(value),
                   node->bytes, node->byte_count) == 0;
    case REALSXP:
        return XLENGTH(value) == node->length &&
               memcmp(REAL(value), node->bytes, node->byte_count) == 0;
    case CPLXSXP:
        return XLENGTH(value) == node->length &&
               memcmp(COMPLEX(value), node->bytes, node->byte_count) == 0;
    case RAWSXP:
        return XLENGTH(value) == node->length &&
               memcmp(RAW(value), node->bytes, node->byte_count) == 0;
    case STRSXP: case VECSXP: case EXPRSXP:
        if (XLENGTH(value) != node->length) return 0;
        for (R_xlen_t i = 0; i < node->length; i++) {
            SEXP child = node->type == STRSXP ? STRING_ELT(value, i) : VECTOR_ELT(value, i);
            if (child != node->elements[i]) return 0;
        }
        return 1;
    default: return 0;
    }
}

int C_snap_check_raw(SEXP ext) {
    snap_profile *p = TYPEOF(ext) == EXTPTRSXP ? R_ExternalPtrAddr(ext) : NULL;
    if (p == NULL || TYPEOF(p->env) != ENVSXP) return 0;
    for (int i = 0; i < p->function_count; i++) {
        R_BindingType_t type = R_GetBindingType(p->symbols[i], p->env);
        if (type != R_BindingTypeValue && type != R_BindingTypeForced)
            return 0;
        if (R_getVar(p->symbols[i], p->env, FALSE) != p->functions[i])
            return 0;
    }
    for (int i = 0; i < p->node_count; i++)
        if (!snap_node_same(&p->nodes[i])) return 0;
    return 1;
}

/* Entry qualification checks the full reachable graph. Between admitted
   native steps, public R-level replacement and body<- alter one of these
   root identities. Direct writes inside an existing bytecode object are
   outside the approved compatibility boundary. */
int C_snap_check_roots_raw(SEXP ext) {
    snap_profile *p = TYPEOF(ext) == EXTPTRSXP ? R_ExternalPtrAddr(ext) : NULL;
    if (p == NULL || TYPEOF(p->env) != ENVSXP) return 0;
    for (int i = 0; i < p->function_count; i++) {
        R_BindingType_t type = R_GetBindingType(p->symbols[i], p->env);
        if ((type != R_BindingTypeValue && type != R_BindingTypeForced) ||
            R_getVarEx(p->symbols[i], p->env, FALSE, R_NilValue) !=
                p->functions[i] ||
            dtatools_probe_public_debugged(p->functions[i]) != 0 ||
            R_ClosureBody(p->functions[i]) != p->bodies[i] ||
            R_ClosureFormals(p->functions[i]) != p->formals[i] ||
            R_ClosureEnv(p->functions[i]) != p->closure_envs[i]) return 0;
    }
    return 1;
}

SEXP C_snap_check(SEXP ext) {
    return Rf_ScalarLogical(C_snap_check_raw(ext));
}

SEXP C_snap_stats(SEXP ext) {
    snap_profile *p = TYPEOF(ext) == EXTPTRSXP ? R_ExternalPtrAddr(ext) : NULL;
    if (p == NULL) return R_NilValue;
    SEXP result = PROTECT(Rf_allocVector(INTSXP, 2));
    INTEGER(result)[0] = p->function_count;
    INTEGER(result)[1] = p->node_count;
    UNPROTECT(1);
    return result;
}

int C_snap_active_raw(SEXP ext, SEXP active) {
    snap_profile *p = TYPEOF(ext) == EXTPTRSXP ? R_ExternalPtrAddr(ext) : NULL;
    if (p == NULL || p->function_count != 1 || TYPEOF(active) != CLOSXP)
        return 0;
    SEXP expected = p->functions[0];
    const snap_node *root = &p->nodes[0];
    snap_check_attr_context ctx = {root, 0, 1};
    int attr_ok = root->attr_count == 0 ? !ANY_ATTRIB(active) :
        ANY_ATTRIB(active) && R_mapAttrib(active, snap_check_attr, &ctx) == NULL &&
        ctx.ok && ctx.index == root->attr_count;
    return attr_ok &&
        (active == expected ||
        (R_ClosureEnv(active) == R_ClosureEnv(expected) &&
         R_ClosureFormals(active) == R_ClosureFormals(expected) &&
         R_ClosureBody(active) == R_ClosureBody(expected)));
}

SEXP C_snap_active(SEXP ext, SEXP active) {
    return Rf_ScalarLogical(C_snap_active_raw(ext, active));
}

SEXP C_snap_active_parts(SEXP ext, SEXP active) {
    snap_profile *p = TYPEOF(ext) == EXTPTRSXP ? R_ExternalPtrAddr(ext) : NULL;
    if (p == NULL || p->function_count != 1 || TYPEOF(active) != CLOSXP)
        return R_NilValue;
    SEXP expected = p->functions[0];
    SEXP out = PROTECT(Rf_allocVector(LGLSXP, 5));
    LOGICAL(out)[0] = active == expected;
    LOGICAL(out)[1] = R_ClosureEnv(active) == R_ClosureEnv(expected);
    LOGICAL(out)[2] = R_ClosureFormals(active) == R_ClosureFormals(expected);
    LOGICAL(out)[3] = R_ClosureBody(active) == R_ClosureBody(expected);
    LOGICAL(out)[4] = ANY_ATTRIB(active) == ANY_ATTRIB(expected);
    UNPROTECT(1);
    return out;
}
