args <- commandArgs(TRUE)
stopifnot(length(args)==3L)
expected_counts <- c(empty=0L,nonmissing=2L,all_missing=0L,mixed=3L)
rows <- list()
for (source in 1:2) {
    records <- readRDS(args[[source]])
    stopifnot(length(records)==24L)
    keys <- character()
    for (x in records) {
        stopifnot(x$kind %in% c('logical','factor','ordered'), x$case %in% names(expected_counts),
                  x$container %in% c('ordinary','table_column'), identical(x$expected, unname(expected_counts[[x$case]])),
                  identical(x$type, if(x$kind=='logical') 'logical' else 'integer'))
        expected_attributes <- if(x$kind=='logical') list(label='Tiny count control') else
            list(levels=c('a','b','unused'), class=if(x$kind=='factor') 'factor' else c('ordered','factor'), label='Tiny count control')
        stopifnot(identical(x$attributes,expected_attributes))
        keys <- c(keys,paste(x$kind,x$case,x$container))
        rows[[length(rows)+1L]] <- data.frame(source=source,kind=x$kind,case=x$case,container=x$container,expected=x$expected,type=x$type)
    }
    stopifnot(length(unique(keys))==24L)
}
stopifnot(identical(readRDS(args[[1L]]),readRDS(args[[2L]])))
write.csv(do.call(rbind,rows),args[[3L]],row.names=FALSE)
cat('PASS 48 saved tiny count records; types, counts and attributes identical across sources; no native calls\n')
