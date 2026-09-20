#include "dtatools-internal.h"

#include "owned-columns.h"
#include "row-filter.h"


static void owned_numeric_gc_call(void *unused) {
    (void) unused;
    R_gc();
}

/* Called by the Arrow reader on the R thread before native
   preparation. Contain any long jump from user finalizers inside C. */
int dtatools_owned_numeric_gc(void) {
    return R_ToplevelExec(owned_numeric_gc_call, NULL);
}









R_altrep_class_t dtatools_dictstring_class;
R_altrep_class_t dtatools_numeric_class;
R_altrep_class_t dtatools_metadata_real_class;
R_altrep_class_t dtatools_metadata_string_class;
R_altrep_class_t dtatools_ephemeral_string_class;
R_altrep_class_t dtatools_mutation_string_class;
SEXP write_callback_condition_classes;
int metadata_real_aggregate_mask_enabled;
int metadata_real_aggregate_mask;




double owned_numeric_compatibility_bytes = 0.0;

#include "egen-values.h"
#include "egen-groups.h"

static const R_CallMethodDef CallEntries[] = {
    {"C_dtatools_owned_numeric_freeze", (DL_FUNC) &C_dtatools_owned_numeric_freeze, 2},
    {"C_dtatools_owned_numeric_info", (DL_FUNC) &C_dtatools_owned_numeric_info, 1},
    {"C_dtatools_native_copy_stats", (DL_FUNC) &C_dtatools_native_copy_stats, 1},
    {"C_dtatools_mutation_views", (DL_FUNC) &C_dtatools_mutation_views, 1},
    {"C_dtatools_mutation_column_view",
     (DL_FUNC) &C_dtatools_mutation_column_view, 2},
    {"C_dtatools_mutation_column_current",
     (DL_FUNC) &C_dtatools_mutation_column_current, 3},
    {"C_dtatools_replacement_fits", (DL_FUNC) &C_dtatools_replacement_fits, 4},
    {"C_dtatools_expose_mutation_column", (DL_FUNC) &C_dtatools_expose_mutation_column, 1},
    {"C_dtatools_release_mutation_views", (DL_FUNC) &C_dtatools_release_mutation_views, 1},
    {"C_dtatools_mutation_info", (DL_FUNC) &C_dtatools_mutation_info, 2},
    {"C_dtatools_is_owned_double", (DL_FUNC) &C_dtatools_is_owned_double, 1},
    {"C_dtatools_settle_foreign_altrep",
     (DL_FUNC) &C_dtatools_settle_foreign_altrep, 1},
    {"C_dtatools_owned_plain_snapshot", (DL_FUNC) &C_dtatools_owned_plain_snapshot, 1},
    {"C_dtatools_owned_coerce", (DL_FUNC) &C_dtatools_owned_coerce, 2},
    {"C_dtatools_owned_missing_mask", (DL_FUNC) &C_dtatools_owned_missing_mask, 1},
    {"C_dtatools_owned_bare", (DL_FUNC) &C_dtatools_owned_bare, 1},
    {"C_dtatools_mutation_prototype", (DL_FUNC) &C_dtatools_mutation_prototype, 1},
    {"C_dtatools_column_names_info", (DL_FUNC) &C_dtatools_column_names_info, 1},
    {"C_dtatools_mutation_shape", (DL_FUNC) &C_dtatools_mutation_shape, 2},
    {"C_dtatools_fast_shape", (DL_FUNC) &C_dtatools_fast_shape, 1},
    {"C_dtatools_set_values_fast", (DL_FUNC) &C_dtatools_set_values_fast, 2},
    {"C_dtatools_patch_scalar", (DL_FUNC) &C_dtatools_patch_scalar, 5},
    {"C_dtatools_generate_scalar", (DL_FUNC) &C_dtatools_generate_scalar, 4},
    {"C_dtatools_mutation_name_location", (DL_FUNC) &C_dtatools_mutation_name_location, 2},
    {"C_dtatools_physical_column_count", (DL_FUNC) &C_dtatools_physical_column_count, 1},
    {"C_dtatools_callback_double", (DL_FUNC) &C_dtatools_callback_double, 3},
    {"C_dtatools_arm_callback_character", (DL_FUNC) &C_dtatools_arm_callback_character, 2},
    {"C_dtatools_callback_character", (DL_FUNC) &C_dtatools_callback_character, 2},
    {"C_dtatools_callback_integer", (DL_FUNC) &C_dtatools_callback_integer, 2},
    {"C_dtatools_callback_integer_after", (DL_FUNC) &C_dtatools_callback_integer_after, 3},
    {"C_dtatools_owned_no_na", (DL_FUNC) &C_dtatools_owned_no_na, 1},
    {"C_dtatools_patch_slot", (DL_FUNC) &C_dtatools_patch_slot, 5},
    {"C_dtatools_fused_patch_slot", (DL_FUNC) &C_dtatools_fused_patch_slot, 10},
    {"C_dtatools_capture_column", (DL_FUNC) &C_dtatools_capture_column, 1},
    {"C_dtatools_owned_string_fits", (DL_FUNC) &C_dtatools_owned_string_fits, 2},
    {"C_dtatools_owned_string_width", (DL_FUNC) &C_dtatools_owned_string_width, 1},
    {"C_dtatools_string_fits", (DL_FUNC) &C_dtatools_string_fits, 3},
    {"C_dtatools_owned_string_attribute", (DL_FUNC) &C_dtatools_owned_string_attribute, 3},
    {"C_dtatools_capture_string", (DL_FUNC) &C_dtatools_capture_string, 1},
    {"C_dtatools_construct_string", (DL_FUNC) &C_dtatools_construct_string, 2},
    {"C_dtatools_owned_utf8_ready", (DL_FUNC) &C_dtatools_owned_utf8_ready, 1},
    {"C_dtatools_owned_scan_stats", (DL_FUNC) &C_dtatools_owned_scan_stats, 1},
    {"C_dtatools_callback_length", (DL_FUNC) &C_dtatools_callback_length, 2},
    {"C_dtatools_dictstring_subset", (DL_FUNC) &C_dtatools_dictstring_subset, 2},
    {"C_dtatools_owned_subset", (DL_FUNC) &C_dtatools_owned_subset, 2},
    {"C_dtatools_gather_owned_discrete", (DL_FUNC) &C_dtatools_gather_owned_discrete, 2},
    {"C_dtatools_owned_set_string", (DL_FUNC) &C_dtatools_owned_set_string, 3},
    {"C_dtatools_owned_info", (DL_FUNC) &C_dtatools_owned_info, 1},
    {"C_dtatools_owned_pointer", (DL_FUNC) &C_dtatools_owned_pointer, 2},
    {"C_dtatools_owned_pointer_write", (DL_FUNC) &C_dtatools_owned_pointer_write, 3},
    {"C_dtatools_egen_group", (DL_FUNC) &dtatools_egen_group, 3},
    {"C_dtatools_egen_summary", (DL_FUNC) &C_dtatools_egen_summary, 4},
    {"C_dtatools_egen_rows", (DL_FUNC) &C_dtatools_egen_rows, 4},
    {"C_dtatools_metadata", (DL_FUNC) &C_dtatools_metadata, 5},
    {"C_dtatools_read", (DL_FUNC) &C_dtatools_read, 7},
    {"C_dtatools_prepare_dta_selection", (DL_FUNC) &C_dtatools_prepare_dta_selection, 2},
    {"C_dtatools_read_prepared_dta", (DL_FUNC) &C_dtatools_read_prepared_dta, 6},
    {"C_dtatools_close_prepared_dta", (DL_FUNC) &C_dtatools_close_prepared_dta, 1},
    {"C_dtatools_write", (DL_FUNC) &C_dtatools_write, 2},
    {"C_dtatools_save_arrow", (DL_FUNC) &C_dtatools_save_arrow, 5},
    {"C_dtatools_has_bytes_encoding",
     (DL_FUNC) &C_dtatools_has_bytes_encoding, 1},
    {"C_dtatools_datasig", (DL_FUNC) &C_dtatools_datasig, 2},
    {"C_dtatools_open_arrow", (DL_FUNC) &C_dtatools_open_arrow, 1},
    {"C_dtatools_close_arrow", (DL_FUNC) &C_dtatools_close_arrow, 1},
    {"C_dtatools_read_arrow", (DL_FUNC) &C_dtatools_read_arrow, 10},
    {"C_dtatools_arrow_metadata",
     (DL_FUNC) &C_dtatools_arrow_metadata, 5},
    {"C_dtatools_write_path_kind",
     (DL_FUNC) &C_dtatools_write_path_kind, 1},
    {"C_dtatools_write_string_plan",
     (DL_FUNC) &C_dtatools_write_string_plan, 1},
    {"C_dtatools_ephemeral_altstring",
     (DL_FUNC) &C_dtatools_ephemeral_altstring, 1},
    {"C_dtatools_construct_numeric",
     (DL_FUNC) &C_dtatools_construct_numeric, 3},
    {"C_dtatools_construct_numeric_trusted",
     (DL_FUNC) &C_dtatools_construct_numeric_trusted, 4},
    {"C_dtatools_gather_numeric",
     (DL_FUNC) &C_dtatools_gather_numeric, 4},
    {"C_dtatools_gather_numeric_columns",
     (DL_FUNC) &C_dtatools_gather_numeric_columns, 4},
    {"C_dtatools_replace_reference_columns",
     (DL_FUNC) &C_dtatools_replace_reference_columns, 5},
    {"C_dtatools_is_numeric_altrep",
     (DL_FUNC) &C_dtatools_is_numeric_altrep, 1},
    {"C_dtatools_is_altrep", (DL_FUNC) &C_dtatools_is_altrep, 1},
    {"C_dtatools_metadata_copy", (DL_FUNC) &C_dtatools_metadata_copy, 1},
    {"C_dtatools_metadata_view", (DL_FUNC) &C_dtatools_metadata_view, 1},
    {"C_dtatools_mark_reference_data",
     (DL_FUNC) &C_dtatools_mark_reference_data, 3},
    {"C_dtatools_set_attribute", (DL_FUNC) &C_dtatools_set_attribute, 3},
    {"C_dtatools_deep_copy_value",
     (DL_FUNC) &C_dtatools_deep_copy_value, 1},
    {"C_dtatools_reference_contents",
     (DL_FUNC) &C_dtatools_reference_contents, 1},
    {"C_dtatools_reference_row_reads",
     (DL_FUNC) &C_dtatools_reference_row_reads, 1},
    {"C_dtatools_inject_reference_write_interrupt",
     (DL_FUNC) &C_dtatools_inject_reference_write_interrupt, 1},
    {"C_dtatools_mutation_rows",
     (DL_FUNC) &C_dtatools_mutation_rows, 2},
    {"C_dtatools_filter_start", (DL_FUNC) &C_dtatools_filter_start, 1},
    {"C_dtatools_filter_reduce", (DL_FUNC) &C_dtatools_filter_reduce, 3},
    {"C_dtatools_filter_finish", (DL_FUNC) &C_dtatools_filter_finish, 2},
    {"C_dtatools_patch_vector",
     (DL_FUNC) &C_dtatools_patch_vector, 3},
    {"C_dtatools_set_data_column",
     (DL_FUNC) &C_dtatools_set_data_column, 3},
    {"C_dtatools_reference_state_valid",
     (DL_FUNC) &C_dtatools_reference_state_valid, 1},
    {"C_dtatools_shared_columns", (DL_FUNC) &C_dtatools_shared_columns, 1},
    {"C_dtatools_column_capacity", (DL_FUNC) &C_dtatools_column_capacity, 1},
    {"C_dtatools_reserve_column_capacity",
     (DL_FUNC) &C_dtatools_reserve_column_capacity, 2},
    {"C_dtatools_inject_column_append_failure",
     (DL_FUNC) &C_dtatools_inject_column_append_failure, 2},
    {"C_dtatools_append_data_column",
     (DL_FUNC) &C_dtatools_append_data_column, 3},
    {"C_dtatools_can_select_data_columns",
     (DL_FUNC) &C_dtatools_can_select_data_columns, 2},
    {"C_dtatools_select_data_columns",
     (DL_FUNC) &C_dtatools_select_data_columns, 6},
    {"C_dtatools_generate_numeric",
     (DL_FUNC) &C_dtatools_generate_numeric, 6},
    {"C_dtatools_inject_generation_interrupt",
     (DL_FUNC) &C_dtatools_inject_generation_interrupt, 1},
    {"C_dtatools_generate_character",
     (DL_FUNC) &C_dtatools_generate_character, 5},
    {"C_dtatools_is_unmaterialized_numeric_altrep",
     (DL_FUNC) &C_dtatools_is_unmaterialized_numeric_altrep, 1},
    {"C_dtatools_is_materialized_numeric_altrep",
     (DL_FUNC) &C_dtatools_is_materialized_numeric_altrep, 1},
    {"C_dtatools_is_unmaterialized_dictstring",
     (DL_FUNC) &C_dtatools_is_unmaterialized_dictstring, 1},
    {"C_dtatools_dictstring_cached_count",
     (DL_FUNC) &C_dtatools_dictstring_cached_count, 1},
    {"C_dtatools_dictstring_max_width",
     (DL_FUNC) &C_dtatools_dictstring_max_width, 1},
    {"C_dtatools_numeric_storage_matches",
     (DL_FUNC) &C_dtatools_numeric_storage_matches, 3},
    {"C_dtatools_force_altrep_materialization",
     (DL_FUNC) &C_dtatools_force_altrep_materialization, 1},
    {"C_dtatools_mutate_first_numeric_altrep",
     (DL_FUNC) &C_dtatools_mutate_first_numeric_altrep, 2},
    {"C_dtatools_mutate_first_dictstring_altrep",
     (DL_FUNC) &C_dtatools_mutate_first_dictstring_altrep, 2},
    {"C_dtatools_metadata_proxy_depth",
     (DL_FUNC) &C_dtatools_metadata_proxy_depth, 1},
    {"C_dtatools_metadata_proxy_aggregate_mask",
     (DL_FUNC) &C_dtatools_metadata_proxy_aggregate_mask, 1},
    {"C_dtatools_has_tagged_na", (DL_FUNC) &C_dtatools_has_tagged_na, 1},
    {"C_dtatools_tagged_missing",
     (DL_FUNC) &C_dtatools_tagged_missing, 1},
    {"C_dtatools_missing_tag", (DL_FUNC) &C_dtatools_missing_tag, 1},
    {"C_dtatools_is_tagged_missing",
     (DL_FUNC) &C_dtatools_is_tagged_missing, 2},
    {"C_dtatools_is_missing", (DL_FUNC) &C_dtatools_is_missing, 1},
    {"C_dtatools_factorize_numeric",
     (DL_FUNC) &C_dtatools_factorize_numeric, 3},
    {"C_dtatools_missing_codes",
     (DL_FUNC) &C_dtatools_missing_codes, 1},
    {"C_dtatools_dta_compare",
     (DL_FUNC) &C_dtatools_dta_compare, 5},
    {"C_dtatools_fused_compare_patch",
     (DL_FUNC) &C_dtatools_fused_compare_patch, 8},
    {NULL, NULL, 0}
};

/**
 * Register native routines, ALTREP classes, and their storage-aware methods.
 * Metadata proxy Duplicate methods keep ordinary R copies compact; physical
 * reference ownership and column-sharing checks are registered .Call entries.
 */
void attribute_visible R_init_dtatools(DllInfo *dll) {
    initialize_owned_columns(dll);
    column_append_blank_names_class = R_make_altstring_class("dtatools_append_blank_names", "dtatools", dll);
    R_set_altrep_Length_method(column_append_blank_names_class, column_append_blank_names_length);
    R_set_altstring_Elt_method(column_append_blank_names_class, column_append_blank_names_elt);
    R_set_altvec_Dataptr_method(column_append_blank_names_class, column_append_blank_names_dataptr);
    R_set_altvec_Dataptr_or_null_method(column_append_blank_names_class, column_append_blank_names_dataptr_or_null);
    write_callback_condition_classes = PROTECT(Rf_allocVector(STRSXP, 2));
    SET_STRING_ELT(
        write_callback_condition_classes, 0, Rf_mkChar("interrupt")
    );
    SET_STRING_ELT(write_callback_condition_classes, 1, Rf_mkChar("error"));
    R_PreserveObject(write_callback_condition_classes);
    UNPROTECT(1);

    dtatools_numeric_class = R_make_altreal_class(
        "dtatools_numeric", "dtatools", dll
    );
    R_set_altrep_Unserialize_method(
        dtatools_numeric_class, numeric_unserialize
    );
    R_set_altrep_Serialized_state_method(
        dtatools_numeric_class, numeric_serialized_state
    );
    R_set_altrep_Duplicate_method(
        dtatools_numeric_class, numeric_duplicate
    );
    R_set_altrep_Length_method(dtatools_numeric_class, numeric_length);
    R_set_altvec_Extract_subset_method(
        dtatools_numeric_class, numeric_extract_subset
    );
    R_set_altvec_Dataptr_method(dtatools_numeric_class, numeric_dataptr);
    R_set_altvec_Dataptr_or_null_method(
        dtatools_numeric_class, numeric_dataptr_or_null
    );
    R_set_altreal_Elt_method(dtatools_numeric_class, numeric_value);
    R_set_altreal_Get_region_method(dtatools_numeric_class, numeric_region);
    R_set_altreal_No_NA_method(dtatools_numeric_class, numeric_no_na);
    R_set_altreal_Sum_method(dtatools_numeric_class, numeric_sum);
    R_set_altreal_Min_method(dtatools_numeric_class, numeric_min);
    R_set_altreal_Max_method(dtatools_numeric_class, numeric_max);
    dtatools_dictstring_class = R_make_altstring_class(
        "dtatools_dictstring", "dtatools", dll
    );
    R_set_altrep_Length_method(dtatools_dictstring_class, dictstring_length);
    R_set_altvec_Dataptr_method(dtatools_dictstring_class, dictstring_dataptr);
    R_set_altvec_Dataptr_or_null_method(
        dtatools_dictstring_class, dictstring_dataptr_or_null
    );
    R_set_altrep_Duplicate_method(
        dtatools_dictstring_class, dictstring_duplicate
    );
    R_set_altvec_Extract_subset_method(
        dtatools_dictstring_class, dictstring_extract_subset
    );
    R_set_altstring_Elt_method(dtatools_dictstring_class, dictstring_value);
    R_set_altstring_Set_elt_method(dtatools_dictstring_class, dictstring_set_elt);
    R_set_altstring_No_NA_method(dtatools_dictstring_class, dictstring_no_na);
    dtatools_mutation_string_class = R_make_altstring_class("dtatools_mutation_string", "dtatools", dll);
    R_set_altrep_Length_method(dtatools_mutation_string_class, mutation_string_length);
    R_set_altrep_Duplicate_method(dtatools_mutation_string_class, mutation_string_duplicate);
    R_set_altvec_Dataptr_method(dtatools_mutation_string_class, mutation_string_dataptr);
    R_set_altvec_Dataptr_or_null_method(dtatools_mutation_string_class, mutation_string_dataptr_or_null);
    R_set_altstring_Elt_method(dtatools_mutation_string_class, mutation_string_elt);
    dtatools_ephemeral_string_class = R_make_altstring_class(
        "dtatools_ephemeral_string", "dtatools", dll
    );
    R_set_altrep_Length_method(
        dtatools_ephemeral_string_class, ephemeral_string_length
    );
    R_set_altstring_Elt_method(
        dtatools_ephemeral_string_class, ephemeral_string_value
    );
    dtatools_metadata_real_class = R_make_altreal_class(
        "dtatools_metadata_real", "dtatools", dll
    );
    R_set_altrep_Length_method(
        dtatools_metadata_real_class, metadata_proxy_length
    );
    R_set_altrep_Duplicate_method(
        dtatools_metadata_real_class, metadata_real_duplicate
    );
    R_set_altvec_Dataptr_method(
        dtatools_metadata_real_class, metadata_real_dataptr
    );
    R_set_altvec_Dataptr_or_null_method(
        dtatools_metadata_real_class, metadata_real_dataptr_or_null
    );
    R_set_altvec_Extract_subset_method(
        dtatools_metadata_real_class, metadata_real_extract_subset
    );
    R_set_altreal_Elt_method(
        dtatools_metadata_real_class, metadata_real_value
    );
    R_set_altreal_Get_region_method(
        dtatools_metadata_real_class, metadata_real_region
    );
    R_set_altreal_No_NA_method(
        dtatools_metadata_real_class, metadata_real_no_na
    );
    R_set_altreal_Sum_method(
        dtatools_metadata_real_class, metadata_real_sum
    );
    R_set_altreal_Min_method(
        dtatools_metadata_real_class, metadata_real_min
    );
    R_set_altreal_Max_method(
        dtatools_metadata_real_class, metadata_real_max
    );
    dtatools_metadata_string_class = R_make_altstring_class(
        "dtatools_metadata_string", "dtatools", dll
    );
    R_set_altrep_Length_method(
        dtatools_metadata_string_class, metadata_proxy_length
    );
    R_set_altrep_Duplicate_method(
        dtatools_metadata_string_class, metadata_string_duplicate
    );
    R_set_altvec_Dataptr_method(
        dtatools_metadata_string_class, metadata_string_dataptr
    );
    R_set_altvec_Dataptr_or_null_method(
        dtatools_metadata_string_class, metadata_string_dataptr_or_null
    );
    R_set_altvec_Extract_subset_method(
        dtatools_metadata_string_class, metadata_string_extract_subset
    );
    R_set_altstring_Elt_method(
        dtatools_metadata_string_class, metadata_string_value
    );
    R_set_altstring_Set_elt_method(
        dtatools_metadata_string_class, metadata_string_set_elt
    );
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
