if (!requireNamespace("haven", quietly = TRUE)) stop("haven is required")

file_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(file_argument)) {
    sub("^--file=", "", file_argument[[1]])
} else {
    "benchmarks/dta-vs-haven/r-package-reproducibility.R"
}
root <- normalizePath(file.path(dirname(script_path), "../.."))
package_dir <- file.path(root, "r-package", "dtaparser")
library_dir <- tempfile("dtaparser-library-")
dir.create(library_dir)
on.exit(unlink(library_dir, recursive = TRUE), add = TRUE)

install_output <- system2(
    file.path(R.home("bin"), "R"),
    c("CMD", "INSTALL", "--no-multiarch", "-l", shQuote(library_dir),
      shQuote(package_dir)),
    stdout = TRUE, stderr = TRUE
)
if (!is.null(attr(install_output, "status")) &&
    attr(install_output, "status") != 0) {
    stop(paste(install_output, collapse = "\n"))
}
.libPaths(c(library_dir, .libPaths()))

normalize_attribute <- function(value) {
    if (is.null(value)) "" else value
}

haven_missing_tags <- function(column) {
    vapply(seq_along(column), function(index) {
        value <- column[[index]]
        if (!is.na(value)) return(NA_character_)
        tag <- haven::na_tag(value)
        if (is.na(tag)) "." else paste0(".", tag)
    }, character(1))
}

compare_file <- function(path) {
    actual <- dtaparser::read_dta(path)
    expected <- haven::read_dta(path)
    stopifnot(
        identical(dim(actual), dim(expected)),
        identical(names(actual), names(expected)),
        identical(
            normalize_attribute(attr(actual, "label", exact = TRUE)),
            normalize_attribute(attr(expected, "label", exact = TRUE))
        )
    )
    for (name in names(actual)) {
        left <- actual[[name]]
        right <- expected[[name]]
        stopifnot(
            identical(
                normalize_attribute(attr(left, "label", exact = TRUE)),
                normalize_attribute(attr(right, "label", exact = TRUE))
            ),
            identical(
                normalize_attribute(attr(left, "format.stata", exact = TRUE)),
                normalize_attribute(attr(right, "format.stata", exact = TRUE))
            )
        )
        if (is.character(right)) {
            stopifnot(identical(as.character(left), as.character(right)))
        } else {
            left_values <- as.numeric(left)
            right_values <- as.numeric(right)
            observed <- !is.na(right_values)
            scale <- pmax(1, abs(left_values[observed]), abs(right_values[observed]))
            stopifnot(all(
                abs(left_values[observed] - right_values[observed]) <= 1e-7 * scale
            ))
            stopifnot(identical(
                dtaparser::dta_missing_tags(left),
                haven_missing_tags(right)
            ))
        }
        left_labels <- attr(left, "labels", exact = TRUE)
        right_labels <- attr(right, "labels", exact = TRUE)
        if (is.null(left_labels) || is.null(right_labels)) {
            stopifnot(is.null(left_labels), is.null(right_labels))
        } else {
            stopifnot(
                identical(names(left_labels), names(right_labels)),
                isTRUE(all.equal(
                    as.numeric(left_labels), as.numeric(right_labels),
                    tolerance = 1e-7, check.attributes = FALSE
                ))
            )
        }
    }
}

fixtures <- sort(list.files(
    file.path(root, "tests", "fixtures", "dta"),
    pattern = "[.]dta$", full.names = TRUE
))
for (fixture in fixtures) compare_file(fixture)
cat(sprintf(
    "R package correctness: PASS — %d files match haven (tolerance 1e-7).\n",
    length(fixtures)
))
