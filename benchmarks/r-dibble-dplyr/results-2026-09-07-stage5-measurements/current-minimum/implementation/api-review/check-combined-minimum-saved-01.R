# Saved data only. No candidate package load, tests, benchmark or profiler.
root <- "/private/tmp/dta-direct-stage5-validation/root-r460-integration"
name <- "candidate-a2d8b6a-v1"
source <- "a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9"
behavior_path <- file.path(root, paste0(name, "-behavior"))
behavior <- readRDS(file.path(behavior_path, "results.rds"))
stopifnot(identical(behavior, dget(file.path(behavior_path, "results.R"))),
    behavior$identity$source == source, behavior$identity$versions[["dplyr"]] == "1.2.1",
    behavior$identity$R == "R version 4.6.0 (2026-04-24)", length(behavior$cases) == 8L,
    all(vapply(behavior$cases, function(x) isTRUE(x$passed), logical(1))))
late <- behavior$cases[[8L]]
stopifnot(identical(late$warnings, rep("restarting interrupted promise evaluation", 3L)))
for (item in c(late$observations$promises, late$observations$closures)) {
    stopifnot(item$kind == "error", "error" %in% item$classes,
        grepl("Obsolete data mask", item$message, fixed = TRUE))
}
observe_path <- file.path(root, paste0(name, "-observe"))
observe <- readRDS(file.path(observe_path, "observations.rds"))
stopifnot(identical(observe, dget(file.path(observe_path, "observations.R"))),
    observe$identity$source == source, observe$identity$dplyr == "1.2.1")
for (kind in c("expanded", "aliased", "named", "unpacked")) {
    stopifnot(identical(observe[[kind]]$tibble, observe[[kind]]$dibble))
}
stopifnot(identical(observe$expanded$dibble$events, c("x:1", "x:2", "y:1", "y:2")),
    observe$expanded$dibble$factories == 1L,
    observe$aliased$dibble$factories == 4L, observe$named$dibble$factories == 4L,
    observe$unpacked$dibble$factories == 0L,
    identical(observe$within_across_input_values, list(x = c(11L,13L), y = c(11L,13L))))
focused <- file.path(root, paste0(name, "-focused"))
details <- readRDS(file.path(focused, "expectation-details.rds"))
stopifnot(identical(details, dget(file.path(focused, "expectation-details.R"))))
entries <- unlist(details, recursive = FALSE)
classes <- vapply(entries, function(x) x$classes[[1L]], character(1))
stopifnot(sum(classes == "expectation_success") == 8859L,
    sum(classes == "expectation_skip") == 3L,
    sum(classes == "expectation_warning") == 4L,
    all(classes %in% c("expectation_success", "expectation_skip", "expectation_warning")))
for (i in which(classes != "expectation_success")) {
    cat(classes[[i]], entries[[i]]$message, "\n")
}
for (suffix in c("", "-behavior", "-observe", "-focused")) for (phase in c("before", "after")) {
    guard <- dget(file.path(root, paste0(name, suffix), paste0("runtime-guard-", phase, ".R")))
    stopifnot(guard$R$version.string == "R version 4.6.0 (2026-04-24)",
        identical(guard$libR, "/private/tmp/dta-direct-stage5-minimum-preflight/r460-clean-install/lib/R/lib/libR.dylib"))
}
cat("PASS: 8 behavior cases, 4 expansion cases, all retained expectations and eight clean-runtime guard snapshots.\n")
