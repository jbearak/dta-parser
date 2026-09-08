# Character/factor examples adapted from dplyr 1.2.1 test-recode.R at
# 95740975c465c29cdb2abdfa13effddb948444dc. MIT notice: inst/NOTICE.
# Additional cases below cover dtatools metadata, dispatch and missing policies.

test_that("owned character recoding retains named replacement rules", {
    x <- c(a = "a", b = "b", missing = NA_character_, literal = "NA")
    expect_identical(recode(x, a = "A"), c("A", "b", NA_character_, "NA"))
    expect_identical(recode(x, a = "A", .default = "D", .missing = "M"),
                     c("A", "D", "M", "D"))
    expect_identical(recode(c("a", "b"), .default = "D"), c("D", "D"))
    expect_identical(recode(c("a", NA_character_), .missing = "M"), c("a", "M"))
    expect_identical(recode(c("a", "b"), !!!list(a = "A", b = "B")), c("A", "B"))
    key <- "a"
    expect_identical(recode("a", !!key := "A", ), "A")
    expect_identical(recode(c("a", "b"), a = "first", a = "second"), c("first", "b"))
    expect_identical(recode(c("a", "b"), a = NULL, .default = "D"), c(NA_character_, "D"))
    expect_identical(recode(c("a", "b", NA_character_), a = c("A", "unused", "unused"),
                            .default = c("unused", "B", "unused"),
                            .missing = c("unused", "unused", "M")), c("A", "B", "M"))
    expect_warning(expect_identical(recode(c("a", "b"), a = 1), c(1, NA_real_)),
                   "Unreplaced values", class = "rlang_warning")
})

test_that("owned character validation keeps lengths types classes and empty templates", {
    expect_identical(recode(character(), a = "A"), character())
    expect_identical(recode(character(), a = character()), character())
    expect_error(recode(character()), "No replacements", class = "rlang_error")
    expect_error(recode(character(), .default = character()), "No replacements", class = "rlang_error")
    expect_error(recode("a", "A"), "Argument 2 must be named", class = "rlang_error")
    expect_error(recode("a", z = c("A", "B")), "length 1", class = "rlang_error")
    expect_error(recode(c("a", "b"), a = "A", z = 1), "type", class = "rlang_error")
    expect_error(recode("a", a = structure("A", class = "first"),
                        z = structure("Z", class = "second")), "class", class = "rlang_error")
    value <- as.Date("2020-01-01")
    expect_identical(recode(c("a", "b"), a = value, .default = unclass(value)), rep(value, 2L))
    expect_error(recode("a", a = 1, z = value), "class", class = "rlang_error")
})

test_that("factor recoding changes levels in source order and retains factor metadata", {
    x <- ordered(c("b", "a", NA), levels = c("unused", "b", "a"))
    attr(x, "label") <- "label"
    attr(x, "custom") <- list(1)
    alias <- x
    out <- recode(x, b = "B")
    expect_identical(as.character(out), c("B", "a", NA_character_))
    expect_identical(levels(out), c("unused", "B", "a"))
    expect_identical(class(out), class(x))
    expect_identical(attr(out, "label"), "label")
    expect_identical(attr(out, "custom"), list(1))
    expect_identical(x, alias)
    out[1L] <- "a"
    expect_identical(x, alias)
    expect_identical(recode(factor(c("a", "b", "c")), b = "a", c = "a"),
                     factor(c("a", "a", "a")))
    expect_identical(recode(factor(c("a", "b")), b = NA_character_), factor(c("a", NA)))
    expect_identical(recode(factor(c("a", "b", NA)), a = 1, b = 2), c(1, 2, NA_real_))
    expect_identical(recode(factor(c("a", "b")), a = 1), c(1, NA_real_))
    expect_identical(recode(factor(c("a", "b")), a = 1, .default = 9), c(1, 9))
    expect_identical(recode(factor(c("a", "b")), a = "first", a = "second"),
                     factor(c("first", "b"), levels = c("first", "b")))
    expect_identical(recode(factor(c("a", "b")), a = NULL, .default = "D"),
                     factor(c(NA, "D"), levels = "D"))
})

test_that("factor replacement sizes are level counts including empty observations", {
    x <- factor("b", levels = c("a", "b", "c"))
    expect_identical(as.character(recode(x, b = c("A", "B", "C"))), "B")
    expect_error(recode(x, b = c("A", "B")), "length 3", class = "rlang_error")
    expect_identical(levels(recode(x[FALSE], b = "B")), c("a", "B", "c"))
    expect_identical(recode(factor(), a = "A"), factor())
    expect_error(recode(factor(), .default = "D"), "No replacements", class = "rlang_error")
    expect_error(recode(x, b = "B", .missing = "M"), "not supported for factors", class = "rlang_error")
    expect_error(recode(x, b = factor("B")), "type", class = "rlang_error")
})

test_that("character and factor argument forcing follows the legacy order", {
    events <- character()
    mark <- function(name, value) { events <<- c(events, name); value }
    recode("a", a = mark("replacement", "A"),
           .default = mark("default", "D"), .missing = mark("missing", "M"))
    expect_identical(events, c("replacement", "default", "missing"))
    events <- character()
    recode(factor("a"), a = mark("replacement", "A"),
           .default = mark("default", "D"), .missing = mark("missing", NULL))
    expect_identical(events, c("replacement", "missing", "default"))
    expect_error(recode(factor("a"), .default = stop("default forced"),
                        .missing = stop("missing forced")), "No replacements")
    expect_error(recode("a", "A", .default = stop("default forced")), "must be named")
    expect_error(recode(factor("a"), "A", .missing = stop("missing forced")), "must be named")
})

test_that("ordinary unsupported types fail without forcing replacements", {
    inputs <- list(TRUE, 1i, as.raw(1), list(1), NULL, data.frame(x = 1),
                   as.POSIXlt("2020-01-01", tz = "UTC"))
    for (x in inputs) {
        expect_error(recode(x, stop("dots forced"), .default = stop("default forced"),
                            .missing = stop("missing forced")), "no applicable method for 'recode'",
                     class = "simpleError")
    }
})

test_that("metadata wrappers retain their three transparent attributes", {
    x <- set_dta_note(c("a", "b"), 4L, "note")
    x <- set_dta_characteristic(x, "source", "character")
    alias <- x
    out <- recode(x, a = "A")
    expect_identical(as.vector(out), c("A", "b"))
    expect_identical(dta_notes(out), c(`4` = "note"))
    expect_identical(dta_characteristics(out), c(source = "character"))
    expect_identical(x, alias)
    out[1L] <- "changed"
    expect_identical(x, alias)
    integer <- set_dta_note(1:2, 1L, "integer")
    expect_identical(as.vector(recode(integer, `1` = 10)), c(10L, 2L))
    expect_warning(legacy <- recode.dtatools_dta_metadata_vector(integer, `1` = 10),
                   "Unreplaced values")
    expect_identical(as.vector(legacy), c(10, NA_real_))
    expect_identical(dta_notes(legacy), c(`1` = "integer"))
    string <- dta_string(c("a", "b"), "str4")
    attr(string, "label") <- "source label"
    expect_identical(recode(string, a = "A"), c("A", "b"))
})

test_that("character-backed Haven input terminates with ordinary character output", {
    # Use the documented class shape without making Haven a core dependency.
    x <- structure(c("a", "b", NA_character_), labels = c(A = "a"), label = "label",
                   class = c("haven_labelled", "vctrs_vctr", "character"))
    expect_identical(recode(x, a = "A"), c("A", "b", NA_character_))
    expect_identical(dtatools:::recode.haven_labelled(x, a = "A"), c("A", "b", NA_character_))
})

test_that("custom methods retain S3 context and inherited NextMethod", {
    method_names <- c("recode.dtatools_recode_first", "recode.dtatools_recode_second")
    old <- lapply(method_names, function(name) get0(name, .GlobalEnv, inherits = FALSE))
    withr::defer({
        for (i in seq_along(method_names)) {
            if (is.null(old[[i]])) rm(list = method_names[[i]], envir = .GlobalEnv)
            else assign(method_names[[i]], old[[i]], .GlobalEnv)
        }
    })
    events <- list()
    first <- function(.x, ..., .default = NULL, .missing = NULL) {
        events[[length(events) + 1L]] <<- list(.Generic, .Class)
        NextMethod()
    }
    second <- function(.x, ..., .default = NULL, .missing = NULL) {
        events[[length(events) + 1L]] <<- list(.Generic, .Class)
        NextMethod()
    }
    assign(method_names[[1L]], first, .GlobalEnv)
    assign(method_names[[2L]], second, .GlobalEnv)
    x <- structure("a", class = c("dtatools_recode_first", "dtatools_recode_second", "character"))
    expect_identical(recode(x, a = "A"), "A")
    expect_length(events, 2L)
    expect_identical(events[[1L]], list("recode", class(x)))
    expect_identical(as.vector(events[[2L]][[2L]]), class(x)[-1L])
    events <- list()
    number <- structure(1, class = c("dtatools_recode_first", "numeric"))
    recode(number, `1` = 2)
    expect_length(events, 0L)
})

test_that("the public numeric path retains all missing tags without optional dispatch", {
    x <- c(NA_real_, tagged_missing(letters), 1)
    alias <- x
    out <- recode(x, `1` = 2)
    expect_identical(missing_tag(out), missing_tag(x))
    expect_identical(out[[28L]], 2)
    expect_identical(x, alias)
    expect_identical(recode(c(1L, NA_integer_), `1` = 10), c(10L, NA_integer_))
    expect_identical(recode(c(1L, NA_integer_), `1` = 10.5), c(10.5, NA_real_))
    expect_error(recode(x, `1` = "one"), "non-numeric recode")
    expect_identical(recode(x, `1` = "one", .missing = "M"), c(rep("M", 27L), "one"))
    expect_error(recode(1, `1` = factor("one")), "Class-changing numeric replacements")
})
