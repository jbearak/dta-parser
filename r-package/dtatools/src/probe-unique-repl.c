/* Experimental guarded native replacement for plain and owned Stata doubles. */
#include "dtatools-internal.h"
#include <float.h>
#include <math.h>
#include <string.h>

static int attempts, shape, entry_shared_count, produced, fit_count, published;
static int abs_scalar_mode = 1;
static int unique_repl_mode = 1;
SEXP C_dtatools_probe_unique_repl_mode(SEXP mode) {
    if (TYPEOF(mode) != INTSXP || XLENGTH(mode) != 1 ||
        (INTEGER(mode)[0] != 0 && INTEGER(mode)[0] != 1))
        Rf_error("invalid repl mode");
    unique_repl_mode = INTEGER(mode)[0];
    return Rf_ScalarInteger(unique_repl_mode);
}
SEXP C_dtatools_probe_abs_mode(SEXP mode) {
    if (TYPEOF(mode) != INTSXP || XLENGTH(mode) != 1 ||
        (INTEGER(mode)[0] != 0 && INTEGER(mode)[0] != 1))
        Rf_error("invalid scratch abs mode");
    abs_scalar_mode = INTEGER(mode)[0];
    return Rf_ScalarInteger(abs_scalar_mode);
}
static SEXP precommit_hook = NULL;
extern SEXP C_dtatools_probe_scalar_public_dependencies(SEXP dependencies);
extern SEXP C_dtatools_probe_caller_plus(SEXP quosure, SEXP dependencies);
extern SEXP C_fast_s3_guard(SEXP quosure, SEXP tables, SEXP live, SEXP namespaces);
extern SEXP C_dtatools_probe_base_guard(SEXP live, SEXP quosure);
extern SEXP C_dtatools_probe_base16_guard(SEXP state);
extern SEXP C_dtatools_probe_public48_guard(SEXP state);
extern SEXP C_dtatools_probe_public_fused_guard(SEXP base, SEXP public48,
                                                 SEXP vctrs, SEXP quosure,
                                                 SEXP dependencies);
extern int dtatools_probe_wrapper_current(SEXP state);
extern SEXP C_dtatools_probe_rlang_guard(SEXP state);
extern SEXP C_dtatools_probe_vctrs_size_guard(SEXP state);

typedef struct { int count; SEXP tags[2]; } attr_tags;
typedef struct { int count; SEXP tags[8], values[8]; } binding_attrs;
static SEXP collect_binding_attr(SEXP tag, SEXP value, void *context) {
    binding_attrs *a = (binding_attrs *)context;
    if (a->count >= 8) { a->count++; return NULL; }
    a->tags[a->count] = tag;
    a->values[a->count++] = value;
    return NULL;
}
static int snapshot_binding_attrs(SEXP x, binding_attrs *out) {
    out->count = 0;
    return R_mapAttrib(x, collect_binding_attr, out) == NULL && out->count <= 8;
}
static int matching_binding_attrs(SEXP x, const binding_attrs *saved) {
    binding_attrs now;
    if (!snapshot_binding_attrs(x, &now) || now.count != saved->count) return 0;
    for (int i=0;i<now.count;++i)
        if (now.tags[i] != saved->tags[i] ||
            now.values[i] != saved->values[i]) return 0;
    return 1;
}
static int canonical_quosure_attrs(SEXP q) {
    SEXP classes = Rf_getAttrib(q, R_ClassSymbol);
    SEXP env = Rf_getAttrib(q, Rf_install(".Environment"));
    return TYPEOF(classes) == STRSXP && !ALTREP(classes) &&
        XLENGTH(classes) == 2 &&
        strcmp(CHAR(STRING_ELT(classes, 0)), "quosure") == 0 &&
        strcmp(CHAR(STRING_ELT(classes, 1)), "formula") == 0 &&
        TYPEOF(env) == ENVSXP;
}
static int canonical_missing_where(SEXP where) {
    return TYPEOF(where) == LANGSXP && canonical_quosure_attrs(where) &&
        CAR(where) == Rf_install("~") && CADR(where) == R_NilValue &&
        CDDR(where) == R_NilValue;
}
/* A bare column source with a same-named caller binding must take the R
   shadow check. Decline even for function bindings, which are harmless in R,
   so no promise or active binding is forced by admission. */
static int source_unshadowed(SEXP symbol, SEXP caller) {
    if (TYPEOF(symbol) != SYMSXP || TYPEOF(caller) != ENVSXP) return 0;
    const char *name = CHAR(PRINTNAME(symbol));
    /* R resolves dots through the call frame, not the data-mask column. */
    if (strncmp(name, "..", 2) == 0) return 0;
    static const char *special[] = {".data", ".env", ".", ".n", ".N"};
    for (int i = 0; i < 5; i++)
        if (strcmp(name, special[i]) == 0) return 0;
    for (SEXP env = caller;; env = R_ParentEnv(env)) {
        /* User database environments can execute a lookup callback even for
           binding inspection. Leave their shadow semantics to the R path. */
        if (TYPEOF(env) != ENVSXP || Rf_isObject(env) || Rf_isS4(env))
            return 0;
        if (env == R_BaseEnv || env == R_EmptyEnv) return 0;
        if (R_GetBindingType(symbol, env) != R_BindingTypeUnbound)
            return 0;
        if (env == R_GlobalEnv) return 1;
    }
}
/* Keep classification callback-free. The arithmetic source is the target. */
static int repl_expression_kind(SEXP expression, SEXP target_name,
                                double *constant) {
    if (TYPEOF(expression) != LANGSXP || ANY_ATTRIB(expression)) return 0;
    if (CAR(expression) == Rf_install("+") &&
        TYPEOF(CADR(expression)) == SYMSXP &&
        strcmp(CHAR(PRINTNAME(CADR(expression))), CHAR(target_name)) == 0 &&
        TYPEOF(CADDR(expression)) == REALSXP &&
        !ALTREP(CADDR(expression)) && !ANY_ATTRIB(CADDR(expression)) &&
        XLENGTH(CADDR(expression)) == 1 &&
        R_FINITE(REAL(CADDR(expression))[0]) &&
        CDDDR(expression) == R_NilValue) {
        *constant = REAL(CADDR(expression))[0];
        return 1;
    }
    if (CAR(expression) != Rf_install("abs") ||
        CDDR(expression) != R_NilValue) return 0;
    SEXP negation = CADR(expression);
    if (TYPEOF(negation) != LANGSXP || ANY_ATTRIB(negation) ||
        CAR(negation) != Rf_install("-") ||
        CDDR(negation) != R_NilValue) return 0;
    SEXP three = CADR(negation);
    if (TYPEOF(three) == REALSXP && !ALTREP(three) &&
        !ANY_ATTRIB(three) && XLENGTH(three) == 1 &&
        R_FINITE(REAL(three)[0])) {
        *constant = fabs(-REAL(three)[0]);
        return 2;
    }
    return 0;
}
static int canonical_captured_syntax(SEXP variable, SEXP values) {
    if (TYPEOF(variable) != LANGSXP || TYPEOF(values) != LANGSXP ||
        !canonical_quosure_attrs(variable) || !canonical_quosure_attrs(values) ||
        CAR(variable) != Rf_install("~") || CAR(values) != Rf_install("~") ||
        CDDR(variable) != R_NilValue || CDDR(values) != R_NilValue) return 0;
    SEXP target = CADR(variable), expression = CADR(values);
    double constant;
    return TYPEOF(target) == STRSXP && !ALTREP(target) && !ANY_ATTRIB(target) &&
        XLENGTH(target) == 1 && STRING_ELT(target,0) != NA_STRING &&
        CHAR(STRING_ELT(target,0))[0] != '\0' &&
        repl_expression_kind(expression, STRING_ELT(target,0), &constant) != 0;
}
#define REPL_MAX_WIDTH 2048
typedef struct {
    SEXP data, arguments, shared, fast_promote, argument_names;
    SEXP variable, values, where;
    SEXP argument_name_elements[16];
    binding_attrs argument_attrs, variable_attrs, values_attrs, where_attrs;
    int fast_promote_value;
    R_BindingType_t formal_types[3];
    SEXP formal_expressions[3], formal_environments[3];
    SEXP argument_fields[16];
    int shared_values[REPL_MAX_WIDTH];
    SEXP data_names, data_name_elements[REPL_MAX_WIDTH], target_name;
    R_xlen_t target_index;
    int expression_kind;
    double expression_constant;
    SEXP source_symbol;
    R_xlen_t argument_count, shared_count;
} frame_certificate;

/* The direct branch is only valid while the public entry frame still has
   the values that the skipped fallback would read. This is a scratch
   source-shape-specific certificate. It declines active/delayed replacements
   instead of evaluating them. */
static SEXP frame_value(SEXP frame, const char *name) {
    SEXP symbol = Rf_install(name);
    R_BindingType_t kind = R_GetBindingType(symbol, frame);
    return kind == R_BindingTypeValue || kind == R_BindingTypeForced ?
        R_getVar(symbol, frame, FALSE) : R_UnboundValue;
}

static int capture_frame(SEXP frame, SEXP data, SEXP shared,
                         SEXP quosure, frame_certificate *cert) {
    if (TYPEOF(frame) != ENVSXP ||
        frame_value(frame, "data") != data ||
        frame_value(frame, "shared") != shared ||
        frame_value(frame, "fast_promote") == R_UnboundValue ||
        TYPEOF(shared) != LGLSXP || ALTREP(shared) ||
        XLENGTH(shared) > REPL_MAX_WIDTH) return 0;
    cert->data = data;
    cert->shared = shared;
    cert->fast_promote = frame_value(frame, "fast_promote");
    cert->arguments = frame_value(frame, "arguments");
    if (TYPEOF(cert->arguments) != VECSXP || ALTREP(cert->arguments) ||
        XLENGTH(cert->arguments) > 16 ||
        !snapshot_binding_attrs(cert->arguments, &cert->argument_attrs)) return 0;
    cert->argument_count = XLENGTH(cert->arguments);
    for (R_xlen_t i = 0; i < cert->argument_count; i++)
        cert->argument_fields[i] = VECTOR_ELT(cert->arguments, i);
    /* The named value quosure is the third field in the exact captured
       `.mutation_arguments()` source shape used by this probe. */
    SEXP names = Rf_getAttrib(cert->arguments, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || ALTREP(names) ||
        cert->argument_count != 3 || XLENGTH(names) != 3 ||
        strcmp(CHAR(STRING_ELT(names,0)), "variable") != 0 ||
        strcmp(CHAR(STRING_ELT(names,1)), "values") != 0 ||
        strcmp(CHAR(STRING_ELT(names,2)), "where") != 0) return 0;
    cert->argument_names = names;
    for (R_xlen_t i = 0; i < cert->argument_count; i++)
        cert->argument_name_elements[i] = STRING_ELT(names, i);
    cert->variable = cert->argument_fields[0];
    cert->values = cert->argument_fields[1];
    cert->where = cert->argument_fields[2];
    if (cert->values != quosure ||
        !canonical_captured_syntax(cert->variable, cert->values) ||
        !canonical_missing_where(cert->where) ||
        !snapshot_binding_attrs(cert->variable, &cert->variable_attrs) ||
        !snapshot_binding_attrs(cert->values, &cert->values_attrs) ||
        !snapshot_binding_attrs(cert->where, &cert->where_attrs)) return 0;
    cert->target_name = STRING_ELT(CADR(cert->variable), 0);
    cert->expression_kind = repl_expression_kind(
        CADR(cert->values), cert->target_name, &cert->expression_constant);
    if (cert->expression_kind == 0) return 0;
    cert->source_symbol = cert->expression_kind == 1 ?
        CADR(CADR(cert->values)) : R_NilValue;
    if (cert->expression_kind == 1 && !source_unshadowed(
            cert->source_symbol,
            Rf_getAttrib(cert->values, Rf_install(".Environment"))))
        return 0;
    cert->shared_count = XLENGTH(shared);
    for (R_xlen_t i = 0; i < cert->shared_count; i++)
        cert->shared_values[i] = LOGICAL(shared)[i];
    static const char *formals[] = {"where", "by", "bysort"};
    for (int i = 0; i < 3; i++) {
        SEXP symbol = Rf_install(formals[i]);
        cert->formal_types[i] = R_GetBindingType(symbol, frame);
        if (cert->formal_types[i] != R_BindingTypeDelayed) return 0;
        cert->formal_expressions[i] = R_DelayedBindingExpression(symbol, frame);
        cert->formal_environments[i] = R_DelayedBindingEnvironment(symbol, frame);
    }
    /* Grouping and sorting have their own observable evaluation and write
       order. The ungrouped transaction only handles the default NULLs. */
    if (cert->formal_expressions[0] != R_NilValue ||
        cert->formal_expressions[1] != R_NilValue ||
        cert->formal_expressions[2] != R_NilValue ||
        cert->formal_environments[0] != frame ||
        cert->formal_environments[1] != frame ||
        cert->formal_environments[2] != frame) return 0;
    SEXP promote = C_dtatools_peek_promote(frame);
    if (TYPEOF(promote) != LGLSXP || LOGICAL(promote)[0] != TRUE ||
        TYPEOF(cert->fast_promote) != LGLSXP ||
        ALTREP(cert->fast_promote) || ANY_ATTRIB(cert->fast_promote) ||
        XLENGTH(cert->fast_promote) != 1) return 0;
    cert->fast_promote_value = LOGICAL(cert->fast_promote)[0];
    return cert->fast_promote_value == TRUE;
}

static int frame_still_matches(SEXP frame, const frame_certificate *cert) {
    SEXP promote = C_dtatools_peek_promote(frame);
    if (frame_value(frame, "data") != cert->data ||
        frame_value(frame, "arguments") != cert->arguments ||
        frame_value(frame, "shared") != cert->shared ||
        frame_value(frame, "fast_promote") != cert->fast_promote ||
        LOGICAL(cert->fast_promote)[0] != cert->fast_promote_value ||
        TYPEOF(promote) != LGLSXP || ALTREP(promote) ||
        XLENGTH(promote) != 1 || LOGICAL(promote)[0] != TRUE ||
        XLENGTH(cert->arguments) != cert->argument_count ||
        XLENGTH(cert->shared) != cert->shared_count ||
        !matching_binding_attrs(cert->arguments, &cert->argument_attrs) ||
        Rf_getAttrib(cert->arguments, R_NamesSymbol) != cert->argument_names ||
        !matching_binding_attrs(cert->variable, &cert->variable_attrs) ||
        !matching_binding_attrs(cert->values, &cert->values_attrs) ||
        !matching_binding_attrs(cert->where, &cert->where_attrs) ||
        !canonical_captured_syntax(cert->variable, cert->values) ||
        !canonical_missing_where(cert->where) ||
        STRING_ELT(CADR(cert->variable), 0) != cert->target_name) return 0;
    double constant;
    int kind = repl_expression_kind(CADR(cert->values), cert->target_name,
                                     &constant);
    if (kind != cert->expression_kind ||
        memcmp(&constant, &cert->expression_constant, sizeof(double)) != 0)
        return 0;
    if (kind == 1 &&
        (CADR(CADR(cert->values)) != cert->source_symbol ||
         !source_unshadowed(cert->source_symbol,
            Rf_getAttrib(cert->values, Rf_install(".Environment")))))
        return 0;
    for (R_xlen_t i = 0; i < cert->argument_count; i++)
        if (VECTOR_ELT(cert->arguments, i) != cert->argument_fields[i] ||
            STRING_ELT(cert->argument_names, i) != cert->argument_name_elements[i]) return 0;
    for (R_xlen_t i = 0; i < cert->shared_count; i++)
        if (LOGICAL(cert->shared)[i] != cert->shared_values[i]) return 0;
    static const char *formals[] = {"where", "by", "bysort"};
    for (int i = 0; i < 3; i++) {
        SEXP symbol = Rf_install(formals[i]);
        if (R_GetBindingType(symbol, frame) != cert->formal_types[i] ||
            R_DelayedBindingExpression(symbol, frame) != cert->formal_expressions[i] ||
            R_DelayedBindingEnvironment(symbol, frame) != cert->formal_environments[i]) return 0;
    }
    return 1;
}


static SEXP record_attr_tag(SEXP tag, SEXP value, void *context) {
    (void) value;
    attr_tags *profile = (attr_tags *) context;
    if (profile->count < 2) profile->tags[profile->count] = tag;
    profile->count++;
    return NULL;
}

static int canonical_x_attributes(SEXP x, attr_tags *profile) {
    profile->count = 0;
    profile->tags[0] = profile->tags[1] = R_NilValue;
    R_mapAttrib(x, record_attr_tag, profile);
    if (profile->count != 2) return 0;
    SEXP storage = Rf_getAttrib(x, Rf_install("stata.storage"));
    SEXP classes = Rf_getAttrib(x, R_ClassSymbol);
    if (TYPEOF(storage) != STRSXP || ALTREP(storage) || ANY_ATTRIB(storage) ||
        XLENGTH(storage) != 1 ||
        strcmp(CHAR(STRING_ELT(storage, 0)), "double") != 0 ||
        TYPEOF(classes) != STRSXP || ALTREP(classes) || ANY_ATTRIB(classes) ||
        XLENGTH(classes) != 4) return 0;
    static const char *expected[] = {
        "dta_numeric", "dta_double", "vctrs_vctr", "double"
    };
    for (int i = 0; i < 4; i++)
        if (strcmp(CHAR(STRING_ELT(classes, i)), expected[i])) return 0;
    return (profile->tags[0] == Rf_install("stata.storage") &&
            profile->tags[1] == R_ClassSymbol) ||
           (profile->tags[1] == Rf_install("stata.storage") &&
            profile->tags[0] == R_ClassSymbol);
}

/* Scratch syntax recognizer for the already-captured named benchmark dots. */
SEXP C_dtatools_probe_repl_syntax(SEXP variable, SEXP values) {
    if (!unique_repl_mode) return Rf_ScalarLogical(FALSE);
    if (TYPEOF(variable) != LANGSXP || TYPEOF(values) != LANGSXP ||
        !Rf_inherits(variable, "quosure") || !Rf_inherits(values, "quosure") ||
        CAR(variable) != Rf_install("~") || CAR(values) != Rf_install("~") ||
        CDDR(variable) != R_NilValue || CDDR(values) != R_NilValue)
        return Rf_ScalarLogical(FALSE);
    SEXP target = CADR(variable), expression = CADR(values);
    double constant;
    if (TYPEOF(target) != STRSXP || ALTREP(target) || ANY_ATTRIB(target) ||
        XLENGTH(target) != 1 || STRING_ELT(target, 0) == NA_STRING ||
        CHAR(STRING_ELT(target, 0))[0] == '\0' ||
        repl_expression_kind(expression, STRING_ELT(target, 0), &constant) == 0)
        return Rf_ScalarLogical(FALSE);
    return Rf_ScalarLogical(TRUE);
}

SEXP C_dtatools_probe_unique_repl_stats(SEXP reset) {
    SEXP out = PROTECT(Rf_allocVector(INTSXP, 6));
    INTEGER(out)[0] = attempts;
    INTEGER(out)[1] = shape;
    INTEGER(out)[2] = entry_shared_count;
    INTEGER(out)[3] = produced;
    INTEGER(out)[4] = fit_count;
    INTEGER(out)[5] = published;
    if (Rf_asLogical(reset))
        attempts = shape = entry_shared_count = produced = fit_count = published = 0;
    UNPROTECT(1);
    return out;
}

SEXP C_dtatools_probe_precommit_hook(SEXP callback) {
    if (callback != R_NilValue && !Rf_isFunction(callback))
        Rf_error("precommit hook must be a function or NULL");
    if (precommit_hook != NULL) R_ReleaseObject(precommit_hook);
    precommit_hook = callback == R_NilValue ? NULL : callback;
    if (precommit_hook != NULL) R_PreserveObject(precommit_hook);
    return Rf_ScalarLogical(1);
}

void dtatools_probe_numeric_precommit(void) {
    if (precommit_hook == NULL) return;
    SEXP callback = PROTECT(precommit_hook);
    precommit_hook = NULL;
    R_ReleaseObject(callback);
    SEXP call = PROTECT(Rf_lang1(callback));
    Rf_eval(call, R_GlobalEnv);
    UNPROTECT(2);
}

SEXP C_dtatools_probe_unique_repl(SEXP data, SEXP shared, SEXP arguments,
                                  SEXP dependencies, SEXP s3_state,
                                  SEXP base_live, SEXP rlang_state,
                                  SEXP vctrs_size_state, SEXP base16_state,
                                  SEXP public48_state, SEXP wrapper_state) {
    SEXP frame = R_GetCurrentEnv();
    if (TYPEOF(arguments) != VECSXP || ALTREP(arguments) ||
        XLENGTH(arguments) != 3)
        return Rf_ScalarLogical(FALSE);
    SEXP variable = VECTOR_ELT(arguments, 0);
    SEXP quosure = VECTOR_ELT(arguments, 1);
    if (Rf_asLogical(C_dtatools_probe_repl_syntax(variable, quosure)) != TRUE)
        return Rf_ScalarLogical(FALSE);
    SEXP tables = frame_value(s3_state, "tables");
    SEXP live = frame_value(s3_state, "live");
    SEXP namespaces = frame_value(s3_state, "namespaces");
    if (TYPEOF(tables) != VECSXP || TYPEOF(live) != VECSXP ||
        TYPEOF(namespaces) != VECSXP ||
        Rf_asLogical(C_dtatools_probe_public_fused_guard(
            base_live, public48_state, vctrs_size_state, quosure,
            dependencies)) != TRUE ||
        Rf_asLogical(C_dtatools_probe_caller_plus(quosure, dependencies)) != TRUE ||
        Rf_asLogical(C_fast_s3_guard(quosure, tables, live, namespaces)) != TRUE ||
        !dtatools_probe_wrapper_current(wrapper_state))
        return Rf_ScalarLogical(FALSE);
    frame_certificate cert;
    attempts++;
    if (!capture_frame(frame, data, shared, quosure, &cert)) return Rf_ScalarLogical(FALSE);
    R_xlen_t shape_rows = 0;
    if (!mutation_fast_shape(data, &shape_rows) ||
        shape_rows < 1 ||
        !dtatools_reference_state_valid_noalloc(data)) return Rf_ScalarLogical(FALSE);
    if (XLENGTH(Rf_getAttrib(data, R_ClassSymbol)) != 5) return Rf_ScalarLogical(FALSE);
    R_xlen_t width = XLENGTH(data);
    if (width < 1 || width > REPL_MAX_WIDTH ||
        TYPEOF(shared) != LGLSXP ||
        ALTREP(shared) ||
        XLENGTH(shared) != width)
        return Rf_ScalarLogical(FALSE);
    SEXP names = Rf_getAttrib(data, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || ALTREP(names) || XLENGTH(names) != width)
        return Rf_ScalarLogical(FALSE);
    cert.data_names = names;
    cert.target_index = width;
    for (R_xlen_t j = 0; j < width; j++) {
        SEXP name = STRING_ELT(names, j);
        cert.data_name_elements[j] = name;
        if (strcmp(CHAR(name), CHAR(cert.target_name)) == 0)
            cert.target_index = j;
    }
    if (cert.target_index == width ||
        LOGICAL(shared)[cert.target_index] == NA_LOGICAL)
        return Rf_ScalarLogical(FALSE);
    SEXP x = PROTECT(VECTOR_ELT(data, cert.target_index));
    if (TYPEOF(x) != REALSXP || Rf_isS4(x) ||
        (!ALTREP(x) && !dtatools_probe_plain_public_guard()) ||
        (ALTREP(x) && (!owned_real(x) || R_altrep_data2(x) != R_NilValue)) ||
        XLENGTH(x) != shape_rows || !Rf_inherits(x, "dta_double")) {
        UNPROTECT(1);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP storage = Rf_getAttrib(x, Rf_install("stata.storage"));
    if (TYPEOF(storage) != STRSXP || ALTREP(storage) || XLENGTH(storage) != 1 ||
        strcmp(CHAR(STRING_ELT(storage, 0)), "double") != 0) {
        UNPROTECT(1);
        return Rf_ScalarLogical(FALSE);
    }
    shape++;
    if (LOGICAL(shared)[cert.target_index]) entry_shared_count++;

    SEXP saved_data1 = PROTECT(ALTREP(x) ? R_altrep_data1(x) : R_NilValue);
    SEXP saved_data2 = PROTECT(ALTREP(x) ? R_altrep_data2(x) : R_NilValue);
    SEXP source = PROTECT(owned_real(x) ? owned_values(x) : x);
    if (TYPEOF(source) != REALSXP || ALTREP(source) || XLENGTH(source) != shape_rows) {
        UNPROTECT(4);
        return Rf_ScalarLogical(FALSE);
    }
    double constant;
    int kind = repl_expression_kind(CADR(quosure), cert.target_name,
                                    &constant);
    if (kind == 0) { UNPROTECT(4); return Rf_ScalarLogical(FALSE); }
    int scalar_mode = owned_real(x) && kind == 2 && abs_scalar_mode &&
        !LOGICAL(shared)[cert.target_index] && !MAYBE_SHARED(x) &&
        !owned_flags(x)[OWNED_SHARED] && !owned_flags(x)[OWNED_EXPOSED];
    /* For an independent owned target, the constant's one-scalar staging
       plan can commit into private backing after all callbacks. If an alias
       appears meanwhile, decline before any write. A target already shared
       at entry uses the ordinary replacement-buffer plan instead. */
    SEXP backing = PROTECT(!scalar_mode
        ? Rf_allocVector(REALSXP, shape_rows) : Rf_ScalarReal(constant));
    SEXP replacement = PROTECT(!scalar_mode
        ? owned_adopt_real(backing) : R_NilValue);
    if (!scalar_mode) SHALLOW_DUPLICATE_ATTRIB(replacement, x);
    produced++;
    R_CheckUserInterrupt();
    /* The test hook can run arbitrary R code. Without it, the only R code
       that can run between admission and publication is a GC finalizer;
       function/method rewrites in that interval are outside this adapter's
       compatibility boundary. Physical value changes remain checked below. */
    int hook_ran = precommit_hook != NULL;
    dtatools_probe_numeric_precommit();
    if (hook_ran && (Rf_asLogical(C_dtatools_probe_public_fused_guard(
            base_live, public48_state, vctrs_size_state, quosure,
            dependencies)) != TRUE ||
        Rf_asLogical(C_dtatools_probe_caller_plus(quosure, dependencies)) != TRUE ||
        Rf_asLogical(C_fast_s3_guard(quosure, tables, live, namespaces)) != TRUE ||
        !dtatools_probe_wrapper_current(wrapper_state))) {
        UNPROTECT(6);
        return Rf_ScalarLogical(FALSE);
    }
    R_xlen_t final_rows = 0;
    if (!dtatools_reference_state_valid_noalloc(data)) {
        UNPROTECT(6);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP final_names = Rf_getAttrib(data, R_NamesSymbol);
    attr_tags target_attrs, staged_attrs;
    if (!mutation_fast_shape(data, &final_rows) || final_rows != shape_rows ||
        XLENGTH(Rf_getAttrib(data, R_ClassSymbol)) != 5 ||
        TYPEOF(final_names) != STRSXP || ALTREP(final_names) ||
        XLENGTH(final_names) != width ||
        final_names != cert.data_names ||
        VECTOR_ELT(data, cert.target_index) != x || XLENGTH(x) != shape_rows ||
        (ALTREP(x) && (!owned_real(x) ||
            R_altrep_data1(x) != saved_data1 ||
            R_altrep_data2(x) != saved_data2)) ||
        (owned_real(x) ? owned_values(x) : x) != source ||
        (!ALTREP(x) && !dtatools_probe_plain_public_guard()) ||
        Rf_isS4(x) || !canonical_x_attributes(x, &target_attrs) ||
        (!scalar_mode &&
         (!canonical_x_attributes(replacement, &staged_attrs) ||
          target_attrs.tags[0] != staged_attrs.tags[0] ||
          target_attrs.tags[1] != staged_attrs.tags[1]))) {
        UNPROTECT(6);
        return Rf_ScalarLogical(FALSE);
    }
    for (R_xlen_t j = 0; j < width; j++) {
        if (STRING_ELT(final_names, j) != cert.data_name_elements[j]) {
            UNPROTECT(6);
            return Rf_ScalarLogical(FALSE);
        }
    }
    if (!frame_still_matches(frame, &cert)) {
        UNPROTECT(6);
        return Rf_ScalarLogical(FALSE);
    }
    if (scalar_mode) {
        if (LOGICAL(shared)[cert.target_index] || MAYBE_SHARED(x) ||
            owned_flags(x)[OWNED_SHARED] ||
            owned_flags(x)[OWNED_EXPOSED]) {
            UNPROTECT(6);
            return Rf_ScalarLogical(FALSE);
        }
        double *out = REAL(source);
        out[0] = constant;
        size_t filled = sizeof(double);
        size_t total = (size_t) shape_rows * sizeof(double);
        while (filled < total) {
            size_t copy = filled <= total-filled ? filled : total-filled;
            memcpy((unsigned char *)out + filled, out, copy);
            filled += copy;
        }
        owned_flags(x)[OWNED_NO_NA] = 1;
        owned_flags(x)[OWNED_FINITE_DOUBLE] = 1;
        fit_count++;
        published++;
        UNPROTECT(6);
        return Rf_ScalarLogical(TRUE);
    }
    const double *xp = REAL(source);
    double *out = REAL(backing);
    for (R_xlen_t i = 0; i < shape_rows; i++) {
        double value = kind == 1 ? xp[i] + constant : constant;
        if (!(value >= -DBL_MAX / 2.0 && value <= DBL_MAX / 2.0)) {
            UNPROTECT(6);
            return Rf_ScalarLogical(FALSE);
        }
        out[i] = value;
    }
    fit_count++;
    owned_flags(replacement)[OWNED_NO_NA] = 1;
    owned_flags(replacement)[OWNED_FINITE_DOUBLE] = 1;
    for (R_xlen_t j = 0; j < width; j++) {
        if (VECTOR_ELT(data, j) == x) SET_VECTOR_ELT(data, j, replacement);
    }
    published++;
    UNPROTECT(6);
    return Rf_ScalarLogical(TRUE);
}
