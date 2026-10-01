# Business calendars use the file grammar documented in [D] Datetime
# business calendars creation. Files are data, never executable R or Stata.
.summarize_calendar_cache <- new.env(parent = emptyenv())

.summarize_business_spec <- function(format) {
    parsed <- regmatches(format, regexec("^%(-?[0-9]*)?tb([A-Za-z_][A-Za-z0-9_]*)(:.*)?$", format))[[1L]]
    if (!length(parsed)) stop("Invalid Stata business-calendar format: ", format, call. = FALSE)
    name <- parsed[[3L]]
    paths <- getOption("dtatools.business_calendar_path", character())
    if (!is.character(paths) || anyNA(paths))
        stop("`dtatools.business_calendar_path` must contain directory paths", call. = FALSE)
    candidates <- file.path(unique(c(getwd(), paths)), paste0(name, ".stbcal"))
    found <- candidates[file.exists(candidates)]
    fallback <- list(kind = "numeric", tokens = character(), width = 9L)
    if (!length(found)) return(fallback)
    path <- normalizePath(found[[1L]], mustWork = TRUE)
    info <- file.info(path)
    stamp <- c(as.double(info$mtime), info$size)
    cached <- .summarize_calendar_cache[[path]]
    if (is.null(cached) || !identical(cached$stamp, stamp)) {
        cached <- list(stamp = stamp, calendar = tryCatch(
            .summarize_read_business_calendar(path), error = function(e) NULL))
        .summarize_calendar_cache[[path]] <- cached
    }
    if (is.null(cached$calendar)) return(fallback)
    picture <- sub("^:", "", parsed[[4L]])
    spec <- .summarize_calendar_spec(paste0("%", parsed[[2L]], "td", picture))
    spec$business <- cached$calendar
    spec
}

.summarize_read_business_calendar <- function(path) {
    lines <- trimws(sub("//.*$", "", readLines(path, warn = FALSE)))
    lines <- lines[nzchar(lines) & !startsWith(lines, "*")]
    dateformat <- "ymd"
    span <- center <- NULL
    rules <- character()
    version <- FALSE
    fail <- function(message) stop("Invalid business calendar `", basename(path),
                                   "`: ", message, call. = FALSE)
    for (line in lines) {
        command <- tolower(sub("[[:space:]].*$", "", line))
        argument <- trimws(sub("^[^[:space:]]+[[:space:]]*", "", line))
        if (command == "version") {
            if (!grepl("^[0-9]+(\\.[0-9]+)?$", argument)) fail("invalid version")
            version <- TRUE
        } else if (command == "purpose") {
            next
        } else if (command == "dateformat") {
            if (!argument %in% c("ymd", "ydm", "myd", "mdy", "dym", "dmy"))
                fail("invalid dateformat")
            dateformat <- argument
        } else if (command == "range") {
            values <- strsplit(argument, "[[:space:]]+")[[1L]]
            if (length(values) != 2L) fail("range needs two dates")
            span <- vapply(values, .summarize_calendar_date, numeric(1), order = dateformat)
        } else if (command == "centerdate") {
            center <- .summarize_calendar_date(argument, dateformat)
        } else if (command %in% c("omit", "from")) {
            rules <- c(rules, line)
        } else fail(paste0("unknown command ", command))
    }
    if (!version || length(span) != 2L || is.null(center))
        fail("version, range, and centerdate are required")
    if (anyNA(span) || is.na(center) || span[[1L]] > span[[2L]] ||
        center < span[[1L]] || center > span[[2L]]) fail("invalid range or centerdate")
    days <- seq.int(span[[1L]], span[[2L]])
    dates <- as.Date(days, origin = "1970-01-01")
    parts <- list(year = as.integer(base::format(dates, "%Y")),
        month = as.integer(base::format(dates, "%m")),
        day = as.integer(base::format(dates, "%d")),
        dow = (days + 4L) %% 7L)
    omitted <- rep(FALSE, length(days))
    for (rule in rules) {
        active <- rep(TRUE, length(days))
        bounded <- FALSE
        if (startsWith(tolower(rule), "from ")) {
            bounded <- TRUE
            prefix <- regmatches(rule, regexec("^from[[:space:]]+([^ ]+)[[:space:]]+to[[:space:]]+([^ :]+)[[:space:]]*:[[:space:]]*(.*)$", rule, ignore.case = TRUE))[[1L]]
            if (!length(prefix)) fail(paste0("invalid from/to rule: ", rule))
            first <- if (prefix[[2L]] == ".") span[[1L]] else .summarize_calendar_date(prefix[[2L]], dateformat)
            last <- if (prefix[[3L]] == ".") span[[2L]] else .summarize_calendar_date(prefix[[3L]], dateformat)
            active <- days >= first & days <= last
            rule <- prefix[[4L]]
        }
        condition <- strsplit(rule, "[[:space:]]+if[[:space:]]+", perl = TRUE)[[1L]]
        if (length(condition) > 2L) fail("more than one if clause")
        rule <- condition[[1L]]
        if (length(condition) == 2L) {
            restrictions <- strsplit(condition[[2L]], "[[:space:]]*&[[:space:]]*")[[1L]]
            for (restriction in restrictions) {
                parsed <- regmatches(trimws(restriction), regexec("^(dow|month|year)\\(([^()]*)\\)$", trimws(restriction)))[[1L]]
                if (!length(parsed)) fail(paste0("invalid restriction: ", restriction))
                name <- parsed[[2L]]
                values <- .summarize_calendar_list(parsed[[3L]], name)
                active <- active & parts[[name]] %in% values
            }
        }
        offsets <- 0L
        pieces <- strsplit(rule, "[[:space:]]+and[[:space:]]+", perl = TRUE)[[1L]]
        if (length(pieces) > 2L) fail("more than one and clause")
        rule <- pieces[[1L]]
        if (length(pieces) == 2L) offsets <- c(0L, .summarize_calendar_list(pieces[[2L]], "offset"))
        if (grepl("^omit[[:space:]]+date[[:space:]]+", rule)) {
            value <- sub("^omit[[:space:]]+date[[:space:]]+", "", rule)
            if (grepl("*", value, fixed = TRUE)) {
                example <- as.Date(.summarize_calendar_date(sub("*", "2000", value, fixed = TRUE), dateformat), origin = "1970-01-01")
                match <- parts$month == as.integer(base::format(example, "%m")) &
                    parts$day == as.integer(base::format(example, "%d"))
            } else {
                if (bounded) fail("from/to is not allowed with a full omit date")
                match <- days == .summarize_calendar_date(value, dateformat)
            }
        } else if (grepl("^omit[[:space:]]+dayofweek[[:space:]]+", rule)) {
            value <- sub("^omit[[:space:]]+dayofweek[[:space:]]+", "", rule)
            match <- parts$dow %in% .summarize_calendar_list(value, "dow")
            if (length(offsets) > 1L) fail("and is not allowed with omit dayofweek")
        } else if (grepl("^omit[[:space:]]+dowinmonth[[:space:]]+", rule)) {
            parsed <- regmatches(rule, regexec("^omit[[:space:]]+dowinmonth[[:space:]]+([+-][0-9]+)[[:space:]]+([A-Za-z]+)([[:space:]]+of[[:space:]]+(.*))?$", rule))[[1L]]
            if (!length(parsed)) fail(paste0("invalid dowinmonth rule: ", rule))
            nth <- as.integer(parsed[[2L]])
            if (nth == 0L) fail("dowinmonth requires a nonzero ordinal")
            match <- parts$dow == .summarize_calendar_list(parsed[[3L]], "dow")
            if (nth > 0L) match <- match & (parts$day - 1L) %/% 7L + 1L == nth else {
                month_size <- c(31L, 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L)[parts$month]
                feb <- parts$month == 2L
                month_size[feb] <- 28L + as.integer(parts$year[feb] %% 4L == 0L &
                    (parts$year[feb] %% 100L != 0L | parts$year[feb] %% 400L == 0L))
                match <- match & (month_size - parts$day) %/% 7L + 1L == -nth
            }
            if (nzchar(parsed[[5L]])) match <- match & parts$month %in%
                .summarize_calendar_list(parsed[[5L]], "month")
        } else fail(paste0("unknown omit rule: ", rule))
        target <- which(active & match)
        for (offset in offsets) {
            positions <- target + offset
            positions <- positions[positions >= 1L & positions <= length(days)]
            omitted[positions] <- TRUE
        }
    }
    if (omitted[[1L]] || omitted[[length(omitted)]]) fail("range boundaries are omitted")
    days <- days[!omitted]
    center_index <- match(center, days)
    if (is.na(center_index)) fail("centerdate is omitted")
    list(days = days, center = center_index)
}

.summarize_calendar_list <- function(text, kind) {
    text <- trimws(gsub("[()]", "", text))
    tokens <- strsplit(text, "[[:space:]]+")[[1L]]
    if (kind %in% c("year", "offset")) {
        values <- suppressWarnings(as.integer(tokens))
        valid <- if (kind == "year") grepl("^[0-9]{4}$", tokens) else grepl("^[+-][0-9]+$", tokens) & values != 0L
    } else {
        choices <- if (kind == "dow")
            c("sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday") else
            tolower(month.name)
        values <- vapply(tolower(tokens), function(token) {
            if (kind == "month" && grepl("^[0-9]+$", token)) return(as.integer(token))
            hits <- which(startsWith(choices, token))
            if (length(hits) == 1L && (kind != "dow" || nchar(token) >= 2L)) hits[[1L]] else NA_integer_
        }, integer(1))
        valid <- !is.na(values) & values >= 1L & values <= length(choices)
        if (kind == "dow") values <- values - 1L
    }
    if (!length(values) || anyNA(values) || !all(valid))
        stop("Invalid business-calendar ", kind, " list: ", text, call. = FALSE)
    values
}

.summarize_calendar_date <- function(text, order = "ymd") {
    tokens <- regmatches(text, gregexpr("[0-9]+|[A-Za-z]+", text))[[1L]]
    if (length(tokens) != 3L) stop("Invalid business-calendar date: ", text, call. = FALSE)
    named_month <- which(grepl("[A-Za-z]", tokens))
    if (length(named_month)) {
        month <- .summarize_calendar_list(tokens[[named_month]], "month")
        other <- setdiff(seq_len(3L), named_month)
        year_pos <- other[nchar(tokens[other]) == 4L]
        if (length(year_pos) != 1L) year_pos <- which(strsplit(order, "")[[1L]] == "y")
        year <- as.integer(tokens[[year_pos]])
        day <- as.integer(tokens[[setdiff(other, year_pos)]])
    } else {
        values <- stats::setNames(as.integer(tokens), strsplit(order, "")[[1L]])
        year <- values[["y"]]
        month <- values[["m"]]
        day <- values[["d"]]
    }
    date <- tryCatch(as.Date(sprintf("%04d-%02d-%02d", year, month, day)), error = function(e) NA)
    if (is.na(date)) stop("Invalid business-calendar date: ", text, call. = FALSE)
    as.double(date)
}
