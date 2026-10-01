# Stata labels generated indicators with the displayed value label, or its
# fixed-width %11.4f numeric fallback. System missing sits at the decimal
# point; tagged missing codes are right-aligned in the full field.
.tab_indicator_label <- function(value, variable_name, display_label = NULL) {
    text <- if (!is.null(display_label)) {
        display_label
    } else if (is.character(value)) {
        if (is.na(value)) "" else value
    } else if (is.na(value)) {
        code <- .tab_missing_codes(as.double(value))
        if (identical(code, 0L)) paste0(strrep(" ", 6L), ".") else
            .tab_pad(.tab_missing_name(code), 11L)
    } else {
        value <- as.double(value)
        fixed <- sprintf("%11.4f", value)
        if (nchar(fixed, type = "width") <= 11L) fixed else
            .tab_pad(.summarize_exponential(value, 4L, width = 11L), 11L)
    }
    substr(paste0(variable_name, "==", text), 1L, 80L)
}
