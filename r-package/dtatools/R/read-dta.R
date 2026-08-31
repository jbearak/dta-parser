#' Read a Stata DTA file
#'
#' Reads releases 105, 108, 110--111, 113--115, and 117--119 through the native Rust parser.
#' Numeric and character columns are created directly by native code. Numeric
#' columns carry their declared Stata storage type throughout the R session.
#' Byte, int, long, and float columns retain their compact Stata storage width
#' until R requests a materialized double vector; source doubles are created
#' eagerly.
#' Dataset and variable labels, numbered notes, arbitrary Stata
#' characteristics, display formats, value labels, `strL` content, and Stata
#' system/extended missing values are retained. Use [stata_notes()] and
#' [stata_characteristics()] at dataset or variable scope.
#' Imported value-label table identity is stored in `value.label.name` when the
#' table name differs from the source variable name or the source table is
#' shared. This differs from the variable label in `label` and the code-to-text
#' mapping in `labels`. Projection checks sharing against all source variables.
#'
#' @section Stata missing values:
#' Stata system missing (`.`) is returned as `NA_real_`; in releases supporting
#' extended missings (113 and newer), `.a` through `.z` use haven-compatible
#' tagged-NA payloads. Base [is.na()] therefore identifies every code present.
#' Use [missing_tag()] to recover their letters, [is_tagged_missing()] to
#' select tagged values, and [tagged_missing()] to create them. Use ordinary
#' `NA_real_`, rather than a tagged value, to create
#' Stata system missing. Missing tags are part of the numeric values and are
#' distinct from Stata value labels stored in a column's `labels` attribute.
#' Tagged missings can be stored in any R double vector; the missing payload
#' itself does not require a Stata-specific class. Imported Stata numerics do
#' carry a class so their storage declaration survives supported operations.
#' Assigning one to an R integer vector widens that vector
#' to double because R integers have only `NA_integer_`. This does not reflect
#' a Stata limitation: Stata `byte`, `int`, and `long` storage each encode all
#' 27 missing codes in reserved high values.
#'
#' `dtatools` therefore presents Stata numeric columns as R doubles. A double
#' can retain the tag in the payload bits of an IEEE-754 missing value, so base
#' [is.na()] works without a package-specific class or method and haven's tag
#' helpers remain interoperable. R integers have only one missing encoding and
#' could not expose `.a` through `.z` losslessly. The R-facing double type does
#' not require eight bytes per source value while the column remains ALTREP:
#' source `byte`, `int`, `long`, and `float` values stay in their compact Stata
#' storage and are converted to doubles on access. Supported mutations validate
#' and re-encode the result. A full materialization widens the backing to R
#' doubles but retains the declared storage class. This combines lossless
#' missing-code semantics with compact steady-state storage.
#' For example:
#' ```
#' x <- c(1, NA_real_, tagged_missing("a"), tagged_missing("z"))
#' is.na(x)
#' missing_tag(x)
#' is_tagged_missing(x)
#' is_tagged_missing(x, "a")
#' is_tagged_missing(x, c("a", "f"))
#'
#' x[1] <- NA_real_                 # Stata .
#' x[2] <- tagged_missing("a")       # Stata .a
#' x[3] <- tagged_missing("f")       # Stata .f
#' ```
#'
#' Base subassignment and [replace()] retain unselected tags when their index
#' contains no missing values; use `!is.na(x) & x == value` when recoding an
#' observed value. Avoid `ifelse(x == value, replacement, x)`, whose missing
#' condition entries become ordinary `NA` and lose their tags.
#'
#' When recoding, `dplyr::case_when()` preserves values returned by its default
#' branch. `dplyr::if_else()` preserves unselected tags when its condition is
#' complete; if the condition can be `NA`, also supply `missing = x`. Once the
#' dtatools namespace is loaded, [recode()] and `dplyr::recode()` preserve
#' unmatched tags in bare numeric, `haven_labelled`, `Date`, and `POSIXct`
#' columns, including inside `dplyr::mutate()`. Missing-value replacement
#' helpers match all 27 codes; select particular extended missing codes with
#' `is_tagged_missing(x, tag)` instead. A transformation may materialize an
#' ALTREP column and may drop Stata metadata attributes when it constructs a
#' new vector, following the same behavior as haven-compatible vectors.
#'
#' @section Stata storage declarations:
#' [stata_storage_type()] reports `"byte"`, `"int"`, `"long"`, `"float"`, or
#' `"double"` without materializing compact backing. Use [stata_byte()],
#' [stata_int()], [stata_long()], [stata_float()], and [stata_double()] to
#' declare storage for derived vectors. Constructors and explicit casts reject
#' unrepresentable values and name the wider constructor to use. Float
#' construction rounds to binary32, as Stata does.
#'
#' Subassignment, [replace()], `dplyr::if_else()`, and `dplyr::mutate()` retain
#' declared storage and re-encode compact results. Arithmetic starts at the
#' operands' common Stata storage type and widens only when the result values
#' require it. Imported `Date` and `POSIXct` columns validate on Stata's source
#' scale, including Stata's 1960 epoch and millisecond datetime unit, while
#' continuing to expose ordinary R temporal values. Base `ifelse()` takes
#' attributes from its condition and therefore returns a bare vector. Pass that
#' result to a storage constructor to declare and compact it again. Re-encoding
#' temporarily materializes doubles, so the memory saving applies after
#' construction and across columns held in memory.
#'
#' @section Labels and missing-code helpers:
#' Reading DTA files and working with their labels does not require haven or
#' labelled. Use [var_label()], [val_labels()], [dataset_label()],
#' [set_var_label()], [set_var_labels()], and [set_val_labels()] to inspect or
#' change package-owned Stata metadata without materializing compact numeric
#' columns or dropping unrelated attributes. For example:
#' ```
#' data <- data.frame(status = c(1, 2, 1))
#' var_label(data$status)
#' var_label(data$status) <- "Interview status"
#' val_labels(data$status)
#' val_labels(data$status) <- c(Complete = 1, Refused = 2)
#' ```
#'
#' The package-owned missing-code helpers also work without haven:
#' ```
#' missing_tag(data$status)
#' is_tagged_missing(data$status, "a")
#' data$status[1] <- tagged_missing("a")
#' ```
#' Use [factor_from_labels()] for an intentional one-way conversion to an
#' ordinary factor. Haven can be installed separately to write older DTA
#' releases or read other statistical formats.
#' See the
#' \href{https://github.com/jbearak/dta-parser/blob/main/docs/r-label-metadata.md}{R label metadata guide}
#' for bulk setters, Stata 19 limits, and the version-specific comparison with
#' labelled 2.16.0.
#'
#' @param file A path, URL, raw vector, or binary connection. Local and remote
#'   gzip files and local bzip2, xz, and zip files are decompressed
#'   automatically. Character vectors containing literal data are not handled,
#'   matching `haven::read_dta()`. URLs are fetched at call time; applications
#'   accepting untrusted `file` values should validate or allowlist sources
#'   before calling `read_dta()`.
#' @param encoding Optional source encoding override. Supported aliases are
#'   `"UTF-8"`/`"UTF8"`, `"Windows-1252"`/`"CP1252"`, and
#'   `"ISO-8859-1"`/`"latin1"`, matched case-insensitively. `NULL` uses
#'   Windows-1252 for pre-Unicode releases 105, 108, 110--111, 113--115, and
#'   117, and UTF-8 for releases 118--119. Older DTA files do not record their
#'   code page, so Windows-1252 is a pragmatic guess that commonly recovers the
#'   intended text. Use `encoding = "UTF-8"` for strict Stata 18 behavior;
#'   malformed input sequences are then replaced deterministically with
#'   U+FFFD. Haven 2.5.5 may instead omit an affected label.
#' @param col_select One or more tidyselect expressions. Predicates see Stata
#'   string storage as character and numeric storage as double. If a source
#'   variable is selected more than once, its first selection and alias win.
#'   Selection is resolved from metadata before observation data are read.
#' @param skip Number of observations to skip. Must be one non-negative whole
#'   number no larger than `2^53`.
#' @param n_max Maximum observations to read. `NA`, either infinity, and
#'   negative finite values read all remaining rows, following haven's
#'   unlimited-row convention. Non-negative values must be whole numbers no
#'   larger than `2^53`.
#' @param threads Number of decoder threads. Zero selects an automatic count
#'   for sufficiently large files in any supported Stata release. One always
#'   uses the serial decoder. For selected `strL` columns, workers decode
#'   observation references before the coordinator resolves their payloads.
#' @param use_numeric_altrep Whether byte, int, long, and float columns should retain
#'   their compact Stata storage through ALTREP. Set to `FALSE` to create eager
#'   R double vectors during decoding, which uses more memory but avoids later
#'   widening when a workload requires a contiguous double data pointer.
#'   Character-column ALTREP is unaffected.
#' @param .name_repair Name repair passed to [tibble::as_tibble()].
#' @param datasig Whether to record the file's [datasig()] signature in the
#'   result's `datasig` attribute, as a load-time record of what the file on
#'   disk signed as; it is never updated afterwards, so it is not a claim
#'   about the object's current content. Computing it costs one hash pass
#'   over the decoded columns (no second read of the file) and equals
#'   `datasig(file)`. Requires reading the complete file: incompatible with
#'   `col_select`, `skip`, and `n_max`.
#' @return A tibble. `%td` columns and legacy or custom formats beginning `%d`
#'   have class `Date`; `%tc` and `%tC` columns have classes `POSIXct` and
#'   `POSIXt` in UTC. Other Stata temporal formats remain numeric with their
#'   `format.stata` attribute.
#' @export
read_dta <- function(file, encoding = NULL, col_select = NULL, skip = 0,
                     n_max = Inf, .name_repair = "unique",
                     threads = getOption("dtatools.threads", 0L),
                     use_numeric_altrep = getOption(
                         "dtatools.numeric_altrep", TRUE
                     ),
                     datasig = FALSE) {
    selection <- rlang::enquo(col_select)
    datasig <- .normalize_arrow_flag(datasig, "datasig")
    if (datasig) .validate_datasig_read(selection, skip, n_max)
    .read_dta_impl(
        file, encoding, selection, skip, n_max, .name_repair,
        materialization = "direct", threads = threads,
        use_numeric_altrep = use_numeric_altrep,
        record_datasig = datasig
    )
}

.validate_datasig_read <- function(selection, skip, n_max) {
    row_window <- .normalize_row_window(skip, n_max)
    if (!rlang::quo_is_null(selection) || row_window$skip > 0 ||
        is.finite(row_window$n_max)) {
        stop(paste(
            "`datasig` requires reading the complete file;",
            "drop `col_select`, `skip`, and `n_max`"
        ), call. = FALSE)
    }
}

# Internal A/B baseline. This deliberately retains the former two-stage path
# so direct-to-R materialization can be benchmarked and checked independently.
.read_dta_rust_vectors <- function(file, encoding = NULL, col_select = NULL,
                                   skip = 0, n_max = Inf,
                                   .name_repair = "unique") {
    .read_dta_impl(
        file, encoding, rlang::enquo(col_select), skip, n_max, .name_repair,
        materialization = "rust-vectors", threads = 1L,
        use_numeric_altrep = FALSE, record_datasig = FALSE
    )
}

# Internal invariant probe used by the native-materialization tests.
.is_numeric_altrep <- function(value) {
    .Call(C_dtatools_is_numeric_altrep, value)
}

.is_altrep <- function(value) {
    .Call(C_dtatools_is_altrep, value)
}

.is_unmaterialized_numeric_altrep <- function(value) {
    .Call(C_dtatools_is_unmaterialized_numeric_altrep, value)
}

.is_unmaterialized_dictstring <- function(value) {
    .Call(C_dtatools_is_unmaterialized_dictstring, value)
}

.dictstring_cached_count <- function(value) {
    .Call(C_dtatools_dictstring_cached_count, value)
}

.force_altrep_materialization <- function(value) {
    .Call(C_dtatools_force_altrep_materialization, value)
}

.mutate_first_numeric_altrep <- function(value, replacement) {
    .Call(C_dtatools_mutate_first_numeric_altrep, value, replacement)
}

.mutate_first_dictstring_altrep <- function(value, replacement) {
    .Call(C_dtatools_mutate_first_dictstring_altrep, value, replacement)
}

.metadata_proxy_depth <- function(value) {
    .Call(C_dtatools_metadata_proxy_depth, value)
}

.metadata_proxy_aggregate_mask <- function(enabled) {
    .Call(C_dtatools_metadata_proxy_aggregate_mask, enabled)
}

.read_dta_impl <- function(file, encoding, selection, skip, n_max,
                           .name_repair, materialization, threads,
                           use_numeric_altrep, record_datasig) {
    encoding <- .validate_dta_encoding(encoding)
    row_window <- .normalize_row_window(skip, n_max)
    threads <- .normalize_threads(threads)
    use_numeric_altrep <- .normalize_use_numeric_altrep(use_numeric_altrep)

    source <- .resolve_dta_source(file)
    on.exit(.cleanup_dta_source(source), add = TRUE)

    if (rlang::quo_is_null(selection)) {
        column_indices <- NULL
    } else {
        metadata_names <- .dta_metadata(source$path, encoding)
        storage <- attr(metadata_names, "dta_storage", exact = TRUE)
        selection_proxy <- stats::setNames(
            lapply(storage, function(type) {
                if (identical(type, "character")) character() else double()
            }),
            metadata_names
        )
        selected <- tidyselect::eval_select(selection, selection_proxy)
        selected <- selected[!duplicated(unname(selected))]
        column_indices <- as.integer(unname(selected) - 1L)
        selected_names <- names(selected)
    }

    native <- .Call(
        C_dtatools_read,
        source$path,
        column_indices,
        row_window$skip,
        row_window$n_max,
        identical(materialization, "direct"),
        threads,
        use_numeric_altrep,
        encoding
    )
    if (!is.null(column_indices)) {
        names(native) <- selected_names
    }

    disk_signature <- if (record_datasig) {
        datasig(native, threads = threads)
    }

    dataset_label <- attr(native, "label", exact = TRUE)
    result <- tibble::as_tibble(native, .name_repair = .name_repair)
    if (!is.null(dataset_label)) attr(result, "label") <- dataset_label
    result <- .copy_stata_metadata_attributes(native, result)
    if (record_datasig) attr(result, "datasig") <- disk_signature
    result
}

.normalize_use_numeric_altrep <- function(value) {
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
        stop("`use_numeric_altrep` must be one non-missing logical value",
             call. = FALSE)
    }
    value
}

.normalize_threads <- function(value) {
    if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
        !is.finite(value) || value < 0 || value != floor(value) ||
        value > .Machine$integer.max) {
        stop("`threads` must be one non-negative whole number", call. = FALSE)
    }
    as.integer(value)
}

.resolve_dta_source <- function(file, fileext = ".dta",
                                implicit_extension = TRUE) {
    if (implicit_extension) file <- .resolve_implicit_dta_read_path(file)
    caller_supplied_source <- inherits(file, "source")
    caller_path <- .caller_dta_source_path(file)
    datasource <- readr::datasource(file)
    source_type <- class(datasource)[[1L]]

    if (identical(source_type, "source_file")) {
        path <- normalizePath(datasource[[1L]], winslash = "/", mustWork = TRUE)
        # Delete only a direct child of tempdir() that differs from a canonical
        # caller-owned path. Ownership never depends on datasource internals,
        # and a caller-supplied source object is always left to its caller.
        temporary_parent <- dirname(path)
        temporary_root <- normalizePath(
            tempdir(), winslash = "/", mustWork = TRUE
        )
        comparison_path <- path
        if (identical(.Platform$OS.type, "windows")) {
            temporary_parent <- tolower(temporary_parent)
            temporary_root <- tolower(temporary_root)
            comparison_path <- tolower(comparison_path)
            if (!is.null(caller_path)) caller_path <- tolower(caller_path)
        }
        temporary <- !caller_supplied_source &&
            identical(temporary_parent, temporary_root) &&
            (is.null(caller_path) || !identical(comparison_path, caller_path))
        return(list(
            path = path,
            temporary = temporary,
            datasource = datasource
        ))
    }

    if (identical(source_type, "source_raw")) {
        path <- tempfile(pattern = "dtatools-", fileext = fileext)
        complete <- FALSE
        on.exit(if (!complete) unlink(path), add = TRUE)
        writeBin(datasource[[1L]], path)
        complete <- TRUE
        return(list(path = path, temporary = TRUE, datasource = datasource))
    }

    stop("This kind of input is not handled.", call. = FALSE)
}

.resolve_implicit_dta_read_path <- function(file) {
    local_scalar <- is.character(file) && length(file) == 1L && !is.na(file) &&
        !grepl("^[[:alpha:]][[:alnum:]+.-]*://", file)
    if (!local_scalar || nzchar(tools::file_ext(basename(file)))) return(file)
    paste0(file, ".dta")
}

.data_source_file_extension <- function(file) {
    is_url <- grepl("^[[:alpha:]][[:alnum:]+.-]*://", file)
    path <- if (is_url) sub("[?#].*$", "", file) else file
    tolower(tools::file_ext(basename(path)))
}

.caller_dta_source_path <- function(file) {
    path <- NULL
    if (is.character(file) && length(file) == 1L && !is.na(file) &&
        file.exists(file)) {
        path <- file
    } else if (inherits(file, "connection")) {
        description <- summary(file)$description
        if (is.character(description) && length(description) == 1L &&
            !is.na(description) && file.exists(description)) {
            path <- description
        }
    }

    if (is.null(path)) return(NULL)
    normalizePath(path, winslash = "/", mustWork = TRUE)
}

.cleanup_dta_source <- function(source) {
    if (isTRUE(source$temporary)) {
        unlink(source$path)
    }
    invisible(NULL)
}

.dta_metadata <- function(file, encoding = NULL, column_start = 1L,
                          column_count = Inf) {
    validate <- function(value, name, unlimited = FALSE) {
        if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
            is.nan(value) || value < 0 || value != floor(value) ||
            (!is.finite(value) && !unlimited) ||
            (is.finite(value) && value > .Machine$integer.max)) {
            stop(sprintf("`%s` must be one non-negative whole number%s", name,
                         if (unlimited) " or Inf" else ""), call. = FALSE)
        }
        if (is.infinite(value)) .Machine$integer.max else as.integer(value)
    }
    start <- validate(column_start, "column_start")
    if (start < 1L) stop("`column_start` must be at least 1", call. = FALSE)
    count <- validate(column_count, "column_count", unlimited = TRUE)
    .Call(C_dtatools_metadata, file, encoding, start - 1L, count)
}

.validate_dta_encoding <- function(encoding) {
    if (is.null(encoding)) return(NULL)
    if (!is.character(encoding) || length(encoding) != 1L || is.na(encoding)) {
        stop("`encoding` must be NULL or one non-missing character string",
             call. = FALSE)
    }
    key <- tolower(gsub("[-_ ]", "", encoding))
    canonical <- switch(key,
        utf8 = "UTF-8",
        windows1252 = "Windows-1252",
        cp1252 = "Windows-1252",
        iso88591 = "ISO-8859-1",
        latin1 = "ISO-8859-1",
        NULL
    )
    if (is.null(canonical)) {
        stop(sprintf(
            "unsupported `encoding` %s; use UTF-8, Windows-1252, or ISO-8859-1",
            encodeString(encoding, quote = "\"")
        ), call. = FALSE)
    }
    canonical
}

.normalize_row_window <- function(skip, n_max) {
    list(
        skip = .normalize_skip(skip),
        n_max = .normalize_n_max(n_max)
    )
}

.normalize_skip <- function(value) {
    .validate_count_shape(value, "skip")
    if (is.na(value) || !is.finite(value) || value < 0 ||
        value > 2^53 || (!is.integer(value) && value != floor(value))) {
        stop(
            "`skip` must be one non-negative whole number no larger than 2^53",
            call. = FALSE
        )
    }
    as.double(value)
}

.normalize_n_max <- function(value) {
    if (length(value) != 1L) {
        stop("`n_max` must have length 1", call. = FALSE)
    }

    # Bare NA is logical in R, but it is the conventional spelling of haven's
    # unlimited-row sentinel. Other logical and non-numeric values remain
    # invalid rather than entering native coercion.
    if (identical(value, NA)) return(Inf)
    .validate_count_type(value, "n_max")
    if (is.na(value)) {
        if (is.nan(value)) {
            stop("`n_max` must not be NaN", call. = FALSE)
        }
        return(Inf)
    }
    if (is.infinite(value) || value < 0) return(Inf)
    if (value > 2^53 || (!is.integer(value) && value != floor(value))) {
        stop(paste(
            "`n_max` must be a whole number no larger than 2^53,",
            "or an unlimited-row sentinel"
        ), call. = FALSE)
    }
    as.double(value)
}

.validate_count_shape <- function(value, argument) {
    if (length(value) != 1L) {
        stop(sprintf("`%s` must have length 1", argument), call. = FALSE)
    }
    .validate_count_type(value, argument)
}

.validate_count_type <- function(value, argument) {
    if (is.object(value) || !(typeof(value) %in% c("integer", "double"))) {
        stop(sprintf("`%s` must be one integer or double", argument),
             call. = FALSE)
    }
}
