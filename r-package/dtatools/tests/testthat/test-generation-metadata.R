.generation_attributes_attempt <- function(source) {
    .Call(C_dtatools_canonical_generate_attributes, source, environment(),
          .metadata_state$dependencies)
}

test_that("generation metadata shortcut admits only ordinary canonical doubles", {
    canonical <- attributes(dta_double(c(1, 2)))
    invisible(.generate_attributes(canonical))
    expected <- identical(as.character(getRversion()), "4.6.1") &&
        identical(as.character(R.version[["svn rev"]]), "90187") &&
        .Call(C_dtatools_metadata_execution_profile, .metadata_execution_probe)
    expect_identical(.generation_attributes_attempt(canonical),
                     expected)
    expect_identical(.generate_attributes(canonical), canonical)
    inputs <- list(
        NULL, list(), canonical[2:1], c(canonical, list(label = "X")),
        attributes(dta_int(c(1, 2))),
        list(stata.storage = "double", class = c("custom", canonical$class)),
        list(stata.storage = structure("double", extra = TRUE), class = canonical$class),
        list(stata.storage = "double", class = structure(canonical$class, extra = TRUE)),
        structure(canonical, class = "custom"), structure(canonical, extra = TRUE),
        list(stata.storage = "double", class = c(NA_character_, canonical$class[-1L])),
        list(stata.storage = "double", class = c("haven_labelled", "vctrs_vctr", "double")),
        list(stata.storage = "double", class = c("dta_datetime", "dta_temporal", "POSIXct", "POSIXt"))
    )
    for (input in inputs) expect_false(.generation_attributes_attempt(input))
    for (name in c("label", "labels", "notes", "format.stata", "unexpected")) {
        described <- canonical
        described[[name]] <- "Drop me"
        expect_identical(.generate_attributes(described), canonical)
    }
    reordered <- canonical[2:1]
    expect_identical(.generate_attributes(reordered), reordered)
    haven <- list(class = c("haven_labelled", "vctrs_vctr", "double"), label = "X")
    expect_identical(.generate_attributes(haven), setNames(list(), character()))
})

test_that("generation metadata admission does not read foreign attributes", {
    for (location in c("names", "storage", "class")) {
        source <- attributes(dta_double(c(1, 2)))
        values <- switch(location, names = names(source), storage = source[[1L]], class = source[[2L]])
        foreign <- .Call(C_dtatools_callback_character, values, function() NULL)
        if (location == "names") names(source) <- foreign
        if (location == "storage") source[[1L]] <- foreign
        if (location == "class") source[[2L]] <- foreign
        reads <- 0L
        .Call(C_dtatools_arm_callback_character, foreign, function() {
            reads <<- reads + 1L
        })
        expect_false(.generation_attributes_attempt(source))
        expect_identical(reads, 0L)
        kept <- .generate_attributes(source)
        if (location != "storage") expect_gt(reads, 0L)
        expect_identical(as.character(kept$class), c("dta_numeric", "dta_double", "vctrs_vctr", "double"))
        expect_identical(as.character(kept$stata.storage), "double")
    }
})

test_that("generated canonical values retain helper callbacks and independent storage", {
    ns <- asNamespace("dtatools")
    events <- character()
    trace(".generate_value", tracer = function() events <<- c(events, "value"), where = ns, print = FALSE)
    on.exit(untrace(".generate_value", where = ns), add = TRUE)
    trace(".generate_attributes", tracer = function() events <<- c(events, "attributes"), where = ns, print = FALSE)
    on.exit(untrace(".generate_attributes", where = ns), add = TRUE)
    d <- dibble(x = c(1, 2, 3, 4), g = c(1, 1, 2, 2))
    events <- character()
    gen(d, y = x + 1, by = g)
    expect_gt(length(events), 0L)
    expect_identical(events, rep(c("value", "attributes"), length(events) / 2L))
    expect_identical(as.double(d$y), c(2, 3, 4, 5))
    expect_identical(dta_storage_type(d$y), "double")
    repl(d, x = 99, where = 1)
    expect_identical(as.double(d$y), c(2, 3, 4, 5))
    repl(d, y = 88, where = 2)
    expect_identical(as.double(d$x), c(99, 2, 3, 4))
    d[, z := structure(y + 1, label = "Drop me", notes = "Drop me"), by = g]
    expect_identical(as.double(d$z), c(3, 89, 5, 6))
    expect_null(attr(d$z, "label", exact = TRUE))
    expect_null(attr(d$z, "notes", exact = TRUE))
})

test_that("generated canonical metadata retains executable base helper tracers", {
    for (target in c("intersect", "startsWith", "setdiff")) {
        data <- dibble(x = c(1, 2, 3, 4), g = c(1, 1, 2, 2))
        calls <- 0L
        total <- 0L
        trace(target, tracer = function() {
            total <<- total + 1L
            in_metadata <- vapply(sys.calls(), function(call) {
                identical(call[[1L]], quote(.generate_attributes))
            }, logical(1))
            if (any(in_metadata)) calls <<- calls + 1L
        }, where = baseenv(), print = FALSE)
        observed <- tryCatch({
            result <- gen(data, y = x + 1, by = g)
            list(result = result, calls = calls, total = total)
        }, finally = untrace(target, where = baseenv()))
        expect_identical(observed$calls, 3L, info = target)
        if (identical(as.character(getNamespaceVersion("vctrs")), "0.7.3") &&
            !is.null(.metadata_state$dependencies)) {
            expected <- switch(target, intersect = 18L, startsWith = 3L, setdiff = 24L)
            expect_identical(observed$total, expected, info = target)
        }
        expect_identical(as.double(observed$result$y), c(2, 3, 4, 5))
    }
})

test_that("canonical metadata retains nested unique callbacks and character methods", {
    source <- attributes(dta_double(c(1, 2)))
    prototype <- dta_double(c(1, 2))
    calls <- 0L
    trace("unique", tracer = function() { calls <<- calls + 1L },
          where = baseenv(), print = FALSE)
    observed <- tryCatch({
        calls <- 0L
        kept <- .generate_attributes(source)
        generation_calls <- calls
        calls <- 0L
        planned <- .dta_attribute_plan(prototype, "double", temporal = FALSE)
        list(kept = kept, planned = planned,
             calls = c(generation_calls, calls))
    }, finally = untrace("unique", where = baseenv()))
    if (!is.null(.metadata_state$dependencies)) {
        expect_identical(observed$calls, c(4L, 4L))
    }
    expect_identical(observed$kept, source)
    expect_identical(observed$planned, source)

    original <- get0("unique.character", envir = .GlobalEnv, inherits = FALSE)
    existed <- exists("unique.character", envir = .GlobalEnv, inherits = FALSE)
    on.exit({
        if (existed) assign("unique.character", original, envir = .GlobalEnv)
        else rm("unique.character", envir = .GlobalEnv)
    }, add = TRUE)
    assign("unique.character", function(x, ...) {
        calls <<- calls + 1L
        base::unique.default(x, ...)
    }, envir = .GlobalEnv)
    calls <- 0L
    kept <- .generate_attributes(source)
    generation_calls <- calls
    calls <- 0L
    planned <- .dta_attribute_plan(prototype, "double", temporal = FALSE)
    if (!is.null(.metadata_state$dependencies)) {
        expect_identical(c(generation_calls, calls), c(4L, 4L))
    }
    expect_identical(kept, source)
    expect_identical(planned, source)
})

test_that("metadata admission leaves active and delayed helpers untouched", {
    for (target in c("intersect", "identity", "unique.character")) {
        for (binding in c("active", "delayed")) {
            frame <- new.env(parent = asNamespace("dtatools"))
            calls <- 0L
            callback <- function() { calls <<- calls + 1L; base::identity }
            if (binding == "active") makeActiveBinding(target, callback, frame)
            else delayedAssign(target, callback(), assign.env = frame)
            expect_false(.Call(C_dtatools_metadata_dependencies_unchanged,
                               frame, .metadata_state$dependencies))
            expect_identical(calls, 0L)
        }
    }
})

test_that("unsupported metadata profiles retain ordinary filtering", {
    saved <- .metadata_state$dependencies
    on.exit(.metadata_state$dependencies <- saved, add = TRUE)
    .metadata_state$dependencies <- NULL
    source <- attributes(dta_double(c(1, 2)))
    expect_false(.generation_attributes_attempt(source))
    expect_identical(.generate_attributes(source), source)
    described <- c(source, list(label = "Drop me"))
    expect_identical(.generate_attributes(described), source)
    data <- dibble(x = c(1, 2, 3, 4), g = c(1, 1, 2, 2))
    gen(data, y = x + 1, by = g)
    expect_identical(as.double(data$y), c(2, 3, 4, 5))
    expect_identical(attributes(data$y), source)
})
