# Untimed supplement to the unchanged owned-double.R measurements.
args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
source('benchmarks/r-dibble-dplyr/owned-double-helpers.R')
lib <- owned_benchmark_start(args[[1L]], args[[2L]], 'candidate')
cat('Untimed original-backing qualification; source', args[[2L]], '\n')
cat('Runner MD5', unname(tools::md5sum('benchmarks/r-dibble-dplyr/owned-double.R')), '\n')
# Match the measured runner's warmed selector state on a separate tiny fixture.
invisible(dplyr::rename(owned_fixture(4L, 8L), changed = c01))
cat('Selector dispatch warmed on a separate four-row fixture\n')
records <- list()
backings <- function(x) vapply(x, `[[`, '', 'backing')
run_size <- function(rows) {
    data <- owned_fixture(rows, 8L)
    frozen <- owned_frozen(data)
    owned_assert_state(data, 'candidate')
    input_path <- tempfile(fileext = '.dta')
    output_path <- tempfile(fileext = '.dta')
    input_arrow <- tempfile(fileext = '.arrow')
    output_arrow <- tempfile(fileext = '.arrow')
    on.exit(unlink(c(input_path, output_path, input_arrow, output_arrow)), add = TRUE)
    save_dta(data, input_path)
    save_arrow(data, input_arrow, compression = 'uncompressed', threads = 1L)
    reads <- list(
        sum = function(x) sum(x$c01),
        mean = function(x) mean(x$c01),
        range = function(x) range(x$c01),
        coercion_double = function(x) as.double(x$c01),
        coercion_integer = function(x) as.integer(x$c01),
        export_data_frame = function(x) as.data.frame(x),
        export_tibble = function(x) tibble::as_tibble(x),
        arithmetic = function(x) x$c01 + 0.5,
        mutate_arithmetic = function(x) dplyr::mutate(x, c01 = c01 + 0.5),
        filter_half = function(x) dplyr::filter(x, c01 > 1.3),
        row_subset = function(x) x[seq.int(1L, nrow(x), by = 2L), ],
        read_dta = function(x) read_dta(input_path),
        write_dta = function(x) { save_dta(x, output_path); invisible(NULL) },
        read_arrow = function(x) read_arrow(input_arrow, threads = 1L),
        write_arrow = function(x) {
            save_arrow(x, output_arrow, compression = 'uncompressed', threads = 1L)
            invisible(NULL)
        }
    )
    for (name in names(reads)) {
        before <- owned_state(data)
        actual <- reads[[name]](data)
        after <- owned_state(data)
        stopifnot(identical(backings(before), backings(after)))
        owned_assert_state(data, 'candidate')
        owned_preserved(data, frozen)
        if (name %in% c('read_dta', 'read_arrow')) owned_assert_roundtrip(actual, frozen)
        if (name == 'write_dta') owned_assert_roundtrip(read_dta(output_path), frozen)
        if (name == 'write_arrow') {
            owned_assert_roundtrip(read_arrow(output_arrow, threads = 1L), frozen)
        }
        fork <- owned_profile(function() dplyr::rename(data, changed = c01))
        owned_assert_state(fork$value, 'candidate')
        stopifnot(identical(backings(before), backings(owned_state(data))),
                  identical(backings(before), backings(owned_state(fork$value))),
                  fork$metrics[['native_owned_capture_bytes']] == 0,
                  fork$metrics[['native_mutation_target_copy_bytes']] == 0,
                  fork$metrics[['r_allocated_bytes']] < 1000000)
        expected <- owned_expected_columns(frozen)
        expected$names[1L] <- 'changed'
        stopifnot(identical(owned_columns(fork$value), expected))
        owned_assert_table(fork$value, frozen, expected$names, rows)
        owned_preserved(data, frozen)
        records[[length(records) + 1L]] <<- data.frame(
            rows, operation = name, original_backing_unchanged = TRUE,
            original_exposure_false = TRUE, original_depth = 1L,
            selector_backing_identical = TRUE,
            selector_r_allocated_bytes = fork$metrics[['r_allocated_bytes']],
            selector_owned_capture_bytes = fork$metrics[['native_owned_capture_bytes']],
            selector_target_copy_bytes = fork$metrics[['native_mutation_target_copy_bytes']],
            frozen_source_values_and_metadata_unchanged = TRUE)
        cat('PASS', rows, name, 'original backing and post-read selector\n')
        rm(before, actual, after, fork, expected)
    }
}
for (rows in c(100000L, 1000000L)) run_size(rows)
stopifnot(length(records) == 30L)
validate_benchmark_install(lib, args[[2L]])
write.csv(do.call(rbind, records), args[[3L]], row.names = FALSE)
cat('All 30 untimed before/after original-backing checks passed\n')
