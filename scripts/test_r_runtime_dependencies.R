# Pure key/version/planning checks. No package installation, network or builds.
source("scripts/install-r-runtime-dependencies.R")
expect_error <- function(code, pattern) {
    error <- tryCatch({ force(code); NULL }, error = identity)
    stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}
description <- list(Depends = "R (>= 4.0.0)", Imports = "rlang (>= 1.2.0), stats, tibble (>= 3.3.1)",
                    Version = "0.11.2", Suggests = "arrow, dplyr, testthat")
requirements <- .runtime_parse(description)
stopifnot(identical(vapply(requirements, `[[`, character(1), "name"), c("R", "rlang", "stats", "tibble")))
abi_identity <- list(image = "ubuntu24", image_version = "20261004", arch = "X64", r = "4.6.1",
                     platform = "x86_64-pc-linux-gnu", rust = "1.98.0", cc = "gcc")
key <- .runtime_key(requirements, abi_identity)
changed <- description
changed$Version <- "99.99.99"
changed$Suggests <- "doesnotexist (>= 999.0)"
changed$Imports <- "tibble( >= 3.3.1 ), stats, rlang (>= 1.2.0)"
stopifnot(identical(key, .runtime_key(.runtime_parse(changed), abi_identity)))
for (field in names(abi_identity)) {
    changed_identity <- abi_identity
    changed_identity[[field]] <- paste0(changed_identity[[field]], "-changed")
    stopifnot(!identical(key, .runtime_key(requirements, changed_identity)))
}
changed$Imports <- "rlang (>= 1.2.1), stats, tibble (>= 3.3.1)"
stopifnot(!identical(key, .runtime_key(.runtime_parse(changed), abi_identity)))
installed <- matrix(c("1.1.0", "4.6.1"), ncol = 1L, dimnames = list(c("rlang", "stats"), "Version"))
stopifnot(identical(.runtime_missing(requirements, installed), c("rlang", "tibble")))
minimum <- list(name = "rlang", operator = ">=", version = "1.2.0")
stopifnot(!.runtime_satisfies("1.1.99", minimum), .runtime_satisfies("1.2.0", minimum),
          .runtime_satisfies("1.3.0", minimum))
expect_error(.runtime_parse(list(Imports = "rlang (oops)")), "Unsupported")
expect_error(.runtime_parse(list(Imports = "dtatools")), "Cannot cache")
temporary <- tempfile("r-runtime-test-")
dir.create(temporary)
package <- file.path(temporary, "package")
dir.create(package)
library <- file.path(temporary, "library")
dir.create(library)
writeLines(c("Package: fixture", "Version: 1.0.0", "Imports: utils (>= 1.0.0)",
             "Suggests: doesnotexist (>= 999.0)"), file.path(package, "DESCRIPTION"))
previous_output <- Sys.getenv("GITHUB_OUTPUT", unset = NA_character_)
output <- file.path(temporary, "github-output")
Sys.setenv(GITHUB_OUTPUT = output)
.runtime_main(c("check", package, library))
stopifnot(identical(readLines(output), "cache_populated=false"))
if (is.na(previous_output)) Sys.unsetenv("GITHUB_OUTPUT") else Sys.setenv(GITHUB_OUTPUT = previous_output)
writeLines(c("Package: fixture", "Version: 1.0.0", "Imports: utils (>= 999.0)"), file.path(package, "DESCRIPTION"))
expect_error(.runtime_main(c("check", package, library)), "Missing/outdated")
dir.create(file.path(library, "dtatools"))
expect_error(.runtime_main(c("check", package, library)), "must not contain dtatools")
unlink(temporary, recursive = TRUE)
cat("R dependency key, minimum-version and no-install checks: PASS\n")
