script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument), winslash = "/"))
source(file.path(script_dir, "common.R"), local = TRUE)

root <- tempfile("r-corpus-roundtrip-")
dir.create(root)
on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
for (corpus in roundtrip_corpora) dir.create(file.path(root, corpus))

fixture <- normalizePath(
    file.path(script_dir, "..", "..", "r-package", "dtaparser", "inst",
              "extdata", "all_types_v118.dta"),
    winslash = "/", mustWork = TRUE
)
stopifnot(file.copy(fixture, file.path(root, "DHS", "ordinary.DTA")))
writeBin(raw(), file.path(root, "MICS", "empty.dta"))
stopifnot(file.symlink(
    file.path(root, "DHS", "ordinary.DTA"),
    file.path(root, "NSFG", "ignored.dta")
))

inventory <- roundtrip_inventory(root, progress = FALSE)
stopifnot(
    nrow(inventory) == 2L,
    identical(sort(inventory$corpus), c("DHS", "MICS")),
    identical(inventory$release[inventory$corpus == "DHS"], 118L),
    is.na(inventory$release[inventory$corpus == "MICS"]),
    any(inventory$sha256 == unname(tools::sha256sum(fixture))),
    !anyDuplicated(inventory$id)
)
empty <- inventory[inventory$corpus == "MICS", , drop = FALSE]
stopifnot(identical(roundtrip_exclusion_reason(empty), "empty-source"))

manifest <- file.path(root, "manifest.tsv")
write.table(inventory[c("corpus", "id", "sha256")], manifest, sep = "\t",
            row.names = FALSE, quote = TRUE)
stopifnot(grepl("^[0-9a-f]{64}$", roundtrip_manifest_hash(manifest)))

rows <- file.path(root, "rows.tsv")
roundtrip_append_tsv(data.frame(id = "one", status = "pass"), rows)
roundtrip_append_tsv(data.frame(id = "two", status = "pass"), rows)
stopifnot(identical(read.delim(rows)$id, c("one", "two")))

darwin_memory <- paste("12345", "maximum resident set size", sep = "  ")
if (identical(Sys.info()[["sysname"]], "Darwin")) {
    stopifnot(identical(roundtrip_parse_memory(darwin_memory), 12345))
}
unlink(root, recursive = TRUE, force = TRUE)
cat("R corpus round-trip framework: PASS\n")
