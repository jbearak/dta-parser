#' Summarize variables using Stata's statistics
#'
#' @name summ
#' @export
summ <- function(x, ..., data = NULL, where = NULL, rows = NULL,
                 by = NULL, weights = NULL,
                 weight = c("aweight", "fweight", "iweight"),
                 detail = FALSE, meanonly = FALSE, format = FALSE,
                 separator = 5, vsquish = FALSE, noemptycells = FALSE,
                 baselevels = FALSE, allbaselevels = FALSE,
                 nofvlabel = FALSE, fvwrap = 1,
                 fvwrapon = c("word", "width"), time = NULL,
                 panel = NULL, delta = 1) {
    caller <- rlang::caller_env()
    x_quo <- if (missing(x)) NULL else rlang::enquo(x)
    dots <- rlang::enquos(...)
    flags <- list(detail = detail, meanonly = meanonly, format = format,
                  vsquish = vsquish, noemptycells = noemptycells,
                  baselevels = baselevels, allbaselevels = allbaselevels,
                  nofvlabel = nofvlabel)
    for (name in names(flags)) .dta_group_flag(flags[[name]], name)
    for (name in c("separator", "fvwrap")) {
        value <- get(name)
        if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
            !is.finite(value) || value != floor(value))
            stop(sprintf("`%s` must be an integer", name), call. = FALSE)
    }
    separator <- abs(separator)
    if (detail && meanonly)
        stop("`detail` and `meanonly` may not be combined", call. = FALSE)
    if (detail && (vsquish || noemptycells || baselevels || allbaselevels ||
        nofvlabel || !missing(fvwrap) || !missing(fvwrapon)))
        stop("factor display options are not allowed with `detail`", call. = FALSE)
    weight <- match.arg(weight)
    fvwrapon <- match.arg(fvwrapon)
    weight_quo <- rlang::enquo(weights)
    weighted <- !rlang::quo_is_null(weight_quo)
    if (weighted && weight == "iweight" && detail)
        stop("iweights are not allowed with `detail`", call. = FALSE)
    inputs <- .summarize_inputs(x_quo, dots, data, caller)
    data <- inputs$data
    columns <- as.list(data)
    n <- nrow(data)
    positions <- .egen_positions(rows)
    by_quo <- rlang::enquo(by)
    group_columns <- columns
    if (!rlang::quo_is_null(by_quo) && !inherits(data, "grouped_df")) {
        group_names <- .mutation_group_names(by_quo, columns, "by")
        for (name in group_names) {
            key <- columns[[name]]
            # Bare and haven-compatible vectors need the same missing-code
            # grouping that Stata columns provide through their vctrs proxy.
            if (typeof(key) == "double" && any(is_tagged_missing(key)))
                group_columns[[name]] <- dta_double(as.double(unclass(key)))
            if (is.character(key) && anyNA(key)) {
                key <- as.character(key)
                key[is.na(key)] <- ""
                group_columns[[name]] <- key
            }
        }
    }
    groups <- .assignment_groups(data, list(columns = group_columns, nrow = n),
        by_quo, NULL, inherits(data, "grouped_df"))
    if (!is.null(groups) && !inherits(data, "grouped_df")) {
        first <- vapply(groups$rows, `[[`, integer(1), 1L)
        groups$keys <- vctrs::new_data_frame(lapply(columns[names(groups$keys)],
            function(key) {
                key <- key[first]
                if (is.character(key)) key[is.na(key)] <- ""
                key
            }), n = length(first))
    }
    if (inherits(data, "rowwise_df"))
        stop("`summ()` does not accept rowwise data", call. = FALSE)
    grouped_request <- !rlang::quo_is_null(by_quo) || inherits(data, "grouped_df")
    group_rows <- if (n == 0L && grouped_request) list() else
        if (is.null(groups)) list(seq_len(n)) else groups$rows
    where_quo <- rlang::enquo(where)
    selected <- vector("list", length(group_rows))
    w <- if (weighted) rep(NA_real_, n) else rep(1, n)
    for (g in seq_along(group_rows)) {
        full <- group_rows[[g]]
        size <- length(full)
        view <- lapply(columns, function(z) z[full])
        extras <- list(.n = seq_len(size), .N = size)
        keep <- .mutation_rows(.eval_mutation_expression(where_quo, view,
            "where", extras), size)
        if (is.null(keep)) keep <- seq_len(size)
        if (!is.null(positions)) {
            if (any(positions > size))
                stop("`rows` contains a position beyond the group row count",
                     call. = FALSE)
            keep <- intersect(keep, positions)
        }
        selected[[g]] <- full[sort(unique(keep))]
        if (weighted) {
            wg <- .eval_mutation_expression(weight_quo, view, "weights", extras)
            wg <- .summarize_numeric(wg)
            if (!length(wg) && size == 0L) next
            if (!length(wg) %in% c(1L, size))
                stop("`weights` must have length one or the group row count",
                     call. = FALSE)
            wg <- rep(wg, length.out = size)
            .summarize_weights(wg[keep], weight)
            w[full] <- wg
        }
    }
    # Plain columns do not depend on the group's estimation sample. Reuse
    # their expansion so ordinary grouped summaries do not scan the full
    # dataset once per group.
    plain_variables <- if (length(selected) &&
        all(inputs$specs %in% names(data))) {
        .summarize_varlist(data, inputs$specs, rep(TRUE, n),
            detail = detail, meanonly = meanonly)
    } else NULL
    result <- list(statistics = list(), smallest = list(), largest = list(),
        r = list(), groups = data.frame(), headers = character(),
        formats = character(), empty = logical(), base = logical(), omitted = logical(),
        display = logical(), factor_labels = character(), factor_headers = character())
    group_index <- integer()
    for (g in seq_along(selected)) {
        variables <- plain_variables
        if (is.null(variables)) {
            sample <- rep(FALSE, n)
            sample[selected[[g]]] <- TRUE
            sample <- sample & !is.na(w) & w != 0
            variables <- .summarize_varlist(data, inputs$specs, sample,
                time = time, panel = panel, delta = delta, noemptycells = noemptycells,
                baselevels = baselevels, allbaselevels = allbaselevels,
                nofvlabel = nofvlabel, detail = detail, meanonly = meanonly,
                weights = w)
        }
        count <- length(variables$values)
        for (j in seq_len(count)) {
            value <- variables$values[[j]]
            if (is.character(value)) {
                if (!is.null(dim(value)))
                    stop("summary inputs must be vectors", call. = FALSE)
            } else .dta_egen_numeric(value)
            fit <- .summarize_statistics(value[selected[[g]]],
                w[selected[[g]]], if (weighted) weight else NULL,
                detail, meanonly)
            i <- length(result$statistics) + 1L
            result$statistics[[i]] <- data.frame(
                variable = variables$names[[j]], as.list(fit$statistics),
                check.names = FALSE, stringsAsFactors = FALSE)
            result$smallest[[i]] <- fit$smallest
            result$largest[[i]] <- fit$largest
            result$r <- fit$r
            result$headers[i] <- variables$headers[[j]]
            fmt <- attr(value, "format.stata", exact = TRUE)
            result$formats[i] <- if (is.null(fmt)) "%9.0g" else fmt
            result$empty[i] <- isTRUE(attr(value, "summarize.empty", exact = TRUE))
            result$base[i] <- isTRUE(attr(value, "summarize.base", exact = TRUE))
            result$omitted[i] <- isTRUE(attr(value, "summarize.omitted", exact = TRUE))
            result$display[i] <- if (is.null(variables$display)) TRUE else variables$display[j]
            for (field in c("factor_labels", "factor_headers"))
                result[[field]][i] <- if (is.null(variables[[field]])) "" else variables[[field]][j]
            group_index[i] <- g
        }
    }
    result$statistics <- if (length(result$statistics)) {
        do.call(rbind, result$statistics)
    } else {
        empty <- .summarize_statistics(numeric(), numeric(), NULL, detail, meanonly)
        template <- data.frame(variable = "", as.list(empty$statistics),
                               check.names = FALSE)
        template[FALSE, , drop = FALSE]
    }
    if (!is.null(groups)) result$groups <-
        vctrs::vec_slice(groups$keys, group_index)
    else if (grouped_request) {
        keys <- if (inherits(data, "grouped_df"))
            setdiff(names(attr(data, "groups", exact = TRUE)), ".rows") else group_names
        result$groups <- vctrs::new_data_frame(lapply(columns[keys],
            function(key) key[integer()]), n = 0L)
    }
    result$options <- c(flags, list(separator = separator, fvwrap = fvwrap,
        fvwrapon = fvwrapon, weight = if (weighted) weight else NULL,
        grouped = grouped_request))
    class(result) <- "dta_summarize"
    if (meanonly) invisible(result) else result
}

.summarize_inputs <- function(x, dots, data, caller) {
    if (!is.null(data) && !is.data.frame(data))
        stop("`data` must be a data frame", call. = FALSE)
    first_evaluated <- FALSE
    if (is.null(data) && !is.null(x)) {
        first <- rlang::eval_tidy(x, env = caller)
        first_evaluated <- TRUE
        if (is.data.frame(first)) {
            data <- first
            x <- NULL
        }
    }
    quos <- c(if (!is.null(x)) list(x), dots)
    if (!is.null(data)) {
        if (is.null(names(data)) || anyNA(names(data)) ||
            any(!nzchar(names(data))) || anyDuplicated(names(data)))
            stop("`data` must have unique, nonempty column names", call. = FALSE)
        specs <- if (!length(quos)) names(data) else unlist(lapply(quos,
            function(q) {
                expr <- rlang::quo_get_expr(q)
                if (rlang::is_symbol(expr)) return(rlang::as_string(expr))
                if (is.character(expr)) return(expr)
                names(tidyselect::eval_select(q, data, allow_rename = FALSE))
            }), use.names = FALSE)
        return(list(data = data, specs = specs))
    }
    if (!length(quos)) stop("nothing to summarize", call. = FALSE)
    values <- if (first_evaluated) c(list(first),
        lapply(dots, rlang::eval_tidy, env = caller)) else
        lapply(quos, rlang::eval_tidy, env = caller)
    if (length(values) == 1L && is.list(values[[1L]]) &&
        !is.object(values[[1L]])) {
        values <- values[[1L]]
        labels <- names(values)
        if (is.null(labels)) labels <- paste0("v", seq_along(values))
    } else {
        labels <- names(quos)
        if (is.null(labels)) labels <- rep("", length(quos))
        for (i in seq_along(quos)) if (!nzchar(labels[i]))
            labels[i] <- rlang::as_label(quos[[i]])
    }
    if (!length(values)) stop("nothing to summarize", call. = FALSE)
    if (length(unique(lengths(values))) != 1L)
        stop("summary vectors must have equal lengths", call. = FALSE)
    names(values) <- make.unique(labels)
    data <- vctrs::new_data_frame(values, n = length(values[[1L]]))
    list(data = data, specs = names(values))
}

.summarize_numeric <- function(x) {
    .dta_egen_numeric(x)
    result <- as.double(unclass(x))
    if (inherits(x, "Date")) result <- result + 3653
    else if (inherits(x, "POSIXct")) result <- (result + 315619200) * 1000
    result
}

.summarize_weights <- function(w, type) {
    if (any(is.infinite(w))) stop("weights must be finite", call. = FALSE)
    w <- w[!is.na(w)]
    if (type != "iweight" && any(w < 0))
        stop("negative weights are not allowed", call. = FALSE)
    if (type == "fweight" && any(w != floor(w)))
        stop("frequency weights must be integers", call. = FALSE)
}

.summarize_statistics <- function(value, weights, weight, detail, meanonly) {
    names <- c("N", "sum_w", "mean", if (!meanonly) c("Var", "sd"),
               "min", "max", "sum", if (detail)
                   c("skewness", "kurtosis", paste0("p", c(1, 5, 10, 25, 50, 75, 90, 95, 99))))
    out <- stats::setNames(rep(NA_real_, length(names)), names)
    out[c("N", "sum_w", "sum")] <- 0
    smallest <- largest <- rep(NA_real_, 4L)
    if (is.character(value)) value <- rep(NA_real_, length(value))
    else value <- .summarize_numeric(value)
    if (any(is.infinite(value)))
        stop("summary inputs must be finite or missing", call. = FALSE)
    keep <- !is.na(value) & !is.na(weights) & weights != 0
    x <- value[keep]
    w <- weights[keep]
    n <- length(x)
    r <- as.list(out[c("N", "sum_w", "sum")])
    if (n) {
        total <- .summarize_sum(w)
        out["N"] <- if (identical(weight, "fweight")) total else n
        out["sum_w"] <- total
        out["sum"] <- .summarize_sum(w * x)
        out["min"] <- min(x)
        out["max"] <- max(x)
        if (total != 0 && is.finite(out[["sum"]] / total)) {
            # Center the moments on the rounded mean, as Stata does.
            mu <- out[["sum"]] / total
            out["mean"] <- mu
            if (!meanonly) {
                centered <- x - mu
                m2 <- .summarize_sum(w * centered^2) / total
                variance <- if (identical(weight, "aweight")) {
                    if (n > 1L) m2 * n / (n - 1) else NA_real_
                } else if (total != 1 && (n > 1L || identical(weight, "fweight"))) {
                    m2 * total / (total - 1)
                } else NA_real_
                out["Var"] <- variance
                out["sd"] <- if (!is.na(variance) && variance >= 0)
                    sqrt(variance) else NA_real_
            }
            if (detail && is.finite(m2) && m2 > 0) {
                out["skewness"] <- (.summarize_sum(w * centered^3) / total) / sqrt(m2^3)
                out["kurtosis"] <- (.summarize_sum(w * centered^4) / total) / m2^2
            }
        }
        if (detail) {
            order <- order(x)
            ordered <- x[order]
            smallest[seq_len(min(n, 4L))] <- utils::head(ordered, 4L)
            largest[5L - rev(seq_len(min(n, 4L)))] <- utils::tail(ordered, 4L)
            ps <- c(1, 5, 10, 25, 50, 75, 90, 95, 99)
            out[paste0("p", ps)] <- .summarize_percentiles(ordered,
                w[order], total, ps)
        }
        out[!is.finite(out)] <- NA_real_
        r <- as.list(out)
    }
    list(statistics = out, r = r, smallest = smallest, largest = largest)
}

.summarize_percentiles <- function(ordered, weights, total, ps) {
    # Native detail results retain zero percentiles when the weight total
    # overflows, even though the moment statistics are unavailable.
    if (!is.finite(total)) return(rep(0, length(ps)))
    cumulative <- cumsum(weights)
    # Native summarize uses a 1e-5 percentage-point boundary tolerance.
    # Scaling after division avoids overflow for large finite weight sums.
    percent <- if (total > .Machine$double.xmax / 100)
        (cumulative / total) * 100 else (cumulative * 100) / total
    n <- length(ordered)
    midpoint <- function(index) ordered[index] / 2 + ordered[index + 1L] / 2
    vapply(ps, function(p) {
        target <- total * (p / 100)
        index <- which(cumulative >= target)[1L]
        if (is.na(index)) return(ordered[n])
        if (index < n && cumulative[index] == target) return(midpoint(index))
        near <- percent > p - 1e-5 & percent < p + 1e-5
        previous <- index > 1L && isTRUE(near[index - 1L])
        current <- isTRUE(near[index])
        # Locate the actual weight interval before checking its boundaries.
        # If both boundaries are near, the percentile lies inside a small
        # positive weight; averaging either boundary would skip that value.
        if (xor(previous, current)) {
            boundary <- if (previous) index - 1L else index
            if (boundary < n) return(midpoint(boundary))
        }
        ordered[index]
    }, numeric(1))
}

.summarize_sum <- function(x) .Call(C_dtatools_summarize_sum, x)
