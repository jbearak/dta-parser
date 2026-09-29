# Independent test oracle: a disabled production record cannot make positive
# native-admission tests pass by selecting their unsupported-runtime branch.
.dtatools_bytecode_execution_expected <- function() {
    private <- new.env(parent = baseenv())
    probe <- function() vector("list", 1L)
    environment(probe) <- private
    probe <- compiler::cmpfun(probe, options = list(optimize = 3L))
    private$vector <- function(...) FALSE
    identical(probe(), list(NULL))
}

.dtatools_execution_profile_expected <- function() {
    identical(as.character(getRversion()), "4.6.1") &&
        identical(as.character(R.version[["svn rev"]]), "90187") &&
        .dtatools_bytecode_execution_expected()
}

# Success counters describe actual publication from canonical production
# bodies. Explicit-frame kernel diagnostics do not increment these counters.
.dtatools_numeric_entry_counts <- function(reset = FALSE) {
    .Primitive(".Call")(get("C_dtatools_numeric_entry_stats", asNamespace("dtatools")), reset)
}

.dtatools_numeric_entry_observe <- function(operation) {
    invisible(.dtatools_numeric_entry_counts(TRUE))
    result <- operation()
    list(result = result, counts = .dtatools_numeric_entry_counts(FALSE))
}

.dtatools_numeric_entry_expected <- function(route = NULL) {
    if (identical(route, "holds")) return(.dtatools_execution_profile_expected())
    .dtatools_execution_profile_expected() &&
        identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
        identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
}
