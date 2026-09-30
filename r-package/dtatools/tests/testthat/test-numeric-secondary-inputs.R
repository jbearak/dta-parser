test_that("numeric secondary inputs keep custom database reads on the original path", {
    skip_if_not_installed("callr")
    fixture <- normalizePath(test_path("fixtures", "numeric-size-userdb.c"))
    records <- .dtatools_child_r("numeric-secondary-userdb", function(libraries, fixture) {
        .libPaths(libraries)
        library(dtatools)
        compiler::enableJIT(0L)
        scratch <- tempfile("numeric-secondary-userdb-")
        dir.create(scratch)
        on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
        prior <- setwd(scratch)
        on.exit(setwd(prior), add = TRUE)
        stopifnot(file.copy(fixture, "numeric-size-userdb.c"))
        output <- system2(file.path(R.home("bin"), "R"),
                          c("CMD", "SHLIB", "numeric-size-userdb.c"),
                          stdout = TRUE, stderr = TRUE)
        if (!is.null(attr(output, "status"))) stop(paste(output, collapse = "\n"))
        dyn.load(file.path(scratch, paste0("numeric-size-userdb", .Platform$dynlib.ext)))
        # Attached table finalizers retain DLL pointers until this child exits.
        ns <- asNamespace("dtatools")
        values <- rep(c(1, 2), length.out = 2048L)
        typed <- dta_double(values)
        for (i in 1:5) {
            invisible(typed + 1)
            invisible(dtatools:::.dta_computed(values, "double"))
            invisible(dtatools:::.dta_storage_holds(values, "double"))
            invisible(dta_double(values))
        }
        run <- function(name, payload, expression, changing = FALSE, getter = FALSE) {
            pointer <- if (changing) .Call("numeric_size_userdb_create_changing", payload, 1L) else
                if (getter) .Call("numeric_size_userdb_create_named", payload, ".declared_dta_storage") else
                    .Call("numeric_size_userdb_create", payload)
            table_name <- paste0("numeric-secondary-userdb-", name)
            database <- attach(pointer, name = table_name, warn.conflicts = FALSE)
            on.exit(detach(table_name, character.only = TRUE), add = TRUE)
            scope <- new.env(parent = database)
            scope$values <- values
            scope$typed <- typed
            scope$public <- dta_double
            scope$scalar <- get(".dta_arith_base", ns)
            scope$computed <- get(".dta_computed", ns)
            scope$construct <- get(".construct_dta_numeric", ns)
            scope$holds <- get(".dta_storage_holds", ns)
            invisible(.Call("numeric_size_userdb_gets", pointer, TRUE))
            error <- NULL
            result <- tryCatch(eval(expression, scope), error = function(condition) {
                error <<- conditionMessage(condition)
                NULL
            })
            list(gets = .Call("numeric_size_userdb_gets", pointer, FALSE), error = error,
                 values = if (is.null(error)) as.double(result) else NULL,
                 storage = if (is.null(error)) dta_storage_type(result) else NULL)
        }
        cases <- list(
            scalar_y = list(1, quote(scalar("+", typed, operand, "double"))),
            scalar_op = list("+", quote(scalar(operand, typed, 1, "double"))),
            scalar_minimum = list("double", quote(scalar("+", typed, 1, operand))),
            computed_minimum = list("double", quote(computed(values, operand))),
            computed_temporal = list(0L, quote(computed(values, "double", operand))),
            construct_storage = list("double", quote(construct(values, NULL, operand))),
            construct_temporal = list(0L, quote(construct(values, NULL, "double", operand))),
            construct_size = list(NULL, quote(construct(values, operand, "double"))),
            holds_storage = list("double", quote(holds(values, operand))),
            public_size = list(NULL, quote(public(values, .size = operand))),
            public_size_error = list(1L, quote(public(values, .size = operand))))
        records <- lapply(names(cases), function(name) {
            case <- cases[[name]]
            run(name, case[[1L]], case[[2L]])
        })
        names(records) <- names(cases)
        records$public_size_changing <- run("changing", NULL,
            quote(public(values, .size = operand)), changing = TRUE)
        records$computed_getter <- run("getter", get(".declared_dta_storage", ns),
            quote(computed(values, .declared_dta_storage(typed))), getter = TRUE)
        records
    }, args = list(libraries = .libPaths(), fixture = fixture))
    values <- rep(c(1, 2), length.out = 2048L)
    for (name in names(records)) {
        record <- records[[name]]
        expect_identical(record$gets, 1L, info = name)
        if (name == "public_size_error") {
            expect_identical(record$error, "Supply `x` or `.size`, not both")
            next
        }
        expect_null(record$error, info = name)
        expected <- if (name == "holds_storage") 1 else
            if (startsWith(name, "scalar_")) values + 1 else values
        expect_identical(record$values, expected, info = name)
        expect_identical(record$storage, if (name == "holds_storage") NULL else "double", info = name)
    }
})
test_that("numeric argument admission preserves forwarded dots values and policies", {
    values <- rep(c(1, 2), length.out = 4096L)
    typed <- dta_double(values)
    invisible(typed + 1)
    cases <- list(
        public_x = list(quote(dta_double(..1)), rep(9, 4096L), values, values, "double"),
        scalar_op = list(quote(.dta_arith_base(..1, typed, 1, "double")),
                         "+", "-", values - 1, "double"),
        scalar_y = list(quote(.dta_arith_base("+", typed, ..1, "double")),
                        1, 3, values + 3, "double"),
        scalar_minimum = list(quote(.dta_arith_base("+", typed, 1, ..1)),
                              "double", "byte", values + 1, "byte"),
        computed_minimum = list(quote(.dta_computed(values, ..1)),
                                "double", "byte", values, "byte"),
        computed_result = list(quote(.dta_computed(..1, "double")),
                               rep(9, 4096L), values, values, "double"),
        construct_storage = list(quote(.construct_dta_numeric(values, NULL, ..1)),
                                 "double", "byte", values, "byte"),
        holds_values = list(quote(.dta_storage_holds(..1, "double")),
                            values, rep(Inf, 4096L), FALSE, NULL)
    )
    for (name in names(cases)) {
        case <- cases[[name]]
        forward <- function(...) {
            assign("..1", case[[2L]], envir = environment())
            eval(case[[1L]], environment())
        }
        result <- forward(case[[3L]])
        expect_identical(if (name == "holds_values") result else as.double(result),
                         case[[4L]], info = name)
        expect_identical(dta_storage_type(result), case[[5L]], info = name)
    }
    forward_size <- function(...) {
        assign("..1", NULL, envir = environment())
        dta_double(values, .size = ..1)
    }
    expect_error(forward_size(1L), "Supply `x` or `.size`, not both", fixed = TRUE)
    forward_second <- function(...) {
        assign("..2", rep(9, 4096L), envir = environment())
        dta_double(..2)
    }
    expect_identical(as.double(forward_second(NULL, values)), values)
})
