script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument)))
source(file.path(script_dir, "haven-parity.R"), local = TRUE)

plain <- structure(
    c(1, 2), label = "Identifier", format.stata = "%10.0g",
    stata.storage = "double",
    class = c("dta_numeric", "dta_double", "vctrs_vctr", "double")
)
labelled <- structure(
    c(1, 2), label = "Region", format.stata = "%12.0g",
    labels = c(North = 1, South = 2), stata.storage = "long",
    class = c(
        "dta_numeric", "dta_long", "haven_labelled", "vctrs_vctr",
        "double"
    )
)
date <- structure(
    c(1, 2), label = "Date", format.stata = "%td",
    stata.storage = "double",
    class = c("dta_temporal", "dta_date", "Date")
)
actual <- normalize_for_haven(data.frame(plain, labelled, date))
expected <- data.frame(
    plain = structure(c(1, 2), label = "Identifier", format.stata = "%10.0g"),
    labelled = structure(
        c(1, 2), label = "Region", format.stata = "%12.0g",
        labels = c(North = 1, South = 2),
        class = c("haven_labelled", "vctrs_vctr", "double")
    ),
    date = structure(
        c(1, 2), label = "Date", format.stata = "%td", class = "Date"
    )
)
stopifnot(identical(actual, expected))
