source(test_path("fixtures", "initial-capture-helpers.R"), local = TRUE)

.initial_capture_names_expected <- function() {
    .dtatools_execution_profile_expected() &&
        identical(as.character(getNamespaceVersion("rlang")), "1.3.0")
}

# groups$rows runs after the constructor's ordinary R name validation and
# before native admission. It can change the input by reference without
# replacing any of the helpers that native capture qualifies.
.initial_capture_names_run <- function(width, mode, change = NULL) {
    columns <- .initial_capture_test_columns(width)
    groups <- new.env(parent = emptyenv())
    groups$type <- "ungrouped"
    groups$names <- character()
    events <- character()
    foreign_reads <- 0L
    foreign_kept <- FALSE
    makeActiveBinding("rows", function() {
        events <<- c(events, "rows")
        if (!is.null(change)) {
            replacement <- change(names(columns))
            if (identical(replacement, "<foreign names>")) {
                replacement <- .initial_capture_test_call(
                    "C_dtatools_callback_character", names(columns), function() {
                        foreign_reads <<- foreign_reads + 1L
                    })
                .initial_capture_test_call("C_dtatools_set_attribute", columns, "names", replacement)
                foreign_kept <<- dtatools:::.is_altrep(names(columns))
                foreign_reads <<- 0L
            } else data.table::setattr(columns, "names", replacement)
        }
        list(1:4)
    }, groups)
    previous <- .initial_capture_test_call("C_dtatools_initial_capture_mode", as.integer(mode))
    on.exit(.initial_capture_test_call("C_dtatools_initial_capture_mode", previous))
    invisible(.initial_capture_test_counts(TRUE))
    error <- NULL
    mask <- NULL
    on.exit(if (!is.null(mask)) try(mask$forget(), silent = TRUE), add = TRUE)
    value <- tryCatch({
        mask <- dtatools:::.new_dibble_expression_mask(columns, groups, 4L, "mutate()")
        mask$values()
    }, error = function(condition) {
        error <<- list(class = class(condition), message = conditionMessage(condition))
        NULL
    })
    counts <- .initial_capture_test_counts()
    cleanup <- tryCatch({
        if (!is.null(mask)) mask$forget()
        NULL
    }, error = function(condition) list(class = class(condition), message = conditionMessage(condition)))
    list(value = value, error = error, cleanup = cleanup, events = events, reads = foreign_reads,
         foreign_kept = foreign_kept, counts = counts)
}

.initial_capture_names_parity <- function(width, change, admitted = FALSE, info = "") {
    enabled <- .initial_capture_names_run(width, 3L, change)
    fallback <- .initial_capture_names_run(width, 0L, change)
    expect_identical(enabled$value, fallback$value, info = info)
    expect_identical(enabled$error, fallback$error, info = info)
    expect_identical(enabled$cleanup, fallback$cleanup, info = info)
    expect_identical(enabled$events, "rows", info = info)
    expect_identical(enabled$events, fallback$events, info = info)
    expect_identical(enabled$reads, fallback$reads, info = info)
    expect_identical(enabled$counts[["batch_admitted"]],
                     as.double(admitted && width > 128L && .initial_capture_names_expected()), info = info)
    expect_identical(fallback$counts[["batch_attempts"]], 0, info = info)
    invisible(list(enabled = enabled, fallback = fallback))
}

test_that("initial capture duplicate checks preserve width limits and full name comparisons", {
    .initial_capture_test_warm()
    for (width in c(63L, 64L, 65L, 100L, 128L, 129L, 256L, 4095L, 4096L, 4097L)) {
        observed <- .initial_capture_names_parity(width, identity,
            admitted = width >= 64L && width <= 4096L, info = paste("width", width))
        expect_null(observed$enabled$error)
        expect_length(observed$enabled$value, width)
    }
    collisions <- readLines(test_path("fixtures", "initial-capture-collision-names.txt"))
    expect_length(unique(collisions), 100L)
    collision_names <- c(collisions, paste0("extra_", seq_len(156L)))
    observed <- .initial_capture_names_parity(256L, function(names) collision_names,
        admitted = TRUE, info = "100 distinct names sharing the low eight hash bits")
    expect_identical(names(observed$enabled$value), collision_names)
})

test_that("initial capture declines duplicate names introduced after R validation", {
    .initial_capture_test_warm()
    collisions <- readLines(test_path("fixtures", "initial-capture-collision-names.txt"))
    for (case in c("adjacent", "distant", "collision", "last-slot")) {
        width <- if (case == "last-slot") 4096L else 256L
        change <- function(names) {
            if (case == "collision") names <- c(collisions, names[-seq_along(collisions)])
            names[[if (case == "adjacent") 2L else length(names)]] <- names[[1L]]
            names
        }
        observed <- .initial_capture_names_parity(width, change, info = case)
        expect_null(observed$enabled$error)
        expect_length(observed$enabled$value, width - 1L)
        expect_identical(observed$enabled$counts[["shape_decline"]],
                         as.double(.initial_capture_names_expected()))
    }
})

test_that("initial capture keeps ASCII encoding and name length boundaries", {
    .initial_capture_test_warm()
    cases <- list(
        nonsyntactic = function(names) { names[[1L]] <- "an ASCII name + punctuation!"; names },
        ascii_utf8 = function(names) { Encoding(names) <- "UTF-8"; names },
        ascii_latin1 = function(names) { Encoding(names) <- "latin1"; names },
        length1024 = function(names) { names[[1L]] <- strrep("a", 1024L); names },
        length1025 = function(names) { names[[1L]] <- strrep("a", 1025L); names },
        utf8 = function(names) { names[[1L]] <- enc2utf8("caf\u00e9"); names },
        latin1 = function(names) { names[[1L]] <- iconv("caf\u00e9", to = "latin1"); names },
        bytes = function(names) {
            value <- rawToChar(as.raw(c(120L, 233L)))
            Encoding(value) <- "bytes"
            names[[1L]] <- value
            names
        },
        empty = function(names) { names[[1L]] <- ""; names },
        missing = function(names) { names[[1L]] <- NA_character_; names }
    )
    accepted <- c("nonsyntactic", "ascii_utf8", "ascii_latin1", "length1024")
    for (case in names(cases)) {
        observed <- .initial_capture_names_parity(256L, cases[[case]],
            admitted = case %in% accepted, info = case)
        if (!case %in% accepted) expect_identical(
            observed$enabled$counts[["shape_decline"]],
            as.double(.initial_capture_names_expected()), info = case)
    }
})

test_that("initial capture leaves deferred foreign name reads on the fallback route", {
    .initial_capture_test_warm()
    observed <- .initial_capture_names_parity(256L, function(names) "<foreign names>")
    expect_true(observed$enabled$foreign_kept)
    expect_true(observed$fallback$foreign_kept)
    expect_gt(observed$enabled$reads, 0L)
    expect_null(observed$enabled$error)
    expect_identical(observed$enabled$counts[["shape_decline"]],
                     as.double(.initial_capture_names_expected()))
})
