/* Promotion fit checks read selected values directly. R's general fallback
   remains responsible for unsupported classes and their vctrs methods. */
static SEXP C_dtatools_replacement_fits(SEXP values, SEXP rows, SEXP row_mode, SEXP kind_value) {
    int type = TYPEOF(values);
    if ((type != REALSXP && type != INTSXP && type != LGLSXP) ||
        Rf_getAttrib(values, R_DimSymbol) != R_NilValue ||
        (type == REALSXP ? !known_numeric_classes(values, 1) : Rf_isObject(values))) return R_NilValue;
    int kind = Rf_asInteger(kind_value);
    if (kind < NUMERIC_BYTE || kind > NUMERIC_DOUBLE) return R_NilValue;
    R_xlen_t length = XLENGTH(values);
    int by_row = Rf_asLogical(row_mode) == TRUE && rows != R_NilValue;
    R_xlen_t count = by_row ? XLENGTH(rows) : length;
    numeric_reader reader = numeric_reader_create(values, length);
    numeric_data encoding;
    if (reader.storage != NULL) { encoding = *reader.storage; reader.storage = &encoding; }
    PROTECT(numeric_payload_root(values));
    reference_rows indices;
    memset(&indices, 0, sizeof(indices));
    numeric_data row_encoding;
    if (by_row) {
        indices = reference_rows_create(rows, length);
        if (indices.real_reader.storage != NULL) {
            row_encoding = *indices.real_reader.storage;
            indices.real_reader.storage = &row_encoding;
        }
    }
    PROTECT(by_row ? numeric_payload_root(rows) : R_NilValue);
    uint32_t float_maximum_bits = UINT32_C(0x7effffff);
    float float_maximum;
    memcpy(&float_maximum, &float_maximum_bits, sizeof(float_maximum));
    int fits = 1;
    for (R_xlen_t i = 0; i < count; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t from = by_row ? reference_patch_row(&indices, i) : i;
        /* A foreign value reader may change a later live row after initial
           validation. Recheck each consumed offset before reading values. */
        if (from >= length) Rf_error("invalid reference mutation row");
        int missing;
        double value = numeric_reader_at(&reader, from, &missing);
        if (missing >= 0) {
            if (missing != 0 && (missing < 'a' || missing > 'z')) fits = 0;
            continue;
        }
        int finite = R_FINITE(value);
        int integral = finite && value == trunc(value);
        switch (kind) {
        case NUMERIC_BYTE: fits = fits && integral && value >= -127 && value <= 100; break;
        case NUMERIC_INT: fits = fits && integral && value >= -32767 && value <= 32740; break;
        case NUMERIC_LONG: fits = fits && integral && value >= -2147483647.0 && value <= 2147483620.0; break;
        case NUMERIC_FLOAT: fits = fits && finite && fabs(value) <= (double) float_maximum && (double) ((float) value) == value; break;
        case NUMERIC_DOUBLE: fits = fits && finite && fabs(value) <= DBL_MAX / 2.0; break;
        }
    }
    UNPROTECT(2);
    return Rf_ScalarLogical(fits);
}

/* Numeric table transactions. No source bytes or ownership claims change
   during staging. The final boundary runs after all potentially dispatching
   readers and allocations; its commit only writes validated bytes and slots. */
typedef struct {
    SEXP data;
    SEXP result;
    SEXP target;
    SEXP rows;
    SEXP replacement;
    SEXP saved_data1;
    SEXP saved_data2;
    SEXP saved_payload;
    R_xlen_t slot;
    R_xlen_t length;
    R_xlen_t count;
    R_xlen_t *positions;
    unsigned char *staged;
    size_t staged_size;
    size_t width;
    int entry_shared;
    int direct;
    int is_compact;
    int is_materialized;
    int stata_double;
    int scalar;
    numeric_data encoding;
    size_t new_missing;
} numeric_slot_transaction;

static int compact_private_handle(SEXP value) {
    if (!ALTREP(value) || R_altrep_data2(value) != R_NilValue) return 0;
    if (R_altrep_inherits(value, dtatools_numeric_class)) {
        return !compact_payload_is_shared(R_altrep_data1(value));
    }
    if (R_altrep_inherits(value, dtatools_metadata_real_class)) {
        SEXP state = metadata_proxy_state(value);
        if (state == R_NilValue || XLENGTH(state) != 2) return 0;
        SEXP source = metadata_proxy_source(value);
        return ALTREP(source) && R_altrep_inherits(source, dtatools_numeric_class) &&
            R_altrep_data2(source) == R_NilValue &&
            compact_payload_is_owned_by(R_altrep_data1(source), metadata_proxy_owner(value));
    }
    return 0;
}

static int numeric_private_handle(const numeric_slot_transaction *transaction) {
    SEXP target = transaction->target;
    /* The registered vector seam explicitly mutates its supplied handle.
       Table writes must also isolate other R bindings to that same handle. */
    if (!transaction->direct && (transaction->entry_shared || MAYBE_SHARED(target))) return 0;
    if (transaction->is_materialized) return 0;
    if (transaction->is_compact) return compact_private_handle(target);
    return owned_real(target) && R_altrep_data2(target) == R_NilValue &&
        !owned_flags(target)[OWNED_SHARED] && !owned_flags(target)[OWNED_EXPOSED];
}

static void stage_numeric_slot(numeric_slot_transaction *transaction) {
    reference_rows rows = reference_rows_create(transaction->rows, transaction->length);
    reference_value_plan values = reference_value_plan_create(
        transaction->replacement, &rows, transaction->count, transaction->length,
        transaction->is_compact || transaction->is_materialized || transaction->stata_double,
        "invalid reference replacement plan");
    transaction->scalar = values.mode == REFERENCE_VALUES_SCALAR;
    if (!transaction->is_compact && !transaction->is_materialized && !transaction->stata_double &&
        TYPEOF(transaction->replacement) != REALSXP) {
        Rf_error("replacement storage does not match its target");
    }
    if (transaction->rows != R_NilValue && transaction->count > 0) {
        if ((size_t) transaction->count > SIZE_MAX / sizeof(R_xlen_t)) {
            Rf_error("reference mutation row plan is too large");
        }
        size_t bytes = (size_t) transaction->count * sizeof(R_xlen_t);
        transaction->positions = (R_xlen_t *) malloc(bytes);
        if (transaction->positions == NULL) Rf_error("could not stage reference mutation rows");
        native_scratch_allocated += (double) bytes;
        for (R_xlen_t i = 0; i < transaction->count; i++) {
            if ((i & 16383) == 0) R_CheckUserInterrupt();
            transaction->positions[i] = reference_patch_row(&rows, i);
        }
    }
    R_xlen_t staged_count = transaction->scalar ? 1 : transaction->count;
    if ((size_t) staged_count > SIZE_MAX / transaction->width) {
        Rf_error("reference replacement plan is too large");
    }
    transaction->staged_size = (size_t) staged_count * transaction->width;
    transaction->staged = (unsigned char *) malloc(
        transaction->staged_size == 0 ? 1 : transaction->staged_size);
    if (transaction->staged == NULL) Rf_error("could not stage reference replacement values");
    native_scratch_allocated += (double) transaction->staged_size;
    numeric_reader reader;
    memset(&reader, 0, sizeof(reader));
    if (transaction->is_compact || transaction->is_materialized || transaction->stata_double) {
        reader = numeric_reader_create(transaction->replacement, values.value_count);
    }
    if (transaction->is_materialized) {
        validate_materialized_numeric_replacement(&transaction->encoding, &reader, &rows, values);
    }
    int invalid_missing = 0, invalid_range = 0;
    for (R_xlen_t i = 0; i < staged_count; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t row = transaction->positions == NULL || transaction->scalar
            ? i : transaction->positions[i];
        R_xlen_t from = reference_value_index(&values, i, row);
        if (transaction->is_compact) {
            int missing;
            double value = numeric_reader_at(&reader, from, &missing);
            validate_compact_patch_value(&transaction->encoding, value, missing);
            unsigned char encoded[4];
            encode_compact_patch_value(&transaction->encoding, value, missing, encoded);
            memcpy(transaction->staged + (size_t) i * transaction->width,
                   encoded, transaction->width);
            if (missing >= 0) transaction->new_missing++;
        } else {
            double value;
            if (transaction->is_materialized) {
                int missing;
                value = numeric_reader_at(&reader, from, &missing);
                value = materialized_numeric_patch_value(&transaction->encoding, value, missing);
            } else if (transaction->stata_double) {
                int missing;
                value = numeric_reader_at(&reader, from, &missing);
                if (missing >= 0) {
                    if (missing == 0) value = NA_REAL;
                    else if (missing >= 'a' && missing <= 'z') {
                        value = numeric_missing_value(missing - 'a' + 1);
                    } else invalid_missing = 1;
                } else if (!R_FINITE(value)) invalid_missing = 1;
                else {
                    double encoded = compact_patch_encoded_value(value, transaction->encoding.temporal);
                    if (!R_FINITE(encoded) || fabs(encoded) > DBL_MAX / 2.0) invalid_range = 1;
                }
            } else value = REAL_ELT(transaction->replacement, from);
            memcpy(transaction->staged + (size_t) i * sizeof(double), &value, sizeof(double));
            if (ISNAN(value)) transaction->new_missing++;
        }
    }
    if (invalid_missing) Rf_error("`values` cannot contain `NaN` or infinities; use `NA_real_` for Stata system missing");
    if (invalid_range) Rf_error("No Stata numeric storage can represent `x`");
    staged_new_bytes += (double) transaction->staged_size;
    if (transaction->scalar && transaction->new_missing) transaction->new_missing = transaction->count;
}

/* These routines receive only plain backing and staged C buffers. There are
   no allocations, callbacks, validation errors or interrupt checks after the
   first write. Partial-write rollback remains exercised by the separate
   dictionary, materialized and fused transaction paths. */
static void commit_numeric_bytes(numeric_slot_transaction *transaction, SEXP column) {
    numeric_data *compact = transaction->is_compact ? unmaterialized_numeric_storage(column) : NULL;
    unsigned char *output = transaction->is_compact
        ? (unsigned char *) compact->values : (unsigned char *) REAL(
            transaction->is_materialized ? R_altrep_data2(column) : owned_values(column));
    if (transaction->rows == R_NilValue) {
        if (transaction->scalar && transaction->count > 0) {
            memcpy(output, transaction->staged, transaction->width);
            size_t total = (size_t) transaction->count * transaction->width;
            for (size_t filled = transaction->width; filled < total;) {
                size_t copied = filled <= total - filled ? filled : total - filled;
                memcpy(output + filled, output, copied);
                filled += copied;
            }
        } else if (transaction->staged_size > 0) {
            memcpy(output, transaction->staged, transaction->staged_size);
        }
        if (compact != NULL) compact->missing_count = transaction->new_missing;
    } else {
        numeric_data staged_encoding = transaction->encoding;
        staged_encoding.values = transaction->staged;
        for (R_xlen_t i = 0; i < transaction->count; i++) {
            size_t row = (size_t) transaction->positions[i];
            size_t from = transaction->scalar ? 0 : (size_t) i;
            if (compact != NULL) {
                int before = numeric_value_is_missing_at(compact, row);
                int after = numeric_value_is_missing_at(&staged_encoding, from);
                if (before && !after) compact->missing_count--;
                if (!before && after) compact->missing_count++;
            }
            memcpy(output + row * transaction->width,
                   transaction->staged + from * transaction->width, transaction->width);
        }
    }
    if (!transaction->is_compact && !transaction->is_materialized) {
        owned_flags(column)[OWNED_NO_NA] = transaction->rows == R_NilValue
            ? transaction->new_missing == 0 : -1;
    }
}

static void validate_numeric_slot_target(const numeric_slot_transaction *transaction);

static SEXP new_numeric_destination(numeric_slot_transaction *transaction) {
    SEXP result;
    if (transaction->is_compact) {
        numeric_data encoding = transaction->encoding;
        if (transaction->rows != R_NilValue) {
            size_t bytes = (size_t) transaction->length * transaction->width;
            SEXP backing = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) bytes));
            validate_numeric_slot_target(transaction);
            memcpy(RAW(backing), RAW(transaction->saved_payload), bytes);
            compact_copy_bytes += (double) bytes;
            mutation_target_copy_bytes += (double) bytes;
            size_t missing = unmaterialized_numeric_storage(transaction->target)->missing_count;
            result = PROTECT(numeric_from_backing(backing, transaction->length,
                encoding.kind, encoding.temporal, encoding.format_version, missing));
            UNPROTECT(2);
            PROTECT(result);
        } else {
            SEXP backing = PROTECT(Rf_allocVector(RAWSXP,
                (R_xlen_t) ((size_t) transaction->length * transaction->width)));
            result = PROTECT(numeric_from_backing(backing, transaction->length,
                encoding.kind, encoding.temporal, encoding.format_version, 0));
            UNPROTECT(2);
            PROTECT(result);
        }
    } else if (transaction->is_materialized) {
        SEXP values = PROTECT(Rf_allocVector(REALSXP, transaction->length));
        SEXP external = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
        result = PROTECT(R_new_altrep(dtatools_numeric_class, external, values));
        UNPROTECT(3);
        PROTECT(result);
    } else if (transaction->rows != R_NilValue) {
        result = PROTECT(owned_capture_real(transaction->target));
        mutation_target_copy_bytes += (double) transaction->length * sizeof(double);
    } else {
        SEXP values = PROTECT(Rf_allocVector(REALSXP, transaction->length));
        result = PROTECT(owned_adopt_real(values));
        UNPROTECT(2);
        PROTECT(result);
    }
    SHALLOW_DUPLICATE_ATTRIB(result, transaction->target);
    UNPROTECT(1);
    return result;
}

static void validate_numeric_slot_target(const numeric_slot_transaction *transaction) {
    if ((!transaction->direct &&
         (transaction->slot >= XLENGTH(transaction->data) ||
          VECTOR_ELT(transaction->data, transaction->slot) != transaction->target)) ||
        XLENGTH(transaction->target) != transaction->length ||
        (ALTREP(transaction->target) &&
         (R_altrep_data1(transaction->target) != transaction->saved_data1 ||
          R_altrep_data2(transaction->target) != transaction->saved_data2))) {
        Rf_error("reference mutation target changed while preparing replacement");
    }
    if (transaction->is_compact && unmaterialized_numeric_storage(transaction->target) == NULL) {
        Rf_error("reference mutation storage changed while preparing replacement");
    }
}

static SEXP apply_numeric_slot(void *data) {
    numeric_slot_transaction *transaction = (numeric_slot_transaction *) data;
    stage_numeric_slot(transaction);
    if (transaction->count == 0) return transaction->result;
    /* Unlike journaled paths, interruption here is before any private bytes
       change. Keep their after-write injection and rollback tests intact. */
    maybe_inject_reference_write_interrupt();
    R_CheckUserInterrupt();
    validate_numeric_slot_target(transaction);
    int private = numeric_private_handle(transaction);
    SEXP column = PROTECT(private ? transaction->target : new_numeric_destination(transaction));
    validate_numeric_slot_target(transaction);
    commit_numeric_bytes(transaction, column);
    if (!private) {
        if (transaction->direct) {
            R_set_altrep_data1(transaction->target, R_altrep_data1(column));
            R_set_altrep_data2(transaction->target, R_NilValue);
        } else commit_identical_slots(transaction->data, transaction->target, column);
    }
    UNPROTECT(1);
    return transaction->result;
}

static void cleanup_numeric_slot(void *data, Rboolean jump) {
    (void) jump;
    numeric_slot_transaction *transaction = (numeric_slot_transaction *) data;
    free(transaction->positions);
    free(transaction->staged);
    transaction->positions = NULL;
    transaction->staged = NULL;
}

static SEXP patch_numeric_target(SEXP data, R_xlen_t slot, SEXP target, SEXP rows,
                                 SEXP replacement, int entry_shared, int direct) {
    PROTECT(target);
    numeric_data *compact = unmaterialized_numeric_storage(target);
    numeric_data materialized;
    int is_materialized = rows == R_NilValue && materialized_numeric_storage(target, &materialized);
    if (compact == NULL && !is_materialized && !owned_real_supported(target) &&
        !(direct && owned_real(target))) {
        UNPROTECT(1);
        return R_NilValue;
    }
    if (rows != R_NilValue && TYPEOF(rows) != INTSXP && TYPEOF(rows) != REALSXP) {
        Rf_error("invalid reference replacement plan");
    }
    numeric_slot_transaction transaction;
    memset(&transaction, 0, sizeof(transaction));
    transaction.data = data;
    transaction.result = PROTECT(direct ? Rf_ScalarLogical(0) : data);
    transaction.direct = direct;
    transaction.target = target;
    transaction.rows = rows;
    transaction.replacement = replacement;
    transaction.saved_data1 = PROTECT(ALTREP(target) ? R_altrep_data1(target) : R_NilValue);
    transaction.saved_data2 = PROTECT(ALTREP(target) ? R_altrep_data2(target) : R_NilValue);
    SEXP source = target;
    if (compact != NULL) {
        while (R_altrep_inherits(source, dtatools_metadata_real_class)) source = metadata_proxy_source(source);
    }
    transaction.saved_payload = PROTECT(compact != NULL
        ? R_ExternalPtrProtected(R_altrep_data1(source)) : R_NilValue);
    transaction.slot = slot;
    transaction.length = XLENGTH(target);
    transaction.count = rows == R_NilValue ? transaction.length : XLENGTH(rows);
    transaction.entry_shared = entry_shared;
    transaction.is_compact = compact != NULL;
    transaction.is_materialized = is_materialized;
    transaction.stata_double = !direct && owned_real(target) && owned_real_supported(target) &&
        (Rf_inherits(target, "dta_numeric") || Rf_inherits(target, "dta_temporal"));
    transaction.width = compact != NULL ? numeric_kind_width(compact->kind) : sizeof(double);
    if ((size_t) transaction.length > SIZE_MAX / transaction.width ||
        (size_t) transaction.length * transaction.width > (size_t) R_XLEN_T_MAX) {
        Rf_error("reference replacement plan is too large");
    }
    if (compact != NULL) transaction.encoding = *compact;
    else if (is_materialized) transaction.encoding = materialized;
    else if (transaction.stata_double) transaction.encoding.temporal =
        Rf_inherits(target, "dta_date") ? 1 : Rf_inherits(target, "dta_datetime") ? 2 : 0;
    SEXP continuation = PROTECT(R_MakeUnwindCont());
    SEXP result = R_UnwindProtect(apply_numeric_slot, &transaction,
        cleanup_numeric_slot, &transaction, continuation);
    UNPROTECT(6);
    return result;
}

static SEXP patch_numeric_slot(SEXP data, R_xlen_t slot, SEXP rows,
                               SEXP replacement, int entry_shared) {
    return patch_numeric_target(data, slot, VECTOR_ELT(data, slot), rows,
                                replacement, entry_shared, 0);
}

static SEXP patch_owned_vector(SEXP target, SEXP rows, SEXP replacement) {
    return patch_numeric_target(R_NilValue, 0, target, rows, replacement, 0, 1);
}

/* Plain atomic table targets use the same late-commit rule as owned numerics.
   This qualifies existing private string/integer writes without introducing
   shared string or integer backing. The legacy direct-vector seam keeps its
   journaled after-write interrupt and rollback behavior. */
static SEXP patch_plain_slot(SEXP data, R_xlen_t slot, SEXP rows,
                             SEXP replacement, int entry_shared) {
    SEXP target = VECTOR_ELT(data, slot);
    int type = TYPEOF(target);
    if (ALTREP(target) || (type != REALSXP && type != INTSXP &&
                          type != LGLSXP && type != STRSXP)) return R_NilValue;
    PROTECT(target);
    R_xlen_t length = XLENGTH(target);
    R_xlen_t count = rows == R_NilValue ? length : XLENGTH(rows);
    reference_rows row_plan = reference_rows_create(rows, length);
    reference_value_plan values = reference_value_plan_create(
        replacement, &row_plan, count, length,
        unmaterialized_dictstring_source(replacement) != R_NilValue,
        "invalid reference replacement plan");
    if (TYPEOF(replacement) != type) Rf_error("replacement storage does not match its target");
    SEXP positions = PROTECT(rows == R_NilValue ? R_NilValue : Rf_allocVector(REALSXP, count));
    for (R_xlen_t i = 0; rows != R_NilValue && i < count; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        REAL(positions)[i] = (double) reference_patch_row(&row_plan, i);
    }
    R_xlen_t staged_count = values.mode == REFERENCE_VALUES_SCALAR ? 1 : count;
    SEXP staged = PROTECT(Rf_allocVector(type, staged_count));
    SEXP cache = PROTECT(type == STRSXP
        ? reference_string_reader_private_cache(replacement, staged_count) : R_NilValue);
    reference_string_reader strings = reference_string_reader_create(replacement, cache);
    SEXP empty = PROTECT(type == STRSXP ? Rf_mkChar("") : R_NilValue);
    int declared_width = type == STRSXP ? string_declared_width(
        Rf_getAttrib(target, Rf_install("stata.string.storage")),
        "Replacement values do not fit their declared Stata string storage") : -1;
    for (R_xlen_t i = 0; i < staged_count; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t row = rows == R_NilValue || values.mode == REFERENCE_VALUES_SCALAR
            ? i : (R_xlen_t) REAL(positions)[i];
        R_xlen_t from = reference_value_index(&values, i, row);
        switch (type) {
        case REALSXP: REAL(staged)[i] = REAL_ELT(replacement, from); break;
        case INTSXP: INTEGER(staged)[i] = INTEGER_ELT(replacement, from); break;
        case LGLSXP: LOGICAL(staged)[i] = LOGICAL_ELT(replacement, from); break;
        case STRSXP: {
            SEXP value = reference_string_reader_at(&strings, from);
            SET_STRING_ELT(staged, i, value == NA_STRING ? empty : value);
            validate_reference_replacement_string(STRING_ELT(staged, i), declared_width);
            break;
        }
        }
    }
    size_t width = type == REALSXP ? sizeof(double) : type == STRSXP ? sizeof(SEXP) : sizeof(int);
    staged_new_bytes += (double) staged_count * width;
    if (count == 0) { UNPROTECT(5); return data; }
    maybe_inject_reference_write_interrupt();
    R_CheckUserInterrupt();
    if (slot >= XLENGTH(data) || VECTOR_ELT(data, slot) != target || XLENGTH(target) != length) {
        Rf_error("reference mutation target changed while preparing replacement");
    }
    int detach = entry_shared || MAYBE_SHARED(target);
    int complete_staged = rows == R_NilValue && values.mode != REFERENCE_VALUES_SCALAR;
    SEXP column = PROTECT(detach ? (complete_staged ? staged : Rf_allocVector(type, length)) : target);
    if (detach) {
        SHALLOW_DUPLICATE_ATTRIB(column, target);
        if (slot >= XLENGTH(data) || VECTOR_ELT(data, slot) != target || XLENGTH(target) != length) {
            Rf_error("reference mutation target changed while preparing replacement");
        }
        if (rows != R_NilValue) {
            if (type == STRSXP) {
                for (R_xlen_t i = 0; i < length; i++) SET_STRING_ELT(column, i, STRING_ELT(target, i));
            } else if (type == REALSXP) memcpy(REAL(column), REAL(target), (size_t) length * width);
            else if (type == INTSXP) memcpy(INTEGER(column), INTEGER(target), (size_t) length * width);
            else memcpy(LOGICAL(column), LOGICAL(target), (size_t) length * width);
            mutation_target_copy_bytes += (double) length * width;
        }
    }
    /* No allocating or dispatching operation occurs after this point. */
    for (R_xlen_t i = 0; column != staged && i < count; i++) {
        R_xlen_t row = rows == R_NilValue ? i : (R_xlen_t) REAL(positions)[i];
        R_xlen_t from = values.mode == REFERENCE_VALUES_SCALAR ? 0 : i;
        switch (type) {
        case REALSXP: REAL(column)[row] = REAL(staged)[from]; break;
        case INTSXP: INTEGER(column)[row] = INTEGER(staged)[from]; break;
        case LGLSXP: LOGICAL(column)[row] = LOGICAL(staged)[from]; break;
        case STRSXP: SET_STRING_ELT(column, row, STRING_ELT(staged, from)); break;
        }
    }
    if (detach) commit_identical_slots(data, target, column);
    UNPROTECT(6);
    return data;
}

/* Inspect through the table so qualification does not itself retain a column
   handle or request a writable pointer. This is an internal validation seam. */
static SEXP C_dtatools_mutation_info(SEXP data, SEXP location) {
    SEXP target = VECTOR_ELT(data, mutation_slot(data, location));
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 7));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 7));
    const char *fields[] = {"handle_shared", "backing_private", "exposed",
                            "backing", "handle", "depth", "bytes"};
    for (int i = 0; i < 7; i++) SET_STRING_ELT(names, i, Rf_mkChar(fields[i]));
    SET_VECTOR_ELT(result, 0, Rf_ScalarLogical(MAYBE_SHARED(target)));
    numeric_data *compact = unmaterialized_numeric_storage(target);
    int is_owned = owned_real(target);
    numeric_data materialized;
    int is_materialized = materialized_numeric_storage(target, &materialized);
    int private = compact != NULL ? compact_private_handle(target) :
        is_owned && !owned_flags(target)[OWNED_SHARED] &&
        !owned_flags(target)[OWNED_EXPOSED] && R_altrep_data2(target) == R_NilValue;
    SET_VECTOR_ELT(result, 1, Rf_ScalarLogical(private));
    SET_VECTOR_ELT(result, 2, Rf_ScalarLogical(is_owned && owned_flags(target)[OWNED_EXPOSED]));
    char address[2 + sizeof(void *) * 2 + 1];
    snprintf(address, sizeof(address), "%p", compact != NULL ? compact->values :
        is_owned ? (void *) owned_values(target) :
        is_materialized ? (void *) R_altrep_data2(target) : (void *) target);
    SET_VECTOR_ELT(result, 3, Rf_mkString(address));
    snprintf(address, sizeof(address), "%p", (void *) target);
    SET_VECTOR_ELT(result, 4, Rf_mkString(address));
    int depth = 0;
    SEXP source = target;
    while (ALTREP(source) && R_altrep_inherits(source, dtatools_metadata_real_class) &&
           R_altrep_data2(source) == R_NilValue) {
        depth++;
        source = metadata_proxy_source(source);
    }
    if (is_owned) depth++;
    SET_VECTOR_ELT(result, 5, Rf_ScalarInteger(depth));
    SET_VECTOR_ELT(result, 6, Rf_ScalarReal((double) XLENGTH(target) *
        (compact != NULL ? numeric_kind_width(compact->kind) :
         TYPEOF(target) == INTSXP || TYPEOF(target) == LGLSXP ? sizeof(int) :
         TYPEOF(target) == STRSXP ? sizeof(SEXP) : sizeof(double))));
    Rf_setAttrib(result, R_NamesSymbol, names);
    UNPROTECT(2);
    return result;
}
