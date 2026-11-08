# Save every input again with an R package's read_dta and save_dta, for
# compat/readback/check.py to read with other readers. Inputs are the
# fixtures in compat/fixtures and compat/readback/strls.dta.
#   Rscript compat/readback/write.R <out-dir> dtaparser|dtatools
# R holds no binary strings, and dtaparser reads no binary strLs, so
# binary.dta is not saved.
args <- commandArgs(trailingOnly = TRUE)
out <- args[[1]]
pkg <- args[[2]]
stopifnot(pkg %in% c("dtaparser", "dtatools"))
read_dta <- getExportedValue(pkg, "read_dta")
save_dta <- getExportedValue(pkg, "save_dta")
dir.create(out, showWarnings = FALSE, recursive = TRUE)
inputs <- c(Sys.glob(file.path("compat", "fixtures", "*.dta")), file.path("compat", "readback", "strls.dta"))
for (path in inputs) {
  save_dta(read_dta(path), file.path(out, basename(path)))
}
