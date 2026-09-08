# Stage 6 row-operation regression coverage; adapted sources are in inst/NOTICE.
.s6_ids <- function(data) as.integer(data$id)
.s6_context <- function() {
    keys <- dplyr::cur_group()
    list(n = dplyr::n(), id = dplyr::cur_group_id(),
         rows = dplyr::cur_group_rows(), keys = names(keys),
         g = if ("g" %in% names(keys)) as.character(keys$g) else character())
}
.s6_plain <- function(data) {
    attr(data, ".dtatools_ref_state") <- NULL
    class(data) <- dtatools:::.reference_base_classes(class(data))
    data
}
