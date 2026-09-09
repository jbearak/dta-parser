# Verify installed native tests and explicitly declared process boundaries.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
cfg <- dget(args[[1L]])
sys.source(cfg$guard, envir = .GlobalEnv)
sys.source(cfg$children, envir = .GlobalEnv)

.native_block_results <- function(results, family, directory) {
    saveRDS(results, file.path(directory, "test-results.rds"))
    .native_write(file.path(directory, "test-results.R"), results)
    frame <- as.data.frame(results)
    write.csv(frame[setdiff(names(frame), "result")], file.path(directory, "test-results.csv"), row.names = FALSE)
    .native_require(all(c("file", "test", "passed", "failed", "error", "skipped", "warning", "result") %in%
                            names(frame)), "Unexpected testthat result schema")
    .native_require(nrow(frame) == length(family$blocks), "Missing or extra test blocks")
    key <- function(file, test, occurrence) paste(file, test, occurrence, sep = "\r")
    actual <- character(nrow(frame))
    for (i in seq_len(nrow(frame))) {
        previous <- seq_len(i)
        occurrence <- sum(frame$file[previous] == frame$file[[i]] & frame$test[previous] == frame$test[[i]])
        actual[[i]] <- key(frame$file[[i]], frame$test[[i]], occurrence)
    }
    expected <- vapply(family$blocks, function(b) key(b$file, b$test,
        if (is.null(b$occurrence)) 1 else b$occurrence), "")
    .native_require(!anyDuplicated(actual) && setequal(actual, expected), "Actual file/test membership differs")
    facts <- vector("list", length(expected))
    for (j in seq_along(family$blocks)) {
        b <- family$blocks[[j]]
        i <- match(expected[[j]], actual)
        conditions <- lapply(frame$result[[i]], function(x) list(class = class(x), condition = .native_condition(x)))
        facts[[j]] <- list(file = b$file, test = b$test, policy = b,
                           passed = frame$passed[[i]], failed = frame$failed[[i]],
                           error = frame$error[[i]], skipped = frame$skipped[[i]],
                           warnings = frame$warning[[i]], conditions = conditions)
    }
    .native_write(file.path(directory, "block-accounting.R"), facts)
    for (fact in facts) {
        .native_require(fact$failed == 0 && !fact$error, paste("Test failed:", fact$file, fact$test))
        .native_require(fact$warnings == fact$policy$warnings, "Warning count differs from explicit policy")
        if (identical(fact$policy$skip, "forbid")) .native_require(!fact$skipped, "Required native block skipped")
        if (identical(fact$policy$skip, "require")) .native_require(fact$skipped, "Expected optional skip did not occur")
        if (!fact$skipped) .native_require(fact$passed >= fact$policy$min_pass, "Too few passing assertions")
        if (fact$skipped) .native_require(fact$passed >= fact$policy$min_pass_before_skip,
            "Skip occurred before the required native assertion prefix")
        if (fact$skipped && !is.null(fact$policy$skip_message)) {
            messages <- vapply(Filter(function(x) "expectation_skip" %in% x$class, fact$conditions),
                function(x) x$condition$message$value, "")
            .native_require(any(messages == fact$policy$skip_message), "Actual skip reason differs")
        }
    }
    .native_write(file.path(directory, "counts.R"), list(blocks = nrow(frame), passed = sum(frame$passed),
        failed = sum(frame$failed), errors = sum(frame$error), warnings = sum(frame$warning), skips = sum(frame$skipped)))
    invisible(facts)
}
.native_run_family <- function(family) {
    directory <- file.path(cfg$output, "families", family$id, "observations")
    .native_require(dir.create(directory, recursive = TRUE), "Family observations already exist")
    context_path <- file.path(directory, "context.rds")
    saveRDS(list(cfg = cfg, family = family, output = directory), context_path)
    quote <- function(x) paste(deparse(x, width.cutoff = 500L), collapse = "\n")
    first <- file.path(family$test_root, "helper-000-native-bootstrap.R")
    last <- file.path(family$test_root, "helper-zzz-native-check.R")
    .native_require(!file.exists(first) && !file.exists(last), "Native helper name collision")
    writeLines(c(paste0("sys.source(", quote(cfg$guard), ", envir = environment())"),
        paste0("sys.source(", quote(cfg$children), ", envir = environment())"),
        paste0(".native_context <- readRDS(", quote(context_path), ")"),
        ".native_context$state <- new.env(parent = emptyenv())",
        ".native_context$state$next_child <- 0L",
        ".native_context$state$background <- list()",
        "options(dtatools.native.context = .native_context)",
        ".native_checkpoint(.native_context$cfg, 'before-helpers',",
        "    file.path(.native_context$output, 'before-helpers.R'))"), first, useBytes = TRUE)
    writeLines(c(".native_checkpoint(.native_context$cfg, 'after-helpers',",
        "    file.path(.native_context$output, 'after-helpers.R'))"), last, useBytes = TRUE)
    .native_write(file.path(directory, "generated-helper-inputs.R"),
        list(paths = c(first, last, context_path), md5 = unname(tools::md5sum(c(first, last, context_path)))))
    original <- NULL
    child_error <- NULL
    terminal_error <- NULL
    tryCatch({
        .native_checkpoint(cfg, "before-family", file.path(directory, "before-family.R"))
        testthat::set_max_fails(Inf)
        results <- testthat::test_dir(family$test_root, reporter = "summary", load_helpers = TRUE,
            package = "dtatools", load_package = "installed", stop_on_failure = FALSE)
        .native_block_results(results, family, directory)
    }, error = function(e) { original <<- e }, interrupt = function(e) { original <<- e })
    context <- getOption("dtatools.native.context")
    tryCatch({
        .native_require(is.list(context) && identical(context$output, directory), "Missing or altered family child context")
        .native_check_children(context)
    }, error = function(e) { child_error <<- e })
    tryCatch(.native_checkpoint(cfg, "after-family", file.path(directory, "after-family.R")),
        error = function(e) { terminal_error <<- e })
    .native_write(file.path(directory, "status.R"), list(original_error = .native_condition(original),
        child_error = .native_condition(child_error), terminal_error = .native_condition(terminal_error),
        complete = is.null(original) && is.null(child_error) && is.null(terminal_error)))
    if (!is.null(original)) stop(original)
    if (!is.null(child_error)) stop(child_error)
    if (!is.null(terminal_error)) stop(terminal_error)
    invisible(NULL)
}
.native_main <- function() {
    original <- NULL
    terminal_error <- NULL
    tryCatch({
        .native_prepare(cfg, cfg$output)
        # Manifest coverage includes constant and replacement exports, not only functions.
        .native_require(identical(sort(getNamespaceExports("dtatools")), sort(.native_chr(cfg$exports))), "Exports changed")
        for (family in cfg$families) .native_run_family(family)
    }, error = function(e) { original <<- e }, interrupt = function(e) { original <<- e })
    tryCatch(.native_terminal(cfg, cfg$output, original), error = function(e) { terminal_error <<- e })
    if (!is.null(original)) stop(original)
    if (!is.null(terminal_error)) stop(terminal_error)
    .native_write(file.path(cfg$output, "completed.R"),
        list(lane = cfg$lane, families = vapply(cfg$families, `[[`, "", "id"), exports = .native_chr(cfg$exports),
             scope = "Selected installed native files and declared child policies completed; no full image closure"))
}
.native_main()
