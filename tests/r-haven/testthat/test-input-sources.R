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
        tryCatch({
            actual <- read_dta(
                server$url, col_select = c(make, price), skip = 3, n_max = 5
            )
            expected <- haven::read_dta(
                server$url, col_select = c(make, price), skip = 3, n_max = 5
            )
            expect_source_parity(actual, expected)
        }, finally = {
            if (server$process$is_alive()) server$process$kill()
            unlink(server$ready)
        })
    }
})

test_that("unsupported literal character data matches haven's error", {
    skip_if_not_installed("haven")
    literal <- c("not", "DTA bytes")
    actual <- tryCatch(read_dta(literal), error = identity)
    expected <- tryCatch(haven::read_dta(literal), error = identity)
    expect_s3_class(actual, "error")
    expect_s3_class(expected, "error")
    expect_identical(conditionMessage(actual), conditionMessage(expected))
})
