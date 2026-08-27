fail <- function(...) stop(..., call. = FALSE)
assert <- function(condition, message) {
    if (!isTRUE(condition)) fail(message)
}

required <- c("haven", "dtaparser")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0L) {
    fail("Missing interoperability dependencies: ", paste(missing, collapse = ", "))
}

tested_version <- "2.5.5"
actual_version <- as.character(utils::packageVersion("haven"))
if (!identical(actual_version, tested_version)) {
    fail(
        "Review the version-specific haven helper comparison before updating ",
        "its baseline. Tested: haven ", tested_version,
        "; installed: haven ", actual_version
    )
}

ours <- dtaparser::tagged_missing(letters)
assert(
    identical(haven::na_tag(ours), letters) &&
        all(haven::is_tagged_na(ours)),
    "haven could not inspect dtaparser tagged missing values"
)

theirs <- haven::tagged_na(letters)
assert(
    identical(dtaparser::missing_tag(theirs), letters) &&
        all(dtaparser::is_tagged_missing(theirs)),
    "dtaparser could not inspect haven tagged missing values"
)

fixture <- system.file(
    "extdata", "value_labels_v118.dta",
    package = "dtaparser", mustWork = TRUE
)
compact_ours <- dtaparser::read_dta(fixture)$foreign
invisible(dtaparser::missing_tag(compact_ours))
invisible(dtaparser::is_tagged_missing(compact_ours))
assert(
    dtaparser:::.is_unmaterialized_numeric_altrep(compact_ours),
    "dtaparser tag inspection materialized compact numeric storage"
)

compact_haven_tag <- dtaparser::read_dta(fixture)$foreign
invisible(haven::na_tag(compact_haven_tag))
assert(
    !dtaparser:::.is_unmaterialized_numeric_altrep(compact_haven_tag),
    "The haven 2.5.5 na_tag() materialization comparison changed"
)

compact_haven_predicate <- dtaparser::read_dta(fixture)$foreign
invisible(haven::is_tagged_na(compact_haven_predicate))
assert(
    !dtaparser:::.is_unmaterialized_numeric_altrep(compact_haven_predicate),
    "The haven 2.5.5 is_tagged_na() materialization comparison changed"
)

assert(
    identical(dtaparser::missing_tag(dtaparser::tagged_missing("A")), "a") &&
        identical(haven::na_tag(haven::tagged_na("A")), "A"),
    "The version-specific uppercase-tag comparison changed"
)
assert(
    inherits(try(dtaparser::tagged_missing("?"), silent = TRUE), "try-error") &&
        identical(haven::na_tag(haven::tagged_na("?")), "?"),
    "The version-specific invalid-tag comparison changed"
)

noncanonical_nan <- readBin(
    as.raw(c(0x7f, 0xf8, 0x00, 0x61, 0x00, 0x00, 0x00, 0x01)),
    "double",
    n = 1L,
    size = 8L,
    endian = "big"
)
assert(
    is.na(dtaparser::missing_tag(noncanonical_nan)) &&
        !dtaparser::is_tagged_missing(noncanonical_nan) &&
        identical(haven::na_tag(noncanonical_nan), "a"),
    "The noncanonical-NaN classification comparison changed"
)

duplicate_labels <- haven::labelled(
    c(1, 2),
    c(Same = 1, Same = 2)
)
ours_factor <- dtaparser::factor_from_labels(duplicate_labels)
haven_factor <- haven::as_factor(duplicate_labels)
assert(
    identical(levels(ours_factor), c("Same [1]", "Same [2]")) &&
        identical(levels(haven_factor), "Same"),
    "The duplicate-label factor comparison changed"
)

missing_factor_input <- haven::labelled(
    c(1, haven::tagged_na("a"), haven::tagged_na("b")),
    c(One = 1, Refused = haven::tagged_na("a"))
)
ours_missing_factor <- dtaparser::factor_from_labels(
    missing_factor_input,
    missing = TRUE
)
haven_missing_factor <- haven::as_factor(missing_factor_input)
assert(
    identical(
        as.character(ours_missing_factor),
        c("One", "Refused", ".b")
    ) &&
        identical(
            as.character(haven_missing_factor),
            c("One", "Refused", NA_character_)
        ),
    "The missing-code factor comparison changed"
)

date_input <- as.Date(c("1960-01-01", "1960-01-02"))
attr(date_input, "format.stata") <- "%td"
attr(date_input, "labels") <- c(Origin = 0)
datetime_input <- as.POSIXct(
    c("1960-01-01 00:00:00", "1960-01-01 00:00:01"),
    tz = "UTC"
)
attr(datetime_input, "format.stata") <- "%tc"
attr(datetime_input, "labels") <- c(Epoch = 0)
assert(
    identical(
        as.character(dtaparser::factor_from_labels(date_input)),
        c("Origin", "1960-01-02")
    ) &&
        identical(
            as.character(dtaparser::factor_from_labels(datetime_input)),
            c("Epoch", "1960-01-01 00:00:01")
        ) &&
        inherits(try(haven::as_factor(date_input), silent = TRUE), "try-error") &&
        inherits(
            try(haven::as_factor(datetime_input), silent = TRUE),
            "try-error"
        ),
    "The temporal factor comparison changed"
)

compact_factor_ours <- dtaparser::read_dta(fixture)$foreign
compact_factor_ours_result <- dtaparser::factor_from_labels(
    compact_factor_ours
)
assert(
    dtaparser:::.is_unmaterialized_numeric_altrep(compact_factor_ours),
    "dtaparser factor conversion materialized compact numeric storage"
)

compact_factor_haven <- dtaparser::read_dta(fixture)$foreign
compact_factor_haven_result <- haven::as_factor(compact_factor_haven)
assert(
    identical(compact_factor_haven_result, compact_factor_ours_result) &&
        dtaparser:::.is_unmaterialized_numeric_altrep(compact_factor_haven),
    "The haven 2.5.5 factor output or compactness comparison changed"
)

message("haven helper interoperability passed for haven ", actual_version)
