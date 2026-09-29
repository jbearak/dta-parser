/* Initial shell extraction and generation capture with fresh call-local proof. */
static double initial_capture_counts[13];
/* Diagnostic selector: 0 = disabled, 1 = shell, 2 = batch, 3 = both. */
static int initial_capture_mode = 3;
/* Conservative crossover from paired width measurements. */
static const R_xlen_t initial_capture_min_width = 64;
/* Paired public-call screens favor the R loop through this width. */
static const R_xlen_t initial_capture_max_r_width = 128;

SEXP C_dtatools_initial_capture_mode(SEXP value) {
    int old = initial_capture_mode;
    if (value != R_NilValue) {
        if (TYPEOF(value) != INTSXP || XLENGTH(value) != 1 ||
            INTEGER(value)[0] < 0 || INTEGER(value)[0] > 3)
            Rf_error("initial capture mode must be 0, 1, 2 or 3");
        initial_capture_mode = INTEGER(value)[0];
    }
    return Rf_ScalarInteger(old);
}

SEXP C_dtatools_initial_capture_stats(SEXP reset) {
    static const char *names[] = {"shell_attempts", "shell_admitted", "batch_attempts",
        "batch_admitted", "generations", "owned", "compact", "frame_decline",
        "dependency_decline", "shape_decline", "state_decline", "commit_decline", "last_dependency"};
    SEXP out = PROTECT(Rf_allocVector(REALSXP, 13));
    SEXP labels = PROTECT(Rf_allocVector(STRSXP, 13));
    for (int i = 0; i < 13; i++) {
        REAL(out)[i] = initial_capture_counts[i];
        SET_STRING_ELT(labels, i, Rf_mkChar(names[i]));
    }
    Rf_setAttrib(out, R_NamesSymbol, labels);
    if (Rf_asLogical(reset) == TRUE) memset(initial_capture_counts, 0, sizeof(initial_capture_counts));
    UNPROTECT(2);
    return out;
}

static int initial_capture_profile(SEXP frame, SEXP profile, int route) {
    if (!combine_plain_list(profile) || XLENGTH(profile) != 9 ||
        !combine_plain_list(VECTOR_ELT(profile, 3)) || XLENGTH(VECTOR_ELT(profile, 3)) != 5 ||
        !combine_plain_list(VECTOR_ELT(profile, 4)) || XLENGTH(VECTOR_ELT(profile, 4)) != 28 ||
        !combine_plain_environment(VECTOR_ELT(profile, 5))) return 0;
    SEXP state = computed_peek(Rf_install(".metadata_state"), frame, 16);
    if (dtatools_metadata_profile_from_state(state) == R_NilValue) return 0;
    return dtatools_execution_frame_same(frame, VECTOR_ELT(profile, route));
}

static int initial_capture_strings(SEXP value, R_xlen_t size) {
    return TYPEOF(value) == STRSXP && !ALTREP(value) && !ANY_ATTRIB(value) &&
        !Rf_isObject(value) && !Rf_isS4(value) && XLENGTH(value) == size;
}

static int initial_capture_slot(SEXP frame, SEXP name, int empty) {
    if (!combine_plain_environment(frame) || R_EnvironmentIsLocked(frame)) return 0;
    R_BindingType_t type = R_GetBindingType(name, frame);
    if (type == R_BindingTypeUnbound) return 1;
    return !empty && (type == R_BindingTypeValue || type == R_BindingTypeForced) &&
        !R_BindingIsLocked(name, frame);
}

/* A bounded decline-only prefilter for an as-yet unqualified frame.
   Each lookup environment must be ordinary: user databases can run their
   get callback even from R_GetBindingType. Never force an operand expression.
   A forced getter can process pending finalizers/interrupts, so keep the walk
   rooted and retain neither its operand nor its verdict as execution proof. */
static int initial_capture_wide_frame(SEXP frame, SEXP symbol, R_xlen_t *width_out) {
    SEXP expression = symbol, environment = frame, value = R_UnboundValue;
    PROTECT_INDEX expression_root, environment_root;
    PROTECT_WITH_INDEX(expression, &expression_root);
    PROTECT_WITH_INDEX(environment, &environment_root);
    for (int remaining = 16; remaining > 0; remaining--) {
        if (expression == R_MissingArg || expression == R_UnboundValue) break;
        if (TYPEOF(expression) != SYMSXP) {
            if (TYPEOF(expression) != LANGSXP) value = expression;
            break;
        }
        if (!combine_plain_environment(environment) || environment == R_EmptyEnv) break;
        R_BindingType_t type = R_GetBindingType(expression, environment);
        if (type == R_BindingTypeValue || type == R_BindingTypeForced) {
            value = R_getVar(expression, environment, FALSE);
            break;
        }
        if (type == R_BindingTypeDelayed) {
            SEXP next_expression = R_DelayedBindingExpression(expression, environment);
            SEXP next_environment = R_DelayedBindingEnvironment(expression, environment);
            REPROTECT(expression = next_expression, expression_root);
            REPROTECT(environment = next_environment, environment_root);
        } else if (type == R_BindingTypeUnbound) {
            REPROTECT(environment = R_ParentEnv(environment), environment_root);
        } else break;
    }
    PROTECT(value);
    int wide = TYPEOF(value) == VECSXP && !ALTREP(value) && !Rf_isS4(value) &&
        XLENGTH(value) >= initial_capture_min_width;
    if (wide && width_out != NULL) *width_out = XLENGTH(value);
    UNPROTECT(3);
    return wide;
}

static int initial_capture_shell_dependencies(SEXP frame, SEXP profile) {
    SEXP package = VECTOR_ELT(profile, 3), primitive = VECTOR_ELT(profile, 4);
    SEXP columns = VECTOR_ELT(package, 0), plain = VECTOR_ELT(package, 1);
    if (!dtatools_execution_lexical_function_same(frame, Rf_install(".data_columns"), columns) ||
        !dtatools_execution_lexical_function_same(R_ClosureEnv(columns), Rf_install(".plain_data_columns"), plain)) return 0;
    static const char *names[] = {"unclass", "attributes<-", "names<-", "attr"};
    for (int i = 0; i < 4; i++) {
        SEXP environment = i < 2 ? R_ClosureEnv(plain) : R_ClosureEnv(columns);
        if (!dtatools_execution_lexical_function_same(environment, Rf_install(names[i]), VECTOR_ELT(primitive, i))) return 0;
    }
    return 1;
}

SEXP C_dtatools_initial_capture_shell(SEXP profile) {
    if (!(initial_capture_mode & 1)) return Rf_ScalarLogical(FALSE);
    initial_capture_counts[0]++;
    SEXP frame = R_GetCurrentEnv(), target = Rf_install("columns");
    if (!initial_capture_wide_frame(frame, Rf_install("data"), NULL)) {
        initial_capture_counts[9]++; return Rf_ScalarLogical(FALSE);
    }
    if (!initial_capture_profile(frame, profile, 0)) {
        initial_capture_counts[7]++; return Rf_ScalarLogical(FALSE);
    }
    if (!initial_capture_shell_dependencies(frame, profile)) {
        initial_capture_counts[8]++; return Rf_ScalarLogical(FALSE);
    }
    SEXP data = PROTECT(computed_peek(Rf_install("data"), frame, 16));
    if (TYPEOF(data) != VECSXP || ALTREP(data) || Rf_isS4(data) ||
        !initial_capture_slot(frame, target, 1)) {
        UNPROTECT(1); initial_capture_counts[9]++; return Rf_ScalarLogical(FALSE);
    }
    SEXP names = PROTECT(Rf_getAttrib(data, R_NamesSymbol));
    R_xlen_t width = XLENGTH(data);
    if (width > 4096 || !initial_capture_strings(names, width)) {
        UNPROTECT(2); initial_capture_counts[9]++; return Rf_ScalarLogical(FALSE);
    }
    SEXP columns = PROTECT(Rf_allocVector(VECSXP, width));
    for (R_xlen_t i = 0; i < width; i++) SET_VECTOR_ELT(columns, i, VECTOR_ELT(data, i));
    Rf_setAttrib(columns, R_NamesSymbol, names);
    if (!initial_capture_slot(frame, target, 1)) {
        UNPROTECT(3); initial_capture_counts[11]++; return Rf_ScalarLogical(FALSE);
    }
    /* The skipped source helper forced this original forwarding chain. */
    R_getVar(Rf_install("data"), frame, TRUE);
    Rf_defineVar(target, columns, frame);
    initial_capture_counts[1]++;
    UNPROTECT(3);
    return Rf_ScalarLogical(TRUE);
}

static int initial_capture_add_same(SEXP frame, SEXP expected) {
    SEXP actual = R_NilValue;
    if (combine_peek_frame(frame, Rf_install("add"), &actual) != COMBINE_VALUE ||
        TYPEOF(actual) != CLOSXP || TYPEOF(expected) != CLOSXP ||
        R_ClosureEnv(actual) != frame ||
        R_mapAttrib(actual, scalar_source_attribute, NULL) != NULL) return 0;
    int remaining = 4096;
    return scalar_same_expression(R_ClosureFormals(actual), R_ClosureFormals(expected), &remaining) &&
        scalar_same_expression(R_ClosureExpr(actual), R_ClosureExpr(expected), &remaining) &&
        TYPEOF(R_ClosureBody(actual)) == BCODESXP && TYPEOF(R_ClosureBody(expected)) == BCODESXP &&
        numeric_bytecode_identical_safe(R_ClosureBody(actual), R_ClosureBody(expected));
}

/* The loaded rlang export route mirrors the production vctrs export guard.
   No registry lookup or delayed/export callback is used to decide admission. */
static SEXP initial_capture_weakref_export(SEXP frame, SEXP ns, SEXP colon) {
    SEXP info, spec, exports, alias, function;
    SEXP name = Rf_install("new_weakref"), spec_symbol = Rf_install("spec");
    if (!dtatools_execution_lexical_function_same(frame, Rf_install("::"), colon) ||
        R_GetBindingType(R_NamespaceEnvSymbol, ns) != R_BindingTypeValue ||
        combine_peek_frame(ns, R_NamespaceEnvSymbol, &info) != COMBINE_VALUE ||
        !combine_plain_environment(info) ||
        combine_peek_frame(info, spec_symbol, &spec) != COMBINE_VALUE ||
        TYPEOF(spec) != STRSXP || ALTREP(spec) ||
        R_mapAttrib(spec, computed_attribute, NULL) != NULL ||
        XLENGTH(spec) < 1 || XLENGTH(spec) > 8 || STRING_ELT(spec, 0) == NA_STRING ||
        strcmp(CHAR(STRING_ELT(spec, 0)), "rlang") != 0 ||
        combine_peek_frame(info, Rf_install("exports"), &exports) != COMBINE_VALUE ||
        combine_peek_frame(exports, name, &alias) != COMBINE_VALUE ||
        !initial_capture_strings(alias, 1) || STRING_ELT(alias, 0) == NA_STRING ||
        strcmp(CHAR(STRING_ELT(alias, 0)), "new_weakref") != 0 ||
        combine_peek_frame(ns, name, &function) != COMBINE_VALUE) return R_UnboundValue;
    return function;
}

static int initial_capture_dependencies(SEXP frame, SEXP profile) {
    static const char *package_names[] = {".capture_dibble_nested", ".metadata_copy", ".repair_data_table_container"};
    static const char *primitive_names[] = {"unclass", "attributes<-", "names<-", "attr",
        "emptyenv", "$", "$<-", "[[", "[[<-", "names", "c", "length", "+",
        "is.null", "is.environment", "is.function", "typeof", "!=", ">",
        ".Call", ".Internal", "::", "for", "{", "<-", "if", "return", "||"};
    SEXP package = VECTOR_ELT(profile, 3), primitives = VECTOR_ELT(profile, 4);
    initial_capture_counts[12] = 1;
    if (!initial_capture_add_same(frame, VECTOR_ELT(profile, 2))) return 0;
    for (int i = 0; i < 3; i++)
        if (!dtatools_execution_lexical_function_same(frame, Rf_install(package_names[i]), VECTOR_ELT(package, i + 2))) {
            initial_capture_counts[12] = 10 + i; return 0;
        }
    initial_capture_counts[12] = 20;
    if (!dtatools_execution_lexical_function_same(frame, Rf_install("new.env"), VECTOR_ELT(profile, 7)) ||
        !dtatools_execution_lexical_function_same(frame, Rf_install("%in%"), VECTOR_ELT(profile, 8))) return 0;
    /* The exact compiled repair route uses internal inherits; its R wrapper
       is not a live dependency. Changed/decompiled repair code already fails. */
    for (int i = 4; i < 28; i++) {
        /* Exact compiled capture executes TYPEOF without settling the lazy
           base wrapper. Independent delayed-binding probes confirm that
           ordinary capture leaves it delayed; changed code fails above. */
        if (i == 16) continue;
        SEXP symbol = Rf_install(primitive_names[i]), expected = VECTOR_ELT(primitives, i);
        if (!dtatools_execution_lexical_function_same(frame, symbol, expected) ||
            !dtatools_execution_lexical_function_same(R_BaseNamespace, symbol, expected)) {
            initial_capture_counts[12] = 100 + i; return 0;
        }
    }
    SEXP rlang = VECTOR_ELT(profile, 5);
    SEXP weak = initial_capture_weakref_export(frame, rlang, VECTOR_ELT(primitives, 21));
    /* This specific audited wrapper contains only a .Call expression over
       its four formals. The complete interpreted/compiled lexical graph is
       checked; source references in standard compiler pools need not match. */
    initial_capture_counts[12] = 200;
    int admitted = scalar_same_function(weak, VECTOR_ELT(profile, 6)) &&
        dtatools_execution_lexical_function_same(rlang, Rf_install(".Call"), VECTOR_ELT(primitives, 19)) &&
        dtatools_execution_lexical_function_same(rlang, Rf_install("{"), VECTOR_ELT(primitives, 23));
    if (admitted) initial_capture_counts[12] = 0;
    return admitted;
}

static SEXP initial_capture_numeric_attribute(SEXP name, SEXP value, void *context) {
    unsigned *seen = context;
    if (name == R_ClassSymbol) {
        if (!initial_capture_strings(value, 4)) return R_NilValue;
        for (int i = 0; i < 4; i++) if (!mask_bindings_ascii_name(STRING_ELT(value, i))) return R_NilValue;
        *seen |= 1U;
    } else if (name == Rf_install("stata.storage")) {
        if (!initial_capture_strings(value, 1) || !mask_bindings_ascii_name(STRING_ELT(value, 0))) return R_NilValue;
        *seen |= 2U;
    } else return R_NilValue;
    return NULL;
}

static int initial_capture_numeric_column(SEXP value) {
    if (TYPEOF(value) != REALSXP || !Rf_isObject(value) || Rf_isS4(value)) return 0;
    unsigned seen = 0;
    if (R_mapAttrib(value, initial_capture_numeric_attribute, &seen) != NULL || seen != 3U) return 0;
    SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
    int kind = computed_storage_kind(Rf_getAttrib(value, Rf_install("stata.storage")));
    static const char *storage_classes[] = {"dta_byte", "dta_int", "dta_long", "dta_float", "dta_double"};
    if (kind < 0 || strcmp(CHAR(STRING_ELT(classes, 0)), "dta_numeric") ||
        strcmp(CHAR(STRING_ELT(classes, 1)), storage_classes[kind]) ||
        strcmp(CHAR(STRING_ELT(classes, 2)), "vctrs_vctr") ||
        strcmp(CHAR(STRING_ELT(classes, 3)), "double")) return 0;
    if (owned_real(value)) return kind == NUMERIC_DOUBLE ? 1 : 0;
    if (!ALTREP(value) || !R_altrep_inherits(value, dtatools_numeric_class) ||
        R_altrep_data2(value) != R_NilValue || TYPEOF(R_altrep_data1(value)) != EXTPTRSXP ||
        R_ExternalPtrAddr(R_altrep_data1(value)) == NULL) return 0;
    return 2;
}

static int initial_capture_initial_state(SEXP frame, SEXP *state, SEXP *current, SEXP *history, SEXP *names) {
    static const char *fields[] = {"current", "generations", "names"};
    if (combine_peek_frame(frame, Rf_install("state"), state) != COMBINE_VALUE ||
        !combine_plain_environment(*state) || R_EnvironmentIsLocked(*state) ||
        combine_peek_frame(*state, Rf_install(fields[0]), current) != COMBINE_VALUE ||
        combine_peek_frame(*state, Rf_install(fields[1]), history) != COMBINE_VALUE ||
        combine_peek_frame(*state, Rf_install(fields[2]), names) != COMBINE_VALUE ||
        !combine_plain_list(*current) || XLENGTH(*current) != 0 ||
        !combine_plain_list(*history) || XLENGTH(*history) != 0 || !initial_capture_strings(*names, 0)) return 0;
    for (int i = 0; i < 3; i++) if (R_BindingIsLocked(Rf_install(fields[i]), *state)) return 0;
    return initial_capture_slot(frame, Rf_install("name"), 0);
}

SEXP C_dtatools_initial_capture_initial(SEXP profile) {
    if (!(initial_capture_mode & 2)) return Rf_ScalarLogical(FALSE);
    initial_capture_counts[2]++;
    SEXP frame = R_GetCurrentEnv();
    R_xlen_t checked_width = 0;
    if (!initial_capture_wide_frame(frame, Rf_install("columns"), &checked_width)) {
        initial_capture_counts[9]++; return Rf_ScalarLogical(FALSE);
    }
    /* No second operand read: use the same ordinary list header that passed
       the existing bounded prefilter, then let the original R add loop run. */
    if (checked_width <= initial_capture_max_r_width) {
        initial_capture_counts[9]++; return Rf_ScalarLogical(FALSE);
    }
    if (!initial_capture_profile(frame, profile, 1)) {
        initial_capture_counts[7]++; return Rf_ScalarLogical(FALSE);
    }
    if (!initial_capture_dependencies(frame, profile)) {
        initial_capture_counts[8]++; return Rf_ScalarLogical(FALSE);
    }
    SEXP columns = PROTECT(computed_peek(Rf_install("columns"), frame, 16));
    if (TYPEOF(columns) != VECSXP || ALTREP(columns) || Rf_isObject(columns) || Rf_isS4(columns) ||
        R_mapAttrib(columns, mask_bindings_current_attribute, NULL) != NULL ||
        XLENGTH(columns) == 0 || XLENGTH(columns) > 4096) {
        UNPROTECT(1); initial_capture_counts[9]++; return Rf_ScalarLogical(FALSE);
    }
    R_xlen_t width = XLENGTH(columns);
    SEXP names = PROTECT(Rf_getAttrib(columns, R_NamesSymbol));
    if (!initial_capture_strings(names, width)) {
        UNPROTECT(2); initial_capture_counts[9]++; return Rf_ScalarLogical(FALSE);
    }
    R_xlen_t owned = 0, compact = 0;
    for (R_xlen_t i = 0; i < width; i++) {
        SEXP name = STRING_ELT(names, i);
        if (!mask_bindings_ascii_name(name)) {
            UNPROTECT(2); initial_capture_counts[9]++; return Rf_ScalarLogical(FALSE);
        }
        /* ASCII CHARSXPs are immutable and interned, independently of the
           requested encoding. Re-read each earlier slot after the unchanged
           interrupt polls; retaining a hash bucket across them could be stale.
           NA_STRING is the uncached exception: a callback can replace an
           earlier slot with NA, whose bytes the original strcmp also reads. */
        for (R_xlen_t j = 0; j < i; j++) {
            SEXP previous = STRING_ELT(names, j);
            if (name == previous ||
                (previous == NA_STRING && !strcmp(CHAR(name), CHAR(previous)))) {
                UNPROTECT(2); initial_capture_counts[9]++; return Rf_ScalarLogical(FALSE);
            }
        }
        int kind = initial_capture_numeric_column(VECTOR_ELT(columns, i));
        if (!kind) { UNPROTECT(2); initial_capture_counts[9]++; return Rf_ScalarLogical(FALSE); }
        if (kind == 1) owned++; else compact++;
    }
    SEXP state, old_current, old_history, old_names;
    if (!initial_capture_initial_state(frame, &state, &old_current, &old_history, &old_names)) {
        UNPROTECT(2); initial_capture_counts[10]++; return Rf_ScalarLogical(FALSE);
    }
    PROTECT(state); PROTECT(old_current); PROTECT(old_history); PROTECT(old_names);
    SEXP current = PROTECT(Rf_allocVector(VECSXP, width));
    SEXP history = PROTECT(Rf_allocVector(VECSXP, width));
    SEXP current_names = PROTECT(Rf_allocVector(STRSXP, width));
    SEXP registered = PROTECT(Rf_allocVector(STRSXP, width));
    SEXP unused = PROTECT(Rf_ScalarLogical(FALSE));
    SEXP name = PROTECT(Rf_ScalarString(STRING_ELT(names, width - 1)));
    SEXP value_symbol = Rf_install("value"), chunks_symbol = Rf_install("chunks"), used_symbol = Rf_install("used");
    for (R_xlen_t i = 0; i < width; i++) {
        R_CheckUserInterrupt();
        SEXP generation = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, 29));
        SEXP captured = PROTECT(C_dtatools_metadata_copy(VECTOR_ELT(columns, i)));
        Rf_defineVar(value_symbol, captured, generation);
        Rf_defineVar(chunks_symbol, R_NilValue, generation);
        Rf_defineVar(used_symbol, unused, generation);
        SET_VECTOR_ELT(current, i, generation);
        SET_STRING_ELT(current_names, i, STRING_ELT(names, i));
        SET_STRING_ELT(registered, i, STRING_ELT(names, i));
        SEXP weak = PROTECT(R_MakeWeakRef(generation, R_NilValue, R_NilValue, FALSE));
        SET_VECTOR_ELT(history, i, weak);
        UNPROTECT(3);
    }
    Rf_setAttrib(current, R_NamesSymbol, current_names);
    SEXP now_state, now_current, now_history, now_names;
    if (!initial_capture_initial_state(frame, &now_state, &now_current, &now_history, &now_names) ||
        now_state != state || now_current != old_current || now_history != old_history || now_names != old_names) {
        UNPROTECT(12); initial_capture_counts[11]++; return Rf_ScalarLogical(FALSE);
    }
    Rf_defineVar(Rf_install("current"), current, state);
    Rf_defineVar(Rf_install("generations"), history, state);
    Rf_defineVar(Rf_install("names"), registered, state);
    Rf_defineVar(Rf_install("name"), name, frame);
    initial_capture_counts[3]++; initial_capture_counts[4] += width;
    initial_capture_counts[5] += owned; initial_capture_counts[6] += compact;
    UNPROTECT(12);
    return Rf_ScalarLogical(TRUE);
}
