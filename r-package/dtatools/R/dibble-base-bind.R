# Ordinary base construction is package-owned;
# explicitly selected foreign S3 methods retain their public generic context.
.dibble_base_bind_dispatch <- function(values, generic) {
    ordinary <- if (generic == "rbind") base::rbind.data.frame else base::cbind.data.frame
    for (value in values) {
        if (!is.object(value)) next
        for (name in class(value)) {
            method <- utils::getS3method(generic, name, optional = TRUE)
            if (!is.null(method)) return(!identical(method, ordinary))
        }
    }
    FALSE
}

.dibble_base_cbind <- function(..., deparse.level = 1) {
    .dibble_base_data_frame(..., check.names = FALSE)
}

#' @export
rbind.dtatools_ref_data <- function(..., deparse.level = 1) {
    inputs <- list(...)
    values <- lapply(inputs, .reference_snapshot)
    constructor <- if (.dibble_base_bind_dispatch(values, "rbind")) base::rbind else
        .dibble_base_rbind
    result <- do.call(constructor, c(values, list(deparse.level = deparse.level)))
    .close_dibble(inputs[[1L]], result)
}

#' @export
cbind.dtatools_ref_data <- function(..., deparse.level = 1) {
    inputs <- list(...)
    values <- lapply(inputs, .reference_snapshot)
    constructor <- if (.dibble_base_bind_dispatch(values, "cbind")) base::cbind else
        .dibble_base_cbind
    result <- do.call(constructor, c(values, list(deparse.level = deparse.level)))
    .close_dibble(inputs[[1L]], result)
}
