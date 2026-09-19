/* Metadata proxies and mutation views: the ALTREP handles that let R hold a
   column without owning its payload, the private views mutation preflight
   reads through, and the shape and name lookups those views answer. */
#include "dtatools-internal.h"

/* Internal ordinary-string reads use a separate temporary handle so R
   preflight frames cannot retain the physical target. Release severs its one
   source reference after evaluation. Public exposure must copy or retain the
   original physical handle, never publish this temporary view. */
static int mutation_string_view(SEXP value) {
    return ALTREP(value) && R_altrep_inherits(value, dtatools_mutation_string_class);
}

static SEXP mutation_string_source(SEXP value) {
    SEXP source = R_altrep_data2(value) == R_NilValue
        ? R_altrep_data1(value) : R_altrep_data2(value);
    if (source == R_NilValue) Rf_error("an internal mutation string view was released");
    return source;
}

R_xlen_t mutation_string_length(SEXP value) { return XLENGTH(mutation_string_source(value)); }
SEXP mutation_string_elt(SEXP value, R_xlen_t i) { return STRING_ELT(mutation_string_source(value), i); }
SEXP mutation_string_duplicate(SEXP value, Rboolean deep) {
    (void) deep;
    SEXP result = PROTECT(Rf_shallow_duplicate(mutation_string_source(value)));
    SHALLOW_DUPLICATE_ATTRIB(result, value);
    UNPROTECT(1);
    return result;
}
void *mutation_string_dataptr(SEXP value, Rboolean writable) {
    if (R_altrep_data2(value) == R_NilValue) {
        SEXP copy = PROTECT(mutation_string_duplicate(value, FALSE));
        R_set_altrep_data2(value, copy);
        UNPROTECT(1);
    }
    SEXP copy = R_altrep_data2(value); /* Always an ordinary private STRSXP. */
    return writable ? DATAPTR_RW(copy) : (void *) DATAPTR_RO(copy);
}
const void *mutation_string_dataptr_or_null(SEXP value) {
    /* The constructor admits only ordinary contiguous strings. Borrowing this
       read-only pointer cannot allocate or invoke a callback; Dataptr isolates
       a separate copy if requested. The call-local view roots either source.
       Element assignment is unsupported; public exposure uses ordinary strings. */
    return DATAPTR_RO(mutation_string_source(value));
}
SEXP C_dtatools_mutation_prototype(SEXP value) {
    int ordinary_discrete = (TYPEOF(value) == INTSXP || TYPEOF(value) == LGLSXP) &&
        Rf_getAttrib(value, R_DimSymbol) == R_NilValue && !Rf_isObject(value);
    int ordinary_string = TYPEOF(value) == STRSXP &&
        (!ALTREP(value) || mutation_string_view(value) ||
         unmaterialized_dictstring_source(value) != R_NilValue) &&
        Rf_getAttrib(value, R_DimSymbol) == R_NilValue && !Rf_isObject(value);
    if ((!owned_column(value) || !owned_supported(value)) &&
        !ordinary_string && !ordinary_discrete) return R_NilValue;
    SEXP result = PROTECT(Rf_allocVector(TYPEOF(value), 0));
    SHALLOW_DUPLICATE_ATTRIB(result, value);
    if (Rf_getAttrib(value, R_NamesSymbol) != R_NilValue) {
        Rf_setAttrib(result, R_NamesSymbol, Rf_allocVector(STRSXP, 0));
    }
    UNPROTECT(1);
    return result;
}


R_xlen_t ephemeral_string_length(SEXP value) {
    return XLENGTH(R_altrep_data1(value));
}

SEXP ephemeral_string_value(SEXP value, R_xlen_t index) {
    SEXP source = STRING_ELT(R_altrep_data1(value), index);
    if (source == NA_STRING) return NA_STRING;
    return Rf_mkCharLenCE(CHAR(source), LENGTH(source), Rf_getCharCE(source));
}

SEXP C_dtatools_ephemeral_altstring(SEXP value) {
    if (TYPEOF(value) != STRSXP) {
        Rf_error("ephemeral ALTSTRING source must be character");
    }
    return R_new_altrep(
        dtatools_ephemeral_string_class, value, R_NilValue
    );
}

SEXP C_dtatools_is_numeric_altrep(SEXP value) {
    return Rf_ScalarLogical(R_altrep_inherits(value, dtatools_numeric_class));
}

SEXP C_dtatools_is_altrep(SEXP value) {
    return Rf_ScalarLogical(ALTREP(value));
}

SEXP metadata_proxy_state(SEXP value) {
    SEXP state = R_altrep_data1(value);
    return TYPEOF(state) == VECSXP && (XLENGTH(state) == 2 || XLENGTH(state) == 3)
        ? state : R_NilValue;
}

SEXP metadata_proxy_source(SEXP value) {
    SEXP state = metadata_proxy_state(value);
    SEXP source = state == R_NilValue
        ? R_altrep_data1(value) : VECTOR_ELT(state, 0);
    if (state != R_NilValue && XLENGTH(state) == 3 &&
        ALTREP(source) && R_altrep_inherits(source, dtatools_numeric_class) &&
        R_altrep_data2(source) == R_NilValue) {
        numeric_data *origin = (numeric_data *) R_ExternalPtrAddr(VECTOR_ELT(state, 2));
        numeric_data *view = numeric_read_storage(source);
        if (origin != NULL && origin->values == view->values &&
            origin->native_owner == view->native_owner) {
            view->missing_count = origin->missing_count;
        }
    }
    return source;
}

SEXP metadata_proxy_owner(SEXP value) {
    SEXP state = metadata_proxy_state(value);
    return state == R_NilValue ? R_NilValue : VECTOR_ELT(state, 1);
}

void metadata_proxy_set_state(
    SEXP value, SEXP source, SEXP owner
) {
    SEXP state = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(state, 0, source);
    SET_VECTOR_ELT(state, 1, owner);
    R_set_altrep_data1(value, state);
    UNPROTECT(1);
}

R_xlen_t metadata_proxy_length(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue
        ? XLENGTH(metadata_proxy_source(value)) : XLENGTH(materialized);
}

double metadata_real_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    return REAL_ELT(
        materialized == R_NilValue ? metadata_proxy_source(value) : materialized,
        index
    );
}

R_xlen_t metadata_real_region(
    SEXP value, R_xlen_t index, R_xlen_t count, double *output
) {
    SEXP materialized = R_altrep_data2(value);
    return REAL_GET_REGION(
        materialized == R_NilValue ? metadata_proxy_source(value) : materialized,
        index, count, output
    );
}

static SEXP metadata_real_materialize(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return materialized;

    SEXP source = metadata_proxy_source(value);
    R_xlen_t length = XLENGTH(source);
    materialized = PROTECT(Rf_allocVector(REALSXP, length));
    R_xlen_t copied = REAL_GET_REGION(source, 0, length, REAL(materialized));
    if (copied != length) {
        UNPROTECT(1);
        Rf_error("failed to materialize dtatools metadata proxy");
    }
    R_set_altrep_data2(value, materialized);
    R_set_altrep_data1(value, R_NilValue);
    UNPROTECT(1);
    return materialized;
}

void *metadata_real_dataptr(SEXP value, Rboolean writeable) {
    SEXP materialized = metadata_real_materialize(value);
    return writeable ? DATAPTR_RW(materialized) : (void *) DATAPTR_RO(materialized);

}

const void *metadata_real_dataptr_or_null(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? NULL : DATAPTR_OR_NULL(materialized);
}

SEXP metadata_real_extract_subset(
    SEXP value, SEXP index, SEXP call
) {
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    SEXP source = metadata_proxy_source(value);
    if (!ALTREP(source) ||
        !R_altrep_inherits(source, dtatools_numeric_class)) {
        return NULL;
    }
    return numeric_extract_subset(source, index, call);
}

int metadata_real_no_na(SEXP value) {
    if (metadata_real_aggregate_mask_enabled) {
        metadata_real_aggregate_mask |= METADATA_AGGREGATE_NO_NA;
    }
    if (R_altrep_data2(value) != R_NilValue) return 0;
    SEXP source = metadata_proxy_source(value);
    return ALTREP(source) &&
        R_altrep_inherits(source, dtatools_numeric_class)
        ? numeric_no_na(source) : 0;
}

SEXP metadata_real_sum(SEXP value, Rboolean na_rm) {
    if (metadata_real_aggregate_mask_enabled) {
        metadata_real_aggregate_mask |= METADATA_AGGREGATE_SUM;
    }
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    SEXP source = metadata_proxy_source(value);
    return ALTREP(source) &&
        R_altrep_inherits(source, dtatools_numeric_class)
        ? numeric_sum(source, na_rm) : NULL;
}

SEXP metadata_real_min(SEXP value, Rboolean na_rm) {
    if (metadata_real_aggregate_mask_enabled) {
        metadata_real_aggregate_mask |= METADATA_AGGREGATE_MIN;
    }
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    SEXP source = metadata_proxy_source(value);
    return ALTREP(source) &&
        R_altrep_inherits(source, dtatools_numeric_class)
        ? numeric_min(source, na_rm) : NULL;
}

SEXP metadata_real_max(SEXP value, Rboolean na_rm) {
    if (metadata_real_aggregate_mask_enabled) {
        metadata_real_aggregate_mask |= METADATA_AGGREGATE_MAX;
    }
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    SEXP source = metadata_proxy_source(value);
    return ALTREP(source) &&
        R_altrep_inherits(source, dtatools_numeric_class)
        ? numeric_max(source, na_rm) : NULL;
}

SEXP metadata_string_value(SEXP value, R_xlen_t index) {
    SEXP materialized = R_altrep_data2(value);
    return STRING_ELT(
        materialized == R_NilValue ? metadata_proxy_source(value) : materialized,
        index
    );
}

static SEXP metadata_string_materialize(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) return materialized;

    SEXP source = metadata_proxy_source(value);
    R_xlen_t length = XLENGTH(source);
    materialized = PROTECT(Rf_allocVector(STRSXP, length));
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        SET_STRING_ELT(materialized, index, STRING_ELT(source, index));
    }
    R_set_altrep_data2(value, materialized);
    R_set_altrep_data1(value, R_NilValue);
    UNPROTECT(1);
    return materialized;
}

SEXP metadata_string_materialize_for_patch(
    SEXP value, SEXP dictionary, SEXP private_cache
) {
    SEXP materialized = R_altrep_data2(value);
    if (materialized != R_NilValue) {
        return detach_shared_materialized_payload(value);
    }
    materialized = PROTECT(dictstring_patch_values(
        dictionary, private_cache
    ));
    R_set_altrep_data2(value, materialized);
    R_set_altrep_data1(value, R_NilValue);
    UNPROTECT(1);
    return materialized;
}

/** Expose this proxy's decoded payload, materializing it on demand. */
void *metadata_string_dataptr(SEXP value, Rboolean writeable) {
    (void) writeable;
    SEXP materialized = metadata_string_materialize(value);
    return DATAPTR_RW(materialized);

}

/** Return an already decoded data pointer without forcing materialization. */
const void *metadata_string_dataptr_or_null(SEXP value) {
    SEXP materialized = R_altrep_data2(value);
    return materialized == R_NilValue ? NULL : DATAPTR_OR_NULL(materialized);
}

/** Replace one string in this proxy's decoded payload after materialization. */
void metadata_string_set_elt(
    SEXP value, R_xlen_t index, SEXP replacement
) {
    SET_STRING_ELT(metadata_string_materialize(value), index, replacement);
}

/**
 * Delegate supported subsets to compact dictionary storage.
 * Return NULL for decoded or unavailable backing so R handles the fallback.
 */
SEXP metadata_string_extract_subset(
    SEXP value, SEXP index, SEXP call
) {
    if (R_altrep_data2(value) != R_NilValue) return NULL;
    SEXP source = unmaterialized_dictstring_source(value);
    if (source == R_NilValue) return NULL;
    return dictstring_extract_subset(source, index, call);
}

/**
 * Build an attribute-preserving proxy around numeric or dictionary storage.
 * When isolate is nonzero, mark compact backing as shared or snapshot decoded
 * backing so a later explicit patch cannot change the source vector.
 */
SEXP metadata_proxy(
    SEXP value, R_altrep_class_t proxy_class, int isolate
) {
    SEXP source = value;
    SEXP read_origin = R_NilValue;
    while (ALTREP(source) && R_altrep_inherits(source, proxy_class) &&
           R_altrep_data2(source) == R_NilValue) {
        SEXP state = metadata_proxy_state(source);
        if (state != R_NilValue && XLENGTH(state) == 3) {
            read_origin = VECTOR_ELT(state, 2);
            if (isolate) compact_payload_mark_shared(read_origin);
        }
        SEXP owner = metadata_proxy_owner(source);
        SEXP next = metadata_proxy_source(source);
        if (isolate && owner != R_NilValue && ALTREP(next) &&
            R_altrep_inherits(next, dtatools_numeric_class) &&
            R_altrep_data2(next) == R_NilValue &&
            compact_payload_is_owned_by(R_altrep_data1(next), owner)) {
            /* A second proxy now shares this payload. Revoke the first
               proxy's exclusive-write claim so its next patch detaches. */
            compact_payload_revoke_claim(R_altrep_data1(next));
        }
        source = next;
    }
    SEXP materialized_snapshot = R_NilValue;
    if (isolate && ALTREP(source) &&
        R_altrep_inherits(source, proxy_class) &&
        R_altrep_data2(source) != R_NilValue) {
        materialized_snapshot = PROTECT(Rf_duplicate(
            R_altrep_data2(source)
        ));
        source = materialized_snapshot;
    }
    SEXP alias = R_NilValue;
    if (isolate && ALTREP(source) &&
        R_altrep_inherits(source, dtatools_numeric_class)) {
        SEXP external = R_altrep_data1(source);
        if (R_altrep_data2(source) == R_NilValue &&
            numeric_payload_retained(numeric_read_storage(source))) {
            alias = PROTECT(numeric_handle_copy(source));
        } else {
            alias = PROTECT(R_new_altrep(
                dtatools_numeric_class, external, R_altrep_data2(source)
            ));
            compact_payload_mark_shared(external);
        }
        source = alias;
    } else if (isolate && ALTREP(source) &&
               R_altrep_inherits(source, dtatools_dictstring_class)) {
        SEXP external = R_altrep_data1(source);
        alias = PROTECT(R_new_altrep(
            dtatools_dictstring_class, external, R_altrep_data2(source)
        ));
        compact_payload_mark_shared(external);
        source = alias;
    }
    SEXP state = PROTECT(Rf_allocVector(VECSXP,
        !isolate && read_origin != R_NilValue ? 3 : 2));
    SET_VECTOR_ELT(state, 0, source);
    SET_VECTOR_ELT(state, 1, R_NilValue);
    if (XLENGTH(state) == 3) SET_VECTOR_ELT(state, 2, read_origin);
    SEXP result = PROTECT(R_new_altrep(proxy_class, state, R_NilValue));
    SHALLOW_DUPLICATE_ATTRIB(result, value);
    UNPROTECT(
        2 + (alias != R_NilValue) +
        (materialized_snapshot != R_NilValue)
    );
    return result;
}

/**
 * Duplicate an unmaterialized numeric proxy without requesting a data pointer.
 * Both R duplication depths use an independent compact payload. Return NULL
 * for decoded proxies so R can perform its ordinary duplication fallback.
 */
SEXP metadata_real_duplicate(SEXP value, Rboolean deep) {
    (void) deep;
    SEXP source = numeric_base_source(value);
    return source == R_NilValue ? NULL : numeric_handle_copy(source);
}

/**
 * Duplicate an unmaterialized dictionary proxy with compact storage intact.
 * The compact copy isolates later writes at either R duplication depth.
 * Return NULL for decoded proxies to request R's duplication fallback.
 */
SEXP metadata_string_duplicate(SEXP value, Rboolean deep) {
    (void) deep;
    if (unmaterialized_dictstring_source(value) == R_NilValue) return NULL;
    return dictstring_compact_copy(value);
}

/**
 * Copy vector attributes and isolate later explicit payload writes.
 * Native ALTREP columns use compact proxies; other vectors use R's shallow
 * duplicate. The returned vector can receive metadata without changing input.
 */
SEXP C_dtatools_metadata_copy(SEXP value) {
    if (mutation_string_view(value)) return mutation_string_duplicate(value, FALSE);
    if (owned_supported(value)) return owned_fork(value);
    if (!ALTREP(value)) return Rf_shallow_duplicate(value);
    if (R_altrep_inherits(value, dtatools_numeric_class) ||
        R_altrep_inherits(value, dtatools_metadata_real_class)) {
        return metadata_proxy(value, dtatools_metadata_real_class, 1);
    }
    if (R_altrep_inherits(value, dtatools_dictstring_class) ||
        R_altrep_inherits(value, dtatools_metadata_string_class)) {
        return metadata_proxy(value, dtatools_metadata_string_class, 1);
    }
    return Rf_shallow_duplicate(value);
}

/**
 * Create a metadata view for internal reads without isolating native backing.
 * Use C_dtatools_metadata_copy when later explicit writes need isolation.
 */
SEXP C_dtatools_metadata_view(SEXP value) {
    if (mutation_string_view(value)) return mutation_string_duplicate(value, FALSE);
    if (owned_column(value)) return owned_fork(value);
    if (!ALTREP(value)) return Rf_shallow_duplicate(value);
    if (R_altrep_inherits(value, dtatools_numeric_class) ||
        R_altrep_inherits(value, dtatools_metadata_real_class)) {
        return metadata_proxy(value, dtatools_metadata_real_class, 0);
    }
    if (R_altrep_inherits(value, dtatools_dictstring_class) ||
        R_altrep_inherits(value, dtatools_metadata_string_class)) {
        return metadata_proxy(value, dtatools_metadata_string_class, 0);
    }
    return Rf_shallow_duplicate(value);
}

/* Call-local read handles keep R validation from creating references to the
   physical column handle. They must cross metadata_copy before user evaluation.
   A compact view has a separate descriptor retaining the raw allocation, so a
   foreign materialization of the physical handle cannot invalidate the view. */
static SEXP mutation_column_view(SEXP value) {
    if (TYPEOF(value) == STRSXP && !ALTREP(value) && !Rf_isObject(value) &&
        Rf_getAttrib(value, R_DimSymbol) == R_NilValue) {
        SEXP view = PROTECT(R_new_altrep(dtatools_mutation_string_class, value, R_NilValue));
        SHALLOW_DUPLICATE_ATTRIB(view, value);
        UNPROTECT(1);
        return view;
    }
    if (owned_column(value) && owned_supported(value)) {
        SEXP view = PROTECT(R_new_altrep(
            owned_class(TYPEOF(value)), R_altrep_data1(value), R_BaseEnv));
        SHALLOW_DUPLICATE_ATTRIB(view, value);
        UNPROTECT(1);
        return view;
    }
    numeric_data *numeric = unmaterialized_numeric_read_storage(value);
    if (numeric != NULL && known_numeric_classes(value, 1)) {
        SEXP source = value;
        while (R_altrep_inherits(source, dtatools_metadata_real_class)) {
            source = metadata_proxy_source(source);
        }
        SEXP origin = R_altrep_data1(source);
        SEXP descriptor = PROTECT(numeric_payload_retained(numeric)
            ? numeric_handle_copy(source)
            : numeric_from_backing(
                R_ExternalPtrProtected(origin), numeric->length, numeric->kind,
                numeric->temporal, numeric->format_version, numeric->missing_count));
        SEXP state = PROTECT(Rf_allocVector(VECSXP, 3));
        SET_VECTOR_ELT(state, 0, descriptor);
        SET_VECTOR_ELT(state, 1, R_NilValue);
        SET_VECTOR_ELT(state, 2, origin);
        SEXP view = PROTECT(R_new_altrep(dtatools_metadata_real_class, state, R_NilValue));
        SHALLOW_DUPLICATE_ATTRIB(view, value);
        UNPROTECT(3);
        return view;
    }
    /* Unknown and unsupported representations retain the physical handle.
       The final conservative native guard therefore captures before writing. */
    return value;
}

SEXP C_dtatools_mutation_views(SEXP data) {
    if (TYPEOF(data) != VECSXP) Rf_error("mutation views need a physical table");
    SEXP result = PROTECT(Rf_allocVector(VECSXP, XLENGTH(data)));
    SEXP sizes = PROTECT(Rf_allocVector(REALSXP, XLENGTH(data)));
    for (R_xlen_t i = 0; i < XLENGTH(data); i++) {
        SEXP column = VECTOR_ELT(data, i);
        SEXP view = mutation_column_view(column);
        SET_VECTOR_ELT(result, i, view);
        /* An internal view must never reach NROW/length/dim dispatch. Unknown
           classes retain their physical handle and conservative alias guard. */
        REAL(sizes)[i] = view == column ? NA_REAL : (double) XLENGTH(view);
    }
    Rf_setAttrib(result, R_NamesSymbol, Rf_getAttrib(data, R_NamesSymbol));
    Rf_setAttrib(result, Rf_install(".dtatools_mutation_views"), Rf_ScalarLogical(1));
    Rf_setAttrib(result, Rf_install(".dtatools_mutation_sizes"), sizes);
    UNPROTECT(2);
    return result;
}

/* One column's private view, in the list form `C_dtatools_release_mutation_views()`
   releases, for a writer that casts against a single target before it reads
   the table's layout. The list records the physical column's address, not
   the column, so the writer can tell whether the slot still holds the column
   the cast was made against; holding the column would make the slot look
   shared and force the patch to detach it. */
static R_xlen_t view_slot(SEXP data, SEXP location) {
    if (TYPEOF(data) != VECSXP) Rf_error("mutation views need a physical table");
    double position = Rf_asReal(location);
    if (ISNAN(position) || position < 1 || position > (double) XLENGTH(data)) {
        Rf_error("mutation view location is out of range");
    }
    return (R_xlen_t) position - 1;
}

SEXP C_dtatools_mutation_column_view(SEXP data, SEXP location) {
    R_xlen_t slot = view_slot(data, location);
    SEXP column = VECTOR_ELT(data, slot);
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 1));
    SEXP view = mutation_column_view(column);
    SET_VECTOR_ELT(result, 0, view);
    SEXP token = PROTECT(R_MakeExternalPtr((void *) column, R_NilValue, R_NilValue));
    SEXP size = PROTECT(Rf_ScalarReal(view == column ? NA_REAL : (double) XLENGTH(view)));
    Rf_setAttrib(result, Rf_install(".dtatools_mutation_views"), Rf_ScalarLogical(1));
    Rf_setAttrib(result, Rf_install(".dtatools_mutation_sizes"), size);
    Rf_setAttrib(result, Rf_install(".dtatools_mutation_slot"), token);
    UNPROTECT(3);
    return result;
}

SEXP C_dtatools_mutation_column_current(SEXP data, SEXP location, SEXP views) {
    R_xlen_t slot = view_slot(data, location);
    SEXP recorded = Rf_getAttrib(views, Rf_install(".dtatools_mutation_slot"));
    if (TYPEOF(recorded) != EXTPTRSXP) return Rf_ScalarLogical(0);
    return Rf_ScalarLogical(R_ExternalPtrAddr(recorded) == (void *) VECTOR_ELT(data, slot));
}

/* These lists belong solely to a finished mutation evaluation. Drop their
   physical fallback references before the late sharing check; genuine aliases
   retained by user callbacks remain counted. No view is used after release. */
SEXP C_dtatools_release_mutation_views(SEXP columns) {
    if (TYPEOF(columns) != VECSXP ||
        Rf_asLogical(Rf_getAttrib(columns, Rf_install(".dtatools_mutation_views"))) != TRUE) {
        return R_NilValue;
    }
    for (R_xlen_t i = 0; i < XLENGTH(columns); i++) {
        SEXP column = VECTOR_ELT(columns, i);
        if (mutation_string_view(column)) R_set_altrep_data1(column, R_NilValue);
        SET_VECTOR_ELT(columns, i, R_NilValue);
    }
    return R_NilValue;
}

SEXP C_dtatools_expose_mutation_column(SEXP value) {
    if (mutation_string_view(value)) return mutation_string_source(value);
    if (owned_column(value) || unmaterialized_numeric_read_storage(value) != NULL) {
        return C_dtatools_metadata_copy(value);
    }
    return value;
}

/* Rf_getAttrib deliberately marks its result immutable. Internal names reads
   must not publish the vector or revoke privacy merely to validate/count it.
   R 4.6's experimental attribute iterator keeps this narrow read on the public
   API; all actual writes still require the real late MAYBE_SHARED check. */
static SEXP mutation_names_attribute(SEXP tag, SEXP value, void *context) {
    (void) context;
    return tag == R_NamesSymbol ? value : NULL;
}

SEXP mutation_physical_names(SEXP data) {
    if (Rf_getAttrib(data, R_DimSymbol) != R_NilValue) return Rf_getAttrib(data, R_NamesSymbol);
    SEXP names = R_mapAttrib(data, mutation_names_attribute, NULL);
    return names == NULL ? R_NilValue : names;
}

/* Diagnostic scalars only: do not export names or affect their sharing. */
SEXP C_dtatools_column_names_info(SEXP data) {
    if (TYPEOF(data) != VECSXP || ALTREP(data)) Rf_error("physical table required");
    SEXP names = mutation_physical_names(data);
    if (TYPEOF(names) != STRSXP || ALTREP(names)) Rf_error("ordinary physical column names required");
    char address[64];
    snprintf(address, sizeof(address), "%p", (void *) names);
    int shared = MAYBE_SHARED(names);
    double length = (double) XLENGTH(names);
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(result, 0, Rf_mkString(address));
    SET_VECTOR_ELT(result, 1, Rf_ScalarLogical(shared));
    SET_VECTOR_ELT(result, 2, Rf_ScalarReal(length));
    UNPROTECT(1);
    return result;
}

/* A 32 KiB fixed stack budget avoids heap churn for common-width tables.
   At a half-full hash table this supports 2,048 names. Wider tables, encoded
   non-ASCII names and callback-capable columns retain the complete R path. */
#define MUTATION_SHAPE_NAME_SLOTS 4096
static int mutation_ascii_name(SEXP name) {
    if (name == NA_STRING || Rf_getCharCE(name) == CE_BYTES) return 0;
    const unsigned char *text = (const unsigned char *) CHAR(name);
    for (; *text; text++) if (*text >= 128) return 0;
    return 1;
}

SEXP C_dtatools_mutation_shape(SEXP data, SEXP row_count) {
    if (ALTREP(row_count) || (TYPEOF(row_count) != INTSXP && TYPEOF(row_count) != REALSXP) ||
        XLENGTH(row_count) != 1) return Rf_ScalarLogical(0);
    if (TYPEOF(data) != VECSXP || ALTREP(data) ||
        XLENGTH(data) > MUTATION_SHAPE_NAME_SLOTS / 2) return Rf_ScalarLogical(0);
    if (Rf_getAttrib(data, R_DimSymbol) != R_NilValue) return Rf_ScalarLogical(0);
    SEXP names = mutation_physical_names(data);
    if (TYPEOF(names) != STRSXP || ALTREP(names) || Rf_isObject(names) ||
        XLENGTH(names) != XLENGTH(data)) return Rf_ScalarLogical(0);
    /* Establish the callback-free domain before reading lengths or names. */
    for (R_xlen_t i = 0; i < XLENGTH(data); i++) {
        SEXP value = VECTOR_ELT(data, i);
        if (ALTREP(Rf_getAttrib(value, R_ClassSymbol))) return Rf_ScalarLogical(0);
        int known = owned_supported(value) ||
            (unmaterialized_numeric_read_storage(value) != NULL && known_numeric_classes(value, 1)) ||
            (!ALTREP(value) && !Rf_isObject(value) &&
             (TYPEOF(value) == REALSXP || TYPEOF(value) == INTSXP ||
              TYPEOF(value) == LGLSXP || TYPEOF(value) == STRSXP));
        if (!known || Rf_getAttrib(value, R_DimSymbol) != R_NilValue) return Rf_ScalarLogical(0);
        SEXP name = STRING_ELT(names, i);
        if (!mutation_ascii_name(name)) return Rf_ScalarLogical(0);
    }
    SEXP seen[MUTATION_SHAPE_NAME_SLOTS] = {0};
    for (R_xlen_t i = 0; i < XLENGTH(data); i++) {
        SEXP name = STRING_ELT(names, i);
        const unsigned char *text = (const unsigned char *) CHAR(name);
        if (!*text) Rf_error("`data` must have unique, non-missing column names; duplicated names are ambiguous");
        uint32_t hash = 2166136261u;
        for (; *text; text++) hash = (hash ^ *text) * 16777619u;
        size_t slot = hash & (MUTATION_SHAPE_NAME_SLOTS - 1);
        while (seen[slot] != NULL) {
            if (seen[slot] == name || strcmp(CHAR(seen[slot]), CHAR(name)) == 0)
                Rf_error("`data` must have unique, non-missing column names; duplicated names are ambiguous");
            slot = (slot + 1) & (MUTATION_SHAPE_NAME_SLOTS - 1);
        }
        seen[slot] = name;
    }
    double expected = Rf_asReal(row_count);
    for (R_xlen_t i = 0; i < XLENGTH(data); i++) {
        if ((double) XLENGTH(VECTOR_ELT(data, i)) != expected)
            Rf_error("`data` has columns with inconsistent row counts; assign `data <- dplyr::ungroup(data)` and group again");
    }
    return Rf_ScalarLogical(1);
}

/* Only used after the ASCII shape certificate above. A non-ASCII query
   declines so R's complete encoding-aware matching remains authoritative. */
SEXP C_dtatools_mutation_name_location(SEXP data, SEXP name) {
    if (TYPEOF(name) != STRSXP || XLENGTH(name) != 1 ||
        !mutation_ascii_name(STRING_ELT(name, 0))) return R_NilValue;
    SEXP names = mutation_physical_names(data);
    if (TYPEOF(names) != STRSXP || ALTREP(names)) return R_NilValue;
    const char *wanted = CHAR(STRING_ELT(name, 0));
    for (R_xlen_t i = 0; i < XLENGTH(names); i++) {
        if (strcmp(CHAR(STRING_ELT(names, i)), wanted) == 0) return Rf_ScalarInteger((int) i + 1);
    }
    return Rf_ScalarInteger(NA_INTEGER);
}

SEXP C_dtatools_physical_column_count(SEXP data) {
    if (TYPEOF(data) != VECSXP) Rf_error("physical column count needs a list");
    return XLENGTH(data) <= INT_MAX ? Rf_ScalarInteger((int) XLENGTH(data))
        : Rf_ScalarReal((double) XLENGTH(data));
}

/**
 * Install fresh reference bookkeeping and classes on the supplied table.
 * The caller must provide an unshared state environment. Its non-owning owner
 * token records table identity without retaining the table or its columns.
 */
SEXP C_dtatools_mark_reference_data(
    SEXP data, SEXP state, SEXP classes
) {
    if (TYPEOF(data) != VECSXP || TYPEOF(state) != ENVSXP ||
        TYPEOF(classes) != STRSXP || XLENGTH(classes) == 0) {
        Rf_error("invalid reference-data state");
    }
    SEXP owner = PROTECT(R_MakeExternalPtr(data, R_NilValue, R_NilValue));
    Rf_defineVar(Rf_install("owner"), owner, state);
    Rf_setAttrib(data, Rf_install(".dtatools_ref_state"), state);
    Rf_setAttrib(data, R_ClassSymbol, classes);
    UNPROTECT(1);
    return data;
}

/**
 * Report whether the supplied table owns its reference bookkeeping.
 * Compare the non-owning token without dereferencing it. Serialization clears
 * external pointers; a physical table copy has a different address. This does
 * not repair state, inspect spare capacity, or determine whether data is typed.
 */
SEXP C_dtatools_reference_state_valid(SEXP data) {
    SEXP state = Rf_getAttrib(data, Rf_install(".dtatools_ref_state"));
    if (!Rf_inherits(data, "dtatools_ref_data") || TYPEOF(state) != ENVSXP)
        return Rf_ScalarLogical(0);
    SEXP owner = R_getVarEx(Rf_install("owner"), state, FALSE, R_NilValue);
    return Rf_ScalarLogical(TYPEOF(owner) == EXTPTRSXP &&
                            R_ExternalPtrAddr(owner) == data);
}

// Replaces one attribute on an object in place. Reference datasets are
// shared by every binding that holds them, so grouping metadata that a
// replacement invalidated must be rewritten on the object itself rather
// than on a copy that only one binding would see.
SEXP C_dtatools_set_attribute(SEXP object, SEXP name, SEXP value) {
    if (TYPEOF(object) != VECSXP || TYPEOF(name) != STRSXP ||
        XLENGTH(name) != 1) {
        Rf_error("invalid attribute assignment");
    }
    Rf_setAttrib(object, Rf_install(CHAR(STRING_ELT(name, 0))), value);
    return object;
}

SEXP C_dtatools_reference_contents(SEXP value) {
    int type = TYPEOF(value);
    if (type != VECSXP && type != EXPRSXP &&
        type != LISTSXP && type != LANGSXP) {
        Rf_error("invalid reference-object container");
    }
    R_xlen_t length = 0;
    if (type == VECSXP || type == EXPRSXP) {
        length = XLENGTH(value);
    } else {
        for (SEXP node = value; node != R_NilValue; node = CDR(node)) {
            if ((length & 16383) == 0) R_CheckUserInterrupt();
            int node_type = TYPEOF(node);
            if (node_type != LISTSXP && node_type != LANGSXP &&
                node_type != DOTSXP) {
                Rf_error("invalid reference-object pairlist");
            }
            if (length == R_XLEN_T_MAX) {
                Rf_error("reference-object container is too long");
            }
            length++;
        }
    }
    SEXP result = PROTECT(Rf_allocVector(VECSXP, length));
    if (type == VECSXP || type == EXPRSXP) {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            SET_VECTOR_ELT(result, index, VECTOR_ELT(value, index));
        }
    } else {
        SEXP node = value;
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            SET_VECTOR_ELT(result, index, CAR(node));
            node = CDR(node);
        }
    }
    UNPROTECT(1);
    return result;
}
