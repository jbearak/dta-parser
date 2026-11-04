# Write our Parquet input for each .dta file: read with dtaparser, write
# with datakit's defaults. bench/parquet/run.py then makes the pyarrow,
# polars and DuckDB versions from these (convert.py), so all hold the
# same data.
#   Rscript bench/parquet/convert.R OUT_DIR KEY=PATH ...
args <- commandArgs(trailingOnly = TRUE)
out <- args[[1]]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
for (a in args[-1]) {
  key <- sub("=.*$", "", a)
  path <- sub("^[^=]*=", "", a)
  dst <- file.path(out, paste0(key, ".parquet"))
  if (file.exists(dst)) next
  x <- dtaparser::read_dta(path)
  datakit::save_parquet(x, paste0(dst, ".tmp"))
  file.rename(paste0(dst, ".tmp"), dst)
  cat(key, format(file.size(dst) / 1e6, digits = 3), "MB\n")
}
