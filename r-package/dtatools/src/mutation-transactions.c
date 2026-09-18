/* Reference mutation transactions: the row and value plans behind repl()
   and gen(), the compact, materialized and vector patch transactions that
   commit them, column append, generation, and the fused compare-and-patch
   fast path. mutation-write.h is included where the transaction types it
   writes through are complete. */
#include "dtatools-internal.h"

static int reference_mutable_altrep(SEXP value) {
    return ALTREP(value) &&
        (owned_column(value) || R_altrep_inherits(value, dtatools_numeric_class) ||
         R_altrep_inherits(value, dtatools_dictstring_class) ||
         R_altrep_inherits(value, dtatools_metadata_real_class) ||
         R_altrep_inherits(value, dtatools_metadata_string_class));
}

/* Only ordinary storage and our native ownership wrappers have callback-free
   element reads. S3 classes do not certify an unknown ALTREP implementation. */
static int reference_callback_free_operand(SEXP value) {
    return !ALTREP(value) || reference_mutable_altrep(value);
}

static SEXP plain_column(SEXP value, int copy_values) {
    int type = TYPEOF(value);
    if (type != REALSXP && type != INTSXP &&
        type != LGLSXP && type != STRSXP) {
        Rf_error("unsupported generic ALTREP replacement storage");
    }
    R_xlen_t length = XLENGTH(value);
    SEXP result = PROTECT(Rf_allocVector(type, length));
    if (copy_values) {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            switch (type) {
            case REALSXP:
                REAL(result)[index] = REAL_ELT(value, index);
                break;
            case INTSXP:
                INTEGER(result)[index] = INTEGER_ELT(value, index);
                break;
            case LGLSXP:
                LOGICAL(result)[index] = LOGICAL_ELT(value, index);
                break;
            case STRSXP:
                SET_STRING_ELT(result, index, STRING_ELT(value, index));
                break;
            }
        }
    }
    DUPLICATE_ATTRIB(result, value);
    UNPROTECT(1);
    return result;
}

static double compact_patch_encoded_value(double value, int temporal) {
    if (temporal == 1) return value + 3653.0;
    if (temporal == 2) {
        double source = (value + 315619200.0) * 1000.0;
        double rounded = round(source);
        double decoded = rounded / 1000.0 - 315619200.0;
        return R_FINITE(source) && decoded == value ? rounded : source;
    }
    return value;
}

static void validate_compact_patch_value(
    const numeric_data *target, double value, int missing_code
) {
    if (missing_code >= 0) {
        if (missing_code == 256 ||
            (missing_code != 0 &&
             (missing_code < 'a' || missing_code > 'z'))) {
            Rf_error(
                "replacement values cannot contain `NaN` or unsupported missing tags"
            );
        }
        if (target->format_version <= 111 && missing_code != 0) {
            Rf_error(
                "this legacy compact column cannot store extended missing values"
            );
        }
        return;
    }
    unsigned char encoded[4] = {0};
    write_numeric_observed(
        encoded, 0, target->kind,
        compact_patch_encoded_value(value, target->temporal)
    );
}

static void write_compact_patch_value(
    numeric_data *target, size_t row, double value, int missing_code
) {
    unsigned char *output = (unsigned char *) target->values;
    if (missing_code >= 0) {
        int offset = missing_code == 0 ? 0 : missing_code - 'a' + 1;
        if (target->format_version <= 111) {
            write_numeric_system_missing_raw(
                output, (R_xlen_t) row, target->kind,
                target->format_version
            );
        } else {
            write_numeric_missing(
                output, (R_xlen_t) row, target->kind, offset
            );
        }
        return;
    }
    write_numeric_observed(
        output, (R_xlen_t) row, target->kind,
        compact_patch_encoded_value(value, target->temporal)
    );
}

static void encode_compact_patch_value(
    const numeric_data *target, double value, int missing_code,
    unsigned char encoded[4]
) {
    numeric_data encoder = *target;
    encoder.values = encoded;
    encoder.length = 1;
    write_compact_patch_value(&encoder, 0, value, missing_code);
}

static void write_encoded_compact_patch_value(
    numeric_data *target, size_t row, const unsigned char encoded[4],
    size_t width
) {
    memcpy(
        (unsigned char *) target->values + row * width,
        encoded, width
    );
}

static void fill_encoded_compact_patch_value(
    numeric_data *target, const unsigned char encoded[4], size_t width
) {
    if (width == 1) {
        memset(target->values, encoded[0], target->length);
        return;
    }
    if (target->length == 0) return;
    /* Seed the first element, then double the filled prefix so the
       fill is memcpy-bound instead of one write per row. */
    write_encoded_compact_patch_value(target, 0, encoded, width);
    unsigned char *bytes = (unsigned char *) target->values;
    size_t total = target->length * width;
    size_t filled = width;
    while (filled < total) {
        size_t copy = filled <= total - filled ? filled : total - filled;
        memcpy(bytes + filled, bytes, copy);
        filled += copy;
    }
}

static numeric_data *detach_compact_patch_target(SEXP value) {
    if (ALTREP(value) &&
        R_altrep_inherits(value, dtatools_numeric_class) &&
        R_altrep_data2(value) == R_NilValue) {
        SEXP external = R_altrep_data1(value);
        numeric_data *source = numeric_storage(value);
        if (!compact_payload_is_shared(external)) return source;
        SEXP detached = PROTECT(numeric_compact_copy(source));
        R_set_altrep_data1(value, R_altrep_data1(detached));
        numeric_data *result = numeric_storage(value);
        UNPROTECT(1);
        return result;
    }
    if (!ALTREP(value) ||
        !R_altrep_inherits(value, dtatools_metadata_real_class) ||
        R_altrep_data2(value) != R_NilValue) {
        return NULL;
    }
    SEXP owned = metadata_proxy_source(value);
    SEXP owner = metadata_proxy_owner(value);
    if (ALTREP(owned) &&
        R_altrep_inherits(owned, dtatools_numeric_class) &&
        R_altrep_data2(owned) == R_NilValue &&
        compact_payload_is_owned_by(R_altrep_data1(owned), owner)) {
        return numeric_storage(owned);
    }
    numeric_data *source = unmaterialized_numeric_storage(value);
    if (source == NULL) return NULL;
    SEXP detached = PROTECT(numeric_compact_copy(source));
    SEXP token = PROTECT(R_MakeExternalPtr(
        NULL, R_NilValue, R_NilValue
    ));
    compact_payload_claim(R_altrep_data1(detached), token);
    metadata_proxy_set_state(value, detached, token);
    R_set_altrep_data2(value, R_NilValue);
    numeric_data *result = numeric_storage(detached);
    UNPROTECT(2);
    return result;
}

static void detach_materialized_patch_target(SEXP value) {
    if (ALTREP(value) &&
        (R_altrep_inherits(value, dtatools_numeric_class) ||
         R_altrep_inherits(value, dtatools_dictstring_class))) {
        (void) detach_shared_materialized_payload(value);
    }
}

typedef struct {
    SEXP value;
    const int *integer_values;
    numeric_reader real_reader;
    R_xlen_t *snapshot;
    R_xlen_t limit;
    int real;
    int snapshot_required;
} reference_rows;

static R_xlen_t reference_live_row_at(
    const reference_rows *rows, R_xlen_t index
) {
    record_reference_row_read();
    if (rows->real) {
        int missing_code;
        double value = numeric_reader_at(
            &rows->real_reader, index, &missing_code
        );
        if (missing_code >= 0 || !R_FINITE(value) ||
            value != trunc(value) || value <= 0 ||
            value > (double) R_XLEN_T_MAX) {
            Rf_error("invalid reference mutation row");
        }
        return (R_xlen_t) value;
    }
    int value = rows->integer_values == NULL
        ? INTEGER_ELT(rows->value, index) : rows->integer_values[index];
    if (value == NA_INTEGER || value <= 0) {
        Rf_error("invalid reference mutation row");
    }
    return (R_xlen_t) value;
}

static R_xlen_t reference_row_at(
    const reference_rows *rows, R_xlen_t index
) {
    return rows->snapshot == NULL
        ? reference_live_row_at(rows, index) : rows->snapshot[index];
}

static reference_rows reference_rows_create(
    SEXP value, R_xlen_t limit
) {
    reference_rows rows;
    memset(&rows, 0, sizeof(rows));
    rows.value = value;
    rows.limit = limit;
    if (value == R_NilValue) return rows;
    if (TYPEOF(value) == INTSXP) {
        rows.integer_values = (const int *) DATAPTR_OR_NULL(value);
    } else if (TYPEOF(value) == REALSXP) {
        rows.real_reader = numeric_reader_create(value, XLENGTH(value));
        rows.real = 1;
    } else {
        Rf_error("invalid reference mutation row plan");
    }
    R_xlen_t length = XLENGTH(value);
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t row = reference_row_at(&rows, index);
        if (row > limit) Rf_error("invalid reference mutation row");
    }
    return rows;
}

static int reference_rows_alias_target(SEXP rows, SEXP target) {
    if (rows == R_NilValue) return 0;
    if (rows == target) return 1;

    numeric_data *row_storage = unmaterialized_numeric_read_storage(rows);
    numeric_data *target_storage = unmaterialized_numeric_read_storage(target);
    if (row_storage != NULL && row_storage == target_storage) return 1;

    const void *row_values = DATAPTR_OR_NULL(rows);
    const void *target_values = DATAPTR_OR_NULL(target);
    return row_values != NULL && row_values == target_values;
}

static reference_rows reference_patch_rows_create(
    SEXP value, SEXP target, R_xlen_t limit
) {
    reference_rows rows = reference_rows_create(value, limit);
    rows.snapshot_required = reference_rows_alias_target(value, target);
    return rows;
}

static void snapshot_reference_rows(reference_rows *rows) {
    if (!rows->snapshot_required || rows->snapshot != NULL ||
        rows->value == R_NilValue) {
        return;
    }
    R_xlen_t length = XLENGTH(rows->value);
    if ((size_t) length > SIZE_MAX / sizeof(R_xlen_t)) {
        Rf_error("reference mutation row plan is too large");
    }
    rows->snapshot = (R_xlen_t *) malloc(
        length == 0 ? 1 : (size_t) length * sizeof(R_xlen_t)
    );
    if (rows->snapshot == NULL) {
        Rf_error("could not snapshot the reference mutation row plan");
    }
    native_scratch_allocated += (double) length * sizeof(R_xlen_t);
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        rows->snapshot[index] = reference_live_row_at(rows, index);
    }
}

static void release_reference_rows(reference_rows *rows) {
    free(rows->snapshot);
    rows->snapshot = NULL;
}

static R_xlen_t reference_patch_row(
    const reference_rows *rows, R_xlen_t index
) {
    if (rows->value == R_NilValue) return index;
    R_xlen_t row = reference_row_at(rows, index);
    if (row > rows->limit) Rf_error("invalid reference mutation row");
    return row - 1;
}

typedef enum {
    REFERENCE_VALUES_SCALAR,
    REFERENCE_VALUES_SELECTED,
    REFERENCE_VALUES_BY_ROW
} reference_value_mode;

typedef struct {
    R_xlen_t count;
    R_xlen_t value_count;
    reference_value_mode mode;
} reference_value_plan;

static reference_value_plan reference_value_plan_create(
    SEXP values, const reference_rows *rows, R_xlen_t count,
    R_xlen_t row_count, int allow_by_row, const char *error_message
) {
    reference_value_plan plan = {
        count, XLENGTH(values), REFERENCE_VALUES_SELECTED
    };
    if (plan.value_count == 1) {
        plan.mode = REFERENCE_VALUES_SCALAR;
    } else if (allow_by_row && rows->value != R_NilValue &&
               plan.value_count == row_count) {
        plan.mode = REFERENCE_VALUES_BY_ROW;
    } else if (plan.value_count != count &&
               !(count == 0 && plan.value_count == 0)) {
        Rf_error("%s", error_message);
    }
    return plan;
}

static R_xlen_t reference_value_index(
    const reference_value_plan *plan, R_xlen_t index, R_xlen_t row
) {
    if (plan->mode == REFERENCE_VALUES_SCALAR) return 0;
    if (plan->mode == REFERENCE_VALUES_BY_ROW) {
        if (row >= plan->value_count) Rf_error("invalid reference mutation row");
        return row;
    }
    return index;
}

static void validate_materialized_numeric_replacement(
    const numeric_data *target, const numeric_reader *reader,
    const reference_rows *rows, reference_value_plan values
) {
    int fits_requested = 1;
    int fits_int = 1;
    int fits_long = 1;
    int fits_float = 1;
    int fits_double = 1;
    uint32_t float_maximum_bits = UINT32_C(0x7effffff);
    float float_maximum;
    memcpy(&float_maximum, &float_maximum_bits, sizeof(float_maximum));
    R_xlen_t count = values.mode == REFERENCE_VALUES_SCALAR
        ? 1 : values.count;
    for (R_xlen_t index = 0; index < count; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t row = values.mode == REFERENCE_VALUES_SCALAR
            ? 0 : reference_patch_row(rows, index);
        R_xlen_t value_index = reference_value_index(&values, index, row);
        int missing_code;
        double value = numeric_reader_at(reader, value_index, &missing_code);
        if (missing_code >= 0) {
            if (missing_code == 256 ||
                (missing_code != 0 &&
                 (missing_code < 'a' || missing_code > 'z'))) {
                Rf_error(
                    "`values` cannot contain `NaN` or infinities; use "
                    "`NA_real_` for Stata system missing"
                );
            }
            continue;
        }
        if (!R_FINITE(value)) {
            Rf_error(
                "`values` cannot contain `NaN` or infinities; use "
                "`NA_real_` for Stata system missing"
            );
        }
        double encoded = compact_patch_encoded_value(value, target->temporal);
        int integral = R_FINITE(encoded) && encoded == trunc(encoded);
        int element_fits_int = integral &&
            encoded >= -32767.0 && encoded <= 32740.0;
        int element_fits_long = integral &&
            encoded >= -2147483647.0 && encoded <= 2147483620.0;
        int element_fits_float = R_FINITE(encoded) &&
            fabs(encoded) <= (double) float_maximum;
        int element_fits_double = R_FINITE(encoded) &&
            fabs(encoded) <= DBL_MAX / 2.0;
        fits_int = fits_int && element_fits_int;
        fits_long = fits_long && element_fits_long;
        fits_float = fits_float && element_fits_float;
        fits_double = fits_double && element_fits_double;
        switch (target->kind) {
        case NUMERIC_BYTE:
            fits_requested = fits_requested && integral &&
                encoded >= -127.0 && encoded <= 100.0;
            break;
        case NUMERIC_INT:
            fits_requested = fits_requested && element_fits_int;
            break;
        case NUMERIC_LONG:
            fits_requested = fits_requested && element_fits_long;
            break;
        case NUMERIC_FLOAT:
            fits_requested = fits_requested && element_fits_float;
            break;
        default:
            Rf_error("invalid compact Stata numeric storage type");
        }
    }
    if (fits_requested) return;
    const char *storage_name = target->kind == NUMERIC_BYTE ? "byte" :
        target->kind == NUMERIC_INT ? "int" :
        target->kind == NUMERIC_LONG ? "long" : "float";
    const char *recommendation = NULL;
    if (target->kind == NUMERIC_BYTE && fits_int) recommendation = "int";
    else if ((target->kind == NUMERIC_BYTE ||
              target->kind == NUMERIC_INT) && fits_long) {
        recommendation = "long";
    } else if ((target->kind == NUMERIC_BYTE ||
                target->kind == NUMERIC_INT) && fits_float) {
        recommendation = "float";
    } else if (fits_double) {
        recommendation = "double";
    }
    if (recommendation == NULL) {
        Rf_error("No Stata numeric storage can represent `x`");
    }
    Rf_error(
        "Stata %s storage cannot represent `x`; use `dta_%s(x)`",
        storage_name, recommendation
    );
}

static double materialized_numeric_patch_value(
    const numeric_data *target, double value, int missing_code
) {
    if (missing_code >= 0) {
        int offset = missing_code == 0 ? 0 : missing_code - 'a' + 1;
        return numeric_missing_value(offset);
    }
    double encoded = compact_patch_encoded_value(value, target->temporal);
    double stored;
    switch (target->kind) {
    case NUMERIC_BYTE:
        stored = (double) ((int8_t) encoded);
        break;
    case NUMERIC_INT:
        stored = (double) ((int16_t) encoded);
        break;
    case NUMERIC_LONG:
        stored = (double) ((int32_t) encoded);
        break;
    case NUMERIC_FLOAT:
        stored = (double) ((float) encoded);
        break;
    default:
        Rf_error("invalid compact Stata numeric storage type");
    }
    return numeric_observed_value(stored, target->temporal);
}

typedef struct {
    numeric_reader reader;
    reference_value_plan values;
    unsigned char scalar_encoded[4];
    int scalar_missing_code;
    int validate_on_apply;
} compact_replacement_plan;

static compact_replacement_plan compact_replacement_plan_create(
    const numeric_data *target, SEXP values, const reference_rows *rows,
    reference_value_plan value_plan, int prevalidate, numeric_data *reader_encoding
) {
    compact_replacement_plan plan;
    memset(&plan, 0, sizeof(plan));
    plan.values = value_plan;
    plan.scalar_missing_code = -1;
    plan.validate_on_apply = !prevalidate;
    plan.reader = numeric_reader_create(values, value_plan.value_count);
    if (plan.reader.storage != NULL) {
        *reader_encoding = *plan.reader.storage;
        plan.reader.storage = reader_encoding;
    }
    if (value_plan.mode == REFERENCE_VALUES_SCALAR) {
        double value = numeric_reader_at(
            &plan.reader, 0, &plan.scalar_missing_code
        );
        validate_compact_patch_value(
            target, value, plan.scalar_missing_code
        );
        encode_compact_patch_value(
            target, value, plan.scalar_missing_code,
            plan.scalar_encoded
        );
    } else if (prevalidate) {
        for (R_xlen_t index = 0; index < value_plan.count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            int missing_code;
            R_xlen_t value_index = value_plan.mode == REFERENCE_VALUES_BY_ROW
                ? reference_patch_row(rows, index) : index;
            double value = numeric_reader_at(
                &plan.reader, value_index, &missing_code
            );
            validate_compact_patch_value(target, value, missing_code);
        }
    }
    return plan;
}

static void apply_compact_replacement(
    numeric_data *target, const reference_rows *rows,
    const compact_replacement_plan *replacement
) {
    size_t width = numeric_kind_width(target->kind);
    if (replacement->values.mode == REFERENCE_VALUES_SCALAR) {
        int new_missing = replacement->scalar_missing_code >= 0;
        if (rows->value == R_NilValue) {
            fill_encoded_compact_patch_value(
                target, replacement->scalar_encoded, width
            );
            target->missing_count = new_missing ? target->length : 0;
            return;
        }
        for (R_xlen_t index = 0;
             index < replacement->values.count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            size_t row = (size_t) reference_patch_row(rows, index);
            int old_missing = numeric_value_is_missing_at(target, row);
            if (old_missing && !new_missing) target->missing_count--;
            if (!old_missing && new_missing) target->missing_count++;
            write_encoded_compact_patch_value(
                target, row, replacement->scalar_encoded, width
            );
        }
        return;
    }
    for (R_xlen_t index = 0;
         index < replacement->values.count; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        int missing_code;
        R_xlen_t row = reference_patch_row(rows, index);
        R_xlen_t value_index = reference_value_index(
            &replacement->values, index, row
        );
        double value = numeric_reader_at(
            &replacement->reader, value_index, &missing_code
        );
        if (replacement->validate_on_apply) {
            validate_compact_patch_value(target, value, missing_code);
        }
        size_t row_offset = (size_t) row;
        int old_missing = numeric_value_is_missing_at(target, row_offset);
        int new_missing = missing_code >= 0;
        if (old_missing && !new_missing) target->missing_count--;
        if (!old_missing && new_missing) target->missing_count++;
        write_compact_patch_value(
            target, row_offset, value, missing_code
        );
    }
}

typedef struct {
    SEXP target;
    SEXP saved_data1;
    SEXP saved_data2;
    reference_rows *rows;
    const compact_replacement_plan *replacement;
    numeric_data *compact;
    unsigned char *undo;
    size_t undo_bytes;
    size_t width;
    size_t saved_missing_count;
    int journal_complete;
} compact_patch_transaction;

static void restore_compact_patch(compact_patch_transaction *transaction) {
    if (R_altrep_data1(transaction->target) != transaction->saved_data1 ||
        R_altrep_data2(transaction->target) != transaction->saved_data2) {
        R_set_altrep_data1(transaction->target, transaction->saved_data1);
        R_set_altrep_data2(transaction->target, transaction->saved_data2);
        return;
    }
    if (transaction->compact == NULL || transaction->undo == NULL) return;
    if (transaction->rows->value == R_NilValue) {
        if (transaction->undo_bytes > 0) {
            memcpy(
                transaction->compact->values,
                transaction->undo,
                transaction->undo_bytes
            );
        }
    } else {
        R_xlen_t count = transaction->replacement->values.count;
        for (R_xlen_t index = 0; index < count; index++) {
            size_t row = (size_t) reference_patch_row(
                transaction->rows, index
            );
            memcpy(
                (unsigned char *) transaction->compact->values +
                    row * transaction->width,
                transaction->undo + (size_t) index * transaction->width,
                transaction->width
            );
        }
    }
    transaction->compact->missing_count = transaction->saved_missing_count;
}

static SEXP apply_compact_patch_transaction(void *data) {
    compact_patch_transaction *transaction =
        (compact_patch_transaction *) data;
    snapshot_reference_rows(transaction->rows);
    R_xlen_t count = transaction->replacement->values.count;
    if (transaction->rows->value == R_NilValue) {
        if (transaction->undo_bytes > 0) {
            memcpy(
                transaction->undo,
                transaction->compact->values,
                transaction->undo_bytes
            );
            old_journal_bytes += (double) transaction->undo_bytes;
        }
    } else {
        for (R_xlen_t index = 0; index < count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            size_t row = (size_t) reference_patch_row(
                transaction->rows, index
            );
            memcpy(
                transaction->undo + (size_t) index * transaction->width,
                (unsigned char *) transaction->compact->values +
                    row * transaction->width,
                transaction->width
            );
            old_journal_bytes += (double) transaction->width;
        }
    }
    transaction->journal_complete = 1;

    transaction->compact = detach_compact_patch_target(transaction->target);
    if (transaction->compact == NULL) {
        Rf_error("compact replacement target became unavailable");
    }
    transaction->saved_missing_count = transaction->compact->missing_count;
    apply_compact_replacement(
        transaction->compact,
        transaction->rows,
        transaction->replacement
    );
    if (count > 0) maybe_inject_reference_write_interrupt();
    R_CheckUserInterrupt();
    return Rf_ScalarLogical(1);
}

static void cleanup_compact_patch_transaction(
    void *data, Rboolean jump
) {
    compact_patch_transaction *transaction =
        (compact_patch_transaction *) data;
    if (jump && transaction->journal_complete) {
        restore_compact_patch(transaction);
    }
    release_reference_rows(transaction->rows);
    free(transaction->undo);
    transaction->undo = NULL;
}

typedef struct {
    SEXP target;
    SEXP replacement;
    reference_string_reader replacement_reader;
    numeric_reader numeric_replacement_reader;
    const numeric_data *materialized_numeric;
    SEXP saved_data1;
    SEXP saved_data2;
    SEXP string_undo;
    SEXP dictstring_private_cache;
    SEXP dictstring_source;
    SEXP replacement_empty;
    reference_rows *rows;
    unsigned char *undo;
    size_t width;
    reference_value_plan values;
    R_xlen_t writes_completed;
    int type;
    int journal_complete;
    int delayed_dictstring_finalize;
    int rollback_required;
    int replacement_string_width;
} vector_patch_transaction;

static SEXP vector_patch_replacement_string(
    const vector_patch_transaction *transaction, R_xlen_t index
) {
    SEXP value = reference_string_reader_at(
        &transaction->replacement_reader, index
    );
    return value == NA_STRING ? transaction->replacement_empty : value;
}

static void validate_reference_replacement_string(
    SEXP value, int declared_width
) {
    size_t width = reference_string_width(value, "replacement");
    if (declared_width > 0 && width > (size_t) declared_width) {
        Rf_error(
            "Replacement values do not fit their declared Stata string storage"
        );
    }
}

static void validate_vector_patch_replacement_strings(
    const vector_patch_transaction *transaction
) {
    if (transaction->type != STRSXP || transaction->values.count == 0) {
        return;
    }
    if (transaction->values.mode == REFERENCE_VALUES_SCALAR) {
        validate_reference_replacement_string(
            vector_patch_replacement_string(transaction, 0),
            transaction->replacement_string_width
        );
        return;
    }
    for (R_xlen_t index = 0;
         index < transaction->values.count; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t row = reference_patch_row(transaction->rows, index);
        R_xlen_t replacement_index = reference_value_index(
            &transaction->values, index, row
        );
        validate_reference_replacement_string(
            vector_patch_replacement_string(transaction, replacement_index),
            transaction->replacement_string_width
        );
    }
}

static int vector_patch_state_changed(
    const vector_patch_transaction *transaction
) {
    return ALTREP(transaction->target) &&
        (R_altrep_data1(transaction->target) != transaction->saved_data1 ||
         R_altrep_data2(transaction->target) != transaction->saved_data2);
}

static void restore_vector_patch(vector_patch_transaction *transaction) {
    if (vector_patch_state_changed(transaction)) {
        SEXP current_data1 = R_altrep_data1(transaction->target);
        if (transaction->delayed_dictstring_finalize &&
            current_data1 != transaction->saved_data1) {
            dictstring_finalize(current_data1);
        }
        R_set_altrep_data1(transaction->target, transaction->saved_data1);
        R_set_altrep_data2(transaction->target, transaction->saved_data2);
        return;
    }
    double *real_output = transaction->type == REALSXP
        ? REAL(transaction->target) : NULL;
    int *integer_output = transaction->type == INTSXP
        ? INTEGER(transaction->target) : NULL;
    int *logical_output = transaction->type == LGLSXP
        ? LOGICAL(transaction->target) : NULL;
    for (R_xlen_t index = 0;
         index < transaction->writes_completed; index++) {
        R_xlen_t row = reference_patch_row(transaction->rows, index);
        switch (transaction->type) {
        case REALSXP:
            memcpy(
                real_output + row,
                transaction->undo + (size_t) index * transaction->width,
                transaction->width
            );
            break;
        case INTSXP:
            memcpy(
                integer_output + row,
                transaction->undo + (size_t) index * transaction->width,
                transaction->width
            );
            break;
        case LGLSXP:
            memcpy(
                logical_output + row,
                transaction->undo + (size_t) index * transaction->width,
                transaction->width
            );
            break;
        case STRSXP:
            SET_STRING_ELT(
                transaction->target, row,
                STRING_ELT(transaction->string_undo, index)
            );
            break;
        }
    }
}

static SEXP apply_vector_patch_transaction(void *data) {
    vector_patch_transaction *transaction =
        (vector_patch_transaction *) data;
    snapshot_reference_rows(transaction->rows);
    int full_dictionary_overwrite =
        transaction->dictstring_source != R_NilValue &&
        transaction->rows->value == R_NilValue;
    if (!full_dictionary_overwrite) {
        validate_vector_patch_replacement_strings(transaction);
    } else if (transaction->values.count > 0 &&
               transaction->values.mode == REFERENCE_VALUES_SCALAR) {
        validate_reference_replacement_string(
            vector_patch_replacement_string(transaction, 0),
            transaction->replacement_string_width
        );
    }
    if (transaction->rollback_required &&
        (transaction->type != STRSXP ||
         transaction->dictstring_source == R_NilValue)) {
        for (R_xlen_t index = 0;
             index < transaction->values.count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            R_xlen_t row = reference_patch_row(transaction->rows, index);
            switch (transaction->type) {
            case REALSXP: {
                double value = REAL_ELT(transaction->target, row);
                memcpy(
                    transaction->undo + (size_t) index * transaction->width,
                    &value, transaction->width
                );
                break;
            }
            case INTSXP: {
                int value = INTEGER_ELT(transaction->target, row);
                memcpy(
                    transaction->undo + (size_t) index * transaction->width,
                    &value, transaction->width
                );
                break;
            }
            case LGLSXP: {
                int value = LOGICAL_ELT(transaction->target, row);
                memcpy(
                    transaction->undo + (size_t) index * transaction->width,
                    &value, transaction->width
                );
                break;
            }
            case STRSXP:
                SET_STRING_ELT(
                    transaction->string_undo, index,
                    STRING_ELT(transaction->target, row)
                );
                break;
            }
            old_journal_bytes += transaction->type == STRSXP
                ? sizeof(SEXP) : transaction->width;
        }
    }
    transaction->journal_complete = transaction->rollback_required;

    if (full_dictionary_overwrite) {
        SEXP materialized = PROTECT(Rf_allocVector(
            STRSXP, transaction->values.count
        ));
        for (R_xlen_t index = 0;
             index < transaction->values.count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            R_xlen_t replacement_index = reference_value_index(
                &transaction->values, index, index
            );
            SEXP value = vector_patch_replacement_string(
                transaction, replacement_index
            );
            if (transaction->values.mode != REFERENCE_VALUES_SCALAR) {
                validate_reference_replacement_string(
                    value, transaction->replacement_string_width
                );
            }
            SET_STRING_ELT(materialized, index, value);
        }
        R_CheckUserInterrupt();
        R_set_altrep_data2(transaction->target, materialized);
        if (!transaction->delayed_dictstring_finalize) {
            R_set_altrep_data1(transaction->target, R_NilValue);
        }
        transaction->writes_completed = transaction->values.count;
        UNPROTECT(1);
    } else if (transaction->delayed_dictstring_finalize) {
        (void) dictstring_materialize_for_patch(
            transaction->target, transaction->dictstring_private_cache
        );
    } else if (transaction->dictstring_source != R_NilValue) {
        (void) metadata_string_materialize_for_patch(
            transaction->target, transaction->dictstring_source,
            transaction->dictstring_private_cache
        );
    } else {
        detach_materialized_patch_target(transaction->target);
    }
    double *real_output = NULL;
    int *integer_output = NULL;
    int *logical_output = NULL;
    SEXP string_output = R_NilValue;
    if (transaction->type == REALSXP) {
        real_output = (double *) DATAPTR_RW(transaction->target);
    } else if (transaction->type == INTSXP) {
        integer_output = INTEGER(transaction->target);
    } else if (transaction->type == LGLSXP) {
        logical_output = LOGICAL(transaction->target);
    } else if (transaction->type == STRSXP) {
        string_output = ALTREP(transaction->target)
            ? R_altrep_data2(transaction->target) : transaction->target;
    }
    for (R_xlen_t index = transaction->writes_completed;
         index < transaction->values.count; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t row = reference_patch_row(transaction->rows, index);
        R_xlen_t replacement_index = reference_value_index(
            &transaction->values, index, row
        );
        switch (transaction->type) {
        case REALSXP:
            if (transaction->materialized_numeric != NULL) {
                int missing_code;
                double value = numeric_reader_at(
                    &transaction->numeric_replacement_reader,
                    replacement_index, &missing_code
                );
                real_output[row] = materialized_numeric_patch_value(
                    transaction->materialized_numeric, value, missing_code
                );
            } else {
                real_output[row] = REAL_ELT(
                    transaction->replacement, replacement_index
                );
            }
            break;
        case INTSXP:
            integer_output[row] = INTEGER_ELT(
                transaction->replacement, replacement_index
            );
            break;
        case LGLSXP:
            logical_output[row] = LOGICAL_ELT(
                transaction->replacement, replacement_index
            );
            break;
        case STRSXP:
            SET_STRING_ELT(
                string_output, row,
                vector_patch_replacement_string(
                    transaction, replacement_index
                )
            );
            break;
        }
        transaction->writes_completed = index + 1;
    }
    if (transaction->values.count > 0) {
        maybe_inject_reference_write_interrupt();
    }
    R_CheckUserInterrupt();
    return Rf_ScalarLogical(0);
}

static void cleanup_vector_patch_transaction(
    void *data, Rboolean jump
) {
    vector_patch_transaction *transaction =
        (vector_patch_transaction *) data;
    if (jump && transaction->journal_complete &&
        (vector_patch_state_changed(transaction) ||
         transaction->writes_completed > 0)) {
        restore_vector_patch(transaction);
    }
    release_reference_rows(transaction->rows);
    free(transaction->undo);
    transaction->undo = NULL;
}

static void commit_vector_patch_transaction(
    vector_patch_transaction *transaction
) {
    if (!transaction->delayed_dictstring_finalize) return;
    SEXP external = R_altrep_data1(transaction->target);
    if (!compact_payload_is_shared(external)) {
        dictstring_finalize(external);
    }
    R_set_altrep_data1(transaction->target, R_NilValue);
}

static SEXP patch_owned_vector(SEXP target, SEXP rows, SEXP replacement);

static SEXP patch_vector(
    SEXP target, SEXP rows, SEXP replacement, int rollback_required
) {
    if (owned_column(target)) return patch_owned_vector(target, rows, replacement);
    if (rows != R_NilValue &&
        TYPEOF(rows) != INTSXP && TYPEOF(rows) != REALSXP) {
        Rf_error("invalid reference replacement plan");
    }
    SEXP entry_data1 = PROTECT(ALTREP(target) ? R_altrep_data1(target) : R_NilValue);
    SEXP entry_data2 = PROTECT(ALTREP(target) ? R_altrep_data2(target) : R_NilValue);
    R_xlen_t target_length = XLENGTH(target);
    /* Unknown ALTREP operands may call R on every read. Finish those reads
       before native descriptors, journaling or writable target pointers live. */
    rows = PROTECT(rows != R_NilValue && !reference_callback_free_operand(rows)
        ? plain_column(rows, 1) : rows);
    R_xlen_t count = rows == R_NilValue ? target_length : XLENGTH(rows);
    reference_rows row_plan = reference_patch_rows_create(
        rows, target, target_length
    );

    PROTECT(numeric_payload_root(rows));
    numeric_data row_encoding;
    if (row_plan.real_reader.storage != NULL) {
        row_encoding = *row_plan.real_reader.storage;
        row_plan.real_reader.storage = &row_encoding;
    }
    replacement = PROTECT(!reference_callback_free_operand(replacement)
        ? plain_column(replacement, 1) : replacement);
    PROTECT(numeric_payload_root(replacement));
    numeric_data *compact = unmaterialized_numeric_storage(target);
    numeric_data materialized_storage;
    numeric_data *materialized = materialized_numeric_storage(
        target, &materialized_storage
    ) ? &materialized_storage : NULL;
    int native_by_row = compact != NULL || materialized != NULL ||
        unmaterialized_dictstring_source(replacement) != R_NilValue;
    reference_value_plan value_plan = reference_value_plan_create(
        replacement, &row_plan, count, target_length, native_by_row,
        "invalid reference replacement plan"
    );
    /* Replacement Length is a callback boundary. Materializing target there
       may explicitly free the compact descriptor even while data1 is rooted. */
    if ((ALTREP(target) && (R_altrep_data1(target) != entry_data1 ||
                           R_altrep_data2(target) != entry_data2)) ||
        XLENGTH(target) != target_length) {
        Rf_error("reference mutation target changed while preparing replacement");
    }
    if (compact != NULL) {
        numeric_data target_encoding = *compact, replacement_encoding;
        compact_replacement_plan replacement_plan =
            compact_replacement_plan_create(
                &target_encoding, replacement, &row_plan, value_plan, 1, &replacement_encoding
            );
        if (R_altrep_data1(target) != entry_data1 || R_altrep_data2(target) != entry_data2 ||
            XLENGTH(target) != target_length) {
            Rf_error("reference mutation target changed while preparing replacement");
        }
        if (count == 0) {
            release_reference_rows(&row_plan);
            UNPROTECT(6);
            return Rf_ScalarLogical(0);
        }
        size_t width = numeric_kind_width(compact->kind);
        if ((size_t) count > SIZE_MAX / width) {
            Rf_error("reference replacement plan is too large");
        }
        size_t undo_bytes = (size_t) count * width;
        SEXP saved_state = PROTECT(Rf_allocVector(VECSXP, 2));
        SET_VECTOR_ELT(saved_state, 0, R_altrep_data1(target));
        SET_VECTOR_ELT(saved_state, 1, R_altrep_data2(target));
        SEXP continuation = PROTECT(R_MakeUnwindCont());
        unsigned char *undo = (unsigned char *) malloc(
            undo_bytes == 0 ? 1 : undo_bytes
        );
        if (undo == NULL) {
            UNPROTECT(8);
            Rf_error("could not allocate reference replacement rollback data");
        }
        native_scratch_allocated += (double) undo_bytes;
        compact_patch_transaction transaction = {
            target,
            VECTOR_ELT(saved_state, 0),
            VECTOR_ELT(saved_state, 1),
            &row_plan,
            &replacement_plan,
            compact,
            undo,
            undo_bytes,
            width,
            compact->missing_count,
            0
        };
        SEXP result = R_UnwindProtect(
            apply_compact_patch_transaction, &transaction,
            cleanup_compact_patch_transaction, &transaction,
            continuation
        );
        UNPROTECT(8);
        return result;
    }

    numeric_data materialized_replacement_encoding;
    numeric_reader materialized_reader;
    memset(&materialized_reader, 0, sizeof(materialized_reader));
    if (materialized != NULL) {
        materialized_reader = numeric_reader_create(
            replacement, value_plan.value_count
        );
        if (materialized_reader.storage != NULL) {
            materialized_replacement_encoding = *materialized_reader.storage;
            materialized_reader.storage = &materialized_replacement_encoding;
        }
        validate_materialized_numeric_replacement(
            materialized, &materialized_reader, &row_plan, value_plan
        );
    } else if (TYPEOF(target) != TYPEOF(replacement)) {
        Rf_error("replacement storage does not match its target");
    }
    int type = TYPEOF(target);
    if (type != REALSXP && type != INTSXP &&
        type != LGLSXP && type != STRSXP) {
        Rf_error("unsupported reference replacement storage");
    }
    if (count == 0) {
        if (type == STRSXP &&
            value_plan.mode == REFERENCE_VALUES_SCALAR) {
            PROTECT(dictstring_read_root(replacement));
            reference_string_reader reader =
                reference_string_reader_create(replacement, R_NilValue);
            int declared_width = string_declared_width(
                Rf_getAttrib(
                    target, Rf_install("stata.string.storage")
                ),
                "Replacement values do not fit their declared Stata string storage"
            );
            validate_reference_replacement_string(
                reference_string_reader_at(&reader, 0), declared_width
            );
            UNPROTECT(1);
        }
        release_reference_rows(&row_plan);
        UNPROTECT(6);
        return Rf_ScalarLogical(0);
    }
    if (ALTREP(target) && !reference_mutable_altrep(target)) {
        Rf_error("generic ALTREP targets must be detached before replacement");
    }
    size_t width = type == REALSXP ? sizeof(double) : sizeof(int);
    SEXP dictstring_source = type == STRSXP
        ? unmaterialized_dictstring_source(target) : R_NilValue;
    SEXP replacement_dictstring_source = type == STRSXP
        ? unmaterialized_dictstring_source(replacement) : R_NilValue;
    if (rows == R_NilValue &&
        ((target == replacement &&
          (type != STRSXP || dictstring_source != R_NilValue)) ||
         (dictstring_source == target &&
          replacement_dictstring_source == target))) {
        release_reference_rows(&row_plan);
        UNPROTECT(6);
        return Rf_ScalarLogical(0);
    }
    int delayed_dictstring_finalize = dictstring_source == target;
    SEXP saved_state = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(
        saved_state, 0,
        ALTREP(target) ? R_altrep_data1(target) : R_NilValue
    );
    SET_VECTOR_ELT(
        saved_state, 1,
        ALTREP(target) ? R_altrep_data2(target) : R_NilValue
    );
    SEXP string_undo = PROTECT(
        rollback_required && type == STRSXP &&
            dictstring_source == R_NilValue
            ? Rf_allocVector(STRSXP, count) : R_NilValue
    );
    SEXP private_cache = PROTECT(
        dictstring_source != R_NilValue && rows != R_NilValue
            ? reference_string_reader_private_cache(
                dictstring_source, count
            )
            : R_NilValue
    );
    SEXP replacement_reader_cache = PROTECT(
        type == STRSXP
            ? reference_string_reader_private_cache(
                replacement,
                value_plan.mode == REFERENCE_VALUES_SCALAR ? 1 : count
            )
            : R_NilValue
    );
    PROTECT(dictstring_read_root(replacement));
    reference_string_reader replacement_reader =
        reference_string_reader_create(
            replacement, replacement_reader_cache
        );
    SEXP replacement_scalar = PROTECT(
        type == STRSXP &&
            value_plan.mode == REFERENCE_VALUES_SCALAR
            ? reference_string_reader_at(&replacement_reader, 0)
            : R_NilValue
    );
    replacement_reader.scalar = replacement_scalar;
    SEXP replacement_empty = PROTECT(
        type == STRSXP ? Rf_mkChar("") : R_NilValue
    );
    SEXP continuation = PROTECT(R_MakeUnwindCont());
    unsigned char *undo = NULL;
    if (rollback_required && type != STRSXP) {
        if ((size_t) count > SIZE_MAX / width) {
            UNPROTECT(14);
            Rf_error("reference replacement plan is too large");
        }
        size_t bytes = (size_t) count * width;
        undo = (unsigned char *) malloc(bytes == 0 ? 1 : bytes);
        if (undo == NULL) {
            UNPROTECT(14);
            Rf_error("could not allocate reference replacement rollback data");
        }
        native_scratch_allocated += (double) bytes;
    }
    vector_patch_transaction transaction = {
        .target = target,
        .replacement = replacement,
        .replacement_reader = replacement_reader,
        .numeric_replacement_reader = materialized_reader,
        .materialized_numeric = materialized,
        .saved_data1 = VECTOR_ELT(saved_state, 0),
        .saved_data2 = VECTOR_ELT(saved_state, 1),
        .string_undo = string_undo,
        .dictstring_private_cache = private_cache,
        .dictstring_source = dictstring_source,
        .replacement_empty = replacement_empty,
        .rows = &row_plan,
        .undo = undo,
        .width = width,
        .values = value_plan,
        .writes_completed = 0,
        .type = type,
        .journal_complete = 0,
        .delayed_dictstring_finalize = delayed_dictstring_finalize,
        .rollback_required = rollback_required,
        .replacement_string_width = type == STRSXP
            ? string_declared_width(
                Rf_getAttrib(
                    target, Rf_install("stata.string.storage")
                ),
                "Replacement values do not fit their declared Stata string storage"
            )
            : -1
    };
    /* The declared storage attribute can itself be a foreign ALTSTRING. All
       its callbacks must finish before journal/apply retain native state. */
    if ((ALTREP(target) && (R_altrep_data1(target) != entry_data1 ||
                           R_altrep_data2(target) != entry_data2)) ||
        XLENGTH(target) != target_length) {
        free(undo);
        Rf_error("reference mutation target changed while preparing replacement");
    }
    SEXP result = R_UnwindProtect(
        apply_vector_patch_transaction, &transaction,
        cleanup_vector_patch_transaction, &transaction,
        continuation
    );
    commit_vector_patch_transaction(&transaction);
    UNPROTECT(14);
    return result;
}

SEXP C_dtatools_patch_vector(
    SEXP target, SEXP rows, SEXP replacement
) {
    numeric_data *immutable = unmaterialized_numeric_read_storage(target);
    if (immutable != NULL && numeric_payload_retained(immutable)) {
        SEXP entry_data1 = PROTECT(R_altrep_data1(target));
        SEXP entry_data2 = PROTECT(R_altrep_data2(target));
        R_xlen_t length = XLENGTH(target);
        SEXP working = PROTECT(numeric_compact_copy(immutable));
        SHALLOW_DUPLICATE_ATTRIB(working, target);
        owned_numeric_compatibility_bytes +=
            (double) immutable->length * (double) numeric_kind_width(immutable->kind);
        SEXP result = PROTECT(patch_vector(working, rows, replacement, 0));
        if (R_altrep_data1(target) != entry_data1 || R_altrep_data2(target) != entry_data2 ||
            XLENGTH(target) != length) {
            Rf_error("reference mutation target changed while preparing replacement");
        }
        if (length != 0 && (rows == R_NilValue || XLENGTH(rows) != 0)) {
            if (R_altrep_inherits(target, dtatools_numeric_class)) {
                R_set_altrep_data1(target, R_altrep_data1(working));
            } else {
                SEXP token = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, R_NilValue));
                compact_payload_claim(R_altrep_data1(working), token);
                metadata_proxy_set_state(target, working, token);
                UNPROTECT(1);
            }
        }
        UNPROTECT(4);
        return result;
    }
    return patch_vector(target, rows, replacement, 1);
}

SEXP C_dtatools_patch_data_column(
    SEXP data, SEXP location, SEXP target, SEXP rows, SEXP replacement
) {
    if (TYPEOF(data) != VECSXP || TYPEOF(location) != INTSXP ||
        XLENGTH(location) != 1) {
        Rf_error("invalid generic ALTREP replacement target");
    }
    int index = INTEGER_ELT(location, 0);
    if (index == NA_INTEGER || index < 1) {
        Rf_error("invalid generic ALTREP replacement target");
    }

    int detached = ALTREP(target) && !reference_mutable_altrep(target);
    if ((R_xlen_t) index > XLENGTH(data)) {
        if (!detached || XLENGTH(target) == 0 ||
            (rows != R_NilValue && XLENGTH(rows) == 0)) {
            PROTECT(patch_vector(target, rows, replacement, 1));
            UNPROTECT(1);
            return target;
        }
        SEXP column = PROTECT(plain_column(target, rows != R_NilValue));
        PROTECT(patch_vector(column, rows, replacement, 0));
        UNPROTECT(2);
        return column;
    }
    if (target != VECTOR_ELT(data, (R_xlen_t) index - 1)) {
        Rf_error("invalid generic ALTREP replacement target");
    }
    if (XLENGTH(target) == 0 ||
        (rows != R_NilValue && XLENGTH(rows) == 0)) {
        PROTECT(patch_vector(target, rows, replacement, 1));
        UNPROTECT(1);
        return target;
    }
    if (!detached) {
        PROTECT(patch_vector(target, rows, replacement, 1));
        UNPROTECT(1);
        return target;
    }

    SEXP column = PROTECT(plain_column(target, rows != R_NilValue));
    PROTECT(patch_vector(column, rows, replacement, 0));
    SET_VECTOR_ELT(data, (R_xlen_t) index - 1, column);
    UNPROTECT(2);
    return column;
}

SEXP C_dtatools_set_data_column(SEXP data, SEXP location, SEXP column) {
    if (TYPEOF(data) != VECSXP) {
        Rf_error("`data` must be a list");
    }
    if (TYPEOF(location) != INTSXP || XLENGTH(location) != 1) {
        Rf_error("`location` must be one integer value");
    }
    int index = INTEGER(location)[0];
    if (index == NA_INTEGER || index < 1 ||
        (R_xlen_t) index > XLENGTH(data)) {
        Rf_error("`location` is out of range");
    }
    SET_VECTOR_ELT(data, (R_xlen_t) index - 1, column);
    return column;
}

static R_xlen_t mutation_slot(SEXP data, SEXP location) {
    if (TYPEOF(data) != VECSXP || TYPEOF(location) != INTSXP || XLENGTH(location) != 1) {
        Rf_error("invalid physical mutation target");
    }
    int slot = INTEGER_ELT(location, 0);
    if (slot == NA_INTEGER || slot < 1 || (R_xlen_t) slot > XLENGTH(data)) {
        Rf_error("invalid physical mutation target");
    }
    return (R_xlen_t) slot - 1;
}

static SEXP mutation_detached_handle(SEXP target, int copy_values) {
    if (ALTREP(target) && !reference_mutable_altrep(target)) {
        return plain_column(target, copy_values);
    }
    if (owned_column(target)) return owned_capture(target);
    /* These working proxies stay inside the native transaction. Their patch
       paths allocate independent decoded values, so preparation need not mark
       original backing shared or revoke a claim that an error must preserve. */
    SEXP result = PROTECT(ALTREP(target) && TYPEOF(target) == REALSXP
        ? metadata_proxy(target, dtatools_metadata_real_class, 0)
        : ALTREP(target) && TYPEOF(target) == STRSXP
            ? metadata_proxy(target, dtatools_metadata_string_class, 0)
            : C_dtatools_metadata_copy(target));
    numeric_data storage;
    if (ALTREP(result) &&
        (materialized_numeric_storage(target, &storage) ||
         (TYPEOF(result) == STRSXP && unmaterialized_dictstring_source(target) == R_NilValue))) {
        (void) DATAPTR_RO(result);
    }
    UNPROTECT(1);
    return result;
}

static void commit_identical_slots(SEXP data, SEXP before, SEXP after) {
    /* Slots and table shape are already validated. No allocation or R code
       may run between committing the first and final identical slot. */
    for (R_xlen_t i = 0; i < XLENGTH(data); i++) {
        if (VECTOR_ELT(data, i) == before) SET_VECTOR_ELT(data, i, after);
    }
}

#include "mutation-write.h"

SEXP C_dtatools_patch_slot(SEXP data, SEXP location, SEXP rows,
                                SEXP replacement, SEXP entry_shared) {
    R_xlen_t slot = mutation_slot(data, location);
    SEXP numeric_result = patch_numeric_slot(data, slot, rows, replacement,
        Rf_asLogical(entry_shared) != FALSE);
    if (numeric_result != R_NilValue) return numeric_result;
    SEXP plain_result = patch_plain_slot(data, slot, rows, replacement,
        Rf_asLogical(entry_shared) != FALSE);
    if (plain_result != R_NilValue) return plain_result;
    SEXP target = VECTOR_ELT(data, slot);
    if (rows == R_NilValue && TYPEOF(target) == STRSXP) {
        SEXP source = unmaterialized_dictstring_source(target);
        SEXP from = unmaterialized_dictstring_source(replacement);
        if (source != R_NilValue && from != R_NilValue &&
            R_altrep_data1(source) == R_altrep_data1(from)) return data;
    }
    PROTECT(target);
    SEXP saved_data1 = PROTECT(ALTREP(target) ? R_altrep_data1(target) : R_NilValue);
    SEXP saved_data2 = PROTECT(ALTREP(target) ? R_altrep_data2(target) : R_NilValue);
    R_xlen_t target_length = XLENGTH(target);
    /* All plain and owned numeric targets were handled above. Remaining
       dictionary, materialized and foreign ALTREP handles need isolated work
       before the legacy patcher invokes any operand callbacks. */
    int detach = 1;
    if (XLENGTH(target) == 0 || (rows != R_NilValue && XLENGTH(rows) == 0)) detach = 0;
    SEXP column = PROTECT(detach ? mutation_detached_handle(target, rows != R_NilValue) : target);
    PROTECT(patch_vector(column, rows, replacement, !detach));
    if (detach) {
        if (slot >= XLENGTH(data) || VECTOR_ELT(data, slot) != target ||
            XLENGTH(target) != target_length ||
            (ALTREP(target) && (R_altrep_data1(target) != saved_data1 ||
                                R_altrep_data2(target) != saved_data2))) {
            Rf_error("reference mutation target changed while preparing replacement");
        }
        commit_identical_slots(data, target, column);
    }
    UNPROTECT(5);
    return data;
}

static void resize_reference_vector(SEXP value, R_xlen_t length) {
    R_resizeVector(value, length);

}

static int can_resize_reference_columns(
    SEXP data, SEXP current_names, R_xlen_t new_length
) {
    R_xlen_t old_length = XLENGTH(data);
    int is_data_table = Rf_inherits(data, "data.table");
    return new_length == old_length ||
        (!ALTREP(data) &&
         R_isResizable(data) &&
         new_length <= R_maxLength(data) &&
         (!is_data_table ||
          (R_isResizable(current_names) &&
           new_length <= R_maxLength(current_names))));

}

/* Which columns of a result list another object also holds. R's own
   reference counts answer this the way copy-on-modify does: a vector a
   verb built for this result is held by the list alone, while one it
   carried over from an input is held by that input too. */
SEXP C_dtatools_shared_columns(SEXP columns) {
    if (TYPEOF(columns) != VECSXP) Rf_error("`columns` must be a list");
    R_xlen_t length = XLENGTH(columns);
    SEXP result = PROTECT(Rf_allocVector(LGLSXP, length));
    for (R_xlen_t index = 0; index < length; index++) {
        LOGICAL(result)[index] = MAYBE_SHARED(VECTOR_ELT(columns, index));
    }
    UNPROTECT(1);
    return result;
}

/* Validate data.table's non-owning self-reference and names identity.
   Pointer addresses are compared only, never dereferenced. A copied or
   deserialized table, or a replaced names vector, requires assigned repair. */
static int data_table_reference_valid(SEXP data) {
    SEXP selfref = Rf_getAttrib(data, Rf_install(".internal.selfref"));
    return TYPEOF(selfref) == EXTPTRSXP &&
        R_ExternalPtrAddr(selfref) == R_NilValue &&
        R_ExternalPtrTag(selfref) == Rf_getAttrib(data, R_NamesSymbol) &&
        TYPEOF(R_ExternalPtrProtected(selfref)) == EXTPTRSXP &&
        R_ExternalPtrAddr(R_ExternalPtrProtected(selfref)) == data;
}

/* Report the usable physical column allocation, or -1 if it cannot resize.
   data.table must have capacity in both its list and names; the R wrapper
   separately checks its self-reference before promising append readiness. */
SEXP C_dtatools_column_capacity(SEXP x) {
    if (TYPEOF(x) != VECSXP) Rf_error("`x` must be a list");
    if (ALTREP(x) || !R_isResizable(x)) return Rf_ScalarReal(-1);
    R_xlen_t capacity = R_maxLength(x);
    if (Rf_inherits(x, "data.table")) {
        SEXP names = Rf_getAttrib(x, R_NamesSymbol);
        if (TYPEOF(names) != STRSXP || ALTREP(names) ||
            !R_isResizable(names) || !data_table_reference_valid(x)) {
            return Rf_ScalarReal(-1);
        }
        if (R_maxLength(names) < capacity) capacity = R_maxLength(names);
    }
    return Rf_ScalarReal((double) capacity);
}

/* Allocate an isolated resizable outer list, retaining the supplied columns.
   R callers isolate column payloads before using this preparation primitive. */
SEXP C_dtatools_reserve_column_capacity(SEXP x, SEXP capacity_value) {
    if (TYPEOF(x) != VECSXP) Rf_error("`x` must be a list");
    double requested = Rf_asReal(capacity_value);
    R_xlen_t length = XLENGTH(x);
    if (!R_FINITE(requested) || requested < (double) length ||
        requested > (double) R_XLEN_T_MAX || requested != floor(requested)) {
        Rf_error("invalid column capacity");
    }
    R_xlen_t capacity = (R_xlen_t) requested;
    SEXP result = PROTECT(R_allocResizableVector(VECSXP, capacity));
    R_resizeVector(result, length);

    for (R_xlen_t index = 0; index < length; index++) {
        SET_VECTOR_ELT(result, index, VECTOR_ELT(x, index));
    }
    SHALLOW_DUPLICATE_ATTRIB(result, x);
    SEXP original_names = Rf_getAttrib(x, R_NamesSymbol);
    if (TYPEOF(original_names) == STRSXP && XLENGTH(original_names) == length) {
        SEXP names = PROTECT(R_allocResizableVector(STRSXP, capacity));
        R_resizeVector(names, length);
        for (R_xlen_t index = 0; index < length; index++) {
            SET_STRING_ELT(names, index, STRING_ELT(original_names, index));
        }
        SHALLOW_DUPLICATE_ATTRIB(names, original_names);
        Rf_setAttrib(result, R_NamesSymbol, names);
        UNPROTECT(1);
    }
    UNPROTECT(1);
    return result;
}

/* Structural append uses public resize/attribute APIs. Resizing removes names;
   detach them first so R's internal getter does not mark private names shared.
   Reinstalling the attribute can allocate, so an unwind journal restores shape
   and original attribute order. Catastrophic allocation failure during cleanup
   cannot be made recoverable with the public attribute setter API. */
/* An O(1) temporary names value lets the public setter replace the existing
   attribute cell before removal. Merely unlinking that cell leaves its old
   reference alive until collection, which would revoke reuse on reinstallation.
   The placeholder retains only its length, never the original names. */
R_altrep_class_t column_append_blank_names_class;

R_xlen_t column_append_blank_names_length(SEXP value) {
    return (R_xlen_t) REAL(R_altrep_data1(value))[0];
}

SEXP column_append_blank_names_elt(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? R_BlankString : STRING_ELT(materialized, index);
}

void *column_append_blank_names_dataptr(SEXP value, Rboolean writable) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized == R_NilValue) {
        R_xlen_t length = column_append_blank_names_length(value);
        materialized = PROTECT(Rf_allocVector(STRSXP, length));
        for (R_xlen_t i = 0; i < length; i++) SET_STRING_ELT(materialized, i, R_BlankString);
        R_set_altrep_data2(value, materialized);
        UNPROTECT(1);
    }
    return writable ? DATAPTR_RW(materialized) : (void *) DATAPTR_RO(materialized);
}

const void *column_append_blank_names_dataptr_or_null(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? NULL : DATAPTR_OR_NULL(materialized);
}

static SEXP column_append_blank_names(R_xlen_t length) {
    SEXP size = PROTECT(Rf_ScalarReal((double) length));
    SEXP result = R_new_altrep(column_append_blank_names_class, size, R_NilValue);
    UNPROTECT(1);
    return result;
}

typedef struct {
    SEXP tag;
    SEXP value;
    PROTECT_INDEX tag_index, value_index;
} append_attribute;

typedef struct {
    SEXP data, original_names, names, new_name, column, result, blank_old, blank_new;
    append_attribute *attributes;
    size_t attribute_count, attribute_capacity;
    R_xlen_t length;
    int reusable, started;
} column_append_transaction;

static int column_append_failure_stage = 0;
static int column_append_failure_interrupt = 0;

SEXP C_dtatools_inject_column_append_failure(SEXP stage, SEXP interrupt) {
    int value = Rf_asInteger(stage);
    int signal = Rf_asLogical(interrupt);
    if (value < 0 || value > 3 || signal == NA_LOGICAL)
        Rf_error("invalid column append failure injection");
    column_append_failure_stage = value;
    column_append_failure_interrupt = signal;
    return R_NilValue;
}

static void maybe_inject_column_append_failure(int stage) {
    if (column_append_failure_stage != stage) return;
    column_append_failure_stage = 0;
    if (column_append_failure_interrupt) {
        Rf_onintr();
    }
    Rf_error("injected column append failure at stage %d", stage);
}

static SEXP count_append_attribute(SEXP tag, SEXP value, void *context) {
    (void) tag;
    (void) value;
    (*(size_t *) context)++;
    return NULL;
}

static SEXP save_append_attribute(SEXP tag, SEXP value, void *context) {
    column_append_transaction *transaction = context;
    if (transaction->attribute_count >= transaction->attribute_capacity)
        Rf_error("column append attributes changed while preparing journal");
    append_attribute *attribute = &transaction->attributes[transaction->attribute_count++];
    attribute->tag = tag;
    attribute->value = value;
    REPROTECT(tag, attribute->tag_index);
    REPROTECT(value, attribute->value_index);
    return NULL;
}

static SEXP apply_column_append(void *context) {
    column_append_transaction *transaction = context;
    transaction->started = 1;
    if (transaction->reusable)
        Rf_setAttrib(transaction->data, R_NamesSymbol, transaction->blank_old);
    Rf_setAttrib(transaction->data, R_NamesSymbol, R_NilValue);
    maybe_inject_column_append_failure(1);
    if (transaction->reusable) R_resizeVector(transaction->names, transaction->length + 1);
    SET_STRING_ELT(transaction->names, transaction->length, transaction->new_name);
    resize_reference_vector(transaction->data, transaction->length + 1);
    SET_VECTOR_ELT(transaction->data, transaction->length, transaction->column);
    maybe_inject_column_append_failure(2);
    Rf_setAttrib(transaction->data, R_NamesSymbol, transaction->names);
    maybe_inject_column_append_failure(3);
    return transaction->result;
}

static void cleanup_column_append(void *context, Rboolean jump) {
    column_append_transaction *transaction = context;
    if (!jump || !transaction->started) return;
    /* Remove names before shrinking as well. Restore every original attribute
       in order, including the exact reference-state object. Attribute setters
       may allocate; all saved values remain protected throughout unwinding. */
    if (transaction->reusable && mutation_physical_names(transaction->data) != R_NilValue)
        Rf_setAttrib(transaction->data, R_NamesSymbol,
                     XLENGTH(transaction->data) == transaction->length
                         ? transaction->blank_old : transaction->blank_new);
    for (size_t i = 0; i < transaction->attribute_count; i++)
        Rf_setAttrib(transaction->data, transaction->attributes[i].tag, R_NilValue);
    resize_reference_vector(transaction->data, transaction->length);
    if (transaction->reusable) R_resizeVector(transaction->original_names, transaction->length);
    for (size_t i = 0; i < transaction->attribute_count; i++)
        Rf_setAttrib(transaction->data, transaction->attributes[i].tag,
                     transaction->attributes[i].value);
}

/* Appends the last physical column when outer capacity is sufficient.
   Data tables grow through their own set(). */
SEXP C_dtatools_append_data_column(SEXP data, SEXP name, SEXP column) {
    if (TYPEOF(data) != VECSXP || TYPEOF(name) != STRSXP ||
        XLENGTH(name) != 1 || Rf_inherits(data, "data.table")) {
        Rf_error("invalid column append");
    }
    SEXP current_names = PROTECT(mutation_physical_names(data));
    R_xlen_t length = XLENGTH(data);
    if (TYPEOF(current_names) != STRSXP || XLENGTH(current_names) != length)
        Rf_error("invalid column append names");
    if (!can_resize_reference_columns(data, current_names, length + 1)) {
        UNPROTECT(1);
        return Rf_ScalarLogical(0);
    }
    SEXP new_name = PROTECT(STRING_ELT(name, 0));
    SEXP names = current_names;
    int reusable = !ALTREP(names) && !ANY_ATTRIB(names) && R_isResizable(names) &&
        R_maxLength(names) >= length + 1 && !MAYBE_SHARED(names);
    if (!reusable) {
        names = PROTECT(R_allocResizableVector(STRSXP, R_maxLength(data)));
        R_resizeVector(names, length + 1);
        for (R_xlen_t index = 0; index < length; index++)
            SET_STRING_ELT(names, index, STRING_ELT(current_names, index));
    } else PROTECT(names);
    SEXP blank_old = PROTECT(reusable ? column_append_blank_names(length) : R_NilValue);
    SEXP blank_new = PROTECT(reusable ? column_append_blank_names(length + 1) : R_NilValue);
    SEXP continuation = PROTECT(R_MakeUnwindCont());
    SEXP result = PROTECT(Rf_ScalarLogical(1));
    size_t attribute_count = 0;
    R_mapAttrib(data, count_append_attribute, &attribute_count);
    if (attribute_count > (INT_MAX - 7) / 2) Rf_error("too many column append attributes");
    append_attribute *attributes = (append_attribute *) R_alloc(attribute_count, sizeof(append_attribute));
    /* The iterator balances its own protect stack around each callback.
       Reserve our roots outside it and only REPROTECT inside the callback. */
    for (size_t i = 0; i < attribute_count; i++) {
        PROTECT_WITH_INDEX(R_NilValue, &attributes[i].tag_index);
        PROTECT_WITH_INDEX(R_NilValue, &attributes[i].value_index);
    }
    column_append_transaction transaction = {
        .data = data, .original_names = current_names, .names = names,
        .new_name = new_name, .column = column, .result = result,
        .blank_old = blank_old, .blank_new = blank_new,
        .attributes = attributes, .attribute_count = 0, .attribute_capacity = attribute_count,
        .length = length, .reusable = reusable, .started = 0
    };
    R_mapAttrib(data, save_append_attribute, &transaction);
    /* All operand callbacks and journal allocation precede this final check.
       The public names setter inside the journal still allocates an attr cell. */
    if (XLENGTH(data) != length || mutation_physical_names(data) != current_names ||
        XLENGTH(current_names) != length ||
        !can_resize_reference_columns(data, current_names, length + 1))
        Rf_error("column append target changed while preparing names");
    if (reusable && MAYBE_SHARED(names))
        Rf_error("column append names became shared while preparing names");
    result = R_UnwindProtect(apply_column_append, &transaction,
                            cleanup_column_append, &transaction, continuation);
    UNPROTECT(7 + 2 * (int) attribute_count);
    return result;
}

/* Return whether the physical table can hold the requested complete column
   count without allocation. This query neither repairs nor mutates its input. */
SEXP C_dtatools_can_select_data_columns(SEXP data, SEXP length) {
    if (TYPEOF(data) != VECSXP || XLENGTH(length) != 1) {
        Rf_error("invalid reference column selection capacity query");
    }
    double requested = Rf_asReal(length);
    if (!R_FINITE(requested) || requested < 0 ||
        requested > (double) R_XLEN_T_MAX || requested != floor(requested)) {
        Rf_error("invalid reference column selection capacity query");
    }
    SEXP current_names = mutation_physical_names(data);
    if (TYPEOF(current_names) != STRSXP ||
        XLENGTH(current_names) != XLENGTH(data)) {
        Rf_error("invalid reference column selection names");
    }
    int can_resize = can_resize_reference_columns(
        data, current_names, (R_xlen_t) requested
    );
    return Rf_ScalarLogical(can_resize);
}

/* Stage and commit a complete physical column selection on the supplied table.
   Capacity and all values are validated first. Fresh names and data.table
   self-reference wrappers keep separate outer copies' bookkeeping untouched.
   An empty data.table has zero rows, including its stored row.names; other
   data-frame containers retain their row count when their last column is dropped. */
SEXP C_dtatools_select_data_columns(
    SEXP data, SEXP columns, SEXP names, SEXP state,
    SEXP base_classes, SEXP reference_classes
) {
    if (TYPEOF(data) != VECSXP ||
        TYPEOF(columns) != VECSXP || TYPEOF(names) != STRSXP ||
        XLENGTH(columns) != XLENGTH(names)) {
        Rf_error("invalid reference column selection plan");
    }
    if (state != R_NilValue && TYPEOF(state) != ENVSXP) {
        Rf_error("invalid reference column selection state");
    }
    if (TYPEOF(base_classes) != STRSXP || XLENGTH(base_classes) == 0 ||
        TYPEOF(reference_classes) != STRSXP ||
        XLENGTH(reference_classes) == 0) {
        Rf_error("invalid reference column selection classes");
    }
    SEXP current_names = PROTECT(Rf_getAttrib(data, R_NamesSymbol));
    if (TYPEOF(current_names) != STRSXP ||
        XLENGTH(current_names) != XLENGTH(data)) {
        Rf_error("invalid reference column selection names");
    }
    for (R_xlen_t index = 0; index < XLENGTH(names); index++) {
        SEXP name = STRING_ELT(names, index);
        if (name == NA_STRING || LENGTH(name) == 0) {
            Rf_error("invalid reference column selection name");
        }
    }
    if (Rf_any_duplicated(names, FALSE) != 0) {
        Rf_error("invalid duplicate reference column selection name");
    }
    SEXP planned_names = PROTECT(Rf_duplicate(names));

    R_xlen_t old_length = XLENGTH(data);
    R_xlen_t new_length = XLENGTH(columns);
    int is_data_table = Rf_inherits(data, "data.table");
    int can_resize = can_resize_reference_columns(
        data, current_names, new_length
    );
    if (!can_resize) {
        Rf_error("column selection requires a prepared physical table");
    }
    int keep_state = state != R_NilValue;
    R_xlen_t installed_length = new_length;
    int protect_count = 2;
    SEXP committed_names;
    SEXP committed_selfref = R_NilValue;
    SEXP empty_rows = R_NilValue;
    if (is_data_table && new_length == 0) {
        empty_rows = PROTECT(Rf_allocVector(INTSXP, 0));
        protect_count++;
    }
    SEXP selfref_symbol = Rf_install(".internal.selfref");
    if (is_data_table) {
        /* Never resize or rewrite names another outer table may share.
           data.table's self-reference tag records its names vector and its
           protected external pointer records the table without owning it.
           Preserve that already-validated owner token in a fresh wrapper;
           changing the old wrapper would change the copied table's state. */
        SEXP selfref = Rf_getAttrib(data, selfref_symbol);
        if (!data_table_reference_valid(data)) {
            Rf_error("data.table column selection needs assigned reserve_columns() preparation");
        }
        R_xlen_t capacity = R_isResizable(data) ? R_maxLength(data) : new_length;
        committed_names = PROTECT(R_allocResizableVector(STRSXP, capacity));
        protect_count++;
        R_resizeVector(committed_names, new_length);
        committed_selfref = PROTECT(R_MakeExternalPtr(
            R_ExternalPtrAddr(selfref), committed_names,
            R_ExternalPtrProtected(selfref)
        ));
        protect_count++;
    } else {
        committed_names = PROTECT(Rf_allocVector(STRSXP, new_length));
        protect_count++;
    }
    for (R_xlen_t index = 0; index < installed_length; index++) {
        SET_STRING_ELT(committed_names, index, STRING_ELT(planned_names, index));
    }

    /* Materialize an ALTREP list wrapper before any visible commit. Once this
       succeeds, installing its already validated elements cannot allocate. */
    if (ALTREP(data)) (void) DATAPTR_RO(data);

    /* R-level selection and state construction are complete. The remaining
       writes commit one already validated plan. */
    SEXP reference_state_symbol = Rf_install(".dtatools_ref_state");
    SEXP sorted_symbol = Rf_install("sorted");
    SEXP index_symbol = Rf_install("index");
    Rf_setAttrib(
        data, reference_state_symbol,
        keep_state ? state : R_NilValue
    );
    Rf_setAttrib(
        data, R_ClassSymbol,
        keep_state ? reference_classes : base_classes
    );
    if (is_data_table) {
        Rf_setAttrib(data, sorted_symbol, R_NilValue);
        Rf_setAttrib(data, index_symbol, R_NilValue);
    }

    if (new_length != old_length) {
        resize_reference_vector(data, new_length);
    }
    for (R_xlen_t index = 0; index < installed_length; index++) {
        SET_VECTOR_ELT(data, index, VECTOR_ELT(columns, index));
    }
    if (is_data_table) {
        Rf_setAttrib(data, selfref_symbol, committed_selfref);
        if (new_length == 0) Rf_setAttrib(data, R_RowNamesSymbol, empty_rows);
    }
    Rf_setAttrib(data, R_NamesSymbol, committed_names);
    UNPROTECT(protect_count);
    return data;
}

/* Test-only, one-shot control at the native generation boundary. Consume it
   on entry so validation errors cannot leave a later generation armed. */
static int generation_interrupt_mode = 0;

SEXP C_dtatools_inject_generation_interrupt(SEXP mode) {
    generation_interrupt_mode = 0;
    if (TYPEOF(mode) != INTSXP || XLENGTH(mode) != 1 ||
        INTEGER(mode)[0] < 0 || INTEGER(mode)[0] > 2)
        Rf_error("invalid generation interrupt injection");
    generation_interrupt_mode = INTEGER(mode)[0];
    return R_NilValue;
}

static void interrupt_generated_column(int mode) {
    if (!mode) return;
    if (mode == 1) {
        Rf_onintr();
        Rf_error("generation interrupt handler returned");
    }
    /* POSIX tests send SIGINT only after observing this readiness marker.
       Poll inside the native call while its staged column is still private. */
    Rprintf("[dtatools-test-generation-ready]\n");
    R_FlushConsole();
    clock_t began = clock();
    if (began == (clock_t) -1) Rf_error("generation interrupt clock unavailable");
    for (;;) {
        R_CheckUserInterrupt();
        clock_t now = clock();
        if (now == (clock_t) -1 ||
            (double) (now - began) / CLOCKS_PER_SEC >= 10.0)
            Rf_error("generation interrupt signal was not delivered");
    }
}

static double generated_double_value(
    const numeric_reader *reader, R_xlen_t index, int temporal
) {
    int missing_code;
    double value = numeric_reader_at(reader, index, &missing_code);
    if (missing_code >= 0) {
        if (missing_code == 0) return NA_REAL;
        if (missing_code >= 'a' && missing_code <= 'z') {
            return numeric_missing_value(missing_code - 'a' + 1);
        }
        Rf_error(
            "generated values cannot contain `NaN` or unsupported missing tags"
        );
    }
    double encoded = compact_patch_encoded_value(value, temporal);
    if (!R_FINITE(encoded) || fabs(encoded) > DBL_MAX / 2.0) {
        Rf_error("No Stata double storage can represent the generated value");
    }
    return value;
}

static SEXP generate_double_numeric(
    SEXP values, const reference_rows *rows, size_t row_count,
    const reference_value_plan *value_plan, int temporal
) {
    numeric_reader reader = numeric_reader_create(
        values, value_plan->value_count
    );
    PROTECT(numeric_payload_root(values));
    numeric_data encoding;
    if (reader.storage != NULL) { encoding = *reader.storage; reader.storage = &encoding; }
    SEXP result = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) row_count));
    double *output = REAL(result);
    if (rows->value != R_NilValue) {
        for (size_t index = 0; index < row_count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            output[index] = NA_REAL;
        }
    }

    if (value_plan->mode == REFERENCE_VALUES_SCALAR) {
        double value = generated_double_value(&reader, 0, temporal);
        if (rows->value == R_NilValue) {
            for (size_t index = 0; index < row_count; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                output[index] = value;
            }
        } else {
            for (R_xlen_t index = 0; index < value_plan->count; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                output[reference_patch_row(rows, index)] = value;
            }
        }
    } else {
        for (R_xlen_t index = 0; index < value_plan->count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            R_xlen_t row = rows->value == R_NilValue
                ? index : reference_patch_row(rows, index);
            R_xlen_t value_index = reference_value_index(
                value_plan, index, row
            );
            output[row] = generated_double_value(
                &reader, value_index, temporal
            );
        }
    }
    UNPROTECT(2);
    return result;
}

static void set_generated_attributes(SEXP value, SEXP attributes) {
    if (TYPEOF(attributes) != VECSXP) {
        Rf_error("invalid generated-column attributes");
    }
    SEXP names = Rf_getAttrib(attributes, R_NamesSymbol);
    if (TYPEOF(names) != STRSXP || XLENGTH(names) != XLENGTH(attributes)) {
        Rf_error("invalid generated-column attributes");
    }
    for (R_xlen_t index = 0; index < XLENGTH(attributes); index++) {
        SEXP name = STRING_ELT(names, index);
        if (name == NA_STRING || LENGTH(name) == 0) {
            Rf_error("invalid generated-column attribute name");
        }
        Rf_setAttrib(
            value, Rf_installChar(name), VECTOR_ELT(attributes, index)
        );
    }
}

int string_declared_width(SEXP declared, const char *message) {
    if (declared == R_NilValue) return -1;
    if (TYPEOF(declared) != STRSXP || XLENGTH(declared) != 1 ||
        STRING_ELT(declared, 0) == NA_STRING) {
        Rf_error("%s", message);
    }
    const char *storage = Rf_translateCharUTF8(STRING_ELT(declared, 0));
    if (strcmp(storage, "strL") == 0) return 0;
    if (strncmp(storage, "str", 3) != 0 || storage[3] == '\0') {
        Rf_error("%s", message);
    }
    int width = 0;
    for (const char *digit = storage + 3; *digit != '\0'; digit++) {
        if (*digit < '0' || *digit > '9' || width > 2045) {
            Rf_error("%s", message);
        }
        width = width * 10 + (*digit - '0');
    }
    if (width < 1 || width > 2045) {
        Rf_error("%s", message);
    }
    return width;
}

static int generated_string_declared_width(SEXP declared) {
    return string_declared_width(
        declared,
        "Generated values do not fit their declared Stata string storage"
    );
}

size_t reference_string_width(SEXP value, const char *operation) {
    if (value == NA_STRING) return 0;
    const char *bytes = Rf_translateCharUTF8(value);
    size_t width = strlen(bytes);
    if (width > (size_t) 2000000000) {
        Rf_error(
            "A %s string exceeds Stata's 2,000,000,000-byte limit",
            operation
        );
    }
    return width;
}

static size_t generated_string_width(SEXP value) {
    return reference_string_width(value, "generated");
}

/* Whether every element of a character vector is a non-missing string of
   at most `width` UTF-8 bytes, in one pass that allocates nothing that
   outlives it: the R-level check builds an n-element width vector. A
   `width` of Inf is strL. A `bytes`-encoded element counts its raw
   length when `allow_bytes` is true, as nchar(type = "bytes") does, and
   fails the check otherwise, for a caller about to hand the vector to a
   kernel that must translate it. NULL for a non-character value. */
SEXP C_dtatools_string_fits(SEXP value, SEXP width, SEXP allow_bytes) {
    if (TYPEOF(value) != STRSXP) return R_NilValue;
    double limit = Rf_asReal(width);
    int bytes_ok = Rf_asLogical(allow_bytes) == TRUE;
    R_xlen_t n = XLENGTH(value);
    for (R_xlen_t i = 0; i < n; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        SEXP item = STRING_ELT(value, i);
        if (item == NA_STRING) return Rf_ScalarLogical(0);
        size_t w;
        if (Rf_getCharCE(item) == CE_BYTES) {
            if (!bytes_ok) return Rf_ScalarLogical(0);
            w = (size_t) LENGTH(item);
        } else {
            const void *marker = vmaxget();
            w = strlen(Rf_translateCharUTF8(item));
            vmaxset(marker);
        }
        if ((double) w > limit) return Rf_ScalarLogical(0);
    }
    return Rf_ScalarLogical(1);
}

SEXP C_dtatools_generate_character(
    SEXP values, SEXP rows, SEXP row_count_value,
    SEXP declared, SEXP attributes
) {
    int interrupt_mode = generation_interrupt_mode;
    generation_interrupt_mode = 0;
    if (TYPEOF(values) != STRSXP ||
        (rows != R_NilValue &&
         TYPEOF(rows) != INTSXP && TYPEOF(rows) != REALSXP)) {
        Rf_error("invalid reference string generation plan");
    }
    double row_count_double = Rf_asReal(row_count_value);
    if (!R_FINITE(row_count_double) || row_count_double < 0 ||
        row_count_double != trunc(row_count_double) ||
        row_count_double > (double) R_XLEN_T_MAX) {
        Rf_error("invalid reference generation row count");
    }
    R_xlen_t row_count = (R_xlen_t) row_count_double;
    R_xlen_t count = rows == R_NilValue ? row_count : XLENGTH(rows);
    reference_rows row_plan = reference_rows_create(rows, row_count);
    PROTECT(numeric_payload_root(rows));
    numeric_data row_encoding;
    if (row_plan.real_reader.storage != NULL) {
        row_encoding = *row_plan.real_reader.storage;
        row_plan.real_reader.storage = &row_encoding;
    }
    reference_value_plan value_plan = reference_value_plan_create(
        values, &row_plan, count, row_count, 1,
        "invalid reference string generation plan"
    );
    int declared_width = generated_string_declared_width(declared);
    SEXP reader_cache = PROTECT(
        reference_string_reader_private_cache(
            values,
            value_plan.mode == REFERENCE_VALUES_SCALAR && count > 0
                ? 1 : count
        )
    );
    PROTECT(dictstring_read_root(values));
    reference_string_reader reader = reference_string_reader_create(
        values, reader_cache
    );

    SEXP scalar_value = PROTECT(
        count > 0 && value_plan.mode == REFERENCE_VALUES_SCALAR
            ? reference_string_reader_at(&reader, 0) : R_NilValue
    );
    SEXP result = PROTECT(Rf_allocVector(STRSXP, row_count));
    SEXP empty = PROTECT(Rf_mkChar(""));
    size_t maximum = scalar_value == R_NilValue
        ? 0 : generated_string_width(scalar_value);
    if (rows != R_NilValue &&
        value_plan.mode != REFERENCE_VALUES_SCALAR) {
        int needs_normalization = 0;
        /* R initializes string vectors with blank strings. Visit selected rows
           in reverse so each final, last-write-wins value is decoded once.
           NA_STRING marks a selected blank, distinguishing it from an
           untouched row until the final normalization pass. */
        for (R_xlen_t remaining = count; remaining > 0; remaining--) {
            R_xlen_t index = remaining - 1;
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            R_xlen_t row = reference_patch_row(&row_plan, index);
            if (STRING_ELT(result, row) != empty) continue;
            R_xlen_t value_index = reference_value_index(
                &value_plan, index, row
            );
            SEXP value = reference_string_reader_at(&reader, value_index);
            SEXP normalized = value == NA_STRING ? empty : value;
            if (normalized == empty) needs_normalization = 1;
            SET_STRING_ELT(
                result, row, normalized == empty ? NA_STRING : normalized
            );
            size_t width = generated_string_width(normalized);
            if (width > maximum) maximum = width;
        }
        if (needs_normalization) {
            for (R_xlen_t index = 0; index < row_count; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                if (STRING_ELT(result, index) == NA_STRING) {
                    SET_STRING_ELT(result, index, empty);
                }
            }
        }
    } else {
        for (R_xlen_t index = 0; index < count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            R_xlen_t row = rows == R_NilValue
                ? index : reference_patch_row(&row_plan, index);
            R_xlen_t value_index = reference_value_index(
                &value_plan, index, row
            );
            SEXP value = value_plan.mode == REFERENCE_VALUES_SCALAR
                ? scalar_value
                : reference_string_reader_at(&reader, value_index);
            SEXP normalized = value == NA_STRING ? empty : value;
            SET_STRING_ELT(result, row, normalized);
            if (value_plan.mode != REFERENCE_VALUES_SCALAR) {
                size_t width = generated_string_width(normalized);
                if (width > maximum) maximum = width;
            }
        }
    }
    interrupt_generated_column(interrupt_mode);
    if (declared_width > 0 && maximum > (size_t) declared_width) {
        Rf_error("Generated values do not fit their declared Stata string storage");
    }

    char inferred[16];
    const char *storage;
    if (declared_width == 0) {
        storage = "strL";
    } else if (declared_width > 0) {
        storage = Rf_translateCharUTF8(STRING_ELT(declared, 0));
    } else if (maximum > 2045) {
        storage = "strL";
    } else {
        snprintf(
            inferred, sizeof(inferred), "str%zu",
            maximum > 0 ? maximum : 1
        );
        storage = inferred;
    }
    SEXP storage_value = PROTECT(Rf_mkString(storage));
    set_generated_attributes(result, attributes);
    Rf_setAttrib(
        result, Rf_install("stata.string.storage"), storage_value
    );
    SEXP owned = PROTECT(owned_adopt(result));
    owned_flags(owned)[OWNED_NO_NA] = 1;
    owned_flags(owned)[OWNED_MAX_WIDTH] = (int) maximum;
    owned_flags(owned)[OWNED_WIDTH_EXACT] = 1;
    UNPROTECT(8);
    return owned;
}

SEXP C_dtatools_generate_numeric(
    SEXP values, SEXP rows, SEXP row_count_value,
    SEXP kind_value, SEXP temporal_value, SEXP attributes
) {
    int interrupt_mode = generation_interrupt_mode;
    generation_interrupt_mode = 0;
    if (rows != R_NilValue &&
        TYPEOF(rows) != INTSXP && TYPEOF(rows) != REALSXP) {
        Rf_error("invalid reference generation plan");
    }
    double row_count_double = Rf_asReal(row_count_value);
    if (!R_FINITE(row_count_double) || row_count_double < 0 ||
        row_count_double != trunc(row_count_double) ||
        row_count_double > (double) R_XLEN_T_MAX ||
        row_count_double > (double) SIZE_MAX) {
        Rf_error("invalid reference generation row count");
    }
    size_t row_count = (size_t) row_count_double;
    int kind = Rf_asInteger(kind_value);
    int temporal = Rf_asInteger(temporal_value);
    if (kind < NUMERIC_BYTE || kind > NUMERIC_DOUBLE ||
        temporal < 0 || temporal > 2) {
        Rf_error("invalid reference generation storage");
    }

    R_xlen_t count = rows == R_NilValue
        ? (R_xlen_t) row_count : XLENGTH(rows);
    reference_rows row_plan = reference_rows_create(
        rows, (R_xlen_t) row_count
    );
    PROTECT(numeric_payload_root(rows));
    numeric_data row_encoding;
    if (row_plan.real_reader.storage != NULL) {
        row_encoding = *row_plan.real_reader.storage;
        row_plan.real_reader.storage = &row_encoding;
    }
    reference_value_plan value_plan = reference_value_plan_create(
        values, &row_plan, count, (R_xlen_t) row_count, 1,
        "invalid reference generation plan"
    );

    if (kind == NUMERIC_DOUBLE) {
        SEXP result = PROTECT(generate_double_numeric(
            values, &row_plan, row_count, &value_plan, temporal
        ));
        interrupt_generated_column(interrupt_mode);
        set_generated_attributes(result, attributes);
        SEXP owned = PROTECT(owned_adopt_real(result));
        UNPROTECT(3);
        return owned;
    }

    numeric_data plan = {
        NULL, row_count, kind, temporal, 119, row_count
    };
    PROTECT(numeric_payload_root(values));
    numeric_data value_encoding;
    compact_replacement_plan replacement_plan =
        compact_replacement_plan_create(
            &plan, values, &row_plan, value_plan, 0, &value_encoding
        );

    size_t width = numeric_kind_width(kind);
    if (row_count > SIZE_MAX / width ||
        row_count * width > (size_t) R_XLEN_T_MAX) {
        Rf_error("generated compact Stata numeric vector is too long");
    }
    SEXP backing = PROTECT(Rf_allocVector(
        RAWSXP, (R_xlen_t) (row_count * width)
    ));
    plan.values = RAW(backing);
    if (row_count > 0) {
        /* Seed one encoded system-missing element, then double the
           filled prefix so initialization is memcpy-bound instead of
           one encoder call per row. */
        write_numeric_missing(plan.values, 0, kind, 0);
        unsigned char *bytes = (unsigned char *) plan.values;
        size_t total = row_count * width;
        size_t filled = width;
        while (filled < total) {
            size_t copy = filled <= total - filled
                ? filled : total - filled;
            memcpy(bytes + filled, bytes, copy);
            filled += copy;
        }
    }
    apply_compact_replacement(&plan, &row_plan, &replacement_plan);
    interrupt_generated_column(interrupt_mode);

    SEXP result = PROTECT(numeric_from_backing(
        backing, row_count, kind, temporal, 119, plan.missing_count
    ));
    set_generated_attributes(result, attributes);
    UNPROTECT(4);
    return result;
}

SEXP C_dtatools_is_unmaterialized_numeric_altrep(SEXP value) {
    while (ALTREP(value)) {
        if (R_altrep_inherits(value, dtatools_numeric_class)) {
            return Rf_ScalarLogical(R_altrep_data2(value) == R_NilValue);
        }
        if (!R_altrep_inherits(value, dtatools_metadata_real_class)) break;
        if (R_altrep_data2(value) != R_NilValue) return Rf_ScalarLogical(0);
        value = metadata_proxy_source(value);
    }
    return Rf_ScalarLogical(0);
}

SEXP C_dtatools_is_materialized_numeric_altrep(SEXP value) {
    numeric_data storage;
    return Rf_ScalarLogical(materialized_numeric_storage(value, &storage));
}

SEXP C_dtatools_is_unmaterialized_dictstring(SEXP value) {
    return Rf_ScalarLogical(
        unmaterialized_dictstring_source(value) != R_NilValue
    );
}

SEXP C_dtatools_dictstring_cached_count(SEXP value) {
    SEXP source = unmaterialized_dictstring_source(value);
    if (source == R_NilValue) {
        Rf_error("value is not an unmaterialized dictionary string");
    }
    SEXP cache = dictstring_cache(source);
    R_xlen_t count = 0;
    for (R_xlen_t index = 0; index < XLENGTH(cache); index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        if (VECTOR_ELT(cache, index) != R_NilValue) count++;
    }
    return Rf_ScalarReal((double) count);
}

/* The widest UTF-8 byte length in a dictionary string's dictionary, read
   without materializing the column, so a dibble can declare `str#`
   storage for an Arrow string while it stays compact. */
SEXP C_dtatools_dictstring_max_width(SEXP value) {
    SEXP source = unmaterialized_dictstring_source(value);
    if (source == R_NilValue) {
        Rf_error("value is not an unmaterialized dictionary string");
    }
    dictstring_data *data = dictstring_storage(source);
    SEXP cache = dictstring_cache(source);
    R_xlen_t value_count = XLENGTH(cache);
    size_t maximum = 0;
    for (R_xlen_t id = 0; id < value_count; id++) {
        if ((id & 16383) == 0) R_CheckUserInterrupt();
        const char *bytes = NULL;
        int length = 0;
        if (!dtatools_dictstring_bytes(
                data, (uint32_t) id, &bytes, &length
            ) || bytes == NULL || length < 0) {
            Rf_error("invalid dtatools string-dictionary value");
        }
        if ((size_t) length > maximum) maximum = (size_t) length;
    }
    return Rf_ScalarReal((double) maximum);
}

SEXP C_dtatools_numeric_storage_matches(
    SEXP value, SEXP kind_value, SEXP temporal_value
) {
    if (TYPEOF(kind_value) != INTSXP || XLENGTH(kind_value) != 1 ||
        INTEGER(kind_value)[0] < 0 || INTEGER(kind_value)[0] > 4 ||
        TYPEOF(temporal_value) != INTSXP || XLENGTH(temporal_value) != 1 ||
        INTEGER(temporal_value)[0] < 0 || INTEGER(temporal_value)[0] > 2) {
        Rf_error("invalid compact Stata storage probe");
    }
    numeric_data *storage = unmaterialized_numeric_read_storage(value);
    return Rf_ScalarLogical(
        storage != NULL && storage->kind == INTEGER(kind_value)[0] &&
        storage->temporal == INTEGER(temporal_value)[0]
    );
}

/* Test-only R-backed adapter. Copy first: the source may already have escaped
   through a writable compact consumer. The new raw allocation is immutable. */
SEXP C_dtatools_owned_numeric_freeze(SEXP value, SEXP chunk_rows_value) {
    numeric_data *source = unmaterialized_numeric_read_storage(value);
    double chunk_rows_double = Rf_asReal(chunk_rows_value);
    if (source == NULL || !R_FINITE(chunk_rows_double) || chunk_rows_double < 1 ||
        chunk_rows_double != trunc(chunk_rows_double) || chunk_rows_double > (double) R_XLEN_T_MAX) {
        Rf_error("owned numeric freeze requires compact values and positive chunk rows");
    }
    size_t bytes = source->length * numeric_kind_width(source->kind);
    SEXP backing = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) bytes));
    numeric_copy_region(source, 0, source->length, RAW(backing));
    SEXP external = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, backing));
    R_RegisterCFinalizerEx(external, numeric_finalize, TRUE);
    void *data = dtatools_owned_numeric_from_raw(
        RAW(backing), source->length, (size_t) chunk_rows_double, source->kind,
        source->temporal, source->format_version, source->missing_count
    );
    if (data == NULL) Rf_error("could not freeze compact numeric storage");
    R_SetExternalPtrAddr(external, data);
    SEXP result = PROTECT(R_new_altrep(dtatools_numeric_class, external, R_NilValue));
    SHALLOW_DUPLICATE_ATTRIB(result, value);
    UNPROTECT(3);
    return result;
}

/* Native bytes count retained Buffer capacities, once per allocation within
   each owner. Independent handles do not add a charge. Separate owners may
   share one allocation, so this is charged memory rather than process RSS. */
SEXP C_dtatools_owned_numeric_info(SEXP value) {
    numeric_data *data = unmaterialized_numeric_read_storage(value);
    int retained = data != NULL && numeric_payload_retained(data);
    const char *labels[] = {"owned", "rows", "chunks", "native_bytes", "live_owners", "compatibility_bytes"};
    SEXP result = PROTECT(Rf_allocVector(REALSXP, 6));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 6));
    REAL(result)[0] = retained;
    REAL(result)[1] = data == NULL ? 0 : (double) data->length;
    REAL(result)[2] = retained ? (double) dtatools_owned_numeric_chunks(data) : 0;
    REAL(result)[3] = (double) dtatools_owned_numeric_live_bytes();
    REAL(result)[4] = (double) dtatools_owned_numeric_live_owners();
    REAL(result)[5] = owned_numeric_compatibility_bytes;
    for (int i = 0; i < 6; i++) SET_STRING_ELT(names, i, Rf_mkChar(labels[i]));
    Rf_setAttrib(result, R_NamesSymbol, names);
    UNPROTECT(2);
    return result;
}

SEXP C_dtatools_force_altrep_materialization(SEXP value) {
    if (!ALTREP(value) ||
        !(TYPEOF(value) == REALSXP || TYPEOF(value) == STRSXP)) {
        Rf_error("internal materialization probe requires an ALTREP vector");
    }
    (void) DATAPTR_RO(value);

    return value;
}

SEXP C_dtatools_mutate_first_numeric_altrep(SEXP value, SEXP replacement) {
    if (!ALTREP(value) || TYPEOF(value) != REALSXP || XLENGTH(value) == 0 ||
        TYPEOF(replacement) != REALSXP || XLENGTH(replacement) != 1) {
        Rf_error("internal writable ALTREP probe requires a nonempty numeric ALTREP vector");
    }
    double *data = (double *) DATAPTR_RW(value);

    data[0] = REAL(replacement)[0];
    return value;
}

SEXP C_dtatools_mutate_first_dictstring_altrep(
    SEXP value, SEXP replacement
) {
    if (!ALTREP(value) || TYPEOF(value) != STRSXP || XLENGTH(value) == 0 ||
        TYPEOF(replacement) != STRSXP || XLENGTH(replacement) != 1) {
        Rf_error(
            "internal writable ALTSTRING probe requires a nonempty "
            "string ALTREP vector"
        );
    }
    SET_STRING_ELT(value, 0, STRING_ELT(replacement, 0));
    return value;
}

SEXP C_dtatools_metadata_proxy_depth(SEXP value) {
    int depth = 0;
    while (ALTREP(value)) {
        if (!(R_altrep_inherits(value, dtatools_metadata_real_class) ||
              R_altrep_inherits(value, dtatools_metadata_string_class))) {
            break;
        }
        if (depth == INT_MAX) Rf_error("metadata proxy depth exceeds R limits");
        depth++;
        value = metadata_proxy_source(value);
    }
    return Rf_ScalarInteger(depth);
}

SEXP C_dtatools_metadata_proxy_aggregate_mask(SEXP enabled) {
    if (TYPEOF(enabled) != LGLSXP || XLENGTH(enabled) != 1 ||
        LOGICAL(enabled)[0] == NA_LOGICAL) {
        Rf_error("internal aggregate-mask state must be logical");
    }
    if (LOGICAL(enabled)[0]) {
        metadata_real_aggregate_mask = 0;
        metadata_real_aggregate_mask_enabled = 1;
    } else {
        metadata_real_aggregate_mask_enabled = 0;
    }
    return Rf_ScalarInteger(metadata_real_aggregate_mask);
}

SEXP C_dtatools_has_tagged_na(SEXP value) {
    if (TYPEOF(value) != REALSXP) return Rf_ScalarLogical(0);
    R_xlen_t length = XLENGTH(value);
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        if (is_tagged_na_value(REAL_ELT(value, index))) {
            return Rf_ScalarLogical(1);
        }
    }
    return Rf_ScalarLogical(0);
}

SEXP C_dtatools_tagged_missing(SEXP tag) {
    if (TYPEOF(tag) != STRSXP) {
        Rf_error("`tag` must be a character vector");
    }

    R_xlen_t length = XLENGTH(tag);
    SEXP result = PROTECT(Rf_allocVector(REALSXP, length));
    double *output = REAL(result);
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        int normalized = normalized_dta_missing_tag(
            STRING_ELT(tag, index), "tag"
        );
        output[index] = numeric_missing_value(normalized - 'a' + 1);
    }
    copy_shape_attributes(result, tag);
    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_is_tagged_missing(SEXP value, SEXP tag) {
    if ((TYPEOF(value) != REALSXP && TYPEOF(value) != INTSXP) ||
        Rf_inherits(value, "factor")) {
        Rf_error("`x` must be a numeric vector");
    }

    int match_any = tag == R_NilValue;
    int selected[26] = {0};
    if (!match_any) {
        if (TYPEOF(tag) != STRSXP) {
            Rf_error("`tag` must be a character vector or NULL");
        }
        R_xlen_t tag_count = XLENGTH(tag);
        for (R_xlen_t index = 0; index < tag_count; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            int normalized = normalized_dta_missing_tag(
                STRING_ELT(tag, index), "tag"
            );
            selected[normalized - 'a'] = 1;
        }
    }

    R_xlen_t length = XLENGTH(value);
    SEXP result = PROTECT(Rf_allocVector(LGLSXP, length));
    int *output = LOGICAL(result);
    if (TYPEOF(value) == REALSXP) {
        numeric_data *storage = unmaterialized_numeric_read_storage(value);
        const double *input = storage == NULL
            ? (const double *) DATAPTR_OR_NULL(value) : NULL;
        if (storage != NULL) {
            if ((R_xlen_t) storage->length != length) {
                Rf_error(
                    "dtatools numeric storage length does not match vector length"
                );
            }
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int offset = numeric_missing_offset_at(
                    storage, (size_t) index
                );
                output[index] = offset >= 1 && offset <= 26 &&
                    (match_any || selected[offset - 1]);
            }
        } else if (input != NULL) {
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int actual = dta_missing_tag_value(input[index]);
                output[index] = actual != 0 &&
                    (match_any || selected[actual - 'a']);
            }
        } else {
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int actual = dta_missing_tag_value(REAL_ELT(value, index));
                output[index] = actual != 0 &&
                    (match_any || selected[actual - 'a']);
            }
        }
    } else {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            output[index] = 0;
        }
    }
    copy_shape_attributes(result, value);
    UNPROTECT(1);
    return result;
}

static int is_missing_supported_class(SEXP value) {
    if (!Rf_isObject(value)) return 1;
    if (Rf_inherits(value, "factor")) return 0;

    SEXP classes = Rf_getAttrib(value, R_ClassSymbol);
    int metadata_only = TYPEOF(classes) == STRSXP && XLENGTH(classes) == 1 &&
        strcmp(
            CHAR(STRING_ELT(classes, 0)),
            "dtatools_dta_metadata_vector"
        ) == 0;

    switch (TYPEOF(value)) {
    case LGLSXP:
    case INTSXP:
    case REALSXP:
        return metadata_only ||
            Rf_inherits(value, "dta_numeric") ||
            Rf_inherits(value, "dta_temporal") ||
            Rf_inherits(value, "Date") ||
            Rf_inherits(value, "POSIXct") ||
            Rf_inherits(value, "haven_labelled");
    case STRSXP:
        return metadata_only || Rf_inherits(value, "haven_labelled") ||
            Rf_inherits(value, "dta_string");
    default:
        return 0;
    }
}

static int is_missing_supported_type(SEXP value) {
    int type = TYPEOF(value);
    return type == LGLSXP || type == INTSXP || type == REALSXP ||
        type == STRSXP;
}

static void validate_is_missing_argument(SEXP value, R_xlen_t argument) {
    if (Rf_getAttrib(value, R_DimSymbol) != R_NilValue) {
        Rf_error(
            "Argument %lld to `is_missing()` must be a vector, not a matrix or array",
            (long long) argument
        );
    }
    if (!is_missing_supported_type(value)) {
        Rf_error(
            "Argument %lld to `is_missing()` must be a logical, numeric, or character vector",
            (long long) argument
        );
    }
    if (!is_missing_supported_class(value)) {
        Rf_error(
            "Argument %lld to `is_missing()` has an unsupported class",
            (long long) argument
        );
    }
}

static int numeric_reader_is_missing_at(
    const numeric_reader *reader, R_xlen_t index
) {
    if (reader->storage != NULL) {
        numeric_data *data = reader->storage;
        return numeric_value_is_missing_at(data, (size_t) index);
    }

    if (reader->type == INTSXP || reader->type == LGLSXP) {
        int value = reader->integer_values == NULL
            ? (reader->type == LGLSXP
                ? LOGICAL_ELT(reader->value, index)
                : INTEGER_ELT(reader->value, index))
            : reader->integer_values[index];
        return value == NA_INTEGER;
    }

    double value = reader->real_values == NULL
        ? REAL_ELT(reader->value, index)
        : reader->real_values[index];
    return ISNAN(value);
}

static int is_missing_value_at(
    SEXP value, const numeric_reader *numeric,
    const reference_string_reader *string, R_xlen_t index
) {
    if (TYPEOF(value) == STRSXP) {
        return reference_string_reader_is_missing_at(string, index);
    }
    return numeric_reader_is_missing_at(numeric, index);
}

SEXP C_dtatools_is_missing(SEXP values) {
    if (TYPEOF(values) != VECSXP) {
        Rf_error("internal `is_missing()` arguments must be a list");
    }
    R_xlen_t argument_count = XLENGTH(values);
    if (argument_count == 0) {
        Rf_error("`is_missing()` requires at least one argument");
    }

    R_xlen_t common_size = 1;
    R_xlen_t common_argument = 0;
    for (R_xlen_t argument = 0; argument < argument_count; argument++) {
        SEXP value = VECTOR_ELT(values, argument);
        validate_is_missing_argument(value, argument + 1);
        R_xlen_t size = XLENGTH(value);
        if (size == 1) continue;
        if (common_argument == 0) {
            common_size = size;
            common_argument = argument + 1;
        } else if (size != common_size) {
            Rf_error(
                "Argument %lld to `is_missing()` has size %lld, which is incompatible with argument %lld of size %lld; only size-one recycling is allowed",
                (long long) (argument + 1), (long long) size,
                (long long) common_argument, (long long) common_size
            );
        }
    }

    SEXP result = PROTECT(Rf_allocVector(LGLSXP, common_size));
    int *output = LOGICAL(result);
    memset(output, 0, (size_t) common_size * sizeof(int));
    R_xlen_t unresolved = common_size;

    for (R_xlen_t argument = 0;
         argument < argument_count && unresolved > 0;
         argument++) {
        SEXP value = VECTOR_ELT(values, argument);
        if (XLENGTH(value) != 1) continue;
        R_CheckUserInterrupt();

        numeric_reader reader = {0};
        numeric_reader *reader_pointer = NULL;
        reference_string_reader string_reader = {0};
        reference_string_reader *string_reader_pointer = NULL;
        if (TYPEOF(value) == STRSXP) {
            string_reader = reference_string_reader_create(value, R_NilValue);
            string_reader_pointer = &string_reader;
        } else {
            reader = numeric_reader_create(value, 1);
            reader_pointer = &reader;
        }
        if (!is_missing_value_at(
                value, reader_pointer, string_reader_pointer, 0
            )) continue;

        for (R_xlen_t index = 0; index < common_size; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            output[index] = 1;
        }
        unresolved = 0;
    }

    for (R_xlen_t argument = 0;
         argument < argument_count && unresolved > 0;
         argument++) {
        SEXP value = VECTOR_ELT(values, argument);
        R_xlen_t size = XLENGTH(value);
        if (size <= 1) continue;

        numeric_reader reader = {0};
        numeric_reader *reader_pointer = NULL;
        reference_string_reader string_reader = {0};
        reference_string_reader *string_reader_pointer = NULL;
        if (TYPEOF(value) == STRSXP) {
            string_reader = reference_string_reader_create(value, R_NilValue);
            string_reader_pointer = &string_reader;
        } else {
            reader = numeric_reader_create(value, size);
            reader_pointer = &reader;
        }

        for (R_xlen_t index = 0;
             index < common_size && unresolved > 0;
             index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            if (output[index]) continue;
            int missing = is_missing_value_at(
                value, reader_pointer, string_reader_pointer, index
            );
            output[index] = missing;
            if (missing) unresolved--;
        }
    }

    for (R_xlen_t argument = 0; argument < argument_count; argument++) {
        SEXP value = VECTOR_ELT(values, argument);
        if (XLENGTH(value) != common_size) continue;
        SEXP names = Rf_getAttrib(value, R_NamesSymbol);
        if (names != R_NilValue) {
            Rf_setAttrib(result, R_NamesSymbol, names);
            break;
        }
    }

    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_missing_tag(SEXP value) {
    if ((TYPEOF(value) != REALSXP && TYPEOF(value) != INTSXP) ||
        Rf_inherits(value, "factor")) {
        Rf_error("`x` must be a numeric vector");
    }

    R_xlen_t length = XLENGTH(value);
    SEXP result = PROTECT(Rf_allocVector(STRSXP, length));
    if (TYPEOF(value) == REALSXP) {
        SEXP tag_names = PROTECT(Rf_allocVector(STRSXP, 26));
        for (int index = 0; index < 26; index++) {
            char text = (char) ('a' + index);
            SET_STRING_ELT(tag_names, index, Rf_mkCharLen(&text, 1));
        }

        numeric_data *storage = unmaterialized_numeric_read_storage(value);
        const double *input = storage == NULL
            ? (const double *) DATAPTR_OR_NULL(value) : NULL;
        if (storage != NULL) {
            if ((R_xlen_t) storage->length != length) {
                Rf_error(
                    "dtatools numeric storage length does not match vector length"
                );
            }
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int offset = numeric_missing_offset_at(
                    storage, (size_t) index
                );
                SET_STRING_ELT(
                    result, index,
                    offset >= 1 && offset <= 26
                        ? STRING_ELT(tag_names, offset - 1) : NA_STRING
                );
            }
        } else if (input != NULL) {
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int tag = dta_missing_tag_value(input[index]);
                SET_STRING_ELT(
                    result, index,
                    tag == 0 ? NA_STRING : STRING_ELT(tag_names, tag - 'a')
                );
            }
        } else {
            for (R_xlen_t index = 0; index < length; index++) {
                if ((index & 16383) == 0) R_CheckUserInterrupt();
                int tag = dta_missing_tag_value(REAL_ELT(value, index));
                SET_STRING_ELT(
                    result, index,
                    tag == 0 ? NA_STRING : STRING_ELT(tag_names, tag - 'a')
                );
            }
        }
        UNPROTECT(1);
    } else {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            SET_STRING_ELT(result, index, NA_STRING);
        }
    }
    copy_shape_attributes(result, value);
    UNPROTECT(1);
    return result;
}

static int numeric_compare_operand_create(
    SEXP value, dtatools_compare_operand *operand, size_t *length, SEXP *read_root
) {
    SEXP root = PROTECT(numeric_payload_root(value));
    *read_root = root;
    numeric_data *compact = unmaterialized_numeric_read_storage(root);
    if (compact == NULL) compact = unmaterialized_numeric_read_storage(value);
    if (compact != NULL) {
        operand->values = compact->values;
        operand->native_owner = compact->native_owner;
        operand->kind = compact->kind;
        operand->temporal = compact->temporal;
        operand->format_version = compact->format_version;
        *length = compact->length;
        UNPROTECT(1);
        return 1;
    }
    if (TYPEOF(value) != REALSXP) { UNPROTECT(1); return 0; }
    operand->values = (void *) DATAPTR_RO(value);
    operand->native_owner = NULL;
    operand->kind = NUMERIC_DOUBLE;
    operand->temporal = 0;
    operand->format_version = 0;
    *length = (size_t) XLENGTH(value);
    UNPROTECT(1);
    return 1;
}

static void numeric_scalar_plan(
    SEXP scalar, double *value, int *rank, const char *message
) {
    if (TYPEOF(scalar) != REALSXP || XLENGTH(scalar) != 2) {
        Rf_error("%s", message);
    }
    *value = REAL(scalar)[0];
    double scalar_rank = REAL(scalar)[1];
    if (ISNAN(scalar_rank) || scalar_rank < 0 || scalar_rank > 27 ||
        scalar_rank != trunc(scalar_rank)) {
        Rf_error("%s", message);
    }
    *rank = (int) scalar_rank;
}

typedef struct {
    SEXP target;
    SEXP saved_data1;
    SEXP saved_data2;
    numeric_data *source;
    numeric_data *patched;
    unsigned char *undo;
    size_t undo_bytes;
    size_t saved_missing_count;
    dtatools_compare_operand left;
    dtatools_compare_operand right;
    dtatools_compare_operand replacement;
    int has_right;
    int has_replacement;
    double scalar_value;
    int scalar_rank;
    double replacement_scalar_value;
    int replacement_scalar_rank;
    int op;
    int threads;
    int journal_complete;
} fused_compare_patch_transaction;

/** Detect replacement of either saved ALTREP state component. */
static int fused_compare_patch_state_changed(
    const fused_compare_patch_transaction *transaction
) {
    return R_altrep_data1(transaction->target) != transaction->saved_data1 ||
        R_altrep_data2(transaction->target) != transaction->saved_data2;
}

/**
 * Restore the saved ALTREP state after detachment, or undo bytes and the
 * missing-value count when the transaction patched its original backing.
 */
static void restore_fused_compare_patch(
    fused_compare_patch_transaction *transaction
) {
    if (fused_compare_patch_state_changed(transaction)) {
        R_set_altrep_data1(transaction->target, transaction->saved_data1);
        R_set_altrep_data2(transaction->target, transaction->saved_data2);
        return;
    }
    if (transaction->undo_bytes > 0) {
        memcpy(
            transaction->source->values,
            transaction->undo,
            transaction->undo_bytes
        );
    }
    transaction->source->missing_count = transaction->saved_missing_count;
}

/**
 * Apply a fused numeric patch under its caller's unwind-protected transaction.
 * Return TRUE after a write, FALSE after a successful zero-match operation,
 * or R_NilValue when the fused kernel cannot handle the request. No-match and
 * fallback paths restore the original target; interruption uses the journal.
 */
static SEXP apply_fused_compare_patch(void *data) {
    fused_compare_patch_transaction *transaction =
        (fused_compare_patch_transaction *) data;
    if (transaction->undo_bytes > 0) {
        memcpy(
            transaction->undo,
            transaction->source->values,
            transaction->undo_bytes
        );
        old_journal_bytes += (double) transaction->undo_bytes;
    }
    transaction->journal_complete = 1;
    transaction->patched = detach_compact_patch_target(transaction->target);
    if (transaction->patched == NULL) {
        Rf_error("compact replacement target became unavailable");
    }
    dtatools_patch_target target = {
        transaction->patched->values,
        transaction->patched->kind,
        transaction->patched->temporal,
        transaction->patched->format_version
    };
    size_t matched = 0;
    size_t old_missing = 0;
    size_t new_missing = 0;
    int status = dtatools_numeric_compare_patch(
        transaction->op,
        &transaction->left,
        transaction->has_right ? &transaction->right : NULL,
        transaction->scalar_value,
        transaction->scalar_rank,
        transaction->has_replacement ? &transaction->replacement : NULL,
        transaction->replacement_scalar_value,
        transaction->replacement_scalar_rank,
        &target,
        transaction->patched->length,
        transaction->threads,
        &matched,
        &old_missing,
        &new_missing
    );
    if (!status || matched == 0) {
        restore_fused_compare_patch(transaction);
        transaction->journal_complete = 0;
        return status ? Rf_ScalarLogical(0) : R_NilValue;
    }
    if (old_missing > transaction->saved_missing_count ||
        transaction->saved_missing_count - old_missing > SIZE_MAX - new_missing) {
        Rf_error("invalid fused replacement missing-value count");
    }
    transaction->patched->missing_count =
        transaction->saved_missing_count - old_missing + new_missing;
    maybe_inject_reference_write_interrupt();
    R_CheckUserInterrupt();
    return Rf_ScalarLogical(1);
}

/**
 * Roll back an unwound patch only after its undo journal is complete.
 * Release the undo buffer on both normal return and non-local exit.
 */
static void cleanup_fused_compare_patch(void *data, Rboolean jump) {
    fused_compare_patch_transaction *transaction =
        (fused_compare_patch_transaction *) data;
    if (jump && transaction->journal_complete) {
        restore_fused_compare_patch(transaction);
    }
    free(transaction->undo);
    transaction->undo = NULL;
}

static SEXP fused_compare_patch(
    SEXP target, SEXP op_value, SEXP x, SEXP y, SEXP scalar,
    SEXP replacement, SEXP replacement_scalar, SEXP threads_value,
    SEXP table, R_xlen_t slot, int entry_shared
) {
    numeric_data *target_storage = unmaterialized_numeric_storage(target);
    if (target_storage == NULL) return R_NilValue;
    /* Operand readers can execute foreign ALTREP callbacks. Retain the
       original handle/state, and use copied encoding fields until they finish. */
    numeric_data encoding = *target_storage;
    SEXP original = PROTECT(target);
    SEXP original_data1 = PROTECT(R_altrep_data1(target));
    SEXP original_data2 = PROTECT(R_altrep_data2(target));
    int protect_count = 3;
    int op = Rf_asInteger(op_value);
    if (op < 0 || op > 5) Rf_error("invalid Stata comparison operator");
    int threads = Rf_asInteger(threads_value);
    if (threads == NA_INTEGER || threads < 0) threads = 0;

    dtatools_compare_operand left;
    SEXP left_root;
    size_t length = 0;
    if (!numeric_compare_operand_create(x, &left, &length, &left_root) ||
        length != encoding.length) {
        UNPROTECT(protect_count);
        return R_NilValue;
    }
    PROTECT(left_root);
    protect_count++;
    dtatools_compare_operand right;
    memset(&right, 0, sizeof(right));
    int has_right = y != R_NilValue;
    double scalar_value = 0.0;
    int scalar_rank = 0;
    if (has_right) {
        size_t right_length = 0;
        SEXP right_root;
        if (!numeric_compare_operand_create(y, &right, &right_length, &right_root) ||
            right_length != length) {
            UNPROTECT(protect_count);
            return R_NilValue;
        }
        PROTECT(right_root);
        protect_count++;
    } else {
        numeric_scalar_plan(
            scalar, &scalar_value, &scalar_rank,
            "invalid Stata comparison scalar plan"
        );
    }

    dtatools_compare_operand replacement_operand;
    memset(&replacement_operand, 0, sizeof(replacement_operand));
    int has_replacement = replacement != R_NilValue;
    double replacement_scalar_value = 0.0;
    int replacement_scalar_rank = 0;
    if (has_replacement) {
        size_t replacement_length = 0;
        SEXP replacement_root;
        if (!numeric_compare_operand_create(
                replacement, &replacement_operand, &replacement_length, &replacement_root
            ) || replacement_length != length) {
            UNPROTECT(protect_count);
            return R_NilValue;
        }
        PROTECT(replacement_root);
        protect_count++;
    } else {
        numeric_scalar_plan(
            replacement_scalar,
            &replacement_scalar_value,
            &replacement_scalar_rank,
            "invalid fused replacement scalar plan"
        );
        int missing_code = replacement_scalar_rank == 0
            ? -1 : (replacement_scalar_rank == 1
                ? 0 : 'a' + replacement_scalar_rank - 2);
        validate_compact_patch_value(
            &encoding, replacement_scalar_value, missing_code
        );
    }

    size_t width = numeric_kind_width(encoding.kind);
    if (encoding.length > SIZE_MAX / width) {
        Rf_error("fused replacement target is too large");
    }
    size_t undo_bytes = encoding.length * width;
    SEXP saved_state = PROTECT(Rf_allocVector(VECSXP, 2));
    SEXP continuation = PROTECT(R_MakeUnwindCont());
    protect_count += 2;
    if ((table != R_NilValue && (slot >= XLENGTH(table) || VECTOR_ELT(table, slot) != original)) ||
        R_altrep_data1(original) != original_data1 || R_altrep_data2(original) != original_data2 ||
        unmaterialized_numeric_storage(original) == NULL) {
        Rf_error("reference mutation target changed while preparing replacement");
    }
    int detached = table != R_NilValue && (entry_shared || MAYBE_SHARED(original));
    if (detached) {
        /* A working capture must not mutate the original backing's claim.
           No-match/error paths discard it without revoking a real sibling. */
        target = PROTECT(C_dtatools_deep_copy_value(original));
        protect_count++;
    }
    if ((table != R_NilValue && (slot >= XLENGTH(table) || VECTOR_ELT(table, slot) != original)) ||
        R_altrep_data1(original) != original_data1 || R_altrep_data2(original) != original_data2 ||
        unmaterialized_numeric_storage(original) == NULL) {
        Rf_error("reference mutation target changed while preparing replacement");
    }
    target_storage = unmaterialized_numeric_storage(target);
    SET_VECTOR_ELT(saved_state, 0, R_altrep_data1(target));
    SET_VECTOR_ELT(saved_state, 1, R_altrep_data2(target));
    unsigned char *undo = (unsigned char *) malloc(
        undo_bytes == 0 ? 1 : undo_bytes
    );
    if (undo == NULL) {
        Rf_error("could not allocate fused replacement rollback data");
    }
    native_scratch_allocated += (double) undo_bytes;
    fused_compare_patch_transaction transaction = {
        .target = target,
        .saved_data1 = VECTOR_ELT(saved_state, 0),
        .saved_data2 = VECTOR_ELT(saved_state, 1),
        .source = target_storage,
        .patched = NULL,
        .undo = undo,
        .undo_bytes = undo_bytes,
        .saved_missing_count = target_storage->missing_count,
        .left = left,
        .right = right,
        .replacement = replacement_operand,
        .has_right = has_right,
        .has_replacement = has_replacement,
        .scalar_value = scalar_value,
        .scalar_rank = scalar_rank,
        .replacement_scalar_value = replacement_scalar_value,
        .replacement_scalar_rank = replacement_scalar_rank,
        .op = op,
        .threads = threads,
        .journal_complete = 0
    };
    SEXP result = PROTECT(R_UnwindProtect(
        apply_fused_compare_patch, &transaction,
        cleanup_fused_compare_patch, &transaction,
        continuation
    ));
    protect_count++;
    if (detached && result != R_NilValue && Rf_asLogical(result) == TRUE) {
        commit_identical_slots(table, original, target);
    }
    UNPROTECT(protect_count);
    return result;
}

SEXP C_dtatools_fused_compare_patch(
    SEXP target, SEXP op_value, SEXP x, SEXP y, SEXP scalar,
    SEXP replacement, SEXP replacement_scalar, SEXP threads_value
) {
    return fused_compare_patch(target, op_value, x, y, scalar, replacement,
        replacement_scalar, threads_value, R_NilValue, 0, 0);
}

SEXP C_dtatools_fused_patch_slot(
    SEXP data, SEXP location, SEXP entry_shared, SEXP op, SEXP left,
    SEXP right, SEXP scalar, SEXP replacement, SEXP replacement_scalar, SEXP threads
) {
    R_xlen_t slot = mutation_slot(data, location);
    return fused_compare_patch(VECTOR_ELT(data, slot), op, left, right, scalar,
        replacement, replacement_scalar, threads, data, slot,
        Rf_asLogical(entry_shared) != FALSE);
}

SEXP C_dtatools_dta_compare(
    SEXP op_value, SEXP x, SEXP y, SEXP scalar, SEXP threads_value
) {
    /* Native Stata comparison over compact numeric storage. Returns
       R_NilValue whenever the operands are outside this kernel's domain
       so the caller falls back to the materializing R implementation
       and its error messages. */
    int op = Rf_asInteger(op_value);
    if (op < 0 || op > 5) Rf_error("invalid Stata comparison operator");
    int threads = Rf_asInteger(threads_value);
    if (threads == NA_INTEGER || threads < 0) threads = 0;

    dtatools_compare_operand left, right;
    SEXP left_root;
    size_t length;
    if (!numeric_compare_operand_create(x, &left, &length, &left_root)) return R_NilValue;
    PROTECT(left_root);
    int protected = 1;
    const dtatools_compare_operand *right_pointer = NULL;
    double scalar_value = 0;
    int scalar_rank = 0;
    if (y != R_NilValue) {
        size_t right_length;
        SEXP right_root;
        if (!numeric_compare_operand_create(y, &right, &right_length, &right_root) || right_length != length) {
            UNPROTECT(protected);
            return R_NilValue;
        }
        PROTECT(right_root);
        protected++;
        right_pointer = &right;
    } else numeric_scalar_plan(scalar, &scalar_value, &scalar_rank,
                               "invalid Stata comparison scalar plan");
    if (length > (size_t) R_XLEN_T_MAX) { UNPROTECT(protected); return R_NilValue; }
    SEXP result = PROTECT(Rf_allocVector(LGLSXP, (R_xlen_t) length));
    int status = dtatools_numeric_compare(op, &left, right_pointer, scalar_value,
        scalar_rank, LOGICAL(result), length, threads);
    UNPROTECT(protected + 1);
    return status ? result : R_NilValue;
}

SEXP C_dtatools_missing_codes(SEXP value) {
    /* NA means observed, zero is system missing, 1--255 is the tagged-NA
       payload byte, and 256 is an ordinary R NaN. */
    SEXP payload = PROTECT(owned_real(value) ? owned_values(value) : value);
    R_xlen_t length = XLENGTH(payload);
    SEXP result = PROTECT(Rf_allocVector(INTSXP, length));
    int *output = INTEGER(result);

    if (TYPEOF(value) == REALSXP) {
        const double *values = owned_real(value) ? (const double *) DATAPTR_RO(payload) : NULL;
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            double element = values != NULL ? values[index] : REAL_ELT(value, index);
            int tag = tagged_na_tag_value(element);
            if (tag != 0) {
                output[index] = tag;
            } else if (ISNA(element)) {
                output[index] = 0;
            } else if (ISNAN(element)) {
                output[index] = 256;
            } else {
                output[index] = NA_INTEGER;
            }
        }
    } else if (TYPEOF(value) == INTSXP) {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            output[index] = INTEGER_ELT(value, index) == NA_INTEGER
                ? 0 : NA_INTEGER;
        }
    } else {
        Rf_error("missing-code classification requires a numeric vector");
    }

    UNPROTECT(2);
    return result;
}

SEXP C_dtatools_replace_table_columns(SEXP data, SEXP columns) {
    if (TYPEOF(data) != VECSXP || TYPEOF(columns) != VECSXP) {
        Rf_error("internal column replacement requires lists");
    }
    R_xlen_t count = XLENGTH(data);
    if (XLENGTH(columns) != count) {
        Rf_error("internal column replacement requires matching lists");
    }
    for (R_xlen_t index = 0; index < count; index++) {
        SET_VECTOR_ELT(data, index, VECTOR_ELT(columns, index));
    }
    return R_NilValue;
}

/* Commits one already gathered set of columns back into a table, and into
   the reference-state column store when the table carries an overlay.
   Every column reaches its destination or none does: the plan is fully
   validated and every binding symbol interned before the commit loop,
   which then only rebinds existing bindings and so cannot allocate. */
SEXP C_dtatools_replace_reference_columns(
    SEXP data, SEXP store, SEXP locations, SEXP names, SEXP columns
) {
    if (TYPEOF(data) != VECSXP || TYPEOF(columns) != VECSXP ||
        TYPEOF(locations) != INTSXP || TYPEOF(names) != STRSXP) {
        Rf_error("internal column replacement requires a valid plan");
    }
    R_xlen_t count = XLENGTH(columns);
    if (XLENGTH(locations) != count || XLENGTH(names) != count) {
        Rf_error("internal column replacement requires matching plan lengths");
    }
    if (store != R_NilValue && TYPEOF(store) != ENVSXP) {
        Rf_error("internal column replacement requires a column store");
    }

    /* Validate the whole plan and intern every binding symbol first. The
       commit loop below then only overwrites list elements and rebinds
       bindings the caller has already checked exist, so it cannot
       allocate or fail part way through. */
    SEXP symbols = PROTECT(Rf_allocVector(VECSXP, count));
    for (R_xlen_t index = 0; index < count; index++) {
        int location = INTEGER_ELT(locations, index);
        if (location != NA_INTEGER &&
            (location < 1 || (R_xlen_t) location > XLENGTH(data))) {
            Rf_error("internal column replacement location is out of range");
        }
        SEXP name = STRING_ELT(names, index);
        if (name == NA_STRING) {
            if (location == NA_INTEGER) {
                Rf_error("internal column replacement targets nothing");
            }
            continue;
        }
        if (store == R_NilValue || LENGTH(name) == 0) {
            Rf_error("internal column replacement has no column store");
        }
        SET_VECTOR_ELT(symbols, index, Rf_installChar(name));
    }

    for (R_xlen_t index = 0; index < count; index++) {
        SEXP column = VECTOR_ELT(columns, index);
        int location = INTEGER_ELT(locations, index);
        if (location != NA_INTEGER) {
            SET_VECTOR_ELT(data, (R_xlen_t) location - 1, column);
        }
        SEXP symbol = VECTOR_ELT(symbols, index);
        if (symbol != R_NilValue) Rf_defineVar(symbol, column, store);
    }
    UNPROTECT(1);
    return R_NilValue;
}
