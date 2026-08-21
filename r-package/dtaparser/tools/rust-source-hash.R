source_roots <- c("src/dta-parser/src", "src/rust/src")
paths <- c(
  "src/dta-parser/Cargo.toml",
  "src/rust/Cargo.toml",
  "src/rust/Cargo.lock",
  "src/rust/cargo-config.toml",
  "src/rust/vendor.tar.gz",
  unlist(lapply(source_roots, function(root) {
    list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  }), use.names = FALSE)
)
build_scripts <- c("src/dta-parser/build.rs", "src/rust/build.rs")
paths <- sort(c(paths, build_scripts[file.exists(build_scripts)]))
paths <- paths[file.info(paths)$isdir %in% FALSE]
if (length(paths) == 0L || any(!file.exists(paths))) {
  stop("Rust source hash input is missing")
}

hashes <- unname(tools::md5sum(paths))
if (anyNA(hashes)) {
  stop("Could not hash every Rust source input")
}

payload <- tempfile()
on.exit(unlink(payload))
writeLines(paste(paths, hashes), payload, useBytes = TRUE)
cat(unname(tools::md5sum(payload)))
