stata_fixture_schema <- "byte=4,int=4,long=9,float=4,double=9,string=10"
stata_fixture_columns <- 40L
stata_fixture_row_bytes <- 431L
stata_fixture_calibration_rows <- 1000L

find_stata <- function() {
    candidates <- unique(c(
        Sys.getenv("STATA_BIN"),
        "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp",
        Sys.which("stata-mp"), Sys.which("stata")
    ))
    candidates <- candidates[nzchar(candidates)]
    candidates <- candidates[file.exists(candidates)]
    if (!length(candidates)) stop("Stata is required; set STATA_BIN")
    normalizePath(candidates[[1L]], winslash = "/", mustWork = TRUE)
}

read_stata_fixture_result <- function(path) {
    fields <- strsplit(
        readLines(path, n = 1L, warn = FALSE), "\t", fixed = TRUE
    )[[1L]]
    if (length(fields) != 6L || fields[[1L]] != "stata" ||
        fields[[2L]] != "ok") {
        stop("Stata fixture generation failed")
    }
    numeric <- suppressWarnings(as.numeric(fields[3:6]))
    if (any(!is.finite(numeric)) || numeric[[1L]] < 0 ||
        numeric[[2L]] <= 0 || numeric[[3L]] != stata_fixture_columns ||
        numeric[[4L]] <= 0) {
        stop("Stata fixture generator returned invalid measurements")
    }
    list(
        elapsed_seconds = numeric[[1L]], rows = numeric[[2L]],
        columns = numeric[[3L]], bytes = numeric[[4L]]
    )
}
