/* Plain and owned typed-double, ungrouped gen admission. Unsupported shapes and
   unaudited public dependencies continue through the ordinary R path. */
#include "dtatools-internal.h"
#include <float.h>

static int probe_attempts = 0;
static int probe_produced = 0;
static int probe_published = 0;
static int probe_gen_mode = 1;
static SEXP after_stage_hook = NULL;
extern int dtatools_probe_gen_public_guard_plain(SEXP frame, SEXP base,
                                                   SEXP public_state,
                                                   SEXP extra_state,
                                                   SEXP wrapper_state,
                                                   SEXP rlang_state,
                                                   SEXP s3_state, int grouped);
extern int dtatools_probe_gen_parse_caller(SEXP frame, SEXP *source_symbol,
                                           SEXP *target_name, SEXP *caller,
                                           double *increment);
extern SEXP C_dtatools_append_mark_reference(SEXP data, SEXP name,
                                             SEXP column, SEXP state,
                                             SEXP classes);

static int ascii_name(const char *value) {
    for (const unsigned char *p=(const unsigned char *)value; *p; ++p)
        if (*p > 127) return 0;
    return 1;
}

/* R column lookup is encoding-aware. A bytes-encoded name is left to the
   ordinary path; all other encodings compare in UTF-8 when pointer/ASCII
   identity does not suffice. The temporary copy survives the second
   translateCharUTF8 call. */
static int same_column_name(SEXP left, SEXP right) {
    if (Rf_getCharCE(left) == CE_BYTES || Rf_getCharCE(right) == CE_BYTES)
        return -1;
    if (left == right) return 1;
    const char *a = CHAR(left), *b = CHAR(right);
    int ascii_a = ascii_name(a), ascii_b = ascii_name(b);
    if (ascii_a && ascii_b) return strcmp(a,b) == 0;
    if (ascii_a != ascii_b) return 0;
    a = Rf_translateCharUTF8(left);
    size_t length = strlen(a);
    char *saved = (char *) R_alloc(length + 1, sizeof(char));
    memcpy(saved,a,length + 1);
    return strcmp(saved,Rf_translateCharUTF8(right)) == 0;
}

static R_xlen_t source_column_index(SEXP names, SEXP source_name,
                                    SEXP target_name) {
    R_xlen_t source_index = -1;
    for (R_xlen_t j = 0; j < XLENGTH(names); j++) {
        SEXP current = STRING_ELT(names, j);
        if (current == NA_STRING) return -1;
        int source_match = same_column_name(current, source_name);
        int target_match = same_column_name(current, target_name);
        if (source_match < 0 || target_match < 0 || target_match ||
            (source_match && source_index >= 0))
            return -1;
        if (source_match) source_index = j;
    }
    return source_index;
}

SEXP C_dtatools_probe_gen_after_stage(SEXP callback) {
    if (callback != R_NilValue && !Rf_isFunction(callback))
        Rf_error("after-stage hook must be a function or NULL");
    if (after_stage_hook != NULL) R_ReleaseObject(after_stage_hook);
    after_stage_hook = callback == R_NilValue ? NULL : callback;
    if (after_stage_hook != NULL) R_PreserveObject(after_stage_hook);
    return Rf_ScalarLogical(TRUE);
}

static void run_after_stage_hook(void) {
    if (after_stage_hook == NULL) return;
    SEXP callback = PROTECT(after_stage_hook);
    after_stage_hook = NULL;
    R_ReleaseObject(callback);
    SEXP call = PROTECT(Rf_lang1(callback));
    Rf_eval(call, R_GlobalEnv);
    UNPROTECT(2);
}

SEXP C_dtatools_probe_direct_final_stats(SEXP reset) {
    SEXP result = PROTECT(Rf_allocVector(INTSXP, 3));
    INTEGER(result)[0] = probe_attempts;
    INTEGER(result)[1] = probe_produced;
    INTEGER(result)[2] = probe_published;
    if (Rf_asLogical(reset)) probe_attempts = probe_produced = probe_published = 0;
    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_probe_direct_final_mode(SEXP mode) {
    int next = Rf_asLogical(mode);
    if (next == NA_LOGICAL) Rf_error("gen probe mode must be TRUE or FALSE");
    int previous = probe_gen_mode;
    probe_gen_mode = next;
    return Rf_ScalarLogical(previous);
}

static int probe_typed_column(SEXP column, R_xlen_t n, const char *storage_name,
                              const char *class_name, int grouping) {
    if (TYPEOF(column) != REALSXP || XLENGTH(column) != n ||
        !(grouping ? (R_altrep_inherits(column, dtatools_metadata_real_class) ||
                      R_altrep_inherits(column, dtatools_numeric_class))
                    : (!ALTREP(column) || owned_real(column))) ||
        (!grouping && ALTREP(column) && R_altrep_data2(column) != R_NilValue) ||
        !Rf_inherits(column, class_name)) return 0;
    if (!ALTREP(column)) {
        SEXP classes = Rf_getAttrib(column, R_ClassSymbol);
        static const char *expected[] = {"dta_numeric", "dta_double", "vctrs_vctr", "double"};
        if (Rf_isS4(column) || R_getAttribCount(column) != 2 ||
            TYPEOF(classes) != STRSXP || ALTREP(classes) || ANY_ATTRIB(classes) ||
            XLENGTH(classes) != 4) return 0;
        for (int i = 0; i < 4; ++i)
            if (strcmp(CHAR(STRING_ELT(classes, i)), expected[i])) return 0;
    }
    SEXP storage = Rf_getAttrib(column, Rf_install("stata.storage"));
    if (!ALTREP(column) && (ALTREP(storage) || ANY_ATTRIB(storage))) return 0;
    return TYPEOF(storage) == STRSXP && XLENGTH(storage) == 1 &&
        strcmp(CHAR(STRING_ELT(storage, 0)), storage_name) == 0;
}

static int omitted_null_formal(SEXP frame, const char *name) {
    SEXP symbol = Rf_install(name);
    return R_GetBindingType(symbol, frame) == R_BindingTypeDelayed &&
        R_DelayedBindingExpression(symbol, frame) == R_NilValue &&
        R_DelayedBindingEnvironment(symbol, frame) == frame;
}

SEXP C_dtatools_probe_direct_final(SEXP data, SEXP base_state,
                                   SEXP public_state, SEXP extra_state,
                                   SEXP wrapper_state,
                                   SEXP rlang_state, SEXP s3_state) {
    if (!probe_gen_mode) return Rf_ScalarLogical(FALSE);
    probe_attempts++;
    SEXP frame = R_GetCurrentEnv();
    SEXP frame_data = R_getVarEx(Rf_install("data"), frame, FALSE, R_NilValue);
    SEXP frame_dots = R_getVarEx(R_DotsSymbol, frame, FALSE, R_NilValue);
    SEXP frame_args = R_getVarEx(Rf_install("arguments"), frame, FALSE, R_NilValue);
    if (!omitted_null_formal(frame, "where") ||
        !omitted_null_formal(frame, "by") ||
        !omitted_null_formal(frame, "bysort"))
        return Rf_ScalarLogical(FALSE);
    if (frame_data != data || TYPEOF(frame_dots) != DOTSXP ||
        TYPEOF(frame_args) != VECSXP ||
        !omitted_null_formal(frame, "by"))
        return Rf_ScalarLogical(FALSE);
    SEXP placement = R_getVarEx(Rf_install("placement"), frame, FALSE, R_NilValue);
    SEXP generate_type = Rf_GetOption1(Rf_install("dtatools.generate_type"));
    if (placement != R_NilValue || TYPEOF(generate_type) != STRSXP ||
        XLENGTH(generate_type) != 1 ||
        strcmp(CHAR(STRING_ELT(generate_type, 0)), "double") != 0)
        return Rf_ScalarLogical(FALSE);
    SEXP source_symbol, target_name, caller;
    double increment;
    if (!dtatools_probe_gen_parse_caller(frame, &source_symbol,
                                         &target_name, &caller, &increment) ||
        TYPEOF(source_symbol) != SYMSXP || TYPEOF(target_name) != CHARSXP ||
        TYPEOF(caller) != ENVSXP)
        return Rf_ScalarLogical(FALSE);
    SEXP saved_source_symbol = source_symbol;
    SEXP saved_target_name = target_name;
    SEXP saved_caller = caller;
    double saved_increment = increment;
    if (TYPEOF(data) != VECSXP || !Rf_inherits(data, "dibble") ||
        !dtatools_reference_state_valid_noalloc(data)) return Rf_ScalarLogical(FALSE);
    R_xlen_t width = XLENGTH(data);
    if (width < 1 || width >= R_XLEN_T_MAX ||
        (double) width >= 9007199254740991.0)
        return Rf_ScalarLogical(FALSE);
    SEXP names = Rf_getAttrib(data, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || ALTREP(names) ||
        XLENGTH(names) != width) return Rf_ScalarLogical(FALSE);
    SEXP source_name = PRINTNAME(source_symbol);
    R_xlen_t source_index = source_column_index(names, source_name,
                                                target_name);
    if (source_index < 0) return Rf_ScalarLogical(FALSE);
    SEXP x = VECTOR_ELT(data, source_index);
    R_xlen_t n = XLENGTH(x);
    if (!probe_typed_column(x, n, "double", "dta_double", 0))
        return Rf_ScalarLogical(FALSE);
    if (!ALTREP(x) && !dtatools_probe_plain_public_guard()) return Rf_ScalarLogical(FALSE);
    SEXP x_backing = owned_real(x) ? owned_values(x) : x;
    if (TYPEOF(x_backing) != REALSXP || ALTREP(x_backing))
        return Rf_ScalarLogical(FALSE);
    SEXP needed = PROTECT(Rf_ScalarReal((double) width + 1));
    int ready = Rf_asLogical(C_dtatools_can_select_data_columns(data, needed));
    UNPROTECT(1);
    if (!ready || !dtatools_probe_gen_public_guard_plain(frame, base_state,
            public_state, extra_state, wrapper_state, rlang_state, s3_state, 0))
        return Rf_ScalarLogical(FALSE);

    SEXP backing = PROTECT(Rf_allocVector(REALSXP, n));
    SEXP column = PROTECT(owned_adopt_real(backing));
    SEXP storage = PROTECT(Rf_mkString("double"));
    Rf_setAttrib(column, Rf_install("stata.storage"), storage);
    SEXP column_classes = PROTECT(Rf_allocVector(STRSXP, 4));
    SET_STRING_ELT(column_classes, 0, Rf_mkChar("dta_numeric"));
    SET_STRING_ELT(column_classes, 1, Rf_mkChar("dta_double"));
    SET_STRING_ELT(column_classes, 2, Rf_mkChar("vctrs_vctr"));
    SET_STRING_ELT(column_classes, 3, Rf_mkChar("double"));
    Rf_setAttrib(column, R_ClassSymbol, column_classes);
    probe_produced++;

    /* The admitted reference dibble has the stable five-class marker. Build the
       non-owning owner state in the same C entry after the append. */
    SEXP classes = PROTECT(Rf_getAttrib(data, R_ClassSymbol));
    if (TYPEOF(classes) != STRSXP || XLENGTH(classes) != 5 ||
        strcmp(CHAR(STRING_ELT(classes, 0)), "dibble") != 0 ||
        strcmp(CHAR(STRING_ELT(classes, 1)), "dtatools_ref_data") != 0 ||
        strcmp(CHAR(STRING_ELT(classes, 2)), "tbl_df") != 0 ||
        strcmp(CHAR(STRING_ELT(classes, 3)), "tbl") != 0 ||
        strcmp(CHAR(STRING_ELT(classes, 4)), "data.frame") != 0) {
        UNPROTECT(5);
        return Rf_ScalarLogical(FALSE);
    }
    SEXP base_classes = PROTECT(Rf_allocVector(STRSXP, 3));
    for (int j = 0; j < 3; j++)
        SET_STRING_ELT(base_classes, j, STRING_ELT(classes, j + 2));
    SEXP state = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, 29));
    Rf_defineVar(Rf_install("classes"), base_classes, state);
    SEXP name = PROTECT(Rf_ScalarString(target_name));
    /* Stage polls precede the final public/source/frame certificate. The
       arithmetic loop itself stays callback-free, as in R's vector kernel. */
    R_CheckUserInterrupt();
    for (R_xlen_t boundary = 8192; boundary < n; boundary += 8192)
        R_CheckUserInterrupt();
    run_after_stage_hook();
    /* Source and active-frame certificates run after every staging
       allocation and explicit interrupt poll, before the output is read. */
    SEXP late_generate_type = Rf_GetOption1(Rf_install("dtatools.generate_type"));
    if (!dtatools_probe_gen_public_guard_plain(frame, base_state,
            public_state, extra_state, wrapper_state, rlang_state, s3_state, 0) ||
        TYPEOF(late_generate_type) != STRSXP ||
        XLENGTH(late_generate_type) != 1 ||
        strcmp(CHAR(STRING_ELT(late_generate_type, 0)), "double") != 0 ||
        R_getVarEx(Rf_install("data"), frame, FALSE, R_NilValue) != frame_data ||
        R_getVarEx(R_DotsSymbol, frame, FALSE, R_NilValue) != frame_dots ||
        R_getVarEx(Rf_install("arguments"), frame, FALSE, R_NilValue) != frame_args ||
        !omitted_null_formal(frame, "where") ||
        !omitted_null_formal(frame, "by") ||
        !omitted_null_formal(frame, "bysort") ||
        R_getVarEx(Rf_install("placement"), frame, FALSE, R_NilValue) != R_NilValue ||
        XLENGTH(data) != width ||
        VECTOR_ELT(data, source_index) != x ||
        (owned_real(x) ? owned_values(x) : x) != x_backing ||
        (!ALTREP(x) && !dtatools_probe_plain_public_guard()) ||
        !probe_typed_column(x, n, "double", "dta_double", 0) ||
        Rf_getAttrib(data, R_NamesSymbol) != names ||
        Rf_getAttrib(data, R_ClassSymbol) != classes ||
        !dtatools_probe_gen_parse_caller(frame, &source_symbol,
                                         &target_name, &caller, &increment) ||
        source_symbol != saved_source_symbol ||
        target_name != saved_target_name || caller != saved_caller ||
        increment != saved_increment ||
        STRING_ELT(name, 0) != target_name ||
        source_column_index(names, source_name, target_name) != source_index ||
        !dtatools_reference_state_valid_noalloc(data)) {
        UNPROTECT(8);
        return Rf_ScalarLogical(FALSE);
    }
    const double *xp = REAL(x_backing);
    double *output = REAL(backing);
    int nonfinite = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        double result = xp[i] + increment;
        output[i] = result;
        nonfinite |= !isfinite(xp[i]) |
            !(result >= -DBL_MAX / 2.0 && result <= DBL_MAX / 2.0);
    }
    if (nonfinite) { UNPROTECT(8); return Rf_ScalarLogical(FALSE); }
    SEXP appended = PROTECT(C_dtatools_append_mark_reference(
        data, name, column, state, classes));
    if (!Rf_asLogical(appended)) {
        UNPROTECT(9);
        return Rf_ScalarLogical(FALSE);
    }
    probe_published++;
    UNPROTECT(9);
    return Rf_ScalarLogical(TRUE);
}
