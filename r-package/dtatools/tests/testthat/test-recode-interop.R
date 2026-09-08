test_that("registered recode methods retain continuation context", {
    skip_if_not_installed("dplyr")
    generic_namespace <- asNamespace("dplyr")
    # A disposable method name confines this optional registration fixture.
    name <- "dtatools_registered_recode_test"
    table <- get(".__S3MethodsTable__.", generic_namespace)
    key <- paste0("recode.", name)
    old <- get0(key, table, inherits = FALSE)
    withr::defer({
        if (is.null(old)) rm(list = key, envir = table)
        else assign(key, old, table)
    })
    events <- list()
    method <- function(.x, ..., .default = NULL, .missing = NULL) {
        events[[length(events) + 1L]] <<- list(.Generic, .Class)
        NextMethod()
    }
    registerS3method("recode", name, method, envir = generic_namespace)
    x <- structure("a", class = c(name, "character"))
    expect_identical(recode(x, a = "A"), "A")
    expect_identical(events, list(list("recode", class(x))))
    events <- list()
    expect_identical(dplyr::recode(x, a = "A"), "A")
    expect_identical(events, list(list("recode", class(x))))
})

test_that("optional generic and public numeric recoding keep distinct policies", {
    skip_if_not_installed("dplyr")
    expect_warning(legacy <- dplyr::recode(1:2, `1` = 10), "Unreplaced values")
    expect_identical(legacy, c(10, NA_real_))
    expect_identical(recode(1:2, `1` = 10), c(10L, 2L))
    expect_identical(dplyr::recode(c(1, tagged_missing("a")), `1` = 2),
                     recode(c(1, tagged_missing("a")), `1` = 2))
})

test_that("foreign registrations preserve registry precedence and function identity", {
    skip_if_not_installed("dplyr")
    ns <- asNamespace("dplyr")
    table <- get(".__S3MethodsTable__.", ns)
    classes <- c("dtatools_recode_collision", "dtatools_recode_namespace", "character", "default")
    keys <- paste0("recode.", classes)
    old <- lapply(keys, function(key) get0(key, table, inherits = FALSE))
    global_key <- keys[[1L]]
    global_old <- get0(global_key, .GlobalEnv, inherits = FALSE)
    withr::defer({
        for (i in seq_along(keys)) {
            if (is.null(old[[i]])) {
                if (exists(keys[[i]], table, inherits = FALSE)) rm(list = keys[[i]], envir = table)
            } else assign(keys[[i]], old[[i]], table)
        }
        if (is.null(global_old)) rm(list = global_key, envir = .GlobalEnv)
        else assign(global_key, global_old, .GlobalEnv)
    })
    assign(global_key, function(.x, ...) "global", .GlobalEnv)
    registerS3method("recode", classes[[1L]], function(.x, ...) "registered", ns)
    expect_identical(recode(structure("a", class = c(classes[[1L]], "character"))), "registered")
    foreign <- eval(quote(function(.x, ...) "foreign namespace closure"), ns)
    registerS3method("recode", classes[[2L]], foreign, ns)
    expect_identical(recode(structure(list(1), class = classes[[2L]])), "foreign namespace closure")
    registerS3method("recode", "character", foreign, ns)
    expect_identical(recode("a"), "foreign namespace closure")
    registerS3method("recode", "default", foreign, ns)
    expect_identical(recode(TRUE), "foreign namespace closure")
})

test_that("actual Haven character input works through both public interfaces", {
    skip_if_not_installed("dplyr")
    skip_if_not_installed("haven")
    x <- haven::labelled(c("a", "b", NA_character_), c(A = "a"), label = "label")
    expect_identical(dtatools::recode(x, a = "A"), c("A", "b", NA_character_))
    expect_identical(dplyr::recode(x, a = "A"), c("A", "b", NA_character_))
})

test_that("package-visible recode methods precede same-slot foreign registrations", {
    skip_if_not_installed("dplyr")
    ns <- asNamespace("dplyr")
    table <- get(".__S3MethodsTable__.", ns)
    classes <- c("numeric", "haven_labelled", "dtatools_dta_metadata_vector")
    keys <- paste0("recode.", classes)
    old <- lapply(keys, function(key) get0(key, table, inherits = FALSE))
    withr::defer({
        for (i in seq_along(keys)) {
            if (is.null(old[[i]])) rm(list = keys[[i]], envir = table)
            else assign(keys[[i]], old[[i]], table)
        }
    })
    for (class in classes) registerS3method("recode", class, function(.x, ...) "foreign", ns)
    x <- set_dta_note(c("a", "b"), 1L, "note")
    out <- recode(x, a = "A")
    expect_identical(as.vector(out), c("A", "b"))
    expect_identical(dta_notes(out), c(`1` = "note"))
    number <- set_dta_note(1:2, 1L, "note")
    expect_warning(out <- recode.dtatools_dta_metadata_vector(number, `1` = 10), "Unreplaced values")
    expect_identical(as.vector(out), c(10, NA_real_))
    x <- structure("a", class = c("haven_labelled", "vctrs_vctr", "character"))
    expect_identical(recode(x, a = "A"), "A")
})

test_that("foreign methods retain the real generic environment and dynamic continuation", {
    skip_if_not_installed("dplyr")
    ns <- asNamespace("dplyr")
    table <- get(".__S3MethodsTable__.", ns)
    classes <- c("dtatools_recode_dynamic_first", "dtatools_recode_dynamic_next")
    keys <- paste0("recode.", classes)
    old <- lapply(keys, function(key) get0(key, table, inherits = FALSE))
    withr::defer({
        for (i in seq_along(keys)) {
            if (is.null(old[[i]])) rm(list = keys[[i]], envir = table)
            else assign(keys[[i]], old[[i]], table)
        }
    })
    first <- function(.x, ..., .default = NULL, .missing = NULL) {
        registerS3method("recode", classes[[2L]], function(.x, ...) "updated", ns)
        list(generic = .Generic, definition = .GenericDefEnv, next_value = NextMethod())
    }
    registerS3method("recode", classes[[1L]], first, ns)
    registerS3method("recode", classes[[2L]], function(.x, ...) "old", ns)
    out <- recode(structure("a", class = c(classes, "character")))
    expect_identical(out$generic, "recode")
    expect_identical(out$definition, ns)
    expect_identical(out$next_value, "updated")
})
