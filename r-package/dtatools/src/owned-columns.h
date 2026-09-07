/* Ordinary atomic backing. Included by init.c so capture, forks and private
   writes share the same implementation. The payload stays on R's vector heap;
   handles retain it through their backing record, without a global registry.
   A public writable pointer permanently makes its backing non-shareable. */
static R_altrep_class_t dtatools_owned_real_class;
static R_altrep_class_t dtatools_owned_integer_class;
static R_altrep_class_t dtatools_owned_logical_class;
static R_altrep_class_t dtatools_owned_string_class;
static double owned_string_scans = 0;
static double owned_string_scanned_values = 0;

/* Non-owning measurement counters. Durable payload is on R's heap; these
   counters also expose native scratch/journal costs that Rprofmem cannot see. */
static double owned_capture_bytes = 0;
static double compact_copy_bytes = 0;
static double mutation_target_copy_bytes = 0;
static double staged_new_bytes = 0;
static double old_journal_bytes = 0;
static double native_scratch_allocated = 0;

enum { OWNED_VALUES, OWNED_FLAGS, OWNED_RECORD_SIZE };
enum { OWNED_SHARED, OWNED_EXPOSED, OWNED_NO_NA, OWNED_MAX_WIDTH, OWNED_WIDTH_EXACT, OWNED_FLAGS_SIZE };

static int owned_real(SEXP value) {
    return ALTREP(value) && R_altrep_inherits(value, dtatools_owned_real_class);
}

static int owned_column(SEXP value) {
    return owned_real(value) || (ALTREP(value) &&
        (R_altrep_inherits(value, dtatools_owned_integer_class) ||
         R_altrep_inherits(value, dtatools_owned_logical_class) ||
         R_altrep_inherits(value, dtatools_owned_string_class)));
}

static R_altrep_class_t owned_class(SEXPTYPE type) {
    switch (type) {
    case REALSXP: return dtatools_owned_real_class;
    case INTSXP: return dtatools_owned_integer_class;
    case LGLSXP: return dtatools_owned_logical_class;
    case STRSXP: return dtatools_owned_string_class;
    default: Rf_error("unsupported owned column storage");
    }
    return dtatools_owned_real_class;
}

static size_t owned_width(SEXP value) {
    return TYPEOF(value) == REALSXP ? sizeof(double) :
        TYPEOF(value) == STRSXP ? sizeof(SEXP) : sizeof(int);
}

static SEXP owned_values(SEXP value) {
    return VECTOR_ELT(R_altrep_data1(value), OWNED_VALUES);
}

static int *owned_flags(SEXP value) {
    return INTEGER(VECTOR_ELT(R_altrep_data1(value), OWNED_FLAGS));
}

static SEXP owned_record(SEXP values) {
    SEXP record = PROTECT(Rf_allocVector(VECSXP, OWNED_RECORD_SIZE));
    SEXP flags = PROTECT(Rf_allocVector(INTSXP, OWNED_FLAGS_SIZE));
    INTEGER(flags)[OWNED_SHARED] = 0;
    INTEGER(flags)[OWNED_EXPOSED] = 0;
    INTEGER(flags)[OWNED_NO_NA] = -1;
    INTEGER(flags)[OWNED_MAX_WIDTH] = -1;
    INTEGER(flags)[OWNED_WIDTH_EXACT] = 0;
    SET_VECTOR_ELT(record, OWNED_VALUES, values);
    SET_VECTOR_ELT(record, OWNED_FLAGS, flags);
    UNPROTECT(2);
    return record;
}

/* Call only at a native allocation's completion, before publishing values or
   retaining a writer. R callers must use capture; they cannot assert freshness. */
static SEXP owned_adopt(SEXP values) {
    if (ALTREP(values) || (TYPEOF(values) != REALSXP && TYPEOF(values) != INTSXP &&
        TYPEOF(values) != LGLSXP && TYPEOF(values) != STRSXP)) {
        Rf_error("invalid native ordinary-column adoption");
    }
    SEXP record = PROTECT(owned_record(values));
    SEXP result = PROTECT(R_new_altrep(owned_class(TYPEOF(values)), record, R_NilValue));
    SHALLOW_DUPLICATE_ATTRIB(result, values);
    CLEAR_ATTRIB(values);
    UNPROTECT(2);
    return result;
}

static SEXP owned_adopt_real(SEXP values) {
    if (TYPEOF(values) != REALSXP) Rf_error("invalid native ordinary-double adoption");
    return owned_adopt(values);
}

static int known_numeric_classes(SEXP value, int compact) {
    if (TYPEOF(value) != REALSXP || Rf_getAttrib(value, R_DimSymbol) != R_NilValue) return 0;
    SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
    if (classes == R_NilValue) return 1;
    const char *supported[] = {
        "dta_double", "dta_numeric", "dta_temporal", "dta_date", "dta_datetime",
        "Date", "POSIXct", "POSIXt", "haven_labelled", "vctrs_vctr", "double",
        "dtatools_dta_metadata_vector"
    };
    if (TYPEOF(classes) != STRSXP || ALTREP(classes) || ANY_ATTRIB(classes)) return 0;
    for (R_xlen_t i = 0; i < XLENGTH(classes); i++) {
        int known = 0;
        const char *name = CHAR(STRING_ELT(classes, i));
        if (compact && (strcmp(name, "dta_byte") == 0 ||
            strcmp(name, "dta_int") == 0 || strcmp(name, "dta_long") == 0 ||
            strcmp(name, "dta_float") == 0)) known = 1;
        for (size_t j = 0; j < sizeof(supported) / sizeof(supported[0]); j++) {
            if (strcmp(name, supported[j]) == 0) { known = 1; break; }
        }
        if (!known) return 0;
    }
    return 1;
}

static int owned_real_supported(SEXP value) {
    return known_numeric_classes(value, 0) && (!ALTREP(value) || owned_real(value));
}

static int owned_supported(SEXP value) {
    if (TYPEOF(value) == REALSXP) return owned_real_supported(value);
    if (Rf_getAttrib(value, R_DimSymbol) != R_NilValue ||
        (ALTREP(value) && !owned_column(value))) return 0;
    int type = TYPEOF(value);
    if (type != STRSXP && type != INTSXP && type != LGLSXP) return 0;
    SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
    if (classes == R_NilValue) return !Rf_isObject(value);
    if (TYPEOF(classes) != STRSXP || ALTREP(classes) || ANY_ATTRIB(classes)) return 0;
    for (R_xlen_t i = 0; i < XLENGTH(classes); i++) {
        const char *name = CHAR(STRING_ELT(classes, i));
        if (strcmp(name, "dtatools_dta_metadata_vector") == 0) continue;
        if (type == STRSXP && (strcmp(name, "dta_string") == 0 ||
            strcmp(name, "vctrs_vctr") == 0 || strcmp(name, "character") == 0)) continue;
        if (type == INTSXP && (strcmp(name, "factor") == 0 || strcmp(name, "ordered") == 0)) continue;
        return 0;
    }
    return 1;
}

/* Match nchar(enc2utf8(x), type = "bytes"), including byte-marked strings.
   The ordinary payload cannot call back while these facts are computed. */
static int owned_string_width(SEXP value) {
    return Rf_getCharCE(value) == CE_BYTES ? LENGTH(value) :
        (int) strlen(Rf_translateCharUTF8(value));
}

static void owned_scan_strings(SEXP value) {
    SEXP record = PROTECT(R_altrep_data1(value));
    SEXP payload = VECTOR_ELT(record, OWNED_VALUES);
    int no_na = 1, maximum = 0;
    owned_string_scans++;
    for (R_xlen_t i = 0; i < XLENGTH(payload); i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        SEXP item = STRING_ELT(payload, i);
        owned_string_scanned_values++;
        if (item == NA_STRING) no_na = 0;
        else { int width = owned_string_width(item); if (width > maximum) maximum = width; }
    }
    int *flags = INTEGER(VECTOR_ELT(record, OWNED_FLAGS));
    flags[OWNED_NO_NA] = no_na;
    flags[OWNED_MAX_WIDTH] = maximum;
    flags[OWNED_WIDTH_EXACT] = 1;
    UNPROTECT(1);
}

static SEXP owned_capture(SEXP value) {
    R_xlen_t length = XLENGTH(value);
    SEXP values = PROTECT(Rf_allocVector(TYPEOF(value), length));
    switch (TYPEOF(value)) {
    case REALSXP:
        if (REAL_GET_REGION(value, 0, length, REAL(values)) != length)
            Rf_error("failed to capture an ordinary-double column");
        break;
    case INTSXP:
        if (INTEGER_GET_REGION(value, 0, length, INTEGER(values)) != length)
            Rf_error("failed to capture an ordinary-integer column");
        break;
    case LGLSXP:
        if (LOGICAL_GET_REGION(value, 0, length, LOGICAL(values)) != length)
            Rf_error("failed to capture an ordinary-logical column");
        break;
    case STRSXP:
        for (R_xlen_t i = 0; i < length; i++) {
            if ((i & 16383) == 0) R_CheckUserInterrupt();
            SET_STRING_ELT(values, i, STRING_ELT(value, i));
        }
        break;
    default: Rf_error("unsupported owned column capture");
    }
    owned_capture_bytes += (double) length * owned_width(value);
    SEXP result = PROTECT(owned_adopt(values));
    SHALLOW_DUPLICATE_ATTRIB(result, value);
    if (owned_column(value) && !owned_flags(value)[OWNED_EXPOSED]) {
        for (int i = OWNED_NO_NA; i < OWNED_FLAGS_SIZE; i++)
            owned_flags(result)[i] = owned_flags(value)[i];
    }
    UNPROTECT(2);
    return result;
}

static SEXP owned_capture_real(SEXP value) { return owned_capture(value); }

static SEXP owned_fork(SEXP value) {
    if (!owned_column(value) || owned_flags(value)[OWNED_EXPOSED]) return owned_capture(value);
    SEXP result = PROTECT(R_new_altrep(owned_class(TYPEOF(value)), R_altrep_data1(value), R_NilValue));
    SHALLOW_DUPLICATE_ATTRIB(result, value);
    owned_flags(value)[OWNED_SHARED] = 1;
    UNPROTECT(1);
    return result;
}

static SEXP owned_fork_real(SEXP value) { return owned_fork(value); }

static SEXP C_dtatools_capture_column(SEXP value) {
    if (!owned_supported(value)) return value;
    SEXP result = PROTECT(owned_fork(value));
    /* Public ingress has already normalized declarations. Prime facts on the
       captured payload so the first operation needs no repeat value scan. */
    if (TYPEOF(result) == STRSXP &&
        Rf_getAttrib(result, Rf_install("stata.string.storage")) != R_NilValue &&
        (owned_flags(result)[OWNED_MAX_WIDTH] < 0 || owned_flags(result)[OWNED_NO_NA] < 0)) {
        owned_scan_strings(result);
    }
    UNPROTECT(1);
    return result;
}

/* A subset upper bound proves wide declarations, but a narrow declaration
   needs an exact maximum before it can be rejected. Exposed backing is rescanned. */
static SEXP C_dtatools_owned_string_fits(SEXP value, SEXP width) {
    if (TYPEOF(value) != STRSXP || !owned_column(value) || !owned_supported(value)) return R_NilValue;
    double limit = Rf_asReal(width);
    int *flags = owned_flags(value);
    if (flags[OWNED_EXPOSED] || flags[OWNED_NO_NA] < 0 || flags[OWNED_MAX_WIDTH] < 0 ||
        (!flags[OWNED_WIDTH_EXACT] && flags[OWNED_MAX_WIDTH] > limit)) owned_scan_strings(value);
    return Rf_ScalarLogical(flags[OWNED_NO_NA] && flags[OWNED_MAX_WIDTH] <= limit);
}

static SEXP C_dtatools_owned_string_width(SEXP value) {
    if (TYPEOF(value) != STRSXP || !owned_column(value) || !owned_supported(value)) return R_NilValue;
    int *flags = owned_flags(value);
    if (flags[OWNED_EXPOSED] || flags[OWNED_NO_NA] < 0 || !flags[OWNED_WIDTH_EXACT]) owned_scan_strings(value);
    return Rf_ScalarInteger(flags[OWNED_NO_NA] ? (flags[OWNED_MAX_WIDTH] > 1 ? flags[OWNED_MAX_WIDTH] : 1) : NA_INTEGER);
}

static SEXP C_dtatools_owned_scan_stats(SEXP reset) {
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 2));
    REAL(result)[0] = owned_string_scans;
    REAL(result)[1] = owned_string_scanned_values;
    if (Rf_asLogical(reset) == TRUE) owned_string_scans = owned_string_scanned_values = 0;
    UNPROTECT(1);
    return result;
}

static SEXP C_dtatools_is_owned_double(SEXP value) {
    return Rf_ScalarLogical(owned_real(value) && owned_real_supported(value));
}

static int owned_bare_real(SEXP value) {
    return owned_real(value) && !Rf_isObject(value) && !ANY_ATTRIB(value);
}

static SEXP C_dtatools_owned_bare(SEXP value) {
    return Rf_ScalarLogical(owned_bare_real(value));
}

/* R's range argument flattening repeatedly requests a writable pointer.
   Give that R call an independent ordinary snapshot, never the owned payload. */
static SEXP C_dtatools_owned_plain_snapshot(SEXP value) {
    if (!owned_real(value)) return R_NilValue;
    SEXP payload = PROTECT(owned_values(value));
    R_xlen_t length = XLENGTH(payload);
    SEXP result = PROTECT(Rf_allocVector(REALSXP, length));
    memcpy(REAL(result), DATAPTR_RO(payload), (size_t) length * sizeof(double));
    owned_capture_bytes += (double) length * sizeof(double);
    SHALLOW_DUPLICATE_ATTRIB(result, value);
    UNPROTECT(2);
    return result;
}

/* Public integer/logical exports discard attributes. Using an explicit seam
   keeps generic ALTREP coercion's attribute and warning order unchanged.
   R allocates a fresh ordinary result for these two target types. */
static SEXP C_dtatools_owned_coerce(SEXP value, SEXP logical) {
    if (!owned_real(value)) return R_NilValue;
    SEXPTYPE type = Rf_asLogical(logical) == TRUE ? LGLSXP : INTSXP;
    SEXP payload = PROTECT(owned_values(value));
    SEXP result = Rf_coerceVector(payload, type);
    UNPROTECT(1);
    return result;
}

/* Only bare handles qualify. Named, shaped and classed values keep base R's
   attribute and method dispatch behavior in the R fallback. */
static SEXP C_dtatools_owned_missing_mask(SEXP value) {
    if (!owned_bare_real(value)) return R_NilValue;
    SEXP payload = PROTECT(owned_values(value));
    R_xlen_t length = XLENGTH(payload);
    SEXP result = PROTECT(Rf_allocVector(LGLSXP, length));
    const double *values = (const double *) DATAPTR_RO(payload);
    int *out = LOGICAL(result);
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        out[i] = ISNAN(values[i]);
    }
    UNPROTECT(2);
    return result;
}


/* This is the only public writable backing preparation for owned columns. Public
   access and transaction access differ solely in their exposure policy. */
static void *owned_prepare(SEXP value, int exposed) {
    if (owned_flags(value)[OWNED_SHARED] || R_altrep_data2(value) == R_BaseEnv) {
        SEXP copy = PROTECT(owned_capture(value));
        R_set_altrep_data1(value, R_altrep_data1(copy));
        R_set_altrep_data2(value, R_NilValue);
        UNPROTECT(1);
    }
    owned_flags(value)[OWNED_NO_NA] = -1;
    owned_flags(value)[OWNED_MAX_WIDTH] = -1;
    owned_flags(value)[OWNED_WIDTH_EXACT] = 0;
    if (exposed) owned_flags(value)[OWNED_EXPOSED] = 1;
    return DATAPTR_RW(owned_values(value));
}

static R_xlen_t owned_real_length(SEXP value) { return XLENGTH(owned_values(value)); }
static double owned_real_elt(SEXP value, R_xlen_t i) { return REAL_ELT(owned_values(value), i); }
static R_xlen_t owned_real_region(SEXP value, R_xlen_t i, R_xlen_t n, double *out) {
    return REAL_GET_REGION(owned_values(value), i, n, out);
}
static void *owned_real_dataptr(SEXP value, Rboolean writable) {
    return writable ? owned_prepare(value, 1) : (void *) DATAPTR_RO(owned_values(value));
}
static const void *owned_real_dataptr_or_null(SEXP value) {
    return DATAPTR_OR_NULL(owned_values(value));
}
static SEXP owned_real_duplicate(SEXP value, Rboolean deep) {
    (void) deep;
    return owned_fork_real(value);
}

static int owned_real_no_na(SEXP value) {
    int *flags = owned_flags(value);
    if (!flags[OWNED_EXPOSED] && flags[OWNED_NO_NA] >= 0) return flags[OWNED_NO_NA];
    SEXP record = PROTECT(R_altrep_data1(value));
    SEXP payload = VECTOR_ELT(record, OWNED_VALUES);
    R_xlen_t length = XLENGTH(payload);
    const double *values = (const double *) DATAPTR_RO(payload);
    int no_na = 1;
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        if (ISNAN(values[i])) { no_na = 0; break; }
    }
    if (!flags[OWNED_EXPOSED]) flags[OWNED_NO_NA] = no_na;
    UNPROTECT(1);
    return no_na;
}

/* No Sum/Min/Max hooks: R's ordinary aggregate implementation uses the
   read-only Dataptr_or_null pointer through its region iterator. Passing the plain backing to
   an R call would let tracing or callbacks retain an untracked writable alias. */

static SEXP owned_real_subset(SEXP value, SEXP index, SEXP call) {
    (void) call;
    if (TYPEOF(index) != INTSXP && TYPEOF(index) != REALSXP) return NULL;
    /* Foreign index methods can detach value and collect its former backing.
       Retain the exact allocation whose pointer this read loop snapshots. */
    SEXP payload = PROTECT(owned_values(value));
    R_xlen_t length = XLENGTH(index), source_length = XLENGTH(payload);
    SEXP values = PROTECT(Rf_allocVector(REALSXP, length));
    const double *source = (const double *) DATAPTR_RO(payload);
    double *out = REAL(values);
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        double position = TYPEOF(index) == INTSXP ? INTEGER_ELT(index, i) : REAL_ELT(index, i);
        out[i] = R_FINITE(position) && position >= 1 && position <= (double) source_length
            ? source[(R_xlen_t) position - 1] : NA_REAL;
    }
    SEXP result = owned_adopt_real(values);
    UNPROTECT(2);
    return result;
}

static SEXP C_dtatools_owned_info(SEXP value) {
    if (!owned_column(value)) return R_NilValue;
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 5));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 5));
    const char *fields[] = {"backing", "shared", "exposed", "bytes", "depth"};
    for (int i = 0; i < 5; i++) SET_STRING_ELT(names, i, Rf_mkChar(fields[i]));
    char address[2 + sizeof(void *) * 2 + 1];
    snprintf(address, sizeof(address), "%p", (void *) owned_values(value));
    SET_VECTOR_ELT(result, 0, Rf_mkString(address));
    SET_VECTOR_ELT(result, 1, Rf_ScalarLogical(owned_flags(value)[OWNED_SHARED]));
    SET_VECTOR_ELT(result, 2, Rf_ScalarLogical(owned_flags(value)[OWNED_EXPOSED]));
    SET_VECTOR_ELT(result, 3, Rf_ScalarReal((double) XLENGTH(value) * owned_width(value)));
    SET_VECTOR_ELT(result, 4, Rf_ScalarInteger(1));
    Rf_setAttrib(result, R_NamesSymbol, names);
    UNPROTECT(2);
    return result;
}

static SEXP C_dtatools_native_copy_stats(SEXP reset) {
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 6));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 6));
    const char *fields[] = {"owned_capture", "compact_copy", "staged_new",
                            "old_journal", "native_scratch_allocated", "mutation_target_copy"};
    double values[] = {owned_capture_bytes, compact_copy_bytes, staged_new_bytes,
                       old_journal_bytes, native_scratch_allocated, mutation_target_copy_bytes};
    for (int i = 0; i < 6; i++) {
        SET_STRING_ELT(names, i, Rf_mkChar(fields[i]));
        REAL(result)[i] = values[i];
    }
    Rf_setAttrib(result, R_NamesSymbol, names);
    if (Rf_asLogical(reset) == TRUE) {
        owned_capture_bytes = compact_copy_bytes = staged_new_bytes = 0;
        old_journal_bytes = native_scratch_allocated = 0;
        mutation_target_copy_bytes = 0;
    }
    UNPROTECT(2);
    return result;
}

static SEXP C_dtatools_owned_pointer(SEXP value, SEXP writable) {
    if (!owned_column(value)) Rf_error("owned column required for pointer probe");
    int write = Rf_asLogical(writable);
    if (write == NA_LOGICAL) Rf_error("pointer access must be read-only or writable");
    void *pointer = write ? DATAPTR_RW(value) : (void *) DATAPTR_RO(value);
    return R_MakeExternalPtr(pointer, write ? R_BaseEnv : R_EmptyEnv, owned_values(value));
}

static SEXP C_dtatools_owned_pointer_write(SEXP pointer, SEXP index, SEXP replacement) {
    if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != R_BaseEnv ||
        R_ExternalPtrAddr(pointer) == NULL) Rf_error("writable pointer required");
    double position = Rf_asReal(index);
    if (!R_FINITE(position) || position < 1 || position != trunc(position) ||
        position > (double) XLENGTH(R_ExternalPtrProtected(pointer))) Rf_error("invalid pointer index");
    SEXP payload = R_ExternalPtrProtected(pointer);
    R_xlen_t i = (R_xlen_t) position - 1;
    switch (TYPEOF(payload)) {
    case REALSXP: ((double *) R_ExternalPtrAddr(pointer))[i] = Rf_asReal(replacement); break;
    case INTSXP: ((int *) R_ExternalPtrAddr(pointer))[i] = Rf_asInteger(replacement); break;
    case LGLSXP: ((int *) R_ExternalPtrAddr(pointer))[i] = Rf_asLogical(replacement); break;
    case STRSXP:
        if (TYPEOF(replacement) != STRSXP || XLENGTH(replacement) != 1) Rf_error("one string required");
        /* Use R's barrier on the exact rooted allocation behind the pointer. */
        SET_STRING_ELT(payload, i, STRING_ELT(replacement, 0)); break;
    default: Rf_error("invalid pointer storage");
    }
    return R_NilValue;
}

static int owned_integer_elt(SEXP value, R_xlen_t i) { return INTEGER_ELT(owned_values(value), i); }
static int owned_logical_elt(SEXP value, R_xlen_t i) { return LOGICAL_ELT(owned_values(value), i); }
static SEXP owned_string_elt(SEXP value, R_xlen_t i) { return STRING_ELT(owned_values(value), i); }
static R_xlen_t owned_integer_region(SEXP value, R_xlen_t i, R_xlen_t n, int *out) {
    return INTEGER_GET_REGION(owned_values(value), i, n, out);
}
static R_xlen_t owned_logical_region(SEXP value, R_xlen_t i, R_xlen_t n, int *out) {
    return LOGICAL_GET_REGION(owned_values(value), i, n, out);
}
static int owned_discrete_no_na(SEXP value) {
    int *flags = owned_flags(value);
    if (!flags[OWNED_EXPOSED] && flags[OWNED_NO_NA] >= 0) return flags[OWNED_NO_NA];
    int no_na = 1;
    SEXP payload = PROTECT(owned_values(value));
    const int *values = (const int *) DATAPTR_RO(payload);
    for (R_xlen_t i = 0; i < XLENGTH(payload); i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        if (values[i] == NA_INTEGER) { no_na = 0; break; }
    }
    if (!flags[OWNED_EXPOSED]) flags[OWNED_NO_NA] = no_na;
    UNPROTECT(1);
    return no_na;
}
static int owned_string_no_na(SEXP value) {
    int *flags = owned_flags(value);
    if (!flags[OWNED_EXPOSED] && flags[OWNED_NO_NA] >= 0) return flags[OWNED_NO_NA];
    SEXP payload = PROTECT(owned_values(value));
    int no_na = 1;
    owned_string_scans++;
    for (R_xlen_t i = 0; i < XLENGTH(payload); i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        owned_string_scanned_values++;
        if (STRING_ELT(payload, i) == NA_STRING) { no_na = 0; break; }
    }
    if (!flags[OWNED_EXPOSED]) flags[OWNED_NO_NA] = no_na;
    UNPROTECT(1);
    return no_na;
}
static SEXP C_dtatools_owned_no_na(SEXP value) {
    if (!owned_column(value)) Rf_error("owned column required for missingness probe");
    int result = TYPEOF(value) == STRSXP ? STRING_NO_NA(value) :
        TYPEOF(value) == REALSXP ? REAL_NO_NA(value) :
        TYPEOF(value) == INTSXP ? INTEGER_NO_NA(value) : LOGICAL_NO_NA(value);
    return Rf_ScalarLogical(result);
}
static void owned_string_set_elt(SEXP value, R_xlen_t i, SEXP replacement) {
    PROTECT(replacement);
    (void) owned_prepare(value, 0);
    SET_STRING_ELT(owned_values(value), i, replacement);
    UNPROTECT(1);
}
static SEXP C_dtatools_owned_set_string(SEXP value, SEXP index, SEXP replacement) {
    if (TYPEOF(value) != STRSXP || !owned_column(value) || TYPEOF(replacement) != STRSXP ||
        XLENGTH(replacement) != 1) Rf_error("owned string and one replacement required");
    double position = Rf_asReal(index);
    if (!R_FINITE(position) || position < 1 || position != trunc(position) || position > XLENGTH(value))
        Rf_error("invalid string index");
    SET_STRING_ELT(value, (R_xlen_t) position - 1, STRING_ELT(replacement, 0));
    return R_NilValue;
}
static SEXP owned_atomic_subset(SEXP value, SEXP index, SEXP call) {
    (void) call;
    if (TYPEOF(index) != INTSXP && TYPEOF(index) != REALSXP) return NULL;
    SEXP record = PROTECT(R_altrep_data1(value));
    SEXP payload = VECTOR_ELT(record, OWNED_VALUES);
    R_xlen_t length = XLENGTH(index), source_length = XLENGTH(payload);
    int type = TYPEOF(value), padded = 0;
    SEXP values = PROTECT(Rf_allocVector(type, length));
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        double position = TYPEOF(index) == INTSXP ? INTEGER_ELT(index, i) : REAL_ELT(index, i);
        int valid = R_FINITE(position) && position >= 1 && position <= (double) source_length;
        if (!valid) padded = 1;
        R_xlen_t from = valid ? (R_xlen_t) position - 1 : 0;
        switch (type) {
        case INTSXP: INTEGER(values)[i] = valid ? INTEGER_ELT(payload, from) : NA_INTEGER; break;
        case LGLSXP: LOGICAL(values)[i] = valid ? LOGICAL_ELT(payload, from) : NA_LOGICAL; break;
        case STRSXP: SET_STRING_ELT(values, i, valid ? STRING_ELT(payload, from) : NA_STRING); break;
        }
    }
    SEXP result = PROTECT(owned_adopt(values));
    int *prior = INTEGER(VECTOR_ELT(record, OWNED_FLAGS));
    /* Foreign index methods can mutate earlier source values and recompute
       facts while this loop is gathering. Their output must be rescanned. */
    if (!prior[OWNED_EXPOSED] && (!ALTREP(index) || owned_column(index))) {
        owned_flags(result)[OWNED_NO_NA] = padded ? 0 : prior[OWNED_NO_NA] == 1 ? 1 : -1;
        owned_flags(result)[OWNED_MAX_WIDTH] = prior[OWNED_MAX_WIDTH];
        owned_flags(result)[OWNED_WIDTH_EXACT] = 0;
    }
    UNPROTECT(3);
    return result;
}

static SEXP C_dtatools_owned_subset(SEXP value, SEXP index) {
    if (!owned_column(value)) Rf_error("owned column required");
    SEXP result = owned_real(value) ? owned_real_subset(value, index, R_NilValue) :
        owned_atomic_subset(value, index, R_NilValue);
    return result == NULL ? R_NilValue : result;
}

typedef struct { SEXP values; SEXP result; } owned_adopt_context;
static void owned_adopt_call(void *data) {
    owned_adopt_context *context = (owned_adopt_context *) data;
    SEXP result = PROTECT(owned_adopt_real(context->values));
    R_PreserveObject(result);
    context->result = result;
    UNPROTECT(1);
}
int dtatools_adopt_real(SEXP values, SEXP *result) {
    owned_adopt_context context = {values, NULL};
    int ok = R_ToplevelExec(owned_adopt_call, &context);
    if (ok) *result = context.result;
    return ok;
}

/* A foreign-style ALTREP probe exercises real native callback boundaries. Its
   one-shot callback is deliberately unrelated to owned backing qualification. */
static R_altrep_class_t dtatools_callback_real_class;
static R_altrep_class_t dtatools_callback_integer_class;
static R_altrep_class_t dtatools_callback_character_class;
static SEXP callback_values(SEXP value) { return VECTOR_ELT(R_altrep_data1(value), 0); }
static void callback_real_read(SEXP value, int element) {
    SEXP state = R_altrep_data1(value);
    if (INTEGER(VECTOR_ELT(state, 2))[0] != element || VECTOR_ELT(state, 1) == R_NilValue) return;
    if (XLENGTH(state) == 4 && INTEGER(VECTOR_ELT(state, 3))[0] > 0) {
        INTEGER(VECTOR_ELT(state, 3))[0]--;
        return;
    }
    SEXP callback = PROTECT(VECTOR_ELT(state, 1));
    SET_VECTOR_ELT(state, 1, R_NilValue);
    SEXP call = PROTECT(Rf_lang1(callback));
    Rf_eval(call, R_GlobalEnv);
    UNPROTECT(2);
}
static R_xlen_t callback_real_length(SEXP value) {
    callback_real_read(value, 2);
    return XLENGTH(callback_values(value));
}
static double callback_real_elt(SEXP value, R_xlen_t i) {
    callback_real_read(value, 1);
    return REAL_ELT(callback_values(value), i);
}
static int callback_integer_elt(SEXP value, R_xlen_t i) {
    callback_real_read(value, 1);
    return INTEGER_ELT(callback_values(value), i);
}
static SEXP callback_character_elt(SEXP value, R_xlen_t i) {
    callback_real_read(value, 1);
    return STRING_ELT(callback_values(value), i);
}
static void *callback_real_dataptr(SEXP value, Rboolean writable) {
    callback_real_read(value, 0);
    return writable ? DATAPTR_RW(callback_values(value)) : (void *) DATAPTR_RO(callback_values(value));
}
static const void *callback_real_dataptr_or_null(SEXP value) { (void) value; return NULL; }
static SEXP C_dtatools_callback_double(SEXP values, SEXP callback, SEXP element) {
    if (TYPEOF(values) != REALSXP || ALTREP(values) || !Rf_isFunction(callback) ||
        Rf_asLogical(element) == NA_LOGICAL) Rf_error("invalid callback-double probe");
    SEXP payload = PROTECT(Rf_duplicate(values));
    SEXP state = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(state, 0, payload);
    SET_VECTOR_ELT(state, 1, callback);
    SET_VECTOR_ELT(state, 2, Rf_ScalarInteger(Rf_asLogical(element)));
    SEXP result = R_new_altrep(dtatools_callback_real_class, state, R_NilValue);
    UNPROTECT(2);
    return result;
}

static SEXP C_dtatools_callback_integer(SEXP values, SEXP callback) {
    if (TYPEOF(values) != INTSXP || ALTREP(values) || !Rf_isFunction(callback)) {
        Rf_error("invalid callback-integer probe");
    }
    SEXP payload = PROTECT(Rf_duplicate(values));
    SEXP state = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(state, 0, payload);
    SET_VECTOR_ELT(state, 1, callback);
    SET_VECTOR_ELT(state, 2, Rf_ScalarInteger(1));
    SEXP result = R_new_altrep(dtatools_callback_integer_class, state, R_NilValue);
    UNPROTECT(2);
    return result;
}

static SEXP C_dtatools_callback_character(SEXP values, SEXP callback) {
    if (TYPEOF(values) != STRSXP || ALTREP(values) || !Rf_isFunction(callback)) {
        Rf_error("invalid callback-character probe");
    }
    SEXP payload = PROTECT(Rf_duplicate(values));
    SEXP state = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(state, 0, payload);
    SET_VECTOR_ELT(state, 1, callback);
    SET_VECTOR_ELT(state, 2, Rf_ScalarInteger(1));
    SEXP result = R_new_altrep(dtatools_callback_character_class, state, R_NilValue);
    UNPROTECT(2);
    return result;
}

static SEXP C_dtatools_callback_integer_after(SEXP values, SEXP callback, SEXP after) {
    if (TYPEOF(values) != INTSXP || ALTREP(values) || !Rf_isFunction(callback) ||
        TYPEOF(after) != INTSXP || XLENGTH(after) != 1 || INTEGER_ELT(after, 0) < 0) {
        Rf_error("invalid delayed callback-integer probe");
    }
    SEXP payload = PROTECT(Rf_duplicate(values));
    SEXP state = PROTECT(Rf_allocVector(VECSXP, 4));
    SET_VECTOR_ELT(state, 0, payload);
    SET_VECTOR_ELT(state, 1, callback);
    SET_VECTOR_ELT(state, 2, Rf_ScalarInteger(1));
    SET_VECTOR_ELT(state, 3, Rf_ScalarInteger(INTEGER_ELT(after, 0)));
    SEXP result = R_new_altrep(dtatools_callback_integer_class, state, R_NilValue);
    UNPROTECT(2);
    return result;
}

static SEXP C_dtatools_callback_length(SEXP values, SEXP callback) {
    SEXP element = PROTECT(Rf_ScalarLogical(0));
    SEXP result = PROTECT(TYPEOF(values) == REALSXP ? C_dtatools_callback_double(values, callback, element) :
        TYPEOF(values) == INTSXP ? C_dtatools_callback_integer(values, callback) :
        TYPEOF(values) == STRSXP ? C_dtatools_callback_character(values, callback) : R_NilValue);
    if (result == R_NilValue) Rf_error("unsupported callback-length type");
    INTEGER(VECTOR_ELT(R_altrep_data1(result), 2))[0] = 2;
    UNPROTECT(2);
    return result;
}

static SEXP C_dtatools_arm_callback_character(SEXP value, SEXP callback) {
    if (!ALTREP(value) || !R_altrep_inherits(value, dtatools_callback_character_class) ||
        !Rf_isFunction(callback)) Rf_error("invalid callback-character probe arm");
    SET_VECTOR_ELT(R_altrep_data1(value), 1, callback);
    return R_NilValue;
}

static void initialize_owned_columns(DllInfo *dll) {
    dtatools_owned_real_class = R_make_altreal_class("dtatools_owned_real", "dtatools", dll);
    R_set_altrep_Length_method(dtatools_owned_real_class, owned_real_length);
    R_set_altrep_Duplicate_method(dtatools_owned_real_class, owned_real_duplicate);
    R_set_altvec_Dataptr_method(dtatools_owned_real_class, owned_real_dataptr);
    R_set_altvec_Dataptr_or_null_method(dtatools_owned_real_class, owned_real_dataptr_or_null);
    R_set_altvec_Extract_subset_method(dtatools_owned_real_class, owned_real_subset);
    R_set_altreal_Elt_method(dtatools_owned_real_class, owned_real_elt);
    R_set_altreal_Get_region_method(dtatools_owned_real_class, owned_real_region);
    R_set_altreal_No_NA_method(dtatools_owned_real_class, owned_real_no_na);
    dtatools_owned_integer_class = R_make_altinteger_class("dtatools_owned_integer", "dtatools", dll);
    dtatools_owned_logical_class = R_make_altlogical_class("dtatools_owned_logical", "dtatools", dll);
    dtatools_owned_string_class = R_make_altstring_class("dtatools_owned_string", "dtatools", dll);
    R_altrep_class_t classes[] = {dtatools_owned_integer_class, dtatools_owned_logical_class, dtatools_owned_string_class};
    for (size_t i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
        R_set_altrep_Length_method(classes[i], owned_real_length);
        R_set_altrep_Duplicate_method(classes[i], owned_real_duplicate);
        R_set_altvec_Dataptr_method(classes[i], owned_real_dataptr);
        R_set_altvec_Dataptr_or_null_method(classes[i], owned_real_dataptr_or_null);
        R_set_altvec_Extract_subset_method(classes[i], owned_atomic_subset);
    }
    R_set_altinteger_Elt_method(dtatools_owned_integer_class, owned_integer_elt);
    R_set_altinteger_Get_region_method(dtatools_owned_integer_class, owned_integer_region);
    R_set_altinteger_No_NA_method(dtatools_owned_integer_class, owned_discrete_no_na);
    R_set_altlogical_Elt_method(dtatools_owned_logical_class, owned_logical_elt);
    R_set_altlogical_Get_region_method(dtatools_owned_logical_class, owned_logical_region);
    R_set_altlogical_No_NA_method(dtatools_owned_logical_class, owned_discrete_no_na);
    R_set_altstring_Elt_method(dtatools_owned_string_class, owned_string_elt);
    R_set_altstring_Set_elt_method(dtatools_owned_string_class, owned_string_set_elt);
    R_set_altstring_No_NA_method(dtatools_owned_string_class, owned_string_no_na);
    dtatools_callback_real_class = R_make_altreal_class("dtatools_callback_real", "dtatools", dll);
    R_set_altrep_Length_method(dtatools_callback_real_class, callback_real_length);
    R_set_altreal_Elt_method(dtatools_callback_real_class, callback_real_elt);
    R_set_altvec_Dataptr_method(dtatools_callback_real_class, callback_real_dataptr);
    R_set_altvec_Dataptr_or_null_method(dtatools_callback_real_class, callback_real_dataptr_or_null);
    dtatools_callback_character_class = R_make_altstring_class("dtatools_callback_character", "dtatools", dll);
    R_set_altrep_Length_method(dtatools_callback_character_class, callback_real_length);
    R_set_altstring_Elt_method(dtatools_callback_character_class, callback_character_elt);
    dtatools_callback_integer_class = R_make_altinteger_class("dtatools_callback_integer", "dtatools", dll);
    R_set_altrep_Length_method(dtatools_callback_integer_class, callback_real_length);
    R_set_altinteger_Elt_method(dtatools_callback_integer_class, callback_integer_elt);
    R_set_altvec_Dataptr_method(dtatools_callback_integer_class, callback_real_dataptr);
    R_set_altvec_Dataptr_or_null_method(dtatools_callback_integer_class, callback_real_dataptr_or_null);
}
