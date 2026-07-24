.dtaparser_state <- new.env(parent = emptyenv())
.dtaparser_state$context <- NULL

.dtaparser_context <- function() {
    if (!is.null(.dtaparser_state$context)) {
        return(.dtaparser_state$context)
    }

    context <- V8::v8()
    javascript_dir <- system.file("js", package = "dtaparser")
    if (!nzchar(javascript_dir)) {
        stop("dtaparser JavaScript bundle is not installed", call. = FALSE)
    }
    context$source(file.path(javascript_dir, "text-decoder.js"))
    context$source(file.path(javascript_dir, "dta-parser.js"))
    context$source(file.path(javascript_dir, "adapter.js"))
    .dtaparser_state$context <- context
    context
}
