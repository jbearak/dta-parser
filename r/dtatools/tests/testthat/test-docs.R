# The documentation's R examples run, and every export is documented.
#
# Each ```r block of README.md, docs/guide/*.md and docs/r.md runs, in
# order, in one environment per file, in a fresh temporary directory.
# Blocks whose info string says `norun` (installation) are skipped. The
# docs live in the repository, not the package, so this skips when the
# package is tested outside a checkout.

repo_root <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", ".."), mustWork = FALSE)

doc_files <- function() {
  testthat::skip_if_not(file.exists(file.path(repo_root, "docs", "r.md")), "docs/r.md is not here")
  c(file.path(repo_root, "README.md"),
    sort(Sys.glob(file.path(repo_root, "docs", "guide", "*.md"))),
    file.path(repo_root, "docs", "r.md"))
}

# The code blocks of one language in a Markdown file: a list of
# list(line, code), `line` being where the block starts.
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
      blocks[[length(blocks) + 1]] <- list(line = i, code = paste(lines[seq_len(end - i - 1) + i], collapse = "\n"))
    }
    i <- end + 1
  }
  blocks
}

test_that("every R example in the docs runs", {
  for (path in doc_files()) {
    blocks <- code_blocks(path, "r")
    if (!length(blocks)) next
    dir <- tempfile("docs-")
    dir.create(dir)
    old <- setwd(dir)
    env <- new.env(parent = globalenv())
    for (b in blocks) {
      where <- paste0(basename(path), ":", b$line)
      result <- tryCatch({
        utils::capture.output(eval(parse(text = b$code, keep.source = FALSE), envir = env))
        NULL
      }, error = function(e) conditionMessage(e))
      expect(is.null(result), paste0(where, ": ", result))
    }
    setwd(old)
    unlink(dir, recursive = TRUE)
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
})
