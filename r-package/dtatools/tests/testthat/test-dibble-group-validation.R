.group_validation_frame <- function(value, key, rows, owned = FALSE, id,
                                    plain_spec = NULL) {
    if (is.null(plain_spec)) {
        plain_spec <- .group_fixture_spec(
            tibble::new_tibble(list(g = value), nrow = NROW(value)))
    }
    if (owned) {
        value <- .Call(dtatools:::C_dtatools_capture_column, value)
        key <- .Call(dtatools:::C_dtatools_capture_column, key)
    }
    .group_fixture_attach(id,
        tibble::new_tibble(list(g = value), nrow = NROW(value)), plain_spec,
        groups = tibble::new_tibble(list(g = key, .rows = rows), nrow = NROW(key)))
}

.group_validation_snapshot <- function(x) list(
    values = vapply(seq_along(x), function(i) x[[i]], ""),
    encodings = Encoding(x), attributes = attributes(x),
    attribute_encodings = lapply(attributes(x), function(value)
        if (is.character(value)) Encoding(value) else NULL))

test_that("character group validation preserves equality and owned backing", {
    utf8 <- enc2utf8("é")
    latin1 <- iconv(utf8, from = "UTF-8", to = "latin1")
    for (owned in c(FALSE, TRUE)) {
        value <- structure(c(latin1, "longer", utf8, NA_character_),
            stata.string.storage = "str1", label = "Unchanged declaration")
        key <- structure(c("unused", utf8, "longer", NA_character_),
            stata.string.storage = "str1")
        data <- .group_validation_frame(value, key,
            vctrs::list_of(integer(), c(1L, 3L), 2L, 4L), owned,
            id = "character_encoding")
        before <- .Call(dtatools:::C_dtatools_owned_info, data$g)
        expect_silent(dtatools:::.validate_group_metadata(data))
        # Public matching may create a temporary encoding-normalization fork.
        # Its conservative shared flag may persist; backing and exposure must not change.
        after <- .Call(dtatools:::C_dtatools_owned_info, data$g)
        fields <- c("backing", "exposed", "bytes", "depth")
        expect_identical(after[fields], before[fields])
        expect_identical(as.character(data$g), as.character(value))
        expect_identical(Encoding(data$g), Encoding(value))
        expect_identical(attributes(data$g), attributes(value))
    }
    # Individual keys may repeat while complete group tuples are unique.
    data <- .group_fixture("multi_aaba")$data
    expect_silent(dtatools:::.validate_group_metadata(data))
    attr(data, "groups")$g[1L] <- "wrong"
    expect_error(dtatools:::.validate_group_metadata(data), "keys that do not match")
    expect_silent(dtatools:::.validate_group_metadata(.group_validation_frame(
        character(), character(), vctrs::list_of(.ptype = integer()),
        id = "character_empty")))
})

test_that("group validation retains declaration errors and foreign length fallback", {
    for (side in c("value", "key")) for (storage in list(1L, c("byte", "int"))) {
        value <- c("b", "a", "b"); key <- c("b", "a")
        data <- .group_validation_frame(value, key, vctrs::list_of(c(1L, 3L), 2L),
            id = "character_bab")
        # Apply the intentional corruption without a grouped replacement method.
        data_class <- class(data)
        class(data) <- NULL
        if (side == "value") attr(data$g, "stata.storage") <- storage else
            attr(attr(data, "groups")$g, "stata.storage") <- storage
        class(data) <- data_class
        expect_error(dtatools:::.validate_group_metadata(data), "values must be")
    }
    effects <- new.env(parent = emptyenv()); effects$count <- 0L
    plain_spec <- .group_fixture_spec(tibble::new_tibble(
        list(g = c("b", "a", "b")), nrow = 3L))
    value <- .Call(dtatools:::C_dtatools_callback_length, c("b", "a", "b"), function() NULL)
    data <- .group_validation_frame(value, c("b", "a"), vctrs::list_of(c(1L, 3L), 2L),
        id = "character_bab", plain_spec = plain_spec)
    .Call(dtatools:::C_dtatools_arm_callback_character, value, function() {
        effects$count <- effects$count + 1L
        gc(FALSE)
        invisible(NULL)
    })
    expect_silent(dtatools:::.validate_group_metadata(data))
    expect_identical(effects$count, 1L)
})

test_that("ordinary character group validation avoids full key expansion allocations", {
    skip_if_not(capabilities("profmem"))
    data <- as_dibble(.group_fixture("ascii_100k_16_typed")$data)
    dtatools:::.validate_group_metadata(data)
    before <- .Call(dtatools:::C_dtatools_owned_info, data$g)
    profile <- tempfile()
    on.exit(unlink(profile), add = TRUE)
    gc(FALSE)
    Rprofmem(profile)
    tryCatch(dtatools:::.validate_group_metadata(data), finally = Rprofmem(NULL))
    lines <- readLines(profile, warn = FALSE)
    bytes <- as.double(sub(" .*", "", lines[grepl("^[0-9]+ :", lines)]))
    expect_lt(sum(bytes), 3000000)
    expect_identical(.Call(dtatools:::C_dtatools_owned_info, data$g), before)
})


test_that("encoding normalization preserves later foreign-write isolation", {
    skip_if_not_installed("data.table")
    utf8 <- enc2utf8("é")
    latin1 <- iconv(utf8, from = "UTF-8", to = "latin1")
    for (case in c("payload", "label", "names")) for (side in c("source", "copy")) {
        value <- c("a", "b", "a", NA_character_)
        key <- c("a", "b", NA_character_)
        if (case == "payload") {
            value[c(1L, 3L)] <- c(latin1, utf8); key[[1L]] <- utf8
        } else attr(value, case) <- if (case == "names") rep(latin1, 4L) else latin1
        attr(value, "stata.string.storage") <- "str8"
        expected <- .group_validation_snapshot(value)
        data <- .group_validation_frame(value, key, vctrs::list_of(c(1L, 3L), 2L, 4L), TRUE,
            id = paste0("character_isolation_", case))
        before <- .Call(dtatools:::C_dtatools_owned_info, data$g)
        expect_silent(dtatools:::.validate_group_metadata(data))
        after <- .Call(dtatools:::C_dtatools_owned_info, data$g)
        fields <- c("backing", "exposed", "bytes", "depth")
        expect_identical(after[fields], before[fields])
        expect_identical(.group_validation_snapshot(data$g), expected)
        copy <- .Call(dtatools:::C_dtatools_capture_column, data$g)
        source_frame <- tibble::new_tibble(list(g = data$g), nrow = 4L)
        copy_frame <- tibble::new_tibble(list(g = copy), nrow = 4L)
        expect_silent(data.table::set(if (side == "source") source_frame else copy_frame,
            i = 1L, j = "g", value = "changed"))
        changed <- expected
        changed$values[[1L]] <- "changed"; changed$encodings[[1L]] <- "unknown"
        expect_identical(.group_validation_snapshot(source_frame$g), if (side == "source") changed else expected)
        expect_identical(.group_validation_snapshot(copy_frame$g), if (side == "copy") changed else expected)
    }
})

test_that("bytes-encoded group attributes retain their existing error boundary", {
    bytes <- rawToChar(as.raw(233L)); Encoding(bytes) <- "bytes"
    for (side in c("value", "key")) for (attribute in c("label", "names")) {
        value <- c("a", "b", "a"); key <- c("a", "b")
        target <- if (side == "value") value else key
        attr(target, attribute) <- if (attribute == "names") rep(bytes, length(target)) else bytes
        if (side == "value") value <- target else key <- target
        expected_value <- .group_validation_snapshot(value)
        expected_key <- .group_validation_snapshot(key)
        data <- .group_validation_frame(c("a", "b", "a"), c("a", "b"),
            vctrs::list_of(c(1L, 3L), 2L), TRUE, id = "character_aba")
        # Apply the intentional corruption without a grouped replacement method.
        data_class <- class(data)
        class(data) <- NULL
        if (side == "value") attr(data$g, attribute) <- attr(target, attribute) else
            attr(attr(data, "groups")$g, attribute) <- attr(target, attribute)
        class(data) <- data_class
        expect_error(dtatools:::.validate_group_metadata(data),
            'translating strings with "bytes" encoding is not allowed', class = "simpleError")
        expect_identical(.group_validation_snapshot(data$g), expected_value)
        expect_identical(.group_validation_snapshot(attr(data, "groups")$g), expected_key)
    }
})

test_that("native group row facts give the R expressions' results", {
    facts <- function(x) .Call(dtatools:::C_dtatools_group_rows_facts, x,
                               dtatools:::.group_rows_list_of_methods)
    expected <- function(x) list(unlist(x, use.names = FALSE), lengths(x),
        !any(vapply(x, is.unsorted, logical(1), strictly = TRUE)))
    pairs <- lapply(seq_len(100L), function(i) c(2L * i - 1L, 2L * i))
    # Setting the attributes of a list this long wraps it in ALTREP.
    wrapped <- vctrs::new_list_of(pairs, ptype = integer())
    expect_true(dtatools:::.is_altrep(wrapped))
    for (x in list(list(c(1L, 3L), integer(), 2L), list(c(3L, 1L), 2L),
                   list(c(1L, 1L)), list(c(NA_integer_, 2L)),
                   vctrs::new_list_of(list(c(1L, 2L), 3L), ptype = integer()),
                   wrapped)) {
        expect_identical(facts(x), expected(x))
    }
    compact <- seq_len(3L)
    expect_true(dtatools:::.is_altrep(compact))
    for (x in list(list(), list(compact), list(c(a = 1L)), list(factor("a")),
                   list(c(1, 2)), list(a = 1L),
                   structure(list(1L), class = "other"),
                   vctrs::new_list_of(list(1L), ptype = integer(), class = "extra"),
                   structure(vctrs::new_list_of(list(1L), ptype = integer()),
                             names = "a"))) {
        expect_null(facts(x))
    }
})

test_that("group validation errors are the same with rows read natively", {
    skip_if_not_installed("dplyr")
    data <- dplyr::group_by(as_dibble(data.frame(
        g = rep(seq_len(100L), each = 2L), x = seq_len(200L))), g)
    facts <- function(rows) .Call(dtatools:::C_dtatools_group_rows_facts, rows,
                                  dtatools:::.group_rows_list_of_methods)
    expect_false(is.null(facts(attr(data, "groups")$.rows)))
    expect_silent(dtatools:::.validate_group_metadata(data))
    damages <- list(
        "malformed grouping metadata" = function(rows) {
            rows[[1L]] <- c(2L, 1L); rows
        },
        "malformed grouping metadata" = function(rows) {
            rows[[1L]] <- c(1L, 1L); rows[[2L]] <- c(2L, 3L, 4L); rows
        },
        "keys that do not match" = function(rows) {
            rows[[1L]] <- 1L; rows[[2L]] <- c(2L, 3L, 4L); rows
        }
    )
    for (index in seq_along(damages)) {
        native <- data
        attr(native, "groups")$.rows <- damages[[index]](attr(data, "groups")$.rows)
        # A compact sequence in the last group sends the same rows through the
        # R expressions.
        fallback <- native
        attr(fallback, "groups")$.rows[[100L]] <- 199:200
        expect_false(is.null(facts(attr(native, "groups")$.rows)))
        expect_null(facts(attr(fallback, "groups")$.rows))
        message <- names(damages)[[index]]
        expect_error(dtatools:::.validate_group_metadata(native), message)
        expect_error(dtatools:::.validate_group_metadata(fallback), message)
        expect_identical(
            tryCatch(dtatools:::.validate_group_metadata(native),
                     error = conditionMessage),
            tryCatch(dtatools:::.validate_group_metadata(fallback),
                     error = conditionMessage))
    }
})

# Replacing a list_of method changes what the R expressions read, so the
# native facts must decline. Methods are replaced only in a disposable child.
test_that("native group row facts decline when list_of dispatch changes", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("callr")
    observed <- callr::r(function(libraries, expected_namespace) {
        .libPaths(libraries)
        library(dtatools)
        stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
            normalizePath(expected_namespace)))
        data <- dplyr::group_by(as_dibble(data.frame(
            g = rep(seq_len(100L), each = 2L), x = seq_len(200L))), g)
        rows <- attr(data, "groups")$.rows
        facts <- function() !is.null(.Call(dtatools:::C_dtatools_group_rows_facts,
            rows, dtatools:::.group_rows_list_of_methods))
        validate <- function() tryCatch({
            dtatools:::.validate_group_metadata(data)
            "valid"
        }, error = conditionMessage)
        register <- function(generic, method) {
            registerS3method(generic, "vctrs_list_of", method, envir = asNamespace("vctrs"))
        }
        original_as_list <- get("as.list.vctrs_list_of", asNamespace("vctrs"))
        original_get <- get("[[.vctrs_list_of", asNamespace("vctrs"))
        result <- list(before = facts())
        # Reversing each group's rows makes them decrease, which the R
        # expressions report through vapply()'s as.list().
        register("as.list", function(x, ...) lapply(original_as_list(x), rev))
        result$as_list <- c(facts(), validate())
        register("as.list", original_as_list)
        result$as_list_restored <- facts()
        register("[[", function(x, i, ...) rev(original_get(x, i)))
        result$get <- facts()
        register("[[", original_get)
        result$get_restored <- facts()
        for (name in c("unlist.vctrs_list_of", "unlist.vctrs_vctr", "unlist.list",
                       "unlist.default", "lengths.vctrs_list_of", "lengths.default",
                       "length.vctrs_list_of", "length.vctrs_vctr")) {
            assign(name, function(x, ...) stop("unexpected"), envir = globalenv())
            result[[name]] <- facts()
            rm(list = name, envir = globalenv())
        }
        reads <- 0L
        makeActiveBinding("unlist.vctrs_list_of", function() {
            reads <<- reads + 1L
            NULL
        }, globalenv())
        result$active <- c(facts(), reads)
        rm("unlist.vctrs_list_of", envir = globalenv())
        result$after <- facts()
        result
    }, args = list(.libPaths(), getNamespaceInfo(asNamespace("dtatools"), "path")),
        libpath = .libPaths(), timeout = 120)
    expect_true(observed$before)
    expect_identical(observed$as_list[[1L]], "FALSE")
    expect_match(observed$as_list[[2L]], "malformed grouping metadata")
    expect_true(observed$as_list_restored)
    expect_false(observed$get)
    expect_true(observed$get_restored)
    for (name in c("unlist.vctrs_list_of", "unlist.vctrs_vctr", "unlist.list",
                   "unlist.default", "lengths.vctrs_list_of", "lengths.default",
                   "length.vctrs_list_of", "length.vctrs_vctr")) {
        expect_false(observed[[name]], info = name)
    }
    expect_identical(observed$active, c(0L, 0L))
    expect_true(observed$after)
})

test_that("native group key matching gives vec_equal's result", {
    match_keys <- function(actual, key, sizes) {
        .Call(dtatools:::C_dtatools_group_keys_match, actual, key, sizes)
    }
    expected <- function(actual, key, sizes) {
        all(vctrs::vec_equal(actual, vctrs::vec_slice(key, rep.int(seq_along(sizes), sizes)),
                             na_equal = TRUE))
    }
    proxy <- function(x) vctrs::vec_proxy_equal(x)
    numbers <- c(1, -0, NA, NaN, Inf, 2.5)
    cases <- list(
        list(c(1L, 1L, NA, 2L), c(1L, NA, 2L), c(2L, 1L, 1L)),
        list(c(1L, 2L, NA, 2L), c(1L, NA, 2L), c(2L, 1L, 1L)),
        list(c(TRUE, TRUE, NA), c(TRUE, NA), c(2L, 1L)),
        list(c(TRUE, FALSE, NA), c(TRUE, NA), c(2L, 1L)),
        list(c(0, 0, NA, NaN, Inf), c(-0, NA, NaN, Inf), c(2L, 1L, 1L, 1L)),
        list(c(0, NaN), c(0, NA), c(1L, 1L)),
        list(c(0, NA), c(0, NaN), c(1L, 1L)),
        list(numbers, numbers[c(1, 3, 6)], c(1L, 4L, 1L)),
        list(rep(2.5, 4L), 2.5, 4L),
        # Stata missing codes compare through the equality proxy's rank.
        list(proxy(dta_double(c(1, 1, NA, tagged_missing("a")))),
             proxy(dta_double(c(1, NA, tagged_missing("a")))), c(2L, 1L, 1L)),
        list(proxy(dta_double(c(1, 1, NA, tagged_missing("a")))),
             proxy(dta_double(c(1, tagged_missing("b"), tagged_missing("a")))), c(2L, 1L, 1L)),
        list(proxy(dta_byte(c(3, 3, 4))), proxy(dta_byte(c(3, 4))), c(2L, 1L)),
        list(proxy(dta_byte(c(3, 3, 4))), proxy(dta_byte(c(3, 5))), c(2L, 1L)),
        # ASCII strings and NA compare as R keeps them, one copy of each.
        list(c("a", "a", NA, "b"), c("a", NA, "b"), c(2L, 1L, 1L)),
        list(c("a", "b", NA, "b"), c("a", NA, "b"), c(2L, 1L, 1L)),
        list(c("NA", NA), c(NA_character_, NA_character_), c(1L, 1L)),
        list(c("", ""), "", 2L),
        list(data.frame(n = c(1, 1, 2), s = c("x", "x", "y")),
             data.frame(n = c(1, 2), s = c("x", "y")), c(2L, 1L)),
        list(data.frame(n = c(1, 1, 2), s = c("x", "z", "y")),
             data.frame(n = c(1, 2), s = c("x", "y")), c(2L, 1L))
    )
    for (case in cases) {
        expect_identical(match_keys(case[[1L]], case[[2L]], case[[3L]]),
                         expected(case[[1L]], case[[2L]], case[[3L]]))
    }
    # Groups listing no rows contribute no values.
    expect_true(match_keys(c(1L, 3L), c(1L, 2L, 3L), c(1L, 0L, 1L)))
    # A read file's compact strings, directly and through a metadata view.
    make <- read_dta(fixture("auto_v118.dta"), col_select = "make")$make
    expect_true(.Call(dtatools:::C_dtatools_is_altrep, make))
    values <- vctrs::vec_proxy_equal(dtatools:::.grouping_key_value(make))
    expect_true(.Call(dtatools:::C_dtatools_is_altrep, values))
    expect_true(match_keys(values, values, rep.int(1L, length(values))))
    expect_false(match_keys(values, rev(values), rep.int(1L, length(values))))
    view <- dtatools:::.metadata_copy(values)
    expect_true(.Call(dtatools:::C_dtatools_is_altrep, view))
    expect_true(match_keys(view, values, rep.int(1L, length(values))))
    # Anything else keeps vctrs's comparison.
    frame <- proxy(dta_double(c(1, 1)))
    key_frame <- proxy(dta_double(1))
    declined <- list(
        list(c(a = 1L, b = 1L), 1L, 2L),
        list(structure(c(1L, 1L), class = "other"), 1L, 2L),
        list(c(1L, 1L), 1, 2L),
        list(c("a", "a"), 1L, 2L),
        list(structure(c("a", "a"), names = c("x", "y")), "a", 2L),
        list(seq_len(2L), 1L, 2L),
        list(c(1L, 1L), 1L, 3L),
        list(c(1L, 1L), 1L, NA_integer_),
        list(c(1L, 1L), 1L, 2),
        list(frame, key_frame$value, 2L),
        list(frame$value, key_frame, 2L),
        list(tibble::as_tibble(frame), tibble::as_tibble(key_frame), 2L),
        list(stats::setNames(frame, c("rank", "other")), key_frame, 2L),
        list(structure(frame, extra = TRUE), key_frame, 2L),
        list(frame, structure(key_frame, row.names = c(NA_integer_, -3L)), 2L)
    )
    for (case in declined) {
        expect_null(match_keys(case[[1L]], case[[2L]], case[[3L]]))
    }
    # vctrs translates other strings to UTF-8 first, which can make unequal
    # elements equal or fail, even after a mismatch, so they keep its call.
    latin1 <- "caf\xe9"
    Encoding(latin1) <- "latin1"
    utf8 <- enc2utf8(latin1)
    bytes <- "caf\xe9"
    Encoding(bytes) <- "bytes"
    expect_true(expected(c(latin1, utf8), utf8, 2L))
    expect_error(expected(c("a", bytes), c("b", bytes), c(1L, 1L)), "bytes")
    for (case in list(list(c(latin1, utf8), utf8, 2L),
                      list(c(utf8, utf8), utf8, 2L),
                      list(c("a", bytes), c("b", bytes), c(1L, 1L)),
                      list(c("a", "b"), c("a", bytes), c(1L, 1L)),
                      list(data.frame(n = c(1, 2), s = c("x", bytes)),
                           data.frame(n = c(1, 3), s = c("x", bytes)), c(1L, 1L)))) {
        expect_null(match_keys(case[[1L]], case[[2L]], case[[3L]]))
    }
})
