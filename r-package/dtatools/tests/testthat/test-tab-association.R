# The inputs, printed association lines, and stored values all come from
# Stata's unedited log. Parsing tabi's simple integer syntax lets each native
# case exercise the R formulas without hand-copying the expected answers.
read_tab_association_oracle <- function() {
    lines <- readLines(test_path("fixtures", "tabulate-association.log"),
                       warn = FALSE, encoding = "UTF-8")
    starts <- grep("^\\. tabi ", lines)
    ends <- c(starts[-1L] - 1L, length(lines))
    lapply(seq_along(starts), function(index) {
        block <- lines[starts[[index]]:ends[[index]]]
        command <- sub("^\\. ", "", block[[1L]])
        parts <- strsplit(sub("^tabi ", "", command), ",", fixed = TRUE)[[1L]]
        rows <- strsplit(parts[[1L]], "\\", fixed = TRUE)[[1L]]
        counts <- do.call(rbind, lapply(rows, function(row) {
            as.numeric(strsplit(trimws(row), " +")[[1L]])
        }))
        options <- setNames(as.list(rep(TRUE, length(strsplit(trimws(parts[[2L]]),
            " +")[[1L]]))), strsplit(trimws(parts[[2L]]), " +")[[1L]])
        if ("exact(2)" %in% names(options)) options$exact <- 2
        if (isTRUE(options$rowsort)) {
            counts <- counts[order(-rowSums(counts)), , drop = FALSE]
        }
        if (isTRUE(options$colsort)) {
            counts <- counts[, order(-colSums(counts)), drop = FALSE]
        }
        scalar_lines <- grep("^ +r\\([[:alnum:]_]+\\) = ", block, value = TRUE)
        scalar_names <- sub("^ +r\\(([^)]+)\\).*$", "\\1", scalar_lines)
        scalar_values <- as.numeric(sub("^.*= +", "", scalar_lines))
        list(command = command, counts = counts, options = options,
             scalars = setNames(as.list(scalar_values), scalar_names),
             output = grep("^ *(Pearson chi2|Likelihood-ratio chi2|Cram\u00e9r's V|gamma =|Kendall's tau-b|Fisher's exact|1-sided Fisher's exact)",
                           block, value = TRUE))
    })
}

test_that("association measures match Stata's stored results and printed lines", {
    cases <- read_tab_association_oracle()
    source <- readLines(test_path("fixtures", "tabulate-association.do"))
    commands <- grep("^tabi ", source, value = TRUE)
    expect_identical(vapply(cases, `[[`, character(1), "command"), commands)
    expect_length(cases, 20L)
    for (case in cases) {
        actual <- .tab_association(case$counts, case$options)
        expect_identical(sort(names(actual)), sort(names(case$scalars)),
                         info = case$command)
        for (name in names(case$scalars)) {
            expect_equal(actual[[name]], case$scalars[[name]], tolerance = 1e-11,
                         info = paste(case$command, name))
        }
        expect_identical(.tab_format_association(actual), case$output,
                         info = case$command)
    }
})

test_that("weighted association accepts fweights and rejects other weights", {
    counts <- matrix(c(30, 18, 38, 14), 2L, byrow = TRUE)
    options <- list(all = TRUE, exact = TRUE)
    expect_identical(.tab_association(counts, options, "fweight"),
                     .tab_association(counts, options))
    for (weight in c("aweight", "iweight", "aw", "iw")) {
        for (measure in c("all", "chi2", "lrchi2", "V", "gamma", "taub", "exact")) {
            expect_error(.tab_association(counts, setNames(list(TRUE), measure),
                                          weight), "not allowed")
        }
    }
})

test_that("unused levels and empty tables do not create association tests", {
    expect_identical(.tab_association(matrix(0, 3L, 2L), list(all = TRUE)),
                     list(N = 0, r = 0L, c = 0L))
    expect_identical(.tab_format_association(list(N = 0, r = 0L, c = 0L)),
                     character())
    expect_identical(.tab_association(matrix(1, 2L, 2L), list()), list())
    expect_identical(.tab_format_association(list()), character())
})

test_that("ordinal errors remain stable for large frequency counts", {
    counts <- matrix(c(20, 10, 2, 16, 12, 4, 10, 16, 6), 3L, byrow = TRUE)
    ordinary <- .tab_association(counts, list(all = TRUE))
    large <- .tab_association(counts * 1e10, list(all = TRUE))
    expect_equal(large$gamma, ordinary$gamma)
    expect_equal(large$taub, ordinary$taub)
    expect_equal(large$CramersV, ordinary$CramersV)
    expect_equal(large$ase_gam * 1e5, ordinary$ase_gam)
    expect_equal(large$ase_taub * 1e5, ordinary$ase_taub)
})
