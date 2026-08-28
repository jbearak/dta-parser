source_roots <- c("src/dta-tools/src", "src/rust/src")
if (any(!dir.exists(source_roots))) {
  stop("Rust source hash input is missing")
}

fixed_paths <- c(
  "src/dta-tools/Cargo.toml",
  "src/rust/Cargo.toml",
  "src/rust/Cargo.lock",
  "src/rust/cargo-config.toml",
  "src/rust/vendor.tar.gz",
  "configure",
  "configure.win",
  "src/Makevars.in",
  "src/Makevars.rust",
  "src/Makevars.win.in",
  "tools/configure-rust.sh",
  "tools/rust-source-hash.R"
)
build_scripts <- c("src/dta-tools/build.rs", "src/rust/build.rs")
existing_build_scripts <- build_scripts[file.exists(build_scripts)]
fixed_inputs <- c(fixed_paths, existing_build_scripts)
if (identical(Sys.getenv("DTA_RUST_HASH_LIST_INPUTS"), "1")) {
  is_directory <- file.info(fixed_inputs)$isdir
  if (anyNA(is_directory) || any(is_directory)) {
    stop("Rust source hash input is missing")
  }
  cat(c(source_roots, fixed_inputs), sep = "\n")
  quit(save = "no")
}

source_files <- unlist(lapply(source_roots, function(root) {
  list.files(
    root,
    recursive = TRUE,
    full.names = TRUE,
    all.files = TRUE,
    include.dirs = FALSE
  )
}), use.names = FALSE)
paths <- sort(c(fixed_inputs, source_files))
is_directory <- file.info(paths)$isdir
if (anyNA(is_directory) || any(is_directory)) {
  stop("Rust source hash input is missing")
}

hashes <- unname(tools::md5sum(paths))
if (anyNA(hashes)) {
  stop("Could not hash every Rust source input")
}
rustc_version <- system2("rustc", "-vV", stdout = TRUE, stderr = TRUE)
cargo_version <- system2("cargo", "-vV", stdout = TRUE, stderr = TRUE)
if (
  !is.null(attr(rustc_version, "status")) ||
    !is.null(attr(cargo_version, "status"))
) {
  stop("Could not identify the Rust toolchain")
}

payload <- tempfile()
on.exit(unlink(payload))
writeLines(
  c(paste(paths, hashes), rustc_version, cargo_version),
  payload,
  useBytes = TRUE
)
cat(unname(tools::md5sum(payload)))
