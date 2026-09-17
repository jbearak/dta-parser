/* File and Arrow I/O: the .Call entry points that read, prepare, write and
   sign datasets, and the marshalling that turns R arguments into the column
   descriptors the Rust side consumes. */
#include "dtatools-internal.h"

const char *optional_encoding(SEXP encoding) {
    if (Rf_isNull(encoding)) return NULL;
    if (TYPEOF(encoding) != STRSXP || XLENGTH(encoding) != 1 ||
        STRING_ELT(encoding, 0) == NA_STRING) {
        Rf_error("`encoding` must be NULL or one non-missing character string");
    }
    return Rf_translateCharUTF8(STRING_ELT(encoding, 0));
}

SEXP C_dtatools_metadata(
    SEXP path, SEXP encoding, SEXP column_start, SEXP column_count,
    SEXP include_value_labels
) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING) {
        Rf_error("`file` must be one non-missing path");
    }
    if (TYPEOF(column_start) != INTSXP || XLENGTH(column_start) != 1 ||
        INTEGER(column_start)[0] < 0 || TYPEOF(column_count) != INTSXP ||
        XLENGTH(column_count) != 1 || INTEGER(column_count)[0] < 0) {
        Rf_error("internal metadata column bounds must be non-negative integers");
    }
    if (TYPEOF(include_value_labels) != LGLSXP ||
        XLENGTH(include_value_labels) != 1 ||
        LOGICAL(include_value_labels)[0] == NA_LOGICAL) {
        Rf_error("internal value-label metadata selector must be logical");
    }
    char *error = NULL;
    SEXP result = dtatools_metadata_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)),
        (uint32_t) INTEGER(column_start)[0],
        (uint32_t) INTEGER(column_count)[0],
        optional_encoding(encoding), LOGICAL(include_value_labels)[0], &error
    );
    if (result == NULL) fail_from_rust(error);
    return result;
}

static void validate_dta_read_arguments(
    SEXP columns, SEXP skip, SEXP n_max, SEXP threads, SEXP numeric_altrep
) {
    int all_columns = Rf_isNull(columns);
    if (!all_columns && TYPEOF(columns) != INTSXP) {
        Rf_error("internal column selection must be integer");
    }
    if (TYPEOF(skip) != REALSXP || XLENGTH(skip) != 1 ||
        TYPEOF(n_max) != REALSXP || XLENGTH(n_max) != 1) {
        Rf_error("internal row bounds must be numeric scalars");
    }
    if (TYPEOF(threads) != INTSXP || XLENGTH(threads) != 1 ||
        INTEGER(threads)[0] < 0) {
        Rf_error("internal thread count must be one non-negative integer");
    }
    if (TYPEOF(numeric_altrep) != LGLSXP || XLENGTH(numeric_altrep) != 1 ||
        LOGICAL(numeric_altrep)[0] == NA_LOGICAL) {
        Rf_error("internal numeric ALTREP selector must be logical");
    }
}

SEXP C_dtatools_read(
    SEXP path, SEXP columns, SEXP skip, SEXP n_max, SEXP threads,
    SEXP numeric_altrep, SEXP encoding
) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING) {
        Rf_error("`file` must be one non-missing path");
    }
    validate_dta_read_arguments(columns, skip, n_max, threads, numeric_altrep);
    int all_columns = Rf_isNull(columns);
    char *error = NULL;
    SEXP result = dtatools_read_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)),
        all_columns ? NULL : INTEGER(columns),
        all_columns ? 0 : (size_t) XLENGTH(columns),
        all_columns,
        REAL(skip)[0],
        REAL(n_max)[0],
        INTEGER(threads)[0],
        LOGICAL(numeric_altrep)[0],
        optional_encoding(encoding),
        &error
    );
    if (result == NULL) fail_from_rust(error);
    return result;
}

static SEXP prepared_dta_tag = NULL;

static void prepared_dta_finalizer(SEXP prepared) {
    void *owner = R_ExternalPtrAddr(prepared);
    if (owner != NULL) {
        R_ClearExternalPtr(prepared);
        dtatools_close_prepared_dta_rust(owner);
    }
}

static void validate_prepared_dta(SEXP prepared) {
    if (TYPEOF(prepared) != EXTPTRSXP || prepared_dta_tag == NULL ||
        R_ExternalPtrTag(prepared) != prepared_dta_tag) {
        Rf_error("invalid prepared DTA read");
    }
}

SEXP C_dtatools_prepare_dta_selection(SEXP path, SEXP encoding) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING) {
        Rf_error("`file` must be one non-missing path");
    }
    if (prepared_dta_tag == NULL) prepared_dta_tag = Rf_install("dtatools_prepared_dta");
    // Allocate and register finalization before transferring a Rust owner.
    // Attaching the returned pointer and metadata below cannot allocate in R.
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 2));
    SEXP prepared = PROTECT(R_MakeExternalPtr(NULL, prepared_dta_tag, R_NilValue));
    R_RegisterCFinalizerEx(prepared, prepared_dta_finalizer, TRUE);
    SET_VECTOR_ELT(result, 0, prepared);
    void *owner = NULL;
    char *error = NULL;
    SEXP metadata = dtatools_prepare_dta_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)), optional_encoding(encoding),
        &owner, &error
    );
    if (metadata == NULL) fail_from_rust(error);
    R_SetExternalPtrAddr(prepared, owner);
    SET_VECTOR_ELT(result, 1, metadata);
    UNPROTECT(2);
    return result;
}

SEXP C_dtatools_read_prepared_dta(
    SEXP prepared, SEXP columns, SEXP skip, SEXP n_max, SEXP threads,
    SEXP numeric_altrep
) {
    validate_prepared_dta(prepared);
    void *owner = R_ExternalPtrAddr(prepared);
    if (owner == NULL) Rf_error("prepared DTA read is closed");
    validate_dta_read_arguments(columns, skip, n_max, threads, numeric_altrep);
    int all_columns = Rf_isNull(columns);
    char *error = NULL;
    SEXP result = dtatools_read_prepared_dta_rust(
        owner, all_columns ? NULL : INTEGER(columns),
        all_columns ? 0 : (size_t) XLENGTH(columns), all_columns,
        REAL(skip)[0], REAL(n_max)[0], INTEGER(threads)[0],
        LOGICAL(numeric_altrep)[0], &error
    );
    if (result == NULL) fail_from_rust(error);
    return result;
}

SEXP C_dtatools_close_prepared_dta(SEXP prepared) {
    validate_prepared_dta(prepared);
    prepared_dta_finalizer(prepared);
    return R_NilValue;
}

static const char *write_scalar_string(SEXP value, const char *name) {
    if (TYPEOF(value) != STRSXP || XLENGTH(value) != 1 ||
        STRING_ELT(value, 0) == NA_STRING) {
        Rf_error("internal `%s` must be one non-missing string", name);
    }
    return Rf_translateCharUTF8(STRING_ELT(value, 0));
}

static SEXP write_utf8_strings(
    SEXP values, const char *name, int allow_missing
) {
    if (TYPEOF(values) != STRSXP) {
        Rf_error("internal `%s` must be character", name);
    }
    R_xlen_t length = XLENGTH(values);
    SEXP normalized = PROTECT(Rf_allocVector(STRSXP, length));
    for (R_xlen_t index = 0; index < length; index++) {
        SEXP element = PROTECT(STRING_ELT(values, index));
        if (element == NA_STRING) {
            if (allow_missing) {
                SET_STRING_ELT(normalized, index, NA_STRING);
                UNPROTECT(1);
                continue;
            }
            UNPROTECT(2);
            Rf_error("internal `%s` contains a missing string", name);
        }
        SEXP utf8 = PROTECT(Rf_mkCharCE(
            Rf_translateCharUTF8(element), CE_UTF8
        ));
        SET_STRING_ELT(normalized, index, utf8);
        UNPROTECT(2);
    }
    UNPROTECT(1);
    return normalized;
}

SEXP C_dtatools_has_bytes_encoding(SEXP values) {
    if (TYPEOF(values) != STRSXP) {
        Rf_error("internal encoding check requires a character vector");
    }
    SEXP source = PROTECT(owned_column(values) ? owned_values(values) : values);
    R_xlen_t length = XLENGTH(source);
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        if (Rf_getCharCE(STRING_ELT(source, index)) == CE_BYTES) {
            UNPROTECT(1);
            return Rf_ScalarLogical(1);
        }
    }
    UNPROTECT(1);
    return Rf_ScalarLogical(0);
}

/* The existing Arrow fallback rejects bytes and calls enc2utf8. Already UTF-8
   owned values need neither a second handle-dispatch scan nor a new payload.
   Inspect actual strings, including exposed backing, without publishing their
   ordinary allocation. Other encodings keep the original R conversion. */
SEXP C_dtatools_owned_utf8_ready(SEXP value) {
    if (TYPEOF(value) != STRSXP || !owned_column(value)) return R_NilValue;
    SEXP payload = PROTECT(owned_values(value));
    R_xlen_t length = XLENGTH(payload);
    const SEXP *strings = STRING_PTR_RO(payload);
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        SEXP item = strings[i];
        if (item == NA_STRING) continue;
        cetype_t encoding = Rf_getCharCE(item);
        if (encoding == CE_BYTES || (encoding != CE_UTF8 && write_string_utf8_status(item) != 1)) {
            UNPROTECT(1);
            return R_NilValue;
        }
    }
    UNPROTECT(1);
    return value;
}

static SEXP write_rooted_strings(
    SEXP roots, R_xlen_t index, SEXP values, const char *name
) {
    SEXP normalized = PROTECT(write_utf8_strings(values, name, 0));
    SET_VECTOR_ELT(roots, index, normalized);
    UNPROTECT(1);
    return normalized;
}

static int is_dta_metadata(SEXP values) {
    return Rf_isNull(values) || TYPEOF(values) == STRSXP;
}

static SEXP write_rooted_dta_metadata(
    SEXP roots, R_xlen_t index, SEXP values, const char *name
) {
    if (Rf_isNull(values)) {
        SET_VECTOR_ELT(roots, index, R_NilValue);
        return R_NilValue;
    }
    return write_rooted_strings(roots, index, values, name);
}

const char *dtatools_string_elt_utf8(SEXP values, size_t index) {
    if (TYPEOF(values) != STRSXP || index >= (size_t) XLENGTH(values) ||
        STRING_ELT(values, (R_xlen_t) index) == NA_STRING) {
        return NULL;
    }
    return CHAR(STRING_ELT(values, (R_xlen_t) index));
}

static SEXP write_rooted_optional_strings(
    SEXP roots, R_xlen_t index, SEXP values, const char *name
) {
    SEXP normalized = PROTECT(write_utf8_strings(values, name, 1));
    SET_VECTOR_ELT(roots, index, normalized);
    UNPROTECT(1);
    return normalized;
}

static const char *write_rooted_scalar_string(
    SEXP roots, R_xlen_t index, SEXP value, const char *name
) {
    if (TYPEOF(value) != STRSXP || XLENGTH(value) != 1) {
        Rf_error("internal `%s` must be one non-missing string", name);
    }
    SEXP normalized = write_rooted_strings(roots, index, value, name);
    return CHAR(STRING_ELT(normalized, 0));
}

static const char *write_rooted_nullable_scalar_string(
    SEXP roots, R_xlen_t index, SEXP value, const char *name
) {
    if (Rf_isNull(value)) {
        SET_VECTOR_ELT(roots, index, R_NilValue);
        return NULL;
    }
    return write_rooted_scalar_string(roots, index, value, name);
}

SEXP C_dtatools_write_path_kind(SEXP path) {
    const char *output_path = write_scalar_string(path, "path");
    char *rust_error = NULL;
    int kind = dtatools_write_path_kind(output_path, &rust_error);
    if (kind < 0) fail_from_rust(rust_error);
    return Rf_ScalarInteger(kind);
}

static int write_column_type(SEXP column) {
    if (TYPEOF(column) != VECSXP || XLENGTH(column) != DTATOOLS_DTA_COLUMN_SLOT_COUNT) {
        Rf_error("internal write column must be a nine-element list");
    }
    SEXP dta_type = VECTOR_ELT(column, DTATOOLS_DTA_COLUMN_TYPE);
    if (TYPEOF(dta_type) != INTSXP || XLENGTH(dta_type) != 1 ||
        INTEGER(dta_type)[0] < 0 || INTEGER(dta_type)[0] > 2050) {
        Rf_error("invalid internal write column metadata");
    }
    return INTEGER(dta_type)[0];
}

SEXP C_dtatools_write(SEXP specification, SEXP path) {
    if (TYPEOF(specification) != VECSXP || XLENGTH(specification) != 5) {
        Rf_error("internal write specification must be a five-element list");
    }
    SEXP dataset_metadata = VECTOR_ELT(specification, 1);
    SEXP columns = VECTOR_ELT(specification, 2);
    SEXP value_label_tables = VECTOR_ELT(specification, 4);
    if (!is_dta_metadata(dataset_metadata) || TYPEOF(columns) != VECSXP ||
        TYPEOF(value_label_tables) != VECSXP) {
        Rf_error("invalid internal write specification");
    }

    size_t column_count = (size_t) XLENGTH(columns);
    size_t table_count = (size_t) XLENGTH(value_label_tables);
    if (column_count > ((size_t) R_XLEN_T_MAX - 4) / 4 ||
        table_count > ((size_t) R_XLEN_T_MAX - 4 - 4 * column_count) / 2) {
        Rf_error("too many internal write columns");
    }
    SEXP string_roots = PROTECT(Rf_allocVector(
        VECSXP, (R_xlen_t) (4 + 4 * column_count + 2 * table_count)
    ));
    SEXP payload_roots = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t) (column_count + table_count)));
    numeric_data *encodings = (numeric_data *) R_alloc((R_SIZE_T) (column_count + table_count), sizeof(numeric_data));
    R_xlen_t root_index = 0;
    const char *output_path = write_rooted_scalar_string(
        string_roots, root_index++, path, "path"
    );
    const char *dataset_label = write_rooted_scalar_string(
        string_roots, root_index++, VECTOR_ELT(specification, 0),
        "dataset label"
    );
    SEXP rooted_dataset_metadata = write_rooted_dta_metadata(
        string_roots, root_index++, dataset_metadata, "dataset Stata metadata"
    );
    const char *timestamp = write_rooted_scalar_string(
        string_roots, root_index++, VECTOR_ELT(specification, 3), "timestamp"
    );

    size_t numeric_column_count = 0;
    for (size_t index = 0; index < column_count; index++) {
        SEXP column = VECTOR_ELT(columns, (R_xlen_t) index);
        if (write_column_type(column) <= 4) numeric_column_count++;
    }

    SEXP numeric_replacements = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t) column_count));
    dtatools_write_column *descriptors = (dtatools_write_column *) R_alloc(
        (R_SIZE_T) column_count, (int) sizeof(dtatools_write_column)
    );
    numeric_reader *value_readers = numeric_column_count == 0 ? NULL :
        (numeric_reader *) R_alloc(
            (R_SIZE_T) numeric_column_count, (int) sizeof(numeric_reader)
        );
    numeric_reader *label_readers = table_count == 0 ? NULL :
        (numeric_reader *) R_alloc(
            (R_SIZE_T) table_count, (int) sizeof(numeric_reader)
        );
    dtatools_write_value_label_table *table_descriptors =
        (dtatools_write_value_label_table *) R_alloc(
            (R_SIZE_T) table_count,
            (int) sizeof(dtatools_write_value_label_table)
        );
    for (size_t index = 0; index < table_count; index++) {
        SEXP table = VECTOR_ELT(value_label_tables, (R_xlen_t) index);
        if (TYPEOF(table) != VECSXP || XLENGTH(table) != 3) {
            Rf_error("internal value-label table must be a three-element list");
        }
        SEXP label_values = VECTOR_ELT(table, 1);
        SEXP label_texts = VECTOR_ELT(table, 2);
        if (TYPEOF(label_texts) != STRSXP ||
            XLENGTH(label_values) != XLENGTH(label_texts)) {
            Rf_error("invalid internal value-label table metadata");
        }
        dtatools_write_value_label_table *descriptor = &table_descriptors[index];
        descriptor->name = write_rooted_scalar_string(
            string_roots, root_index++, VECTOR_ELT(table, 0),
            "value-label table name"
        );
        descriptor->label_texts = write_rooted_strings(
            string_roots, root_index++, label_texts, "value-label text"
        );
        descriptor->label_count = (size_t) XLENGTH(label_values);
        descriptor->label_values = NULL;
        if (descriptor->label_count > 0) {
            numeric_reader *reader = &label_readers[index];
            SEXP root = numeric_payload_root(label_values);
            SET_VECTOR_ELT(payload_roots, (R_xlen_t) index, root);
            *reader = numeric_reader_create(
                unmaterialized_numeric_read_storage(root) != NULL ? root : label_values,
                (R_xlen_t) descriptor->label_count);
            if (reader->storage != NULL) {
                encodings[index] = *reader->storage;
                reader->storage = &encodings[index];
            }
            descriptor->label_values = reader;
        }
    }
    size_t value_reader_index = 0;
    size_t row_count = 0;
    for (size_t index = 0; index < column_count; index++) {
        SEXP column = VECTOR_ELT(columns, (R_xlen_t) index);
        int dta_type = write_column_type(column);
        SEXP values = VECTOR_ELT(column, DTATOOLS_DTA_COLUMN_VALUES);
        SEXP numeric_shift = VECTOR_ELT(column, DTATOOLS_DTA_COLUMN_NUMERIC_SHIFT);
        SEXP numeric_scale = VECTOR_ELT(column, DTATOOLS_DTA_COLUMN_NUMERIC_SCALE);
        SEXP value_label_index = VECTOR_ELT(column, DTATOOLS_DTA_COLUMN_VALUE_LABEL_INDEX);
        SEXP dta_metadata = VECTOR_ELT(column, DTATOOLS_DTA_COLUMN_DTA_METADATA);
        if (!is_dta_metadata(dta_metadata) ||
            TYPEOF(value_label_index) != INTSXP ||
            XLENGTH(value_label_index) != 1 ||
            TYPEOF(numeric_shift) != REALSXP || XLENGTH(numeric_shift) != 1 ||
            TYPEOF(numeric_scale) != REALSXP || XLENGTH(numeric_scale) != 1 ||
            !R_FINITE(REAL(numeric_shift)[0]) ||
            !R_FINITE(REAL(numeric_scale)[0])) {
            Rf_error("invalid internal write column metadata");
        }
        int table_index = INTEGER(value_label_index)[0];
        if (table_index < -1 ||
            (table_index >= 0 && (size_t) table_index >= table_count)) {
            Rf_error("invalid internal value-label table index");
        }
        size_t length = (size_t) XLENGTH(values);
        if (index == 0) row_count = length;
        if (length != row_count) {
            Rf_error("internal write columns have different lengths");
        }

        const char *name = write_rooted_scalar_string(
            string_roots, root_index++, VECTOR_ELT(column, DTATOOLS_DTA_COLUMN_NAME), "name"
        );
        const char *format = write_rooted_scalar_string(
            string_roots, root_index++, VECTOR_ELT(column, DTATOOLS_DTA_COLUMN_FORMAT), "format"
        );
        const char *label = write_rooted_scalar_string(
            string_roots, root_index++, VECTOR_ELT(column, DTATOOLS_DTA_COLUMN_LABEL), "variable label"
        );
        dta_metadata = write_rooted_dta_metadata(
            string_roots, root_index++, dta_metadata, "variable Stata metadata"
        );
        dtatools_write_column *descriptor = &descriptors[index];
        *descriptor = (dtatools_write_column) {
            .name = name,
            .dta_type = dta_type,
            .format = format,
            .label = label,
            .string_values = R_NilValue,
            .dta_metadata = dta_metadata,
            .value_label_index = table_index,
            .numeric_shift = REAL(numeric_shift)[0],
            .numeric_scale = REAL(numeric_scale)[0],
            .direct_numeric_kind = WRITE_NUMERIC_CALLBACK
        };
        if (descriptor->dta_type <= 4) {
            numeric_reader *reader = &value_readers[value_reader_index++];
            SEXP root = numeric_payload_root(values);
            SET_VECTOR_ELT(payload_roots, (R_xlen_t) (table_count + index), root);
            *reader = numeric_reader_create(
                unmaterialized_numeric_read_storage(root) != NULL ? root : values,
                (R_xlen_t) row_count);
            if (reader->storage != NULL) {
                encodings[table_count + index] = *reader->storage;
                reader->storage = &encodings[table_count + index];
            }
            descriptor->numeric_values = reader;
            if (reader->storage != NULL) {
                descriptor->direct_numeric_values = reader->storage->values;
                descriptor->direct_numeric_owner = reader->storage->native_owner;
                descriptor->direct_numeric_kind =
                    WRITE_NUMERIC_BYTE + reader->storage->kind;
                descriptor->direct_numeric_format_version =
                    reader->storage->format_version;
                descriptor->direct_numeric_temporal = reader->storage->temporal;
                descriptor->direct_numeric_no_na =
                    reader->storage->missing_count == 0;
            } else if (reader->integer_values != NULL) {
                descriptor->direct_numeric_values = reader->integer_values;
                descriptor->direct_numeric_kind = WRITE_NUMERIC_INTEGER;
            } else if (reader->real_values != NULL) {
                descriptor->direct_numeric_values = reader->real_values;
                descriptor->direct_numeric_kind = WRITE_NUMERIC_DOUBLE;
            }
        } else {
            if (TYPEOF(values) != STRSXP) {
                Rf_error("internal string write column must be character");
            }
            descriptor->string_values = owned_column(values) ? owned_values(values) : values;
            SET_VECTOR_ELT(payload_roots, (R_xlen_t) (table_count + index), descriptor->string_values);
            SEXP dictionary_source = unmaterialized_dictstring_source(values);
            if (dictionary_source != R_NilValue) {
                SEXP root = PROTECT(dictstring_read_root(dictionary_source));
                SET_VECTOR_ELT(payload_roots, (R_xlen_t) (table_count + index), root);
                descriptor->direct_string_data = R_ExternalPtrAddr(root);
                UNPROTECT(1);
            }
        }
    }

    char *rust_error = NULL;
    int ok = dtatools_write_rust(
        output_path, dataset_label, rooted_dataset_metadata, descriptors,
        column_count, table_descriptors, table_count, REAL(numeric_replacements),
        row_count, timestamp, &rust_error
    );
    if (ok < 0) {
        UNPROTECT(3);
        Rf_onintr();
        Rf_error("write interrupted");
    }
    if (!ok) fail_from_rust(rust_error);
    UNPROTECT(3);
    return numeric_replacements;
}

/* One Arrow write column: a fourteen-element list built by
 * .prepare_arrow_write(): name, kind, values, levels, ordered, label, format,
 * storage, tz, units, haven_labelled, string_storage, value_label_index.
 * The final element is variable Stata metadata. Character data must already
 * be UTF-8; the R layer normalizes
 * with enc2utf8(). */
static void arrow_write_column_descriptor(
    SEXP column, size_t index, size_t row_count, SEXP string_roots,
    R_xlen_t *root_index, size_t table_count,
    dtatools_arrow_column *descriptor
) {
    if (TYPEOF(column) != VECSXP ||
        XLENGTH(column) != DTATOOLS_ARROW_COLUMN_SLOT_COUNT) {
        Rf_error("internal Arrow column must be a fourteen-element list");
    }
    SEXP kind_value = VECTOR_ELT(column, DTATOOLS_ARROW_COLUMN_KIND);
    SEXP values = VECTOR_ELT(column, DTATOOLS_ARROW_COLUMN_VALUES);
    SEXP levels = VECTOR_ELT(column, DTATOOLS_ARROW_COLUMN_LEVELS);
    SEXP ordered = VECTOR_ELT(column, DTATOOLS_ARROW_COLUMN_ORDERED);
    SEXP storage = VECTOR_ELT(column, DTATOOLS_ARROW_COLUMN_STORAGE);
    SEXP haven_labelled = VECTOR_ELT(
        column, DTATOOLS_ARROW_COLUMN_HAVEN_LABELLED
    );
    SEXP string_storage = VECTOR_ELT(
        column, DTATOOLS_ARROW_COLUMN_STRING_STORAGE
    );
    SEXP value_label_index = VECTOR_ELT(
        column, DTATOOLS_ARROW_COLUMN_VALUE_LABEL_INDEX
    );
    SEXP dta_metadata = VECTOR_ELT(
        column, DTATOOLS_ARROW_COLUMN_DTA_METADATA
    );
    if (TYPEOF(kind_value) != INTSXP || XLENGTH(kind_value) != 1 ||
        TYPEOF(ordered) != LGLSXP || XLENGTH(ordered) != 1 ||
        TYPEOF(storage) != INTSXP || XLENGTH(storage) != 1 ||
        !is_dta_metadata(dta_metadata) ||
        TYPEOF(haven_labelled) != LGLSXP || XLENGTH(haven_labelled) != 1 ||
        LOGICAL(haven_labelled)[0] == NA_LOGICAL ||
        TYPEOF(string_storage) != INTSXP || XLENGTH(string_storage) != 1 ||
        TYPEOF(value_label_index) != INTSXP ||
        XLENGTH(value_label_index) != 1) {
        Rf_error("invalid internal Arrow column metadata");
    }
    int table_index = INTEGER(value_label_index)[0];
    if (table_index < -1 ||
        (table_index >= 0 && (size_t) table_index >= table_count)) {
        Rf_error("invalid internal Arrow value-label table index");
    }
    if ((size_t) XLENGTH(values) != row_count) {
        Rf_error("internal Arrow columns have different lengths");
    }

    memset(descriptor, 0, sizeof(*descriptor));
    descriptor->kind = INTEGER(kind_value)[0];
    descriptor->storage = INTEGER(storage)[0];
    descriptor->string_storage = INTEGER(string_storage)[0];
    descriptor->ordered = LOGICAL(ordered)[0] == 1;
    descriptor->strings = R_NilValue;
    descriptor->name = write_rooted_scalar_string(
        string_roots, (*root_index)++,
        VECTOR_ELT(column, DTATOOLS_ARROW_COLUMN_NAME), "name"
    );
    descriptor->label = write_rooted_scalar_string(
        string_roots, (*root_index)++,
        VECTOR_ELT(column, DTATOOLS_ARROW_COLUMN_LABEL), "variable label"
    );
    descriptor->format = write_rooted_scalar_string(
        string_roots, (*root_index)++,
        VECTOR_ELT(column, DTATOOLS_ARROW_COLUMN_FORMAT), "format"
    );
    descriptor->tz = write_rooted_nullable_scalar_string(
        string_roots, (*root_index)++,
        VECTOR_ELT(column, DTATOOLS_ARROW_COLUMN_TIME_ZONE), "time zone"
    );
    descriptor->units = write_rooted_scalar_string(
        string_roots, (*root_index)++,
        VECTOR_ELT(column, DTATOOLS_ARROW_COLUMN_UNITS), "units"
    );
    descriptor->value_label_index = table_index;
    descriptor->dta_metadata = write_rooted_dta_metadata(
        string_roots, (*root_index)++, dta_metadata, "variable Stata metadata"
    );
    descriptor->haven_labelled = LOGICAL(haven_labelled)[0];

    /* Later column metadata and foreign readers may detach this handle. */
    SEXP dictionary_root = PROTECT(dictstring_read_root(values));
    SET_VECTOR_ELT(string_roots, (*root_index)++, dictionary_root != R_NilValue ?
                   dictionary_root : numeric_payload_root(values));
    UNPROTECT(1);
    switch (descriptor->kind) {
    case 0: /* logical */
        if (TYPEOF(values) != LGLSXP) {
            Rf_error("internal Arrow logical column has the wrong type");
        }
        descriptor->values = DATAPTR_RO(values);
        break;
    case 1: /* integer */
    case 10: /* labelled integer written as Float64 */
        if (TYPEOF(values) != INTSXP) {
            Rf_error("internal Arrow integer column has the wrong type");
        }
        descriptor->values = DATAPTR_RO(values);
        break;
    case 2: /* double */
    case 6: /* date */
    case 7: /* datetime */
    case 8: /* difftime */
        if (TYPEOF(values) != REALSXP) {
            Rf_error("internal Arrow double column has the wrong type");
        }
        descriptor->values = DATAPTR_RO(values);
        break;
    case 3: { /* character */
        if (TYPEOF(values) != STRSXP) {
            Rf_error("internal Arrow character column has the wrong type");
        }
        descriptor->strings = owned_column(values) ? owned_values(values) : values;
        descriptor->string_count = row_count;
        SEXP dictionary_source = unmaterialized_dictstring_source(values);
        if (dictionary_source != R_NilValue) {
            descriptor->dictstring = R_ExternalPtrAddr(dictionary_root);
        }
        break;
    }
    case 4: /* raw */
        if (TYPEOF(values) != RAWSXP) {
            Rf_error("internal Arrow raw column has the wrong type");
        }
        descriptor->values = RAW(values);
        break;
    case 5: /* factor */
        if (TYPEOF(values) != INTSXP || TYPEOF(levels) != STRSXP) {
            Rf_error("internal Arrow factor column has the wrong type");
        }
        descriptor->values = DATAPTR_RO(values);
        descriptor->strings = write_rooted_optional_strings(
            string_roots, (*root_index)++, levels, "factor levels"
        );
        descriptor->string_count = (size_t) XLENGTH(levels);
        break;
    case 9: { /* profiled Stata numeric */
        numeric_data *compact = unmaterialized_numeric_read_storage(values);
        if (compact != NULL) {
            descriptor->compact_values = compact->values;
            descriptor->compact_owner = compact->native_owner;
            descriptor->compact_kind = compact->kind;
            descriptor->compact_format_version = compact->format_version;
            descriptor->compact_temporal = compact->temporal;
        } else {
            if (TYPEOF(values) != REALSXP) {
                Rf_error("internal Arrow Stata column has the wrong type");
            }
            descriptor->values = DATAPTR_RO(values);
        }
        break;
    }
    default:
        Rf_error("invalid internal Arrow column kind");
    }
    (void) index;
}

typedef struct {
    const char *dataset_label;
    const char *output_container;
    SEXP dataset_metadata;
    dtatools_arrow_column *columns;
    size_t column_count;
    dtatools_arrow_value_label_table *value_label_tables;
    size_t value_label_table_count;
    size_t row_count;
} arrow_write_specification;

static void arrow_write_specification_sizes(
    SEXP specification, size_t *column_count, size_t *table_count
) {
    if (TYPEOF(specification) != VECSXP ||
        XLENGTH(specification) != DTATOOLS_ARROW_SPECIFICATION_SLOT_COUNT) {
        Rf_error("internal Arrow specification must be a five-element list");
    }
    SEXP dataset_metadata = VECTOR_ELT(
        specification, DTATOOLS_ARROW_SPECIFICATION_DTA_METADATA
    );
    SEXP columns = VECTOR_ELT(
        specification, DTATOOLS_ARROW_SPECIFICATION_COLUMNS
    );
    SEXP tables = VECTOR_ELT(
        specification, DTATOOLS_ARROW_SPECIFICATION_VALUE_LABEL_TABLES
    );
    if (!is_dta_metadata(dataset_metadata) || TYPEOF(columns) != VECSXP ||
        TYPEOF(tables) != VECSXP) {
        Rf_error("invalid internal Arrow specification");
    }
    *column_count = (size_t) XLENGTH(columns);
    *table_count = (size_t) XLENGTH(tables);
}

static arrow_write_specification prepare_arrow_write_specification(
    SEXP specification, SEXP string_roots, R_xlen_t *root_index
) {
    size_t column_count = 0;
    size_t table_count = 0;
    arrow_write_specification_sizes(
        specification, &column_count, &table_count
    );
    SEXP dataset_metadata = VECTOR_ELT(
        specification, DTATOOLS_ARROW_SPECIFICATION_DTA_METADATA
    );
    SEXP columns = VECTOR_ELT(
        specification, DTATOOLS_ARROW_SPECIFICATION_COLUMNS
    );
    SEXP tables = VECTOR_ELT(
        specification, DTATOOLS_ARROW_SPECIFICATION_VALUE_LABEL_TABLES
    );
    arrow_write_specification result = {
        .dataset_label = write_rooted_scalar_string(
            string_roots, (*root_index)++,
            VECTOR_ELT(
                specification, DTATOOLS_ARROW_SPECIFICATION_DATASET_LABEL
            ),
            "dataset label"
        ),
        .dataset_metadata = write_rooted_dta_metadata(
            string_roots, (*root_index)++, dataset_metadata,
            "dataset Stata metadata"
        ),
        .output_container = write_rooted_nullable_scalar_string(
            string_roots, (*root_index)++,
            VECTOR_ELT(
                specification, DTATOOLS_ARROW_SPECIFICATION_OUTPUT_CONTAINER
            ),
            "output container"
        ),
        .column_count = column_count,
        .value_label_table_count = table_count,
        .row_count = 0
    };
    if (column_count > 0) {
        SEXP first = VECTOR_ELT(columns, 0);
        if (TYPEOF(first) != VECSXP ||
            XLENGTH(first) != DTATOOLS_ARROW_COLUMN_SLOT_COUNT) {
            Rf_error("internal Arrow column must be a fourteen-element list");
        }
        result.row_count = (size_t) XLENGTH(VECTOR_ELT(
            first, DTATOOLS_ARROW_COLUMN_VALUES
        ));
    }
    result.value_label_tables =
        (dtatools_arrow_value_label_table *) R_alloc(
            (R_SIZE_T) table_count,
            (int) sizeof(dtatools_arrow_value_label_table)
        );
    for (size_t index = 0; index < table_count; index++) {
        SEXP table = VECTOR_ELT(tables, (R_xlen_t) index);
        if (TYPEOF(table) != VECSXP ||
            XLENGTH(table) != DTATOOLS_ARROW_VALUE_LABEL_TABLE_SLOT_COUNT) {
            Rf_error("internal Arrow value-label table must be a three-element list");
        }
        SEXP label_values = VECTOR_ELT(
            table, DTATOOLS_ARROW_VALUE_LABEL_TABLE_VALUES
        );
        SEXP label_texts = VECTOR_ELT(
            table, DTATOOLS_ARROW_VALUE_LABEL_TABLE_TEXTS
        );
        if (TYPEOF(label_values) != REALSXP || TYPEOF(label_texts) != STRSXP ||
            XLENGTH(label_values) != XLENGTH(label_texts)) {
            Rf_error("invalid internal Arrow value-label table metadata");
        }
        dtatools_arrow_value_label_table *descriptor =
            &result.value_label_tables[index];
        descriptor->name = write_rooted_scalar_string(
            string_roots, (*root_index)++,
            VECTOR_ELT(table, DTATOOLS_ARROW_VALUE_LABEL_TABLE_NAME),
            "value-label table name"
        );
        descriptor->label_texts = write_rooted_strings(
            string_roots, (*root_index)++, label_texts, "value-label text"
        );
        descriptor->label_count = (size_t) XLENGTH(label_values);
        SET_VECTOR_ELT(string_roots, (*root_index)++, numeric_payload_root(label_values));
        descriptor->label_values = descriptor->label_count > 0
            ? (const double *) DATAPTR_RO(label_values) : NULL;
    }
    result.columns = (dtatools_arrow_column *) R_alloc(
        (R_SIZE_T) column_count, (int) sizeof(dtatools_arrow_column)
    );
    for (size_t index = 0; index < column_count; index++) {
        arrow_write_column_descriptor(
            VECTOR_ELT(columns, (R_xlen_t) index), index, result.row_count,
            string_roots, root_index, table_count, &result.columns[index]
        );
    }
    return result;
}

SEXP C_dtatools_save_arrow(
    SEXP specification, SEXP path, SEXP compression, SEXP threads,
    SEXP checksums
) {
    if (TYPEOF(threads) != INTSXP || XLENGTH(threads) != 1 ||
        INTEGER(threads)[0] < 0) {
        Rf_error("internal thread count must be one non-negative integer");
    }
    if (TYPEOF(checksums) != LGLSXP || XLENGTH(checksums) != 1 ||
        LOGICAL(checksums)[0] == NA_LOGICAL) {
        Rf_error("internal checksums flag must be TRUE or FALSE");
    }
    size_t column_count = 0;
    size_t table_count = 0;
    arrow_write_specification_sizes(
        specification, &column_count, &table_count
    );
    if (column_count > ((size_t) R_XLEN_T_MAX - 5) / 8 ||
        table_count > ((size_t) R_XLEN_T_MAX - 5 - 8 * column_count) / 3) {
        Rf_error("too many internal Arrow columns");
    }
    SEXP string_roots = PROTECT(Rf_allocVector(
        VECSXP, (R_xlen_t) (5 + 8 * column_count + 3 * table_count)
    ));
    R_xlen_t root_index = 0;
    const char *output_path = write_rooted_scalar_string(
        string_roots, root_index++, path, "path"
    );
    const char *compression_label = write_rooted_scalar_string(
        string_roots, root_index++, compression, "compression"
    );
    arrow_write_specification prepared = prepare_arrow_write_specification(
        specification, string_roots, &root_index
    );

    int interrupted = 0;
    char *rust_error = NULL;
    SEXP result = dtatools_save_arrow_rust(
        output_path, prepared.dataset_label, prepared.output_container,
        prepared.dataset_metadata,
        prepared.columns, prepared.column_count,
        prepared.value_label_tables, prepared.value_label_table_count,
        prepared.row_count,
        compression_label, INTEGER(threads)[0], LOGICAL(checksums)[0],
        &interrupted,
        &rust_error
    );
    if (result == NULL) {
        UNPROTECT(1);
        if (interrupted) {
            Rf_onintr();
            Rf_error("Arrow write interrupted");
        }
        fail_from_rust(rust_error);
    }
    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_datasig(SEXP specification, SEXP threads) {
    if (TYPEOF(threads) != INTSXP || XLENGTH(threads) != 1 ||
        INTEGER(threads)[0] < 0) {
        Rf_error("internal thread count must be one non-negative integer");
    }
    size_t column_count = 0;
    size_t table_count = 0;
    arrow_write_specification_sizes(
        specification, &column_count, &table_count
    );
    if (column_count > ((size_t) R_XLEN_T_MAX - 3) / 8 ||
        table_count > ((size_t) R_XLEN_T_MAX - 3 - 8 * column_count) / 3) {
        Rf_error("too many internal Arrow columns");
    }
    SEXP string_roots = PROTECT(Rf_allocVector(
        VECSXP, (R_xlen_t) (3 + 8 * column_count + 3 * table_count)
    ));
    R_xlen_t root_index = 0;
    arrow_write_specification prepared = prepare_arrow_write_specification(
        specification, string_roots, &root_index
    );

    int interrupted = 0;
    char *rust_error = NULL;
    SEXP result = dtatools_datasig_rust(
        prepared.dataset_label, prepared.dataset_metadata,
        prepared.columns, prepared.column_count, prepared.value_label_tables,
        prepared.value_label_table_count, prepared.row_count, INTEGER(threads)[0],
        &interrupted,
        &rust_error
    );
    if (result == NULL) {
        UNPROTECT(1);
        if (interrupted) {
            Rf_onintr();
            Rf_error("Arrow signature interrupted");
        }
        fail_from_rust(rust_error);
    }
    UNPROTECT(1);
    return result;
}

static SEXP dtatools_arrow_snapshot_tag = NULL;

static void arrow_snapshot_finalize(SEXP external) {
    void *snapshot = R_ExternalPtrAddr(external);
    if (snapshot != NULL) {
        dtatools_close_arrow_rust(snapshot);
        R_ClearExternalPtr(external);
    }
}

static void *arrow_snapshot_pointer(SEXP external) {
    if (TYPEOF(external) != EXTPTRSXP ||
        dtatools_arrow_snapshot_tag == NULL ||
        R_ExternalPtrTag(external) != dtatools_arrow_snapshot_tag) {
        Rf_error("internal Arrow file snapshot is invalid");
    }
    void *snapshot = R_ExternalPtrAddr(external);
    if (snapshot == NULL) {
        Rf_error("internal Arrow file snapshot is closed");
    }
    return snapshot;
}

SEXP C_dtatools_open_arrow(SEXP path) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 ||
        STRING_ELT(path, 0) == NA_STRING) {
        Rf_error("`file` must be one non-missing path");
    }
    char *rust_error = NULL;
    void *snapshot = dtatools_open_arrow_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)), &rust_error
    );
    if (snapshot == NULL) fail_from_rust(rust_error);
    if (dtatools_arrow_snapshot_tag == NULL) {
        dtatools_arrow_snapshot_tag = Rf_install("dtatools_arrow_snapshot");
    }
    SEXP external = PROTECT(R_MakeExternalPtr(
        snapshot, dtatools_arrow_snapshot_tag, R_NilValue
    ));
    R_RegisterCFinalizerEx(external, arrow_snapshot_finalize, TRUE);
    UNPROTECT(1);
    return external;
}

SEXP C_dtatools_close_arrow(SEXP snapshot) {
    (void) arrow_snapshot_pointer(snapshot);
    arrow_snapshot_finalize(snapshot);
    return R_NilValue;
}

SEXP C_dtatools_read_arrow(
    SEXP snapshot, SEXP columns, SEXP skip, SEXP n_max, SEXP verify, SEXP profile,
    SEXP numeric_altrep, SEXP threads, SEXP datasig, SEXP count_source_rows
) {
    void *snapshot_pointer = arrow_snapshot_pointer(snapshot);
    int all_columns = Rf_isNull(columns);
    if (!all_columns && TYPEOF(columns) != INTSXP) {
        Rf_error("internal column selection must be integer");
    }
    if (TYPEOF(skip) != REALSXP || XLENGTH(skip) != 1 ||
        TYPEOF(n_max) != REALSXP || XLENGTH(n_max) != 1) {
        Rf_error("internal row bounds must be numeric scalars");
    }
    if (TYPEOF(verify) != LGLSXP || XLENGTH(verify) != 1 ||
        LOGICAL(verify)[0] == NA_LOGICAL ||
        TYPEOF(profile) != LGLSXP || XLENGTH(profile) != 1 ||
        LOGICAL(profile)[0] == NA_LOGICAL) {
        Rf_error("internal Arrow read flags must be logical");
    }
    if (TYPEOF(numeric_altrep) != LGLSXP || XLENGTH(numeric_altrep) != 1 ||
        LOGICAL(numeric_altrep)[0] == NA_LOGICAL) {
        Rf_error("internal numeric ALTREP selector must be logical");
    }
    if (TYPEOF(datasig) != LGLSXP || XLENGTH(datasig) != 1 ||
        LOGICAL(datasig)[0] == NA_LOGICAL) {
        Rf_error("internal data signature selector must be logical");
    }
    if (TYPEOF(count_source_rows) != LGLSXP ||
        XLENGTH(count_source_rows) != 1 ||
        LOGICAL(count_source_rows)[0] == NA_LOGICAL) {
        Rf_error("internal source-row selector must be logical");
    }
    if (TYPEOF(threads) != INTSXP || XLENGTH(threads) != 1 ||
        INTEGER(threads)[0] < 0) {
        Rf_error("internal thread count must be one non-negative integer");
    }
    int interrupted = 0;
    char *rust_error = NULL;
    SEXP result = dtatools_read_arrow_rust(
        snapshot_pointer,
        all_columns ? NULL : INTEGER(columns),
        all_columns ? 0 : (size_t) XLENGTH(columns),
        all_columns,
        REAL(skip)[0],
        REAL(n_max)[0],
        LOGICAL(verify)[0],
        LOGICAL(profile)[0],
        LOGICAL(numeric_altrep)[0],
        INTEGER(threads)[0],
        LOGICAL(datasig)[0],
        LOGICAL(count_source_rows)[0],
        &interrupted,
        &rust_error
    );
    if (result == NULL) {
        if (interrupted) {
            Rf_onintr();
            Rf_error("Arrow read interrupted");
        }
        fail_from_rust(rust_error);
    }
    return result;
}

SEXP C_dtatools_arrow_metadata(
    SEXP snapshot, SEXP profile, SEXP scan_ambiguous_int32,
    SEXP skip, SEXP n_max
) {
    void *snapshot_pointer = arrow_snapshot_pointer(snapshot);
    if (TYPEOF(profile) != LGLSXP || XLENGTH(profile) != 1 ||
        LOGICAL(profile)[0] == NA_LOGICAL ||
        TYPEOF(scan_ambiguous_int32) != LGLSXP ||
        XLENGTH(scan_ambiguous_int32) != 1 ||
        LOGICAL(scan_ambiguous_int32)[0] == NA_LOGICAL) {
        Rf_error("internal Arrow metadata selectors must be logical");
    }
    if (TYPEOF(skip) != REALSXP || XLENGTH(skip) != 1 ||
        TYPEOF(n_max) != REALSXP || XLENGTH(n_max) != 1) {
        Rf_error("internal Arrow metadata row bounds must be numeric scalars");
    }
    int interrupted = 0;
    char *rust_error = NULL;
    SEXP result = dtatools_arrow_metadata_rust(
        snapshot_pointer, LOGICAL(profile)[0],
        LOGICAL(scan_ambiguous_int32)[0],
        REAL(skip)[0], REAL(n_max)[0],
        &interrupted, &rust_error
    );
    if (result == NULL) {
        if (interrupted) {
            Rf_onintr();
            Rf_error("Arrow read interrupted");
        }
        fail_from_rust(rust_error);
    }
    return result;
}

SEXP C_dtatools_arrow_datasig(SEXP path) {
    if (TYPEOF(path) != STRSXP || XLENGTH(path) != 1 ||
        STRING_ELT(path, 0) == NA_STRING) {
        Rf_error("`file` must be one non-missing path");
    }
    char *error = NULL;
    SEXP result = dtatools_arrow_datasig_rust(
        Rf_translateCharUTF8(STRING_ELT(path, 0)), &error
    );
    if (result == NULL) fail_from_rust(error);
    return result;
}
