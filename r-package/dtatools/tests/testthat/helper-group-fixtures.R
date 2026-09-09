# Fixtures are produced by real dplyr in scripts/prepare-dplyr-group-fixtures.R.
# This helper must remain usable when dplyr is physically absent.
.group_fixture_value <- function(value) {
    kind <- typeof(value)
    if (kind %in% c("environment", "externalptr", "closure", "promise")) {
        stop("A group fixture specification must contain plain values.")
    }
    attrs <- attributes(value)
    if (is.data.frame(value)) attrs$row.names <- .row_names_info(value, 0L)
    attributes_spec <- if (is.null(attrs)) NULL else
        lapply(attrs, .group_fixture_value)
    payload <- switch(kind,
        double = writeBin(as.double(value), raw(), size = 8L, endian = "little"),
        integer = as.integer(value),
        logical = as.logical(value),
        character = list(value = as.character(value), encoding = Encoding(value),
            bytes = lapply(as.character(value), function(x) if (is.na(x)) NULL else charToRaw(x))),
        raw = as.raw(value),
        list = lapply(seq_along(value), function(i) .group_fixture_value(.subset2(value, i))),
        "NULL" = NULL,
        stop("Unsupported group fixture specification type: ", kind)
    )
    list(type = kind, attributes = attributes_spec, value = payload)
}

.group_fixture_spec <- function(data) {
    if (!is.data.frame(data) || inherits(data, "dtatools_ref_data")) {
        stop("Make the plain fixture specification before constructing reference data.")
    }
    .group_fixture_value(data)
}

.group_fixture_registry <- function() {
    path <- testthat::test_path("fixtures", "dplyr-groups.rds")
    if (!file.exists(path)) stop("Missing committed dplyr group fixture registry.")
    registry <- readRDS(path)
    if (!identical(registry$schema, 1L) || !is.list(registry$cases) ||
        is.null(names(registry$cases)) || anyDuplicated(names(registry$cases))) {
        stop("Invalid dplyr group fixture registry.")
    }
    registry
}

.group_fixture <- function(id) {
    stopifnot(is.character(id), length(id) == 1L, !is.na(id))
    registry <- .group_fixture_registry()
    if (!id %in% names(registry$cases)) stop("Unknown group fixture: ", id)
    entry <- registry$cases[[id]]
    if (!identical(entry$id, id) || !is.data.frame(entry$data) ||
        inherits(entry$data, "dtatools_ref_data") ||
        !inherits(entry$data, c("grouped_df", "rowwise_df")) ||
        !identical(attr(entry$data, "groups", exact = TRUE), entry$groups)) {
        stop("Invalid recorded grouped input: ", id)
    }
    entry
}

.group_fixture_attach <- function(id, data, plain_spec, groups = NULL) {
    # The caller derives plain_spec from the actual safe input before capture,
    # then constructs fresh owned/callback columns from that input. Never read
    # the fresh payload here: doing so could expose storage or consume callbacks.
    entry <- .group_fixture(id)
    if (!identical(plain_spec, entry$plain_spec)) {
        stop("Fresh input does not match the recorded plain fixture: ", id)
    }
    if (!is.data.frame(data) || inherits(data, "dtatools_ref_data") ||
        !identical(names(data), entry$shape$names) ||
        !identical(.row_names_info(data, 2L), entry$shape$rows)) {
        stop("Fresh frame does not match the recorded fixture shape: ", id)
    }
    for (i in seq_along(data)) {
        value <- .subset2(data, i)
        shape <- entry$shape$columns[[i]]
        if (!identical(typeof(value), shape$type) ||
            !identical(attributes(value), shape$attributes)) {
            stop("Fresh column structure differs from the recorded fixture: ", id)
        }
    }
    if (is.null(groups)) groups <- entry$groups else {
        if (!is.data.frame(groups) || !identical(names(groups), names(entry$groups)) ||
            !identical(.row_names_info(groups, 2L), .row_names_info(entry$groups, 2L)) ||
            !identical(class(groups), class(entry$groups)) ||
            !identical(attr(groups, ".drop", exact = TRUE),
                       attr(entry$groups, ".drop", exact = TRUE)) ||
            !identical(.subset2(groups, ".rows"), .subset2(entry$groups, ".rows"))) {
            stop("Fresh groups differ from the recorded fixture shape: ", id)
        }
        for (key in setdiff(names(groups), ".rows")) {
            if (!identical(typeof(.subset2(groups, key)), typeof(.subset2(entry$groups, key))) ||
                !identical(attributes(.subset2(groups, key)),
                           attributes(.subset2(entry$groups, key)))) {
                stop("Fresh grouping key structure differs from the recorded fixture: ", id)
            }
        }
    }
    attr(data, "groups") <- groups
    class(data) <- class(entry$data)
    data
}
