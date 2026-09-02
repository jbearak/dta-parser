# Guards `inst/raven/nse.toml` against drift. Raven matches positional
# arguments against the declared `formals`, so a renamed or reordered argument
# in R/ silently shifts which argument Raven suppresses. These tests fail
# instead.

# Minimal reader for the subset of TOML the declaration file uses: `[[function]]
# table headers, `key = "string"`, `key = true/false`, and string arrays written
# either on one line or across several. Comments and blank lines are dropped.
# Deliberately not a general TOML parser -- it only has to read a file this
# package writes.
read_nse_declarations <- function(path) {
    lines <- readLines(path, warn = FALSE)
    lines <- sub("(^|\\s)#.*$", "", lines)
    lines <- trimws(lines)
    lines <- lines[nzchar(lines)]

    # Join continuation lines so each array occupies one entry.
    joined <- character(0)
    buffer <- ""
    for (line in lines) {
        buffer <- if (nzchar(buffer)) paste(buffer, line) else line
        if (lengths(regmatches(buffer, gregexpr("[", buffer, fixed = TRUE))) ==
            lengths(regmatches(buffer, gregexpr("]", buffer, fixed = TRUE)))) {
            joined <- c(joined, buffer)
            buffer <- ""
        }
    }

    declarations <- list()
    current <- NULL
    for (line in joined) {
        if (identical(line, "[[function]]")) {
            if (!is.null(current)) declarations[[length(declarations) + 1]] <- current
            current <- list()
            next
        }
        if (is.null(current)) next # pre-table keys such as `schema`
        parts <- regmatches(line, regexpr("=", line), invert = TRUE)[[1]]
        if (length(parts) != 2) next
        key <- trimws(parts[[1]])
        value <- trimws(parts[[2]])
        current[[key]] <- if (startsWith(value, "[")) {
            quoted <- unlist(regmatches(value, gregexpr('"[^"]*"', value)))
            gsub('"', "", quoted, fixed = TRUE)
        } else if (value %in% c("true", "false")) {
            identical(value, "true")
        } else {
            gsub('"', "", value, fixed = TRUE)
        }
    }
    if (!is.null(current)) declarations[[length(declarations) + 1]] <- current
    declarations
}

declaration_path <- function() {
    # `testthat::test_local()` runs against the source tree, an installed check
    # against the installed package; try both.
    installed <- system.file("raven", "nse.toml", package = "dtatools")
    if (nzchar(installed)) return(installed)
    testthat::test_path("..", "..", "inst", "raven", "nse.toml")
}

# The policy the package must keep declaring. Spelled out here so that deleting
# a `[[function]]` table, or emptying its `captured` list, fails instead of
# silently leaving Raven without the suppression -- the later tests only check
# the tables that are still present.
expected_policy <- list(
    gen = list(captured = c("where", "by", "bysort"), captured_dots = TRUE),
    repl = list(captured = c("where", "by", "bysort"), captured_dots = TRUE),
    replace_values = list(
        captured = c("where", "by", "bysort"), captured_dots = TRUE
    ),
    keep_vars = list(captured = character(), captured_dots = TRUE),
    drop_vars = list(captured = character(), captured_dots = TRUE),
    set_var_label = list(captured = "variable", captured_dots = FALSE),
    tab = list(captured = "x", captured_dots = TRUE),
    read_dta = list(captured = "col_select", captured_dots = FALSE),
    read_arrow = list(captured = "col_select", captured_dots = FALSE)
)

test_that("every declared function is exported by the package", {
    declarations <- read_nse_declarations(declaration_path())
    expect_gt(length(declarations), 0)
    exported <- getNamespaceExports("dtatools")
    for (declaration in declarations) {
        expect_true(
            declaration$name %in% exported,
            info = paste(declaration$name, "is declared but not exported")
        )
    }
})

test_that("the declaration file still carries the expected policy", {
    declarations <- read_nse_declarations(declaration_path())
    names(declarations) <- vapply(declarations, function(d) d$name, character(1))
    expect_setequal(names(declarations), names(expected_policy))

    for (name in names(expected_policy)) {
        declaration <- declarations[[name]]
        expect_identical(
            declaration$captured,
            expected_policy[[name]]$captured,
            info = paste("inst/raven/nse.toml no longer captures the expected arguments of", name)
        )
        expect_identical(
            isTRUE(declaration$captured_dots),
            expected_policy[[name]]$captured_dots,
            info = paste("inst/raven/nse.toml changed captured_dots for", name)
        )
    }
})

test_that("declared formals match the function signatures", {
    for (declaration in read_nse_declarations(declaration_path())) {
        actual <- names(formals(get(declaration$name, asNamespace("dtatools"))))
        expect_identical(
            declaration$formals,
            actual,
            info = paste(
                "inst/raven/nse.toml declares", declaration$name,
                "with formals that no longer match R/"
            )
        )
    }
})

test_that("captured arguments name real formals", {
    for (declaration in read_nse_declarations(declaration_path())) {
        expect_true(
            all(declaration$captured %in% declaration$formals),
            info = paste(declaration$name, "captures a name that is not a formal")
        )
    }
})
