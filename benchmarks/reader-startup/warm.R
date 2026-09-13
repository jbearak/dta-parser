# Batch warm reads so sub-millisecond calls exceed the R clock resolution.
args <- commandArgs(TRUE)
stopifnot(length(args) == 3L, args[[1L]] %in% c("read_dta", "read_arrow"))
.libPaths(c(Sys.getenv("DTATOOLS_BENCH_LIB"), .libPaths()))
read <- getExportedValue("dtatools", args[[1L]])
stopifnot(identical(normalizePath(find.package("dtatools")),
                    normalizePath(file.path(Sys.getenv("DTATOOLS_BENCH_LIB"), "dtatools"))))
path <- args[[2L]]
count <- as.integer(args[[3L]])
stopifnot(!is.na(count), count > 0L)
value <- read(path)
gc()
started <- proc.time()
for (iteration in seq_len(count)) value <- read(path)
duration <- (proc.time() - started) / count
cat(sprintf("DTATOOLS_BENCH\tok\t%.9f\t%d\t%d\n",
            duration[["elapsed"]], nrow(value), ncol(value)))
cat(sprintf("DTATOOLS_CPU\t%.9f\t%.9f\n",
            duration[["user.self"]], duration[["sys.self"]]))
