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
#'
#' Re-encoding materializes `x` as doubles while it validates the values. The
#' compact representation reduces steady-state memory use, not peak memory use
#' during construction.
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

.stata_storage_class <- function(storage) {
    c("stata_numeric", paste0("stata_", storage), "vctrs_vctr", "double")
}

.normalize_stata_size <- function(size) {
    if (!is.numeric(size) || length(size) != 1L || is.na(size) ||
        !is.finite(size) || size < 0 || size != floor(size) ||
        size > .Machine$integer.max) {
        stop("`.size` must be one non-negative whole number", call. = FALSE)
    }
    as.integer(size)
}

.construct_stata_numeric <- function(x, .size, storage) {
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
    missing_codes <- .tab_missing_codes(values)
    stata_missing <- !is.na(missing_codes) &
        (missing_codes == 0L |
         (missing_codes >= utf8ToInt("a") &
          missing_codes <= utf8ToInt("z")))
    invalid_missing <- !is.na(missing_codes) & !stata_missing
    observed <- is.na(missing_codes)
    invalid_observed <- .invalid_stata_observed(values, observed, storage)
    if (any(invalid_missing | invalid_observed)) {
        .stop_unrepresentable_stata(values, observed, storage)
    }

    result <- if (identical(storage, "double")) {
        values
    } else {
        .Call(
            C_dtaparser_construct_numeric,
            values,
            match(storage, .stata_storage) - 1L
        )
    }
    attr(result, "stata.storage") <- storage
    attr(result, "class") <- .stata_storage_class(storage)
    names(result) <- value_names
    result
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

.stop_unrepresentable_stata <- function(values, observed, storage) {
    recommendation <- switch(storage,
        byte = .wider_from_byte(values[observed]),
        int = .wider_from_int(values[observed]),
        long = "double",
        float = "double",
        double = NULL
    )
    if (is.null(recommendation)) {
        stop("Stata double storage cannot represent `x`", call. = FALSE)
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
    "double"
}

.wider_from_int <- function(values) {
    if (all(is.finite(values) & values == floor(values) &
            values >= -2147483647 & values <= 2147483620)) {
        return("long")
    }
    if (all(is.finite(values) & abs(values) <= .stata_float_max)) {
        return("float")
    }
    "double"
}

#' @export
as.double.stata_numeric <- function(x, ...) {
    as.double(.stata_data(x))
}

#' @export
as.character.stata_numeric <- function(x, ...) {
    as.character(.stata_data(x), ...)
}

.stata_data <- function(x) {
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

.restore_stata_metadata <- function(value, prototype, storage) {
    classes <- .stata_classes_from(prototype, storage)
    desired <- attributes(prototype)
    result_names <- names(value)
    desired$names <- NULL
    desired$stata.storage <- storage
    desired$class <- classes
    if (!is.null(result_names)) desired$names <- result_names
    plain_attributes <- desired
    plain_attributes$names <- NULL
    plain_attributes$class <- NULL
    plain_attributes$stata.storage <- NULL
    if (length(plain_attributes) == 0L &&
        identical(stata_storage_type(value), storage) &&
        identical(class(value), classes)) {
        return(value)
    }
    value <- .metadata_copy(value)
    attributes(value) <- NULL
    for (name in names(desired)) attr(value, name) <- desired[[name]]
    value
}

.stata_ptype <- function(storage, prototype) {
    .restore_stata_metadata(
        .construct_stata_numeric(double(), NULL, storage),
        prototype,
        storage
    )
}

#' @export
vec_proxy.stata_numeric <- function(x, ...) {
    .stata_data(x)
}

#' @export
vec_restore.stata_numeric <- function(x, to, ...) {
    storage <- stata_storage_type(to)
    value <- .construct_stata_numeric(as.double(x), NULL, storage)
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
    .stata_ptype(storage, prototype)
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
    value <- .construct_stata_numeric(as.double(x), NULL, storage)
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

#' @export
`[<-.stata_numeric` <- function(x, i, ..., value) {
    if (missing(i)) i <- rep(TRUE, length(x))
    if (length(list(...)) > 0L) {
        stop("Stata numeric vectors do not support array subscripts",
             call. = FALSE)
    }
    vctrs::vec_assign(x, i, value)
}

#' @export
`[[<-.stata_numeric` <- function(x, i, ..., value) {
    if (length(list(...)) > 0L) {
        stop("Stata numeric vectors do not support array subscripts",
             call. = FALSE)
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

.stata_computed <- function(result, minimum) {
    if (typeof(result) == "logical" || typeof(result) == "complex") {
        return(result)
    }
    values <- as.double(result)
    names(values) <- names(result)
    missing_codes <- .tab_missing_codes(values)
    computational_nan <- !is.na(missing_codes) & missing_codes == 256L
    values[computational_nan | is.infinite(values)] <- NA_real_

    observed <- is.na(.tab_missing_codes(values))
    for (storage in .stata_storage_candidates(minimum)) {
        if (!any(.invalid_stata_observed(values, observed, storage))) {
            return(.construct_stata_numeric(values, NULL, storage))
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
    storage <- vapply(inputs, stata_storage_type, character(1))
    minimum <- Reduce(.stata_promote, storage)
    operation <- getExportedValue("base", .Generic)
    arguments <- c(lapply(inputs, .stata_data), list(na.rm = na.rm))
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

.stata_temporal_kind <- function(x) {
    if (inherits(x, "stata_date")) "date" else "datetime"
}

.base_stata_temporal <- function(x) {
    value <- .metadata_copy(x)
    classes <- class(value)
    classes <- classes[!classes %in% c(
        "stata_temporal", "stata_date", "stata_datetime"
    )]
    attr(value, "stata.storage") <- NULL
    attr(value, "class") <- classes
    value
}

.restore_stata_temporal <- function(value, prototype, storage) {
    result <- .construct_stata_numeric(as.double(value), NULL, storage)
    desired <- attributes(prototype)
    result_names <- names(value)
    desired$names <- NULL
    desired$stata.storage <- storage
    desired$class <- class(prototype)
    if (!is.null(result_names)) desired$names <- result_names
    result <- .metadata_copy(result)
    attributes(result) <- NULL
    for (name in names(desired)) attr(result, name) <- desired[[name]]
    result
}

.stata_temporal_ptype <- function(storage, prototype) {
    .restore_stata_temporal(double(), prototype, storage)
}

#' @export
vec_proxy.stata_temporal <- function(x, ...) {
    .stata_data(x)
}

#' @export
vec_restore.stata_temporal <- function(x, to, ...) {
    .restore_stata_temporal(x, to, stata_storage_type(to))
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
    .stata_temporal_ptype(storage, prototype)
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
    typed <- .stata_computed(
        as.double(result), stata_storage_type(prototype)
    )
    .restore_stata_temporal(
        typed, prototype, stata_storage_type(typed)
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
