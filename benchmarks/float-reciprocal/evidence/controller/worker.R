args <- commandArgs(TRUE)
stopifnot(length(args) %in% 3:4)
qualify <- length(args)==4L && identical(args[[4L]],'qualify')
stopifnot(length(args)==3L || qualify)
.libPaths(c(normalizePath(args[[1L]]),.libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'),'path')),
    file.path(normalizePath(args[[1L]]),'dtatools')))
round <- as.integer(args[[2L]]); stopifnot(!is.na(round),round>0L)
threads <- 1L; options(dtatools.threads=threads)
stopifnot(identical(.Call(dtatools:::C_dtatools_test_numeric_size_minimum,NULL),2048L))
hash_raw <- function(x) digest::digest(x,algo='sha256',serialize=FALSE)
value_hash <- function(x) hash_raw(writeBin(as.double(x),raw(),8L,endian='little'))
rank_hash <- function(x) hash_raw(writeBin(as.integer(x),raw(),4L,endian='little'))
metadata_hash <- function(x) digest::digest(attributes(x),algo='sha256')
state <- function(x) {
    info <- .Call(dtatools:::C_dtatools_owned_numeric_info,x)
    c(compact=dtatools:::.is_unmaterialized_numeric_altrep(x),
      materialized=.Call(dtatools:::C_dtatools_is_materialized_numeric_altrep,x),
      retained=info[['owned']],chunks=info[['chunks']])
}
entry <- function() .Call(dtatools:::C_dtatools_numeric_entry_stats,FALSE)[['scalar']]
operations <- list(reciprocal=function(x) 1.01/x)
strata <- data.frame(n=c(1024L,2048L,4096L,16384L,rep(1000000L,5L)),
    pattern=c(rep('none',5L),'sparse','prefix256','random_half','all_tags'))
indices <- (seq_len(nrow(strata))+(round-2L))%%nrow(strata)+1L
if(round%%2L==0L) indices <- rev(indices)
rows <- list()
for(pp in seq_along(indices)) {
    index <- indices[[pp]];n <- strata$n[[index]];pattern <- strata$pattern[[index]]
    plain <- as.double((seq_len(n)*13)%%10001L-5000L)/8
    ranks <- integer(n)
    positions <- switch(pattern,none=integer(),sparse=seq.int(13L,n,by=997L),
        random_half={RNGkind('Mersenne-Twister','Inversion','Rejection');set.seed(29071L);sample.int(n,n%/%2L)},
        clustered_half=seq_len(n%/%2L),prefix256=seq_len(256L),suffix256=seq.int(n-255L,n),all_tags=seq_len(n))
    ranks[positions] <- rep(1:27,length.out=length(positions))
    for(code in 1:27) plain[ranks==code] <- if(code==1L) NA_real_ else tagged_missing(letters[code-1L])
    stopifnot(pattern=='none' || all(1:27 %in% ranks))
    input_hash <- value_hash(plain); ranks_hash <- rank_hash(ranks)
    values <- list(compact=dta_float(plain),typed_double=dta_double(plain))
    for(op_position in seq_along(operations)) {
        operation <- names(operations)[[op_position]];call <- operations[[operation]]
        order <- names(values)
        if((round+index-1L)%%2L==0L) order <- rev(order)
        reference <- call(plain)
        reference[ranks>0L | !is.finite(reference) | abs(reference)>(2^53-1)*2^970] <- NA_real_
        zero_observed <- sum(!is.na(plain) & plain==0)
        stopifnot(sum(is.na(reference))==length(positions)+zero_observed)
        for(rp in seq_along(order)) {
            representation <- order[[rp]];x <- values[[representation]]
            before <- state(x);meta <- metadata_hash(x)
            expected <- reference
            expected_storage <- if(representation=='compact') 'float' else if(representation=='typed_double') 'double' else ''
            if(representation=='compact') {
                observed <- !is.na(expected)
                stopifnot(all(abs(expected[observed])<=(2^24-1)*2^103))
                expected[observed] <- readBin(writeBin(expected[observed],raw(),4L,endian='little'),double(),sum(observed),4L,endian='little')
            }
            expected_hash <- value_hash(expected);mask <- is.na(expected);missing_hash <- rank_hash(mask)
            stopifnot(identical(value_hash(x),input_hash),identical(state(x),before))
            check <- function(result) {
                storage <- if(inherits(result,'dta_numeric')) dta_storage_type(result) else ''
                stopifnot(identical(storage,expected_storage),identical(value_hash(result),expected_hash),
                    identical(is.na(result),mask),identical(anyNA(result),any(mask)),
                    identical(state(x),before),identical(metadata_hash(x),meta),identical(value_hash(x),input_hash),
                    identical(state(x),before))
                if(representation=='compact') stopifnot(dtatools:::.is_unmaterialized_numeric_altrep(result))
            }
            check(call(x))
            started <- entry();result <- call(x);qualification_calls <- entry()-started
            check(result);stopifnot(qualification_calls==if(n<2048L) 0 else 1)
            result_meta <- metadata_hash(result)
            repetitions <- 1L;cpu <- wall <- 0;native_calls <- qualification_calls
            if(!qualify) {
                repeat {
                    gc();start <- proc.time()
                    for(i in seq_len(repetitions)) result <- call(x)
                    delta <- proc.time()-start;duration <- unname(delta[['user.self']]+delta[['sys.self']])
                    if(duration>=0.05 || repetitions>=100000L) break
                    repetitions <- repetitions*2L
                }
                repetitions <- min(1000000L,max(repetitions,as.integer(ceiling(repetitions*0.3/max(duration,0.001)))))
                gc();started <- entry();start <- proc.time()
                for(i in seq_len(repetitions)) result <- call(x)
                delta <- proc.time()-start;native_calls <- entry()-started
                cpu <- unname(delta[['user.self']]+delta[['sys.self']]);wall <- unname(delta[['elapsed']])
                check(result);stopifnot(native_calls==if(n<2048L) 0 else repetitions,
                    identical(metadata_hash(result),result_meta))
            }
            # Cache qualification is outside clocks and native-entry accounting.
            # Clearing every oracle-missing row detects a cached overcount too.
            result_before <- state(result)
            original_result <- result
            cleared <- expected
            cleared[mask] <- 0
            cleared_hash <- value_hash(cleared)
            mutable <- dibble(x=result)
            replace_values(mutable,x=0,where=which(mask))
            stopifnot(identical(value_hash(mutable$x),cleared_hash),
                !anyNA(mutable$x),identical(state(result),result_before),
                identical(value_hash(original_result),expected_hash),
                identical(metadata_hash(original_result),result_meta))
            check(result)
            after <- state(x)
            rows[[length(rows)+1L]] <- data.frame(round,phase=if(qualify)'qualify' else 'measure',threads,rows=n,
                pattern,pattern_position=pp,operation,operation_position=op_position,representation,position=rp,
                repetitions,cpu,wall,native_calls,qualification_calls,input_hash,rank_hash=ranks_hash,mutation_checked=TRUE,cleared_hash,
                result_hash=expected_hash,missing_hash,metadata_hash=meta,result_metadata_hash=result_meta,
                input_missing=length(positions),zero_observed,result_missing=sum(mask),result_storage=expected_storage,
                compact_before=as.logical(before[['compact']]),compact_after=as.logical(after[['compact']]),
                materialized_before=as.logical(before[['materialized']]),materialized_after=as.logical(after[['materialized']]),
                retained_before=before[['retained']],retained_after=after[['retained']],
                chunks_before=before[['chunks']],chunks_after=after[['chunks']])
        }
    }
}
write.csv(do.call(rbind,rows),args[[3L]],row.names=FALSE)
cat(length(rows),if(qualify)'qualified cases\n' else 'qualified observations\n')
