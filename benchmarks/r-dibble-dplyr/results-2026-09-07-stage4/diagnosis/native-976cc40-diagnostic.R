lib <- "/private/tmp/dta-direct-stage4-validation/candidate-976cc40-library"
sha <- "976cc403f21b9adbb454d39c9c3447717b67c29f"
root <- "/private/tmp/dta-direct-stage4-validation/source-976cc40"
source(file.path(root, "benchmarks/r-dibble-dplyr/helpers.R"))
validate_benchmark_install(lib, sha)
Sys.setenv(DTATOOLS_BENCHMARK_CHILD = "1", DTATOOLS_BENCHMARK_LIBRARY = lib,
           DTATOOLS_BENCHMARK_SHA = sha, DTATOOLS_BENCHMARK_STATE = "diagnostic-unchanged-runner")
cat("DIAGNOSTIC ONLY: unchanged runner sourced to retain error-time scalar metrics\n")
failure <- tryCatch({source(file.path(root, "benchmarks/r-reference-mutation/run.R"), local = .GlobalEnv); NULL}, error = identity)
for (name in c("character_fill_time", "dictionary_replacement_time", "dictionary_profile",
               "character_generation_time", "scalar_dictionary_replacement_time",
               "ordinary_scalar_replacement_time")) {
    if (exists(name, envir = .GlobalEnv, inherits = FALSE)) {
        cat("Diagnostic metric:", name, "\n")
        print(get(name, envir = .GlobalEnv))
    }
}
validate_benchmark_install(lib, sha)
if (!is.null(failure)) {cat("FAILURE:", conditionMessage(failure), "\n"); quit(status = 1L)}
