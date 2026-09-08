args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
raw_cases <- list(empty = character(), nonmissing = c('a', ''), missing_first = NA_character_, missing_last = c('a', NA_character_))
stored_cases <- list(empty = character(), nonmissing = c('a', ''), missing_first = '', missing_last = c('a', ''))
records <- list()
for (source in 1:2) {
    values <- readRDS(args[[source]])
    stopifnot(length(values) == 8L)
    for (i in seq_along(values)) {
        x <- values[[i]]
        stopifnot(x$case %in% names(raw_cases), x$container %in% c('ordinary','table_column'))
        ordinary <- x$container == 'ordinary'
        expected <- if (ordinary) raw_cases[[x$case]] else stored_cases[[x$case]]
        missing <- anyNA(expected)
        visits <- if (missing) match(NA_character_, expected) else length(expected)
        attributes <- if (ordinary) NULL else list(stata.string.storage = if (x$case %in% c('missing_first','missing_last')) 'str1' else 'str12')
        stopifnot(identical(x$original, raw_cases[[x$case]]), is.null(x$original_attributes),
                  identical(x$actual, expected), identical(x$attributes, attributes), !x$is_object,
                  identical(x$declaration, structure(raw_cases[[x$case]], stata.string.storage='str12')),
                  identical(x$declaration_attributes, list(stata.string.storage='str12')),
                  identical(x$actual_any_na, missing), identical(x$native_elt, missing), identical(x$native_pointer, missing),
                  identical(x$native_visits, as.double(visits)),
                  identical(x$original_identical_predicate, identical(expected, raw_cases[[x$case]])))
        records[[length(records)+1L]] <- data.frame(source=source, case=x$case, container=x$container,
            actual_any_na=x$actual_any_na, native_visits=x$native_visits, original_predicate=x$original_identical_predicate,
            storage=if(ordinary) NA_character_ else attributes$stata.string.storage)
    }
}
stopifnot(identical(readRDS(args[[1L]]), readRDS(args[[2L]])))
write.csv(do.call(rbind, records), args[[3L]], row.names=FALSE)
cat('PASS 16 saved fixture observations; both sources identical; no constructor or native calls executed\n')
