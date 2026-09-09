test_that("unsupported dplyr registration warns once without touching methods", {
    # Exercise the version policy on a private copy of the registration closure.
    # This does not load an old dplyr or mutate a namespace.
    register <- .register_dplyr_methods
    scope <- new.env(parent = environment(register))
    state <- new.env(parent = emptyenv())
    state$namespace <- NULL
    state$previous <- list()
    state$unsupported_warned <- FALSE
    scope$.dplyr_registration_state <- state
    scope$isNamespaceLoaded <- function(package) TRUE
    scope$asNamespace <- function(package) emptyenv()
    scope$getNamespaceVersion <- function(namespace) package_version("1.2.0")
    scope$getExportedValue <- function(...) stop("Unexpected generic lookup")
    environment(register) <- scope

    expect_warning(result <- register(), "dplyr integration requires dplyr 1.2.1 or newer")
    expect_null(result)
    expect_true(state$unsupported_warned)
    expect_silent(register())
    expect_silent(register(only = "recode.haven_labelled"))
    expect_null(state$namespace)
    expect_identical(state$previous, list())

    # The absent path must still return before even asking for a namespace.
    scope$isNamespaceLoaded <- function(package) FALSE
    scope$asNamespace <- function(package) stop("Unexpected namespace lookup")
    expect_silent(register())
})

test_that("native namespace loading and recoding leave dplyr unloaded", {
    skip_if_not_installed("callr")
    observed <- .dtatools_child_r("native-namespace", function(libraries, expected_path) {
        .libPaths(libraries)
        stopifnot(!isNamespaceLoaded("dplyr"))
        ns <- loadNamespace("dtatools")
        stopifnot(identical(normalizePath(getNamespaceInfo(ns, "path")), expected_path))
        x <- dtatools::as_dibble(data.frame(x = c(1, 2), text = c("a", "b")))
        y <- x[2:1, ]
        result <- list(
            character = dtatools::recode(c("a", NA_character_), a = "A", .missing = "M"),
            factor = dtatools::recode(factor(c("b", "a")), b = "B"),
            numeric = dtatools::recode(c(1, dtatools::tagged_missing("a")), `1` = 3),
            rows = as.double(y$x), exports = sort(getNamespaceExports(ns)),
            dplyr_loaded = isNamespaceLoaded("dplyr"),
            namespace_path = getNamespaceInfo(ns, "path"))
        stopifnot(!isNamespaceLoaded("dplyr"))
        result
    }, args = list(.libPaths(), normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path"))),
        libpath = .libPaths(), timeout = 120)
    expect_identical(observed$character, c("A", "M"))
    expect_identical(observed$factor, factor(c("B", "a"), levels = c("a", "B")))
    expect_identical(observed$numeric, c(3, tagged_missing("a")))
    expect_identical(observed$rows, c(2, 1))
    expect_false(observed$dplyr_loaded)
    expect_identical(observed$exports, sort(getNamespaceExports("dtatools")))
    expect_length(observed$exports, 106L)
    expect_identical(normalizePath(observed$namespace_path),
        normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")))
})

test_that("optional method hooks and registry ownership survive real reloads", {
    skip_if_not_installed("callr")
    skip_if_not_installed("dplyr", "1.2.1")
    for (order in c("dtatools-first", "dplyr-first")) {
        observed <- callr::r(function(libraries, order, expected_path) {
            .libPaths(libraries)
            load_owned <- function() {
                ns <- loadNamespace("dtatools")
                stopifnot(identical(normalizePath(getNamespaceInfo(ns, "path")), expected_path))
                ns
            }
            owner <- function(fn, namespace) {
                is.function(fn) && !is.null(environment(fn)) &&
                    identical(topenv(environment(fn)), namespace)
            }
            has_owner <- function(x, namespace) {
                if (is.function(x)) return(owner(x, namespace))
                if (is.list(x)) return(any(vapply(x, has_owner, logical(1), namespace)))
                FALSE
            }
            events <- list(c("dplyr", "onLoad"), c("dplyr", "onUnload"),
                c("labelled", "onLoad"), c("labelled", "onUnload"), c("labelled", "attach"))
            hook_counts <- function(namespace) vapply(events, function(event) {
                sum(vapply(getHook(packageEvent(event[[1L]], event[[2L]])),
                    owner, logical(1), namespace))
            }, integer(1))
            verify <- function(ns, generic_ns) {
                spec <- get(".dplyr_method_classes", ns)
                table <- get(".__S3MethodsTable__.", generic_ns)
                count <- 0L
                for (generic in names(spec)) for (class in spec[[generic]]) {
                    key <- paste0(generic, ".", class)
                    stopifnot(identical(get(key, table, inherits = FALSE),
                        get(key, ns, inherits = FALSE)))
                    count <- count + 1L
                }
                stopifnot(count == 46L, identical(hook_counts(ns), rep(1L, 5L)),
                    !has_owner(getNamespaceInfo(generic_ns, "S3methods"), ns))
                d <- dtatools::as_dibble(data.frame(x = c(1, 2)))
                out <- dplyr::mutate(d, y = x + 1)
                stopifnot(identical(as.double(out$y), c(2, 3)),
                    identical(as.double(d$x), c(1, 2)),
                    identical(dplyr::recode(c(1, dtatools::tagged_missing("a")), `1` = 3),
                        c(3, dtatools::tagged_missing("a"))))
                count
            }
            if (order == "dtatools-first") {
                before <- load_owned()
                stopifnot(!isNamespaceLoaded("dplyr"), identical(hook_counts(before), rep(1L, 5L)))
                unloadNamespace("dtatools")
                stopifnot(identical(hook_counts(before), rep(0L, 5L)), !isNamespaceLoaded("dplyr"))
                ns <- load_owned()
                generic_ns <- loadNamespace("dplyr")
                prior <- NULL
            } else {
                generic_ns <- loadNamespace("dplyr")
                prior <- as.list(get(".__S3MethodsTable__.", generic_ns))
                ns <- load_owned()
            }
            counts <- verify(ns, generic_ns)
            suppressPackageStartupMessages(library("dtatools", character.only = TRUE))
            suppressPackageStartupMessages(library("dplyr", character.only = TRUE))
            stopifnot(verify(ns, generic_ns) == 46L)
            detach("package:dtatools", unload = FALSE)
            detach("package:dplyr", unload = FALSE)
            stopifnot(verify(ns, generic_ns) == 46L)
            metadata <- getNamespaceInfo(generic_ns, "S3methods")
            for (i in seq_len(3L)) {
                old <- ns
                unloadNamespace("dtatools")
                stopifnot(identical(hook_counts(old), rep(0L, 5L)),
                    !has_owner(as.list(get(".__S3MethodsTable__.", generic_ns)), old),
                    identical(getNamespaceInfo(generic_ns, "S3methods"), metadata))
                if (!is.null(prior)) {
                    spec <- get(".dplyr_method_classes", old)
                    table <- get(".__S3MethodsTable__.", generic_ns)
                    for (generic in names(spec)) for (class in spec[[generic]]) {
                        key <- paste0(generic, ".", class)
                        stopifnot(identical(exists(key, table, inherits = FALSE), key %in% names(prior)),
                            identical(get0(key, table, inherits = FALSE), prior[[key]]))
                    }
                }
                ns <- load_owned()
                stopifnot(!identical(ns, old))
                counts <- c(counts, verify(ns, generic_ns))
            }
            for (i in seq_len(2L)) {
                old_generic <- generic_ns
                unloadNamespace("dplyr")
                state <- get(".dplyr_registration_state", ns)
                stopifnot(is.null(state$namespace), identical(state$previous, list()))
                generic_ns <- loadNamespace("dplyr")
                stopifnot(!identical(old_generic, generic_ns))
                counts <- c(counts, verify(ns, generic_ns))
            }
            replacement <- function(.x, ...) "later legitimate method"
            registerS3method("recode", "haven_labelled", replacement,
                envir = new.env(parent = generic_ns))
            unloadNamespace("dtatools")
            table <- get(".__S3MethodsTable__.", generic_ns)
            stopifnot(identical(get("recode.haven_labelled", table), replacement),
                identical(hook_counts(ns), rep(0L, 5L)),
                !has_owner(as.list(table), ns),
                !has_owner(getNamespaceInfo(generic_ns, "S3methods"), ns))
            list(counts = counts, later_method = get("recode.haven_labelled", table)(NULL),
                hooks = hook_counts(ns), dplyr_loaded = isNamespaceLoaded("dplyr"))
        }, args = list(.libPaths(), order, normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path"))),
            libpath = .libPaths(), timeout = 120)
        expect_identical(observed$counts, rep(46L, 6L))
        expect_identical(observed$later_method, "later legitimate method")
        expect_identical(observed$hooks, rep(0L, 5L))
        expect_true(observed$dplyr_loaded)
    }
})

test_that("failed optional registration restores slots and preserves unrelated hooks", {
    skip_if_not_installed("callr")
    skip_if_not_installed("dplyr", "1.2.1")
    observed <- callr::r(function(libraries, expected_path) {
        .libPaths(libraries)
        namespace <- loadNamespace("dplyr")
        table <- get(".__S3MethodsTable__.", namespace)
        key <- "distinct.dtatools_ref_data"
        sentinel <- function(.data, ...) "unrelated method"
        registerS3method("distinct", "dtatools_ref_data", sentinel,
            envir = new.env(parent = namespace))
        # Fail the real registry write after earlier recode/arrange writes.
        # No generic or namespace function body is replaced.
        lockBinding(key, table)
        snapshot <- function() {
            keys <- sort(ls(table, all.names = TRUE))
            stats::setNames(lapply(keys, get, envir = table, inherits = FALSE), keys)
        }
        before <- snapshot()
        metadata <- getNamespaceInfo(namespace, "S3methods")
        events <- list(c("dplyr", "onLoad"), c("dplyr", "onUnload"),
            c("labelled", "onLoad"), c("labelled", "onUnload"), c("labelled", "attach"))
        hooks <- lapply(events, function(event) {
            name <- packageEvent(event[[1L]], event[[2L]])
            setHook(name, function(...) invisible(NULL), action = "append")
            getHook(name)
        })
        condition <- tryCatch(loadNamespace("dtatools"), error = identity)
        stopifnot(inherits(condition, "error"), !isNamespaceLoaded("dtatools"),
            identical(snapshot(), before),
            identical(getNamespaceInfo(namespace, "S3methods"), metadata))
        for (i in seq_along(events)) {
            event <- events[[i]]
            stopifnot(identical(getHook(packageEvent(event[[1L]], event[[2L]])), hooks[[i]]))
        }
        unlockBinding(key, table)
        rm(list = key, envir = table)
        recovered <- loadNamespace("dtatools")
        stopifnot(identical(normalizePath(getNamespaceInfo(recovered, "path")), expected_path))
        stopifnot(identical(get(key, table), get(key, recovered)),
            identical(dtatools::recode("a", a = "A"), "A"))
        list(failed = conditionMessage(condition), restored = TRUE, recovered = TRUE)
    }, args = list(.libPaths(), normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path"))),
        libpath = .libPaths(), timeout = 120)
    expect_match(observed$failed, "locked binding")
    expect_true(observed$restored)
    expect_true(observed$recovered)
})

test_that("labelled load and unload restore only live prior methods", {
    skip_if_not_installed("callr")
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("labelled")
    for (order in c("labelled-first", "dtatools-first")) {
        observed <- callr::r(function(libraries, order, expected_path) {
            .libPaths(libraries)
            load_owned <- function() {
                ns <- loadNamespace("dtatools")
                stopifnot(identical(normalizePath(getNamespaceInfo(ns, "path")), expected_path))
                ns
            }
            if (order == "labelled-first") loadNamespace("labelled")
            ns <- load_owned()
            labelled_ns <- loadNamespace("labelled")
            generic_ns <- asNamespace("dplyr")
            table <- get(".__S3MethodsTable__.", generic_ns)
            ours <- get("recode.haven_labelled", ns)
            theirs <- get("recode.haven_labelled", labelled_ns)
            stopifnot(identical(get("recode.haven_labelled", table), ours))
            metadata <- getNamespaceInfo(generic_ns, "S3methods")
            unloadNamespace("dtatools")
            stopifnot(identical(get("recode.haven_labelled", table), theirs),
                identical(getNamespaceInfo(generic_ns, "S3methods"), metadata))
            ns <- load_owned()
            state <- get(".dplyr_registration_state", ns)
            stopifnot(identical(state$previous$recode.haven_labelled$previous, theirs))
            unloadNamespace("labelled")
            stopifnot(is.null(state$previous$recode.haven_labelled$previous))
            labelled_ns <- loadNamespace("labelled")
            stopifnot(identical(get("recode.haven_labelled", table), get("recode.haven_labelled", ns)))
            x <- haven::labelled(c(1, dtatools::tagged_missing("a")), c(one = 1))
            stopifnot(identical(dplyr::recode(x, `1` = 3), dtatools::recode(x, `1` = 3)))
            unloadNamespace("dtatools")
            stopifnot(identical(get("recode.haven_labelled", table),
                get("recode.haven_labelled", labelled_ns)))
            list(restored = TRUE, labelled_hooks = c(
                onLoad = exists(".onLoad", labelled_ns, inherits = FALSE),
                onUnload = exists(".onUnload", labelled_ns, inherits = FALSE)))
        }, args = list(.libPaths(), order, normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path"))),
            libpath = .libPaths(), timeout = 120)
        expect_true(observed$restored)
        expect_type(observed$labelled_hooks, "logical")
    }
})

test_that("labelled attachment warns once only when it masks dtatools", {
    skip_if_not_installed("callr")
    skip_if_not_installed("dplyr", "1.2.1")
    skip_if_not_installed("labelled")
    for (order in c("labelled-first", "dtatools-first")) {
        observed <- callr::r(function(libraries, order, expected_path) {
            .libPaths(libraries)
            warnings <- character()
            attach_package <- function(name) {
                withCallingHandlers(
                    suppressPackageStartupMessages(library(name, character.only = TRUE)),
                    warning = function(condition) {
                        warnings <<- c(warnings, conditionMessage(condition))
                        invokeRestart("muffleWarning")
                    }
                )
                if (isNamespaceLoaded("dtatools")) {
                    stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path")),
                        expected_path))
                }
            }
            if (order == "labelled-first") {
                attach_package("labelled")
                attach_package("dtatools")
            } else {
                attach_package("dtatools")
                attach_package("labelled")
            }
            initial <- warnings
            detach("package:labelled", unload = FALSE)
            attach_package("labelled")
            after_second <- warnings
            detach("package:labelled", unload = FALSE)
            attach_package("labelled")
            table <- get(".__S3MethodsTable__.", asNamespace("dplyr"))
            stopifnot(identical(get("recode.haven_labelled", table),
                get("recode.haven_labelled", asNamespace("dtatools"))))
            list(initial = initial, after_second = after_second, final = warnings)
        }, args = list(.libPaths(), order, normalizePath(getNamespaceInfo(asNamespace("dtatools"), "path"))),
            libpath = .libPaths(), timeout = 120)
        expect_length(observed$initial, if (order == "labelled-first") 0L else 1L)
        expect_length(observed$after_second, 1L)
        expect_identical(observed$final, observed$after_second)
        expect_match(observed$final, "labelled.*attached after dtatools.*masks")
    }
})
