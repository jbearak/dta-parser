# Run only in a released setup window. The Python controller creates the mirror.
args <- commandArgs(TRUE)
config <- jsonlite::read_json(args[[1]], simplifyVector = TRUE)
.libPaths(c(config$library, .libPaths()))
library(testthat)
library(dtatools)
stopifnot(identical(normalizePath(find.package('dtatools')),
                    normalizePath(file.path(config$library, 'dtatools'))))
.metadata_probe_records <- list()
options(metadata.probe.output = config$output)
files <- list.files(config$test_directory, pattern = '^test-.*\\.[Rr]$')
target <- 'test-metadata-execution-profile.R'
stopifnot(target %in% files)
if (config$mode == 'prefix') files <- files[seq_len(match(target, files))]
if (config$mode == 'suspects') {
    files <- files[files %in% c('test-arithmetic-payload-lifetime.R',
        'test-dta-numeric.R', 'test-double-combine.R',
        'test-generation-metadata.R', 'test-label-metadata.R',
        'test-mask-bindings.R', 'test-mask-reader-callbacks.R',
        'test-metadata-dependency-settlement.R', target)]
}
if (config$mode == 'focus') files <- target
if (!is.null(config$only_files)) files <- files[files %in% config$only_files]
stopifnot(target %in% files)
# File basenames contain no regex metacharacters except '-' and '.R'.
filter <- paste0('^(', paste(sub('\\.[Rr]$', '', sub('^test-', '', files)), collapse='|'), ')$')
record <- list(R=R.version, library=find.package('dtatools'), libpaths=.libPaths(),
    environment=Sys.getenv(c("R_DISABLE_BYTECODE","R_ENABLE_JIT","NOT_CRAN",
        "R_DEFAULT_PACKAGES","R_TESTS","R_KEEP_PKG_SOURCE","_R_CHECK_FORCE_SUGGESTS_")),
    options=options()[intersect(names(options()), c("keep.source","keep.source.pkgs",
        "dtatools.generate_type","dtatools.output","expressions","warn"))], selected_files=files,
    loaded_namespaces=loadedNamespaces(), source_binding=config$source_binding,
    instrumentation=config$instrument)
saveRDS(record, file.path(config$output, 'process-before.rds'))
status <- tryCatch({
    if(config$runner == 'check') {
        setwd(dirname(config$test_directory))
        testthat::test_check('dtatools', filter=filter, reporter='summary')
    } else {
        results <- testthat::test_dir(config$test_directory, filter=filter,
            package='dtatools', load_package='installed', reporter='summary',
            stop_on_failure=FALSE)
        frame <- as.data.frame(results)
        write.csv(frame[c('file','test','passed','failed','error','skipped','warning')],
            file.path(config$output, 'assertions.csv'), row.names=FALSE)
        stopifnot(!any(frame$failed), !any(frame$error), !any(frame$skipped))
    }
    list(ok=TRUE)
}, error=function(e) list(ok=FALSE, message=conditionMessage(e), call=conditionCall(e)))
saveRDS(.metadata_probe_records, file.path(config$output, 'callback-records.rds'))
saveRDS(list(status=status, loaded_namespaces=loadedNamespaces()),
    file.path(config$output, 'process-after.rds'))
quit(status=if(status$ok) 0L else 1L)
