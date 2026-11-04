# Write small Parquet fixtures with arrow and nanoparquet, from data made
# here, into compat/parquet/fixtures/. See make_fixtures.py for the
# order to run the scripts in. Needs arrow and nanoparquet.

out <- file.path("compat", "parquet", "fixtures")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

n <- 600L
i <- seq_len(n) - 1L
na_every <- function(x, every) {
  x[i %% every == 3L] <- NA
  x
}

base <- as.POSIXct("2021-06-01 12:00:00", tz = "UTC")
df <- data.frame(
  int = na_every(i * 1001L - 1000000L, 10L),
  dbl = na_every(i / 9 - 100, 11L),
  flag = na_every(i %% 2L == 0L, 12L),
  word = na_every(paste("word", i %% 30L, "é"), 13L),
  day = na_every(as.Date("1990-01-01") + i * 5L, 14L),
  when = na_every(base + i * 3601, 15L),
  fac = na_every(factor(c("b", "a", "c")[i %% 3L + 1L], levels = c("c", "b", "a")), 16L),
  stringsAsFactors = FALSE
)
attr(df$when, "tzone") <- "Europe/Paris"
df$blob <- lapply(i, function(k) if (k %% 17L == 3L) NULL else as.raw(c(k %% 256L, 1L, 2L)))

arrow::write_parquet(df, file.path(out, "arrow_r_default.parquet"))
# nanoparquet has no blob type for a list of raw vectors with NULLs, so
# its fixture leaves that column out.
nanoparquet::write_parquet(df[setdiff(names(df), "blob")], file.path(out, "nanoparquet_default.parquet"))

cat(sprintf("wrote arrow_r_default.parquet (arrow %s), nanoparquet_default.parquet (nanoparquet %s)\n",
            packageVersion("arrow"), packageVersion("nanoparquet")))
