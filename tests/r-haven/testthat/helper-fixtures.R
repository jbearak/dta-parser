root <- Sys.getenv("DTA_PARSER_ROOT", unset = NA_character_)
if (is.na(root)) {
    stop("DTA_PARSER_ROOT must identify the repository checkout", call. = FALSE)
}
source(file.path(
    root, "r-package", "dtaparser", "tests", "testthat", "helper-fixtures.R"
))

load_test_helpers <- function(file, names) {
    expressions <- parse(file.path(
        root, "r-package", "dtaparser", "tests", "testthat", file
    ))
    for (expression in expressions) {
        if (is.call(expression) && identical(expression[[1L]], quote(`<-`)) &&
            as.character(expression[[2L]]) %in% names) {
            eval(expression, envir = parent.frame())
        }
    }
}

load_test_helpers(
    "test-input-sources.R",
    c(
        "input_fixture", "read_fixture_bytes", "expect_source_parity",
        "write_compressed_fixture", "start_fixture_server"
    )
)
load_test_helpers("test-read-dta.R", "replace_first_byte")
load_test_helpers("test-stata-numeric.R", "fixture_with_temporal_storage")
rm(load_test_helpers)
