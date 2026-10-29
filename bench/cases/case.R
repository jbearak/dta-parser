# Benchmark tasks for R's .dta readers; bench/run.py drives this.
#   Rscript bench/cases/case.R READER FILE OUT TASKS RUNS COLS SKIP N
# READER is ours (dtatools), haven or readstata13. The arguments are as
# in bench/cases/case.py.
args <- commandArgs(trailingOnly = TRUE)
reader <- args[[1]]; path <- args[[2]]; out_path <- args[[3]]; tasks <- args[[4]]
runs <- as.integer(args[[5]]); cols <- strsplit(args[[6]], ",")[[1]]
skip <- as.numeric(args[[7]]); n <- as.numeric(args[[8]])
tmp <- dirname(normalizePath(out_path, mustWork = FALSE))

pkg <- c(ours = "dtatools", haven = "haven", readstata13 = "readstata13")[[reader]]
invisible(loadNamespace(pkg))
if (reader == "haven") invisible(loadNamespace("tidyselect"))
loaded <- as.numeric(Sys.time())

# Seconds, to the microsecond (proc.time() counts milliseconds).
now <- function() as.numeric(Sys.time())

r13 <- function(...) readstata13::read.dta13(..., convert.factors = FALSE, convert.dates = FALSE)
readers <- list(
  ours = list(
    read = function(p) dtatools::read_dta(p),
    five = function(p, cols) dtatools::read_dta(p, col_select = cols),
    window = function(p, skip, n) dtatools::read_dta(p, skip = skip, n_max = n),
    meta = function(p) dtatools::read_dta(p, n_max = 0),
    write = function(d, dst) dtatools::save_dta(d, dst)
  ),
  haven = list(
    read = function(p) haven::read_dta(p),
    five = function(p, cols) haven::read_dta(p, col_select = tidyselect::all_of(cols)),
    window = function(p, skip, n) haven::read_dta(p, skip = skip, n_max = n),
    meta = function(p) haven::read_dta(p, n_max = 0),
    write = function(d, dst) haven::write_dta(d, dst, version = 14)
  ),
  readstata13 = list(
    read = function(p) r13(p),
    five = function(p, cols) r13(p, select.cols = cols),
    window = function(p, skip, n) r13(p, select.rows = c(skip + 1, skip + n)),
    # No metadata-only read: the nearest is one row.
    meta = function(p) r13(p, select.rows = c(1, 0)),
    write = function(d, dst) readstata13::save.dta13(d, dst, version = 118, convert.factors = FALSE,
                                                    convert.dates = FALSE)
  )
)
r <- readers[[reader]]
# In-process runs stop early, after at least three, once they pass this
# many seconds.
budget <- 60

# A column's numbers as Stata stores them (haven turns %td and %tc into
# Date and POSIXct).
as_stata <- function(x) {
  if (inherits(x, "Date")) return(as.double(x) + 3653)
  if (inherits(x, "POSIXct")) return((as.double(x) + 315619200) * 1000)
  as.double(x)
}

# Task 2: one pass over every value.
checksum <- function(d) {
  total <- 0; missing <- 0; len <- 0
  for (x in d) {
    if (is.character(x)) {
      len <- len + sum(nchar(x), na.rm = TRUE)
    } else {
      v <- as_stata(x)
      miss <- is.na(v)
      total <- total + sum(v[!miss])
      missing <- missing + sum(miss)
    }
  }
  list(sum = total, missing = missing, length = len)
}

run_task <- function(task) {
  if (task == 6) {
    d <- r$read(path)
    dst <- file.path(tmp, sprintf("w%d.dta", Sys.getpid()))
    gc()
    t <- now()
    r$write(d, dst)
    elapsed <- now() - t
    unlink(dst)
    return(list(elapsed, NULL))
  }
  gc()
  t <- now()
  out <- NULL
  switch(task,
    r$read(path),
    out <- checksum(r$read(path)),
    r$five(path, cols),
    r$window(path, skip, n),
    r$meta(path))
  list(now() - t, out)
}

# Correctness: each column as a hash of its canonical cells.
sha <- function(x) substr(digest::digest(x, algo = "sha256", serialize = FALSE), 1, 16)
hash_text <- function(x) if (is.null(x)) NULL else sha(enc2utf8(paste(x, collapse = "")))

codes_of <- function(x) {
  if (inherits(x, "dta_num")) return(dtatools:::dta_codes(x))
  if (inherits(x, "haven_labelled") || (reader == "haven" && is.double(x))) {
    tag <- haven::na_tag(x)
    return(ifelse(is.na(x), ifelse(is.na(tag), 1L, match(tag, letters) + 1L), 0L))
  }
  NULL
}

canon_column <- function(x) {
  if (is.character(x)) {
    x[is.na(x)] <- ""
    return(list(kind = "str", hash = sha(paste0(enc2utf8(paste(x, collapse = "\x1f")), "|", length(x)))))
  }
  v <- as_stata(x)
  miss <- is.na(v)
  v[miss] <- 0
  codes <- codes_of(x)
  list(kind = "num", hash = sha(c(writeBin(v, raw(), endian = "little"), as.raw(miss))),
       codes = if (!is.null(codes) && reader != "readstata13") sha(as.raw(codes)))
}

canon_frame <- function(d) list(nrows = nrow(d), columns = unname(lapply(d, canon_column)))

key_of <- function(v) {
  tag <- if (reader == "haven") haven::na_tag(v) else NA
  codes <- if (inherits(v, "dta_num")) dtatools:::dta_codes(v) else ifelse(is.na(v), ifelse(is.na(tag), 1L, match(tag, letters) + 1L), 0L)
  ifelse(codes == 0, sprintf("%.17g", as.double(v)), ifelse(codes == 1, ".", paste0(".", letters[pmax(codes - 1, 1)])))
}

label_text <- function(labels) {
  if (is.null(labels) || !length(labels)) return(hash_text(""))
  hash_text(paste(sort(paste0(key_of(labels), "\t", names(labels))), collapse = "\n"))
}

STORAGE13 <- c("65530" = "byte", "65529" = "int", "65528" = "long", "65527" = "float", "65526" = "double",
               "251" = "byte", "252" = "int", "253" = "long", "254" = "float", "255" = "double", "32768" = "strL")
canon_meta <- function(p) {
  if (reader == "readstata13") {
    d <- r13(p, select.rows = c(1, 0))
    types <- attr(d, "types"); sets <- attr(d, "label.table"); vl <- attr(d, "val.labels")
    columns <- lapply(seq_along(d), function(i) {
      st <- STORAGE13[as.character(types[[i]])]
      list(name = hash_text(names(d)[[i]]),
           storage = if (is.na(st)) paste0("str", types[[i]]) else unname(st),
           format = attr(d, "formats")[[i]], label = hash_text(attr(d, "var.labels")[[i]]),
           value_labels = label_text(if (nzchar(vl[[i]])) sets[[vl[[i]]]]))
    })
    return(list(label = hash_text(attr(d, "datalabel")), columns = columns))
  }
  d <- r$meta(p)
  columns <- lapply(names(d), function(nm) {
    x <- d[[nm]]
    st <- if (is.character(x)) "str" else attr(x, "storage")
    list(name = hash_text(nm), storage = st,
         format = attr(x, if (reader == "haven") "format.stata" else "format"),
         label = hash_text(attr(x, "label") %||% ""), value_labels = label_text(attr(x, "labels")))
  })
  list(label = hash_text(attr(d, "label") %||% ""), columns = columns)
}

attempt <- function(f) tryCatch(f(), error = function(e) list(error = substr(conditionMessage(e), 1, 500)))

check <- function() {
  out <- list()
  d <- NULL
  out$full <- attempt(function() { d <<- r$read(path); canon_frame(d) })
  if (!is.null(d)) {
    out$checksum <- attempt(function() {
      s <- checksum(d)
      s$abs <- sum(vapply(Filter(Negate(is.character), d), function(x) sum(abs(as_stata(x)), na.rm = TRUE), 0))
      s
    })
  }
  out$five <- attempt(function() canon_frame(r$five(path, cols)))
  out$window <- attempt(function() canon_frame(r$window(path, skip, n)))
  out$meta <- attempt(function() canon_meta(path))
  if (!is.null(d)) {
    dst <- file.path(tmp, sprintf("check%d.dta", Sys.getpid()))
    out$write <- attempt(function() {
      r$write(d, dst)
      # Re-read by an open-source reader (haven), as is the source.
      reader <<- "haven"
      r <<- readers$haven
      list(data = canon_frame(haven::read_dta(dst)), meta = canon_meta(dst))
    })
    unlink(dst)
  }
  out
}

report <- list(loaded = loaded, version = as.character(packageVersion(pkg)))
if (tasks == "check") {
  report$check <- check()
} else {
  report$tasks <- list()
  for (task in as.integer(strsplit(tasks, ",")[[1]])) {
    entry <- tryCatch({
      e <- list()
      times <- numeric()
      n_runs <- runs
      if (runs > 1) {
        res <- run_task(task)
        e$first <- res[[1]]; e$checksum <- res[[2]]
        # Too slow to repeat: the one run counts.
        if (e$first > budget) { times <- e$first; n_runs <- 0 }
      }
      for (i in seq_len(n_runs)) {
        res <- run_task(task)
        times <- c(times, res[[1]])
        e$checksum <- res[[2]]
        if (length(times) >= 3 && sum(times) > budget) break
      }
      e$times <- I(times)  # a JSON array even with one run
      e
    }, error = function(e) list(error = substr(conditionMessage(e), 1, 500)))
    report$tasks[[as.character(task)]] <- entry
  }
}
jsonlite::write_json(report, out_path, auto_unbox = TRUE, digits = NA, null = "null")
