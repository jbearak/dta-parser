# Private runtime inventory; the Python driver removes library paths before publication.
args <- commandArgs(TRUE)
script <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]])
source(file.path(dirname(normalizePath(script)), "common.R"))
activate_library()
cat("R\t", R.version.string, "\t", R.version$platform, "\t", R.home("bin"), "\n", sep = "")
for (package in c("dtatools", "tibble", "haven", "arrow", "data.table", "readr", "vroom", "fst", "qs2")) {
    available <- requireNamespace(package, quietly = TRUE)
    cat("PACKAGE\t", package, "\t", if (available) as.character(packageVersion(package)) else "unavailable",
        "\t", if (available) normalizePath(find.package(package)) else "-", "\n", sep = "")
}
if (requireNamespace("data.table", quietly = TRUE)) cat("THREADS\tfread\t", data.table::getDTthreads(), "\n", sep = "")
if (requireNamespace("arrow", quietly = TRUE)) cat("THREADS\tarrow\t", arrow::cpu_count(), "\n", sep = "")
if (requireNamespace("readr", quietly = TRUE)) cat("THREADS\treadr\t", readr::readr_threads(), "\n", sep = "")
if (requireNamespace("vroom", quietly = TRUE)) cat("THREADS\tvroom\t", eval(formals(vroom::vroom)$num_threads, environment(vroom::vroom)), "\n", sep = "")
if (requireNamespace("fst", quietly = TRUE)) cat("THREADS\tfst\t", fst::threads_fst(), "\n", sep = "")
cat("THREADS\tqs2\t1\n")
cat("THREADS\tdtatools\t", getOption("dtatools.threads", 0L), "\n", sep = "")

if (requireNamespace("vroom", quietly = TRUE)) cat("ALTREP\t", as.integer(vroom::vroom_altrep()), "\n", sep = "")
