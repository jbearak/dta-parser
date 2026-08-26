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

message("haven helper interoperability passed for haven ", actual_version)
