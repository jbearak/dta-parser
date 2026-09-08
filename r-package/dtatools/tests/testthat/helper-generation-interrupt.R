native_generation_interrupt_cases <- function(package_path, load_package, mode) {
    load_package(package_path)
    inject <- get("C_dtatools_inject_generation_interrupt", asNamespace("dtatools"))
    run_case <- function(name, values, existing = FALSE, dictionary = FALSE) {
        on.exit(.Call(inject, 0L), add = TRUE)
        data <- reserve_columns(data.frame(anchor = dta_byte(.size = 8L)))
        if (existing) gen(data, prior, 1)
        alias <- data
        before <- serialize(data, NULL)
        names_before <- names(data)
        state_before <- dtatools:::.reference_state(data)
        reference_before <- inherits(data, "dtatools_ref_data")
        cache_before <- if (dictionary) dtatools:::.dictstring_cached_count(values)
        cat("[dtatools-test-generation-case] ", name, "\n", sep = "")
        .Call(inject, mode)
        condition <- tryCatch({
            gen(data, created, .env$values)
            NULL
        }, condition = identity)
        checks <- list(
            interrupted = inherits(condition, "interrupt"),
            unchanged = identical(serialize(data, NULL), before),
            alias_unchanged = identical(serialize(alias, NULL), before),
            names = identical(names(data), names_before),
            reference = identical(inherits(data, "dtatools_ref_data"), reference_before),
            state = identical(dtatools:::.reference_state(data), state_before)
        )
        if (dictionary) {
            checks$source_compact <- dtatools:::.is_unmaterialized_dictstring(values)
            checks$source_cache <- identical(dtatools:::.dictstring_cached_count(values), cache_before)
        }
        # Do not clear the injection before retry: native entry must consume it.
        retry_condition <- tryCatch({
            gen(data, retry, .env$values)
            NULL
        }, condition = identity)
        checks$retry_completed <- is.null(retry_condition)
        checks$retry_names <- identical(names(alias), c(names_before, "retry"))
        expected <- if (dictionary) rep(c("a", "b"), 4L) else
            rep_len(if (is.character(values)) as.character(values) else as.double(values), 8L)
        observed <- if (!is.null(retry_condition)) NULL else
            if (is.character(values)) as.character(data$retry) else as.double(data$retry)
        checks$retry_values <- identical(observed, expected)
        if (dictionary) {
            checks$retry_source_compact <- dtatools:::.is_unmaterialized_dictstring(values)
            checks$retry_source_cache <- identical(dtatools:::.dictstring_cached_count(values), cache_before)
        }
        list(checks = checks, condition = class(condition), retry_condition = class(retry_condition))
    }
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data.frame(source = rep(c("a", "b"), 4L)), path)
    source <- read_arrow(path)$source
    list(
        numeric_first = run_case("numeric_first", seq_len(8L)),
        numeric_existing = run_case("numeric_existing", seq_len(8L), TRUE),
        character_first = run_case("character_first", "x"),
        character_existing = run_case("character_existing", "x", TRUE),
        dictionary = run_case("dictionary", source, dictionary = TRUE),
        double_first = run_case("double_first", dta_double(seq_len(8L))),
        double_existing = run_case("double_existing", dta_double(seq_len(8L)), TRUE)
    )
}

expect_generation_interrupt_cases <- function(result) {
    for (name in names(result)) {
        case <- result[[name]]
        for (check in names(case$checks)) {
            expect_true(case$checks[[check]], info = paste(name, check,
                paste(case$condition, collapse = "/"),
                "retry", paste(case$retry_condition, collapse = "/")))
        }
    }
}

run_posix_generation_interrupt_cases <- function(package_path, load_package) {
    process <- callr::r_bg(native_generation_interrupt_cases,
        args = list(package_path = package_path, load_package = load_package, mode = 2L),
        libpath = .libPaths(), stdout = "|", stderr = "|", supervise = TRUE)
    on.exit(process$kill(), add = TRUE)
    sent <- character()
    error_lines <- character()
    current <- NULL
    started <- Sys.time()
    while (process$is_alive()) {
        process$poll_io(100)
        error_lines <- tail(c(error_lines, process$read_error_lines()), 100L)
        lines <- process$read_output_lines()
        for (line in lines) {
            if (startsWith(line, "[dtatools-test-generation-case] ")) {
                current <- substring(line, nchar("[dtatools-test-generation-case] ") + 1L)
            }
            if (identical(line, "[dtatools-test-generation-ready]")) {
                stopifnot(!is.null(current), !current %in% sent)
                stopifnot(tools::pskill(process$get_pid(), tools::SIGINT))
                sent <- c(sent, current)
            }
        }
        if (as.numeric(difftime(Sys.time(), started, units = "secs")) > 30) {
            stop("Timed out waiting for native generation checkpoints: ",
                paste(sent, collapse = ", "), "\nRecent child stderr:\n",
                paste(error_lines, collapse = "\n"))
        }
    }
    result <- process$get_result()
    stopifnot(identical(sent, names(result)))
    result
}
