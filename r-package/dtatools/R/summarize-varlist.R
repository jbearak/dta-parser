# Expand Stata's virtual variables without changing the source dataset. Keep
# full-length vectors: an if/in sample determines factor levels, not which
# observations can supply a lag or lead.
.summarize_varlist <- function(data, specs, sample, time = NULL, panel = NULL,
                               delta = 1, noemptycells = FALSE,
                               baselevels = FALSE, allbaselevels = FALSE,
                               nofvlabel = FALSE, detail = FALSE, meanonly = FALSE,
                               weights = NULL) {
    if (is.null(specs)) specs <- names(data)
    sample <- !is.na(sample) & sample
    if (is.null(weights)) weights <- rep(1, nrow(data))
    terms <- unlist(lapply(specs, function(spec) {
        unlist(lapply(if (spec %in% names(data)) spec else .summarize_split(spec), .summarize_terms,
                      columns = names(data)), recursive = FALSE)
    }), recursive = FALSE)
    time_index <- NULL
    time_values <- function(x, operators) {
        if (!length(operators)) return(x)
        if (is.null(time_index)) {
            if (!is.character(time) || length(time) != 1L ||
                !time %in% names(data)) {
                stop("Time-series variables require a `time` column", call. = FALSE)
            }
            if (!is.numeric(delta) || length(delta) != 1L ||
                is.na(delta) || !is.finite(delta) || delta <= 0) {
                stop("`delta` must be one positive finite number", call. = FALSE)
            }
            clock <- .summarize_var_numeric(data[[time]])
            if (any(!is.finite(clock)))
                stop("Time variable must contain finite, nonmissing values", call. = FALSE)
            if (is.null(panel)) ids <- rep.int(1L, length(clock)) else {
                if (!is.character(panel) || length(panel) != 1L ||
                    !panel %in% names(data))
                    stop("`panel` must name one column", call. = FALSE)
                if (anyNA(data[[panel]]))
                    stop("Panel variable must not contain missing values", call. = FALSE)
                ids <- match(data[[panel]], unique(data[[panel]]))
            }
            # Integer panel IDs avoid collisions between textual panel labels.
            # Work on the declared time grid so decimal deltas do not miss
            # matches solely because of binary floating-point subtraction.
            origins <- vapply(split(clock, ids), min, numeric(1))
            ticks <- (clock - origins[as.character(ids)]) / delta
            if (any(abs(ticks - round(ticks)) > 1e-7))
                stop("Time values must lie on the grid defined by `delta`", call. = FALSE)
            clock <- round(ticks)
            keys <- paste(ids, sprintf("%.17g", clock), sep = ":")
            if (anyDuplicated(keys))
                stop("Repeated time values within panel", call. = FALSE)
            time_index <<- list(clock = clock, ids = ids, keys = keys)
        }
        .summarize_time_values(.summarize_var_numeric(x), operators,
                               time_index, 1)
    }
    evaluated <- lapply(terms, function(term) {
        result <- lapply(term, .summarize_component, data = data, sample = sample,
                         time_values = time_values, nofvlabel = nofvlabel, weights = weights)
        kinds <- attr(term, "summarize.omission_rules", exact = TRUE)
        attr(result, "summarize.omission_rules") <- lapply(kinds, function(kind) {
            rule <- list()
            for (component in result) {
                setting <- attr(component, "summarize.factor", exact = TRUE)
                if (is.null(setting)) next
                key <- .summarize_model_key(component[[1L]])
                if (key %in% names(rule)) next
                selected <- if (kind == "original") c(setting$bases, setting$omissions)
                if (!length(selected)) selected <- setting$reference
                rule[[key]] <- selected
            }
            rule
        })
        attr(result, "summarize.factor_order") <- attr(term, "summarize.factor_order", exact = TRUE)
        result
    })
    evaluated <- .summarize_factor_settings(evaluated, nofvlabel)
    for (i in seq_along(terms)) for (j in seq_along(terms[[i]])) {
        if (isTRUE(terms[[i]][[j]]$suppress_omission) ||
            isTRUE(terms[[i]][[j]]$repeated_factor)) {
            evaluated[[i]][[j]] <- lapply(evaluated[[i]][[j]], function(component) {
                component$omitted <- FALSE
                component$name <- sub("^([0-9]+)o\\.", "\\1.", component$name)
                component
            })
        }
    }
    evaluated <- lapply(evaluated, function(term) {
        omission_rules <- attr(term, "summarize.omission_rules", exact = TRUE)
        factor_order <- attr(term, "summarize.factor_order", exact = TRUE)
        omitted_keys <- vapply(Filter(function(component)
            !component[[1L]]$factor && component[[1L]]$omitted, term),
            function(component) .summarize_model_key(component[[1L]]), character(1))
        term <- lapply(term, function(component) {
            if (.summarize_model_key(component[[1L]]) %in% omitted_keys)
                component[[1L]]$omitted <- TRUE
            component
        })
        categorical <- vapply(term, function(x) isTRUE(x[[1L]]$factor), logical(1))
        factor_positions <- which(categorical)
        repeated <- factor_positions[duplicated(vapply(term[factor_positions],
            function(x) x[[1L]]$key, character(1)))]
        if (length(repeated)) term <- term[-repeated]
        categorical <- vapply(term, function(x) isTRUE(x[[1L]]$factor), logical(1))
        order_keys <- vapply(term, function(component)
            paste0(if (component[[1L]]$time) "" else ".", component[[1L]]$key), character(1))
        term <- term[order(!categorical, if (length(factor_order))
            match(order_keys, factor_order) else seq_along(term), na.last = TRUE)]
        attr(term, "summarize.omission_rules") <- omission_rules
        term
    })
    # Explicit base specifications follow the terms in the varlist. In a bare
    # a#b interaction only the joint base is omitted; a##b also supplies each
    # main effect, so either explicit base can omit an interaction.
    keys <- lapply(evaluated, function(term) {
        vapply(term, function(component) .summarize_model_key(component[[1L]]), character(1))
    })
    signatures <- vapply(keys, function(key) paste(sort(key), collapse = "#"), character(1))
    # Omission declarations belong to complete model terms. Combining their
    # component flags would incorrectly omit main effects or create omitted
    # interaction cells that no occurrence of the term actually declared.
    term_rules <- lapply(evaluated, function(term) {
        factor <- vapply(term, function(component) component[[1L]]$factor, logical(1))
        continuous_omitted <- vapply(term[!factor], function(component)
            component[[1L]]$omitted, logical(1))
        if (!all(continuous_omitted)) return(list())
        special <- attr(term, "summarize.omission_rules", exact = TRUE)
        rules <- lapply(special, function(rule)
            list(levels = rule, omissions = list(), always = TRUE))
        # Repeated factors preserve the original declaration's omission rule.
        # Their later explicit base is still resolved globally for base cells.
        if (length(special) == 2L) return(rules)
        levels <- omissions <- list()
        for (component in term[factor]) {
            key <- .summarize_model_key(component[[1L]])
            levels[[key]] <- vapply(Filter(function(x) x$base || x$omitted, component), `[[`, numeric(1), "level")
            omissions[[key]] <- vapply(Filter(function(x) x$omitted, component), `[[`, numeric(1), "level")
        }
        if (all(lengths(levels) > 0L) && (any(lengths(omissions) > 0L) || any(continuous_omitted)))
            rules <- c(rules, list(list(levels = levels, omissions = omissions,
                                       always = any(continuous_omitted))))
        rules
    })
    omission_rules <- lapply(seq_along(evaluated), function(i) {
        unlist(term_rules[signatures == signatures[[i]]], recursive = FALSE)
    })
    output <- list(values = list(), names = character(), headers = character(),
                   factor_labels = character(), factor_headers = character(),
                   display = logical())
    time_columns <- time_labels <- character()
    time_active <- logical()
    expanded_keys <- character()
    for (term_index in seq_along(evaluated)) {
        term <- evaluated[[term_index]]
        choices <- .summarize_cross(term)
        for (choice in choices) {
            value <- choice[[1L]]$value
            if (length(choice) > 1L) {
                for (component in choice[-1L])
                    value <- .summarize_var_numeric(value) * .summarize_var_numeric(component$value)
            }
            factor <- vapply(choice, `[[`, logical(1), "factor")
            bases <- vapply(choice, `[[`, logical(1), "base")
            omitted <- vapply(choice, `[[`, logical(1), "omitted")
            component_keys <- vapply(choice, .summarize_model_key, character(1))
            lower_base_term <- any(vapply(keys, function(key) {
                if (length(key) >= length(component_keys)) return(FALSE)
                remaining <- seq_along(component_keys)
                for (part in key) {
                    position <- match(part, component_keys[remaining])
                    if (is.na(position)) return(FALSE)
                    remaining <- remaining[-position]
                }
                all(bases[remaining])
            }, logical(1)))
            is_base <- any(bases) && (all(bases) || lower_base_term)
            is_omitted <- if (!any(factor)) any(omitted) && all(omitted | bases) else
                any(vapply(omission_rules[[term_index]], function(rule) {
                    all(vapply(choice[factor], function(component)
                        component$level %in% rule$levels[[.summarize_model_key(component)]], logical(1))) &&
                        (rule$always || any(vapply(choice[factor], function(component)
                            component$level %in% rule$omissions[[.summarize_model_key(component)]], logical(1))))
                }, logical(1)))
            # A zero-valued continuous interaction is not an empty factor cell.
            cell <- rep.int(TRUE, nrow(data))
            for (component in choice[factor])
                cell <- cell & !is.na(component$value) & component$value != 0
            has_observations <- any(sample & !is.na(value))
            is_empty <- any(factor) && !any(cell & sample) && has_observations
            display <- !has_observations || (!(is_base && !(detail || meanonly || allbaselevels ||
                         (baselevels && !lower_base_term))) &&
                !(is_empty && noemptycells && !(detail || meanonly)))
            if (is_base || is_omitted) value[!is.na(value)] <- 0
            if (is_base) attr(value, "summarize.base") <- TRUE
            if (is_omitted) attr(value, "summarize.omitted") <- TRUE
            if (is_empty) attr(value, "summarize.empty") <- TRUE
            parts <- vapply(choice, `[[`, character(1), "name")
            if (!is_omitted) parts <- sub("^([0-9]+)o\\.", "\\1.", parts)
            else {
                parts[factor & !bases] <- sub("^([0-9]+)(bn|o)?\\.", "\\1o.", parts[factor & !bases])
                parts[!factor] <- sub("^c\\.", "co.", parts[!factor])
            }
            if (is_base && lower_base_term) {
                parts[!bases & factor] <- sub("^([0-9]+)(b|o)?\\.", "\\1o.", parts[!bases & factor])
                parts[!factor] <- sub("^c\\.", "co.", parts[!factor])
            }
            if (is_empty) parts[factor] <- sub("^([0-9]+)(b|o)?\\.", "\\1o.", parts[factor])
            if (length(choice) == 1L && !any(factor)) {
                name <- sub("^co\\.", "o.", sub("^c\\.", "", parts))
            } else name <- paste(parts, collapse = "#")
            expanded_key <- paste(sort(vapply(choice, function(component) {
                paste(.summarize_model_key(component),
                      if (component$factor) component$level else "", sep = "=")
            }, character(1))), collapse = "#")
            if ((any(factor) || length(choice) > 1L) && expanded_key %in% expanded_keys) next
            header <- if (length(choice) == 1L) choice[[1L]]$header else name
            if (!nzchar(header)) header <- name
            factor_header <- ""
            factor_label <- ""
            if (any(factor)) {
                factor_header <- paste(vapply(choice, function(x) {
                    if (x$factor) x$key else x$name
                }, character(1)), collapse = "#")
                has_labels <- any(vapply(choice[factor], `[[`, logical(1), "labelled"))
                factor_label <- paste(vapply(choice[factor], `[[`, character(1), "level_label"),
                                      collapse = if (has_labels) "#" else " ")
            } else if (length(choice) == 1L && choice[[1L]]$time) {
                factor_header <- choice[[1L]]$variable
                factor_label <- choice[[1L]]$time_label
            }
            output$values[[length(output$values) + 1L]] <- value
            output$names <- c(output$names, name)
            output$headers <- c(output$headers, header)
            output$factor_headers <- c(output$factor_headers, factor_header)
            output$factor_labels <- c(output$factor_labels, factor_label)
            output$display <- c(output$display, display)
            expanded_keys <- c(expanded_keys, expanded_key)
            simple <- length(choice) == 1L && !any(factor)
            time_columns <- c(time_columns, if (simple) choice[[1L]]$variable else "")
            time_labels <- c(time_labels, if (simple) choice[[1L]]$time_label else "")
            time_active <- c(time_active, simple && choice[[1L]]$time)
        }
    }
    if (length(time_columns)) {
        runs <- split(seq_along(time_columns), cumsum(c(TRUE,
            utils::tail(time_columns, -1L) != utils::head(time_columns, -1L))))
        for (run in runs) if (any(time_active[run])) {
            output$factor_headers[run] <- time_columns[run]
            output$factor_labels[run] <- time_labels[run]
        }
    }
    output
}

.summarize_model_key <- function(component) {
    paste0(if (component$factor) "i." else "c.", component$key)
}

.summarize_var_numeric <- function(value) {
    if (!typeof(value) %in% c("double", "integer", "logical") ||
        !is.null(dim(value)) || inherits(value, c("integer64", "difftime")) ||
        !(is.numeric(value) || is.logical(value) ||
          inherits(value, c("Date", "POSIXct", "factor")))) {
        stop("Factor and time-series operators require numeric variables", call. = FALSE)
    }
    result <- as.double(unclass(value))
    if (inherits(value, "Date")) result <- result + 3653
    else if (inherits(value, "POSIXct")) result <- (result + 315619200) * 1000
    result
}

# Split only at parentheses depth zero. Numlists and grouped varlists can
# contain spaces, and the ordinal base spelling ib(#2) can contain a hash.
.summarize_split <- function(text, interactions = FALSE) {
    chars <- strsplit(trimws(text), "", fixed = TRUE)[[1L]]
    parts <- character()
    operators <- character()
    depth <- 0L
    start <- 1L
    i <- 1L
    while (i <= length(chars)) {
        ch <- chars[[i]]
        if (ch == "(") depth <- depth + 1L
        if (ch == ")") depth <- depth - 1L
        if (depth < 0L) stop("Invalid parentheses in summarize varlist", call. = FALSE)
        split <- depth == 0L && if (interactions) ch == "#" else grepl("[[:space:]]", ch)
        if (split) {
            if (i > start) parts <- c(parts, paste0(chars[start:(i - 1L)], collapse = ""))
            if (interactions) {
                op <- "#"
                if (i < length(chars) && chars[[i + 1L]] == "#") {
                    op <- "##"
                    i <- i + 1L
                }
                operators <- c(operators, op)
            }
            start <- i + 1L
        }
        i <- i + 1L
    }
    if (depth != 0L) stop("Invalid parentheses in summarize varlist", call. = FALSE)
    if (start <= length(chars)) parts <- c(parts, paste0(chars[start:length(chars)], collapse = ""))
    if (interactions) list(parts = parts, operators = operators) else parts
}

.summarize_terms <- function(spec, columns, implicit = FALSE) {
    # A literal name takes precedence over Stata punctuation, which is useful
    # for ordinary R tables that have non-Stata column names.
    if (spec %in% columns) {
        return(list(list(list(variable = spec, prefix = if (implicit) "i" else ""))))
    }
    split <- .summarize_split(spec, interactions = TRUE)
    if (length(split$operators)) {
        if (length(split$parts) != length(split$operators) + 1L)
            stop("Invalid factor-variable interaction", call. = FALSE)
        terms <- .summarize_terms(split$parts[[1L]], columns, TRUE)
        for (i in seq_along(split$operators)) {
            right <- .summarize_terms(split$parts[[i + 1L]], columns, TRUE)
            interactions <- unlist(lapply(terms, function(left) {
                lapply(right, function(other) {
                    joined <- lapply(c(left, other), function(component) {
                        component$suppress_omission <- FALSE
                        component
                    })
                    left_specs <- lapply(left, function(component) .summarize_parse_prefix(component$prefix))
                    right_specs <- lapply(other, function(component) .summarize_parse_prefix(component$prefix))
                    factor_keys <- function(components, specifications) {
                        vapply(seq_along(components), function(i) {
                            if (is.null(specifications[[i]]$factor_spec)) return(NA_character_)
                            paste0(.summarize_time_name(specifications[[i]]$operators), ".", components[[i]]$variable)
                        }, character(1))
                    }
                    left_keys <- factor_keys(left, left_specs)
                    right_keys <- factor_keys(other, right_specs)
                    left_order <- attr(left, "summarize.factor_order", exact = TRUE)
                    right_order <- attr(other, "summarize.factor_order", exact = TRUE)
                    if (is.null(left_order)) left_order <- unique(left_keys[!is.na(left_keys)])
                    if (is.null(right_order)) right_order <- unique(right_keys[!is.na(right_keys)])
                    # A nested interaction that contains the entire left
                    # factor term keeps its own variable order.
                    attr(joined, "summarize.factor_order") <- if (
                        all(!is.na(left_keys)) && length(right_order) > length(left_order) &&
                        all(left_order %in% right_order)) right_order else unique(c(left_order, right_order))
                    attr(joined, "summarize.new_repeated") <-
                        length(intersect(left_keys[!is.na(left_keys)], right_keys[!is.na(right_keys)])) > 0L
                    # Stata resolves # sequentially. Appending an omitted
                    # continuous variable can retain the preceding factor
                    # interaction's reference cell. Parentheses therefore
                    # matter, as does adding another component afterward.
                    if (length(left) > 1L && length(other) == 1L &&
                        all(vapply(left_specs, function(x) !is.null(x$factor_spec), logical(1))) &&
                        is.null(right_specs[[1L]]$factor_spec) && right_specs[[1L]]$raw_omitted &&
                        !.summarize_explicit_factor(left_specs[[1L]]$factor_spec) &&
                        any(vapply(left_specs[-1L], function(x)
                            .summarize_explicit_factor(x$factor_spec), logical(1))))
                        attr(joined, "summarize.omission_rules") <- "original"
                    joined
                })
            }), recursive = FALSE)
            terms <- if (split$operators[[i]] == "##") {
                mains <- lapply(c(terms, right), function(term) {
                    if (length(term) != 1L) return(term)
                    result <- lapply(term, function(component) {
                        component$suppress_omission <- TRUE
                        component
                    })
                    attributes(result) <- attributes(term)
                    result
                })
                c(mains, interactions)
            } else interactions
        }
        # Repeated continuous occurrences share an omission declaration within
        # this expression, including occurrences in different expanded terms.
        continuous_key <- function(component) {
            parsed <- .summarize_parse_prefix(component$prefix)
            if (!is.null(parsed$factor_spec)) return(NA_character_)
            paste0(.summarize_time_name(parsed$operators), ".", component$variable)
        }
        components <- unlist(terms, recursive = FALSE)
        omitted <- vapply(components, function(component) {
            parsed <- .summarize_parse_prefix(component$prefix)
            parsed$raw_omitted || isTRUE(component$raw_omitted)
        }, logical(1))
        omitted_keys <- unique(vapply(components[omitted], continuous_key, character(1)))
        terms <- lapply(terms, function(term) {
            result <- lapply(term, function(component) {
                if (continuous_key(component) %in% omitted_keys) component$raw_omitted <- TRUE
                component
            })
            attributes(result) <- attributes(term)
            result
        })
        terms <- lapply(terms, function(term) {
            parsed <- lapply(term, function(component) .summarize_parse_prefix(component$prefix))
            factor_keys <- vapply(seq_along(term), function(i) {
                if (is.null(parsed[[i]]$factor_spec)) return(NA_character_)
                paste0(.summarize_time_name(parsed[[i]]$operators), ".", term[[i]]$variable)
            }, character(1))
            repeated_keys <- unique(factor_keys[duplicated(factor_keys) & !is.na(factor_keys)])
            unique_keys <- unique(factor_keys[!is.na(factor_keys)])
            for (key in repeated_keys) {
                positions <- which(!is.na(factor_keys) & factor_keys == key)
                specifications <- vapply(parsed[positions], `[[`, character(1), "factor_spec")
                omissions <- grepl("^(io|o)|^[0-9]+o$", specifications)
                bases <- grepl("^(ib|b)", specifications) & !specifications %in% c("ibn", "bn")
                explicit_bases <- grepl("^[0-9]+b$", specifications)
                if (sum(omissions) > 1L ||
                    (any(omissions) && (any(explicit_bases) ||
                        any(vapply(which(omissions), function(i) any(bases[seq_len(i)]), logical(1))))))
                    stop("Multiple omitted operators for one factor in an interaction", call. = FALSE)
                if (length(unique_keys) == 1L)
                    for (position in positions) term[[position]]$repeated_factor <- TRUE
            }
            # Introducing a repeated factor into an existing interaction can
            # retain both its original omitted cell and its reference cell.
            # A repetition already resolved in an earlier binary step cannot.
            if (isTRUE(attr(term, "summarize.new_repeated", exact = TRUE)) &&
                length(repeated_keys) && length(unique_keys) > 1L &&
                all(vapply(unique_keys, function(key) {
                    any(vapply(parsed[which(factor_keys == key)], function(x)
                        .summarize_explicit_factor(x$factor_spec), logical(1)))
                }, logical(1))))
                attr(term, "summarize.omission_rules") <- c("original", "reference")
            term
        })
        # ## can repeat a main effect when a group contains several variables.
        signatures <- vapply(terms, function(term) paste(vapply(term, function(x) {
            parsed <- .summarize_parse_prefix(x$prefix)
            prefix <- if (is.null(parsed$factor_spec))
                paste0(if (parsed$raw_omitted && !isTRUE(x$suppress_omission)) "o" else "c",
                       .summarize_time_name(parsed$operators)) else x$prefix
            paste0(prefix, ".", x$variable)
        }, character(1)), collapse = "#"), character(1))
        return(terms[!duplicated(signatures)])
    }
    if (startsWith(spec, "(") && endsWith(spec, ")")) {
        inside <- substr(spec, 2L, nchar(spec) - 1L)
        return(unlist(lapply(.summarize_split(inside), .summarize_terms,
                             columns = columns, implicit = implicit), recursive = FALSE))
    }
    grouped <- regexpr("\\.\\(", spec)
    if (grouped[[1L]] > 0L && endsWith(spec, ")")) {
        prefix <- substr(spec, 1L, grouped[[1L]])
        inside <- substr(spec, grouped[[1L]] + 2L, nchar(spec) - 1L)
        return(unlist(lapply(.summarize_split(inside), function(child)
            .summarize_terms(paste0(prefix, child), columns, implicit)), recursive = FALSE))
    }
    dots <- gregexpr("\\.", spec)[[1L]]
    if (dots[[1L]] > 0L) {
        dot <- utils::tail(dots, 1L)
        prefix <- substr(spec, 1L, dot - 1L)
        variable <- substr(spec, dot + 1L, nchar(spec))
    } else {
        prefix <- if (implicit) "i" else ""
        variable <- spec
    }
    variables <- .summarize_select_names(variable, columns)
    unlist(lapply(variables, function(variable) {
        lapply(.summarize_expand_operator_lists(prefix), function(operator)
            list(list(variable = variable, prefix = operator)))
    }), recursive = FALSE)
}

.summarize_select_names <- function(spec, columns) {
    if (spec == "_all") return(columns)
    if (spec %in% columns) return(spec)
    if (grepl("[*?]", spec)) {
        selected <- columns[grepl(utils::glob2rx(spec), columns)]
    } else if (grepl("-", spec, fixed = TRUE)) {
        bounds <- strsplit(spec, "-", fixed = TRUE)[[1L]]
        if (length(bounds) != 2L)
            stop("Invalid variable range: ", spec, call. = FALSE)
        limits <- vapply(bounds, function(bound) {
            resolved <- .summarize_select_names(bound, columns)
            if (length(resolved) != 1L) stop("Ambiguous variable: ", bound, call. = FALSE)
            match(resolved, columns)
        }, integer(1))
        if (limits[[1L]] > limits[[2L]])
            stop("Variable range is in reverse dataset order: ", spec, call. = FALSE)
        selected <- columns[seq.int(limits[[1L]], limits[[2L]])]
    } else {
        selected <- columns[startsWith(columns, spec)]
        if (length(selected) > 1L) stop("Ambiguous variable: ", spec, call. = FALSE)
    }
    if (!length(selected)) stop("Variable not found: ", spec, call. = FALSE)
    selected
}

.summarize_numlist <- function(text) {
    tokens <- strsplit(trimws(text), "[[:space:],]+")[[1L]]
    limit <- 100000L
    too_large <- function() stop("Factor or time-series numlist is too large", call. = FALSE)
    if (length(tokens) > limit) too_large()
    ranges <- vector("list", length(tokens))
    total <- 0
    for (i in seq_along(tokens)) {
        token <- tokens[[i]]
        if (grepl("^[0-9]+/[0-9]+$", token)) {
            bounds <- as.double(strsplit(token, "/", fixed = TRUE)[[1L]])
            increment <- 1
        } else if (grepl("^[0-9]+\\(-?[0-9]+\\)[0-9]+$", token)) {
            values <- as.double(strsplit(token, "[()]")[[1L]])
            if (values[[2L]] == 0) stop("Invalid zero numlist increment", call. = FALSE)
            bounds <- values[c(1L, 3L)]
            increment <- abs(values[[2L]])
        } else if (grepl("^[0-9]+$", token)) {
            bounds <- rep(as.double(token), 2L)
            increment <- 1
        }
        else stop("Invalid factor or time-series numlist: ", text, call. = FALSE)
        if (any(!is.finite(bounds)) || !is.finite(increment))
            too_large()
        difference <- bounds[[2L]] - bounds[[1L]]
        count <- floor(abs(difference) / increment) + 1
        total <- total + count
        if (total > limit) too_large()
        # Stata takes the increment's magnitude and the endpoints' direction.
        step <- if (difference < 0) -increment else increment
        last <- bounds[[1L]] + step * (count - 1)
        if (!is.finite(last) || max(bounds[[1L]], last) > .Machine$integer.max) too_large()
        ranges[[i]] <- c(from = bounds[[1L]], by = step, count = count)
    }
    # Validate every token, including the cumulative length, before allocating
    # any expanded range. Duplicates still count toward the expansion limit.
    result <- unlist(lapply(ranges, function(range)
        seq.int(from = range[["from"]], by = range[["by"]], length.out = range[["count"]])),
        use.names = FALSE)
    unique(result)
}

.summarize_expand_operator_lists <- function(prefix) {
    match <- regexpr("[LlFfDdSs]\\([^()]*(?:\\([^()]*\\)[^()]*)?\\)", prefix, perl = TRUE)
    if (match[[1L]] < 0L) return(prefix)
    start <- match[[1L]]
    end <- start + attr(match, "match.length") - 1L
    list_text <- substr(prefix, start + 2L, end - 1L)
    unlist(lapply(.summarize_numlist(list_text), function(number) {
        replacement <- paste0(substr(prefix, 1L, start), number,
                              substr(prefix, end + 1L, nchar(prefix)))
        .summarize_expand_operator_lists(replacement)
    }), use.names = FALSE)
}

.summarize_cross <- function(sets) {
    result <- list(list())
    for (set in sets) {
        result <- unlist(lapply(result, function(prefix) {
            lapply(set, function(value) c(prefix, list(value)))
        }), recursive = FALSE)
    }
    result
}

.summarize_parse_prefix <- function(prefix) {
    original <- prefix
    prefix <- gsub(".", "", prefix, fixed = TRUE)
    factor_spec <- NULL
    continuous <- FALSE
    raw_omitted <- FALSE
    operators <- list()
    while (nzchar(prefix)) {
        patterns <- c(
            "^(?:ib|b)(?:n|\\((?:first|last|freq|#[0-9]+)\\)|[0-9]+)",
            "^(?:io|o)(?:\\((?:[^()]|\\([^()]*\\))*\\)|[0-9]+)",
            "^i(?:\\((?:[^()]|\\([^()]*\\))*\\)|[0-9]+)?",
            "^[0-9]+(?:bn|b|o)?", "^co", "^c", "^o", "^[LlFfDdSs][0-9]*"
        )
        token <- NULL
        for (pattern in patterns) {
            found <- regexpr(pattern, prefix, perl = TRUE)
            if (found[[1L]] == 1L) {
                token <- regmatches(prefix, found)
                break
            }
        }
        if (is.null(token)) stop("Invalid factor or time-series operator: ",
                                 original, call. = FALSE)
        prefix <- substr(prefix, nchar(token) + 1L, nchar(prefix))
        if (grepl("^[LlFfDdSs]", token)) {
            order <- substr(token, 2L, nchar(token))
            order <- if (nzchar(order)) as.double(order) else 1
            if (!is.finite(order) || order > 10000)
                stop("Time-series order is too large", call. = FALSE)
            operators[[length(operators) + 1L]] <- list(
                op = toupper(substr(token, 1L, 1L)), order = order)
        } else if (token %in% c("c", "co", "o")) {
            continuous <- TRUE
            raw_omitted <- token %in% c("co", "o")
        } else {
            if (!is.null(factor_spec))
                stop("Repeated factor-variable operator", call. = FALSE)
            factor_spec <- token
        }
    }
    if (continuous && !is.null(factor_spec))
        stop("Conflicting factor and continuous operators", call. = FALSE)
    list(factor_spec = factor_spec, continuous = continuous,
         raw_omitted = raw_omitted, operators = operators)
}

.summarize_explicit_factor <- function(specification) {
    !is.null(specification) &&
        grepl("^(ib|b|io|o)|^[0-9]+[bo]$", specification) &&
        !specification %in% c("ibn", "bn")
}

.summarize_component <- function(component, data, sample, time_values, nofvlabel, weights) {
    variable <- component$variable
    parsed <- .summarize_parse_prefix(component$prefix)
    factor_spec <- parsed$factor_spec
    continuous <- parsed$continuous
    raw_omitted <- parsed$raw_omitted || isTRUE(component$raw_omitted)
    operators <- parsed$operators
    x <- data[[variable]]
    if (!is.null(factor_spec) && any(vapply(operators, function(op)
        op$op %in% c("D", "S"), logical(1))))
        stop("Factor variables allow only lag and lead operators", call. = FALSE)
    if (length(operators)) {
        original_format <- attr(x, "format.stata", exact = TRUE)
        x <- time_values(x, operators)
        attr(x, "format.stata") <- original_format
    }
    time_name <- .summarize_time_name(operators)
    key <- paste0(if (nzchar(time_name)) paste0(time_name, ".") else "", variable)
    label <- attr(data[[variable]], "label", exact = TRUE)
    if (is.null(label) || !is.character(label) || length(label) != 1L || is.na(label)) label <- ""
    template <- list(value = x, name = key, key = key, variable = variable,
                     header = label, factor = FALSE, base = FALSE,
                     omitted = raw_omitted, labelled = FALSE, level_label = "",
                     time = nzchar(time_name),
                     time_label = if (!nzchar(time_name)) "--." else
                         paste0(if (time_name %in% c("L", "F", "D", "S"))
                             paste0(time_name, "1") else time_name, "."))
    if (is.null(factor_spec)) {
        if (continuous) template$name <- paste0("c.", key)
        return(list(template))
    }
    values <- .summarize_var_numeric(x)
    observed <- values[sample & !is.na(values)]
    if (any(!is.finite(observed) | observed < 0 | observed != trunc(observed) |
            observed > 32740))
        stop("Factor variables must contain integers from 0 to 32740", call. = FALSE)
    levels <- sort(unique(observed))
    if (!length(levels)) levels <- 0
    reference <- levels[[1L]]
    bases <- omissions <- numeric()
    no_base <- FALSE
    selected_levels <- NULL
    if (grepl("^(ib|b)", factor_spec)) {
        base <- sub("^(ib|b)", "", factor_spec)
        no_base <- base == "n"
        if (base != "n") {
            bases <- switch(base,
                "(first)" = levels[[1L]],
                "(last)" = utils::tail(levels, 1L),
                "(freq)" = levels[[which.max(vapply(levels, function(level)
                    sum(weights[sample & !is.na(values) & values == level]), numeric(1)))]],
                if (grepl("^\\(#[0-9]+\\)$", base)) {
                    position <- as.integer(sub("^\\(#([0-9]+)\\)$", "\\1", base))
                    if (position < 1L || position > length(levels))
                        stop("Factor base position is outside observed levels", call. = FALSE)
                    levels[[position]]
                } else as.double(base))
            if (!length(observed) && base %in% c("(first)", "(last)", "(freq)"))
                bases <- numeric()
        }
    } else if (grepl("^(io|o)", factor_spec)) {
        omissions <- sub("^(io|o)", "", factor_spec)
        omissions <- .summarize_numlist(gsub("^\\(|\\)$", "", omissions))
    } else if (grepl("^[0-9]+(bn|b|o)$", factor_spec)) {
        levels <- as.double(sub("(bn|b|o)$", "", factor_spec))
        selected_levels <- levels
        no_base <- endsWith(factor_spec, "bn")
        if (endsWith(factor_spec, "b")) bases <- levels
        if (endsWith(factor_spec, "o")) omissions <- levels
    } else if (factor_spec != "i") {
        selected <- sub("^i", "", factor_spec)
        levels <- .summarize_numlist(gsub("^\\(|\\)$", "", selected))
        selected_levels <- levels
    }
    levels <- sort(unique(c(levels, bases)))
    if (!length(observed) && length(bases) && !0 %in% bases)
        omissions <- unique(c(omissions, 0))
    if (any(levels > 32740))
        stop("Factor levels must be between 0 and 32740", call. = FALSE)
    labels <- attr(data[[variable]], "labels", exact = TRUE)
    if (is.factor(data[[variable]])) labels <- stats::setNames(seq_along(levels(data[[variable]])),
                                                       levels(data[[variable]]))
    settings <- list(template = template, source = values, levels = levels,
                     bases = bases, omissions = omissions, labels = labels,
                     no_base = no_base, selected = selected_levels,
                     reference = if (no_base) numeric() else reference)
    result <- .summarize_factor_records(settings, nofvlabel)
    attr(result, "summarize.factor") <- settings
    result
}

.summarize_factor_records <- function(settings, nofvlabel) {
    lapply(settings$levels, function(level) {
        template <- settings$template
        values <- settings$source
        labels <- settings$labels
        result <- template
        result$value <- as.double(values == level)
        result$base <- level %in% settings$bases
        result$omitted <- level %in% settings$omissions
        result$factor <- TRUE
        result$level <- level
        code <- format(level, scientific = FALSE, trim = TRUE)
        suffix <- if (result$base) "b" else if (result$omitted) "o" else
            if (settings$no_base && level == settings$levels[[1L]]) "bn" else ""
        result$name <- paste0(code, suffix, ".", template$key)
        result$level_label <- code
        if (!nofvlabel && !is.null(labels) && !is.null(names(labels))) {
            match <- match(level, as.double(labels))
            if (!is.na(match) && !is.na(names(labels)[[match]]) && nzchar(names(labels)[[match]])) {
                result$labelled <- TRUE
                result$level_label <- names(labels)[[match]]
            }
        }
        result
    })
}

# Stata resolves level restrictions and explicit bases for a variable across
# the complete varlist, before expanding its occurrences in interactions.
.summarize_factor_settings <- function(terms, nofvlabel) {
    declarations <- list()
    for (term in terms) for (component in term) {
        setting <- attr(component, "summarize.factor", exact = TRUE)
        if (is.null(setting)) next
        key <- setting$template$key
        declarations[[key]] <- c(declarations[[key]], list(setting))
    }
    for (key in names(declarations)) {
        settings <- declarations[[key]]
        bases <- unique(unlist(lapply(settings, `[[`, "bases"), use.names = FALSE))
        no_base <- any(vapply(settings, `[[`, logical(1), "no_base"))
        if (length(bases) > 1L || (length(bases) && no_base))
            stop("Factor variable base category conflict: ", key, call. = FALSE)
        selected <- unlist(lapply(settings, `[[`, "selected"), use.names = FALSE)
        levels <- if (length(selected)) selected else
            unlist(lapply(settings, `[[`, "levels"), use.names = FALSE)
        setting <- settings[[1L]]
        setting$levels <- sort(unique(c(levels, bases)))
        setting$bases <- bases
        setting$no_base <- no_base
        declarations[[key]] <- setting
    }
    lapply(terms, function(term) {
        result <- lapply(term, function(component) {
            setting <- attr(component, "summarize.factor", exact = TRUE)
            if (is.null(setting)) return(component)
            resolved <- declarations[[setting$template$key]]
            resolved$omissions <- setting$omissions
            .summarize_factor_records(resolved, nofvlabel)
        })
        attributes(result) <- attributes(term)
        result
    })
}

.summarize_time_name <- function(operators) {
    if (!length(operators)) return("")
    shift <- 0
    differences <- 0
    seasons <- numeric()
    for (operator in operators) {
        if (operator$op == "L") shift <- shift + operator$order
        else if (operator$op == "F") shift <- shift - operator$order
        else if (operator$op == "D") differences <- differences + operator$order
        else if (operator$order > 0) seasons <- c(seasons, operator$order)
    }
    part <- function(op, order) if (order == 0) "" else
        paste0(op, if (order == 1) "" else order)
    paste0(part(if (shift < 0) "F" else "L", abs(shift)),
           part("D", differences),
           if (length(seasons)) paste0(vapply(sort(seasons), function(season)
               part("S", season), character(1)), collapse = "") else "")
}

.summarize_time_values <- function(values, operators, index, delta) {
    shift <- 0
    coefficients <- c("0" = 1)
    differences <- numeric()
    for (operator in operators) {
        if (operator$op == "L") shift <- shift + operator$order
        else if (operator$op == "F") shift <- shift - operator$order
        else if (operator$op == "D") differences <- c(differences, rep.int(1, operator$order))
        else if (operator$order > 0) differences <- c(differences, operator$order)
    }
    for (lag in differences) {
        offsets <- as.double(names(coefficients))
        combined <- c(coefficients, -coefficients)
        keys <- c(offsets, offsets + lag)
        coefficients <- tapply(combined, keys, sum)
        coefficients <- coefficients[coefficients != 0]
    }
    result <- numeric(length(values))
    for (i in seq_along(coefficients)) {
        offset <- as.double(names(coefficients)[[i]]) + shift
        target <- index$clock - offset * delta
        keys <- paste(index$ids, sprintf("%.17g", target), sep = ":")
        matched <- match(keys, index$keys)
        result <- result + coefficients[[i]] * values[matched]
    }
    result
}
