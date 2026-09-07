args <- commandArgs(TRUE)
if (length(args) != 4L) stop("Expected library, revision, helper DLL, and new result path")
if (file.exists(args[[4L]])) stop("Result already exists")
source("/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/helpers.R")
validate_benchmark_install(args[[1L]], args[[2L]])
suppressPackageStartupMessages(library(dtatools, lib.loc = args[[1L]]))
stopifnot(identical(normalizePath(find.package("dtatools")),
                    normalizePath(file.path(args[[1L]], "dtatools"))))
ns <- asNamespace("dtatools")
entry <- getNativeSymbolInfo("C_dtatools_owned_string_width",
                            PACKAGE = getLoadedDLLs()[["dtatools"]],
                            withRegistrationInfo = FALSE)
helper <- dyn.load(args[[3L]])
probe <- getNativeSymbolInfo("scan_vmax", PACKAGE = helper)
latin <- rawToChar(as.raw(0xe9))
Encoding(latin) <- "latin1"
bytes <- latin
Encoding(bytes) <- "bytes"
fixtures <- list(ascii = rep("abc", 1L), latin1 = rep(latin, 1L),
                 utf8 = rep(enc2utf8(latin), 1L), bytes = rep(bytes, 1L),
                 latin1_na = c(rep(latin, 0L), NA_character_), empty = character())
records <- lapply(names(fixtures), function(name) {
    values <- fixtures[[name]]
    x <- .Call(get("C_dtatools_capture_column", ns), values)
    # A plain captured character vector has no storage declaration, so its
    # first width request must scan the actual package's owned payload.
    invisible(.Call(get("C_dtatools_owned_scan_stats", ns), TRUE))
    observed <- .Call(probe, entry$address, x)
    scans <- .Call(get("C_dtatools_owned_scan_stats", ns), FALSE)
    expected <- if (anyNA(values)) NA_integer_ else
        if (!length(values)) 1L else max(1L, nchar(enc2utf8(values), type = "bytes"))
    stopifnot(identical(observed[[1L]], expected),
              identical(scans, c(1, as.double(length(values)))))
    list(case = name, width = observed[[1L]], retained_vmax = observed[[2L]], scans = scans)
})
validate_benchmark_install(args[[1L]], args[[2L]])
record <- list(source = args[[2L]],
               dll_md5 = unname(tools::md5sum(getLoadedDLLs()[["dtatools"]][["path"]])),
               cases = records, temporary_storage_released =
                   !any(vapply(records, `[[`, logical(1), "retained_vmax")))
saveRDS(record, args[[4L]])
print(record)
if (!record$temporary_storage_released)
    stop("Actual package width scan retains R temporary conversion storage until .Call returns",
         call. = FALSE)
