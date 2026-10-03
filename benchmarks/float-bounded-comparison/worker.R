args <- commandArgs(TRUE)
stopifnot(length(args) %in% 4:5)
qualify_only <- length(args)==5L && identical(args[[5]],'qualify')
stopifnot(length(args)==4L || qualify_only)
.libPaths(c(normalizePath(args[[1]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'),'path')),
    file.path(normalizePath(args[[1]]),'dtatools')))
round <- as.integer(args[[2]])
stopifnot(length(round)==1L,!is.na(round),round>=1L)
hash <- function(x) digest::digest(writeBin(x,raw(),size=4L,endian='little'),algo='sha256',serialize=FALSE)
metadata_hash <- function(x) digest::digest(attributes(x),algo='sha256')
value_hash <- function(x) digest::digest(writeBin(as.double(x),raw(),size=8L,endian='little'),algo='sha256',serialize=FALSE)
state <- function(x) {
    info <- .Call(dtatools:::C_dtatools_owned_numeric_info,x)
    list(compact=dtatools:::.is_unmaterialized_numeric_altrep(x),
        materialized=.Call(dtatools:::C_dtatools_is_materialized_numeric_altrep,x),
        retained=info[['owned']],chunks=info[['chunks']])
}
rows <- list(); n <- 1000000L; threads <- 1L
options(dtatools.threads=threads)
operations <- list(pair_less=function(x,y) x<y,pair_equal=function(x,y) x==y)
panel <- args[[4]]
panels <- list(density=c('random_half','clustered_half','all_tags'),
    pattern=c('dense_prefix256','dense_suffix256','alternating64'),
    ordinary=c('none','sparse'))
stopifnot(panel %in% names(panels))
patterns <- panels[[panel]]
layouts <- c('plain','retained')
permutations <- list(c(1L,2L,3L),c(1L,3L,2L),c(2L,1L,3L),
    c(2L,3L,1L),c(3L,1L,2L),c(3L,2L,1L))
pattern_order <- if(length(patterns)==3L) patterns[permutations[[(round-1L)%%6L+1L]]] else
    if(round%%2L) patterns else rev(patterns)
operation_order <- if(round%%2L) names(operations) else rev(names(operations))
for(pattern_position in seq_along(pattern_order)) {
    pattern <- pattern_order[[pattern_position]]
    px <- as.double((seq_len(n)*13) %% 10001L-5000L)/8
    py <- as.double((seq_len(n)*19) %% 10001L-5000L)/8
    rx <- integer(n); ry <- integer(n)
    if(pattern=='random_half') {
        RNGkind('Mersenne-Twister','Inversion','Rejection')
        set.seed(29071L); ix <- sample.int(n,n%/%2L,replace=FALSE)
        set.seed(60149L); iy <- sample.int(n,n%/%2L,replace=FALSE)
    } else if(pattern=='clustered_half') {
        ix <- iy <- seq_len(n%/%2L)
    } else if(pattern=='all_tags') {
        ix <- iy <- seq_len(n)
    } else if(pattern=='dense_prefix256') {
        ix <- iy <- seq_len(256L)
    } else if(pattern=='dense_suffix256') {
        ix <- iy <- seq.int(n-255L,n)
    } else if(pattern=='alternating64') {
        ix <- iy <- which(((seq_len(n)-1L)%/%64L)%%2L==0L)
    } else if(pattern=='sparse') {
        ix <- seq.int(13L,n,by=997L); iy <- seq.int(19L,n,by=991L)
    } else ix <- iy <- integer(0)
    rx[ix] <- rep(1:27,length.out=length(ix))
    ry[iy] <- rep(27:1,length.out=length(iy))
    stopifnot(sum(rx>0L)==length(ix),sum(ry>0L)==length(iy),
        pattern=='none' || all(1:27 %in% rx),pattern=='none' || all(1:27 %in% ry))
    for(code in 1:27) {
        value <- if(code==1L) NA_real_ else tagged_missing(letters[code-1L])
        px[rx==code] <- value; py[ry==code] <- value
    }
    vx <- px; vy <- py; vx[rx>0L] <- 0; vy[ry>0L] <- 0
    expected <- list(pair_less=rx<ry | (rx==ry & vx<vy),pair_equal=rx==ry & vx==vy)
    input_hash <- value_hash(px); y_hash <- value_hash(py)
    rank_x_hash <- hash(rx); rank_y_hash <- hash(ry)
    x_missing <- sum(rx>0L); y_missing <- sum(ry>0L)
    pair_missing <- sum(rx>0L | ry>0L)
    layout_order <- if((round+match(pattern,patterns))%%2L) layouts else rev(layouts)
    for(layout_position in seq_along(layout_order)) {
        layout <- layout_order[[layout_position]]
        x <- list(compact=dta_float(px),typed_double=dta_double(px))
        y <- list(compact=dta_float(py),typed_double=dta_double(py))
        if(layout=='retained') {
            x$compact <- .Call(dtatools:::C_dtatools_owned_numeric_freeze,x$compact,8191L)
            y$compact <- .Call(dtatools:::C_dtatools_owned_numeric_freeze,y$compact,16385L)
        }
        stopifnot(state(x$compact)[['retained']]==as.integer(layout=='retained'),
            state(y$compact)[['retained']]==as.integer(layout=='retained'))
    for(operation_position in seq_along(operation_order)) {
        operation <- operation_order[[operation_position]]
        case <- (match(pattern,patterns)-1L)*4L+(match(layout,layouts)-1L)*2L+match(operation,names(operations))
        order <- if((round+case)%%2L) names(x) else rev(names(x))
        for(position in seq_along(order)) {
            representation <- order[[position]]
            a <- x[[representation]]; b <- y[[representation]]; call <- operations[[operation]]
            stopifnot(identical(value_hash(a),input_hash),identical(value_hash(b),y_hash))
            metadata_x <- metadata_hash(a); metadata_y <- metadata_hash(b)
            before <- state(a); before_y <- state(b); reference <- expected[[operation]]
            actual <- call(a,b)
            stopifnot(identical(actual,reference),identical(state(a),before),identical(state(b),before_y))
            op <- if(operation=='pair_equal') 0L else 2L
            native <- .Call(dtatools:::C_dtatools_dta_compare,op,a,b,NULL,threads)
            stopifnot(identical(native,reference))
            reps <- 1L
            if(!qualify_only) repeat {
                gc(); start <- proc.time(); for(i in seq_len(reps)) result <- call(a,b)
                duration <- sum((proc.time()-start)[1:2])
                if(duration>=.05 || reps>=10000L) break
                reps <- reps*5L
            }
            if(qualify_only) {
                result <- call(a,b); timing <- c(user.self=0,sys.self=0,elapsed=0)
            } else {
                reps <- max(reps,ceiling(reps*.30/max(duration,.001)))
                gc(); start <- proc.time(); for(i in seq_len(reps)) result <- call(a,b)
                timing <- proc.time()-start
            }
            stopifnot(identical(result,reference),identical(value_hash(a),input_hash),
                identical(value_hash(b),y_hash),identical(state(a),before),identical(state(b),before_y),
                identical(metadata_hash(a),metadata_x),identical(metadata_hash(b),metadata_y))
            rows[[length(rows)+1L]] <- data.frame(round,phase=if(qualify_only) "qualify" else "measure",threads,panel,pattern,pattern_position,layout,layout_position,
                operation,operation_position,representation,position,rows=n,repetitions=reps,
                x_missing,y_missing,pair_missing,rank_x_hash,rank_y_hash,cpu=sum(timing[1:2]),wall=timing[['elapsed']],
                result_hash=hash(result),input_hash,y_hash,compact_before=before[['compact']],
                compact_after=state(a)[['compact']],materialized_before=before[['materialized']],
                materialized_after=state(a)[['materialized']],y_compact_before=before_y[['compact']],
                y_compact_after=state(b)[['compact']],y_materialized_before=before_y[['materialized']],
                y_materialized_after=state(b)[['materialized']],
                retained_before=before[['retained']],retained_after=state(a)[['retained']],
                y_retained_before=before_y[['retained']],y_retained_after=state(b)[['retained']],
                chunks_before=before[['chunks']],chunks_after=state(a)[['chunks']],
                y_chunks_before=before_y[['chunks']],y_chunks_after=state(b)[['chunks']],
                metadata_x,metadata_y,native_qualified=TRUE)
        }
    }
    }
}
write.csv(do.call(rbind,rows),args[[3]],row.names=FALSE)
cat(length(rows),'qualified observations\n')
