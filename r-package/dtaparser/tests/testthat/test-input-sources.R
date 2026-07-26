input_fixture <- function() {
    system.file("extdata", "auto_v118.dta", package = "dtaparser",
                mustWork = TRUE)
}

read_fixture_bytes <- function() {
    path <- input_fixture()
    readBin(path, "raw", n = file.info(path)$size)
}

expect_source_parity <- function(actual, expected) {
    expect_identical(dim(actual), dim(expected))
    expect_identical(names(actual), names(expected))
    expect_identical(attr(actual, "label", exact = TRUE),
                     attr(expected, "label", exact = TRUE))
    for (name in names(actual)) {
        expect_equal(actual[[name]], expected[[name]], tolerance = 1e-7,
                     info = name)
    }
}

write_compressed_fixture <- function(kind) {
    input <- input_fixture()
    output <- tempfile(fileext = paste0(".", kind))
    bytes <- read_fixture_bytes()

    if (identical(kind, "zip")) {
        if (!nzchar(Sys.which("zip"))) {
            testthat::skip("a zip executable is required")
        }
        directory <- tempfile(pattern = "dtaparser-zip-")
        dir.create(directory)
        copied <- file.path(directory, basename(input))
        file.copy(input, copied)
        old <- setwd(directory)
        on.exit({
            setwd(old)
            unlink(directory, recursive = TRUE)
        }, add = TRUE)
        utils::zip(output, basename(copied))
        if (!file.exists(output) || file.info(output)$size == 0) {
            stop("failed to create zip fixture", call. = FALSE)
        }
        return(output)
    }

    connection <- switch(kind,
        gz = gzfile(output, "wb"),
        bz2 = bzfile(output, "wb"),
        xz = xzfile(output, "wb")
    )
    on.exit(close(connection), add = TRUE)
    writeBin(bytes, connection)
    output
}

start_fixture_server <- function(path) {
    port <- tryCatch(httpuv::randomPort(), error = function(error) {
        testthat::skip("this environment does not permit a loopback server")
    })
    ready <- tempfile(pattern = "dtaparser-http-ready-")
    process <- callr::r_bg(
        function(path, port, ready) {
            bytes <- readBin(path, "raw", n = file.info(path)$size)
            app <- list(call = function(request) {
                list(
                    status = 200L,
                    headers = list("Content-Type" = "application/octet-stream"),
                    body = bytes
                )
            })
            server <- httpuv::startServer("127.0.0.1", port, app)
            on.exit(httpuv::stopServer(server), add = TRUE)
            file.create(ready)
            repeat httpuv::service(100)
        },
        args = list(normalizePath(path), port, ready),
        supervise = TRUE
    )

    deadline <- Sys.time() + 10
    while (!file.exists(ready) && process$is_alive() && Sys.time() < deadline) {
        Sys.sleep(0.02)
    }
    if (!file.exists(ready)) {
        process$kill()
        stop("local HTTP fixture server did not start", call. = FALSE)
    }

    list(
        url = sprintf("http://127.0.0.1:%d/%s", port, basename(path)),
        process = process,
        ready = ready
    )
}

test_that("plain local paths retain the direct path fast path", {
    path <- normalizePath(input_fixture())
    source <- dtaparser:::.resolve_dta_source(path)
    on.exit(dtaparser:::.cleanup_dta_source(source), add = TRUE)

    expect_identical(source$path, path)
    expect_false(source$temporary)
})

test_that("caller-supplied datasource paths are never deleted", {
    path <- tempfile(fileext = ".dta")
    file.copy(input_fixture(), path)
    on.exit(unlink(path), add = TRUE)
    datasource <- readr::datasource(path)
    datasource$env <- new.env(parent = emptyenv())

    source <- dtaparser:::.resolve_dta_source(datasource)
    expect_false(source$temporary)
    dtaparser:::.cleanup_dta_source(source)
    expect_true(file.exists(path))
})

test_that("raw bytes and binary connections match haven", {
    skip_if_not_installed("haven")
    bytes <- read_fixture_bytes()

    actual_raw <- read_dta(
        bytes, col_select = c(make, price), skip = 3, n_max = 5
    )
    expected_raw <- haven::read_dta(
        bytes, col_select = c(make, price), skip = 3, n_max = 5
    )
    expect_source_parity(actual_raw, expected_raw)

    actual_connection <- rawConnection(bytes, "rb")
    expected_connection <- rawConnection(bytes, "rb")
    on.exit(close(actual_connection), add = TRUE)
    on.exit(close(expected_connection), add = TRUE)
    actual <- read_dta(actual_connection, skip = 3, n_max = 5)
    expected <- haven::read_dta(expected_connection, skip = 3, n_max = 5)
    expect_source_parity(actual, expected)

    # haven 2.5.5 resolves a connection twice when col_select is supplied,
    # exhausting a non-rewindable connection before its data pass. Resolve it
    # once so selection remains useful while retaining haven's selected values.
    selected_connection <- rawConnection(bytes, "rb")
    on.exit(close(selected_connection), add = TRUE)
    selected <- read_dta(
        selected_connection, col_select = c(make, price),
        skip = 3, n_max = 5
    )
    expect_source_parity(selected, expected[c("make", "price")])
})

test_that("local compressed sources match haven", {
    skip_if_not_installed("haven")

    for (kind in c("gz", "bz2", "xz", "zip")) {
        path <- write_compressed_fixture(kind)
        on.exit(unlink(path), add = TRUE)
        actual <- read_dta(
            path, col_select = c(make, price), skip = 3, n_max = 5
        )
        expected <- haven::read_dta(
            path, col_select = c(make, price), skip = 3, n_max = 5
        )
        expect_source_parity(actual, expected)
    }
})

test_that("URL sources match haven over a hermetic loopback server", {
    skip_if_not_installed("haven")
    skip_if_not_installed("callr")
    skip_if_not_installed("httpuv")

    gzip <- write_compressed_fixture("gz")
    on.exit(unlink(gzip), add = TRUE)

    for (path in c(input_fixture(), gzip)) {
        server <- start_fixture_server(path)
        actual <- read_dta(
            server$url, col_select = c(make, price), skip = 3, n_max = 5
        )
        expected <- haven::read_dta(
            server$url, col_select = c(make, price), skip = 3, n_max = 5
        )
        server$process$kill()
        unlink(server$ready)
        expect_source_parity(actual, expected)
    }
})

test_that("temporary sources are cleaned automatically after reads and errors", {
    bytes <- read_fixture_bytes()
    resolved <- list()
    original_resolver <- dtaparser:::.resolve_dta_source
    local_mocked_bindings(
        .resolve_dta_source = function(file) {
            source <- original_resolver(file)
            resolved[[length(resolved) + 1L]] <<- list(
                path = source$path,
                temporary = source$temporary
            )
            source
        },
        .package = "dtaparser"
    )

    expect_silent(read_dta(bytes, n_max = 1))
    expect_true(resolved[[1L]]$temporary)
    expect_false(file.exists(resolved[[1L]]$path))
    expect_error(read_dta(as.raw(1:8)), "header|format|small|read|I/O",
                 ignore.case = TRUE)
    expect_true(resolved[[2L]]$temporary)
    expect_false(file.exists(resolved[[2L]]$path))

    connection <- rawConnection(bytes, "rb")
    on.exit(close(connection), add = TRUE)
    expect_silent(read_dta(connection, n_max = 1))
    expect_true(resolved[[3L]]$temporary)
    expect_false(file.exists(resolved[[3L]]$path))

    malformed_connection <- rawConnection(as.raw(1:8), "rb")
    on.exit(close(malformed_connection), add = TRUE)
    expect_error(
        read_dta(malformed_connection),
        "header|format|small|read|I/O",
        ignore.case = TRUE
    )
    expect_true(resolved[[4L]]$temporary)
    expect_false(file.exists(resolved[[4L]]$path))
})

test_that("temporary sources are cleaned when an interrupt unwinds the read", {
    skip_if_not_installed("callr")
    result <- callr::r(
        function(library, bytes) {
            .libPaths(c(library, .libPaths()))
            library(dtaparser)
            path <- NULL
            original_resolver <- dtaparser:::.resolve_dta_source
            testthat::local_mocked_bindings(
                .resolve_dta_source = function(file) {
                    source <- original_resolver(file)
                    path <<- source$path
                    source
                },
                .dta_metadata = function(file) rlang::interrupt(),
                .package = "dtaparser"
            )
            interrupted <- tryCatch(
                {
                    dtaparser::read_dta(bytes)
                    FALSE
                },
                interrupt = function(condition) TRUE
            )
            list(interrupted = interrupted, temporary_exists = file.exists(path))
        },
        args = list(
            dirname(find.package("dtaparser")),
            read_fixture_bytes()
        )
    )

    expect_true(result$interrupted)
    expect_false(result$temporary_exists)
})

test_that("unsupported literal character data matches haven's error", {
    skip_if_not_installed("haven")
    literal <- c("not", "DTA bytes")
    expect_error(read_dta(literal), "kind of input is not handled")
    expect_error(haven::read_dta(literal), "kind of input is not handled")
})
