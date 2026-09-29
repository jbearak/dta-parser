.initial_capture_test_call <- function(name, ...) {
    .Primitive(".Call")(get(name, asNamespace("dtatools")), ...)
}

.initial_capture_test_counts <- function(reset = FALSE) {
    .initial_capture_test_call("C_dtatools_initial_capture_stats", reset)
}

.initial_capture_test_owned <- function(value) {
    .subset2(dtatools::as_dibble(tibble::tibble(x = rep(as.double(value), 1L))), 1L)
}

.initial_capture_test_columns <- function(width = 256L) {
    values <- lapply(seq_len(width - 1L), function(i) .initial_capture_test_owned(1:4 + i - 1L))
    names(values) <- c("x", if (width > 2L) paste0("v", seq_len(width - 2L)))
    values$g <- dtatools::dta_long(1:4)
    values
}

.initial_capture_test_groups <- function() {
    list(rows = list(1:2, 3:4), names = "g", keys = tibble::tibble(g = 1:2), type = "grouped")
}

.initial_capture_test_set <- function(where, name, value) {
    locked <- bindingIsLocked(name, where)
    if (locked) unlockBinding(name, where)
    assign(name, value, where)
    if (locked) lockBinding(name, where)
    invisible(NULL)
}

.initial_capture_test_run <- function(route, columns, data, groups = .initial_capture_test_groups()) {
    ns <- asNamespace("dtatools")
    if (route == "shell") return(get(".begin_dibble_result", ns)(data, "mutate()", "columns")$columns)
    mask <- get(".new_dibble_expression_mask", ns)(columns, groups, 4L, "mutate()")
    on.exit(mask$forget())
    mask$values()
}

.initial_capture_test_warm <- function() {
    columns <- .initial_capture_test_columns()
    data <- do.call(dtatools::dibble, columns)
    for (i in 1:3) for (route in c("shell", "batch"))
        invisible(.initial_capture_test_run(route, columns, data))
    invisible(NULL)
}
