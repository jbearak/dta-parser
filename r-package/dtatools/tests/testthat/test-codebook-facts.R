.codebook_facts_reference <- function(x) {
    distinct <- unique(x)
    q <- stats::quantile(x, c(.1, .25, .5, .75, .9), names = FALSE, type = 2)
    sorted <- sort(distinct)
    unit <- if (length(sorted) < 2L) NA_real_ else min(diff(sorted))
    list(distinct, c(min(x), max(x), unit, q))
}

test_that("codebook facts of whole numbers match the R calls they replace", {
    facts <- function(x) .Call(C_dtatools_codebook_facts, x)
    samples <- list(5, c(3, 3), c(2, 1), c(-127, 100, 0, 5, 5, -3),
                    c(2^53 - 1, 2^53 - 2, 2^53 - 1), -c(2^53 - 1, 2^53 - 2),
                    c(0, 65538), rep(c(9, -4, 9, 0), 25))
    # Counts whose quantile positions are whole numbers average two order
    # statistics; the others read one. Repeats test ties at each position.
    for (n in c(1:12, 20, 40, 99, 100, 101, 65539)) {
        samples <- c(samples, list(as.double((seq_len(n) * 7919) %% 13 - 6),
                                   as.double(seq_len(n) %/% 3)))
    }
    for (x in samples) {
        expect_identical(facts(x), .codebook_facts_reference(x),
                         info = paste(utils::head(x), collapse = " "))
    }
    # Fractions, missing and infinite values, -0, magnitudes from 2^53, a
    # range wider than the count plus 65,536, attributes and integers keep
    # the R calls.
    for (x in list(double(), c(1, 2.5), c(1, NaN), c(1, NA), c(1, Inf), c(1, -0),
                   c(0, 2^53), c(0, 65539), c(a = 1), 1:3)) {
        expect_null(facts(x))
    }
})

test_that("codebook statistics and label coverage match the R calls", {
    values <- c(5, 3, 9, 3, 1, NA, 7, 9, 2, tagged_missing("b"), 3)
    data <- data.frame(tallied = values, fractional = values / 2,
                       wide = c(values[-11L], 1e6))
    attr(data$tallied, "labels") <- c(one = 1, three = 3)
    compact <- dibble(byte = dta_byte(values), long = dta_long(values * 1000))
    for (frame in list(data, compact)) {
        result <- codebook(frame, problems = TRUE, detail = TRUE)
        for (name in names(frame)) {
            observed <- as.double(unclass(frame[[name]]))
            observed <- observed[!is.na(observed)]
            row <- result$variables[result$variables$variable == name, ]
            expected <- c(min(observed), max(observed),
                          min(diff(sort(unique(observed)))), mean(observed),
                          stats::sd(observed),
                          stats::quantile(observed, c(.1, .25, .5, .75, .9),
                                          names = FALSE, type = 2))
            expect_identical(
                unname(unlist(row[c("minimum", "maximum", "unit", "mean", "sd",
                                    "p10", "p25", "p50", "p75", "p90")])),
                expected, info = name)
            expect_identical(row$unique_nonmissing, length(unique(observed)))
        }
    }
    # Unlabelled values are listed in order of first appearance.
    result <- codebook(data, problems = TRUE, detail = TRUE)
    coverage <- result$diagnostics[
        result$diagnostics$code == "incomplete_value_labels", ]
    expect_identical(coverage$details[[1L]][[1L]]$values, c(5, 9, 7, 2))
})
