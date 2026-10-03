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

SEXP C_dtatools_summarize_sum(SEXP x);
SEXP C_dtatools_numeric_mean(SEXP x, SEXP na_rm);
SEXP C_dtatools_mean_admitted(SEXP frame);
SEXP C_dtatools_range_admitted(SEXP frame);
SEXP C_dtatools_numeric_range(SEXP values, SEXP na_rm);
SEXP C_dtatools_summarize_moments(SEXP values, SEXP weights, SEXP detail, SEXP meanonly);
SEXP C_dtatools_numeric_identity_key(SEXP values, SEXP argument);
SEXP C_dtatools_numeric_match_keys(SEXP x, SEXP table, SEXP nomatch, SEXP incomparables);
SEXP C_dtatools_numeric_duplicated_keys(SEXP keys);
SEXP C_dtatools_numeric_any_na(SEXP value, SEXP recursive);

/* THROWAWAY unique-target function-entry floor. */
SEXP C_dtatools_probe_unique_repl(SEXP data, SEXP shared, SEXP arguments,
                                  SEXP dependencies, SEXP s3_state,
                                  SEXP base_live, SEXP rlang_state,
                                  SEXP vctrs_size_state, SEXP base16_state,
                                  SEXP public48_state, SEXP wrapper_state);
SEXP C_dtatools_probe_unique_repl_stats(SEXP reset);
SEXP C_dtatools_probe_unique_repl_mode(SEXP mode);
SEXP C_dtatools_profile_file_fingerprints(SEXP paths);
SEXP C_dtatools_probe_abs_mode(SEXP mode);
SEXP C_dtatools_probe_precommit_hook(SEXP callback);
SEXP C_dtatools_probe_scalar_public_dependencies(SEXP dependencies);
SEXP C_dtatools_probe_caller_plus(SEXP quosure, SEXP dependencies);
SEXP C_dtatools_probe_repl_syntax(SEXP variable, SEXP values);
SEXP C_fast_s3_guard(SEXP quosure, SEXP tables, SEXP live, SEXP namespaces);
SEXP C_dtatools_probe_base_profile(SEXP frozen);
SEXP C_dtatools_probe_base_guard(SEXP live, SEXP quosure);
SEXP C_dtatools_probe_base_guard_deep(SEXP live, SEXP quosure);
SEXP C_dtatools_probe_rlang_profile(SEXP ns, SEXP frozen);
SEXP C_dtatools_probe_rlang_guard(SEXP state);
SEXP C_dtatools_probe_vctrs_size_guard(SEXP state);
SEXP C_dtatools_probe_vctrs_size_guard_deep(SEXP state);
SEXP C_dtatools_probe_base16_guard(SEXP state);
SEXP C_dtatools_probe_base16_formals_only(SEXP state);
SEXP C_dtatools_probe_base16_mode(SEXP mode);
SEXP C_probe_48_expected_plain(SEXP expected);
SEXP C_dtatools_probe_public48_capture(SEXP state);
SEXP C_dtatools_probe_public48_guard(SEXP state);
SEXP C_probe_public48_source_qualification(SEXP current, SEXP frozen);
SEXP C_probe_public48_debug_available(SEXP unused);
SEXP C_probe_public48_debug_state(SEXP fn);
SEXP C_probe_public48_same_pointer(SEXP a, SEXP b);
SEXP C_dtatools_probe_public_fused_guard(SEXP base, SEXP public48,
                                          SEXP vctrs, SEXP quosure,
                                          SEXP dependencies);
SEXP C_dtatools_probe_wrapper_capture(SEXP state);
SEXP C_dtatools_probe_wrapper_guard(SEXP state);
SEXP C_dtatools_probe_direct_final(SEXP data, SEXP base, SEXP public_state,
                                   SEXP extra, SEXP wrapper, SEXP rlang,
                                   SEXP s3);
SEXP C_dtatools_probe_direct_final_mode(SEXP mode);
SEXP C_dtatools_probe_direct_final_stats(SEXP reset);
SEXP C_dtatools_probe_grouped_gen(SEXP data, SEXP base, SEXP public_state,
                                  SEXP extra, SEXP wrapper, SEXP rlang,
                                  SEXP s3, SEXP grouped);
SEXP C_dtatools_probe_grouped_gen_mode(SEXP mode);
SEXP C_dtatools_probe_grouped_gen_stats(SEXP reset);
SEXP C_dtatools_probe_grouped_gen_after_stage(SEXP callback);
SEXP C_dtatools_probe_gen_after_stage(SEXP callback);
SEXP C_dtatools_probe_gen_extra_capture(SEXP state);
SEXP C_dtatools_probe_gen_append_hook(SEXP callback, SEXP stage);
void dtatools_probe_gen_primitive_init(void);
SEXP C_dtatools_grouped_active_mutate(SEXP ignored);
SEXP C_dtatools_grouped_mode(SEXP);
SEXP C_dtatools_grouped_stats(SEXP);
SEXP C_dtatools_probe_grouped_capacity_hook(SEXP, SEXP);
SEXP C_dtatools_grouped_disable(SEXP ignored);
SEXP C_dtatools_grouped_guard_early(SEXP ignored);
SEXP C_dtatools_grouped_guard_public(SEXP ignored);
SEXP C_dtatools_grouped_begin_context(SEXP data);
SEXP C_dtatools_grouped_entry(SEXP data, SEXP dots, SEXP by,
                              SEXP captured_dots, SEXP captured_by,
                              SEXP captured_columns);
SEXP C_dtatools_grouped_pin_operators(SEXP operators);
SEXP C_dtatools_grouped_pin_public(SEXP roots);
SEXP C_dtatools_grouped_pin_absent(SEXP roots);
SEXP C_dtatools_probe_mutate_selector(SEXP frame);
SEXP C_dtatools_probe_mutate_mode(SEXP enabled);
SEXP C_dtatools_probe_dplyr_early_stats(SEXP reset);
SEXP C_dtatools_probe_arm_publication_gc(SEXP value);
SEXP C_dtatools_probe_fork_gc_index(SEXP value);
SEXP C_dtatools_probe_pin_operators(SEXP operators);
SEXP C_dtatools_probe_pin_public(SEXP roots);
SEXP C_dtatools_probe_pin_absent(SEXP roots);
SEXP C_dtatools_probe_guard_public(SEXP ignored);
void dtatools_probe_release_public_cache(void);
void dtatools_probe_plain_public_release(void);
SEXP C_dtatools_probe_plain_public_pin(SEXP state);

SEXP C_bracket_s3_guard(SEXP caller, SEXP tables, SEXP live, SEXP namespaces);
SEXP C_bracket_s3_init(SEXP ignored);
SEXP C_dtatools_probe_bracket_append_mark_reference(SEXP data, SEXP name, SEXP column, SEXP state, SEXP classes);
SEXP C_dtatools_probe_bracket_general_batch(SEXP data, SEXP assignments, SEXP profile);
SEXP C_dtatools_probe_bracket_general_descriptor(SEXP data, SEXP assignments, SEXP caller);
SEXP C_dtatools_probe_bracket_ordinary_append_hook(SEXP hook);
SEXP C_dtatools_probe_bracket_public_guard(SEXP profile, SEXP assignments);
SEXP C_dtatools_probe_bracket_public_live(SEXP profile, SEXP assignments);
SEXP C_dtatools_probe_bracket_public_live_caller(SEXP profile, SEXP caller);
SEXP C_dtatools_probe_bracket_raw_five_parser(SEXP raw_j, SEXP profile);
SEXP C_dtatools_probe_bracket_raw_parser_into_frame(SEXP raw_j, SEXP profile);
SEXP C_dtatools_probe_bracket_raw_parser_stats(SEXP reset);
SEXP C_dtatools_probe_bracket_step_stats(SEXP reset);
SEXP C_dtatools_probe_gen_public_guard(SEXP base, SEXP public_state, SEXP extra_state, SEXP wrapper_state, SEXP rlang_state, SEXP s3_state);
SEXP C_dtatools_probe_grouped_bracket_batch(SEXP data, SEXP assignments, SEXP by, SEXP where, SEXP caller, SEXP extra_state, SEXP s3_state);
SEXP C_dtatools_probe_grouped_bracket_mode(SEXP requested);
SEXP C_dtatools_probe_grouped_bracket_pin(SEXP state);
SEXP C_dtatools_probe_grouped_bracket_profile(SEXP on);
SEXP C_dtatools_probe_grouped_bracket_raw(SEXP raw_j);
SEXP C_dtatools_probe_grouped_bracket_rebind_live(SEXP ignored);
SEXP C_dtatools_probe_grouped_bracket_selection(SEXP key, SEXP name);
SEXP C_dtatools_probe_grouped_bracket_stats(SEXP reset);
SEXP C_dtatools_probe_grouped_guard_live(SEXP ignored);
SEXP C_dtatools_probe_grouped_output_hook(SEXP hook);
SEXP C_dtatools_probe_grouped_owned_write_first(SEXP column, SEXP number);
SEXP C_dtatools_probe_grouped_set_column_attr(SEXP column, SEXP name, SEXP value);
SEXP C_dtatools_probe_grouped_set_column_label(SEXP column, SEXP label);
SEXP C_dtatools_probe_grouped_set_table_attr(SEXP data, SEXP name, SEXP value);
SEXP C_dtatools_probe_owned_set_storage(SEXP value, SEXP storage);
SEXP C_dtatools_probe_owned_write_first(SEXP value, SEXP scalar);
SEXP C_dtatools_probe_plan_key_change(SEXP key, SEXP change, SEXP replacement);
SEXP C_dtatools_probe_prepared_copy_after_names_hook(SEXP hook);
SEXP C_snap_active(SEXP ext, SEXP active);
SEXP C_snap_active_parts(SEXP ext, SEXP active);
SEXP C_snap_check(SEXP ext);
SEXP C_snap_new(SEXP functions, SEXP env);
SEXP C_snap_new_bracket(SEXP functions, SEXP env);
SEXP C_snap_new_shallow_all(SEXP functions, SEXP env);
SEXP C_snap_stats(SEXP ext);

SEXP C_dtatools_probe_bracket_generation_hook(SEXP ignored);
SEXP C_dtatools_probe_bracket_pre_generation_hook(SEXP resolved);

static const R_CallMethodDef CallEntries[] = {
    {"C_dtatools_summarize_sum", (DL_FUNC) &C_dtatools_summarize_sum, 1},
    {"C_dtatools_numeric_mean", (DL_FUNC) &C_dtatools_numeric_mean, 2},
    {"C_dtatools_mean_admitted", (DL_FUNC) &C_dtatools_mean_admitted, 1},
    {"C_dtatools_range_admitted", (DL_FUNC) &C_dtatools_range_admitted, 1},
    {"C_dtatools_numeric_range", (DL_FUNC) &C_dtatools_numeric_range, 2},
    {"C_dtatools_summarize_moments", (DL_FUNC) &C_dtatools_summarize_moments, 4},
    {"C_dtatools_numeric_identity_key", (DL_FUNC) &C_dtatools_numeric_identity_key, 2},
    {"C_dtatools_numeric_match_keys", (DL_FUNC) &C_dtatools_numeric_match_keys, 4},
    {"C_dtatools_numeric_duplicated_keys", (DL_FUNC) &C_dtatools_numeric_duplicated_keys, 1},
    {"C_dtatools_numeric_any_na", (DL_FUNC) &C_dtatools_numeric_any_na, 2},
    {"C_dtatools_grouped_active_mutate", (DL_FUNC) &C_dtatools_grouped_active_mutate, 1},
    {"C_dtatools_grouped_mode", (DL_FUNC) &C_dtatools_grouped_mode, 1},
    {"C_dtatools_grouped_stats", (DL_FUNC) &C_dtatools_grouped_stats, 1},
    {"C_dtatools_probe_grouped_capacity_hook", (DL_FUNC) &C_dtatools_probe_grouped_capacity_hook, 2},
    {"C_dtatools_grouped_disable", (DL_FUNC) &C_dtatools_grouped_disable, 1},
    {"C_dtatools_grouped_guard_early", (DL_FUNC) &C_dtatools_grouped_guard_early, 1},
    {"C_dtatools_grouped_guard_public", (DL_FUNC) &C_dtatools_grouped_guard_public, 1},
    {"C_dtatools_grouped_begin_context", (DL_FUNC) &C_dtatools_grouped_begin_context, 1},
    {"C_dtatools_grouped_entry", (DL_FUNC) &C_dtatools_grouped_entry, 6},
    {"C_dtatools_grouped_pin_operators", (DL_FUNC) &C_dtatools_grouped_pin_operators, 1},
    {"C_dtatools_grouped_pin_public", (DL_FUNC) &C_dtatools_grouped_pin_public, 1},
    {"C_dtatools_grouped_pin_absent", (DL_FUNC) &C_dtatools_grouped_pin_absent, 1},
    {"C_dtatools_probe_mutate_selector", (DL_FUNC) &C_dtatools_probe_mutate_selector, 1},
    {"C_dtatools_probe_mutate_mode", (DL_FUNC) &C_dtatools_probe_mutate_mode, 1},
    {"C_dtatools_probe_dplyr_early_stats", (DL_FUNC) &C_dtatools_probe_dplyr_early_stats, 1},
    {"C_dtatools_probe_arm_publication_gc", (DL_FUNC) &C_dtatools_probe_arm_publication_gc, 1},
    {"C_dtatools_probe_fork_gc_index", (DL_FUNC) &C_dtatools_probe_fork_gc_index, 1},
    {"C_dtatools_probe_pin_operators", (DL_FUNC) &C_dtatools_probe_pin_operators, 1},
    {"C_dtatools_probe_pin_public", (DL_FUNC) &C_dtatools_probe_pin_public, 1},
    {"C_dtatools_probe_pin_absent", (DL_FUNC) &C_dtatools_probe_pin_absent, 1},
    {"C_dtatools_probe_guard_public", (DL_FUNC) &C_dtatools_probe_guard_public, 1},
    {"C_dtatools_probe_unique_repl", (DL_FUNC) &C_dtatools_probe_unique_repl, 11},
    {"C_dtatools_probe_unique_repl_stats", (DL_FUNC) &C_dtatools_probe_unique_repl_stats, 1},
    {"C_dtatools_probe_unique_repl_mode", (DL_FUNC) &C_dtatools_probe_unique_repl_mode, 1},
    {"C_dtatools_profile_file_fingerprints",
     (DL_FUNC) &C_dtatools_profile_file_fingerprints, 1},
    {"C_dtatools_probe_abs_mode", (DL_FUNC) &C_dtatools_probe_abs_mode, 1},
    {"C_dtatools_probe_precommit_hook", (DL_FUNC) &C_dtatools_probe_precommit_hook, 1},
    {"C_dtatools_probe_scalar_public_dependencies", (DL_FUNC) &C_dtatools_probe_scalar_public_dependencies, 1},
    {"C_dtatools_probe_caller_plus", (DL_FUNC) &C_dtatools_probe_caller_plus, 2},
    {"C_dtatools_probe_repl_syntax", (DL_FUNC) &C_dtatools_probe_repl_syntax, 2},
    {"C_fast_s3_guard", (DL_FUNC) &C_fast_s3_guard, 4},
    {"C_dtatools_probe_base_profile", (DL_FUNC) &C_dtatools_probe_base_profile, 1},
    {"C_dtatools_probe_base_guard", (DL_FUNC) &C_dtatools_probe_base_guard, 2},
    {"C_dtatools_probe_base_guard_deep", (DL_FUNC) &C_dtatools_probe_base_guard_deep, 2},
    {"C_dtatools_probe_rlang_profile", (DL_FUNC) &C_dtatools_probe_rlang_profile, 2},
    {"C_dtatools_probe_rlang_guard", (DL_FUNC) &C_dtatools_probe_rlang_guard, 1},
    {"C_dtatools_probe_vctrs_size_guard", (DL_FUNC) &C_dtatools_probe_vctrs_size_guard, 1},
    {"C_dtatools_probe_vctrs_size_guard_deep", (DL_FUNC) &C_dtatools_probe_vctrs_size_guard_deep, 1},
    {"C_dtatools_probe_base16_guard", (DL_FUNC) &C_dtatools_probe_base16_guard, 1},
    {"C_dtatools_probe_base16_formals_only", (DL_FUNC) &C_dtatools_probe_base16_formals_only, 1},
    {"C_dtatools_probe_base16_mode", (DL_FUNC) &C_dtatools_probe_base16_mode, 1},
    {"C_probe_48_expected_plain", (DL_FUNC) &C_probe_48_expected_plain, 1},
    {"C_dtatools_probe_public48_capture", (DL_FUNC) &C_dtatools_probe_public48_capture, 1},
    {"C_dtatools_probe_public48_guard", (DL_FUNC) &C_dtatools_probe_public48_guard, 1},
    {"C_probe_public48_source_qualification", (DL_FUNC) &C_probe_public48_source_qualification, 2},
    {"C_probe_public48_debug_available", (DL_FUNC) &C_probe_public48_debug_available, 1},
    {"C_probe_public48_debug_state", (DL_FUNC) &C_probe_public48_debug_state, 1},
    {"C_probe_public48_same_pointer", (DL_FUNC) &C_probe_public48_same_pointer, 2},
    {"C_dtatools_probe_public_fused_guard", (DL_FUNC) &C_dtatools_probe_public_fused_guard, 5},
    {"C_dtatools_probe_wrapper_capture", (DL_FUNC) &C_dtatools_probe_wrapper_capture, 1},
    {"C_dtatools_probe_wrapper_guard", (DL_FUNC) &C_dtatools_probe_wrapper_guard, 1},
    {"C_dtatools_probe_direct_final", (DL_FUNC) &C_dtatools_probe_direct_final, 7},
    {"C_dtatools_probe_direct_final_mode", (DL_FUNC) &C_dtatools_probe_direct_final_mode, 1},
    {"C_dtatools_probe_direct_final_stats", (DL_FUNC) &C_dtatools_probe_direct_final_stats, 1},
    {"C_dtatools_probe_grouped_gen", (DL_FUNC) &C_dtatools_probe_grouped_gen, 8},
    {"C_dtatools_probe_grouped_gen_mode", (DL_FUNC) &C_dtatools_probe_grouped_gen_mode, 1},
    {"C_dtatools_probe_grouped_gen_stats", (DL_FUNC) &C_dtatools_probe_grouped_gen_stats, 1},
    {"C_dtatools_probe_grouped_gen_after_stage", (DL_FUNC) &C_dtatools_probe_grouped_gen_after_stage, 1},
    {"C_dtatools_probe_gen_after_stage", (DL_FUNC) &C_dtatools_probe_gen_after_stage, 1},
    {"C_dtatools_probe_plain_public_pin", (DL_FUNC) &C_dtatools_probe_plain_public_pin, 1},
    {"C_dtatools_probe_gen_extra_capture", (DL_FUNC) &C_dtatools_probe_gen_extra_capture, 1},
    {"C_dtatools_probe_gen_append_hook", (DL_FUNC) &C_dtatools_probe_gen_append_hook, 2},
    {"C_dtatools_initial_capture_mode", (DL_FUNC) &C_dtatools_initial_capture_mode, 1},
    {"C_dtatools_initial_capture_shell", (DL_FUNC) &C_dtatools_initial_capture_shell, 1},
    {"C_dtatools_initial_capture_initial", (DL_FUNC) &C_dtatools_initial_capture_initial, 1},
    {"C_dtatools_initial_capture_stats", (DL_FUNC) &C_dtatools_initial_capture_stats, 1},
    {"C_dtatools_owned_numeric_freeze", (DL_FUNC) &C_dtatools_owned_numeric_freeze, 2},
    {"C_dtatools_owned_numeric_info", (DL_FUNC) &C_dtatools_owned_numeric_info, 1},
    {"C_dtatools_numeric_domain_info", (DL_FUNC) &C_dtatools_numeric_domain_info, 1},
    {"C_dtatools_native_copy_stats", (DL_FUNC) &C_dtatools_native_copy_stats, 1},
    {"C_dtatools_numeric_entry_stats", (DL_FUNC) &C_dtatools_numeric_entry_stats, 1},
    {"C_dtatools_test_arithmetic_checkpoint", (DL_FUNC) &C_dtatools_test_arithmetic_checkpoint, 2},
    {"C_dtatools_test_materialization_checkpoint", (DL_FUNC) &C_dtatools_test_materialization_checkpoint, 2},
    {"C_dtatools_test_numeric_size_minimum", (DL_FUNC) &C_dtatools_test_numeric_size_minimum, 1},
    {"C_dtatools_numeric_size_stats", (DL_FUNC) &C_dtatools_numeric_size_stats, 1},
    {"C_dtatools_test_numeric_size_gate", (DL_FUNC) &C_dtatools_test_numeric_size_gate, 1},
    {"C_dtatools_capture_branch_frame", (DL_FUNC) &C_dtatools_capture_branch_frame, 0},
    {"C_dtatools_select_branch", (DL_FUNC) &C_dtatools_select_branch, 2},
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
    {"C_dtatools_peek_promote", (DL_FUNC) &C_dtatools_peek_promote, 1},
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
    {"C_dtatools_egen_group_stats", (DL_FUNC) &C_dtatools_egen_group_stats, 1},
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
    {"C_dtatools_try_mask_bindings",
     (DL_FUNC) &C_dtatools_try_mask_bindings, 3},
    {"C_dtatools_expected_numeric_profile", (DL_FUNC) &C_dtatools_expected_numeric_profile, 2},
    {"C_dtatools_numeric_proof_stats", (DL_FUNC) &C_dtatools_numeric_proof_stats, 1},
    {"C_dtatools_test_numeric_proof", (DL_FUNC) &C_dtatools_test_numeric_proof, 3},
    {"C_dtatools_test_numeric_old_proof", (DL_FUNC) &C_dtatools_test_numeric_old_proof, 2},
    {"C_dtatools_numeric_entry_state",
     (DL_FUNC) &C_dtatools_numeric_entry_state, 1},
    {"C_dtatools_double_combine_dependencies",
     (DL_FUNC) &C_dtatools_double_combine_dependencies, 1},
    {"C_dtatools_canonical_generate_attributes",
     (DL_FUNC) &C_dtatools_canonical_generate_attributes, 3},
    {"C_dtatools_metadata_execution_profile",
     (DL_FUNC) &C_dtatools_metadata_execution_profile, 1},
    {"C_dtatools_metadata_dependencies_unchanged",
     (DL_FUNC) &C_dtatools_metadata_dependencies_unchanged, 2},
    {"C_dtatools_canonical_attribute_plan",
     (DL_FUNC) &C_dtatools_canonical_attribute_plan, 2},
    {"C_dtatools_attribute_plan_stats", (DL_FUNC) &C_dtatools_attribute_plan_stats, 1},
    {"C_dtatools_try_combine_double",
     (DL_FUNC) &C_dtatools_try_combine_double, 5},
    {"C_dtatools_combine_double_into_current",
     (DL_FUNC) &C_dtatools_combine_double_into_current, 3},
    {"C_dtatools_construct_double",
     (DL_FUNC) &C_dtatools_construct_double, 3},
    {"C_dtatools_double_fits",
     (DL_FUNC) &C_dtatools_double_fits, 3},
    {"C_dtatools_construct_numeric_trusted",
     (DL_FUNC) &C_dtatools_construct_numeric_trusted, 4},
    {"C_dtatools_computed_numeric",
     (DL_FUNC) &C_dtatools_computed_numeric, 4},
    {"C_dtatools_scalar_arithmetic",
     (DL_FUNC) &C_dtatools_scalar_arithmetic, 5},
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
    {"C_dtatools_test_arrow_strings_interrupt",
     (DL_FUNC) &C_dtatools_test_arrow_strings_interrupt, 1},
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
    {"C_bracket_s3_guard", (DL_FUNC) &C_bracket_s3_guard, 4},
    {"C_bracket_s3_init", (DL_FUNC) &C_bracket_s3_init, 1},
    {"C_dtatools_probe_bracket_append_mark_reference", (DL_FUNC) &C_dtatools_probe_bracket_append_mark_reference, 5},
    {"C_dtatools_probe_bracket_general_batch", (DL_FUNC) &C_dtatools_probe_bracket_general_batch, 3},
    {"C_dtatools_probe_bracket_general_descriptor", (DL_FUNC) &C_dtatools_probe_bracket_general_descriptor, 3},
    {"C_dtatools_probe_bracket_ordinary_append_hook", (DL_FUNC) &C_dtatools_probe_bracket_ordinary_append_hook, 1},
    {"C_dtatools_probe_bracket_public_guard", (DL_FUNC) &C_dtatools_probe_bracket_public_guard, 2},
    {"C_dtatools_probe_bracket_public_live", (DL_FUNC) &C_dtatools_probe_bracket_public_live, 2},
    {"C_dtatools_probe_bracket_public_live_caller", (DL_FUNC) &C_dtatools_probe_bracket_public_live_caller, 2},
    {"C_dtatools_probe_bracket_raw_five_parser", (DL_FUNC) &C_dtatools_probe_bracket_raw_five_parser, 2},
    {"C_dtatools_probe_bracket_raw_parser_into_frame", (DL_FUNC) &C_dtatools_probe_bracket_raw_parser_into_frame, 2},
    {"C_dtatools_probe_bracket_raw_parser_stats", (DL_FUNC) &C_dtatools_probe_bracket_raw_parser_stats, 1},
    {"C_dtatools_probe_bracket_step_stats", (DL_FUNC) &C_dtatools_probe_bracket_step_stats, 1},
    {"C_dtatools_probe_gen_public_guard", (DL_FUNC) &C_dtatools_probe_gen_public_guard, 6},
    {"C_dtatools_probe_grouped_bracket_batch", (DL_FUNC) &C_dtatools_probe_grouped_bracket_batch, 7},
    {"C_dtatools_probe_grouped_bracket_mode", (DL_FUNC) &C_dtatools_probe_grouped_bracket_mode, 1},
    {"C_dtatools_probe_grouped_bracket_pin", (DL_FUNC) &C_dtatools_probe_grouped_bracket_pin, 1},
    {"C_dtatools_probe_grouped_bracket_profile", (DL_FUNC) &C_dtatools_probe_grouped_bracket_profile, 1},
    {"C_dtatools_probe_grouped_bracket_raw", (DL_FUNC) &C_dtatools_probe_grouped_bracket_raw, 1},
    {"C_dtatools_probe_grouped_bracket_rebind_live", (DL_FUNC) &C_dtatools_probe_grouped_bracket_rebind_live, 1},
    {"C_dtatools_probe_grouped_bracket_selection", (DL_FUNC) &C_dtatools_probe_grouped_bracket_selection, 2},
    {"C_dtatools_probe_grouped_bracket_stats", (DL_FUNC) &C_dtatools_probe_grouped_bracket_stats, 1},
    {"C_dtatools_probe_grouped_guard_live", (DL_FUNC) &C_dtatools_probe_grouped_guard_live, 1},
    {"C_dtatools_probe_grouped_output_hook", (DL_FUNC) &C_dtatools_probe_grouped_output_hook, 1},
    {"C_dtatools_probe_grouped_owned_write_first", (DL_FUNC) &C_dtatools_probe_grouped_owned_write_first, 2},
    {"C_dtatools_probe_grouped_set_column_attr", (DL_FUNC) &C_dtatools_probe_grouped_set_column_attr, 3},
    {"C_dtatools_probe_grouped_set_column_label", (DL_FUNC) &C_dtatools_probe_grouped_set_column_label, 2},
    {"C_dtatools_probe_grouped_set_table_attr", (DL_FUNC) &C_dtatools_probe_grouped_set_table_attr, 3},
    {"C_dtatools_probe_owned_set_storage", (DL_FUNC) &C_dtatools_probe_owned_set_storage, 2},
    {"C_dtatools_probe_owned_write_first", (DL_FUNC) &C_dtatools_probe_owned_write_first, 2},
    {"C_dtatools_probe_plan_key_change", (DL_FUNC) &C_dtatools_probe_plan_key_change, 3},
    {"C_dtatools_probe_prepared_copy_after_names_hook", (DL_FUNC) &C_dtatools_probe_prepared_copy_after_names_hook, 1},
    {"C_snap_active", (DL_FUNC) &C_snap_active, 2},
    {"C_snap_active_parts", (DL_FUNC) &C_snap_active_parts, 2},
    {"C_snap_check", (DL_FUNC) &C_snap_check, 1},
    {"C_snap_new", (DL_FUNC) &C_snap_new, 2},
    {"C_snap_new_bracket", (DL_FUNC) &C_snap_new_bracket, 2},
    {"C_snap_new_shallow_all", (DL_FUNC) &C_snap_new_shallow_all, 2},
    {"C_snap_stats", (DL_FUNC) &C_snap_stats, 1},
    {"C_dtatools_probe_bracket_generation_hook", (DL_FUNC) &C_dtatools_probe_bracket_generation_hook, 1},
    {"C_dtatools_probe_bracket_pre_generation_hook", (DL_FUNC) &C_dtatools_probe_bracket_pre_generation_hook, 1},
    {NULL, NULL, 0}
};

/**
 * Register native routines, ALTREP classes, and their storage-aware methods.
 * Metadata proxy Duplicate methods keep ordinary R copies compact; physical
 * reference ownership and column-sharing checks are registered .Call entries.
 */
void attribute_visible R_init_dtatools(DllInfo *dll) {
    dtatools_probe_gen_primitive_init();
    initialize_numeric_size_gate();
    initialize_owned_columns(dll);
    initialize_generated_real_reader();
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

void attribute_visible R_unload_dtatools(DllInfo *dll) {
    (void) dll;
    dtatools_probe_release_public_cache();
    dtatools_probe_plain_public_release();
    release_generated_real_reader();
}
