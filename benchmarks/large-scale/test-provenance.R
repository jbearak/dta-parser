script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument)))
source(file.path(script_dir, "..", "benchmark-common.R"), local = TRUE)
source(file.path(script_dir, "provenance.R"), local = TRUE)

root <- tempfile("large-scale-provenance-")
dir.create(root)
on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
status <- system2("git", c("-C", shQuote(root), "init", "--quiet"))
stopifnot(identical(status, 0L))
dir.create(file.path(root, "scope"))
tracked <- file.path(root, "scope", "tracked.txt")
writeLines("tracked", tracked)
status <- system2(
    "git", c("-C", shQuote(root), "add", "--", "scope/tracked.txt")
)
stopifnot(identical(status, 0L))

present_digest <- benchmark_tree_digest(root, "scope")
unlink(tracked)
missing_digest <- benchmark_tree_digest(root, "scope")
stopifnot(!identical(present_digest, missing_digest))

stopifnot(file.symlink("missing-target", tracked))
dangling_error <- tryCatch(
    benchmark_tree_digest(root, "scope"),
    error = identity
)
stopifnot(
    inherits(dangling_error, "error"),
    identical(
        conditionMessage(dangling_error),
        "benchmark source provenance input must be a regular nonsymlink file"
    )
)

cat("Large-scale provenance framework: PASS\n")
