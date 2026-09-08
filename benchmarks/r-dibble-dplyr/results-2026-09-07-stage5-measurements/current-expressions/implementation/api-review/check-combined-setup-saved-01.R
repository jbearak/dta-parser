# Read retained source states only; no workload or candidate package load.
path <- "/private/tmp/dta-direct-stage5-validation/root-expression-performance/candidate-a2d8b6a-qualify-01"
qualification <- dget(file.path(path,"qualification.R"))
stopifnot(qualification$source == "a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9",
    length(qualification$records) == 16L, all(unlist(qualification$records)))
states <- readRDS(file.path(path,"source-states.rds"))
stopifnot(length(states) == 78L)
for (i in seq.int(1L,length(states),by=2L)) {
    before <- states[[i]]; after <- states[[i+1L]]
    stopifnot(all(before$phase=="fixture"),all(after$phase=="after_oracle"))
    before$phase <- after$phase <- NULL
    stopifnot(identical(before,after))
}
cat("PASS: all 16 reference qualification records; 39 source fixture/oracle state pairs identical,",
    sum(vapply(states,nrow,integer(1))), "retained state rows.\n")
