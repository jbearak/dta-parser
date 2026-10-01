# Association measures use Stata's tabulate twoway formulas. In particular,
# Cramer's V is signed for a 2 x 2 table, and neither Pearson's statistic nor
# the ordinal standard errors use a continuity correction.
# https://www.stata.com/manuals/rtabulatetwoway.pdf
.tab_association <- function(counts, options, weight_type = NULL) {
    measures <- c("chi2", "lrchi2", "V", "gamma", "taub")
    selected <- vapply(measures, function(name) {
        (isTRUE(options[[name]]) || isTRUE(options$all)) &&
            !isTRUE(options[[paste0("no", name)]])
    }, logical(1))
    exact <- !is.null(options$exact) && !identical(options$exact, FALSE)
    if (!any(selected) && !exact) return(list())
    if (!is.null(weight_type) &&
        weight_type %in% c("aw", "aweight", "aweights", "iw", "iweight", "iweights")) {
        stop("association statistics are not allowed with aweights or iweights",
             call. = FALSE)
    }

    # Unused factor levels are an R extension; they must not add degrees of
    # freedom or create zero expected counts in the observed-data tests.
    counts <- as.matrix(counts)
    counts <- counts[rowSums(counts) > 0, colSums(counts) > 0, drop = FALSE]
    n <- sum(counts)
    nr <- nrow(counts)
    nc <- ncol(counts)
    result <- list(N = n, r = nr, c = nc)
    if (n == 0 || nr < 2L || nc < 2L) return(result)

    row <- rowSums(counts)
    column <- colSums(counts)
    expected <- outer(row / n, column)
    df <- (nr - 1) * (nc - 1)
    if (selected[["chi2"]] || selected[["V"]]) {
        chi2 <- sum((counts - expected)^2 / expected)
        if (selected[["chi2"]]) {
            result$chi2 <- chi2
            result$p <- stats::pchisq(chi2, df, lower.tail = FALSE)
        }
        if (selected[["V"]]) {
            result$CramersV <- if (nr == 2L && nc == 2L) {
                (counts[1L, 1L] / n * (counts[2L, 2L] / n) -
                    counts[1L, 2L] / n * (counts[2L, 1L] / n)) /
                    sqrt(prod(row / n) * prod(column / n))
            } else {
                sqrt(chi2 / n / min(nr - 1L, nc - 1L))
            }
        }
    }
    if (selected[["lrchi2"]]) {
        observed <- counts > 0
        result$chi2_lr <- max(0, 2 * sum(counts[observed] *
            log(counts[observed] / expected[observed])))
        result$p_lr <- stats::pchisq(result$chi2_lr, df, lower.tail = FALSE)
    }
    if (selected[["gamma"]] || selected[["taub"]]) {
        result <- c(result, .tab_ordinal_association(
            counts, selected[["gamma"]], selected[["taub"]]
        ))
    }
    if (exact) {
        multiplier <- if (isTRUE(options$exact)) 1 else options$exact
        # Both R and Stata use FEXACT for general tables. The multiplier is
        # a resource control, not an approximation: never substitute Monte
        # Carlo probabilities when the exact workspace is insufficient.
        workspace <- min(.Machine$integer.max, 200000 * multiplier)
        result$p_exact <- stats::fisher.test(
            counts, workspace = workspace
        )$p.value
        if (nr == 2L && nc == 2L) {
            a <- counts[1L, 1L]
            result$p1_exact <- min(
                stats::phyper(a, column[[1L]], column[[2L]], row[[1L]]),
                stats::phyper(a - 1, column[[1L]], column[[2L]], row[[1L]],
                              lower.tail = FALSE)
            )
        }
    }
    result
}

.tab_ordinal_association <- function(counts, gamma, taub) {
    n <- sum(counts)
    probability <- counts / n
    nr <- nrow(counts)
    nc <- ncol(counts)
    # A two-dimensional cumulative sum gives all four open quadrants in
    # O(rows * columns), without constructing pairs of observations.
    prefix <- matrix(0, nr + 1L, nc + 1L)
    prefix[-1L, -1L] <- t(apply(apply(probability, 2L, cumsum), 1L, cumsum))
    row <- rowSums(probability)
    column <- colSums(probability)
    concordant <- prefix[seq_len(nr), seq_len(nc)] +
        prefix[-1L, -1L] - outer(cumsum(row), rep(1, nc)) -
        outer(rep(1, nr), cumsum(column)) + sum(probability)
    discordant <- outer(c(0, cumsum(row)[-nr]), rep(1, nc)) +
        outer(rep(1, nr), c(0, cumsum(column)[-nc])) -
        prefix[-1L, seq_len(nc)] - prefix[seq_len(nr), -1L]
    concordant <- pmax(0, concordant)
    discordant <- pmax(0, discordant)
    p <- sum(probability * concordant)
    q <- sum(probability * discordant)
    result <- list()
    if (gamma) {
        result$gamma <- (p - q) / (p + q)
        influence <- 2 * (concordant - discordant -
            result$gamma * (concordant + discordant)) / (p + q)
        result$ase_gam <- sqrt(sum(probability * influence^2) / n)
    }
    if (taub) {
        # Delta-method influence functions are algebraically equivalent to
        # Stata's formula. Center before squaring to avoid cancellation at
        # perfect association, and normalize counts to avoid n^8 overflow.
        wr <- sum(row * (1 - row))
        wc <- sum(column * (1 - column))
        result$taub <- (p - q) / sqrt(wr * wc)
        influence <- 2 * (concordant - discordant) / sqrt(wr * wc) +
            result$taub * (outer(row / wr, rep(1, nc)) +
                          outer(rep(1, nr), column / wc))
        influence <- influence - sum(probability * influence)
        result$ase_taub <- sqrt(sum(probability * influence^2) / n)
    }
    result
}

.tab_format_association <- function(results) {
    lines <- character()
    add <- function(label, value, suffix = "", digits = 4L, width = 8L) {
        text <- if (is.finite(value)) {
            sprintf(paste0("%", width, ".", digits, "f"), value)
        } else {
            sprintf(paste0("%", width, "s"), ".")
        }
        # Stata's %8.4f switches to %8.1e when the fixed decimal form no
        # longer fits. Its probability and ASE fields are always fixed.
        if (nchar(text, type = "width") > width && is.finite(value)) {
            text <- sprintf(paste0("%", width, ".1e"), value)
        }
        padding <- strrep(" ", max(0L, 25L - nchar(label, type = "width")))
        lines <<- c(lines, paste0(padding, label, " = ", text, suffix))
    }
    df <- (results$r - 1L) * (results$c - 1L)
    if (!is.null(results[["chi2"]])) {
        add(sprintf("Pearson chi2(%d)", df), results[["chi2"]],
            sprintf("   Pr = %.3f", results[["p"]]))
    }
    if (!is.null(results$chi2_lr)) {
        add(sprintf("Likelihood-ratio chi2(%d)", df), results$chi2_lr,
            sprintf("   Pr = %.3f", results$p_lr))
    }
    if (!is.null(results$CramersV)) add("Cram\u00e9r's V", results$CramersV)
    if (!is.null(results$gamma)) {
        add("gamma", results$gamma, sprintf("  ASE = %.3f", results$ase_gam))
    }
    if (!is.null(results$taub)) {
        add("Kendall's tau-b", results$taub,
            sprintf("  ASE = %.3f", results$ase_taub))
    }
    if (!is.null(results$p_exact)) {
        add("Fisher's exact", results$p_exact, digits = 3L, width = 21L)
    }
    if (!is.null(results$p1_exact)) {
        add("1-sided Fisher's exact", results$p1_exact, digits = 3L, width = 21L)
    }
    lines
}
