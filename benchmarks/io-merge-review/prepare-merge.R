# Reproduce the README fixture without running unrelated join competitors.
args <- commandArgs(TRUE)
stopifnot(length(args) == 1L, dir.exists(args[[1L]]))
directory <- normalizePath(args[[1L]])
root <- Sys.getenv("DTATOOLS_REVIEW_ROOT")
source(file.path(root, "benchmarks/reader-refresh/workers/benchmark-common.R"))
benchmark_activate_library("dtatools", verify_dtatools = TRUE)
suppressPackageStartupMessages(library(dtatools))
stopifnot(!any(file.exists(file.path(directory, c("master.dta", "using.dta", "master-standard.rds", "using-standard.rds")))))
set.seed(7)
n_master <- 200000L
mothers <- sample.int(n_master, 120000L)
births_per <- sample(1:5, length(mothers), replace = TRUE)
n_using <- sum(births_per)
stopifnot(n_using == 360044L)
caseid <- sprintf("%04d %06d %02d", sample.int(9999, n_master, replace = TRUE),
                  seq_len(n_master), sample.int(20, n_master, replace = TRUE))
shared_names <- sprintf("s%d", 1:60)
master <- tibble::new_tibble(c(list(caseid = caseid),
    setNames(lapply(seq_len(60L), function(index) dta_int(sample.int(500, n_master, replace = TRUE))), shared_names),
    setNames(lapply(seq_len(90L), function(index) rnorm(n_master)), sprintf("m%d", seq_len(90L)))) , nrow = n_master)
using <- tibble::new_tibble(c(list(caseid = rep(caseid[mothers], births_per),
    bidx = dta_byte(unlist(lapply(births_per, seq_len)))),
    setNames(lapply(seq_len(60L), function(index) dta_int(sample.int(500, n_using, replace = TRUE))), shared_names),
    setNames(lapply(seq_len(48L), function(index) rnorm(n_using)), sprintf("u%d", seq_len(48L)))) , nrow = n_using)
save_dta(master, file.path(directory, "master.dta"))
save_dta(using, file.path(directory, "using.dta"))
rm(master, using)
invisible(gc())
ordinary <- function(value) {
    if (inherits(value, c("dta_byte", "dta_int", "dta_long"))) return(as.integer(as.vector(value)))
    if (inherits(value, c("dta_float", "dta_double"))) return(as.double(as.vector(value)))
    if (is.character(value)) return(as.character(value))
    if (is.integer(value)) return(as.integer(value))
    if (is.double(value)) return(as.double(value))
    stop("unsupported fixture column")
}
for (side in c("master", "using")) {
    data <- read_dta(file.path(directory, paste0(side, ".dta")))
    frame <- as.data.frame(lapply(data, ordinary), optional = TRUE,
                           stringsAsFactors = FALSE, check.names = FALSE)
    saveRDS(frame, file.path(directory, paste0(side, "-standard.rds")), compress = FALSE)
    cat(side, nrow(frame), ncol(frame), datasig(data), "\n", sep = "\t")
}
