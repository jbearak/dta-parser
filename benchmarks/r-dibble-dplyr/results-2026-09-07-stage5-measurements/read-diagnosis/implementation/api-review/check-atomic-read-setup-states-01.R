# Saved-state-only inspection; no package or operation is loaded.
root <- "/private/tmp/dta-direct-stage5-validation/root-expression-performance"
count <- 0L
for (setup in c("cold", "warm")) {
    path <- file.path(root, paste0("candidate-a2d8b6a-read-setup-", setup, "-01"))
    before <- readRDS(file.path(path, "source-states-1.rds"))
    fork <- readRDS(file.path(path, "fork-states.rds"))
    stopifnot(identical(names(before), c("before", "before_profile", "before_timing")),
              identical(names(fork), c("source", "result")))
    stages <- c(before, fork)
    for (stage in stages) {
        stopifnot(length(stage) == 8L)
        for (column in stage) {
            stopifnot(identical(names(column), c("handle_shared", "backing_private", "exposed", "backing", "handle", "depth", "bytes")),
                      isTRUE(column$handle_shared), identical(column$backing_private, FALSE),
                      identical(column$exposed, FALSE), column$depth == 1L, column$bytes == 800000,
                      is.character(column$backing), length(column$backing) == 1L)
            count <- count + 1L
        }
    }
    backing <- function(x) vapply(x, function(y) y$backing, "")
    handles <- function(x) vapply(x, function(y) y$handle, "")
    stopifnot(all(vapply(stages, function(x) identical(backing(x), backing(before[[1L]])), logical(1))),
              identical(handles(fork$source), handles(before[[1L]])),
              all(handles(fork$result) != handles(fork$source)))
    cat("PASS", setup, "five eight-column stages preserve all backings; renamed result has fresh handles\n")
}
stopifnot(count == 80L)
cat("PASS eighty saved column-state records\n")
