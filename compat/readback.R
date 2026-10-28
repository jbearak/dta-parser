# Write every fixture again with dtatools (read_dta, then save_dta) into
# the directory given, for compat/readback.py to read with pandas.
#   Rscript compat/readback.R <out-dir>
out <- commandArgs(trailingOnly = TRUE)[[1]]
dir.create(out, showWarnings = FALSE, recursive = TRUE)
for (path in Sys.glob(file.path("compat", "fixtures", "*.dta"))) {
  dtatools::save_dta(dtatools::read_dta(path), file.path(out, basename(path)))
}
