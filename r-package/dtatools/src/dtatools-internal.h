/* Internal interface shared by the dtatools native compilation units.
   Everything here crosses a unit boundary: shared descriptors, the Rust
   bridge, module globals created in R_init_dtatools, and the functions one
   unit calls in another. Unit-local helpers stay static in their own file. */
#ifndef DTATOOLS_INTERNAL_H
#define DTATOOLS_INTERNAL_H

#include <R.h>
#include <Rversion.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Altrep.h>
#include <R_ext/Memory.h>
#include <R_ext/GraphicsEngine.h>
#include <R_ext/Utils.h>
#include <R_ext/Visibility.h>
#include <float.h>
#include <limits.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Internal linkage across units, invisible outside the shared object: a
   foreign library exporting the same generic name must not preempt these. */
/* Hidden visibility keeps these ELF/Mach-O symbols out of the dynamic table.
   Windows ignores the attribute and would export every external symbol, so
   dtatools-win.def restricts the DLL export table to R_init_dtatools. */
#define DTATOOLS_INTERNAL attribute_hidden

/* Descriptors shared across units, including the layouts mirrored in Rust. */
enum { OWNED_SHARED, OWNED_EXPOSED, OWNED_NO_NA, OWNED_MAX_WIDTH, OWNED_WIDTH_EXACT, OWNED_FLAGS_SIZE };

typedef struct {
    void *values;
    int kind;
    int temporal;
    int format_version;
    const void *native_owner;
} dtatools_compare_operand;

typedef struct {
    void *values;
    int kind;
    int temporal;
    int format_version;
} dtatools_patch_target;

typedef struct {
    const char *name;
    const double *label_values;
    SEXP label_texts;
    size_t label_count;
} dtatools_arrow_value_label_table;

typedef struct {
    const char *name;
    int kind;
    const char *label;
    const char *format;
    int storage;
    int string_storage;
    int ordered;
    const char *tz;
    const char *units;
    const void *values;
    SEXP strings;
    size_t string_count;
    const void *compact_values;
    int compact_kind;
    int compact_format_version;
    int compact_temporal;
    int value_label_index;
    SEXP dta_metadata;
    int haven_labelled;
    /* Unmaterialized dictionary-string payload, or NULL for eager columns. */
    const void *dictstring;
    const void *compact_owner;
} dtatools_arrow_column;

enum dtatools_arrow_specification_slot {
    DTATOOLS_ARROW_SPECIFICATION_DATASET_LABEL = 0,
    DTATOOLS_ARROW_SPECIFICATION_DTA_METADATA = 1,
    DTATOOLS_ARROW_SPECIFICATION_COLUMNS = 2,
    DTATOOLS_ARROW_SPECIFICATION_VALUE_LABEL_TABLES = 3,
    DTATOOLS_ARROW_SPECIFICATION_OUTPUT_CONTAINER = 4,
    DTATOOLS_ARROW_SPECIFICATION_SLOT_COUNT = 5
};

enum dtatools_arrow_column_slot {
    DTATOOLS_ARROW_COLUMN_NAME = 0,
    DTATOOLS_ARROW_COLUMN_KIND = 1,
    DTATOOLS_ARROW_COLUMN_VALUES = 2,
    DTATOOLS_ARROW_COLUMN_LEVELS = 3,
    DTATOOLS_ARROW_COLUMN_ORDERED = 4,
    DTATOOLS_ARROW_COLUMN_LABEL = 5,
    DTATOOLS_ARROW_COLUMN_FORMAT = 6,
    DTATOOLS_ARROW_COLUMN_STORAGE = 7,
    DTATOOLS_ARROW_COLUMN_TIME_ZONE = 8,
    DTATOOLS_ARROW_COLUMN_UNITS = 9,
    DTATOOLS_ARROW_COLUMN_HAVEN_LABELLED = 10,
    DTATOOLS_ARROW_COLUMN_STRING_STORAGE = 11,
    DTATOOLS_ARROW_COLUMN_VALUE_LABEL_INDEX = 12,
    DTATOOLS_ARROW_COLUMN_DTA_METADATA = 13,
    DTATOOLS_ARROW_COLUMN_SLOT_COUNT = 14
};

enum dtatools_arrow_value_label_table_slot {
    DTATOOLS_ARROW_VALUE_LABEL_TABLE_NAME = 0,
    DTATOOLS_ARROW_VALUE_LABEL_TABLE_VALUES = 1,
    DTATOOLS_ARROW_VALUE_LABEL_TABLE_TEXTS = 2,
    DTATOOLS_ARROW_VALUE_LABEL_TABLE_SLOT_COUNT = 3
};

typedef struct {
    const char *name;
    void *label_values;
    SEXP label_texts;
    size_t label_count;
} dtatools_write_value_label_table;

typedef struct {
    uint32_t *value_ids;
    size_t length;
} dictstring_data;

enum {
    METADATA_AGGREGATE_NO_NA = 1,
    METADATA_AGGREGATE_SUM = 2,
    METADATA_AGGREGATE_MIN = 4,
    METADATA_AGGREGATE_MAX = 8
};

enum {
    NUMERIC_BYTE = 0,
    NUMERIC_INT = 1,
    NUMERIC_LONG = 2,
    NUMERIC_FLOAT = 3,
    NUMERIC_DOUBLE = 4
};

enum {
    WRITE_NUMERIC_CALLBACK = 0,
    WRITE_NUMERIC_INTEGER = 1,
    WRITE_NUMERIC_DOUBLE = 2,
    WRITE_NUMERIC_BYTE = 3,
    WRITE_NUMERIC_INT = 4,
    WRITE_NUMERIC_LONG = 5,
    WRITE_NUMERIC_FLOAT = 6
};

typedef struct {
    const char *name;
    int dta_type;
    const char *format;
    const char *label;
    void *numeric_values;
    SEXP string_values;
    int value_label_index;
    SEXP dta_metadata;
    double numeric_shift;
    double numeric_scale;
    const void *direct_numeric_values;
    int direct_numeric_kind;
    int direct_numeric_format_version;
    int direct_numeric_temporal;
    int direct_numeric_no_na;
    void *direct_string_data;
    const void *direct_numeric_owner;
} dtatools_write_column;

enum dtatools_dta_column_slot {
    DTATOOLS_DTA_COLUMN_NAME = 0,
    DTATOOLS_DTA_COLUMN_TYPE = 1,
    DTATOOLS_DTA_COLUMN_FORMAT = 2,
    DTATOOLS_DTA_COLUMN_LABEL = 3,
    DTATOOLS_DTA_COLUMN_VALUES = 4,
    DTATOOLS_DTA_COLUMN_NUMERIC_SHIFT = 5,
    DTATOOLS_DTA_COLUMN_NUMERIC_SCALE = 6,
    DTATOOLS_DTA_COLUMN_VALUE_LABEL_INDEX = 7,
    DTATOOLS_DTA_COLUMN_DTA_METADATA = 8,
    DTATOOLS_DTA_COLUMN_SLOT_COUNT = 9
};

/* Rust entry points linked from libdtatools_r.a. */
extern SEXP dtatools_metadata_rust(
    const char *, uint32_t, uint32_t, const char *, int, char **
);
extern SEXP dtatools_read_rust(
    const char *, const int *, size_t, int, double, double, int, int,
    const char *, char **
);
extern SEXP dtatools_prepare_dta_rust(const char *, const char *, void **, char **);
extern SEXP dtatools_read_prepared_dta_rust(
    void *, const int *, size_t, int, double, double, int, int, char **
);
extern void dtatools_close_prepared_dta_rust(void *);
extern int dtatools_write_rust(
    const char *, const char *, SEXP, const void *,
    size_t, const void *, size_t, double *, size_t, const char *, char **
);
extern int dtatools_write_path_kind(const char *, char **);
extern void dtatools_free_error(char *);
extern void dtatools_numeric_free(void *);
extern void *dtatools_numeric_alloc(void *, size_t, int, int, size_t);
extern void *dtatools_owned_numeric_from_raw(
    const unsigned char *, size_t, size_t, int, int, int, size_t
);
extern void *dtatools_owned_numeric_clone(const void *);
extern int dtatools_owned_numeric_region(
    const void *, size_t, size_t, const void **, size_t *
);
extern size_t dtatools_owned_numeric_live_bytes(void);
extern size_t dtatools_owned_numeric_live_owners(void);
extern size_t dtatools_owned_numeric_chunks(const void *);
extern int dtatools_numeric_compare(
    int, const dtatools_compare_operand *, const dtatools_compare_operand *,
    double, int, int *, size_t, int
);
extern int dtatools_numeric_compare_patch(
    int, const dtatools_compare_operand *, const dtatools_compare_operand *,
    double, int, const dtatools_compare_operand *, double, int,
    const dtatools_patch_target *, size_t, int,
    size_t *, size_t *, size_t *
);
extern int dtatools_gather_numeric_columns(
    const void *, size_t, const int *, const int *, size_t
);
extern void dtatools_dictstring_free(void *);
extern int dtatools_dictstring_retain(void *);
extern int dtatools_dictstring_bytes(
    void *, uint32_t, const char **, int *
);
extern void *dtatools_dictstring_clone(const void *);
extern void *dtatools_dictstring_gather(
    const void *, const uint32_t *, size_t
);
extern SEXP dtatools_save_arrow_rust(
    const char *, const char *, const char *, SEXP, const dtatools_arrow_column *,
    size_t, const dtatools_arrow_value_label_table *, size_t, size_t,
    const char *, int, int, int *, char **
);
extern SEXP dtatools_datasig_rust(
    const char *, SEXP, const dtatools_arrow_column *, size_t,
    const dtatools_arrow_value_label_table *, size_t, size_t,
    int, int *, char **
);
extern void *dtatools_open_arrow_rust(const char *, char **);
extern void dtatools_close_arrow_rust(void *);
extern SEXP dtatools_read_arrow_rust(
    const void *, const int *, size_t, int, double, double, int, int, int,
    int, int, int, int *, char **
);
extern SEXP dtatools_arrow_metadata_rust(
    const void *, int, int, double, double, int *, char **
);

typedef struct {
    void *values;
    size_t length;
    int kind;
    int temporal;
    int format_version;
    size_t missing_count;
    /* Opaque immutable Rust owner. values is NULL when this is non-NULL. */
    const void *native_owner;
} numeric_data;

/* A retained payload keeps its bytes behind the immutable Rust owner and is
   read span by span; a plain payload keeps them contiguous in values. Every
   ownership decision asks this rather than testing the field. */
static inline int numeric_payload_retained(const numeric_data *data) {
    return data->native_owner != NULL;
}

/* One contiguous plain span of a payload. span->values addresses the bytes,
   span->length counts them, and offset is the span's start relative to the
   region being visited. The span descriptor is valid only during the call. */
typedef void (*numeric_span_visitor)(
    const numeric_data *span, size_t offset, void *context
);

typedef struct {
    SEXP value;
    numeric_data *storage;
    const double *real_values;
    const int *integer_values;
    int type;
} numeric_reader;

typedef struct {
    SEXP values;
    SEXP source;
    SEXP cache;
    SEXP private_cache;
    SEXP scalar;
    dictstring_data *data;
} reference_string_reader;

typedef struct {
    void *data;
    size_t value_count;
    int transferred;
    SEXP result;
} make_dictstring_context;

/* Module globals. ALTREP classes are created in R_init_dtatools; counters
   are read by diagnostics entry points in other units. */
DTATOOLS_INTERNAL extern R_altrep_class_t dtatools_dictstring_class;
DTATOOLS_INTERNAL extern R_altrep_class_t dtatools_numeric_class;
DTATOOLS_INTERNAL extern R_altrep_class_t dtatools_metadata_real_class;
DTATOOLS_INTERNAL extern R_altrep_class_t dtatools_metadata_string_class;
DTATOOLS_INTERNAL extern R_altrep_class_t dtatools_ephemeral_string_class;
DTATOOLS_INTERNAL extern R_altrep_class_t dtatools_mutation_string_class;
DTATOOLS_INTERNAL extern SEXP write_callback_condition_classes;
DTATOOLS_INTERNAL extern int metadata_real_aggregate_mask_enabled;
DTATOOLS_INTERNAL extern int metadata_real_aggregate_mask;
DTATOOLS_INTERNAL extern double owned_numeric_compatibility_bytes;
DTATOOLS_INTERNAL extern R_altrep_class_t column_append_blank_names_class;
DTATOOLS_INTERNAL extern double compact_copy_bytes;
DTATOOLS_INTERNAL extern double mutation_target_copy_bytes;
DTATOOLS_INTERNAL extern double staged_new_bytes;
DTATOOLS_INTERNAL extern double old_journal_bytes;
DTATOOLS_INTERNAL extern double native_scratch_allocated;

/* Ordinary owned atomic backing (owned-columns.h). */
DTATOOLS_INTERNAL int owned_real(SEXP value);
DTATOOLS_INTERNAL int owned_column(SEXP value);
DTATOOLS_INTERNAL R_altrep_class_t owned_class(SEXPTYPE type);
DTATOOLS_INTERNAL SEXP owned_values(SEXP value);
DTATOOLS_INTERNAL int *owned_flags(SEXP value);
DTATOOLS_INTERNAL SEXP owned_adopt(SEXP values);
DTATOOLS_INTERNAL SEXP owned_adopt_real(SEXP values);
DTATOOLS_INTERNAL int known_numeric_classes(SEXP value, int compact);
DTATOOLS_INTERNAL int owned_real_supported(SEXP value);
DTATOOLS_INTERNAL int owned_supported(SEXP value);
DTATOOLS_INTERNAL void owned_scan_strings(SEXP value);
DTATOOLS_INTERNAL SEXP owned_capture(SEXP value);
DTATOOLS_INTERNAL SEXP owned_capture_real(SEXP value);
DTATOOLS_INTERNAL SEXP owned_fork(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_capture_column(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_string_attribute(SEXP value, SEXP name, SEXP replacement);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_string_fits(SEXP value, SEXP width);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_string_width(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_string_fits(SEXP value, SEXP width, SEXP allow_bytes);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_scan_stats(SEXP reset);
DTATOOLS_INTERNAL SEXP C_dtatools_is_owned_double(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_bare(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_plain_snapshot(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_coerce(SEXP value, SEXP logical);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_missing_mask(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_info(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_native_copy_stats(SEXP reset);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_pointer(SEXP value, SEXP writable);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_pointer_write(SEXP pointer, SEXP index, SEXP replacement);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_no_na(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_set_string(SEXP value, SEXP index, SEXP replacement);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_subset(SEXP value, SEXP index);
DTATOOLS_INTERNAL SEXP C_dtatools_gather_owned_discrete(SEXP columns, SEXP locations);
DTATOOLS_INTERNAL int dtatools_adopt_atomic(SEXP values, SEXP *result);
DTATOOLS_INTERNAL SEXP C_dtatools_callback_double(SEXP values, SEXP callback, SEXP element);
DTATOOLS_INTERNAL SEXP C_dtatools_callback_integer(SEXP values, SEXP callback);
DTATOOLS_INTERNAL SEXP C_dtatools_callback_character(SEXP values, SEXP callback);
DTATOOLS_INTERNAL SEXP C_dtatools_callback_integer_after(SEXP values, SEXP callback, SEXP after);
DTATOOLS_INTERNAL SEXP C_dtatools_callback_length(SEXP values, SEXP callback);
DTATOOLS_INTERNAL SEXP C_dtatools_arm_callback_character(SEXP value, SEXP callback);
DTATOOLS_INTERNAL void initialize_owned_columns(DllInfo *dll);

/* Row filter reduction (row-filter.h). */
DTATOOLS_INTERNAL SEXP C_dtatools_filter_start(SEXP size);
DTATOOLS_INTERNAL SEXP C_dtatools_filter_reduce(SEXP state, SEXP rows, SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_filter_finish(SEXP state, SEXP inverse);

/* Compact numeric payload and ALTREP class. */
DTATOOLS_INTERNAL int compact_payload_is_shared(SEXP external);
DTATOOLS_INTERNAL void compact_payload_mark_shared(SEXP external);
DTATOOLS_INTERNAL int compact_payload_is_owned_by(SEXP external, SEXP owner);
DTATOOLS_INTERNAL void compact_payload_claim(SEXP external, SEXP owner);
DTATOOLS_INTERNAL void compact_payload_revoke_claim(SEXP external);
DTATOOLS_INTERNAL SEXP detach_shared_materialized_payload(SEXP value);
DTATOOLS_INTERNAL void numeric_finalize(SEXP external);
DTATOOLS_INTERNAL numeric_data *numeric_read_storage(SEXP value);
DTATOOLS_INTERNAL numeric_data *numeric_storage(SEXP value);
DTATOOLS_INTERNAL R_xlen_t numeric_length(SEXP value);
DTATOOLS_INTERNAL double numeric_missing_value(int offset);
DTATOOLS_INTERNAL int tagged_na_tag_value(double value);
DTATOOLS_INTERNAL int is_tagged_na_value(double value);
DTATOOLS_INTERNAL int dta_expression_string_is_missing(SEXP value);
DTATOOLS_INTERNAL int dta_missing_tag_value(double value);
DTATOOLS_INTERNAL int normalized_dta_missing_tag(SEXP value, const char *argument);
DTATOOLS_INTERNAL void copy_shape_attributes(SEXP target, SEXP source);
DTATOOLS_INTERNAL numeric_data *unmaterialized_numeric_storage(SEXP value);
DTATOOLS_INTERNAL SEXP numeric_base_source(SEXP value);
DTATOOLS_INTERNAL numeric_data *unmaterialized_numeric_read_storage(SEXP value);
DTATOOLS_INTERNAL void numeric_for_each_span(
    const numeric_data *data, size_t start, size_t length,
    numeric_span_visitor visit, void *context
);
DTATOOLS_INTERNAL void numeric_copy_region(
    const numeric_data *data, size_t start, size_t length, void *output
);
DTATOOLS_INTERNAL int materialized_numeric_storage(
    SEXP value, numeric_data *storage
);
DTATOOLS_INTERNAL double numeric_observed_value(double value, int temporal);
DTATOOLS_INTERNAL int numeric_missing_offset_at(
    const numeric_data *data, size_t index
);
DTATOOLS_INTERNAL int numeric_value_is_missing_at(
    const numeric_data *data, size_t index
);
DTATOOLS_INTERNAL SEXP numeric_payload_root(SEXP value);
DTATOOLS_INTERNAL numeric_reader numeric_reader_create(
    SEXP value, R_xlen_t expected_length
);
DTATOOLS_INTERNAL double numeric_reader_at(
    const numeric_reader *reader, R_xlen_t index, int *missing_code
);
DTATOOLS_INTERNAL void record_reference_row_read(void);
DTATOOLS_INTERNAL SEXP C_dtatools_reference_row_reads(SEXP enabled);
DTATOOLS_INTERNAL SEXP C_dtatools_inject_reference_write_interrupt(SEXP enabled);
DTATOOLS_INTERNAL void maybe_inject_reference_write_interrupt(void);
DTATOOLS_INTERNAL SEXP C_dtatools_mutation_rows(SEXP value, SEXP row_count_value);
DTATOOLS_INTERNAL int write_string_utf8_status(SEXP value);
DTATOOLS_INTERNAL int dtatools_write_numeric_region(
    const void *reader_pointer, size_t start, size_t length,
    double *values, int *missing_codes,
    char *error_message, size_t error_capacity
);
DTATOOLS_INTERNAL int dtatools_write_string_region(
    SEXP values, size_t start, size_t length, uint64_t *ids,
    const char **strings, size_t *string_lengths,
    char *error_message, size_t error_capacity
);
DTATOOLS_INTERNAL SEXP C_dtatools_capture_string(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_construct_string(SEXP value, SEXP storage);
DTATOOLS_INTERNAL SEXP C_dtatools_write_string_plan(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_factorize_numeric(
    SEXP value, SEXP seeds, SEXP missing_mode
);
DTATOOLS_INTERNAL double numeric_value(SEXP value, R_xlen_t index);
DTATOOLS_INTERNAL R_xlen_t numeric_region(
    SEXP value, R_xlen_t index, R_xlen_t count, double *output
);
DTATOOLS_INTERNAL void *numeric_dataptr(SEXP value, Rboolean writeable);
DTATOOLS_INTERNAL const void *numeric_dataptr_or_null(SEXP value);
DTATOOLS_INTERNAL int numeric_no_na(SEXP value);
DTATOOLS_INTERNAL SEXP numeric_sum(SEXP value, Rboolean na_rm);
DTATOOLS_INTERNAL SEXP numeric_min(SEXP value, Rboolean na_rm);
DTATOOLS_INTERNAL SEXP numeric_max(SEXP value, Rboolean na_rm);
DTATOOLS_INTERNAL SEXP numeric_from_backing(
    SEXP backing, size_t length, int kind, int temporal,
    int format_version, size_t missing_count
);
DTATOOLS_INTERNAL SEXP numeric_compact_copy(const numeric_data *data);
DTATOOLS_INTERNAL SEXP numeric_handle_copy(SEXP source);
DTATOOLS_INTERNAL SEXP numeric_serialized_state(SEXP value);
DTATOOLS_INTERNAL SEXP numeric_unserialize(SEXP class, SEXP state);
DTATOOLS_INTERNAL SEXP numeric_duplicate(SEXP value, Rboolean deep);
DTATOOLS_INTERNAL void write_numeric_system_missing_raw(
    unsigned char *output, R_xlen_t index, int kind, int format_version
);
DTATOOLS_INTERNAL SEXP numeric_extract_subset(SEXP value, SEXP index, SEXP call);
DTATOOLS_INTERNAL SEXP C_dtatools_gather_numeric(
    SEXP x, SEXP y, SEXP x_rows, SEXP y_rows
);
DTATOOLS_INTERNAL SEXP C_dtatools_gather_numeric_columns(
    SEXP x, SEXP y, SEXP x_rows, SEXP y_rows
);
DTATOOLS_INTERNAL int dtatools_make_numeric(
    void *data, SEXP backing, int *transferred, SEXP *result
);
DTATOOLS_INTERNAL size_t numeric_kind_width(int kind);
DTATOOLS_INTERNAL void write_numeric_missing(
    unsigned char *output, R_xlen_t index, int kind, int offset
);
DTATOOLS_INTERNAL void write_numeric_observed(
    unsigned char *output, R_xlen_t index, int kind, double value
);
DTATOOLS_INTERNAL SEXP C_dtatools_construct_numeric(
    SEXP value, SEXP kind_value, SEXP temporal_value
);
DTATOOLS_INTERNAL SEXP C_dtatools_construct_numeric_trusted(
    SEXP value, SEXP missing_codes, SEXP kind_value, SEXP temporal_value
);

/* Dictionary-backed strings. */
DTATOOLS_INTERNAL void dictstring_finalize(SEXP external);
DTATOOLS_INTERNAL dictstring_data *dictstring_storage(SEXP value);
DTATOOLS_INTERNAL SEXP dictstring_cache(SEXP value);
DTATOOLS_INTERNAL SEXP unmaterialized_dictstring_source(SEXP value);
DTATOOLS_INTERNAL SEXP dictstring_read_root(SEXP value);
DTATOOLS_INTERNAL SEXP reference_string_reader_private_cache(
    SEXP values, R_xlen_t read_count
);
DTATOOLS_INTERNAL reference_string_reader reference_string_reader_create(
    SEXP values, SEXP private_cache
);
DTATOOLS_INTERNAL SEXP reference_string_reader_at(
    const reference_string_reader *reader, R_xlen_t index
);
DTATOOLS_INTERNAL int reference_string_reader_is_missing_at(
    const reference_string_reader *reader, R_xlen_t index
);
DTATOOLS_INTERNAL R_xlen_t dictstring_length(SEXP value);
DTATOOLS_INTERNAL SEXP dictstring_value(SEXP value, R_xlen_t index);
DTATOOLS_INTERNAL SEXP dictstring_patch_values(SEXP value, SEXP private_cache);
DTATOOLS_INTERNAL SEXP dictstring_materialize_for_patch(SEXP value, SEXP private_cache);
DTATOOLS_INTERNAL void *dictstring_dataptr(SEXP value, Rboolean writeable);
DTATOOLS_INTERNAL const void *dictstring_dataptr_or_null(SEXP value);
DTATOOLS_INTERNAL void dictstring_set_elt(SEXP value, R_xlen_t index, SEXP replacement);
DTATOOLS_INTERNAL int dictstring_no_na(SEXP value);
DTATOOLS_INTERNAL SEXP dictstring_duplicate(SEXP value, Rboolean deep);
DTATOOLS_INTERNAL SEXP dictstring_compact_copy(SEXP value);
DTATOOLS_INTERNAL SEXP dictstring_extract_subset(SEXP value, SEXP index, SEXP call);
DTATOOLS_INTERNAL SEXP C_dtatools_dictstring_subset(SEXP value, SEXP index);
DTATOOLS_INTERNAL SEXP C_dtatools_deep_copy_value(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_reference_contents(SEXP value);

/* R-side helpers called by Rust. */
DTATOOLS_INTERNAL int dtatools_make_dictstring(
    void *data, size_t value_count, int *transferred, SEXP *result
);
DTATOOLS_INTERNAL int dtatools_alloc_vector(int type, R_xlen_t length, SEXP *result);
DTATOOLS_INTERNAL size_t dtatools_xlength(SEXP value);
DTATOOLS_INTERNAL int dtatools_is_null(SEXP value);
DTATOOLS_INTERNAL int dtatools_preserve_object(SEXP object);
DTATOOLS_INTERNAL void dtatools_release_object(SEXP object);
DTATOOLS_INTERNAL int dtatools_make_char(
    const char *value, int length, int encoding, SEXP *result
);
DTATOOLS_INTERNAL int dtatools_install(const char *name, SEXP *result);
DTATOOLS_INTERNAL int dtatools_set_attrib(SEXP object, SEXP name, SEXP value);
DTATOOLS_INTERNAL int dtatools_check_interrupt(void);
DTATOOLS_INTERNAL void fail_from_rust(char *message);
DTATOOLS_INTERNAL const char *optional_encoding(SEXP encoding);

/* DTA and Arrow read/write marshalling. */
DTATOOLS_INTERNAL SEXP C_dtatools_metadata(
    SEXP path, SEXP encoding, SEXP column_start, SEXP column_count,
    SEXP include_value_labels
);
DTATOOLS_INTERNAL SEXP C_dtatools_read(
    SEXP path, SEXP columns, SEXP skip, SEXP n_max, SEXP threads,
    SEXP numeric_altrep, SEXP encoding
);
DTATOOLS_INTERNAL SEXP C_dtatools_prepare_dta_selection(SEXP path, SEXP encoding);
DTATOOLS_INTERNAL SEXP C_dtatools_read_prepared_dta(
    SEXP prepared, SEXP columns, SEXP skip, SEXP n_max, SEXP threads,
    SEXP numeric_altrep
);
DTATOOLS_INTERNAL SEXP C_dtatools_close_prepared_dta(SEXP prepared);
DTATOOLS_INTERNAL SEXP C_dtatools_has_bytes_encoding(SEXP values);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_utf8_ready(SEXP value);
DTATOOLS_INTERNAL const char *dtatools_string_elt_utf8(SEXP values, size_t index);
DTATOOLS_INTERNAL SEXP C_dtatools_write_path_kind(SEXP path);
DTATOOLS_INTERNAL SEXP C_dtatools_write(SEXP specification, SEXP path);
DTATOOLS_INTERNAL SEXP C_dtatools_save_arrow(
    SEXP specification, SEXP path, SEXP compression, SEXP threads,
    SEXP checksums
);
DTATOOLS_INTERNAL SEXP C_dtatools_datasig(SEXP specification, SEXP threads);
DTATOOLS_INTERNAL SEXP C_dtatools_open_arrow(SEXP path);
DTATOOLS_INTERNAL SEXP C_dtatools_close_arrow(SEXP snapshot);
DTATOOLS_INTERNAL SEXP C_dtatools_read_arrow(
    SEXP snapshot, SEXP columns, SEXP skip, SEXP n_max, SEXP verify, SEXP profile,
    SEXP numeric_altrep, SEXP threads, SEXP datasig, SEXP count_source_rows
);
DTATOOLS_INTERNAL SEXP C_dtatools_arrow_metadata(
    SEXP snapshot, SEXP profile, SEXP scan_ambiguous_int32,
    SEXP skip, SEXP n_max
);

/* Metadata proxies and mutation views. */
DTATOOLS_INTERNAL R_xlen_t mutation_string_length(SEXP value);
DTATOOLS_INTERNAL SEXP mutation_string_elt(SEXP value, R_xlen_t i);
DTATOOLS_INTERNAL SEXP mutation_string_duplicate(SEXP value, Rboolean deep);
DTATOOLS_INTERNAL void *mutation_string_dataptr(SEXP value, Rboolean writable);
DTATOOLS_INTERNAL const void *mutation_string_dataptr_or_null(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_mutation_prototype(SEXP value);
DTATOOLS_INTERNAL R_xlen_t ephemeral_string_length(SEXP value);
DTATOOLS_INTERNAL SEXP ephemeral_string_value(SEXP value, R_xlen_t index);
DTATOOLS_INTERNAL SEXP C_dtatools_ephemeral_altstring(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_is_numeric_altrep(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_is_altrep(SEXP value);
DTATOOLS_INTERNAL SEXP metadata_proxy_state(SEXP value);
DTATOOLS_INTERNAL SEXP metadata_proxy_source(SEXP value);
DTATOOLS_INTERNAL SEXP metadata_proxy_owner(SEXP value);
DTATOOLS_INTERNAL void metadata_proxy_set_state(
    SEXP value, SEXP source, SEXP owner
);
DTATOOLS_INTERNAL R_xlen_t metadata_proxy_length(SEXP value);
DTATOOLS_INTERNAL double metadata_real_value(SEXP value, R_xlen_t index);
DTATOOLS_INTERNAL R_xlen_t metadata_real_region(
    SEXP value, R_xlen_t index, R_xlen_t count, double *output
);
DTATOOLS_INTERNAL void *metadata_real_dataptr(SEXP value, Rboolean writeable);
DTATOOLS_INTERNAL const void *metadata_real_dataptr_or_null(SEXP value);
DTATOOLS_INTERNAL SEXP metadata_real_extract_subset(
    SEXP value, SEXP index, SEXP call
);
DTATOOLS_INTERNAL int metadata_real_no_na(SEXP value);
DTATOOLS_INTERNAL SEXP metadata_real_sum(SEXP value, Rboolean na_rm);
DTATOOLS_INTERNAL SEXP metadata_real_min(SEXP value, Rboolean na_rm);
DTATOOLS_INTERNAL SEXP metadata_real_max(SEXP value, Rboolean na_rm);
DTATOOLS_INTERNAL SEXP metadata_string_value(SEXP value, R_xlen_t index);
DTATOOLS_INTERNAL SEXP metadata_string_materialize_for_patch(
    SEXP value, SEXP dictionary, SEXP private_cache
);
DTATOOLS_INTERNAL void *metadata_string_dataptr(SEXP value, Rboolean writeable);
DTATOOLS_INTERNAL const void *metadata_string_dataptr_or_null(SEXP value);
DTATOOLS_INTERNAL void metadata_string_set_elt(
    SEXP value, R_xlen_t index, SEXP replacement
);
DTATOOLS_INTERNAL SEXP metadata_string_extract_subset(
    SEXP value, SEXP index, SEXP call
);
DTATOOLS_INTERNAL SEXP metadata_proxy(
    SEXP value, R_altrep_class_t proxy_class, int isolate
);
DTATOOLS_INTERNAL SEXP metadata_real_duplicate(SEXP value, Rboolean deep);
DTATOOLS_INTERNAL SEXP metadata_string_duplicate(SEXP value, Rboolean deep);
DTATOOLS_INTERNAL SEXP C_dtatools_metadata_copy(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_metadata_view(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_mutation_views(SEXP data);
DTATOOLS_INTERNAL SEXP C_dtatools_release_mutation_views(SEXP columns);
DTATOOLS_INTERNAL SEXP C_dtatools_expose_mutation_column(SEXP value);
DTATOOLS_INTERNAL SEXP mutation_physical_names(SEXP data);
DTATOOLS_INTERNAL SEXP C_dtatools_column_names_info(SEXP data);
DTATOOLS_INTERNAL SEXP C_dtatools_mutation_shape(SEXP data, SEXP row_count);
DTATOOLS_INTERNAL SEXP C_dtatools_mutation_name_location(SEXP data, SEXP name);
DTATOOLS_INTERNAL SEXP C_dtatools_physical_column_count(SEXP data);
DTATOOLS_INTERNAL SEXP C_dtatools_mark_reference_data(
    SEXP data, SEXP state, SEXP classes
);
DTATOOLS_INTERNAL SEXP C_dtatools_reference_state_valid(SEXP data);
DTATOOLS_INTERNAL SEXP C_dtatools_set_attribute(SEXP object, SEXP name, SEXP value);

/* Reference table transactions. */
DTATOOLS_INTERNAL SEXP C_dtatools_replacement_fits(SEXP values, SEXP rows, SEXP row_mode, SEXP kind_value);
DTATOOLS_INTERNAL SEXP C_dtatools_mutation_info(SEXP data, SEXP location);
DTATOOLS_INTERNAL SEXP C_dtatools_patch_vector(
    SEXP target, SEXP rows, SEXP replacement
);
DTATOOLS_INTERNAL SEXP C_dtatools_set_data_column(SEXP data, SEXP location, SEXP column);
DTATOOLS_INTERNAL SEXP C_dtatools_patch_slot(SEXP data, SEXP location, SEXP rows,
                                SEXP replacement, SEXP entry_shared);
DTATOOLS_INTERNAL SEXP C_dtatools_shared_columns(SEXP columns);
DTATOOLS_INTERNAL SEXP C_dtatools_column_capacity(SEXP x);
DTATOOLS_INTERNAL SEXP C_dtatools_reserve_column_capacity(SEXP x, SEXP capacity_value);
DTATOOLS_INTERNAL R_xlen_t column_append_blank_names_length(SEXP value);
DTATOOLS_INTERNAL SEXP column_append_blank_names_elt(SEXP value, R_xlen_t index);
DTATOOLS_INTERNAL void *column_append_blank_names_dataptr(SEXP value, Rboolean writable);
DTATOOLS_INTERNAL const void *column_append_blank_names_dataptr_or_null(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_inject_column_append_failure(SEXP stage, SEXP interrupt);
DTATOOLS_INTERNAL SEXP C_dtatools_append_data_column(SEXP data, SEXP name, SEXP column);
DTATOOLS_INTERNAL SEXP C_dtatools_can_select_data_columns(SEXP data, SEXP length);
DTATOOLS_INTERNAL SEXP C_dtatools_select_data_columns(
    SEXP data, SEXP columns, SEXP names, SEXP state,
    SEXP base_classes, SEXP reference_classes
);
DTATOOLS_INTERNAL SEXP C_dtatools_inject_generation_interrupt(SEXP mode);
DTATOOLS_INTERNAL int string_declared_width(SEXP declared, const char *message);
DTATOOLS_INTERNAL size_t reference_string_width(SEXP value, const char *operation);
DTATOOLS_INTERNAL SEXP C_dtatools_generate_character(
    SEXP values, SEXP rows, SEXP row_count_value,
    SEXP declared, SEXP attributes
);
DTATOOLS_INTERNAL SEXP C_dtatools_generate_numeric(
    SEXP values, SEXP rows, SEXP row_count_value,
    SEXP kind_value, SEXP temporal_value, SEXP attributes
);
DTATOOLS_INTERNAL SEXP C_dtatools_is_unmaterialized_numeric_altrep(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_is_materialized_numeric_altrep(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_is_unmaterialized_dictstring(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_dictstring_cached_count(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_dictstring_max_width(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_numeric_storage_matches(
    SEXP value, SEXP kind_value, SEXP temporal_value
);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_numeric_freeze(SEXP value, SEXP chunk_rows_value);
DTATOOLS_INTERNAL SEXP C_dtatools_owned_numeric_info(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_force_altrep_materialization(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_mutate_first_numeric_altrep(SEXP value, SEXP replacement);
DTATOOLS_INTERNAL SEXP C_dtatools_mutate_first_dictstring_altrep(
    SEXP value, SEXP replacement
);
DTATOOLS_INTERNAL SEXP C_dtatools_metadata_proxy_depth(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_metadata_proxy_aggregate_mask(SEXP enabled);
DTATOOLS_INTERNAL SEXP C_dtatools_has_tagged_na(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_tagged_missing(SEXP tag);
DTATOOLS_INTERNAL SEXP C_dtatools_is_tagged_missing(SEXP value, SEXP tag);
DTATOOLS_INTERNAL SEXP C_dtatools_is_missing(SEXP values);
DTATOOLS_INTERNAL SEXP C_dtatools_missing_tag(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_fused_compare_patch(
    SEXP target, SEXP op_value, SEXP x, SEXP y, SEXP scalar,
    SEXP replacement, SEXP replacement_scalar, SEXP threads_value
);
DTATOOLS_INTERNAL SEXP C_dtatools_fused_patch_slot(
    SEXP data, SEXP location, SEXP entry_shared, SEXP op, SEXP left,
    SEXP right, SEXP scalar, SEXP replacement, SEXP replacement_scalar, SEXP threads
);
DTATOOLS_INTERNAL SEXP C_dtatools_dta_compare(
    SEXP op_value, SEXP x, SEXP y, SEXP scalar, SEXP threads_value
);
DTATOOLS_INTERNAL SEXP C_dtatools_missing_codes(SEXP value);
DTATOOLS_INTERNAL SEXP C_dtatools_replace_reference_columns(
    SEXP data, SEXP store, SEXP locations, SEXP names, SEXP columns
);

/* egen summaries and groups. */
DTATOOLS_INTERNAL SEXP C_dtatools_egen_summary(SEXP input, SEXP operation, SEXP missing,
                           SEXP allow_nan);
DTATOOLS_INTERNAL SEXP dtatools_egen_group(SEXP columns, SEXP include_missing,
                               SEXP allow_nan);
DTATOOLS_INTERNAL SEXP C_dtatools_egen_rows(SEXP columns, SEXP operation, SEXP missing,
                        SEXP allow_nan);

/* Registration. */
DTATOOLS_INTERNAL int dtatools_owned_numeric_gc(void);

#endif /* DTATOOLS_INTERNAL_H */
