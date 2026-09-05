normalize_for_haven <- function(value) {
    attr(value, "dta_format_version") <- NULL
    if (is.data.frame(value)) {
        for (index in seq_along(value)) {
            value[[index]] <- normalize_for_haven(value[[index]])
        }
        return(value)
    }

    classes <- attr(value, "class", exact = TRUE)
    if (!is.null(classes) && any(startsWith(classes, "dta_"))) {
        attr(value, "stata.storage") <- NULL
        classes <- classes[!startsWith(classes, "dta_")]
        if (identical(classes, c("vctrs_vctr", "double"))) {
            classes <- NULL
        }
        attr(value, "class") <- classes
    }
    value
}
