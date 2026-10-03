args <- commandArgs(TRUE)
stopifnot(length(args) %in% 3:4)
qualify <- length(args)==4L && identical(args[[4L]],'qualify')
stopifnot(length(args)==3L || qualify)
.libPaths(c(normalizePath(args[[1L]]),.libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'),'path')),
    file.path(normalizePath(args[[1L]]),'dtatools')))
round <- as.integer(args[[2L]]); stopifnot(!is.na(round),round>0L)
n <- 1000000L; threads <- 1L; options(dtatools.threads=threads)
hash_raw <- function(x) digest::digest(x,algo='sha256',serialize=FALSE)
value_hash <- function(x) hash_raw(writeBin(as.double(x),raw(),8L,endian='little'))
rank_hash <- function(x) hash_raw(writeBin(as.integer(x),raw(),4L,endian='little'))
pair_hash <- function(x,y) value_hash(c(as.double(x),as.double(y)))
metadata_hash <- function(x,y) digest::digest(list(attributes(x),attributes(y)),algo='sha256')
state <- function(x) {
    info <- .Call(dtatools:::C_dtatools_owned_numeric_info,x)
    c(compact=dtatools:::.is_unmaterialized_numeric_altrep(x),
      materialized=.Call(dtatools:::C_dtatools_is_materialized_numeric_altrep,x),
      retained=info[['owned']],chunks=info[['chunks']])
}
pair_state <- function(x,y) c(setNames(state(x),paste0('long_',names(state(x)))),
    setNames(state(y),paste0('float_',names(state(y)))))
entry <- function() .Call(dtatools:::C_dtatools_numeric_entry_stats,FALSE)[['scalar']]
operations <- list(long_float=function(x,y)x+y,float_long=function(x,y)y+x)
panels <- list(plain=c('none','sparse','random_half','prefix256','suffix256','all_tags'),
    retained=c('none','sparse','random_half','prefix256','suffix256'),short=c('none','sparse'))
layouts <- names(panels)
layout_order <- layouts[(seq_along(layouts)+(round-1L)%%3L-1L)%%3L+1L]
if(round%%2L==0L)layout_order <- rev(layout_order)
operation_order <- if(round%%2L)names(operations) else rev(names(operations))
permutations <- list(c(1L,2L,3L),c(1L,3L,2L),c(2L,1L,3L),c(2L,3L,1L),c(3L,1L,2L),c(3L,2L,1L))
rows <- list()
for(lp in seq_along(layout_order)) {
    layout <- layout_order[[lp]]; patterns <- panels[[layout]]
    pattern_order <- patterns[(seq_along(patterns)+(round-1L)%%length(patterns)-1L)%%length(patterns)+1L]
    if(round%%2L==0L)pattern_order <- rev(pattern_order)
    for(pp in seq_along(pattern_order)) {
        pattern <- pattern_order[[pp]]
        # Exact grids from the original long_float_add acceptance case.
        x_plain <- as.double((seq_len(n)*13)%%10001L-5000L)
        y_plain <- as.double((seq_len(n)*19)%%1001L-500L)/8
        x_positions <- y_positions <- integer()
        if(pattern=='sparse') {
            x_positions <- seq.int(13L,n,by=997L);y_positions <- seq.int(19L,n,by=991L)
        } else if(pattern=='random_half') {
            RNGkind('Mersenne-Twister','Inversion','Rejection');set.seed(31791L)
            x_positions <- sample.int(n,n%/%2L);set.seed(42793L);y_positions <- sample.int(n,n%/%2L)
        } else if(pattern=='prefix256') y_positions <- seq_len(256L)
        else if(pattern=='suffix256') y_positions <- seq.int(n-255L,n)
        else if(pattern=='all_tags')x_positions <- y_positions <- seq_len(n)
        xr <- yr <- integer(n)
        xr[x_positions] <- rep(1:27,length.out=length(x_positions))
        yr[y_positions] <- rep(27:1,length.out=length(y_positions))
        for(code in 1:27) {
            x_plain[xr==code] <- if(code==1L)NA_real_ else tagged_missing(letters[code-1L])
            y_plain[yr==code] <- if(code==1L)NA_real_ else tagged_missing(letters[code-1L])
        }
        missing <- xr>0L | yr>0L
        overlap <- sum(xr>0L & yr>0L)
        stopifnot(sum(missing)==length(x_positions)+length(y_positions)-overlap)
        input_hash <- pair_hash(x_plain,y_plain);ranks_hash <- rank_hash(c(xr,yr))
        values <- list(compact=list(dta_long(x_plain),dta_float(y_plain)),
                       typed_double=list(dta_double(x_plain),dta_double(y_plain)))
        chunks <- switch(layout,plain=c(0L,0L),retained=c(8191L,16385L),short=c(7L,11L))
        if(layout!='plain')for(side in 1:2)
            values$compact[[side]] <- .Call(dtatools:::C_dtatools_owned_numeric_freeze,values$compact[[side]],chunks[[side]])
        if(pattern=='none')values$ordinary <- list(x_plain,y_plain)
        for(op_position in seq_along(operation_order)) {
            operation <- operation_order[[op_position]];call <- operations[[operation]]
            op_index <- match(operation,names(operations))
            order <- names(values)
            if(length(order)==3L)order <- order[permutations[[(round-1L+op_index-1L+match(layout,layouts)-1L)%%6L+1L]]]
            else if((round+match(pattern,patterns)-1L+op_index-1L+match(layout,layouts)-1L)%%2L==0L)order <- rev(order)
            expected <- call(x_plain,y_plain);expected[missing] <- NA_real_
            stopifnot(all(is.finite(expected[!missing])),identical(is.na(expected),missing))
            expected_hash <- value_hash(expected);missing_hash <- rank_hash(missing)
            cleared <- expected;cleared[missing] <- 0;cleared_hash <- value_hash(cleared)
            for(rp in seq_along(order)) {
                representation <- order[[rp]];x <- values[[representation]][[1L]];y <- values[[representation]][[2L]]
                before <- pair_state(x,y);meta <- metadata_hash(x,y)
                expected_storage <- if(representation=='ordinary')'' else 'double'
                check_sources <- function()stopifnot(identical(pair_state(x,y),before),
                    identical(metadata_hash(x,y),meta),identical(pair_hash(x,y),input_hash),identical(pair_state(x,y),before))
                check <- function(result) {
                    storage <- if(inherits(result,'dta_numeric'))dta_storage_type(result) else ''
                    stopifnot(identical(storage,expected_storage),identical(value_hash(result),expected_hash),
                        identical(is.na(result),missing),identical(anyNA(result),any(missing)))
                    check_sources()
                }
                check_sources();check(call(x,y))
                started <- entry();result <- call(x,y);qualification_calls <- entry()-started
                check(result);stopifnot(qualification_calls==if(representation=='ordinary')0 else 1)
                result_meta <- digest::digest(attributes(result),algo='sha256')
                repetitions <- 1L;cpu <- wall <- 0;native_calls <- qualification_calls
                if(!qualify) {
                    repeat {
                        gc();start <- proc.time()
                        for(i in seq_len(repetitions))result <- call(x,y)
                        delta <- proc.time()-start;duration <- unname(delta[['user.self']]+delta[['sys.self']])
                        if(duration>=0.05 || repetitions>=100000L)break
                        repetitions <- repetitions*2L
                    }
                    repetitions <- min(1000000L,max(repetitions,as.integer(ceiling(repetitions*0.3/max(duration,0.001)))))
                    gc();started <- entry();start <- proc.time()
                    for(i in seq_len(repetitions))result <- call(x,y)
                    delta <- proc.time()-start;native_calls <- entry()-started
                    cpu <- unname(delta[['user.self']]+delta[['sys.self']]);wall <- unname(delta[['elapsed']])
                    check(result);stopifnot(native_calls==if(representation=='ordinary')0 else repetitions,
                        identical(digest::digest(attributes(result),algo='sha256'),result_meta))
                }
                # Outside both clocks and entry-counter intervals, clear every
                # oracle missing to verify the exact cached count, retaining the
                # original result to exercise copy-on-write.
                mutation_checked <- representation!='ordinary'
                if(mutation_checked) {
                    table <- dibble(value=result)
                    if(any(missing))replace_values(table,value=0,where=which(missing))
                    stopifnot(identical(value_hash(table$value),cleared_hash),!anyNA(table$value))
                    check(result)
                }
                after <- pair_state(x,y)
                row <- data.frame(round,phase=if(qualify)'qualify' else 'measure',threads,rows=n,
                    layout,layout_position=lp,pattern,pattern_position=pp,operation,operation_position=op_position,
                    representation,position=rp,repetitions,cpu,wall,native_calls,qualification_calls,input_hash,
                    rank_hash=ranks_hash,result_hash=expected_hash,missing_hash,metadata_hash=meta,
                    result_metadata_hash=result_meta,long_missing=length(x_positions),float_missing=length(y_positions),
                    overlap,result_missing=sum(missing),result_storage=expected_storage,mutation_checked,
                    cleared_hash=if(mutation_checked)cleared_hash else '')
                for(key in names(before)) {
                    row[[paste0(key,'_before')]] <- before[[key]]
                    row[[paste0(key,'_after')]] <- after[[key]]
                }
                rows[[length(rows)+1L]] <- row
            }
        }
    }
}
write.csv(do.call(rbind,rows),args[[3L]],row.names=FALSE)
cat(length(rows),if(qualify)'qualified cases\n' else 'qualified observations\n')
