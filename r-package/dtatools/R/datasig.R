#' Compute a data signature
#'
#' Computes an order-sensitive content signature of a dataset, for recording
#' alongside raw data files (for example in a git-tracked table) and later
#' comparing against the file read back from disk. The signature covers the
#' row and column counts, column names and order, Stata storage types,
#' display formats, variable labels, value-label tables, the dataset label
#' and notes, and every value in row order, digested through the same
#' canonical per-buffer xxHash64 checksums that [save_arrow()] embeds in its
#' file footer.
#'
#' @section Differences from Stata's `datasignature`:
#' Stata's signature is invariant to the order of observations and even to
#' the order of values within a single variable, so swapping two values in a
#' column — or swapping whole rows between sorted and unsorted copies — goes
#' undetected. This signature is a function of the values in row order:
#' sorting the data, swapping two values within a column, or swapping values
#' between columns all change it. The two commands therefore answer different
#' questions; this one answers "is this file bit-for-bit the dataset I
#' recorded?", which is the integrity question for raw data under a
#' reproducible pipeline.
#'
#' @section Container independence:
#' The signature is a function of the logical dataset, not the container it
#' came from. The same data signs identically whether passed as the in-memory
#' [read_dta()] result, as a `.dta` path, or as an `.arrow` path (with any
#' compression), because both readers return the same read model. A frame
#' that was never saved can sign differently from its own `.dta` file,
#' because [save_dta()] attaches display formats the constructed frame may
#' lack; sign the file (or its read model), not the pre-save frame. Changing
#' a column's declared Stata storage type changes the signature even when the
#' values are unchanged, matching Stata's definition.
#'
#' @section Recomputation:
#' R cannot reliably detect whether a data frame changed after it was loaded
#' (copy-on-modify means a signature cached at load time would survive the
#' modification and lie), so `datasig()` always recomputes from current
#' content. The hashing is parallel and operates on the columns' existing
#' backing memory, so recomputation costs roughly what [save_arrow()] saves in
#' checksum time — well under a second per gigabyte.
#'
#' To record the disk signature at load time instead of recomputing later,
#' pass `datasig = TRUE` to [read_dta()] or [read_arrow()]: the reader
#' attaches the file's signature as the result's `datasig` attribute.
#' [read_arrow()] derives it from the file's stored footer checksums for
#' almost nothing, even under projection; [read_dta()] hashes the decoded
#' columns, so it requires a full read.
#'
#' The payload definition is versioned internally (currently version 1); any
#' future change to it will be documented as producing new signatures.
#'
#' @param data A data frame, or one path to a `.dta` or `.arrow` file to
#'   read first. Columns must be writable by [save_arrow()].
#' @param threads Number of threads used to hash. `0` (the default) selects a
#'   thread count automatically; `1` forces serial hashing. Defaults to the
#'   `dtatools.threads` option.
#' @return One string of the form `"rows:columns:digest"`, where the digest
#'   is sixteen hexadecimal characters.
#' @examples
#' data <- data.frame(answer = stata_byte(c(1, tagged_missing("a"))))
#' datasig(data)
#'
#' # Swapped values change the signature (Stata's datasignature misses this).
#' swapped <- data.frame(answer = stata_byte(c(tagged_missing("a"), 1)))
#' datasig(swapped)
#' @export
datasig <- function(data, threads = getOption("dtatools.threads", 0L)) {
    threads <- .normalize_threads(threads)
    if (!is.data.frame(data)) {
        if (is.character(data) && length(data) == 1L && !is.na(data)) {
            extension <- .data_source_file_extension(data)
            data <- if (identical(extension, "arrow")) {
                # The data are rehashed below, so footer verification is not
                # needed and checksum-free profile files remain signable.
                read_arrow(data, verify = FALSE)
            } else {
                read_dta(data)
            }
        } else {
            stop(
                "`data` must be a data frame or one DTA or Arrow file path",
                call. = FALSE
            )
        }
    }
    specification <- .prepare_arrow_write(
        data, attr(data, "label", exact = TRUE), TRUE
    )
    .Call(C_dtatools_datasig, specification, threads)
}
