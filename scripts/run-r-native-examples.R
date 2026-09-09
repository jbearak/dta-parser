local({
    # Run installed public help examples under the native library guard.
    args <- commandArgs(TRUE)
    stopifnot(length(args) == 1L)
    cfg <- dget(args[[1L]])
    source(cfg$guard, local = environment())
    output <- cfg$output
    stopifnot(dir.exists(output))

    tag <- function(node) {
        value <- attr(node, "Rd_tag")
        if (is.null(value)) "" else value
    }
    section <- function(rd, name) rd[vapply(rd, tag, "") == name]
    text <- function(nodes) paste(unlist(nodes, use.names = FALSE), collapse = "")
    condition_record <- function(condition) list(
        class = class(condition), message = conditionMessage(condition),
        call = paste(deparse(conditionCall(condition)), collapse = "\n"))

    original <- NULL
    terminal_error <- NULL
    topics <- list()
    inventory <- list()
    options(warn = 1)
    tryCatch({
        .native_prepare(cfg, output)
        library("datasets")
        loadNamespace("jsonlite", lib.loc = dirname(cfg$expected_packages$jsonlite$path))
        db <- tools::Rd_db("dtatools", lib.loc = dirname(cfg$package$path))
        files <- sort(list.files(cfg$source_man, pattern = "\\.Rd$", full.names = FALSE), method = "radix")
        .native_require(identical(sort(names(db), method = "radix"), files),
            "Installed/source help topic membership differs")
        .native_checkpoint(cfg, "examples-index", file.path(output, "index-observation.R"))
        code_directory <- cfg$code_output
        .native_require(!file.exists(code_directory), "Example code output already exists")
        dir.create(code_directory, recursive = FALSE, showWarnings = FALSE)
        .native_require(dir.exists(code_directory), "Missing local example code directory")
        for (file in files) {
            installed_rd <- db[[file]]
            source_rd <- tools::parse_Rd(file.path(cfg$source_man, file))
            has_examples <- length(section(installed_rd, "\\examples")) > 0L
            .native_require(identical(has_examples, length(section(source_rd, "\\examples")) > 0L),
                paste("Example presence differs:", file))
            aliases <- section(installed_rd, "\\alias")
            .native_require(length(aliases) > 0L, paste("Missing installed help alias:", file))
            alias <- text(aliases[[1L]])
            record <- list(file = file, topic = alias, has_examples = has_examples)
            if (has_examples) {
                installed_code <- file.path(code_directory, paste0(file, "-installed.R"))
                source_code <- file.path(code_directory, paste0(file, "-source.R"))
                tools::Rd2ex(installed_rd, installed_code,
                    commentDontrun = TRUE, commentDonttest = FALSE)
                tools::Rd2ex(source_rd, source_code,
                    commentDontrun = TRUE, commentDonttest = FALSE)
                .native_require(identical(readBin(installed_code, "raw", file.info(installed_code)$size),
                                          readBin(source_code, "raw", file.info(source_code)$size)),
                    paste("Installed/source example code differs:", file))
                record$installed_code_md5 <- unname(tools::md5sum(installed_code))
                record$source_code_md5 <- unname(tools::md5sum(source_code))
                lines <- utils::example(alias, package = "dtatools", lib.loc = dirname(cfg$package$path),
                    character.only = TRUE, give.lines = TRUE, type = "console",
                    run.dontrun = FALSE, run.donttest = TRUE)
                .native_require(identical(lines, readLines(installed_code, warn = FALSE)),
                    paste("Public example selection differs:", file))
                record$optional_guards <- lines[grepl("requireNamespace\\(", lines)]
                inventory[[length(inventory) + 1L]] <- record
                number <- length(topics) + 1L
                prefix <- sprintf("%03d", number)
                .native_checkpoint(cfg, paste0("before-example-", alias),
                    file.path(output, paste0(prefix, "-before.R")))
                observed <- list(file = file, topic = alias, warnings = list(), error = NULL,
                                 completed = FALSE)
                interrupted <- NULL
                tryCatch(withCallingHandlers({
                    utils::example(alias, package = "dtatools", lib.loc = dirname(cfg$package$path),
                        character.only = TRUE, local = new.env(parent = .GlobalEnv), type = "console",
                        echo = TRUE, setRNG = TRUE, ask = FALSE, catch.aborts = FALSE,
                        run.dontrun = FALSE, run.donttest = TRUE)
                    observed$completed <- TRUE
                }, warning = function(condition) {
                    observed$warnings[[length(observed$warnings) + 1L]] <<- condition_record(condition)
                }), error = function(condition) {
                    observed$error <<- condition_record(condition)
                }, interrupt = function(condition) {
                    observed$error <<- condition_record(condition)
                    interrupted <<- condition
                })
                topics[[length(topics) + 1L]] <- observed
                .native_write(file.path(output, paste0(prefix, "-result.R")), observed)
                .native_checkpoint(cfg, paste0("after-example-", alias),
                    file.path(output, paste0(prefix, "-after.R")))
                if (!is.null(interrupted)) stop(interrupted)
            } else {
                inventory[[length(inventory) + 1L]] <- record
            }
        }
        .native_require(length(topics) > 0L, "No installed examples executed")
        .native_require(all(vapply(topics, function(x) isTRUE(x$completed) && is.null(x$error), logical(1))),
            "An installed example failed")
    }, error = function(condition) { original <<- condition_record(condition) },
       interrupt = function(condition) { original <<- condition_record(condition) })
    tryCatch(.native_checkpoint(cfg, "examples-terminal", file.path(output, "terminal.R")),
        error = function(condition) { terminal_error <<- condition_record(condition) })
    result <- list(complete = is.null(original) && is.null(terminal_error),
        original_error = original, terminal_error = terminal_error, inventory = inventory, topics = topics,
        run_dontrun = FALSE, run_donttest = TRUE,
        scope = "Installed public examples matched to archived source help; native library checks before/after every executed topic")
    .native_write(file.path(output, "result.R"), result)
    if (isNamespaceLoaded("jsonlite")) jsonlite::write_json(result, file.path(output, "result.json"),
        auto_unbox = TRUE, pretty = TRUE, null = "null")
    if (!result$complete) quit(status = 1L)
})
