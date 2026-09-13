input_fixture <- function() {
    system.file("extdata", "auto_v118.dta", package = "dtatools",
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
        expect_equal(
            without_dta_storage(actual[[name]]),
            expected[[name]],
            tolerance = 1e-7,
            info = name
        )
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
        directory <- tempfile(pattern = "dtatools-zip-")
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
    ready <- tempfile(pattern = "dtatools-http-ready-")
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
    if (!file.exists(ready) || !process$is_alive()) {
        if (process$is_alive()) process$kill()
        unlink(ready)
        stop("local HTTP fixture server did not start", call. = FALSE)
    }

    list(
        url = sprintf("http://127.0.0.1:%d/%s", port, basename(path)),
        process = process,
        ready = ready
    )
}

test_that("plain local paths retain the direct path fast path", {
    path <- normalizePath(input_fixture(), winslash = "/")
    source <- dtatools:::.resolve_dta_source(path)
    on.exit(dtatools:::.cleanup_dta_source(source), add = TRUE)

    expect_identical(source$path, path)
    expect_false(source$temporary)
})

test_that("first local reads avoid source-adapter dependency loading", {
    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(arrow_path), add = TRUE)
    expected <- read_dta(input_fixture(), n_max = 2)
    save_arrow(expected, arrow_path)
    legacy_path <- tempfile(fileext = ".dta")
    on.exit(unlink(legacy_path), add = TRUE)
    legacy <- fixture("auto_v115.dta")
    bytes <- readBin(legacy, "raw", n = file.info(legacy)$size)
    # Real legacy survey files have nonzero values in this unused byte.
    bytes[[4L]] <- as.raw(255L)
    writeBin(bytes, legacy_path)
    paths <- c(input_fixture(), legacy, legacy_path, arrow_path)
    for (index in seq_along(paths)) {
        path <- paths[[index]]
        reader <- if (identical(path, arrow_path)) "read_arrow" else "read_dta"
        result <- .dtatools_child_r("local-source-startup", function(reader, path) {
            before <- loadedNamespaces()
            read <- getExportedValue("dtatools", reader)
            data <- read(path, n_max = 2)
            list(loaded = setdiff(loadedNamespaces(), before),
                 dimensions = dim(data), names = names(data),
                 mpg = as.double(data$mpg))
        }, args = list(reader, path))
        expect_false(any(c("readr", "tools") %in% result$loaded))
        expect_identical(result$dimensions, dim(expected))
        expect_identical(result$names, names(expected))
        expect_identical(result$mpg, as.double(expected$mpg))
    }
})

test_that("local source detection preserves content and caller ownership", {
    directory <- tempfile(pattern = "dtatools-local-source-")
    dir.create(directory)
    on.exit(unlink(directory, recursive = TRUE), add = TRUE)
    expected <- read_dta(input_fixture())
    for (name in c("plain.gz", "survey data.dta", "\u00e9tude.dta")) {
        path <- file.path(directory, name)
        expect_true(file.copy(input_fixture(), path))
        expect_identical_table(read_dta(path), expected)
        expect_true(file.exists(path))
    }
    for (kind in c("gz", "bz2", "xz")) {
        compressed <- write_compressed_fixture(kind)
        on.exit(unlink(compressed), add = TRUE)
        path <- file.path(directory, paste0(kind, ".dta"))
        expect_true(file.copy(compressed, path))
        expect_identical_table(read_dta(path), expected)
        expect_true(file.exists(path))
    }
    expect_error(read_dta(I(input_fixture())), "not handled")
    expect_error(read_dta(c(input_fixture(), input_fixture())), "not handled")
    if (.Platform$OS.type == "unix") {
        path <- file.path(directory, "line\nbreak.dta")
        expect_true(file.copy(input_fixture(), path))
        expect_error(read_dta(path), "not handled")
        expect_true(file.exists(path))
        link <- file.path(directory, "linked.dta")
        expect_true(file.symlink(input_fixture(), link))
        expect_identical_table(read_dta(link), expected)
        expect_true(file.exists(link))
    }
    malformed <- file.path(directory, "malformed.dta")
    writeBin(charToRaw("<stata_dta>"), malformed)
    expect_error(read_dta(malformed))
    expect_true(file.exists(malformed))
})

test_that("compressed Arrow content retains source-adapter handling", {
    paths <- vapply(seq_len(4L), function(i) tempfile(fileext = ".arrow"), "")
    on.exit(unlink(paths), add = TRUE)
    expected <- read_dta(input_fixture(), n_max = 2)
    save_arrow(expected, paths[[1L]])
    bytes <- readBin(paths[[1L]], "raw", n = file.info(paths[[1L]])$size)
    writers <- list(gzfile, bzfile, xzfile)
    for (index in seq_along(writers)) {
        path <- paths[[index + 1L]]
        connection <- writers[[index]](path, "wb")
        tryCatch(writeBin(bytes, connection), finally = close(connection))
        expect_identical_table(read_arrow(path), expected)
        expect_true(file.exists(path))
    }
})

test_that("implicit read extensions retain file_ext semantics", {
    paths <- c("survey", ".hidden", "..hidden", "survey.", "survey.dta",
               "survey.dta.gz", "survey.a-b", "survey.a_b", "survey.123",
               "directory.with.dots/survey", "survey.\u00e9", "...")
    for (path in paths) {
        expected <- if (nzchar(tools::file_ext(basename(path)))) path else
            paste0(path, ".dta")
        expect_identical(dtatools:::.resolve_implicit_dta_read_path(path), expected)
    }
})

test_that("local readers ignore global filesystem helpers", {
    expected <- read_dta(input_fixture(), n_max = 2)
    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(arrow_path), add = TRUE)
    save_arrow(expected, arrow_path)
    rlang::local_bindings(
        file_test = function(...) stop("global file_test must not be called"),
        .env = globalenv()
    )
    expect_identical_table(read_dta(input_fixture(), n_max = 2), expected)
    expect_identical_table(read_arrow(arrow_path), expected)
})

test_that("extensionless local reads resolve to the matching .dta file", {
    base <- tempfile(pattern = "dtatools-extensionless-")
    dta <- paste0(base, ".dta")
    file.copy(input_fixture(), dta)
    writeBin(as.raw(1:8), base)
    on.exit(unlink(c(base, dta)), add = TRUE)

    actual <- read_dta(base, n_max = 2)
    expected <- read_dta(dta, n_max = 2)
    expect_identical_table(actual, expected)
})

test_that("caller-supplied datasource paths are never deleted", {
    path <- tempfile(fileext = ".dta")
    file.copy(input_fixture(), path)
    on.exit(unlink(path), add = TRUE)
    direct_source <- dtatools:::.resolve_dta_source(path)
    expect_false(direct_source$temporary)
    dtatools:::.cleanup_dta_source(direct_source)
    expect_true(file.exists(path))

    datasource <- readr::datasource(path)
    datasource$env <- new.env(parent = emptyenv())

    source <- dtatools:::.resolve_dta_source(datasource)
    expect_false(source$temporary)
    dtatools:::.cleanup_dta_source(source)
    expect_true(file.exists(path))
})




test_that("temporary sources are cleaned automatically after reads and errors", {
    bytes <- read_fixture_bytes()
    resolved <- list()
    original_resolver <- dtatools:::.resolve_dta_source
    local_mocked_bindings(
        .resolve_dta_source = function(file) {
            source <- original_resolver(file)
            resolved[[length(resolved) + 1L]] <<- list(
                path = source$path,
                temporary = source$temporary
            )
            source
        },
        .package = "dtatools"
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
    path <- NULL
    original_resolver <- dtatools:::.resolve_dta_source
    local_mocked_bindings(
        .resolve_dta_source = function(file) {
            source <- original_resolver(file)
            path <<- source$path
            source
        },
        .dta_metadata = function(file, encoding = NULL) rlang::interrupt(),
        .package = "dtatools"
    )
    interrupted <- tryCatch(
        {
            read_dta(
                read_fixture_bytes(), col_select = tidyselect::everything()
            )
            FALSE
        },
        interrupt = function(condition) TRUE
    )

    expect_true(interrupted)
    expect_false(file.exists(path))
})
