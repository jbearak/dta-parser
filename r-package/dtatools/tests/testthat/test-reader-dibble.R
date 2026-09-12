test_that("direct reader dibbles preserve the general constructor's semantics", {
    for (name in c("auto_v118.dta", "all_types_v118.dta",
                   "missing_values_v115.dta", "missing_values_v118.dta")) {
        path <- fixture(name)
        arrow_path <- tempfile(fileext = ".arrow")
        save_arrow(read_dta(path, output = "tibble"), arrow_path)
        for (reader in list(read_dta, read_arrow)) {
            input <- if (identical(reader, read_dta)) path else arrow_path
            for (compact in c(TRUE, FALSE)) {
                for (window in list(list(), list(skip = 1, n_max = 2),
                                    list(n_max = 0), list(skip = 1e6))) {
                    args <- c(list(file = input, use_numeric_altrep = compact), window)
                    direct <- do.call(reader, c(args, list(output = "dibble")))
                    ordinary <- do.call(reader, c(args, list(output = "tibble")))
                    expected <- as_dibble(ordinary)
                    expect_equal(.reference_snapshot(direct), .reference_snapshot(expected))
                    expect_identical(datasig(direct), datasig(expected))
                    expect_true(.reference_state_valid(direct))
                    expect_gte(column_capacity(direct), ncol(direct) + 1024L)
                }
            }
        }
        unlink(arrow_path)
    }
})

test_that("direct readers retain name repair and empty projection rules", {
    dta_path <- fixture("all_types_v118.dta")
    arrow_path <- tempfile(fileext = ".arrow")
    on.exit(unlink(arrow_path), add = TRUE)
    save_arrow(read_dta(dta_path), arrow_path)
    for (reader in list(read_dta, read_arrow)) {
        input <- if (identical(reader, read_dta)) dta_path else arrow_path
        calls <- 0L
        repair <- function(names) {
            calls <<- calls + 1L
            paste0("column ", seq_along(names))
        }
        result <- reader(input, .name_repair = repair)
        expect_identical(calls, 1L)
        expect_identical(names(result), paste0("column ", seq_len(ncol(result))))
        expect_error(reader(input, .name_repair = function(x) rep("x", length(x))),
                     "a dibble needs unique, non-missing column names")
        expect_error(reader(input, .name_repair = function(x) rep("", length(x))),
                     "a dibble needs unique, non-missing column names")
        empty <- reader(input, col_select = integer(), skip = 1, n_max = 2)
        expect_identical(dim(empty), c(2L, 0L))
        expect_true(.reference_state_valid(empty))
        selected <- reader(input, col_select = c(renamed = 2, 1), n_max = 2)
        expect_identical(names(selected)[[1L]], "renamed")
        expect_equal(.reference_snapshot(selected), .reference_snapshot(as_dibble(
            reader(input, col_select = c(renamed = 2, 1), n_max = 2, output = "tibble")
        )))
    }
})

test_that("direct reader ownership survives exports writes and file removal", {
    source <- dibble(x = dta_double(c(1, 2, 3)),
                     compact = dta_int(c(1, 2, 3)), text = c("a", "bb", ""))
    for (kind in c("dta", "arrow")) {
        path <- tempfile(fileext = paste0(".", kind))
        if (kind == "dta") save_dta(source, path) else save_arrow(source, path)
        data <- if (kind == "dta") read_dta(path) else read_arrow(path)
        unlink(path)
        gc()
        expect_true(.is_unmaterialized_numeric_altrep(.subset2(data, "compact")))
        expect_true(.is_unmaterialized_dictstring(.subset2(data, "text")))
        expect_false(.Call(C_dtatools_owned_info, .subset2(data, "x"))$exposed)
        saved <- data[, ]
        exported <- as.data.frame(data)
        pointer <- .Call(C_dtatools_owned_pointer, exported$x, TRUE)
        .Call(C_dtatools_owned_pointer_write, pointer, 1L, 9)
        expect_identical(as.double(data$x), c(1, 2, 3))
        expect_identical(as.double(saved$x), c(1, 2, 3))
        replace_values(data, x, 7, where = 2L)
        replace_values(data, text, "cc", where = 2L)
        expect_identical(as.double(saved$x), c(1, 2, 3))
        expect_identical(as.character(saved$text), c("a", "bb", ""))
        expect_identical(as.double(exported$x), c(9, 2, 3))
        alias <- data
        gen(data, added = 1L)
        expect_identical(as.integer(alias$added), rep(1L, 3L))
        expect_true(.reference_state_valid(data))
    }
})

test_that("direct Arrow dibbles normalize ordinary R columns and retain metadata", {
    data <- tibble::tibble(
        integer = c(1L, NA, 3L), double = c(1.5, NA, 3.25),
        logical = c(TRUE, NA, FALSE), text = c("alpha", NA, ""),
        dictionary = c("a", "bb", "a"),
        factor = ordered(c("a", NA, "b"), levels = c("a", "b", "unused")),
        date = as.Date(c("2000-01-01", NA, "2020-01-01")),
        datetime = as.POSIXct(c(1, NA, 3), origin = "1970-01-01", tz = "UTC"),
        duration = as.difftime(c(1, NA, 3), units = "hours"), raw = as.raw(1:3)
    )
    set_dta_note(data, 1L, "dataset note")
    set_dta_note(data, 2L, "variable note", variable = "text")
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    save_arrow(data, path)
    for (profile in c(TRUE, FALSE)) {
        direct <- read_arrow(path, output = "dibble", profile = profile)
        expected <- as_dibble(read_arrow(path, output = "tibble", profile = profile))
        expect_equal(.reference_snapshot(direct), .reference_snapshot(expected))
        expect_true(.reference_state_valid(direct))
        # A classed ordinary string carrying notes keeps the general
        # constructor's passthrough policy, including its NA.
        expect_identical(as.character(direct$text),
                         c("alpha", if (profile) NA_character_ else "", ""))
        expect_identical(dta_storage_type(direct$integer), "long")
        expect_identical(dta_storage_type(direct$double), "double")
        expect_identical(direct$logical, c(TRUE, NA, FALSE))
    }
    expect_false(is_dibble(read_arrow(path)))
    withr::local_options(dtatools.output = "dibble")
    expect_false(is_dibble(read_arrow(path)))
    signed <- read_arrow(path, output = "dibble", datasig = TRUE, n_max = 1)
    expect_identical(attr(signed, "datasig"), datasig(path))
    expect_identical(dta_notes(signed), dta_notes(data))
})

test_that("direct Arrow dibbles repair declarations that do not fit the values", {
    skip_if_not_installed("arrow")
    schema <- arrow::schema(arrow::field("text", arrow::utf8(), metadata = list(
        "dtatools:field" = '{"version":0,"string_storage":"str1"}'
    )))$WithMetadata(list("dtatools:profile-version" = "0"))
    path <- tempfile(fileext = ".arrow")
    on.exit(unlink(path), add = TRUE)
    for (values in list(c("\u00e9", "wide", ""), c("\u00e9", NA, ""))) {
        arrow::write_ipc_file(arrow::Table$create(text = values, schema = schema), path)
        result <- read_arrow(path, output = "dibble", verify = FALSE)
        expected <- as_dibble(read_arrow(path, output = "tibble", verify = FALSE))
        expect_equal(.reference_snapshot(result), .reference_snapshot(expected))
        expect_identical(as.character(result$text), replace(values, is.na(values), ""))
        expect_true(.string_declaration_holds(result$text))
    }
})

test_that("direct DTA dibbles widen strings expanded by decoding", {
    path <- tempfile(fileext = ".dta")
    on.exit(unlink(path), add = TRUE)
    save_dta(dibble(text = dta_string("x", storage = "str1")), path)
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    start <- grepRaw(charToRaw("<data>"), bytes, fixed = TRUE)
    bytes[start + 6L] <- as.raw(0xe9)
    writeBin(bytes, path)
    direct <- read_dta(path, encoding = "CP1252", datasig = TRUE)
    ordinary <- read_dta(path, encoding = "CP1252", output = "tibble", datasig = TRUE)
    expect_equal(.reference_snapshot(direct), .reference_snapshot(as_dibble(ordinary)))
    expect_identical(as.character(direct$text), "\u00e9")
    expect_identical(dta_storage_type(direct$text), "str2")
    expect_identical(attr(direct, "datasig"), attr(ordinary, "datasig"))
})
