/* Structural classifier for a five-output bracket operation.
 * This does not authorize native execution: the public callback certificate,
 * physical source/metadata rechecks, and prepared append are separate.
 * It deliberately inspects the actual objects returned by the R parser. */
#define ENABLE_LEGACY_NONAPI_FUNS 1
#include "dtatools-internal.h"
extern SEXP dtatools_probe_double_input_values(SEXP column);
#include <limits.h>
#include <stdio.h>
#include <string.h>

extern int probe_canonical_source_attrs(SEXP column);
extern int C_dtatools_probe_bracket_public_guard_raw(SEXP profile,
                                                      SEXP caller);
static int raw_parser_successes = 0;
static int raw_parser_frame_bindings = 0;
static SEXP raw_parser_pending = NULL;

static void clear_raw_parser_pending(void) {
    if (raw_parser_pending != NULL) {
        SEXP pending = raw_parser_pending;
        raw_parser_pending = NULL;
        R_ReleaseObject(pending);
    }
}

/* One-shot identity receipt. Reentrant parsing invalidates an outer receipt,
   making it take the conservative full guard. The preserved object cannot be
   recycled into a false match if an operation never reaches batch admission. */
int dtatools_probe_consume_raw_parsed(SEXP assignments) {
    int matched = raw_parser_pending != NULL &&
        raw_parser_pending == assignments;
    clear_raw_parser_pending();
    return matched;
}

SEXP C_dtatools_probe_bracket_raw_parser_stats(SEXP reset) {
    SEXP result = PROTECT(Rf_allocVector(INTSXP, 2));
    INTEGER(result)[0] = raw_parser_successes;
    INTEGER(result)[1] = raw_parser_frame_bindings;
    if (Rf_asLogical(reset) == TRUE)
        raw_parser_successes = raw_parser_frame_bindings = 0;
    UNPROTECT(1);
    return result;
}

static int one_field(SEXP value, const char *wanted) {
    return TYPEOF(value) == STRSXP && XLENGTH(value) == 1 &&
        !ALTREP(value) &&
        strcmp(CHAR(STRING_ELT(value, 0)), wanted) == 0;
}

static int bounded_offset(SEXP literal, double *offset) {
    if (TYPEOF(literal) != REALSXP || ALTREP(literal) ||
        ANY_ATTRIB(literal) || Rf_isS4(literal) || XLENGTH(literal) != 1) return 0;
    double value = REAL(literal)[0];
    if (!R_FINITE(value) || value < -1000000.0 || value > 1000000.0)
        return 0;
    *offset = value;
    return 1;
}

static int parsed_quosure(SEXP quo, SEXP caller, SEXP *source,
                          double *offset, int *offset_seen) {
    if (TYPEOF(quo) != LANGSXP || Rf_length(quo) != 2 ||
        CAR(quo) != Rf_install("~") ||
        Rf_getAttrib(quo, Rf_install(".Environment")) != caller)
        return 0;
    SEXP classes = Rf_getAttrib(quo, R_ClassSymbol);
    if (TYPEOF(classes) != STRSXP || ALTREP(classes) ||
        XLENGTH(classes) != 2 ||
        strcmp(CHAR(STRING_ELT(classes, 0)), "quosure") != 0 ||
        strcmp(CHAR(STRING_ELT(classes, 1)), "formula") != 0)
        return 0;
    SEXP expr = CADR(quo);
    if (TYPEOF(expr) != LANGSXP || Rf_length(expr) != 3 ||
        CAR(expr) != Rf_install("+") || TYPEOF(CADR(expr)) != SYMSXP)
        return 0;
    SEXP literal = CADDR(expr);
    double current_offset;
    if (!bounded_offset(literal, &current_offset)) return 0;
    if (*source == R_NilValue) *source = CADR(expr);
    if (*source != CADR(expr)) return 0;
    if (*offset_seen && *offset != current_offset) return 0;
    *offset = current_offset;
    *offset_seen = 1;
    return 1;
}

int dtatools_probe_bracket_source_unshadowed(SEXP caller, SEXP source) {
    if (TYPEOF(caller) != ENVSXP || TYPEOF(source) != SYMSXP)
        return 0;
    /* These names resolve to pronouns, row helpers, or R dots references,
       even when the table contains a column with the same name. */
    if (source == Rf_install(".data") || source == Rf_install(".env") ||
        source == Rf_install(".n") || source == Rf_install(".N") ||
        strncmp(CHAR(PRINTNAME(source)), "..", 2) == 0) return 0;
    /* Scan attached environments as well as the immediate caller chain.
     * Declining a harmless function binding is intentional: no promise is
     * made about rlang's data-mask conflict rules without its evaluator. */
    for (SEXP env = caller; env != R_EmptyEnv && env != R_BaseEnv;
         env = R_ParentEnv(env)) {
        if (TYPEOF(env) != ENVSXP || Rf_isObject(env) || Rf_isS4(env))
            return 0;
        if (R_GetBindingType(source, env) != R_BindingTypeUnbound)
            return 0;
    }
    return 1;
}

/* Result: source slot (zero-based), source symbol, target names,
 * source handle. The caller must freeze its parsed/where/selection objects
 * separately and revalidate every descriptor field before each publication.
 * Returning NULL means the untouched ordinary R path must run. */
SEXP C_dtatools_probe_bracket_general_descriptor(SEXP data,
                                                  SEXP assignments,
                                                  SEXP caller) {
    if (TYPEOF(data) != VECSXP || ALTREP(data) ||
        TYPEOF(assignments) != VECSXP ||
        (XLENGTH(assignments) != 1 && XLENGTH(assignments) != 5) ||
        TYPEOF(caller) != ENVSXP ||
        !Rf_inherits(data, "dibble") ||
        !Rf_inherits(data, "dtatools_ref_data"))
        return R_NilValue;
    SEXP table_names = Rf_getAttrib(data, R_NamesSymbol);
    R_xlen_t width = XLENGTH(data);
    SEXP table_classes = Rf_getAttrib(data, R_ClassSymbol);
    const char *expected_table_classes[] = {
        "dibble", "dtatools_ref_data", "tbl_df", "tbl", "data.frame"
    };
    if (TYPEOF(table_classes) != STRSXP || ALTREP(table_classes) ||
        XLENGTH(table_classes) != 5) return R_NilValue;
    for (int index = 0; index < 5; index++)
        if (strcmp(CHAR(STRING_ELT(table_classes, index)),
                   expected_table_classes[index]) != 0)
            return R_NilValue;
    if (TYPEOF(table_names) != STRSXP || ALTREP(table_names) ||
        XLENGTH(table_names) != width || width < 1)
        return R_NilValue;

    SEXP source_symbol = R_NilValue;
    double offset = 0.0;
    int offset_seen = 0;
    SEXP targets = PROTECT(Rf_allocVector(STRSXP, XLENGTH(assignments)));
    for (R_xlen_t index = 0; index < XLENGTH(assignments); index++) {
        SEXP assignment = VECTOR_ELT(assignments, index);
        if (TYPEOF(assignment) != VECSXP || XLENGTH(assignment) != 2) {
            UNPROTECT(1); return R_NilValue;
        }
        SEXP fields = Rf_getAttrib(assignment, R_NamesSymbol);
        if (TYPEOF(fields) != STRSXP || ALTREP(fields) ||
            XLENGTH(fields) != 2 ||
            strcmp(CHAR(STRING_ELT(fields, 0)), "name") != 0 ||
            strcmp(CHAR(STRING_ELT(fields, 1)), "values") != 0) {
            UNPROTECT(1); return R_NilValue;
        }
        SEXP target = VECTOR_ELT(assignment, 0);
        if (TYPEOF(target) != STRSXP || ALTREP(target) ||
            XLENGTH(target) != 1 ||
            STRING_ELT(target, 0) == NA_STRING ||
            CHAR(STRING_ELT(target, 0))[0] == '\0' ||
            !parsed_quosure(VECTOR_ELT(assignment, 1), caller,
                            &source_symbol, &offset, &offset_seen)) {
            UNPROTECT(1); return R_NilValue;
        }
        SEXP target_name = STRING_ELT(target, 0);
        for (R_xlen_t prior = 0; prior < index; prior++)
            if (strcmp(CHAR(target_name),
                       CHAR(STRING_ELT(targets, prior))) == 0) {
                UNPROTECT(1); return R_NilValue;
            }
        for (R_xlen_t slot = 0; slot < width; slot++)
            if (strcmp(CHAR(target_name),
                       CHAR(STRING_ELT(table_names, slot))) == 0) {
                UNPROTECT(1); return R_NilValue;
            }
        SET_STRING_ELT(targets, index, target_name);
    }
    if (!dtatools_probe_bracket_source_unshadowed(caller, source_symbol)) {
        UNPROTECT(1); return R_NilValue;
    }
    SEXP source_name = PRINTNAME(source_symbol);
    R_xlen_t source_slot = width;
    for (R_xlen_t slot = 0; slot < width; slot++)
        if (strcmp(CHAR(source_name),
                   CHAR(STRING_ELT(table_names, slot))) == 0) {
            if (source_slot != width) {
                UNPROTECT(1); return R_NilValue;
            }
            source_slot = slot;
        }
    if (source_slot == width || source_slot > INT_MAX) {
        UNPROTECT(1); return R_NilValue;
    }
    SEXP source = VECTOR_ELT(data, source_slot);
    SEXP values = dtatools_probe_double_input_values(source);
    if ((!ALTREP(source) && !dtatools_probe_plain_public_guard()) ||
        TYPEOF(values) != REALSXP || ALTREP(values) ||
        XLENGTH(values) != XLENGTH(source) ||
        !probe_canonical_source_attrs(source) ||
        !one_field(Rf_getAttrib(source, Rf_install("stata.storage")),
                   "double")) {
        UNPROTECT(1); return R_NilValue;
    }
    SEXP classes = Rf_getAttrib(source, R_ClassSymbol);
    const char *expected[] = {
        "dta_numeric", "dta_double", "vctrs_vctr", "double"
    };
    if (TYPEOF(classes) != STRSXP || ALTREP(classes) ||
        XLENGTH(classes) != 4) {
        UNPROTECT(1); return R_NilValue;
    }
    for (int i = 0; i < 4; i++)
        if (strcmp(CHAR(STRING_ELT(classes, i)), expected[i]) != 0) {
            UNPROTECT(1); return R_NilValue;
        }
    SEXP descriptor = PROTECT(Rf_allocVector(VECSXP, 5));
    SEXP slot = PROTECT(Rf_ScalarInteger((int) source_slot));
    SEXP literal_offset = PROTECT(Rf_ScalarReal(offset));
    SET_VECTOR_ELT(descriptor, 0, slot);
    SET_VECTOR_ELT(descriptor, 1, source_symbol);
    SET_VECTOR_ELT(descriptor, 2, targets);
    SET_VECTOR_ELT(descriptor, 3, source);
    SET_VECTOR_ELT(descriptor, 4, literal_offset);
    UNPROTECT(4);
    return descriptor;
}

static int raw_one_value_kind(SEXP value, SEXP *source_symbol,
                              double *offset, int *offset_seen) {
    if (TYPEOF(value) == REALSXP && !ALTREP(value) &&
        !ANY_ATTRIB(value) && !Rf_isS4(value) && XLENGTH(value) == 1 &&
        R_FINITE(REAL(value)[0])) return 1;
    if (TYPEOF(value) != LANGSXP || ANY_ATTRIB(value)) return 0;
    if (CAR(value) == Rf_install("abs") &&
        Rf_length(value) == 2) {
        SEXP negative = CADR(value);
        if (TYPEOF(negative) == LANGSXP && !ANY_ATTRIB(negative) &&
            CAR(negative) == Rf_install("-") &&
            Rf_length(negative) == 2 &&
            TYPEOF(CADR(negative)) == REALSXP &&
            !ALTREP(CADR(negative)) && !ANY_ATTRIB(CADR(negative)) &&
            !Rf_isS4(CADR(negative)) &&
            XLENGTH(CADR(negative)) == 1 &&
            R_FINITE(REAL(CADR(negative))[0])) return 2;
        return 0;
    }
    double current_offset;
    if (CAR(value) != Rf_install("+") || Rf_length(value) != 3 ||
        TYPEOF(CADR(value)) != SYMSXP ||
        !bounded_offset(CADDR(value), &current_offset)) return 0;
    if (*source_symbol == R_NilValue) *source_symbol = CADR(value);
    if (*source_symbol != CADR(value) ||
        (*offset_seen && *offset != current_offset)) return 0;
    *offset = current_offset;
    *offset_seen = 1;
    return 3;
}

/* Earlier parser seam for one or five direct source + 1 assignments. The
 * public dependency guard runs before it can omit parser callbacks. */
extern double probe_general_clock_ns(void);
extern void probe_general_phase_add(int slot, double elapsed);
extern int C_dtatools_probe_bracket_public_live_raw(SEXP profile, SEXP caller);
SEXP C_dtatools_probe_bracket_raw_five_parser(SEXP raw_j, SEXP profile) {
    clear_raw_parser_pending();
    if (TYPEOF(raw_j) != LANGSXP || Rf_length(raw_j) != 2 ||
        CAR(raw_j) != Rf_install("~")) return R_NilValue;
    SEXP raw_classes = Rf_getAttrib(raw_j, R_ClassSymbol);
    SEXP caller = Rf_getAttrib(raw_j, Rf_install(".Environment"));
    if (TYPEOF(raw_classes) != STRSXP || XLENGTH(raw_classes) != 2 ||
        strcmp(CHAR(STRING_ELT(raw_classes, 0)), "quosure") != 0 ||
        strcmp(CHAR(STRING_ELT(raw_classes, 1)), "formula") != 0 ||
        TYPEOF(caller) != ENVSXP)
        return R_NilValue;
    SEXP expression = CADR(raw_j);
    if (TYPEOF(expression) != LANGSXP ||
        CAR(expression) != Rf_install(":="))
        return R_NilValue;
    double phase_start = probe_general_clock_ns();
    int guard_ok = C_dtatools_probe_bracket_public_guard_raw(profile, caller);
    probe_general_phase_add(0, probe_general_clock_ns() - phase_start);
    if (!guard_ok) return R_NilValue;
    R_xlen_t count = Rf_length(expression) - 1;
    int tagged = count == 5;
    if (!tagged && count != 2) return R_NilValue;
    SEXP arguments = CDR(expression), source_symbol = R_NilValue;
    double offset = 0.0;
    int offset_seen = 0;
    SEXP node = arguments;
    for (R_xlen_t index = 0; index < (tagged ? 5 : 1);
         index++, node = tagged ? CDR(node) : R_NilValue) {
        if (TYPEOF(node) != LISTSXP) return R_NilValue;
        SEXP value = tagged ? CAR(node) : CADDR(expression);
        SEXP target = tagged ? TAG(node) : CAR(node);
        if ((tagged && TYPEOF(target) != SYMSXP) ||
            (!tagged && (TAG(node) != R_NilValue ||
                         TYPEOF(target) != SYMSXP ||
                         TAG(CDR(node)) != R_NilValue)) ||
            target == R_DotsSymbol ||
            !CHAR(PRINTNAME(target))[0] ||
            (!tagged ? raw_one_value_kind(value, &source_symbol,
                                          &offset, &offset_seen) == 0 :
             raw_one_value_kind(value, &source_symbol,
                                &offset, &offset_seen) != 3))
            return R_NilValue;
        for (SEXP previous = arguments; tagged && previous != node;
             previous = CDR(previous))
            if (TAG(previous) == target) return R_NilValue;
    }
    phase_start = probe_general_clock_ns();
    SEXP result = PROTECT(Rf_allocVector(VECSXP, tagged ? 5 : 1));
    node = arguments;
    for (int index = 0; index < (tagged ? 5 : 1);
         index++, node = tagged ? CDR(node) : R_NilValue) {
        SEXP target = tagged ? PRINTNAME(TAG(node)) : PRINTNAME(CAR(node));
        /* enquo() snapshots this bounded RHS before later row/group captures
           can mutate the caller's literal through a public callback. */
        SEXP value = PROTECT(Rf_duplicate(tagged ? CAR(node) : CADDR(expression)));
        SEXP assignment = PROTECT(Rf_allocVector(VECSXP, 2));
        SEXP name = PROTECT(Rf_ScalarString(target));
        SEXP quo = PROTECT(Rf_lang2(Rf_install("~"), value));
        SEXP field_names = PROTECT(Rf_allocVector(STRSXP, 2));
        SET_STRING_ELT(field_names, 0, Rf_mkChar("name"));
        SET_STRING_ELT(field_names, 1, Rf_mkChar("values"));
        SEXP classes = PROTECT(Rf_allocVector(STRSXP, 2));
        SET_STRING_ELT(classes, 0, Rf_mkChar("quosure"));
        SET_STRING_ELT(classes, 1, Rf_mkChar("formula"));
        Rf_setAttrib(quo, Rf_install(".Environment"), caller);
        Rf_setAttrib(quo, R_ClassSymbol, classes);
        SET_VECTOR_ELT(assignment, 0, name);
        SET_VECTOR_ELT(assignment, 1, quo);
        Rf_setAttrib(assignment, R_NamesSymbol, field_names);
        SET_VECTOR_ELT(result, index, assignment);
        UNPROTECT(6);
    }
    probe_general_phase_add(1, probe_general_clock_ns() - phase_start);
    phase_start = probe_general_clock_ns();
    guard_ok = C_dtatools_probe_bracket_public_live_raw(profile, caller);
    probe_general_phase_add(2, probe_general_clock_ns() - phase_start);
    if (!guard_ok) {
        UNPROTECT(1);
        return R_NilValue;
    }
    raw_parser_successes++;
    clear_raw_parser_pending();
    R_PreserveObject(result);
    clear_raw_parser_pending();
    raw_parser_pending = result;
    UNPROTECT(1);
    return result;
}

/* Bind only on success. During ordinary fallback, parser traces must see the
 * same still-unbound `assignments` local that clean HEAD exposes. */
SEXP C_dtatools_probe_bracket_raw_parser_into_frame(SEXP raw_j,
                                                     SEXP profile) {
    SEXP frame = R_GetCurrentEnv();
    SEXP symbol = Rf_install("assignments");
    if (TYPEOF(frame) != ENVSXP ||
        R_GetBindingType(symbol, frame) != R_BindingTypeUnbound)
        return Rf_ScalarLogical(FALSE);
    SEXP parsed = PROTECT(C_dtatools_probe_bracket_raw_five_parser(
        raw_j, profile));
    if (parsed == R_NilValue) {
        UNPROTECT(1);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP yes = PROTECT(Rf_ScalarLogical(TRUE));
    Rf_defineVar(symbol, parsed, frame);
    raw_parser_frame_bindings++;
    UNPROTECT(2);
    return yes;
}
