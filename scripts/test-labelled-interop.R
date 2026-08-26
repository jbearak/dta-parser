fail <- function(...) stop(..., call. = FALSE)
assert <- function(condition, message) {
    if (!isTRUE(condition)) fail(message)
}

required <- c("callr", "dplyr", "haven", "labelled", "vctrs", "dtaparser")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0L) {
    fail("Missing interoperability dependencies: ", paste(missing, collapse = ", "))
}

tested_versions <- c(labelled = "2.16.0", haven = "2.5.5")
actual_versions <- vapply(names(tested_versions), function(package) {
    as.character(utils::packageVersion(package))
}, character(1))
if (!identical(actual_versions, tested_versions)) {
    fail(
        "Review the version-specific labelled comparison before updating its ",
        "baseline. Tested: ",
        paste(names(tested_versions), tested_versions, sep = " ", collapse = ", "),
        "; installed: ",
        paste(names(actual_versions), actual_versions, sep = " ", collapse = ", ")
    )
}

attach_result <- function(order) {
    callr::r(
        function(order) {
            warnings <- character()
            withCallingHandlers(
                {
                    suppressPackageStartupMessages(library(order[[1L]],
                                                           character.only = TRUE))
                    suppressPackageStartupMessages(library(order[[2L]],
                                                           character.only = TRUE))
                },
                warning = function(condition) {
                    warnings <<- c(warnings, conditionMessage(condition))
                    invokeRestart("muffleWarning")
                }
            )

            shared <- c(
                "var_label", "var_label<-", "val_labels", "val_labels<-",
                "set_variable_labels", "set_value_labels"
            )
            owner <- vapply(shared, function(name) {
                resolved <- get(name, mode = "function")
                if (identical(resolved, getExportedValue("dtaparser", name))) {
                    "dtaparser"
                } else if (identical(
                    resolved, getExportedValue("labelled", name)
                )) {
                    "labelled"
                } else {
                    "other"
                }
            }, character(1))

            list(owner = owner, warnings = warnings)
        },
        args = list(order = order),
        spinner = FALSE
    )
}

labelled_first <- attach_result(c("labelled", "dtaparser"))
assert(
    identical(unname(labelled_first$owner), rep("dtaparser", 6L)),
    "dtaparser helpers did not take precedence when dtaparser attached last"
)
assert(
    !any(grepl("attached after dtaparser", labelled_first$warnings,
               fixed = TRUE)),
    "The masking warning fired for the safe attach order"
)

dtaparser_first <- attach_result(c("dtaparser", "labelled"))
assert(
    identical(unname(dtaparser_first$owner), rep("labelled", 6L)),
    "Normal R masking did not apply when labelled attached last"
)
masking_warnings <- grepl(
    "attached after dtaparser", dtaparser_first$warnings, fixed = TRUE
)
assert(
    sum(masking_warnings) == 1L,
    "Attaching labelled after dtaparser must emit one scoped masking warning"
)

interop <- callr::r(
    function() {
        suppressPackageStartupMessages(library(dtaparser))
        withCallingHandlers(
            suppressPackageStartupMessages(library(labelled)),
            warning = function(condition) invokeRestart("muffleWarning")
        )

        path <- system.file(
            "extdata", "value_labels_v118.dta",
            package = "dtaparser", mustWork = TRUE
        )
        source <- dtaparser::read_dta(path)$foreign
        ours <- dtaparser::set_value_labels(
            source, Domestic = 0, Imported = 1
        )
        recoded <- dplyr::recode(ours, `0` = 10)

        labelled_result <- source
        labelled::val_labels(labelled_result) <- c(
            Domestic = 0, Imported = 1
        )
        labelled_variable_result <- source
        labelled::var_label(labelled_variable_result) <- "Vehicle origin"
        labelled_custom_result <- structure(c(0, 1), provenance = "imported")
        labelled::val_labels(labelled_custom_result) <- c(
            Domestic = 0, Imported = 1
        )
        date_result <- as.Date(c("1970-01-01", "1970-01-02"))
        labelled::val_labels(date_result) <- c(Epoch = 0)

        list(
            ours_is_altrep = dtaparser:::.is_altrep(ours),
            ours_format = attr(ours, "format.stata", exact = TRUE),
            labelled_reads_ours = labelled::val_labels(ours),
            labelled_reads_variable = labelled::var_label(ours),
            factor_values = as.character(haven::as_factor(ours)),
            recode_labels = dtaparser::val_labels(recoded),
            recode_format = attr(recoded, "format.stata", exact = TRUE),
            labelled_is_altrep = dtaparser:::.is_altrep(labelled_result),
            labelled_format = attr(labelled_result, "format.stata", exact = TRUE),
            labelled_variable_is_altrep = dtaparser:::.is_altrep(
                labelled_variable_result
            ),
            labelled_custom = attr(
                labelled_custom_result, "provenance", exact = TRUE
            ),
            labelled_date_class = class(date_result),
            qualified_owner = identical(
                dtaparser::var_label,
                getExportedValue("dtaparser", "var_label")
            )
        )
    },
    spinner = FALSE
)

assert(interop$ours_is_altrep, "dtaparser value-label mutation materialized ALTREP")
assert(identical(interop$ours_format, "%8.0g"), "dtaparser dropped format.stata")
assert(
    identical(interop$labelled_reads_ours, c(Domestic = 0, Imported = 1)),
    "labelled could not read dtaparser value-label metadata"
)
assert(
    identical(interop$labelled_reads_variable, "Car origin"),
    "labelled could not read dtaparser variable-label metadata"
)
assert(
    identical(interop$factor_values, rep(c("Imported", "Domestic"), 5L)),
    "haven::as_factor() did not understand dtaparser metadata"
)
assert(
    identical(interop$recode_labels, c(Domestic = 0, Imported = 1)) &&
        identical(interop$recode_format, "%8.0g"),
    "Loading labelled displaced dtaparser's metadata-preserving recode method"
)
assert(
    !interop$labelled_is_altrep && is.null(interop$labelled_format),
    "The labelled 2.16.0 materialization/metadata-loss comparison changed"
)
assert(
    !interop$labelled_variable_is_altrep,
    "The labelled 2.16.0 variable-label materialization comparison changed"
)
assert(
    is.null(interop$labelled_custom),
    "The labelled 2.16.0 custom-attribute comparison changed"
)
assert(
    identical(
        interop$labelled_date_class,
        c("haven_labelled", "vctrs_vctr", "double")
    ),
    "The labelled 2.16.0 temporal-class comparison changed"
)
assert(interop$qualified_owner, "Qualified dtaparser helpers were displaced")

message(
    "labelled interoperability passed for labelled ", actual_versions[["labelled"]],
    " and haven ", actual_versions[["haven"]]
)
