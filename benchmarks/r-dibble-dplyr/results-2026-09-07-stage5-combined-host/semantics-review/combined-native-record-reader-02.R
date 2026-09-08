root <- '/private/tmp/dta-direct-stage5-validation/implementation/native-combined-01'
script <- file.path(root, 'source/benchmarks/r-reference-mutation/run.R')
expressions <- parse(script)
counts <- c(stopifnot_calls=0L, assertion_expressions=0L, readiness_call_sites=0L)
walk <- function(x) {
 if (is.call(x)) {
  if (identical(x[[1L]], as.name('stopifnot'))) {
   counts[['stopifnot_calls']] <<- counts[['stopifnot_calls']] + 1L
   counts[['assertion_expressions']] <<- counts[['assertion_expressions']] + length(x)-1L
  }
  if (identical(x[[1L]],as.name('assert_frame')) && length(x)>2L) counts[['readiness_call_sites']] <<- counts[['readiness_call_sites']]+1L
 }
 if (is.call(x) || is.expression(x) || is.pairlist(x)) for (i in seq_along(x)) if (!identical(x[[i]], quote(expr=)) && !is.symbol(x[[i]])) walk(x[[i]])
}
walk(expressions)
identity <- dget(file.path(root,'preflight-identity.R'))
stopifnot(identity$source_sha == 'a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9', identity$provenance$source_tree == 'b08c77d91bdce67032f13aced90c29d068d6e95a', identity$dll_md5 == 'eb6ce934ca80b3321b58f75653302fa4', identity$runtime$version.string == 'R version 4.6.1 (2026-06-24)')
files <- file.path(identity$package_path,names(identity$provenance$files))
stopifnot(identical(unname(tools::md5sum(files)),unname(identity$provenance$files)))
print(counts)
cat('PASS retained provenance files and static source counts; no native code or workload sourced or executed\n')
