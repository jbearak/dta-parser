# The legacy fixtures' R half (README.md here). Two modes:
#
#     Rscript compat/parquet/legacy/make.R write   # R's save_parquet() writes r_*.parquet
#     Rscript compat/parquet/legacy/make.R read    # R's read_parquet() reads every *.parquet
#
# `write` saves each data frame it writes as <name>.rds beside its file.
# `read` saves, as <name>.read.rds, what datakit 3.1.0 reads from every
# file here, R's and TypeScript's, with the options in readings.R.
# make.sh runs both, with make.mjs between them.
#
# Needs dtaparser and datakit 3.1.0, tibble and bit64 (R_LIBS may point
# at a scratch library holding them). Every value is made here.

suppressPackageStartupMessages({
  library(dtaparser)
  library(datakit)
})

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1, args[1] %in% c("write", "read"))
dir <- "compat/parquet/legacy"
stopifnot(dir.exists(dir))
na <- tagged_na

if (args[1] == "write") {
  # Every type R's writer takes, with labels, formats, .a to .z and nulls.
  types <- function() {
    n <- 8
    score <- with_labels(c(1.5, NA, na("a"), -2.25, na("z"), 2^1000, NaN, -0),
                         c(Low = 1.5, na(c(Refused = "a", Other = "z"))), label = "A score")
    attr(score, "label_set") <- "scorelab"
    attr(score, "format") <- "%9.2f"
    # Two columns sharing one label set.
    yn1 <- with_labels(c(1, 0, na("d"), 1, -127, NA, 100, 0), c(No = 0, Yes = 1, na(c("Don't know" = "d"))))
    attr(yn1, "label_set") <- "yn"
    attr(yn1, "storage") <- "byte"
    yn2 <- with_labels(c(0L, 1L, 1L, NA, 0L, 1L, 0L, 1L), c(No = 0L, Yes = 1L))
    attr(yn2, "label_set") <- "yn_int"
    attr(yn2, "storage") <- "byte"
    int16 <- c(-32767, 32740, na("e"), 0, NA, 1, 2, 3)
    attr(int16, "storage") <- "int"
    long <- c(2147483620, -2147483647, na("b"), 0, NA, 7, 8, 9)
    attr(long, "storage") <- "long"
    attr(long, "label") <- "A long holding a letter"
    long_plain <- c(2147483620L, -2147483647L, NA, 0L, 5L, 6L, 7L, 8L)
    attr(long_plain, "label") <- "A long without letters"
    fl <- c(0.5, na("c"), 3.25, NA, -1, 2, 2^100, -0.125)
    attr(fl, "storage") <- "float"
    # Two codes sharing a text.
    dup <- with_labels(c(1, 2, 3, 1, 5, NA, 2, 3), c(Yes = 1, No = 2, Yes = 3))
    day <- as.Date(c("2024-03-01", NA, "1960-01-01", "1900-02-28", "2100-12-31", "1970-01-01", "0001-01-01", "9999-12-31"))
    attr(day, "format") <- "%tdCCYY-NN-DD"
    day_letters <- day
    day_letters[c(2, 5)] <- c(na("d"), na("z"))
    out <- tibble::tibble(
      id = seq_len(n), score = score, yn1 = yn1, yn2 = yn2, int16 = int16, long = long,
      long_plain = long_plain, fl = fl, dup = dup,
      flag = c(TRUE, FALSE, NA, TRUE, TRUE, FALSE, NA, FALSE),
      word = c("a", NA, "", "\u00e9t\u00e9", "x y", "z", "\u4e2d\u6587", strrep("long ", 40)),
      region = factor(c("N", "S", NA, "N", "E", "S", "N", "N"), levels = c("S", "N", "E", "W")),
      grade = factor(c("low", "high", "mid", NA, "low", "low", "high", "mid"), levels = c("low", "mid", "high"),
                     ordered = TRUE),
      day = day,
      day_letters = day_letters,
      dayfrac = as.Date(c(19000.5, 0, NA, -1.25, 1, 2, 3, 4)),
      when = as.POSIXct(c(0, 1709285400.25, NA, -1, 86400, 1e9, 2e9, -2e9), tz = "America/New_York"),
      when_utc = as.POSIXct(c(1.0000001, 2, NA, 3.5, -0.0000001, 6, 7, 8), tz = "UTC"),
      when_letters = as.POSIXct(c(0, na("k"), NA, 1.5, 2, 3, 4, 5), tz = "Europe/Paris"),
      big = bit64::as.integer64(c("9007199254740992", "-9007199254740992", NA, "0", "1", "2", "3", "4")),
      blob = list(as.raw(c(0, 1, 255)), NULL, raw(0), as.raw(7), as.raw(1:10), NULL, as.raw(0), as.raw(2))
    )
    attr(out, "label") <- "Legacy types from R"
    attr(out, "notes") <- c("A note from R.", "A second note, \u00e9t\u00e9.")
    attr(out, "characteristics") <- data.frame(variable = c("_dta", "score"), name = c("origin", "note1"),
                                               value = c("make.R", "The score's note."))
    attr(out, "sort_order") <- "id"
    out
  }

  # Several row groups: 1,200 rows, labels with letters, text with few
  # and many distinct values, a factor and a timestamp.
  rows <- function() {
    n <- 1200L
    i <- seq_len(n)
    letter <- function(k) na(letters[(k %% 26) + 1])
    lab <- ifelse(i %% 4 == 1, NA_real_, (i %% 3))
    lab[i %% 4 == 2] <- vapply(i[i %% 4 == 2], letter, 0)
    lab <- with_labels(lab, c(None = 0, Some = 1, Many = 2, na(c(Refused = "a", Skipped = "m"))), label = "Labelled")
    attr(lab, "storage") <- "byte"
    tibble::tibble(
      i = i,
      lab = lab,
      x = ifelse(i %% 11 == 0, NA, i * 1.25 - 7),
      few = ifelse(i %% 29 == 0, NA, c("alpha", "b\u00e9ta", "", "gamma")[(i %% 4) + 1]),
      many = paste("value", i),
      cat = factor(c("low", "mid", "high")[(i %% 3) + 1], levels = c("low", "mid", "high", "unused")),
      when = as.POSIXct(1.7e9 + i * 0.001, tz = "Asia/Kolkata")
    )
  }

  write <- function(df, name, ..., source = name) {
    save_parquet(df, file.path(dir, paste0(name, ".parquet")), ...)
    saveRDS(df, file.path(dir, paste0(source, ".rds")), version = 3, compress = "xz")
    cat("R wrote", name, "\n")
  }
  t <- types()
  write(t, "r_types")
  write(t, "r_types_no_letters", missing_letters = FALSE, source = "r_types")
  # A table with no rows: no row groups, so levels and labels come from
  # the profile alone.
  write(t[0, ], "r_empty")
  # Values the reader refuses by default: 64-bit integers a double does
  # not hold exactly.
  write(tibble::tibble(big = bit64::as.integer64(c("9007199254740993", "-9223372036854775807", NA, "1"))), "r_edges")
  r <- rows()
  write(r, "r_rows_zstd", source = "r_rows", compression = "zstd", row_group_size = 300)
  write(r, "r_rows_gzip", source = "r_rows", compression = "gzip", row_group_size = 500)
  write(r, "r_rows_lz4_raw", source = "r_rows", compression = "lz4_raw", row_group_size = 500)
  write(r, "r_rows_none", source = "r_rows", compression = "none", row_group_size = 500)
  quit(status = 0)
}

# ------------------------------------------------------------- R reads

source(file.path(dir, "readings.R"))
for (f in sort(Sys.glob(file.path(dir, "*.parquet")))) {
  name <- sub("\\.parquet$", "", basename(f))
  saveRDS(legacy_readings(f), file.path(dir, paste0(name, ".read.rds")), version = 3, compress = "xz")
  cat("R read", name, "\n")
}
