#include "dtatools-internal.h"

/* Finite doubles use their bits, with one representation for zero. Canonical
   missing codes occupy NaN bit patterns, which cannot collide with a finite
   value. The raw key vector snapshots each argument before R forces the next. */
static uint64_t identity_key(double value, int missing_code) {
    if (missing_code >= 0)
        return UINT64_C(0x7ff8000000000000) | (uint64_t) missing_code;
    uint64_t key = 0;
    if (value != 0.0) memcpy(&key, &value, sizeof(key));
    return key;
}

static void identity_store(unsigned char *keys, R_xlen_t index, uint64_t key) {
    memcpy(keys + (size_t) index * sizeof(key), &key, sizeof(key));
}

static uint64_t identity_load(const unsigned char *keys, R_xlen_t index) {
    uint64_t key;
    memcpy(&key, keys + (size_t) index * sizeof(key), sizeof(key));
    return key;
}

static void identity_error(const char *argument, int invalid, int infinite) {
    if (invalid) {
        Rf_errorcall(R_NilValue, "`%s` contains a noncanonical NaN; use `NA_real_` for `.`, "
                 "or `tagged_missing()` for `.a` through `.z`", argument);
    }
    if (infinite) {
        Rf_errorcall(R_NilValue, "`%s` contains an infinite value, which has no Stata identity",
                 argument);
    }
}

SEXP C_dtatools_numeric_identity_key(SEXP value, SEXP argument) {
    /* A foreign ALTREP may expose a pointer while its element method still
       runs observable callbacks. Keep its original R reads and snapshot. */
    if (ALTREP(value) && !owned_real(value) &&
        !R_altrep_inherits(value, dtatools_numeric_class) &&
        unmaterialized_numeric_read_storage(value) == NULL &&
        !(R_altrep_inherits(value, dtatools_metadata_real_class) &&
          R_altrep_data2(value) != R_NilValue)) return R_NilValue;
    R_xlen_t length = XLENGTH(value);
    if (length > R_XLEN_T_MAX / (R_xlen_t) sizeof(uint64_t))
        Rf_error("numeric identity key buffer is too large");
    if (TYPEOF(argument) != STRSXP || XLENGTH(argument) != 1)
        Rf_error("invalid numeric identity argument name");

    /* Unknown S3 classes keep the complete R conversion and validation path.
       Pack only its finished character keys, without rereading the operand. */
    if (TYPEOF(value) == STRSXP) {
        SEXP result = PROTECT(Rf_allocVector(
            RAWSXP, length * (R_xlen_t) sizeof(uint64_t)
        ));
        unsigned char *output = RAW(result);
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            const char *key = CHAR(STRING_ELT(value, index));
            char *end;
            uint64_t packed;
            if (key[0] == 'n' && key[1] == ':') {
                double observed = strtod(key + 2, &end);
                if (end == key + 2 || *end != '\0' || !R_FINITE(observed))
                    Rf_error("invalid numeric identity key");
                packed = identity_key(observed, -1);
            } else if (key[0] == 'm' && key[1] == ':') {
                long missing_code = strtol(key + 2, &end, 10);
                if (end == key + 2 || *end != '\0' ||
                    (missing_code != 0 &&
                     (missing_code < 'a' || missing_code > 'z')))
                    Rf_error("invalid numeric identity key");
                packed = identity_key(0, (int) missing_code);
            } else {
                Rf_error("invalid numeric identity key");
            }
            identity_store(output, index, packed);
        }
        UNPROTECT(1);
        return result;
    }

    numeric_data storage;
    SEXP root = PROTECT(numeric_missing_mask_capture(value, &storage));
    numeric_reader reader;
    int protected_count = 1;
    if (root != R_NilValue) {
        reader = (numeric_reader) {value, &storage, NULL, NULL, REALSXP};
    } else {
        PROTECT(numeric_payload_root(value));
        protected_count++;
        reader = numeric_reader_create(value, length);
    }
    SEXP result = PROTECT(Rf_allocVector(
        RAWSXP, length * (R_xlen_t) sizeof(uint64_t)
    ));
    protected_count++;
    unsigned char *output = RAW(result);
    double values[1024];
    int codes[1024];
    int invalid = 0, infinite = 0;
    for (R_xlen_t start = 0; start < length;) {
        R_xlen_t count = length - start;
        if (count > 1024) count = 1024;
        R_CheckUserInterrupt();
        numeric_reader_region(&reader, start, count, values, codes);
        for (R_xlen_t offset = 0; offset < count; offset++) {
            int code = codes[offset];
            invalid |= code >= 0 && code != 0 && (code < 'a' || code > 'z');
            infinite |= code < 0 && !R_FINITE(values[offset]);
            identity_store(output, start + offset,
                           identity_key(values[offset], code));
        }
        start += count;
    }
    identity_error(CHAR(STRING_ELT(argument, 0)), invalid, infinite);
    UNPROTECT(protected_count);
    return result;
}

static R_xlen_t identity_length(SEXP keys) {
    if (TYPEOF(keys) != RAWSXP || XLENGTH(keys) % sizeof(uint64_t) != 0)
        Rf_error("invalid numeric identity key buffer");
    return XLENGTH(keys) / (R_xlen_t) sizeof(uint64_t);
}

static uint64_t identity_hash(uint64_t key) {
    key ^= key >> 30;
    key *= UINT64_C(0xbf58476d1ce4e5b9);
    key ^= key >> 27;
    key *= UINT64_C(0x94d049bb133111eb);
    return key ^ (key >> 31);
}

typedef struct {
    const unsigned char *keys;
    R_xlen_t *slots;
    size_t mask;
} identity_table;

static identity_table identity_table_create(SEXP keys, R_xlen_t length) {
    size_t capacity = 2;
    if ((uint64_t) length > SIZE_MAX / (2 * sizeof(R_xlen_t)))
        Rf_error("numeric identity hash table is too large");
    size_t required = (size_t) length * 2;
    while (capacity < required) {
        if (capacity > SIZE_MAX / (2 * sizeof(R_xlen_t)))
            Rf_error("numeric identity hash table is too large");
        capacity *= 2;
    }
    R_xlen_t *slots = (R_xlen_t *) R_alloc(capacity, sizeof(R_xlen_t));
    memset(slots, 0, capacity * sizeof(R_xlen_t));
    return (identity_table) {RAW(keys), slots, capacity - 1};
}

static R_xlen_t *identity_slot(identity_table *table, uint64_t key) {
    size_t slot = (size_t) identity_hash(key) & table->mask;
    while (table->slots[slot] != 0) {
        R_xlen_t index = table->slots[slot];
        if (index < 0) index = -index;
        if (identity_load(table->keys, index - 1) == key) break;
        slot = (slot + 1) & table->mask;
    }
    return &table->slots[slot];
}

SEXP C_dtatools_numeric_match_keys(
    SEXP x, SEXP table_keys, SEXP nomatch, SEXP incomparables
) {
    R_xlen_t length = identity_length(x);
    R_xlen_t table_length = identity_length(table_keys);
    R_xlen_t incomparable_length = incomparables == R_NilValue
        ? 0 : identity_length(incomparables);
    int unmatched = Rf_asInteger(nomatch);
    if (table_length > INT_MAX)
        Rf_error("long vectors are not supported in `table`");
    SEXP result = PROTECT(Rf_allocVector(INTSXP, length));
    int *output = INTEGER(result);
    if (table_length == 0) {
        for (R_xlen_t index = 0; index < length; index++) {
            if ((index & 16383) == 0) R_CheckUserInterrupt();
            output[index] = unmatched;
        }
        UNPROTECT(1);
        return result;
    }
    identity_table table = identity_table_create(table_keys, table_length);
    const unsigned char *x_values = RAW(x);
    const unsigned char *table_values = RAW(table_keys);
    const unsigned char *incomparable_values = incomparables == R_NilValue
        ? NULL : RAW(incomparables);
    for (R_xlen_t index = 0; index < table_length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t *slot = identity_slot(&table, identity_load(table_values, index));
        if (*slot == 0) *slot = index + 1;
    }
    for (R_xlen_t index = 0; index < incomparable_length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t *slot = identity_slot(&table, identity_load(incomparable_values, index));
        if (*slot > 0) *slot = -*slot;
    }
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t location = *identity_slot(&table, identity_load(x_values, index));
        output[index] = location > 0 ? (int) location : unmatched;
    }
    UNPROTECT(1);
    return result;
}

SEXP C_dtatools_numeric_duplicated_keys(SEXP keys) {
    R_xlen_t length = identity_length(keys);
    SEXP result = PROTECT(Rf_allocVector(LGLSXP, length));
    identity_table table = identity_table_create(keys, length);
    const unsigned char *values = RAW(keys);
    int *output = LOGICAL(result);
    for (R_xlen_t index = 0; index < length; index++) {
        if ((index & 16383) == 0) R_CheckUserInterrupt();
        R_xlen_t *slot = identity_slot(&table, identity_load(values, index));
        output[index] = *slot != 0;
        if (*slot == 0) *slot = index + 1;
    }
    UNPROTECT(1);
    return result;
}
