args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) {
    stop("usage: Rscript generate-base.R OUTPUT [ROWS]")
}

output <- normalizePath(args[[1L]], mustWork = FALSE)
rows <- if (length(args) >= 2L) as.integer(args[[2L]]) else 100000L
stopifnot(is.finite(rows), rows >= 1000L)

benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
.libPaths(c(normalizePath(benchmark_library, winslash = "/", mustWork = TRUE),
            .libPaths()))

if (!requireNamespace("haven", quietly = TRUE)) {
    stop("haven is required")
}
if (!requireNamespace("dtaparser", quietly = TRUE)) {
    stop("dtaparser is required")
}

i <- seq_len(rows)
cycle <- function(values, offset = 0L) values[((i + offset - 1L) %% length(values)) + 1L]

region <- haven::labelled(
    as.integer((i - 1L) %% 6L + 1L),
    labels = c(Northeast = 1L, Midwest = 2L, South = 3L, West = 4L,
               Territory = 5L, Overseas = 6L)
)
education <- haven::labelled(
    as.integer((i * 7L) %% 5L + 1L),
    labels = c(Primary = 1L, Secondary = 2L, College = 3L,
               Graduate = 4L, Unknown = 5L)
)
employment <- haven::labelled(
    as.integer((i * 11L) %% 5L + 1L),
    labels = c(Employed = 1L, Unemployed = 2L, Student = 3L,
               Retired = 4L, Other = 5L)
)
health <- haven::labelled(
    as.integer((i * 13L) %% 5L + 1L),
    labels = c(Excellent = 1L, Good = 2L, Fair = 3L, Poor = 4L,
               Missing = 5L)
)

income <- 18000 + (i %% 250000) * 1.17
income[i %% 997L == 0L] <- haven::tagged_na("a")
expenditure <- 9000 + (i %% 140000) * 0.83
expenditure[i %% 991L == 0L] <- NA_real_

dataset <- data.frame(
    id = as.double(i),
    household_id = as.double((i - 1L) %/% 3L + 1L),
    wave = as.integer((i - 1L) %% 12L + 1L),
    income = income,
    expenditure = expenditure,
    sampling_weight = 0.25 + (i %% 10000L) / 1000,
    latitude = -44.5 + (i %% 134000L) / 1000,
    longitude = -179.5 + (i %% 359000L) / 1000,
    score_physical = sin(i / 113) * 12 + 50,
    score_mental = cos(i / 127) * 11 + 51,
    score_economic = log1p(i %% 50000L),
    score_environment = sqrt(i %% 100000L),
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
    region = region,
    education = education,
    employment = employment,
    self_rated_health = health,
    birth_date = as.Date("1940-01-01") + (i %% 25000L),
    interview_date = as.Date("2010-01-01") + (i %% 5500L),
    created_at = as.POSIXct("2018-01-01", tz = "UTC") + (i %% 10000000L),
    updated_at = as.POSIXct("2020-01-01", tz = "UTC") + (i %% 15000000L),
    case_code = sprintf("CASE-%08d", i %% 100000000L),
    state_code = cycle(state.abb),
    county = cycle(c("Kings", "Queens", "Cook", "Harris", "Maricopa",
                     "Orange", "Wayne", "Clark", "Franklin", "Fairfax")),
    occupation = cycle(c("Education", "Healthcare", "Construction", "Retail",
                         "Manufacturing", "Technology", "Hospitality",
                         "Transportation", "Government", "Agriculture")),
    industry = cycle(c("Public administration", "Professional services",
                       "Health and social care", "Wholesale and retail",
                       "Information services", "Accommodation and food")),
    product_code = sprintf("P%05d-%04d", i %% 100000L, (i * 17L) %% 10000L),
    cohort = cycle(c("pre-1965", "1965-1979", "1980-1994", "1995-2009",
                     "2010-present")),
    language = cycle(c("English", "Spanish", "French", "Mandarin", "Arabic",
                       "Portuguese", "Hindi", "Other")),
    description = sprintf(
        "Household survey record %08d in rotating panel %02d with verified response",
        i %% 100000000L, i %% 24L
    ),
    note = sprintf(
        "Quality-controlled synthetic microdata row %08d; source wave %02d; deterministic benchmark payload.",
        i %% 100000000L, i %% 12L
    ),
    stringsAsFactors = FALSE,
    check.names = FALSE
)

attr(dataset, "label") <- "Synthetic mixed-type longitudinal household microdata"
for (name in names(dataset)) {
    attr(dataset[[name]], "label") <- paste("Benchmark field", name)
}

storage_columns <- list(
    byte = c("wave", "household_size", "children", "survey_month"),
    int = c("age", "visits", "survey_year", "status_code"),
    long = c(
        "id", "household_id", "provider_count", "event_count",
        "quality_flag", "region", "education", "employment",
        "self_rated_health"
    ),
    float = c(
        "sampling_weight", "latitude", "score_physical", "score_mental"
    ),
    double = c(
        "income", "expenditure", "longitude", "score_economic",
        "score_environment"
    )
)
for (storage in names(storage_columns)) {
    for (name in storage_columns[[storage]]) {
        attr(dataset[[name]], "stata.storage") <- storage
    }
}

dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile(
    pattern = paste0(basename(output), "."),
    tmpdir = dirname(output), fileext = ".dta"
)
on.exit(unlink(temporary), add = TRUE)
dtaparser::write_dta(dataset, temporary, version = 19L)

# Replace the wall-clock write time in the Stata 118 header so identical inputs
# produce byte-identical fixtures.
bytes <- readBin(temporary, "raw", file.info(temporary)$size)
tag <- charToRaw("<timestamp>")
timestamp_start <- grepRaw(tag, bytes, fixed = TRUE)
fixed_timestamp <- charToRaw("01 Jan 2000 00:00")
stopifnot(
    length(timestamp_start) == 1L,
    as.integer(bytes[[timestamp_start + length(tag)]]) == length(fixed_timestamp)
)
indices <- timestamp_start + length(tag) + seq_along(fixed_timestamp)
bytes[indices] <- fixed_timestamp
writeBin(bytes, temporary)
rm(bytes)

if (!file.rename(temporary, output)) {
    stop("could not atomically replace ", output)
}
cat(sprintf("wrote %s: %d rows, %d columns, %d bytes\n",
            output, nrow(dataset), ncol(dataset), file.info(output)$size))
