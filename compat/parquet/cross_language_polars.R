# One frame in both languages (plan 0025, stage 4). R's half:
#
#     Rscript compat/parquet/cross_language_polars.R save DIR
#     Rscript compat/parquet/cross_language_polars.R dump DIR
#
# compat/parquet/cross_language_polars.sh runs them between Python's
# halves; cross_language_polars.py says what each step does and compares.
# `save` reads DIR/fixture.parquet and DIR/fixture.dta with
# read_parquet_pl() and read_dta_pl(), with factors off and on, and saves
# what it read with save_parquet() and save_dta() as
# DIR/saved_r*.{parquet,dta}. `dump` makes every read DIR/cases.json
# lists and writes each frame as Arrow IPC (DIR/r/CASE.arrow) and its
# datakit_meta as JSON (DIR/r/CASE.json), value labels as {"set",
# "code", "text"} records, a code being a number or ".", ".a" ... ".z".
#
# Needs dtaparser, datakit, polars, nanoarrow and jsonlite installed
# (R_LIBS may point at a scratch library holding them).

suppressPackageStartupMessages({
  library(datakit)
  library(polars)
})

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2, args[1] %in% c("save", "dump"))
dir <- args[2]

read_one <- function(file, a) {
  path <- file.path(dir, file)
  reader <- if (endsWith(file, ".dta")) read_dta_pl else read_parquet_pl
  call <- list(path, skip = a$skip %||% 0, n_max = a$n_max %||% Inf, factors = isTRUE(a$factors),
               letters = !identical(a$letters, FALSE))
  if (!is.null(a$columns)) call$col_select <- unlist(a$columns)
  suppressWarnings(do.call(reader, call))
}

if (args[1] == "save") {
  for (src in c("fixture.parquet", "fixture.dta")) {
    for (factors in c(FALSE, TRUE)) {
      res <- read_one(src, list(factors = factors))
      ext <- tools::file_ext(src)
      out <- file.path(dir, paste0("saved_r", if (factors) "_factors", ".", ext))
      if (ext == "dta") save_dta(res$df, out, meta = res$meta) else save_parquet(res$df, out, meta = res$meta)
    }
  }
  cat("R saved what it read in", dir, "\n")
  quit(status = 0)
}

# A value label's code: a number, or ".", ".a" ... ".z".
code_of <- function(v) {
  tag <- na_tag(v)
  if (!is.na(tag)) return(paste0(".", tag))
  if (is.na(v)) return(".")
  unclass(v)
}

# A named list that jsonlite writes as an object even when empty.
object <- function(x) if (length(x)) as.list(x) else structure(list(), names = character())

meta_json <- function(meta) {
  columns <- lapply(names(meta$columns), function(n) {
    c <- meta$columns[[n]]
    list(name = n, label = c$label, format = c$format, value_labels = c$value_labels, ordered = c$ordered)
  })
  labels <- list()
  for (s in names(meta$value_labels)) {
    set <- meta$value_labels[[s]]
    for (i in seq_along(set)) {
      labels[[length(labels) + 1]] <- list(set = s, code = code_of(set[i]), text = names(set)[[i]])
    }
  }
  list(
    label = meta$label,
    notes = I(meta$notes),
    characteristics = object(lapply(meta$characteristics, object)),
    sort = I(meta$sort),
    timestamp = meta$timestamp,
    columns = columns,
    value_labels = labels,
    rows = meta$rows,
    storage = object(meta$storage)
  )
}

out_dir <- file.path(dir, "r")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
cases <- jsonlite::read_json(file.path(dir, "cases.json"))
for (case in cases) {
  out <- file.path(out_dir, case$name)
  res <- tryCatch(read_one(case$file, case$args), error = function(e) e)
  if (inherits(res, "error")) {
    jsonlite::write_json(list(error = conditionMessage(res)), paste0(out, ".json"), auto_unbox = TRUE)
    next
  }
  res$df$write_ipc(paste0(out, ".arrow"), compression = "uncompressed")
  jsonlite::write_json(meta_json(res$meta), paste0(out, ".json"), auto_unbox = TRUE, null = "null", na = "null",
                       digits = NA, pretty = TRUE)
}
cat("R dumped", length(cases), "reads in", out_dir, "with polars", format(packageVersion("polars")), "\n")
