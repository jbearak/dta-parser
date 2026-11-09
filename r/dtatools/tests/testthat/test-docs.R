# The documentation's R examples run, and every export is documented.
#
# Each ```r block of README.md, docs/guide/*.md and docs/r.md runs, in
# order, in one environment per file, in a fresh temporary directory, and
# the packages a file attaches are detached after it.
# Blocks whose info string says `norun` (installation) are skipped.
# Blocks whose info string says `polars` (datakit's polars functions)
# need R 4.3, polars and nanoarrow: without them they are skipped, or,
# with DATAKIT_REQUIRE_POLARS=true (CI), the test fails. The docs live
# in the repository, not the package, so this skips when the package is
# tested outside a checkout.

repo_root <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", ".."), mustWork = FALSE)

doc_files <- function() {
  testthat::skip_if_not(file.exists(file.path(repo_root, "docs", "r.md")), "docs/r.md is not here")
  c(file.path(repo_root, "README.md"),
    sort(Sys.glob(file.path(repo_root, "docs", "guide", "*.md"))),
    file.path(repo_root, "docs", "r.md"))
}

# The code blocks of one language in a Markdown file: a list of
# list(line, code, polars), `line` being where the block starts and
# `polars` whether its info string says so.
code_blocks <- function(path, lang) {
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  blocks <- list()
  i <- 1
  while (i <= length(lines)) {
    open <- regmatches(lines[i], regexec("^```+\\s*([A-Za-z]*)(.*)$", lines[i]))[[1]]
    if (length(open) == 0) {
      i <- i + 1
      next
    }
    fence <- sub("^(`+).*", "\\1", lines[i])
    end <- i + 1
    while (end <= length(lines) && !startsWith(lines[end], fence)) end <- end + 1
    if (open[2] == lang && !grepl("norun", open[3])) {
      blocks[[length(blocks) + 1]] <- list(line = i, code = paste(lines[seq_len(end - i - 1) + i], collapse = "\n"),
                                           polars = grepl("polars", open[3]))
    }
    i <- end + 1
  }
  blocks
}

# What the polars examples need that is missing: character() if nothing.
polars_missing <- function() {
  c(if (getRversion() < "4.3") "R 4.3",
    if (!requireNamespace("polars", quietly = TRUE)) "polars",
    if (!requireNamespace("nanoarrow", quietly = TRUE)) "nanoarrow")
}

test_that("every R example in the docs runs", {
  missing <- polars_missing()
  if (length(missing) && identical(tolower(Sys.getenv("DATAKIT_REQUIRE_POLARS")), "true")) {
    stop("DATAKIT_REQUIRE_POLARS is set, but the docs' polars examples need ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  skipped <- character()
  for (path in doc_files()) {
    blocks <- code_blocks(path, "r")
    if (!length(blocks)) next
    dir <- tempfile("docs-")
    dir.create(dir)
    old <- setwd(dir)
    attached <- search()
    env <- new.env(parent = globalenv())
    for (b in blocks) {
      where <- paste0(basename(path), ":", b$line)
      if (b$polars && length(missing)) {
        skipped <- c(skipped, where)
        next
      }
      result <- tryCatch({
        utils::capture.output(eval(parse(text = b$code, keep.source = FALSE), envir = env))
        NULL
      }, error = function(e) conditionMessage(e))
      expect(is.null(result), paste0(where, ": ", result))
    }
    setwd(old)
    unlink(dir, recursive = TRUE)
    # A file's library() calls attach for the whole session; detach them
    # so that, say, README.md's dtaparser does not mask dtatools' read_dta
    # in docs/r.md.
    for (name in setdiff(search(), attached)) detach(name, character.only = TRUE)
  }
  if (length(skipped)) {
    testthat::skip(paste0(length(skipped), " polars examples not run: they need ", paste(missing, collapse = ", ")))
  }
})

test_that("every export has a help page and appears in docs/r.md", {
  page <- paste(readLines(doc_files()[[length(doc_files())]], encoding = "UTF-8", warn = FALSE), collapse = "\n")
  for (name in sort(getNamespaceExports("dtatools"))) {
    expect(length(utils::help(name, package = "dtatools")) > 0, paste("no help page for", name))
    if (grepl("^\\.[a-z]$", name)) next  # .a to .z: documented together
    expect(grepl(paste0("`", name, "("), page, fixed = TRUE) || grepl(paste0("`", name, "`"), page, fixed = TRUE),
           paste("docs/r.md does not mention", name))
  }
  for (pkg in c("dtaparser", "datakit")) {
    for (name in sort(getNamespaceExports(pkg))) {
      expect(length(utils::help(name, package = (pkg))) > 0, paste0("no help page for ", pkg, "'s ", name))
      expect(grepl(paste0("`", name, "("), page, fixed = TRUE) || grepl(paste0("`", name, "`"), page, fixed = TRUE),
             paste0("docs/r.md does not mention ", pkg, "'s ", name))
    }
  }
})
