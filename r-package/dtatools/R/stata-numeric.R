#' Construct and inspect Stata numeric storage
#'
#' The storage-named constructors create numeric vectors whose declared Stata
#' storage type persists through supported vector operations. `byte`, `int`,
#' `long`, and `float` values use compact backing while R observes doubles.
#' `float` values are rounded to binary32 precision.
#'
#' Supply `x` to encode values or `.size` to allocate that many Stata system
#' missing values. Observed values must fit the requested storage type. Use the
#' wider constructor named in an error when they do not. Stata system missing
#' and extended missings `.a` through `.z` are valid in every storage type.
#' R `NaN` is not a Stata missing code. Construction, explicit casts,
#' assignment, and recode replacements reject it. Use `NA_real_` for system
#' missing or [tagged_missing()] for an extended missing value.
#'
#' Construction validates and encodes ordinary numeric vectors in native code
#' without allocating full-length validation vectors. Native and vctrs slicing
#' gather compact backing directly. Operations that require re-encoding an
#' existing compact vector still expose its values as doubles first.
#'
#' `serialize()` and `saveRDS()` retain compact backing for unmaterialized
#' `byte`, `int`, `long`, and `float` vectors. Loading the result reconstructs
#' an unmaterialized compact vector. A vector that was already materialized is
#' serialized as its current R doubles so any prior writable access is kept.
#'
#' @section Vector operations:
#' Subset assignment, [replace()], `dplyr::if_else()`, `dplyr::mutate()`, and
#' vctrs concatenation retain declared storage and re-encode compact results.
#' Extending a vector with another declared Stata numeric uses their common
#' storage type and combines compatible metadata. This supports base data-frame
#' reconstruction such as right and full [merge()] calls. Extending with a bare
#' value remains strict, like replacement within the existing vector.
#' Stata-backed `Date` and `POSIXct` vectors use the same extension rule when
#' both inputs have the same temporal kind.
#' Base `ifelse()` takes attributes from its condition, so it returns a bare
#' vector. Pass that result to a constructor to declare storage again.
#'
#' Common types follow the lossless Stata lattice: `byte` promotes to `int`,
#' `long`, `float`, or `double`; `int` promotes to `long`, `float`, or `double`;
#' and `long` combined with `float` promotes to `double`. Declared storage wins
#' over a bare logical, integer, or double vector. Explicit casts into declared
#' storage are strict and use the same errors as the constructors. Common-type
#' operations retain variable labels and merge compatible value-label tables;
#' conflicting text for one code warns and uses the left input's label.
#'
#' Arithmetic and the numeric group generics start at the operands' common
#' storage type, then widen only when the computed values require it. This is
#' value-dependent: integer overflow or a fractional result may change the
#' result's declared storage. Arithmetic results that are `NaN`, infinite, or
#' outside Stata's double range become Stata system missing.
#'
#' @param x For a constructor, a logical, integer, or double vector to encode.
#'   For `stata_storage_type()`, a vector to inspect.
#' @param .size A non-negative whole number of system missing values to
#'   allocate. Do not supply both `x` and `.size`.
#' @return A double vector carrying its declared Stata storage type.
#'   `stata_storage_type()` returns that type as one string, or `NULL` for a
#'   vector without a declared type.
#' @examples
#' codes <- stata_byte(c(1, 2, NA_real_, tagged_missing("a")))
#' stata_storage_type(codes)
#' missing <- stata_int(.size = 100)
#' undefined <- stata_byte(0) / stata_byte(0)
#' is.na(undefined)
#' try(stata_byte(NaN))
#' @export
stata_byte <- function(x = NULL, .size = NULL) {
    .construct_stata_numeric(x, .size, "byte")
}

#' @rdname stata_byte
#' @export
stata_int <- function(x = NULL, .size = NULL) {
    .construct_stata_numeric(x, .size, "int")
}

#' @rdname stata_byte
#' @export
stata_long <- function(x = NULL, .size = NULL) {
    .construct_stata_numeric(x, .size, "long")
}

#' @rdname stata_byte
#' @export
stata_float <- function(x = NULL, .size = NULL) {
    .construct_stata_numeric(x, .size, "float")
}

#' @rdname stata_byte
#' @export
stata_double <- function(x = NULL, .size = NULL) {
    .construct_stata_numeric(x, .size, "double")
}

#' @rdname stata_byte
#' @export
stata_storage_type <- function(x) {
    attr(x, "stata.storage", exact = TRUE)
}

.stata_storage <- c("byte", "int", "long", "float", "double")

.stata_temporal_none <- 0L
.stata_temporal_date <- 1L
.stata_temporal_datetime <- 2L

.stata_storage_class <- function(storage) {
    c("stata_numeric", paste0("stata_", storage), "vctrs_vctr", "double")
}

.compact_stata_storage_matches <- function(
    value, storage, temporal = .stata_temporal_none
) {
    .Call(
        C_dtatools_numeric_storage_matches,
        value, match(storage, .stata_storage) - 1L, temporal
    )
}

.normalize_stata_size <- function(size) {
    if (!is.numeric(size) || length(size) != 1L || is.na(size) ||
        !is.finite(size) || size < 0 || size != floor(size) ||
        size > .Machine$integer.max) {
        stop("`.size` must be one non-negative whole number", call. = FALSE)
    }
    as.integer(size)
}

.construct_stata_numeric <- function(
    x, .size, storage, temporal = .stata_temporal_none
) {
    if (!is.null(x) && !is.null(.size)) {
        stop("Supply `x` or `.size`, not both", call. = FALSE)
    }
    if (!is.null(.size)) {
        x <- rep(NA_real_, .normalize_stata_size(.size))
    } else if (is.null(x)) {
        x <- double()
    }
    if (!(typeof(x) %in% c("logical", "integer", "double")) ||
        is.factor(x) || !is.null(dim(x))) {
        stop("`x` must be a logical, integer, or double vector", call. = FALSE)
    }

    value_names <- names(x)
    values <- as.double(x)
    if (!identical(storage, "double") &&
        identical(temporal, .stata_temporal_none)) {
        result <- .Call(
            C_dtatools_construct_numeric,
            values,
            match(storage, .stata_storage) - 1L,
            temporal
        )
        attr(result, "stata.storage") <- storage
        attr(result, "class") <- .stata_storage_class(storage)
        names(result) <- value_names
        return(result)
    }
    missing_codes <- .tab_missing_codes(values)
    stata_missing <- !is.na(missing_codes) &
        (missing_codes == 0L |
         (missing_codes >= utf8ToInt("a") &
          missing_codes <= utf8ToInt("z")))
    invalid_missing <- !is.na(missing_codes) & !stata_missing
    observed <- is.na(missing_codes)
    encoded <- .encode_stata_temporal(values, observed, temporal)
    invalid_observed <- .invalid_stata_observed(encoded, observed, storage)
    if (any(invalid_missing | invalid_observed)) {
        .stop_unrepresentable_stata(
            encoded, observed, storage, any(invalid_missing)
        )
    }

    result <- if (identical(storage, "double")) {
        values
    } else {
        .Call(
            C_dtatools_construct_numeric,
            encoded,
            match(storage, .stata_storage) - 1L,
            temporal
        )
    }
    attr(result, "stata.storage") <- storage
    attr(result, "class") <- .stata_storage_class(storage)
    names(result) <- value_names
    result
}

.encode_stata_temporal <- function(values, observed, temporal) {
    if (identical(temporal, .stata_temporal_none)) return(values)

    encoded <- values
    if (identical(temporal, .stata_temporal_date)) {
        encoded[observed] <- encoded[observed] + 3653
    } else if (identical(temporal, .stata_temporal_datetime)) {
        source_values <- (encoded[observed] + 315619200) * 1000
        rounded <- round(source_values)
        decoded <- rounded / 1000 - 315619200
        snap <- is.finite(source_values) &
            decoded == encoded[observed]
        source_values[snap] <- rounded[snap]
        encoded[observed] <- source_values
    } else {
        stop("invalid Stata temporal storage type", call. = FALSE)
    }
    encoded
}

.invalid_stata_observed <- function(values, observed, storage) {
    invalid <- rep(FALSE, length(values))
    if (!any(observed)) return(invalid)
    candidate <- values[observed]
    valid <- switch(storage,
        byte = is.finite(candidate) & candidate == floor(candidate) &
            candidate >= -127 & candidate <= 100,
        int = is.finite(candidate) & candidate == floor(candidate) &
            candidate >= -32767 & candidate <= 32740,
        long = is.finite(candidate) & candidate == floor(candidate) &
            candidate >= -2147483647 & candidate <= 2147483620,
        float = is.finite(candidate) &
            abs(candidate) <= .stata_float_max,
        double = is.finite(candidate) &
            abs(candidate) <= .Machine$double.xmax / 2
    )
    invalid[observed] <- !valid
    invalid
}

.stata_float_max <- 2^126 * (2 - 2^-23)

.stop_unrepresentable_stata <- function(
    values, observed, storage, invalid_missing = FALSE
) {
    candidates <- values[observed]
    if (invalid_missing || any(!is.finite(candidates))) {
        stop(
            paste0(
                "No Stata numeric storage can represent `x`; use ",
                "`NA_real_` for system missing or `tagged_missing()` for ",
                "`.a` through `.z`"
            ),
            call. = FALSE
        )
    }
    recommendation <- switch(storage,
        byte = .wider_from_byte(candidates),
        int = .wider_from_int(candidates),
        long = if (.fits_stata_double(candidates)) "double" else NULL,
        float = if (.fits_stata_double(candidates)) "double" else NULL,
        double = NULL
    )
    if (is.null(recommendation)) {
        stop("No Stata numeric storage can represent `x`", call. = FALSE)
    }
    stop(
        sprintf(
            "Stata %s storage cannot represent `x`; use `stata_%s(x)`",
            storage, recommendation
        ),
        call. = FALSE
    )
}

.wider_from_byte <- function(values) {
    if (all(is.finite(values) & values == floor(values) &
            values >= -32767 & values <= 32740)) {
        return("int")
    }
    if (all(is.finite(values) & values == floor(values) &
            values >= -2147483647 & values <= 2147483620)) {
        return("long")
    }
    if (all(is.finite(values) & abs(values) <= .stata_float_max)) {
        return("float")
    }
    if (.fits_stata_double(values)) "double" else NULL
}

.wider_from_int <- function(values) {
    if (all(is.finite(values) & values == floor(values) &
            values >= -2147483647 & values <= 2147483620)) {
        return("long")
    }
    if (all(is.finite(values) & abs(values) <= .stata_float_max)) {
        return("float")
    }
    if (.fits_stata_double(values)) "double" else NULL
}

.fits_stata_double <- function(values) {
    all(is.finite(values) & abs(values) <= .Machine$double.xmax / 2)
}

#' @export
as.double.stata_numeric <- function(x, ...) {
    as.double(.stata_snapshot(x))
}

#' @export
as.character.stata_numeric <- function(x, ...) {
    as.character(.stata_snapshot(x), ...)
}

.stata_data <- function(x) {
    value_names <- names(x)
    value <- .metadata_view(x)
    attributes(value) <- NULL
    names(value) <- value_names
    value
}

.stata_snapshot <- function(x) {
    value_names <- names(x)
    value <- .metadata_copy(x)
    attributes(value) <- NULL
    names(value) <- value_names
    value
}

.stata_promote <- function(left, right) {
    if (identical(left, right)) return(left)
    pair <- sort(c(left, right))
    key <- paste(pair, collapse = ":")
    switch(key,
        "byte:int" = "int",
        "byte:long" = "long",
        "byte:float" = "float",
        "byte:double" = "double",
        "int:long" = "long",
        "float:int" = "float",
        "double:int" = "double",
        "float:long" = "double",
        "double:long" = "double",
        "double:float" = "double",
        stop("unknown Stata storage type combination", call. = FALSE)
    )
}

.stata_classes_from <- function(prototype, storage) {
    classes <- class(prototype)
    storage_classes <- paste0("stata_", .stata_storage)
    location <- classes %in% storage_classes
    if (any(location)) {
        classes[location] <- paste0("stata_", storage)
        return(classes)
    }
    .stata_storage_class(storage)
}

.replace_stata_attributes <- function(value, desired) {
    value <- .metadata_copy(value)
    for (name in names(attributes(value))) attr(value, name) <- NULL
    for (name in names(desired)) attr(value, name) <- desired[[name]]
    value
}

.stata_attribute_plan <- function(
    prototype, storage, result_names = NULL,
    temporal = inherits(prototype, "stata_temporal"), labelled = FALSE
) {
    desired <- attributes(prototype)
    desired$names <- NULL
    desired$stata.storage <- storage
    classes <- if (temporal) {
        class(prototype)
    } else {
        .stata_classes_from(prototype, storage)
    }
    if (labelled && !temporal && !is.null(desired$labels) &&
        !"haven_labelled" %in% classes) {
        location <- match("vctrs_vctr", classes)
        classes <- append(classes, "haven_labelled", after = location - 1L)
    }
    desired$class <- classes
    if (!is.null(result_names)) desired$names <- result_names
    desired
}

.restore_stata_metadata <- function(value, prototype, storage) {
    desired <- .stata_attribute_plan(
        prototype, storage, result_names = names(value), temporal = FALSE
    )
    plain_attributes <- desired
    plain_attributes$names <- NULL
    plain_attributes$class <- NULL
    plain_attributes$stata.storage <- NULL
    if (length(plain_attributes) == 0L &&
        identical(stata_storage_type(value), storage) &&
        identical(class(value), desired$class)) {
        return(value)
    }
    .replace_stata_attributes(value, desired)
}

.stata_ptype <- function(storage, prototype) {
    .restore_stata_metadata(
        .construct_stata_numeric(double(), NULL, storage),
        prototype,
        storage
    )
}

.stata_value_label_keys <- function(labels) {
    if (is.null(labels)) return(character())

    missing_codes <- .tab_missing_codes(labels)
    observed <- is.na(missing_codes)
    keys <- character(length(labels))
    keys[observed] <- paste0("number:", format(
        labels[observed], scientific = FALSE, trim = TRUE
    ))
    keys[!observed] <- paste0("missing:", missing_codes[!observed])
    keys
}

.stata_combine_value_labels <- function(
    x_labels, y_labels, x_arg = "", y_arg = ""
) {
    if (is.null(x_labels)) return(y_labels)
    if (is.null(y_labels)) return(x_labels)

    x_keys <- .stata_value_label_keys(x_labels)
    y_keys <- .stata_value_label_keys(y_labels)
    shared <- match(y_keys, x_keys, nomatch = 0L)
    conflicts <- shared > 0L &
        names(y_labels) != names(x_labels)[pmax(shared, 1L)]
    if (any(conflicts)) {
        left <- if (nzchar(x_arg)) paste0("`", x_arg, "`") else "left input"
        right <- if (nzchar(y_arg)) paste0("`", y_arg, "`") else "right input"
        warning(
            sprintf(
                "%s and %s have conflicting value labels; labels from %s win",
                left, right, left
            ),
            call. = FALSE
        )
    }
    c(x_labels, y_labels[shared == 0L])
}

.reconcile_stata_metadata <- function(
    result, x, y, x_arg = "", y_arg = ""
) {
    labels <- .stata_combine_value_labels(
        attr(x, "labels", exact = TRUE),
        attr(y, "labels", exact = TRUE),
        x_arg,
        y_arg
    )
    variable_label <- attr(x, "label", exact = TRUE)
    if (is.null(variable_label)) {
        variable_label <- attr(y, "label", exact = TRUE)
    }

    result <- .metadata_copy(result)
    attr(result, "labels") <- labels
    attr(result, "label") <- variable_label
    .apply_haven_labelled_class(result, !is.null(labels))
}

.stata_common_ptype <- function(
    x, y, storage, prototype, x_arg = "", y_arg = ""
) {
    .reconcile_stata_metadata(
        .stata_ptype(storage, prototype),
        x,
        y,
        x_arg,
        y_arg
    )
}

#' @export
vec_proxy.stata_numeric <- function(x, ...) {
    .stata_snapshot(x)
}

#' @export
as.data.frame.stata_numeric <- function(
    x, row.names = NULL, optional = FALSE, ...,
    nm = paste(deparse(substitute(x), width.cutoff = 500L), collapse = " ")
) {
    force(nm)
    if (!is.null(dim(x))) return(NextMethod())
    nrows <- length(x)
    if (is.null(row.names)) {
        if (nrows == 0L) {
            row.names <- character()
        } else if (length(row.names <- names(x)) != nrows ||
                   anyDuplicated(row.names)) {
            row.names <- .set_row_names(nrows)
        }
    } else if (!(is.character(row.names) || is.integer(row.names)) ||
               length(row.names) != nrows) {
        stop(sprintf(
            "'row.names' is not a character or integer vector of length %s",
            nrows
        ), call. = FALSE)
    }
    column <- x
    if (!is.null(names(column))) names(column) <- NULL
    columns <- list(column)
    if (!optional) names(columns) <- nm
    vctrs::new_data_frame(columns, n = nrows, row.names = row.names)
}

#' @export
vec_restore.stata_numeric <- function(x, to, ...) {
    storage <- stata_storage_type(to)
    if (.compact_stata_storage_matches(x, storage)) {
        return(.restore_stata_metadata(x, to, storage))
    }
    value <- .construct_stata_numeric(x, NULL, storage)
    .restore_stata_metadata(value, to, storage)
}

#' @export
vec_ptype2.stata_numeric.stata_numeric <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    left <- stata_storage_type(x)
    right <- stata_storage_type(y)
    storage <- .stata_promote(left, right)
    prototype <- if (identical(storage, right)) y else x
    .stata_common_ptype(
        x, y, storage, prototype, x_arg = x_arg, y_arg = y_arg
    )
}

#' @export
vec_ptype2.stata_numeric.double <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    .stata_ptype(stata_storage_type(x), x)
}

#' @export
vec_ptype2.double.stata_numeric <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    .stata_ptype(stata_storage_type(y), y)
}

#' @export
vec_ptype2.stata_numeric.integer <- vec_ptype2.stata_numeric.double

#' @export
vec_ptype2.integer.stata_numeric <- vec_ptype2.double.stata_numeric

#' @export
vec_ptype2.stata_numeric.logical <- vec_ptype2.stata_numeric.double

#' @export
vec_ptype2.logical.stata_numeric <- vec_ptype2.double.stata_numeric

.cast_to_stata <- function(x, to) {
    storage <- stata_storage_type(to)
    value <- .construct_stata_numeric(x, NULL, storage)
    .restore_stata_metadata(value, to, storage)
}

#' @export
vec_cast.stata_numeric.stata_numeric <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    .cast_to_stata(x, to)
}

#' @export
vec_cast.stata_numeric.double <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    .cast_to_stata(x, to)
}

#' @export
vec_cast.stata_numeric.integer <- vec_cast.stata_numeric.double

#' @export
vec_cast.stata_numeric.logical <- vec_cast.stata_numeric.double

#' @export
vec_cast.double.stata_numeric <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    as.double(x)
}

.stata_subscript_extends <- function(x, i) {
    size <- length(x)
    if (is.character(i)) {
        existing <- names(x)
        if (is.null(existing)) existing <- character()
        return(any(!is.na(i) & !(i %in% existing)))
    }
    if (is.logical(i)) {
        if (length(i) <= size) return(FALSE)
        return(any(i[seq.int(size + 1L, length(i))], na.rm = TRUE))
    }
    if (is.numeric(i)) {
        return(any(trunc(i) > size, na.rm = TRUE))
    }
    FALSE
}

.extend_stata_numeric <- function(x, i, value, scalar = FALSE) {
    prototype <- if (inherits(value, "stata_numeric")) {
        vctrs::vec_ptype2(x, value)
    } else {
        vctrs::vec_ptype(x)
    }
    data <- .stata_data(x)
    replacement <- .stata_data(vctrs::vec_cast(value, prototype))
    if (scalar) data[[i]] <- replacement else data[i] <- replacement
    vctrs::vec_restore(data, prototype)
}

#' @export
`[<-.stata_numeric` <- function(x, i, ..., value) {
    if (missing(i)) i <- rep(TRUE, length(x))
    if (length(list(...)) > 0L) {
        stop("Stata numeric vectors do not support array subscripts",
             call. = FALSE)
    }
    if (.stata_subscript_extends(x, i)) {
        return(.extend_stata_numeric(x, i, value))
    }
    vctrs::vec_assign(x, i, value)
}

#' @export
`[[<-.stata_numeric` <- function(x, i, ..., value) {
    if (length(list(...)) > 0L) {
        stop("Stata numeric vectors do not support array subscripts",
             call. = FALSE)
    }
    if (.stata_subscript_extends(x, i)) {
        return(.extend_stata_numeric(x, i, value, scalar = TRUE))
    }
    vctrs::vec_assign(x, i, value)
}

.stata_storage_candidates <- function(minimum) {
    switch(minimum,
        byte = c("byte", "int", "long", "float", "double"),
        int = c("int", "long", "float", "double"),
        long = c("long", "double"),
        float = c("float", "double"),
        double = "double"
    )
}

.stata_computed <- function(
    result, minimum, temporal = .stata_temporal_none
) {
    if (typeof(result) == "logical" || typeof(result) == "complex") {
        return(result)
    }
    values <- as.double(result)
    names(values) <- names(result)
    missing_codes <- .tab_missing_codes(values)
    computational_nan <- !is.na(missing_codes) & missing_codes == 256L
    values[computational_nan | is.infinite(values)] <- NA_real_

    missing_codes <- .tab_missing_codes(values)
    observed <- is.na(missing_codes)
    encoded <- .encode_stata_temporal(values, observed, temporal)
    outside_double <- observed &
        (!is.finite(encoded) |
         abs(encoded) > .Machine$double.xmax / 2)
    if (any(outside_double)) {
        values[outside_double] <- NA_real_
        missing_codes <- .tab_missing_codes(values)
        observed <- is.na(missing_codes)
        encoded <- .encode_stata_temporal(values, observed, temporal)
    }
    for (storage in .stata_storage_candidates(minimum)) {
        if (!any(.invalid_stata_observed(encoded, observed, storage))) {
            return(.construct_stata_numeric(
                values, NULL, storage, temporal = temporal
            ))
        }
    }
    stop("computed values cannot be represented in Stata numeric storage",
         call. = FALSE)
}

.stata_arith_base <- function(op, x, y, minimum) {
    left <- if (inherits(x, "stata_numeric")) .stata_data(x) else x
    right <- if (inherits(y, "stata_numeric")) .stata_data(y) else y
    args <- vctrs::vec_recycle_common(left, right)
    operation <- getExportedValue("base", op)
    result <- suppressWarnings(operation(args[[1L]], args[[2L]]))
    .stata_computed(result, minimum)
}

#' @export
vec_arith.stata_numeric <- function(op, x, y, ...) {
    UseMethod("vec_arith.stata_numeric", y)
}

#' @export
vec_arith.stata_numeric.MISSING <- function(op, x, y, ...) {
    if (identical(op, "+")) return(x)
    if (identical(op, "!")) return(!.stata_data(x))
    if (!identical(op, "-")) vctrs::stop_incompatible_op(op, x, y)
    result <- suppressWarnings(-.stata_data(x))
    .stata_computed(result, stata_storage_type(x))
}

#' @export
vec_arith.stata_numeric.stata_numeric <- function(op, x, y, ...) {
    minimum <- .stata_promote(
        stata_storage_type(x), stata_storage_type(y)
    )
    .stata_arith_base(op, x, y, minimum)
}

#' @export
vec_arith.stata_numeric.numeric <- function(op, x, y, ...) {
    .stata_arith_base(op, x, y, stata_storage_type(x))
}

#' @export
vec_arith.numeric.stata_numeric <- function(op, x, y, ...) {
    .stata_arith_base(op, x, y, stata_storage_type(y))
}

#' @export
vec_arith.stata_numeric.logical <- vec_arith.stata_numeric.numeric

#' @export
vec_arith.logical.stata_numeric <- vec_arith.numeric.stata_numeric

#' @export
vec_arith.stata_numeric.default <- function(op, x, y, ...) {
    vctrs::stop_incompatible_op(op, x, y)
}

#' @export
vec_math.stata_numeric <- function(.fn, .x, ...) {
    operation <- getExportedValue("base", .fn)
    result <- suppressWarnings(operation(.stata_data(.x), ...))
    if (length(.x) == 0L && .fn %in% c("min", "max", "range")) {
        return(result)
    }
    .stata_computed(result, stata_storage_type(.x))
}

#' @export
Math.stata_numeric <- function(x, ...) {
    vec_math.stata_numeric(.Generic, x, ...)
}

#' @export
Summary.stata_numeric <- function(..., na.rm = FALSE) {
    inputs <- list(...)
    declared <- Filter(
        function(value) inherits(value, "stata_numeric"), inputs
    )
    storage <- vapply(declared, stata_storage_type, character(1))
    minimum <- Reduce(.stata_promote, storage)
    operation <- getExportedValue("base", .Generic)
    arguments <- c(lapply(inputs, function(value) {
        if (inherits(value, "stata_numeric")) .stata_data(value) else value
    }), list(na.rm = na.rm))
    empty_extreme <- sum(lengths(inputs)) == 0L &&
        .Generic %in% c("min", "max", "range")
    result <- if (empty_extreme) {
        do.call(operation, arguments)
    } else {
        suppressWarnings(do.call(operation, arguments))
    }
    if (empty_extreme) {
        return(result)
    }
    .stata_computed(result, minimum)
}

#' @export
mean.stata_numeric <- function(x, ..., na.rm = FALSE) {
    result <- suppressWarnings(mean(.stata_data(x), ..., na.rm = na.rm))
    .stata_computed(result, stata_storage_type(x))
}

#' @export
median.stata_numeric <- function(x, na.rm = FALSE, ...) {
    result <- suppressWarnings(stats::median(
        .stata_data(x), na.rm = na.rm, ...
    ))
    .stata_computed(result, stata_storage_type(x))
}

#' @export
quantile.stata_numeric <- function(
    x, probs = seq(0, 1, 0.25), na.rm = FALSE, names = TRUE,
    type = 7, ...
) {
    result <- suppressWarnings(stats::quantile(
        .stata_data(x), probs = probs, na.rm = na.rm, names = names,
        type = type, ...
    ))
    .stata_computed(result, stata_storage_type(x))
}

#' @export
anyNA.stata_numeric <- function(x, recursive = FALSE) {
    anyNA(.stata_data(x), recursive = recursive)
}

#' @export
Complex.stata_numeric <- function(z) {
    operation <- getExportedValue("base", .Generic)
    result <- suppressWarnings(operation(.stata_data(z)))
    .stata_computed(result, stata_storage_type(z))
}

.stata_temporal_kind <- function(x) {
    if (inherits(x, "stata_date")) "date" else "datetime"
}

.stata_temporal_code <- function(x) {
    if (identical(.stata_temporal_kind(x), "date")) {
        .stata_temporal_date
    } else {
        .stata_temporal_datetime
    }
}

.base_stata_temporal <- function(x) {
    value <- .metadata_view(x)
    classes <- class(value)
    classes <- classes[!classes %in% c(
        "stata_temporal", "stata_date", "stata_datetime"
    )]
    attr(value, "stata.storage") <- NULL
    attr(value, "class") <- classes
    value
}

.attach_stata_temporal <- function(
    result, prototype, storage, result_names = names(result)
) {
    desired <- .stata_attribute_plan(
        prototype, storage, result_names = result_names, temporal = TRUE
    )
    .replace_stata_attributes(result, desired)
}

.restore_stata_temporal <- function(value, prototype, storage) {
    if (.compact_stata_storage_matches(
        value, storage, .stata_temporal_code(prototype)
    )) {
        return(.attach_stata_temporal(value, prototype, storage))
    }
    result <- .construct_stata_numeric(
        as.double(value), NULL, storage,
        temporal = .stata_temporal_code(prototype)
    )
    .attach_stata_temporal(
        result, prototype, storage, result_names = names(value)
    )
}

.computed_stata_temporal <- function(value, prototype, minimum) {
    result <- .stata_computed(
        as.double(value), minimum,
        temporal = .stata_temporal_code(prototype)
    )
    .attach_stata_temporal(
        result, prototype, stata_storage_type(result),
        result_names = names(value)
    )
}

.stata_temporal_ptype <- function(storage, prototype) {
    .restore_stata_temporal(double(), prototype, storage)
}

#' @export
vec_proxy.stata_temporal <- function(x, ...) {
    .stata_snapshot(x)
}

#' @export
vec_restore.stata_temporal <- function(x, to, ...) {
    .restore_stata_temporal(x, to, stata_storage_type(to))
}

.extend_stata_temporal <- function(x, i, value, scalar = FALSE) {
    prototype <- if (inherits(value, "stata_temporal")) {
        vctrs::vec_ptype2(x, value)
    } else {
        vctrs::vec_ptype(x)
    }
    data <- .base_stata_temporal(x)
    replacement <- .base_stata_temporal(
        vctrs::vec_cast(value, prototype)
    )
    if (scalar) data[[i]] <- replacement else data[i] <- replacement
    vctrs::vec_restore(data, prototype)
}

#' @export
`[.stata_temporal` <- function(x, i, ..., drop = TRUE) {
    if (length(list(...)) > 0L) {
        stop("Stata temporal vectors do not support array subscripts",
             call. = FALSE)
    }
    data <- .base_stata_temporal(x)
    result <- if (missing(i)) data[] else data[i]
    .restore_stata_temporal(result, x, stata_storage_type(x))
}

#' @export
`[[.stata_temporal` <- function(x, i, ...) {
    if (length(list(...)) > 0L) {
        stop("Stata temporal vectors do not support array subscripts",
             call. = FALSE)
    }
    result <- .base_stata_temporal(x)[[i]]
    .restore_stata_temporal(result, x, stata_storage_type(x))
}

#' @export
`[<-.stata_temporal` <- function(x, i, ..., value) {
    if (length(list(...)) > 0L) {
        stop("Stata temporal vectors do not support array subscripts",
             call. = FALSE)
    }
    if (!missing(i) && .stata_subscript_extends(x, i)) {
        return(.extend_stata_temporal(x, i, value))
    }
    data <- .base_stata_temporal(x)
    replacement <- if (inherits(value, "stata_temporal")) {
        .base_stata_temporal(value)
    } else {
        value
    }
    if (missing(i)) data[] <- replacement else data[i] <- replacement
    .restore_stata_temporal(data, x, stata_storage_type(x))
}

#' @export
`[[<-.stata_temporal` <- function(x, i, ..., value) {
    if (length(list(...)) > 0L) {
        stop("Stata temporal vectors do not support array subscripts",
             call. = FALSE)
    }
    if (.stata_subscript_extends(x, i)) {
        return(.extend_stata_temporal(x, i, value, scalar = TRUE))
    }
    data <- .base_stata_temporal(x)
    replacement <- if (inherits(value, "stata_temporal")) {
        .base_stata_temporal(value)
    } else {
        value
    }
    data[[i]] <- replacement
    .restore_stata_temporal(data, x, stata_storage_type(x))
}

#' @export
vec_ptype2.stata_temporal.stata_temporal <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    if (!identical(.stata_temporal_kind(x), .stata_temporal_kind(y))) {
        vctrs::stop_incompatible_type(x, y, x_arg = x_arg, y_arg = y_arg)
    }
    storage <- .stata_promote(
        stata_storage_type(x), stata_storage_type(y)
    )
    prototype <- if (identical(storage, stata_storage_type(y))) y else x
    .reconcile_stata_metadata(
        .stata_temporal_ptype(storage, prototype),
        x,
        y,
        x_arg,
        y_arg
    )
}

#' @export
vec_ptype2.stata_temporal.logical <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    .stata_temporal_ptype(stata_storage_type(x), x)
}

#' @export
vec_ptype2.logical.stata_temporal <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    .stata_temporal_ptype(stata_storage_type(y), y)
}

.stata_temporal_ptype2_base <- function(
    typed, base_kind, x, y, x_arg, y_arg
) {
    if (!identical(.stata_temporal_kind(typed), base_kind)) {
        vctrs::stop_incompatible_type(x, y, x_arg = x_arg, y_arg = y_arg)
    }
    .stata_temporal_ptype(stata_storage_type(typed), typed)
}

#' @export
vec_ptype2.stata_temporal.Date <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    .stata_temporal_ptype2_base(x, "date", x, y, x_arg, y_arg)
}

#' @export
vec_ptype2.Date.stata_temporal <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    .stata_temporal_ptype2_base(y, "date", x, y, x_arg, y_arg)
}

#' @export
vec_ptype2.stata_temporal.POSIXct <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    .stata_temporal_ptype2_base(x, "datetime", x, y, x_arg, y_arg)
}

#' @export
vec_ptype2.POSIXct.stata_temporal <- function(
    x, y, ..., x_arg = "", y_arg = ""
) {
    .stata_temporal_ptype2_base(y, "datetime", x, y, x_arg, y_arg)
}

#' @export
vec_cast.stata_temporal.stata_temporal <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    if (!identical(.stata_temporal_kind(x), .stata_temporal_kind(to))) {
        vctrs::stop_incompatible_cast(
            x, to, x_arg = x_arg, to_arg = to_arg, call = call
        )
    }
    .restore_stata_temporal(x, to, stata_storage_type(to))
}

#' @export
vec_cast.stata_temporal.logical <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    if (any(!is.na(x))) {
        vctrs::stop_incompatible_cast(
            x, to, x_arg = x_arg, to_arg = to_arg, call = call
        )
    }
    .restore_stata_temporal(as.double(x), to, stata_storage_type(to))
}

.cast_base_to_stata_temporal <- function(
    x, to, kind, x_arg, to_arg, call
) {
    if (!identical(.stata_temporal_kind(to), kind)) {
        vctrs::stop_incompatible_cast(
            x, to, x_arg = x_arg, to_arg = to_arg, call = call
        )
    }
    .restore_stata_temporal(x, to, stata_storage_type(to))
}

#' @export
vec_cast.stata_temporal.Date <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    .cast_base_to_stata_temporal(
        x, to, "date", x_arg, to_arg, call
    )
}

#' @export
vec_cast.stata_temporal.POSIXct <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    .cast_base_to_stata_temporal(
        x, to, "datetime", x_arg, to_arg, call
    )
}

#' @export
vec_cast.Date.stata_temporal <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    if (!identical(.stata_temporal_kind(x), "date")) {
        vctrs::stop_incompatible_cast(
            x, to, x_arg = x_arg, to_arg = to_arg, call = call
        )
    }
    vctrs::vec_restore(as.double(x), to)
}

#' @export
vec_cast.POSIXct.stata_temporal <- function(
    x, to, ..., x_arg = "", to_arg = "", call = rlang::caller_env()
) {
    if (!identical(.stata_temporal_kind(x), "datetime")) {
        vctrs::stop_incompatible_cast(
            x, to, x_arg = x_arg, to_arg = to_arg, call = call
        )
    }
    vctrs::vec_restore(as.double(x), to)
}

.stata_temporal_minimum <- function(inputs) {
    .validate_stata_temporal_kinds(inputs)
    declared <- Filter(
        function(value) inherits(value, "stata_temporal"), inputs
    )
    Reduce(
        .stata_promote,
        vapply(declared, stata_storage_type, character(1))
    )
}

.temporal_kind_or_missing <- function(value) {
    if (inherits(value, "stata_temporal")) {
        return(.stata_temporal_kind(value))
    }
    if (inherits(value, "Date")) return("date")
    if (inherits(value, "POSIXct")) return("datetime")
    NA_character_
}

.validate_stata_temporal_kinds <- function(inputs) {
    kinds <- vapply(inputs, .temporal_kind_or_missing, character(1))
    temporal <- which(!is.na(kinds))
    if (length(temporal) < 2L) return(invisible(NULL))

    different <- temporal[kinds[temporal] != kinds[temporal[[1L]]]]
    if (length(different) > 0L) {
        right <- different[[1L]]
        vctrs::stop_incompatible_type(
            inputs[[temporal[[1L]]]],
            inputs[[right]],
            x_arg = paste0("..", temporal[[1L]]),
            y_arg = paste0("..", right)
        )
    }
    invisible(NULL)
}

#' @export
Summary.stata_temporal <- function(..., na.rm = FALSE) {
    inputs <- list(...)
    minimum <- .stata_temporal_minimum(inputs)
    prototype <- Filter(
        function(value) inherits(value, "stata_temporal"), inputs
    )[[1L]]
    arguments <- c(lapply(inputs, function(value) {
        if (inherits(value, "stata_temporal")) {
            .base_stata_temporal(value)
        } else {
            value
        }
    }), list(na.rm = na.rm))
    result <- do.call(getExportedValue("base", .Generic), arguments)
    if (!(inherits(result, "Date") || inherits(result, "POSIXct"))) {
        return(result)
    }
    empty_extreme <- sum(lengths(inputs)) == 0L &&
        .Generic %in% c("min", "max", "range")
    if (empty_extreme) return(result)
    .computed_stata_temporal(result, prototype, minimum)
}

#' @export
mean.stata_temporal <- function(x, ..., na.rm = FALSE) {
    result <- mean(.base_stata_temporal(x), ..., na.rm = na.rm)
    .computed_stata_temporal(result, x, stata_storage_type(x))
}

#' @export
c.stata_temporal <- function(..., recursive = FALSE) {
    inputs <- list(...)
    minimum <- .stata_temporal_minimum(inputs)
    prototype <- Filter(
        function(value) inherits(value, "stata_temporal"), inputs
    )[[1L]]
    arguments <- c(lapply(inputs, function(value) {
        if (inherits(value, "stata_temporal")) {
            .base_stata_temporal(value)
        } else {
            value
        }
    }), list(recursive = recursive))
    result <- do.call(base::c, arguments)
    .restore_stata_temporal(result, prototype, minimum)
}

#' @export
rep.stata_temporal <- function(x, ...) {
    result <- rep(.base_stata_temporal(x), ...)
    .restore_stata_temporal(result, x, stata_storage_type(x))
}

.stata_temporal_op <- function(op, e1, e2) {
    left <- if (inherits(e1, "stata_temporal")) {
        .base_stata_temporal(e1)
    } else {
        e1
    }
    unary <- missing(e2)
    if (!unary) {
        right <- if (inherits(e2, "stata_temporal")) {
            .base_stata_temporal(e2)
        } else {
            e2
        }
    }
    operation <- getExportedValue("base", op)
    result <- if (unary) operation(left) else operation(left, right)
    if (!(inherits(result, "Date") || inherits(result, "POSIXct"))) {
        return(result)
    }
    prototype <- if (inherits(e1, "stata_temporal")) e1 else e2
    .computed_stata_temporal(
        result, prototype, stata_storage_type(prototype)
    )
}

#' @export
`+.stata_temporal` <- function(e1, e2) {
    if (missing(e2)) .stata_temporal_op("+", e1) else
        .stata_temporal_op("+", e1, e2)
}

#' @export
`-.stata_temporal` <- function(e1, e2) {
    if (missing(e2)) .stata_temporal_op("-", e1) else
        .stata_temporal_op("-", e1, e2)
}

#' @export
`==.stata_temporal` <- function(e1, e2) .stata_temporal_op("==", e1, e2)

#' @export
`!=.stata_temporal` <- function(e1, e2) .stata_temporal_op("!=", e1, e2)

#' @export
`<.stata_temporal` <- function(e1, e2) .stata_temporal_op("<", e1, e2)

#' @export
`<=.stata_temporal` <- function(e1, e2) .stata_temporal_op("<=", e1, e2)

#' @export
`>.stata_temporal` <- function(e1, e2) .stata_temporal_op(">", e1, e2)

#' @export
`>=.stata_temporal` <- function(e1, e2) .stata_temporal_op(">=", e1, e2)
