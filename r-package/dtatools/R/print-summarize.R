#' @export
print.dta_summarize <- function(x, ..., width = getOption("width", 80L)) {
    lines <- format(x, ..., width = width)
    if (length(lines)) cat(lines, sep = "\n")
    invisible(x)
}

#' @export
format.dta_summarize <- function(x, ..., width = getOption("width", 80L)) {
    if (isTRUE(x$options$meanonly)) return(character())
    if (!nrow(x$statistics)) return(if (isTRUE(x$options$grouped)) character() else "no variables defined")
    selected <- seq_len(nrow(x$statistics))
    if (!isTRUE(x$options$detail)) {
        if (!is.null(x$display)) selected <- selected[x$display[selected]]
        if (isTRUE(x$options$noemptycells) && !is.null(x$empty)) {
            selected <- selected[!x$empty[selected]]
        }
    }
    grouped <- !is.null(x$groups) && ncol(x$groups) > 0L
    if (!grouped) return(.summarize_format_rows(x, selected))
    keys <- x$groups
    changed <- rep(FALSE, nrow(keys))
    changed[[1L]] <- TRUE
    if (nrow(keys) > 1L) {
        for (j in seq_len(ncol(keys))) {
            value <- as.character(.prepare_tab_argument(keys[[j]], "distinguish", "value"))
            changed[-1L] <- changed[-1L] |
                xor(is.na(value[-1L]), is.na(value[-length(value)])) |
                (!is.na(value[-1L]) & !is.na(value[-length(value)]) &
                 value[-1L] != value[-length(value)])
        }
    }
    blocks <- split(seq_len(nrow(keys)), cumsum(changed))
    unlist(lapply(seq_along(blocks), function(k) {
        rows <- intersect(blocks[[k]], selected)
        values <- vapply(keys, function(column) {
            as.character(.prepare_tab_argument(column, "distinguish", "label"))[blocks[[k]][[1L]]]
        }, character(1))
        c(if (k > 1L) "", strrep("-", max(1L, as.integer(width))),
          paste0("-> ", paste(paste(names(keys), "=", values), collapse = ", ")),
          "", .summarize_format_rows(x, rows))
    }), use.names = FALSE)
}

#' @export
as.data.frame.dta_summarize <- function(x, row.names = NULL, optional = FALSE, ...) {
    result <- x$statistics
    if (!is.null(x$groups) && ncol(x$groups)) {
        result <- cbind(x$groups, result)
        names(result) <- make.unique(names(result))
    }
    if (!is.null(row.names)) row.names(result) <- row.names
    result
}

.summarize_format_rows <- function(x, rows) {
    if (isTRUE(x$options$detail)) {
        return(unlist(lapply(seq_along(rows), function(j) {
            c(if (j > 1L) "", .summarize_format_detail(x, rows[[j]]))
        }), use.names = FALSE))
    }
    weighted <- !is.null(x$options$weight) &&
        x$options$weight %in% c("aweight", "iweight", "aw", "iw")
    rule <- paste0(strrep("-", 13L), "+", strrep("-", if (weighted) 65L else 57L))
    result <- c(if (weighted) {
        "    Variable |     Obs      Weight        Mean   Std. dev.       Min        Max"
    } else {
        "    Variable |        Obs        Mean    Std. dev.       Min        Max"
    }, rule)
    previous <- ""
    separator <- x$options$separator
    if (is.null(separator)) separator <- 5L
    for (j in seq_along(rows)) {
        i <- rows[[j]]
        current <- if (length(x$factor_headers)) x$factor_headers[[i]] else ""
        if (is.na(current)) current <- ""
        if (j > 1L && separator > 0L && (j - 1L) %% separator == 0L) {
            result <- c(result, rule)
        } else if (j > 1L && !identical(previous, current) &&
                   (nzchar(previous) || nzchar(current)) && !isTRUE(x$options$vsquish)) {
            result <- c(result, "             |")
        }
        if (nzchar(current) && !identical(previous, current)) {
            result <- c(result, paste0(.tab_pad(.summarize_abbreviate(current), 12L), " |"))
        }
        if (nzchar(current)) {
            label <- if (length(x$factor_labels)) x$factor_labels[[i]] else x$statistics$variable[[i]]
            labels <- .summarize_factor_label(label, x$options)
            stub <- ifelse(endsWith(labels, "#"),
                paste0(.tab_pad(sub("#$", "", labels), 11L), " #|"),
                paste0(.tab_pad(labels, 11L), "  |"))
        } else {
            stub <- paste0(.tab_pad(.summarize_abbreviate(x$statistics$variable[[i]]), 12L), " |")
        }
        stats <- x$statistics[i, , drop = FALSE]
        count_width <- if (weighted) 8L else 11L
        count <- .tab_pad(.summarize_count(stats$N, count_width), count_width)
        if (weighted) count <- paste0(count, .tab_pad(.summarize_weight(stats$sum_w), 12L))
        state <- if (length(x$empty) && x$empty[[i]]) "empty" else
            if (length(x$base) && x$base[[i]]) "base" else
            if (length(x$omitted) && x$omitted[[i]]) "omitted" else ""
        rest <- if (nzchar(state)) paste0(count, "   (", state, ")") else if (isTRUE(stats$N == 0)) count else {
            fmt <- .summarize_row_format(x, i)
            paste0(count,
                   .summarize_field(stats$mean, fmt, 3L),
                   .tab_pad(.summarize_number(stats$sd, .summarize_dispersion_format(fmt)), if (weighted) 11L else 12L),
                   .summarize_field(stats$min, fmt, 2L),
                   .summarize_field(stats$max, fmt, 2L))
        }
        result <- c(result, paste0(stub, c(rep("", length(stub) - 1L), rest)))
        previous <- current
    }
    result
}

.summarize_format_detail <- function(x, i) {
    stats <- x$statistics[i, , drop = FALSE]
    name <- stats$variable[[1L]]
    label <- if (length(x$headers)) x$headers[[i]] else name
    if (is.na(label) || !nzchar(label)) label <- name
    generated <- length(x$factor_headers) && nzchar(x$factor_headers[[i]])
    headings <- c(if (generated && !identical(label, name)) name, .tab_wrap(label, 48L))
    headings <- paste0(strrep(" ", pmax(0L, floor((61L - .tab_width(headings)) / 2L))), headings)
    result <- c(headings, strrep("-", 61L))
    if (isTRUE(stats$N == 0)) return(c(result, "no observations"))
    fmt <- .summarize_row_format(x, i)
    value <- function(number) .summarize_field(number, fmt)
    stat <- function(number) .tab_pad(.summarize_number(number, .summarize_dispersion_format(fmt)), 9L)
    small <- x$smallest[[i]]
    large <- x$largest[[i]]
    small <- c(small, rep(NA_real_, max(0L, 4L - length(small))))[1:4]
    large <- c(rep(NA_real_, max(0L, 4L - length(large))), large)[1:4]
    left <- function(percent, number, extreme = NULL) {
        paste0(.tab_pad(paste0(percent, "%"), 3L), "    ", value(number),
               if (!is.null(extreme)) paste0("      ", value(extreme)))
    }
    c(result, "      Percentiles      Smallest",
      left(1, stats$p1, small[[1L]]), left(5, stats$p5, small[[2L]]),
      paste0(left(10, stats$p10, small[[3L]]), "       Obs", .tab_pad(.summarize_count(stats$N), 20L)),
      paste0(left(25, stats$p25, small[[4L]]), "       Sum of wgt.",
             .tab_pad(if (isTRUE(x$options$weight %in% c("aweight", "aw")))
                 .summarize_weight(stats$sum_w, comma = TRUE) else .summarize_count(stats$sum_w), 12L)),
      "", paste0(left(50, stats$p50), "                      Mean          ", value(stats$mean)),
      paste0("                        Largest       Std. dev.     ", stat(stats$sd)),
      left(75, stats$p75, large[[1L]]),
      paste0(left(90, stats$p90, large[[2L]]), "       Variance      ", stat(stats$Var)),
      paste0(left(95, stats$p95, large[[3L]]), "       Skewness      ", stat(stats$skewness)),
      paste0(left(99, stats$p99, large[[4L]]), "       Kurtosis      ", stat(stats$kurtosis)))
}

.summarize_row_format <- function(x, i) {
    fmt <- if (isTRUE(x$options$format) && length(x$formats) >= i &&
        !is.na(x$formats[[i]]) && nzchar(x$formats[[i]])) x$formats[[i]] else "%9.0g"
    sub("^%(-?[0-9]*)?d", "%\\1td", fmt)
}

.summarize_dispersion_format <- function(format) {
    if (grepl("^%(-?[0-9]*)?t", format)) "%9.0g" else format
}

.summarize_field <- function(value, format, lead = 0L) {
    width <- 9L
    if (grepl("^%(-?[0-9]*)?t", format)) {
        spec <- .summarize_calendar_spec(format)
        width <- spec$width
        if (isTRUE(spec$left)) {
            text <- .summarize_number(value, format)
            return(paste0(strrep(" ", lead), text, strrep(" ", max(0L, width - .tab_width(text)))))
        }
    }
    paste0(strrep(" ", lead), .tab_pad(.summarize_number(value, format), width))
}

.summarize_count <- function(x, width = 11L) {
    vapply(as.double(x), function(value) {
        if (!is.finite(value)) return(".")
        text <- formatC(value, format = "f", digits = 0L, big.mark = ",")
        if (nchar(text) > width) text <- formatC(value, format = "f", digits = 0L)
        if (nchar(text) <= width) text else .summarize_exponential(value, width - 7L, width)
    }, character(1), USE.NAMES = FALSE)
}

.summarize_weight <- function(x, comma = FALSE) {
    vapply(as.double(x), function(value) {
        if (!is.finite(value)) "." else .summarize_general(value, comma = comma, width = 11L)
    }, character(1), USE.NAMES = FALSE)
}

.summarize_abbreviate <- function(text, width = 12L) {
    if (.tab_width(text) <= width) text else
        paste0(.tab_cut(text, width - 2L), "~", substring(text, nchar(text)))
}

.summarize_factor_label <- function(label, options) {
    components <- strsplit(label, "#", fixed = TRUE)[[1L]]
    if (length(components) > 1L && .tab_width(label) > 11L) {
        return(unlist(lapply(seq_along(components), function(i) {
            lines <- .summarize_factor_label(components[[i]], options)
            if (i < length(components)) lines[[length(lines)]] <- paste0(lines[[length(lines)]], "#")
            lines
        }), use.names = FALSE))
    }
    wrap <- if (is.null(options$fvwrap)) 1L else options$fvwrap
    # Factor levels use an eleven-column stub and Stata's two-dot truncation.
    shorten <- function(s) if (.tab_width(s) <= 11L) s else paste0(.tab_cut(s, 9L), "..")
    if (wrap <= 1L) return(shorten(label))
    if (identical(options$fvwrapon, "width")) {
        chars <- strsplit(label, "", fixed = TRUE)[[1L]]
        lines <- vapply(split(chars, (seq_along(chars) - 1L) %/% 11L), paste, "", collapse = "")
    } else lines <- .tab_wrap(label, 11L)
    if (length(lines) > wrap) {
        lines <- c(lines[seq_len(wrap - 2L)],
            shorten(paste(lines[seq.int(wrap - 1L, length(lines) - 1L)], collapse = " ")),
            utils::tail(lines, 1L))
    }
    unname(lines)
}

# summarize uses a nine-character numeric format, even when a stored
# numeric format requests a wider field. Its default is Stata's %9.0g.
.summarize_number <- function(x, format = "%9.0g") {
    vapply(as.double(x), function(value) {
        if (!is.finite(value)) return(".")
        if (grepl("^%(-?[0-9]*)?t", format)) return(.summarize_date(value, format))
        parsed <- regmatches(format, regexec("^%-?[0-9]+[.,]([0-9]+)([fg])([c]?)$", format))[[1L]]
        digits <- if (length(parsed)) as.integer(parsed[[2L]]) else 0L
        family <- if (length(parsed)) parsed[[3L]] else "g"
        comma <- length(parsed) && identical(parsed[[4L]], "c")
        if (family == "f") {
            if (digits > 7L) digits <- 0L
            text <- formatC(value, format = "f", digits = digits, big.mark = if (comma) "," else "")
            if (nchar(text) > 9L && comma)
                text <- formatC(value, format = "f", digits = digits)
            if (nchar(text) <= 9L) return(text)
            return(.summarize_exponential(value, 2L))
        }
        .summarize_general(value, digits, comma)
    }, character(1), USE.NAMES = FALSE)
}

# General formats reserve a sign and decimal point, and retain leading
# fractional zeros when the requested precision is smaller than the width.
.summarize_general <- function(value, digits = 0L, comma = FALSE, width = 9L) {
    significant <- if (digits == 0L) max(2L, width - 2L) else
        max(2L, min(digits, width - 2L))
    magnitude <- if (value == 0) 0 else floor(log10(abs(value)))
    exponential <- max(1L, width - 7L)
    if (value != 0 && (abs(value) < 1e-5 || magnitude >= width - 2L))
        return(.summarize_exponential(value, min(exponential, significant - 1L), width))
    decimals <- max(0L, min(width - 2L, significant - magnitude - 1L))
    rounded <- round(.summarize_half_away(value, decimals), decimals)
    if (value != 0 && rounded == 0)
        return(.summarize_exponential(value, min(exponential, significant - 1L), width))
    if (abs(rounded) >= 10^(width - 2L))
        return(.summarize_exponential(value, exponential, width))
    if (digits > 0L && decimals == 0L && abs(rounded) >= 10^(magnitude + 1L))
        return(.summarize_exponential(value, 1L, width))
    if (comma && magnitude >= 3L) {
        grouped_decimals <- max(0L, decimals - magnitude %/% 3L)
        grouped <- formatC(.summarize_half_away(value, grouped_decimals), format = "f", digits = grouped_decimals, big.mark = ",")
        if (grouped_decimals > 0L) grouped <- sub("\\.?0+$", "", grouped)
        grouped_width <- width - 2L + as.integer(grepl(".", grouped, fixed = TRUE))
        if (nchar(grouped) - as.integer(value < 0) <= grouped_width) {
            decimals <- grouped_decimals
        } else comma <- FALSE
    }
    text <- formatC(.summarize_half_away(value, decimals), format = "f", digits = decimals, big.mark = if (comma) "," else "")
    if (decimals > 0L) text <- sub("\\.?0+$", "", text)
    text <- sub("^(-?)0\\.", "\\1.", text)
    if (identical(text, "-0")) text <- "0"
    if (nchar(text) > width) .summarize_exponential(value, min(exponential, significant - 1L), width) else text
}

.summarize_half_away <- function(value, digits) {
    # A decimal halfway value is exactly representable in binary only when
    # multiplying by 2^(digits + 1) gives an odd integer. Leave nearby values
    # untouched so ordinary decimal conversion preserves their direction.
    if ((abs(value) * 2^(digits + 1L)) %% 2 == 1)
        sign(value) * (trunc(abs(value) * 10^digits) + 1) / 10^digits
    else value
}

.summarize_exponential <- function(value, digits, width = 9L) {
    exponent <- floor(log10(abs(value)))
    # Three-digit exponents consume one of the available mantissa digits.
    digits <- min(digits, max(0L, max(8L, width) - 5L - max(2L, nchar(abs(exponent)))))
    scaled <- abs(value) / 10^(exponent - digits)
    if (is.finite(scaled) && scaled %% 1 == .5) {
        mantissa <- (trunc(scaled) + 1) / 10^digits
        if (mantissa >= 10) {
            mantissa <- mantissa / 10
            exponent <- exponent + 1L
        }
        text <- paste0(if (value < 0) "-" else "",
            sprintf(paste0("%.", digits, "f"), mantissa),
            "e", sprintf("%+03d", as.integer(exponent)))
    } else text <- sprintf(paste0("%.", digits, "e"), value)
    if (digits == 0L) text <- sub("e", ".e", text, fixed = TRUE)
    text
}

# Calendar pictures follow [D] Datetime display formats. Parse complete
# tokens rather than substituting R strftime patterns: Stata also has
# half-years, its own 52-week year, literal escapes, and leap seconds.
.summarize_calendar_spec <- function(format) {
    parsed <- regmatches(format, regexec("^%(-?[0-9]*)?t([a-zA-Z])(.*)$", format))[[1L]]
    if (!length(parsed)) stop("Invalid Stata calendar format: ", format, call. = FALSE)
    kind <- parsed[[3L]]
    if (kind == "b") return(.summarize_business_spec(format))
    if (!kind %in% c("d", "c", "C", "w", "m", "q", "h", "y"))
        stop("Unsupported Stata calendar format: ", format, call. = FALSE)
    picture <- parsed[[4L]]
    default <- !nzchar(picture)
    if (default) picture <- switch(kind,
        c = "DDmonCCYY_HH:MM:SS", C = "DDmonCCYY_HH:MM:SS",
        d = "DDmonCCYY", w = "CCYY!www", m = "CCYY!mnn",
        q = "CCYY!qq", h = "CCYY!hh", y = "CCYY")
    widths <- c(DAYNAME = 9L, Dayname = 9L, Month = 9L, month = 9L,
        "A.M." = 4L, "a.m." = 4L, ".sss" = 4L, ".ss" = 3L, ".s" = 2L,
        Mon = 3L, mon = 3L, Day = 3L, day = 3L, JJJ = 3L, jjj = 3L,
        CC = 2L, cc = 2L, YY = 2L, yy = 2L, NN = 2L, nn = 2L,
        DD = 2L, dd = 2L, Da = 2L, da = 2L, WW = 2L, ww = 2L,
        HH = 2L, Hh = 2L, hH = 2L, hh = 2L, MM = 2L, mm = 2L,
        SS = 2L, ss = 2L, AM = 2L, am = 2L, h = 1L, q = 1L,
        D = 2L, N = 2L, Y = 2L, m = 3L)
    tokens <- character()
    width <- 0L
    while (nzchar(picture)) {
        if (startsWith(picture, "!") && nchar(picture) >= 2L) {
            token <- substr(picture, 1L, 2L)
            extent <- 1L
        } else {
            matches <- names(widths)[startsWith(picture, names(widths))]
            if (length(matches)) {
                token <- matches[[1L]]
                extent <- widths[[token]]
            } else {
                token <- substr(picture, 1L, 1L)
                if (!token %in% c(".", ",", ":", "-", "_", " ", "/", "\\", "+"))
                    stop("Unsupported token in Stata calendar format: ", format, call. = FALSE)
                extent <- if (token == "+") 0L else 1L
            }
        }
        tokens <- c(tokens, token)
        width <- width + extent
        picture <- substring(picture, nchar(token) + 1L)
    }
    numeric_width <- min(12L, width)
    left <- startsWith(parsed[[2L]], "-")
    if (default && kind == "y" && !left) width <- 9L
    if (nzchar(sub("^-", "", parsed[[2L]]))) width <- abs(as.integer(parsed[[2L]]))
    list(kind = kind, tokens = tokens, width = width, numeric_width = numeric_width, left = left)
}

.summarize_date <- function(value, format) {
    spec <- .summarize_calendar_spec(format)
    kind <- spec$kind
    if (kind == "numeric") return(.summarize_number(value))
    if (!is.null(spec$business)) {
        position <- spec$business$center + trunc(value)
        if (position < 1L || position > length(spec$business$days)) return(.summarize_number(value))
        value <- spec$business$days[[position]] - as.double(as.Date("1960-01-01"))
    }
    # Stata's calendars cover years 0100 through 9999. Keep out-of-range
    # codes numeric before constructing an R date, which may itself reject them.
    bounds <- switch(kind,
        d = c(-679350, 2936550), w = c(-96720, 418080),
        m = c(-22320, 96480), q = c(-7440, 32160),
        h = c(-3720, 16080), y = c(100, 10000),
        c = c(-58695840000000, 253717920000000),
        C = c(-58695840000000, 253717920027000))
    if (value < bounds[[1L]] || value >= bounds[[2L]]) {
        numeric_width <- spec$numeric_width
        text <- .summarize_general(value, width = numeric_width)
        if (spec$left) return(text)
        return(paste0(strrep(" ", max(0L, spec$width - numeric_width)),
            .tab_pad(text, numeric_width)))
    }
    period <- floor(value)
    leap <- FALSE
    milliseconds <- 0L
    if (kind %in% c("c", "C")) {
        milliseconds <- floor(value %% 1000)
        if (kind == "C") {
            # All leap seconds in Stata's leapseconds.maint, also listed
            # by IERS. The most recent insertion was 31 December 2016.
            dates <- c("1972-07-01", "1973-01-01", "1974-01-01", "1975-01-01",
                "1976-01-01", "1977-01-01", "1978-01-01", "1979-01-01",
                "1980-01-01", "1981-07-01", "1982-07-01", "1983-07-01",
                "1985-07-01", "1988-01-01", "1990-01-01", "1991-01-01",
                "1992-07-01", "1993-07-01", "1994-07-01", "1996-01-01",
                "1997-07-01", "1999-01-01", "2006-01-01", "2009-01-01",
                "2012-07-01", "2015-07-01", "2017-01-01")
            midnight <- as.double(as.Date(dates) - as.Date("1960-01-01")) * 86400000
            starts <- midnight + (seq_along(dates) - 1L) * 1000
            index <- findInterval(value, starts)
            leap <- index > 0L && value < starts[[index]] + 1000
            value <- if (leap) midnight[[index]] - 1000 + milliseconds else value - index * 1000
        }
        date <- as.POSIXlt(as.POSIXct(floor(value) / 1000, origin = "1960-01-01", tz = "UTC"), tz = "UTC")
    } else {
        date <- if (kind == "d") as.Date(period, origin = "1960-01-01") else {
            periods <- switch(kind, m = 12L, q = 4L, h = 2L, w = 52L, y = 1L)
            year <- if (kind == "y") period else 1960L + period %/% periods
            unit <- period %% periods
            month <- switch(kind, m = unit + 1L, q = 3L * unit + 1L,
                            h = 6L * unit + 1L, 1L)
            origin <- as.Date(sprintf("%04d-%02d-01", year, month))
            if (kind == "w") origin + unit * 7L else origin
        }
        date <- as.POSIXlt(date, tz = "UTC")
    }
    year <- date$year + 1900L
    month <- date$mon + 1L
    day <- date$mday
    hour <- date$hour
    second <- if (leap) 60L else floor(date$sec)
    month_names <- c("January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December")
    day_names <- c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
    month_name <- month_names[[month]]
    day_name <- day_names[[date$wday + 1L]]
    pad <- function(number, n = 2L) sprintf(paste0("%0", n, "d"), as.integer(number))
    hour12 <- if (hour %% 12L == 0L) 12L else hour %% 12L
    text <- c(CC = pad(year %/% 100L), cc = as.character(year %/% 100L),
        YY = pad(year %% 100L), yy = as.character(year %% 100L),
        JJJ = pad(date$yday + 1L, 3L), jjj = as.character(date$yday + 1L),
        Month = month_name, month = tolower(month_name), Mon = substr(month_name, 1L, 3L),
        mon = tolower(substr(month_name, 1L, 3L)), NN = pad(month), nn = as.character(month),
        DD = pad(day), dd = as.character(day), DAYNAME = .tab_pad(day_name, 9L),
        Dayname = day_name, Day = substr(day_name, 1L, 3L), Da = substr(day_name, 1L, 2L),
        day = tolower(substr(day_name, 1L, 3L)), da = tolower(substr(day_name, 1L, 2L)),
        h = as.character((month - 1L) %/% 6L + 1L), q = as.character((month - 1L) %/% 3L + 1L),
        WW = pad(min(52L, date$yday %/% 7L + 1L)), ww = as.character(min(52L, date$yday %/% 7L + 1L)),
        HH = pad(hour), Hh = pad(hour12), hH = as.character(hour), hh = as.character(hour12),
        MM = pad(date$min), mm = as.character(date$min), SS = pad(second), ss = as.character(second),
        ".s" = paste0(".", milliseconds %/% 100L), ".ss" = paste0(".", pad(milliseconds %/% 10L)),
        ".sss" = paste0(".", pad(milliseconds, 3L)), am = if (hour < 12L) "am" else "pm",
        AM = if (hour < 12L) "AM" else "PM", "a.m." = if (hour < 12L) "a.m." else "p.m.",
        "A.M." = if (hour < 12L) "A.M." else "P.M.", D = pad(day), N = pad(month),
        Y = pad(year %% 100L), m = substr(month_name, 1L, 3L))
    paste0(vapply(spec$tokens, function(token) {
        if (startsWith(token, "!")) return(substring(token, 2L))
        if (token == "+") return("")
        if (token == "_") return(" ")
        if (token %in% names(text)) text[[token]] else token
    }, character(1)), collapse = "")
}
