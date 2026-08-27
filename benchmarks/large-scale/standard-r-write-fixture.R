standard_r_write_schema <- function(data) {
    stopifnot(is.data.frame(data), ncol(data) == 40L)
    classes <- vapply(data, function(column) {
        if (inherits(column, "POSIXct")) return("POSIXct")
        if (inherits(column, "Date")) return("Date")
        typeof(column)
    }, character(1L))
    expected <- c(
        double = 11L, integer = 11L, logical = 4L, Date = 2L,
        POSIXct = 2L, character = 10L
    )
    observed <- table(factor(classes, levels = names(expected)))
    if (!identical(as.integer(observed), unname(expected)) ||
        any(vapply(data, function(column) {
            any(c("stata.storage", "format.stata", "label", "labels") %in%
                names(attributes(column)))
        }, logical(1L)))) {
        stop("standard-R write fixture has unexpected types or Stata metadata")
    }
    paste(paste(names(expected), expected, sep = "="), collapse = ",")
}

make_standard_r_write_fixture <- function(rows) {
    stopifnot(length(rows) == 1L, is.finite(rows), rows >= 1L)
    rows <- as.integer(rows)
    i <- seq_len(rows)
    cycle <- function(values, offset = 0L) {
        rep_len(c(tail(values, offset), head(values, length(values) - offset)), rows)
    }
    repeated_format <- function(format, modulus, multiplier = 1L) {
        base_i <- seq_len(min(rows, modulus))
        values <- sprintf(format, (base_i * multiplier) %% modulus)
        rep_len(values, rows)
    }

    income <- 18000 + (i %% 250000L) * 1.17
    income[i %% 997L == 0L] <- NA_real_
    expenditure <- 9000 + (i %% 140000L) * 0.83
    expenditure[i %% 991L == 0L] <- NA_real_
    eligible <- i %% 2L == 0L
    eligible[i %% 1009L == 0L] <- NA

    data <- data.frame(
        id = as.double(i),
        household_id = as.double((i - 1L) %/% 3L + 1L),
        income = income,
        expenditure = expenditure,
        sampling_weight = 0.25 + (i %% 10000L) / 1000,
        latitude = -44.5 + (i %% 134000L) / 1000,
        longitude = -179.5 + (i %% 359000L) / 1000,
        score_physical = sin(i / 113) * 12 + 50,
        score_mental = cos(i / 127) * 11 + 51,
        score_economic = log1p(i %% 50000L),
        score_environment = sqrt(i %% 100000L),
        wave = as.integer((i - 1L) %% 12L + 1L),
        age = as.integer(18L + i %% 83L),
        household_size = as.integer(1L + i %% 8L),
        children = as.integer(i %% 5L),
        visits = as.integer(i %% 24L),
        survey_year = as.integer(2000L + i %% 25L),
        survey_month = as.integer(1L + i %% 12L),
        status_code = as.integer(i %% 17L),
        provider_count = as.integer(i %% 12L),
        event_count = as.integer(i %% 200L),
        quality_flag = as.integer(i %% 4L),
        eligible = eligible,
        insured = i %% 3L != 0L,
        responded = i %% 5L != 0L,
        follow_up = i %% 7L == 0L,
        birth_date = as.Date("1940-01-01") + (i %% 25000L),
        interview_date = as.Date("2010-01-01") + (i %% 5500L),
        created_at = as.POSIXct("2018-01-01", tz = "UTC") +
            (i %% 10000000L),
        updated_at = as.POSIXct("2020-01-01", tz = "UTC") +
            (i %% 15000000L),
        case_code = repeated_format("CASE-%08d", 100000L),
        state_code = cycle(state.abb),
        county = cycle(c(
            "Kings", "Queens", "Cook", "Harris", "Maricopa", "Orange",
            "Wayne", "Clark", "Franklin", "Fairfax"
        )),
        occupation = cycle(c(
            "Education", "Healthcare", "Construction", "Retail",
            "Manufacturing", "Technology", "Hospitality", "Transportation",
            "Government", "Agriculture"
        )),
        industry = cycle(c(
            "Public administration", "Professional services",
            "Health and social care", "Wholesale and retail",
            "Information services", "Accommodation and food"
        )),
        product_code = repeated_format("P%09d", 100000L, 17L),
        cohort = cycle(c(
            "pre-1965", "1965-1979", "1980-1994", "1995-2009",
            "2010-present"
        )),
        language = cycle(c(
            "English", "Spanish", "French", "Mandarin", "Arabic",
            "Portuguese", "Hindi", "Other"
        )),
        description = rep_len(sprintf(
            "Household survey record %08d in rotating panel %02d with verified response",
            seq_len(min(rows, 100000L)), seq_len(min(rows, 100000L)) %% 24L
        ), rows),
        note = rep_len(sprintf(
            paste0(
                "Quality-controlled synthetic microdata row %08d; ",
                "source wave %02d; deterministic benchmark payload."
            ),
            seq_len(min(rows, 100000L)), seq_len(min(rows, 100000L)) %% 12L
        ), rows),
        stringsAsFactors = FALSE,
        check.names = FALSE
    )
    standard_r_write_schema(data)
    data
}
