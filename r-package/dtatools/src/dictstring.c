/* Compact dictionary strings: the dictstring_data ALTREP methods, the
   reference string reader shared with mutation, and the compact subset and
   copy paths that keep a dictionary payload private to its result. */
#include "dtatools-internal.h"

void dictstring_finalize(SEXP external) {
    void *data = R_ExternalPtrAddr(external);
    if (data != NULL) {
        R_ClearExternalPtr(external);
        dtatools_dictstring_free(data);
    }
    R_SetExternalPtrProtected(external, R_NilValue);
}

dictstring_data *dictstring_storage(SEXP value) {
    SEXP external = R_altrep_data1(value);
    dictstring_data *data = (dictstring_data *) R_ExternalPtrAddr(external);
    if (data == NULL) Rf_error("dtatools string indices are no longer available");
    return data;
}

SEXP dictstring_cache(SEXP value) {
    SEXP cache = R_ExternalPtrProtected(R_altrep_data1(value));
    if (TYPEOF(cache) != VECSXP) {
        Rf_error("dtatools string cache is no longer available");
    }
    return cache;
}

SEXP unmaterialized_dictstring_source(SEXP value) {
    while (ALTREP(value) &&
           R_altrep_inherits(value, dtatools_metadata_string_class) &&
           R_altrep_data2(value) == R_NilValue) {
        value = metadata_proxy_source(value);
    }
    return ALTREP(value) &&
            R_altrep_inherits(value, dtatools_dictstring_class) &&
            R_altrep_data2(value) == R_NilValue
        ? value : R_NilValue;
}

/* A native reader owns a reference to the immutable Rust descriptor and its
   exact cache. Materialization may release the original external pointer while
   a later callback runs, but cannot free this pinned allocation. A finalizer
   releases the pin on normal return or unwind, without changing sharing flags. */
SEXP dictstring_read_root(SEXP value) {
    SEXP source = unmaterialized_dictstring_source(value);
    if (source == R_NilValue) return R_NilValue;
    SEXP root = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, dictstring_cache(source)));
    R_RegisterCFinalizerEx(root, dictstring_finalize, TRUE);
    void *data = dictstring_storage(source);
    if (!dtatools_dictstring_retain(data)) Rf_error("could not retain dictionary read storage");
    R_SetExternalPtrAddr(root, data);
    UNPROTECT(1);
    return root;
}

static SEXP dictstring_cached_value(
    dictstring_data *data, SEXP cache, uint32_t id
) {
    if ((R_xlen_t) id >= XLENGTH(cache)) {
        Rf_error("invalid dtatools string-dictionary index");
    }
    SEXP cached = VECTOR_ELT(cache, (R_xlen_t) id);
    if (cached != R_NilValue) return cached;

    const char *bytes = NULL;
    int length = 0;
    if (!dtatools_dictstring_bytes(data, id, &bytes, &length) ||
        bytes == NULL || length < 0) {
        Rf_error("invalid dtatools string-dictionary value");
    }
    cached = Rf_mkCharLenCE(bytes, length, CE_UTF8);
    SET_VECTOR_ELT(cache, (R_xlen_t) id, cached);
    return cached;
}


SEXP reference_string_reader_private_cache(
    SEXP values, R_xlen_t read_count
) {
    SEXP source = unmaterialized_dictstring_source(values);
    if (source == R_NilValue) return R_NilValue;
    R_xlen_t cardinality = XLENGTH(dictstring_cache(source));
    return cardinality > 0 && cardinality <= read_count / 4
        ? Rf_allocVector(VECSXP, cardinality) : R_NilValue;
}

reference_string_reader reference_string_reader_create(
    SEXP values, SEXP private_cache
) {
    reference_string_reader reader = {
        .values = values,
        .source = unmaterialized_dictstring_source(values),
        .cache = R_NilValue,
        .private_cache = private_cache,
        .scalar = R_NilValue,
        .data = NULL
    };
    if (reader.source != R_NilValue) {
        reader.cache = dictstring_cache(reader.source);
        reader.data = dictstring_storage(reader.source);
    }
    return reader;
}

SEXP reference_string_reader_at(
    const reference_string_reader *reader, R_xlen_t index
) {
    if (reader->scalar != R_NilValue) return reader->scalar;
    if (reader->source == R_NilValue) {
        return STRING_ELT(reader->values, index);
    }
    if (index < 0 || (size_t) index >= reader->data->length) {
        Rf_error("invalid reference string plan");
    }
    uint32_t id = reader->data->value_ids[index];
    if ((R_xlen_t) id >= XLENGTH(reader->cache)) {
        Rf_error("invalid dtatools string-dictionary index");
    }
    SEXP cached = VECTOR_ELT(reader->cache, (R_xlen_t) id);
    if (cached != R_NilValue) return cached;
    if (reader->private_cache != R_NilValue) {
        cached = VECTOR_ELT(reader->private_cache, (R_xlen_t) id);
        if (cached != R_NilValue) return cached;
    }

    const char *bytes = NULL;
    int length = 0;
    if (!dtatools_dictstring_bytes(reader->data, id, &bytes, &length) ||
        bytes == NULL || length < 0) {
        Rf_error("invalid dtatools string-dictionary value");
    }
    cached = Rf_mkCharLenCE(bytes, length, CE_UTF8);
    if (reader->private_cache != R_NilValue) {
        SET_VECTOR_ELT(reader->private_cache, (R_xlen_t) id, cached);
    }
    return cached;
}

int reference_string_reader_is_missing_at(
    const reference_string_reader *reader, R_xlen_t index
) {
    if (reader->scalar != R_NilValue) {
        return dta_expression_string_is_missing(reader->scalar);
    }
    if (reader->source == R_NilValue) {
        return dta_expression_string_is_missing(
            STRING_ELT(reader->values, index)
        );
    }
    if (index < 0 || (size_t) index >= reader->data->length) {
        Rf_error("invalid reference string plan");
    }
    uint32_t id = reader->data->value_ids[index];
    if ((R_xlen_t) id >= XLENGTH(reader->cache)) {
        Rf_error("invalid dtatools string-dictionary index");
    }

    const char *bytes = NULL;
    int length = 0;
    if (!dtatools_dictstring_bytes(reader->data, id, &bytes, &length) ||
        bytes == NULL || length < 0) {
        Rf_error("invalid dtatools string-dictionary value");
    }
    return length == 0;
}

R_xlen_t dictstring_length(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return XLENGTH(materialized);
    size_t length = dictstring_storage(value)->length;
    if (length > (size_t) R_XLEN_T_MAX) {
        Rf_error("dtatools string vector is too long");
    }
    return (R_xlen_t) length;
}

SEXP dictstring_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return STRING_ELT(materialized, index);
    dictstring_data *data = dictstring_storage(value);
    if (index < 0 || (size_t) index >= data->length) {
        Rf_error("invalid dtatools string-vector index");
    }
    SEXP cache = dictstring_cache(value);
    uint32_t id = data->value_ids[index];
    return dictstring_cached_value(data, cache, id);
}

static SEXP dictstring_materialized_values(SEXP value, SEXP cache) {
    dictstring_data *data = dictstring_storage(value);
    R_xlen_t dictionary_length = XLENGTH(cache);
    for (R_xlen_t id = 0; id < dictionary_length; id++) {
        if ((id & 16383) == 0) R_CheckUserInterrupt();
        (void) dictstring_cached_value(data, cache, (uint32_t) id);
    }
    SEXP materialized = PROTECT(Rf_allocVector(
        STRSXP, (R_xlen_t) data->length
    ));
    for (size_t index = 0; index < data->length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        uint32_t id = data->value_ids[index];
        if ((R_xlen_t) id >= dictionary_length) {
            Rf_error("invalid dtatools string-dictionary index");
        }
        SET_STRING_ELT(
            materialized, (R_xlen_t) index,
            VECTOR_ELT(cache, (R_xlen_t) id)
        );
    }
    UNPROTECT(1);
    return materialized;
}

SEXP dictstring_patch_values(SEXP value, SEXP private_cache) {
    reference_string_reader reader = reference_string_reader_create(
        value, private_cache
    );
    R_xlen_t length = dictstring_length(value);
    SEXP materialized = PROTECT(Rf_allocVector(STRSXP, length));
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        SET_STRING_ELT(
            materialized, index,
            reference_string_reader_at(&reader, index)
        );
    }
    UNPROTECT(1);
    return materialized;
}

static SEXP dictstring_materialize(SEXP value, Rboolean writeable) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) {
        return writeable
            ? detach_shared_materialized_payload(value) : materialized;
    }

    if (compact_payload_is_shared(R_altrep_data1(value))) {
        SEXP detached = PROTECT(dictstring_compact_copy(value));
        R_set_altrep_data1(value, R_altrep_data1(detached));
        UNPROTECT(1);
    }
    SEXP cache = dictstring_cache(value);
    materialized = PROTECT(dictstring_materialized_values(value, cache));
    R_set_altrep_data2(value, materialized);
    dictstring_finalize(R_altrep_data1(value));
    UNPROTECT(1);
    return materialized;
}

SEXP dictstring_materialize_for_patch(SEXP value, SEXP private_cache) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) {
        return detach_shared_materialized_payload(value);
    }
    materialized = PROTECT(dictstring_patch_values(value, private_cache));
    R_set_altrep_data2(value, materialized);
    UNPROTECT(1);
    return materialized;
}

void *dictstring_dataptr(SEXP value, Rboolean writeable) {
    SEXP materialized = dictstring_materialize(value, writeable);
    return DATAPTR_RW(materialized);

}

const void *dictstring_dataptr_or_null(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? NULL : DATAPTR_OR_NULL(materialized);
}

void dictstring_set_elt(SEXP value, R_xlen_t index, SEXP replacement) {
    SET_STRING_ELT(
        dictstring_materialize(value, TRUE), index, replacement
    );
}

int dictstring_no_na(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized == R_NilValue) return 1;
    R_xlen_t length = XLENGTH(materialized);
    for (R_xlen_t index = 0; index < length; index++) {
        if (STRING_ELT(materialized, index) == NA_STRING) return 0;
    }
    return 1;
}

/* R's duplicate of a compact dictionary string that several bindings
   share, as `attr(x, "label") <- ...` on a read column or a fresh subset
   asks for. Without this method R would materialize the copy. */
SEXP dictstring_duplicate(SEXP value, Rboolean deep) {
    (void) deep;
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    return dictstring_compact_copy(value);
}

SEXP dictstring_compact_copy(SEXP value) {
    SEXP source = unmaterialized_dictstring_source(value);
    if (source == R_NilValue) return R_NilValue;
    dictstring_data *source_data = dictstring_storage(source);
    SEXP source_cache = dictstring_cache(source);
    SEXP cache = PROTECT(Rf_allocVector(VECSXP, XLENGTH(source_cache)));
    SEXP external = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, cache));
    R_RegisterCFinalizerEx(external, dictstring_finalize, TRUE);
    void *copy = dtatools_dictstring_clone(source_data);
    if (copy == NULL) {
        Rf_error("could not copy compact dictionary-string storage");
    }
    R_SetExternalPtrAddr(external, copy);
    SEXP result = PROTECT(R_new_altrep(
        dtatools_dictstring_class, external, R_NilValue
    ));
    DUPLICATE_ATTRIB(result, value);
    UNPROTECT(3);
    return result;
}

/* `x[i]` on a compact dictionary string stays compact: the selected value
   ids are gathered over a private copy of the dictionary, so the result
   owns its payload and the source is untouched. An index outside the
   vector would need `NA`, which the dictionary cannot hold, so such a
   subset falls back to R's default and materializes. */
SEXP dictstring_extract_subset(SEXP value, SEXP index, SEXP call) {
    (void) call;
    if (R_altrep_data2(value) != R_NilValue ||
        (TYPEOF(index) != INTSXP && TYPEOF(index) != REALSXP)) {
        return NULL;
    }
    SEXP root = PROTECT(dictstring_read_root(value));
    dictstring_data *data = (dictstring_data *) R_ExternalPtrAddr(root);
    R_xlen_t length = XLENGTH(index);
    if ((size_t) length > SIZE_MAX / sizeof(uint32_t)) {
        Rf_error("compact dictionary-string subset is too long");
    }
    SEXP ids = PROTECT(Rf_allocVector(
        RAWSXP, (R_xlen_t) ((size_t) length * sizeof(uint32_t))
    ));
    uint32_t *output = (uint32_t *) RAW(ids);
    for (R_xlen_t i = 0; i < length; i++) {
        if ((i & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t source = -1;
        if (TYPEOF(index) == INTSXP) {
            int candidate = INTEGER_ELT(index, i);
            if (candidate != NA_INTEGER && candidate > 0 &&
                (size_t) candidate <= data->length) source = candidate - 1;
        } else {
            double candidate = REAL_ELT(index, i);
            if (R_FINITE(candidate) && candidate >= 1 &&
                candidate <= (double) data->length) {
                source = (R_xlen_t) candidate - 1;
            }
        }
        if (source < 0) {
            UNPROTECT(2);
            return NULL;
        }
        output[i] = data->value_ids[source];
    }
    SEXP source_cache = R_ExternalPtrProtected(root);
    R_xlen_t cardinality = XLENGTH(source_cache);
    SEXP cache = PROTECT(Rf_allocVector(VECSXP, cardinality));
    for (R_xlen_t id = 0; id < cardinality; id++) {
        if ((id & 16383) == 0) R_CheckUserInterrupt();
        SET_VECTOR_ELT(cache, id, VECTOR_ELT(source_cache, id));
    }
    SEXP external = PROTECT(R_MakeExternalPtr(NULL, R_NilValue, cache));
    R_RegisterCFinalizerEx(external, dictstring_finalize, TRUE);
    void *gathered = dtatools_dictstring_gather(
        data, output, (size_t) length
    );
    if (gathered == NULL) {
        Rf_error("could not subset compact dictionary-string storage");
    }
    R_SetExternalPtrAddr(external, gathered);
    SEXP result = R_new_altrep(
        dtatools_dictstring_class, external, R_NilValue
    );
    UNPROTECT(4);
    return result;
}

SEXP C_dtatools_dictstring_subset(SEXP value, SEXP index) {
    if (unmaterialized_dictstring_source(value) == R_NilValue) Rf_error("compact dictionary required");
    SEXP result = dictstring_extract_subset(unmaterialized_dictstring_source(value), index, R_NilValue);
    return result == NULL ? R_NilValue : result;
}

SEXP C_dtatools_deep_copy_value(SEXP value) {
    if (owned_column(value)) return owned_capture(value);
    numeric_data *numeric = unmaterialized_numeric_read_storage(value);
    if (numeric != NULL) {
        SEXP result = PROTECT(numeric_handle_copy(numeric_base_source(value)));
        DUPLICATE_ATTRIB(result, value);
        UNPROTECT(1);
        return result;
    }
    SEXP dictionary = dictstring_compact_copy(value);
    if (dictionary != R_NilValue) return dictionary;
    return Rf_duplicate(value);
}
