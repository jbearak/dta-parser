# Dump what haven and readstata13 read from each .dta file under <dir>
# to <file>.haven.json and <file>.readstata13.json beside it, for
# compat/readback/check.py. Run from the repository root:
#   Rscript compat/readback/dump.R <dir>
source(file.path("compat", "expected.R"))
dir <- commandArgs(trailingOnly = TRUE)[[1]]
for (path in list.files(dir, pattern = "\\.dta$", recursive = TRUE, full.names = TRUE)) {
  for (reader in c("haven", "readstata13")) {
    dump_json(path, reader, paste0(path, ".", reader, ".json"))
  }
}
