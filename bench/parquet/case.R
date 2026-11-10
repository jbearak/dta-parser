# One Parquet benchmark case in R, in a fresh process; bench/parquet/run.py
# runs it under /usr/bin/time -l, five times per case.
#
#   Rscript bench/parquet/case.R LIB TASK FILE OUT COLS SKIP N [WARM]
#
# LIB is ours (datakit), arrow, nanoparquet or duckdb. TASK is one of
#   full    read the whole file
#   five    read five named columns (COLS, comma-separated)
#   window  read N rows from row SKIP (0-based)
#   pass    read the whole file, then one pass over every value
#   write   read FILE (a .dta) with dtaparser, then time writing it with
#           LIB's defaults
#   zstd    the same, with zstd at level 3
#   snappy  the same, with snappy (ours only: for the default codec)
# Only the task is timed (wall and CPU, user plus system, of this
# process and its threads); OUT gets a JSON report. That first call is
# the process's first use of the library, with whatever the library
# sets up once (its threads, its lazily loaded code). With WARM (for
# bench/parquet/warm.py), a read is then called up to WARM more times,
# with gc() before each, stopping after 20 seconds once two are done:
# the report also holds their median wall and CPU times, what a
# session's later reads cost.
args <- commandArgs(trailingOnly = TRUE)
lib <- args[[1]]; task <- args[[2]]; path <- args[[3]]; out_path <- args[[4]]
cols <- strsplit(args[[5]], ",", fixed = TRUE)[[1]]
skip <- as.numeric(args[[6]]); n <- as.numeric(args[[7]])
warm <- if (length(args) >= 8) as.integer(args[[8]]) else 0L
tmp <- dirname(normalizePath(out_path, mustWork = FALSE))

pkg <- c(ours = "datakit", arrow = "arrow", nanoparquet = "nanoparquet", duckdb = "duckdb")[[lib]]
invisible(loadNamespace(pkg))
for (ns in c("tibble", "vctrs", "tidyselect", "dtaparser")) invisible(loadNamespace(ns))
if (lib == "duckdb") invisible(loadNamespace("DBI"))
loaded <- as.numeric(Sys.time())

now <- function() as.numeric(Sys.time())
cpu <- function() {
  t <- proc.time()
  t[["user.self"]] + t[["sys.self"]]
}
quoted <- function(x) paste0('"', gsub('"', '""', x), '"')
sql_path <- function(p) paste0("'", gsub("'", "''", p), "'")

con <- NULL
if (lib == "duckdb") con <- DBI::dbConnect(duckdb::duckdb())
duck <- function(sql) DBI::dbGetQuery(con, sql)

readers <- list(
  ours = list(
    full = function(p) datakit::read_parquet(p),
    five = function(p, cols) datakit::read_parquet(p, col_select = cols),
    window = function(p, skip, n) datakit::read_parquet(p, skip = skip, n_max = n)
  ),
  arrow = list(
    full = function(p) arrow::read_parquet(p),
    five = function(p, cols) arrow::read_parquet(p, col_select = tidyselect::all_of(cols)),
    # read_parquet() has no rows; the shortest route reads the table and
    # converts only the slice.
    window = function(p, skip, n) {
      t <- arrow::read_parquet(p, as_data_frame = FALSE)
      as.data.frame(t$Slice(skip, n))
    }
  ),
  nanoparquet = list(
    full = function(p) nanoparquet::read_parquet(p),
    five = function(p, cols) nanoparquet::read_parquet(p, col_select = cols),
    # No rows either: read, then slice.
    window = function(p, skip, n) {
      d <- nanoparquet::read_parquet(p)
      d[seq(skip + 1, min(skip + n, nrow(d))), , drop = FALSE]
    }
  ),
  duckdb = list(
    full = function(p) duck(paste("SELECT * FROM read_parquet(", sql_path(p), ")")),
    five = function(p, cols) duck(paste("SELECT", paste(quoted(cols), collapse = ", "), "FROM read_parquet(", sql_path(p), ")")),
    window = function(p, skip, n) duck(sprintf("SELECT * FROM read_parquet(%s) LIMIT %d OFFSET %d", sql_path(p), n, skip))
  )
)

writers <- list(
  ours = list(
    write = function(d, dst) datakit::save_parquet(d, dst),
    zstd = function(d, dst) datakit::save_parquet(d, dst, compression = "zstd", compression_level = 3),
    snappy = function(d, dst) datakit::save_parquet(d, dst, compression = "snappy")
  ),
  arrow = list(
    write = function(d, dst) arrow::write_parquet(d, dst),
    zstd = function(d, dst) arrow::write_parquet(d, dst, compression = "zstd", compression_level = 3)
  ),
  nanoparquet = list(
    write = function(d, dst) nanoparquet::write_parquet(d, dst),
    zstd = function(d, dst) nanoparquet::write_parquet(d, dst, compression = "zstd",
                                                       options = nanoparquet::parquet_options(compression_level = 3))
  ),
  duckdb = list(
    write = function(d, dst) {
      duckdb::duckdb_register(con, "t", d)
      DBI::dbExecute(con, paste("COPY t TO", sql_path(dst), "(FORMAT parquet)"))
    },
    zstd = function(d, dst) {
      duckdb::duckdb_register(con, "t", d)
      DBI::dbExecute(con, paste("COPY t TO", sql_path(dst), "(FORMAT parquet, COMPRESSION zstd, COMPRESSION_LEVEL 3)"))
    }
  )
)

# One pass over every value: the sum of the numbers, the count of
# missing values and the total length of the text, so deferred work
# (arrow's and our strings) is done.
pass <- function(d) {
  total <- 0; missing <- 0; len <- 0
  for (x in d) {
    if (is.character(x)) {
      len <- len + sum(nchar(x), na.rm = TRUE)
      missing <- missing + sum(is.na(x))
    } else if (is.list(x)) {
      len <- len + sum(lengths(x))
    } else {
      v <- as.double(vctrs::vec_data(if (is.factor(x)) as.integer(x) else x))
      miss <- is.na(v)
      total <- total + sum(v[!miss])
      missing <- missing + sum(miss)
    }
  }
  list(sum = total, missing = missing, length = len)
}

threads <- switch(lib,
  ours = { d <- Sys.getenv("DTA_THREADS"); if (nzchar(d)) d else "default" },
  arrow = as.character(arrow::cpu_count()),
  nanoparquet = "1",
  duckdb = as.character(duck("SELECT current_setting('threads') AS t")$t)
)

result <- list(loaded = loaded, version = as.character(utils::packageVersion(pkg)), threads = threads)
if (task %in% c("write", "zstd", "snappy")) {
  d <- dtaparser::read_dta(path)
  # A frame as a user holds it: every string made, so no writer pays for
  # another's deferred strings. Labelled columns stay as read_dta gives
  # them, except for DuckDB, which cannot register the class: plain
  # numbers there (not timed).
  for (i in seq_along(d)) {
    if (is.character(d[[i]])) { s <- character(length(d[[i]])); s[] <- d[[i]]; d[[i]] <- s }
    if (lib == "duckdb" && inherits(d[[i]], "dtaparser_labelled")) d[[i]] <- vctrs::vec_data(d[[i]])
  }
  dst <- file.path(tmp, sprintf("w%d.parquet", Sys.getpid()))
  invisible(gc())
  t0 <- now(); c0 <- cpu()
  writers[[lib]][[task]](d, dst)
  result$wall <- now() - t0; result$cpu <- cpu() - c0
  result$bytes <- file.size(dst)
  unlink(dst)
} else {
  r <- readers[[lib]]
  run <- function() switch(task,
    full = r$full(path),
    five = r$five(path, cols),
    window = r$window(path, skip, n),
    pass = pass(r$full(path)))
  invisible(gc())
  t0 <- now(); c0 <- cpu()
  out <- run()
  result$wall <- now() - t0; result$cpu <- cpu() - c0
  if (task == "pass") result$checksum <- out else result$rows <- nrow(out)
  if (warm > 0) {
    walls <- numeric(); cpus <- numeric(); started <- now()
    for (i in seq_len(warm)) {
      rm(out); invisible(gc())
      t0 <- now(); c0 <- cpu()
      out <- run()
      walls[i] <- now() - t0; cpus[i] <- cpu() - c0
      if (i >= 2 && now() - started > 20) break
    }
    result$warm_wall <- stats::median(walls); result$warm_cpu <- stats::median(cpus)
    result$warm_runs <- length(walls)
  }
}
writeLines(jsonlite::toJSON(result, auto_unbox = TRUE, digits = NA), out_path)
