# The fixtures live in the dta-parser repository (compat/fixtures), not in
# the package; tests that need them skip when the package is tested
# outside a checkout.
fixture_dir <- normalizePath(file.path(testthat::test_path(), "..", "..", "..", "..", "compat", "fixtures"),
                             mustWork = FALSE)

fixtures <- function() {
  testthat::skip_if_not(dir.exists(fixture_dir), "compat/fixtures is not here")
  Sys.glob(file.path(fixture_dir, "*.dta"))
}

# A column for write_fixture(): values (doubles may hold haven's tagged
# NAs for .a to .z), storage type, display format and value labels.
col <- function(x, storage, format = "%9.0g", labels = NULL) {
  list(x = x, storage = storage, format = format, labels = labels)
}

# Write a release-118 file through dtaparser's own writer (the one
# dtatools' save_dta uses), for the storage types and formats haven's
# writer cannot make. Each labelled column gets a label set of its name.
write_fixture <- function(...) {
  cols <- list(...)
  path <- tempfile(fileext = ".dta")
  labelled <- names(cols)[vapply(cols, function(c) !is.null(c$labels), TRUE)]
  spec <- list(
    columns = unname(lapply(cols, `[[`, "x")),
    names = names(cols),
    storage = unname(vapply(cols, `[[`, "", "storage")),
    formats = unname(vapply(cols, `[[`, "", "format")),
    labels = rep("", length(cols)),
    label_sets = ifelse(names(cols) %in% labelled, names(cols), ""),
    sets = unname(lapply(labelled, function(n) {
      labels <- cols[[n]]$labels
      list(name = n, codes = as.double(unname(labels)), texts = names(labels))
    })),
    data_label = "",
    timestamp = "01 Jan 2026 00:00",
    notes = character(),
    characteristics = list(character(), character(), character()),
    sort_order = integer()
  )
  .Call(dtaparser:::C_dta_write, path, spec)
  path
}

# -2: not a packed column; -1: packed once, now made; else the number of
# cache slots made so far.
state <- function(x) .Call(dtaparser:::C_dta_packed_state, x)[[1]]

# Run R code in a fresh R process with this session's library paths;
# returns its output lines.
fresh_r <- function(code) {
  rscript <- file.path(R.home("bin"), "Rscript")
  libs <- paste0("R_LIBS=", paste(.libPaths(), collapse = .Platform$path.sep))
  out <- suppressWarnings(system2(rscript, c("-e", shQuote(code)), stdout = TRUE, stderr = TRUE, env = libs))
  out[!grepl("^OMP:", out)]
}
