/* Frozen selection for canonical integral Stata grouping keys. Native publication
   additionally requires the bracket dependency and input checks. */
#include "dtatools-internal.h"

typedef struct { int count, seen; } key_attrs;
static SEXP check_key_attr(SEXP tag, SEXP value, void *raw) {
    (void) value;
    key_attrs *attrs = (key_attrs *) raw;
    attrs->count++;
    if (tag == R_ClassSymbol) attrs->seen |= 1;
    else if (tag == Rf_install("stata.storage")) attrs->seen |= 2;
    else return R_NilValue;
    return NULL;
}

static int canonical_long(SEXP key) {
    if (TYPEOF(key) != REALSXP || XLENGTH(key) > INT_MAX ||
        !(R_altrep_inherits(key, dtatools_metadata_real_class) ||
          R_altrep_inherits(key, dtatools_numeric_class)) ||
        R_altrep_data2(key) != R_NilValue ||
        (owned_real(key) && owned_flags(key)[OWNED_EXPOSED])) return 0;
    key_attrs attrs = {0, 0};
    if (R_mapAttrib(key, check_key_attr, &attrs) != NULL ||
        attrs.count != 2 || attrs.seen != 3) return 0;
    SEXP classes = Rf_getAttrib(key, R_ClassSymbol);
    static const char *wanted[] = {
        "dta_numeric", "dta_long", "vctrs_vctr", "double"
    };
    if (TYPEOF(classes) != STRSXP || ALTREP(classes) ||
        XLENGTH(classes) != 4) return 0;
    for (int i = 0; i < 4; i++)
        if (strcmp(CHAR(STRING_ELT(classes, i)), wanted[i])) return 0;
    SEXP storage = Rf_getAttrib(key, Rf_install("stata.storage"));
    return TYPEOF(storage) == STRSXP && !ALTREP(storage) &&
        XLENGTH(storage) == 1 &&
        strcmp(CHAR(STRING_ELT(storage, 0)), "long") == 0;
}

/* lowbias32 mixer from Chris Wellons's hash-prospector, under the Unlicense.
   https://github.com/skeeto/hash-prospector#two-round-functions
   The frozen first-occurrence grouping plan around it is separate work. */
static size_t key_hash(uint32_t key) {
    uint32_t x = key;
    x ^= x >> 16;
    x *= UINT32_C(0x7feb352d);
    x ^= x >> 15;
    x *= UINT32_C(0x846ca68b);
    x ^= x >> 16;
    return (size_t) x;
}

static int hash_slot(int key, const int *table, const int *unique,
                     size_t mask) {
    size_t slot = key_hash((uint32_t) key) & mask;
    while (table[slot] && unique[table[slot] - 1] != key)
        slot = (slot + 1) & mask;
    return (int) slot;
}

static int key_matches_snapshot(SEXP key, SEXP base, SEXP snapshot,
                                R_xlen_t n) {
    if (base != R_NilValue &&
        R_altrep_inherits(base, dtatools_numeric_class) &&
        R_altrep_data2(base) == R_NilValue) {
        /* Read the descriptor only after the final noalloc identity seal.
           numeric_region is unsuitable here: its decoding loop polls at
           offset zero, even for a short chunk. numeric_copy_region uses a
           memcpy-only visitor; chunks below 16384 also avoid the retained
           payload loop's interrupt poll. */
        numeric_data *storage = numeric_read_storage(base);
        if (storage->length != (size_t) n) return 0;
        if (storage->kind == NUMERIC_LONG && storage->temporal == 0) {
            int32_t raw[8192];
            double current[8192];
            for (R_xlen_t row = 0; row < n; row += 8192) {
                R_xlen_t count = n - row < 8192 ? n - row : 8192;
                numeric_copy_region(storage, (size_t) row,
                                    (size_t) count, raw);
                for (R_xlen_t offset = 0; offset < count; offset++) {
                    int32_t value = raw[offset];
                    if (value < 1 ||
                        (storage->format_version <= 111
                         ? value == INT32_MAX
                         : value >= INT32_C(2147483621)))
                        return 0;
                    current[offset] = (double) value;
                }
                if (memcmp(current, REAL(snapshot) + row,
                           (size_t) count * sizeof(double)) != 0)
                    return 0;
            }
            return 1;
        }
    }
    /* Retain the original comparator outside the known compact reader. */
    for (R_xlen_t row = 0; row < n; row++)
        if (numeric_value(base == R_NilValue ? key : base, row) !=
            REAL(snapshot)[row]) return 0;
    return 1;
}

/* Preallocate every R holder before capturing a public descriptor. A public
   materialization may explicitly free that descriptor even when its data1
   record is rooted. The private descriptor below cannot be reached by such
   a callback, and its byte owner remains rooted through snapshot polls. */
static SEXP private_key_reader(SEXP key, SEXP base, SEXP initial_data1,
                               R_xlen_t n) {
    /* Only scalar allocation sizes survive these R allocations. The
       descriptor and byte pointer are reacquired after the final seal. */
    numeric_data *entry = numeric_read_storage(base);
    int retained = numeric_payload_retained(entry);
    int entry_kind = entry->kind;
    if (entry_kind < NUMERIC_BYTE || entry_kind > NUMERIC_FLOAT)
        return R_NilValue;
    size_t width = numeric_kind_width(entry_kind);
    if ((size_t) n > SIZE_MAX / width ||
        (size_t) n * width > (size_t) R_XLEN_T_MAX)
        return R_NilValue;
    SEXP external = PROTECT(R_MakeExternalPtr(
        NULL, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(external, numeric_finalize, TRUE);
    SEXP reader = PROTECT(R_new_altrep(
        dtatools_numeric_class, external, R_NilValue));
    SEXP frozen_backing = PROTECT(retained ? R_NilValue :
        Rf_allocVector(RAWSXP, (R_xlen_t) ((size_t) n * width)));
    if (!canonical_long(key) || XLENGTH(key) != n ||
        numeric_base_source(key) != base ||
        R_altrep_data1(base) != initial_data1 ||
        R_altrep_data2(base) != R_NilValue) {
        UNPROTECT(3); return R_NilValue;
    }
    numeric_data *data = numeric_read_storage(base);
    if (data->length != (size_t) n || data->kind != entry_kind ||
        numeric_payload_retained(data) != retained) {
        UNPROTECT(3); return R_NilValue;
    }
    SEXP backing = R_ExternalPtrProtected(initial_data1);
    void *copy;
    if (numeric_payload_retained(data)) {
        /* Native allocation/Arc retention invokes no R callback. */
        copy = dtatools_owned_numeric_clone(data);
    } else {
        if (TYPEOF(backing) != RAWSXP || ALTREP(backing) ||
            data->length > SIZE_MAX / width ||
            data->length * width != (size_t) XLENGTH(backing) ||
            data->values != RAW(backing)) {
            UNPROTECT(3); return R_NilValue;
        }
        /* Freeze plain bytes in one noalloc copy. A public value mutation
           during the later snapshot polls cannot rewrite this private RAW. */
        memcpy(RAW(frozen_backing), data->values, data->length * width);
        backing = frozen_backing;
        copy = dtatools_numeric_alloc(RAW(backing), data->length, data->kind,
                                      data->temporal, data->missing_count);
        if (copy != NULL)
            ((numeric_data *) copy)->format_version = data->format_version;
    }
    if (copy == NULL) { UNPROTECT(3); return R_NilValue; }
    R_SetExternalPtrProtected(external, backing);
    R_SetExternalPtrAddr(external, copy);
    UNPROTECT(3);
    return reader;
}

/* Scratch-only shape/identity mutation control, never an admission helper. */
SEXP C_dtatools_probe_plan_key_change(SEXP key, SEXP change, SEXP replacement) {
    SEXP base = numeric_base_source(key);
    if (base == R_NilValue || TYPEOF(change) != INTSXP ||
        XLENGTH(change) != 1)
        Rf_error("invalid scratch plan key change");
    if (INTEGER(change)[0] == 0) {
        if (TYPEOF(replacement) != INTSXP || XLENGTH(replacement) != 1 ||
            INTEGER(replacement)[0] < 0)
            Rf_error("invalid scratch plan key extent");
        numeric_read_storage(base)->length = (size_t) INTEGER(replacement)[0];
    } else if (INTEGER(change)[0] == 1 && TYPEOF(replacement) == EXTPTRSXP) {
        R_set_altrep_data1(base, replacement);
    } else if (INTEGER(change)[0] == 3) {
        return Rf_ScalarLogical(numeric_payload_retained(numeric_read_storage(base)));
    } else if (INTEGER(change)[0] == 2) {
        SEXP replacement_base = numeric_base_source(replacement);
        if (replacement_base == R_NilValue)
            Rf_error("invalid scratch plan replacement key");
        R_set_altrep_data1(base, R_altrep_data1(replacement_base));
    } else Rf_error("invalid scratch plan key change mode");
    return R_NilValue;
}

SEXP C_dtatools_probe_grouped_bracket_selection(SEXP key, SEXP name) {
    int double_key = TYPEOF(key) == REALSXP && (!ALTREP(key) || owned_real(key)) &&
        dtatools_grouped_double_values(key, XLENGTH(key)) != R_NilValue;
    if ((!canonical_long(key) && !double_key) || TYPEOF(name) != STRSXP ||
        XLENGTH(name) != 1 || STRING_ELT(name, 0) == NA_STRING ||
        !CHAR(STRING_ELT(name, 0))[0]) return R_NilValue;
    R_xlen_t n = XLENGTH(key);
    if (!n) return R_NilValue;
    SEXP base = double_key ? dtatools_grouped_double_values(key, n) : numeric_base_source(key);
    if (base == R_NilValue || (double_key && !dtatools_probe_plain_public_guard())) return R_NilValue;
    PROTECT(key);
    PROTECT(base);
    /* Root the old record independently: a callback may replace data1 and
       then collect the old record before the final identity comparison. */
    SEXP initial_data1 = PROTECT(double_key ? base : R_altrep_data1(base));
    /* This bounded prototype is meant for a physical floor. A production
       admission would instead size/check these allocations without a row
       threshold or decline based on required bytes. */
    if (n > 10000000) { UNPROTECT(3); return R_NilValue; }
    SEXP read_handle = PROTECT(double_key ? Rf_allocVector(REALSXP, n) :
        private_key_reader(key, base, initial_data1, n));
    if (double_key) {
        if (dtatools_grouped_double_values(key, n) != base) {
            UNPROTECT(4); return R_NilValue;
        }
        memcpy(REAL(read_handle), REAL(base), (size_t)n * sizeof(double));
    }
    if (read_handle == R_NilValue) { UNPROTECT(4); return R_NilValue; }
    size_t buckets = 2;
    while (buckets < (size_t) n * 2) buckets *= 2;
    int *table = (int *) R_alloc(buckets, sizeof(int));
    int *unique = (int *) R_alloc((size_t) n, sizeof(int));
    int *counts = (int *) R_alloc((size_t) n, sizeof(int));
    /* Preserve each first-pass group index. The second pass can write rows
       directly without repeating hash/mixer lookup. counts becomes the
       per-group write cursor after every positions vector is allocated. */
    int *row_groups = (int *) R_alloc((size_t) n, sizeof(int));
    memset(table, 0, buckets * sizeof(int));
    SEXP snapshot = PROTECT(Rf_allocVector(REALSXP, n));
    /* Scratch-only real-finalizer control after the private reader is rooted. */
    SEXP snapshot_hook = Rf_GetOption1(Rf_install(
        "dtatools.probe_grouped_plan_snapshot_hook"));
    if (Rf_isFunction(snapshot_hook)) {
        SEXP call = PROTECT(Rf_lang1(snapshot_hook));
        Rf_eval(call, R_GlobalEnv);
        UNPROTECT(1);
    }
    if (double_key) memcpy(REAL(snapshot), REAL(read_handle), (size_t)n * sizeof(double));
    else if (numeric_region(read_handle, 0, n, REAL(snapshot)) != n) {
        UNPROTECT(5); return R_NilValue;
    }
    /* snapshot is a fresh protected ordinary REAL vector. Its storage does
       not move, and no public callback can obtain this private holder. Keep
       the original interrupt positions and all floating-point predicates. */
    const double *snapshot_values = REAL(snapshot);
    int groups = 0;
    for (R_xlen_t row = 0; row < n; row++) {
        if ((row & 1023) == 0) R_CheckUserInterrupt();
        double value = snapshot_values[row];
        if (!R_FINITE(value) || value < 1 || value > INT_MAX ||
            value != (int) value) {
            UNPROTECT(5); return R_NilValue;
        }
        int code = (int) value;
        int slot = hash_slot(code, table, unique, buckets - 1);
        if (!table[slot]) {
            unique[groups] = code;
            counts[groups] = 0;
            table[slot] = ++groups;
        }
        int group = table[slot] - 1;
        row_groups[row] = group;
        counts[group]++;
    }
    SEXP rows = PROTECT(Rf_allocVector(VECSXP, groups));
    SEXP selected = PROTECT(Rf_allocVector(VECSXP, groups));
    for (int group = 0; group < groups; group++) {
        SEXP positions = PROTECT(Rf_allocVector(INTSXP, counts[group]));
        SET_VECTOR_ELT(rows, group, positions);
        counts[group] = 0;
        /* Hash lookup is complete. Reuse its R_alloc byte storage for these
           private row-vector pointers. buckets >= 2*n >= 2*groups, so this
           fits whenever a pointer occupies at most two ints. memcpy avoids
           alignment and aliasing assumptions about the original int table.
           Each ordinary positions vector remains reachable through rows. */
        if (sizeof(int *) <= 2 * sizeof(int)) {
            int *positions_values = INTEGER(positions);
            memcpy((unsigned char *) table + (size_t) group * sizeof(int *),
                   &positions_values, sizeof positions_values);
        }
        UNPROTECT(1);
    }
    if (sizeof(int *) <= 2 * sizeof(int)) {
        for (R_xlen_t row = 0; row < n; row++) {
            int group = row_groups[row];
            int *positions_values;
            memcpy(&positions_values,
                   (unsigned char *) table + (size_t) group * sizeof(int *),
                   sizeof positions_values);
            positions_values[counts[group]++] = (int) row + 1;
        }
    } else {
        /* Keep the original fill on an unusual pointer-width build. */
        for (R_xlen_t row = 0; row < n; row++) {
            int group = row_groups[row];
            INTEGER(VECTOR_ELT(rows, group))[counts[group]++] = (int) row + 1;
        }
    }
    SEXP key_backing = PROTECT(Rf_allocVector(REALSXP, groups));
    for (int group = 0; group < groups; group++)
        REAL(key_backing)[group] = unique[group];
    SEXP key_column = PROTECT(owned_adopt_real(key_backing));
    Rf_setAttrib(key_column, Rf_install("stata.storage"),
                 Rf_getAttrib(key, Rf_install("stata.storage")));
    Rf_setAttrib(key_column, R_ClassSymbol, Rf_getAttrib(key, R_ClassSymbol));
    SEXP keys = PROTECT(Rf_allocVector(VECSXP, 1));
    SET_VECTOR_ELT(keys, 0, key_column);
    Rf_setAttrib(keys, R_NamesSymbol, name);
    SEXP row_names = PROTECT(Rf_allocVector(INTSXP, 2));
    INTEGER(row_names)[0] = NA_INTEGER;
    INTEGER(row_names)[1] = -groups;
    Rf_setAttrib(keys, R_RowNamesSymbol, row_names);
    SEXP df_class = PROTECT(Rf_mkString("data.frame"));
    Rf_setAttrib(keys, R_ClassSymbol, df_class);
    SEXP plan = PROTECT(R_NewEnv(R_EmptyEnv, TRUE, 29));
    Rf_defineVar(Rf_install("rows"), rows, plan);
    Rf_defineVar(Rf_install("keys"), keys, plan);
    Rf_defineVar(Rf_install("order"), R_NilValue, plan);
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(result, 0, plan);
    SET_VECTOR_ELT(result, 2, selected);
    SEXP result_names = PROTECT(Rf_allocVector(STRSXP, 3));
    SET_STRING_ELT(result_names, 0, Rf_mkChar("groups"));
    SET_STRING_ELT(result_names, 1, Rf_mkChar("rows"));
    SET_STRING_ELT(result_names, 2, Rf_mkChar("group_rows"));
    Rf_setAttrib(result, R_NamesSymbol, result_names);
    /* Scratch-only matched allocation/finalizer test point. */
    SEXP hook = Rf_GetOption1(Rf_install(
        "dtatools.probe_grouped_plan_validation_hook"));
    if (Rf_isFunction(hook)) {
        SEXP call = PROTECT(Rf_lang1(hook));
        Rf_eval(call, R_GlobalEnv);
        UNPROTECT(1);
    }
    /* A callback-capable allocation might have edited the key in place.
       The caller can then run the untouched ordinary selection path. */
    if (double_key ?
        (dtatools_grouped_double_values(key, n) != base || !dtatools_probe_plain_public_guard()) :
        (!canonical_long(key) || XLENGTH(key) != n ||
         numeric_base_source(key) != base || R_altrep_data1(base) != initial_data1 ||
         R_altrep_data2(base) != R_NilValue)) {
        UNPROTECT(15); return R_NilValue;
    }
    /* Use chunks below numeric_for_each_span's retained-payload interrupt
       threshold. This final comparison introduces no new R allocation or
       interrupt boundary and preserves exact bits for admitted long keys. */
    if (double_key ? memcmp(REAL(base), REAL(snapshot), (size_t)n * sizeof(double)) != 0 :
        !key_matches_snapshot(key, base, snapshot, n)) {
        UNPROTECT(15); return R_NilValue;
    }
    UNPROTECT(15);
    return result;
}
