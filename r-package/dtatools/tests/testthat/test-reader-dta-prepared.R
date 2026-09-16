.prepare_dta_test <- function(path, encoding = NULL) {
    .Call(dtatools:::C_dtatools_prepare_dta_selection, path, encoding)
}

.read_prepared_dta_test <- function(prepared, columns = NULL, skip = 0,
                                    n_max = Inf, direct = TRUE, compact = TRUE) {
    .Call(dtatools:::C_dtatools_read_prepared_dta, prepared, columns,
          as.double(skip), as.double(n_max), direct, 1L, compact)
}

test_that("prepared DTA metadata and observations retain one file identity", {
    withr::local_envvar(DTATOOLS_EXPERIMENT_DTA_PREPARED = "1")
    directory <- withr::local_tempdir()
    path <- file.path(directory, "source.dta")
    retained <- file.path(directory, "retained.dta")
    expect_true(file.copy(fixture("auto_v118.dta"), path))
    expected <- read_dta(path, col_select = c(price, mpg), output = "tibble")
    replace_path <- function() {
        expect_true(file.rename(path, retained))
        expect_true(file.copy(fixture("all_types_v118.dta"), path))
        gc()
        c("price", "mpg")
    }
    actual <- read_dta(path, col_select = tidyselect::all_of(replace_path()),
                       output = "tibble")
    expect_identical(actual, expected)
    expect_false("price" %in% names(read_dta(path, output = "tibble")))
})

test_that("prepared DTA reads consume once and close idempotently", {
    path <- fixture("auto_v118.dta")
    prepared <- .prepare_dta_test(path)
    withr::defer(dtatools:::.close_prepared_dta(prepared[[1L]]))
    expect_identical(prepared[[2L]], dtatools:::.dta_metadata(path))
    actual <- .read_prepared_dta_test(prepared[[1L]], c(1L, 0L), n_max = 3)
    expect_identical(names(actual), c("price", "make"))
    expect_equal(nrow(actual), 3)
    expect_error(.read_prepared_dta_test(prepared[[1L]]), "already consumed")
    expect_null(dtatools:::.close_prepared_dta(prepared[[1L]]))
    expect_null(dtatools:::.close_prepared_dta(prepared[[1L]]))
    expect_error(.read_prepared_dta_test(prepared[[1L]]), "is closed")
    expect_error(.read_prepared_dta_test(new.env()), "invalid prepared DTA")

    failed <- .prepare_dta_test(path)
    withr::defer(dtatools:::.close_prepared_dta(failed[[1L]]))
    expect_error(.read_prepared_dta_test(failed[[1L]], -1L), "projected column")
    expect_error(.read_prepared_dta_test(failed[[1L]]), "already consumed")
    expect_null(dtatools:::.close_prepared_dta(failed[[1L]]))

    unopened <- .prepare_dta_test(path)
    expect_null(dtatools:::.close_prepared_dta(unopened[[1L]]))
    expect_null(dtatools:::.close_prepared_dta(unopened[[1L]]))
    expect_error(.read_prepared_dta_test(unopened[[1L]]), "is closed")
})

test_that("prepared DTA closes before raw, gzip and connection source cleanup", {
    withr::local_envvar(DTATOOLS_EXPERIMENT_DTA_PREPARED = "1")
    original_close <- dtatools:::.close_prepared_dta
    original_cleanup <- dtatools:::.cleanup_dta_source
    events <- character()
    closed <- NULL
    source_path <- NULL
    local_mocked_bindings(
        .close_prepared_dta = function(prepared) {
            events <<- c(events, "close")
            closed <<- prepared
            original_close(prepared)
        },
        .cleanup_dta_source = function(source) {
            events <<- c(events, "cleanup")
            source_path <<- source$path
            expect_true(source$temporary)
            expect_error(.read_prepared_dta_test(closed), "is closed")
            original_cleanup(source)
        },
        .package = "dtatools"
    )
    path <- fixture("auto_v118.dta")
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    compressed <- withr::local_tempfile(fileext = ".dta.gz")
    output <- gzfile(compressed, "wb")
    writeBin(bytes, output)
    close(output)
    for (kind in c("raw", "gzip", "connection")) {
        for (failure in c(FALSE, TRUE)) {
            events <- character()
            closed <- NULL
            input <- switch(kind, raw = bytes, gzip = compressed,
                            connection = rawConnection(bytes, "rb"))
            if (failure) {
                expect_error(read_dta(input, col_select = tidyselect::all_of("absent_column")),
                             "absent_column")
            } else {
                expect_equal(nrow(read_dta(input, col_select = c(price, mpg), n_max = 2)), 2)
            }
            if (inherits(input, "connection")) close(input)
            expect_identical(events, c("close", "cleanup"), info = kind)
            expect_false(file.exists(source_path), info = kind)
            expect_true(file.exists(compressed))
        }
    }
})

test_that("prepared selection preserves selector warnings and errors", {
    path <- fixture("auto_v118.dta")
    capture_read <- function(prepared, invalid = FALSE) {
        warnings <- list()
        result <- withCallingHandlers(
            tryCatch(withr::with_envvar(
                c(DTATOOLS_EXPERIMENT_DTA_PREPARED = prepared),
                read_dta(path, output = "tibble", col_select = {
                    warning("selector diagnostic", call. = FALSE)
                    tidyselect::all_of(if (invalid) "absent_column" else c("price", "mpg"))
                })
            ), error = function(condition) list(class = class(condition),
                                                 message = conditionMessage(condition))),
            warning = function(condition) {
                warnings[[length(warnings) + 1L]] <<- list(
                    class = class(condition), message = conditionMessage(condition)
                )
                invokeRestart("muffleWarning")
            }
        )
        list(result = result, warnings = warnings)
    }
    for (invalid in c(FALSE, TRUE)) {
        expected <- capture_read("0", invalid)
        actual <- capture_read("1", invalid)
        expect_identical(actual, expected)
        expect_identical(actual$warnings[[1L]]$message, "selector diagnostic")
    }
})

test_that("an interrupted selector closes prepared DTA before source cleanup", {
    withr::local_envvar(DTATOOLS_EXPERIMENT_DTA_PREPARED = "1")
    original_close <- dtatools:::.close_prepared_dta
    original_cleanup <- dtatools:::.cleanup_dta_source
    events <- character()
    source_path <- NULL
    local_mocked_bindings(
        .close_prepared_dta = function(prepared) {
            events <<- c(events, "close")
            original_close(prepared)
        },
        .cleanup_dta_source = function(source) {
            events <<- c(events, "cleanup")
            source_path <<- source$path
            original_cleanup(source)
        },
        .package = "dtatools"
    )
    path <- fixture("auto_v118.dta")
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    interrupted <- tryCatch({
        read_dta(bytes, col_select = { rlang::interrupt(); tidyselect::everything() })
        FALSE
    }, interrupt = function(condition) TRUE)
    expect_true(interrupted)
    expect_identical(events, c("close", "cleanup"))
    expect_false(file.exists(source_path))
})

test_that("full DTA reads reuse decode plans without selection metadata discovery", {
    withr::local_envvar(DTATOOLS_EXPERIMENT_DTA_PREPARED = "1")
    local_mocked_bindings(
        .dta_metadata = function(...) stop("unexpected metadata preflight"),
        .close_prepared_dta = function(...) stop("unexpected prepared read"),
        .package = "dtatools"
    )
    for (name in c("auto_v118.dta", "synthetic_v105.dta", "all_types_v115.dta",
                   "wide_v118.dta", "empty_v118.dta", "value_labels_v118.dta",
                   "strl_test_v118.dta")) {
        for (compact in c(TRUE, FALSE)) {
            for (window in list(c(1, 3), c(0, 0))) {
                read_full <- function() read_dta(
                    fixture(name), skip = window[[1L]], n_max = window[[2L]],
                    threads = 4L, use_numeric_altrep = compact, output = "tibble"
                )
                expected <- withr::with_envvar(
                    c(DTATOOLS_EXPERIMENT_DTA_PREPARED = "0"), read_full()
                )
                expect_identical(read_full(), expected, info = paste(name, compact))
            }
        }
    }
})

test_that("prepared selections preserve legacy, wide, empty and labelled reads", {
    paths <- c("synthetic_v105.dta", "synthetic_v108.dta", "synthetic_v110.dta",
               "synthetic_v111.dta", "all_types_v115.dta", "all_types_v117.dta",
               "all_types_v118.dta", "wide_v115.dta", "wide_v118.dta",
               "empty_v115.dta", "empty_v118.dta", "value_labels_v115.dta",
               "value_labels_v118.dta", "strl_test_v118.dta")
    for (name in paths) {
        path <- fixture(name)
        columns <- rev(as.character(dtatools:::.dta_metadata(path)))
        selections <- list(columns, head(columns, 3L), character())
        for (selected in selections) {
            for (window in list(c(0, Inf), c(1, 3), c(0, 0), c(1e6, 2))) {
                for (compact in c(TRUE, FALSE)) {
                    read_selected <- function() read_dta(
                        path, col_select = tidyselect::all_of(selected),
                        skip = window[[1L]], n_max = window[[2L]],
                        use_numeric_altrep = compact, threads = 4L, output = "tibble"
                    )
                    expected <- withr::with_envvar(
                        c(DTATOOLS_EXPERIMENT_DTA_PREPARED = "0"), read_selected()
                    )
                    actual <- withr::with_envvar(
                        c(DTATOOLS_EXPERIMENT_DTA_PREPARED = "1"), read_selected()
                    )
                    expect_identical(actual, expected,
                                     info = paste(name, length(selected),
                                                  paste(window, collapse = ":"), compact))
                }
            }
        }
    }
})

test_that("prepared proxies, renaming and collector reads preserve labels", {
    for (name in c("auto_v118.dta", "all_types_v115.dta", "value_labels_v118.dta")) {
        path <- fixture(name)
        for (reader in list(function(...) read_dta(..., output = "tibble"),
                            dtatools:::.read_dta_rust_vectors)) {
            read_selected <- function() reader(
                path, col_select = c(tidyselect::where(is.numeric),
                                     renamed = tidyselect::last_col()),
                skip = 1, n_max = 3
            )
            expected <- withr::with_envvar(
                c(DTATOOLS_EXPERIMENT_DTA_PREPARED = "0"), read_selected()
            )
            actual <- withr::with_envvar(
                c(DTATOOLS_EXPERIMENT_DTA_PREPARED = "1"), read_selected()
            )
            expect_identical(actual, expected, info = name)
        }
    }
})
